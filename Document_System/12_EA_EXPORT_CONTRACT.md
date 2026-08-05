# 12. EA Export Contract — Buffer Reference

> **Version:** 1.0
> **Date:** 2026-08-05
> **Status:** Active
> **Applies to:** QuantEdge RSI v12.2+ (commit `7ce9b6f`+)

---

## 1. Overview

QuantEdge RSI indicator exposes **25 indicator buffers** (indices 0-24) readable by any Expert Advisor via `iCustom()`. This document is the authoritative contract for EA authors consuming these buffers.

```
QuantEdge_RSI indicator (25 buffers)
    │
    │  iCustom() / CopyBuffer()
    │
    v
EA Template (QuantEdge_EA_Template.mq4/.mq5)
    │
    ├─→ Decision Gates (rec level, confidence, staleness, spread, no-duplicate)
    ├─→ Lot Sizing (suggestedRisk% → lot)
    └─→ OrderSend / CTrade
```

---

## 2. Buffer Index Table

| Index | Name | Meaning | Valid Range | When Populated |
|-------|------|---------|-------------|----------------|
| 0 | `BufferGreen` | RSI fast line | 0-100 | Every bar |
| 1 | `BufferRed` | RSI signal/slow line | 0-100 | Every bar |
| 2 | `BufferBBUpper` | Bollinger upper band on RSI | 0-100 | Every bar |
| 3 | `BufferBBLower` | Bollinger lower band on RSI | 0-100 | Every bar |
| 4 | `BufferOrange` | Baseline MA line | 0-100 | Every bar |
| 5 | `BufferBuySignal` | Buy signal case number | 1-9 (RSI) | Signal bar only |
| 6 | `BufferSellSignal` | Sell signal case number | 1-9 (RSI) | Signal bar only |
| 7 | `BufferEntry` | Entry price | > 0 | Signal bar only |
| 8 | `BufferSL` | Stop loss price | > 0 | Signal bar only |
| 9 | `BufferTP1` | Take profit 1 price | > 0 | Signal bar only |
| 10 | `BufferTP2` | Take profit 2 price | > 0 (0 if N/A) | Signal bar only |
| 11 | `BufferProbTP1` | Probability of hitting TP1 | 0-100 (%) | Closed signal bar only |
| 12 | `BufferProbTP2` | Probability of hitting TP2 | 0-100 (%) | Closed signal bar only |
| 13 | `BufferProbTP3` | Probability of hitting TP3 | 0-100 (%) | Closed signal bar only |
| 14 | `BufferProbSL` | Probability of hitting SL | 0-100 (%) | Closed signal bar only |
| 15 | `BufferProbSamples` | Sample count backing probability | >= 0 (int) | Closed signal bar only |
| 16 | `BufferProbDecayedTP1` | Time-decayed TP1 probability | 0-100 (%) | Closed signal bar only |
| 17 | `BufferProbSurvivalRatio` | Edge survival ratio | 0.0-1.0 | Closed signal bar only |
| 18 | `BufferProbExpiresMin` | Minutes until edge < 15% | >= 0 (int) | Closed signal bar only |
| 19 | `BufferXGBProbTP1` | XGBoost-predicted TP1 probability | 0-100 (%) | Closed signal bar only |
| 20 | `BufferXGBActive` | XGBoost model was active | 0.0 or 1.0 | Closed signal bar only |
| 21 | `BufferRecLevel` | Recommendation level (enum ordinal) | 0-5 (int) | Closed signal bar only |
| 22 | `BufferRecConfidence` | Recommendation confidence score | 0-100 (int) | Closed signal bar only |
| 23 | `BufferRecEV` | Expected Value in R-multiples | any double | Closed signal bar only |
| 24 | `BufferRecSuggestedRisk` | Suggested risk percent | 0.0-2.0 (%) | Closed signal bar only |

All buffers return `EMPTY_VALUE` at bars where they are not populated.

---

## 3. Population Timing Rules

| Group | Buffers | Populated When |
|-------|---------|----------------|
| RSI Lines | 0-4 | Every calculated bar (always available) |
| Signal Detection | 5-6 | Bar where a signal case fired (historical + current) |
| Entry/SL/TP Prices | 7-10 | Bar where a signal case fired (historical + current) |
| Probability/XGB/Rec | 11-24 | **ONLY at the just-closed signal bar** (`i >= rates_total - 2`) |

**Why buffers 11-24 are closed-bar-only:** `CalculateProbability()` is computationally expensive (Bayesian ensemble + XGBoost + Weibull survival). Re-running it for every historical bar on chart load would be prohibitively slow. These buffers are computed once when a signal bar closes and are NOT back-filled on full recalc.

---

## 4. EA Polling Rule

> **Read at `shift=1` (last closed bar) when a new bar is detected (`Time[0]` changed).**
> **Do NOT poll every tick** — `CalculateProbability()` is only invoked when a new signal bar closes, so intra-bar reads return the same cached values.

Source: `QuantEdge_RSI.mq5:82-87`, `QuantEdge_RSI.mq4:79-84`.

### MQ4 Read Pattern

```c
double val = iCustom(Symbol(), Period(), InpIndicatorName, /* inputs */, bufferIndex, 1);
if(val == EMPTY_VALUE) { /* no signal at this bar */ }
```

### MQ5 Read Pattern

```c
// OnInit(): create handle once
int hIndicator = iCustom(Symbol(), Period(), InpIndicatorName, /* inputs */);

// OnTick(): read per new bar
double buf[1];
if(CopyBuffer(hIndicator, bufferIndex, 1, 1, buf) == 1 && buf[0] != EMPTY_VALUE)
{
   // buf[0] contains the value
}

// OnDeinit(): release handle
IndicatorRelease(hIndicator);
```

---

## 5. Recommendation Level Enum (Buffer 21)

Buffer 21 (`BufferRecLevel`) contains the ordinal of `ENUM_RECOMMENDATION` cast to `double`.

| Ordinal | Name | Label | Risk Cap | Score/EV Gate |
|---------|------|-------|----------|---------------|
| 0 | `REC_STRONG_ENTRY` | "STRONG ENTRY" | 2.0% | score >= 75, EV > 0.15R |
| 1 | `REC_ENTRY` | "ENTRY" | 1.5% | score >= 55, EV > 0.05R |
| 2 | `REC_CAUTION_ENTRY` | "CAUTION ENTRY" | 1.0% | score >= 35, EV > 0 |
| 3 | `REC_WAIT` | "WAIT" | 0% | EV > -0.05R |
| 4 | `REC_AVOID` | "AVOID" | 0% | EV <= -0.05R |
| 5 | `REC_COUNTER_TREND` | "AVOID (Counter Trend)" | 0% | EV <= -0.05R + MTF against |

Source: `Include/QuantEdge/Analysis/Normalize.mqh:752-756` (enum), `:903-938` (classification), `:944-953` (hard gate).

**Important:** MQL cannot cast a `double` buffer value back to a named enum. EA code must compare against the literal ordinal (e.g., `if(recLevel <= 1.0)` to accept STRONG_ENTRY + ENTRY) or redeclare the enum locally.

---

## 6. Suggested Risk (Buffer 24)

Buffer 24 (`BufferRecSuggestedRisk`) is a **risk percent** — NOT a lot size.

Value = `min(kellyFraction × 100, tierCap)`, where `tierCap` is from the table above (2.0/1.5/1.0/0%). When recommendation is WAIT, AVOID, or COUNTER_TREND, this value is always `0.0`.

**EA lot-size conversion:**
```
lotSize = AccountBalance() * suggestedRiskPct / 100.0 / (slDistancePoints * tickValue)
lotSize = normalize to LotStep, clamp [MinLot, MaxLot]
```

Cross-reference: `Document_System/02_LOT_SIZING.md` for the indicator's own Kelly Fraction logic.

---

## 7. Staleness / Expiry Derivation

There is no explicit `expiryTime` buffer. Instead, three buffers together let an EA compute a signal staleness gate:

| Buffer | Index | Use |
|--------|-------|-----|
| `BufferProbExpiresMin` | 18 | Estimated minutes until edge drops below 15% |
| `BufferProbSurvivalRatio` | 17 | Current edge survival (1.0 = fresh, 0.0 = expired) |
| `BufferProbDecayedTP1` | 16 | Time-decayed TP1 probability |

**Recommended staleness check:**
```
elapsedMinutes = (TimeCurrent() - signalBarTime) / 60;
isExpired = (elapsedMinutes > BufferProbExpiresMin[shift])
         || (BufferProbSurvivalRatio[shift] < 0.15);
```

The 15% threshold corresponds to the edge-remaining floor documented in `Structs.mqh:118`.

---

## 8. Statistical Significance Gate

The indicator already demotes any STRONG_ENTRY / ENTRY / CAUTION_ENTRY recommendation to **WAIT** when `probSamples < GetMinSamplesForTimeframe()`.

This means buffer 21 (`RecLevel`) is inherently conservative — it will not recommend trading when the underlying historical simulation has insufficient data. EA authors do NOT need to re-implement this check; it is already embedded in the recommendation.

Source: `Normalize.mqh:944-953`.

---

## 9. SL/TP Price Mode

Buffers 7-10 (Entry, SL, TP1, TP2) reflect the active `InpSLTPMode` at indicator runtime. As of commit `95846d2`, the default is `SLTP_EV_OPTIMIZED` — grid search + Newton's method + golden-section refinement, optimizing `EV = P(TP) × R:R - (1 - P(TP))`.

EA authors should NOT assume SL/TP are simple ATR multiples. If you need the raw ATR-based levels, set `InpSLTPMode = SLTP_ATR_BASED` in the indicator inputs.

---

## 10. InpEAMode

`Config.mqh:67` defines `input bool InpEAMode = false`. When set to `true`:
- Suppresses chart objects (arrows, lines, panel) for performance
- Recommended when loading the indicator via `iCustom()` from an EA

---

## 11. Known Gaps

| Gap | Status | Reasoning |
|-----|--------|-----------|
| No TP3 price buffer | By design | `SignalData.takeProfit3` exists internally but TP3 is rarely used by EAs. Defer to future micro-sprint if demand arises. |
| No lot-size buffer | By design | Lot sizing requires broker/account context (balance, tick value, lot step) that only the EA has. EA computes `balance × riskPct / slDistance / tickValue` from buffer 24. |

---

## 12. Case Number Reference

| Range | Source | Status |
|-------|--------|--------|
| 1-9 | RSI Signal Cases | Active |
| 11-19 | MACD (future) | Reserved |
| 21-29 | ICT (future) | Reserved |
| 31-39 | Price Action (future) | Reserved |
| 91-99 | Custom / User-defined | Reserved |

Buffers 5 (buy) and 6 (sell) hold the case number at signal bars. For case name display, see `Include/QuantEdge/Data/SignalLogger.mqh` → `SL_GetCaseName()`.

Cross-reference: `Document_System/05b_SIGNAL_CONTRACT.md` for full case conditions and detection priority order.
