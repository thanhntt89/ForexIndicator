# Latency Review: RSICore.mqh

**File**: `Include/RSI_Advanced/RSICore.mqh` (~49 lines)
**Role**: Core RSI line calculation — Green (Fast SMA), Red (Signal SMA), Orange (BB Middle), BB bands
**Severity**: LOW — efficient incremental calculation

---

## Critical Bugs: NONE

---

## Observations

### 1. `iRSI()` called per bar in the loop
**Location**: Line ~15 (inside `CalculateRSILines`)

```mql
for(int i = startBar; i < rates_total; i++)
{
   g_rawRSI[i] = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, rates_total - 1 - i);
   ...
}
```

**Analysis**:
- **MQL4**: `iRSI()` is a native built-in — O(1) per call after initial calculation. No issue.
- **MQL5**: Uses batch cache via MQLCompat.mqh — reads from `_cache_rsi[]` array. O(1) per call.
- **Verdict**: Efficient in both platforms.

### 2. SMA/StdDev calculations use helper functions
- `CalculateSMA()` and `CalculateStdDev()` from MathUtils.mqh
- Each is O(period) per bar — standard and unavoidable
- Total: O(bars × max_period) which is expected

### 3. Incremental calculation path
- On new bar (non-fullRecalc), `startBar` is set to `prev_calculated - 1 - lookback`
- Only recalculates the last few bars — correct and efficient
- **Verdict**: Well-implemented incremental update

---

## Verdict: PASS — No action required. Efficient implementation.
