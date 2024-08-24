module stream_pay::liner_pay {

    use sui::coin::{Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::bcs;
    use sui::hash;
    use sui::vec_set::{Self, VecSet};
    use sui::event;
    use std::string::{String, utf8};

    const ELenNotEqual: u64 = 0;
    const EStreamExisted: u64 = 1;
    const EAmountPerSecInvalid: u64 = 2;
    const EStreamNotExisted: u64 = 3;
    const EDoNotRug: u64 = 4;
    const ENotAuth: u64 = 5;

    
    // 支付者池子，存储支付金额信息
    public struct PayerPool has key, store{
        id: UID,
        // 余额，随时间线性递减
        p_balance: Balance<SUI>,
        // 应支付的费用，随时间线性递增
        p_debt: Balance<SUI>,
        // owner address
        owner: address,
        stream_ids: VecSet<vector<u8>>,
        // 上次结算时间
        p_last_settlement_time: u64,
        // 每秒应支付的总金额
        p_total_paid_amount_per: u64,
    }

    // 接收者卡片信息，凭借该卡片领取薪资，类似于员工卡
    public struct ReciverCard has key, store {
        id: UID,
        // 支付者信息
        payer: address,
        // 接收者信息
        recipient: address,
        // 每秒的工资
        r_amount_per: u64,
        // 上次结算时间
        r_last_settlement_time: u64,
    }

    // 支付流信息
    public struct StreamInfo has drop {
        payer: address,
        reciver: address,
        amount_per_sec: u64,
    }

    public struct CreatePayerPool has copy, drop {
        pool_id: ID,
        owner: address,
    }

    public struct StreamAction has copy, drop {
        stream_id: vector<u8>,
        action_type: String,
        payer: address,
        p_total_paid_amount_per: u64,
        p_last_settlement_time: u64,
        recipient: address,
        r_amount_per: u64,
        r_last_settlement_time: u64,
    }

    public struct WithdrawAction has copy, drop {
        stream_id: vector<u8>,
        action_type: String,
        from: address,
        to: address,
        amount: u64,
        owe: bool,
    }

    public entry fun createPayPoolAndStream(amount: Coin<SUI>, recipients: vector<address>, amount_per_sec_vec: vector<u64>, clock: &Clock, ctx: &mut TxContext) {
        assert!(recipients.length() == amount_per_sec_vec.length(), ELenNotEqual);

        let mut payer_pool = PayerPool {
            id: object::new(ctx),
            p_balance: amount.into_balance(),
            p_debt: balance::zero(),
            owner: ctx.sender(),
            stream_ids: vec_set::empty(),
            p_last_settlement_time: 0,
            p_total_paid_amount_per: 0,
        };

        event::emit(CreatePayerPool { pool_id: payer_pool.id.to_inner(), owner: payer_pool.owner });
        
        let mut i = 0;
        while(i < recipients.length()) {
            createStream(&mut payer_pool, recipients[i], amount_per_sec_vec[i], clock, ctx);
            i = i + 1;
        };

        transfer::share_object(payer_pool);
    }

    // step1 创建 Payer Pool 并预存薪资
    public fun createAndDeposit(amount: Coin<SUI>, ctx: &mut TxContext): address {
        let payer_pool = PayerPool {
            id: object::new(ctx),
            p_balance: amount.into_balance(),
            p_debt: balance::zero(),
            owner: ctx.sender(),
            stream_ids: vec_set::empty(),
            p_last_settlement_time: 0,
            p_total_paid_amount_per: 0,
        };

        event::emit(CreatePayerPool { pool_id: payer_pool.id.to_inner(), owner: payer_pool.owner });
        
        let payer_pool_address = payer_pool.id.to_address();

        transfer::share_object(payer_pool);

        payer_pool_address
    }

    // 获取支付流的哈希，作为唯一标识
    fun getStreamId(payer: address, reciver: address, amount_per_sec: u64): vector<u8> {
        let stream_info = StreamInfo {
            payer,
            reciver,
            amount_per_sec,
        };
        let stream_bytes = bcs::to_bytes(&stream_info);
        hash::keccak256(&stream_bytes)
    }

    // step2 payer 创建自动支付流，用于为 recipient 支付工资
    public fun createStream(payer_pool: &mut PayerPool, recipient: address, amount_per_sec: u64, clock: &Clock, ctx: &mut TxContext): address {
        // 必须是 payer owner 才可以创建支付流，因为 payer 是共享对象，因此需要显式控制权限
        assert!(payer_pool.owner == ctx.sender(), ENotAuth);
        // 每秒支付的工资必须大于 0
        assert!(amount_per_sec > 0, EAmountPerSecInvalid);

        // 判断是否已存在，不允许重复创建（key: payer + recipient + amount)
        let stream_id = getStreamId(payer_pool.owner, recipient, amount_per_sec);
        let existed = !payer_pool.stream_ids.is_empty() && payer_pool.stream_ids.contains(&stream_id);
        assert!(!existed, EStreamExisted);

        // 保存该笔支付流信息
        payer_pool.stream_ids.insert(stream_id);

        // 创建接收者，并以当前时间作为最后结算时间
        let r_last_settlement_time = clock.timestamp_ms()/1000;
        let reciver_card = ReciverCard {
            id: object::new(ctx),
            payer: payer_pool.owner,
            recipient: recipient,
            r_amount_per: amount_per_sec,
            r_last_settlement_time,
        };
        let reciver_card_address = reciver_card.id.to_address();
        transfer::transfer(reciver_card, recipient);

        // payer 先结算
        settlement(payer_pool, clock);

        // payer 增加总支付额度
        payer_pool.p_total_paid_amount_per = payer_pool.p_total_paid_amount_per + amount_per_sec;

        event::emit(StreamAction {
            stream_id,
            action_type: utf8(b"create stream"),
            payer: payer_pool.owner,
            p_total_paid_amount_per: payer_pool.p_total_paid_amount_per,
            p_last_settlement_time: payer_pool.p_last_settlement_time,
            recipient,
            r_amount_per: amount_per_sec,
            r_last_settlement_time: r_last_settlement_time,
        });

        reciver_card_address
    }

    // step3 雇员领取工资
    public entry fun withdraw(payer_pool: &mut PayerPool, reciver_card: &mut ReciverCard, amount_per_sec: u64, clock: &Clock, ctx: &mut TxContext) {

        // 支付流必须存在
        let stream_id = getStreamId(payer_pool.owner, reciver_card.recipient, amount_per_sec);
        assert!(payer_pool.stream_ids.contains(&stream_id), EStreamNotExisted);

        // payer 结算，并得到结算的时间点 last_upate
        let (last_upate, owe) =settlement(payer_pool, clock);

        // 领取工资
        let delta = last_upate - reciver_card.r_last_settlement_time;
        let income = delta * reciver_card.r_amount_per;
        let income_coin = payer_pool.p_debt.split(income);
        transfer::public_transfer(income_coin.into_coin(ctx), reciver_card.recipient);
        // 更新结算时间
        reciver_card.r_last_settlement_time = last_upate;

        event::emit(WithdrawAction {
            stream_id,
            action_type: utf8(b"reciver withdraw"),
            from: payer_pool.owner,
            to: reciver_card.recipient,
            amount: income,
            owe,
        });
    }

    fun settlement(payer_pool: &mut PayerPool, clock: &Clock): (u64, bool) {
        let delta = clock.timestamp_ms()/1000 - payer_pool.p_last_settlement_time;
        // 计算应支付的费用
        let ready_pay  = delta * payer_pool.p_total_paid_amount_per;

        let mut owe = false;

        // 如果余额足够支付
        if (payer_pool.p_balance.value() >= ready_pay) {
            let ready_pay_coin = payer_pool.p_balance.split(ready_pay);
            payer_pool.p_debt.join(ready_pay_coin);
            payer_pool.p_last_settlement_time = clock.timestamp_ms()/1000;
        } else {
            // 计算能够支付多少秒的总费用
            let timePaid = payer_pool.p_balance.value() / payer_pool.p_total_paid_amount_per;
            payer_pool.p_last_settlement_time = payer_pool.p_last_settlement_time + timePaid;

            // 计算 payer 结算后的余额
            let payer_balance = payer_pool.p_balance.value() % payer_pool.p_total_paid_amount_per;
            // 计算 payer 应支付的费用
            let ready_pay = payer_pool.p_balance.value() - payer_balance;
            let ready_pay_coin = payer_pool.p_balance.split(ready_pay);
            // 应支付的费用转入到 p_debt 字段
            payer_pool.p_debt.join(ready_pay_coin);
            owe = true;
        };

        (payer_pool.p_last_settlement_time, owe)
    }

    // step4 boss 查询余额
    public entry fun getPayerBalance(payer_pool: &PayerPool, clock: &Clock): u64 {
        // 结算前余额
        let p_balance = payer_pool.p_balance.value();
        let delta = clock.timestamp_ms()/1000 - payer_pool.p_last_settlement_time;
        // 计算应支付的费用
        let ready_pay = delta * payer_pool.p_total_paid_amount_per;

        if(p_balance >= ready_pay) {
            // 实际余额 = 结算前余额 - 应支付的费用
            p_balance - ready_pay
        } else {
            0
        }
    }

    // step5 payer 提取余额
    public entry fun withdrawPayer(payer_pool: &mut PayerPool, amount: u64, clock: &Clock, ctx: &mut TxContext) {
        // 必须是 payer owner 才可以提取，因为 payer 是共享对象，因此需要显式控制权限
        assert!(payer_pool.owner == ctx.sender(), ENotAuth);
        // 提取的数量要小于当前余额
        assert!(payer_pool.p_balance.value() >= amount, EDoNotRug);
        
        // 提取后的余额要满足结算要求
        let withdraw_coin = payer_pool.p_balance.split(amount);
        let delta = clock.timestamp_ms()/1000 - payer_pool.p_last_settlement_time;
        assert!(payer_pool.p_balance.value() >= delta * payer_pool.p_total_paid_amount_per, EDoNotRug);

        // 提取后的余额转入到 payer 账户
        transfer::public_transfer(withdraw_coin.into_coin(ctx), payer_pool.owner);

        event::emit(WithdrawAction {
            stream_id: vector::empty<u8>(),
            action_type: utf8(b"payer withdraw"),
            from: payer_pool.id.to_address(),
            to: payer_pool.owner,
            amount,
            owe: false,
        });
    }

    // step5 payer 提取所有余额
    public entry fun withdrawPayerAll(payer_pool: &mut PayerPool, clock: &Clock, ctx: &mut TxContext) {
        // 必须是 payer owner 才可以提取，因为 payer 是共享对象，因此需要显式控制权限
        assert!(payer_pool.owner == ctx.sender(), ENotAuth);

        let delta = clock.timestamp_ms()/1000 - payer_pool.p_last_settlement_time;
        assert!(payer_pool.p_balance.value() >= delta * payer_pool.p_total_paid_amount_per, EDoNotRug);

        let withdraw_amount = payer_pool.p_balance.value() - (delta * payer_pool.p_total_paid_amount_per);
        withdrawPayer(payer_pool, withdraw_amount, clock, ctx);
    }


    // step6 取消支付流
    // 输入的参数依赖于 ptb 获取的 Reciver 信息
    public entry fun cancelStream(payer_pool: &mut PayerPool, recipient: address, amount_per_sec: u64, last_settlement_time: u64, clock: &Clock, ctx: &mut TxContext) {
        // 1.权限控制，必须是 payer owner 才可以取消支付流，因为 payer 是共享对象，因此需要显式控制权限
        assert!(payer_pool.owner == ctx.sender(), ENotAuth);

        // 2.先结算
        // 2.1 支付流必须存在
        let stream_id = getStreamId(payer_pool.owner, recipient, amount_per_sec);
        assert!(payer_pool.stream_ids.contains(&stream_id), EStreamNotExisted);

        // 2.2 payer 结算，并得到结算的时间点 last_upate
        let (last_upate, _owe) =settlement(payer_pool, clock);

        // 2.3 recipient 领取截止到 last_upate 的工资
        let delta = last_upate - last_settlement_time;
        let income = delta * amount_per_sec;
        let income_coin = payer_pool.p_debt.split(income);
        transfer::public_transfer(income_coin.into_coin(ctx), recipient);
        
        // 3.删除支付流
        payer_pool.stream_ids.remove(&stream_id);

        // 4.扣除支付总额
        payer_pool.p_total_paid_amount_per = payer_pool.p_total_paid_amount_per - amount_per_sec;

        event::emit(StreamAction {
            stream_id,
            action_type: utf8(b"cancle stream"),
            payer: payer_pool.owner,
            p_total_paid_amount_per: payer_pool.p_total_paid_amount_per,
            p_last_settlement_time: payer_pool.p_last_settlement_time,
            recipient,
            r_amount_per: amount_per_sec,
            r_last_settlement_time: last_settlement_time,
        });
    }



    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::coin;
    #[test_only]
    use std::debug;
    #[test_only]
    use sui::clock;

    #[test]
    fun test_liner_pay() {
        let alice: address = @100;
        let bob: address = @101;
        let eve: address = @102;

        // test createAndDeposit
        let mut scenario = test_scenario::begin(alice);
        {
            let my_coin = coin::mint_for_testing<SUI>(100 * 10000, scenario.ctx());
            createAndDeposit(my_coin, scenario.ctx());
        };

        scenario.next_tx(alice);

        // test createStream
        {
            let mut payer_pool = scenario.take_shared<PayerPool>();
            assert!(payer_pool.p_balance.value() == 100 * 10000, 0);
            assert!(payer_pool.p_debt.value() == 0, 1);
            assert!(payer_pool.owner == alice, 2);
            let len = payer_pool.stream_ids.size();
            debug::print(&len);
            assert!(payer_pool.stream_ids.is_empty(), 3);
            assert!(payer_pool.p_last_settlement_time == 0, 4);
            assert!(payer_pool.p_total_paid_amount_per == 0, 5);


            let mut my_clock = clock::create_for_testing(scenario.ctx());
            my_clock.set_for_testing(1000 * 10);
            createStream(&mut payer_pool, bob, 1, &my_clock, scenario.ctx());
            test_scenario::return_shared<PayerPool>(payer_pool);
            my_clock.destroy_for_testing();
        };

        scenario.next_tx(bob);

        {
            let payer_pool = scenario.take_shared<PayerPool>();
            let reciver_card = scenario.take_from_sender<ReciverCard>();

            // streamId
            let stream_id = getStreamId(alice, bob, 1);
            debug::print(&utf8(b"stream_id"));
            debug::print(&stream_id);
            assert!(payer_pool.stream_ids.contains(&stream_id), 6);

            // reciver card
            assert!(reciver_card.payer == alice, 7);
            assert!(reciver_card.recipient == bob, 8);
            assert!(reciver_card.r_last_settlement_time == 10, 9);
            assert!(reciver_card.r_amount_per == 1, 10);

            // payer pool total
            assert!(payer_pool.p_total_paid_amount_per == 1, 11);
            assert!(payer_pool.p_last_settlement_time == 10, 12);

            test_scenario::return_shared(payer_pool);
            scenario.return_to_sender<ReciverCard>(reciver_card);

        };

        scenario.next_tx(bob);

        // test withdraw
        {
            let mut payer_pool = scenario.take_shared<PayerPool>();
            let mut reciver_card = scenario.take_from_sender<ReciverCard>();
            let mut my_clock = clock::create_for_testing(scenario.ctx());
            my_clock.set_for_testing(1000 * 20);
            withdraw(&mut payer_pool, &mut reciver_card, 1, &my_clock, scenario.ctx());
            my_clock.destroy_for_testing();

            test_scenario::return_shared(payer_pool);
            scenario.return_to_sender<ReciverCard>(reciver_card);
        };

        scenario.next_tx(bob);

        {
            let payer_pool = scenario.take_shared<PayerPool>();
            let reciver_card = scenario.take_from_sender<ReciverCard>();
            
            let p_balance = payer_pool.p_balance.value();
            debug::print(&utf8(b"p_balance"));
            debug::print(&p_balance);
            assert!(payer_pool.p_last_settlement_time == 20, 13);
            
            let p_debt = payer_pool.p_debt.value();
            debug::print(&utf8(b"p_debt"));
            debug::print(&p_debt);

            let bob_coin = scenario.take_from_sender<Coin<SUI>>();
            let bob_coin_amout = bob_coin.value();
            debug::print(&utf8(b"bob_coin_amout"));
            debug::print(&bob_coin_amout);

            test_scenario::return_shared(payer_pool);
            scenario.return_to_sender<ReciverCard>(reciver_card);
            scenario.return_to_sender<Coin<SUI>>(bob_coin);
        };

        scenario.next_tx(alice);

        // test eve createStream
        {
            let mut payer_pool = scenario.take_shared<PayerPool>();
            
            let mut my_clock = clock::create_for_testing(scenario.ctx());
            my_clock.set_for_testing(1000 * 30);
            createStream(&mut payer_pool, eve, 1, &my_clock, scenario.ctx());
            test_scenario::return_shared<PayerPool>(payer_pool);
            my_clock.destroy_for_testing();
        };

        scenario.next_tx(eve);
        // eve withdraw
        {
            let mut payer_pool = scenario.take_shared<PayerPool>();
            let mut reciver_card = scenario.take_from_sender<ReciverCard>();
            let mut my_clock = clock::create_for_testing(scenario.ctx());
            my_clock.set_for_testing(1000 * 40);
            withdraw(&mut payer_pool, &mut reciver_card, 1, &my_clock, scenario.ctx());
            my_clock.destroy_for_testing();
            test_scenario::return_shared(payer_pool);
            scenario.return_to_sender<ReciverCard>(reciver_card);
        };

        scenario.next_tx(eve);

        {
            let payer_pool = scenario.take_shared<PayerPool>();
            let eve_reciver_card = scenario.take_from_sender<ReciverCard>();
            debug::print(&utf8(b"---------------------------------------"));

            let p_last_settlement_time = payer_pool.p_last_settlement_time;
            debug::print(&utf8(b"payer p_last_settlement_time"));
            debug::print(&p_last_settlement_time);
            assert!(p_last_settlement_time == 40, 13);

            let p_balance = payer_pool.p_balance.value();
            debug::print(&utf8(b"40s p_balance"));
            debug::print(&p_balance);
            assert!(p_balance == (100 * 10000 - 40), 13);
            
            let p_debt = payer_pool.p_debt.value();
            debug::print(&utf8(b"40s p_debt 欠 bob"));
            debug::print(&p_debt);
            assert!(p_debt == 20, 14);

            let eve_coin = scenario.take_from_sender<Coin<SUI>>();
            let eve_coin_amout = eve_coin.value();
            debug::print(&utf8(b"eve_coin_amout"));
            debug::print(&eve_coin_amout);
            assert!(eve_coin_amout == 10, 15);

            let eve_last_update = eve_reciver_card.r_last_settlement_time;
            assert!(eve_last_update == 40, 16);

            test_scenario::return_shared(payer_pool);
            scenario.return_to_sender(eve_reciver_card);
            scenario.return_to_sender<Coin<SUI>>(eve_coin);
        };

        scenario.next_tx(alice);

        // test withdrawPayerAll
        {
            let mut payer_pool = scenario.take_shared<PayerPool>();
            let mut my_clock = clock::create_for_testing(scenario.ctx());
            my_clock.set_for_testing(1000 * 50);
            withdrawPayerAll(&mut payer_pool, &my_clock , scenario.ctx());

            my_clock.destroy_for_testing();
            test_scenario::return_shared(payer_pool);
        };

        scenario.next_tx(alice);

        {
            let payer_pool = scenario.take_shared<PayerPool>();
            debug::print(&utf8(b"50s ======================="));

            let p_balance = payer_pool.p_balance.value();
            debug::print(&utf8(b"50s p_balance"));
            debug::print(&p_balance);
            assert!(p_balance == 20, 13);

            let p_debt = payer_pool.p_debt.value();
            debug::print(&utf8(b"50s p_debt 欠 bob and eve"));
            debug::print(&p_debt);
            assert!(p_debt == 20, 14);

            let alice_balance = scenario.take_from_sender<Coin<SUI>>();
            let alice_balance_amout = alice_balance.value();
            debug::print(&utf8(b"alice_balance_amout"));
            debug::print(&alice_balance_amout);
            assert!(alice_balance_amout == (100 * 10000 - 60), 15);

            assert!(payer_pool.stream_ids.size() == 2, 16);
            assert!(payer_pool.p_last_settlement_time == 40, 17);


            test_scenario::return_shared(payer_pool);
            scenario.return_to_sender<Coin<SUI>>(alice_balance);
        };

        scenario.next_tx(alice);

        // test cancelStream of bob
        {
            let mut payer_pool = scenario.take_shared<PayerPool>();
            let mut my_clock = clock::create_for_testing(scenario.ctx());
            my_clock.set_for_testing(1000 * 50);
            cancelStream(&mut payer_pool, bob, 1, 20, &my_clock, scenario.ctx());

            my_clock.destroy_for_testing();
            test_scenario::return_shared(payer_pool);
        };

        scenario.next_tx(bob);
        
        {
            let payer_pool = scenario.take_shared<PayerPool>();
            debug::print(&utf8(b"cancelStream ======================="));

            // bob SUI 余额变化
            let bob_coin = scenario.take_from_sender<Coin<SUI>>();
            let bob_coin_amout = bob_coin.value();
            debug::print(&utf8(b"bob_coin_amout"));
            debug::print(&bob_coin_amout);
            // 或者 30
            assert!(bob_coin_amout == 30, 13);


            // steam_id 不存在
            assert!(payer_pool.stream_ids.size() == 1, 14);

            // payer total 变成 1
            assert!(payer_pool.p_total_paid_amount_per == 1, 15);


            test_scenario::return_shared(payer_pool);
            scenario.return_to_sender<Coin<SUI>>(bob_coin);
        };

        scenario.end();
    }
}