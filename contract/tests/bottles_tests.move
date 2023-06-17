#[test_only]
module thrust::test_sale {
    // use std::vector;

    use sui::test_scenario as test;
    // use sui::coin;
    // use sui::sui::SUI;
    // use sui::transfer;
    // use sui::clock;

    use thrust::thirsty_monkeys;

    const BUYER: address = @0xBABE;
    const ADMIN: address = @0xCAFE;

    struct Coin has drop {}

    #[test]
    fun init_scenario(): test::Scenario {
        let scenario = test::begin(ADMIN);

        thirsty_monkeys::init_for_testing(test::ctx(&mut scenario));

        scenario
    }
}