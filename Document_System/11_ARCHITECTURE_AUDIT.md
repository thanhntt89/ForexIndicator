# QuantEdge — Architecture Audit (4 Criteria)

> Đánh giá khách quan thiết kế hiện tại theo 4 tiêu chí chất lượng platform.

---

## Tiêu Chí 1: Có Thể Đo Lường Được (Measurable)

### ✅ ĐÃ ĐẠT — Cực kỳ mạnh

| Cơ chế đo lường | File | Mô tả |
|----------------|------|-------|
| Brier Score per-case | `CalibrationEngine.mqh` | Đo độ calibration xác suất 0.0–0.25 |
| Walk-Forward IS/OOS | `WalkForward.mqh` | IS vs OOS win rate, overfit ratio <1.15 |
| Permutation p-value | `WalkForward.mqh` | p<0.05 → edge có ý nghĩa thống kê |
| Information Coefficient | `WalkForward.mqh` | Pearson(angleStrength, outcome) |
| Kelly Fraction | `WalkForward.mqh` | Optimal sizing dựa trên edge thực đo |
| Rolling Win Rate | `WalkForward.mqh` | Last 10/20/50/All — trend detection |
| Session Win Rate | `SessionStatistics.mqh` | Per-session × per-case (n>=20) |
| Signal Score 0-100 | `SignalEngine.mqh` | EV(50) + DataConf(25) + MTF(5) + Inter(10) + WF(±10) |
| Expected Value per zone | `SLTP.mqh` | EV = probReach * (winRate*RR - lossRate*1) |
| Survival Ratio | `ProbabilityEngine.mqh` | Weibull survival — edge còn lại bao nhiêu |

**Verdict:** Platform đo được TẤT CẢ các metrics quan trọng nhất của một quant system.
Mọi xác suất, score, EV đều traceable qua PROB ATTRIBUTION panel — không có "black box".

---

## Tiêu Chí 2: Dễ Mở Rộng (Extensible)

### ⚠️ CẦN CẢI THIỆN — 70% đạt

#### ✅ Đã extensible tốt:

| Module | Mức độ | Lý do |
|--------|--------|-------|
| `XGBModel.mqh` | Cao | Load bất kỳ binary model nào |
| `CalibrationEngine.mqh` | Cao | Chỉ cần g_signals[] và g_outcomes[] |
| `WalkForward.mqh` | Cao | Không biết gì về signal source |
| `MQLCompat.mqh` | Cao | Pure adapter, zero business logic |
| `TFConfig.mqh` | Tốt | Thêm timeframe mới = thêm 1 profile |

#### ❌ Tight coupling (blockers):

| Module | Vấn đề | Impact |
|--------|--------|--------|
| `RSICore.mqh` → Main | Gọi trực tiếp `BufferGreen[]` | Không thể thêm MACD/PA |
| `SLTP.mqh` → `ProbabilityEngine.mqh` | Gọi `SimulateSignalOutcome()` trực tiếp | Không tách được |
| `PanelDrawing.mqh` → All | Đọc trực tiếp tất cả global structs | Fragile |

#### Fix cần thiết (Sprint 2):
```
Thêm: Include/QuantEdge/Signals/ISignalSource.mqh
  Signal_Init(), Signal_Calculate(), Signal_DetectBuy(), Signal_DetectSell()

Kết quả: Thêm tín hiệu mới = 1 file mới + 1 dòng include
```

---

## Tiêu Chí 3: Dễ Maintain (Maintainable)

### ⚠️ CẦN CẢI THIỆN — 65% đạt

#### ✅ Maintainable tốt:

| Yếu tố | Trạng thái |
|--------|-----------|
| Module separation rõ ràng (31 files theo layer) | OK |
| Config centralized trong Config.mqh | OK |
| Anti-overfitting comments giải thích WHY | OK |
| Document System (11 files .md) | OK |

#### ❌ Maintainability issues:

| Issue | Severity |
|-------|---------|
| `ProbabilityEngine.mqh` 81KB/1711 dòng — God module | Cao |
| `SLTP.mqh` mix SL/TP + Entry Zones + Lot size | Trung bình |
| `PanelDrawing.mqh` đọc tất cả globals | Trung bình |
| Không có unit tests | Cao |

#### Fix cần thiết:
```
1. Tách ProbabilityEngine: BayesianEngine + SessionBlend + TimeDecay
2. Tạo PanelDataProvider struct (panel đọc 1 struct, không access globals)
3. Thêm unit test script (PowerShell/Python)
```

---

## Tiêu Chí 4: AI Training Support

### ✅ CƠ BẢN ĐÃ ĐẠT — 75% đạt

#### ✅ Đã có:

| Component | File | Mô tả |
|-----------|------|-------|
| Training data logging | `SignalLogger.mqh` | 3 CSV: signals + scoring + outcomes |
| JOIN key | `SIGNAL_ID` | Nối signals ↔ outcomes |
| XGBoost model loader | `XGBModel.mqh` | Binary tree loader |
| 19-feature input | `XGBIntegration.mqh` | RSI, ATR, session, case, MTF, WF... |
| Brier-weighted ensemble | `XGBIntegration.mqh` | Auto-weight model tốt hơn |

#### Data Pipeline hiện có:
```
MT4/5 → SignalLogger → signals.csv + scoring.csv + outcomes.csv
                           (Python script)
              train_xgboost.py → model.bin → MQL4/Files/QuantEdge_XGB/
                           (Indicator load)
              XGBModel.mqh loads model on start → predict per signal
```

#### ❌ Thiếu:

| Thiếu | Sprint |
|-------|--------|
| Python auto-training script | Sprint 4 |
| Model versioning + rollback | Sprint 4 |
| Feature importance export (SHAP) | Sprint 4 |
| A/B shadow mode compare models | Sprint 4 |

---

## Tiêu Chí 5: Output Cho EA

### ❌ CHƯA CÓ — 0% (Sprint 6)

Hiện tại luồng là: **Indicator → Trader → Manual trade**
Cần thêm: **Indicator → File → EA → Auto trade**

#### Thiết kế SignalExport (cần build):

```mql4
// Include/QuantEdge/SignalExport.mqh
struct ExportedSignal {
   string  symbol;
   int     direction;       // 1=BUY, -1=SELL
   double  entryPrice;      // Best zone entry
   double  stopLoss;
   double  takeProfit1;
   double  lotSize;         // From PositionSizing
   double  probTP1;         // Win probability
   double  expectedValue;   // EV in R
   int     confidence;      // 0-100 score
   string  recommendation;  // "STRONG ENTRY" / "ENTRY" / "WAIT" / "AVOID"
   datetime signalTime;
   datetime expiryTime;     // Auto-expire sau N bars
};

// Output: MQL4/Files/QuantEdge_Signal.json (1 file, overwrite mỗi update)
```

#### EA Receiver logic:
```
1. Đọc QuantEdge_Signal.json mỗi tick
2. Kiểm tra: expiryTime > TimeCurrent()
3. Kiểm tra: recommendation IN ("STRONG ENTRY", "ENTRY")
4. Kiểm tra: confidence >= InpMinConfidence (e.g. 65)
5. Kiểm tra: chưa có lệnh cùng direction
6. Vào lệnh với lotSize từ file
```

---

## Tóm Tắt Đánh Giá

| Tiêu chí | Điểm | Trạng thái |
|---------|------|-----------|
| Measurable (Đo lường) | **9/10** | Xuất sắc — đầy đủ Brier, WF, IC, Kelly, EV |
| Extensible (Mở rộng) | **7/10** | Tốt — cần tách Signal Interface |
| Maintainable (Maintain) | **6/10** | Trung bình — cần tách ProbEngine + tests |
| AI Training Support | **7/10** | Tốt — cần auto-training script |
| EA Output | **0/10** | Chưa có — cần Sprint 6 |
| **TỔNG** | **29/50** | **58% — platform potential cao, cần 5 Sprint** |

---

## Gaps Cần Lấp (Theo Thứ Tự Ưu Tiên)

### P0 — Blocking (Sprint 0, tuần 1)
1. **`PositionSizing.mqh`** — Kelly → Lot (hiện Kelly chỉ hiển thị, chưa dùng)
2. **`SignalExport.mqh`** skeleton — EA cần output này

### P1 — Important (Sprint 1-2, tuần 2-4)
3. **`ISignalSource.mqh`** interface — tách RSI thành plugin
4. **Dynamic Risk Budget** — lot giảm khi thua liên tục

### P2 — Enhancement (Sprint 3-4, tuần 5-7)
5. **`auto_train_xgb.py`** — Python tự động training XGBoost
6. **Panel Decision Summary** — 1 dòng tóm tắt cho trader

### P3 — Long-term (Sprint 5-6, tuần 8-10)
7. **Tách `ProbabilityEngine.mqh`** thành sub-modules
8. **EA Template** nhận tín hiệu từ indicator
9. **Unit tests** cho core functions
