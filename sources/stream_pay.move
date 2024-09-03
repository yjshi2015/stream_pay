module stream_pay::liner_pay {

    use sui::coin::{Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::bcs;
    use sui::hash;
    use sui::vec_set::{Self, VecSet};
    use sui::event;
    use sui::tx_context::TxContext;
    use sui::object::{Self, UID, new, delete};
    use sui::transfer::{Self, transfer, public_transfer, share_object};
    use std::string::{String, utf8, concat};
    use std::vector;

    // Error codes
    const E_LEN_NOT_EQUAL: u64 = 0;
    const E_STREAM_EXISTED: u64 = 1;
    const E_AMOUNT_PER_SEC_INVALID: u64 = 2;
    const E_STREAM_NOT_EXISTED: u64 = 3;
    const E_INSUFFICIENT_FUNDS: u64 = 4;
    const E_NOT_AUTHORIZED: u64 = 5;

    // PayerPool struct to store information about the payer's pool
    public struct PayerPool has key, store {
        id: UID,
        p_balance: Balance<SUI>, // Payer's balance, linearly decreasing over time
        p_debt: Balance<SUI>, // Amount owed, linearly increasing over time
        owner: address, // Owner's address
        stream_ids: VecSet<vector<u8>>, // Set of stream identifiers
        p_last_settlement_time: u64, // Last settlement time
        p_total_paid_amount_per: u64, // Total amount to be paid per second
    }

    // ReceiverCard struct representing a recipient's card for withdrawing payments
    public struct ReceiverCard has key, store {
        id: UID,
        payer: address, // Address of the payer
        recipient: address, // Address of the recipient
        r_amount_per: u64, // Amount per second to be received
        r_last_settlement_time: u64, // Last settlement time
    }

    // Stream information struct
    public struct StreamInfo has drop {
        payer: address,
        recipient: address,
        amount_per_sec: u64,
    }

    // Event structs for tracking actions
    public struct CreatePayerPool has copy, drop {
        pool_id: UID,
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

    // Function to create a payer pool and multiple streams
    public entry fun createPayPoolAndStream(
        amount: Coin<SUI>, 
        recipients: vector<address>, 
        amount_per_sec_vec: vector<u64>, 
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&recipients) == vector::length(&amount_per_sec_vec), E_LEN_NOT_EQUAL);

        let mut payer_pool = PayerPool {
            id: new(ctx),
            p_balance: amount.into_balance(),
            p_debt: balance::zero(),
            owner: ctx.sender(),
            stream_ids: vec_set::empty(),
            p_last_settlement_time: clock.timestamp_ms() / 1000,
            p_total_paid_amount_per: 0,
        };

        event::emit(CreatePayerPool { pool_id: payer_pool.id, owner: payer_pool.owner });

        let mut i = 0;
        while (i < vector::length(&recipients)) {
            createStream(&mut payer_pool, *vector::borrow(&recipients, i), *vector::borrow(&amount_per_sec_vec, i), clock, ctx);
            i = i + 1;
        };

        share_object(payer_pool);
    }

    // Function to create a payer pool and deposit an amount
    public entry fun createAndDeposit(amount: Coin<SUI>, ctx: &mut TxContext): address {
        let payer_pool = PayerPool {
            id: new(ctx),
            p_balance: amount.into_balance(),
            p_debt: balance::zero(),
            owner: ctx.sender(),
            stream_ids: vec_set::empty(),
            p_last_settlement_time: 0,
            p_total_paid_amount_per: 0,
        };

        event::emit(CreatePayerPool { pool_id: payer_pool.id, owner: payer_pool.owner });
        
        let payer_pool_address = payer_pool.id.to_address();
        share_object(payer_pool);

        payer_pool_address
    }

    // Function to generate a unique stream identifier
    fun getStreamId(payer: address, recipient: address, amount_per_sec: u64): vector<u8> {
        let stream_info = StreamInfo {
            payer,
            recipient,
            amount_per_sec,
        };
        let stream_bytes = bcs::to_bytes(&stream_info);
        hash::keccak256(&stream_bytes)
    }

    // Function to create a payment stream for a recipient
    public fun createStream(payer_pool: &mut PayerPool, recipient: address, amount_per_sec: u64, clock: &Clock, ctx: &mut TxContext): address {
        assert!(payer_pool.owner == ctx.sender(), E_NOT_AUTHORIZED);
        assert!(amount_per_sec > 0, E_AMOUNT_PER_SEC_INVALID);

        let stream_id = getStreamId(payer_pool.owner, recipient, amount_per_sec);
        assert!(!payer_pool.stream_ids.contains(&stream_id), E_STREAM_EXISTED);

        payer_pool.stream_ids.insert(stream_id);

        let r_last_settlement_time = clock.timestamp_ms() / 1000;
        let receiver_card = ReceiverCard {
            id: new(ctx),
            payer: payer_pool.owner,
            recipient,
            r_amount_per: amount_per_sec,
            r_last_settlement_time,
        };
        let receiver_card_address = receiver_card.id.to_address();
        transfer(receiver_card, recipient);

        settlement(payer_pool, clock);

        payer_pool.p_total_paid_amount_per += amount_per_sec;

        event::emit(StreamAction {
            stream_id,
            action_type: utf8(b"create stream"),
            payer: payer_pool.owner,
            p_total_paid_amount_per: payer_pool.p_total_paid_amount_per,
            p_last_settlement_time: payer_pool.p_last_settlement_time,
            recipient,
            r_amount_per: amount_per_sec,
            r_last_settlement_time,
        });

        receiver_card_address
    }

    // Function to withdraw payment by the recipient
    public entry fun withdraw(payer_pool: &mut PayerPool, receiver_card: &mut ReceiverCard, amount_per_sec: u64, clock: &Clock, ctx: &mut TxContext) {
        let stream_id = getStreamId(payer_pool.owner, receiver_card.recipient, amount_per_sec);
        assert!(payer_pool.stream_ids.contains(&stream_id), E_STREAM_NOT_EXISTED);

        let (last_update, owe) = settlement(payer_pool, clock);

        let delta = last_update - receiver_card.r_last_settlement_time;
        let income = delta * receiver_card.r_amount_per;
        let income_coin = payer_pool.p_debt.split(income);
        public_transfer(income_coin.into_coin(ctx), receiver_card.recipient);

        receiver_card.r_last_settlement_time = last_update;

        event::emit(WithdrawAction {
            stream_id,
            action_type: utf8(b"receiver withdraw"),
            from: payer_pool.owner,
            to: receiver_card.recipient,
            amount: income,
            owe,
        });
    }

    // Function to perform settlement of the payer pool
    fun settlement(payer_pool: &mut PayerPool, clock: &Clock): (u64, bool) {
        let delta = clock.timestamp_ms() / 1000 - payer_pool.p_last_settlement_time;
        let ready_pay = delta * payer_pool.p_total_paid_amount_per;

        let mut owe = false;

        if (payer_pool.p_balance.value() >= ready_pay) {
            let ready_pay_coin = payer_pool.p_balance.split(ready_pay);
            payer_pool.p_debt.join(ready_pay_coin);
            payer_pool.p_last_settlement_time = clock.timestamp_ms() / 1000;
        } else {
            let time_paid = payer_pool.p_balance.value() / payer_pool.p_total_paid_amount_per;
            payer_pool.p_last_settlement_time += time_paid;

            let payer_balance = payer_pool.p_balance.value() % payer_pool.p_total_paid_amount_per;
            let ready_pay = payer_pool.p_balance.value() - payer_balance;
            let ready_pay_coin = payer_pool.p_balance.split(ready_pay);
            payer_pool.p_debt.join(ready_pay_coin);
            owe = true;
        };

        (payer_pool.p_last_settlement_time, owe)
    }

    // Additional functions and improvements omitted for brevity
}
