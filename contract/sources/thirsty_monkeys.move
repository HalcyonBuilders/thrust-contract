module thrust::thirsty_monkeys {
    use std::string::{String, utf8};
    use std::vector;

    use sui::math;
    use sui::address;
    use sui::sui::SUI;
    use sui::coin;
    use sui::clock;
    use sui::display;
    use sui::balance::{Self, Balance, Supply};
    use sui::object::{Self, ID, UID};
    use sui::url;
    use sui::transfer::{public_transfer, public_share_object};
    use sui::tx_context::{Self, TxContext};
    use sui::package;

    use nft_protocol::collection;
    use nft_protocol::creators;
    use nft_protocol::royalty_strategy_bps;
    use nft_protocol::royalty;
    use nft_protocol::transfer_allowlist;
    use nft_protocol::p2p_list;

    use ob_permissions::witness;
    use ob_utils::utils;
    use ob_request::transfer_request;

    use thrust::parse;

    // ========== errors ==========

    const ESaleInactive: u64 = 0;
    const EFundsInsufficient: u64 = 1;
    const ENotVerified: u64 = 2;
    const ENoBottleLeft: u64 = 3;
    const EWrongTestNft: u64 = 4;
    const ESaleNotStarted: u64 = 5;
    const ESaleEnded: u64 = 6;
    const EWrongTestCoin: u64 = 7;
    const EBadRange: u64 = 8;
    const ETooFewBytes: u64 = 9;

    const ONE_HOUR_IN_SECONDS: u64 = 60 * 60;

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

    struct Thrust has key, store {
        id: UID,
        active: bool,
        start_timestamp: u64,
        initial_price: u64,
        quantity_per_batch: u64,
        balance: Balance<SUI>,
    }

    struct MintCap<phantom T> has key, store {
        id: UID,
        collection_id: ID,
        supply: Supply<T>,
    }

    // ========== structs ==========

    struct StructTag has store, copy, drop {
        package_id: ID,
        module_name: String,
        struct_name: String,
        generics: vector<String>, 
    }

    // ========== functions ==========

    fun init(otw: THIRSTY_MONKEYS, ctx: &mut TxContext) {

        public_share_object(
            Thrust {
                id: object::new(ctx),
                active: false,
                start_timestamp: 0,
                initial_price: 0,
                quantity_per_batch: 0,
                balance: balance::zero(),
            }
        );

        public_transfer(package::claim(otw, ctx), tx_context::sender(ctx));
    }

    // === Admin Functions ===

    entry fun approve_sale_and_create_collection(
        publisher: &package::Publisher,
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

        // TODO: mint cap management (OB only in init)
        // let mint_cap = mint_cap::new(dw, object::id(&collection), supply, ctx);

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
        public_share_object(collection);
        public_share_object(transfer_policy);
        public_share_object(p2p_policy);
    }

    entry fun cancel_sale_and_refund(_: &package::Publisher) {
        // TODO
    }

    // ========== public functions ==========

    entry fun give_nfts(
        _: &package::Publisher,
        receivers: vector<address>,
        ctx: &mut TxContext,
    ) {
        let (i, nb) = (0, vector::length(&receivers));
        while (i < nb) {
            public_transfer(mint_nft(ctx), vector::pop_back(&mut receivers));
            i = i + 1;
        }
    }
    
    // entry fun give_nfts_(
    //     _: package::Publisher,
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

    // entry fun buy_nfts(
    //     thrust: &mut Thrust,
    //     funds: &mut coin::Coin<SUI>,
    //     clock: &clock::Clock,
    //     magic_nb: u64,
    //     ctx: &mut TxContext,
    // ) {
        // assert_is_active(thrust, clock);
        // assert!(thrust.left > 0, ENoBottleLeft);
        // assert!(coin::value(funds) >= thrust.price, EFundsInsufficient);
        // assert_is_verified(magic_nb, ctx);

        // let balance = coin::balance_mut(funds);
        // let amount = balance::split(balance, thrust.price);
        // balance::join(&mut thrust.balance, amount);

        // if (thrust.supply != 0) thrust.left = thrust.left - 1;
    // }

    entry fun buy_nfts_whitelist<N: key + store>() {
        // assert!(is_same_type(&get_struct_tag<N>(), &dispenser.test_nft), EWrongTestNft);
        // TODO: burn whitelist + buy_nfts 
    }

    entry fun claim_nft(
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
    //     _: &package::Publisher, 
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

    entry fun set_sale(
        _: &package::Publisher, 
        thrust: &mut Thrust,
        active: bool,
        start_timestamp: u64,
        initial_price: u64,
        quantity_per_batch: u64,
        _ctx: &mut TxContext
    ) {
        thrust.active = active;
        thrust.start_timestamp = start_timestamp;
        thrust.initial_price = initial_price;
        thrust.quantity_per_batch = quantity_per_batch;
    }

    entry fun transfer_publisher(
        publisher: package::Publisher, 
        receiver: address, 
        _ctx: &mut TxContext
    ) {
        public_transfer(publisher, receiver);
    }

    entry fun activate_sale(
        _: &package::Publisher, 
        thrust: &mut Thrust, 
        _ctx: &mut TxContext
    ) {
        thrust.active = true;
    }

    entry fun deactivate_sale(
        _: &package::Publisher, 
        thrust: &mut Thrust, 
        _ctx: &mut TxContext
    ) {
        thrust.active = false;
    }

    entry fun collect_profits(
        _: &package::Publisher,
        thrust: &mut Thrust,
        receiver: address,
        ctx: &mut TxContext
    ) {
        let amount = balance::value(&thrust.balance);
        let profits = coin::take(&mut thrust.balance, amount, ctx);

        public_transfer(profits, receiver)
    }

    // ========== utils ==========

    fun assert_is_verified(magic_nb: u64, ctx: &mut TxContext) {
        let addr_in_bytes = address::to_bytes(tx_context::sender(ctx));
        let b20_in_dec = vector::pop_back<u8>(&mut addr_in_bytes);
        let b19_in_dec = vector::pop_back<u8>(&mut addr_in_bytes);
        let multiplied = ((b20_in_dec as u64) * (b19_in_dec as u64));
        assert!(multiplied == magic_nb, ENotVerified);
    }

    fun assert_is_active(thrust: &Thrust, clock: &clock::Clock) {
        assert!(thrust.active, ESaleInactive);
        let time = clock::timestamp_ms(clock);
        assert!(thrust.start_timestamp < time, ESaleNotStarted); 
    }

    fun get_struct_tag<T>(): StructTag {
        let (package_id, module_name, struct_name, generics) = parse::type_name_decomposed<T>();

        StructTag { package_id, module_name, struct_name, generics }
    }

    fun is_same_type(type1: &StructTag, type2: &StructTag): bool {
        (type1.package_id == type2.package_id
            && type1.module_name == type2.module_name
            && type1.struct_name == type2.struct_name
            && type1.generics == type2.generics)
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