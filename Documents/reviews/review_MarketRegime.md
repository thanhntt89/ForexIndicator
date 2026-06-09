# Latency Review: MarketRegime.mqh

**File**: `Include/RSI_Advanced/MarketRegime.mqh` (~91 lines)
**Role**: Market regime detection (uptrend/downtrend/ranging), adaptive angle threshold, angle Z-score
**Severity**: LOW

---

## Critical Bugs: NONE

All functions use pre-computed buffer values (`BufferGreen`, `BufferOrange`, `BufferBBUpper/Lower`) with bounded loops of 20 iterations max.

---

## Observations

### 1. `DetectMarketRegime()` — 20-Iteration Loop
- Computes average BB width over 20 bars
- Uses buffer values (no iRSI/iATR calls)
- O(20) — negligible cost

### 2. `GetAdaptiveAngleThreshold()` — 20-Iteration Loop
- Computes variance of Green RSI deltas over 20 bars
- Buffer reads only — no broker API calls
- O(20) — negligible cost

### 3. `CalculateAngleStrength()` — O(1) After Threshold Calc
- Calls `GetAdaptiveAngleThreshold()` internally (20 iterations)
- Returns Z-score as ratio — clean implementation
- Called once per signal in OnCalculate — not a hot path

---

## Verdict: PASS — Well-implemented, efficient functions
