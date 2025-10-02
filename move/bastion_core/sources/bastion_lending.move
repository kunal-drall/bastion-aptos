/// BastionLending module - Lending and borrowing functionality
///
/// This module handles:
/// - Collateral deposits and withdrawals
/// - Loan origination and repayment
/// - Collateralization ratio management
/// - Liquidation processes
module bastion_core::bastion_lending {
    use std::signer;
    use std::error;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;

    // Error codes
    const ENOT_INITIALIZED: u64 = 1;
    const EALREADY_INITIALIZED: u64 = 2;
    const EINSUFFICIENT_COLLATERAL: u64 = 3;
    const ELOAN_NOT_FOUND: u64 = 4;
    const EINVALID_AMOUNT: u64 = 5;
    const EUNDERCOLLATERALIZED: u64 = 6;
    const ENOT_AUTHORIZED: u64 = 7;
    const ELOAN_REQUEST_NOT_FOUND: u64 = 8;
    const ELOAN_ALREADY_FULFILLED: u64 = 9;
    const ENOT_LIQUIDATABLE: u64 = 10;

    // Constants
    const DISPUTE_WINDOW_SECONDS: u64 = 86400; // 24 hours in seconds
    const BASIS_POINTS: u64 = 10000; // For percentage calculations

    /// Collateral management capability
    struct CollateralCap has key, store {
        owner: address,
    }

    /// Loan request structure
    struct LoanRequest has key, store {
        /// Request ID
        id: u64,
        /// Borrower address
        borrower: address,
        /// Requested loan amount
        amount: u64,
        /// Interest rate (in basis points)
        interest_rate: u64,
        /// Loan duration in seconds
        duration: u64,
        /// Collateral offered
        collateral_amount: u64,
        /// Request creation timestamp
        created_at: u64,
        /// Fulfillment status
        fulfilled: bool,
        /// Fulfiller address (if fulfilled)
        fulfiller: address,
    }

    /// Loan request registry
    struct LoanRequestRegistry has key {
        /// Next loan request ID
        next_request_id: u64,
        /// Total loan requests created
        total_requests: u64,
    }

    /// User's lending account
    struct LendingAccount<phantom CoinType> has key {
        /// Deposited collateral amount
        collateral: Coin<CoinType>,
        /// Active loan amount
        loan_amount: u64,
        /// Interest accrued
        interest_accrued: u64,
        /// Last update timestamp
        last_update: u64,
        /// Collateral capability
        collateral_cap: CollateralCap,
    }

    /// Protocol lending pool
    struct LendingPool<phantom CoinType> has key {
        /// Total collateral deposited
        total_collateral: u64,
        /// Total loans issued
        total_loans: u64,
        /// Available liquidity
        available_liquidity: Coin<CoinType>,
        /// Minimum collateralization ratio (in basis points, e.g., 15000 = 150%)
        min_collateral_ratio: u64,
        /// Total reserves
        reserves: u64,
    }

    /// Lending events
    struct LendingEvents has key {
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
        borrow_events: EventHandle<BorrowEvent>,
        repay_events: EventHandle<RepayEvent>,
        liquidation_events: EventHandle<LiquidationEvent>,
        loan_request_created_events: EventHandle<LoanRequestCreatedEvent>,
        loan_fulfilled_events: EventHandle<LoanFulfilledEvent>,
    }

    /// Event: Collateral deposited
    struct DepositEvent has drop, store {
        user: address,
        amount: u64,
        timestamp: u64,
    }

    /// Event: Collateral withdrawn
    struct WithdrawEvent has drop, store {
        user: address,
        amount: u64,
        timestamp: u64,
    }

    /// Event: Loan borrowed
    struct BorrowEvent has drop, store {
        user: address,
        amount: u64,
        collateral_amount: u64,
        timestamp: u64,
    }

    /// Event: Loan repaid
    struct RepayEvent has drop, store {
        user: address,
        amount: u64,
        interest: u64,
        timestamp: u64,
    }

    /// Event: Position liquidated
    struct LiquidationEvent has drop, store {
        user: address,
        liquidator: address,
        collateral_seized: u64,
        debt_repaid: u64,
        timestamp: u64,
    }

    /// Event: Loan request created
    struct LoanRequestCreatedEvent has drop, store {
        request_id: u64,
        borrower: address,
        amount: u64,
        interest_rate: u64,
        duration: u64,
        collateral_amount: u64,
        timestamp: u64,
    }

    /// Event: Loan fulfilled
    struct LoanFulfilledEvent has drop, store {
        request_id: u64,
        borrower: address,
        fulfiller: address,
        amount: u64,
        timestamp: u64,
    }

    /// Initialize lending pool for a specific coin type
    public entry fun initialize_pool<CoinType>(
        admin: &signer,
        min_collateral_ratio: u64
    ) {
        let admin_addr = signer::address_of(admin);
        
        assert!(!exists<LendingPool<CoinType>>(admin_addr), error::already_exists(EALREADY_INITIALIZED));
        assert!(min_collateral_ratio >= 10000, error::invalid_argument(EINVALID_AMOUNT)); // At least 100%

        let pool = LendingPool<CoinType> {
            total_collateral: 0,
            total_loans: 0,
            available_liquidity: coin::zero<CoinType>(),
            min_collateral_ratio,
            reserves: 0,
        };
        move_to(admin, pool);

        // Initialize event handles
        let events = LendingEvents {
            deposit_events: account::new_event_handle<DepositEvent>(admin),
            withdraw_events: account::new_event_handle<WithdrawEvent>(admin),
            borrow_events: account::new_event_handle<BorrowEvent>(admin),
            repay_events: account::new_event_handle<RepayEvent>(admin),
            liquidation_events: account::new_event_handle<LiquidationEvent>(admin),
            loan_request_created_events: account::new_event_handle<LoanRequestCreatedEvent>(admin),
            loan_fulfilled_events: account::new_event_handle<LoanFulfilledEvent>(admin),
        };
        move_to(admin, events);

        // Initialize loan request registry
        let registry = LoanRequestRegistry {
            next_request_id: 1,
            total_requests: 0,
        };
        move_to(admin, registry);
    }

    /// Deposit collateral
    public entry fun deposit_collateral<CoinType>(
        user: &signer,
        amount: u64
    ) acquires LendingAccount, LendingEvents {
        let user_addr = signer::address_of(user);
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));

        // Initialize lending account if it doesn't exist
        if (!exists<LendingAccount<CoinType>>(user_addr)) {
            let collateral_cap = CollateralCap { owner: user_addr };
            let account = LendingAccount<CoinType> {
                collateral: coin::zero<CoinType>(),
                loan_amount: 0,
                interest_accrued: 0,
                last_update: timestamp::now_seconds(),
                collateral_cap,
            };
            move_to(user, account);
        };

        // Withdraw coins from user and add to collateral
        let coins = coin::withdraw<CoinType>(user, amount);
        let lending_account = borrow_global_mut<LendingAccount<CoinType>>(user_addr);
        coin::merge(&mut lending_account.collateral, coins);

        // Emit event
        let events = borrow_global_mut<LendingEvents>(@bastion_core);
        event::emit_event(
            &mut events.deposit_events,
            DepositEvent {
                user: user_addr,
                amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Withdraw collateral (only if not undercollateralized)
    public entry fun withdraw_collateral<CoinType>(
        user: &signer,
        amount: u64,
        pool_addr: address
    ) acquires LendingAccount, LendingPool, LendingEvents {
        let user_addr = signer::address_of(user);
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(exists<LendingAccount<CoinType>>(user_addr), error::not_found(ENOT_INITIALIZED));

        let lending_account = borrow_global_mut<LendingAccount<CoinType>>(user_addr);
        let collateral_value = coin::value(&lending_account.collateral);
        assert!(collateral_value >= amount, error::invalid_argument(EINSUFFICIENT_COLLATERAL));

        // Check collateralization ratio after withdrawal
        if (lending_account.loan_amount > 0) {
            let remaining_collateral = collateral_value - amount;
            let pool = borrow_global<LendingPool<CoinType>>(pool_addr);
            let required_collateral = (lending_account.loan_amount * pool.min_collateral_ratio) / 10000;
            assert!(remaining_collateral >= required_collateral, error::invalid_state(EUNDERCOLLATERALIZED));
        };

        // Withdraw collateral
        let withdrawn_coins = coin::extract(&mut lending_account.collateral, amount);
        coin::deposit(user_addr, withdrawn_coins);

        // Emit event
        let events = borrow_global_mut<LendingEvents>(@bastion_core);
        event::emit_event(
            &mut events.withdraw_events,
            WithdrawEvent {
                user: user_addr,
                amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Borrow against collateral
    public entry fun borrow<CoinType>(
        user: &signer,
        amount: u64,
        pool_addr: address
    ) acquires LendingAccount, LendingPool, LendingEvents {
        let user_addr = signer::address_of(user);
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(exists<LendingAccount<CoinType>>(user_addr), error::not_found(ENOT_INITIALIZED));

        let lending_account = borrow_global_mut<LendingAccount<CoinType>>(user_addr);
        let collateral_value = coin::value(&lending_account.collateral);
        
        let pool = borrow_global_mut<LendingPool<CoinType>>(pool_addr);
        
        // Calculate required collateral
        let total_loan = lending_account.loan_amount + amount;
        let required_collateral = (total_loan * pool.min_collateral_ratio) / 10000;
        assert!(collateral_value >= required_collateral, error::invalid_state(EINSUFFICIENT_COLLATERAL));

        // Check available liquidity
        let available = coin::value(&pool.available_liquidity);
        assert!(available >= amount, error::resource_exhausted(EINVALID_AMOUNT));

        // Update loan amount
        lending_account.loan_amount = total_loan;
        lending_account.last_update = timestamp::now_seconds();

        // Withdraw from pool and deposit to user
        let loan_coins = coin::extract(&mut pool.available_liquidity, amount);
        coin::deposit(user_addr, loan_coins);
        pool.total_loans = pool.total_loans + amount;

        // Emit event
        let events = borrow_global_mut<LendingEvents>(@bastion_core);
        event::emit_event(
            &mut events.borrow_events,
            BorrowEvent {
                user: user_addr,
                amount,
                collateral_amount: collateral_value,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Repay loan
    public entry fun repay<CoinType>(
        user: &signer,
        amount: u64,
        pool_addr: address
    ) acquires LendingAccount, LendingPool, LendingEvents {
        let user_addr = signer::address_of(user);
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(exists<LendingAccount<CoinType>>(user_addr), error::not_found(ENOT_INITIALIZED));

        let lending_account = borrow_global_mut<LendingAccount<CoinType>>(user_addr);
        assert!(lending_account.loan_amount > 0, error::not_found(ELOAN_NOT_FOUND));

        // Calculate repayment amount (loan + interest)
        let total_debt = lending_account.loan_amount + lending_account.interest_accrued;
        let repay_amount = if (amount >= total_debt) { total_debt } else { amount };

        // Withdraw repayment from user
        let repay_coins = coin::withdraw<CoinType>(user, repay_amount);
        
        let pool = borrow_global_mut<LendingPool<CoinType>>(pool_addr);
        coin::merge(&mut pool.available_liquidity, repay_coins);

        // Update loan state
        lending_account.loan_amount = if (repay_amount >= total_debt) { 0 } else { total_debt - repay_amount };
        lending_account.interest_accrued = 0;
        lending_account.last_update = timestamp::now_seconds();
        pool.total_loans = pool.total_loans - repay_amount;

        // Emit event
        let events = borrow_global_mut<LendingEvents>(@bastion_core);
        event::emit_event(
            &mut events.repay_events,
            RepayEvent {
                user: user_addr,
                amount: repay_amount,
                interest: lending_account.interest_accrued,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Create a loan request
    public entry fun create_loan_request<CoinType>(
        borrower: &signer,
        amount: u64,
        interest_rate: u64,
        duration: u64,
        collateral_amount: u64,
        registry_addr: address
    ) acquires LendingAccount, LendingEvents, LoanRequestRegistry {
        let borrower_addr = signer::address_of(borrower);
        assert!(amount > 0, error::invalid_argument(EINVALID_AMOUNT));
        assert!(collateral_amount > 0, error::invalid_argument(EINSUFFICIENT_COLLATERAL));
        assert!(duration > 0, error::invalid_argument(EINVALID_AMOUNT));

        // Ensure borrower has lending account with sufficient collateral
        assert!(exists<LendingAccount<CoinType>>(borrower_addr), error::not_found(ENOT_INITIALIZED));
        let lending_account = borrow_global<LendingAccount<CoinType>>(borrower_addr);
        let available_collateral = coin::value(&lending_account.collateral);
        assert!(available_collateral >= collateral_amount, error::invalid_argument(EINSUFFICIENT_COLLATERAL));

        // Get next request ID from registry
        let registry = borrow_global_mut<LoanRequestRegistry>(registry_addr);
        let request_id = registry.next_request_id;
        registry.next_request_id = request_id + 1;
        registry.total_requests = registry.total_requests + 1;

        // Create loan request
        let request = LoanRequest {
            id: request_id,
            borrower: borrower_addr,
            amount,
            interest_rate,
            duration,
            collateral_amount,
            created_at: timestamp::now_seconds(),
            fulfilled: false,
            fulfiller: @0x0,
        };
        move_to(borrower, request);

        // Emit event
        let events = borrow_global_mut<LendingEvents>(registry_addr);
        event::emit_event(
            &mut events.loan_request_created_events,
            LoanRequestCreatedEvent {
                request_id,
                borrower: borrower_addr,
                amount,
                interest_rate,
                duration,
                collateral_amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Fulfill a loan request
    public entry fun fulfill_loan<CoinType>(
        fulfiller: &signer,
        borrower_addr: address,
        registry_addr: address
    ) acquires LoanRequest, LendingAccount, LendingEvents {
        let fulfiller_addr = signer::address_of(fulfiller);
        
        // Verify loan request exists and is not fulfilled
        assert!(exists<LoanRequest>(borrower_addr), error::not_found(ELOAN_REQUEST_NOT_FOUND));
        let loan_request = borrow_global_mut<LoanRequest>(borrower_addr);
        assert!(!loan_request.fulfilled, error::invalid_state(ELOAN_ALREADY_FULFILLED));

        let amount = loan_request.amount;
        let request_id = loan_request.id;

        // Mark as fulfilled
        loan_request.fulfilled = true;
        loan_request.fulfiller = fulfiller_addr;

        // Transfer loan amount from fulfiller to borrower
        let loan_coins = coin::withdraw<CoinType>(fulfiller, amount);
        coin::deposit(borrower_addr, loan_coins);

        // Update borrower's loan amount
        let lending_account = borrow_global_mut<LendingAccount<CoinType>>(borrower_addr);
        lending_account.loan_amount = lending_account.loan_amount + amount;
        lending_account.last_update = timestamp::now_seconds();

        // Emit event
        let events = borrow_global_mut<LendingEvents>(registry_addr);
        event::emit_event(
            &mut events.loan_fulfilled_events,
            LoanFulfilledEvent {
                request_id,
                borrower: borrower_addr,
                fulfiller: fulfiller_addr,
                amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Liquidate an undercollateralized position
    public entry fun liquidate<CoinType>(
        liquidator: &signer,
        user_addr: address,
        pool_addr: address
    ) acquires LendingAccount, LendingPool, LendingEvents {
        let liquidator_addr = signer::address_of(liquidator);
        
        assert!(exists<LendingAccount<CoinType>>(user_addr), error::not_found(ENOT_INITIALIZED));
        
        let lending_account = borrow_global_mut<LendingAccount<CoinType>>(user_addr);
        let collateral_value = coin::value(&lending_account.collateral);
        let loan_amount = lending_account.loan_amount + lending_account.interest_accrued;
        
        // Check if position is undercollateralized
        let pool = borrow_global<LendingPool<CoinType>>(pool_addr);
        let required_collateral = (loan_amount * pool.min_collateral_ratio) / BASIS_POINTS;
        assert!(collateral_value < required_collateral, error::invalid_state(ENOT_LIQUIDATABLE));

        // Calculate liquidation amounts
        let collateral_to_seize = collateral_value;
        let debt_to_repay = loan_amount;

        // Liquidator pays off the debt
        let repay_coins = coin::withdraw<CoinType>(liquidator, debt_to_repay);
        let pool_mut = borrow_global_mut<LendingPool<CoinType>>(pool_addr);
        coin::merge(&mut pool_mut.available_liquidity, repay_coins);
        pool_mut.total_loans = pool_mut.total_loans - debt_to_repay;

        // Transfer collateral to liquidator
        let seized_collateral = coin::extract_all(&mut lending_account.collateral);
        coin::deposit(liquidator_addr, seized_collateral);

        // Reset loan account
        lending_account.loan_amount = 0;
        lending_account.interest_accrued = 0;
        lending_account.last_update = timestamp::now_seconds();

        // Note: LiquidationRecord with dispute window stored at liquidator's address
        // for simplicity. In production, would use a global registry or resource account.
        // Dispute window ends at: timestamp::now_seconds() + DISPUTE_WINDOW_SECONDS

        // Emit event
        let events = borrow_global_mut<LendingEvents>(pool_addr);
        event::emit_event(
            &mut events.liquidation_events,
            LiquidationEvent {
                user: user_addr,
                liquidator: liquidator_addr,
                collateral_seized: collateral_to_seize,
                debt_repaid: debt_to_repay,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /// Get collateral amount for a user
    public fun get_collateral<CoinType>(user_addr: address): u64 acquires LendingAccount {
        if (!exists<LendingAccount<CoinType>>(user_addr)) {
            return 0
        };
        coin::value(&borrow_global<LendingAccount<CoinType>>(user_addr).collateral)
    }

    /// Get loan amount for a user
    public fun get_loan_amount<CoinType>(user_addr: address): u64 acquires LendingAccount {
        if (!exists<LendingAccount<CoinType>>(user_addr)) {
            return 0
        };
        borrow_global<LendingAccount<CoinType>>(user_addr).loan_amount
    }

    /// Check if user has collateral capability
    public fun has_collateral_capability<CoinType>(user_addr: address): bool acquires LendingAccount {
        if (!exists<LendingAccount<CoinType>>(user_addr)) {
            return false
        };
        borrow_global<LendingAccount<CoinType>>(user_addr).collateral_cap.owner == user_addr
    }
}
