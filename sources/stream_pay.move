module stream_pay::liner_pay {

    use sui::coin::Coin;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::bcs;
    use sui::hash;
    use sui::vec_set::{Self, VecSet};

    const EDonotEnoughMoney: u64 = 0;
    const EStreamExisted: u64 = 1;
    const EAmountPerSecInvalid: u64 = 2;

    // 支付者（Boss）
    public struct Payer has key, store{
        id: UID,
        // the balance of payer
        p_balance: Balance<SUI>,
        // the money of reciver
        p_debt: Balance<SUI>,
        // owner address
        owner: address,
        stream_ids: VecSet<vector<u8>>,
        // the last settlement time of payer
        p_last_settlement_time: u64,
        // the total paid amount of payer
        p_total_paid_amount_per: u64,
    }

    // 接收者（自由职业者）
    public struct Reciver has key, store {
        id: UID,
        // payer address
        payer: address,
        // reciver address
        recipient: address,
        // wage per second
        r_amount_per: u64,
        // last settlement time
        r_last_settlement_time: u64,
    }

    public struct StreamInfo has drop {
        payer: address,
        reciver: address,
        amount_per_sec: u64,
    }

    // step1 创建 Payer 并预存薪资
    public entry fun createAndDeposit(amount: Coin<SUI>, ctx: &mut TxContext) {
        let payer = Payer {
            id: object::new(ctx),
            p_balance: amount.into_balance(),
            p_debt: balance::zero(),
            owner: ctx.sender(),
            stream_ids: vec_set::empty(),
            p_last_settlement_time: 0,
            p_total_paid_amount_per: 0,
        };

        transfer::share_object(payer);
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

    // step2 boss 创建自动支付流
    public entry fun createStream(payer: &mut Payer, recipient: address, amount_per_sec: u64, clock: &Clock, ctx: &mut TxContext) {
        assert!(amount_per_sec > 0, EAmountPerSecInvalid);

        // 判断是否已存在，不允许重复创建（key: payer + recipient + amount)
        let stream_id = getStreamId(payer.owner, recipient, amount_per_sec);
        let existed = !payer.stream_ids.is_empty() && payer.stream_ids.contains(&stream_id);
        assert!(!existed, EStreamExisted);

        // 保存该笔支付流信息
        payer.stream_ids.insert(stream_id);

        // 创建接收者，并以当前时间作为最后结算时间
        let reciver = Reciver {
            id: object::new(ctx),
            payer: payer.owner,
            recipient: recipient,
            r_amount_per: amount_per_sec,
            r_last_settlement_time: clock.timestamp_ms(),
        };
        transfer::transfer(reciver, recipient);

        // payer 先结算
        settlement(payer, clock);

        // payer 增加总支付额度
        payer.p_total_paid_amount_per = payer.p_total_paid_amount_per + amount_per_sec;
    }

    // step3 雇员领取工资
    public entry fun withdraw(payer: &mut Payer, reciver: &mut Reciver, clock: &Clock, ctx: &mut TxContext) {
        settlement(payer, clock);

        let reciver_delta = clock.timestamp_ms() - reciver.r_last_settlement_time;
        let income = reciver_delta * reciver.r_amount_per;
        let income_coin = payer.p_debt.split(income);
        transfer::public_transfer(income_coin.into_coin(ctx), reciver.recipient);
        reciver.r_last_settlement_time = clock.timestamp_ms();
    }

    public fun settlement(payer: &mut Payer, clock: &Clock) {
        let delta = clock.timestamp_ms() - payer.p_last_settlement_time;
        let ready_pay  = delta * payer.p_total_paid_amount_per;
        assert!(payer.p_balance.value() >= ready_pay, EDonotEnoughMoney);
        let ready_pay_coin = payer.p_balance.split(ready_pay);
        payer.p_debt.join(ready_pay_coin);
        payer.p_last_settlement_time = clock.timestamp_ms();
    }

    // step4 boss 查询余额
}