/// InterestGovernance module - Interest rate governance and management
///
/// This module handles:
/// - Dynamic interest rate calculation
/// - Governance voting on rate changes
/// - Interest accrual mechanisms
/// - Rate model parameters
module bastion_core::interest_governance {
    use std::signer;
    use std::error;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;

    // Error codes
    const ENOT_INITIALIZED: u64 = 1;
    const EALREADY_INITIALIZED: u64 = 2;
    const EINVALID_RATE: u64 = 3;
    const ENOT_AUTHORIZED: u64 = 4;
    const EPROPOSAL_NOT_FOUND: u64 = 5;
    const EALREADY_VOTED: u64 = 6;

    // Constants
    const MAX_INTEREST_RATE: u64 = 10000; // 100% in basis points
    const BASIS_POINTS: u64 = 10000; // 1 basis point = 0.01%

    /// Interest rate model
    struct InterestRateModel has key {
        /// Base interest rate (in basis points)
        base_rate: u64,
        /// Optimal utilization rate (in basis points)
        optimal_utilization: u64,
        /// Slope below optimal utilization
        slope_1: u64,
        /// Slope above optimal utilization
        slope_2: u64,
        /// Last update timestamp
        last_updated: u64,
    }

    /// Governance proposal for rate changes
    struct RateProposal has store, drop {
        /// Proposal ID
        id: u64,
        /// Proposer address
        proposer: address,
        /// Proposed new base rate
        new_base_rate: u64,
        /// Votes in favor
        votes_for: u64,
        /// Votes against
        votes_against: u64,
        /// Proposal creation time
        created_at: u64,
        /// Proposal expiry time
        expires_at: u64,
        /// Executed flag
        executed: bool,
    }

    /// Governance registry
    struct GovernanceRegistry has key {
        /// Next proposal ID
        next_proposal_id: u64,
        /// Minimum votes required for proposal
        quorum: u64,
        /// Voting period duration (in seconds)
        voting_period: u64,
        /// Admin address
        admin: address,
    }

    /// Interest governance events
    struct InterestEvents has key {
        rate_updated_events: EventHandle<RateUpdatedEvent>,
        proposal_created_events: EventHandle<ProposalCreatedEvent>,
        vote_cast_events: EventHandle<VoteCastEvent>,
        proposal_executed_events: EventHandle<ProposalExecutedEvent>,
    }

    /// Event: Interest rate updated
    struct RateUpdatedEvent has drop, store {
        old_base_rate: u64,
        new_base_rate: u64,
        updated_by: address,
        timestamp: u64,
    }

    /// Event: Proposal created
    struct ProposalCreatedEvent has drop, store {
        proposal_id: u64,
        proposer: address,
        new_base_rate: u64,
        timestamp: u64,
    }

    /// Event: Vote cast
    struct VoteCastEvent has drop, store {
        proposal_id: u64,
        voter: address,
        in_favor: bool,
        timestamp: u64,
    }

    /// Event: Proposal executed
    struct ProposalExecutedEvent has drop, store {
        proposal_id: u64,
        executed: bool,
        timestamp: u64,
    }

    /// Initialize interest governance
    public entry fun initialize(
        admin: &signer,
        base_rate: u64,
        optimal_utilization: u64,
        slope_1: u64,
        slope_2: u64
    ) {
        let admin_addr = signer::address_of(admin);
        
        assert!(!exists<InterestRateModel>(admin_addr), error::already_exists(EALREADY_INITIALIZED));
        assert!(base_rate <= MAX_INTEREST_RATE, error::invalid_argument(EINVALID_RATE));
        assert!(optimal_utilization <= BASIS_POINTS, error::invalid_argument(EINVALID_RATE));
        
        // Create interest rate model
        let model = InterestRateModel {
            base_rate,
            optimal_utilization,
            slope_1,
            slope_2,
            last_updated: timestamp::now_seconds(),
        };
        move_to(admin, model);

        // Initialize governance registry
        let registry = GovernanceRegistry {
            next_proposal_id: 1,
            quorum: 100, // Require 100 votes minimum
            voting_period: 86400 * 7, // 7 days in seconds
            admin: admin_addr,
        };
        move_to(admin, registry);

        // Initialize event handles
        let events = InterestEvents {
            rate_updated_events: account::new_event_handle<RateUpdatedEvent>(admin),
            proposal_created_events: account::new_event_handle<ProposalCreatedEvent>(admin),
            vote_cast_events: account::new_event_handle<VoteCastEvent>(admin),
            proposal_executed_events: account::new_event_handle<ProposalExecutedEvent>(admin),
        };
        move_to(admin, events);
    }

    /// Calculate current interest rate based on utilization
    public fun calculate_interest_rate(
        governance_addr: address,
        utilization_rate: u64
    ): u64 acquires InterestRateModel {
        assert!(exists<InterestRateModel>(governance_addr), error::not_found(ENOT_INITIALIZED));
        
        let model = borrow_global<InterestRateModel>(governance_addr);
        
        if (utilization_rate <= model.optimal_utilization) {
            // Below optimal: base_rate + (utilization_rate * slope_1) / optimal_utilization
            model.base_rate + (utilization_rate * model.slope_1) / model.optimal_utilization
        } else {
            // Above optimal: base_rate + slope_1 + ((utilization_rate - optimal) * slope_2) / (BASIS_POINTS - optimal)
            let excess_utilization = utilization_rate - model.optimal_utilization;
            let denominator = BASIS_POINTS - model.optimal_utilization;
            model.base_rate + model.slope_1 + (excess_utilization * model.slope_2) / denominator
        }
    }

    /// Calculate accrued interest
    public fun calculate_accrued_interest(
        principal: u64,
        interest_rate: u64,
        time_elapsed: u64
    ): u64 {
        // Simple interest: principal * rate * time / (BASIS_POINTS * SECONDS_PER_YEAR)
        // For simplicity, using 365 days
        let seconds_per_year = 365 * 24 * 60 * 60;
        (principal * interest_rate * time_elapsed) / (BASIS_POINTS * seconds_per_year)
    }

    /// Update base rate directly (admin only)
    public entry fun update_base_rate(
        admin: &signer,
        new_base_rate: u64
    ) acquires InterestRateModel, GovernanceRegistry, InterestEvents {
        let admin_addr = signer::address_of(admin);
        
        assert!(exists<GovernanceRegistry>(admin_addr), error::not_found(ENOT_INITIALIZED));
        let registry = borrow_global<GovernanceRegistry>(admin_addr);
        assert!(registry.admin == admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        assert!(new_base_rate <= MAX_INTEREST_RATE, error::invalid_argument(EINVALID_RATE));
        
        let model = borrow_global_mut<InterestRateModel>(admin_addr);
        let old_rate = model.base_rate;
        model.base_rate = new_base_rate;
        model.last_updated = timestamp::now_seconds();

        // Emit event
        let events = borrow_global_mut<InterestEvents>(admin_addr);
        event::emit_event(
            &mut events.rate_updated_events,
            RateUpdatedEvent {
                old_base_rate: old_rate,
                new_base_rate,
                updated_by: admin_addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Update optimal utilization rate (admin only)
    public entry fun update_optimal_utilization(
        admin: &signer,
        new_optimal_utilization: u64
    ) acquires InterestRateModel, GovernanceRegistry {
        let admin_addr = signer::address_of(admin);
        
        assert!(exists<GovernanceRegistry>(admin_addr), error::not_found(ENOT_INITIALIZED));
        let registry = borrow_global<GovernanceRegistry>(admin_addr);
        assert!(registry.admin == admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        assert!(new_optimal_utilization <= BASIS_POINTS, error::invalid_argument(EINVALID_RATE));
        
        let model = borrow_global_mut<InterestRateModel>(admin_addr);
        model.optimal_utilization = new_optimal_utilization;
        model.last_updated = timestamp::now_seconds();
    }

    /// Update slope parameters (admin only)
    public entry fun update_slopes(
        admin: &signer,
        new_slope_1: u64,
        new_slope_2: u64
    ) acquires InterestRateModel, GovernanceRegistry {
        let admin_addr = signer::address_of(admin);
        
        assert!(exists<GovernanceRegistry>(admin_addr), error::not_found(ENOT_INITIALIZED));
        let registry = borrow_global<GovernanceRegistry>(admin_addr);
        assert!(registry.admin == admin_addr, error::permission_denied(ENOT_AUTHORIZED));
        
        let model = borrow_global_mut<InterestRateModel>(admin_addr);
        model.slope_1 = new_slope_1;
        model.slope_2 = new_slope_2;
        model.last_updated = timestamp::now_seconds();
    }

    /// Get current interest rate model parameters
    public fun get_rate_model(governance_addr: address): (u64, u64, u64, u64) acquires InterestRateModel {
        assert!(exists<InterestRateModel>(governance_addr), error::not_found(ENOT_INITIALIZED));
        let model = borrow_global<InterestRateModel>(governance_addr);
        (model.base_rate, model.optimal_utilization, model.slope_1, model.slope_2)
    }

    /// Get base rate
    public fun get_base_rate(governance_addr: address): u64 acquires InterestRateModel {
        assert!(exists<InterestRateModel>(governance_addr), error::not_found(ENOT_INITIALIZED));
        borrow_global<InterestRateModel>(governance_addr).base_rate
    }

    #[test_only]
    use aptos_framework::account::create_signer_for_test;

    #[test(admin = @bastion_core)]
    fun test_initialize(admin: &signer) {
        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@0x1));
        initialize(admin, 200, 8000, 100, 500); // 2% base, 80% optimal, slopes
        let admin_addr = signer::address_of(admin);
        assert!(exists<InterestRateModel>(admin_addr), 1);
        assert!(get_base_rate(admin_addr) == 200, 2);
    }

    #[test(admin = @bastion_core)]
    fun test_calculate_interest_rate(admin: &signer) {
        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@0x1));
        initialize(admin, 200, 8000, 100, 500); // 2% base, 80% optimal
        let admin_addr = signer::address_of(admin);
        
        // Test below optimal utilization
        let rate_50 = calculate_interest_rate(admin_addr, 5000); // 50% utilization
        assert!(rate_50 > 200, 1); // Should be higher than base rate
        
        // Test above optimal utilization
        let rate_90 = calculate_interest_rate(admin_addr, 9000); // 90% utilization
        assert!(rate_90 > rate_50, 2); // Should be higher than 50% rate
    }

    #[test(admin = @bastion_core)]
    fun test_calculate_accrued_interest(admin: &signer) {
        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@0x1));
        let principal = 100000;
        let rate = 500; // 5% in basis points
        let time = 365 * 24 * 60 * 60; // 1 year in seconds
        
        let interest = calculate_accrued_interest(principal, rate, time);
        assert!(interest == 5000, 1); // Should be 5% of principal
    }
}
