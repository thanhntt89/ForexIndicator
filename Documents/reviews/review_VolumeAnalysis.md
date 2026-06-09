# Latency Review: VolumeAnalysis.mqh

**File**: `Include/RSI_Advanced/VolumeAnalysis.mqh` (~96 lines)
**Role**: Volume ratio, volume trend, volume confirmation scoring per case
**Severity**: LOW

---

## Critical Bugs: NONE

---

## Observations

### 1. `GetVolumeRatio()` — 20 iVolume Calls
- Loops over `lookback` (default 20) bars calling `iVolume()`
- Called during signal scoring — not per-tick
- O(20) — acceptable

### 2. `GetVolumeTrend()` — 10 iVolume Calls
- Splits lookback into halves, sums volume
- O(10) — negligible

### 3. `GetVolumeConfirmation()` — Switch + Two Helper Calls
- Calls `GetVolumeRatio()` and `GetVolumeTrend()` once each
- Total: ~30 iVolume calls per signal score
- **Impact**: Only during signal detection, not per-tick

### 4. `Bars` Usage
- `j < Bars` — uses the `Bars` property which is redefined as `_compat_GetBars()` in MQL5
- Each access calls `::Bars(_Symbol, _Period)` — a function call inside the loop condition
- **Fix**: Cache `Bars` before loop:
```mql
int totalBars = Bars;
for(int j = barShift + 1; j <= barShift + lookback && j < totalBars; j++)
```

---

## Verdict: PASS — Minor optimization opportunity with Bars caching
