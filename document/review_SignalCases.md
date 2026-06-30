# Latency Review: SignalCases.mqh

**File**: `Include/RSI_Advanced/SignalCases.mqh` (~261 lines)
**Role**: 8 signal case detection functions (OB/OS Bounce, Regular/Hidden Divergence, Strong Trend, Orange Level, Trend Continuation, Sideway Breakout, Basic Crossover)
**Severity**: LOW — simple buffer comparisons

---

## Critical Bugs: NONE

All case detection functions are simple conditional checks on pre-computed buffer values. No loops, no I/O, no heavy computation.

---

## Observations

### 1. Cases 2 & 3 (Divergence) Call `FindTwoSwingLows/Highs`
- These functions are in SwingDetection.mqh and contain a loop
- Loop is bounded by `InpSwingLookback` (default ~20) — acceptable
- Each divergence case involves ~40 loop iterations max

### 2. `ConfirmedCrossUp()` / `ConfirmedCrossDown()` — 2-Bar Confirmation
- Checks `i-1` and `i-2` bars — O(1), correct

### 3. Case Priority Order Handled in Main File
- Detection functions themselves are stateless and side-effect-free — good design
- Priority logic (6→2→4→3→1→5→7) is in the main OnCalculate loop

### 4. All Cases Use Buffer Values (Pre-Computed)
- `BufferGreen`, `BufferRed`, `BufferOrange`, `BufferBBUpper`, `BufferBBLower`
- No `iRSI()` or `iATR()` calls inside case checks — efficient

---

## Verdict: PASS — Well-implemented, no action required
