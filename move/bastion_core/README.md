# Bastion Core - Move Package

A comprehensive Aptos Move package for the Bastion decentralized lending and trust protocol.

## Overview

Bastion Core provides a complete on-chain infrastructure for peer-to-peer lending with social trust, lending circles, dynamic interest rates, and payment processing.

## Modules

### 1. BastionCore (`bastion_core.move`)

**Purpose**: Core protocol functionality and administrative controls

**Key Features**:
- Protocol initialization and configuration
- Admin capability-based access control
- Protocol pause/unpause mechanism
- Total Value Locked (TVL) tracking
- Version management

**Key Structs**:
- `ProtocolConfig`: Main protocol configuration and state
- `AdminCap`: Administrative capability for access control
- `ProtocolEvents`: Event handles for protocol lifecycle events

**Events**:
- `ProtocolInitializedEvent`: Emitted when protocol is initialized
- `AdminChangedEvent`: Emitted when admin is transferred
- `ProtocolPausedEvent`: Emitted when protocol pause state changes
- `ConfigUpdatedEvent`: Emitted when configuration is updated

**Access Control**:
- Admin-only functions require `AdminCap` capability
- Protocol can be paused for emergency situations
- Admin transfer supported for governance evolution

### 2. BastionLending (`bastion_lending.move`)

**Purpose**: Core lending and borrowing functionality

**Key Features**:
- Collateral deposit and withdrawal
- Loan origination against collateral
- Collateralization ratio enforcement
- Loan repayment with interest
- Liquidation support (framework)

**Key Structs**:
- `LendingAccount<CoinType>`: User's lending position (collateral + loan)
- `LendingPool<CoinType>`: Protocol liquidity pool
- `CollateralCap`: Capability for collateral ownership

**Events**:
- `DepositEvent`: Collateral deposited
- `WithdrawEvent`: Collateral withdrawn
- `BorrowEvent`: Loan borrowed
- `RepayEvent`: Loan repaid
- `LiquidationEvent`: Position liquidated

**Safety Features**:
- Minimum collateralization ratio enforcement
- Over-collateralization required for borrowing
- Real-time collateral ratio checks on withdrawals
- Escrow-based collateral management

### 3. BastionCircles (`bastion_circles.move`)

**Purpose**: Lending circles and group management

**Key Features**:
- Create lending circles with configurable parameters
- Member management (add/remove)
- Circle ownership with capabilities
- Member contribution tracking
- Active/inactive circle states

**Key Structs**:
- `Circle`: Lending circle with members and rules
- `CircleOwnerCap`: Ownership capability for circle management
- `CircleRegistry`: Global registry for circle IDs
- `CircleMemberships`: User's circle membership tracking

**Events**:
- `CircleCreatedEvent`: Circle created
- `MemberAddedEvent`: Member added to circle
- `MemberRemovedEvent`: Member removed from circle
- `ContributionEvent`: Contribution made to circle pool

**Circle Management**:
- Maximum member limits
- Minimum contribution requirements
- Owner-only member management
- Multi-circle membership support

### 4. TrustManager (`trust_manager.move`)

**Purpose**: Trust scoring and reputation system

**Key Features**:
- Dynamic trust score calculation (0-1000 scale)
- Transaction history tracking
- Peer endorsements
- Credit limit calculation based on trust
- Reputation levels (0-5 stars)

**Key Structs**:
- `TrustScore`: User's trust score and history
- `TrustRegistry`: Global trust statistics
- `Endorsement`: Peer endorsement records

**Events**:
- `ScoreUpdatedEvent`: Trust score changed
- `EndorsementEvent`: User endorsed another user
- `ReputationChangedEvent`: Reputation level changed

**Trust Mechanics**:
- Initial score: 500 (50% trust)
- Successful transactions: +5 points
- Failed transactions: -20 points
- Endorsements: +10 points per endorsement
- Max score: 1000, Min score: 0
- Credit limit proportional to trust score

### 5. InterestGovernance (`interest_governance.move`)

**Purpose**: Dynamic interest rate calculation and governance

**Key Features**:
- Utilization-based interest rate model
- Governance proposals for rate changes
- Multi-parameter rate model (base, slopes, optimal utilization)
- Interest accrual calculations
- Admin controls with governance support

**Key Structs**:
- `InterestRateModel`: Rate model parameters
- `RateProposal`: Governance proposal for rate changes
- `GovernanceRegistry`: Governance configuration

**Events**:
- `RateUpdatedEvent`: Interest rate updated
- `ProposalCreatedEvent`: Governance proposal created
- `VoteCastEvent`: Vote cast on proposal
- `ProposalExecutedEvent`: Proposal executed

**Rate Model**:
- Base rate: Minimum interest rate
- Optimal utilization: Target utilization percentage
- Slope 1: Interest increase below optimal
- Slope 2: Interest increase above optimal (steeper)
- Dynamic calculation based on pool utilization

### 6. Payments (`payments.move`)

**Purpose**: Payment processing and settlement

**Key Features**:
- Payment creation and processing
- Escrow-based payment holding
- Payment status tracking
- Payment statistics
- Multi-party payment support (framework)

**Key Structs**:
- `Payment`: Payment record with status
- `PaymentAccount<CoinType>`: User's payment account
- `PaymentRegistry`: Global payment tracking
- `PaymentSchedule`: Recurring payment framework

**Events**:
- `PaymentCreatedEvent`: Payment created
- `PaymentCompletedEvent`: Payment completed
- `PaymentFailedEvent`: Payment failed
- `PaymentCancelledEvent`: Payment cancelled

**Payment Flow**:
1. Payer creates payment → funds moved to escrow
2. Payment held in escrow with PENDING status
3. Payee completes payment → funds transferred
4. Or payer cancels → funds returned from escrow

## Storage Layout

### Resource Accounts

**Protocol Admin Account** (single instance):
- `ProtocolConfig`: Protocol-wide configuration
- `AdminCap`: Administrative capability
- `ProtocolEvents`: Protocol event handles
- `CircleRegistry`: Global circle registry
- `TrustRegistry`: Global trust statistics
- `InterestRateModel`: Interest rate parameters
- `GovernanceRegistry`: Governance configuration
- `PaymentRegistry`: Payment tracking

**User Accounts** (per user):
- `LendingAccount<CoinType>`: Lending position
- `TrustScore`: Trust score and history
- `CircleMemberships`: Circle memberships
- `PaymentAccount<CoinType>`: Payment account
- `Circle`: If user created a circle
- `CircleOwnerCap`: If user owns a circle
- `PaymentSchedule`: If user has recurring payments

### Type Parameters

Most structs are generic over `CoinType` to support multiple currencies:
- `LendingAccount<CoinType>`
- `LendingPool<CoinType>`
- `PaymentAccount<CoinType>`

This enables multi-currency lending and payments (e.g., APT, USDC, USDT).

## Protocol Invariants

### Safety Invariants

1. **Collateralization**: 
   - Active loans MUST maintain minimum collateral ratio
   - Withdrawals MUST NOT violate collateral requirements
   - Collateral >= (Loan Amount × Min Collateral Ratio)

2. **Accounting**:
   - Total collateral in pool = Sum of all user collateral
   - Total loans issued ≤ Available liquidity + Reserves
   - Escrow balance = Sum of pending payments

3. **Access Control**:
   - Only AdminCap holders can call admin functions
   - Only CircleOwnerCap holders can manage their circles
   - Only CollateralCap holders can manage their collateral

4. **Trust Scores**:
   - Trust scores bounded: 0 ≤ score ≤ 1000
   - Scores only modified through defined rules
   - Endorsements unique per endorser-endorsed pair

5. **Payment Integrity**:
   - Funds locked in escrow during PENDING status
   - Completed payments immutable
   - Cancelled payments return funds to payer

### Liveness Properties

1. **Protocol Operations**:
   - When not paused, all user operations available
   - Admin can unpause if paused
   - No permanent locks on user funds

2. **Lending Operations**:
   - Users can always repay loans (no blocking)
   - Well-collateralized positions can always withdraw excess
   - Liquidations possible for undercollateralized positions

3. **Circle Operations**:
   - Circle owner can always manage members
   - Members can leave circles (through owner removal)
   - Inactive circles don't block operations

## Migration Path

### Version 1 to Version 2 (Example)

**Scenario**: Adding new field to `ProtocolConfig`

```move
// V1
struct ProtocolConfig has key {
    admin: address,
    version: u64,
    paused: bool,
    total_value_locked: u64,
}

// V2
struct ProtocolConfig has key {
    admin: address,
    version: u64,
    paused: bool,
    total_value_locked: u64,
    new_field: u64,  // New field added
}
```

**Migration Steps**:

1. **Deploy New Code**: Deploy updated module with `upgrade_policy = "compatible"`
2. **Migration Function**: Add migration function to initialize new field
3. **Version Check**: Update version number in `ProtocolConfig`
4. **Lazy Migration**: Or use lazy migration where old struct is read and new struct is written

**Example Migration Function**:

```move
public entry fun migrate_to_v2(admin: &signer) acquires ProtocolConfig, AdminCap {
    assert_admin(signer::address_of(admin));
    let config = borrow_global_mut<ProtocolConfig>(signer::address_of(admin));
    // Initialize new field with default value
    // config.new_field = 0;  // Would need to use workaround for struct modification
    config.version = 2;
}
```

### Breaking Changes

For breaking changes that cannot use struct compatibility:

1. **Deploy Separate Module**: Deploy new module (e.g., `bastion_core_v2`)
2. **Data Migration Script**: Create off-chain script to read V1 data
3. **Recreate Resources**: Users recreate resources in V2
4. **Deprecation Period**: Run both versions during transition
5. **Sunsetting V1**: Disable V1 after migration complete

### Upgrade Strategies

**Compatible Upgrades** (recommended):
- Add new functions
- Add new resources
- Extend structs with new fields (with care)
- Add new events

**Incompatible Changes** (require full migration):
- Remove fields from structs
- Change field types
- Remove functions that are dependencies
- Change function signatures

## Building and Testing

### Prerequisites

```bash
# Install Aptos CLI
curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3
```

### Build

```bash
cd move/bastion_core
aptos move compile
```

### Test

```bash
cd move/bastion_core
aptos move test
```

### Deploy

```bash
# Initialize account if needed
aptos init

# Compile and publish
aptos move publish --named-addresses bastion_core=default
```

## Security Considerations

### Access Control

1. **Admin Functions**: Protected by `AdminCap` capability
2. **User Resources**: Owned and controlled by users
3. **Circle Management**: Protected by `CircleOwnerCap`
4. **Collateral**: Protected by `CollateralCap`

### Economic Security

1. **Over-collateralization**: Required for all loans
2. **Interest Accrual**: Automatic and transparent
3. **Liquidation**: Protection against bad debt
4. **Rate Limits**: Can be added via governance

### Smart Contract Security

1. **Integer Overflow**: Use checked arithmetic
2. **Reentrancy**: Not applicable (Move prevents)
3. **Access Control**: Capability-based security
4. **Resource Safety**: Move's resource semantics

### Audit Recommendations

- [ ] External security audit before mainnet
- [ ] Economic model validation
- [ ] Stress testing with adversarial scenarios
- [ ] Formal verification of critical invariants

## Gas Optimization

### Efficient Patterns

1. **Batch Operations**: Group multiple operations when possible
2. **Lazy Updates**: Update state only when necessary
3. **Event Efficiency**: Emit events only for significant state changes
4. **Vector Operations**: Minimize vector iteration

### Cost Estimates

- Protocol initialization: ~500-1000 gas units
- Deposit collateral: ~200-400 gas units
- Borrow: ~300-500 gas units
- Repay: ~300-500 gas units
- Create circle: ~400-600 gas units
- Create payment: ~300-500 gas units

## Future Enhancements

### Planned Features

1. **Flash Loans**: Uncollateralized loans within single transaction
2. **Cross-Circle Lending**: Lending between circles with negotiated rates
3. **NFT Collateral**: Support NFTs as collateral
4. **Yield Farming**: Interest distribution to liquidity providers
5. **Governance Token**: Protocol governance token
6. **Insurance Fund**: Protocol insurance against defaults

### Integration Points

1. **Oracles**: Price feeds for multi-asset collateral
2. **DeFi Protocols**: Integration with other DeFi protocols
3. **Analytics**: On-chain analytics and reporting
4. **Automation**: Automated liquidations and payments

## Support and Resources

- **Documentation**: [Aptos Move Documentation](https://aptos.dev/move/move-on-aptos)
- **Move Book**: [Move Book](https://move-book.com/)
- **Security**: See [SECURITY.md](../../SECURITY.md)
- **Contributing**: See [CONTRIBUTING.md](../../docs/CONTRIBUTING.md)

## License

Apache License 2.0 - See [LICENSE](../../LICENSE)
