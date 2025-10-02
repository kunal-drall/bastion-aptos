/// TrustManager module - Trust scoring and reputation system
///
/// This module handles:
/// - Trust score calculation and management
/// - Reputation tracking
/// - Endorsements between users
/// - Credit limits based on trust scores
module bastion_core::trust_manager {
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;

    // Error codes
    const ENOT_INITIALIZED: u64 = 1;
    const EALREADY_INITIALIZED: u64 = 2;
    const EINVALID_SCORE: u64 = 3;
    const ECANNOT_ENDORSE_SELF: u64 = 4;
    const EALREADY_ENDORSED: u64 = 5;
    const ENOT_AUTHORIZED: u64 = 6;

    // Constants
    const MAX_TRUST_SCORE: u64 = 1000;
    const MIN_TRUST_SCORE: u64 = 0;
    const INITIAL_TRUST_SCORE: u64 = 500;

    /// Trust score record for a user
    struct TrustScore has key {
        /// Current trust score (0-1000)
        score: u64,
        /// Number of successful transactions
        successful_transactions: u64,
        /// Number of failed/defaulted transactions
        failed_transactions: u64,
        /// Total amount borrowed
        total_borrowed: u64,
        /// Total amount repaid on time
        total_repaid_on_time: u64,
        /// List of endorsers
        endorsers: vector<address>,
        /// Last updated timestamp
        last_updated: u64,
    }

    /// Endorsement record
    struct Endorsement has store, drop {
        endorser: address,
        endorsed: address,
        timestamp: u64,
    }

    /// Global trust registry
    struct TrustRegistry has key {
        /// Total users with trust scores
        total_users: u64,
        /// Average trust score across all users
        average_score: u64,
    }

    /// Trust events
    struct TrustEvents has key {
        score_updated_events: EventHandle<ScoreUpdatedEvent>,
        endorsement_events: EventHandle<EndorsementEvent>,
        reputation_changed_events: EventHandle<ReputationChangedEvent>,
    }

    /// Event: Trust score updated
    struct ScoreUpdatedEvent has drop, store {
        user: address,
        old_score: u64,
        new_score: u64,
        reason: vector<u8>,
        timestamp: u64,
    }

    /// Event: User endorsed another user
    struct EndorsementEvent has drop, store {
        endorser: address,
        endorsed: address,
        timestamp: u64,
    }

    /// Event: Reputation level changed
    struct ReputationChangedEvent has drop, store {
        user: address,
        old_level: u64,
        new_level: u64,
        timestamp: u64,
    }

    /// Initialize trust registry
    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        assert!(!exists<TrustRegistry>(admin_addr), error::already_exists(EALREADY_INITIALIZED));
        
        let registry = TrustRegistry {
            total_users: 0,
            average_score: INITIAL_TRUST_SCORE,
        };
        move_to(admin, registry);

        // Initialize event handles
        let events = TrustEvents {
            score_updated_events: account::new_event_handle<ScoreUpdatedEvent>(admin),
            endorsement_events: account::new_event_handle<EndorsementEvent>(admin),
            reputation_changed_events: account::new_event_handle<ReputationChangedEvent>(admin),
        };
        move_to(admin, events);
    }

    /// Initialize trust score for a new user
    public entry fun initialize_trust_score(user: &signer) {
        let user_addr = signer::address_of(user);
        
        assert!(!exists<TrustScore>(user_addr), error::already_exists(EALREADY_INITIALIZED));
        
        let trust_score = TrustScore {
            score: INITIAL_TRUST_SCORE,
            successful_transactions: 0,
            failed_transactions: 0,
            total_borrowed: 0,
            total_repaid_on_time: 0,
            endorsers: vector::empty<address>(),
            last_updated: timestamp::now_seconds(),
        };
        move_to(user, trust_score);
    }

    /// Endorse another user (increases their trust score)
    public entry fun endorse_user(
        endorser: &signer,
        endorsed_addr: address,
        registry_addr: address
    ) acquires TrustScore, TrustEvents {
        let endorser_addr = signer::address_of(endorser);
        
        assert!(endorser_addr != endorsed_addr, error::invalid_argument(ECANNOT_ENDORSE_SELF));
        assert!(exists<TrustScore>(endorser_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<TrustScore>(endorsed_addr), error::not_found(ENOT_INITIALIZED));
        
        let endorsed_trust = borrow_global_mut<TrustScore>(endorsed_addr);
        
        // Check if already endorsed
        assert!(!vector::contains(&endorsed_trust.endorsers, &endorser_addr), 
                error::already_exists(EALREADY_ENDORSED));
        
        // Add endorser
        vector::push_back(&mut endorsed_trust.endorsers, endorser_addr);
        
        // Increase trust score (e.g., +10 per endorsement, capped at MAX)
        let old_score = endorsed_trust.score;
        let score_increase = 10;
        endorsed_trust.score = if (endorsed_trust.score + score_increase > MAX_TRUST_SCORE) {
            MAX_TRUST_SCORE
        } else {
            endorsed_trust.score + score_increase
        };
        endorsed_trust.last_updated = timestamp::now_seconds();

        // Emit events
        let events = borrow_global_mut<TrustEvents>(registry_addr);
        event::emit_event(
            &mut events.endorsement_events,
            EndorsementEvent {
                endorser: endorser_addr,
                endorsed: endorsed_addr,
                timestamp: timestamp::now_seconds(),
            }
        );

        event::emit_event(
            &mut events.score_updated_events,
            ScoreUpdatedEvent {
                user: endorsed_addr,
                old_score,
                new_score: endorsed_trust.score,
                reason: b"endorsement",
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Update trust score based on transaction outcome
    public fun update_score_on_transaction(
        user_addr: address,
        success: bool,
        amount: u64,
        registry_addr: address
    ) acquires TrustScore, TrustEvents {
        assert!(exists<TrustScore>(user_addr), error::not_found(ENOT_INITIALIZED));
        
        let trust = borrow_global_mut<TrustScore>(user_addr);
        let old_score = trust.score;
        
        if (success) {
            trust.successful_transactions = trust.successful_transactions + 1;
            trust.total_repaid_on_time = trust.total_repaid_on_time + amount;
            
            // Increase score for successful transaction
            let score_increase = 5;
            trust.score = if (trust.score + score_increase > MAX_TRUST_SCORE) {
                MAX_TRUST_SCORE
            } else {
                trust.score + score_increase
            };
        } else {
            trust.failed_transactions = trust.failed_transactions + 1;
            
            // Decrease score for failed transaction
            let score_decrease = 20;
            trust.score = if (trust.score < score_decrease) {
                MIN_TRUST_SCORE
            } else {
                trust.score - score_decrease
            };
        };
        
        trust.last_updated = timestamp::now_seconds();

        // Emit event
        let events = borrow_global_mut<TrustEvents>(registry_addr);
        event::emit_event(
            &mut events.score_updated_events,
            ScoreUpdatedEvent {
                user: user_addr,
                old_score,
                new_score: trust.score,
                reason: if (success) { b"successful_transaction" } else { b"failed_transaction" },
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Record a borrow
    public fun record_borrow(user_addr: address, amount: u64) acquires TrustScore {
        assert!(exists<TrustScore>(user_addr), error::not_found(ENOT_INITIALIZED));
        let trust = borrow_global_mut<TrustScore>(user_addr);
        trust.total_borrowed = trust.total_borrowed + amount;
        trust.last_updated = timestamp::now_seconds();
    }

    /// Get trust score
    public fun get_trust_score(user_addr: address): u64 acquires TrustScore {
        if (!exists<TrustScore>(user_addr)) {
            return INITIAL_TRUST_SCORE
        };
        borrow_global<TrustScore>(user_addr).score
    }

    /// Calculate credit limit based on trust score
    public fun calculate_credit_limit(user_addr: address, base_limit: u64): u64 acquires TrustScore {
        let score = get_trust_score(user_addr);
        // Credit limit = base_limit * (score / MAX_TRUST_SCORE)
        (base_limit * score) / MAX_TRUST_SCORE
    }

    /// Get reputation level (0-5 stars based on score)
    public fun get_reputation_level(user_addr: address): u64 acquires TrustScore {
        let score = get_trust_score(user_addr);
        if (score >= 900) { 5 }
        else if (score >= 750) { 4 }
        else if (score >= 600) { 3 }
        else if (score >= 400) { 2 }
        else if (score >= 200) { 1 }
        else { 0 }
    }

    /// Get transaction statistics
    public fun get_transaction_stats(user_addr: address): (u64, u64, u64) acquires TrustScore {
        if (!exists<TrustScore>(user_addr)) {
            return (0, 0, 0)
        };
        let trust = borrow_global<TrustScore>(user_addr);
        (trust.successful_transactions, trust.failed_transactions, trust.total_borrowed)
    }

    /// Get number of endorsements
    public fun get_endorsement_count(user_addr: address): u64 acquires TrustScore {
        if (!exists<TrustScore>(user_addr)) {
            return 0
        };
        vector::length(&borrow_global<TrustScore>(user_addr).endorsers)
    }

    #[test_only]
    use aptos_framework::account::create_signer_for_test;

    #[test(admin = @bastion_core)]
    fun test_initialize(admin: &signer) {
        initialize(admin);
        let admin_addr = signer::address_of(admin);
        assert!(exists<TrustRegistry>(admin_addr), 1);
    }

    #[test(user = @0x123)]
    fun test_initialize_trust_score(user: &signer) {
        initialize_trust_score(user);
        let user_addr = signer::address_of(user);
        assert!(exists<TrustScore>(user_addr), 1);
        assert!(get_trust_score(user_addr) == INITIAL_TRUST_SCORE, 2);
    }

    #[test(endorser = @0x123, endorsed = @0x456, registry = @bastion_core)]
    fun test_endorse_user(endorser: &signer, endorsed: &signer, registry: &signer) {
        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@0x1));
        initialize(registry);
        initialize_trust_score(endorser);
        initialize_trust_score(endorsed);
        
        let endorsed_addr = signer::address_of(endorsed);
        let initial_score = get_trust_score(endorsed_addr);
        
        endorse_user(endorser, endorsed_addr, signer::address_of(registry));
        
        let new_score = get_trust_score(endorsed_addr);
        assert!(new_score > initial_score, 1);
        assert!(get_endorsement_count(endorsed_addr) == 1, 2);
    }
}
