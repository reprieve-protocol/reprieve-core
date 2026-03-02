# reprieve-chainlink-api-guard-v1

Profile workflow for `CHAINLINK_API_GUARD_V1`.

## Current status

- HTTP primary trigger + cron fallback both run full V1 orchestration flow.
- V1 risk engine computes decision from adapter snapshots + Chainlink API path/fallback.
- Planner enforces single-mode rescue (`TOP_UP` or `REPAY`) and builds `executeRescue` plan.
- Source-chain execution is supported (`executeRescue`) with tx hash + optional CCIP message id capture.
- EVM-log reconciliation maps settlement lifecycle:
  - `CrossChainInitiated` -> `DISPATCHED`
  - `CrossChainCompleted` -> `DELIVERED_SUCCESS`
  - `CrossChainDestinationFailed` -> `DELIVERED_FAILED`
  - `RescueCompleted` / `RescueFailed` -> same-chain terminal tracking

## HTTP payload knobs

- `user` (`0x...`) optional, defaults to `monitoring.defaultUser`
- `runMode` = `execute | monitor_only | dry_run` (HTTP default: `execute`, cron default: `monitor_only`)
- `rescueMode` = `TOP_UP | REPAY` (default from config)
- `executionId` (`bytes32`) optional deterministic override
- `pendingExecId` (`bytes32`) optional pending cross-chain guard
- `sourceAdapter` / `targetAdapter` optional planning hints
- `forceCrossChain` boolean optional
- `targetChainSelector` optional cross-chain override
- `targetCollateralAsset` / `targetDebtAsset` optional cross-chain asset hints
- `transferAmount` optional action amount override
- `maxFeeWei` optional max native fee override
- `deadlineSeconds` optional deadline horizon override

## Local checks

- `bun run build`
- `bun test lib/risk-v1.test.ts`
- `cre workflow simulate ./reprieve-chainlink-api-guard-v1 --target=staging-settings`
