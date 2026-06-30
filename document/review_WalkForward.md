# Latency Review: WalkForward.mqh

**File**: `Include/RSI_Advanced/WalkForward.mqh` (~432 lines)
**Role**: Walk-Forward IS/OOS validation, rolling performance tracker, regime stability check, spread regime
**Severity**: **MEDIUM** — contains O(n²) loop and per-tick ATR scans

---

## Critical Bug #1: `CalculateWalkForwardMetrics()` — O(n²) Signal-Outcome Matching

**Location**: Lines 52-121
**Severity**: P1

```mql
for(int i = 0; i < g_outcomeCount; i++)  // Outer: all outcomes
{
   // ... 
   for(int s = 0; s < g_signalCount; s++)  // Inner: all signals
   {
      if(g_signals[s].signalTime == g_outcomes[i].signalTime)
      {
         isInSample = (s < splitIndex);
         break;
      }
   }
}
```

**Problem**: For each outcome, linearly searches ALL signals to find matching time. With 200 outcomes × 500 signals = 100,000 comparisons.

**Impact**: Called once per new bar — not catastrophic, but wasteful.

**Fix**: Since signals and outcomes are time-ordered, use binary search or index lookup:
```mql
// Optimization: outcomes share signalTime with signals.
// Since both arrays are time-ordered, use two-pointer technique:
int sIdx = 0;
for(int i = 0; i < g_outcomeCount; i++)
{
   while(sIdx < g_signalCount && g_signals[sIdx].signalTime < g_outcomes[i].signalTime)
      sIdx++;
   if(sIdx < g_signalCount && g_signals[sIdx].signalTime == g_outcomes[i].signalTime)
      isInSample = (sIdx < splitIndex);
}
```
This reduces O(n×m) to O(n+m).

---

## Critical Bug #2: `CheckRegimeStability()` — 100 iATR Calls

**Location**: Lines 283-318
**Severity**: P2

```mql
for(int i = 1; i <= 100 && i < Bars; i++)
{
   avgATR += iATR(NULL, 0, 14, i);
   atrCnt++;
}
```

**Problem**: 100 iATR calls per invocation.

**Worse**: `GetRegimeColor()` calls `CheckRegimeStability()` — and `GetRegimeColor()` is called from `DrawInfoPanel()`. So on MQL4, this fires every tick.

**Impact**: 100 iATR calls per tick (MQL4) in the draw path.

**Fix**: Cache per bar:
```mql
static datetime s_regimeBar = 0;
static string s_regimeResult = "";
datetime curBar = iTime(NULL, 0, 0);
if(curBar == s_regimeBar) return s_regimeResult;
s_regimeBar = curBar;
```

---

## Critical Bug #3: `UpdateSpreadRegime()` — 50 iATR Calls Every Tick

**Location**: Lines 341-393
**Severity**: P1

```mql
// Called from "Lightweight: every tick" section
void UpdateSpreadRegime()
{
   // ... 
   for(int i = 1; i <= 50 && i < Bars; i++)
   {
      avgATR += iATR(NULL, 0, 14, i);  // 50 iATR calls
   }
}
```

**Problem**: Marked as "lightweight" in the main loop, but actually does 50 iATR calls per tick.

**Impact**: 50 iATR calls × 4 ticks/sec (M1) = **200 iATR calls per second** just for spread regime.

**Fix**: Move to new-bar section:
```mql
// In main OnCalculate(), move from "every tick" to "per new bar":
if(isNewBar)
{
   UpdateSpreadRegime();  // Only needed per bar, not per tick
   // ...
}
```

---

## Observation: `CalculateRollingPerformance()` is Efficient
- Single loop over `g_outcomes[]` — O(n)
- Called once per new bar
- No API calls — just arithmetic on stored data
- Well-designed with static counter optimization

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| WalkForward O(n²) matching | P1 | 10 lines | Reduces 100K to O(n+m) |
| CheckRegimeStability 100 iATR | P2 | 5 lines | Eliminates 100 calls per tick |
| UpdateSpreadRegime every tick | P1 | 1 line | Move to per-bar; saves 200 calls/sec |

---

## Verdict: **FIX REQUIRED** — Move UpdateSpreadRegime to per-bar section; cache CheckRegimeStability
