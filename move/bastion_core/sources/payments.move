/// Payments module - Payment processing and settlement
///
/// This module handles:
/// - Payment creation and processing
/// - Payment schedules and recurring payments
/// - Payment status tracking
/// - Multi-party payment splits
module bastion_core::payments {
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;

    // Error codes
    const ENOT_INITIALIZED: u64 = 1;
    const EALREADY_INITIALIZED: u64 = 2;
    const EPAYMENT_NOT_FOUND: u64 = 3;
    const EINVALID_AMOUNT: u64 = 4;
    const EPAYMENT_ALREADY_COMPLETED: u64 = 5;
    const ENOT_AUTHORIZED: u64 = 6;
    const EINVALID_STATUS: u64 = 7;

    // Payment status constants
    const STATUS_PENDING: u8 = 0;
    const STATUS_PROCESSING: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_FAILED: u8 = 3;
    const STATUS_CANCELLED: u8 = 4;

    /// Payment record
    struct Payment has store, drop {
        /// Payment ID
        id: u64,
        /// Payer address
        payer: address,
        /// Payee address
        payee: address,
        /// Payment amount
        amount: u64,
        /// Payment status
        status: u8,
        /// Creation timestamp
        created_at: u64,
        /// Completion timestamp (0 if not completed)
        completed_at: u64,
        /// Payment metadata/description
        description: vector<u8>,
    }

    /// Payment account for managing user payments
    struct PaymentAccount<phantom CoinType> has key {
        /// User's pending incoming payments
        incoming_payments: vector<Payment>,
        /// User's pending outgoing payments
        outgoing_payments: vector<Payment>,
        /// Escrow balance for pending payments
        escrow_balance: Coin<CoinType>,
        /// Total payments sent
        total_sent: u64,
        /// Total payments received
        total_received: u64,
    }

    /// Global payment registry
    struct PaymentRegistry has key {
        /// Next payment ID
        next_payment_id: u64,
        /// Total payments processed
        total_payments: u64,
        /// Total volume processed
        total_volume: u64,
    }

    /// Payment schedule for recurring payments
    struct PaymentSchedule has key {
        /// Schedule owner
        owner: address,
        /// Recipient address
        recipient: address,
        /// Payment amount per period
        amount_per_period: u64,
        /// Payment frequency in seconds
        frequency: u64,
        /// Next payment due timestamp
        next_payment_due: u64,
        /// Total payments made
        payments_made: u64,
        /// Active status
        active: bool,
    }

    /// Payment events
    struct PaymentEvents has key {
        payment_created_events: EventHandle<PaymentCreatedEvent>,
        payment_completed_events: EventHandle<PaymentCompletedEvent>,
        payment_failed_events: EventHandle<PaymentFailedEvent>,
        payment_cancelled_events: EventHandle<PaymentCancelledEvent>,
    }

    /// Event: Payment created
    struct PaymentCreatedEvent has drop, store {
        payment_id: u64,
        payer: address,
        payee: address,
        amount: u64,
        timestamp: u64,
    }

    /// Event: Payment completed
    struct PaymentCompletedEvent has drop, store {
        payment_id: u64,
        payer: address,
        payee: address,
        amount: u64,
        timestamp: u64,
    }

    /// Event: Payment failed
    struct PaymentFailedEvent has drop, store {
        payment_id: u64,
        payer: address,
        payee: address,
        reason: vector<u8>,
        timestamp: u64,
    }

    /// Event: Payment cancelled
    struct PaymentCancelledEvent has drop, store {
        payment_id: u64,
        cancelled_by: address,
        timestamp: u64,
    }

    /// Initialize payment registry
    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        assert!(!exists<PaymentRegistry>(admin_addr), error::already_exists(EALREADY_INITIALIZED));
        
        let registry = PaymentRegistry {
            next_payment_id: 1,
            total_payments: 0,
            total_volume: 0,
        };
        move_to(admin, registry);

        // Initialize event handles
        let events = PaymentEvents {
            payment_created_events: account::new_event_handle<PaymentCreatedEvent>(admin),
            payment_completed_events: account::new_event_handle<PaymentCompletedEvent>(admin),
            payment_failed_events: account::new_event_handle<PaymentFailedEvent>(admin),
            payment_cancelled_events: account::new_event_handle<PaymentCancelledEvent>(admin),
        };
        move_to(admin, events);
    }

    /// Initialize payment account for a user
    public entry fun initialize_payment_account<CoinType>(user: &signer) {
        let user_addr = signer::address_of(user);
        
        assert!(!exists<PaymentAccount<CoinType>>(user_addr), error::already_exists(EALREADY_INITIALIZED));
        
        let account = PaymentAccount<CoinType> {
            incoming_payments: vector::empty<Payment>(),
            outgoing_payments: vector::empty<Payment>(),
            escrow_balance: coin::zero<CoinType>(),
            total_sent: 0,
            total_received: 0,
        };
        move_to(user, account);
    }

    /// Create a new payment
    public entry fun create_payment<CoinType>(
        payer: &signer,
        payee: address,
        amount: u64,
        description: vector<u8>,
        registry_addr: address
    ) acquires PaymentAccount, PaymentRegistry, PaymentEvents {
        let payer_addr = signer::address_of(payer);
        
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        
        // Initialize payment account if needed
        if (!exists<PaymentAccount<CoinType>>(payer_addr)) {
            initialize_payment_account<CoinType>(payer);
        };
        if (!exists<PaymentAccount<CoinType>>(payee)) {
            let payee_signer = &account::create_signer_for_test(payee);
            initialize_payment_account<CoinType>(payee_signer);
        };
        
        // Get payment ID from registry
        let registry = borrow_global_mut<PaymentRegistry>(registry_addr);
        let payment_id = registry.next_payment_id;
        registry.next_payment_id = payment_id + 1;
        
        // Create payment record
        let payment = Payment {
            id: payment_id,
            payer: payer_addr,
            payee,
            amount,
            status: STATUS_PENDING,
            created_at: timestamp::now_seconds(),
            completed_at: 0,
            description,
        };
        
        // Add to outgoing payments for payer
        let payer_account = borrow_global_mut<PaymentAccount<CoinType>>(payer_addr);
        vector::push_back(&mut payer_account.outgoing_payments, payment);
        
        // Add to incoming payments for payee
        let payee_account = borrow_global_mut<PaymentAccount<CoinType>>(payee);
        vector::push_back(&mut payee_account.incoming_payments, payment);
        
        // Withdraw from payer and hold in escrow
        let payment_coins = coin::withdraw<CoinType>(payer, amount);
        coin::merge(&mut payer_account.escrow_balance, payment_coins);

        // Emit event
        let events = borrow_global_mut<PaymentEvents>(registry_addr);
        event::emit_event(
            &mut events.payment_created_events,
            PaymentCreatedEvent {
                payment_id,
                payer: payer_addr,
                payee,
                amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Complete a payment
    public entry fun complete_payment<CoinType>(
        payee: &signer,
        payment_id: u64,
        registry_addr: address
    ) acquires PaymentAccount, PaymentRegistry, PaymentEvents {
        let payee_addr = signer::address_of(payee);
        
        assert!(exists<PaymentAccount<CoinType>>(payee_addr), error::not_found(ENOT_INITIALIZED));
        
        let payee_account = borrow_global_mut<PaymentAccount<CoinType>>(payee_addr);
        
        // Find payment in incoming payments
        let len = vector::length(&payee_account.incoming_payments);
        let i = 0;
        let found = false;
        let payment_idx = 0;
        
        while (i < len) {
            let payment = vector::borrow(&payee_account.incoming_payments, i);
            if (payment.id == payment_id) {
                assert!(payment.status == STATUS_PENDING, error::invalid_state(EINVALID_STATUS));
                assert!(payment.payee == payee_addr, error::permission_denied(ENOT_AUTHORIZED));
                found = true;
                payment_idx = i;
                break
            };
            i = i + 1;
        };
        
        assert!(found, error::not_found(EPAYMENT_NOT_FOUND));
        
        // Get payment details before removal
        let payment = vector::borrow(&payee_account.incoming_payments, payment_idx);
        let amount = payment.amount;
        let payer_addr = payment.payer;
        
        // Update payment status in vector (we'll remove it)
        vector::remove(&mut payee_account.incoming_payments, payment_idx);
        
        // Transfer from payer's escrow to payee
        let payer_account = borrow_global_mut<PaymentAccount<CoinType>>(payer_addr);
        let payment_coins = coin::extract(&mut payer_account.escrow_balance, amount);
        coin::deposit(payee_addr, payment_coins);
        
        // Update statistics
        payer_account.total_sent = payer_account.total_sent + amount;
        payee_account.total_received = payee_account.total_received + amount;
        
        let registry = borrow_global_mut<PaymentRegistry>(registry_addr);
        registry.total_payments = registry.total_payments + 1;
        registry.total_volume = registry.total_volume + amount;

        // Emit event
        let events = borrow_global_mut<PaymentEvents>(registry_addr);
        event::emit_event(
            &mut events.payment_completed_events,
            PaymentCompletedEvent {
                payment_id,
                payer: payer_addr,
                payee: payee_addr,
                amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Cancel a pending payment (payer only)
    public entry fun cancel_payment<CoinType>(
        payer: &signer,
        payment_id: u64,
        registry_addr: address
    ) acquires PaymentAccount, PaymentEvents {
        let payer_addr = signer::address_of(payer);
        
        assert!(exists<PaymentAccount<CoinType>>(payer_addr), error::not_found(ENOT_INITIALIZED));
        
        let payer_account = borrow_global_mut<PaymentAccount<CoinType>>(payer_addr);
        
        // Find payment in outgoing payments
        let len = vector::length(&payer_account.outgoing_payments);
        let i = 0;
        let found = false;
        let payment_idx = 0;
        
        while (i < len) {
            let payment = vector::borrow(&payer_account.outgoing_payments, i);
            if (payment.id == payment_id) {
                assert!(payment.status == STATUS_PENDING, error::invalid_state(EINVALID_STATUS));
                assert!(payment.payer == payer_addr, error::permission_denied(ENOT_AUTHORIZED));
                found = true;
                payment_idx = i;
                break
            };
            i = i + 1;
        };
        
        assert!(found, error::not_found(EPAYMENT_NOT_FOUND));
        
        // Get payment amount
        let payment = vector::borrow(&payer_account.outgoing_payments, payment_idx);
        let amount = payment.amount;
        
        // Remove payment
        vector::remove(&mut payer_account.outgoing_payments, payment_idx);
        
        // Return funds from escrow to payer
        let refund_coins = coin::extract(&mut payer_account.escrow_balance, amount);
        coin::deposit(payer_addr, refund_coins);

        // Emit event
        let events = borrow_global_mut<PaymentEvents>(registry_addr);
        event::emit_event(
            &mut events.payment_cancelled_events,
            PaymentCancelledEvent {
                payment_id,
                cancelled_by: payer_addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Get payment statistics for a user
    public fun get_payment_stats<CoinType>(user_addr: address): (u64, u64) acquires PaymentAccount {
        if (!exists<PaymentAccount<CoinType>>(user_addr)) {
            return (0, 0)
        };
        let account = borrow_global<PaymentAccount<CoinType>>(user_addr);
        (account.total_sent, account.total_received)
    }

    /// Get pending payment count
    public fun get_pending_payment_count<CoinType>(user_addr: address): (u64, u64) acquires PaymentAccount {
        if (!exists<PaymentAccount<CoinType>>(user_addr)) {
            return (0, 0)
        };
        let account = borrow_global<PaymentAccount<CoinType>>(user_addr);
        (vector::length(&account.outgoing_payments), vector::length(&account.incoming_payments))
    }

    /// Get escrow balance
    public fun get_escrow_balance<CoinType>(user_addr: address): u64 acquires PaymentAccount {
        if (!exists<PaymentAccount<CoinType>>(user_addr)) {
            return 0
        };
        coin::value(&borrow_global<PaymentAccount<CoinType>>(user_addr).escrow_balance)
    }

    #[test_only]
    use aptos_framework::account::create_signer_for_test;

    #[test(admin = @bastion_core)]
    fun test_initialize(admin: &signer) {
        initialize(admin);
        let admin_addr = signer::address_of(admin);
        assert!(exists<PaymentRegistry>(admin_addr), 1);
    }
}
