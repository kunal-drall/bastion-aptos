/// BastionCore module - Core functionality and administrative controls
/// 
/// This module provides the foundational components for the Bastion protocol including:
/// - Administrative access control
/// - Protocol configuration and state management
/// - Core events and data structures
module bastion_core::bastion_core {
    use std::signer;
    use std::error;
    use std::vector;
    use std::hash;
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;

    // Error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EALREADY_INITIALIZED: u64 = 2;
    const ENOT_INITIALIZED: u64 = 3;
    const EINVALID_PARAMETER: u64 = 4;
    const EINVALID_AMOUNT: u64 = 5;
    const EINSUFFICIENT_COLLATERAL: u64 = 6;
    const EINVALID_TRUST_SCORE: u64 = 7;
    
    // Constants
    const MAX_TRUST_SCORE: u64 = 1000;

    /// Core protocol configuration and state
    struct ProtocolConfig has key {
        /// Protocol administrator address
        admin: address,
        /// Protocol version
        version: u64,
        /// Protocol paused state
        paused: bool,
        /// Total value locked in protocol
        total_value_locked: u64,
    }

    /// Administrative capability - grants full protocol control
    struct AdminCap has key, store {
        /// Owner of this capability
        owner: address,
    }

    /// User profile resource
    struct UserProfile has key {
        /// User address
        user: address,
        /// Trust score (0-1000)
        trust_score: u64,
        /// Total collateral deposited across all coin types
        total_collateral_value: u64,
        /// Registration timestamp
        registered_at: u64,
        /// Last activity timestamp
        last_activity: u64,
    }

    /// User collateral account for a specific coin type
    struct UserCollateral<phantom CoinType> has key {
        /// Deposited collateral
        collateral: Coin<CoinType>,
        /// Owner address
        owner: address,
    }

    /// Events for protocol initialization
    struct ProtocolEvents has key {
        initialized_events: EventHandle<ProtocolInitializedEvent>,
        admin_changed_events: EventHandle<AdminChangedEvent>,
        paused_events: EventHandle<ProtocolPausedEvent>,
        config_updated_events: EventHandle<ConfigUpdatedEvent>,
        user_registered_events: EventHandle<UserRegisteredEvent>,
        trust_score_changed_events: EventHandle<TrustScoreChangedEvent>,
        deposit_events: EventHandle<DepositEvent>,
        withdrawal_events: EventHandle<WithdrawalEvent>,
    }

    /// Event: Protocol initialized
    struct ProtocolInitializedEvent has drop, store {
        admin: address,
        version: u64,
        timestamp: u64,
    }

    /// Event: Admin address changed
    struct AdminChangedEvent has drop, store {
        old_admin: address,
        new_admin: address,
        timestamp: u64,
    }

    /// Event: Protocol paused/unpaused
    struct ProtocolPausedEvent has drop, store {
        paused: bool,
        admin: address,
        timestamp: u64,
    }

    /// Event: Configuration updated
    struct ConfigUpdatedEvent has drop, store {
        field: vector<u8>,
        admin: address,
        timestamp: u64,
    }

    /// Event: User registered
    struct UserRegisteredEvent has drop, store {
        user: address,
        timestamp: u64,
    }

    /// Event: Trust score changed
    struct TrustScoreChangedEvent has drop, store {
        user: address,
        old_score: u64,
        new_score: u64,
        timestamp: u64,
    }

    /// Event: Collateral deposited
    struct DepositEvent has drop, store {
        user: address,
        amount: u64,
        timestamp: u64,
    }

    /// Event: Collateral withdrawn
    struct WithdrawalEvent has drop, store {
        user: address,
        amount: u64,
        timestamp: u64,
    }

    /// Initialize the Bastion protocol
    /// Can only be called once by the admin account
    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        assert!(!exists<ProtocolConfig>(admin_addr), error::already_exists(EALREADY_INITIALIZED));
        
        // Create protocol configuration
        let config = ProtocolConfig {
            admin: admin_addr,
            version: 1,
            paused: false,
            total_value_locked: 0,
        };
        move_to(admin, config);

        // Create admin capability
        let admin_cap = AdminCap {
            owner: admin_addr,
        };
        move_to(admin, admin_cap);

        // Initialize event handles
        let events = ProtocolEvents {
            initialized_events: account::new_event_handle<ProtocolInitializedEvent>(admin),
            admin_changed_events: account::new_event_handle<AdminChangedEvent>(admin),
            paused_events: account::new_event_handle<ProtocolPausedEvent>(admin),
            config_updated_events: account::new_event_handle<ConfigUpdatedEvent>(admin),
            user_registered_events: account::new_event_handle<UserRegisteredEvent>(admin),
            trust_score_changed_events: account::new_event_handle<TrustScoreChangedEvent>(admin),
            deposit_events: account::new_event_handle<DepositEvent>(admin),
            withdrawal_events: account::new_event_handle<WithdrawalEvent>(admin),
        };

        event::emit_event(
            &mut events.initialized_events,
            ProtocolInitializedEvent {
                admin: admin_addr,
                version: 1,
                timestamp: timestamp::now_seconds(),
            }
        );

        move_to(admin, events);
    }

    /// Update protocol admin - only current admin can call
    public entry fun update_admin(admin: &signer, new_admin: address) acquires ProtocolConfig, ProtocolEvents, AdminCap {
        let admin_addr = signer::address_of(admin);
        
        assert!(exists<ProtocolConfig>(admin_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<AdminCap>(admin_addr), error::permission_denied(ENOT_AUTHORIZED));
        
        let config = borrow_global_mut<ProtocolConfig>(admin_addr);
        assert!(config.admin == admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        
        let old_admin = config.admin;
        config.admin = new_admin;

        // Update admin capability owner
        let admin_cap = borrow_global_mut<AdminCap>(admin_addr);
        admin_cap.owner = new_admin;

        // Emit event
        let events = borrow_global_mut<ProtocolEvents>(admin_addr);
        event::emit_event(
            &mut events.admin_changed_events,
            AdminChangedEvent {
                old_admin,
                new_admin,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Pause/unpause the protocol - only admin can call
    public entry fun set_paused(admin: &signer, paused: bool) acquires ProtocolConfig, ProtocolEvents, AdminCap {
        let admin_addr = signer::address_of(admin);
        assert_admin(admin_addr);
        
        let config = borrow_global_mut<ProtocolConfig>(admin_addr);
        config.paused = paused;

        // Emit event
        let events = borrow_global_mut<ProtocolEvents>(admin_addr);
        event::emit_event(
            &mut events.paused_events,
            ProtocolPausedEvent {
                paused,
                admin: admin_addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Check if protocol is paused
    public fun is_paused(admin_addr: address): bool acquires ProtocolConfig {
        assert!(exists<ProtocolConfig>(admin_addr), error::not_found(ENOT_INITIALIZED));
        borrow_global<ProtocolConfig>(admin_addr).paused
    }

    /// Get protocol version
    public fun get_version(admin_addr: address): u64 acquires ProtocolConfig {
        assert!(exists<ProtocolConfig>(admin_addr), error::not_found(ENOT_INITIALIZED));
        borrow_global<ProtocolConfig>(admin_addr).version
    }

    /// Get total value locked
    public fun get_total_value_locked(admin_addr: address): u64 acquires ProtocolConfig {
        assert!(exists<ProtocolConfig>(admin_addr), error::not_found(ENOT_INITIALIZED));
        borrow_global<ProtocolConfig>(admin_addr).total_value_locked
    }

    /// Update total value locked - internal function for other modules
    public(friend) fun update_total_value_locked(admin_addr: address, new_tvl: u64) acquires ProtocolConfig {
        assert!(exists<ProtocolConfig>(admin_addr), error::not_found(ENOT_INITIALIZED));
        let config = borrow_global_mut<ProtocolConfig>(admin_addr);
        config.total_value_locked = new_tvl;
    }

    /// Assert caller is admin
    fun assert_admin(addr: address) acquires ProtocolConfig, AdminCap {
        assert!(exists<ProtocolConfig>(addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<AdminCap>(addr), error::permission_denied(ENOT_AUTHORIZED));
        let config = borrow_global<ProtocolConfig>(addr);
        assert!(config.admin == addr, error::permission_denied(ENOT_AUTHORIZED));
    }

    /// Check if address has admin capability
    public fun has_admin_capability(addr: address): bool {
        exists<AdminCap>(addr)
    }

    /// Register a new user in the protocol
    public entry fun register_user(account: &signer) acquires ProtocolEvents {
        let user_addr = signer::address_of(account);
        
        assert!(!exists<UserProfile>(user_addr), error::already_exists(EALREADY_INITIALIZED));
        
        let profile = UserProfile {
            user: user_addr,
            trust_score: 500, // Initial trust score
            total_collateral_value: 0,
            registered_at: timestamp::now_seconds(),
            last_activity: timestamp::now_seconds(),
        };
        move_to(account, profile);

        // Emit event
        let events = borrow_global_mut<ProtocolEvents>(@bastion_core);
        event::emit_event(
            &mut events.user_registered_events,
            UserRegisteredEvent {
                user: user_addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Set trust score for a user (admin only)
    public entry fun set_trust_score(
        admin: &signer,
        user_addr: address,
        new_score: u64
    ) acquires UserProfile, ProtocolEvents, ProtocolConfig, AdminCap {
        let admin_addr = signer::address_of(admin);
        assert_admin(admin_addr);
        
        assert!(new_score <= MAX_TRUST_SCORE, error::invalid_argument(EINVALID_TRUST_SCORE));
        assert!(exists<UserProfile>(user_addr), error::not_found(ENOT_INITIALIZED));
        
        let profile = borrow_global_mut<UserProfile>(user_addr);
        let old_score = profile.trust_score;
        profile.trust_score = new_score;
        profile.last_activity = timestamp::now_seconds();

        // Emit event
        let events = borrow_global_mut<ProtocolEvents>(@bastion_core);
        event::emit_event(
            &mut events.trust_score_changed_events,
            TrustScoreChangedEvent {
                user: user_addr,
                old_score,
                new_score,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Deposit collateral for a user
    public entry fun deposit_collateral<CoinType>(
        account: &signer,
        amount: u64
    ) acquires UserProfile, UserCollateral, ProtocolEvents {
        let user_addr = signer::address_of(account);
        
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(exists<UserProfile>(user_addr), error::not_found(ENOT_INITIALIZED));
        
        // Initialize collateral account if it doesn't exist
        if (!exists<UserCollateral<CoinType>>(user_addr)) {
            let collateral_account = UserCollateral<CoinType> {
                collateral: coin::zero<CoinType>(),
                owner: user_addr,
            };
            move_to(account, collateral_account);
        };

        // Withdraw coins from user and add to collateral
        let coins = coin::withdraw<CoinType>(account, amount);
        let collateral_account = borrow_global_mut<UserCollateral<CoinType>>(user_addr);
        coin::merge(&mut collateral_account.collateral, coins);

        // Update user profile
        let profile = borrow_global_mut<UserProfile>(user_addr);
        profile.total_collateral_value = profile.total_collateral_value + amount;
        profile.last_activity = timestamp::now_seconds();

        // Emit event
        let events = borrow_global_mut<ProtocolEvents>(@bastion_core);
        event::emit_event(
            &mut events.deposit_events,
            DepositEvent {
                user: user_addr,
                amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Withdraw collateral for a user
    public entry fun withdraw_collateral<CoinType>(
        account: &signer,
        amount: u64
    ) acquires UserProfile, UserCollateral, ProtocolEvents {
        let user_addr = signer::address_of(account);
        
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(exists<UserProfile>(user_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<UserCollateral<CoinType>>(user_addr), error::not_found(ENOT_INITIALIZED));
        
        let collateral_account = borrow_global_mut<UserCollateral<CoinType>>(user_addr);
        let collateral_value = coin::value(&collateral_account.collateral);
        
        assert!(collateral_value >= amount, error::invalid_argument(EINSUFFICIENT_COLLATERAL));
        
        // Withdraw collateral
        let withdrawn_coins = coin::extract(&mut collateral_account.collateral, amount);
        coin::deposit(user_addr, withdrawn_coins);

        // Update user profile
        let profile = borrow_global_mut<UserProfile>(user_addr);
        profile.total_collateral_value = profile.total_collateral_value - amount;
        profile.last_activity = timestamp::now_seconds();

        // Emit event
        let events = borrow_global_mut<ProtocolEvents>(@bastion_core);
        event::emit_event(
            &mut events.withdrawal_events,
            WithdrawalEvent {
                user: user_addr,
                amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Hash circle identifier (useful for creating unique circle IDs)
    public fun hash_circle_id(name: vector<u8>, creator: address): vector<u8> {
        let creator_bytes = bcs::to_bytes(&creator);
        vector::append(&mut name, creator_bytes);
        hash::sha3_256(name)
    }

    /// Get user profile info
    public fun get_user_profile(user_addr: address): (u64, u64, u64, u64) acquires UserProfile {
        assert!(exists<UserProfile>(user_addr), error::not_found(ENOT_INITIALIZED));
        let profile = borrow_global<UserProfile>(user_addr);
        (profile.trust_score, profile.total_collateral_value, profile.registered_at, profile.last_activity)
    }

    /// Get user collateral balance
    public fun get_collateral_balance<CoinType>(user_addr: address): u64 acquires UserCollateral {
        if (!exists<UserCollateral<CoinType>>(user_addr)) {
            return 0
        };
        coin::value(&borrow_global<UserCollateral<CoinType>>(user_addr).collateral)
    }

    /// Check if user is registered
    public fun is_user_registered(user_addr: address): bool {
        exists<UserProfile>(user_addr)
    }

    #[test(admin = @bastion_core)]
    fun test_initialize(admin: &signer) {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        initialize(admin);
        let admin_addr = signer::address_of(admin);
        assert!(exists<ProtocolConfig>(admin_addr), 1);
        assert!(has_admin_capability(admin_addr), 2);
        assert!(get_version(admin_addr) == 1, 3);
        assert!(!is_paused(admin_addr), 4);
    }

    #[test(admin = @bastion_core)]
    fun test_pause_unpause(admin: &signer) {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        initialize(admin);
        let admin_addr = signer::address_of(admin);
        
        set_paused(admin, true);
        assert!(is_paused(admin_addr), 1);
        
        set_paused(admin, false);
        assert!(!is_paused(admin_addr), 2);
    }

    #[test(admin = @bastion_core, user = @0x123)]
    fun test_register_user(admin: &signer, user: &signer) {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        initialize(admin);
        
        register_user(user);
        let user_addr = signer::address_of(user);
        assert!(is_user_registered(user_addr), 1);
        
        let (trust_score, collateral, _, _) = get_user_profile(user_addr);
        assert!(trust_score == 500, 2);
        assert!(collateral == 0, 3);
    }

    #[test(admin = @bastion_core, user = @0x123)]
    fun test_set_trust_score(admin: &signer, user: &signer) {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        initialize(admin);
        register_user(user);
        
        let user_addr = signer::address_of(user);
        set_trust_score(admin, user_addr, 750);
        
        let (trust_score, _, _, _) = get_user_profile(user_addr);
        assert!(trust_score == 750, 1);
    }

    #[test]
    fun test_hash_circle_id() {
        let name = b"test_circle";
        let creator = @0x123;
        let hash = hash_circle_id(name, creator);
        assert!(vector::length(&hash) == 32, 1); // SHA3-256 produces 32 bytes
    }
}
