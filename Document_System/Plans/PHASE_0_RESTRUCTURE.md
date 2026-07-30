# Phase 0: Project Restructure

> **Goal:** Chuyển flat 31-file structure → layered 7-folder architecture
> **Duration:** 1 ngày
> **Prerequisite:** None
> **Blocks:** Tất cả Sprint 0-6
> **Reference:** [12_PROJECT_STRUCTURE.md](../12_PROJECT_STRUCTURE.md)

---

## Status: `DONE` (2026-07-30)

---

## Task List

### 0a. Tạo folder structure
**Status:** `DONE` (2026-07-30)

Folders:
- [x] `Include/QuantEdge/Core/`
- [x] `Include/QuantEdge/Signal/`
- [x] `Include/QuantEdge/Analysis/`
- [x] `Include/QuantEdge/Engine/`
- [x] `Include/QuantEdge/AI/`
- [x] `Include/QuantEdge/Risk/`
- [x] `Include/QuantEdge/Display/`
- [x] `Include/QuantEdge/Data/`

---

### 0b. Move files vào đúng folder
**Status:** `DONE` (2026-07-30)

| Layer | Files |
|---|---|
| Core | Config, Structs, Globals, MQLCompat, MathUtils, TFConfig |
| Signal | RSICore, SignalCases, SwingDetection, CandleNormalize |
| Analysis | Normalize, IntermarketAnalysis, MarketRegime, SessionFilter, SessionStatistics, VolumeAnalysis, VolatilityAnalysis |
| Engine | ProbabilityEngine, WalkForward, CalibrationEngine, SignalEngine, SLTP, MTFEngine |
| AI | XGBModel, XGBIntegration |
| Risk | RiskManager |
| Display | PanelDrawing, LineDrawing, ArrowManager, ChartEvents |
| Data | SignalLogger |

---

### 0c. Update #include paths trong main files (.mq4/.mq5)
**Status:** `DONE` (2026-07-30)

---

### 0d. Update #include paths trong tất cả .mqh (internal cross-refs)
**Status:** `DONE` (2026-07-30)

---

### 0e. Compile verify
**Status:** `DONE` (2026-07-30)

- [x] MQ4 compile 0 errors
- [x] MQ5 compile 0 errors

---

### 0f. Viết Signal Contract spec
**Status:** `DONE` (2026-07-30)

---

## Completion Checklist

- [x] All 7 folders created
- [x] All 31 files moved
- [x] All #include paths updated (main files + mqh internals)
- [x] MQ4 compiles clean
- [x] MQ5 compiles clean
- [x] Signal Contract spec written
- [x] Git pushed to `features/QuantEdge-RSI`
