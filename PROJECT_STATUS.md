# RSI Advanced V11.30 - Project Status & Context Summary

Tài liệu này đóng vai trò là **Source of Truth (Nguồn thông tin gốc)** của dự án. AI ở các phiên tiếp theo **BẮT BUỘC** đọc file này để biết trạng thái hiện tại của code, các phát hiện định lượng mới nhất, và các công việc cần tiếp tục triển khai.

---

## 1. Trạng Thái Code & Kiến Trúc Hiện Tại
Dự án đã được cấu trúc lại hoàn chỉnh để hỗ trợ song song cả MT4 và MT5 với tính năng ghi log định lượng:

- **Build Pipeline**: File `make.ps1` thực hiện build song song `RSI_Advanced.mq4` (MT4) và `RSI_Advanced.mq5` (MT5).
- **MT5 Compatibility**: Sử dụng `Include/RSI_Advanced/MQLCompat.mqh` để chạy chung mã nguồn logic với MT4.
- **Logging System**: Ghi log định lượng chi tiết với cơ chế RAM Queue + Bulk Flush để chống đơ chart. Đang được tắt mặc định ở `Config.mqh`.

---

## 2. Kết Quả Phân Tích Định Lượng (XAUUSD - M1 vs M5)
- **M1 vs M5**: Khung M1 hiệu quả hơn M5 về kỳ vọng toán học (MFE trung bình lớn hơn MAE trung bình).
- **Phân loại Case**: 
  - *Case 6 (TrendCont)*: Hoạt động rất tốt trên M1, đánh nhanh thắng nhanh. Tránh đánh vào phiên Asian và LateNY.
  - *Case 7 (SidewayBreak)*: Hoạt động cực tốt trên M5, nhưng rất tệ trên M1 do sideway ảo.
- **Phiên Giao Dịch**: Phiên Overlap Âu-Mỹ là phiên ngon nhất cho M1. Phiên London là phiên ngon nhất cho M5.

---

## 3. Changelog Các Phiên Gần Nhất

### V11.30 — Data Quality Metrics + Signal Invalidation Fix (2026-06-25)

**Signal Invalidation Fix:**
- SL-breached signals now clear all lines (PREFIX_LINE/PROB/ZONE) instead of dim drawing
- Auto-switch to next valid signal (newest first) when active signal invalidated
- Entry zones no longer persist from old signal when new signal appears (reset s_zonesDrawn on signal change)

**Data Quality Metrics (new feature):**
- 11 new fields in ProbabilityData struct: rawCountT1/T2, countT3, nEffT1/T2, timeoutCount, oldestDays, realPct, wrT1/T2/T3
- Panel: 1 compact DQ line `T1:nEff(raw) T2:nEff(raw) T3:count Real:X% Span:Xd`
- Color coding: green (Real>=50%), yellow (>=20%), orange (<20%)
- CSV scoring log: +4 columns (RAW_T1, RAW_T2, COUNT_T3, REAL_PCT)
- Design doc: `document/design_data_quality_metrics.md`

**Files modified:** Structs.mqh, ProbabilityEngine.mqh, PanelDrawing.mqh, SignalLogger.mqh, RSI_Advanced.mq4, RSI_Advanced.mq5

### V11.29 — Cross-Broker Scan Direction Fix (2026-06-11)

**Van de**: V11.28 time-based cap KHONG du de fix cross-broker inconsistency.
Root cause thuc su: scan direction OLD→NEW + maxSamples limit → 2 broker lay sample tu
thoi ky hoan toan khac nhau.

**Phan tich root cause:**
- Tier 3 `ScanHistoricalATRBased()` va Edge `MeasureEdgeFromHistory()` Phase 2 deu loop OLD→NEW
- Khi dat `maxSamples` (200 cho Tier 3, 2000 cho Edge), loop break
- MT4 (40k bars): `startScan` = bar 22720 → first 200 qualifying bars tu 5-6 thang truoc
- MT5 (10k bars): `startScan` = bar 110 → first 200 qualifying bars tu 5-7 tuan truoc
- Gold SELL 5 thang truoc (sideways $2600) → WR=36.9%, SELL 5 tuan truoc (uptrend $3200+) → WR=14.3%
- Ket qua: MT4 Edge=62%, MT5 No Edge — cung data nhung khac time sampling

**Fix 2 diem (scan direction reversal):**

1. **ProbabilityEngine.mqh — `ScanHistoricalATRBased()`**: Doi loop tu `i = startScan → tier3End`
   sang `i = tier3End-1 → startScan` (NEW→OLD). Ca 2 broker bat dau tu boundary voi stored signals
   (cung thoi diem) → lay cung nhom bars gan nhat. `iTime()` guard doi tu `continue` sang `break`
   (khi gap bar cu hon cutoff, tat ca bars sau cung cu hon).

2. **Normalize.mqh — `MeasureEdgeFromHistory()` Phase 2**: Doi loop tu `i = RSIPeriod+10 → phase1Start`
   sang `i = deepUpperBound-1 → RSIPeriod+10` (NEW→OLD). Cung logic: sample recent data truoc.

**Tai sao NEW→OLD tot hon OLD→NEW:**
```
Scan direction | MT4 (40k bars)          | MT5 (10k bars)          | Match?
---------------|-------------------------|-------------------------|-------
OLD→NEW        | Samples tu 5-6 thang    | Samples tu 5-7 tuan     | KHONG
NEW→OLD        | Samples tu 1-4 tuan     | Samples tu 1-4 tuan     | GIONG
```

**Bonus**: NEW→OLD cung cai thien chat luong — recent market conditions phu hop hon de predict
signal hien tai (VD: gold uptrend 2026 khong lien quan den sideways 2023).

**Files changed**: ProbabilityEngine.mqh, Normalize.mqh

---

### V11.28 — Cross-Broker Tier 3 Data Normalization (2026-06-11)

**Van de**: Tier 3 (ATR historical scan) cho ket qua khac nhau giua 2 broker cung TF cung symbol:
- `GetEffectiveProbMaxBars()`: `available * 0.8` scale voi `Bars` → broker 65k bars scan 52k (tu 2005), broker 30k scan 24k (tu 2015) → khac time period hoan toan
- `GetMaxLookbackForTimeframe()`: `sqrt(available/5000) * baseCap` → broker nhieu lich su hon collect nhieu sample hon
- `ScanHistoricalATRBased()`: khong co time-based guard → scan bar tu 2005 khi broker co 20 nam lich su, trong khi S7 hard prune da loai Tier 1/2 signals >365 ngay

**Tier 1/2 da thong nhat** (khong doi): InpMaxBars=500 co dinh, CandleNormalize GMT+0, S7 recency decay time-based, S5-S9 similarity weighting.

**Fix 3 diem cho Tier 3:**

1. **MathUtils.mqh — `GetEffectiveProbMaxBars()`**: Bo `available * 0.8`, doi sang time-based cap khop S7 maxDays:
   - M1-M5: 60 ngay (= S7 hard prune), M15-H1: 180 ngay, H4+: 365 ngay
   - `barsPerDay = 1440 / Period()`, return `MathMin(timeBased, available)`
   - Ca 2 broker cung TF scan cung calendar window

2. **MathUtils.mqh — `GetMaxLookbackForTimeframe()`**: Bo `sqrt(Bars/5000)` scaling, dung fixed baseCap:
   - M1=300, M5=250, M15/M30=200, H1=150, H4=120, D1+=100
   - Ca 2 broker collect cung so sample toi da

3. **ProbabilityEngine.mqh — `ScanHistoricalATRBased()` loop**: Them `iTime()` guard:
   - `t3CutoffTime = TimeCurrent() - t3MaxDays * 86400`
   - Skip bars cu hon maxDays, dong bo voi S7 hard prune cua Tier 1/2
   - Belt-and-suspenders: bat edge cases weekends/holidays lam lech bar count vs thoi gian

4. **Normalize.mqh — `MeasureEdgeFromHistory()` Phase 2 deep scan**: Them `iTime()` guard:
   - Phase 2 scan tu bar 24 den `Bars-InpMaxBars` → broker 40k bars scan 20 nam, broker 10k scan 5 nam
   - Fix: `edgeCutoffTime = TimeCurrent() - edgeMaxDays * 86400`, skip bars cu hon maxDays
   - Verified: day la nguyen nhan MT5 M15 khong hien Edge (SELL tren gold 2022+ = no edge)

5. **MathUtils.mqh — `GetTPMeasurementBars()`**: Them time-based cap:
   - `target = MathMin(target, timeBased)` truoc khi cap boi available
   - TP ratio measurement cung scan cung calendar window

**Cross-broker consistency sau fix:**
```
Component              | Truoc fix         | Sau fix
-----------------------|-------------------|------------------
Tier 1/2 signal window | 500 bars (OK)     | Khong doi
Tier 3 scan window     | Bars*0.8 (KHAC)   | maxDays co dinh (GIONG)
Tier 3 sample cap      | baseCap*sqrt(Bars) | baseCap co dinh (GIONG)
Tier 3 time boundary   | Khong co           | iTime() guard (GIONG)
Edge Phase 2 scan      | bar 24→Bars (KHAC) | iTime() guard (GIONG)
TP measurement scan    | Bars-100 (KHAC)    | maxDays cap (GIONG)
```

**Verified on M15 XAUUSD**: MT4 scan gold 2015 (sideways) → SELL WR=61%, Edge=62%.
MT5 scan gold 2022+ (uptrend) → SELL WR=14%, no Edge. Root cause: cung bug Bars-dependent scan.

**Files changed**: MathUtils.mqh, ProbabilityEngine.mqh, Normalize.mqh

---

### V11.25 — Edge Display Fix + Smart Session Block + Dynamic SL (2026-06-10)

**Bug Fix: H4 TP1 khong hien thi Edge:% (ProbabilityEngine.mqh + PanelDrawing.mqh)**

Root cause (3 layers):
1. `avgBarsToTP1/avgBarsToSL` duoc assign BEN TRONG block `if(totalUsed >= minBayesian)`. Tren H4, S5-S9 similarity weighting (session+RSI+ATR discount) lam giam nEff xuong duoi 10 → avgBarsToTP1 = 0. Fix phien truoc: tach ra ngoai minBayesian gate.
2. ATR fallback (tinh avgBarsToTP1 tu khoang cach TP/SL) nam BEN TRONG `if(tw > 0)`. Debug log cho thay tw=0.000 (t1tw=1.47, t2tw=0.44 — deu duoi threshold 3.0 do S5-S9 discounting). Fix: di chuyen ATR fallback ra NGOAI `if(tw > 0)`.
3. ATR fallback dung linear estimate `D/ATR` → TP1=4×ATR cho 4 bars. Voi barsAgo=5, Weibull decay cuc manh → probability crash tu 72.6% xuong 51.6%, pha vo tin hieu cu. Fix: random walk scaling `(D/ATR)^2` → TP1=4×ATR cho 16 bars (price diffuses as sqrt(N)).
4. Panel `hasProb` condition: `totalSamples >= minSamples` → khi tw=0, totalSamples=0, panel an toan bo Probability section. Fix: them `|| probTP1 > 0` de hien panel khi probability da duoc tinh qua theoretical path.

Fixes:
- ProbabilityEngine.mqh:~1108: ATR fallback ra ngoai `if(tw > 0)`, doi `MathMax(1.0, D/ATR)` sang `MathMax(2.0, (D/ATR)^2)`
- PanelDrawing.mqh:266: `hasProb` them `|| g_currentProb.probTP1 > 0`

**Feature: Smart Session Hard Block (Config.mqh, mq4, mq5)**

3 inputs moi trong group "Session Hard Block":
- `InpHardCase6Asian = true` — Block Case 6 (Trend Cont.) trong Asian/DeadZone (UTC 20:00-07:00)
- `InpHardCase6LateNY = true` — Block Case 6 trong LateNY (UTC 16:00-20:00)
- `InpHardM1Overlap = true` — M1: chi cho signal trong Overlap session (UTC 12:00-16:00)

Quyet dinh khong implement `InpHardM1BuyBlock`: probability engine da co `InpMinSignalScore` + hien thi AVOID khi WR thap. Hard block theo timeframe la redundant va vi pham nguyen tac "cau hinh, khong phu thuoc TF".

Pre-detection inject: `int _sb = GetSessionBlock(time[i]); if(InpHardM1Overlap && Period()==TF_M1 && _sb!=2) continue;`
Post-detection inject: Case 6 block khi `_sb==0||_sb==3`, sau do `if(buySignal==0 && sellSignal==0) continue;`

**Feature: Dynamic Case-specific SL Ratio (SLTP.mqh, mq4, mq5)**

Them `int caseNum = 0` vao `CalculateSLTP()`, `CalculateSLTP_ATR()`, `CalculateSLTP_Hybrid()`. Override `slRatio`:
- Case 7 + M5 → `slRatio = 1.2` (tight stop, sideway breakout — cu gia di nhanh hoac sai)
- Case 6 + M5 → `slRatio = 2.2` (wide stop, trend continuation can room)
- `maxSLDist = outATR * (slRatio + 0.5)` trong Hybrid cung duoc cap nhat

TP1 khong override: `MeasureOptimalTPRatios()` chay TRUOC va se override TP1 neu |optTP1-InpTPRatio|>15% → hard-code TP1 bi vo hieu hoa.

Call sites: `CalculateSLTP(..., buySignal)` va `CalculateSLTP(..., sellSignal)` trong mq4/mq5.

**Files changed**: `ProbabilityEngine.mqh`, `PanelDrawing.mqh`, `Config.mqh`, `SLTP.mqh`, `RSI_Advanced.mq5`, `RSI_Advanced.mq4`

---

### V11.24 — MTFSlotTF PERIOD_* → TF_* Fix (2026-06-10)

**Van de CRITICAL**: `MTFSlotTF()` trong MTFEngine.mqh tra ve `PERIOD_H4=16388` thay vi `TF_H4=240`. Tren MT5:
- `MinutesToTimeframe(16388)` khong match → fallback ve `_Period` → doc SAI timeframe
- MTF slot filtering broken: `16385 <= 240` = FALSE → H1/H4 slots khong bi filter tren H4 chart
- Weight comparisons `g_mtfData[i].timeframe >= PERIOD_H4` luon FALSE
- Ket qua: H4 signal hoan toan khac giua MT4/MT5 (khac Case, khac MTF trend, entry chenh 50+ pip)

**Fix**:
1. **MTFEngine.mqh:23-28** — `MTFSlotTF()` doi tu `PERIOD_*` sang `TF_*` (M5/M15/M30/H1/H4/D1)
2. **MTFEngine.mqh:280-302** — Weight comparisons doi tu `PERIOD_*` sang `TF_*`
3. **WalkForward.mqh:423** — Cross-TF mismatch check doi `PERIOD_H4` → `TF_H4`
4. **MathUtils.mqh:48-56** — `GetTimeframeString()` switch cases doi tu `PERIOD_*` sang `TF_*`

**Ket qua verified ALL TFs (MT4 Exness GMT+0 vs MT5 ThinkMarkets GMT+3)**:
```
TF   | Case  | MTF         | Entry diff | Status
-----|-------|-------------|------------|--------
M1   | diff  | —           | ~6 pip     | Expected (TF qua nho, price feed sensitive)
M5   | match | match       | ~17 pip    | Normal (price feed sensitivity)
M15  | match | match       | ~0.06 pip  | Perfect
M30  | match | exact match | ~0.4 pip   | Perfect
H1   | match | match       | ~1 pip     | Perfect
H4   | match | exact match | ~21 pip    | Good (broker bar timing)
D1   | match | match       | ~15 pip    | Good (3h close difference)
W1   | match | match       | N/A        | Good
```
M1/M5: chenh lech do price feed giua broker, khong fix duoc bang code.
M15-W1: dong bo tot, Case + MTF trend + direction deu khop.

**Root cause documentation**: Luu vao `memory/feedback_period_mt5.md` — 3 traps de tranh tai pham

---

### V11.23 — GMT Normalization Fixes: D1 chart + H4 shift + TF scope (2026-06-10)

**Van de 1 — H4 chart signal lech 1-2 nen** (GetNormH4Shift):
- MT5 H4 signal hien thi o nen 12:00 (broker), MT4 o nen 20:00 (UTC).
- Nguyen nhan: `GetNormH4Shift` dung broker H4 bar open time de map → UTC H4 block. Broker H4 bar 12:00 (GMT+3) = UTC 09:00 → floor to UTC 08:00, nhung nen broker nay thuc te overlap voi UTC 12:00 block.
- Fix: dung thoi diem H1 bar cuoi cung trong H4 bar (`brokerBarTime + 3*3600`) de map chinh xac 1:1.

**Van de 2 — D1 chart RSI sai hoan toan** (RSICore.mqh):
- `g_gmtNormActive=true` tren D1 chart (vi D1 period > H4), nhung RSICore chi co H4 normalized path → D1 chart bars nhan RSI tu H4 normalized data (sai dimension).
- Fix: Them TF dispatch: `Period()==TF_H4` dung H4 normalized, `Period()==TF_D1` dung D1 normalized. Cac TF khac dung native iRSI.

**Van de 3 — D1 normalization lookup sai** (GetNormD1Shift):
- Broker D1 bar o 00:00 (GMT+3) = UTC 21:00 ngay truoc → floor sai ngay.
- Fix: dung midpoint `+12*3600` truoc khi convert → UTC day dung.

**Van de 4 — W1/MN1 chart** (ShouldNormalizeH4):
- `ShouldNormalizeH4()` tra true cho W1/MN1, nhung khong co normalized W1/MN1 data, va GMT offset chi anh huong <2.5% candle duration.
- Fix: `ShouldNormalizeH4()` chi active cho H4 va D1. W1/MN1 dung native iRSI (du chinh xac).
- Panel hien thi "SHIFTED Xh" (orange) tren W1/MN1 thay vi "Normalized" (lime).

**Files changed**: CandleNormalize.mqh, RSICore.mqh, PanelDrawing.mqh

**TF normalization matrix sau fix**:
```
TF      | Chart RSI        | MTF H4/D1           | Panel Status
--------|------------------|---------------------|------------------
M1-M30  | native iRSI (OK) | normalized (g_gmtMTFNormNeeded) | no GMT line
H1      | native iRSI (OK) | normalized (g_gmtMTFNormNeeded) | no GMT line
H4      | g_normRSI (UTC)  | normalized           | "H4 Normalized"
D1      | g_normD1RSI(UTC) | normalized           | "D1 Normalized"
W1/MN1  | native iRSI (OK) | normalized           | "SHIFTED Xh"
```

---

### V11.22 — GMT MTF Normalization (2026-06-10)

**Van de**: MT4 (Exness, GMT+0) va MT5 (ThinkMarkets, GMT+3) cho ket qua MTF hoan toan nguoc nhau tren H1:
- MT4 H1: MTF H4 SELL BEAR, D1 SELL BEAR → STRONG BEAR 2/2 ALIGNED
- MT5 H1: MTF H4 BUY BULL, D1 BUY BULL → STRONG BULL 3/3 AGAINST
- Nguyen nhan: `ShouldNormalizeH4()` tra false tren H1 chart → MTF engine dung native `iRSI(NULL, PERIOD_H4/D1, ...)` voi broker candle boundaries (GMT+3) → RSI hoan toan khac.

**Fix GMT-FIX-B3c — MTF H4/D1 Normalized RSI**

1. **Globals.mqh**: Them `g_gmtMTFNormNeeded` flag — true khi broker offset != 0, bat ke chart TF nao
2. **CandleNormalize.mqh**: Them D1 normalization pipeline hoan chinh:
   - `NORM_D1_MAX=200`, `NORM_D1_MIN_CONVERGE=30`
   - `BuildNormalizedD1Candles()` — group H4 normalized candles thanh D1 (cung UTC day)
   - `ComputeNormalizedD1RSI()` — Wilder RSI tren D1 closes
   - `GetNormD1Shift()` — binary search map broker time → D1 normalized shift
   - `GetNormD1RSIByShift()` — lookup D1 RSI by shift
   - `GetNormMTF_RSI(slot, tf, barShift)` — unified MTF helper cho slot 4 (H4) va 5 (D1)
   - `BuildNormalizedH4Candles()` goi `BuildNormalizedD1Candles()` o cuoi
3. **MTFEngine.mqh**: `MTF_BuildRamBuffer` va `MTF_UpdateRamBuffer` check `g_gmtMTFNormNeeded` cho slot 4/5, dung `GetNormMTF_RSI()` truoc khi fallback ve native `iRSI`
4. **RSI_Advanced.mq5/mq4**:
   - OnInit: set `g_gmtMTFNormNeeded = (g_gmtBrokerOffset != 0)`
   - fullRecalc block: `BuildNormalizedH4Candles()` TRUOC `MTF_InitRamBuffers()` de normalized data san sang
   - Per-tick: refresh normalized candles cho ca `g_gmtNormActive` va `g_gmtMTFNormNeeded`
   - `g_normRecalcDone` force fullRecalc bao gom ca MTF normalization

**Flow tren MT5 (GMT+3) H1 chart**:
```
OnInit → g_gmtMTFNormNeeded=true → BuildNormalizedH4Candles (tu H1 data)
  → BuildNormalizedD1Candles (tu H4 normalized) → ComputeNormalizedD1RSI
fullRecalc → BuildNormalizedH4Candles → MTF_InitRamBuffers
  → MTF_BuildRamBuffer(slot=4/5) → GetNormMTF_RSI → normalized RSI thay native
```

**Files changed**: Globals.mqh, CandleNormalize.mqh, MTFEngine.mqh, RSI_Advanced.mq5, RSI_Advanced.mq4

---

### V11.21 — Signal Display Filter + Quant Logging + VTT Removal (2026-06-08)

**VirtualTradeTracker — XÓA HOÀN TOÀN**
- Xóa `VirtualTradeTracker.mqh` (309 dòng) + 3 tài liệu liên quan
- Xóa toàn bộ tham chiếu trong: mq4, mq5, Config, Globals, Structs, SignalLogger, LineDrawing
- Xóa: VirtualPosition struct, virtual CSV logger, CreateHistoryLine/UpdateHistoryLineEnd, 6 input parameters
- Lý do: `VP_HasActiveTrade()` đang **block tín hiệu M1/M5**, không có vòng feedback vào quyết định giao dịch

**Signal Display Filter — Ẩn visual cho AVOID/WAIT**
- Khi recommendation = AVOID / WAIT / COUNTER_TREND:
  - SL/TP lines: **ẩn** (không còn 5 đường ngang rác)
  - Probability labels: **ẩn**
  - Entry zones: **ẩn**
  - Arrow: **giữ** (tham chiếu lịch sử)
  - Panel: **giữ** (hiển thị AVOID [score/100] + lý do)
- Files: `RSI_Advanced.mq4`, `RSI_Advanced.mq5`

**Scoring CSV — File log thứ 3 cho quant analysis**
- File mới: `scoring_SYMBOL_TF_YYYY.csv`
- 15 cột: `SIGNAL_ID, SCORE, REC_LEVEL, PROB_TP1, PROB_SL, PROB_N, EV, RR, MTF_AGREE_PCT, MTF_TREND, ANGLE_Z, HOUR, DOW, SPREAD_RATIO, WF_ROBUST`
- JOIN với signals + outcomes qua `SIGNAL_ID` → đủ context cho phân tích quant
- File: `SignalLogger.mqh`

**Signal Log Enrichment**
- Thêm 3 cột vào `signals_*.csv`: `ANGLE_Z`, `HOUR`, `DOW`
- MQ5 được thêm đầy đủ: `LoggerInit`, `FlushLogQueues`, `CheckAndLogNewlyResolved` (trước đây thiếu hoàn toàn)
- `TradeRecommendation` struct thêm 2 field: `ev`, `mtfAlignRatio` để expose cho scoring log
- Files: `SignalLogger.mqh`, `RSI_Advanced.mq5`, `Normalize.mqh`

**Hệ thống log 3 file:**
```
MQL4/Files/RSI_Advanced_Logs/
├── signals_XAUUSD_M1_2026.csv    — signal facts (entry, SL/TP, ATR, session, angleZ, hour, dow)
├── scoring_XAUUSD_M1_2026.csv    — decision context (score, rec, prob, EV, MTF, spread)
└── outcomes_XAUUSD_M1_2026.csv   — results (TP/SL hit, bars held, MFE/MAE)
JOIN: signals ← scoring ← outcomes ON SIGNAL_ID
```

---

### V11.20 — M1/M5 Anti-Overfitting + Broker Independence (2026-06-07)
1. **Signal Priority Reorder**: thứ tự 1→7 đổi thành 6→2→4→3→1→5→7 cho M1/M5
2. **Cooldown Enforcement**: `InpCooldownBars=5` được sử dụng thực sự trong signal loop
3. **MTF Minimum Agreement Gate**: `InpMinMTFAgreement=40` — tối thiểu 40% MTF đồng ý mới confirm signal
4. **MTF Weighted Agreement**: H4/D1=3x, H1=2x, M30=1.5x (trước đây bằng nhau)
5. **Raised Bayesian Min Samples**: M1=16, M5=13, H1=10 (trước đây =3 cho tất cả)
6. **Tighter Edge RSI Filters**: thu hẹp RSI ranges theo từng case, clamp lên [0.45, 0.70]
7. **Broker-Resistant Spread**: ATR × % theo instrument thay vì MODE_SPREAD
8. **Continuous EV Scoring**: linear mapping thay thế 6-step discrete

---

### V11.10 — Probability Display Fix (2026-06-07)
- Fix: Probability labels không hiển thị trên M1/M5
- Nguyên nhân: gate `totalSamples < GetMinSamplesForTimeframe()` — M1 cần 50 mẫu, gần như không bao giờ đạt
- Fix: đổi gate thành `probTP1 <= 0 && probSL <= 0`
- Thêm label `[theo]` khi dùng theoretical-only probability (n=0)

---

## 3b. Các Cập Nhật & Bản Vá Định Lượng Bắt Buộc Ghi Nhớ (Phiên trước)
AI phiên trước và User Thanh đã phối hợp rà soát toàn diện hệ thống `SLTP.mqh` và `IntermarketAnalysis.mqh` dưới góc độ Quant:

1. **Fix Lỗi Asymmetric Bias trong SL/TP**: 
   Đã gỡ bỏ giới hạn `MathMin/MathMax` trong `CalculateSLTP()`. Thuật toán đo MFE (Lợi nhuận tối đa quá khứ) thông qua `MeasureOptimalTPRatios` giờ đây được phép nới rộng TP (Let Profits Run) nếu lịch sử cho thấy lệnh có thể chạy xa hơn, không còn bị chặn một chiều như trước.
   
2. **Khắc phục Lookahead Bias (Rò rỉ dữ liệu Tương lai)**: 
   Hàm `FindNearestSwingLow` và `FindNearestSwingHigh` đã được ép sử dụng nến đã đóng (`bs = 1` trở lên). Tuyệt đối **không dùng `bs = 0`** để gán biến Depth ATR cho Swing, tránh hiện tượng Repainting SL/TP liên tục khi nến đang chạy.

3. **Luật Bất Thành Văn cho Intermarket Analysis**:
   Khác với SL/TP, hàm `CalculateIntermarketTrend` đóng vai trò là Macro-Momentum Filter. **BẮT BUỘC dùng nến Live (`shift 0`)** cho tính toán ATR và SMA của DXY/EURUSD để EA có thể block lệnh ngay tắp lự khi USD bùng nổ. Không được sửa thành nến `1` nếu không EA sẽ bị mù thông tin vĩ mô chậm 1 nến!

4. **Fix Timeout Data**: 
   Hàm `MeasureOptimalTPRatios` và `MeasureZoneReachProb` đã được sửa để dùng `timeBasedMax`, không bị rớt mất dữ liệu thống kê.

5. **Quy tắc mã hóa (Encoding) và Viết comment ASCII**: 
   Đã phát hiện và sửa lỗi vỡ font tiếng Việt (double-encoding mojibake) trong `RSI_Advanced.mq4` do xung đột bảng mã giữa công cụ soạn thảo UTF-8 của AI và cách đọc ANSI của MetaEditor. Toàn bộ comment tiếng Việt lỗi đã được chuyển sang tiếng Anh không dấu. **Bắt buộc AI sau này chỉ được phép viết comment bằng tiếng Anh hoặc tiếng Việt không dấu trong tất cả các file nguồn `.mq4`, `.mq5`, `.mqh`.** Chi tiết xem tại [Encoding_Guide.md](file:///d:/Thanh/Forex/RSI_Advanced/Documents/Encoding_Guide.md).

---

## 4. Dinh Huong Cong Viec Cho AI Phien Tiep Theo (Next Steps)

### DA HOAN THANH — GMT Normalization (V11.22 + V11.23)
- [x] GMT-FIX-B3: H4 candle normalization tu H1 data (chart RSI)
- [x] GMT-FIX-B3b: Force fullRecalc khi normalization ready (async H1 data MT5)
- [x] GMT-FIX-B3c: MTF H4/D1 normalized RSI — fix MTF signals nguoc nhau giua MT4/MT5
- [x] D1 normalization pipeline (build tu H4 normalized candles)
- [x] Fix GetNormH4Shift: +3h offset de map broker H4 bar → UTC H4 block chinh xac
- [x] Fix RSICore D1 dispatch: D1 chart dung g_normD1RSI thay vi H4 normalized
- [x] Fix GetNormD1Shift: +12h midpoint de map broker D1 bar → UTC day chinh xac
- [x] Fix ShouldNormalizeH4: chi H4/D1, W1/MN1 dung native iRSI (<2.5% impact)
- [x] Panel: hien thi "D1 Normalized" tren D1 chart, "SHIFTED Xh" tren W1/MN1

### DA VERIFY — V11.24 ALL TFs (2026-06-10)
- [x] Compile thanh cong ca mq4 va mq5
- [x] MT5 M15-M30: Case + MTF + Entry gan nhu identical voi MT4
- [x] MT5 H1: Case + MTF H4/D1 trend khop voi MT4 H1
- [x] MT5 H4: Case 6 + STRONG BEAR -100% khop voi MT4 (truoc fix: hoan toan khac)
- [x] MT5 D1: Arrow pattern + direction khop, entry chenh ~15 pip (3h close diff)
- [x] MT5 W1: Arrow pattern khop, khong can normalization
- [x] MT5 M1/M5: Chenh lech signal la do price feed, khong phai bug

### DA HOAN THANH — Probability Pipeline S1-S9 (verified 2026-06-10)
Roadmap chi tiet: `document/counter_review_anti_overfit.md`
- [x] **S1** IC gate angle adjustment — chi apply edge khi IC>=0.05 (ProbabilityEngine.mqh:1161)
- [x] **S2** spreadAtSignal field + fix SELL simulation bias (Structs.mqh + ProbabilityEngine.mqh)
- [x] **S3** sessionBlock + rsiAtSignal fields (Structs.mqh — foundation cho S5/S8)
- [x] **S4** g_outcomes[] hybrid override — actual outcome ghi de simulation (ProbabilityEngine.mqh:850-916)
- [x] **S5** Continuous similarity weighting: session + angle Gaussian (ProbabilityEngine.mqh:832+)
- [x] **S6** Wilson n_eff (sumW2) — ngan overconfidence khi weights phan tan (ProbabilityEngine.mqh:841+)
- [x] **S7** Recency decay (halflife 60 days, TF-adaptive) (ProbabilityEngine.mqh:931)
- [x] **S8** RSI Gaussian kernel (TF-adaptive sigma) (ProbabilityEngine.mqh:946)
- [x] **S9** ATR ratio weight (log-ratio sigma=0.7) (ProbabilityEngine.mqh:958)

Items DA LOAI BO (counter-review ket luan khong can):
- ~~GetSessionQualityNormalized~~ (dead code, ROI=0)
- ~~Tier A/B/C/D architecture~~ (over-engineer, hybrid S4 dat 80% benefit)
- ~~4/7 SignalData fields~~ (volRegime/marketRegime/mtfAlign/bbWidth — dimensional explosion)
- ~~Time decay 0.93/week~~ (free parameter, can Brier Score truoc)

### DA HOAN THANH — V11.25 (2026-06-10)
- [x] Bug fix: H4 TP1 Edge display — 3 layers: avgBarsToTP1 ngoai minBayesian, ATR fallback ngoai tw>0, random walk (D/ATR)^2, panel hasProb relaxed
- [x] Smart Session Hard Block: InpHardCase6Asian, InpHardCase6LateNY, InpHardM1Overlap (Config.mqh + mq4/mq5)
- [x] Dynamic Case SL ratio: Case 7 M5=1.2 ATR, Case 6 M5=2.2 ATR (SLTP.mqh + mq4/mq5)
- [x] InpHardM1BuyBlock: KHONG implement — probability engine + InpMinSignalScore da xu ly du
- [ ] Commit branch feature/improvement-v11-spec

### V11.26 — WalkForward False Positive Fix + SL Floor Sync (2026-06-10)

**Bug Fix: WalkForward MathAbs false positive (WalkForward.mqh:181-196)**

Root cause: H4 XAUUSD tren 2 broker cho signal giong nhau (Case 6 SELL) nhung score khac 28 diem (27 WAIT vs 55 ENTRY). Nguyen nhan:
1. `MathAbs(IS - OOS) < 7.0` block ca truong hop OOS > IS (khong phai overfit)
2. OOS sample n=8 → Wilson CI ±25% → bat ky gap nao deu la noise
3. wfScore swing 15 diem (-10 OVERFIT vs +5 ROBUST) gay ra chenh lech score lon

Fix 3 dieu kien:
- `isOosGap = IS - OOS` (one-sided, chi penalize IS > OOS = overfit that)
- `enoughOOS = (oosSamples >= 15)` — minimum sample guard
- `isRobust = !enoughOOS || (ratioOK && absoluteOK && hasWins)` — default ROBUST khi thieu data

**Bug Fix: SL floor missing trong MT4 (RSI_Advanced.mq4)**

MT5 co SL floor block (line 476-484) ngan SL qua nho → Gambler's Ruin output cuc doan (W:1%). MT4 thieu block nay. Da sync:
- BUY: `minSLDist = curATR * InpSLRatio * 0.3`, neu `slDist < minSLDist` → floor len
- SELL: tuong tu

**Math correction: Gambler's Ruin TP2-TP3 gap (document/review_probability_counter.md)**

Loi document (khong phai code): claim TP2-TP3 gap = 5.1% tai edge=0.56 la SAI. Dung: 2.75% tai edge=0.56 (r=0.7866). 5.1% ung voi edge=0.48 (min bound). Da sua bang math table day du trong document.

**Files changed**: WalkForward.mqh, RSI_Advanced.mq4, document/review_probability_counter.md

---

### V11.27 — MT5 Bars Macro Root Cause Fix + Low Data Gate + Server Time (2026-06-10)

**CRITICAL BUG FIX: MT5 Bars macro tra ve server total thay vi rates_total (ROOT CAUSE)**

Trieu chung: MT5 M30 hien n=0 probability samples, recommendation CAUTION ENTRY W:67% (theoretical only). MT4 cung TF hien n=282 va W:43% (historical data).

Root cause chain:
1. `_compat_GetBars()` trong MQLCompat.mqh tra ve `::Bars(_Symbol, _Period)` = tong so bar tren server (vd: 50,000)
2. `barIndex` tu OnCalculate chi trong pham vi `rates_total` (vd: 5,000)
3. `SimulateSignalOutcome()` tinh `barShift = Bars - 1 - signalBar` = 50000 - 1 - 4999 = 45001 → tro vao bar co xua hoac khong ton tai
4. `iHigh(NULL, 0, 45001)` tra ve 0 → `if(bH == 0 || bL == 0) continue;` → skip toan bo bars
5. Simulation timeout → n=0 → fallback Gambler's Ruin theoretical model → 67% probability → CAUTION ENTRY voi ZERO data backing
6. `GetConfidenceText(0, ...)` skip margin of error (me=0) → hien "HIGH" confidence (!)

Fix 3 layers:
- **Layer 1 (Root Cause)**: `_compat_GetBars()` gio return `g_ratesTotal` (set = `rates_total` o dau OnCalculate). Anh huong ~25 cho dung `Bars` trong ProbabilityEngine.mqh va Normalize.mqh — tat ca fix tu dong qua macro.
- **Layer 2 (Safety Net)**: `GetTradeRecommendation()` them hard gate: khi `probSamples < GetMinSamplesForTimeframe()`, cap ENTRY/CAUTION_ENTRY xuong WAIT. AVOID/COUNTER_TREND khong bi anh huong.
- **Layer 3 (Visual Warning)**: `GetConfidenceText()` them early return: n=0 → "NO DATA (theoretical only)" mau do, n<minSamples → "LOW DATA (n<X)" mau cam.

**Feature: Server Time tren Panel (PanelDrawing.mqh)**

Hien thi `Server: HH:MM | UTC: HH:MM (GMT+X)` tren panel (ca no-signal va signal-active). Cho phep cross-broker comparison: 2 panel cung hien UTC time → xac nhan cung thoi diem khi so sanh signal.

**Files changed**: MQLCompat.mqh, Globals.mqh, RSI_Advanced.mq5, RSI_Advanced.mq4, MathUtils.mqh, Normalize.mqh, PanelDrawing.mqh

---

### HIEU BIET QUAN TRONG: H4 Signal Khac Nhau Giua Broker (EXPECTED)

**Day la hanh vi BINH THUONG, khong phai bug.** Arrow tren H4 se KHAC nhau giua 2 broker co GMT offset khac nhau (vd: Exness GMT+0 vs ThinkMarkets GMT+2).

**Nguyen nhan:**
- H4 candle boundaries lech 2h: Exness 00/04/08/12/16/20 UTC vs ThinkMarkets 22/02/06/10/14/18 UTC
- OHLC hoan toan khac → swing high/low khac → divergence khac
- GMT normalization CHI fix RSI (rebuild H4 tu H1 → GMT+0 aligned), KHONG fix price data

**Case nao anh huong:**
| Case | Dung gi | Khac giua broker? |
|------|---------|-------------------|
| 1 (OB/OS), 4 (Strong), 6 (TrendCont), 7 (Sideway) | Chi RSI | Gan giong (RSI normalized) |
| 2 (RegDiv), 3 (HidDiv), 5 (Orange) | RSI + price high[]/low[] | SE KHAC (price khong normalized) |
| Cooldown cascade | Bar index | 1 signal lech → chain toan bo arrows sau do lech |

**Khi compare signal giua MT4 vs MT5**: phai dung CUNG BROKER (hoac cung GMT offset). Khac broker → khac arrows la expected.

---

### DA HOAN THANH — V11.27 (2026-06-10)
- [x] ROOT CAUSE: MT5 Bars macro return server total → fix bang g_ratesTotal (MQLCompat.mqh, Globals.mqh, mq4, mq5)
- [x] Safety net: GetTradeRecommendation cap ENTRY→WAIT khi n < minSamples (Normalize.mqh)
- [x] Visual warning: GetConfidenceText n=0 → "NO DATA" do, n<min → "LOW DATA" cam (MathUtils.mqh)
- [x] Server time display: Server + UTC + GMT offset tren panel (PanelDrawing.mqh)
- [ ] Compile va verify MT5 co n>0 sau Bars fix
- [ ] Commit branch feature/improvement-v11-spec

### DA HOAN THANH — V11.28 (2026-06-11)
- [x] GetEffectiveProbMaxBars: time-based cap (maxDays per TF) thay cho Bars*0.8 (MathUtils.mqh)
- [x] GetMaxLookbackForTimeframe: fixed baseCap, bo sqrt(Bars/5000) scaling (MathUtils.mqh)
- [x] ScanHistoricalATRBased: iTime() guard skip bars cu hon maxDays (ProbabilityEngine.mqh)
- [x] MeasureEdgeFromHistory Phase 2: iTime() guard cho deep scan (Normalize.mqh) — fix MT5 M15 no Edge
- [x] GetTPMeasurementBars: time-based cap thay cho Bars-100 (MathUtils.mqh)
- [ ] Compile va verify cross-broker consistency

---

### V11.30 — Normalize.mqh Dead Code Removal + SLTP Systematic Fix (2026-06-12)

**PHAN 1 — Normalize.mqh: 4 bugs da fix (DONE)**

1. **Session quality sanity check xoa (Normalize.mqh:371)**
   Dead code: diff = |localHour - utcHour| luon = |GMTOffset|. Block if(diff>5) trigger cho
   moi broker UTC+6+ → return 0.5 co dinh. Fix: xoa 6 dong dead code.

2. **Credibility ramp discontinuity (Normalize.mqh:696)**
   Bug: tai histSamples=minSamples, credibility nhay nguoc tu ~0.98 xuong 0.70 (them data = it tin hon).
   Fix: credibility = MathMin(1.0, histSamples/minSamples) — smooth monotonic, dat 1.0 tai minSamples.

3. **GetUTCDatetime historical DST (Normalize.mqh:207)**
   Bug: dung current GMT offset de convert historical signals → sai 1h cho signals qua DST boundary.
   Fix: dung GuessEUBrokerOffset(localTime) — DST-aware cho thoi diem lich su, khong can thay struct.

4. **GetScoreWeights dead code xoa (Normalize.mqh:417)**
   14 dong dead: defined 1 lan, called 0 lan. Score engine dung component scores rieng.
   Fix: xoa toan bo function + section header.

**PHAN 2 — SLTP.mqh: design spec + fix**

Bug 1 — "CLOSER TP" comment sai (CRITICAL)
- Hien tai: replace outTP1 bang measured bat ke closer hay not
- Fix: Bayesian shrinkage blended=measured*cred + parametric*(1-cred), chi apply khi blended < parametric
- k_tf shrinkage prior: M5=50, M15=80, H1=180, H4=300, D1=600
- Minimum samples truoc khi blend: M5=80, M15=60, H1=30, H4=20, D1=10
- Clip [InpSLRatio*0.8, InpTPRatio*2.0]

Bug 2 — Phase 2 OLD→NEW + khong filter case
- Fix: doi sang NEW→OLD + time cutoff (giong MeasureEdgeFromHistory)
- Them caseNum param, graceful degradation L1(case-specific)→L2(group)→L3(direction)→L4(parametric)
- Min samples per level per TF: L1 M5=60/H4=15, L2 M5=100/H4=25, L3=30
- IS-only (bo qua OOS signals giong MeasureEdgeFromHistory)

Bug 3 — CASE-SL chi M5, thieu H1/H4/D1
- Fix: multiplier table x InpSLRatio theo [case x TF]:
  Case 0=1.0, Case1/5=0.80-1.00, Case2/3=0.95-1.10, Case4=1.05-1.25, Case6=1.10-1.20, Case7=0.70-0.95
  Bounds [0.70, 1.40]. Function GetCaseTFSLMultiplier(caseNum, tf).

Bug 4 — _Period vs Period() dormant MT5
- Fix: doi _Period → Period() (1 dong).

**Files changed**: Normalize.mqh (done 2026-06-12), SLTP.mqh (done 2026-06-12)

**Chi tiet SLTP.mqh implementation:**

Bug 4: _Period → Period() (1 dong, dormant fix MT5 ENUM vs minutes)

Bug 3: GetCaseTFSLMultiplier(caseNum, tf) — full table 6 cases x 5 TF groups:
  slRatio = InpSLRatio * multiplier, bounds [0.70, 1.40]
  Case 0=1.0/1.0/1.0/1.0/1.05 | Case 1/5=0.80/0.85/0.90/0.95/1.00
  Case 2/3=0.95/1.00/1.00/1.05/1.10 | Case 4=1.05/1.10/1.15/1.20/1.25
  Case 6=1.10/1.10/1.10/1.15/1.20 | Case 7=0.70/0.80/0.85/0.90/0.95
  Applied in CalculateSLTP_ATR() and CalculateSLTP_Hybrid()

Bug 2: MeasureOptimalTPRatios() rewrite:
  + Them caseNum=0 parameter, Phase 2 doi OLD→NEW sang NEW→OLD + time cutoff
  + IS-only: bo OOS signals (splitIdx giong MeasureEdgeFromHistory)
  + Graceful degradation L1→L2→L3→L4:
    L1 case-specific (RSI filter theo case), L2 case-group (reversal vs trend),
    L3 direction-only (original), L4 parametric (return neu khong du data)
  + Min samples: L1 M5=60/H4=15 | L2 M5=100/H4=25 | L3=30
  + Helper: _TPRatioRSIFilter(), _TPRatioMinSamples()

Bug 1: CalculateSLTP() CLOSER TP + Bayesian shrinkage:
  + blended = measured * cred + parametric * (1-cred), k_tf: M5=50→D1=600
    D1 15 samples → 2.4% measured weight (near-pure parametric)
    M5 60 samples → 54.5% measured weight
  + Conservative gate: chi apply khi blended closer to entry (tighten only, not widen)
  + Hard clip [InpSLRatio*0.8, InpTPRatio*2.0]

---

---

### V11.31 — Signal Log Enrichment for Quant Scalping Analysis (2026-06-12)

**Muc tieu**: Bo sung du lieu log de phan tich hieu qua tin hieu theo tung TF
cho scalping intraday H4 tro xuong. Data sau khi co du se dung de:
- Xac dinh combination case + TF + session + vol_regime co win rate cao nhat
- Phan tich partial profit (TP2/TP3 hit rate) de chon risk strategy
- Feature engineering cho ML model predict signal quality

**Danh gia log hien tai**:
- signals.csv (21 cols): SIGNAL_ID, ENTRY/SL/TP, ATR, SESSION, ANGLE_Z, HOUR, DOW
- scoring.csv (15 cols): SCORE, PROB_TP1, EV, RR, MTF_AGREE_PCT, SPREAD_RATIO, WF_ROBUST
- outcomes.csv (10 cols): OUTCOME, BARS_HELD, MFE, MAE, EXIT_PRICE
- JOIN 3 file qua SIGNAL_ID — thiet ke dung, can bo sung cot

**Tasklist V11.31 — SignalLogger.mqh (file: Include/RSI_Advanced/SignalLogger.mqh)**

P1 — Critical (must have cho scalping quant):
- [ ] P1-1: signals.csv them RSI_AT_SIGNAL — tu sig.rsiAtSignal (da co trong struct, chua log)
            Feature quan trong: RSI level nao per case co win rate tot nhat
- [ ] P1-2: signals.csv them ATR_RATIO — curATR / iATR(50,1); numeric vol regime
            Phan tich: QUIET (<0.7) vs EVENT (>1.8) signal quality khac nhau hoan toan
- [ ] P1-3: signals.csv them SPREAD_PIPS — absolute pips (khong chi ratio)
            Scalping M1/M5: spread 0.5 pip vs 3 pip anh huong P&L truc tiep
- [ ] P1-4: signals.csv them D1_TREND — huong D1 tai thoi diem signal (1/0/-1)
            Intraday bias: BUY khi D1 BULL vs BEAR khac win rate 20-30%
- [ ] P1-5: signals.csv them SLTP_METHOD (0=ATR,1=Fib,2=Hybrid) + AUTO_CONFIG (0/1)
            Can thiet sau khi them auto-config: so sanh method effectiveness per TF
- [ ] P1-6: outcomes.csv them TP2_HIT, TP3_HIT (0/1)
            Phan tich partial profit: nen dung 1:2 hay 1:3 cho tung case/TF

P2 — Important:
- [ ] P2-1: scoring.csv them MTF_H4_TREND, MTF_H1_TREND (rieng le, khong chi aggregate)
            Xac dinh: H4+H1 aligned > H4 only > mixed — quan trong nhat cho H1 scalping
- [ ] P2-2: signals.csv them TIME_IN_SESSION_MIN — phut ke tu khi session mo
            Phan tich: signal dau session (0-30 phut) vs cuoi session khac nhau

P3 — Nice to have:
- [ ] P3-1: outcomes.csv them P&L_PIPS — loi/lo tuyet doi bang pips
            Visualization va quick stats khong can reconstruct tu prices

**Header moi sau khi bo sung:**

signals.csv (28 cols):
  SIGNAL_ID,SYMBOL,TF,SIGNAL_TIME,LOG_TIME,DIR,CASE_NUM,CASE_NAME,
  ENTRY,SL,TP1,TP2,TP3,ATR,SL_DIST_ATR,TP1_DIST_ATR,RR_RATIO,
  SESSION,ANGLE_Z,HOUR,DOW,
  RSI_AT_SIGNAL,ATR_RATIO,SPREAD_PIPS,D1_TREND,SLTP_METHOD,AUTO_CONFIG,
  TIME_IN_SESSION_MIN

scoring.csv (17 cols):
  SIGNAL_ID,SCORE,REC_LEVEL,PROB_TP1,PROB_SL,PROB_N,EV,RR,
  MTF_AGREE_PCT,MTF_TREND,MTF_H4_TREND,MTF_H1_TREND,
  ANGLE_Z,HOUR,DOW,SPREAD_RATIO,WF_ROBUST

outcomes.csv (13 cols):
  SIGNAL_ID,SYMBOL,SIGNAL_TIME,OUTCOME,OUTCOME_TIME,EXIT_PRICE,
  BARS_HELD,REASON,MFE,MAE,TP2_HIT,TP3_HIT,PL_PIPS

---

### CONG VIEC CON LAI
- [x] V11.30 Normalize.mqh 4 bugs (done 2026-06-12)
- [x] V11.30 SLTP.mqh 4 bugs implement (done 2026-06-12)
- [x] V11.30 TFConfig.mqh auto scalping profile per TF (done 2026-06-12)
- [x] V11.31 P1-1: signals.csv + RSI_AT_SIGNAL (done 2026-06-12)
- [x] V11.31 P1-2: signals.csv + ATR_RATIO (done 2026-06-12)
- [x] V11.31 P1-3: signals.csv + SPREAD_PIPS (done 2026-06-12)
- [x] V11.31 P1-4: signals.csv + D1_TREND (done 2026-06-12)
- [x] V11.31 P1-5: signals.csv + SLTP_METHOD + AUTO_CONFIG (done 2026-06-12)
- [x] V11.31 P1-6: outcomes.csv + TP2_HIT + TP3_HIT (done 2026-06-12)
- [x] V11.31 P2-1: scoring.csv + MTF_H4_TREND + MTF_H1_TREND (done 2026-06-12)
- [x] V11.31 P2-2: signals.csv + TIME_IN_SESSION_MIN (done 2026-06-12)
- [x] V11.31 P3-1: outcomes.csv + P&L_PIPS (done 2026-06-12)
- [ ] Compile va verify SLTP changes (SL/TP hop ly tren cac TF, no regression)
- [ ] Compile va verify cross-broker Tier 3 consistency (cung TF, 2 broker → cung probability)
- [ ] Commit branch feature/improvement-v11-spec sau khi verify tren chart thuc te