#[test_only]
module stream_pay::stream_pay_tests {
    // uncomment this line to import the module
    // use stream_pay::stream_pay;

    #[test_only]
    use sui::test_scenario;

    const ENotImplemented: u64 = 0;

    #[test_only]
    public struct TokenA has drop {}
    


    // #[test]
    // fun test_borrow() {
    //     let owner: address = @100;
    //     let alice: address = @101;

    //     let mut scenario = test_scenario::begin(owner);
    // }

    // #[test, expected_failure(abort_code = ::stream_pay::stream_pay_tests::ENotImplemented)]
    // fun test_stream_pay_fail() {
    //     abort ENotImplemented
    // }
}
