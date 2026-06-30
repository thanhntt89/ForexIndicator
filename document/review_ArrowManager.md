# Latency Review: ArrowManager.mqh

**File**: `Include/RSI_Advanced/ArrowManager.mqh` (~41 lines)
**Role**: Create signal arrow objects on chart
**Severity**: LOW

---

## Critical Bugs: NONE

---

## Observations

### 1. `CreateSignalArrow()` is clean
- Creates one OBJ_ARROW per signal
- Sets properties (color, size, tooltip)
- Only called when a new signal is detected on a closed bar — infrequent

### 2. Object naming convention is correct
- Uses `PREFIX_ARROW + caseNum + "_" + time` format
- Matches what `FindSignalByArrowName()` expects to parse

---

## Verdict: PASS — No action required
