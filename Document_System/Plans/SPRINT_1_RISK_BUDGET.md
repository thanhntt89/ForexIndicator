# Sprint 1: Risk Budget + Drawdown Scaling

> **Goal:** Portfolio-level risk management with DD scaling
> **Duration:** 1 week
> **Prerequisite:** Sprint 0
> **Status:** `DONE` (2026-07-31)

---

## Tasks

### 1.1 Multi-level Circuit Breaker + DD Scaling
**Status:** `DONE`

Thay binary circuit breaker (ON/OFF at 3%) bằng 4-level gradual scaling:

| Level | Trigger DD% | ddScale | Input |
|-------|------------|---------|-------|
| Green | < 1.5% | 1.0 | — |
| Yellow | >= 1.5% | 0.50 | `InpDDYellowPct` |
| Orange | >= 2.5% | 0.25 | `InpDDOrangePct` |
| Red | >= 3.0% | 0.0 (STOP) | `InpDDRedPct` |

Thêm: equity HWM tracking (intraday), rolling max DD từ 10 outcomes gần nhất.

Files: `Structs.mqh` (+4 fields), `RiskManager.mqh` (rewrite)

### 1.2 Kết nối RiskManager ↔ PositionSizing
**Status:** `DONE`

- Fix: RiskManager exposure calc dùng `GetEffectiveRiskPct()` thay `GetActiveRiskPct()`
- PositionSizing nhân thêm `ddScale` vào adjusted risk
- Flow: `UpdatePortfolioRisk()` → ddScale → `CalculatePositionSize()` → adjustedRiskPct

Files: `RiskManager.mqh`, `PositionSizing.mqh`

### 1.3 Signal Quality Risk Allocation
**Status:** `DONE`

- `qualityScale = 1.0 + (probTP1/100 - 0.5) * 2.0`, clamped [0.5, 2.0]
- Controlled by `InpUseQualityAlloc` (default true)
- Signal 68% TP → 1.36x risk, signal 52% → 1.04x risk

Files: `PositionSizing.mqh`

### 1.4 Config Inputs
**Status:** `DONE`

Thêm vào Risk Manager group:
- `InpDDYellowPct` (1.5%) — Scale 50%
- `InpDDOrangePct` (2.5%) — Scale 25%
- `InpDDRedPct` (3.0%) — Full STOP
- `InpMinRiskPct` (0.25%) — Floor risk per trade
- `InpUseQualityAlloc` (true) — Scale risk by signal quality

Removed: `InpMaxDailyDrawdown` (replaced by 3-level DD inputs)

Files: `Config.mqh`

### 1.5 Panel Display
**Status:** `DONE`

Portfolio risk display upgraded to 2 lines:
```
Risk:1.2/2.0% T:3/15 [GREEN]
DD:0.7% Scale:100% Lot:0.15
```

Color theo CB level. Position Sizing section thêm DD% factor.

Files: `PanelDrawing.mqh`

---

## Acceptance Criteria
- [x] Multi-level CB: Yellow(50%), Orange(25%), Red(STOP)
- [x] ddScale feeds into PositionSizing lot calculation
- [x] Signal quality scales risk proportionally
- [x] RiskManager uses GetEffectiveRiskPct() (not raw)
- [x] Panel shows CB level + DD scale + lot
- [ ] MQ4 compile 0 errors (user verify)
- [ ] MQ5 compile 0 errors (user verify)

---

## Files Changed (5)
| File | Change |
|------|--------|
| `Include/QuantEdge/Core/Structs.mqh` | +4 fields: ddScale, cbLevel, equityHWM, rollingMaxDD. Removed: maxDailyDD |
| `Include/QuantEdge/Core/Config.mqh` | +5 inputs, -1 input (InpMaxDailyDrawdown) |
| `Include/QuantEdge/Risk/RiskManager.mqh` | Rewrite: multi-level CB, equity HWM, rolling DD, uses GetEffectiveRiskPct() |
| `Include/QuantEdge/Risk/PositionSizing.mqh` | +ddScale, +qualityScale, InpMinRiskPct floor |
| `Include/QuantEdge/Display/PanelDrawing.mqh` | 2-line risk display with CB level, DD scale info |
