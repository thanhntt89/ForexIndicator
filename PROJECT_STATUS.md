# RSI Advanced V12.0 - Project Status & Context Summary

Tài liệu này đóng vai trò là **Source of Truth (Nguồn thông tin gốc)** của dự án. AI ở các phiên tiếp theo **BẮT BUỘC** đọc file này để biết trạng thái hiện tại của code, các phát hiện định lượng mới nhất, và các công việc cần tiếp tục triển khai.

---

## 1. Trạng Thái Code & Kiến Trúc Hiện Tại
Dự án đã được cấu trúc lại hoàn chỉnh để hỗ trợ song song cả MT4 và MT5 với tính năng ghi log định lượng:

- **Build Pipeline**: File `make.ps1` thực hiện build song song `RSI_Advanced.mq4` (MT4) và `RSI_Advanced.mq5` (MT5).
- **MT5 Compatibility**: Sử dụng `Include/RSI_Advanced/MQLCompat.mqh` để chạy chung mã nguồn logic với MT4.
- **Logging System**: Ghi log định lượng chi tiết với cơ chế RAM Queue + Bulk Flush để chống đơ chart. **Bật mặc định** (`InpEnableSignalLog = true`) từ V11.31 để outcomes thực persist qua TF switch/restart.

---

## 2. Kết Quả Phân Tích Định Lượng (XAUUSD - M1 vs M5)
- **M1 vs M5**: Khung M1 hiệu quả hơn M5 về kỳ vọng toán học (MFE trung bình lớn hơn MAE trung bình).
- **Phân loại Case**: 
  - *Case 6 (TrendCont)*: Hoạt động rất tốt trên M1, đánh nhanh thắng nhanh. Tránh đánh vào phiên Asian và LateNY.
  - *Case 7 (SidewayBreak)*: Hoạt động cực tốt trên M5, nhưng rất tệ trên M1 do sideway ảo.
- **Phiên Giao Dịch**: Phiên Overlap Âu-Mỹ là phiên ngon nhất cho M1. Phiên London là phiên ngon nhất cho M5.

---

## 3. Changelog Các Phiên Gần Nhất

### V12.0 — XGBoost Probability Integration (2026-07-07)

**Boi canh**: User muon tich hop XGBoost de tinh xac suat tin hieu, chay song song voi pipeline
Bayesian hien tai. XGBoost bo sung kha nang hoc **non-linear feature interactions** ma Bayesian
khong capture duoc (vi du: Case 1 + London + high ATR + RSI gan 30 co ket qua khac han tung
feature rieng le). Indicator chi **build 1 lan**, XGBoost duoc export thanh if/else code MQL
thuan — khong can Python runtime.

**3 mode hoat dong (input dropdown, mac dinh CALIBRATION = khong doi hanh vi):**

| Mode | Enum value | Cach hoat dong |
|------|-----------|----------------|
| **PROB_CALIBRATION** (mac dinh) | 0 | Bayesian pipeline hien tai, XGBoost code nam yen |
| **PROB_XGBOOST** | 1 | Chi dung XGBoost, bo qua Step 1-5 Bayesian |
| **PROB_ENSEMBLE** | 2 | Bayesian + XGBoost → Brier-weighted average |

**Auto-fallback**: Neu chon XGBOOST/ENSEMBLE nhung XGB chua san sang (samples < 20 hoac Brier > 0.25
hoac chua train model), tu dong fallback ve CALIBRATION va hien warning tren panel.

**Kiem truc ky thuat:**
```
[Offline]                          [Runtime MQL]
CSV data (signals+scoring+outcomes)
    |                              XGBModel.mqh (50 if/else trees)
    v                                   |
rsi_xgboost_train.py               CalculateProbability()
(walk-forward CV,                  Step 1-5: Bayesian (existing)
 XGBoost train,                    Step 5.1: XGB inject (NEW)
 export to MQL)                      CALIBRATION → skip
                                     XGBOOST → XGBPredict() only
                                     ENSEMBLE → Brier-weighted avg
                                   Step 5.5-6: calibration/normalize
```

**Combination (mode ENSEMBLE) — Brier-weighted Model Averaging:**
```
w_bayes = 1 / max(brier_bayes, 0.10)^2
w_xgb   = 1 / max(brier_xgb, 0.10)^2
probCombined = (probBayes * w_bayes + probXGB * w_xgb) / (w_bayes + w_xgb)
```
Model nao du bao chinh xac hon (Brier thap hon) tu dong co weight cao hon.

**Anti-Overfit Safeguards:**
1. Feature exclusion: PROB_TP1/EV/RR tu scoring KHONG dung lam XGB feature (chong copy Bayesian)
2. Walk-forward only: expanding window + purge gap, KHONG random split
3. Brier gate tu dong: XGB weight=0 khi samples<20 hoac Brier>0.25
4. Conservative hyperparameters: max_depth=4, n_estimators=50, min_child_weight=10
5. Validation checks truoc export: OOS Brier<0.25, AUC>0.55, no single feature>50% importance

**17 XGBoost features (loai tru Bayesian output de chong double-count):**
- Tu signals: RSI_AT_SIGNAL, ANGLE_Z, ATR_RATIO, SL_DIST_ATR, TP1_DIST_ATR, RR_RATIO,
  SPREAD_PIPS, TIME_IN_SESSION_MIN, CASE_NUM, DIR, SESSION, HOUR, DOW, D1_TREND
- Tu scoring: MTF_AGREE_PCT, SPREAD_RATIO, WF_ROBUST, MTF_H4_TREND, MTF_H1_TREND
- **LOAI TRU**: PROB_TP1, PROB_SL, EV, RR, RAW_T1/T2, COUNT_T3, REAL_PCT

**So luong tin hieu toi thieu de train:**

| Muc | Signals resolved | Mo ta |
|-----|-----------------|-------|
| Toi thieu tuyet doi | 150 | Walk-forward 2-3 fold, ket qua chua on dinh |
| Khuyen nghi | 300-500 | Walk-forward 5 fold, moi fold ~60 OOS signals |
| Ly tuong | 1000+ | Co the tang max_depth=5, feature interaction ro rang |

**Files moi tao (3):**
- `Include/RSI_Advanced/XGBModel.mqh` — placeholder (returns 50% flat), se bi thay boi Python script
- `Include/RSI_Advanced/XGBIntegration.mqh` — XGBGetPrediction, CombineXGBWithBayesian, XGBIsReady,
  UpdateXGBBrierMetrics, XGBModeLabel
- `tools/rsi_xgboost_train.py` — Python training pipeline (chi chay offline, KHONG can khi indicator chay)

**Files sua (8):**
- Config.mqh: ENUM_PROB_MODE enum + InpProbMode input (group Probability)
- Structs.mqh: xgbPredictedProb (SignalData), xgbProbTP1/xgbWeight/bayesianWeight/xgbActive (ProbabilityData)
- Globals.mqh: g_xgbProbTP1, g_xgbBrierScore, g_xgbBrierSamples + StoreSignal init
- ProbabilityEngine.mqh: Step 5.1 block (~40 dong) — mode switch + XGBPredict + Brier-weighted combine
- PanelDrawing.mqh: XGB mode/probability display (green/yellow/orange/gray)
- SignalLogger.mqh: cot XGB_PROB_TP1 trong scoring CSV
- RSI_Advanced.mq4: #include + xgbPredictedProb storage + UpdateXGBBrierMetrics + LogScoringSnapshot arg
- RSI_Advanced.mq5: tuong tu mq4

**Panel display theo mode:**
```
CALIBRATION:  XGB:OFF                         (dim gray)
XGBOOST:      XGB:58.3% Brier:0.183           (lime, active)
ENSEMBLE:     XGB:58.3% [w=0.38] Brier:0.183  (lime, weights shown)
Fallback:     XGB:-- [12/20]                   (yellow, accumulating)
Poor Brier:   XGB:45.1% Brier:0.281!          (orange, warning)
No model:     XGB:no model                    (gray)
```

**LUU Y SAU COMPILE**: Them field vao SignalData → **xoa `RSI_SESS_*.bin`** de tranh doc sai binary cu.

---

### HUONG DAN SU DUNG XGBOOST TRAINING PIPELINE

**Buoc 1: Tich luy data (BAT BUOC)**
- Chay indicator voi `InpProbMode = PROB_CALIBRATION` (mac dinh)
- Bat `InpEnableSignalLog = true` (da default-on tu V11.31)
- Thu thap toi thieu 150 resolved signals (khuyen nghi 300+)
- Data tu dong luu vao: `MQL4/Files/RSI_Advanced_Logs/` (hoac MQL5)
  ```
  signals_XAUUSD_H1_2026.csv
  scoring_XAUUSD_H1_2026.csv
  outcomes_XAUUSD_H1_2026.csv
  ```

**Buoc 2: Cai dat Python dependencies (1 lan)**
```bash
pip install xgboost pandas numpy scikit-learn matplotlib
```

**Buoc 3: Chay training**
```bash
cd RSI_Advanced/tools
python rsi_xgboost_train.py --data-dir "C:/path/to/MQL4/Files/RSI_Advanced_Logs"
```

Output:
- Walk-forward validation report (5 folds, Brier + AUC per fold)
- Feature importance ranking
- Calibration plot: `xgb_calibration.png`
- Neu PASS validation → tu dong gen `Include/RSI_Advanced/XGBModel.mqh`
- Neu FAIL → khong export (dung `--force` de override, khong khuyen nghi)

**Buoc 4: Recompile + doi mode**
1. Recompile indicator (MT4 + MT5) — XGBModel.mqh gio chua real model
2. Xoa `RSI_SESS_*.bin` (struct da doi tu V12.0)
3. Doi input: `InpProbMode = PROB_ENSEMBLE` (hoac PROB_XGBOOST)
4. Panel se hien XGB probability + weights

**Buoc 5: Monitor + retrain**
- Theo doi Brier score cua XGB tren panel (xanh < 0.20, vang 0.20-0.25, cam > 0.25)
- Khi co them data moi (100+ signals moi), retrain:
  ```bash
  python rsi_xgboost_train.py --data-dir "..." --output "Include/RSI_Advanced/XGBModel.mqh"
  ```
- Recompile de cap nhat model

**Options cua training script:**

| Flag | Mo ta | Mac dinh |
|------|-------|----------|
| `--data-dir` | Thu muc chua 3 file CSV | *bat buoc* |
| `--output` | Duong dan output XGBModel.mqh | `Include/RSI_Advanced/XGBModel.mqh` |
| `--force` | Export du validation fail | `false` |

**Validation gates (phai pass de export):**
- OOS Brier < 0.25 (model co skill)
- OOS AUC > 0.55 (phan biet duoc win/loss)
- Calibration curve approximately monotonic
- No single feature > 50% importance (chong overfit 1 feature)

**Khi nao KHONG nen dung XGBoost:**
- Duoi 150 signals → chua du data, model se overfit
- OOS Brier > 0.25 → model khong co skill, giu CALIBRATION
- 1 feature dominate >50% → model hoc shortcut, khong generalizable

---

### V11.37 — TF-Switch Performance Fix (load lâu → 16ms) (2026-07-06)

**Bối cảnh**: User báo "chuyển time frame load lâu" (cả MT4 lẫn MT5, mọi TF). Cắm `[PERF]`
instrument (GetTickCount quanh từng phase OnCalculate, Print chỉ khi fullRecalc) để khoanh vùng
bằng số thật thay vì đoán. Kết quả: **3000-4766ms → 16ms** (user verify trên MT4 XAUUSDc).

**3 hotspot trong fullRecalc (mỗi lần đổi TF / attach đều chạy fullRecalc):**

1. **MTF_InitRamBuffers dựng 250 bar × 4-6 slot HTF** — nhưng `GetMTFTrend` CHỈ đọc bar `[0]` và
   `[2]`. Fix: `MTF_INIT_BUILD_BARS = 8` (Globals.mqh); buffer vẫn tự lớn dần qua `MTF_UpdateRamBuffer`.
   (Bản bulk CopyBuffer/CopyTime thử trước đã **REVERT** — build-8 đủ nhanh, CopyTime HTF có nguy cơ
   block trên MT4.)

2. **`MeasureOptimalTPRatios` (SLTP.mqh) deep history scan KHÔNG cache, gọi 1 lần/tín hiệu** trong
   detection loop. `barIndex` param không dùng; Phase 1 skip lúc fullRecalc; Phase 2 thuần lịch sử →
   kết quả giống nhau mọi tín hiệu cùng `(isBuy, caseNum)` trong 1 pass. Fix: **memo-cache** bảng 20
   slot (index `caseNum*2+dir`, invalidate `(Period, totalBars)`; KHÔNG key g_signalCount — tăng giữa
   loop → thrash). `return`→`break`+store 1 chỗ.

3. **[DOMINANT ~2953-4766ms] `LoggerInit(true)` xóa 3 file CSV (`FileDelete×3`) mỗi fullRecalc.** Vừa
   chậm ~3s vừa là **bug data-loss** (log quant bị xóa mỗi lần đổi TF). Fix: `LoggerInit(false)` trong
   fullRecalc + **forward-only logging** — `LogSignalEntry`/`LogOutcomePending` chỉ ghi khi nến vừa đóng
   (`i >= rates_total-2`); `TrackSignalForSession` thêm param `willLog` → tín hiệu lịch sử đặt
   `loggedToFile=true` để `CheckAndLogNewlyResolved` không ghi lại (không dup dù không wipe). → Log giờ
   **bền qua TF switch**.

**Chống trùng (do bỏ wipe — bảo đảm KHÔNG double-count kết quả):**
- `LoadSessionStatsFromOutcomesCSV` (đường DUY NHẤT nạp g_outcomes thiếu dedup; chỉ chạy fallback khi
  thiếu `.bin`): thêm pass dedup O(n) theo (signalTime, case, dir) sau `SortOutcomesByTime`, trước
  `UpdateSessionStats`.
- `tools/zone_edge.py`: thêm dedup signals theo SIGNAL_ID (outcomes đã dedup sẵn qua dict last-wins).
- `g_outcomes` (tính live) LUÔN đủ vì re-resolve mỗi phiên qua `CheckPendingOutcomes`; forward-only +
  willLog chỉ ảnh hưởng FILE CSV, không ảnh hưởng probability/session stats.

**Helper mới**: `TFPeriod(int)` (MathUtils.mqh — MT5 `MinutesToTimeframe` / MT4 identity) cho `CopyRates`
bulk H1 trong `BuildNormalizedH4Candles` (MT5 GMT≠0 — giữ). Tránh bẫy `TF_*` vs `PERIOD_*`.

**Files changed**: Globals.mqh, MathUtils.mqh, MTFEngine.mqh, SLTP.mqh, CandleNormalize.mqh,
SessionStatistics.mqh, RSI_Advanced.mq4, RSI_Advanced.mq5, tools/zone_edge.py.
**KHÔNG struct change → KHÔNG cần xóa `.bin`.** `[PERF-PROBE]` đã gỡ sạch sau verify.
**Còn lại (optional)**: outcomes CSV có thể phình dần theo phiên (đã dedup lúc đọc nên KHÔNG sai kết quả);
Tier-3 `ScanHistoricalATRBased` cold scan (display=16ms nên OK, chưa đụng).

### V11.36 — AngIC Diagnostic + OS-Cross Monitor + Case 9 (OB/OS Raw Crossover) (2026-07-01)

**Boi canh**: User dieu tra vi sao mot so cu "green cat red" khong ra mui ten (M30/H1/H4),
va vi sao cung thi truong nhung H4 co tin hieu ma H1/M30 khong. Ket luan: **khong phai bug** —
(1) trong trend khong co cross moi; (2) ngưỡng goc thich nghi tang trong trend loc cross non;
(3) closed-bar guard hoan mui ten o nen dang chay; (4) moi TF tinh RSI rieng nen le nhau (ban chat
MTF). Case bat dao chieu SOM = Case 1 (OB/OS Bounce, chi ban khi RSI green < 32). Sau do user de xuat
rule "green cat red duoi 32" va yeu cau dua vao he thong de tu theo doi.

**3 thay doi (Include dung chung mq4+mq5; 2 file root sync):**

1. **AngIC panel diagnostic** (PanelDrawing.mqh, sau dong Kelly): hien `infoCoeff` + `icSamples`
   theo dung gate ProbabilityEngine dung cho angle edge (`icSamples>=20 && infoCoeff>=0.05`). Bands
   theo WalkForward.mqh header: >0.10 strong / 0.05-0.10 weak / <0.05 noise / <0 INVERSE. Mau: lime ON,
   vang weak-ON, cam INVERSE, dim n/a hoac not-applied. Cho user thay **thuc nghiem** goc co edge tren
   symbol/TF cua minh hay khong (2-pass calcY + draw da can chinh; cleanup prefix-scan an toan).

2. **OS-Cross monitor marker** (ArrowManager.mqh `DrawOSCrossMonitor` + `PREFIX_OSMON` + `InpMonitorOSCross`):
   cham nho aqua/magenta o cho green cat red trong vung OB/OS. Ban dau la buoc quan sat, **KHONG** vao
   pipeline. Sau khi Case 9 thanh tin hieu that -> **default TAT** (`InpMonitorOSCross=false`), giu lai de
   overlay so sanh RAW pattern vs Case 9 arrows. Cleanup PREFIX_OSMON o deinit + fullRecalc ca 2 root.

3. **Case 9 = OB/OS Raw Crossover** (promote thanh tin hieu that, day du pipeline):
   - Dinh nghia (FINAL - plain cross): `greenCrossUp && ConfirmedCrossUp(i)` (BUY) / `greenCrossDown &&
     ConfirmedCrossDown(i)` (SELL) — tuc **Case 8 BO angle gate**. Case 8 (cross doc) uu tien cao hon nen
     Case 9 hung cac cross YEU-goc Case 8 bo → tach rieng do xac suat Tier-1 CUA CHINH NO. KHONG zone,
     KHONG angle, KHONG lookback (da bo input InpCase9OSLevel/InpCase9Lookback). Grouped reversal-family (SL tight).
     Uu tien **thap nhat**, `InpEnableCase9=true`. **Da doi dinh nghia 3 lan theo user**: strict green<32 luc cross
     → bounce-from-oversold (B, lookback) → **plain cross (final)** (user: "de rieng 1 case khi xanh cat len do,
     tinh xac suat rieng"). **AngIC:-0.13 INVERSE tren XAUUSD H1 (n=38) → cross KHONG co edge o day; Case 9 phan
     lon se WAIT/No-Edge — dung de DO plain-cross co edge rieng khong, arrow != lenh.**
   - **Solution A (zone measurement, thay vi tach case theo vung)**: user muon 3 case theo vung (buy<32 /
     sell>68 / mid) — TU CHOI vi fragment data + trung Case 1/5 (priority). Thay vao do: `RSI_AT_SIGNAL` da
     log tren MOI tin hieu → tool **`tools/zone_edge.py`** join signals+outcomes qua SIGNAL_ID, xuat
     Win%/AvgPL(pip)/MFE-MAE per (case × vung OS/MID/OB × huong) + rollup pure-zone. Do duoc zone-edge NGAY
     tu data cu, khong can them case. Chay: `python tools/zone_edge.py --dir <Files/RSI_Advanced_Logs> --symbol XAUUSD --tf H1`.
   - **Nhom REVERSAL** (khong phai trend): giong Case 1 (fires o RSI extreme). SL tight (nhom 1/5),
     RSI band reversal, session-quality nhom 1/5/9. (Workflow map ban dau de xuat trend group — da
     **override** sang reversal vi ban chat OB/OS.)
   - Bat tren: M15/M30/H1/H4+ (dung noi Case 8 bat). Tat tren M1/M5 (giong Case 1/8 vang o do).

**CRITICAL — dual-indexing scheme khi them case (GHI NHO de khong OOB lan sau):**
- **Scheme A** (index = caseNumber truc tiep, 0..N): `g_cfgCaseEnabled[]`, `g_brierCaseScore[]`,
  `g_brierCaseSamples[]` (Globals), `caseSqErr[]`/`caseMatched[]` (CalibrationEngine). Them case ->
  **literal [9]->[10]** + loop `c<9->c<10` + bound `cbn<=8->cbn<=9` / `cn<=8->cn<=9`.
- **Scheme B** (index = caseNumber-1, qua macro): `#define CASE_COUNT` (Structs.mqh:4). Dieu khien
  `winsPerCase[SESSION_BLOCKS][CASE_COUNT]` (Structs) + SessionStatistics loops/clamps + ProbEngine:1419.
  Them case -> **CASE_COUNT 8->9** (tu dong cascade). **KHONG** dung literal cho nhom nay.
- Bo sot 1 cho = OOB crash hoac case im lang khong bat. Dung workflow 3-agent map het footprint truoc khi sua.

**Files changed (11)**: Structs.mqh (CASE_COUNT), Globals.mqh (3 arrays [10]), Config.mqh (InpEnableCase9 +
InpMonitorOSCross), CalibrationEngine.mqh (arrays+loops+bound), ProbabilityEngine.mqh (Brier bound cbn<=9),
SignalCases.mqh (name/detail/CheckCase9), TFConfig.mqh (getter+8 loops c<10+bound>9+enable[9]), SLTP.mqh
(reversal group: SL mult x5, RSI filter, isReversal/isRev/sigRev), Normalize.mqh + SessionFilter.mqh
(session-quality reversal group), SignalLogger.mqh (OBOSCross), RSI_Advanced.mq4/mq5 (Case 9 detection block).

**Verify**: grep 0 straggler ([9] decl / c<9 / <=8 bounds); Case 9 wired 11 file; mq4:408-411 == mq5:460-463.
**KHONG build** — user tu compile. **Caveat**: CASE_COUNT doi -> struct SessionStats doi size -> **xoa
RSI_SESS_*.bin** (tu rebuild) sau khi cai ban nay de tranh doc sai binary cu.
**Trang thai**: Case 9 la EXPERIMENT (user tu theo doi win-rate/EV qua AngIC + log). Neu khong an -> tat
`InpEnableCase9=false`. Neu tot -> giu; neu muon giam nhieu -> them lai gate angle/MTF.

### V11.35 — Dead Code Cleanup + Xác Nhận Priority Table Đã Hoàn Thành (2026-07-01)

**Bối cảnh**: User đưa bảng priority "nâng điểm 72 → 82-85" (spread bias + missing context fields,
IC gate cho angle, **S5 continuous similarity weighting + S6 n_eff**, Rolling WF, Permutation test,
MQL4 performance throttle) và hỏi còn mục nào cần xử lý ngay. Verify lại toàn bộ code hiện tại →
**TẤT CẢ các mục đã được implement**. Bảng trong ảnh là **roadmap CŨ** (từ trước khi S1-S9 build ở
thời V11.31, verified 2026-06-10). Con số "72 → 82-85" không còn đúng với code hiện tại.

**Trạng thái verified toàn bộ priority table**:

| Mục | Trạng thái | Vị trí |
|-----|-----------|--------|
| P0 Spread bias + context fields | Done | `spreadAtSignal` cả 3 tier + SELL bias fix (S2); sessionBlock/rsiAtSignal/angleStrength/atrValue lưu (S3) + dùng weight (S5/S7/S8/S9) |
| P0 IC gate cho angle | Done | ProbabilityEngine.mqh:1334-1341 (icSamples>=20 && infoCoeff>=0.05) |
| P1 S5 similarity + S6 n_eff | Done | ProbabilityEngine.mqh:1002-1089 (session+angle+recency+RSI+ATR kernel); nEff feed Wilson @1385 |
| P1 Rolling WF | Done | WalkForward.mqh:217-286 (K=5 windows, median overfit ratio) |
| P2 Permutation test | Done | WalkForward.mqh:295-338 (100 perms, LCG RNG, p-value) |
| P2 MQL4 perf throttle | Done | RSI_Advanced.mq4:709 / mq5:774 (throttle 200ms + new-bar/price/signal gate) |

**Phát hiện + fix (dead code)**: Trong lúc verify phát hiện hàm `ScanStoredSignals` (bản integer-count
Tier-1, ProbabilityEngine.mqh) **KHÔNG được gọi ở bất kỳ đâu**. Hàm active thực sự là
`ScanStoredSignalsBoth` (ProbabilityEngine.mqh:914 — weighted S5-S9 đầy đủ). Dead code này đã **2 lần**
khiến phân tích hiểu nhầm "Tier 1 dùng integer count" (dẫn tới đề xuất re-implement S5/S6 vốn đã có).
Xóa để tránh nhầm lẫn về sau.

**Changes (4 edit, Include dùng chung mq4+mq5 — không cần sync riêng 2 platform)**:
1. **ProbabilityEngine.mqh** — Xóa banner + toàn bộ hàm `ScanStoredSignals` (55 dòng). Bonus: xóa 1 ký
   tự non-ASCII `->` trong comment (đúng quy tắc comment ASCII).
2. **Sửa 3 comment tham chiếu tên hàm đã xóa** (chỉ đổi chữ, không đổi logic):
   - ProbabilityEngine.mqh (~911, trong `ScanStoredSignalsBoth`): "Same cap as ScanStoredSignals" →
     "Same forward-window cap as the Tier1+2 scan (symmetric window)"
   - Structs.mqh:34 + Normalize.mqh:556: đổi `ScanStoredSignals` → `ScanStoredSignalsBoth`

**Verify**: grep `ScanStoredSignals\b` → 0 kết quả; `ScanStoredSignalsBoth` → 8 occurrences còn nguyên.
Không call site → không thể gây lỗi biên dịch. Panel + probability KHÔNG đổi hành vi (hàm đã chết,
không nằm trong pipeline).

**Đòn bẩy nâng điểm còn lại**: chủ yếu là **tích lũy data** (anti-overconfidence shrink giữ prob ~50%
tới khi đủ outcomes) — KHÔNG phải code. Các mục quant "Còn lại" nhỏ (không nằm trong bảng): Case 8
empirical RSI band từ percentile khi n>=50 (Option C); Case 8 min |Green-Red| separation cross-broker.

**Files changed**: ProbabilityEngine.mqh, Structs.mqh, Normalize.mqh. **KHÔNG build** — user tự compile.

### V11.34 — Stale-Display Fallback Lock Fix (2026-06-30)

**Bối cảnh**: User báo lại "tín hiệu gần nhất SELL mà entry zone hiển thị BUY" (XAUUSD M5, panel
BUY Case 1, Age 50m, P/L +118 pip — đã chạy quá TP3). Workflow 9-agent (5 hypothesis trace +
synthesis + 3 adversarial verify) kết luận đây là **regression của fallback V11.33**, KHÔNG phải
stale-arrow / repaint / sticky-band (H2/H3/H5 đều REFUTED).

**Root cause (CONFIRMED)**: Fallback `[STALE-FIX]` V11.33 và click tay **dùng CHUNG 1 cờ**
`g_userSelectedSignal`. Cờ này chỉ được nhả khi `g_signalCount` **tăng nghiêm ngặt** (mq5:655 cũ),
mà prune+re-detect mỗi tick giữ count không đổi → một khi panel "pin" sang BUY cũ (do fallback khi
SELL mới nhất bị invalidate lúc giá vọt lên, HOẶC do click tay) thì **kẹt vĩnh viễn** ở BUY tới khi
có tín hiệu mới toanh. PanelDrawing đọc hướng chỉ từ `g_signals[g_activeSignalIndex].isBuySignal`
(verify H5: chỉ 2 nơi ghi cờ = fallback mq5:717 + click ChartEvents:41).
> **Lưu ý chẩn đoán (verifier flag)**: KHÔNG phân biệt được từ screenshot là do fallback hay do
> click tay — cả hai set cùng cờ. Fix xử lý CẢ HAI: pin tay vẫn giữ tới khi có tín hiệu mới hơn.

**Fix (tag `[STALE-FIX2]`, mq4+mq5 đồng bộ, 8 edit):**
1. **Globals.mqh:29** — thêm cờ riêng `g_autoFallbackActive` (auto-releasable, tách khỏi pin tay).
2. **Auto-switch block** (mq5 ~655-684 / mq4 ~600-629) — nhả override khi:
   (a) `g_signalCount` tăng **HOẶC** `newestTime` (signalTime tín hiệu mới nhất) tiến lên — không bị
   prune che; **và** (b) auto-fallback đang bật mà tín hiệu mới nhất hợp lệ trở lại → nhả ngay, không
   chờ count tăng.
3. **Fallback loop** (mq5:717 / mq4:664) — set `g_autoFallbackActive=true` (đánh dấu là auto).
4. **ChartEvents:41/36** — click tay set `g_autoFallbackActive=false` (pin tay KHÔNG bị auto-nhả);
   deselect cũng clear.
5. **fullRecalc reset** (mq5 ~268 / mq4 ~246) — reset `g_userSelectedSignal=false` + `g_autoFallbackActive=false`.

**Giữ nguyên intent V11.33**: vẫn fallback khi tín hiệu active invalidate; recency guard `iBarShift>10`
KHÔNG đổi (không hồi sinh tín hiệu cổ); chỉ bỏ phần "kẹt" ngoài ý muốn → panel quay về tín hiệu mới
nhất (SELL) ngay khi nó hợp lệ trở lại.

**Còn lại / khuyến nghị**:
- Hỏi user: có **tự click mũi tên BUY** trước khi chụp không? Nếu có → là behavior đúng (H4-prongB);
  fix vẫn hợp lý (auto-nhả khi có SELL mới hơn).
- Optional: thêm debug tag panel (g_userSelectedSignal / g_autoFallbackActive / activeIdx vs count-1)
  để screenshot lần sau phân biệt rõ fallback-lock vs pin tay.
- "Entry zone" trên chart thực ra là DIM-MODE SLTP+EN label (DrawSLTPLines dim + EN tag `[n=4/250]`),
  KHÔNG phải PREFIX_ZONE band (bị xóa khi WAIT). Không phải lỗi hướng.
- **KHÔNG build** — user tự compile. mq4+mq5 đã đồng bộ.

### V11.33 — Stale-Display / Cross-Platform Diagnosis (2026-06-30)

**Bối cảnh**: User báo (a) tín hiệu mới nhất nhưng panel hiện vị trí tín hiệu CŨ; (b) cùng H4: MT5 SELL
vs MT4 BUY. Workflow 8-agent (trace + adversarial verify) kết luận:
- **MT5 SELL vs MT4 BUY KHÔNG phải bug normalization.** Normalization GMT+3 căn UTC đúng (không off-by-one).
  Nguyên nhân: (1) **khác broker feed** XAUUSDc(MT5) vs XAUUSD(MT4) → lật crossover biên [bản chất, không fix code được trừ khi cùng symbol];
  (2) **stale-display freeze** — cả 2 panel kẹt ở tín hiệu CŨ khác nhau (MT5 7 nến, MT4 13 nến; MT4 circuit-breaker chặn tín hiệu mới).

**3 fix display (mq4+mq5 đồng bộ, tag `[STALE-FIX]`):**

1. **Tách StoreSignal khỏi risk gate** (mq5 buy:487/sell:534, mq4 buy:433/sell:485):
   - Trước: `if(!CanTakeNewSignal()){ buySignal=0; continue; }` → BỎ lưu tín hiệu → panel đóng băng ở tín hiệu cũ.
   - Sau: `bool _buyBlocked = ...` (bỏ continue) → LUÔN StoreSignal/arrow/track; chỉ chặn `OnNewSignalAccepted` (đếm trade) khi blocked.
   - Lợi: panel phản ánh nến hiện tại; stats empirical thu cả tín hiệu bị block (data tốt hơn).

2. **Title `[BLOCKED]`** (PanelDrawing ~442): khi `!CanTakeNewSignal()` → title thêm `[BLOCKED]` màu cam → tín hiệu không actionable không bị hiểu nhầm là entry tươi.

3. **Recency guard ở invalidation fallback** (mq5 ~708, mq4 ~655): vòng quét ngược thêm `if(iBarShift(signalTime) > 10) continue;` → không "hồi sinh" tín hiệu cổ/expired (vd 99 nến); không có tín hiệu hợp lệ gần → giữ tín hiệu mới nhất (invalidated).

**Lưu ý hành vi**: alert giờ kêu cả khi blocked (panel hiện `[BLOCKED]`). Cap recency = 10 bar (heuristic, tunable).
**Còn lại (optional)**: Case 8 min |Green−Red| separation để giảm lật cross biên giữa 2 platform; unify offset source (signalTimeUTC dùng GuessEUBrokerOffset tách khỏi GetBrokerGMTOffset — lệch 1h cho non-EU GMT+3 mùa đông).

### V11.32 — Case 8 (Basic Crossover) + Probability De-bias (2026-06-30)

**Bối cảnh**: User báo "có setup BUY (green cắt red, trên orange) mà không ra mũi tên". Audit phát hiện
indicator KHÔNG có trigger green-cross-red độc lập (Case 0 cũ định nghĩa nhưng chưa wire; caseNumber=0
đụng sentinel "no-filter"). → Thêm **Case 8 = Basic Crossover** với segmentation riêng (ci=7), rồi
audit 10-agent về tính hợp lệ xác suất → fix 5 vấn đề.

**1. Case 8 — Basic Crossover (Green x Red + strong angle), priority thấp nhất:**
- `CheckCase8_Buy/Sell = ConfirmedCrossUp/Down`; loop gate `greenCrossUp && strongAngleUp` (như Case 2/3/5)
- Bật ở M15/M30/H1/H4 (TFConfig), tắt ở M1/M5 (nhiễu). Toggle `InpEnableCase8`
- `g_cfgCaseEnabled[8]→[9]`, `GetActiveCaseEnabled` bound 0..8, SLTP nhóm trend, Normalize session-quality
- Files: Config, Globals, TFConfig, SignalCases, SLTP, Normalize, RSI_Advanced.mq4/mq5

**2. Probability de-bias cho Case 8 (Option B — bỏ band RSI lệch):**
- Band hardcode `rsi 18-48/52-82` (copy từ caseNum<=0) là **biased estimator** cho crossover RSI-agnostic:
  loại bỏ continuation-cross ở RSI>=50, exclusion lại correlated với angle gate (chọn cross dốc) → bias XUỐNG.
- Fix: tách `caseNum==8` ra nhánh riêng, dải sanity 5-95, để momentum filter (rsi rising/falling) làm gate thật.
  - `Normalize.mqh` Phase-2 (~603/612) + `ProbabilityEngine.mqh` Tier-3 (~614-627, thêm `rsiPrev8` momentum check)

**3. Per-case Brier shrink (anti-overconfidence, thay global):**
- `g_brierCaseScore[9]/g_brierCaseSamples[9]` (Globals), populate trong `UpdateBrierMetrics` (CalibrationEngine)
- Step 5.65: case >=20 outcome → shrink theo Brier riêng; case <20 → global shrink + **uncertainty shrink**
  `*= (0.5+0.5*valRatio)` → case mới (Case 8) KHÔNG hiện high-confidence trước khi có track record (ramp 0.5→1.0)

**4. Confidence/WAIT-gate dùng real-signal nEff (loại Tier-3 inflation):**
- `recN = round(nEffT1+nEffT2)` thay `totalSamples` khi gọi `GetTradeRecommendation` (mq4/mq5/PanelDrawing)
- Trước: Tier-3 deep-scan (50-200 bar không phải tín hiệu) thổi phồng n → dataConfidence/WAIT gate sai

**5. Bug bonus:**
- `edgeCachedOutcome` thêm guard `barIndex==-1` (Normalize) — chống stale cache sau TF switch (như simCachedTP)
- Xóa dead code `pWilson` (CombineTheoreticalHistorical tính rồi không dùng → gây hiểu nhầm có Wilson smoothing)

**Lưu ý hành vi (quan trọng khi test):** Case 8 (và mọi case <20 outcome đã resolve) sẽ hiện xác suất bị
kéo về phía 50% và có thể "WAIT (Low Data)" cho đến khi tích đủ track record. Đây là **anti-overconfidence
CỐ Ý**, tự nới ra khi outcomes tích lũy (cần InpEnableSignalLog=true, đã default-on từ V11.31).

**Còn lại (chưa làm)**: Option C — band RSI cho Case 8 từ percentile 10-90 thực nghiệm của stored signals khi n>=50.

**Audit đầy đủ**: workflow 10-agent (trace pipeline + adversarial verify), mọi finding verified, lưu transcript phiên.

### V11.31 — Brier Feedback + Outcome Persistence (2026-06-30)

**Bối cảnh**: Review quant cho scalping. Xác minh S1-S9 đã implement đầy đủ (review trước nhầm là chưa).
Thêm 1 cải tiến anti-overfit + fix 2 vấn đề persistence của actual outcomes qua TF switch.

**1. Brier Calibration Shrink (Step 5.65) — anti-overfit:**
- Khi `g_brierMetrics.samples >= 20 && brierScore > 0.20` → shrink probability về 50%
- `shrinkFactor = max(0, 1 - (brier - 0.20) / 0.15)` — Brier 0.20→no shrink, 0.35→full shrink to 50%
- **0 free parameter** (0.20 = well-calibrated, 0.35 = worse-than-random 0.25 + margin)
- Vị trí: sau Step 5.6 (Session Quality), trước Step 5.7 (Time Decay)
- Panel: hiển thị `Shrk:67%` khi active
- File: `ProbabilityEngine.mqh`, `PanelDrawing.mqh`
- **Đã loại bỏ** (overfitting risk): regime multiplier calibration từ data (64 cells × 8/cell → SE±18%)

**2. InpEnableSignalLog default true:**
- `Config.mqh:235` false→true
- Lý do: outcomes thực (g_outcomes[]) chỉ persist qua `outcomes_{Sym}_{TF}_{Year}.csv` khi logging bật.
  Tắt log → mỗi TF switch/restart rebuild outcomes bằng re-simulation (mất ground truth cho Brier/SessionWR/S4/OOS).

**3. Reload outcomes CSV trên TF/symbol switch:**
- OnInit load condition thêm `REASON_CHARTCHANGE` (cả .mq4 + .mq5)
- Trước: chỉ recompile/param mới load CSV → đổi TF mất actual outcomes
- Sau: đổi TF → session binary đã xóa lúc deinit → fallback `LoadSessionStatsFromOutcomesCSV()` → khôi phục win/loss thực
- An toàn: dedup ở `TrackSignalForSession()` (SessionStatistics.mqh:224-229) chống double-count khi fullRecalc re-track

**Kiến trúc storage (xác nhận per-Symbol-per-TF, không lẫn data):**
- Signals: `RSI_SIG_{Sym}_{TF}.bin` — save mọi deinit, load fullRecalc (tự động, không cần flag)
- Session stats: `RSI_SESS_{Sym}_{TF}.bin` — chỉ recompile/param
- Outcomes: `outcomes_{Sym}_{TF}_{Year}.csv` — cần InpEnableSignalLog
- MTF panel (H1/H4/D1): tính LIVE qua iRSI cache RAM, không đọc file TF khác

**Quant score (verified, không phải ước lượng từ doc):** ~90/100 — phù hợp live scalping test M5/M15/M30.

**Files modified:** Config.mqh, ProbabilityEngine.mqh, PanelDrawing.mqh, RSI_Advanced.mq4, RSI_Advanced.mq5

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