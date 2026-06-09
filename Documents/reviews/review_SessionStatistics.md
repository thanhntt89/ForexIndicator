# Latency Review: SessionStatistics.mqh

**File**: `Include/RSI_Advanced/SessionStatistics.mqh` (~488 lines)
**Role**: Session-based win rate tracking, outcome monitoring, CSV persistence, binary snapshot
**Severity**: **MEDIUM** — per-tick outcome scanning + incremental ArrayResize

---

## Critical Bug #1: `CheckPendingOutcomes()` — Full Outcome Scan Every Tick

**Location**: Lines 198-265
**Severity**: P1

```mql
void CheckPendingOutcomes()
{
   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome != 0) continue;  // Skip resolved
      
      int sigBarShift = iBarShift(NULL, 0, g_outcomes[i].signalTime, false);
      // Scan from signal to current
      for(int b = sigBarShift - 1; b >= 0; b--)
      {
         double barHigh = iHigh(NULL, 0, b);
         double barLow  = iLow(NULL, 0, b);
         // ... TP/SL check ...
      }
   }
}
```

**Problem**: Called every tick. For each pending outcome, scans ALL bars from signal time to current bar. With 20 pending outcomes × 100 bars each = 2,000 iHigh/iLow calls per tick.

**Impact**: On M1 with many unresolved signals, this adds significant overhead.

**Fix**: Only scan the latest bar (shift=0) for each pending outcome on normal ticks. Full historical scan only on new bar:
```mql
void CheckPendingOutcomes()
{
   static datetime s_lastFullScan = 0;
   datetime curBar = iTime(NULL, 0, 0);
   bool fullScan = (curBar != s_lastFullScan);
   if(fullScan) s_lastFullScan = curBar;
   
   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome != 0) continue;
      
      if(fullScan)
      {
         // Full bar-by-bar scan (existing logic)
      }
      else
      {
         // Quick check: only current bar (shift=0)
         double barHigh = iHigh(NULL, 0, 0);
         double barLow  = iLow(NULL, 0, 0);
         // ... TP/SL check against current bar only ...
      }
   }
}
```

---

## Critical Bug #2: `TrackSignalForSession()` — Incremental ArrayResize + Linear Dedup

**Location**: Lines 165-191
**Severity**: P2

```mql
void TrackSignalForSession(...)
{
   // Linear dedup scan
   for(int i = 0; i < g_outcomeCount; i++)
      if(g_outcomes[i].signalTime == signalTime && ...) return;
   
   g_outcomeCount++;
   ArrayResize(g_outcomes, g_outcomeCount);  // Realloc every time
}
```

**Problem**: Same pattern as `StoreSignal()` — incremental ArrayResize without reserve.

**Fix**:
```mql
ArrayResize(g_outcomes, g_outcomeCount, 64);  // Reserve 64 extra slots
```

---

## Critical Bug #3: `LoadSessionStatsFromOutcomesCSV()` — File I/O + Incremental ArrayResize

**Location**: Lines 381-453
**Severity**: P2 (OnInit only)

Each CSV row triggers:
1. String parsing (9 fields)
2. `ParseOutcomeSignalID()` with string operations
3. `ArrayResize(g_outcomes, g_outcomeCount)` — incremental

**Impact**: On first load with 200+ outcomes, this means 200 realloc operations.

**Fix**: Pre-count lines or use reserve:
```mql
ArrayResize(g_outcomes, g_outcomeCount, 256);
```

---

## Observation: `UpdateSessionStats()` is Efficient

**Location**: Lines 81-137

Uses static counter `s_lastProcessedCount` to skip if no new resolved outcomes — good optimization.

---

## Observation: Binary Snapshot (Save/Load) is Efficient

**Location**: Lines 466-487

`FileWriteStruct` / `FileReadStruct` — single I/O operation for the entire SessionStats struct. Much faster than CSV parsing. Good design.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| CheckPendingOutcomes every tick | P1 | 15 lines | Reduces 2K+ iHigh/iLow calls to ~20 |
| TrackSignalForSession ArrayResize | P2 | 1 line | Eliminates realloc per signal |
| CSV load incremental ArrayResize | P2 | 1 line | Faster startup |

---

## Verdict: **FIX REQUIRED** — CheckPendingOutcomes needs tick-optimized fast path
