# 05b. Signal Contract Specification

> **Version:** 1.0
> **Date:** 2026-07-30
> **Status:** Active
> **Applies to:** QuantEdge RSI v11.37+

---

## 1. Overview

Signal Contract defines the exact interface between **Signal Detection** (Layer 1) and the rest of the platform (Engine, Display, Data layers). Any future signal source (MACD, ICT, etc.) MUST implement this contract to plug into the probability pipeline.

```
Signal Source (Layer 1)
    |
    v
StoreSignal() --> g_signals[] --> ProbabilityEngine --> g_currentProb
                       |                                      |
                       v                                      v
              ArrowManager (Display)              PanelDrawing (Display)
              SignalLogger (Data)                 LineDrawing (Display)
```

---

## 2. SignalData Struct (Core/Structs.mqh)

Every signal source MUST populate a `SignalData` record via `StoreSignal()`.

```c
struct SignalData
{
   // === REQUIRED ===
   datetime signalTime;        // Broker local time at signal bar open
   int      barIndex;          // Bar index in buffer arrays
   int      caseNumber;        // Unique case ID (1-9 RSI, 11-19 MACD future, etc.)
   bool     isBuySignal;       // Direction: true=BUY, false=SELL
   double   entryPrice;        // Computed entry price
   double   stopLoss;          // SL level
   double   takeProfit1;       // TP1 level
   double   takeProfit2;       // TP2 level (0 if not applicable)
   double   takeProfit3;       // TP3 level (0 if not applicable)
   double   atrValue;          // ATR at signal bar

   // === OPTIONAL ===
   datetime signalTimeUTC;     // UTC-normalized (auto-computed by StoreSignal)
   double   angleStrength;     // Z-score of momentum (0.0 = not computed)
   int      rsiPeriod;         // Parameter at detection time
   double   spreadAtSignal;    // Broker spread at signal time
   int      sessionBlock;      // 0=Asian, 1=London, 2=Overlap, 3=LateNY
   double   rsiAtSignal;       // RSI value at signal bar

   // === INTERNAL (managed by Engine) ===
   int      simCachedTP;       // Simulation cache (99 = not cached)
   int      simCachedBTR;      // Bars-to-result for above
   int      edgeCachedOutcome; // Edge measurement cache (99 = not cached)
   double   predictedProb;     // probTP1 at creation (Brier Score calibration)
   double   xgbPredictedProb;  // XGBoost probTP1 at creation
};
```

---

## 3. StoreSignal() — Storage Interface

**File:** `Core/Globals.mqh`

```c
void StoreSignal(datetime t, int barIdx, int caseNum, bool isBuy,
                 double entry, double sl, double tp1, double tp2, double tp3,
                 double atr, double angleZ = 0.0,
                 double spread = 0.0, int sessBlock = -1, double rsiVal = 0.0)
```

**Behavior:**
- Appends to `g_signals[]` with 128-element reserve
- Auto-computes `signalTimeUTC` via `NormalizeCandleToUTC(t, Period())`
- Sets `rsiPeriod = InpRSIPeriod`
- Initializes all sim caches to 99

**Rules:**
- Call ONLY on closed bars (anti-repaint)
- Call ONCE per signal (no duplicates)
- `caseNumber` MUST be unique per signal source range

---

## 4. Case Number Convention

| Range | Source | Status |
|-------|--------|--------|
| 1-9 | RSI Signal Cases | Active |
| 11-19 | MACD (future) | Reserved |
| 21-29 | ICT (future) | Reserved |
| 31-39 | Price Action (future) | Reserved |
| 91-99 | Custom / User-defined | Reserved |

### Current RSI Cases (1-9)

| Case | Name | Buy Condition | Sell Condition | Angle Gate |
|------|------|---------------|----------------|------------|
| 1 | OB/OS Bounce | Green crosses above 32 + BB Lower | Green crosses below 68 + BB Upper | No |
| 2 | Regular Divergence | Price: Lower Low, RSI: Higher Low | Price: Higher High, RSI: Lower High | Yes |
| 3 | Hidden Divergence | Price: Higher Low, RSI: Lower Low | Price: Lower High, RSI: Higher High | Yes |
| 4 | Strong Trend | Green crosses above 50 + breaks BB Upper | Green crosses below 50 + breaks BB Lower | No |
| 5 | Orange Near Level | Orange near 32 (within tolerance) | Orange near 68 (within tolerance) | Yes |
| 6 | Trend Continuation | Pullback to Orange, bounce up | Pullback to Orange, bounce down | No (session hard-block) |
| 7 | Sideway Breakout | BB Upper breakout + N crosses in lookback | BB Lower breakout + N crosses in lookback | No |
| 8 | Basic Crossover | 2-bar confirmed Green > Red, strong angle | 2-bar confirmed Green < Red, strong angle | Yes (strong) |
| 9 | Plain Cross | 2-bar confirmed Green > Red | 2-bar confirmed Green < Red | No |

### Detection Priority Order

```
Case 6 -> 2 -> 4 -> 3 -> 1 -> 5 -> 7 -> 8 -> 9
(first match wins)
```

---

## 5. Signal Lifecycle

```
  INIT --> DETECT --> STORE --> DISPLAY
                        |
                   PROBABILITY
                        |
            +-----------+-----------+
            v           v           v
        OUTCOME    TIME-DECAY    PERSIST
```

| Phase | Location | Actions |
|-------|----------|---------|
| Init | `OnInit()` | Reset signals, apply TF auto-config, load persisted binary |
| Detect | `OnCalculate()` loop | Iterate closed bars, check cases in priority order |
| Store | `StoreSignal()` | Append to `g_signals[]`, compute UTC time, init caches |
| Display | After detection | Arrow, panel, SL/TP lines |
| Probability | `CalculateProbability(idx)` | 6-step pipeline, throttled 200ms |
| Outcome | Per-tick | Check TP/SL hit, update session stats |
| Time-Decay | Within probability | Weibull survival model |
| Persist | `OnDeinit()` | `SaveSignalsBinary()` for warm restart |

---

## 6. Probability Pipeline (Engine/ProbabilityEngine.mqh)

| Step | Name | Description |
|------|------|-------------|
| 1 | Historical Simulation | 3-tier scan: Tier1 (same-case weighted), Tier2 (other-case), Tier3 (ATR-based) |
| 2 | Edge Measurement | Directional edge from stored signals |
| 3 | Edge Adjustments | MTF, intermarket, angle Z-score, vol-regime, market state |
| 4 | Theoretical Probability | Gambler's Ruin with fat-tail, vol-cluster, spread corrections |
| 5 | Bayesian Combine | Wilson Score SE weighted average |
| 5.1 | XGBoost Integration | CALIBRATION (skip) / XGBOOST (override) / ENSEMBLE (Brier-weighted) |
| 5.5 | Confidence Adjustments | 1-bar price confirmation + ATR spike detection |
| 5.6 | Session Quality | Bayesian blend with per-session win rate (n>=50 gate) |
| 5.65 | Brier Calibration Shrink | Per-case or global Brier drives shrink toward 50% |
| 5.7 | Time-Decay / Survival | Weibull model |
| 6 | Final Normalize | probTP1 + probSL = 100%, TP2 <= TP1, TP3 <= TP2 |

---

## 7. Future Signal Source Contract (Sprint 2)

Any new signal source MUST:

1. Implement detection functions returning `bool` for buy/sell per bar
2. Use unique case numbers within its reserved range
3. Call `StoreSignal()` with all required fields on closed bars only
4. Respect cooldown via `GetActiveCooldownBars()`
5. Provide `GetCaseName(caseNum)` for display
6. NOT directly access Engine/Display/Data layer globals

---

## 8. Known Layer Violations (to fix in Sprint 2)

| File | Violation |
|------|-----------|
| `Analysis/SessionStatistics.mqh` | includes `../Engine/WalkForward.mqh` |
| `Analysis/SessionFilter.mqh` | includes `../Engine/WalkForward.mqh` |
