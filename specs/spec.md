# Reprieve

<aside>
🏦

**Reprieve — cross-protocol stop-loss that protects positions across multiple DeFi venues automatically**

</aside>

**Idea Pool:** [Reprieve](https://www.notion.so/Reprieve-835d095176514174b7df9e9789a0f32a?pvs=21) · **Sprint:** 4 days · **Based on:** Traditional stop-loss + [Gelato Automation](https://www.gelato.network/) + [DeFi Saver](https://defisaver.com/)

---

### Overview

- **User selects a rescue strategy** (1 strategy = 1 CRE per user) → configures params (HF threshold, priority queue, budget cap) → pays LINK to deploy CRE · per-token ERC20 approval for position tokens (aTokens, cTokens, vault shares) · pre-approved in demo; demo video briefly mentions users need to approve
- **Per-user CRE workflow** — each user's CRE has customizable trigger logic and HF computation per strategy · triggered by external bot (anyone can call) · CRE verifies conditions using Chainlink Data Feeds + off-chain quant data before executing
- **Chainlink Data Feeds** — CRE reads prices inside its workflow (verifiable by DON) for health factor computation and rescue decisions
- **Rescue Executor** fires on confirmed breach → priority queue → same-chain-first rescue, CCIP cross-chain as escalation · `RescueEscrow.sol` holds funds if CCIP fails
- **Tenderly simulation** pre-validates rescue tx (best-effort; abort on fail in demo)
- **On-chain rescue log** — immutable audit trail of every action written by CRE WF3
- **Demo always runs the max path** — cross-chain CCIP rescue forced to showcase all Chainlink touchpoints (CRE × Data Feeds × CCIP)

### Why CRE fits (Chainlink Runtime Environment)

- **Hybrid computation (quant + on-chain)** — incorporate richer off-chain signals (volatility, volume, OI, funding, CEX/DEX spreads, risk models) while keeping execution verifiable
- **Trustless automation** — the same CRE workflow that evaluates conditions can also execute the rescue, without a centralized bot operator
- **Faster reactions** — event-driven triggers + cron baseline reduce time-to-rescue vs cron-only bots
- **Composable end-to-end** — CRE orchestrates Data Feeds + CCIP + on-chain contracts as one coherent safety system
- **Auditability** — all key actions are logged on-chain for user verification

### Backlogs

[Reprieve — Backlogs](https://www.notion.so/Reprieve-Backlogs-0fdfb75cf9cc4ddaab53814e3c76fd5e?pvs=21)

### Jobs to be Done

[Reprieve — Jobs to be Done](https://www.notion.so/Reprieve-Jobs-to-be-Done-9cc0c8daa3d94c5e84971317eb403693?pvs=21)

### Demo Script

[Reprieve — Demo Script](https://www.notion.so/Reprieve-Demo-Script-d3ed17f9b91640319be9d9886a03eafe?pvs=21)

### Docs

[Reprieve — Architecture](https://www.notion.so/Reprieve-Architecture-4bffd8ba9f0849f49ee3d505e4896197?pvs=21)

[Reprieve — Default Parameters](https://www.notion.so/Reprieve-Default-Parameters-64a3f3b6f502418b9fe1645b501072b9?pvs=21)

### Acceptance Criteria

- [x]  **Product scope decision (demo)** — *liquidation protection only* (stop-loss / reprieve), not general portfolio rebalancing ✅
- [x]  **Approval UX decision (demo)** — per-token ERC20 approval; native tokens not supported; demo pre-approves upfront (not shown in demo video/script, but briefly mentioned ~1–2s that users need to approve to use) ✅
- [x]  **Token scope decision** — ERC20 position tokens (aTokens, cTokens, vault shares); users approve these to our protocol ✅
- [x]  **Adapter pattern (dev scope)** — demo uses mock lending market adapters; mainnet uses real ABIs/APIs from Aave V3/V4, Compound V3, Morpho V2 with same adapter structure ✅
- [x]  **Position discovery** — app auto-scans existing positions from external lending protocols; no manual import ✅
- [x]  **CRE config model** — app generates a customized CRE with user config embedded, deploys on-chain (still verifiable by DON) ✅
- [ ]  Dashboard renders positions from Aave + Compound + Morpho with live health factors
- [ ]  Setup flow: user picks a rescue strategy (each strategy = 1 CRE) → configures params (HF threshold, budget cap, priority queue) → signs tx to pay LINK (CRE deploy + operation fee) → UI requests fund approval if needed
- [ ]  Per-user CRE computes aggregate risk score when triggered by bot (customizable logic per strategy)
- [ ]  Rescue triggers when aggregate HF < user threshold — priority queue determines protocol order
- [ ]  Budget guard enforces per-rescue + per-day gas/spend cap
- [ ]  CCIP cross-chain collateral rescue executes on Arbitrum Sepolia ↔ Base Sepolia
- [ ]  On-chain rescue log written for every rescue action (protocol, amount, chains, gas, timestamp)
- [ ]  Per-user CRE: 1 workflow per user, bot-triggered, unified flow handles detection → rescue → logging
- [ ]  Same-chain-first rescue logic in priority queue — CCIP only when no same-chain source available
- [ ]  `RescueEscrow.sol` — holds funds on source chain if CCIP fails, user can claim or protocol retries
- [ ]  Cross-chain lock: `rescueInProgress[user]` blocks concurrent rescues while CCIP in flight
- [ ]  User protection coverage calculator in setup UI — shows required reserve vs current delegated capacity
- [ ]  Tenderly pre-simulation integrated — best-effort simulate → execute on success; abort with clear reason on failure *(confirmed feasible)* · ⚠️ runs inside CRE; cross-chain visibility limited to current chain — needs testing
- [ ]  Demo script dry run (4:30 max)

### References

- [Concrete Protocol](https://docs.concrete.xyz/Overview/how-it-works/) · ERC-4626 vaults · liquidation protection
- [DeFi Saver](https://defisaver.com/) · automated protection on Aave/Compound (single-chain)
- [Gelato Network](https://www.gelato.network/) · flexible on-chain automation
- [InstaDapp](https://instadapp.io/) · multi-protocol dashboard
- [Tenderly](https://tenderly.co/) · monitoring, simulation, alerting
- [Aave Historical Liquidations](https://aave.com/blog/historical-liquidations) · $429M liquidated Jan 31–Feb 5, 2026

### Code

- **Repo:** *TBD*
- **Stack:** `Chainlink CRE` · `Data Feeds` · `CCIP` · `EVM`
- **Chains:** Arbitrum Sepolia · Base Sepolia
- **Protocols:** Aave V3/V4 · Compound V3 · Morpho V2 · **Dev scope:** mock adapters (demo) → real ABI adapters (mainnet)
- **Key modules:** Health factor aggregator, Multi-signal trigger, Priority action queue (same-chain-first), Budget guard, Rescue executor, Rescue escrow
- **CRE Contracts:** `HealthMonitor.sol` · `RescueExecutor.sol` · `RescueLog.sol` *(PriceWatcher removed — price checked inside CRE workflow, verifiable by DON)*
- **Supporting Contracts:** `RescueEscrow.sol` · `CCIPReceiver.sol` *(RescueConfig + BudgetGuard removed — config/budget stored in user's CRE, still verifiable)*
- **CRE Docs:** [CRE Overview](https://chain.link/chainlink-runtime-environment) · [CRE SDK](https://docs.chain.link/cre/llms-full-ts.txt)
- **Tenderly:** Confirmed feasible — best-effort pre-flight simulation

---

### Project Tracker

[Reprieve Tracker](Reprieve/Reprieve%20Tracker%206367c115aeb3412485f619079fff965a.csv)

[Reprieve — Partner Overview](https://www.notion.so/Reprieve-Partner-Overview-917638aac44e4740b06016639b3bebfc?pvs=21)