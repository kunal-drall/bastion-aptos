/// BastionCircles module - Lending circles and group management
///
/// This module handles:
/// - Creation and management of lending circles
/// - Member management (add/remove)
/// - Circle-specific lending rules and limits
/// - Shared collateral pools
module bastion_core::bastion_circles {
    use std::signer;
    use std::error;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;

    // Error codes
    const ENOT_INITIALIZED: u64 = 1;
    const EALREADY_INITIALIZED: u64 = 2;
    const ENOT_CIRCLE_OWNER: u64 = 3;
    const ENOT_MEMBER: u64 = 4;
    const EALREADY_MEMBER: u64 = 5;
    const ECIRCLE_FULL: u64 = 6;
    const EINVALID_PARAMETER: u64 = 7;
    const EINSUFFICIENT_STAKE: u64 = 8;
    const EBID_NOT_FOUND: u64 = 9;
    const EINVALID_BID: u64 = 10;
    const EINSUFFICIENT_POOL: u64 = 11;
    const EBIDDING_CLOSED: u64 = 12;

    // Constants
    const STAKE_TO_LOAN_RATIO: u64 = 200; // 200% - stake must be 2x loan amount
    const BASIS_POINTS: u64 = 10000;
    const BIDDING_PERIOD_SECONDS: u64 = 604800; // 7 days

    /// Circle ownership capability
    struct CircleOwnerCap has key, store {
        circle_id: u64,
        owner: address,
    }

    /// Lending circle structure
    struct Circle has key, store {
        /// Unique circle ID
        id: u64,
        /// Circle owner/creator
        owner: address,
        /// Circle name
        name: vector<u8>,
        /// List of member addresses
        members: vector<address>,
        /// Maximum members allowed
        max_members: u64,
        /// Total pool contribution by all members
        total_pool: u64,
        /// Minimum contribution required per member
        min_contribution: u64,
        /// Circle creation timestamp
        created_at: u64,
        /// Circle active status
        active: bool,
    }

    /// Global circle registry
    struct CircleRegistry has key {
        /// Next circle ID to assign
        next_circle_id: u64,
        /// Total number of circles created
        total_circles: u64,
    }

    /// User's circle memberships
    struct CircleMemberships has key {
        /// List of circle IDs user belongs to
        circle_ids: vector<u64>,
    }

    /// Member stake in a circle
    struct CircleStake has key, store {
        /// Circle ID
        circle_id: u64,
        /// Member address
        member: address,
        /// Staked amount
        stake_amount: u64,
        /// Stake timestamp
        staked_at: u64,
    }

    /// Bid for circle funds
    struct Bid has store, drop {
        /// Bidder address
        bidder: address,
        /// Bid amount
        amount: u64,
        /// Interest rate offered (in basis points)
        interest_rate: u64,
        /// Bid timestamp
        timestamp: u64,
        /// Bid status
        accepted: bool,
    }

    /// Circle bidding round
    struct BiddingRound has key, store {
        /// Circle ID
        circle_id: u64,
        /// Round number
        round_number: u64,
        /// List of bids
        bids: vector<Bid>,
        /// Bidding start time
        start_time: u64,
        /// Bidding end time
        end_time: u64,
        /// Round active status
        active: bool,
    }

    /// Circle events
    struct CircleEvents has key {
        circle_created_events: EventHandle<CircleCreatedEvent>,
        member_added_events: EventHandle<MemberAddedEvent>,
        member_removed_events: EventHandle<MemberRemovedEvent>,
        contribution_events: EventHandle<ContributionEvent>,
        stake_events: EventHandle<StakeEvent>,
        bid_submitted_events: EventHandle<BidSubmittedEvent>,
        funds_distributed_events: EventHandle<FundsDistributedEvent>,
    }

    /// Event: Circle created
    struct CircleCreatedEvent has drop, store {
        circle_id: u64,
        owner: address,
        name: vector<u8>,
        max_members: u64,
        timestamp: u64,
    }

    /// Event: Member added to circle
    struct MemberAddedEvent has drop, store {
        circle_id: u64,
        member: address,
        added_by: address,
        timestamp: u64,
    }

    /// Event: Member removed from circle
    struct MemberRemovedEvent has drop, store {
        circle_id: u64,
        member: address,
        removed_by: address,
        timestamp: u64,
    }

    /// Event: Contribution made to circle
    struct ContributionEvent has drop, store {
        circle_id: u64,
        member: address,
        amount: u64,
        timestamp: u64,
    }

    /// Event: Member staked in circle
    struct StakeEvent has drop, store {
        circle_id: u64,
        member: address,
        stake_amount: u64,
        timestamp: u64,
    }

    /// Event: Bid submitted
    struct BidSubmittedEvent has drop, store {
        circle_id: u64,
        bidder: address,
        amount: u64,
        interest_rate: u64,
        timestamp: u64,
    }

    /// Event: Funds distributed
    struct FundsDistributedEvent has drop, store {
        circle_id: u64,
        recipient: address,
        amount: u64,
        timestamp: u64,
    }

    /// Initialize circle registry
    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        assert!(!exists<CircleRegistry>(admin_addr), error::already_exists(EALREADY_INITIALIZED));
        
        let registry = CircleRegistry {
            next_circle_id: 1,
            total_circles: 0,
        };
        move_to(admin, registry);

        // Initialize event handles
        let events = CircleEvents {
            circle_created_events: account::new_event_handle<CircleCreatedEvent>(admin),
            member_added_events: account::new_event_handle<MemberAddedEvent>(admin),
            member_removed_events: account::new_event_handle<MemberRemovedEvent>(admin),
            contribution_events: account::new_event_handle<ContributionEvent>(admin),
            stake_events: account::new_event_handle<StakeEvent>(admin),
            bid_submitted_events: account::new_event_handle<BidSubmittedEvent>(admin),
            funds_distributed_events: account::new_event_handle<FundsDistributedEvent>(admin),
        };
        move_to(admin, events);
    }

    /// Create a new lending circle
    public entry fun create_circle(
        creator: &signer,
        name: vector<u8>,
        max_members: u64,
        min_contribution: u64,
        registry_addr: address
    ) acquires CircleRegistry, CircleEvents {
        let creator_addr = signer::address_of(creator);
        
        assert!(max_members > 0 && max_members <= 100, error::invalid_argument(EINVALID_PARAMETER));
        assert!(vector::length(&name) > 0, error::invalid_argument(EINVALID_PARAMETER));

        // Get next circle ID from registry
        let registry = borrow_global_mut<CircleRegistry>(registry_addr);
        let circle_id = registry.next_circle_id;
        registry.next_circle_id = circle_id + 1;
        registry.total_circles = registry.total_circles + 1;

        // Create circle
        let members = vector::empty<address>();
        vector::push_back(&mut members, creator_addr);

        let circle = Circle {
            id: circle_id,
            owner: creator_addr,
            name,
            members,
            max_members,
            total_pool: 0,
            min_contribution,
            created_at: timestamp::now_seconds(),
            active: true,
        };

        // Store circle at creator's address with unique resource identifier
        move_to(creator, circle);

        // Create circle owner capability
        let owner_cap = CircleOwnerCap {
            circle_id,
            owner: creator_addr,
        };
        move_to(creator, owner_cap);

        // Initialize creator's memberships if needed
        if (!exists<CircleMemberships>(creator_addr)) {
            let memberships = CircleMemberships {
                circle_ids: vector::empty<u64>(),
            };
            move_to(creator, memberships);
        };
        
        let memberships = borrow_global_mut<CircleMemberships>(creator_addr);
        vector::push_back(&mut memberships.circle_ids, circle_id);

        // Emit event
        let events = borrow_global_mut<CircleEvents>(registry_addr);
        event::emit_event(
            &mut events.circle_created_events,
            CircleCreatedEvent {
                circle_id,
                owner: creator_addr,
                name: circle.name,
                max_members,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Add member to circle - only owner can call
    /// Note: New member should call join_circle to complete their membership with stake
    public entry fun add_member(
        owner: &signer,
        new_member: address,
        registry_addr: address
    ) acquires Circle, CircleOwnerCap, CircleMemberships, CircleEvents {
        let owner_addr = signer::address_of(owner);
        
        assert!(exists<Circle>(owner_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<CircleOwnerCap>(owner_addr), error::permission_denied(ENOT_CIRCLE_OWNER));
        
        let circle = borrow_global_mut<Circle>(owner_addr);
        assert!(circle.owner == owner_addr, error::permission_denied(ENOT_CIRCLE_OWNER));
        assert!(circle.active, error::invalid_state(EINVALID_PARAMETER));
        
        // Check if circle is not full
        assert!(vector::length(&circle.members) < circle.max_members, error::invalid_state(ECIRCLE_FULL));
        
        // Check if member is not already in circle
        assert!(!vector::contains(&circle.members, &new_member), error::already_exists(EALREADY_MEMBER));
        
        // Add member
        vector::push_back(&mut circle.members, new_member);

        // Update member's memberships if already exists
        if (exists<CircleMemberships>(new_member)) {
            let memberships = borrow_global_mut<CircleMemberships>(new_member);
            vector::push_back(&mut memberships.circle_ids, circle.id);
        };
        // Note: If CircleMemberships doesn't exist, it will be created when member calls join_circle

        // Emit event
        let events = borrow_global_mut<CircleEvents>(registry_addr);
        event::emit_event(
            &mut events.member_added_events,
            MemberAddedEvent {
                circle_id: circle.id,
                member: new_member,
                added_by: owner_addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Remove member from circle - only owner can call
    public entry fun remove_member(
        owner: &signer,
        member_to_remove: address,
        registry_addr: address
    ) acquires Circle, CircleOwnerCap, CircleMemberships, CircleEvents {
        let owner_addr = signer::address_of(owner);
        
        assert!(exists<Circle>(owner_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<CircleOwnerCap>(owner_addr), error::permission_denied(ENOT_CIRCLE_OWNER));
        
        let circle = borrow_global_mut<Circle>(owner_addr);
        assert!(circle.owner == owner_addr, error::permission_denied(ENOT_CIRCLE_OWNER));
        
        // Check if member exists in circle
        let (found, index) = vector::index_of(&circle.members, &member_to_remove);
        assert!(found, error::not_found(ENOT_MEMBER));
        
        // Remove member (cannot remove owner)
        assert!(member_to_remove != owner_addr, error::invalid_argument(EINVALID_PARAMETER));
        vector::remove(&mut circle.members, index);

        // Update member's memberships
        if (exists<CircleMemberships>(member_to_remove)) {
            let memberships = borrow_global_mut<CircleMemberships>(member_to_remove);
            let (found, idx) = vector::index_of(&memberships.circle_ids, &circle.id);
            if (found) {
                vector::remove(&mut memberships.circle_ids, idx);
            };
        };

        // Emit event
        let events = borrow_global_mut<CircleEvents>(registry_addr);
        event::emit_event(
            &mut events.member_removed_events,
            MemberRemovedEvent {
                circle_id: circle.id,
                member: member_to_remove,
                removed_by: owner_addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Deactivate circle - only owner can call
    public entry fun deactivate_circle(owner: &signer) acquires Circle, CircleOwnerCap {
        let owner_addr = signer::address_of(owner);
        
        assert!(exists<Circle>(owner_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<CircleOwnerCap>(owner_addr), error::permission_denied(ENOT_CIRCLE_OWNER));
        
        let circle = borrow_global_mut<Circle>(owner_addr);
        assert!(circle.owner == owner_addr, error::permission_denied(ENOT_CIRCLE_OWNER));
        
        circle.active = false;
    }

    /// Get circle info
    public fun get_circle_info(circle_addr: address): (u64, address, u64, u64, bool) acquires Circle {
        assert!(exists<Circle>(circle_addr), error::not_found(ENOT_INITIALIZED));
        let circle = borrow_global<Circle>(circle_addr);
        (circle.id, circle.owner, vector::length(&circle.members), circle.max_members, circle.active)
    }

    /// Check if address is circle member
    public fun is_member(circle_addr: address, member: address): bool acquires Circle {
        if (!exists<Circle>(circle_addr)) {
            return false
        };
        let circle = borrow_global<Circle>(circle_addr);
        vector::contains(&circle.members, &member)
    }

    /// Get member count
    public fun get_member_count(circle_addr: address): u64 acquires Circle {
        assert!(exists<Circle>(circle_addr), error::not_found(ENOT_INITIALIZED));
        let circle = borrow_global<Circle>(circle_addr);
        vector::length(&circle.members)
    }

    /// Join circle with stake
    public entry fun join_circle(
        member: &signer,
        circle_owner_addr: address,
        stake_amount: u64,
        registry_addr: address
    ) acquires Circle, CircleMemberships, CircleEvents {
        let member_addr = signer::address_of(member);
        
        assert!(exists<Circle>(circle_owner_addr), error::not_found(ENOT_INITIALIZED));
        assert!(stake_amount > 0, error::invalid_argument(EINVALID_PARAMETER));
        
        let circle = borrow_global_mut<Circle>(circle_owner_addr);
        assert!(circle.active, error::invalid_state(EINVALID_PARAMETER));
        
        // Check minimum contribution requirement
        assert!(stake_amount >= circle.min_contribution, error::invalid_argument(EINSUFFICIENT_STAKE));
        
        // Check if circle is not full
        assert!(vector::length(&circle.members) < circle.max_members, error::invalid_state(ECIRCLE_FULL));
        
        // Check if member is not already in circle
        assert!(!vector::contains(&circle.members, &member_addr), error::already_exists(EALREADY_MEMBER));
        
        // Add member
        vector::push_back(&mut circle.members, member_addr);
        circle.total_pool = circle.total_pool + stake_amount;

        // Create stake record
        let stake = CircleStake {
            circle_id: circle.id,
            member: member_addr,
            stake_amount,
            staked_at: timestamp::now_seconds(),
        };
        move_to(member, stake);

        // Update member's memberships
        if (!exists<CircleMemberships>(member_addr)) {
            let memberships = CircleMemberships {
                circle_ids: vector::empty<u64>(),
            };
            move_to(member, memberships);
        };
        
        let memberships = borrow_global_mut<CircleMemberships>(member_addr);
        vector::push_back(&mut memberships.circle_ids, circle.id);

        // Emit events
        let events = borrow_global_mut<CircleEvents>(registry_addr);
        event::emit_event(
            &mut events.stake_events,
            StakeEvent {
                circle_id: circle.id,
                member: member_addr,
                stake_amount,
                timestamp: timestamp::now_seconds(),
            }
        );
        event::emit_event(
            &mut events.member_added_events,
            MemberAddedEvent {
                circle_id: circle.id,
                member: member_addr,
                added_by: member_addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Start a new bidding round - only owner can call
    public entry fun start_bidding_round(
        owner: &signer
    ) acquires Circle, CircleOwnerCap {
        let owner_addr = signer::address_of(owner);
        
        assert!(exists<Circle>(owner_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<CircleOwnerCap>(owner_addr), error::permission_denied(ENOT_CIRCLE_OWNER));
        
        let circle = borrow_global<Circle>(owner_addr);
        assert!(circle.owner == owner_addr, error::permission_denied(ENOT_CIRCLE_OWNER));
        
        // Initialize bidding round
        let round_number = if (exists<BiddingRound>(owner_addr)) {
            let old_round = borrow_global<BiddingRound>(owner_addr);
            old_round.round_number + 1
        } else {
            1
        };

        let round = BiddingRound {
            circle_id: circle.id,
            round_number,
            bids: vector::empty<Bid>(),
            start_time: timestamp::now_seconds(),
            end_time: timestamp::now_seconds() + BIDDING_PERIOD_SECONDS,
            active: true,
        };
        
        if (exists<BiddingRound>(owner_addr)) {
            // Replace existing round
            let old_round = move_from<BiddingRound>(owner_addr);
            let BiddingRound { circle_id: _, round_number: _, bids: _, start_time: _, end_time: _, active: _ } = old_round;
        };
        
        move_to(owner, round);
    }

    /// Submit bid for circle funds
    public entry fun submit_bid(
        bidder: &signer,
        circle_owner_addr: address,
        amount: u64,
        interest_rate: u64,
        registry_addr: address
    ) acquires Circle, CircleStake, BiddingRound, CircleEvents {
        let bidder_addr = signer::address_of(bidder);
        
        assert!(exists<Circle>(circle_owner_addr), error::not_found(ENOT_INITIALIZED));
        assert!(amount > 0, error::invalid_argument(EINVALID_PARAMETER));
        
        let circle = borrow_global<Circle>(circle_owner_addr);
        assert!(circle.active, error::invalid_state(EINVALID_PARAMETER));
        
        // Verify bidder is a member
        assert!(vector::contains(&circle.members, &bidder_addr), error::permission_denied(ENOT_MEMBER));
        
        // Check stake-to-loan ratio
        assert!(exists<CircleStake>(bidder_addr), error::not_found(EINSUFFICIENT_STAKE));
        let stake = borrow_global<CircleStake>(bidder_addr);
        assert!(stake.circle_id == circle.id, error::invalid_argument(EINVALID_PARAMETER));
        
        // Enforce stake-to-loan ratio: stake must be at least STAKE_TO_LOAN_RATIO% of loan
        let required_stake = (amount * STAKE_TO_LOAN_RATIO) / 100;
        assert!(stake.stake_amount >= required_stake, error::invalid_argument(EINSUFFICIENT_STAKE));
        
        // Check pool has sufficient funds
        assert!(circle.total_pool >= amount, error::invalid_state(EINSUFFICIENT_POOL));

        // Verify bidding round exists and is active
        assert!(exists<BiddingRound>(circle_owner_addr), error::not_found(ENOT_INITIALIZED));
        let bidding_round = borrow_global_mut<BiddingRound>(circle_owner_addr);
        assert!(bidding_round.active, error::invalid_state(EBIDDING_CLOSED));
        assert!(timestamp::now_seconds() <= bidding_round.end_time, error::invalid_state(EBIDDING_CLOSED));

        // Create and add bid
        let bid = Bid {
            bidder: bidder_addr,
            amount,
            interest_rate,
            timestamp: timestamp::now_seconds(),
            accepted: false,
        };
        vector::push_back(&mut bidding_round.bids, bid);

        // Emit event
        let events = borrow_global_mut<CircleEvents>(registry_addr);
        event::emit_event(
            &mut events.bid_submitted_events,
            BidSubmittedEvent {
                circle_id: circle.id,
                bidder: bidder_addr,
                amount,
                interest_rate,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Distribute funds to winning bidder
    public entry fun distribute_funds(
        owner: &signer,
        winner_addr: address,
        registry_addr: address
    ) acquires Circle, CircleOwnerCap, BiddingRound, CircleEvents {
        let owner_addr = signer::address_of(owner);
        
        assert!(exists<Circle>(owner_addr), error::not_found(ENOT_INITIALIZED));
        assert!(exists<CircleOwnerCap>(owner_addr), error::permission_denied(ENOT_CIRCLE_OWNER));
        
        let circle = borrow_global_mut<Circle>(owner_addr);
        assert!(circle.owner == owner_addr, error::permission_denied(ENOT_CIRCLE_OWNER));
        
        assert!(exists<BiddingRound>(owner_addr), error::not_found(EBID_NOT_FOUND));
        let bidding_round = borrow_global_mut<BiddingRound>(owner_addr);
        
        // Find and validate winning bid
        let bids = &mut bidding_round.bids;
        let bid_count = vector::length(bids);
        assert!(bid_count > 0, error::not_found(EBID_NOT_FOUND));
        
        let i = 0;
        let found = false;
        let distribution_amount = 0;
        while (i < bid_count) {
            let bid = vector::borrow_mut(bids, i);
            if (bid.bidder == winner_addr && !bid.accepted) {
                bid.accepted = true;
                distribution_amount = bid.amount;
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, error::not_found(EBID_NOT_FOUND));
        assert!(circle.total_pool >= distribution_amount, error::invalid_state(EINSUFFICIENT_POOL));
        
        // Update circle pool
        circle.total_pool = circle.total_pool - distribution_amount;

        // Emit event
        let events = borrow_global_mut<CircleEvents>(registry_addr);
        event::emit_event(
            &mut events.funds_distributed_events,
            FundsDistributedEvent {
                circle_id: circle.id,
                recipient: winner_addr,
                amount: distribution_amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    #[test_only]
    use aptos_framework::account::create_signer_for_test;

    #[test(admin = @bastion_core)]
    fun test_initialize(admin: &signer) {
        initialize(admin);
        let admin_addr = signer::address_of(admin);
        assert!(exists<CircleRegistry>(admin_addr), 1);
    }

    #[test(creator = @0x123, registry = @bastion_core)]
    fun test_create_circle(creator: &signer, registry: &signer) {
        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@0x1));
        initialize(registry);
        
        let registry_addr = signer::address_of(registry);
        create_circle(creator, b"Test Circle", 10, 100, registry_addr);
        
        let creator_addr = signer::address_of(creator);
        assert!(exists<Circle>(creator_addr), 1);
        assert!(exists<CircleOwnerCap>(creator_addr), 2);
        
        let (id, owner, member_count, max_members, active) = get_circle_info(creator_addr);
        assert!(id == 1, 3);
        assert!(owner == creator_addr, 4);
        assert!(member_count == 1, 5);
        assert!(max_members == 10, 6);
        assert!(active, 7);
    }
}
