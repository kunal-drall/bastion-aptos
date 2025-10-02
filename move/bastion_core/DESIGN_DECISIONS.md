# Design Decisions: BastionLending & BastionCircles

## Architectural Decisions

### 1. Loan Request Model

**Decision**: Implement a two-phase loan process (request → fulfill) instead of direct matching.

**Rationale**:
- **Flexibility**: Borrowers can specify their terms (amount, interest rate, duration)
- **Transparency**: All loan requests are visible on-chain
- **Market-driven**: Lenders can choose which requests to fulfill
- **Asynchronous**: No need for both parties to be online simultaneously

**Alternative Considered**: Direct peer-to-peer matching
- **Rejected because**: Would require complex matching logic and limit flexibility

### 2. Storage Pattern for Loan Requests

**Decision**: Store LoanRequest at borrower's address.

**Rationale**:
- **Simplicity**: Each borrower can have one active loan request at a time
- **Gas efficiency**: No need for complex indexing structures
- **Access pattern**: Easy to check if borrower has pending request
- **Resource safety**: Move's resource model ensures no duplication

**Trade-off**: 
- Borrowers limited to one request at a time
- Acceptable for initial implementation, can be extended later with request IDs

### 3. Stake-to-Loan Ratio: 200%

**Decision**: Require 200% stake-to-loan ratio in circle bidding.

**Rationale**:
- **Risk mitigation**: 2x collateralization ensures skin in the game
- **Default protection**: Circle has 2x coverage if borrower defaults
- **Conservative**: Better to start conservative, can adjust via governance
- **Simple calculation**: Easy to verify and understand

**Calculation**: `required_stake = (loan_amount * 200) / 100`

**Alternative Considered**: Dynamic ratios based on trust scores
- **Rejected for v1**: Adds complexity, can be added in future iterations

### 4. Bidding Period: 7 Days

**Decision**: Fixed 7-day bidding periods for circle loan rounds.

**Rationale**:
- **Fair access**: Gives all members reasonable time to prepare bids
- **Market discovery**: Allows price discovery through competitive bidding
- **Not too long**: Prevents capital from being locked up indefinitely
- **Standard period**: Aligns with common governance voting periods

**Alternative Considered**: Variable periods set by owner
- **Rejected**: Fixed period ensures predictability and fairness

### 5. Dispute Window: 24 Hours

**Decision**: 24-hour dispute window for liquidations.

**Rationale**:
- **User protection**: Gives users time to dispute erroneous liquidations
- **Balance**: Long enough to notice, short enough to not lock capital
- **Offline tolerance**: Users may not be constantly monitoring positions
- **Standard practice**: Aligns with traditional finance clearing periods

**Implementation Note**: 
- Tracked via event timestamps and constant
- Actual dispute resolution mechanism to be implemented in governance module

### 6. Event-Driven Architecture

**Decision**: Emit events for all state changes.

**Rationale**:
- **Off-chain indexing**: Essential for building UIs and analytics
- **Audit trail**: Complete history of protocol operations
- **Monitoring**: Enables real-time monitoring and alerting
- **Composability**: Other protocols can react to events

**Events Implemented**:
- Lending: LoanRequestCreated, LoanFulfilled, Liquidation
- Circles: Stake, BidSubmitted, FundsDistributed

### 7. Capability-Based Access Control

**Decision**: Use Move capabilities (CircleOwnerCap, CollateralCap) for access control.

**Rationale**:
- **Move native**: Leverages Move's resource model
- **Type safety**: Compiler-enforced access control
- **Transferable**: Capabilities can be transferred if needed
- **Explicit**: Clear ownership and permission model

**Alternative Considered**: Simple address checks
- **Rejected**: Less secure and less flexible

### 8. BiddingRound Storage Location

**Decision**: Store BiddingRound at circle owner's address.

**Rationale**:
- **Logical grouping**: Owned by circle owner who controls bidding
- **Single source**: One active round per circle
- **Access control**: Owner can start/end rounds
- **Simple lookup**: Easy to find round for a given circle

**Implementation Challenge**: 
- Can't use test functions in production
- Solution: Owner must explicitly call `start_bidding_round`

### 9. Liquidation Model

**Decision**: Anyone can liquidate undercollateralized positions (permissionless).

**Rationale**:
- **Protocol safety**: Ensures bad debt is quickly addressed
- **Economic incentive**: Liquidators profit from liquidations
- **Decentralization**: No need for privileged liquidators
- **Standard DeFi**: Follows patterns from Aave, Compound, etc.

**Safety Mechanisms**:
- Collateral ratio verification
- Dispute window for protection
- Transparent event emissions

### 10. Pool Management in Circles

**Decision**: Track total pool at circle level, individual stakes separately.

**Rationale**:
- **Efficient checking**: Quick validation of available funds
- **Member tracking**: Separate CircleStake records for stake history
- **Distribution logic**: Easy to reduce pool when distributing
- **Accounting**: Clear separation of concerns

**Invariant**: `circle.total_pool == sum(all_member_stakes)`

## Technical Considerations

### Move-Specific Patterns

#### Resource Management
- Resources (LoanRequest, CircleStake, etc.) stored at user addresses
- Ensures single ownership and prevents duplication
- Move's linear types prevent resource leaks

#### Generic Types
- Functions parameterized with `<CoinType>` for token flexibility
- Allows protocol to work with any Aptos coin type
- Type safety prevents mixing different coin types

#### Vector Operations
- Used for member lists and bid collections
- Linear search acceptable for small collections (max 100 members)
- Could be optimized with table/map structures for larger scales

### Gas Optimization

#### Minimal State Changes
- Events use `drop` ability (no storage cost)
- Borrow mutations rather than move/replace when possible
- Early validation to fail fast

#### Batch Operations
- Future consideration: Allow batch bid submissions
- Future consideration: Batch liquidations

### Scalability Considerations

#### Current Limitations
1. One loan request per borrower
2. Linear search in bid vectors
3. Fixed 100 member limit per circle

#### Future Improvements
1. Multiple concurrent requests via request ID mapping
2. Table-based indexing for large bid collections
3. Configurable circle limits
4. Pagination for member/bid queries

## Security Considerations

### Attack Vectors Addressed

#### 1. Front-Running Protection
- **Issue**: Liquidators could front-run each other
- **Mitigation**: Dispute window provides buffer
- **Future**: Could add liquidation auctions

#### 2. Collateral Manipulation
- **Issue**: Users could try to withdraw collateral before liquidation
- **Mitigation**: Collateral ratio checked on all withdrawals
- **Protection**: Insufficient collateral error prevents withdrawal

#### 3. Bid Spamming
- **Issue**: Members could spam bids to DOS bidding
- **Mitigation**: Gas costs naturally limit spam
- **Future**: Could add bid limits per member

#### 4. Pool Drain
- **Issue**: Owner could distribute all funds unfairly
- **Mitigation**: Only winning bids can be distributed
- **Future**: Multi-sig or governance for distribution

### Validation Strategy

#### Input Validation
- All amounts checked for > 0
- All addresses verified to exist
- All timestamps compared to current time

#### State Validation
- Collateral sufficiency before operations
- Pool sufficiency before distributions
- Ratio requirements before bidding

#### Access Validation
- Capability requirements enforced
- Membership requirements checked
- Owner permissions verified

## Future Enhancements

### Short-term (v2)
1. **Dynamic Interest Rates**: Based on utilization and risk
2. **Partial Fulfillment**: Allow multiple lenders per request
3. **Bid Modification**: Allow members to update bids
4. **Automated Distribution**: Algorithm-based winner selection

### Medium-term (v3)
1. **Multi-collateral**: Support multiple coin types as collateral
2. **Insurance Pool**: Protocol-level insurance for defaults
3. **Credit Scoring**: Integration with trust manager
4. **Flash Loans**: Uncollateralized loans within transaction

### Long-term (v4)
1. **Cross-chain**: Bridge to other chains
2. **NFT Collateral**: Support NFTs as collateral
3. **Synthetic Assets**: Create synthetic positions
4. **Automated Market Making**: AMM for loan matching

## Testing Strategy

### Unit Test Coverage
- All public functions
- All error conditions
- All validation checks
- All event emissions

### Integration Test Scenarios
1. Happy path: Create → fulfill → repay
2. Liquidation path: Undercollateralized → liquidate
3. Circle path: Join → bid → distribute
4. Edge cases: Boundaries, limits, timing

### Invariant Testing
```move
// Example invariants to test
assert!(circle.total_pool >= distribution_amount)
assert!(stake.stake_amount >= bid.amount * 2)
assert!(collateral >= loan * min_ratio / BASIS_POINTS)
```

## Lessons Learned

### Move-Specific Learnings
1. **No dynamic signers**: Can't create signers for other addresses in production
   - Solution: Require users to call functions themselves
   
2. **Resource storage**: Each resource needs explicit storage location
   - Pattern: Store at owner's address for access control
   
3. **Generic constraints**: Need proper type parameters for flexibility
   - Pattern: Use `<phantom CoinType>` for type safety

### Design Learnings
1. **Start simple**: Basic functionality first, optimize later
2. **Event everything**: Crucial for off-chain tooling
3. **Clear ownership**: Capabilities make permissions explicit
4. **Conservative ratios**: Better to be safe initially

## References

- Aptos Move Documentation
- Aave V2 Liquidation Model
- Compound Finance Interest Rates
- MakerDAO Collateral System
- Move Language Specification
