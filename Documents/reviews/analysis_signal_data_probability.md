# Phân tích: Dữ liệu tín hiệu lịch sử trong pipeline xác suất

**Ngày**: 2026-06-09  
**Mục đích**: Hiểu rõ hệ thống đang dùng dữ liệu gì, đặc điểm ra sao, và thiếu gì để cải thiện về sau.

---

## 1. Cấu trúc tín hiệu lưu trữ (`SignalData` trong `g_signals[]`)

```mql4
struct SignalData {
   datetime signalTime      // thời điểm bar đóng
   int      barIndex        // vị trí trong indicator buffer
   int      caseNumber      // 1–8 (loại pattern RSI)
   bool     isBuySignal     // hướng giao dịch
   double   entryPrice      // open[i+1] ± slippage (±0.15–0.3 ATR)
   double   stopLoss        // ATR / Fibonacci / Hybrid
   double   takeProfit1/2/3 // TP levels
   double   atrValue        // ATR tại bar tín hiệu
   double   angleStrength   // Z-score của Green RSI momentum (2-bar delta / adaptive threshold)
   int      rsiPeriod       // snapshot InpRSIPeriod (guard Tier 3 contamination)
   int      simCachedTP     // kết quả simulation đã cache (99 = chưa tính)
   int      simCachedBTR    // số bars đến kết quả (cached)
   int      edgeCachedOutcome // kết quả edge binary (99 = chưa tính)
}
```

**Giới hạn lưu trữ**: `g_signals[]` chứa tối đa `InpMaxBars = 500` tín hiệu gần nhất.  
**Không persist qua session**: khi indicator restart, toàn bộ rebuild từ đầu.

---

## 2. Điều kiện sinh tín hiệu

Tất cả tín hiệu đều yêu cầu **đồng thời**:

1. **Green/Red crossover** xảy ra trên closed bar (không phải forming bar)
2. **Strong angle**: `greenDelta > InpAngleThreshold` (hoặc `*0.5` cho Case 2/3)
3. **Case-specific condition** (xem bảng)
4. **Cooldown**: cách tín hiệu cùng hướng trước ≥ `InpCooldownBars`
5. **Signal score** ≥ `InpMinSignalScore`

| Case | Tên | Điều kiện cốt lõi | Đặc điểm |
|---|---|---|---|
| 1 | OB/OS Bounce | Green vượt qua 32/68 **và** nằm ngoài BB band | Reversal từ extreme |
| 2 | Regular Divergence | Price lower-low + RSI higher-low | Giảm momentum |
| 3 | Hidden Divergence | Price higher-low + RSI lower-low | Trend continuation |
| 4 | Strong Trend | Green cross qua 50 **và** breakout khỏi BB | Breakout entry |
| 5 | Orange Level | Orange RSI gần 32/68 (±InpOrangeTolerance=5) | Baseline support/resist |
| 6 | Trend Continuation | Green/Red cùng phía Orange, pullback hợp lệ | Pullback reentry |
| 7 | Sideway Breakout | ≥N crossovers bên trong BB → phá vỡ | Post-consolidation |
| 8 | Basic Crossover | Cross với strong angle — điều kiện tối thiểu | |

**Thứ tự ưu tiên** khi detect (mã hóa cứng, case sau chỉ check khi case trước = 0):
```
Priority: 6 → 2 → 4 → 3 → 1 → 5 → 7
```
Một bar chỉ có tối đa 1 BUY signal và 1 SELL signal.

---

## 3. Luồng dữ liệu vào pipeline xác suất

```
g_signals[] (≤500 tín hiệu gần nhất)
  ├─ Tier 1 [w = n^0.75 × 1.0]: cùng direction + cùng caseNumber
  └─ Tier 2 [w = sqrt(n) × 0.5]: cùng direction + bất kỳ case (trừ Tier1)

Raw price history (toàn bộ lịch sử ngoài InpMaxBars)
  └─ Tier 3 [w = sqrt(n) × 0.15]: ScanHistoricalATRBased
     - Filter: RSI level range theo case (21–35 điểm RSI — rất rộng)
     - Filter phụ: angle tier (binary: Z≥1.0 hay không)
     - Simulation: entry+ATR hoặc SL trong maxFwd bars

MeasureEdgeFromHistory (đo "edge" — P(price đi đúng hướng 1 ATR))
  ├─ Phase 1: từ g_signals[] (fast, edgeCachedOutcome)
  └─ Phase 2: scan toàn bộ lịch sử ngoài InpMaxBars (RSI momentum filter)
```

**Simulation logic cho Tier 1/2** (`SimulateSignalOutcome`):
```
Scan từ barIndex+1 đến barIndex+maxFwd:
  if barLow  <= stopLoss   → outcome = -1 (SL hit)
  if barHigh >= takeProfit1 → outcome = +1 (TP1 hit)
  Kết thúc maxFwd          → outcome = 0  (timeout, bỏ qua)
Spread: dùng MarketInfo(Symbol(), MODE_SPREAD) hiện tại [⚠ không phải spread lịch sử]
```

---

## 4. Feature matrix: có lưu và có dùng không

| Feature | Lưu trong SignalData? | Dùng Tier 1/2? | Dùng Tier 3? | Ghi chú |
|---|---|---|---|---|
| Direction (BUY/SELL) | ✅ | ✅ | ✅ | |
| Case number | ✅ | ✅ exact match | 🟡 loose filter | |
| Entry price | ✅ | ✅ simulation | ✅ ATR proxy | |
| SL / TP levels | ✅ | ✅ simulation | ✅ ATR proxy | |
| ATR tại signal | ✅ | ✅ timeout scale | ✅ | |
| Angle Z-score | ✅ | ❌ không weight | 🟡 binary only | Z≥1.0 là strong |
| RSI value tại bar | ❌ | ❌ | 🟡 range 21–35pt | Không lưu exact |
| Session block | ❌ | ❌ | ❌ | Chỉ trong g_outcomes |
| Market regime | ❌ | ❌ | ❌ | Trending/Ranging/Event |
| MTF alignment | ❌ | ❌ | ❌ | Chỉ dùng MTF hiện tại |
| BB width | ❌ | ❌ | ❌ | Vol context không capture |
| Orange value | ❌ | ❌ | ❌ | RSI baseline bị bỏ qua |
| Volume | ❌ | ❌ | ❌ | |
| Spread thực tế | ❌ | ❌ (dùng spread LIVE ⚠) | ❌ | Systematic bias |
| Green/Red values | ❌ | ❌ | ❌ | RSI exact không lưu |

---

## 5. Vấn đề cốt lõi

### V1 — Sample size quá nhỏ ở lower timeframes

`g_signals[]` capped tại 500. Số mẫu Tier 1 thực tế:

| TF | Tín hiệu/ngày | 500 = | Tier 1 BUY Case2 (ước tính) | Độ tin cậy |
|---|---|---|---|---|
| M1 | ~50 | ~10 ngày | 5–10 mẫu | Gần như vô nghĩa |
| M5 | ~15 | ~5 tuần | 10–20 mẫu | Rất yếu |
| M15 | ~8 | ~2 tháng | 15–30 mẫu | Yếu |
| H1 | ~2 | ~8 tháng | 30–60 mẫu | Chấp nhận được |
| H4 | ~0.5 | ~3 năm | 80–150 mẫu | Tốt |

**Hệ quả**: Ở M1–M15, Tier 1/2 hiếm khi có đủ `minSamples` → Tier 3 dominate → probability chủ yếu là raw price scan, không phải learned từ actual signals.

### V2 — Spread lịch sử sai (systematic bias)

File: [ProbabilityEngine.mqh:243](../Include/RSI_Advanced/ProbabilityEngine.mqh)

```mql4
// Bug: dùng spread HIỆN TẠI để simulate các bar trong lịch sử
double avgSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
```

XAUUSD spread varies: Asian ~$0.30, London open ~$0.50–$1.50, news spike ~$5+.  
Nếu simulate bar từ 6 tháng trước với spread hiện tại: có thể lật outcome SL/TP cho các signal có SL distance gần spread.

### V3 — Không phân tầng theo context thị trường

Tất cả signals trong Tier 1 được pool chung bất kể:
- Market regime (trending vs ranging vs event)
- Session (Asian vs London vs Overlap)
- MTF alignment (đồng thuận vs ngược chiều)
- Volatility level (quiet vs normal vs spike)

**Ví dụ vấn đề**: Case 1 BUY (OB/OS Bounce):
- Trong **ranging market**: win rate có thể 65%+ (RSI reversal mạnh)
- Trong **trending bear**: win rate có thể 30%– (bear continuation mạnh hơn)

Hệ thống trả về win rate **trung bình** của cả hai điều kiện — không phản ánh đúng signal hiện tại đang ở điều kiện nào.

### V4 — g_outcomes[] (actual tracked) không feed vào Tier 1/2

Hệ thống có **2 nguồn outcome song song** nhưng không cross-reference:

```
[SimulateSignalOutcome trên g_signals[]]  ← Tier 1/2 probability dùng
         ≠
[g_outcomes[] live tracking thực tế]      ← Chỉ dùng cho session stats (Step 5.6)
```

Nếu một signal trong g_signals[] đã được g_outcomes[] ghi nhận là SL hit thực tế, thông tin đó **không được dùng** để cải thiện Tier 1/2 probability. Tier 1/2 vẫn re-simulate từ đầu.

Trong khi đó, simulation (`SimulateSignalOutcome`) có thể disagree với actual outcome vì:
- Dùng close[bar] làm entry (không phải actual fill price)
- Dùng OHLC (không phải bid/ask tick data)
- Dùng spread sai (V2)

### V5 — AngleStrength lưu nhưng không weight trong Tier 1/2

`angleStrength` (Z-score) được lưu vào mọi signal, nhưng trong `ScanStoredSignalsBoth`:
- Signal Z=4.0 (cực mạnh) = trọng số bằng signal Z=0.5 (yếu)

Tier 3 chỉ filter binary: `Z ≥ 1.0` là "strong", dưới là "weak". Không gradient.

`angleStrength` chỉ được dùng ở:
- Step 3: linear edge adjustment `(Z-1.0) × 0.03` — ảnh hưởng nhỏ
- IC calculation: Pearson correlation check (phát hiện nếu angle không predict outcome)

### V6 — Tier 3 RSI filter quá rộng

```mql4
// BUY, case 1/5: rsi < 33 && rsi > 12  → 21 điểm RSI range
// BUY, case 2/3: rsi < 45 && rsi > 20  → 25 điểm RSI range
// BUY, other:    rsi < 50 && rsi > 15  → 35 điểm RSI range
```

Bar với RSI=22 và RSI=44 đều được tính là "similar" cho Case 2 BUY. Đây là hai trạng thái thị trường khác nhau rõ rệt.

### V7 — Case detection order cứng, không adaptive

Thứ tự priority cứng: 6→2→4→3→1→5→7. Nếu Case 6 fires thì Cases 1/2/3/4/5/7 không được check dù có thể có tín hiệu mạnh hơn.

Probability engine không biết "signal này có thể là Case 2 VÀ Case 6" — chỉ thấy Case 6.

---

## 6. Tóm tắt — Mô hình đang hỏi gì

**Câu hỏi hiện tại**:
> "Với tất cả tín hiệu cùng case+direction trong 500 bar gần nhất, bao nhiêu % đã hit TP1 trong simulation?"  
> → Kết hợp với Gambler's Ruin + MTF/angle/session adjustment

**Câu hỏi nên hỏi**:
> "Với tín hiệu loại này, trong điều kiện thị trường GIỐNG điều kiện hiện tại (regime, session, MTF alignment, vol level), bao nhiêu % hit TP1 theo actual tracked outcomes?"

**Gap cốt lõi**: Tín hiệu không lưu đủ context để so sánh "like-with-like".  
→ Đang so sánh táo với hỗn hợp táo+cam+lê trong một giỏ không phân loại.

---

## 7. Hướng cải thiện tiếp theo (gợi ý, chưa implement)

| Priority | Cải thiện | Effort | Impact |
|---|---|---|---|
| HIGH | Lưu thêm `sessionBlock` vào SignalData; filter Tier 1/2 theo session | Thấp | Cao |
| HIGH | Thêm `rsiValue` tại signal vào SignalData; Tier 3 dùng tighter band ±5pt | Thấp | Cao |
| HIGH | Dùng `g_outcomes[]` actual outcome cho Tier 1/2 thay vì re-simulate | Trung | Rất cao |
| MEDIUM | Weight Tier 1/2 bằng angleStrength (không chỉ binary) | Thấp | Trung |
| MEDIUM | Lưu `volRegime` + `marketRegime` vào SignalData; filter Tier 1/2 | Trung | Cao |
| MEDIUM | Fix spread bug: lưu spread tại signal time hoặc dùng spread=0 cho simulation | Thấp | Trung |
| LOW | Lưu MTF alignment score tại signal time | Trung | Trung |
| LOW | Tighter Tier 3 RSI band: ±5pt thay vì ±12–17pt | Thấp | Thấp |

**Priority #1 về tác động**: Dùng `g_outcomes[]` actual outcomes thay vì simulation.  
→ Loại bỏ V2 (spread sai), V3 (entry sai), cho kết quả sát thực nhất.  
→ Yêu cầu: join g_outcomes với g_signals theo signalTime, ưu tiên outcome thực nếu có.
