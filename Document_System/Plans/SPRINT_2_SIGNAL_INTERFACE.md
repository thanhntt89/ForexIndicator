# Sprint 2: Signal Interface (RSI -> Plugin)

> **Goal:** Extract RSI detection into pluggable 2-tier signal platform
> **Duration:** 2 sessions
> **Prerequisite:** Phase 0
> **Status:** `DONE`

---

## Architecture

```
Main loop (.mq4/.mq5)
  │  ONLY knows: SignalResult + SLTP + StoreSignal + logging
  │  DOES NOT know: case numbers, cooldown, session filter, strategy rules
  │
  └─→ SignalDetector_Detect()         ← Platform gates + strategy chain
        │  Platform gates: cooldown (stableAnchor exception)
        │  Strategy chain (first-match wins):
        │
        ├─→ RSI_Detect()              ← Cases 1-9, session filter Case 6
        ├─→ MACD_Detect()             ← (future, cases 11-19)
        └─→ ICT_Detect()              ← (future, cases 21-29)
```

## New Files

| File | Purpose |
|---|---|
| `Signal/ISignalSource.mqh` | `SignalResult` struct + interface contract |
| `Signal/RSIStrategy.mqh` | RSI cases 1-9, buffer validation, crossover, angle, session filter |
| `Signal/SignalDetector.mqh` | Platform orchestrator: cooldown gate + strategy chain routing |

## Tasks

| # | Task | Status | Files |
|---|---|---|---|
| 2.1 | Fix phantom includes | `DONE` | SessionStatistics.mqh, SessionFilter.mqh |
| 2.2 | Parameterize buffer access | `DONE` | MarketRegime, VolatilityAnalysis, Normalize, ProbabilityEngine, XGBIntegration, SignalEngine, SLTP, ChartEvents |
| 2.3 | Create signal architecture | `DONE` | ISignalSource.mqh, RSIStrategy.mqh, SignalDetector.mqh |
| 2.4 | Refactor main files | `DONE` | QuantEdge_RSI.mq4, QuantEdge_RSI.mq5 |
| 2.5 | Update documentation | `DONE` | SPRINT_2, MASTER_PLAN |

## Verification Checklist

- [x] Grep audit: `BufferGreen[`/`BufferOrange[`/`BufferBBUpper[`/`BufferBBLower[` in Analysis/Engine/AI → 0 hits
- [x] Include guards: `QE_ISIGNALSOURCE_MQH`, `QE_RSISTRATEGY_MQH`, `QE_SIGNALDETECTOR_MQH`
- [x] MQ4/MQ5 sync: Main loop identical structure (user compile verify)
- [x] Behavioral equivalence: Case priority 6→2→4→3→1→5→7→8→9 + pre-gates + session filter Case 6 + cooldown preserved
- [x] Platform test: Adding MACD = 1 file + few lines in SignalDetector
- [x] Abstraction audit: Main loop has NO hardcoded case numbers, cooldown logic, session filter, or strategy-specific rules

## Case Number Convention

| Range | Strategy | Status |
|---|---|---|
| 1-9 | RSI | Active |
| 11-19 | MACD | Reserved |
| 21-29 | ICT | Reserved |
| 31-39 | Price Action | Reserved |
| 91-99 | Custom | Reserved |
