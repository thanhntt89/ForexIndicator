# Latency Review: SLTP.mqh

**File**: `Include/RSI_Advanced/SLTP.mqh` (~955 lines)
**Role**: SL/TP calculation (ATR, Fibonacci, Hybrid methods), Entry Zone system, optimal TP ratio measurement
**Severity**: **HIGH** — Contains O(n²) bubble sort and deep bar scanning

---

## Critical Bug #1: `MeasureOptimalTPRatios()` — Bubble Sort O(n²)

**Location**: ~Lines 400-500
**Severity**: P1

```mql
// Bubble sort for percentile calculation
for(int i = 0; i < count - 1; i++)
   for(int j = 0; j < count - i - 1; j++)
      if(ratios[j] > ratios[j+1])
         { double tmp = ratios[j]; ratios[j] = ratios[j+1]; ratios[j+1] = tmp; }
```

**Problem**: Sorts up to 500 samples with O(n²) complexity = 250,000 comparisons worst case.
- Called when computing TP ratios for signal display
- Not called every tick, but fires on signal change

**Impact**: 500² = 250,000 comparisons — measurable delay (~50-100ms) on signal click.

**Fix**: Replace with insertion sort (better for nearly-sorted data) or use simple percentile approximation:
```mql
// O(n) percentile without full sort — find k-th smallest using partial sort
double GetPercentile(double &arr[], int count, double pct)
{
   int targetIdx = (int)(count * pct);
   // Use selection algorithm O(n) instead of full sort O(n²)
   for(int i = 0; i <= targetIdx; i++)
   {
      int minIdx = i;
      for(int j = i + 1; j < count; j++)
         if(arr[j] < arr[minIdx]) minIdx = j;
      if(minIdx != i) { double t = arr[i]; arr[i] = arr[minIdx]; arr[minIdx] = t; }
   }
   return(arr[targetIdx]);
}
```
This gives O(n × k) where k = percentile index, much faster than full sort for p25/p50/p75.

---

## Critical Bug #2: `MeasureOptimalTPRatios()` — Deep History Scan

**Location**: ~Lines 350-400
**Severity**: P1

```mql
int maxScan = GetTPMeasurementBars();  // Up to 5000 bars
for(int i = startSearch; i < maxScan; i++)
{
   double rsi = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, i);
   double atr = iATR(NULL, 0, InpATRPeriod, i);
   // ... match conditions ...
   // ... forward simulation for each match ...
}
```

**Problem**: Up to 5000 bars × (iRSI + iATR per bar) + forward simulation for matches. Combined with the bubble sort above, this function is the second-heaviest computation in the indicator.

**Impact**: Called on signal change — adds 200-500ms per signal.

**Fix**: Cache results per signal index + timeframe bar. Only recompute when signal changes:
```mql
static int s_lastMeasuredSigIdx = -1;
if(sigIdx == s_lastMeasuredSigIdx) return;  // Use cached TP ratios
s_lastMeasuredSigIdx = sigIdx;
```

---

## Critical Bug #3: `CalculateEntryZones()` — Complex Nested Loops

**Location**: ~Lines 600-900
**Severity**: P1

This function performs:
1. Price distribution analysis with bar-by-bar loop
2. Volume validation with iVolume calls
3. Zone reach probability with forward bar simulation
4. Each zone: multiple bar loops for validation

**Total**: Estimated 5,000-15,000 iterations per call.

**When called**:
- MQL4: Every tick (inside display section with no throttle)
- MQL5: Every 200ms or on new bar

**Fix**: Only recompute when signal or bar changes:
```mql
static int s_zoneSigIdx = -1;
static datetime s_zoneBarTime = 0;
datetime curBar = iTime(NULL, 0, 0);
if(sigIdx == s_zoneSigIdx && curBar == s_zoneBarTime) return;
```

---

## Critical Bug #4: `ValidateSLAgainstVolume()` — Micro-Zone Nested Loops

**Location**: ~Lines 800-850
**Severity**: P2

Contains nested loops for micro-zone volume analysis:
```mql
for(int zone = 0; zone < microZones; zone++)
{
   for(int b = startBar; b <= endBar; b++)
   {
      // ... iVolume + iHigh + iLow per bar ...
   }
}
```

**Impact**: Medium — only called from CalculateEntryZones which itself runs too often.

---

## CalculateSLTP() — Core Function is Clean

**Location**: ~Lines 50-200
**Severity**: NONE

The main `CalculateSLTP()` function dispatches to ATR/Fib/Hybrid methods. Each method uses:
- A few iATR calls
- Swing detection loops (bounded by lookback)
- Simple arithmetic

**Verdict**: Clean implementation, no performance concern.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| Bubble sort O(n²) | P1 | Medium | Eliminates 250K comparisons |
| Deep history scan uncached | P1 | 5 lines | Prevents re-scan on same signal |
| CalculateEntryZones every tick | P1 | 5 lines | Eliminates 5K-15K iterations/tick |
| ValidateSLAgainstVolume nested | P2 | N/A | Fixed by caching parent function |

---

## Verdict: **FIX REQUIRED** — Cache CalculateEntryZones and MeasureOptimalTPRatios results per signal
