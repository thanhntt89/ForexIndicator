# Latency Review: MQLCompat.mqh

**File**: `Include/RSI_Advanced/MQLCompat.mqh` (~603 lines)
**Role**: MQL4→MQL5 compatibility layer — wraps iRSI, iATR, iClose, iHigh, iLow, iVolume, iTime, iBarShift, MarketInfo, DeleteObjectsByPrefix
**Severity**: LOW — Well-designed batch cache system

---

## Critical Bugs: NONE — This file is one of the best-engineered components

---

## Positive Analysis: Batch Price Cache (Excellent Design)

### Architecture
```
_RefreshPriceCache()
├── CopyClose → _cache_close[]     ┐
├── CopyHigh → _cache_high[]       │ All 6 arrays cached
├── CopyLow → _cache_low[]         │ in ONE refresh per tick
├── CopyOpen → _cache_open[]       │
├── CopyTickVolume → _cache_volume[]│
└── CopyTime → _cache_time[]       ┘

_RefreshRSICache(handle) → _cache_rsi[]   // Separate indicator cache
_RefreshATRCache(handle) → _cache_atr[]   // Separate indicator cache
```

### Key Design Decisions (All Correct):
1. **Tick-based invalidation**: `_cache_tick = GetTickCount()` prevents double-refresh per tick
2. **10,000 bar limit**: `copyCount = MathMin(totalBars, 10000)` prevents excessive memory
3. **Current-symbol fast path**: Uses cache only for `_Symbol + _Period`, fallback for cross-symbol
4. **Handle cache**: Linear search but small array (typically <20 entries) — acceptable

---

## Observations

### 1. `iBarShift()` Linear Scan for Current Symbol
**Location**: Lines 417-452

```mql
// Use cache for current symbol/TF
for(int i = 0; i < _cache_size; i++)
{
   if(_cache_time[i] <= time)
      return(i);
}
```

**Analysis**: Linear scan of up to 10,000 cached times. Since the cache is sorted (descending, series-order), this is worst-case O(10,000).

**Fix (optional)**: Binary search would reduce to O(log n) ≈ 13 comparisons:
```mql
// Binary search on sorted series-order time array
int lo = 0, hi = _cache_size - 1;
while(lo <= hi)
{
   int mid = (lo + hi) / 2;
   if(_cache_time[mid] == time) return mid;
   if(_cache_time[mid] > time) lo = mid + 1;
   else hi = mid - 1;
}
return(exact ? -1 : lo);
```

**Impact**: LOW — iBarShift is not called in hot loops (only CheckPendingOutcomes and some display functions).

### 2. Handle Cache Linear Search
**Location**: Lines 95-115

```mql
for(int i = 0; i < g_handleCacheCount; i++)
   if(g_handleCache[i].key == key) return(g_handleCache[i].handle);
```

String comparison in a linear scan. Cache typically has <20 entries, so O(20) with string comparison is acceptable.

### 3. `InvalidatePriceCache()` Design
- Called at start of `OnCalculate()` in MQL5
- Forces refresh of all caches
- Correct — ensures fresh data each calculation cycle

### 4. `Bars` Macro
```mql
#define Bars _compat_GetBars()
```
Every `Bars` reference calls `::Bars(_Symbol, _Period)`. Used in loop conditions throughout the codebase — each access is a function call.

**Impact**: LOW per call, but used in many places.

**Fix**: Cache `Bars` at the start of OnCalculate:
```mql
int g_cachedBars = 0;
// In OnCalculate:
g_cachedBars = Bars;
// Replace Bars references in loops with g_cachedBars
```

---

## Verdict: **PASS — Excellent engineering**. The batch cache system is the right approach for MQL5 performance. Minor optimizations possible (binary search in iBarShift, Bars caching) but not critical.
