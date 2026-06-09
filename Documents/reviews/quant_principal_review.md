# Quant Principal Review — Pipeline Xác Suất RSI_Advanced

**Ngày**: 2026-06-09  
**Vai trò**: Principal Quant — đánh giá chất lượng mô hình và đề xuất giải pháp

---

## 1. Nhận xét tổng thể

Nền toán học là **đúng và tinh vi**:
- Gambler's Ruin (Brownian motion với drift) ← phù hợp intraday price movement
- Fat-tail penalty (kurtosis empirical) ← correct tail risk adjustment
- Vol-cluster penalty (Pearson autocorrelation) ← GARCH effect
- Wilson Score SE + Bayesian blend ← solid Bayesian framework
- Weibull survival analysis ← correct conditional probability over time

**Vấn đề không phải model, mà là data đưa vào model.**

**Hai vấn đề kiến trúc cốt lõi:**

```
Vấn đề 1: Prior không phụ thuộc điều kiện thị trường
  Gambler's Ruin dùng edge chung cho mọi session/regime/vol
  → P(TP) bằng nhau dù London trend hay Asian flat

Vấn đề 2: Likelihood sai nguồn
  Tier 1/2 dùng SimulateSignalOutcome() — spread sai, entry proxy
  g_outcomes[] có ACTUAL results nhưng KHÔNG feed vào Tier 1/2
```

---

## 2. Phát hiện quan trọng nhất

### 2.1 Feature tốt nhất đang bị underused

`g_sessionStats.winRatePerCase[block][case]` — lưu win rate THỰC ĐO theo (session × case) từ actual outcomes. Đây là ground truth tốt nhất. Nhưng chỉ dùng làm điều chỉnh hậu kỳ ở Step 5.6, không phải primary estimate.

### 2.2 Prior xây từ ý kiến, không phải data

`GetSessionQualityNormalized()` — hardcoded lookup table:
```mql4
case 2: if(isLondon) return(0.70);   // OPINION — không có data backing
        if(isAsian)  return(0.45);   // OPINION
```
Nên là: nếu g_sessionStats có n≥20, dùng measured win rate. Nếu không, trả về 0.5 (neutral) — không dùng số ý kiến.

### 2.3 SimulateSignalOutcome có systematic bias

File ProbabilityEngine.mqh:243:
```mql4
double avgSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point; // LIVE spread
```
Dùng spread hiện tại cho simulation lịch sử 6 tháng trước. XAUUSD spread Asian ~$0.30, London open ~$0.50–$1.50 — sai số này có thể lật outcome SL/TP cho signals gần SL.

---

## 3. Mở rộng SignalData — Fingerprint đầy đủ

```mql4
struct SignalData {
   // HIỆN CÓ
   datetime signalTime; int barIndex; int caseNumber; bool isBuySignal;
   double entryPrice, stopLoss, takeProfit1, takeProfit2, takeProfit3;
   double atrValue, angleStrength;

   // THÊM MỚI — tất cả available tại signal detection time, chi phí ~40 bytes/signal
   int    sessionBlock;          // 0=Asian 1=London 2=Overlap 3=LateNY
   double rsiAtSignal;           // BufferGreen[i] — exact RSI value
   int    volRegimeAtSignal;     // VOL_QUIET/NORMAL/TRENDING/EVENT
   int    marketRegimeAtSignal;  // DetectMarketRegime() result: -1/0/+1
   int    mtfAlignScore;         // CalculateMTFAgreement() tại signal time
   double bbWidthRatio;          // (BBUpper-BBLower)/avgBBWidth — vol context
   double spreadAtSignal;        // MarketInfo(MODE_SPREAD)*_Point tại bar
}
```

---

## 4. Kiến trúc tầng mới

```
Nguồn dữ liệu                         Trọng số          Khi dùng
───────────────────────────────────────────────────────────────────
TIER A — Actual, same context:
  g_outcomes[] actual result            w = n^0.8         n ≥ 5
  filter: case + session + volRegime

TIER B — Actual, relaxed:
  g_outcomes[] actual result            w = n^0.6         n ≥ 5
  filter: case + direction (any session)
  Time-weighted: w_i = 0.93^(age_weeks) — recent > old

TIER C — Simulation fallback:
  SimulateSignalOutcome(g_signals[])    w = n^0.5         A+B < minSamples
  (dùng spreadAtSignal đã lưu, không phải live spread)

TIER D — Statistical prior:
  Gambler's Ruin với regime-adaptive    w = 1/SE_model²   luôn có
  edge = GetLearnedSessionEdge()
───────────────────────────────────────────────────────────────────
P_final = Σ(rate_i × w_i) / Σ(w_i)    [precision-weighted Bayesian]
```

---

## 5. Regime-conditional edge — thay hardcoded table

```mql4
// THAY THẾ GetSessionQualityNormalized() hardcoded

double GetLearnedSessionEdge(int caseNum, int sessionBlock, double fallback)
{
   int ci = MathMax(0, MathMin(caseNum - 1, CASE_COUNT - 1));
   int n  = g_sessionStats.totalPerCase[sessionBlock][ci];

   if(n >= 20)
   {
      double measuredWR  = g_sessionStats.winRatePerCase[sessionBlock][ci];
      // Bayesian shrinkage: weight toward 0.5 when sample is thin
      double credibility = MathMin(1.0, (double)n / 50.0);
      return(measuredWR * credibility + 0.5 * (1.0 - credibility));
   }
   return(fallback); // Neutral — không dùng số ý kiến
}
```

**Kết quả**: Session quality estimate tự động cải thiện mỗi ngày có thêm outcomes.

---

## 6. AngleStrength — Gaussian kernel weighting

```mql4
// THAY THẾ binary filter (Z≥1.0) trong Tier B/C

double AngleSimilarityWeight(double z_current, double z_hist)
{
   // Gaussian kernel: signals với angle tương tự được weight nhiều hơn
   // σ=1.0: cách 1 std → weight 0.61, cách 2 std → weight 0.14
   double diff = z_current - z_hist;
   return MathExp(-0.5 * diff * diff);
}

// Dùng trong ScanStoredSignalsBoth:
// Thay vì count++ (weight=1), dùng weight += AngleSimilarityWeight(curZ, histZ)
```

---

## 7. IC-gated angle adjustment

```mql4
// CalculateInformationCoefficient() đã tính IC, nhưng chỉ display
// Dùng IC để gate angle edge adjustment:

if(g_walkForward.icSamples >= 20)
{
   double ic = g_walkForward.infoCoeff;
   if(ic >= 0.05)  // Có alpha thực sự
   {
      double angleAdj = MathMax(-0.03, MathMin(0.04, (curSig.angleStrength-1.0)*0.03));
      edgeAdjustment += angleAdj * caseDamp;
   }
   // IC < 0.05: angleStrength là noise → không điều chỉnh
}
```

---

## 8. Đánh giá từng component

| Component | Đánh giá | Action |
|---|---|---|
| Gambler's Ruin formula | ✅ Toán đúng | GIỮ — chỉ thay edge input |
| Fat tail penalty | ✅ Đúng lý thuyết | GIỮ |
| Vol cluster penalty | ✅ GARCH effect | GIỮ |
| Wilson Score SE + Bayes | ✅ Solid framework | GIỮ |
| Weibull survival | ✅ Đúng cho conditional prob | GIỮ |
| GetSessionQualityNormalized | ❌ Hardcoded opinion | THAY bằng learned |
| SimulateSignalOutcome | 🟡 Proxy có bias | HẠ xuống fallback |
| g_outcomes[] in Tier 1/2 | ❌ Không dùng | NÂNG LÊN primary source |
| Tier 3 RSI filter 25–35pt | ❌ Quá rộng | THU HẸP ±8pt |
| Step 5.6 session blend | 🟡 Đúng hướng, quá muộn | Dùng sớm hơn |
| AngleStrength binary | 🟡 Quá thô | Gaussian similarity |
| IC computation | ✅ Tính đúng, dùng sai | Dùng làm gate |

---

## 9. Thứ tự implement — ROI tối đa

### Phase 1 — Data quality (dễ, impact cao)
1. Thêm 7 fields vào `SignalData` (sessionBlock, rsiAtSignal, volRegime, marketRegime, mtfAlignScore, bbWidthRatio, spreadAtSignal)
2. Lưu các giá trị này lúc signal detection trong RSI_Advanced.mq4
3. Thay `GetSessionQualityNormalized()` → `GetLearnedSessionEdge()`
4. Fix spread trong `SimulateSignalOutcome()`: dùng `g_signals[s].spreadAtSignal` nếu có

### Phase 2 — Use actual outcomes (impact rất cao)
5. Trong `ScanStoredSignalsBoth`: check g_outcomes[], nếu signalTime match → dùng actual outcome
6. Tạo Tier A: filter thêm sessionBlock + volRegime
7. Thêm time decay vào Tier B/C: `w_i = 0.93^(age_in_weeks)`

### Phase 3 — Better conditioning
8. IC gate cho angleStrength adjustment
9. AngleStrength Gaussian weighting thay binary
10. Thu hẹp Tier 3 RSI band từ 25–35pt xuống ±8pt

### Phase 4 — Calibration (sau ≥200 outcomes)
11. Platt scaling: fit logistic regression trên predicted vs actual outcome
12. Calibration curve plot để verify P=60% → thực tế ~60%

---

## 10. Kỳ vọng kết quả

| Metric | Hiện tại (ước tính) | Sau Phase 1+2 | Sau Phase 1+2+3 |
|---|---|---|---|
| Brier Score | ~0.23–0.25 | ~0.20–0.22 | ~0.18–0.20 |
| Calibration error | ±8–12% | ±5–7% | ±3–5% |
| IC | 0.03–0.08 (varies) | Unchanged | Unchanged |
| Resolution (discrimination) | Trung bình | Tốt | Tốt |

**Ghi chú về kỳ vọng**: Edge RSI signal thực tế nhỏ (52–58% win rate typical). Không kỳ vọng Brier Score < 0.18 hay Calibration error < 3% — đây là giới hạn thực tế của loại tín hiệu này, không phải giới hạn của model.

---

## 11. Điểm mấu chốt

> Hệ thống hiện tại đang cố ước tính xác suất có điều kiện với dữ liệu không có điều kiện.  
> Model toán học tinh vi nhưng data đưa vào là hỗn hợp nhiều chế độ thị trường.  
> Output là **trung bình của các điều kiện** — không phải probability cho điều kiện **hiện tại**.

**Thứ tự ưu tiên tuyệt đối:**
1. Thêm context vào SignalData (Phase 1) — foundation, không có không làm được Phase 2
2. Dùng g_outcomes[] actual (Phase 2) — impact lớn nhất, loại bỏ simulation bias
3. Thay hardcoded session table bằng learned (Phase 1, mục 3) — loại bỏ opinion
