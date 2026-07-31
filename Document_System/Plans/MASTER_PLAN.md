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
Sprint 4 ── XGB Auto-Train + SHAP ────────────── 2 tuần
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
| Sprint 2: Signal Interface | `NOT STARTED` | — | — | [SPRINT_2_SIGNAL_INTERFACE.md](SPRINT_2_SIGNAL_INTERFACE.md) |
| Sprint 3: Export API | `NOT STARTED` | — | — | [SPRINT_3_EXPORT_API.md](SPRINT_3_EXPORT_API.md) |
| Sprint 4: XGB Auto-Train | `NOT STARTED` | — | — | [SPRINT_4_XGB_AUTOTRAIN.md](SPRINT_4_XGB_AUTOTRAIN.md) |
| Sprint 5: Enhanced UX | `NOT STARTED` | — | — | [SPRINT_5_ENHANCED_UX.md](SPRINT_5_ENHANCED_UX.md) |
| Sprint 6: Backtest | `NOT STARTED` | — | — | [SPRINT_6_BACKTEST.md](SPRINT_6_BACKTEST.md) |

---

## Platform Readiness Score

| Criterion | Before | Target | Current |
|---|---|---|---|
| Measurable | 9/10 | 9/10 | 9/10 |
| Extensible | 7/10 | 9/10 | 7/10 |
| Maintainable | 6/10 | 8/10 | 6/10 |
| AI Training | 7/10 | 9/10 | 7/10 |
| EA Output | 0/10 | 7/10 | 0/10 |
| **Total** | **29/50** | **42/50** | **29/50** |

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
