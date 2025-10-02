# Bastion Core Architecture

## Module Dependency Graph

```
bastion_core (Core Protocol)
    ↓
    ├── bastion_lending (Lending Operations)
    ├── bastion_circles (Social Lending)
    ├── trust_manager (Reputation)
    ├── interest_governance (Rate Management)
    └── payments (Payment Processing)
```

## Capability-Based Access Control

### Capabilities Hierarchy

```
AdminCap (bastion_core)
    ├─ Protocol Configuration
    ├─ Pause/Unpause
    └─ Admin Transfer

CircleOwnerCap (bastion_circles)
    ├─ Add Members
    ├─ Remove Members
    └─ Deactivate Circle

CollateralCap (bastion_lending)
    ├─ Deposit Collateral
    ├─ Withdraw Collateral
    └─ Manage Lending Position
```

## Data Flow Diagrams

### Lending Flow

```
User
  │
  ├─→ deposit_collateral()
  │     └─→ LendingAccount.collateral += amount
  │
  ├─→ borrow()
  │     ├─→ Check collateralization ratio
  │     ├─→ Update loan_amount
  │     └─→ Transfer from pool to user
  │
  └─→ repay()
        ├─→ Calculate interest
        ├─→ Transfer from user to pool
        └─→ Update loan_amount
```

### Trust Score Flow

```
User Actions
  │
  ├─→ Successful Transaction
  │     └─→ score += 5
  │
  ├─→ Failed Transaction
  │     └─→ score -= 20
  │
  └─→ Receive Endorsement
        └─→ score += 10

Trust Score → Credit Limit
  credit_limit = base_limit × (score / 1000)
```

### Circle Management Flow

```
Circle Creation
  │
  ├─→ create_circle()
  │     ├─→ Generate unique circle_id
  │     ├─→ Create Circle resource
  │     ├─→ Issue CircleOwnerCap
  │     └─→ Add creator as first member
  │
Circle Operations
  │
  ├─→ add_member()
  │     ├─→ Verify CircleOwnerCap
  │     ├─→ Check max_members
  │     └─→ Update members list
  │
  └─→ remove_member()
        ├─→ Verify CircleOwnerCap
        ├─→ Find member in list
        └─→ Remove from members
```

### Interest Rate Calculation

```
Utilization Rate
  │
  utilization = total_loans / (total_collateral + liquidity)
  │
  ├─→ Below Optimal (< 80%)
  │     rate = base_rate + (utilization × slope_1) / optimal
  │
  └─→ Above Optimal (≥ 80%)
        rate = base_rate + slope_1 + 
               ((utilization - optimal) × slope_2) / (100% - optimal)
```

### Payment Flow

```
Create Payment
  │
  ├─→ create_payment()
  │     ├─→ Withdraw from payer
  │     ├─→ Hold in escrow
  │     ├─→ Create Payment record (PENDING)
  │     └─→ Add to incoming/outgoing lists
  │
Payment Settlement
  │
  ├─→ complete_payment()
  │     ├─→ Verify payee
  │     ├─→ Transfer from escrow to payee
  │     ├─→ Update statistics
  │     └─→ Remove from lists
  │
  └─→ cancel_payment()
        ├─→ Verify payer
        ├─→ Return from escrow to payer
        └─→ Remove from lists
```

## Storage Architecture

### Global Singletons (Admin Account)

```
Admin Account (@bastion_core)
  │
  ├─→ ProtocolConfig
  │     ├─ admin: address
  │     ├─ version: u64
  │     ├─ paused: bool
  │     └─ total_value_locked: u64
  │
  ├─→ AdminCap
  │     └─ owner: address
  │
  ├─→ CircleRegistry
  │     ├─ next_circle_id: u64
  │     └─ total_circles: u64
  │
  ├─→ TrustRegistry
  │     ├─ total_users: u64
  │     └─ average_score: u64
  │
  ├─→ InterestRateModel
  │     ├─ base_rate: u64
  │     ├─ optimal_utilization: u64
  │     ├─ slope_1: u64
  │     └─ slope_2: u64
  │
  ├─→ GovernanceRegistry
  │     ├─ next_proposal_id: u64
  │     ├─ quorum: u64
  │     └─ voting_period: u64
  │
  ├─→ PaymentRegistry
  │     ├─ next_payment_id: u64
  │     ├─ total_payments: u64
  │     └─ total_volume: u64
  │
  └─→ Event Handles (per module)
        ├─ ProtocolEvents
        ├─ LendingEvents
        ├─ CircleEvents
        ├─ TrustEvents
        ├─ InterestEvents
        └─ PaymentEvents
```

### User Resources

```
User Account
  │
  ├─→ LendingAccount<CoinType>
  │     ├─ collateral: Coin<CoinType>
  │     ├─ loan_amount: u64
  │     ├─ interest_accrued: u64
  │     ├─ last_update: u64
  │     └─ collateral_cap: CollateralCap
  │
  ├─→ TrustScore
  │     ├─ score: u64 (0-1000)
  │     ├─ successful_transactions: u64
  │     ├─ failed_transactions: u64
  │     ├─ total_borrowed: u64
  │     ├─ total_repaid_on_time: u64
  │     ├─ endorsers: vector<address>
  │     └─ last_updated: u64
  │
  ├─→ CircleMemberships
  │     └─ circle_ids: vector<u64>
  │
  ├─→ PaymentAccount<CoinType>
  │     ├─ incoming_payments: vector<Payment>
  │     ├─ outgoing_payments: vector<Payment>
  │     ├─ escrow_balance: Coin<CoinType>
  │     ├─ total_sent: u64
  │     └─ total_received: u64
  │
  └─→ Circle (if owner)
        ├─ id: u64
        ├─ owner: address
        ├─ name: vector<u8>
        ├─ members: vector<address>
        ├─ max_members: u64
        ├─ total_pool: u64
        ├─ min_contribution: u64
        ├─ created_at: u64
        └─ active: bool
```

## Security Model

### Access Control Matrix

| Resource              | Operation        | Required Capability | Additional Checks |
|-----------------------|------------------|---------------------|-------------------|
| ProtocolConfig        | update           | AdminCap            | Owner match       |
| ProtocolConfig        | pause/unpause    | AdminCap            | Owner match       |
| LendingAccount        | deposit          | -                   | User owns account |
| LendingAccount        | withdraw         | CollateralCap       | Collateral ratio  |
| LendingAccount        | borrow           | CollateralCap       | Collateral ratio  |
| LendingAccount        | repay            | -                   | User owns account |
| Circle                | add_member       | CircleOwnerCap      | Circle active     |
| Circle                | remove_member    | CircleOwnerCap      | Not removing self |
| Circle                | deactivate       | CircleOwnerCap      | Owner match       |
| TrustScore            | initialize       | -                   | Not exists        |
| TrustScore            | endorse          | -                   | Not self-endorse  |
| TrustScore            | update           | System              | Internal only     |
| InterestRateModel     | update_rate      | AdminCap            | Rate limits       |
| Payment               | create           | -                   | Sufficient funds  |
| Payment               | complete         | -                   | Is payee          |
| Payment               | cancel           | -                   | Is payer          |

### Invariant Checks

#### Lending Invariants

```move
// Checked at withdrawal time
assert!(remaining_collateral >= (loan_amount × min_collateral_ratio / 10000))

// Checked at borrow time
assert!(collateral >= (new_loan_amount × min_collateral_ratio / 10000))

// Always maintained
assert!(total_loans ≤ available_liquidity + reserves)
```

#### Trust Score Invariants

```move
// Always maintained
assert!(trust_score >= MIN_TRUST_SCORE && trust_score <= MAX_TRUST_SCORE)
assert!(MIN_TRUST_SCORE == 0 && MAX_TRUST_SCORE == 1000)

// Endorsement uniqueness
assert!(!vector::contains(&endorsers, &new_endorser))
```

#### Circle Invariants

```move
// At member addition
assert!(member_count < max_members)
assert!(!vector::contains(&members, &new_member))

// Owner always in members
assert!(vector::contains(&members, &owner))
```

#### Payment Invariants

```move
// Escrow balance equals pending payments
assert!(escrow_balance == sum(outgoing_payments.amount))

// Payment state transitions
PENDING → COMPLETED | FAILED | CANCELLED
// No transitions from COMPLETED, FAILED, or CANCELLED
```

## Event Architecture

### Event Categories

#### Protocol Events
- `ProtocolInitializedEvent`
- `AdminChangedEvent`
- `ProtocolPausedEvent`
- `ConfigUpdatedEvent`

#### Lending Events
- `DepositEvent`
- `WithdrawEvent`
- `BorrowEvent`
- `RepayEvent`
- `LiquidationEvent`

#### Circle Events
- `CircleCreatedEvent`
- `MemberAddedEvent`
- `MemberRemovedEvent`
- `ContributionEvent`

#### Trust Events
- `ScoreUpdatedEvent`
- `EndorsementEvent`
- `ReputationChangedEvent`

#### Interest Events
- `RateUpdatedEvent`
- `ProposalCreatedEvent`
- `VoteCastEvent`
- `ProposalExecutedEvent`

#### Payment Events
- `PaymentCreatedEvent`
- `PaymentCompletedEvent`
- `PaymentFailedEvent`
- `PaymentCancelledEvent`

### Event Usage Patterns

Events are emitted for:
1. **State Changes**: All significant state modifications
2. **Access Control**: Admin actions and capability usage
3. **Economic Activity**: All financial transactions
4. **Social Actions**: Trust endorsements, circle membership changes
5. **Governance**: Proposal creation and voting

Events enable:
- Off-chain indexing and analytics
- Real-time monitoring and alerting
- Audit trails for compliance
- User activity feeds
- Protocol metrics dashboards

## Upgrade Path

### Compatible Upgrades

```
V1 → V2: Add new module
  ├─→ Deploy new module
  ├─→ No data migration needed
  └─→ Users opt-in to new features

V1 → V2: Add struct field
  ├─→ Deploy updated module
  ├─→ Run migration function
  └─→ Old structs remain compatible
```

### Breaking Changes

```
V1 → V2: Remove struct field
  ├─→ Deploy new module (different address)
  ├─→ Create migration script
  ├─→ Users migrate manually
  └─→ Deprecate V1 after transition period
```

## Gas Optimization Strategies

### Batch Operations
- Group related state updates
- Minimize storage writes
- Use single transaction for related ops

### Lazy Evaluation
- Defer calculations until needed
- Cache computed values when appropriate
- Update indices incrementally

### Efficient Data Structures
- Use vectors for small collections
- Consider table for large mappings
- Minimize nested struct depth

### Event Optimization
- Emit events only for significant changes
- Use compact event structures
- Batch related events when possible

## Integration Points

### External Systems

```
Bastion Core
  │
  ├─→ Price Oracles
  │     └─ Multi-asset collateral valuation
  │
  ├─→ Other DeFi Protocols
  │     ├─ Yield aggregators
  │     └─ Liquidity sources
  │
  ├─→ Analytics Services
  │     ├─ Event indexers
  │     └─ Dashboard data
  │
  └─→ Automation Services
        ├─ Liquidation bots
        ├─ Interest rate updates
        └─ Payment processing
```

## Testing Strategy

### Unit Tests
- Test each function in isolation
- Verify error conditions
- Check edge cases

### Integration Tests
- Test module interactions
- Verify end-to-end flows
- Test complex scenarios

### Invariant Tests
- Verify protocol invariants
- Test under adversarial conditions
- Stress test with large values

### Gas Tests
- Measure gas consumption
- Optimize hot paths
- Compare alternative implementations

## Monitoring and Observability

### Key Metrics

**Protocol Health**
- Total Value Locked (TVL)
- Collateralization ratio distribution
- Interest rate trends
- Protocol utilization

**User Activity**
- Active users
- Transaction volume
- Payment success rate
- Trust score distribution

**Circle Metrics**
- Active circles
- Average members per circle
- Circle contribution rates
- Circle success metrics

**Risk Metrics**
- Undercollateralized positions
- Default rate
- Liquidation volume
- Trust score decay

### Alerting

**Critical Alerts**
- Protocol paused
- Large collateral withdrawal
- Undercollateralized positions
- Governance proposals

**Warning Alerts**
- High utilization rate
- Trust score drops
- Payment failures
- Circle deactivations
