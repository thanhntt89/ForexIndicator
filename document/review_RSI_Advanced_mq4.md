# Latency Review: RSI_Advanced.mq4

**File**: `RSI_Advanced.mq4` (~534 lines)
**Role**: MQL4 main entry point — OnInit, OnDeinit, OnCalculate, OnChartEvent
**Severity**: **P0 CRITICAL** — THE file with the worst performance architecture

---

## Critical Bug #1: NO DISPLAY THROTTLE — Every Tick Fires Heavy Computation

**Location**: Lines 451-530 (Display Update section)
**Severity**: P0 — ROOT CAUSE of all MQL4 lag

```mql
// Lines 471-472: NO THROTTLE
if(InpShowMTF) RefreshMTFData();          // 612 iRSI calls
if(InpShowProbability) CalculateProbability(g_activeSignalIndex); // 50K+ iterations

// Lines 508-518: NO THROTTLE  
DrawInfoPanel(g_activeSignalIndex);       // MeasureEdgeFromHistory 10K+ iterations
DrawSLTPLines(g_activeSignalIndex, ...);  // Object create/delete
CalculateEntryZones(...);                 // 5K-15K iterations
DrawZoneLines(...);                       // Object create/delete
DrawProbabilityLabels(...);               // UpdateTPHitStatus + objects
```

**Total per tick (MQL4)**:
| Operation | Est. Iterations | iRSI/iATR Calls |
|-----------|-----------------|-----------------|
| RefreshMTFData | 612 | 612 |
| CalculateProbability | 50,000+ | 5,000+ |
| MeasureEdgeFromHistory | 10,000+ | 2,000+ |
| CalculateEntryZones | 5,000+ | 500+ |
| UpdateSpreadRegime | 50 | 50 |
| CheckPendingOutcomes | 2,000+ | 2,000+ |
| **TOTAL PER TICK** | **~70,000+** | **~10,000+** |

**At 4 ticks/sec on M1**: **~280,000 iterations/sec** and **~40,000 API calls/sec**.

**Compare MQL5** (`RSI_Advanced.mq5`): Has 200ms throttle + `isNewBar || forceRedraw` guard + `forceRedraw` conditions. MQL5 version is ~10-20× more efficient.

---

## Critical Bug #2: MQL4 Missing Display Throttle That MQL5 Has

**Direct Comparison**:

| Feature | MQL4 (mq4) | MQL5 (mq5) |
|---------|------------|------------|
| Display throttle | NONE | 200ms minimum |
| MTF refresh guard | NONE | `isNewBar \|\| forceRedraw` |
| Price movement check | NONE | ATR × 0.1 threshold |
| SLTP redraw cache | NONE | `s_sltpDrawn` flag |
| Zone redraw cache | NONE | `s_zonesDrawn` flag |
| Force redraw conditions | NONE | 5 specific conditions |

**The MQL5 version already has the correct architecture**. The MQL4 version needs to adopt it.

---

## Critical Bug #3: `CalculateEntryZones()` Runs Every Tick

**Location**: Lines 513-516
**Severity**: P0

```mql
CalculateEntryZones(
   activeSig.isBuySignal, activeSig.barIndex,
   activeSig.entryPrice, activeSig.stopLoss, activeSig.takeProfit1,
   activeSig.atrValue, high, low, rates_total);
DrawZoneLines(suppressDisplay);
```

Entry zones are price-based and only change when:
1. A new signal appears
2. A new bar forms (price structure changes)

Running zone calculation every tick is 100% wasted computation.

---

## Critical Bug #4: `fullRecalc` Logging Difference

**Location**: Line 197 (mq4) vs not present in mq5
**Severity**: P3

```mql
// mq4 line 197:
LoggerInit(true);  // Deletes and recreates log files on fullRecalc
```

MQL5 version does NOT call `LoggerInit(true)` on fullRecalc. This means MQL4 destroys log files when switching timeframes or when history is shortened, while MQL5 preserves them.

---

## Optimal Fix: Port MQL5 Display Throttle to MQL4

The following block from MQL5 should be added to MQL4 (lines 451+):

```mql
// Add these static variables at start of display section:
static uint    s_lastDrawTick = 0;
static double  s_lastDrawPrice = 0;
static int     s_lastDrawSignalIdx = -1;
static bool    s_lastInvalidated = false;
static bool    s_sltpDrawn = false;
static bool    s_zonesDrawn = false;

uint currentTick = GetTickCount();
bool forceRedraw = false;
if(g_activeSignalIndex != s_lastDrawSignalIdx) forceRedraw = true;
if(signalInvalidated != s_lastInvalidated) forceRedraw = true;
if(isNewBar) forceRedraw = true;
double priceDelta = MathAbs(curPrice - s_lastDrawPrice);
if(activeSig.atrValue > 0 && priceDelta > activeSig.atrValue * 0.1) forceRedraw = true;

if(!forceRedraw && (currentTick - s_lastDrawTick) < 200)
{
   // Skip redraw — nothing changed
}
else
{
   s_lastDrawTick = currentTick;
   s_lastDrawPrice = curPrice;
   // ... existing display code ...
}
```

**Effort**: ~30 lines copy-paste from mq5. **Impact**: 10-20× performance improvement.

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| No display throttle | P0 | 30 lines | 10-20× performance improvement |
| CalculateEntryZones every tick | P0 | Fixed by throttle | Eliminates 5K-15K iterations/tick |
| CalculateProbability every tick | P0 | Fixed by throttle | Eliminates 50K+ iterations/tick |
| RefreshMTFData every tick | P0 | Fixed by throttle | Eliminates 612 calls/tick |
| LoggerInit(true) on fullRecalc | P3 | 1 line | Preserve log files |

---

## Verdict: **CRITICAL FIX REQUIRED** — Port MQL5 display throttle to MQL4. This is the #1 highest-impact fix in the entire codebase, eliminating ~280,000 wasted iterations per second.
