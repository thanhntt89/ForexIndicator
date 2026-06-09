# Latency Review: IntermarketAnalysis.mqh

**File**: `Include/RSI_Advanced/IntermarketAnalysis.mqh` (~227 lines)
**Role**: DXY/EURUSD correlation scoring for Gold signals
**Severity**: **MEDIUM** — symbol detection overhead + per-tick intermarket refresh

---

## Critical Bug #1: `DetectIntermarketSymbol()` — 15 iClose Calls on Failure

**Location**: Lines 20-58
**Severity**: P2

```mql
string dxySymbols[] = {"DXYm","USDX","DXY","DX","USDIndex","DXY.","USDX.","DXYc","USDXm"};
for(int i = 0; i < ArraySize(dxySymbols); i++)
{
   double price = iClose(dxySymbols[i], Period(), 0);  // Broker API call
   if(price > 0) { ... return; }
}
string eurSymbols[] = {"EURUSD","EURUSDm","EURUSDc","EURUSD.","EURUSDb","EURUSDpro"};
for(int i = 0; i < ArraySize(eurSymbols); i++)
{
   double price = iClose(eurSymbols[i], Period(), 0);  // Broker API call
   if(price > 0) { ... return; }
}
```

**Problem**: If no intermarket symbol is available, ALL 15 symbols are tested with `iClose()` — each one may log an error in the terminal and waste time looking up non-existent symbols.

**Impact**: Only called once (or when connection is lost), so not a per-tick issue. But on brokers without DXY/EURUSD, this fires repeatedly due to the reconnection logic in `RefreshIntermarketData()`.

**Fix**: Add a "tried and failed" flag:
```mql
static bool s_detectionAttempted = false;
if(s_detectionAttempted && !g_intermarket.isAvailable) return;
s_detectionAttempted = true;
// ... existing detection ...
```

---

## Critical Bug #2: `CalculateIntermarketTrend()` — Two Loops of iClose

**Location**: Lines 77-120
**Severity**: P2

```mql
for(int i = 0; i < period; i++)
{
   double price = iClose(sym, Period(), i);  // Cross-symbol iClose
   sma0 += price;
}
for(int i = 1; i <= period; i++)
{
   double price = iClose(sym, Period(), i);  // Same calls overlapping!
   smaPrev += price;
}
```

**Problem**: Two loops that overlap significantly — bars 1 to `period-1` are read in BOTH loops. With default `InpIntermarketPeriod=20`, that's 20 + 20 = 40 iClose calls, but 19 are redundant.

**Fix**: Single loop:
```mql
double prices[];
ArrayResize(prices, period + 1);
for(int i = 0; i <= period; i++)
   prices[i] = iClose(sym, Period(), i);

double sma0 = 0, smaPrev = 0;
for(int i = 0; i < period; i++) sma0 += prices[i];
for(int i = 1; i <= period; i++) smaPrev += prices[i];
```

---

## Critical Bug #3: `RefreshIntermarketData()` Runs Every Tick

**Location**: Called from OnCalculate() `// Lightweight: every tick` section
**Severity**: P2

Intermarket trend data (DXY/EURUSD SMA slope) changes very slowly — at most once per bar. Running `CalculateIntermarketTrend()` every tick with 40 iClose calls is wasteful.

**Fix**: Guard with new-bar check:
```mql
void RefreshIntermarketData()
{
   static datetime s_lastBar = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(curBar == s_lastBar) return;
   s_lastBar = curBar;
   // ... existing logic ...
}
```

---

## Recommendation Summary

| Bug | Severity | Effort | Impact |
|-----|----------|--------|--------|
| Symbol detection retry loop | P2 | 3 lines | Prevents repeated failed lookups |
| Overlapping iClose loops | P2 | 5 lines | Eliminates 19 redundant calls |
| Per-tick refresh | P2 | 4 lines | Reduces to per-bar only |

---

## Verdict: FIX RECOMMENDED — Add new-bar guard to RefreshIntermarketData
