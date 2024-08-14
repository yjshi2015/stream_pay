module stream_pay::liner_pay {

    use sui::coin::Coin;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::Clock;

    const EDonotEnoughMoney : u64 = 0;

    // 支付者（Boss）
    public struct Payer has key, store{
        id: UID,
        // 资金池余额
        p_balance: Balance<SUI>,
        // 待支付的债务
        p_debt: Balance<SUI>,
        // boss 地址
        owner: address,
        // 上次结算时间
        p_last_settlement_time: u64,
        // 每秒支付的工资总数
        p_total_paid_amount_per: u64,
    }

    // 接收者（雇员）
    public struct Reciver has key, store {
        id: UID,
        payer: address,
        recipient: address,
        r_amount_per: u64,
        r_last_update_time: u64,
    }

    // step1 创建 Payer 并预存薪资
    public entry fun createAndDeposit(amount: Coin<SUI>, ctx: &mut TxContext) {
        let payer = Payer {
            id: object::new(ctx),
            p_balance: amount.into_balance(),
            p_debt: balance::zero(),
            owner: ctx.sender(),
            p_last_settlement_time: 0,
            p_total_paid_amount_per: 0,
        };

        transfer::share_object(payer);
    }

    // step2 boss 创建自动支付流
    public entry fun createStream(payer: &mut Payer, recipient: address, amount_per_sec: u64, ctx: &mut TxContext) {
        // todo payer 增加总支付额度
        payer.p_total_paid_amount_per = payer.p_total_paid_amount_per + amount_per_sec;

        let reciver = Reciver {
            id: object::new(ctx),
            payer: payer.owner,
            recipient: recipient,
            r_amount_per: amount_per_sec,
            r_last_update_time: 0,
        };
        transfer::transfer(reciver, recipient);
    }

    // step3 雇员领取工资
    public entry fun withdraw(payer: &mut Payer, reciver: &mut Reciver, clock: &Clock, ctx: &mut TxContext) {
        settlement(payer, clock);

        let reciver_delta = clock.timestamp_ms() - reciver.r_last_update_time;
        let income = reciver_delta * reciver.r_amount_per;
        let income_coin = payer.p_debt.split(income);
        transfer::public_transfer(income_coin.into_coin(ctx), reciver.recipient);
        reciver.r_last_update_time = clock.timestamp_ms();
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
git remote add origin git@github.com:yjshi2015/stream_pay.git