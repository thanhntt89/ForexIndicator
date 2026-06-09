# Latency Review: ProbabilityEngine.mqh

**File**: `Include/RSI_Advanced/ProbabilityEngine.mqh` (~1009 lines)
**Role**: 6-step probability pipeline — Historical scan, edge measurement, Weibull decay, Gambler's Ruin, Bayesian combine, normalization
**Severity**: **P0 CRITICAL** — THE #1 performance bottleneck in the entire indicator

---

## Critical Bug #1: `CalculateProbability()` Runs Every Tick in MQL4

**Location**: Called from `OnCalculate()` display section
**Severity**: P0 — SYSTEM-CRITICAL LAG SOURCE

**MQL4** (`RSI_Advanced.mq4` line 472):
```mql
if(InpShowProbability) CalculateProbability(g_activeSignalIndex);
```
No throttle. Runs on every incoming tick.

**MQL5** (`RSI_Advanced.mq5` line 559): Inside 200ms throttle — better but still too frequent.

**What `CalculateProbability()` does per call:**
1. `ScanStoredSignals()` — iterates ALL stored signals, simulates each forward bar-by-bar
2. `ScanStoredSignals()` again — second pass for all-case baseline
3. `ScanHistoricalATRBased()` — scans up to 30,000 historical bars:
   - Per bar: `iRSI()` + `iATR()` + angle-tier filtering
   - For each match: forward-simulate up to 80 bars checking TP/SL hits
4. `MeasureEdgeFromHistory()` — another full scan of stored signals + deep history
5. `UpdateVolRegime()` — loops 50 bars computing ATR
6. `ApplyTimeDecay()` — Weibull survival calculation

**Total per call**: Estimated **50,000-200,000 loop iterations** depending on signal count and bar count.

**On M1 XAUUSD (~4 ticks/sec)**: **200,000-800,000 iterations per second** — this WILL freeze the chart.

---

## Critical Bug #2: `ScanHistoricalATRBased()` — Unbounded Deep Scan

**Location**: Lines ~300-400
**Severity**: P0

```mql
int maxBars = GetEffectiveProbMaxBars();  // Can return up to 30,000
for(int i = startSearch; i < maxBars; i++)
{
   double rsi = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, i);
   double atr = iATR(NULL, 0, InpATRPeriod, i);
   // ... angle tier filtering ...
   
   // For each match: forward simulate
   for(int f = 1; f <= maxForward; f++)
   {
      // ... check TP/SL hit per forward bar ...
   }
}
```

**Problem**: Outer loop up to 30,000 bars × inner loop up to 80 bars = 2.4M iterations worst case. Even with early exits, typical case is 100K+ iterations.

**Fix**: 
1. **Cache results**: Store scan results and only rescan when signal changes
2. **Early termination**: Stop after reaching `minSamples` with high confidence
3. **Per-TF caps**: M1 max 2000 bars, M5 max 3000, H1 max 5000

```mql
// Add static cache
static int    s_cachedSignalIdx = -1;
static double s_cachedProbTP1 = 0;
// ... other cached fields ...

void CalculateProbability(int sigIdx)
{
   if(sigIdx == s_cachedSignalIdx && !isNewBar) return;  // Use cached result
   s_cachedSignalIdx = sigIdx;
   // ... existing computation ...
}
```

---

## Critical Bug #3: `SimulateSignalOutcome()` — Per-Signal Bar-by-Bar Simulation

**Location**: Lines ~50-100
**Severity**: P1

For each stored signal, simulates forward bar-by-bar:
```mql
for(int f = 1; f <= maxForward; f++)
{
   double barHigh = iHigh(NULL, 0, barShift - f);
   double barLow  = iLow(NULL, 0, barShift - f);
   // ... TP/SL check ...
}
```

**Problem**: With 200 signals × 60 forward bars = 12,000 iHigh/iLow calls per ScanStoredSignals() call. Called twice = 24,000 calls.

**Fix**: Use batch price cache (already implemented in MQLCompat.mqh for current TF) — ensure the simulation reads from cache.

---

## Critical Bug #4: `UpdateVolRegime()` — 50 iATR Calls

**Location**: Lines ~600-650
**Severity**: P2

```mql
for(int i = 0; i < 50; i++)
{
   avgATR += iATR(NULL, 0, InpATRPeriod, i);
}
```

**Impact**: 50 iATR calls per CalculateProbability() call. Minor individually but adds to the total.

**Fix**: Cache the vol regime result per bar.

---

## Optimal Fix Strategy (Priority Order)

### Fix 1: Cache CalculateProbability results (HIGHEST IMPACT)
```mql
static int     s_probCachedSigIdx = -1;
static datetime s_probCachedBarTime = 0;

void CalculateProbability(int sigIdx)
{
   datetime curBar = iTime(NULL, 0, 0);
   if(sigIdx == s_probCachedSigIdx && curBar == s_probCachedBarTime)
      return;  // Result unchanged — skip ALL computation
   s_probCachedSigIdx = sigIdx;
   s_probCachedBarTime = curBar;
   // ... existing 6-step pipeline ...
}
```
**Effort**: 5 lines. **Impact**: Eliminates 99%+ of redundant computation.

### Fix 2: Cap deep scan by timeframe
```mql
int GetSafeMaxBars()
{
   int tf = Period();
   if(tf <= 1)   return(2000);
   if(tf <= 5)   return(3000);
   if(tf <= 15)  return(4000);
   if(tf <= 60)  return(5000);
   return(5000);
}
```

### Fix 3: Early termination when confidence is sufficient
```mql
if(totalSamples >= GetMinSamplesForTimeframe() * 2)
   break;  // Enough data for reliable probability — stop scanning
```

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| No result caching | P0 | 5 lines | Eliminates 99% redundant computation |
| Every-tick execution (MQL4) | P0 | 1 line | Prevents chart freeze on M1 |
| Unbounded 30K bar scan | P1 | 3 lines | Caps worst-case at reasonable level |
| Double ScanStoredSignals | P2 | Medium | Halves signal simulation work |
| SimulateSignalOutcome no batch | P2 | Medium | Reduces iHigh/iLow overhead |

---

## Verdict: **CRITICAL FIX REQUIRED** — This is the single largest performance bottleneck.
Adding a 5-line cache check would eliminate virtually all lag from this module.
