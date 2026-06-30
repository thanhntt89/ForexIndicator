# Latency Review: Config.mqh

**File**: `Include/RSI_Advanced/Config.mqh` (~210 lines)
**Role**: All `input` parameters, ENUM definitions, prefix constants, `IsBacktestMode()` macro
**Severity**: LOW — no runtime computation

---

## Critical Bugs: NONE

Config.mqh is a pure declaration file with no runtime code. No latency issues.

---

## Observations

### 1. `InpMaxBars` default may be too high
- **Default**: 5000 bars — on M1 this means scanning ~3.5 days of data
- **Impact**: Every `fullRecalc` iterates up to 5000 bars for RSI + signal detection
- **Recommendation**: Consider lowering default to 2000 for M1/M5, or make it TF-adaptive

### 2. `InpProbMaxBars` default (3000) drives the heaviest computation
- This parameter directly controls how many historical bars `ScanHistoricalATRBased()` scans
- On M1 with 3000 bars, the probability engine loops 3000 × forward_bars per scan
- **Recommendation**: Add a per-TF default table (M1=1000, M5=1500, H1=3000)

### 3. `IsBacktestMode()` macro redefined in multiple files
- Defined here AND in `SessionStatistics.mqh` AND `SignalLogger.mqh`
- Uses `#ifndef ISBACKTESTMODE_DEFINED` guard — works but fragile
- **Recommendation**: Define only in Config.mqh, remove duplicates

### 4. No input validation ranges
- MQL4/5 `input` doesn't support min/max range declarations
- Invalid combinations (e.g., `InpSLRatio=0`) caught in `OnInit()` — this is correct

---

## Verdict: PASS — No action required for latency optimization
