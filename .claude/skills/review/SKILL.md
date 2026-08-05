---
name: review
description: Review QuantEdge RSI MQL4/MQL5 code changes for correctness, platform sync, and project rule compliance. Use proactively before any commit or when the user asks for a review.
allowed-tools: Bash Read Grep Glob Agent ReportFindings
---

# QuantEdge RSI — Code Review Skill

You are reviewing code for the **QuantEdge RSI** project — a dual-compiled MT4/MT5 trading indicator with a 7-layer architecture (`Include/QuantEdge/{Core,Signal,Analysis,Engine,AI,Risk,Display,Data}/`).

## Review scope

Review changes since the last commit unless the user specifies files or a diff range:

```
!`cd "f:\Jimmii\Projects\RSI_Advanced" && git diff --stat HEAD 2>/dev/null || echo "no git diff"`
```

If no uncommitted changes, ask the user what to review.

## Checklist — check every item, report only violations found

### 1. PERIOD_* trap (CRITICAL — silent wrong-data bug on MT5)

Grep ALL changed `.mqh`/`.mq4`/`.mq5` files for `PERIOD_H1`, `PERIOD_H4`, `PERIOD_D1`, `PERIOD_W1`, `PERIOD_MN1` used in **runtime code** (comparisons, function arguments, struct field assignments). These are 16385/16388/16408/32769/49153 on MT5, but `Period()` returns minutes (60/240/1440/10080/43200) — comparison or passing to functions silently fails.

**Must use:** `TF_H1`(60), `TF_H4`(240), `TF_D1`(1440), `TF_W1`(10080), `TF_MN1`(43200) from `Config.mqh`.

Three specific trap patterns:
- **Comparison trap:** `if(Period() >= PERIOD_H4)` → always FALSE on MT5 (240 >= 16388)
- **Function arg trap:** `iRSI(NULL, PERIOD_H4, ...)` → `MinutesToTimeframe()` finds no match, falls back to `_Period`, reads wrong TF
- **Struct field trap:** storing `PERIOD_H4` in a struct, later comparing with `TF_H4` → never matches

Exception: `PERIOD_M1` through `PERIOD_M30` happen to equal `TF_*` values on both platforms — acceptable but `TF_*` preferred for consistency.

### 2. MQ4/MQ5 sync (CRITICAL)

Every logic change in `.mq4` must be mirrored in `.mq5` and vice versa. Check:
- Same detection logic, same gate conditions, same buffer indices
- Platform-specific differences are ONLY allowed in: `iCustom()` call syntax, `CopyBuffer()` vs direct array, `CTrade` vs `OrderSend()`, `PositionsTotal()` vs `OrdersTotal()`, `#property` declarations
- If a `.mqh` include file changed, verify it compiles under both MQL4 and MQL5 semantics (e.g., `datetime` vs `int` differences, `ArraySetAsSeries` behavior)

### 3. ProbabilityEngine protection (CRITICAL — Rule #2)

If ANY file in `Include/QuantEdge/Engine/ProbabilityEngine.mqh` is modified:
- **FLAG IMMEDIATELY** — changes to this file require Walk-Forward validation (backtest comparison before vs after)
- Also flag changes to `Normalize.mqh` if they affect `GetTradeRecommendation()`, probability flow, or `ENUM_RECOMMENDATION`
- Also flag changes to `SLTP.mqh`/`SLTPOptimizer.mqh` if they affect signal outcome simulation

### 4. Layer violation check

The 7-layer architecture has strict dependency rules:
```
Core (Config, Structs, Globals, MQLCompat) — no upward deps
Signal (ISignalSource, RSIStrategy, SignalDetector) — depends on Core only
Analysis (Normalize, SessionStats, MarketRegime, etc.) — depends on Core
Engine (ProbabilityEngine, SLTP, WalkForward, etc.) — depends on Core + Analysis
AI (XGBModel, XGBIntegration, CalibrationEngine) — depends on Core + Engine
Risk (RiskManager, PositionSizing) — depends on Core + Engine
Display (PanelDrawing, ArrowManager, LineDrawing, ChartEvents) — depends on all
Data (SignalLogger) — depends on Core
```

Flag any `#include` that goes **upward** (e.g., Analysis including Engine, Core including Display).

### 5. Buffer contract stability

If buffer indices 0-24 are modified in `QuantEdge_RSI.mq4` or `.mq5`:
- Verify `#property indicator_buffers` count matches actual `SetIndexBuffer()` count
- Verify MQ4 and MQ5 have identical buffer index assignments
- Flag if any existing buffer index changed meaning (breaks EA consumers — see `Document_System/12_EA_EXPORT_CONTRACT.md`)
- New buffers MUST be appended (index 25+), never inserted mid-sequence

### 6. Signal contract compliance

If signal detection code changes (`Signal/RSIStrategy.mqh`, `Signal/SignalDetector.mqh`, or any future signal source):
- Must call `StoreSignal()` with all required fields on closed bars ONLY (anti-repaint)
- Case numbers must be within the source's reserved range (1-9 RSI, 11-19 MACD, 21-29 ICT, 31-39 PA, 91-99 Custom)
- Detection priority order must be preserved: `Case 6 → 2 → 4 → 3 → 1 → 5 → 7 → 8 → 9`
- Platform gates (cooldown, session filter) must remain in `SignalDetector.mqh`, NOT in strategy files

### 7. Dead code and stale references

- `InpEnableCase0` in `Config.mqh:102` is deprecated and not wired — flag if any new code references it
- `VERSION "10.20"` in `Config.mqh:7` is stale (project is past V12.2) — flag if version-dependent logic references it
- GMT offset duality: `GuessEUBrokerOffset()` vs `GetBrokerGMTOffset()` in `Normalize.mqh` — flag if new code adds more call sites without resolving the duality

### 8. Common MQL pitfalls

- **Array bounds:** MQL arrays are 0-indexed. Check `ArrayResize()` before `ArrayAppend` patterns. Check `rates_total - 1` vs `rates_total - 2` boundary for closed-bar logic.
- **EMPTY_VALUE sentinel:** Buffers must be initialized to `EMPTY_VALUE`, not `0.0`. Check `ArrayInitialize(buffer, EMPTY_VALUE)` in `OnInit()`/fullRecalc paths.
- **Static cache invalidation:** If adding a static variable cache, it MUST check `g_tfGeneration` to invalidate on timeframe switch (see Sprint 2 audit fix: 8 caches already have this guard).
- **Division by zero:** Check all divisions involving ATR, tick value, lot step, spread — these can be 0 on illiquid symbols or during market close.
- **String concatenation in hot paths:** `StringFormat()`/`StringConcatenate()` in `OnCalculate()` loops is expensive — flag if in inner loops processing every bar.

### 9. Risk/Position Sizing integrity

If `Risk/PositionSizing.mqh` or `Risk/RiskManager.mqh` changes:
- Kelly fraction formula: `f* = (W*B - L) / B` must remain correct
- Circuit breaker levels must be monotonically increasing: Yellow(1.5%) < Orange(2.5%) < Red(3.0%)
- `GetEffectiveRiskPct()` must be used (not `GetActiveRiskPct()`) wherever exposure is calculated
- `ddScale` must feed into lot calculation

### 10. EA template consistency

If `QuantEdge_EA_Template.mq4` or `.mq5` changes:
- Buffer index constants (`BUF_*`) must match `12_EA_EXPORT_CONTRACT.md`
- `InpEnableAutoTrading` must default to `false`
- 5-gate chain must remain complete: recommendation level, confidence, staleness, no-duplicate, spread
- MQ4 uses `OrderSend()`/`OrdersTotal()`, MQ5 uses `CTrade`/`PositionsTotal()` — do not mix

### 11. Performance patterns

This project has a documented history of performance bugs (17 Phase 1 fixes, 7 PROB-FIX fixes, MTF RAM buffer rewrite). Any change touching hot paths must be checked against these patterns.

**Three-tier throttle architecture** — violating these tiers is a performance regression:
- **Tier 1 (per-tick, lightweight):** `OnCalculate()` inner loop, RSI line computation, signal detection — NO probability, NO string ops, NO display updates
- **Tier 2 (200ms `GetTickCount()` throttle):** Display/probability/SLTP recalculation — gated by `GetTickCount() - g_lastUpdateTick >= 200`. Flag any probability or SLTP call outside this gate.
- **Tier 3 (per-bar `isNewBar`):** Stats, regime updates, full signal evaluation — runs once when `Time[0]` changes. Flag any `SessionStatistics` or `MarketRegime` call in per-tick code.

**`g_tfGeneration` cache invalidation pattern:**
- 10 static caches across 7 files use `if(s_XXXGen != g_tfGeneration) { reset; s_XXXGen = g_tfGeneration; }` to invalidate on timeframe switch or fullRecalc
- Any NEW static cache MUST implement this pattern — flag missing `g_tfGeneration` guard
- Existing caches: MarketRegime, ProbabilityEngine, SLTP (×2), WalkForward (×2), SignalLogger, SessionStatistics, Normalize, CandleNormalize

**`ArrayResize` patterns:**
- `ArrayResize(arr, newSize)` without reserve parameter causes O(n) reallocation every call — flag in loops
- Correct pattern: `ArrayResize(arr, newSize, RESERVE)` with reserve block (e.g., 256), or static-grow-only (`if(newSize > ArraySize(arr)) ArrayResize(...)`)
- PROB-FIX-4 fixed exactly this in `ProbabilityEngine.mqh` — static-grow with 256-element reserve

**Batch price cache (`MQLCompat.mqh:128-204`):**
- MT5 `CopyBuffer()`/`CopyRates()` per-bar in a loop = thousands of calls → must use batch `CopyBuffer(handle, 0, 0, count, destArray[])` pattern
- Flag any `CopyBuffer()` or `CopyRates()` inside `for(int i=...; i<rates_total; ...)` loop without batch pre-fetch

**Per-bar datetime guard (PROB-FIX-1 pattern):**
- `CalculateProbability()` and similar expensive functions must check `if(signalTime == s_lastCalcTime) return cached;` to avoid recalculation on every tick of the same bar
- Flag any expensive computation (probability, SLTP optimization, XGBoost prediction) called without a per-bar or per-signal guard

**String operations in hot paths:**
- `StringFormat()`, `StringConcatenate()`, `"str" + var` inside `OnCalculate()` inner loops creates GC pressure
- `Comment()` for debug output in per-tick code is especially expensive
- Flag: string ops inside any `for(int i=...; i<rates_total; ...)` loop or per-tick code path (except logging gated behind `if(InpDebugMode)`)

**iRSI/iATR caching:**
- Direct `iRSI()`/`iATR()` calls inside loops create implicit indicator handles per call on MT5
- Must use pre-fetched arrays (see MTF RAM buffer system) or indicator handles created once in `OnInit()`

### 12. Multi-Timeframe (MTF) data update patterns

The MTF system (`Include/QuantEdge/Engine/MTFEngine.mqh`) eliminated 612 cross-TF `iRSI()` calls per tick by pre-caching RAM buffers. Changes to MTF-related code must preserve these performance guarantees.

**MTF RAM buffer architecture:**
- 6 higher timeframes × 250-bar RAM buffers (~42KB total) pre-cached
- Rebuild triggered ONLY when a new HTF bar forms (`iTime(Symbol(), htfPeriod, 0) != s_lastHTFBarTime[tf]`)
- Flag any code that calls `iRSI(Symbol(), higherTF, ...)` directly instead of reading from `g_mtfBuffers[]` — this defeats the RAM cache

**`MTF_INIT_BUILD_BARS` limit:**
- Initial buffer build is capped (default 250 bars) to prevent startup lag
- Flag any change that increases this constant without profiling impact
- `[PERF]` comment at `MTFEngine.mqh:71`: "Build only a few recent bars"

**Read-only indices — `[0]` and `[2]` only:**
- `[PERF]` at `Globals.mqh:43`: "Only bar indices [0] and [2] of the MTF buffers are ever read"
- The MTF system is optimized for reading current bar (0) and lookback bar (2) — flag any new code reading arbitrary MTF buffer indices (e.g., `g_mtfBuffers[tf][i]` where `i` could be large) as it may exceed the pre-cached depth

**Bulk CopyRates for cross-TF OHLC:**
- `CandleNormalize.mqh:125`: "[PERF] Bulk-fetch all H1 OHLC+time in ONE CopyRates call"
- Any new cross-TF candle data access must use `CopyRates()` batch pattern, NOT per-bar `iOpen()/iHigh()/iLow()/iClose()`

**MTF cache invalidation:**
- MTF buffers participate in `g_tfGeneration` invalidation — if the user switches timeframe, ALL MTF caches must be rebuilt
- Flag any MTF-related static cache missing the `g_tfGeneration` guard (see item 11)

## Output format

Use ReportFindings to report violations found. For each finding:
- `file`: the file path (repo-relative)
- `line`: the exact line number
- `category`: one of `period-trap`, `mq4-mq5-sync`, `prob-engine-rule2`, `layer-violation`, `buffer-contract`, `signal-contract`, `dead-code`, `mql-pitfall`, `risk-integrity`, `ea-consistency`, `performance`, `mtf-data`, `correctness`, `security`
- `summary`: one sentence describing the violation
- `failure_scenario`: concrete scenario where this bug manifests

If no violations found, report an empty findings array — do not fabricate issues.

## What NOT to review

- Do NOT run `make.ps1` or MetaEditor — user compiles
- Do NOT flag code style/formatting — MQL has no standard linter
- Do NOT suggest splitting ProbabilityEngine — that's a known tech debt, not a per-change review finding
- Do NOT flag missing comments — project convention is minimal comments
