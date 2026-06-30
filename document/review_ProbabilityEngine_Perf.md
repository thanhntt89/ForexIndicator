# Performance Review — Probability Calculation Pipeline

**Ngày**: 2026-06-09  
**Phạm vi**: Toàn bộ pipeline từ data retrieval đến output xác suất  
**Files**: ProbabilityEngine.mqh, Normalize.mqh, WalkForward.mqh, MathUtils.mqh

---

## Tóm tắt nhanh

```
Pipeline: CalculateProbability() → per-bar cache (1 full run per bar)
  ├─ STEP 1: ScanStoredSignals × 2  → O(2n), simCachedTP OK
  │    └─ ScanHistoricalATRBased     → O(n_hist) iRSI+iATR, NO CACHE  [P1]
  ├─ STEP 2: MeasureEdgeFromHistory  → O(n_hist) iRSI+iATR+iHigh/iLow, NO CACHE  [P0 CRITICAL]
  ├─ STEP 3: UpdateVolRegime         → 50 iATR calls, no standalone cache  [P1]
  ├─ STEP 5.5: ATR Spike Detection   → 50 iATR calls (signal bar), no cache  [P1]
  └─ IC join (per new bar):          → O(outcomeCount × splitIdx)  [P2]
```

**Vấn đề lớn nhất**: `MeasureEdgeFromHistory()` Phase 2 không có cache — chạy lại toàn bộ O(n) bar scan mỗi khi bar mới xuất hiện.

---

## Chi tiết từng vấn đề

---

### [PROB-P0] MeasureEdgeFromHistory() Phase 2 — Không có cache

**File**: [Normalize.mqh:461-507](../Include/RSI_Advanced/Normalize.mqh#L461)  
**Severity**: P0 — CRITICAL  

**Vấn đề**:

Phase 2 của `MeasureEdgeFromHistory()` scan lịch sử giá ngoài vùng `InpMaxBars`:

```mql4
int phase1Start = Bars - InpMaxBars;   // e.g. 30000 - 500 = 29500
int deepEnd     = Bars - maxFwd - 10;  // e.g. 30000 - 40 - 10 = 29950

for(int i = InpRSIPeriod+10; i < phase1Start && i < deepEnd; i++)  // 0..29476
{
   int bs = Bars - 1 - i;
   double rsi = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs);   // call 1
   double atr = iATR(NULL, 0, InpATRPeriod, bs);             // call 2
   if(!rel) continue;
   double rsiPrev = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs+1); // call 3
   // Rồi simulate O(maxFwd) bars mỗi matching bar
   for(int b = i+1; b < i+maxFwd; b++)
   {
      iHigh(NULL, 0, Bars-1-b);  // call 4
      iLow(NULL, 0, Bars-1-b);   // call 5
   }
}
```

**Ước tính cost trên M1, 30,000 bars, InpMaxBars=500**:
```
Phase 2 iterations: 29,476
Per iteration (non-matching):  2 indicator calls  → 58,952 calls
Matching rate ~20%:  ~5,895 bars
Per matching bar: 1 iRSI + O(40×2) bar data  → ~405,750 calls
TOTAL mỗi lần chạy: ~464,700 indicator/bar data calls
```

**Không có cache nào** — hàm này chạy lại từ đầu mỗi khi `CalculateProbability()` được gọi với signal mới hoặc bar mới.

**Fix đề xuất (PROB-FIX-1)**:

```mql4
double MeasureEdgeFromHistory(int caseNum, bool isBuy, int maxForward)
{
   // [PROB-FIX-1] Cache Phase 2 result per (caseNum, isBuy, signalCount).
   // Phase 2 scans bars OUTSIDE InpMaxBars — those bars don't change when
   // a new bar forms. Only invalidate when new signal appears (g_signalCount changes).
   static int    s_cachedN    = -1;
   static int    s_cachedCase = -99;
   static bool   s_cachedBuy  = false;
   static double s_cachedEdge = 0.51;
   
   // Phase 1 result (from stored signals — fast, has edgeCachedOutcome)
   // ... (existing Phase 1 code, already fast) ...
   
   // Phase 2: deep historical scan
   if(s_cachedN == g_signalCount && s_cachedCase == caseNum && s_cachedBuy == isBuy)
   {
      // Merge Phase 1 (live) + cached Phase 2 totals
      // (need to store Phase 2 totalCount/correctCount separately)
   }
   else
   {
      // Run Phase 2 scan, cache result
      s_cachedN    = g_signalCount;
      s_cachedCase = caseNum;
      s_cachedBuy  = isBuy;
   }
}
```

**Lợi ích**: Phase 2 chỉ chạy khi có signal mới (rare) thay vì mỗi bar. **~100× faster** trên M1.

---

### [PROB-P1a] ScanHistoricalATRBased() — Không có cache

**File**: [ProbabilityEngine.mqh:386-470](../Include/RSI_Advanced/ProbabilityEngine.mqh#L386)  
**Severity**: P1  

**Vấn đề**:

```mql4
void ScanHistoricalATRBased(...)
{
   int startScan = MathMax(Bars - probLookback, InpRSIPeriod + InpBBPeriod + 10);
   int tier3End  = Bars - maxFwd - 10;

   for(int i = startScan; i < tier3End; i++)  // up to maxSamples bars
   {
      double rsi = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs);   // call per bar
      double atr = iATR(NULL, 0, InpATRPeriod, bs);             // call per bar
      if(similar && angleFilter)
      {
         double rsiPrev2 = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs+2); // conditional
         int out = SimulateSignalOutcome(...);  // O(maxFwd) loop
      }
   }
}
```

Được gọi khi `t1_t + t2_t < minSamples` (tức là khi có ít tín hiệu stored). Không có cache — chạy lại hoàn toàn mỗi khi signal/bar thay đổi.

**Fix đề xuất (PROB-FIX-2)**:

```mql4
// Cache per (signalTime, isBuy, caseNum) — kết quả chỉ đổi khi bars mới làm thay đổi tier3End
static datetime s_atrCachedSigTime = 0;
static bool     s_atrCachedBuy = false;
static int      s_atrCachedCase = -1;
static int      s_atrCachedBarCount = -1;
// Cache output variables...
if(curSig.signalTime == s_atrCachedSigTime && curSig.isBuySignal == s_atrCachedBuy &&
   curSig.caseNumber == s_atrCachedCase && Bars == s_atrCachedBarCount)
{
   // Use cached outputs
   return;
}
```

---

### [PROB-P1b] UpdateVolRegime() — 50 iATR calls, không có standalone cache

**File**: [ProbabilityEngine.mqh:486-533](../Include/RSI_Advanced/ProbabilityEngine.mqh#L486)  
**Severity**: P1  

**Vấn đề**:

```mql4
void UpdateVolRegime()
{
   double curATR = iATR(NULL, 0, InpATRPeriod, 0);   // call 1

   for(int i = 1; i <= lookback; i++)                 // 50 calls
      avgATR += iATR(NULL, 0, InpATRPeriod, i);       // calls 2-51
}
```

`CalculateProbability()` có per-bar cache, nên `UpdateVolRegime()` chỉ chạy 1 lần/bar. Tuy nhiên nếu hàm này được gọi từ path khác (e.g. future code), sẽ không có guard.

**Fix đề xuất (PROB-FIX-3)**:

```mql4
void UpdateVolRegime()
{
   // [PROB-FIX-3] Per-bar cache — 50 iATR calls là đủ tốn kém để cache
   static datetime s_volBarTime = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(curBar == s_volBarTime) return;
   s_volBarTime = curBar;
   // ... existing code ...
}
```

---

### [PROB-P1c] ATR Spike Detection (Step 5.5) — 50 iATR gọi lại, có thể dùng g_volRegime

**File**: [ProbabilityEngine.mqh:924-950](../Include/RSI_Advanced/ProbabilityEngine.mqh#L924)  
**Severity**: P1  

**Vấn đề**:

```mql4
// Step 5.5: ATR Spike Detection
int curBarShift = Bars - 1 - curSig.barIndex;  // ← SIGNAL bar shift

for(int a = curBarShift + 1; a <= curBarShift + 50 && a < Bars; a++)
   avgATR += iATR(NULL, 0, InpATRPeriod, a);   // 50 iATR calls tại signal bar
```

Đây là 50 iATR calls THÊM, tính avg ATR tại thời điểm signal bar. Kết quả này không thay đổi vì signal bar đã đóng — nên có thể cache per (signalBarIndex).

Hơn nữa, `UpdateVolRegime()` đã tính avg ATR cho current bar. Nếu signal là current bar, có thể reuse `g_volRegime.atrRatio`. Nếu signal đã cũ, cần cache riêng.

**Fix đề xuất (PROB-FIX-4)**:

```mql4
// Cache signal-bar ATR ratio per signal index — once computed, never changes
static int    s_spikeSignalIdx = -1;
static double s_spikeCurATR   = 0;
static double s_spikeAvgATR   = 0;

if(currentSignalIndex != s_spikeSignalIdx)
{
   s_spikeSignalIdx = currentSignalIndex;
   int curBarShift = Bars - 1 - curSig.barIndex;
   s_spikeCurATR = iATR(NULL, 0, InpATRPeriod, curBarShift);
   s_spikeAvgATR = 0;
   for(int a = curBarShift+1; a <= curBarShift+50 && a < Bars; a++)
      s_spikeAvgATR += iATR(NULL, 0, InpATRPeriod, a);
   if(50 > 0) s_spikeAvgATR /= 50;
}
// Use s_spikeCurATR / s_spikeAvgATR (computed once per signal, not per bar)
```

**Lợi ích**: 50 iATR calls → 0 khi cùng signal (chạy 1 lần khi signal đổi).

---

### [PROB-P2a] ScanStoredSignals() gọi 2 lần — O(2n) thay vì O(n)

**File**: [ProbabilityEngine.mqh:702-725](../Include/RSI_Advanced/ProbabilityEngine.mqh#L702)  
**Severity**: P2  

**Vấn đề**:

```mql4
// Tier 1: same-case
ScanStoredSignals(curSig, true, maxFwd,
                  t1_t, t1_to, t1_1, t1_2, t1_3, t1_s, t1_b1, t1_bs);

// Tier 2: all-cases (scan again!)
ScanStoredSignals(curSig, false, maxFwd,
                  t2_t, t2_to, t2_1, t2_2, t2_3, t2_s, t2_b1, t2_bs);
// Then subtract Tier 1 from Tier 2
t2_t -= t1_t; t2_1 -= t1_1; ...
```

`ScanStoredSignals()` với `matchCase=false` lại scan toàn bộ `g_signals[]` thêm 1 lần nữa. Logic tối ưu: 1 pass duy nhất đếm đồng thời cả same-case và all-case.

**Fix đề xuất (PROB-FIX-5)**:

```mql4
// Single-pass: count tier1 (same-case) and tier2 (all-case) simultaneously
void ScanStoredSignalsBoth(const SignalData &curSig, int maxFwd,
   int &t1_t, int &t1_1, int &t1_2, int &t1_3, int &t1_s, double &t1_b1, double &t1_bs,
   int &t2_t, int &t2_1, int &t2_2, int &t2_3, int &t2_s, double &t2_b1, double &t2_bs)
{
   for(int s = 0; s < g_signalCount; s++)
   {
      if(g_signals[s].signalTime == curSig.signalTime) continue;
      if(g_signals[s].isBuySignal != curSig.isBuySignal) continue;
      // ... (common filters) ...
      
      int out = ...; // simCachedTP lookup (O(1))
      bool sameCase = (g_signals[s].caseNumber == curSig.caseNumber);
      
      // Accumulate into t2 always, t1 conditionally
      t2_t++; ...
      if(sameCase) { t1_t++; ... }
   }
   // Subtract t1 from t2 to get "other-case only"
   t2_t -= t1_t; ...
}
```

**Lợi ích**: Giảm từ 2 lần scan → 1 lần scan `g_signals[]`. 50% faster cho Tier 1+2.

---

### [PROB-P2b] CalculateInformationCoefficient() — O(n×m) join không có index

**File**: [WalkForward.mqh:62-106](../Include/RSI_Advanced/WalkForward.mqh#L62)  
**Severity**: P2  

**Vấn đề**:

```mql4
for(int i = 0; i < g_outcomeCount && n < 200; i++)    // outer: O(outcomeCount)
{
   if(g_outcomes[i].outcome == 0) continue;
   for(int s = 0; s < splitIdx && s < g_signalCount; s++)  // inner: O(splitIdx)
   {
      if(g_signals[s].signalTime != g_outcomes[i].signalTime) continue;
      // Match found
   }
}
```

Với `outcomeCount=1000` và `splitIdx=400`: **400,000 so sánh** mỗi lần tính IC.

**Fix đề xuất (PROB-FIX-6)**:

Pre-build map `signalTime → angleStrength` trước khi join:
```mql4
// Build lookup array (sorted by time for binary search)
// hoặc dùng linear scan nhưng break sớm
for(int s = 0; s < splitIdx; s++)
{
   if(g_signals[s].signalTime == g_outcomes[i].signalTime) // early break when found
   { ... break; }
}
```
Hoặc sort g_signals theo signalTime + binary search → O(n log n) thay vì O(n×m).

---

### [PROB-P3] Signal outcome memory cap — O(n) shift

**File**: [RSI_Advanced.mq4:457-464](../RSI_Advanced.mq4#L457)  
**Severity**: P3 (chạy per-bar khi outcomeCount > 500)  

```mql4
if(g_outcomeCount > 500)
{
   int removeCount = g_outcomeCount - 500;
   for(int i = 0; i < 500; i++)           // O(500) struct copy
      g_outcomes[i] = g_outcomes[i + removeCount];
   g_outcomeCount = 500;
}
```

Mỗi lần chạy: 500 `SignalOutcome` struct copies. Tần suất: chỉ khi outcomeCount vượt 500 (hiếm). Acceptable.

---

## Tổng kết và Priority

| ID | Vấn đề | File:Line | Severity | Fix |
|---|---|---|---|---|
| PROB-P0 | `MeasureEdgeFromHistory()` Phase 2 không cache | Normalize.mqh:461 | **CRITICAL** | Cache per (caseNum, isBuy, signalCount) |
| PROB-P1a | `ScanHistoricalATRBased()` không cache | ProbabilityEngine.mqh:386 | HIGH | Cache per (sigTime, isBuy, caseNum, Bars) |
| PROB-P1b | `UpdateVolRegime()` 50 iATR, không standalone cache | ProbabilityEngine.mqh:486 | HIGH | Per-bar datetime guard |
| PROB-P1c | ATR Spike Detection 50 iATR per bar, per signal | ProbabilityEngine.mqh:924 | HIGH | Cache per signal index (historical bar fixed) |
| PROB-P2a | `ScanStoredSignals()` × 2 = O(2n) | ProbabilityEngine.mqh:702 | MEDIUM | Single-pass combined counting |
| PROB-P2b | IC join O(n×m) không index | WalkForward.mqh:74 | MEDIUM | Binary search trên sorted signalTime |
| PROB-P3 | Outcome cap O(500) struct shift | RSI_Advanced.mq4:457 | LOW | Acceptable |

---

## Ước tính tiết kiệm (M1 chart, 30,000 bars, 1 signal active)

| Fix | Trước | Sau | Tiết kiệm |
|---|---|---|---|
| PROB-P0 | ~464,700 calls/bar | ~0 khi cùng signalCount | **~99% Phase 2** |
| PROB-P1a | ~maxSamples × 3 iRSI/iATR | 0 khi cùng signal | **100% Tier3** |
| PROB-P1b | 50 iATR/bar | 0/bar sau 1 lần | **100% per same bar** |
| PROB-P1c | 50 iATR/bar | 50 iATR khi signal đổi | **100% per same signal** |
| PROB-P2a | O(2n) scan | O(n) scan | **50% ScanStoredSignals** |

---

## Call graph hiện tại (per bar)

```
OnCalculate [per tick]
 ├─ CheckPendingOutcomes()          — scan g_outcomes (per tick, cuong cần check)
 └─ [isNewBar]
     ├─ UpdateSpreadRegime()        — 50 iATR calls [P3, acceptable]
     ├─ CalculateRollingPerformance()— O(outcomeCount) [fast]
     └─ CalculateWalkForwardMetrics()
         └─ CalculateInformationCoefficient()  — O(n×m) [P2b]

 └─ [forceRedraw / 200ms throttle]
     ├─ RefreshMTFData()            — 0 iRSI (RAM buffer, đã fix)
     └─ CalculateProbability()
         ├─ [per-bar cache gate]
         ├─ ScanStoredSignals × 2  — O(2×signalCount), cached outcomes [P2a]
         ├─ ScanHistoricalATRBased  — O(n) iRSI+iATR [P1a, khi Tier1+2 nhỏ]
         ├─ MeasureEdgeFromHistory()
         │   ├─ Phase 1: O(signalCount), edgeCachedOutcome [fast]
         │   └─ Phase 2: O(29k+) iRSI+iATR+iHigh/iLow [P0 CRITICAL]
         ├─ UpdateVolRegime()       — 50 iATR [P1b]
         ├─ ATR Spike Detection     — 50 iATR [P1c]
         └─ ApplyTimeDecay()        — O(1) math [fast]
```
