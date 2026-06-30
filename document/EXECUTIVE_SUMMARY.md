# RSI Advanced — Latency System Review: Executive Summary

**Date**: 2026-06-09
**Reviewer**: Principal System Engineer (MT4/MT5 Indicator Architecture)
**Scope**: Full codebase review — 25 source files, ~6,500 lines of MQL4/MQL5 code
**Focus**: Realtime chart indicator performance, UI responsiveness, computation efficiency

---

## Overall Architecture Assessment

The RSI Advanced indicator is a **feature-rich, analytically sophisticated** trading tool. The quantitative depth (Weibull survival, Wilson Score, Walk-Forward validation, Gambler's Ruin) is impressive and academically sound.

However, the **runtime performance architecture has critical flaws** that cause visible lag on M1/M5 timeframes. The root cause is a pattern of **heavy computation running on every tick without throttling or caching**.

---

## Severity Distribution

| Severity | Count | Description |
|----------|-------|-------------|
| **P0 CRITICAL** | 4 | Causes visible chart freeze/lag |
| **P1 HIGH** | 8 | Significant performance degradation |
| **P2 MEDIUM** | 10 | Measurable but tolerable overhead |
| **P3 LOW** | 3 | Minor or cosmetic issues |
| **PASS** | 8 files | No action required |

---

## TOP 5 CRITICAL FIXES (Priority Order)

### FIX #1: Port MQL5 Display Throttle to MQL4
**File**: `RSI_Advanced.mq4` lines 451-530
**Impact**: 10-20× overall performance improvement
**Effort**: 30 lines (copy from mq5)
**Problem**: MQL4 has NO display throttle — every tick fires:
- `CalculateProbability()` — 50,000+ iterations
- `MeasureEdgeFromHistory()` — 10,000+ iterations
- `RefreshMTFData()` — 612 iRSI calls
- `CalculateEntryZones()` — 5,000+ iterations
- Total: **~280,000 wasted iterations per second on M1**

MQL5 already has the correct throttle (200ms + 5 conditions). Port it.

---

### FIX #2: Cache `CalculateProbability()` Results Per Signal+Bar
**File**: `ProbabilityEngine.mqh`
**Impact**: Eliminates 99% of redundant probability computation
**Effort**: 5 lines

```mql
static int     s_probCachedSigIdx = -1;
static datetime s_probCachedBarTime = 0;

void CalculateProbability(int sigIdx)
{
   datetime curBar = iTime(NULL, 0, 0);
   if(sigIdx == s_probCachedSigIdx && curBar == s_probCachedBarTime)
      return;  // ← Skip 50,000+ iterations
   s_probCachedSigIdx = sigIdx;
   s_probCachedBarTime = curBar;
   // ... existing pipeline ...
}
```

---

### FIX #3: Move `MeasureEdgeFromHistory()` Out of `DrawInfoPanel()`
**File**: `PanelDrawing.mqh` ~line 572, `Normalize.mqh`
**Impact**: Removes 10,000-50,000 iterations from the UI render path
**Effort**: 10 lines

Pre-compute in the main loop and store in a global variable. The draw function reads the cached result.

---

### FIX #4: Move `UpdateSpreadRegime()` to Per-Bar Section
**File**: `RSI_Advanced.mq4` and `RSI_Advanced.mq5`
**Impact**: Eliminates 50 iATR calls per tick
**Effort**: 1 line (move to isNewBar block)

Currently mislabeled as "Lightweight: every tick" but does 50 iATR calls.

---

### FIX #5: Add MTF Cache Invalidation by Higher-TF Bar Time
**File**: `MTFEngine.mqh`
**Impact**: Prevents recalculating unchanged MTF data
**Effort**: 5 lines

H4 MTF data only changes every 4 hours — no reason to recalculate every tick/bar.

---

## ADDITIONAL IMPORTANT FIXES

### FIX #6: `StoreSignal()` ArrayResize Reserve
**File**: `Globals.mqh` line 96
```mql
ArrayResize(g_signals, g_signalCount, 128);  // Add reserve parameter
```

### FIX #7: `CheckPendingOutcomes()` — Tick-Optimized Fast Path
**File**: `SessionStatistics.mqh` lines 198-265
Only check current bar on normal ticks; full historical scan only on new bar.

### FIX #8: `MeasureOptimalTPRatios()` — Replace Bubble Sort
**File**: `SLTP.mqh` ~line 400
Replace O(n²) bubble sort with partial selection sort for percentile calculation.

### FIX #9: Missing `LogSignalEntry()` in MQL5
**File**: `RSI_Advanced.mq5` signal detection block
MQL5 never logs signals to CSV — data loss bug.

### FIX #10: `DeleteObjectsByPrefix()` — Use Built-in
**File**: `MathUtils.mqh` and `MQLCompat.mqh`
```mql
ObjectsDeleteAll(0, prefix);  // Built-in, faster than manual loop
```

---

## PERFORMANCE IMPACT ESTIMATE

### Before Fixes (MQL4 on M1 XAUUSD, ~4 ticks/sec):
```
Per tick: ~70,000 iterations + ~10,000 API calls
Per second: ~280,000 iterations + ~40,000 API calls
Result: VISIBLE LAG, chart freezes during probability calculation
```

### After Fixes #1-#5:
```
Per tick: ~100 iterations + ~20 API calls (MarketInfo, iClose)
Per new bar: ~70,000 iterations (ONCE, then cached)
Per second: ~400 iterations + ~80 API calls
Result: SMOOTH chart, computation only on meaningful events
```

**Expected improvement: 700× reduction in per-tick computation**

---

## WHAT A WELL-CODED INDICATOR MUST PRIORITIZE

### 1. Tick Throttling (HIGHEST PRIORITY)
Never run heavy computation on every tick. Use:
- New-bar detection (`currentBarTime != s_lastBarTime`)
- Minimum time interval (200ms via `GetTickCount()`)
- Price-movement threshold (ATR × 0.1)
- Signal-change detection

### 2. Result Caching
Any computation that depends on historical data should be cached per bar. Historical data doesn't change between ticks on the same bar.

### 3. Separate Computation from Rendering
Never call heavy analysis functions from within UI draw functions. Pre-compute, store in globals, then read from draw functions.

### 4. Incremental Calculation
Only recalculate what changed. The `fullRecalc` vs incremental path is correct in RSICore — extend this pattern to all modules.

### 5. Batch API Calls
The MQLCompat.mqh batch cache is excellent — extend this pattern to cross-TF calls in MTFEngine.

### 6. Memory Pre-Allocation
Always use `ArrayResize(array, size, reserve)` — the third parameter prevents per-item reallocation.

---

## FILE-BY-FILE VERDICT

| File | Severity | Action |
|------|----------|--------|
| Config.mqh | PASS | No action |
| Structs.mqh | PASS | No action |
| **Globals.mqh** | P1 | ArrayResize reserve |
| MathUtils.mqh | P3 | ObjectsDeleteAll |
| RSICore.mqh | PASS | No action |
| **MTFEngine.mqh** | P0 | Tick throttle + HTF cache |
| **ProbabilityEngine.mqh** | P0 | Result caching |
| SignalEngine.mqh | PASS | No action |
| SignalCases.mqh | PASS | No action |
| SwingDetection.mqh | PASS | No action |
| ArrowManager.mqh | PASS | No action |
| **LineDrawing.mqh** | P2 | Reduce redundant iATR, update-only pattern |
| **PanelDrawing.mqh** | P0 | Move MeasureEdgeFromHistory out |
| ChartEvents.mqh | P2 | Loading indicator for UX |
| **SLTP.mqh** | P1 | Cache zones, fix bubble sort |
| **Normalize.mqh** | P0 | Cache MeasureEdgeFromHistory |
| **IntermarketAnalysis.mqh** | P2 | Per-bar guard |
| SessionFilter.mqh | PASS | No action |
| **SessionStatistics.mqh** | P1 | Fast-path CheckPendingOutcomes |
| MarketRegime.mqh | PASS | No action |
| VolumeAnalysis.mqh | P3 | Cache Bars |
| VolatilityAnalysis.mqh | P3 | Cache GetATRState |
| **WalkForward.mqh** | P1 | O(n+m) matching, move spread to per-bar |
| MQLCompat.mqh | PASS | Excellent batch cache |
| SignalLogger.mqh | PASS | Good queue-based design |
| **RSI_Advanced.mq4** | **P0** | **PORT MQ5 THROTTLE** |
| **RSI_Advanced.mq5** | P1 | Cache probability, fix logging gap |

---

## CONCLUSION

The indicator's **analytical engine is excellent** — Weibull decay, Wilson Score, Walk-Forward, Entry Zones are all well-implemented mathematically. The **MQLCompat.mqh batch cache** shows strong engineering.

The **critical weakness is the runtime execution model**: heavy computations designed for offline analysis are running in a realtime tick loop without caching or throttling. This is a **solvable architectural problem**, not a fundamental design flaw.

**Implementing Fixes #1-#5 (~50 lines total) will transform this from a laggy indicator to a smooth, professional-grade realtime tool.**
