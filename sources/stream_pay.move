module stream_pay::liner_pay {

    use sui::coin::Coin;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::bcs;
    use sui::hash;
    use sui::vec_set::{Self, VecSet};

    const EStreamExisted: u64 = 1;
    const EAmountPerSecInvalid: u64 = 2;
    const EStreamNotExisted: u64 = 3;
    const EDoNotRug: u64 = 4;
    const ENotAuth: u64 = 5;

    // todo envent 

    
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

    // step1 创建 Payer Pool 并预存薪资
    public entry fun createAndDeposit(amount: Coin<SUI>, ctx: &mut TxContext) {
        let payer_pool = PayerPool {
            id: object::new(ctx),
            p_balance: amount.into_balance(),
            p_debt: balance::zero(),
            owner: ctx.sender(),
            stream_ids: vec_set::empty(),
            p_last_settlement_time: 0,
            p_total_paid_amount_per: 0,
        };

        transfer::share_object(payer_pool);
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
    public entry fun createStream(payer_pool: &mut PayerPool, recipient: address, amount_per_sec: u64, clock: &Clock, ctx: &mut TxContext) {
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
        let reciver_card = ReciverCard {
            id: object::new(ctx),
            payer: payer_pool.owner,
            recipient: recipient,
            r_amount_per: amount_per_sec,
            r_last_settlement_time: clock.timestamp_ms(),
        };
        transfer::transfer(reciver_card, recipient);

        // payer 先结算
        settlement(payer_pool, clock);

        // payer 增加总支付额度
        payer_pool.p_total_paid_amount_per = payer_pool.p_total_paid_amount_per + amount_per_sec;
    }

    // step3 雇员领取工资
    public entry fun withdraw(payer_pool: &mut PayerPool, reciver_card: &mut ReciverCard, amount_per_sec: u64, clock: &Clock, ctx: &mut TxContext) {

        // 支付流必须存在
        let streamId = getStreamId(payer_pool.owner, reciver_card.recipient, amount_per_sec);
        assert!(payer_pool.stream_ids.contains(&streamId), EStreamNotExisted);

        // payer 结算，并得到结算的时间点 last_upate
        let last_upate =settlement(payer_pool, clock);

        // 领取工资
        let delta = last_upate - reciver_card.r_last_settlement_time;
        let income = delta * reciver_card.r_amount_per;
        let income_coin = payer_pool.p_debt.split(income);
        transfer::public_transfer(income_coin.into_coin(ctx), reciver_card.recipient);
        // 更新结算时间
        reciver_card.r_last_settlement_time = last_upate;
    }

    fun settlement(payer_pool: &mut PayerPool, clock: &Clock): u64 {
        let delta = clock.timestamp_ms() - payer_pool.p_last_settlement_time;
        // 计算应支付的费用
        let ready_pay  = delta * payer_pool.p_total_paid_amount_per;

        // todo event 
        // 如果余额足够支付
        if (payer_pool.p_balance.value() >= ready_pay) {
            let ready_pay_coin = payer_pool.p_balance.split(ready_pay);
            payer_pool.p_debt.join(ready_pay_coin);
            payer_pool.p_last_settlement_time = clock.timestamp_ms();
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
        };

        payer_pool.p_last_settlement_time
    }

    // step4 boss 查询余额
    public entry fun getPayerBalance(payer_pool: &PayerPool, clock: &Clock): u64 {
        // 结算前余额
        let p_balance = payer_pool.p_balance.value();
        let delta = clock.timestamp_ms() - payer_pool.p_last_settlement_time;
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
        let delta = clock.timestamp_ms() - payer_pool.p_last_settlement_time;
        assert!(payer_pool.p_balance.value() >= delta * payer_pool.p_total_paid_amount_per, EDoNotRug);

        // 提取后的余额转入到 payer 账户
        transfer::public_transfer(withdraw_coin.into_coin(ctx), payer_pool.owner);
    }

    // step5 payer 提取所有余额
    public entry fun withdrawPayerAll(payer_pool: &mut PayerPool, clock: &Clock, ctx: &mut TxContext) {
        // 必须是 payer owner 才可以提取，因为 payer 是共享对象，因此需要显式控制权限
        assert!(payer_pool.owner == ctx.sender(), ENotAuth);

        let delta = clock.timestamp_ms() - payer_pool.p_last_settlement_time;
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
        let streamId = getStreamId(payer_pool.owner, recipient, amount_per_sec);
        assert!(payer_pool.stream_ids.contains(&streamId), EStreamNotExisted);

        // 2.2 payer 结算，并得到结算的时间点 last_upate
        let last_upate =settlement(payer_pool, clock);

        // 2.3 recipient 领取截止到 last_upate 的工资
        let delta = last_upate - last_settlement_time;
        let income = delta * amount_per_sec;
        let income_coin = payer_pool.p_debt.split(income);
        transfer::public_transfer(income_coin.into_coin(ctx), recipient);
        
        // 3.删除支付流
        payer_pool.stream_ids.remove(&streamId);

        // 4.扣除支付总额
        payer_pool.p_total_paid_amount_per = payer_pool.p_total_paid_amount_per - amount_per_sec;
    }
}