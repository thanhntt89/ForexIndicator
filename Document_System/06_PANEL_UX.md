# QuantEdge — Panel UX & Trade Decision Summary

## 1. Hiện Trạng Panel (PanelDrawing.mqh — 1278 dòng, 54.7KB)

### Panel đã hiển thị

| Section | Nội dung | Trạng thái |
|---------|---------|-----------|
| Title Bar | "QuantEdge - BUY SIGNAL" + recommendation level | ✅ |
| Case Info | Case number + name + detail lines | ✅ |
| Time Info | Symbol, TF, signal time, broker UTC | ✅ |
| Probability | probTP1/TP2/TP3/SL % + bars-to-result | ✅ |
| Recommendation | STRONG ENTRY / ENTRY / CAUTION / WAIT / AVOID | ✅ |
| R:R Display | Risk/Reward ratio cho 3 TP levels | ✅ |
| Entry Zones | Price, lot, R:R, Reach%, Win%, EV per zone | ✅ |
| MTF Status | Multi-timeframe trend per TF | ✅ |
| V11 Extras | Intermarket, Brier, WalkForward, Spread, VolRegime | ✅ |
| Survival | Time-decay bar + survival ratio | ✅ |
| Rolling Perf | Last 10/20/50/All win rates | ✅ |
| Session Stats | Win rate per session block | ✅ |

### Recommendation Engine (Normalize.mqh, dòng 749-967)

```
ENUM_RECOMMENDATION:
  REC_STRONG_ENTRY    → Score ≥ 75 & EV > 0.15R  → Green "STRONG ENTRY"
  REC_ENTRY           → Score ≥ 55 & EV > 0.05R  → Green "ENTRY"
  REC_CAUTION_ENTRY   → Score ≥ 35 & EV > 0       → Yellow "CAUTION ENTRY"
  REC_WAIT            → EV > -0.05                 → Orange "WAIT"
  REC_AVOID           → EV ≤ -0.05                → Red "AVOID"
  REC_COUNTER_TREND   → MTF against + negative EV  → Red "AVOID (Counter Trend)"
```

Score = EV(0-50) + DataConfidence(0-25) + MTF(0-5) + Intermarket(0-10) + WF(±10) + Spread(0 to -7)

### Hard Gate
Nếu `probSamples < minReqSamples` → cap tại WAIT (không cho ENTRY dù EV dương — lý thuyết suông)

## 2. Thiếu Sót

### ⚠️ Trade Decision Summary (Chưa có)

Trader cần **1 dòng tóm tắt** để ra quyết định trong 2 giây:

```
BUY 0.15 lot @ 2345.50 | 67% TP1 | EV +1.2R | Kelly 8% → STRONG ENTRY
```

### ⚠️ PROB ATTRIBUTION (Chỉ debug mode)

`InpShowProbExplain = false` mặc định → trader không biết xác suất bị kéo xuống bởi yếu tố nào.

### ⚠️ Decision Dashboard

Chưa có panel riêng tổng hợp 3 câu trả lời cốt lõi:
1. Vào hay không?
2. Vào ở giá nào?
3. Vào bao nhiêu lot?

## 3. Thiết Kế Mới

### 3.1 Trade Decision Summary Line (TDS)

Thêm 1 dòng nổi bật nhất trên panel:

```mql4
// Hiển thị ngay dưới title bar:
string tds = dir + " " +
   DoubleToString(bestLotSize, 2) + " lot" +
   " @ " + DoubleToString(bestEntryPrice, _Digits) +
   " | " + DoubleToString(probTP1, 0) + "% TP" +
   " | EV+" + DoubleToString(ev, 2) + "R" +
   " | Kelly " + DoubleToString(kellyPct, 0) + "%" +
   " → " + rec.label;
```

Color:
- Green → STRONG / ENTRY
- Yellow → CAUTION
- Orange → WAIT
- Red → AVOID

### 3.2 Quick Attribution Bar

Thay thế debug-only PROB EXPLAIN bằng compact waterfall:

```
Edge 52% → MTF +2% → Inter -1% → GR 64% → Brier -3% → Decay -5% = 56%
```

Hiển thị dưới dạng 1 dòng text nhỏ (fs-2), màu theo positive/negative.

### 3.3 Confidence Meter

Visual bar hiển thị confidence 0-100:

```
Confidence: [████████████░░░░░░] 67/100
```

Dùng `CreateRectangleLabel` để tạo thanh progress bar.

### 3.4 Risk Summary Section

```
Account: $10,000 | Today: -$45 (-0.45%)
Risk Budget: 2.55% remaining | Circuit: OK
Suggested: 0.15 lot (1.2% risk) | Kelly: 8%
```

## 4. File Cần Sửa

| File | Hành động |
|------|----------|
| `Include/QuantEdge/PanelDrawing.mqh` | Thêm TDS line + Attribution bar + Confidence meter |
| `Include/QuantEdge/Config.mqh` | Thêm `InpShowDecisionSummary` input (default true) |
| `Include/QuantEdge/Normalize.mqh` | Mở rộng `TradeRecommendation` struct thêm lotSize, bestZone |
