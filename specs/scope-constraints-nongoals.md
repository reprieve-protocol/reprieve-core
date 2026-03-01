# Reprieve Sprint Scope Clarification

## Goal
Build a demo-ready liquidation protection system (not a full portfolio manager) that can detect risk across Aave/Compound/Morpho-style positions and execute rescue actions with Chainlink CRE, Data Feeds, and CCIP.

## Sprint Scope (Now)
- Dashboard that auto-discovers positions from Aave-like, Compound-like, and Morpho-like protocol instances, and shows per-position + aggregate health factor.
- Setup flow:
  - User picks rescue strategy (1 strategy = 1 CRE workflow per user).
  - User sets threshold, priority order, and budget caps.
  - User pays LINK for CRE deployment/operation.
  - User grants ERC20 approvals for position tokens (demo can be pre-approved).
- Per-user CRE workflow, bot-triggered:
  - Detect positions.
  - Read Chainlink Data Feed prices.
  - Read off-chain quant signals.
  - Compute aggregate risk/health.
  - Trigger rescue when threshold breached.
  - Write on-chain rescue log.
- Rescue execution logic:
  - Same-chain-first source selection by priority queue.
  - Fall-through to next source if insufficient collateral.
  - Cross-chain escalation via CCIP between Ethereum Sepolia and Base Sepolia.
  - `RescueEscrow.sol` for failed CCIP transfers.
  - Cross-chain lock `rescueInProgress[user]` while transfer is in flight.
- Guardrails and safety:
  - Budget guard (per rescue + daily cap).
  - Source reserve protection (do not withdraw more than 80% of available source collateral).
  - Recovery target buffer (target HF = threshold x 1.10).
  - Tenderly best-effort pre-simulation (execute on pass, abort on fail in demo).
  - Stale data skip path and rapid deterioration urgent event.
- Verification/audit:
  - Immutable on-chain log for every rescue (protocol, amount, source/target chain, gas, timestamp).
  - History view and linkage to CRE execution proof.
- Demo protocol layer:
  - Implement and deploy local protocol-mimic contracts on each target chain (Ethereum Sepolia and Base Sepolia) to emulate minimal Aave/Compound/Morpho behaviors required by Reprieve.
  - Adapters consume a common interface and point to mimic deployments in demo.

## Hard Constraints
- Product scope: liquidation protection only.
- Token scope: ERC20 position tokens only (aTokens, cTokens, vault shares); native token rescue is out of scope.
- Chain scope: Ethereum Sepolia and Base Sepolia for demo cross-chain path.
- Sepolia dependency constraint: do not rely on official Aave/Compound/Morpho Sepolia deployments for the core demo path.
- Integration strategy: use self-deployed, minimal protocol-mimic contracts as authoritative protocol endpoints for demo.
- Mock protocol economics must align with [demo-lending-merged.md](/Users/sniperman/code/reprieve/specs/demo-lending-merged.md): centralized owner-updated oracle, 75% max LTV, 80% liquidation threshold, fixed 5% APR, and permissionless liquidation path.
- Compound mimic scope: implement a minimal Compound-like market plus `MockCToken`; detailed Comet internals are out of scope.
- Architecture scope: per-user CRE workflow that is permissionlessly triggerable but internally validated and DON-verifiable.
- Adapter scope: demo can use mock adapters with same interface planned for real protocol adapters.
- Demo expectation: force/show max path including CCIP to demonstrate all Chainlink touchpoints.
- Timebox: 4-day sprint, so prioritize end-to-end reliability of the core rescue loop over extra UX/features.

## Explicit Non-Goals (This Sprint)
- General portfolio rebalancing or yield optimization.
- Institutional feature set (multisig approvals, RBAC, compliance exports, institutional reporting).
- Full production hardening for all failure modes and all chains.
- Native token handling in rescue flow.
- Supporting protocols beyond Aave/Compound/Morpho.
- Full parity with production Aave/Compound/Morpho semantics, interest models, and liquidation engines.
- Removing user approvals entirely (approvalless flow not in scope).
- Building a centralized-operator architecture.

## Acceptance Boundary (Definition of Done)
- User can onboard and configure protection in one flow.
- System can detect threshold breach and execute rescue (same-chain and CCIP path).
- Failed CCIP path is safely escrowed and recoverable/retriable.
- Every rescue attempt is logged on-chain with auditable metadata.
- Demo script can complete within 4:30 and visibly exercises Chainlink components.

## Open Decisions To Lock Early
- Aggregate HF method in MVP: weighted average only vs user-selectable (weighted/min).
- Quant signal provider/API and fallback behavior when provider is unavailable.
- Trigger cadence and latency target for external bot calls.
- Exact formula and assumptions for the coverage calculator.
- Retry policy details for escrowed failed CCIP transfers (count, interval, who can trigger).
- Behavior when Tenderly is down in non-demo environments (force-execute feature deferred or not).
