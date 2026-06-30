# Latency Review: LineDrawing.mqh

**File**: `Include/RSI_Advanced/LineDrawing.mqh` (~268 lines)
**Role**: Draw SL/TP lines, price tags, probability labels, entry zone lines on main chart
**Severity**: **MEDIUM** — redundant object operations and uncached iATR calls

---

## Critical Bug #1: Duplicate iATR Calls

**Location**: `CreatePriceTag()` and `CreateProbLabel()`
**Severity**: P2

Both functions independently call:
```mql
double atr14 = iATR(NULL, 0, 14, 0);
```

When `DrawSLTPLines()` calls `CreatePriceTag()` 5× and `CreateProbLabel()` calls it again, that's 6+ redundant iATR calls in a single draw cycle.

**Fix**: Compute ATR once in the caller and pass as parameter:
```mql
void DrawSLTPLines(int sigIdx, bool dimMode = false)
{
   double atr14 = iATR(NULL, 0, 14, 0);  // Compute once
   CreatePriceTag(..., atr14);
   CreatePriceTag(..., atr14);
   // ...
}
```

---

## Critical Bug #2: Delete-Then-Create Pattern on Every Redraw

**Location**: All `Create*` functions
**Severity**: P2

```mql
void CreateHorizontalLine(string name, ...)
{
   ObjectDelete(name);     // Delete if exists
   ObjectCreate(name, OBJ_HLINE, 0, ...);  // Recreate
   // Set properties...
}
```

**Problem**: Even if the line hasn't changed, it's deleted and recreated. Each delete + create + property set = ~5 API calls per object. With 10+ objects per draw cycle, that's 50+ object API calls.

**Fix**: Check if object exists and only update changed properties:
```mql
void CreateHorizontalLine(string name, double price, color clr, ...)
{
   if(ObjectFind(name) >= 0)
   {
      // Just update price and color if changed
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      return;
   }
   // Create new only if doesn't exist
   ObjectCreate(name, OBJ_HLINE, 0, ...);
   // ... set all properties ...
}
```

---

## Critical Bug #3: `DrawProbabilityLabels()` Calls `UpdateTPHitStatus()`

**Location**: Inside `DrawProbabilityLabels()`
**Severity**: P2

```mql
void DrawProbabilityLabels(bool dimMode = false)
{
   UpdateTPHitStatus(g_activeSignalIndex);  // MarketInfo call inside
   // ... create label objects ...
}
```

`UpdateTPHitStatus()` calls `MarketInfo(MODE_BID/ASK)` — a broker API call inside a drawing function that runs every tick (MQL4) or every 200ms (MQL5).

**Fix**: Call `UpdateTPHitStatus()` once in the main loop before the draw section, not inside the drawing function.

---

## Critical Bug #4: `DrawZoneLines()` — Object Loop Without Cache

**Location**: Lines ~200-268
**Severity**: P2

Creates objects in a loop for each zone. On MQL4, this runs every tick, creating/deleting zone objects continuously.

**Impact**: On MQL4 with 5 zones × 3 objects each = 15 delete+create cycles per tick.

**Fix**: Add dirty flag to only redraw zones when data changes:
```mql
if(!g_forceZoneRedraw) return;
g_forceZoneRedraw = false;
// ... draw zones ...
```

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| Duplicate iATR calls | P2 | 5 lines | Eliminates 5+ redundant broker calls |
| Delete-then-create pattern | P2 | Medium | Reduces object API calls by 50% |
| UpdateTPHitStatus in draw | P2 | 2 lines | Removes MarketInfo from draw path |
| Zone redraw without dirty flag | P2 | 3 lines | Eliminates unnecessary zone redraws |

---

## Verdict: FIX RECOMMENDED — Multiple small optimizations that compound significantly
