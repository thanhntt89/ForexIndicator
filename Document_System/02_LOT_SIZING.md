# QuantEdge — Position Sizing Engine (Lot Calculator)

## 1. Mục Tiêu

Tính **lot size tối ưu** cho mỗi entry zone, dựa trên:
- Xác suất TP/SL (từ ProbabilityEngine)
- Kelly Fraction (từ WalkForward)
- Volatility Regime (từ MarketRegime)
- Account balance + risk budget

## 2. Hiện Trạng

### ✅ Đã có trong code (SLTP.mqh, dòng 1039+)

```
Zone 1 (Market):  lotSize = riskShare × totalRisk / slDistance
Zone 2 (PB-Z2):   lotSize = riskShare × totalRisk / slDistance (wider SL)
Zone 3 (PB-Z3):   lotSize = riskShare × totalRisk / slDistance (widest SL)
```

- `riskShare` phân bổ cố định: Zone1=50%, Zone2=30%, Zone3=20%
- `totalRisk` = `InpTotalRiskPercent` × AccountBalance (mặc định 1%)

### ⚠️ Thiếu sót quan trọng

| Thiếu | Vì sao quan trọng |
|-------|-------------------|
| Kelly Fraction không ảnh hưởng lot | Kelly đã tính trong WalkForward nhưng chỉ hiển thị, chưa dùng |
| Risk share cố định | Nên phân bổ theo EV: zone có EV cao nhất nhận nhiều risk nhất |
| Không scale theo Vol Regime | EVENT regime nên giảm lot, QUIET regime cho phép tăng |
| Không cap theo Brier quality | Khi Brier Score > 0.20 (dự báo kém) → giảm lot |

## 3. Thiết Kế Mới: Adaptive Position Sizing

### 3.1 Công Thức Lot Size

```
lotSize = BaseLot × KellyScale × VolScale × BrierScale × RiskShareByEV
```

### 3.2 Từng Thành Phần

#### BaseLot (Fixed Fractional)
```
BaseLot = (AccountBalance × MaxRiskPct) / (SL_distance × TickValue)
```
Đây là lot cơ bản — risk X% tài khoản nếu chạm SL.

#### KellyScale (0.0 – 1.0)
```
HalfKelly = g_walkForward.kellyFraction    // Đã tính trong WalkForward.mqh
KellyScale = clamp(HalfKelly / 0.25, 0.0, 1.0)
```
- HalfKelly = 0.25 (25%) → KellyScale = 1.0 (full size)
- HalfKelly = 0.10 (10%) → KellyScale = 0.4 (giảm 60%)
- HalfKelly ≤ 0 → KellyScale = 0.0 → **KHÔNG VÀO LỆNH**

#### VolScale (Volatility Adjustment)
```
VOL_QUIET    → 1.2  (ATR thấp → spread impact nhỏ → size lớn hơn)
VOL_NORMAL   → 1.0  (mặc định)
VOL_TRENDING → 0.8  (directional → giữ bình thường nhưng cẩn trọng)
VOL_EVENT    → 0.3  (spike/news → giảm mạnh)
```

#### BrierScale (Calibration Quality)
```
if(BrierScore < 0.15)  BrierScale = 1.0    // Calibration tốt
if(BrierScore < 0.20)  BrierScale = 0.8    // Trung bình
if(BrierScore < 0.25)  BrierScale = 0.5    // Yếu
if(BrierScore >= 0.25) BrierScale = 0.2    // Rất yếu (gần coin flip)
```

#### RiskShareByEV (Phân Bổ Theo Expected Value)
Thay thế phân bổ cố định 50/30/20:
```
Nếu Zone2.EV > Zone1.EV:
  Zone2 nhận 50%, Zone1 nhận 30%
  
Tổng: sum(riskShare) = 1.0 luôn
```

### 3.3 Giới Hạn An Toàn

| Constraint | Giá trị |
|-----------|---------|
| Min lot | MarketInfo(MODE_MINLOT) |
| Max lot | MarketInfo(MODE_MAXLOT) |
| Max risk per trade | 3% (hard cap, bất kể Kelly nói gì) |
| Max daily exposure | `InpMaxDailyRiskPct` (circuit breaker) |
| Min probability để vào | probTP1 > 52% (phải có edge) |

## 4. File Cần Tạo / Sửa

| File | Hành động |
|------|----------|
| `Include/QuantEdge/PositionSizing.mqh` | **[NEW]** Module mới |
| `Include/QuantEdge/SLTP.mqh` | Gọi PositionSizing thay vì tính lot inline |
| `Include/QuantEdge/Structs.mqh` | Thêm `PositionSizeResult` struct |
| `Include/QuantEdge/Config.mqh` | Thêm inputs: MaxRiskCap, MinEdgeToTrade |

## 5. API Interface

```mql4
struct PositionSizeResult
{
   double lotSize;          // Final calculated lot
   double riskPercent;      // Actual risk % of account
   double kellyFraction;    // Kelly value used
   double volScale;         // Vol regime multiplier
   double brierScale;       // Calibration quality multiplier
   string reason;           // "OK" or rejection reason
   bool   approved;         // true = safe to trade
};

PositionSizeResult CalculateOptimalLot(
   int zoneIndex,           // Which entry zone
   double slDistance,        // SL distance in price
   double probTP1,           // Probability from engine
   double accountBalance    // Current balance
);
```
