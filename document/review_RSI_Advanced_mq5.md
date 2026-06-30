# Latency Review: RSI_Advanced.mq5

**File**: `RSI_Advanced.mq5` (~648 lines)
**Role**: MQL5 main entry point — OnInit, OnDeinit, OnCalculate, OnChartEvent
**Severity**: **MEDIUM** — Has display throttle but still runs some heavy ops too often

---

## Architecture: Significantly Better Than MQL4

The MQL5 version implements a proper display throttle system:

```mql
// 5 force-redraw conditions:
if(g_activeSignalIndex != s_lastDrawSignalIdx) forceRedraw = true;  // New signal
if(signalInvalidated != s_lastInvalidated) forceRedraw = true;      // State change
if(isNewBar) forceRedraw = true;                                     // New bar
if(priceDelta > activeSig.atrValue * 0.1) forceRedraw = true;      // Price moved
if(!forceRedraw && (currentTick - s_lastDrawTick) < 200) { /* skip */ }
```

This reduces display updates from ~4/sec to ~5-10 per bar on M1. **Well-designed**.

---

## Critical Bug #1: `CalculateProbability()` Still Runs on Every Redraw

**Location**: Line 559
**Severity**: P1

```mql
if(InpShowProbability) CalculateProbability(g_activeSignalIndex);
```

Even with the 200ms throttle, `CalculateProbability()` runs 5+ times per minute. Each call does 50,000+ iterations.

**Fix**: Add signal-change + new-bar guard:
```mql
static int s_probLastSigIdx = -1;
static datetime s_probLastBar = 0;
bool probNeedsRefresh = (g_activeSignalIndex != s_probLastSigIdx) || isNewBar;
if(InpShowProbability && probNeedsRefresh)
{
   CalculateProbability(g_activeSignalIndex);
   s_probLastSigIdx = g_activeSignalIndex;
   s_probLastBar = currentBarTime;
}
```

---

## Critical Bug #2: "Lightweight Every Tick" Section Contains Heavy Operations

**Location**: Lines 466-470
**Severity**: P1

```mql
// Lightweight: every tick
RefreshIntermarketData();     // 40 iClose calls on cross-symbol
CheckPendingOutcomes();       // O(pending × bars) scan
CheckAndLogNewlyResolved();   // Iterates all outcomes
UpdateSpreadRegime();         // 50 iATR calls ← NOT LIGHTWEIGHT
```

`UpdateSpreadRegime()` does 50 iATR calls — mislabeled as "lightweight".

**Fix**: Move `UpdateSpreadRegime()` and `RefreshIntermarketData()` to the new-bar section:
```mql
if(isNewBar)
{
   UpdateSpreadRegime();
   RefreshIntermarketData();
   // ... existing new-bar operations ...
}
```

---

## Critical Bug #3: Missing `LogSignalEntry()` / `LogOutcomePending()` in MQ5

**Location**: MQ5 signal detection block (lines 396-437)
**Severity**: P2 — Data loss

Comparing MQ4 (lines 367-371):
```mql
// MQ4 has:
LogSignalEntry(time[i], buySignal, true, entryPrice, sl, tp1, tp2, tp3, atrVal,
               GetSessionBlock(time[i]), angleZ);
LogOutcomePending(time[i], buySignal, true);
```

MQ5 signal detection block does NOT call `LogSignalEntry()` or `LogOutcomePending()`. Signals detected in MQ5 are never logged to CSV.

**Fix**: Add the same logging calls to the MQ5 signal detection block:
```mql
if(buySignal > 0)
{
   // ... existing StoreSignal/TrackSignalForSession ...
   LogSignalEntry(time[i], buySignal, true, entryPrice, sl, tp1, tp2, tp3, atrVal,
                  GetSessionBlock(time[i]), angleZ);
   LogOutcomePending(time[i], buySignal, true);
}
```

---

## Critical Bug #4: `InvalidatePriceCache()` at Start of OnCalculate

**Location**: Line 204-205
**Severity**: NONE (correct design)

```mql
#ifdef __MQL5__
InvalidatePriceCache();  // Force refresh at start of each OnCalculate
#endif
```

This is correct — ensures fresh data per OnCalculate cycle. The batch cache then refreshes lazily on first use.

---

## Observation: OnDeinit Properly Releases Handles

```mql
ReleaseAllHandles();  // Releases all indicator handles — prevents resource leak
```

MQL4 version has `#ifdef __MQL5__` guard for this — correct.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| CalculateProbability on every redraw | P1 | 5 lines | Reduces 50K iterations to per-bar only |
| UpdateSpreadRegime "lightweight" | P1 | 1 line | Move to per-bar section |
| Missing LogSignalEntry in MQ5 | P2 | 4 lines | Fix data loss — no CSV logging in MQ5 |
| RefreshIntermarketData per tick | P2 | 1 line | Move to per-bar section |

---

## Verdict: **FIX REQUIRED** — MQ5 is well-architected but needs: (1) probability caching per signal, (2) move spread/intermarket to per-bar, (3) add missing signal logging.
