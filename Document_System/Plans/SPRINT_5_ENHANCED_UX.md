# Sprint 5: Enhanced UX

> **Goal:** Panel UX nâng cấp — trader ra quyết định trong 2 giây, attribution minh bạch, risk budget rõ ràng
> **Duration:** 1 week (~20h)
> **Prerequisite:** Sprint 0 (PositionSizing) + Sprint 1 (Risk Budget) + Sprint 3 (EA Export)
> **Status:** `IN PROGRESS` (5.1-5.6 code DONE, awaiting 5.7 user compile/verify)

---

## Scope Assessment

### Đã có (post-Sprint 3/4 follow-ups):
- Manual Dashboard mode (`DASHBOARD_MANUAL` vs `DASHBOARD_FULL`) — DONE
- `DrawDashboard()` single dispatcher — DONE
- Close buttons trên indicator panel (5 buttons + GV command) — DONE
- Drag/collapse + state persistence — DONE
- Text-art confidence bar trong Manual mode (`[||||||||..]`) — DONE (partial)

### Chưa có (Sprint 5 scope):
1. **Trade Decision Summary line (TDS)** — NOT DONE
2. **Quick Attribution Bar** (compact waterfall 1-line) — NOT DONE
3. **Confidence Meter** (visual `CreateRectangleLabel` bar) — NOT DONE (chỉ có text-art)
4. **Risk Summary section** (account $, daily P&L, budget remaining) — PARTIAL (format khác plan)
5. **PROB EXPLAIN exposed** (default `true` hoặc compact version) — NOT DONE (vẫn `false` + "(debug)")

### Nguyên tắc:
- **KHÔNG thay đổi ProbabilityEngine** — chỉ đọc data, render UX (Rule #2 safe)
- **KHÔNG thêm buffer** — EA contract 25 buffers bảo toàn
- MQ4/MQ5 shared `.mqh` — thay đổi tự động apply cả hai platform
- User tự compile (Rule #5)

---

## Tasks

| # | Task | Status | Files | Effort |
|---|---|---|---|---|
| 5.1 | Trade Decision Summary line (TDS) | `DONE` | `PanelDrawing.mqh`, `Config.mqh` | 3h |
| 5.2 | Quick Attribution Bar (compact waterfall) | `DONE` | `PanelDrawing.mqh`, `Config.mqh` | 3h |
| 5.3 | Confidence Meter (visual rectangle bar) | `DONE` | `PanelDrawing.mqh` | 2h |
| 5.4 | Risk Summary section (account + P&L + budget) | `DONE` | `PanelDrawing.mqh` | 3h |
| 5.5 | PROB EXPLAIN user-facing mode | `DONE` | `Config.mqh`, `PanelDrawing.mqh` | 2h |
| 5.6 | Manual panel integration (TDS + Attribution + Meter) | `DONE` | `PanelDrawing.mqh` | 3h |
| 5.7 | MQ4/MQ5 sync verify + compile test — USER | `NOT STARTED` | *(user task)* | 1h |
| 5.8 | Update MASTER_PLAN + this file | `IN PROGRESS` | `MASTER_PLAN.md`, this file | 0.5h |

---

### 5.1 Trade Decision Summary Line (TDS)

**Mục tiêu:** 1 dòng nổi bật nhất trên panel — trader đọc xong biết ngay vào hay không.

**Vị trí:** Ngay dưới title bar (trước Case Info), cả Full và Manual mode.

**Format:**
```
BUY 0.15 lot @ 2345.50 | 67% TP1 | EV +1.2R | Kelly 8% → STRONG ENTRY
```

**Data sources (tất cả đã có):**
| Field | Source |
|---|---|
| Direction | `g_signals[idx].isBuySignal` |
| Lot size | `g_positionSize.recommendedLot` |
| Entry price | `g_entryZones[0].price` (best zone) hoặc `g_signals[idx].entryPrice` |
| Prob TP1 | `g_currentProb.probTP1` |
| EV | `rec.ev` (từ `TradeRecommendation`) |
| Kelly % | `g_positionSize.kellyPct` (từ `PositionSizeData`, không nằm trong `TradeRecommendation`) |
| Recommendation | `rec.label` |

**Config:**
```mql4
input bool InpShowTDS = true; // Show Trade Decision Summary
```

**Color logic:**
- `REC_STRONG_ENTRY` / `REC_ENTRY` → `clrLime`
- `REC_CAUTION_ENTRY` → `clrYellow`
- `REC_WAIT` → `clrOrange`
- `REC_AVOID` / `REC_COUNTER_TREND` → `clrRed`
- No signal → `clrGray`, text = "— No Active Signal —"

**Implementation:** Hàm `DrawTDSLine(int &y, ...)` trong `PanelDrawing.mqh`, gọi từ cả `DrawInfoPanel()` và `DrawManualPanel()`.

---

### 5.2 Quick Attribution Bar (Compact Waterfall)

**Mục tiêu:** 1 dòng compact thay thế debug panel 20 dòng — trader thấy ngay yếu tố nào kéo xác suất lên/xuống.

**Format:**
```
Edge 52% → MTF +2% → Inter -1% → Vol 0% → Brier -3% → Decay -5% = 45%
```

**Data source:** `ExplainData` struct (đã đầy đủ trong `ProbabilityEngine.mqh`).

| Component | Field | Computation |
|---|---|---|
| Edge (base) | `explain.probAfterBase` | Base probability from historical data |
| MTF adj | `explain.probAfterMTF - explain.probAfterBase` | Delta from MTF alignment |
| Inter adj | `explain.probAfterInter - explain.probAfterMTF` | Delta from intermarket |
| Vol adj | `explain.probAfterMktSt - explain.probAfterInter` | Delta from market state/vol regime |
| Brier adj | `explain.probAfterBrier - explain.probAfterMktSt` | Delta from Brier calibration shrinkage |
| Decay | `explain.probFinal - explain.probAfterBrier` | Delta from survival/time-decay |
| Final | `explain.probFinal` | Final adjusted probability |

> **Note:** `ExplainData` struct stores running probabilities (`probAfterBase`, `probAfterMTF`, etc.) and edge deltas (`edgeMTF`, `edgeInter`, `edgeMktSt`). The waterfall computes visible deltas as differences between successive `probAfter*` fields.

**Color per component:** Positive → `clrLime`, Negative → `clrTomato`, Zero → `clrGray`.

**Config:**
```mql4
input bool InpShowAttribution = true; // Show probability attribution bar
```

**Vị trí:** Ngay dưới TDS line (cả Full và Manual mode). Font size nhỏ hơn (8pt vs 10pt).

**Implementation:** Hàm `DrawAttributionBar(int &y, const ExplainData &explain)` trong `PanelDrawing.mqh`.

---

### 5.3 Confidence Meter (Visual Rectangle Bar)

**Mục tiêu:** Thanh progress bar đồ họa thay thế text-art `[||||..]`.

**Visual:**
```
Confidence: [██████████████░░░░░░░░] 67/100
             ← green fill →← gray bg →
```

**Implementation:**
- 2 `OBJ_RECTANGLE_LABEL` objects:
  - Background bar (full width, `clrDarkSlateGray`)
  - Fill bar (proportional width, color theo confidence level)
- Text label `"67/100"` overlay bằng `OBJ_LABEL`

**Color thresholds:**
| Confidence | Fill Color |
|---|---|
| ≥ 70 | `clrLime` |
| ≥ 50 | `clrYellow` |
| ≥ 30 | `clrOrange` |
| < 30 | `clrRed` |

**Bar dimensions:** Width = 200px (scaled), Height = 14px. Object prefix = `PREFIX_PANEL + "CONF_"`.

**Áp dụng:** Cả Full panel (thay text `[67/100]`) và Manual panel (thay text-art bar).

**Implementation:** Hàm `DrawConfidenceMeter(int &y, int confidence)` trong `PanelDrawing.mqh`. Cleanup trong `DeleteObjectsByPrefix()` đã xử lý tự động vì dùng `PREFIX_PANEL`.

---

### 5.4 Risk Summary Section

**Mục tiêu:** 3 dòng compact — account state + risk budget + suggestion.

**Format (Full panel):**
```
Account: $10,000.00 | Today: -$45.30 (-0.45%)
Risk Budget: 2.55% remaining | Circuit: GREEN
Suggested: 0.15 lot (1.2% risk) | Kelly: 8%
```

**Format (Manual panel):** 2 dòng rút gọn:
```
$10,000 | Today -$45 | Budget 2.55% | Circuit OK
0.15 lot (1.2%) | Kelly 8%
```

**Data sources:**
| Field | Source | API |
|---|---|---|
| Account balance | Live | `AccountBalance()` (cross-platform, wrapped in `MQLCompat.mqh`) |
| Today P&L | Computed | `g_portfolioRisk.dailyPnLPips` (already tracked in `RiskManager.mqh`) |
| Risk budget remaining | Computed | `InpMaxDailyRiskPct - g_portfolioRisk.dailyDrawdownPct` |
| Circuit status | `g_portfolioRisk` | `g_portfolioRisk.cbLevel` (int 0-3: GREEN/YELLOW/ORANGE/RED) |
| Circuit active | `g_portfolioRisk` | `g_portfolioRisk.circuitBreakerActive` (bool) |
| Suggested lot | `g_positionSize` | `g_positionSize.recommendedLot` |
| Suggested risk % | `g_positionSize` | `g_positionSize.adjustedRiskPct` |
| Kelly % | `g_positionSize` | `g_positionSize.kellyPct` |

> **Note:** `AccountProfit()` trả về floating P&L of open positions, KHÔNG phải daily P&L. Dùng `g_portfolioRisk.dailyPnLPips` (đã computed trong `RiskManager.mqh`) cho today's P&L chính xác hơn. Để convert sang $: `dailyPnLPips × tickValue × lotSize`.

**Thay thế:** Dòng risk hiện tại trong V11 Extras section (lines 1202-1239) → gộp vào Risk Summary mới. Không duplicate.

**Config:**
```mql4
input bool InpShowRiskSummary = true; // Show risk summary section
```

**Implementation:** Hàm `DrawRiskSummary(int &y, bool compact)` trong `PanelDrawing.mqh`.

> **Deviation (actual impl):** Không convert `dailyPnLPips` sang $ — grep toàn codebase không tìm thấy pip→$ helper nào cho field này (không phải `AccountProfit()`), nên hiển thị trực tiếp `+X.X pips` thay vì `$X.XX` để tránh tự bịa công thức convert chưa validate. Format thực tế: `Today: +12.3 pips` (Full) / `Today +12pips` (Manual).

---

### 5.5 PROB EXPLAIN User-Facing Mode

**Mục tiêu:** Cho user xem probability breakdown mà không cần bật debug mode.

**Phương án:** Thay đổi `InpShowProbExplain` behavior:
- Đổi tên input: `InpShowProbExplain` → giữ nguyên tên (backward compat)
- Đổi default: `false` → `true`
- Đổi comment: `"Show probability attribution panel (debug)"` → `"Show probability attribution panel"`
- Nếu `InpShowAttribution = true` (task 5.2 — compact bar trên main panel):
  - `InpShowProbExplain = true` → hiện side panel CHI TIẾT (20 dòng, như hiện tại)
  - `InpShowProbExplain = false` → ẩn side panel (compact bar đã đủ)
- Nếu `InpShowAttribution = false`:
  - `InpShowProbExplain = true` → hiện side panel (fallback cho user muốn chi tiết)
  - `InpShowProbExplain = false` → ẩn tất cả attribution

**File changes:**
- `Config.mqh`: Đổi default + comment
- `PanelDrawing.mqh`: Không thay đổi logic `DrawExplainPanel()` — chỉ đổi gate condition

---

### 5.6 Manual Panel Integration

**Mục tiêu:** Integrate TDS + Attribution + Confidence Meter vào `DrawManualPanel()`.

**Layout Manual panel (sau Sprint 5):**
```
┌─────────────────────────────────────┐
│ QuantEdge — BUY SIGNAL         [—] │  ← title bar (existing)
│ BUY 0.15 @ 2345 | 67% | +1.2R     │  ← TDS line (5.1) — rút gọn
│ Edge52→MTF+2→Int-1→Vol0→Br-3=45%  │  ← Attribution (5.2) — font nhỏ
│ Confidence: [████████░░░] 67/100   │  ← Meter (5.3) — thay text-art
│ Entry: 2345.50  SL: 2340.00       │  ← Price levels (existing)
│ TP1: 2355 (67% 2.0R)              │
│ TP2: 2365 (45% 3.2R)              │
│ TP3: 2380 (28% 5.1R)              │
│ $10,000 | Today -$45 | Budget 2.5% │  ← Risk (5.4) — compact
│ 0.15 lot (1.2%) | Kelly 8%        │
│ MTF: ↑H1 ↑H4 ↑D1 — Aligned 100%  │  ← MTF (existing)
│ Expires: 14:30 (2h 15m)           │  ← Expiry (existing)
│ [Close+] [Close-] [Buy+] [Sell+]  │  ← Close buttons (existing)
│ [        CLOSE ALL          ]      │
└─────────────────────────────────────┘
```

**Implementation:** Chèn gọi `DrawTDSLine()`, `DrawAttributionBar()`, `DrawConfidenceMeter()`, `DrawRiskSummary(compact=true)` vào `DrawManualPanel()` tại vị trí thích hợp. Cập nhật `y` offset cho các section phía dưới.

---

### 5.7 MQ4/MQ5 Sync + Compile — USER

Tất cả thay đổi nằm trong shared `.mqh` files → tự động sync. User verify:
- Compile `QuantEdge_RSI.mq4` — 0 errors
- Compile `QuantEdge_RSI.mq5` — 0 errors
- Visual check: Full panel có TDS + Attribution + Meter + Risk Summary
- Visual check: Manual panel có layout mới
- Check `InpShowProbExplain = true` default → side panel hiện

---

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Panel quá dài (nhiều dòng mới) | TDS + Attribution chỉ thêm 2 dòng. Meter thay thế text. Risk Summary gộp V11 risk lines. Net thêm ~3 dòng Full, ~2 dòng Manual. |
| `CreateRectangleLabel` z-order conflict | Dùng `PREFIX_PANEL + "CONF_"` prefix → cleanup chung. `OBJPROP_BACK = false` đảm bảo render trên foreground. |
| Account data không available trong tester | `IsBacktestMode()` guard → ẩn Risk Summary section khi chạy tester (balance/profit meaningless). |
| Attribution bar quá dài trên timeframe nhỏ | Truncate component names: "Edge", "MTF", "Int", "Vol", "Br", "Dec". Max ~50 chars. |

---

## Files Changed Summary

| File | Action | Lines ± (est.) |
|---|---|---|
| `Include/QuantEdge/Display/PanelDrawing.mqh` | Add 4 new draw functions + integrate into both panels | +200, -30 |
| `Include/QuantEdge/Core/Config.mqh` | Add 3 inputs (`InpShowTDS`, `InpShowAttribution`, `InpShowRiskSummary`), change `InpShowProbExplain` default | +6, -1 |

**Zero changes to:** `ProbabilityEngine.mqh`, `Normalize.mqh`, `WalkForward.mqh`, `SignalLogger.mqh`, buffer count, EA template.
