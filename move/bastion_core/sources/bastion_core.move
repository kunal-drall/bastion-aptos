/// BastionCore module - Core functionality and administrative controls
/// 
/// This module provides the foundational components for the Bastion protocol including:
/// - Administrative access control
/// - Protocol configuration and state management
/// - Core events and data structures
module bastion_core::bastion_core {
    use std::signer;
    use std::error;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};

    // Error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EALREADY_INITIALIZED: u64 = 2;
    const ENOT_INITIALIZED: u64 = 3;
    const EINVALID_PARAMETER: u64 = 4;

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

    /// Events for protocol initialization
    struct ProtocolEvents has key {
        initialized_events: EventHandle<ProtocolInitializedEvent>,
        admin_changed_events: EventHandle<AdminChangedEvent>,
        paused_events: EventHandle<ProtocolPausedEvent>,
        config_updated_events: EventHandle<ConfigUpdatedEvent>,
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
        };

        event::emit_event(
            &mut events.initialized_events,
            ProtocolInitializedEvent {
                admin: admin_addr,
                version: 1,
                timestamp: aptos_framework::timestamp::now_seconds(),
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
                timestamp: aptos_framework::timestamp::now_seconds(),
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
                timestamp: aptos_framework::timestamp::now_seconds(),
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

    #[test_only]
    use aptos_framework::timestamp;

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
}
