module thrust::thirsty_monkeys {
    use std::string::{String, utf8};
    use std::vector;

    use sui::math;
    use sui::address;
    use sui::sui::SUI;
    use sui::coin;
    use sui::clock::{Clock, timestamp_ms};
    use sui::display;
    use sui::balance::{Self, Balance};
    use sui::object::{Self, ID, UID};
    use sui::url;
    use sui::transfer::{public_transfer, public_share_object};
    use sui::tx_context::{Self, TxContext};
    use sui::package::{Publisher, claim};
    use sui::dynamic_field as df;

    use nft_protocol::collection;
    use nft_protocol::creators;
    use nft_protocol::royalty_strategy_bps;
    use nft_protocol::royalty;
    use nft_protocol::transfer_allowlist;
    use nft_protocol::p2p_list;

    use ob_permissions::witness;
    use ob_utils::utils;
    use ob_request::transfer_request;

    // ========== errors ==========

    const ESaleInactive: u64 = 0;
    const EWrongCoinAmount: u64 = 1;
    const ENotVerified: u64 = 2;
    const ENotEnoughLeft: u64 = 3;
    const EExceededSupply: u64 = 4;
    const ESaleNotStarted: u64 = 5;
    const ESaleEnded: u64 = 6;
    const ETooFewBytes: u64 = 7;

    const ONE_HOUR_IN_MS: u64 = 60 * 60 * 1000;

    // ========== witnesses ==========

    struct THIRSTY_MONKEYS has drop {}

    struct Witness has drop {}

    // ========== objects ==========

    struct Whitelist has key, store {
        id: UID
    }

    struct ThirstyMonkey has key, store {
        id: UID,
        name: String,
        description: String,
        url: url::Url,
    }

    struct ProofOfMint has key, store {
        id: UID,
        nft_ids: vector<u64>,
    }

    struct Thrust has key, store {
        id: UID,
        active: bool,
        start_timestamp: u64,
        initial_price: u64,
        supply_per_batch: u64,
        total_purchased: u64,
        balance: Balance<SUI>,
    }

    struct MintCap has key, store {
        id: UID,
        collection_id: ID,
        refund_batch: u64,
        supply: Supply,
    }

    // ========== resources ==========

    struct Supply has store {
        max: u64,
        current: u64,
    }

    // ========== functions ==========

    fun init(otw: THIRSTY_MONKEYS, ctx: &mut TxContext) {

        public_share_object(
            Thrust {
                id: object::new(ctx),
                active: false,
                start_timestamp: 0,
                initial_price: 0,
                supply_per_batch: 0,
                total_purchased: 0,
                balance: balance::zero(),
            }
        );

        public_transfer(claim(otw, ctx), tx_context::sender(ctx));
    }

    // === Admin Functions ===

    public fun approve_sale_and_create_collection(
        publisher: &Publisher,
        clock: &Clock,
        thrust: &mut Thrust,
        description: vector<u8>,
        project_url: vector<u8>,
        creator: address,
        ctx: &mut TxContext
    ) {
        let dw = witness::from_witness(Witness {});
        let (collection) = collection::create<witness::Witness<ThirstyMonkey>>(dw, ctx);
        collection::add_domain(
            dw,
            &mut collection,
            url::new_unsafe_from_bytes(b"https://halcyon.builders"),
        );

        let current_batch = current_batch(thrust, clock);
        let mint_cap = MintCap {
            id: object::new(ctx),
            collection_id: object::id(&collection),
            refund_batch: current_batch,
            supply: Supply {
                max: thrust.supply_per_batch * current_batch,
                current: 0,
            }
        };

        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url"),
            utf8(b"project_url"),
        ];
        let values = vector[
            utf8(b"{name}"),
            utf8(description),
            utf8(b"{url}"),
            utf8(project_url),
        ];
        let display = display::new_with_fields<ThirstyMonkey>(publisher, keys, values, ctx);
        display::update_version(&mut display);
        public_transfer(display,  creator);

        let creators = vector[creator, @0xCAFE];
        let shares = vector[9500, 500];
        let shares = utils::from_vec_to_map(creators, shares);
        collection::add_domain(
            dw,
            &mut collection,
            creators::new(utils::vec_set_from_vec(&creators)),
        );
        royalty_strategy_bps::create_domain_and_add_strategy(
            dw, &mut collection, royalty::from_shares(shares, ctx), 100, ctx,
        );

        let (transfer_policy, transfer_policy_cap) =
            transfer_request::init_policy<ThirstyMonkey>(publisher, ctx);
        royalty_strategy_bps::enforce(&mut transfer_policy, &transfer_policy_cap);
        transfer_allowlist::enforce(&mut transfer_policy, &transfer_policy_cap);

        let (p2p_policy, p2p_policy_cap) =
            transfer_request::init_policy<ThirstyMonkey>(publisher, ctx);
        p2p_list::enforce(&mut p2p_policy, &p2p_policy_cap);

        // public_share_object(mint_cap);
        public_transfer(transfer_policy_cap, creator);
        public_transfer(p2p_policy_cap, creator);
        public_share_object(mint_cap);
        public_share_object(collection);
        public_share_object(transfer_policy);
        public_share_object(p2p_policy);
    }

    public fun cancel_sale_and_refund(_: &Publisher) {
        // TODO
    }

    // ========== public functions ==========

    public fun new_whitelist(_: &Publisher, ctx: &mut TxContext): Whitelist {
        Whitelist {
            id: object::new(ctx),
        }
    }

    public fun new_proof_of_mint(ctx: &mut TxContext): ProofOfMint {
        ProofOfMint {
            id: object::new(ctx),
            nft_ids: vector::empty(),
        }
    }
    
    public fun buy_nfts(
        thrust: &mut Thrust,
        pom: &mut ProofOfMint,
        funds: coin::Coin<SUI>,
        clock: &Clock,
        magic_nb: u64,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert_is_verified(magic_nb, ctx);
        assert!(thrust.active, ESaleInactive);
        assert!(get_sale_status(thrust, clock) == 1, ESaleInactive);
        let purchased = thrust.total_purchased;
        assert!(purchased + amount < current_max_supply(thrust, clock), ENotEnoughLeft);

        assert!(coin::value(&mut funds) == current_price(thrust, clock) * amount, EWrongCoinAmount);
        let balance = coin::into_balance(funds);
        balance::join(&mut thrust.balance, balance);

        df::add(&mut pom.id, current_batch(thrust, clock), amount);
        thrust.total_purchased = purchased + amount;
    }

    public fun buy_nfts_whitelist<N: key + store>(
        wl: Whitelist,
        thrust: &mut Thrust,
        pom: &mut ProofOfMint,
        funds: coin::Coin<SUI>,
        clock: &Clock,
        magic_nb: u64,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        let Whitelist { id } = wl;
        object::delete(id);
        buy_nfts(thrust, pom, funds, clock, magic_nb, amount, ctx)
    }

    public fun give_nft(
        _: &Publisher,
        _ctx: &mut TxContext,
    ) {}
    
    // public fun give_nfts_(
    //     _: Publisher,
    //     receivers: vector<address>,
    //     ctx: &mut TxContext,
    // ): vector<ThirstyMonkey> {
    //     let (i, nb) = (0, vector::length(&receivers));
    //     let nfts = vector::empty<ThirstyMonkey>();
    //     while (i < nb) {
    //         let nft = mint_nft(ctx);
    //         vector::push_back(&mut nfts, nft);
    //         i = i + 1;
    //     };
    //     nfts
    // }


    public fun claim_nft(
        ctx: &mut TxContext,
    ) {
        // TODO
        let nft = claim_nft_(ctx);
        public_transfer(nft, tx_context::sender(ctx));
    }

    public fun claim_nft_(
        ctx: &mut TxContext,
    ): ThirstyMonkey {
        // TODO
        mint_nft(ctx)
    }

    // ========== private functions ==========

    fun mint_nft(
        ctx: &mut TxContext,
    ): ThirstyMonkey {
        let name = utf8(b"Empty Bottle");
        let description = utf8(b"This bottle is empty and is worth nothing, maybe you could recycle it?");
        let url = url::new_unsafe_from_bytes(b"https://i.postimg.cc/tTxtnNpP/Empty-Bottle.png");
        
        ThirstyMonkey {
            id: object::new(ctx),
            name,
            description,
            url,
        }
    }

    // fun set_altcoin(
    //     _: &Publisher, 
    //     dispenser: &mut Dispenser,
    //     gen1: vector<u8>,
    //     gen2: vector<u8>,
    //     gen3: vector<u8>,
    //     _ctx: &mut TxContext
    // ) {
    //     let generics = utf8(gen1);
    //     string::append_utf8(&mut generics, b"::");
    //     string::append_utf8(&mut generics, gen2);
    //     string::append_utf8(&mut generics, b"::");
    //     string::append_utf8(&mut generics, gen3);

    //     dispenser.test_coin = StructTag {
    //         package_id: object::id_from_address(@0x2),
    //         module_name: utf8(b"coin"),
    //         struct_name: utf8(b"Coin"),
    //         generics: vector[generics],
    //     };
    // }

    // ========== admin setup functions ==========

    public fun set_sale(
        _: &Publisher, 
        thrust: &mut Thrust,
        active: bool,
        start_timestamp: u64,
        initial_price: u64,
        supply_per_batch: u64,
        _ctx: &mut TxContext
    ) {
        thrust.active = active;
        thrust.start_timestamp = start_timestamp;
        thrust.initial_price = initial_price;
        thrust.supply_per_batch = supply_per_batch;
    }

    public fun transfer_publisher(
        publisher: Publisher, 
        receiver: address, 
        _ctx: &mut TxContext
    ) {
        public_transfer(publisher, receiver);
    }

    public fun activate_sale(
        _: &Publisher, 
        thrust: &mut Thrust, 
        _ctx: &mut TxContext
    ) {
        thrust.active = true;
    }

    public fun deactivate_sale(
        _: &Publisher, 
        thrust: &mut Thrust, 
        _ctx: &mut TxContext
    ) {
        thrust.active = false;
    }

    public fun collect_profits(
        _: &Publisher,
        thrust: &mut Thrust,
        receiver: address,
        ctx: &mut TxContext
    ) {
        let amount = balance::value(&thrust.balance);
        let profits = coin::take(&mut thrust.balance, amount, ctx);

        public_transfer(profits, receiver)
    }

    // ========== utils ==========

    fun increment_supply(supply: &mut Supply, value: u64) {
        assert!(
            supply.current + value <= supply.max,
            EExceededSupply,
        );
        supply.current = supply.current + value;
    }

    fun current_batch(thrust: &Thrust, clock: &Clock): u64 {
        let time = timestamp_ms(clock);
        (time - thrust.start_timestamp) / ONE_HOUR_IN_MS
    }

    fun current_max_supply(thrust: &Thrust, clock: &Clock): u64 {
        current_batch(thrust, clock) * thrust.supply_per_batch
    }

    fun current_price(thrust: &Thrust, clock: &Clock): u64 {
        thrust.initial_price + (current_batch(thrust, clock) - 1) * thrust.initial_price / 2
    }

    fun get_sale_status(thrust: &Thrust, clock: &Clock): u64 {
        let time = timestamp_ms(clock);
        let status;

        if (thrust.start_timestamp > time || thrust.total_purchased == current_max_supply(thrust, clock)) {
		    status = 0; // sale closed
        } else if (thrust.total_purchased == 10000 || thrust.total_purchased < current_max_supply(thrust, clock) - thrust.supply_per_batch) {
            status = 2; // sale ended
        } else {
            status = 1; // sale in progress
        };
        
        status
    }

    fun assert_is_verified(magic_nb: u64, ctx: &mut TxContext) {
        let addr_in_bytes = address::to_bytes(tx_context::sender(ctx));
        let b20_in_dec = vector::pop_back<u8>(&mut addr_in_bytes);
        let b19_in_dec = vector::pop_back<u8>(&mut addr_in_bytes);
        let multiplied = ((b20_in_dec as u64) * (b19_in_dec as u64));
        assert!(multiplied == magic_nb, ENotVerified);
    }

    fun from_bytes(bytes: vector<u8>): u64 {
        assert!(vector::length(&bytes) >= 8, ETooFewBytes);

        let i: u8 = 0;
        let sum: u64 = 0;
        while (i < 8) {
            sum = sum + (*vector::borrow(&bytes, (i as u64)) as u64) * math::pow(2, (7 - i) * 8);
            i = i + 1;
        };

        sum
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(THIRSTY_MONKEYS {}, ctx)
    }
}