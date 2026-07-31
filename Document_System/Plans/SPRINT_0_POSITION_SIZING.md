# Sprint 0: PositionSizing + Trade Summary

> **Goal:** Kelly Fraction lot sizing + vol scaling + Brier scaling + trade summary panel
> **Duration:** 1 week
> **Prerequisite:** Phase 0 (DONE)
> **Blocks:** Sprint 1

---

## Status: `DONE` (2026-07-30)

---

## Tasks

### 0a. Create `Risk/PositionSizing.mqh`
- Kelly Fraction: `f* = (W*B - L) / B` where W=winRate, B=avgWin/avgLoss, L=1-W
- Half-Kelly default (conservative)
- Vol scaling: reduce size when ATR > 1.5x median
- Brier scaling: reduce size when Brier > 0.22
- Input: `InpRiskPercent` (% of balance per trade)

### 0b. Wire PositionSizing into PanelDrawing
- Display recommended lot size on panel
- Show Kelly fraction, vol adjustment, Brier adjustment

### 0c. Trade Summary section
- Win/Loss count, Win Rate, Avg P/L
- Per-case breakdown if enough data

### 0d. Compile verify (MQ4 + MQ5)

---

## Acceptance Criteria
- [x] MQ4 compile 0 errors
- [x] MQ5 compile 0 errors
- [x] Panel shows lot size recommendation
- [x] Kelly fraction matches manual calculation
