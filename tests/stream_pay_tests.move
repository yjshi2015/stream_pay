#[test_only]
module stream_pay::liner_pay_tests {

//     use stream_pay::liner_pay::{Self, PayerPool};
//     use sui::coin;
//     use sui::sui::SUI;

    #[test_only]
    use sui::test_scenario;
    use std::debug;

//     #[test]
//     fun test_createAndDeposit() {
//         let owner: address = @100;
//         let alice: address = @101;

//         let mut scenario = test_scenario::begin(owner);
//         {
//             let my_coin = coin::mint_for_testing<SUI>(100, scenario.ctx());
//             liner_pay::createAndDeposit(my_coin, scenario.ctx());
//             let payer_pool = scenario.take_from_sender<PayerPool>();

//             assert(payer_pool.p_balance == 100);
//             assert(payer_pool.p_debt == 0);
//             assert(payer_pool.owner == owner);
//             assert(payer_pool.stream_ids == vec![]);
//             assert(payer_pool.p_last_settlement_time == 0);
//             assert(payer_pool.p_total_paid_amount_per == 0);
//         }


//     }

    #[test]
    fun test_stream_pay_fail() {
        let owner: address = @100;
        let mut scenario = test_scenario::begin(owner);

        let objId = object::new(scenario.ctx());
        debug::print(&objId.to_inner());
        debug::print(&objId.to_address());
        object::delete(objId);
        scenario.end();
    }
}
