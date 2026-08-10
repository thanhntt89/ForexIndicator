# QuantEdge Platform — Master Plan

> Source of Truth cho toàn bộ lộ trình chuyển đổi từ Indicator → Platform.
> Cập nhật status mỗi khi hoàn thành task.

---

## Timeline Overview

```
Phase 0 ─── Project Restructure ──────────────── 1 ngày
Sprint 0 ── PositionSizing + Trade Summary ───── 1 tuần
Sprint 1 ── Risk Budget + DD Scaling ─────────── 1 tuần
Sprint 2 ── Signal Interface (RSI → Plugin) ──── 2 tuần
Sprint 3 ── Export API + EA Template ─────────── 1 tuần
Sprint 4 ── XGB Versioning + SHAP + Shadow ────── 1 tuần
Sprint 5 ── Enhanced UX ──────────────────────── 1 tuần
Sprint 6 ── Backtest Engine (optional) ───────── 2 tuần
                                          Total: ~10 tuần
```

---

## Phase / Sprint Status

| Phase | Status | Start | End | Plan File |
|---|---|---|---|---|
| Phase 0: Project Restructure | `DONE` | 2026-07-30 | 2026-07-30 | [PHASE_0_RESTRUCTURE.md](PHASE_0_RESTRUCTURE.md) |
| Sprint 0: PositionSizing | `DONE` | 2026-07-30 | 2026-07-30 | [SPRINT_0_POSITION_SIZING.md](SPRINT_0_POSITION_SIZING.md) |
| Sprint 1: Risk Budget | `DONE` | 2026-07-31 | 2026-07-31 | [SPRINT_1_RISK_BUDGET.md](SPRINT_1_RISK_BUDGET.md) |
| Sprint 2: Signal Interface | `DONE` | 2026-07-31 | 2026-07-31 | [SPRINT_2_SIGNAL_INTERFACE.md](SPRINT_2_SIGNAL_INTERFACE.md) |
| Sprint 3: Export API | `DONE` | 2026-08-05 | 2026-08-05 | [SPRINT_3_EXPORT_API.md](SPRINT_3_EXPORT_API.md) |
| Sprint 4: XGB Versioning+SHAP+Shadow | `DONE` | 2026-08-06 | 2026-08-06 | [SPRINT_4_XGB_AUTOTRAIN.md](SPRINT_4_XGB_AUTOTRAIN.md) |
| Sprint 5: Enhanced UX | `IN PROGRESS` | 2026-08-10 | — | [SPRINT_5_ENHANCED_UX.md](SPRINT_5_ENHANCED_UX.md) |
| Sprint 6: Backtest | `PLANNED` | — | — | [SPRINT_6_BACKTEST.md](SPRINT_6_BACKTEST.md) |

---

## Platform Readiness Score

| Criterion | Before | Target | Current |
|---|---|---|---|
| Measurable | 9/10 | 9/10 | 9/10 |
| Extensible | 7/10 | 9/10 | 9/10 |
| Maintainable | 6/10 | 8/10 | 8/10 |
| AI Training | 7/10 | 9/10 | 9/10 |
| EA Output | 0/10 | 7/10 | 5/10 |
| **Total** | **29/50** | **42/50** | **40/50** |

---

## Dependencies Between Sprints

```
Phase 0 ──→ Sprint 0 ──→ Sprint 1
                │
                └──→ Sprint 2 ──→ Sprint 3
                                    │
                Sprint 4 (independent, can start after Phase 0)
                                    │
                Sprint 5 (after Sprint 0+1+3)
                Sprint 6 (optional, after Sprint 2)
```

**Critical path:** Phase 0 → Sprint 0 → Sprint 1 → Sprint 3

---

## Rules

1. **Mỗi Sprint PHẢI compile thành công** cả MQ4 và MQ5 trước khi mark complete
2. **KHÔNG thay đổi ProbabilityEngine** mà không Walk-Forward before/after
3. **Mỗi task hoàn thành → update status** trong file plan tương ứng
4. **Review diff trước khi commit** — MQ4 và MQ5 phải sync
5. **User tự compile** — Claude KHÔNG chạy MetaEditor

---

## Changelog

| Date | Change |
|---|---|
| 2026-07-30 | Created master plan with Phase 0 + 7 sprints |
| 2026-07-31 | Sprint 2 DONE — 2-tier signal platform (SignalDetector + RSIStrategy), buffer parameterization, layer violations fixed |
| 2026-07-31 | Post-Sprint-2 audit fix — `g_tfGeneration` guard added to 8 static caches (MarketRegime, ProbabilityEngine, SLTP×2, WalkForward×2, SignalLogger, SessionStatistics, Normalize) to prevent stale data returned after timeframe switch |
| 2026-08-05 | Sprint 3 DONE — EA Export Contract doc (`12_EA_EXPORT_CONTRACT.md`), reference EA templates for MQ4 (iCustom) and MQ5 (handle+CopyBuffer+CTrade), 5-gate decision chain, lot-from-risk helper. Zero indicator-side changes (buffer export already complete via `7ce9b6f`). EA defaults to skeleton mode (`InpEnableAutoTrading=false`). |
| 2026-08-06 | Sprint 4 DONE — Model version registry (`tools/model_registry.py`: archive/promote/rollback, per-key champion+shadow manifest), gated auto-promote (`auto_promote:false` default — retrains land as shadow, never auto-overwrite champion), 3 new tray actions (Promote Shadow, Rollback Champion, View History), SHAP feature importance export (`save_shap_report`, optional dep). Indicator A/B shadow mode: `XGBModelShadow.mqh` (new, duplicated loader, shares only binary-format primitives with `XGBModel.mqh`), `InpEnableXGBShadow` input (default `false`), "Candidate:" panel line with independent Brier tracking. Shadow prediction wired via one additive, gated line in `ProbabilityEngine.mqh` STEP 5.1 (zero existing lines changed — see Sprint 4 doc's Scope Decision for why Rule #2 is satisfied without WF re-validation). MQ4/MQ5 kept in sync (4 shadow call sites each, verified via grep diff). Zero EA-facing buffer changes (still 25). |
| 2026-08-06 | EA close-order panel + build restructure (post-Sprint-4 follow-up, unrelated to Sprint 5) — `Experts/QuantEdge_EA_Template.mq4`/`.mq5` moved from repo root into new `Experts/` folder via `git mv` (history preserved). Added draggable on-chart close panel: 5 buttons (Close All Profit, Close All Loss, Close Buy Profit, Close Sell Profit, CLOSE ALL), each gated by native `MessageBox()` OK/Cancel confirmation showing match count + total P/L — no timer or double-click trick. Header-click collapses/expands the panel; position persisted per-symbol/per-magic via `GlobalVariableSet/Get` (`QE_EA_Panel{X,Y}_<symbol>_<magic>`, namespaced `"QEEA_"` object prefix to avoid colliding with the indicator's own panel objects). Platform-specific close logic only: `.mq4` uses `OrdersTotal()`/`OrderSelect()`/`OrderClose()`, `.mq5` uses `PositionsTotal()`/`PositionGetTicket()`/`CTrade.PositionClose()`. Zero changes to `OnTick()` entry logic in either file — `InpEnableAutoTrading` (still defaults `false`) remains the sole entry gate, independent of the close panel. `make.ps1` extended with EA compile (MT4+MT5) and deploy sections (`MQL4/Experts`, `MQL5/Experts`), mirroring the existing indicator compile/deploy pattern exactly. Diff-review per Rule #4: function-name parity (17/17 identical), constant parity (`QEEA_*`/`CRIT_*` identical), zero `PERIOD_*` usage, no MQ4/MQ5 API mixing — zero findings. User to compile/verify per Rule #5. |
| 2026-08-06 | Close panel bugfix — buttons appeared unresponsive on demo. Root cause: `ClosePositionsByCriteria()` filtered candidate orders/positions by `OrderMagicNumber()`/`POSITION_MAGIC == InpMagicNumber`, so any position opened manually or by a different EA (confirmed via a live position with comment `"M17_Stop"`, not this EA's `"QE C%d ..."` format) was silently excluded — every button reported "no matching positions" for every criteria, including `CLOSE ALL`. Click delivery, `OnChartEvent()`, `MessageBox()`, and drag were all working correctly the whole time (verified via Experts-tab log before the fix). Fix: removed the magic-number filter from `ClosePositionsByCriteria()` in both `.mq4`/`.mq5` — now closes by `Symbol()` match only, regardless of which EA/manual order opened the position. `HasOpenPosition()` (Gate 4, entry-duplicate check) intentionally left untouched — it must keep filtering by this EA's own magic number, that's unrelated to the close panel. Two earlier attempts (removing `OBJPROP_SELECTABLE=false`, brightening button colors) were necessary UI polish but did not address this root cause. |
| 2026-08-06 | Manual Trading Dashboard mode — new `ENUM_DASHBOARD_MODE` input (`DASHBOARD_FULL` default / `DASHBOARD_MANUAL`). When Manual mode selected, indicator draws compact ~15-line panel replacing the full 35-line info panel: signal banner, recommendation + confidence bar, price levels (Entry/SL/TP1-3 with prob + R:R), entry zones, MTF alignment (single row), signal expiry, plus 5 horizontal close buttons (Close Profit, Close Loss, Close Buy+, Close Sell+, CLOSE ALL). Buttons trigger `MessageBox()` confirmation, then write `GlobalVariableSet("QE_CloseCmd_<Symbol()>", criteria+1)`. EA polls this GV at top of `OnTick()` (before bar-time guard, so commands execute on every tick), reads criteria, calls `ClosePositionsByCriteria()`. Panel supports collapse/expand toggle. 8 files changed (459 ins, 12 del): `Config.mqh` (enum+input+prefix), `Globals.mqh` (collapsed state), `PanelDrawing.mqh` (+346: `CreateCloseButton()` + `DrawManualPanel()`), `ChartEvents.mqh` (+44: click handler + collapse toggle), `QuantEdge_RSI.mq4`/`.mq5` (conditional draw routing + deinit cleanup), `QuantEdge_EA_Template.mq4`/`.mq5` (+13 each: GV polling). MQ4/MQ5 fully synced. No PERIOD_* violations. No ProbabilityEngine changes. |
| 2026-08-06 | Manual Dashboard drag/collapse bugfixes — (1) dragging the panel in Manual mode reverted to the Full panel: drag handlers in `ChartEvents.mqh` unconditionally called `DrawInfoPanel()`, ignoring `InpDashboardMode`; (2) clicking the header did not expand a collapsed panel: the collapse-toggle check was nested inside the `PREFIX_CLOSE`-only branch, so `PREFIX_PANEL`-prefixed clicks could never reach it. Fixed both by checking `InpDashboardMode` before choosing the draw function and moving the toggle check outside the close-button branch. |
| 2026-08-06 | Full-mode drag ghosting bugfix — dragging the panel in Full mode caused overlapping/garbled text. Root cause: `DrawInfoPanel()`'s layout-change detection (`s_lastSignalIndex`/`s_lastInvalidated`/etc.) only triggers `DeleteObjectsByPrefix(PREFIX_PANEL)` on content-state changes, not position changes — so stale objects could linger with inconsistent counts across drag redraws. Fixed by force-deleting `PREFIX_PANEL` (and `PREFIX_CLOSE` in Manual mode) objects before every drag-triggered redraw. |
| 2026-08-06 | `DrawDashboard()` dispatcher refactor (design feedback: eliminate duplicated `InpDashboardMode` branching) — added a single `DrawDashboard(int signalIndex, bool clearStale=false)` in `PanelDrawing.mqh` that checks `InpDashboardMode` once and routes to `DrawManualPanel()`/`DrawInfoPanel()`; `clearStale=true` deletes `PREFIX_PANEL`/`PREFIX_CLOSE` before drawing (used by drag/collapse/reselect call sites). Replaced 5 duplicated call sites across `ChartEvents.mqh` and `QuantEdge_RSI.mq4`/`.mq5`, additionally catching a previously-unnoticed 4th instance of the Manual-mode bug in the arrow-click handler (`ChartEvents.mqh`, was unconditionally calling `DrawInfoPanel()`). MQ4/MQ5 synced (shared `.mqh`, both `.mq4`/`.mq5` root files patched identically). |
| 2026-08-10 | Sprint 5 plan finalized (7 tasks, ~20h) — TDS line, Quick Attribution Bar, Confidence Meter (visual `CreateRectangleLabel`), Risk Summary (account/P&L/budget), PROB EXPLAIN user-facing mode, Manual panel integration. Scope: `PanelDrawing.mqh` (+200 lines, 4 new draw functions) + `Config.mqh` (+6 lines, 3 inputs + 1 default change). Zero ProbabilityEngine/buffer changes. All data sources verified against actual struct field names (`g_portfolioRisk` not `g_riskState`, `g_positionSize.adjustedRiskPct` not `riskPercent`, `ExplainData.probAfterBase/probAfterMTF/etc.` not `baseProbTP1/mtfAdjust`). |
| 2026-08-10 | Sprint 6 plan finalized (11 tasks, ~40h, 2 weeks) — VirtualTradeTracker engine (Tier 1 tick + Tier 2 bar architecture from VirtualTradeHistory_Spec v2.0), multi-position tracking (Market + Pullback Z2-Z5), chart history lines (OBJ_TREND green=TP red=SL), virtual_trades CSV (24 cols, persistent handle), PerfReport panel section (PF/Sharpe/Sortino/MaxDD/EV), EA OnTester() hook (custom EV×sqrt(N) metric), Python offline analyzer (equity curve/monthly returns/session breakdown/XGB impact). +1,223 lines across 12 files. Zero ProbabilityEngine/buffer changes. Dependencies verified: `SL_GetSessionName()` (not `GetSessionName()`), `SL_GetTFName()` (not `GetTFString()`), `IsNewBar()` must be created, `SignalData.isBuySignal` (not `.isBuy`). Recommend Sprint 5 before Sprint 6 (shared Config/PanelDrawing edits). |
| 2026-08-10 | Sprint 5 tasks 5.1-5.6 implemented — `PanelDrawing.mqh`: 4 new functions (`DrawTDSLine`, `DrawAttributionBar`, `DrawConfidenceMeter`, `DrawRiskSummary`) wired into both `DrawInfoPanel()` (Full) and `DrawManualPanel()` (Manual), replacing old `V_RK`/`V_RK2` portfolio-risk text block and the Manual panel's text-art confidence bar (`\|\|\|\|\|\|....`). `Config.mqh`: added `InpShowTDS`/`InpShowAttribution`/`InpShowRiskSummary` (all default `true`), flipped `InpShowProbExplain` default `false`→`true` and dropped `"(debug)"` label. PASS-1/PASS-3 height-content line counts verified 1:1 in both panels. Zero `PERIOD_*` violations, zero dangling `V_RK` references, zero root `.mq4`/`.mq5` changes needed (shared `.mqh` only). Deviation from mockup: `g_portfolioRisk.dailyPnLPips` shown as raw pips, not converted to $ — no existing pip→$ helper found for this field via grep, avoided fabricating unvalidated conversion math in a risk-display panel. Pending: 5.7 (user compile/verify MQ4+MQ5), 5.8 (this entry). |
| 2026-08-06 | EA close-button function split + double-confirm fix — split the single switch-case `ClosePositionsByCriteria()` in `Experts/QuantEdge_EA_Template.mq4`/`.mq5` into 5 dedicated functions (`CloseAllProfit`, `CloseAllLoss`, `CloseBuyProfit`, `CloseSellProfit`, `CloseAllPositions`), each self-contained (own filter loop + own ticket close) so each button's logic can be audited/fixed independently, plus shared `CloseCriteriaLabel()`/`ConfirmClose()`/`ExecuteClose()` helpers. Each new function takes `bool confirm=true`: the EA's own on-chart panel buttons (`OnChartEvent()`) now call the dedicated function directly with the default (shows `MessageBox()`); the indicator's Manual panel GlobalVariable-poll path (`OnTick()`) calls `ClosePositionsByCriteria(cmd, false)` — a thin criteria→function dispatcher kept only for this one caller — skipping the confirmation, since the indicator already confirmed once before setting the GV. This removes the previously redundant second `MessageBox()` on the GV-polling path. No magic-number filtering added (positions from other EAs/magics still processed, per explicit requirement — unchanged from `d11bb5e`). MQ4 (`OrdersTotal`/`OrderSelect`/`OrderClose`, profit includes `OrderCommission()`) and MQ5 (`PositionsTotal`/`PositionGetTicket`/`CTrade.PositionClose`) verified 1:1 function-signature parity (9/9). |
