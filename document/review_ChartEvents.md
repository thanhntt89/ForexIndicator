# Latency Review: ChartEvents.mqh

**File**: `Include/RSI_Advanced/ChartEvents.mqh` (~106 lines)
**Role**: Handle arrow clicks and panel drag events
**Severity**: **MEDIUM** — arrow click triggers heavy recomputation

---

## Critical Bug #1: Arrow Click Triggers Full Probability Recalculation

**Location**: Lines 36-44
**Severity**: P1

```mql
if(id == CHARTEVENT_OBJECT_CLICK)
{
   if(StringFind(sparam, PREFIX_ARROW) == 0)
   {
      g_activeSignalIndex = sigIdx;
      if(InpShowMTF) RefreshMTFData();          // ← 612 iRSI calls
      if(InpShowProbability) CalculateProbability(sigIdx); // ← 50K+ iterations
      DrawInfoPanel(sigIdx);                    // ← MeasureEdgeFromHistory
      DrawSLTPLines(sigIdx);
   }
}
```

**Problem**: On a single arrow click, three heavy operations fire synchronously:
1. `RefreshMTFData()` — 612 iRSI calls
2. `CalculateProbability()` — 50,000+ iterations
3. `DrawInfoPanel()` → `MeasureEdgeFromHistory()` — 10,000+ iterations

**Impact**: Visible 0.5-2 second freeze on click, especially on M1/M5 charts.

**Fix**: This is acceptable for an explicit user action (click). The user expects a brief computation. However, showing a "Calculating..." placeholder first would improve perceived responsiveness:
```mql
// Show loading state immediately
DrawInfoPanel_Loading(sigIdx);
ChartRedraw();
// Then compute
if(InpShowMTF) RefreshMTFData();
if(InpShowProbability) CalculateProbability(sigIdx);
DrawInfoPanel(sigIdx);
```

---

## Observation: Panel Drag Throttle is Well-Implemented

**Location**: Lines 60-75
**Severity**: NONE

```mql
static uint s_lastDrag = 0;
uint now = GetTickCount();
if(now - s_lastDrag > 40)  // 25 FPS cap
{
   s_lastDrag = now;
   DrawInfoPanel(g_activeSignalIndex);
}
```

**Verdict**: 40ms throttle (25 FPS) is correct for drag smoothness without excessive CPU usage.

---

## Observation: ChartSetInteger CHART_MOUSE_SCROLL Control

**Location**: Lines 83-84, 98, 102
**Severity**: NONE

Correctly disables chart scroll during panel drag and re-enables on release. Clean implementation.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| Arrow click triggers heavy compute | P1 | Low | Acceptable for user action; add loading indicator |
| Panel drag throttle | NONE | N/A | Already well-implemented at 25 FPS |

---

## Verdict: MINOR — Arrow click delay is acceptable for explicit user action. Consider loading indicator for UX.
