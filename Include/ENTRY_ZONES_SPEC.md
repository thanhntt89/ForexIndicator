# RSI Advanced - Multi-Entry Zone System
## Specification Document v1.0

---

## 1. OVERVIEW

### Mục đích
Thay vì 1 điểm entry duy nhất (market entry), hệ thống tạo ra
2-5 vùng giá entry với xác suất khác nhau. Mỗi vùng có lot size
riêng sao cho tổng rủi ro khi ALL zones bị SL = InpTotalRiskPercent.

### Nguyên tắc core
- SL CHUNG cho tất cả zones (structure-based)
- TP CHUNG cho tất cả zones (close ALL khi hit TP)
- Lot size KHÁC NHAU per zone (risk-weighted)
- Số zones TỰ ĐỘNG đề xuất dựa trên market condition
- Minimum 2 zones, Maximum = InpEntryZoneCount (default 3)

---

## 2. LÝ THUYẾT

### 2.1 Price Distribution Analysis (Dalton 1993)
- Scan price history trong vùng Entry → SL
- Chia thành micro-zones
- Đếm số bars active trong mỗi micro-zone
- Vùng LOW activity = liquidity void
- Giá tendency sweep qua liquidity void rồi reverse
- Entry tại liquidity void = entry sau liquidity sweep

### 2.2 Fibonacci Retracement Fallback (Gaucan 2011)
- Khi không đủ data cho price distribution → dùng Fibonacci
- 0.382 retracement = Zone 2 default
- 0.618 retracement = Zone 3 default
- 0.786 retracement = Zone 4 default
- 0.886 retracement = Zone 5 default

### 2.3 Risk Distribution (Van Tharp 1998)
- Total risk = InpTotalRiskPercent% of account
- Chia theo zone: zone gần entry nhất = lot lớn nhất
- Lý do: zone gần entry có P(reach) cao nhất
- Zone xa có P(reach) thấp hơn nhưng R:R tốt hơn

### 2.4 Expected Value per Zone (Kelly 1956)
- EV(Zone) = P(reach) × [P(TP1|zone) × R:R - P(SL|zone) × 1.0]
- Zone có EV positive = RECOMMEND
- Zone có EV negative = SKIP (không vào)
- Số zones thực tế = số zones có EV positive (min 2)

---

## 3. ZONE CALCULATION

### 3.1 Zone Entry Prices
Input: entryPrice (market), slPrice, atr
moveHeight = |entryPrice - slPrice|

Zone 1: Market entry = entryPrice (luôn có)

Zone 2-5: Tìm từ Price Distribution Analysis
Scan range: entryPrice → slPrice
Chia thành 20 micro-zones
Đếm bar activity per micro-zone
Tìm lowest activity zones trong search ranges:
Zone 2 search: 15-35% retracement
Zone 3 search: 35-55% retracement
Zone 4 search: 55-75% retracement
Zone 5 search: 75-90% retracement

Fallback (insufficient data):
Zone 2 = entryPrice - moveHeight × 0.382
Zone 3 = entryPrice - moveHeight × 0.618
Zone 4 = entryPrice - moveHeight × 0.786
Zone 5 = entryPrice - moveHeight × 0.886

### 3.2 Zone Validation
Zone INVALID nếu:

SL distance < ATR × 0.3 (quá gần SL)
Zone price ngoài range [SL, Entry]
EV negative VÀ không phải Zone 1
Zone 1 (Market) luôn VALID (baseline)

### 3.3 Zone Reach Probability
P(reach Zone N) = measured từ historical data

Scan past signals:
Cho mỗi signal cùng direction:
Track min price (BUY) hoặc max price (SELL)
trong maxForward bars sau signal

pullbackDepth = |entry - extremePrice| / moveHeight

Nếu pullbackDepth >= zone_retracement_level → zone reached
P(Zone 1) ≈ 95% (market entry, gần như chắc chắn)
P(Zone 2) = count(reached) / total_signals
P(Zone 3) = count(reached) / total_signals

### 3.4 Zone TP Probability
P(TP1 from Zone N) = CalculateRealMarketProbTP(
measuredEdge,
slDistance_from_zoneN,
tp1Distance_from_zoneN,
atr
)

Zone N gần SL hơn → slDistance nhỏ hơn → R:R lớn hơn
→ P(TP1) có thể cao hơn hoặc thấp hơn tùy edge

### 3.5 Zone Expected Value
EV(Zone N) = P(reach_N) × [P(TP1|N) × R:R(N) - P(SL|N) × 1.0]

Nếu EV > 0: Zone RECOMMENDED
Nếu EV <= 0: Zone SKIPPED (trừ Zone 1)

---

## 4. ADAPTIVE ZONE COUNT

### 4.1 Logic tự động đề xuất số zones

maxZones = InpEntryZoneCount (user config, default 3)
minZones = 2 (luôn có ít nhất 2 zones)

Bước 1: Tính tất cả maxZones zones
Bước 2: Check validity + EV per zone
Bước 3: Đếm zones có EV positive = validCount

recommendedZones = MAX(minZones, validCount)
recommendedZones = MIN(recommendedZones, maxZones)

Nếu validCount < 2:
→ Giữ Zone 1 (market) + Zone 2 (nearest valid)
→ Warn: "Limited zones - low pullback probability"


### 4.2 Market condition factors

ATR spike (curATR > avgATR × 1.5):
→ Pullback MORE likely (after spike, mean reversion)
→ INCREASE recommended zones

ATR low (curATR < avgATR × 0.5):
→ Pullback LESS likely (low volatility, drifting)
→ DECREASE recommended zones

RSI extreme (< 25 hoặc > 75):
→ Strong momentum, pullback LESS likely
→ DECREASE recommended zones

RSI near 50:
→ Indecisive, pullback MORE likely
→ INCREASE recommended zones


## 5. LOT SIZE CALCULATION

### 5.1 Risk Distribution

Total risk = AccountBalance() × InpTotalRiskPercent / 100

Base distribution (3 zones):
Zone 1: 50% of risk
Zone 2: 30% of risk
Zone 3: 20% of risk

Auto-adjust for N zones:
Zone 1 always gets largest share
Remaining zones split proportionally

Formula:
Zone 1 share = 40% + 10% / N
Zone K share = (100% - Zone1_share) / (N-1) × weight(K)
weight(K) = (N - K) / sum(1..N-1)

Ví dụ 5 zones:
Zone 1: 42%, Zone 2: 20%, Zone 3: 16%,
Zone 4: 12%, Zone 5: 10%
Total: 100%

### 5.2 Lot Size Formula

For each zone:
riskAmount = totalRisk × zoneRiskShare
slDistance = |zonePrice - slPrice|
pipValue = MarketInfo(MODE_TICKVALUE) × (slDistance / MODE_TICKSIZE)
lotSize = riskAmount / pipValue
lotSize = MAX(lotSize, MODE_MINLOT)
lotSize = NormalizeDouble(lotSize, lotDigits)

Verify:
totalLots = sum(all zone lots)
maxLoss = sum(zoneN_lot × zoneN_SL_distance × pipValue)
maxLoss MUST <= totalRisk
If maxLoss > totalRisk: scale down all lots proportionally

## 6. DISPLAY

### 6.1 Panel Section

Entry Zones (SL: 4488.234):
Z1 Market : 4506.06 0.03lot R:R1:2.6 P:95%→25% EV:-0.10R
Z2 LiqVoid: 4499.10 0.02lot R:R1:4.9 P:60%→30% EV:+0.46R ★
Z3 LiqVoid: 4494.90 0.01lot R:R1:8.4 P:35%→35% EV:+0.80R ★★
Recommended: 3 zones | Total risk: 1.0% ($10)
Best zone: Z3 (EV +0.80R)

★ = EV positive
★★ = highest EV
Zones without ★ = EV negative (market entry baseline)

### 6.2 Chart Lines

Valid zones: solid line + price tag + "ZN R:R P:XX%"
Invalid zones: NOT shown
EV negative zones: dashed line (lighter color)

Line type: OBJ_HLINE (consistent with SL/TP)
Labels: same pixel-fixed system as existing price tags

### 6.3 Height Calculation

Panel height for zones section:
Title line: 1 × lh
Per zone: 1 × lh (only valid zones)
Summary: 1 × lh
Total: (2 + validZoneCount) × lh


## 7. CONFIG INPUTS

```mql4
input string inp_grp_zones       = "========== Entry Zones ==========";
input int    InpEntryZoneCount   = 3;              // Max entry zones (2-5)
input double InpTotalRiskPercent = 1.0;            // Total risk % of account
input int    InpPriceDistLookback= 50;             // Price distribution lookback bars
input color  InpZone1Color       = clrWhite;       // Zone 1 (Market) color
input color  InpZone2Color       = clrDodgerBlue;  // Zone 2 color
input color  InpZone3Color       = clrRoyalBlue;   // Zone 3 color
input color  InpZone4Color       = clrSlateBlue;   // Zone 4 color
input color  InpZone5Color       = clrDarkSlateBlue; // Zone 5 color
8. DATA STRUCTURES
mql4

struct EntryZone
{
   double price;           // Entry price for this zone
   double slDistance;       // Distance from zone price to SL
   double tp1Distance;     // Distance from zone price to TP1
   double riskShare;       // Fraction of total risk (0-1)
   double lotSize;         // Calculated lot size
   double rrRatio;         // R:R ratio from this zone
   double probReach;       // P(price reaches this zone)
   double probTP1;         // P(TP1 hit | entered at this zone)
   double expectedValue;   // EV per trade from this zone
   bool   isValid;         // Zone is valid (SL distance OK)
   bool   isRecommended;   // Zone has positive EV
   string zoneName;        // "Market", "LiqVoid", etc
};
9. FILES AFFECTED

Config.mqh         → Add zone inputs
SLTP.mqh           → Add zone calculation functions
PanelDrawing.mqh   → Add zone display section
LineDrawing.mqh    → Add zone lines on chart
RSI_AdvancedSignal.mq4 → Call zone calculation, pass to display
Globals.mqh        → Add zone data array
Structs.mqh        → Add EntryZone struct
10. EXAMPLES
Example 1: Strong trend, M5 Gold

Signal: BUY Case 4
Entry: 4506, SL: 4488, TP1: 4553
moveHeight: 18, ATR: 7.13

Price Distribution finds:
  Zone 2: 4500.5 (liquidity void at 31% retracement)
  Zone 3: 4495.2 (liquidity void at 60% retracement)

Market condition:
  ATR normal, RSI 62 → recommend 3 zones

Zones:
  Z1: 4506.0, SL_dist=18.0, TP1_dist=47.0, R:R=2.6, P=95%→25%, EV=-0.10
  Z2: 4500.5, SL_dist=12.5, TP1_dist=52.5, R:R=4.2, P=58%→32%, EV=+0.52 ★
  Z3: 4495.2, SL_dist=7.2,  TP1_dist=57.8, R:R=8.0, P=33%→38%, EV=+0.76 ★★

Lot sizes (account $1000, risk 1% = $10):
  Z1: $5.0 risk / (18.0 × $0.10) = 0.028 → 0.03 lot
  Z2: $3.0 risk / (12.5 × $0.10) = 0.024 → 0.02 lot
  Z3: $2.0 risk / (7.2 × $0.10) = 0.028 → 0.03 lot
  Total max loss if ALL SL: $5 + $3 + $2 = $10 = 1.0% ✅
Example 2: Low volatility, M15 Gold

Signal: SELL Case 6
ATR low (< 50% average) → recommend 2 zones only

Zones:
  Z1: Market entry (valid)
  Z2: Shallow pullback (valid, EV+)
  Z3: Deep pullback (INVALID - SL distance < ATR×0.3)

Recommended: 2 zones
Risk redistribution: Z1=60%, Z2=40%
Example 3: ATR spike, H1 Gold

Signal: BUY Case 1
ATR spike (> 150% average) → pullback likely → recommend 4 zones

Zones:
  Z1: Market (valid)
  Z2: 25% retracement (valid, EV+)
  Z3: 45% retracement (valid, EV+)
  Z4: 65% retracement (valid, EV+)

Recommended: 4 zones (max allowed by InpEntryZoneCount)
11. ANTI-OVERFITTING MEASURES

1. Price distribution uses RAW bar counts (no smoothing)
2. Zone prices from LIQUIDITY VOIDS (data-driven, not Fibonacci)
3. Fibonacci only as FALLBACK when insufficient data
4. Reach probability MEASURED from historical signals
5. EV calculation uses MEASURED edge (not guessed)
6. Lot sizes from MATH formula (Kelly/Van Tharp)
7. Zone count ADAPTIVE to market condition (not fixed)
8. Risk shares AUTO-CALCULATED (not optimized on data)
12. LIMITATIONS

1. AccountBalance() in indicator may not update realtime
   → Lot sizes approximate, trader should verify
   
2. Price distribution based on VISIBLE bars only
   → Limited by InpPriceDistLookback
   
3. Liquidity void ≠ guaranteed reversal zone
   → Price CAN sweep through without reversing
   
4. Zone reach probability based on PAST signals
   → Future may differ (non-stationary market)
   
5. Lot calculation assumes SINGLE instrument
   → If trading multiple pairs, total risk > 1% per pair

Collapse
Save
Copy
1
2

Đây là spec document. Confirm thiết kế OK rồi tôi implement 7 files.
