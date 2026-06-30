# Latency Review: Normalize.mqh

**File**: `Include/RSI_Advanced/Normalize.mqh` (~656 lines)
**Role**: Instrument detection, pip normalization, GMT offset, angle thresholds, spread buffer, market corrections, edge measurement, trade recommendation
**Severity**: **HIGH** — Contains multiple heavy scan functions

---

## Critical Bug #1: `MeasureEdgeFromHistory()` — Heavy Scan Called from Panel Draw

**Location**: ~Lines 400-550
**Severity**: P0 — THE function that makes PanelDrawing slow

```mql
double MeasureEdgeFromHistory(int caseNum, bool isBuy, ...)
{
   // Scan stored signals
   for(int i = 0; i < g_signalCount; i++)
   {
      // Forward-simulate each matching signal
      for(int f = 1; f <= maxForward; f++)
      {
         // ... iHigh, iLow per bar ...
      }
   }
   
   // Scan deep history
   int deepMax = MathMin(samples * 5, 2000);
   for(int i = startSearch; i < deepMax; i++)
   {
      double rsi = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, i);
      double atr = iATR(NULL, 0, InpATRPeriod, i);
      // ... match + forward simulate ...
   }
   
   // Wilson Score Bayesian combination
   // ...
}
```

**Problem**: This function scans up to 2000 bars with iRSI/iATR per bar, plus forward simulation for each match. Then called from `DrawInfoPanel()` which runs every tick in MQL4.

**Impact**: 10,000-50,000 iterations per call × 4 calls/sec (MQL4 M1) = **40,000-200,000 iterations/sec**.

**Fix**: Cache result per signal + bar:
```mql
static int     s_edgeCachedSig = -1;
static datetime s_edgeCachedBar = 0;
static double  s_edgeCachedResult = 0;

double MeasureEdgeFromHistory(...)
{
   datetime curBar = iTime(NULL, 0, 0);
   if(caseNum_sig == s_edgeCachedSig && curBar == s_edgeCachedBar)
      return s_edgeCachedResult;
   // ... compute ...
   s_edgeCachedResult = result;
   return result;
}
```

---

## Critical Bug #2: `GetFatTailPenalty()` — 500-Bar Loop

**Location**: ~Lines 550-580
**Severity**: P2

```mql
double GetFatTailPenalty()
{
   for(int i = 0; i < 500; i++)
   {
      double ret = (iClose(NULL, 0, i) - iClose(NULL, 0, i+1)) / iClose(NULL, 0, i+1);
      // ... kurtosis calculation ...
   }
}
```

**Impact**: 500 × iClose calls (cached in MQL5, but still 500 loop iterations).

**Fix**: Cache per bar (kurtosis changes only on new bar):
```mql
static datetime s_fatTailBar = 0;
static double s_fatTailResult = 0;
if(iTime(NULL, 0, 0) == s_fatTailBar) return s_fatTailResult;
```

---

## Critical Bug #3: `GetVolClusterPenalty()` — 200-Bar Loop

**Location**: ~Lines 580-610
**Severity**: P2

```mql
double GetVolClusterPenalty()
{
   for(int i = 0; i < 200; i++)
   {
      double atr = iATR(NULL, 0, 14, i);
      // ... cluster detection ...
   }
}
```

**Impact**: 200 iATR calls per invocation.

**Fix**: Same caching pattern as above.

---

## Critical Bug #4: `DetectInstrumentType()` — String Matching on Every Call

**Location**: ~Lines 10-80
**Severity**: P2

```mql
ENUM_INSTRUMENT_TYPE DetectInstrumentType()
{
   string sym = Symbol();
   // ... multiple StringFind checks ...
}
```

**Problem**: Called from many places (session filter, normalization, etc.) and does string matching every time. The instrument type NEVER changes during a session.

**Fix**: Cache on first call:
```mql
static ENUM_INSTRUMENT_TYPE s_cachedType = -1;
if(s_cachedType >= 0) return s_cachedType;
// ... detection logic ...
s_cachedType = result;
return result;
```

---

## Observation: `GetTradeRecommendation()` is Clean

**Location**: ~Lines 600-656
**Severity**: NONE

Multi-factor scoring function with no loops — just arithmetic on pre-computed values. Well-designed.

---

## Observation: `CombineTheoreticalHistorical()` is Efficient

Wilson Score Bayesian combination — O(1) computation. No issues.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| MeasureEdgeFromHistory uncached | P0 | 5 lines | Eliminates 40K-200K iterations/sec |
| GetFatTailPenalty 500-bar loop | P2 | 3 lines | Cache per bar |
| GetVolClusterPenalty 200-bar loop | P2 | 3 lines | Cache per bar |
| DetectInstrumentType uncached | P2 | 3 lines | Eliminate string matching per call |

---

## Verdict: **CRITICAL FIX REQUIRED** — MeasureEdgeFromHistory caching is essential
