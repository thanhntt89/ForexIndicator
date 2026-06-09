# Latency Review: SignalEngine.mqh

**File**: `Include/RSI_Advanced/SignalEngine.mqh` (~92 lines)
**Role**: Composite signal scoring — weighted components (RSI, Volume, Volatility, Session, MTF, S/R)
**Severity**: LOW — lightweight computation

---

## Critical Bugs: NONE

`CalculateSignalScore()` is a simple weighted sum calculation with no loops or heavy operations. Each component score is passed in as a pre-computed value.

---

## Observations

### 1. Score Calculation is Clean
```mql
double finalScore = rsiScore * 50.0
                  + volScore * 8.0
                  + volatScore * 12.0
                  + sessionScore * 8.0
                  + mtfScore * 12.0
                  + srScore * 10.0;
```
- O(1) computation — no performance concern
- Weights sum to 100 — mathematically correct

### 2. Quality Thresholds are Fixed
- HIGH >= 75, MODERATE >= 55, LOW >= 40, REJECT below 40
- These are reasonable but not adaptive — could benefit from per-TF or per-case tuning
- **Not a bug** — design choice

### 3. `GetCaseName()` uses switch statement
- O(1), no issue

---

## Verdict: PASS — No action required
