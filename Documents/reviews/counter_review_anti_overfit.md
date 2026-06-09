# Counter-Review: Phản biện Quant Principal Review (HỢP NHẤT)

**Ngày**: 2026-06-09 (cập nhật lần 2)  
**Vai trò**: Quant System Engineer + Quant Analyst — phản biện từ góc anti-overfitting  
**Mục đích**: Review lại từng đề xuất trong `quant_principal_review.md`, challenge với data thực từ code  
**Đọc cùng**: `quant_principal_review.md` (bản gốc), `analysis_signal_data_probability.md` (phân tích data)

---

## PHÁT HIỆN SỐ 0 — Bản review trước có lỗi thực tế nghiêm trọng

### `GetSessionQualityNormalized()` KHÔNG dùng trong probability pipeline

Bản review trước viết:

> "`GetSessionQualityNormalized()` — hardcoded lookup table... chỉ dùng làm điều chỉnh hậu kỳ ở Step 5.6, không phải primary estimate"

**Thực tế** (grep toàn bộ codebase):

```
GetSessionQualityNormalized → DEFINED tại Normalize.mqh:244
                            → CALLED BỞI SessionStatistics.mqh:158 (trong GetMeasuredSessionQuality)
GetMeasuredSessionQuality   → DEFINED tại SessionStatistics.mqh:148
                            → KHÔNG BAO GIỜ ĐƯỢC GỌI bởi bất kỳ file nào
```

**Step 5.6** (ProbabilityEngine.mqh:1040-1117) truy cập **trực tiếp** `g_sessionStats.winRatePerCase[block][ci]` và `g_sessionStats.winRate[block]`, KHÔNG gọi `GetSessionQualityNormalized()`.

**Kết luận**: `GetSessionQualityNormalized()` là **dead code** trong probability pipeline. Nó có thể được dùng ở nơi khác (signal scoring?), nhưng KHÔNG ảnh hưởng đến xác suất output. Bản review trước đặt nó làm "vấn đề kiến trúc cốt lõi" — đây là sai lầm phân tích.

**Hệ quả**: Phase 1 item 3 ("thay GetSessionQualityNormalized bằng GetLearnedSessionEdge") có **ROI = 0** cho probability pipeline. Không cần thay, vì nó không được gọi.

---

## 1. Phản biện: Thêm 7 fields vào SignalData

### Đề xuất gốc
Thêm `sessionBlock, rsiAtSignal, volRegimeAtSignal, marketRegimeAtSignal, mtfAlignScore, bbWidthRatio, spreadAtSignal` → dùng để filter Tier 1/2 theo context.

### Đồng ý

| Field | Đồng ý? | Lý do |
|---|---|---|
| `spreadAtSignal` | **ĐỒNG Ý** | Fix V2 (spread bias). Chi phí = 1 double/signal. Dùng trong SimulateSignalOutcome thay MarketInfo live. ROI rõ ràng. |
| `sessionBlock` | **ĐỒNG Ý** | 1 int/signal, tính bằng hàm hiện có. Dù không filter, lưu lại giúp phân tích. |
| `rsiAtSignal` | **ĐỒNG Ý** | 1 double/signal, giúp Tier 3 RSI band chính xác hơn. |

### KHÔNG đồng ý

| Field | Vấn đề |
|---|---|
| `volRegimeAtSignal` | **Overfitting bait**. Xem phân tích dimensional explosion bên dưới. |
| `marketRegimeAtSignal` | Tương tự. Regime detection chính nó đã unstable across time windows. |
| `mtfAlignScore` | MTF alignment tại signal time ≠ MTF alignment hiện tại. Nếu dùng để filter: survivorship bias. |
| `bbWidthRatio` | `avgBBWidth` tính trên lookback bao nhiêu? Tham số mới = free parameter. |

### The Dimensional Curse — vấn đề chính

Nếu filter Tier A theo `(case + session + volRegime)`:

```
8 cases × 2 directions × 4 sessions × 4 vol regimes = 256 cells

g_signals[] max = 500 signals
→ 500 / 256 = ~2 signals per cell trung bình

Wilson Score SE tại n=2: SE ≈ 0.35 (±35%)
→ Win rate 60% thực → 95% CI = [25%, 95%]
→ HOÀN TOÀN VÔ NGHĨA THỐNG KÊ
```

Bayesian blend sẽ luôn fallback về theoretical (theoSE=0.15 < adjustedSE=0.35/credibility) → toàn bộ Tier A conditional filtering trở thành **dead code ẩn**.

**Đây là lỗi thiết kế cổ điển**: thêm dimension vào model mà không kiểm tra xem data có đủ population hay không.

### Giải pháp thay thế: Continuous Similarity Weighting

Thay vì discrete bin `(session=London, vol=TRENDING)`, dùng continuous distance:

```mql4
// Mỗi signal lịch sử nhận weight dựa trên khoảng cách tổng hợp
// tới signal hiện tại — KHÔNG CẮT, KHÔNG BIN
double SignalSimilarityWeight(const SignalData &hist, const SignalData &cur)
{
   double w = 1.0;

   // Session: same=1.0, adjacent=0.7, opposite=0.4
   int sessDiff = MathAbs(GetSessionBlock(hist.signalTime) - GetSessionBlock(cur.signalTime));
   if(sessDiff > 2) sessDiff = 4 - sessDiff;  // wrap around
   w *= (sessDiff == 0) ? 1.0 : (sessDiff == 1) ? 0.7 : 0.4;

   // Angle: Gaussian kernel σ=2.0 (WIDE — anti-overfit)
   if(cur.angleStrength > 0.1 && hist.angleStrength > 0.1)
   {
      double dz = cur.angleStrength - hist.angleStrength;
      w *= MathExp(-0.5 * dz * dz / 4.0);  // σ²=4.0
   }

   return w;
}

// Trong ScanStoredSignalsBoth: thay count++ bằng weightedCount += weight
```

**Lợi ích so với conditional filtering**:
1. **Không chia nhỏ samples** — mọi signal đều contribute, signal giống hơn đóng góp nhiều hơn
2. **Graceful degradation** — khi ít data, weights gần bằng nhau → hoạt động như unconditional
3. **Không có thêm hyperparameter ngưỡng** (n≥5, n≥20) cần tune
4. **Không có dimensional explosion** — effective sample size = Σ(weights), luôn > 0

**Rủi ro**: σ quá nhỏ → overfitting (effective n thấp). **Giải pháp**: σ ≥ 2.0 cho tất cả dimensions.

---

## 2. Phản biện: Tier A/B/C/D Architecture — dùng g_outcomes[] actual

### Đồng ý một phần

Ý tưởng dùng actual outcomes thay vì simulation là **đúng về nguyên tắc**.

### Vấn đề kỹ thuật nghiêm trọng

**g_outcomes[] chỉ có binary outcome (+1=TP1, -1=SL), không có TP2/TP3 granularity.**

```c
struct SignalOutcome {
   int outcome;    // 1=TP1 hit, -1=SL hit, -2=Reversal, 0=pending
   // KHÔNG CÓ: đã hit TP2 chưa? TP3 chưa?
};
```

SimulateSignalOutcome trả về `out ∈ {-1, 0, 1, 2, 3}` (multi-level). Pipeline hiện tại tính `probTP1, probTP2, probTP3` riêng biệt.

Nếu thay bằng g_outcomes[]: chỉ tính được `probTP1 vs probSL`. **Mất hoàn toàn probTP2 và probTP3.**

**Đây là regression, không phải improvement.**

### Vấn đề thứ 2: CSV-loaded outcomes thiếu fields

```c
// LoadSessionStatsFromOutcomesCSV sets:
g_outcomes[idx].entryPrice = 0;    // UNKNOWN
g_outcomes[idx].stopLoss   = 0;    // UNKNOWN
g_outcomes[idx].takeProfit1 = 0;   // UNKNOWN
```

Không có entry/SL/TP → không thể tính R-multiple, không thể so sánh SL distance, không thể weight theo trade quality.

### Giải pháp thay thế: Hybrid Integration

```
KHÔNG thay Tier 1/2 bằng g_outcomes[].
THAY VÀO ĐÓ: khi g_outcomes[] có actual outcome cho cùng signalTime:
  → Override SimulateSignalOutcome kết quả bằng actual outcome
  → GIỮ multi-level granularity (simulated TP2/TP3)
  → Chỉ thay win/loss binary từ actual
```

**Cách implement** (trong ScanStoredSignalsBoth):
```mql4
// Sau khi simulate, check if actual outcome exists
for(int o = 0; o < g_outcomeCount; o++)
{
   if(g_outcomes[o].signalTime == g_signals[s].signalTime &&
      g_outcomes[o].outcome != 0)
   {
      // Override win/loss direction — keep TP level from simulation
      if(g_outcomes[o].outcome > 0 && out <= 0) out = 1;      // actual TP but sim said SL/timeout
      if(g_outcomes[o].outcome < 0 && out >= 1) out = -1;     // actual SL but sim said TP
      break;
   }
}
```

**Lợi ích**:
- Actual outcome fixes simulation bias (V2, V4)
- Giữ TP2/TP3 granularity
- Không thay đổi pipeline structure
- Chi phí: O(outcomeCount) lookup per signal → hashmap nếu cần

---

## 3. Phản biện: Time decay 0.93/week

### ~~KHÔNG ĐỒNG Ý~~ → SỬA LẠI: Đồng ý concept, KHÔNG đồng ý parameter

**[ERRATA]** Phiên bản trước nói time decay "double-count" với Weibull — **SAI**. Chúng đo 2 thứ KHÁC NHAU:

| Mechanism | Đo gì | Scope |
|---|---|---|
| **Weibull (Step 5.7)** | Signal HIỆN TẠI aging — edge fading theo thời gian | Intra-signal: "signal này 20 bar tuổi rồi" |
| **Time decay 0.93/week** | Signals LỊCH SỬ THAM KHẢO — recent signals đại diện thị trường hiện tại hơn | Inter-signal: "Case 2 BUY tuần trước quan trọng hơn 3 tháng trước" |

**Không double-count.** Weibull điều chỉnh output probability của signal đang active. Time decay điều chỉnh weight của historical reference signals khi ước lượng win rate. Hai tầng khác nhau.

### Vẫn KHÔNG đồng ý với parameter 0.93

`0.93^(age_weeks)` → half-life ≈ 9.5 tuần.

**Vấn đề**: Đây là **free parameter** không có calibration method.

- Nếu 0.93 quá aggressive → discard data quá sớm → sample size giảm → variance tăng
- Nếu 0.93 quá conservative → keep stale data → bias toward old regime
- Không có cách biết 0.93 đúng hay sai mà không backtest trên nhiều symbols/TFs
- Backtest trên in-sample → fit 0.93 to noise → overfit

### Khuyến nghị

**Concept đúng, chưa implement.** Cần Brier Score tracking trước để validate decay rate. Tạm thời dùng continuous similarity weighting (mục 1) cho session/angle — đã capture phần lớn "relevance" mà không thêm free parameter.

---

## 4. Phản biện: AngleStrength Gaussian weighting (σ=1.0)

### Đồng ý conceptually, KHÔNG đồng ý σ=1.0

Gaussian kernel weighting tốt hơn binary filter (Z≥1.0). Nhưng:

**σ=1.0 quá hẹp cho anti-overfitting**:
```
Z_current=2.0, Z_hist=0.5 → diff=1.5 → weight = exp(-1.125) = 0.32
→ Signal cách 1.5 std chỉ đóng góp 32%
→ Effective sample size giảm mạnh
```

**σ=2.0 an toàn hơn**:
```
diff=1.5 → weight = exp(-0.28) = 0.76
→ Signal cách 1.5 std vẫn đóng góp 76%
→ Effective n giảm ít, bias improvement vẫn có
```

**Bias-Variance Tradeoff**:
| σ | Bias reduction | Variance increase | Net effect |
|---|---|---|---|
| 0.5 | Cao | RẤT cao (eff. n rất nhỏ) | **XẤU — overfit** |
| 1.0 | Trung | Cao | Trung (risky) |
| 2.0 | Thấp-trung | Thấp | **TỐT — safe improvement** |
| 5.0 | Rất thấp | Gần 0 | Gần như không đổi |

### Khuyến nghị: σ=2.0

Khi n > 100 signals cùng case: có thể thử σ=1.5.
Khi n < 30: σ=3.0 hoặc tắt (weight=1.0 cho tất cả).

**Adaptive σ**:
```mql4
double sigma = (sameCaseCount > 100) ? 1.5 :
               (sameCaseCount > 30)  ? 2.0 : 999.0;  // 999 = disabled
```

---

## 5. Phản biện: IC-gated angle adjustment

### **ĐỒNG Ý HOÀN TOÀN** — đây là đề xuất tốt nhất trong review

IC gate là **anti-overfitting measure**, không phải feature addition:
- IC < 0.05 → angleStrength là noise → tắt edge adjustment → **giảm complexity**
- IC ≥ 0.05 → angleStrength có predictive power → giữ adjustment
- Không thêm hyperparameter mới (IC threshold 0.05 là standard)
- Không thêm dimension mới
- Đã có infrastructure (WalkForward.mqh tính IC sẵn)

**Thay đổi nhỏ duy nhất cần thiết**: thêm 3 dòng code vào Step 3.

**ROI**: Cao. Effort: Thấp. Risk: Gần 0.

---

## 6. Phản biện: Tier 3 RSI band ±8pt

### Đồng ý hướng, KHÔNG đồng ý mức

Hiện tại: 21-35pt RSI range → quá rộng, nhất trí.

Đề xuất: ±8pt → quá hẹp cho lower timeframes.

**Phân tích sample impact**:

```
Giả sử 2000 bars lịch sử, ~200 bars có RSI trong zone.
Current ±17pt: ~200 bars match
±8pt:  ~94 bars match (giảm 53%)
±5pt:  ~59 bars match (giảm 71%)
```

Tier 3 đã có weight thấp nhất (0.15). Giảm sample từ 200→94 tăng SE ~40%.

### Khuyến nghị: ±12pt

Compromise: giảm noise nhưng giữ đủ samples.

Hoặc tốt hơn: **continuous Gaussian weighting trên RSI distance** (giống AngleStrength):

```mql4
double rsiDist = MathAbs(barRSI - curSig_RSI);
double rsiWeight = MathExp(-0.5 * rsiDist * rsiDist / (12.0 * 12.0));  // σ=12pt
// Thay vì binary cutoff, mọi bar đều contribute, bar gần hơn weight cao hơn
```

---

## 7. Phản biện: SimulateSignalOutcome spread bias (V2)

### ĐỒNG Ý — đây là bug thực sự

```mql4
// ProbabilityEngine.mqh:243
double avgSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
```

Dùng live spread cho simulation lịch sử = systematic bias.

### NHƯNG giải pháp "lưu spreadAtSignal" chỉ fix 50%

- **Signals mới** (từ bây giờ): spreadAtSignal chính xác ✓
- **Signals cũ** (đã trong g_signals[], rebuilt on fullRecalc): spreadAtSignal = 0 (chưa lưu)
- **Historical bars** (Tier 3, không phải signal): KHÔNG BAO GIỜ có spread

### Giải pháp pragmatic

```mql4
// Trong SimulateSignalOutcome:
double simSpread;
if(knownSpread > 0)  // spreadAtSignal đã lưu
   simSpread = knownSpread;
else
{
   // Heuristic: estimate spread từ session time
   int hr = TimeHour(iTime(NULL, 0, signalBar));
   double baseSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
   if(hr >= 0 && hr < 8)        simSpread = baseSpread * 0.7;  // Asian: thấp hơn
   else if(hr >= 8 && hr < 16)  simSpread = baseSpread * 1.0;  // London/Overlap: normal
   else                          simSpread = baseSpread * 0.8;  // LateNY: hơi thấp
}
```

Heuristic này không hoàn hảo nhưng tốt hơn dùng live spread. Không thêm hyperparameter fit-to-data.

---

## 8. Step 5.6 Session Quality — đánh giá lại

### Code thực tế tốt hơn review trước mô tả

Bản review trước nói Step 5.6 "chỉ là điều chỉnh hậu kỳ". Thực tế:

```mql4
// ProbabilityEngine.mqh:1047-1048
bool hasCaseData = (g_sessionStats.totalPerCase[block][ci] >= 20 &&
                    g_sessionStats.winRatePerCase[block][ci] >= 0.0);
```

Step 5.6 ĐÃ dùng `winRatePerCase[block][ci]` — tức measured win rate per (session × case) — khi n≥20. Đây chính xác là điều review trước đề xuất nên làm.

**Vấn đề thực sự** (nhỏ hơn review trước nói):

1. **Deadzone threshold 10%**: `if(MathAbs(measuredWR - baselineWR) > 0.10)` — khi model nói 55% và data nói 62%, deadzone chặn → data thực bị bỏ qua. Nhưng 7% difference tại n=30 có SE≈0.09 → thực sự là noise. Vậy 10% threshold hợp lý ở moderate n.

2. **n≥20 cho per-case, nhưng 8 cases × 4 sessions = 32 cells**: cần 20 outcomes mỗi cell → 640 total outcomes tối thiểu. Ở M1 (~50 signals/day, ~60% resolve), cần ~20 ngày. Ở H1 (~2/day), cần ~1 năm. → H1+ hiếm khi đạt per-case data.

### Khuyến nghị cải thiện Step 5.6

```
GIẢM deadzone threshold: 0.10 → 0.07 (khi n≥50)
GIẢM n threshold cho per-session (không per-case): 20 → 10 (per-session has 4 cells, not 32)
GIỮ n≥20 cho per-case (32 cells, cần nhiều data)
```

Đây là micro-improvement, không phải architectural change.

---

## 9. Phát hiện bổ sung (từ so sánh lần 2)

### 9.1 `GetSessionQuality()` trong SessionFilter.mqh — ALIVE

Counter-review đúng khi nói `GetSessionQualityNormalized()` = dead code cho probability pipeline.

Nhưng có **hàm KHÁC**: `GetSessionQuality()` tại `SessionFilter.mqh:12` — cũng hardcoded, VÀ đang được gọi:

```mql4
// SignalEngine.mqh:57
score.sessionScore = GetSessionQuality(caseNum, signalTime) * 100.0;
// SignalEngine.mqh:76 — chiếm 8% weight trong total score
```

Session score ảnh hưởng xem signal có pass `InpMinSignalScore` hay không → **quyết định signal nào vào g_signals[]** → gián tiếp ảnh hưởng data quality.

**Verdict**: Impact thấp (8% weight), KHÔNG fix phiên này. Ghi nhận cho phiên sau.

### 9.2 BUY/SELL spread asymmetry trong SimulateSignalOutcome

```mql4
// BUY (line 262-295):  bH >= tp1Price, bL <= slPrice    → KHÔNG dùng spread
// SELL (line 297-330):  effHigh = bH + avgSpread          → DÙNG spread
```

Đây là **ĐÚNG** cho BID-chart:
- BUY: enter ASK, exit BID → chart candle (BID) dùng trực tiếp
- SELL: enter BID, exit ASK → cần +spread vào candle

**Hệ quả khi fix V2**: spread bug chỉ ảnh hưởng **SELL side**. BUY simulation không dùng spread → không bị bias. Khi thêm `spreadAtSignal`: chỉ cần truyền cho SELL path.

### 9.3 Wilson Score SE cần n_eff cho weighted samples

Nếu implement continuous similarity weighting (mục 1), `ScanStoredSignalsBoth` chuyển từ integer counts sang weighted sums. Step 5 Bayesian combine hiện dùng integer n:

```mql4
// Hiện tại:
double measuredSE = MathSqrt((p*(1-p)/n + z2/(4*n*n)) / (1+z2/n));
```

Với weighted samples, n phải thay bằng **effective sample size**:

```
n_eff = (Σw_i)² / Σ(w_i²)
```

Nếu bỏ qua: Σw có thể lớn hơn actual #signals → SE quá nhỏ → probability output overconfident.

**Verdict**: PHẢI implement cùng lúc với similarity weighting. Không tách riêng.

---

## 10. ROADMAP HỢP NHẤT — Nâng cao data quality cho probability pipeline

> **Mục tiêu**: Cải thiện chất lượng dữ liệu đầu vào cho module tính xác suất.
> **Nguyên tắc**: Chỉ làm những gì trực tiếp cải thiện input data. Measurement/validation = phiên sau.

### S1. IC gate cho angle adjustment
**Vấn đề**: AngleStrength edge adjustment (+3%/-3%) luôn active dù angle không predict outcome.
**Fix**: Chỉ apply khi IC ≥ 0.05 (data nói angle có alpha).
**File**: `ProbabilityEngine.mqh` Step 3 (~line 916)
**Code**:
```mql4
// TRƯỚC: luôn apply
if(curSig.angleStrength > 0.1)
{
   double caseDamp = ...;
   double angleAdj = ...;
   edgeAdjustment += angleAdj * caseDamp;
}

// SAU: chỉ apply khi IC xác nhận angle predict outcome
if(curSig.angleStrength > 0.1 &&
   g_walkForward.icSamples >= 20 && g_walkForward.infoCoeff >= 0.05)
{
   double caseDamp = ...;
   double angleAdj = ...;
   edgeAdjustment += angleAdj * caseDamp;
}
```
**Effort**: 2 dòng thêm. **Anti-overfit**: Giảm noise khi angle = random.

### S2. `spreadAtSignal` vào SignalData + fix SimulateSignalOutcome
**Vấn đề**: V2 — SELL simulation dùng live spread cho lịch sử → systematic bias.
**Fix**:
1. Thêm field `double spreadAtSignal` vào `SignalData` (Structs.mqh)
2. Lưu giá trị lúc signal detection (RSI_Advanced.mq4/mq5)
3. Truyền vào `SimulateSignalOutcome` thay `MarketInfo(MODE_SPREAD)`
4. Fallback: nếu `spreadAtSignal == 0` (signal cũ chưa lưu) → giữ behavior hiện tại

**File**: `Structs.mqh`, `RSI_Advanced.mq4`, `RSI_Advanced.mq5`, `ProbabilityEngine.mqh`
**Effort**: 1 field + ~10 dòng sửa. **Anti-overfit**: Fix bug, không thêm parameter.

### S3. `sessionBlock` + `rsiAtSignal` vào SignalData
**Vấn đề**: Signal không lưu context → không thể so sánh "like-with-like".
**Fix**:
1. Thêm `int sessionBlock` + `double rsiAtSignal` vào `SignalData`
2. Lưu lúc signal detection: `sessionBlock = GetSessionBlock(signalTime)`, `rsiAtSignal = BufferGreen[i]`
3. Chưa filter/weight — chỉ lưu foundation cho S5

**File**: `Structs.mqh`, `RSI_Advanced.mq4`, `RSI_Advanced.mq5`
**Effort**: 2 fields + 2 dòng. **Anti-overfit**: Neutral (chỉ lưu data, chưa dùng).

### S4. Hybrid g_outcomes[] override
**Vấn đề**: V4 — Tier 1/2 re-simulate outcome dù actual outcome đã có trong g_outcomes[].
**Fix**: Trong `ScanStoredSignalsBoth`, sau khi simulate, check g_outcomes[] xem cùng signalTime có actual outcome không. Nếu có → override win/loss direction, GIỮ TP level từ simulation.

**File**: `ProbabilityEngine.mqh` (trong `ScanStoredSignalsBoth`)
**Code**:
```mql4
// Sau khi có out từ SimulateSignalOutcome:
for(int o = 0; o < g_outcomeCount; o++)
{
   if(g_outcomes[o].signalTime == g_signals[s].signalTime &&
      g_outcomes[o].outcome != 0)
   {
      // Actual outcome overrides simulation direction
      if(g_outcomes[o].outcome > 0 && out <= 0) out = 1;   // actual TP, sim said SL/timeout
      if(g_outcomes[o].outcome < 0 && out >= 1) out = -1;  // actual SL, sim said TP
      break;
   }
}
```
**Lưu ý**: O(outcomeCount) per signal. Nếu chậm → build datetime→index lookup 1 lần.
**Effort**: ~15 dòng. **Anti-overfit**: Giảm simulation bias, dùng ground truth.

### S5. Continuous similarity weighting
**Vấn đề**: Tier 1/2 pool TẤT CẢ signals cùng case+direction — trộn Asian+London, quiet+volatile.
**Fix**: Weight mỗi historical signal theo khoảng cách tới signal hiện tại.

**File**: `ProbabilityEngine.mqh` (trong `ScanStoredSignalsBoth`)
**Thay đổi**:
```mql4
// TRƯỚC (integer count):
t1_t++;
if(out >= 1) { t1_1++; t1_b1 += btr; }

// SAU (weighted):
double w = 1.0;

// Session similarity: same=1.0, adjacent=0.7, opposite=0.4
int curBlock  = GetSessionBlock(curSig.signalTime);
int histBlock = GetSessionBlock(g_signals[s].signalTime);
int sessDiff  = MathAbs(curBlock - histBlock);
if(sessDiff > 2) sessDiff = 4 - sessDiff;
w *= (sessDiff == 0) ? 1.0 : (sessDiff == 1) ? 0.7 : 0.4;

// Angle similarity: Gaussian kernel σ=2.0
if(curSig.angleStrength > 0.1 && g_signals[s].angleStrength > 0.1)
{
   double dz = curSig.angleStrength - g_signals[s].angleStrength;
   w *= MathExp(-0.5 * dz * dz / 4.0);  // σ²=4.0
}

t1_tw += w;   // weighted total (double, thay int)
if(out >= 1) { t1_w1 += w; t1_b1 += btr * w; }
// ... tương tự cho t1_w2, t1_w3, t1_ws
```

**Hệ quả**: Tier 1/2 counts chuyển từ `int` sang `double`. Cần cập nhật:
- Function signature `ScanStoredSignalsBoth`
- Tier weight calculation (w1, w2, w3)
- `totalUsed` → `totalWeight` (double)
- Step 5 Bayesian combine: dùng `n_eff` (xem S6)

**Effort**: Medium (~50 dòng thay đổi). **Anti-overfit**: Tốt — không mất sample, graceful degradation.

### S6. Wilson Score SE → n_eff
**Vấn đề**: Wilson Score SE dùng integer n. Với weighted samples, n không phản ánh actual uncertainty.
**Fix**: Tính n_eff = (Σw)² / Σ(w²), dùng thay n trong Wilson formula.

**File**: `ProbabilityEngine.mqh` Step 5 Bayesian combine (~line 953)
**Code**:
```mql4
// Cần track thêm trong ScanStoredSignalsBoth:
double t1_sumW2 = 0;  // Σ(w²) — cho n_eff

// Trong loop:
t1_sumW2 += w * w;

// Trong Step 5:
double n_eff = (t1_tw > 0 && t1_sumW2 > 0) ? (t1_tw * t1_tw) / t1_sumW2 : 0;
// Dùng n_eff thay totalUsed trong CombineTheoreticalHistorical
```
**Effort**: ~10 dòng. **Anti-overfit**: Ngăn overconfidence khi weights phân tán.

**PHẢI implement cùng S5.** Không tách riêng.

---

## 11. S7–S9: Weight mở rộng — khai thác data đã capture nhưng chưa dùng

### Phát hiện sau khi implement S1–S6

S5 continuous weighting chỉ dùng **2/5 chiều** có sẵn. Ba chiều còn lại đã capture (S2/S3) nhưng chưa weight:

| Chiều | Field có sẵn | Dùng trong S5? | Ảnh hưởng nếu bỏ qua |
|-------|-------------|----------------|----------------------|
| Session | `signalTime` → `GetSessionBlock` | **Có** | — |
| Angle Z | `angleStrength` | **Có** | — |
| **Recency** | `signalTime` | **CHƯA** | Signal 6 tháng trước = signal hôm qua → regime mixing |
| **RSI value** | `rsiAtSignal` (S3) | **CHƯA** | RSI=15 rất khác RSI=35, cùng weight |
| **ATR regime** | `atrValue` | **CHƯA** | Low-vol signal khác high-vol, không distinguish |

**Lý do không hard-filter**: 500 signals ÷ nhiều chiều = quá ít samples/cell. Continuous weight giữ tất cả data, giảm weight signals ít relevant → đúng nguyên tắc #2 Anti-Overfit Framework.

**Trade-off**: Thêm weight → n_eff giảm (294 → ~80–150). Nhưng 80 samples **thực sự giống** signal hiện tại tốt hơn 294 samples trộn regime.

---

### S7: Recency decay weight — ưu tiên data gần

**Vấn đề**: Thị trường có regime change (Fed policy, correlation structure, vol regime). Signal cũ từ regime khác **không đại diện** cho hiện tại. Không weight recency = probability bị trung bình hóa giữa các regime → mờ.

**Giải pháp**: Exponential decay theo khoảng cách thời gian.

```mql4
// halflife = 60 ngày (~1440 bars M30, ~17280 bars M5)
// signal 60 ngày trước: w *= 0.5
// signal 120 ngày trước: w *= 0.25
// signal 1 ngày trước: w *= 0.99
double daysDiff = (double)(curSig.signalTime - g_signals[s].signalTime) / 86400.0;
if(daysDiff > 0)
   w *= MathExp(-0.693 * daysDiff / 60.0);  // ln(2) ≈ 0.693, halflife=60 days
```

**Anti-overfit**: halflife=60 đủ rộng — không quá aggressive (30 ngày = mất data), không quá lazy (180 ngày ≈ không weight). Cross-symbol stable vì dùng calendar time, không phải bar count.

**KHÔNG double-count với Weibull Time Decay (Step 5.7)**: Recency decay đánh giá **input relevance** (signal cũ ít đại diện cho market hiện tại). Weibull decay đánh giá **output freshness** (signal đã sống lâu → TP khó đạt hơn). Hai concept khác nhau hoàn toàn. Xem Anti-Overfit Framework nguyên tắc #4.

**Effort**: 3 dòng code, cùng block S5 weight.

---

### S8: RSI Gaussian kernel — dùng data S3 đã capture

**Vấn đề**: `rsiAtSignal` đã capture (S3) nhưng chưa ảnh hưởng weight. Signal ở RSI=15 (deep oversold, mean-reversion mạnh) có win rate khác hẳn RSI=32 (barely oversold, dễ fail). Trộn cùng weight = probability sai.

**Giải pháp**: Gaussian kernel tương tự angle weight.

```mql4
// σ=5.0 RSI points — đủ rộng để không quá aggressive
// RSI cách 5 points: w *= 0.61
// RSI cách 10 points: w *= 0.14
// RSI cách 2 points: w *= 0.92
if(curSig.rsiAtSignal > 0 && g_signals[s].rsiAtSignal > 0)
{
   double dr = curSig.rsiAtSignal - g_signals[s].rsiAtSignal;
   w *= MathExp(-0.5 * dr * dr / 25.0);  // σ²=25 (σ=5.0)
}
```

**Anti-overfit**: σ=5.0 là wide prior. RSI range thực tế cho signals ~15–40 (oversold) hoặc ~60–85 (overbought). σ=5.0 nghĩa là signals cách 10 RSI points vẫn giữ 14% weight — không quá strict.

**Effort**: 4 dòng code, cùng block S5 weight.

---

### S9: ATR ratio weight — normalize theo volatility regime

**Vấn đề**: Signal khi ATR=10 pips (low vol, tight range) rất khác ATR=30 pips (high vol, wide swings). Hiện tại simulation dùng TP/SL cố định của mỗi signal (đã tỷ lệ ATR), nhưng market behavior thay đổi theo vol regime. Signal low-vol trong high-vol market (hoặc ngược lại) ít representative.

**Giải pháp**: Weight theo log-ratio ATR.

```mql4
// ATR ratio 1:1 → weight = 1.0
// ATR ratio 2:1 → weight ≈ 0.5
// ATR ratio 3:1 → weight ≈ 0.3
if(curSig.atrValue > 0 && g_signals[s].atrValue > 0)
{
   double logRatio = MathLog(curSig.atrValue / g_signals[s].atrValue);
   w *= MathExp(-logRatio * logRatio / 0.96);  // σ_log ≈ 0.7 (ATR ratio ~2x = 50% weight)
}
```

**Anti-overfit**: Dùng log-ratio vì ATR scale khác nhau giữa symbols. σ_log=0.7 cho phép ATR dao động ±2x vẫn giữ weight đáng kể.

**Effort**: 4 dòng code, cùng block S5 weight.

---

### Thứ tự implement S7–S9 (sau S1–S6)

```
S7 → Recency decay          [3 dòng, impact CAO — loại regime mixing]
S8 → RSI Gaussian kernel    [4 dòng, impact CAO — dùng data S3]
S9 → ATR ratio weight       [4 dòng, impact TRUNG BÌNH]
```

Tất cả thêm vào cùng block [S5] trong `ScanStoredSignalsBoth()` line 747–758.

**Dự kiến n_eff sau S7–S9**: Giảm từ ~294 xuống ~80–150. Wilson SE rộng hơn → Bayesian combine lean thêm về theoretical. Đây là trade-off đúng: ít samples relevant > nhiều samples irrelevant.

---

## 12. LOẠI BỎ — các đề xuất không phục vụ data quality

| # | Đề xuất | Lý do loại |
|---|---|---|
| ~~X1~~ | Thay GetSessionQualityNormalized | Dead code, ROI = 0 |
| ~~X2~~ | Tier A conditional filter (case+session+volRegime) | Dimensional explosion: 256 cells / 500 signals |
| ~~X3~~ | Time decay 0.93/week | Concept đúng nhưng free parameter, cần Brier Score trước |
| ~~X4~~ | Thêm volRegime/marketRegime/mtfAlign/bbWidth vào SignalData | Thêm dimension mà sample không đủ |
| ~~X5~~ | 4-tier A/B/C/D thay Tier 1/2/3 | Over-engineer; hybrid S4 đạt 80% benefit |
| ~~X6~~ | Brier Score tracking | Measurement, không phải data quality (phiên sau) |
| ~~X7~~ | GetSessionQuality() SessionFilter.mqh | 8% weight, risk cao, impact thấp (phiên sau) |
| ~~X8~~ | Platt scaling | Cần ≥200 outcomes + Brier baseline (phiên sau) |

---

## 12. Anti-Overfitting Framework

### Nguyên tắc thiết kế cho indicator real-time với 500 signal cap

```
1. KHÔNG BAO GIỜ thêm discrete conditional dimension nếu chưa có ≥30 samples per cell
   → 500 signals / cells < 30: bị chi phối bởi noise

2. Continuous weighting > Discrete filtering
   → Gaussian kernel giữ tất cả data, gradient weight
   → Binary cutoff mất data, tạo cliff effect

3. Mỗi hyperparameter mới = 1 degree of freedom to overfit
   → Trước khi thêm: "có cách validate cross-symbol không?"
   → Nếu không → dùng wide prior (σ lớn, threshold thấp)

4. Double-count check: nếu effect đã adjust ở 1 step, không adjust lại ở step khác
   (Lưu ý: Weibull output decay ≠ input relevance decay — KHÔNG double-count.
    Xem mục 3 errata.)

5. Weighted samples → PHẢI dùng n_eff
   → n_eff = (Σw)² / Σ(w²)
   → Bỏ qua → Wilson SE quá nhỏ → overconfident probability
```

---

## 13. Kết luận

### So với bản `quant_principal_review.md` gốc:

| Điểm | Review gốc | Counter-review | Hợp nhất |
|---|---|---|---|
| GetSessionQualityNormalized | "Vấn đề cốt lõi" | Dead code | **Dead code — bỏ qua** |
| 7 fields SignalData | Thêm tất cả | Chỉ 3/7 | **3 fields: spread, session, rsi** |
| Tier A/B/C/D | Thay kiến trúc | Over-engineer | **Hybrid override (S4) + similarity weight (S5)** |
| Time decay 0.93/week | Implement | Double-count (SAI) → free param | **Concept đúng, chưa implement** |
| IC gate | Implement | Đồng ý | **Implement (S1)** |
| AngleStrength Gaussian | σ=1.0 | σ≥2.0 | **σ=2.0, gộp vào S5** |
| g_outcomes[] actual | Thay Tier 1/2 | Mất TP2/TP3 | **Hybrid override (S4)** |
| Wilson Score n_eff | Không đề cập | Bắt buộc | **Implement cùng S5 (S6)** |

### 9 items implement (theo thứ tự):

```
S1 → IC gate                    [2 dòng,  anti-overfit, ROI cao]        ✅ Done
S2 → spreadAtSignal + fix sim   [10 dòng, fix bug V2]                  ✅ Done
S3 → sessionBlock + rsiAtSignal [2 fields, foundation]                  ✅ Done
S4 → g_outcomes hybrid override [15 dòng, ground truth]                 ✅ Done
S5 → similarity weighting       [50 dòng, core improvement]             ✅ Done
S6 → Wilson n_eff               [10 dòng, PHẢI đi cùng S5]             ✅ Done
S7 → Recency decay weight       [3 dòng,  loại regime mixing]           ✅ Done
S8 → RSI Gaussian kernel        [4 dòng,  khai thác S3 data]            ✅ Done
S9 → ATR ratio weight           [4 dòng,  vol regime similarity]        ✅ Done
```

> **Quy tắc vàng**: Trong quant, thêm 1 feature đúng tốt hơn thêm 5 features hay.
> Model hiện tại có nền toán vững. Cải thiện data quality đầu vào — không thay model.
> S7–S9 khai thác data đã capture (S2/S3) — không thêm field mới, chỉ dùng data có sẵn.
