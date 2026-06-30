# Latency Review: Structs.mqh

**File**: `Include/RSI_Advanced/Structs.mqh` (~167 lines)
**Role**: All data structures (SignalData, ProbabilityData, EntryZone, SessionStats, etc.)
**Severity**: LOW — pure type definitions

---

## Critical Bugs: NONE

Structs.mqh defines data types only. No runtime computation.

---

## Observations

### 1. `SessionStats` struct uses 2D arrays `[4][CASE_COUNT]`
- Fixed-size arrays (4 sessions × 8 cases = 32 elements per metric)
- **Impact**: Minimal — small fixed memory, no heap allocation
- **Status**: Correct design for fixed-dimension data

### 2. `SignalData` struct is value-copied frequently
- `SignalData activeSig = g_signals[g_activeSignalIndex]` creates a copy every tick
- **Impact**: Low (~100 bytes per copy) — not a bottleneck but worth noting
- **Recommendation**: Use reference/pointer if MQL5, or accept the copy cost in MQL4

### 3. `ProbabilityData` struct has good field coverage
- Includes decay/survival fields, sample counts, and confidence metrics
- **Status**: Well-designed, no waste

### 4. `ENUM_VOL_REGIME` and `VolRegimeData` are clean
- Enum + struct pattern is correct for regime classification
- No memory concerns

---

## Verdict: PASS — No action required
