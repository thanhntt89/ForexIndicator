# QuantEdge — Implementation Roadmap

## Lộ Trình Xây Dựng Platform

---

## Sprint 0: Foundation (1 tuần) — ƯU TIÊN CAO NHẤT

### Mục tiêu: Hoàn thiện core decision engine hiện có

| # | Task | File | Effort |
|---|------|------|--------|
| 0.1 | Tạo `PositionSizing.mqh` module mới | `Include/QuantEdge/PositionSizing.mqh` | 2h |
| 0.2 | Kết nối Kelly Fraction → lot calculation | `PositionSizing.mqh` + `SLTP.mqh` | 3h |
| 0.3 | Thêm VolScale + BrierScale vào lot | `PositionSizing.mqh` | 2h |
| 0.4 | Thêm Trade Decision Summary line lên panel | `PanelDrawing.mqh` | 2h |
| 0.5 | Test compile + behavior unchanged | `make.ps1` | 1h |

**Deliverable:** Khi signal xuất hiện, panel hiện:
```
BUY 0.15 lot @ 2345.50 | 67% TP | EV +1.2R → STRONG ENTRY
```

---

## Sprint 1: Risk Budget (1 tuần)

### Mục tiêu: Dynamic risk allocation

| # | Task | File | Effort |
|---|------|------|--------|
| 1.1 | Upgrade RiskManager: DD Scaling (3 levels) | `RiskManager.mqh` | 3h |
| 1.2 | EV-based risk share cho Entry Zones | `SLTP.mqh` | 2h |
| 1.3 | Risk Budget display trên panel | `PanelDrawing.mqh` | 2h |
| 1.4 | Config inputs: MinRiskPct, MaxRiskCap | `Config.mqh` | 1h |
| 1.5 | Integration test | | 2h |

**Deliverable:** Lot tự động giảm khi thua liên tục, tăng khi thắng.

---

## Sprint 2: Signal Interface (2 tuần)

### Mục tiêu: Tách RSI thành plugin, chuẩn bị pluggable platform

| # | Task | File | Effort |
|---|------|------|--------|
| 2.1 | Tạo `Signals/ISignalSource.mqh` interface | `Include/QuantEdge/Signals/` | 2h |
| 2.2 | Refactor RSI → `Signals/RSISignal.mqh` | `RSISignal.mqh` | 8h |
| 2.3 | Update main file dùng Signal_Detect*() | `QuantEdge_RSI.mq4/5` | 4h |
| 2.4 | Verify compile + behavior 100% unchanged | | 4h |
| 2.5 | Update ProbabilityEngine nhận signal-agnostic data | `ProbabilityEngine.mqh` | 4h |

**Deliverable:** RSI code tách riêng, main file gọi qua interface.

---

## Sprint 3: Enhanced UX (1 tuần)

### Mục tiêu: Panel thông tin cho trader ra quyết định nhanh

| # | Task | File | Effort |
|---|------|------|--------|
| 3.1 | Quick Attribution Bar (1-line waterfall) | `PanelDrawing.mqh` | 3h |
| 3.2 | Confidence Meter (visual bar) | `PanelDrawing.mqh` | 2h |
| 3.3 | Risk Summary section (account, DD, budget) | `PanelDrawing.mqh` | 2h |
| 3.4 | Bật PROB EXPLAIN cho user (không chỉ debug) | `Config.mqh` + `PanelDrawing.mqh` | 1h |

**Deliverable:** Panel chuyên nghiệp, đầy đủ data ra quyết định trong 3 giây.

---

## Sprint 4: XGBoost Auto-Training (2 tuần)

### Mục tiêu: AI tự học từ data

| # | Task | File | Effort |
|---|------|------|--------|
| 4.1 | Python auto-training script | `tools/auto_train_xgb.py` | 8h |
| 4.2 | Model versioning + rollback | `tools/model_manager.py` | 4h |
| 4.3 | Feature importance export (SHAP) | `tools/feature_importance.py` | 4h |
| 4.4 | A/B shadow mode trong indicator | `XGBIntegration.mqh` | 4h |

**Deliverable:** Chạy 1 lệnh → tự train từ CSV logs → export model → indicator load tự động.

---

## Sprint 5: Backtest Engine (2 tuần)

### Mục tiêu: Virtual trading simulation tự động

| # | Task | File | Effort |
|---|------|------|--------|
| 5.1 | Virtual trade simulator | `Include/QuantEdge/BacktestEngine.mqh` | 12h |
| 5.2 | Performance report (PF, WR, MaxDD, Sharpe) | `Include/QuantEdge/PerfReport.mqh` | 6h |
| 5.3 | CSV export cho analysis | `BacktestEngine.mqh` | 2h |

**Deliverable:** Chạy trên MT4 Strategy Tester → tự động collect performance metrics.

---

## Sprint 6: Export API (1 tuần)

### Mục tiêu: Gửi tín hiệu cho EA tự động vào lệnh

| # | Task | File | Effort |
|---|------|------|--------|
| 6.1 | File-based signal export (JSON/pipe) | `Include/QuantEdge/SignalExport.mqh` | 4h |
| 6.2 | EA receiver template | `QuantEdge_EA_Template.mq4` | 4h |
| 6.3 | Telegram/Discord webhook (optional) | `tools/webhook_sender.py` | 4h |

**Deliverable:** QuantEdge indicator → file → EA đọc → tự vào lệnh.

---

## Tổng Timeline

| Sprint | Thời gian | Cumulative |
|--------|----------|------------|
| Sprint 0: Foundation | 1 tuần | Tuần 1 |
| Sprint 1: Risk Budget | 1 tuần | Tuần 2 |
| Sprint 2: Signal Interface | 2 tuần | Tuần 4 |
| Sprint 3: Enhanced UX | 1 tuần | Tuần 5 |
| Sprint 4: XGB Auto-Train | 2 tuần | Tuần 7 |
| Sprint 5: Backtest Engine | 2 tuần | Tuần 9 |
| Sprint 6: Export API | 1 tuần | Tuần 10 |

**Tổng: ~10 tuần** (nếu làm full-time)

---

## Nguyên Tắc Quan Trọng

> [!CAUTION]
> **KHÔNG BAO GIỜ** thay đổi ProbabilityEngine pipeline mà không chạy Walk-Forward validation trước và sau.
> Mọi thay đổi ảnh hưởng xác suất PHẢI có backtest so sánh trước/sau.

> [!IMPORTANT]
> **Mỗi Sprint** phải kết thúc bằng compile test + behavior verification.
> Không merge code chưa compile thành công.

> [!TIP]
> Sprint 0 và Sprint 1 tạo ra 80% giá trị platform.
> Có thể dùng ngay sau Sprint 1 mà không cần đợi Sprint 2-6.
