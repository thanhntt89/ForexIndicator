# Latency Review: Globals.mqh

**File**: `Include/RSI_Advanced/Globals.mqh` (~194 lines)
**Role**: Global state variables, signal storage, panel position persistence, TP tracking
**Severity**: **HIGH** — contains performance-critical allocation patterns

---

## Critical Bug #1: `StoreSignal()` — Incremental ArrayResize

**Location**: Lines 91-109
**Severity**: P1 — CRITICAL for large signal counts

```mql
void StoreSignal(...)
{
   g_signalCount++;
   ArrayResize(g_signals, g_signalCount);  // ← Realloc EVERY signal
   ...
}
```

**Problem**: `ArrayResize()` without reserve parameter causes memory reallocation on every single signal. On a chart with 200+ signals, this means 200+ realloc operations during `fullRecalc`, each copying all existing data.

**Impact**: O(n²) total memory copies during full recalculation. On M1 charts with many signals, this causes a visible stutter.

**Fix**:
```mql
void StoreSignal(...)
{
   g_signalCount++;
   int currentSize = ArraySize(g_signals);
   if(g_signalCount > currentSize)
      ArrayResize(g_signals, g_signalCount, 128);  // Reserve 128 extra slots
   ...
}
```

---

## Critical Bug #2: `FindSignalByArrowName()` — Linear Backward Search

**Location**: Lines 111-125
**Severity**: P2 — Medium (only on arrow click)

```mql
for(int i = g_signalCount - 1; i >= 0; i--)
   if(g_signals[i].signalTime == sigTime && ...)
      return(i);
```

**Problem**: Linear scan of all signals on every arrow click. With 500+ signals, this adds noticeable click-to-response delay.

**Impact**: LOW in practice (user clicks are infrequent), but could be O(n) on large signal sets.

**Fix**: Since the search starts from the end and most clicks are on recent signals, the current backward iteration is acceptable. No change needed unless signal count exceeds 1000.

---

## Critical Bug #3: `UpdateTPHitStatus()` — MarketInfo Every Call

**Location**: Lines 171-193
**Severity**: P2 — Called from `DrawProbabilityLabels()` which runs frequently

```mql
double curPrice = (sig.isBuySignal)
   ? MarketInfo(Symbol(), MODE_BID)
   : MarketInfo(Symbol(), MODE_ASK);
```

**Problem**: `MarketInfo()` is a broker API call. Called from within the draw path every tick (in mq4) or every 200ms (in mq5).

**Impact**: Minor per-call, but adds up when called alongside other heavy operations in the same tick.

**Fix**: Pass `curPrice` as parameter from the caller which already has `iClose()` value, avoiding the extra MarketInfo call.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| StoreSignal ArrayResize | P1 | 1 line | Eliminates O(n²) realloc on fullRecalc |
| FindSignalByArrowName | P3 | N/A | Acceptable for current scale |
| UpdateTPHitStatus MarketInfo | P2 | 2 lines | Minor tick-level optimization |

---

## Verdict: FIX REQUIRED — ArrayResize reserve parameter is the priority fix
