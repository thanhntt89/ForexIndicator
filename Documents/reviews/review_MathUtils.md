# Latency Review: MathUtils.mqh

**File**: `Include/RSI_Advanced/MathUtils.mqh` (~212 lines)
**Role**: SMA, StdDev, timeframe utilities, dynamic bar count calculations, probability bar display
**Severity**: LOW — utility functions with acceptable performance

---

## Critical Bugs: NONE

All functions are lightweight with bounded loops.

---

## Observations

### 1. `DeleteObjectsByPrefix()` — O(n) Full Chart Scan

**Location**: Lines 64-73 (MQL4 version), also in MQLCompat.mqh (MQL5 version)
**Severity**: P2 — Called 5× during fullRecalc (ARROW, LINE, PANEL, PROB, ZONE)

```mql
for(int i = ObjectsTotal() - 1; i >= 0; i--)
{
   string name = ObjectName(i);
   if(StringFind(name, prefix) == 0)
      ObjectDelete(name);
}
```

**Problem**: Each call iterates ALL chart objects, not just indicator objects. If chart has 500 objects (from other indicators/EAs), each DeleteObjectsByPrefix call scans all 500. Called 5× during fullRecalc = 2500 string comparisons.

**Impact**: LOW on clean charts, MODERATE on busy charts with many objects from other tools.

**Fix**: MQL4/5 provides `ObjectsDeleteAll()` with prefix parameter:
```mql
void DeleteObjectsByPrefix(string prefix)
{
   ObjectsDeleteAll(0, prefix);  // Built-in prefix delete, faster than manual loop
}
```
This is ~3-5× faster on charts with many objects.

### 2. `GetEffectiveProbMaxBars()` auto-scales to 30,000 bars
- Line 150: `MathMin(autoMax, 30000)` — on M1 this could pass 30K bars to the probability engine
- **Impact**: Upstream consumers (ProbabilityEngine) will loop over all these bars
- **Recommendation**: Cap at 10000 for M1, 15000 for M5 to prevent runaway computation

### 3. `CalculateSMA()` and `CalculateStdDev()` are clean
- Simple loops, bounded by period parameter
- No issues

### 4. `ProbBar()` — String concatenation in loop
- 10-iteration loop building a visual bar string
- **Impact**: Negligible — only called for display

---

## Verdict: MINOR FIX — Use ObjectsDeleteAll() for prefix deletion
