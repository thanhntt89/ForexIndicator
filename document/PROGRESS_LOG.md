# RSI_Advanced — Nhật ký tiến độ kỹ thuật

**Phiên bản indicator**: v10.20  
**Nền tảng**: MT4 + MT5 (dual-compile qua MQLCompat.mqh)  
**Cập nhật lần cuối**: 2026-06-09

---

## 1. Kiến trúc tổng quan

### Cấu trúc file chính

```
RSI_Advanced.mq4 / RSI_Advanced.mq5        — Main indicator (OnInit/OnCalculate/OnDeinit)
Include/RSI_Advanced/
  Config.mqh          — input parameters (InpRSIPeriod, InpMTF_H1, v.v.)
  Structs.mqh         — struct definitions (SignalData, MTFStatus, SessionStats, v.v.)
  Globals.mqh         — global variables (g_signals[], g_outcomes[], g_mtfData[], RAM buffers)
  MathUtils.mqh       — CalculateSMA(), CalculateStdDev()
  MQLCompat.mqh       — MQL4→MQL5 bridge (iRSI, iATR, iTime wrapper), batch price cache
  RSICore.mqh         — CalculateRSILines() — điền BufferGreen/Red/Orange/BBUpper/BBLower
  MarketRegime.mqh    — DetectMarketRegime(), GetAdaptiveAngleThreshold(), CalculateAngleStrength()
  SwingDetection.mqh  — FindSwingHigh/Low()
  SignalCases.mqh     — DetectCase1..7() — 8 signal types
  SignalEngine.mqh    — (wrapper, nếu có)
  SLTP.mqh            — CalculateSLTP(), MeasureOptimalTPRatios()
  MTFEngine.mqh       — RefreshMTFData(), RAM buffer system (xem mục 3)
  IntermarketAnalysis.mqh — DXY/EURUSD correlation
  SessionStatistics.mqh   — TrackSignalForSession(), CheckPendingOutcomes(), LoadSessionStatsFromOutcomesCSV()
  WalkForward.mqh         — CheckRegimeStability(), WalkForwardData
  ProbabilityEngine.mqh   — CalculateProbability(), ScanStoredSignals()
  Normalize.mqh           — GetSessionQuality(), DetectInstrumentType() (cached)
  ArrowManager.mqh        — DrawArrow(), DeleteObjectsByPrefix()
  LineDrawing.mqh         — DrawSLTPLines(), DrawEntryZones()
  PanelDrawing.mqh        — DrawInfoPanel() — toàn bộ UI panel
  ChartEvents.mqh         — HandleChartEvent() — drag panel, click arrow
  SignalLogger.mqh        — CSV logging queue (signals/outcomes/scoring files)
  VolatilityAnalysis.mqh  — GetVolClusterPenalty(), CalculateATR()
  VolumeAnalysis.mqh      — GetVolumeScore()
  SessionFilter.mqh       — GetSessionQuality()
```

### Build script
`make.ps1` tại project root:
- MT4 compiler: `C:\Program Files (x86)\MetaTrader 4 EXNESS\metaeditor.exe`
- MT5 compiler: `C:\Program Files\TF Global Markets MetaTrader 5 Terminal\MetaEditor64.exe`
- Deploy đến 4 MT4 terminals + 1 MT5 terminal qua AppData path

---

## 2. Phiên 1 — Performance Review & Fixes (17 fixes)

### Phân tích bottleneck per-tick

| Priority | Vấn đề | Tác động |
|---|---|---|
| P0 | `DrawInfoPanel()` gọi `DetectInstrumentType()` mỗi tick | 3× StringFind per tick |
| P0 | `CalculateMTFAgreement()` gọi lại sau khi đã tính | Duplicate call |
| P0 | `GetRegimeColor()` gọi `CheckRegimeStability()` riêng | Duplicate 20-bar scan |
| P1 | `CheckAndLogNewlyResolved()` scan từ i=0 mỗi tick | O(n) scan toàn bộ outcomes |
| P2 | `CheckRegimeStability()` không cache | Chạy lại mỗi tick cùng bar |
| P2 | `GetAdaptiveAngleThreshold()` không cache | 20-bar variance loop × 2/signal |
| P2 | `TrackSignalForSession()` ArrayResize thiếu reserve | O(n) realloc mỗi signal |
| P2 | `LoadSessionStatsFromOutcomesCSV()` ArrayResize thiếu reserve | O(n) realloc mỗi CSV row |
| P2 | `GetFatTailPenalty/GetVolClusterPenalty` không cache | Chạy lại mỗi tick |
| P2 | `iBarShift()` trong MQLCompat linear scan O(10000) | Binary search giảm O(14) |
| P3 | `MeasureOptimalTPRatios()` dùng selection sort O(n²) | Đổi sang ArraySort O(n log n) |
| P3 | `ArrayResize(moveRatios)` trong SLTP thiếu reserve | Realloc mỗi iteration |

### Files đã sửa (17 fixes có tag `[PERF-FIX Pn-m]`)

| File | Fix | Mô tả |
|---|---|---|
| **Normalize.mqh** | P0-1a | Cache `DetectInstrumentType()` vào `g_cachedInstType` global |
| **Normalize.mqh** | P0-1b | Cache `GetCleanSymbolName()` vào `g_cachedCleanSymbol` |
| **Normalize.mqh** | P0-1c | Cache `GetBrokerGMTOffset()` vào `g_cachedBrokerGMT` |
| **Normalize.mqh** | P2-2a | Cache `GetFatTailPenalty()` per-bar bằng static datetime |
| **Normalize.mqh** | P2-2b | Cache `GetVolClusterPenalty()` per-bar bằng static datetime |
| **MQLCompat.mqh** | P2-1 | `iBarShift()`: O(n) linear → O(log n) binary search |
| **MTFEngine.mqh** | P0-3 | Thêm overload `GetMTFTrend(tf, gv, rv)` nhận pre-computed values — **deprecated trong Phiên 2** |
| **WalkForward.mqh** | P2-3a | Cache `CheckRegimeStability()` + `GetRegimeColor()` per-bar |
| **WalkForward.mqh** | P2-3b | Xóa dead loop tính `currentSpread` 50 lần (kết quả không dùng) |
| **MarketRegime.mqh** | P2-5 | Cache `GetAdaptiveAngleThreshold()` per-barIndex |
| **PanelDrawing.mqh** | P0-2a | Dùng `mtfAgree` đã tính thay vì gọi `CalculateMTFAgreement()` lại |
| **PanelDrawing.mqh** | P0-2b | Dùng `g_cachedRegimeColor` trực tiếp (2 chỗ) thay vì `GetRegimeColor()` |
| **SessionStatistics.mqh** | P2-4a | `TrackSignalForSession()`: `ArrayResize(..., 32)` reserve |
| **SessionStatistics.mqh** | P2-4b | `LoadSessionStatsFromOutcomesCSV()`: `ArrayResize(..., 64)` reserve |
| **SignalLogger.mqh** | P1-2 | `CheckAndLogNewlyResolved()`: static `s_logScanStart` bỏ qua prefix đã log |
| **SLTP.mqh** | P2-4c/d | Phase 1+2: `ArrayResize(moveRatios, ..., 64)` reserve |
| **SLTP.mqh** | P3b | `MeasureOptimalTPRatios()`: selection sort O(n²) → `ArraySort` O(n log n) |

### Globals thêm vào Normalize.mqh
```mql4
ENUM_INSTRUMENT_TYPE g_cachedInstType = INST_OTHER;
bool g_instTypeCached = false;
string g_cachedCleanSymbol = "";
bool g_cleanSymbolCached = false;
int g_cachedBrokerGMT = 2;
bool g_brokerGMTCached = false;
```

### Globals thêm vào WalkForward.mqh
```mql4
string g_cachedRegimeText = "Regime: STABLE";
color  g_cachedRegimeColor = clrLime;
datetime g_regimeCacheBarTime = 0;
```

---

## 3. Phiên 2 — MTF RAM Buffer Architecture

### Vấn đề cũ
Mỗi tick `RefreshMTFData()` → `CheckAndAddMTF()` × 6 TF → `CalculateMTF_SMA_RSI()` → **612 iRSI() cross-TF calls/tick**.

### Giải pháp: RAM Buffer 250 bars × 6 TF

**Thêm vào Globals.mqh:**
```mql4
#define MTF_RAM_BARS 250
double   g_mtfRamGreen  [6][MTF_RAM_BARS]; // [slot][barIdx], 0=most recent HTF bar
double   g_mtfRamRed    [6][MTF_RAM_BARS];
double   g_mtfRamOrange [6][MTF_RAM_BARS];
datetime g_mtfRamBarTime[6][MTF_RAM_BARS];
int      g_mtfRamCount  [6];
datetime g_mtfRamLastTime[6];
bool     g_mtfRamReady  [6];
// ~42 KB tổng
```

**Slot mapping:** 0=M5, 1=M15, 2=M30, 3=H1, 4=H4, 5=D1

**MTFEngine.mqh — viết lại hoàn toàn:**

| Function | Khi gọi | Cost |
|---|---|---|
| `MTF_BuildRamBuffer(slot, tf)` | fullRecalc | 284 iRSI calls per TF (one-time) |
| `MTF_InitRamBuffers()` | fullRecalc (từ mq4/mq5) | 6 × Build |
| `MTF_UpdateRamBuffer(slot, tf)` | Khi new HTF bar | shift O(250) + 35 iRSI calls |
| `MTF_UpdateAllRamBuffers()` | Mỗi tick (đầu RefreshMTFData) | 0 nếu không có HTF bar mới |
| `GetMTFTrend(slot)` | Từ CheckAndAddMTF | O(1) read từ RAM |
| `CheckAndAddMTF(slot,...)` | Từ RefreshMTFData | **0 iRSI()** — đọc g_mtfRam*[slot][0] |

**Gọi từ RSI_Advanced.mq4/mq5:**
```mql4
if(fullRecalc)
{
   // ... existing resets ...
   MTF_InitRamBuffers();  // ← thêm vào
}
```

**Hiệu quả:**
- Per-tick: **612 → 0** iRSI() calls khi cùng HTF bar
- Per new HTF bar: tối đa 35 × số TF thay đổi
- Bonus: 250 bars lịch sử MTF có sẵn trong RAM cho thuật toán phức tạp hơn

---

## 4. Lỗi biên dịch pre-existing (KHÔNG phải do chúng ta)

### MT4 — 16 errors, 1 warning
Toàn bộ từ `VirtualTradeTracker.mqh`:
- `error 229: '&' - reference cannot used`
- `error 246: parameter conversion not allowed`

### MT5 — 20 errors, 8 warnings
- `VirtualTradeTracker.mqh`: Mutex.mqh không tìm thấy, `g_vpMutex` undeclared
- `LineDrawing.mqh`: enum conversion errors
- `SignalLogger.mqh`: PeriodSeconds enum, open parenthesis errors

**Lỗi này tồn tại từ trước, chúng ta không tạo ra và chưa fix.**

---

## 5. Trạng thái hiện tại (2026-06-09)

### Đã hoàn thành
- [x] 17 PERF-FIX trong 7 files (Phiên 1)
- [x] MTF RAM buffer system toàn bộ (Phiên 2)
- [x] Tất cả fixes có comment `[PERF-FIX Pn-m]` trong code

### Performance — Trạng thái hoàn chỉnh

**Đã tối ưu hoàn toàn về mặt thuật toán** (2026-06-09). Tất cả hot paths có cache. Bottleneck duy nhất còn lại: panel ObjectSet ~40 calls/200ms — giới hạn MetaTrader API, không thể tối ưu code thêm.

```
Per-tick:  CheckPendingOutcomes O(1), RefreshIntermarket 0/tick, MTF 0 iRSI
Per-bar:   UpdateSpreadRegime 50 iATR (1x/bar), WalkForward O(outcomeCount) integers
Per-signal change: ScanStoredSignalsBoth O(signalCount), Phase 2 chỉ chạy khi signalCount đổi
```

### Chưa làm / Todo tiếp theo (ưu tiên giảm dần)

1. [ ] **Fix VirtualTradeTracker.mqh** — 16 MT4 pre-existing errors (reference/conversion)
2. [ ] **Fix LineDrawing.mqh** — MT5 enum conversion errors
3. [ ] **Fix SignalLogger.mqh** — MT5 PeriodSeconds errors
4. [ ] **MTF divergence detection** — g_mtfRam[6][250] có sẵn 250 bars mỗi TF, implement HTF divergence/confluence từ RAM
5. [ ] **Cải thiện dữ liệu tín hiệu** — xem `document/analysis_signal_data_probability.md` mục 7 để biết chi tiết (priority: dùng g_outcomes actual thay vì simulation, lưu sessionBlock+rsiValue+volRegime vào SignalData)
6. [ ] **Version bump** — v10.20 → v11.0 (sau 3 phiên optimize lớn)
7. [ ] **Commit changes** — branch feature/improvement-v11-spec có nhiều thay đổi chưa commit

### Cách search fixes trong code
```
Grep: [PERF-FIX
```
Tìm tất cả 17 vị trí fix trong codebase.

---

## 4. Phiên 3 — Probability Pipeline Performance Fixes (6 fixes)

**Review doc đầy đủ**: `document/review_ProbabilityEngine_Perf.md`

| Fix | File | Vấn đề | Giải pháp |
|---|---|---|---|
| **PROB-FIX-1** | Normalize.mqh:406 | `MeasureEdgeFromHistory()` Phase 2 — ~465k indicator calls/bar | Cache per (caseNum, isBuy, signalCount, maxForward) |
| **PROB-FIX-2** | ProbabilityEngine.mqh:386 | `ScanHistoricalATRBased()` — O(n) iRSI+iATR, không cache | Cache per (sigTime, isBuy, caseNum, Bars) |
| **PROB-FIX-3** | ProbabilityEngine.mqh:486 | `UpdateVolRegime()` — 50 iATR, không standalone cache | Per-bar datetime guard |
| **PROB-FIX-4** | ProbabilityEngine.mqh:925 | ATR Spike Detection — 50 iATR per bar per same signal | Cache per signal index (historical bar immutable) |
| **PROB-FIX-5** | ProbabilityEngine.mqh:698 | `ScanStoredSignals()` × 2 — O(2n) | New `ScanStoredSignalsBoth()` O(n) + update STEP 1 call |
| **PROB-FIX-6** | WalkForward.mqh:62 | `CalculateInformationCoefficient()` O(n×m) join mỗi bar | Cache per (outcomeCount, splitIdx) |

**Tổng impact**: `CalculateProbability()` trước chạy ~465k indicator calls/bar mới. Sau: ~0 khi cùng signalCount (P0); chỉ ~50 iATR/bar mới (P1b) + ~50 iATR khi signal đổi (P1c).

| **PROB-FIX-7** | WalkForward.mqh:449 | `UpdateSpreadRegime()` — 50 iATR/bar, không cache | Per-bar datetime guard; tick-level dùng cached avgSpread |

**Sau PROB-FIX-7**: Toàn bộ thuật toán đã được tối ưu hoàn toàn. Bottleneck duy nhất còn lại là panel ObjectSet calls (~40 calls/200ms) — giới hạn của MetaTrader chart object API, không phải code logic.

---

## 5. Phiên 4 — Phân tích dữ liệu tín hiệu + Quant Principal Review

**Documents**:
- `document/analysis_signal_data_probability.md` — feature gap analysis chi tiết
- `document/quant_principal_review.md` — **ĐỌC TRƯỚC KHI CODE** kiến trúc cải thiện

---

### 5.1 Cấu trúc tín hiệu hiện tại và những gì còn thiếu

Mỗi `SignalData` lưu 10 fields. 7 fields cần thêm để probability có thể conditional:

```mql4
// CẦN THÊM VÀO SignalData — tất cả available tại signal detection time
int    sessionBlock;          // 0=Asian 1=London 2=Overlap 3=LateNY
double rsiAtSignal;           // BufferGreen[i] — exact RSI value
int    volRegimeAtSignal;     // VOL_QUIET/NORMAL/TRENDING/EVENT
int    marketRegimeAtSignal;  // -1=bear, 0=range, +1=bull
int    mtfAlignScore;         // -100..+100 tại thời điểm signal
double bbWidthRatio;          // (BBUpper-BBLower)/avgBBWidth
double spreadAtSignal;        // MarketInfo(MODE_SPREAD)*_Point
```

**7 vấn đề đã xác định** (xem `analysis_signal_data_probability.md` mục 5):

| # | Vấn đề | Impact |
|---|---|---|
| V1 | Sample size quá nhỏ ở M1/M5 (5–20 mẫu Tier 1) | Tier 1 gần như vô nghĩa |
| V2 | Spread sai: dùng LIVE spread cho historical simulation | Systematic bias SL/TP |
| V3 | Không phân tầng context (trending + ranging + Asian + London = 1 pool) | Win rate trung bình không phản ánh điều kiện thực |
| V4 | g_outcomes[] actual không feed vào Tier 1/2 | Dùng proxy thay vì ground truth |
| V5 | AngleStrength không weight trong Tier 1/2 | Z=4.0 và Z=0.5 trọng số bằng nhau |
| V6 | Tier 3 RSI filter quá rộng (21–35 điểm) | Match không granular |
| V7 | Detection priority cứng — bar chỉ có 1 case | Miss multi-case context |

---

### 5.2 Phát hiện quan trọng nhất (Quant Principal Review)

**1. Prior xây từ ý kiến, không phải data:**

`GetSessionQualityNormalized()` hardcode:
```mql4
case 2: if(isLondon) return(0.70);   // KHÔNG CÓ DATA BACKING
        if(isAsian)  return(0.45);
```
Nhưng `g_sessionStats.winRatePerCase[block][case]` — đã có win rate THỰC ĐO — chỉ dùng làm điều chỉnh phụ Step 5.6. Đây là feature tốt nhất trong hệ thống đang bị underused.

**2. Likelihood sai nguồn:**

```
g_outcomes[]    → actual price hit TP/SL (tick-level, bid/ask)  ← GROUND TRUTH
SimulateOutcome → bar OHLC simulation, spread sai              ← PROXY, có bias
```
Tier 1/2 dùng proxy. g_outcomes actual không vào Tier 1/2.

**3. Kết luận cốt lõi:**
> Hệ thống ước tính xác suất có điều kiện với dữ liệu **không có điều kiện**.
> Output là trung bình của nhiều chế độ thị trường — không phải probability cho điều kiện **hiện tại**.

---

### 5.3 Kiến trúc tầng đề xuất

```
TIER A — Actual, same context     w = n^0.8   (n≥5)
  g_outcomes[] actual result
  filter: case + session + volRegime

TIER B — Actual, relaxed          w = n^0.6   (n≥5)
  g_outcomes[] actual result
  filter: case + direction
  time-weight: 0.93^(age_weeks)

TIER C — Simulation fallback      w = n^0.5   (A+B < minSamples)
  SimulateSignalOutcome(g_signals[])
  dùng spreadAtSignal đã lưu, không phải live spread

TIER D — Statistical prior        w = 1/SE²   (luôn có)
  Gambler's Ruin với edge = GetLearnedSessionEdge()
  thay GetSessionQualityNormalized() hardcoded
```

**GetLearnedSessionEdge()** thay thế hardcoded table:
```mql4
double GetLearnedSessionEdge(int caseNum, int sessionBlock, double fallback)
{
   int n = g_sessionStats.totalPerCase[sessionBlock][caseNum-1];
   if(n >= 20)
   {
      double measured = g_sessionStats.winRatePerCase[sessionBlock][caseNum-1];
      double cred = MathMin(1.0, n / 50.0);  // Bayesian shrinkage
      return(measured * cred + 0.5 * (1.0 - cred));
   }
   return(fallback);  // neutral — không dùng số ý kiến
}
```

---

### 5.4 Đánh giá component — giữ / sửa / bỏ

| Component | Verdict | Action |
|---|---|---|
| Gambler's Ruin formula | ✅ Toán đúng | GIỮ |
| Fat tail + Vol cluster penalty | ✅ Đúng lý thuyết | GIỮ |
| Wilson Score SE + Bayesian | ✅ Solid | GIỮ |
| Weibull survival analysis | ✅ Đúng | GIỮ |
| `GetSessionQualityNormalized()` | ❌ Hardcoded opinion | THAY bằng `GetLearnedSessionEdge()` |
| SimulateSignalOutcome Tier 1/2 | 🟡 Proxy có bias | HẠ xuống fallback Tier C |
| g_outcomes[] | ✅ Ground truth | NÂNG LÊN Tier A primary |
| Tier 3 RSI 25–35pt filter | ❌ Quá rộng | THU HẸP ±8pt |
| AngleStrength binary | 🟡 Thô | Gaussian kernel similarity |
| IC computation | ✅ Tính đúng | DÙNG làm gate angle adjustment |

---

### 5.5 Roadmap implement (Phase 1→4)

| Phase | Nội dung | Dependencies | Impact |
|---|---|---|---|
| **1 — Data foundation** | Thêm 7 fields vào SignalData; lưu tại signal detection; thay hardcoded session table | Phải làm trước | Foundation |
| **2 — Use actual outcomes** | Tier A từ g_outcomes[]; time decay 0.93/week | Phase 1 | Highest |
| **3 — Better conditioning** | IC gate; Gaussian angle weight; Tier 3 ±8pt | Phase 1+2 | Medium |
| **4 — Calibration** | Platt scaling sau ≥200 outcomes | Phase 1+2+3 | Refine |

**Kỳ vọng sau Phase 1+2**: Brier Score từ ~0.23–0.25 xuống ~0.18–0.20; Calibration error từ ±8–12% xuống ±3–5%.

---

## 6. Tham khảo nhanh per-file

| File | Trạng thái | Ghi chú |
|---|---|---|
| Config.mqh | Không đổi | inputs, defines |
| Structs.mqh | Không đổi | struct types |
| Globals.mqh | **Thêm MTF RAM buf** | g_mtfRam*, MTF_RAM_BARS |
| MQLCompat.mqh | **Fix P2-1** | iBarShift binary search |
| RSICore.mqh | Không đổi | |
| MarketRegime.mqh | **Fix P2-5** | Cache GetAdaptiveAngleThreshold |
| SwingDetection.mqh | Không đổi | |
| SignalCases.mqh | Không đổi | |
| SLTP.mqh | **Fix P2-4c/d + P3b** | ArrayResize reserve, ArraySort |
| MTFEngine.mqh | **Rewrite hoàn toàn** | RAM buffer system, 0 iRSI/tick |
| IntermarketAnalysis.mqh | Không đổi | |
| SessionStatistics.mqh | **Fix P2-4a/b** | ArrayResize reserve |
| WalkForward.mqh | **Fix P2-3a/b + PROB-FIX-6/7** | Cache regime, dead loop removed; cache IC join + UpdateSpreadRegime |
| ProbabilityEngine.mqh | **PROB-FIX-2/3/4/5** | Cache ATRBased, VolRegime, SpikeDetect; ScanStoredSignalsBoth |
| Normalize.mqh | **Fix P0-1a/b/c + P2-2a/b + PROB-FIX-1** | Global caches + MeasureEdgeFromHistory cache |
| ArrowManager.mqh | Không đổi | |
| LineDrawing.mqh | Không đổi (MT5 errors pre-exist) | |
| PanelDrawing.mqh | **Fix P0-2a/b** | Reuse mtfAgree, g_cachedRegimeColor |
| ChartEvents.mqh | Không đổi | |
| SignalLogger.mqh | **Fix P1-2** | s_logScanStart skip logged |
| VolumeAnalysis.mqh | Không đổi | |
| VolatilityAnalysis.mqh | Không đổi | |
| SessionFilter.mqh | Không đổi | |
| RSI_Advanced.mq4 | **+MTF_InitRamBuffers()** | fullRecalc block |
| RSI_Advanced.mq5 | **+MTF_InitRamBuffers()** | fullRecalc block |
