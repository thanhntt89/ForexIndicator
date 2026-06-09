# Latency Review: SignalLogger.mqh

**File**: `Include/RSI_Advanced/SignalLogger.mqh` (~494 lines)
**Role**: CSV logging with in-memory queue (signals, scoring, outcomes)
**Severity**: LOW — Well-designed queue-based I/O

---

## Critical Bugs: NONE — Good implementation

---

## Positive Analysis: In-Memory Queue Pattern (Excellent)

### Architecture
```
Signal occurs → QueueSignalRow(row)     → s_signalQueue[]
Score computed → QueueScoringRow(row)    → s_scoringQueue[]
Outcome resolved → QueueOutcomeRow(row) → s_outcomeQueue[]

FlushLogQueues() → Write all queued rows to disk at once
```

This design correctly separates hot-path (signal detection) from I/O (file writing):
- No file I/O during signal detection loop
- Batch write via `FlushLogQueues()` — single file open/write/close per flush
- Queue pre-allocated with 128-slot chunks — avoids per-item ArrayResize

---

## Observations

### 1. Queue ArrayResize Uses 128-Slot Reserve (Good)
```mql
void QueueSignalRow(string row)
{
   if(s_signalQueueCount >= size)
      ArrayResize(s_signalQueue, size + 128);
}
```
**Verdict**: Correct — amortized O(1) insertion.

### 2. Duplicate `SL_GetTFName()` Function
- `SL_GetTFName()` in SignalLogger.mqh
- `SS_GetTFName()` in SessionStatistics.mqh
- `GetTimeframeString()` in MathUtils.mqh
- All three do the same thing (Period → string mapping)

**Impact**: Code duplication, not performance. But adds maintenance burden.

**Fix**: Use a single shared function. The comment in SessionStatistics says "avoids cross-include" — the real fix is to put TF name in MathUtils.mqh (which has no dependencies) and include it everywhere.

### 3. `FlushLogQueues()` File Open/Close Pattern
- Opens file, writes all queued rows, closes file
- `SL_OpenAppend()` checks existence, seeks to end — correct
- File I/O only on `FlushLogQueues()` call (per new bar or per fullRecalc) — correct timing

### 4. `LoggerInit(fullReset=true)` Deletes and Recreates Files
- Called during `fullRecalc` in MQL4 — destroys existing log files on TF switch
- **Impact**: User loses log data when switching timeframes
- **Fix**: Consider appending with dedup rather than deleting on fullRecalc

### 5. Backtest Mode Guard
```mql
if(IsBacktestMode()) return;
```
All logging functions skip in backtest — correct for performance, but means no backtest logging.

---

## Verdict: PASS — Well-engineered queue-based logging system. Minor code dedup opportunity.
