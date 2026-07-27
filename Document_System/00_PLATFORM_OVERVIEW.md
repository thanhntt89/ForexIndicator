# QuantEdge Platform — Tổng Quan & Tầm Nhìn

## 1. Tầm Nhìn Sản Phẩm

**QuantEdge** là một **Quantitative Decision-Support Platform** (Nền tảng hỗ trợ quyết định giao dịch định lượng) chạy trên MetaTrader 4/5.

### Mục tiêu cốt lõi
Khi tín hiệu xuất hiện trên chart, trader cần 3 câu trả lời tức thì:

| # | Câu hỏi | Platform trả lời bằng |
|---|---------|----------------------|
| 1 | **Vào hay không?** | Xác suất TP/SL có lợi thế thống kê (Bayesian + XGBoost) |
| 2 | **Vào ở giá nào?** | Multi-Entry Zone với EV riêng cho từng vùng giá |
| 3 | **Vào bao nhiêu lot?** | Position Sizing dựa trên Kelly Fraction + Risk Budget |

### Kiến trúc tầng Platform

```
┌──────────────────────────────────────────────────────────┐
│                    DISPLAY LAYER                          │
│  PanelDrawing │ LineDrawing │ ArrowManager │ ChartEvents  │
└──────────────┬───────────────────────────────────────────┘
               │
┌──────────────┴───────────────────────────────────────────┐
│                  DECISION ENGINE                          │
│  ProbabilityEngine │ WalkForward │ CalibrationEngine      │
│  XGBIntegration    │ RiskManager │ SessionStatistics      │
│  IntermarketAnalysis │ MarketRegime                       │
└──────────────┬───────────────────────────────────────────┘
               │
┌──────────────┴───────────────────────────────────────────┐
│                  SIGNAL LAYER (pluggable)                  │
│  RSICore │ SignalCases │ SignalEngine │ SwingDetection     │
│  SLTP    │ Normalize   │ CandleNormalize │ MathUtils      │
└──────────────┬───────────────────────────────────────────┘
               │
┌──────────────┴───────────────────────────────────────────┐
│                  DATA / INFRA LAYER                        │
│  Config │ Globals │ Structs │ TFConfig │ MQLCompat        │
│  SignalLogger │ SessionFilter │ VolumeAnalysis             │
│  VolatilityAnalysis │ XGBModel                            │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Đánh Giá Hiện Trạng (Readiness Assessment)

### ✅ ĐÃ CÓ (78% platform)

| Thành phần | Module | Trạng thái |
|------------|--------|-----------|
| Signal Detection (9 Cases) | RSICore, SignalCases | ✅ Production |
| SL/TP Calculation (ATR+Fib+Hybrid) | SLTP | ✅ Production |
| Bayesian Probability Pipeline | ProbabilityEngine (81KB) | ✅ Production |
| Multi-Timeframe Agreement | MTFEngine | ✅ Production |
| Walk-Forward IS/OOS Validation | WalkForward (28KB) | ✅ Production |
| Brier Score Calibration | CalibrationEngine | ✅ Production |
| XGBoost AI Integration | XGBIntegration + XGBModel | ✅ Production |
| Entry Zone System | SLTP (CalculateEntryZones) | ✅ Production |
| Session Statistics | SessionStatistics (29KB) | ✅ Production |
| Intermarket Correlation | IntermarketAnalysis | ✅ Production |
| Market Regime Detection | MarketRegime | ✅ Production |
| Signal Logging / CSV Export | SignalLogger (26KB) | ✅ Production |
| Portfolio Risk (circuit breaker) | RiskManager | ✅ Production |
| Kelly Fraction (Half-Kelly) | WalkForward | ✅ Computed |
| Info Panel + Chart Events | PanelDrawing, ChartEvents | ✅ Production |
| TF Auto-Config | TFConfig | ✅ Production |

### ⚠️ CÓ NHƯNG CHƯA ĐỦ (cần nâng cấp)

| Thành phần | Vấn đề | Cần làm |
|------------|--------|---------|
| **Lot Size Calculator** | EntryZone.lotSize đã tính nhưng dùng risk% cố định, chưa dùng Kelly | Xem `02_LOT_SIZING.md` |
| **Risk Budget** | RiskManager có circuit breaker nhưng chưa phân bổ risk theo xác suất | Xem `04_RISK_MANAGER.md` |
| **PROB ATTRIBUTION panel** | Hiện chỉ debug mode (InpShowProbExplain=false) | Xem `06_PANEL_UX.md` |
| **Signal Pluggability** | RSI gắn chặt vào main file, chưa là interface | Xem `01_ARCHITECTURE.md` |

### ❌ CHƯA CÓ (22% còn thiếu)

| Thành phần | Ưu tiên | Mô tả |
|------------|---------|-------|
| **Position Sizing Engine** | P0 | Module riêng tính lot dựa trên Kelly × xác suất × volatility regime |
| **Signal Interface** | P1 | Interface trừu tượng cho phép plug MACD, Price Action, etc. |
| **Trade Decision Summary** | P1 | Panel tổng hợp 1 dòng: "BUY 0.15 lot @ 2345.50 | 67% TP | EV +1.2R" |
| **Backtest Engine** | P2 | Virtual trade simulation tự động trên dữ liệu lịch sử |
| **Config Presets** | P2 | Scalping / Swing / Conservative preset |
| **Export API** | P3 | Gửi tín hiệu qua file/pipe cho EA tự động vào lệnh |

---

## 3. Danh Sách Tài Liệu Chi Tiết

| File | Nội dung |
|------|---------|
| `01_ARCHITECTURE.md` | Kiến trúc platform chi tiết + dependency graph |
| `02_LOT_SIZING.md` | Thuật toán Position Sizing Engine |
| `03_PROBABILITY_PIPELINE.md` | Pipeline xác suất 7 bước |
| `04_RISK_MANAGER.md` | Risk Budget + Circuit Breaker + Drawdown |
| `05_SIGNAL_INTERFACE.md` | Thiết kế Signal Interface cho pluggable signals |
| `06_PANEL_UX.md` | Thiết kế Panel UX + Trade Decision Summary |
| `07_WALKFORWARD.md` | Walk-Forward Validation + Anti-Overfitting |
| `08_XGB_AI.md` | XGBoost Integration + Auto-Training |
| `09_ENTRY_ZONES.md` | Multi-Entry Zone System |
| `10_IMPLEMENTATION_ROADMAP.md` | Lộ trình thực hiện theo Sprint |

---

## 4. Technology Stack

| Layer | Công nghệ |
|-------|-----------|
| Platform Runtime | MQL4 / MQL5 (cross-platform via MQLCompat.mqh) |
| AI Training | Python + XGBoost + Binary model export |
| Data Pipeline | CSV logging + Binary model files |
| Build System | PowerShell (make.ps1) + MetaEditor |
| Version Control | Git + GitHub (thanhntt89/ForexIndicator) |
