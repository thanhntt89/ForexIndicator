# Latency Review: PanelDrawing.mqh

**File**: `Include/RSI_Advanced/PanelDrawing.mqh` (~733 lines)
**Role**: Info panel rendering — the largest UI component with signal details, probability, MTF, zones
**Severity**: **P0 CRITICAL** — heavy computation embedded in UI render function

---

## Critical Bug #1: `MeasureEdgeFromHistory()` Called Inside Panel Draw

**Location**: ~Line 572
**Severity**: P0 — SYSTEM-CRITICAL

```mql
void DrawInfoPanel(int sigIdx)
{
   // ... 500+ lines of panel setup ...
   
   // Inside the active-signal branch:
   double edgeData = MeasureEdgeFromHistory(...);  // ← HEAVY COMPUTATION
   
   // ... more panel lines ...
}
```

**What `MeasureEdgeFromHistory()` does:**
1. Scans ALL stored signals simulating outcomes
2. Scans up to 2000 bars of deep history for ATR-based pattern matching
3. For each match: forward-simulates bar-by-bar
4. Computes Wilson Score Bayesian interval

**Total**: Estimated 10,000-50,000 iterations per call.

**When it runs:**
- MQL4: EVERY TICK (no throttle on DrawInfoPanel)
- MQL5: Every 200ms

**Impact**: This single call makes `DrawInfoPanel()` a computational bottleneck disguised as a UI function.

**Fix**: Move `MeasureEdgeFromHistory()` out of the draw function. Pre-compute in the main loop and store in a global:
```mql
// In OnCalculate(), before DrawInfoPanel():
static double s_cachedEdge = 0;
if(isNewBar || forceRedraw)
   s_cachedEdge = MeasureEdgeFromHistory(...);

// In DrawInfoPanel():
double edgeData = s_cachedEdge;  // Use pre-computed value
```

---

## Critical Bug #2: Dozens of Object Create/Modify Calls Per Render

**Location**: Entire function
**Severity**: P1

`DrawInfoPanel()` creates/modifies approximately:
- 1 background rectangle
- 1 title bar
- 20-30 OBJ_LABEL text lines
- Each label: `ObjectCreate()` + 4-5 `ObjectSetInteger/String()` calls

**Total**: ~120-150 object API calls per panel render.

**Mitigation already present**: Static variable `s_lastLayout` detects layout changes to avoid unnecessary redraws — GOOD. But this only prevents redraw when layout is identical.

**Impact**: On MQL4 without throttle, 150 object calls per tick at 4 ticks/sec = **600 object calls/sec**.

**Fix**: The existing layout-change detection is a good pattern. Ensure it covers ALL branches (both no-signal and active-signal modes).

---

## Critical Bug #3: `ChartRedraw()` Called at End of DrawInfoPanel

**Location**: Last line of DrawInfoPanel()
**Severity**: P2

```mql
ChartRedraw();
```

**Problem**: Forces immediate chart repaint. Combined with being called every tick (MQL4), this causes the chart to flicker and increases CPU load.

**Fix**: Remove `ChartRedraw()` from the panel draw function. Let the terminal's natural repaint cycle handle it, or call it once at the end of `OnCalculate()`.

---

## Critical Bug #4: Panel Auto-Position Adjustment

**Location**: Lines ~700-720
**Severity**: P3 (Cosmetic)

```mql
if(!g_panelUserMoved)
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   g_panelPosX = chartW - InpPanelWidth - 20;
   // ...
}
```

**Problem**: Called every render to adjust position when user hasn't dragged. This causes the panel to jump when the chart window is resized.

**Impact**: LOW — purely cosmetic, but can be disorienting.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| MeasureEdgeFromHistory in draw | P0 | 10 lines | Eliminates 10K-50K iterations per tick |
| 150 object calls per render | P1 | N/A | Mitigated by existing layout cache |
| ChartRedraw per call | P2 | 1 line | Reduces chart repaint load |
| Panel auto-position | P3 | N/A | Cosmetic only |

---

## Verdict: **CRITICAL FIX REQUIRED** — Move MeasureEdgeFromHistory() out of the draw function immediately.
