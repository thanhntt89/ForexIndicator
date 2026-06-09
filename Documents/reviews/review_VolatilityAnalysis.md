# Latency Review: VolatilityAnalysis.mqh

**File**: `Include/RSI_Advanced/VolatilityAnalysis.mqh` (~77 lines)
**Role**: BB width percentile, ATR state, volatility confirmation scoring
**Severity**: LOW-MEDIUM

---

## Critical Bug #1: `GetATRState()` — 50 iATR Calls

**Location**: Lines 34-46
**Severity**: P2

```mql
double GetATRState(int barShift)
{
   double curATR = iATR(NULL, 0, InpATRPeriod, barShift);
   double avgATR = 0;
   for(int j = barShift + 1; j <= barShift + 50 && j < Bars; j++)
   {
      avgATR += iATR(NULL, 0, InpATRPeriod, j);  // 50 iATR calls
      cnt++;
   }
}
```

**Problem**: 50 iATR calls per invocation. In MQL5, each non-cached iATR call is a CopyBuffer.
For current symbol/TF, the batch cache handles this. For other scenarios, it's 50 API calls.

**Impact**: Called from `GetVolatilityConfirmation()` during signal scoring — not per-tick. Acceptable.

**Fix**: Could cache ATR state per bar, but given it's not in the hot path, this is low priority.

---

## Observation: `GetBBWidthPercentile()` is Efficient
- Uses pre-computed BufferBBUpper/Lower values
- Loop of `lookback` (default 50) iterations — simple comparisons
- No API calls — just buffer reads

---

## Verdict: PASS — Acceptable performance. GetATRState could be cached but not critical.
