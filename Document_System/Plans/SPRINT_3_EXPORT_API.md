# Sprint 3: Export API + EA Template

> **Goal:** Signal export API for EA consumption
> **Duration:** 1 week
> **Prerequisite:** Sprint 2 (DONE)
> **Status:** `DONE` (2026-08-05)

---

## Scope Decision

Buffer-based export (25 buffers, indices 0-24) was already built in commit `7ce9b6f` (2026-08-03, pre-dates this sprint). Sprint 3 scope = **EA Template + documentation only**. No new indicator buffers, no `ProbabilityEngine`/`SLTP`/`Normalize` changes (Rule #2 — Walk-Forward not triggered).

Key rationale:
- All semantic fields an EA needs already exist in buffers (direction, entry/SL/TP, probability, confidence, recommendation, EV, suggested risk %)
- Lot size = derived value (`balance × riskPct / slDistance / tickValue`) — needs broker/account context only the EA has
- Buffer indices are a public contract (marketed in `sales/03_description/product_description_EN.md` for buffers 5-10)
- EA ships as reference/skeleton with `InpEnableAutoTrading = false` by default

See `Document_System/12_EA_EXPORT_CONTRACT.md` for full buffer reference.

---

## Tasks

| # | Task | Status | Files |
|---|---|---|---|
| 3.1 | Buffer contract reference doc | `DONE` | `Document_System/12_EA_EXPORT_CONTRACT.md` (new) |
| 3.2 | EA template — MQ4 | `DONE` | `QuantEdge_EA_Template.mq4` (new) |
| 3.3 | EA template — MQ5 | `DONE` | `QuantEdge_EA_Template.mq5` (new) |
| 3.4 | Update MASTER_PLAN + this file | `DONE` | `MASTER_PLAN.md`, `SPRINT_3_EXPORT_API.md` |
| 3.5 | Compile verify (MQ4 + MQ5) — USER | `NOT STARTED` | *(user task)* |

### 3.1 Buffer Contract Reference Doc

`Document_System/12_EA_EXPORT_CONTRACT.md` — full EA-facing reference:
- Complete buffer index table (0-24): meaning, range, EMPTY_VALUE, population timing
- `ENUM_RECOMMENDATION` ordinal table (0-5): score/EV thresholds, risk caps
- Staleness/expiry derivation from buffers 16-18
- `InpEAMode` (Config.mqh:67) documentation
- SL/TP mode caveat (EV-Optimized default, not naive ATR)
- Known gaps (no TP3 price buffer, no lot-size buffer — by design)

### 3.2 EA Template — MQ4

`QuantEdge_EA_Template.mq4` — reference EA consuming indicator via `iCustom()`:
- Inputs: `InpIndicatorName`, `InpEnableAutoTrading` (false), `InpMinConfidence` (65), `InpMinRecLevel` (1=ENTRY), `InpAllowCaution`, `InpMaxLotSize`, `InpMaxSpreadPoints`, `InpMagicNumber`, `InpSlippage`
- Pass-through indicator params: `Ind_RSIPeriod`, `Ind_FastMAPeriod`, `Ind_SignalMAPeriod`, `Ind_BBPeriod`, `Ind_BBDeviation`, `Ind_EAMode=true`
- New-bar detection → read buffers at shift=1 → 5-gate decision chain:
  1. Recommendation-level gate (ordinal <= `InpMinRecLevel`)
  2. Confidence gate (buffer 22 >= `InpMinConfidence`)
  3. Staleness gate (survival ratio >= 0.15)
  4. No-duplicate-position gate (same symbol+direction+magic)
  5. Spread gate (current spread <= `InpMaxSpreadPoints`)
- Inline `CalculateLotFromRisk()`: `balance × riskPct / 100 / (slDistance × tickValue)`, normalized to LotStep
- `OrderSend()` gated behind `InpEnableAutoTrading`, comment embeds case+rec level

### 3.3 EA Template — MQ5

`QuantEdge_EA_Template.mq5` — same gate logic, materially different read/order layer:
- `iCustom()` in `OnInit()` returns handle, `CopyBuffer()` per read in `OnTick()`
- `CTrade` class (`#include <Trade/Trade.mqh>`) for `Buy()`/`Sell()`
- `IndicatorRelease()` in `OnDeinit()`
- Position scanning via `PositionsTotal()`/`PositionGetTicket()`/`PositionGetString()`

---

## Acceptance Criteria

- [x] `Document_System/12_EA_EXPORT_CONTRACT.md` created — all 25 buffer indices documented
- [x] `ENUM_RECOMMENDATION` ordinal table (0-5) included with Normalize.mqh cross-ref
- [x] Staleness/expiry derivation documented (buffers 16-18)
- [x] `QuantEdge_EA_Template.mq4` created — iCustom() reads, 5 decision gates, lot-from-risk helper
- [x] `QuantEdge_EA_Template.mq5` created — same gates, handle-based CopyBuffer() read pattern
- [x] `InpEnableAutoTrading` defaults false in both EA files
- [x] Zero changes to `ProbabilityEngine.mqh`, `SLTP.mqh`, `SLTPOptimizer.mqh`, `Normalize.mqh`
- [x] Zero new indicator buffers — buffer count remains 25
- [x] MASTER_PLAN.md updated: Sprint 3 status, dates, EA Output readiness score
- [ ] MQ4 compile 0 errors (user verify)
- [ ] MQ5 compile 0 errors (user verify)
- [ ] Demo-account smoke test: gate decisions logged on new bar, auto-trading OFF (user verify)

---

## Files Changed/Created (5)

| File | Change |
|------|--------|
| `Document_System/12_EA_EXPORT_CONTRACT.md` | New — full buffer reference doc (indices 0-24, ENUM_RECOMMENDATION ordinals, staleness derivation) |
| `QuantEdge_EA_Template.mq4` | New — reference EA: iCustom() polling, 5-gate chain, lot helper, InpEnableAutoTrading-gated OrderSend |
| `QuantEdge_EA_Template.mq5` | New — same logic, handle-based CopyBuffer() + CTrade order placement |
| `Document_System/Plans/MASTER_PLAN.md` | Sprint 3 → DONE, dates, EA Output readiness score, changelog |
| `Document_System/Plans/SPRINT_3_EXPORT_API.md` | Populated from stub with tasks/acceptance/files |

**NOT touched:** `QuantEdge_RSI.mq4/.mq5` (buffer export already complete), `Include/QuantEdge/Engine/*`, `Include/QuantEdge/Analysis/Normalize.mqh`, `sales/` mirror (pre-existing sync debt — separate future ticket).
