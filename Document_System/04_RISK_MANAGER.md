# QuantEdge — Risk Manager & Risk Budget

## 1. Hiện Trạng (RiskManager.mqh — 95 dòng)

### Đã có
| Tính năng | Trạng thái | Mô tả |
|-----------|-----------|-------|
| Circuit Breaker | ✅ | Dừng giao dịch khi DD > `InpMaxDailyDrawdown` (3%) |
| Max Open Signals | ✅ | Giới hạn `InpMaxOpenSignals` (3) |
| Max Daily Trades | ✅ | Giới hạn `InpMaxDailyTrades` (15) |
| Max Exposure % | ✅ | Giới hạn `InpMaxDailyRiskPct` (2%) |
| Daily Reset | ✅ | Reset counters mỗi ngày mới |

### Thiếu
| Tính năng | Ưu tiên | Mô tả |
|-----------|---------|-------|
| Dynamic Risk Budget | P0 | Phân bổ risk theo xác suất + EV |
| Correlation Guard | P1 | Không cho 2 lệnh cùng hướng trên cùng cặp tiền |
| Drawdown Scaling | P1 | Giảm lot tự động khi DD tăng dần |
| Weekly/Monthly Caps | P2 | Giới hạn theo tuần/tháng |

## 2. Thiết Kế: Dynamic Risk Budget

### Concept
Thay vì risk cố định 1% mỗi lệnh, phân bổ risk budget dựa trên chất lượng tín hiệu:

```
                    Daily Risk Budget: 3%
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
   Signal A: 68% TP    Signal B: 55% TP   Signal C: 52% TP
   EV: +1.8R           EV: +0.5R          EV: +0.1R
   Risk: 1.5%          Risk: 1.0%         Risk: 0.5%
```

### Risk Allocation Formula

```
signalQuality = (probTP1 / 100 - 0.5) × KellyFraction × VolScale
riskAlloc     = BasePct × (1 + signalQuality × 2)
riskAlloc     = clamp(riskAlloc, MinRiskPct, MaxRiskPct)
```

### Drawdown Scaling (Anti-Tilt)

```
recentDD = max drawdown trong 10 lệnh gần nhất
ddScale  = 1.0 - (recentDD / maxAllowedDD)
ddScale  = clamp(ddScale, 0.25, 1.0)

effectiveRisk = riskAlloc × ddScale
```

Khi thua liên tục → lot tự động giảm → bảo vệ vốn
Khi thắng trở lại → lot tự động phục hồi

## 3. Circuit Breaker Levels

| Level | Trigger | Hành động |
|-------|---------|----------|
| Yellow | DD > 1.5% | Scale lot xuống 50% |
| Orange | DD > 2.5% | Scale lot xuống 25% |
| Red | DD > 3.0% | STOP — không vào lệnh mới |
| Critical | DD > 5.0% | Alert popup + sound |

## 4. File Cần Tạo / Sửa

| File | Hành động |
|------|----------|
| `Include/QuantEdge/RiskManager.mqh` | Nâng cấp thêm Risk Budget + DD Scaling |
| `Include/QuantEdge/Config.mqh` | Thêm inputs: MinRiskPct, MaxRiskPct, DDScale levels |
| `Include/QuantEdge/PanelDrawing.mqh` | Hiển thị Risk Budget status trên panel |
