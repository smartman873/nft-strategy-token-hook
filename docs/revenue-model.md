# Revenue Model

## Config Fields
- `enabled`
- `revenueToken`
- `revenueShareBps` (`<= 2000`)
- `acquireThreshold`
- `valuationMode`
- `policyNonce`

## Routing
Captured amount is routed by `FeeRouter`:
- strategy reserve amount
- optional treasury amount

LP fee mechanics remain native to AMM; only hook-captured share is routed here.
