# Security

## Threats Considered
- share inflation / donation dynamics
- unauthorized config updates
- reentrancy on vault paths
- stale config replay
- valuation manipulation risks

## Mitigations
- `onlyPoolManager` in hook entrypoints
- `onlyOwner` on policy updates
- `onlyHook` on vault revenue capture
- `ReentrancyGuard` in vault mutations
- policy nonce monotonicity check
- conservative ZERO_VALUE default

## Residual Risks
- governance/admin misconfiguration
- economic griefing by adverse market timing
- mock market assumptions are non-production
