# AngleStrength — Tích Hợp Góc Cắt Vào Pipeline Xác Suất
**Version:** Spec v1.0 | **Target:** RSI Advanced V10.20 → V10.21
**Date:** 2026-06-06

---

## I. Bối Cảnh & Vấn Đề

### Lý thuyết Mastering RSI yêu cầu phân biệt góc cắt:
- **12h–2h (mạnh):** Đường Green cắt lên Red với góc dốc, momentum cao → xác suất thắng cao
- **2h–4h (yếu):** Green cắt với góc ngang → xác suất thấp, nên bỏ qua
- **4h–6h (mạnh xuống):** Tương tự nhưng chiều giảm

### Vấn đề hiện tại trong code:
`ScanHistoricalATRBased()` trong `ProbabilityEngine.mqh` gộp tất cả tín hiệu
(góc mạnh + góc yếu) vào cùng 1 pool thống kê → **probTP1 bị averaged down**

**Ví dụ cụ thể:**
```
Nếu: Góc mạnh (Z > 1.5): win rate thực = 55%
     Góc yếu  (Z < 0.8): win rate thực = 40%
     Tỉ lệ xuất hiện:     50% mỗi loại
→ probTP1 hiển thị = 47.5% (không đúng cho cả hai trường hợp)
→ Khi góc mạnh: underestimate 7.5%, khi góc yếu: overestimate 7.5%
```

---

## II. Định Nghĩa Góc Chính Xác (Toán Học)

### AngleStrength = Z-score của momentum Green

```
Tại bar i (sau crossover):
  greenDelta2 = Green[i] - Green[i-2]        // Thay đổi qua 2 nến
  adaptiveThresh = stddev(ΔGreen, 20 bars) × 1.5  // Ngưỡng động

  AngleStrength (Z-score) = greenDelta2 / adaptiveThresh
```

### Tại sao KHÔNG dùng arctan (góc độ thực)?

**Vấn đề của arctan:**
```
angle = arctan(ΔGreen / N_bars)
```
- Phụ thuộc vào scale trục Y của chart (pixel) — biến đổi theo zoom
- Không so sánh được giữa các thời điểm có volatility khác nhau
- Không có đơn vị chuẩn hóa

**Z-score tốt hơn vì:**
- Tự normalize theo volatility hiện tại của Green
- Z > 1.5 luôn có nghĩa "mạnh hơn 80% các crossover gần đây"
- Không phụ thuộc scale màn hình
- Đã có hạ tầng tính trong `GetAdaptiveAngleThreshold()` — chỉ cần tách return value

### Bảng ánh xạ Z-score → "Giờ đồng hồ":

| Z-score AngleStrength | Ý nghĩa lý thuyết | Tier |
|-----------------------|-------------------|------|
| ≥ 2.0                 | 12h–1h (cực mạnh) | STRONG |
| 1.0 – 2.0             | 1h–3h (mạnh)      | NORMAL |
| 0.5 – 1.0             | 3h–4h (yếu)       | WEAK |
| < 0.5                 | 4h–6h (sideway)   | REJECT |

---

## III. Thiết Kế Thay Đổi (4 File)

### File 1: `Structs.mqh` — Thêm field vào SignalData

```mql4
struct SignalData
{
   datetime signalTime;
   int      barIndex;
   int      caseNumber;
   bool     isBuySignal;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   double   takeProfit2;
   double   takeProfit3;
   double   atrValue;
   // [THÊM MỚI]
   double   angleStrength;  // Z-score của momentum Green tại bar tín hiệu
                            // 0.0 = không tính được, > 0 = có giá trị
};
```

**Breaking change:** Không phá vỡ backward compatibility — `angleStrength = 0.0` mặc định = "chưa tính"

---

### File 2: `MarketRegime.mqh` — Tách hàm tính Z-score

**Hàm mới** (tách từ `GetAdaptiveAngleThreshold`):

```mql4
//+------------------------------------------------------------------+
//| Calculate angle Z-score of Green line at crossover bar            |
//| Returns: Z-score (0.0 if insufficient data)                       |
//| > 1.5 = strong angle (12h-2h clock), < 0.5 = weak (sideway)      |
//+------------------------------------------------------------------+
double CalculateAngleStrength(int barIndex)
{
   if(barIndex < 3 || BufferGreen[barIndex] == EMPTY_VALUE) return(0.0);
   if(BufferGreen[barIndex-2] == EMPTY_VALUE) return(0.0);

   // Momentum qua 2 nến (ổn định hơn 1 nến, ít noise hơn 3 nến)
   double greenDelta2 = MathAbs(BufferGreen[barIndex] - BufferGreen[barIndex-2]);

   // Adaptive threshold = stddev × 1.5 (từ GetAdaptiveAngleThreshold)
   double adaptiveThresh = GetAdaptiveAngleThreshold(barIndex);
   if(adaptiveThresh <= 0.0) return(0.0);

   // Z-score: bao nhiêu "độ lệch chuẩn" so với crossover trung bình
   double zScore = greenDelta2 / adaptiveThresh;
   return(MathMin(zScore, 5.0)); // Cap tại 5.0 để tránh outlier
}
```

---

### File 3: `Globals.mqh` — Cập nhật StoreSignal

```mql4
void StoreSignal(datetime t, int barIdx, int caseNum, bool isBuy,
                 double entry, double sl, double tp1, double tp2, double tp3,
                 double atr, double angleZ = 0.0)   // [THÊM tham số]
{
   g_signalCount++;
   ArrayResize(g_signals, g_signalCount);
   int idx = g_signalCount - 1;
   g_signals[idx].signalTime   = t;
   g_signals[idx].barIndex     = barIdx;
   g_signals[idx].caseNumber   = caseNum;
   g_signals[idx].isBuySignal  = isBuy;
   g_signals[idx].entryPrice   = entry;
   g_signals[idx].stopLoss     = sl;
   g_signals[idx].takeProfit1  = tp1;
   g_signals[idx].takeProfit2  = tp2;
   g_signals[idx].takeProfit3  = tp3;
   g_signals[idx].atrValue     = atr;
   g_signals[idx].angleStrength = angleZ;  // [THÊM MỚI]
}
```

**Backward compatible:** `angleZ = 0.0` là default → các call cũ không cần sửa.

---

### File 4: `ProbabilityEngine.mqh` — 2 điểm tích hợp

#### Điểm A: `ScanHistoricalATRBased()` — Stratify theo angle tier

```mql4
// THÊM VÀO: Sau khi xác định `similar = true`, lọc thêm angle tier
if(similar)
{
   // Tính angleStrength của bar lịch sử
   double histAngle = 0.0;
   if(bs >= 3 && bs < Bars - 1)
   {
      double d2 = iMA(NULL,0,2,0,MODE_SMA,InpPrice,bs)
                - iMA(NULL,0,2,0,MODE_SMA,InpPrice,bs+2);
      // Dùng ATR làm proxy cho adaptiveThresh (approx)
      histAngle = (atr > 0) ? MathAbs(d2) / (atr * 0.5) : 0.0;
   }

   // So sánh tier của tín hiệu hiện tại vs lịch sử
   // curSig.angleStrength > 0 mới filter (= 0 nghĩa là không có dữ liệu)
   if(curSig.angleStrength > 0.5 && histAngle > 0)
   {
      bool curStrong  = (curSig.angleStrength >= 1.0);
      bool histStrong = (histAngle >= 1.0);
      // Chỉ include nếu cùng tier (cả hai mạnh, hoặc cả hai yếu)
      if(curStrong != histStrong) { similar = false; }
   }
}
```

#### Điểm B: `CalculateProbability()` — Điều chỉnh edgeAdjustment tại Step 3

```mql4
// THÊM VÀO: Cuối STEP 3, sau MTF và Intermarket
// Angle strength adjustment (direct from signal's crossover quality)
double angleZ = curSig.angleStrength;
if(angleZ > 0.1)
{
   // Z > 2.0: +3% edge (tín hiệu góc rất mạnh)
   // Z = 1.0: ±0% (neutral)
   // Z < 0.5: -3% edge (tín hiệu góc yếu)
   // Công thức linear: adj = (Z - 1.0) × 0.03, clamp [-0.03, +0.04]
   double angleAdj = MathMax(-0.03, MathMin(0.04, (angleZ - 1.0) * 0.03));
   edgeAdjustment += angleAdj;
}
```

---

## IV. Nơi Tính AngleStrength trong Main Indicator

Trong `RSI_Advanced.mq4` và `RSI_Advanced.mq5`, tại block detect signal:

```mql4
// Trước StoreSignal, tính angle:
double angleZ = CalculateAngleStrength(i);

// BUY signal:
StoreSignal(time[i], i, buySignal, true, entryPrice, sl, tp1, tp2, tp3, atrVal, angleZ);

// SELL signal:
StoreSignal(time[i], i, sellSignal, false, entryPrice, sl, tp1, tp2, tp3, atrVal, angleZ);
```

---

## V. Dự Kiến Tác Động Lên probTP1

### Scenario mô phỏng (XAUUSD M1, 500 tín hiệu):

| Angle tier | N tín hiệu (est.) | probTP1 trước | probTP1 sau | Thay đổi |
|-----------|------------------|--------------|-------------|---------|
| STRONG (Z ≥ 1.5) | ~180 (36%) | 35% | 42–48% | +7–13% |
| NORMAL (Z 1.0–1.5) | ~200 (40%) | 35% | 33–37% | ±2% |
| WEAK (Z < 1.0) | ~120 (24%) | 35% | 28–33% | -2–7% |

> **Kết quả quan trọng nhất:** Trader thấy probTP1=42% thay vì 35% khi góc thực sự mạnh
> → Quyết định vào lệnh tốt hơn, cỡ lot hợp lý hơn theo Kelly criterion

### Tác động lên Recommendation Engine:

```
STRONG angle + probTP1 tăng → EV score cao hơn → ENTRY hoặc STRONG ENTRY
WEAK angle + probTP1 giảm  → EV score thấp   → WAIT hoặc CAUTION
```

---

## VI. Rủi Ro & Giới Hạn

### ⚠️ Rủi ro 1: Stratification làm giảm sample size
Khi chia pool thống kê theo tier, mỗi tier có ít mẫu hơn → confidence interval rộng hơn.

**Mitigation:** Chỉ apply stratification khi `curSig.angleStrength > 0.5` (có dữ liệu đáng tin) VÀ khi tổng samples vẫn ≥ minSamples/2. Nếu samples quá ít, fallback về pool không stratified.

### ⚠️ Rủi ro 2: Proxy angle trong ScanHistoricalATRBased không chính xác
`histAngle` dùng iMA/ATR làm proxy (không phải buffers thực) → có thể sai lệch.

**Mitigation:** Tier comparison dùng ngưỡng 1.0 (rộng) thay vì Z-score liên tục → ít nhạy cảm với sai số.

### ⚠️ Rủi ro 3: Case 2, 3 (Divergence) — góc không đại diện cho sức mạnh tín hiệu
Divergence signals thường có góc crossover vừa phải nhưng win rate cao.

**Mitigation:** Trong điểm B (edgeAdjustment), giảm ảnh hưởng angle cho Case 2/3:
```mql4
double caseMult = (caseNum == 2 || caseNum == 3) ? 0.4 : 1.0;
double angleAdj = ... * caseMult;
```

---

## VII. Files Cần Sửa & Thứ Tự Triển Khai

```
Thứ tự (phải đúng thứ tự vì dependency):
  1. Structs.mqh       → Thêm angleStrength field
  2. MarketRegime.mqh  → Thêm CalculateAngleStrength()
  3. Globals.mqh       → Update StoreSignal signature (optional param)
  4. ProbabilityEngine.mqh → 2 điểm tích hợp (Scan + edgeAdj)
  5. RSI_Advanced.mq4  → Tính và pass angleZ vào StoreSignal
  6. RSI_Advanced.mq5  → Tương tự mq4
  7. Compile + verify 0 errors
```

---

## VIII. Verification Plan

### Automated:
- Compile: 0 errors, 0 warnings
- `angleStrength > 0` cho tất cả tín hiệu sau bar 20

### Manual:
1. Chạy chỉ báo trên XAUUSD M1, quan sát panel
2. Tìm 2 tín hiệu cùng Case gần nhau: 1 góc dốc, 1 góc ngang
3. Xác nhận: tín hiệu góc dốc có probTP1 cao hơn (expected: +5–10%)
4. Xác nhận: Recommendation của góc dốc ≥ Recommendation của góc ngang

---

*Spec này được lưu vào Documents/ và Projects để AI lần sau đọc trước khi implement.*
