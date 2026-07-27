# QuantEdge — Multi-Entry Zone System

## 1. Tổng Quan

Entry Zone System tính **nhiều điểm vào lệnh** (pullback zones) cho mỗi signal,
mỗi zone có R:R, xác suất reach, EV riêng.
Source: `SLTP.mqh` (45KB, 1192 dòng, hàm `SL_CalculateMultiZoneEntries`)

```
Signal BUY @ 2345.00
  ├── Z1 Market:  2345.00  0.08 lot  R:R 1:2.0  Reach:95%  Win:64%  EV +0.83R *
  ├── Z2 PB-Z2:   2343.50  0.05 lot  R:R 1:2.5  Reach:72%  Win:68%  EV +0.92R *
  └── Z3 PB-Z3:   2341.00  0.03 lot  R:R 1:3.2  Reach:35%  Win:73%  EV +0.56R
```

## 2. Zone Types

| Zone | Tên | Mô tả |
|------|-----|-------|
| Z1 | Market | Entry tại giá hiện tại (probReach = 95%) |
| Z2 | PB-Z2 | Pullback zone 2 (giá thấp hơn cho BUY, cao hơn cho SELL) |
| Z3 | PB-Z3 | Pullback zone 3 (sâu hơn Z2) |
| Z4 | PB-Z4 | Optional — chỉ khi ATR spike (adaptive) |
| Z5 | PB-Z5 | Optional — maximum pullback |

### Adaptive Zone Count

```
atrRatio > 1.5 → adaptiveMax = maxZones + 1 (nhiều zone hơn khi volatile)
atrRatio < 0.5 → adaptiveMax = maxZones - 1 (ít zone hơn khi yên tĩnh)
```

## 3. Mỗi Zone Tính Gì?

### 3.1 Zone Price (Pullback Levels)

Pullback prices từ phân phối giá lịch sử (`InpPriceDistLookback = 50` bars):
- Z2: Percentile 25% retrace
- Z3: Percentile 50% retrace
- Z4: Percentile 75% retrace

### 3.2 Reach Probability (probReach)

```
rawReach = MeasureZoneReachProb(isBuy, marketEntry, zonePrice, moveHeight, maxFwd)
distDecay = exp(-distFraction × 2.0)     // Exponential decay theo khoảng cách
probReach = clamp(rawReach × distDecay, 0.05, 0.90)
```

### 3.3 R:R Ratio Per Zone

```
slDistance = |zonePrice - SL|
tp1Distance = |TP1 - zonePrice|
rrRatio = tp1Distance / slDistance
```

Zone sâu hơn → SL xa hơn → R:R tốt hơn (nhưng reach thấp hơn).

### 3.4 Win Probability Per Zone

```
probTP1 = CalculateRealMarketProbTP(edge, slDistance, tp1Distance, atr) × 100
```

Mỗi zone có xác suất riêng vì khoảng cách SL/TP khác nhau.

### 3.5 Expected Value (EV)

```
EV = probReach × (winRate × rrRatio - (1 - winRate) × 1.0)
```

**EV > 0** → Zone có lợi thế thống kê → `isRecommended = true`
**EV < 0** → Zone lỗ kỳ vọng → `isRecommended = false` (hiển thị mờ)

### 3.6 Lot Size

```
pipValue = tickValue × (slDistance / tickSize)
lotSize = (totalRisk × riskShare) / pipValue
lotSize = max(lotSize, MODE_MINLOT)
```

### 3.7 Risk Share

```
shares[] = CalculateRiskShares(adaptiveMax)
```

Hiện tại: phân bổ cố định (Z1: 50%, Z2: 30%, Z3: 20%).
**Cần cải thiện:** phân bổ theo EV (zone EV cao nhất nhận nhiều risk nhất).

## 4. Zone Validation

Zone bị reject (`isValid = false`) khi:
- `price ≤ 0` (không tìm được pullback level)
- Price nằm ngoài range [marketEntry, SL]
- `slDistance < minSLDist` (quá gần SL)

## 5. Panel & Chart Display

### Panel
```
Entry Zones (2 rec | Risk:1.0%)
Z1 Market:2345.00 0.08lot R:R1:2.0 Reach:95% Win:64% EV:0.83R *
Z2 PB-Z2:2343.50 0.05lot R:R1:2.5 Reach:72% Win:68% EV:0.92R *
Z3 PB-Z3:2341.00 0.03lot R:R1:3.2 Reach:35% Win:73% EV:0.56R
Best: Z2 EV+0.92R
```

### Chart Lines (LineDrawing.mqh)
- Horizontal dash line tại mỗi zone price
- Tag label: price + lot + R:R + Reach% + Win% + EV

## 6. Cần Cải Thiện

| Hạng mục | Mô tả |
|----------|-------|
| EV-based risk allocation | Zone EV cao → riskShare cao |
| Dynamic zone spacing | Spacing dựa trên vol regime |
| Trailing zones | Update zone prices khi thị trường di chuyển |
| Zone history | Log zone outcomes cho machine learning |
