# Latency Review: SwingDetection.mqh

**File**: `Include/RSI_Advanced/SwingDetection.mqh` (~73 lines)
**Role**: Find two swing lows/highs for divergence detection
**Severity**: LOW

---

## Critical Bugs: NONE

---

## Observations

### 1. Loop Bounded by Configurable Depth
```mql
for(int j = barIndex - depth; j < barIndex; j++)
```
- `depth` comes from `InpSwingLookback` (default ~20)
- Maximum iterations: ~20 per call — negligible cost

### 2. Called Only During Signal Detection
- `FindTwoSwingLows()` / `FindTwoSwingHighs()` called from Cases 2 and 3
- Only executed when crossover conditions are met — infrequent
- No per-tick execution

### 3. Uses Buffer Values (Pre-Computed)
- Reads from `BufferGreen[]` — no indicator calls inside

---

## Verdict: PASS — No action required
