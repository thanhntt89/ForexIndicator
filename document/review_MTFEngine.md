# Latency Review: MTFEngine.mqh

**File**: `Include/RSI_Advanced/MTFEngine.mqh` (~135 lines)
**Role**: Multi-Timeframe analysis — RSI calculation on 6 higher timeframes, agreement scoring
**Severity**: **HIGH** — multiple cross-timeframe iRSI calls per tick

---

## Critical Bug #1: `CalculateMTF_SMA_RSI_Shifted()` — iRSI Loop per Timeframe

**Location**: Lines ~10-35
**Severity**: P1 — HOT PATH, called 6× per `RefreshMTFData()`

```mql
double CalculateMTF_SMA_RSI_Shifted(int tf, int smaPeriod, int shiftBars)
{
   double sum = 0;
   for(int i = shiftBars; i < shiftBars + smaPeriod; i++)
   {
      double rsi = iRSI(NULL, tf, InpRSIPeriod, PRICE_CLOSE, i);
      if(rsi <= 0) return(EMPTY_VALUE);
      sum += rsi;
   }
   return(sum / smaPeriod);
}
```

**Problem**: For each of 6 timeframes, this function calls `iRSI()` in a loop of `smaPeriod` iterations.
- With default `InpFastMAPeriod=5`, `InpSignalMAPeriod=9`, `InpBBPeriod=20`:
  - `CheckAndAddMTF()` calls this function 3× (green, red, orange SMA)
  - Per timeframe: 3 × (5 + 9 + 20) = 102 iRSI calls
  - 6 timeframes: **612 iRSI calls per RefreshMTFData()**

**MQL4 Impact**: Each iRSI() is O(1) after initial calc — acceptable but still 612 function calls.
**MQL5 Impact**: For non-current-TF, each iRSI() does a `CopyBuffer()` call (no batch cache for other TFs). **612 CopyBuffer calls = severe overhead.**

**Fix (MQL5 priority)**:
```mql
// Batch: CopyBuffer once per timeframe, then index locally
double rsiBuffer[];
int handle = GetCachedIndicatorHandle(...);
CopyBuffer(handle, 0, 0, smaPeriod + shiftBars + 1, rsiBuffer);
// Then compute SMA from rsiBuffer[] — eliminates 100+ CopyBuffer calls per TF
```

---

## Critical Bug #2: `RefreshMTFData()` Runs Every Tick (MQL4)

**Location**: Called from `OnCalculate()` in both mq4 and mq5
**Severity**: P0 in MQL4, P2 in MQL5

**MQL4** (`RSI_Advanced.mq4` line 471): `RefreshMTFData()` is called without any throttle in the display section — runs on every single tick.

**MQL5** (`RSI_Advanced.mq5` line 558): Throttled by 200ms timer AND `isNewBar || forceRedraw` guard — correct.

**Impact**: On M1 XAUUSD with ~4 ticks/second, MQL4 fires 612 iRSI calls × 4 = **~2,448 iRSI calls per second** for MTF alone.

**Fix for MQL4**: Add new-bar guard:
```mql
// In mq4 display section, replace:
if(InpShowMTF) RefreshMTFData();
// With:
if(InpShowMTF && isNewBar) RefreshMTFData();
```

---

## Critical Bug #3: MTF Data Not Cached Between Ticks

**Problem**: `g_mtfData[6]` is recalculated from scratch every call. No stale-check logic.

**Impact**: MTF data changes only on new bars of the higher timeframe (e.g., H4 MTF data only changes every 4 hours). Recalculating every tick is wasted work.

**Fix**: Add timestamp-based cache per timeframe:
```mql
struct MTFStatus {
   // ... existing fields ...
   datetime lastCalcTime;  // Add: when was this TF last computed
};

void CheckAndAddMTF(int tf)
{
   datetime htfBar = iTime(NULL, tf, 0);
   if(g_mtfData[g_mtfCount].lastCalcTime == htfBar) return;  // No change
   // ... existing calculation ...
   g_mtfData[g_mtfCount].lastCalcTime = htfBar;
}
```

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| iRSI loop per TF (MQL5) | P1 | Medium | Eliminates ~600 CopyBuffer calls/tick |
| No tick throttle (MQL4) | P0 | 1 line | Eliminates ~2400 calls/sec on M1 |
| No HTF cache invalidation | P1 | 5 lines | Prevents recomputing unchanged TF data |

---

## Verdict: **FIX REQUIRED** — MQL4 tick throttle is the highest-priority 1-line fix
