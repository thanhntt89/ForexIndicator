# Sprint 6: Backtest Engine

> **Goal:** Virtual trading simulation trên chart + performance report + Python offline analysis
> **Duration:** 2 weeks (~40h)
> **Prerequisite:** Sprint 2 (Signal Interface — DONE)
> **Status:** `CODE COMPLETE — awaiting user compile (task 6.10)`

---

## Scope Assessment

### Đã có (reuse):

| Component | File | Reuse |
|---|---|---|
| Single-trade simulator | `ProbabilityEngine.mqh` — `SimulateSignalOutcome()` | Core primitive: SL/TP hit detection, spread-corrected, multi-TP |
| Walk-Forward IS/OOS | `WalkForward.mqh` — full Pardo (2008) impl | Validation layer: overfit ratio, IC, permutation test |
| Rolling performance | `WalkForward.mqh` — last 10/20/50/all WR | Direct reuse for PerfReport |
| Signal/scoring/outcome CSV | `SignalLogger.mqh` — 3-file JOIN schema (28+26+13 cols) | Data feed for Python offline backtest |
| SL/TP optimization | `SLTPOptimizer.mqh` — grid + Newton + golden section | Per-trade SL/TP tuning |
| Brier calibration | `CalibrationEngine.mqh` — per-case metrics | PerfReport calibration metric |
| Virtual Trade History spec | `Documents/VirtualTradeHistory_Spec.md` (v2.0) | Blueprint: struct, tick/bar tier, CSV, chart lines |
| EA Template | `Experts/QuantEdge_EA_Template.mq4/.mq5` | Add `OnTester()` for Strategy Tester optimization |

### Chưa có (Sprint 6 deliverables):

1. **VirtualTradeTracker.mqh** — multi-position virtual trade engine (on-chart)
2. **PerfReport section** — equity curve metrics (PF, Sharpe, MaxDD, Sortino) trên panel
3. **OnTester() hook** — EA returns custom metric cho Strategy Tester optimization
4. **Python offline backtest** — replay từ CSV, produce full performance report

### Nguyên tắc:
- **KHÔNG thay đổi ProbabilityEngine pipeline** — chỉ đọc data đã có (Rule #2 safe)
- **KHÔNG thêm indicator buffer** — EA contract 25 buffers bảo toàn
- Virtual trades = visualization + CSV logging, KHÔNG ảnh hưởng signal detection
- MQ4/MQ5 synced qua shared `.mqh` (MT5 cần mutex — spec v2.0 §9)
- User tự compile (Rule #5)

---

## Tasks

| # | Task | Status | Files | Effort |
|---|---|---|---|---|
| 6.1 | VirtualPosition struct + globals | `DONE` | `Structs.mqh`, `Globals.mqh` | 2h |
| 6.2 | VirtualTradeTracker.mqh — core engine | `DONE` | `VirtualTradeTracker.mqh` (new) | 8h |
| 6.3 | Virtual trade CSV logging | `DONE` | `SignalLogger.mqh` | 3h |
| 6.4 | Chart history lines (OBJ_TREND) | `DONE` | `LineDrawing.mqh` | 2h |
| 6.5 | Main file integration (OnTick + OnBarClose) | `DONE` | `QuantEdge_RSI.mq4/.mq5` | 2h |
| 6.6 | Config inputs (Virtual History) | `DONE` | `Config.mqh` | 1h |
| 6.7 | PerfReport panel section | `DONE` | `PanelDrawing.mqh` | 4h |
| 6.8 | EA OnTester() hook | `DONE` | `Experts/QuantEdge_EA_Template.mq4/.mq5` | 3h |
| 6.9 | Python offline backtest script | `DONE` | `tools/backtest_analyzer.py` (new) | 8h |
| 6.10 | MQ4/MQ5 sync verify + compile — USER | `NOT STARTED` | *(user task)* | 2h |
| 6.11 | Update MASTER_PLAN + this file | `DONE` | `MASTER_PLAN.md`, this file | 0.5h |

---

### 6.1 VirtualPosition Struct + Globals

**Reference:** Spec v2.0 §5.1 + §5.2

**Structs.mqh — thêm struct:**
```mql4
struct VirtualPosition
{
   // Identity (composite key — không dùng index)
   datetime signalTime;
   int      signalCaseNum;
   int      zoneIndex;        // 0=Market, 1-4=Pullback Z2-Z5
   string   entryType;        // "MARKET","PULLBACK_Z2",..."PULLBACK_Z5"

   // Entry
   double   entryPrice;
   bool     isActivated;
   datetime activationTime;
   int      activationBar;

   // Shared SL/TP (absolute price, same for all zones in a signal)
   double   stopLoss;
   double   takeProfit1, takeProfit2, takeProfit3;
   bool     isBuy;
   string   sessionName;

   // Tracking
   int      maxTPReached;     // 0-3, only increases
   datetime tpTime[4];        // [1]=TP1, [2]=TP2, [3]=TP3. [0] unused.
   int      finalOutcome;     // 0=pending, 1=TP_HIT, -1=SL_HIT, -2=REVERSAL
   datetime outcomeTime;
   double   closePrice;

   // MFE/MAE (price units, convert to pips at CSV write)
   double   mfe, mae;

   // Tier 1→2 communication
   bool     needsRedraw, needsLog;

   // Drawing
   bool     historyDrawn;
   string   objectName;
};
```

**Globals.mqh — thêm:**
```mql4
#define MAX_VIRTUAL_POS 200
VirtualPosition g_virtualPositions[MAX_VIRTUAL_POS];
int             g_vpCount     = 0;
int             g_vpWriteHead = 0;    // circular write pointer
int             g_csvVirtualHandle = INVALID_HANDLE;
int             g_csvVirtualPending = 0;
```

---

### 6.2 VirtualTradeTracker.mqh — Core Engine

**New file:** `Include/QuantEdge/Engine/VirtualTradeTracker.mqh`

**Reference:** Spec v2.0 §2 (Tier 1/2 architecture), §4 (multi-position), §7 (processing flow)

**Key functions:**

| Function | Tier | Description |
|---|---|---|
| `VP_AddPosition(VirtualPosition &pos)` | — | Circular buffer insert (spec §5.3) |
| `OnNewSignal(const SignalData &sig)` | Bar | Create Market + valid Pullback zones (spec §7.1). Maps `sig.isBuySignal` → `pos.isBuy`. |
| `UpdateVirtualPositions_Tick(bid, ask)` | Tick | Loop all active → CheckActivation + CheckSLTP + UpdateMFE_MAE |
| `VP_CheckActivation(idx, bid, ask)` | Tick | Pullback zone activation (spec §4.3) |
| `VP_CheckSLTP(idx, bid, ask)` | Tick | TP3→TP2→TP1→SL check, high-water mark (spec §7.2) |
| `VP_HitTP(idx, tpLevel, t, price)` | Tick | Update maxTPReached + tpTime[], set needsRedraw |
| `VP_UpdateMFE_MAE(idx, bid, ask)` | Tick | Track max favorable/adverse excursion |
| `UpdateVirtualPositions_OnBar()` | Bar | Redraw lines + flush CSV for flagged positions |
| `VP_CloseAllBySignal(signalTime, price)` | Bar | Reversal: close all pending positions of old signal (spec §7.4) |

**Performance constraint (spec §2.1):**
- Tier 1 (every tick): numeric only — `O(1)` per position, zero chart object calls
- Tier 2 (bar close): chart operations + CSV flush

**MT5 thread safety (spec §9):**
```mql4
#ifdef __MQL5__
   #define LOCK_VP   // TODO: CMutex if OnTimer used concurrently
   #define UNLOCK_VP
#else
   #define LOCK_VP
   #define UNLOCK_VP
#endif
```
Note: Indicator (not EA) — `OnCalculate()` is single-threaded on MT5 indicators. Mutex chỉ cần nếu kết hợp `OnTimer()` song song. Giữ macro placeholder.

---

### 6.3 Virtual Trade CSV Logging

**Reference:** Spec v2.0 §6

**File:** `SignalLogger.mqh` — thêm 4 functions:

| Function | Description |
|---|---|
| `InitVirtualCSV()` | Open persistent handle, write header (24 columns). Gọi từ `OnInit()`. |
| `CloseVirtualCSV()` | Flush + close handle. Gọi từ `OnDeinit()`. |
| `AppendVirtualTradeLog(pos)` | Format + write 1 row. Gọi từ Tier 2 khi `needsLog=true`. |
| `PriceToPips(priceUnits)` | Convert price units → pips (handles XAUUSD Digits=2). |

**Output file:** `virtual_trades_SYMBOL_TF_YYYY.csv`

**Columns (24):**
```
SIGNAL_ID, SYMBOL, TF, SIGNAL_TIME, CASE_NUM, CASE_NAME, DIR, SESSION,
ENTRY_TYPE, ENTRY_PRICE, ACTIVATION_TIME,
SL, TP1, TP2, TP3, ATR,
MAX_TP_REACHED, FINAL_OUTCOME, OUTCOME_TIME,
EXIT_PRICE, BARS_HELD, MFE_PIPS, MAE_PIPS, RR_RATIO
```

**JOIN key:** `SIGNAL_ID` — shared with `signals_*.csv` và `scoring_*.csv` cho cross-analysis.

**Guard:** `IsBacktestMode()` — vẫn log trong tester (khác `SignalLogger` main CSV). Virtual trades là backtest data.

---

### 6.4 Chart History Lines

**Reference:** Spec v2.0 §3

**File:** `LineDrawing.mqh` — thêm 2 functions:

| Function | Description |
|---|---|
| `CreateHistoryLine(name, t1, p1, t2, p2, clr, width, style)` | Create `OBJ_TREND`, ray=false, selectable=false, hidden=true |
| `UpdateHistoryLineEnd(name, t2, p2)` | Move endpoint (for progressive TP tracking) |

**Visual rules:**
| Outcome | Line Color | Endpoint |
|---|---|---|
| TP hit (maxTPReached > 0) | `InpColorVirtualTP` (clrLime) | Highest TP reached |
| SL hit (no TP) | `InpColorVirtualSL` (clrRed) | SL price |
| Reversal (no TP) | `InpColorVirtualSL` (clrRed) | Close price at reversal |
| TP then SL | `InpColorVirtualTP` (clrLime) | Highest TP (green wins) |

**Object naming:** `"VH_" + signalTime + "_Z" + zoneIndex` — prefix `"VH_"` for bulk cleanup.

**OnDeinit:** History lines are KEPT on chart (analysis data). Optional `VP_DeleteAllHistoryLines()` for manual cleanup.

---

### 6.5 Main File Integration

**Files:** `QuantEdge_RSI.mq4`, `QuantEdge_RSI.mq5`

**Changes:**

```
OnInit():
  + InitVirtualCSV()

OnCalculate() / OnTick():
  + UpdateVirtualPositions_Tick(bid, ask)     // every tick
  + if(isNewBar):
      + UpdateVirtualPositions_OnBar()        // bar close
      + if(newSignalDetected):
          + if(directionReversed):
              + VP_CloseAllBySignal(oldSignalTime, close)
          + OnNewSignal(currentSignal)

OnDeinit():
  + CloseVirtualCSV()
```

**Key integration point:** `OnNewSignal()` gọi SAU `Signal_Detect*()` + `ProbabilityEngine` + `EntryZones` calculation — tất cả data đã populated.

---

### 6.6 Config Inputs

**File:** `Config.mqh`

```mql4
input string   inp_grp_vhist           = "===== Virtual Trade History =====";
input bool     InpEnableVirtualTrades   = true;     // Enable virtual trade tracking
input bool     InpShowHistoryLines      = true;     // Draw history lines on chart
input color    InpColorVirtualTP        = clrLime;  // TP line color
input color    InpColorVirtualSL        = clrRed;   // SL line color
input int      InpHistoryLineWidth      = 1;        // History line width
input int      InpHistoryLineStyle      = 0;        // History line style (0=solid)
```

**Guard:** `InpEnableVirtualTrades = false` → toàn bộ virtual trade engine disabled (zero tick overhead).

---

### 6.7 PerfReport Panel Section

**File:** `PanelDrawing.mqh`

**Mục tiêu:** 4-5 dòng compact hiển thị performance metrics từ virtual trades.

**Format (Full panel — V11 Extras area):**
```
--- Virtual Perf ---
Trades: 47 (32W 15L) | WR: 68.1%
PF: 2.14 | Sharpe: 1.85 | Sortino: 2.31
MaxDD: -3.2% | Avg RR: 1.8 | EV: +0.42R
Market: 72% WR | Pullback: 61% WR
```

**Format (Manual panel):** 2 dòng rút gọn:
```
47 trades 68%WR PF:2.14 DD:-3.2%
Mkt:72% PB:61% EV:+0.42R
```

**Data source:** Tính real-time từ `g_virtualPositions[]`:
| Metric | Formula |
|---|---|
| Win Rate | `wins / total` (finalOutcome > 0 = win) |
| Profit Factor | `grossProfit / grossLoss` (pips-based) |
| Sharpe | `mean(returns) / std(returns) * sqrt(252)` — daily returns proxy |
| Sortino | `mean(returns) / downside_std(returns) * sqrt(252)` |
| Max Drawdown | Peak-to-trough on cumulative pips equity curve |
| Avg R:R | `mean(TP_distance / SL_distance)` for winning trades |
| EV per trade | `WR × avgWin - (1-WR) × avgLoss` in R units |

**Implementation:** Hàm `DrawPerfReport(int &y, bool compact)` + helper `CalculateVirtualPerf()` trả về struct `VirtualPerfMetrics`.

**Config:**
```mql4
input bool InpShowVirtualPerf = true; // Show virtual trade performance
```

---

### 6.8 EA OnTester() Hook

**Files:** `Experts/QuantEdge_EA_Template.mq4`, `.mq5`

**Mục tiêu:** Return custom optimization metric cho MT4/MT5 Strategy Tester.

```mql4
double OnTester()
{
   if(OrdersHistoryTotal() == 0) return -999;

   double totalProfit = 0, totalLoss = 0;
   int wins = 0, losses = 0;

   // Loop qua closed orders → tính WR, PF, Sharpe
   // ...

   // Custom metric: EV * sqrt(trades) — reward edge AND sample size
   double wr = (double)wins / (wins + losses);
   double avgWin = (wins > 0) ? totalProfit / wins : 0;
   double avgLoss = (losses > 0) ? MathAbs(totalLoss) / losses : 1;
   double ev = wr * avgWin - (1 - wr) * avgLoss;
   double metric = ev * MathSqrt(wins + losses);

   return metric;
}
```

**MQ4 vs MQ5:**
- MQ4: `OrdersHistoryTotal()` + `OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)`
- MQ5: `HistorySelect(0, TimeCurrent())` + `HistoryDealsTotal()` + `HistoryDealGetDouble()`

**Strategy Tester custom optimization:** User chọn "Custom max" → tester maximize `OnTester()` return value.

---

### 6.9 Python Offline Backtest Script

**New file:** `tools/backtest_analyzer.py`

**Mục tiêu:** Đọc CSV logs → replay → produce comprehensive performance report.

**Input files (auto-discovered):**
- `signals_SYMBOL_TF_YYYY.csv` — signal data
- `scoring_SYMBOL_TF_YYYY.csv` — model predictions
- `outcomes_SYMBOL_TF_YYYY.csv` — actual outcomes
- `virtual_trades_SYMBOL_TF_YYYY.csv` — virtual trade data (optional, if available)

**Output:** `backtest_report_SYMBOL_TF.html` + `backtest_summary.json`

**Report sections:**

| Section | Content |
|---|---|
| Executive Summary | Total trades, WR, PF, Sharpe, Sortino, MaxDD, EV |
| Equity Curve | Cumulative P&L (pips) over time — matplotlib chart |
| Monthly Returns | Heatmap: month × year → monthly return % |
| Win Rate by Case | Per signal-case breakdown |
| Win Rate by Session | Asian/London/Overlap/LateNY |
| Win Rate by Direction | BUY vs SELL |
| Entry Type Analysis | Market vs Pullback Z2-Z5 performance comparison |
| Drawdown Analysis | Drawdown periods, recovery time, max consecutive losses |
| XGBoost Impact | Compare WR with/without XGB filter (`XGB_PROB_TP1 > 0`) |
| Calibration | Predicted prob vs actual outcome (reliability diagram) |
| Feature Importance | Top features correlated with outcomes (from scoring CSV) |
| Walk-Forward Summary | IS/OOS overfit ratio from existing data |

**Dependencies:** `pandas`, `matplotlib`, `numpy` (same as `quantedge_xgboost_train.py`).

**CLI:**
```bash
python tools/backtest_analyzer.py --symbol XAUUSD --tf H1 --year 2026
python tools/backtest_analyzer.py --data-dir ./logs --all
```

---

### 6.10 MQ4/MQ5 Sync + Compile — USER

Verify checklist:
- [ ] Compile `QuantEdge_RSI.mq4` — 0 errors
- [ ] Compile `QuantEdge_RSI.mq5` — 0 errors
- [ ] Compile `QuantEdge_EA_Template.mq4` — 0 errors (OnTester)
- [ ] Compile `QuantEdge_EA_Template.mq5` — 0 errors (OnTester)
- [ ] Apply indicator to chart → virtual trade lines appear
- [ ] Check `MQL4/Files/virtual_trades_*.csv` output
- [ ] Run Strategy Tester with EA → `OnTester()` returns non-zero
- [ ] Run `python tools/backtest_analyzer.py --help` → no import errors

---

## Architecture Overview

```
┌────────────────────────────────────────────────────┐
│  QuantEdge Indicator (OnCalculate / OnTick)         │
│                                                     │
│  Signal Detection → Probability → EntryZones        │
│       │                                             │
│       ▼                                             │
│  VirtualTradeTracker                                │
│  ┌─────────────┐  ┌──────────────┐                 │
│  │ Tier 1 Tick  │  │ Tier 2 Bar   │                 │
│  │ Activation   │  │ Redraw lines │                 │
│  │ SL/TP check  │→ │ Flush CSV    │                 │
│  │ MFE/MAE      │  │ Log trades   │                 │
│  └─────────────┘  └──────┬───────┘                 │
│                          │                          │
│                          ▼                          │
│  ┌────────────────┐  ┌──────────────┐              │
│  │ PanelDrawing   │  │ SignalLogger  │              │
│  │ PerfReport     │  │ VirtualCSV   │              │
│  │ (real-time)    │  │ (persistent) │              │
│  └────────────────┘  └──────┬───────┘              │
└────────────────────────────────┼─────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  Python backtest_analyzer│
                    │  Read CSVs → Analyze    │
                    │  → HTML report          │
                    └─────────────────────────┘

┌────────────────────────────────┐
│  EA Template (OnTick+OnTester) │
│  9-gate execution + close      │
│  OnTester() → custom metric    │
│  → Strategy Tester optimization │
└────────────────────────────────┘
```

---

## Phasing (2 weeks)

### Week 1: Core Engine (tasks 6.1—6.6)
- Day 1-2: Struct + Globals + VirtualTradeTracker core (6.1, 6.2)
- Day 3: CSV logging + chart lines (6.3, 6.4)
- Day 4: Main file integration + config (6.5, 6.6)
- Day 5: Compile test + first virtual trades on chart

### Week 2: Reporting + Analysis (tasks 6.7—6.10)
- Day 6-7: PerfReport panel section (6.7)
- Day 8: EA OnTester hook (6.8)
- Day 9-10: Python backtest analyzer (6.9)
- Day 10: Full integration test + user compile (6.10)

---

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Tick loop performance (200 positions × 300 ticks/min) | Tier 1/2 split: Tier 1 = 6 comparisons/pos (O(1)), no chart ops. 200×6 = 1200 ops/tick — negligible. |
| Array overflow | Circular buffer (MAX_VIRTUAL_POS=200) with overwrite-oldest. Resolved positions recycled first. |
| CSV file corruption (crash mid-write) | Batch flush every 10 rows + `FileFlush()`. Persistent handle = no open/close overhead. **Note:** Existing `SignalLogger.mqh` uses queue+batch-flush (open-write-close per flush), not persistent handles. Virtual CSV deliberately uses persistent handle because virtual trade writes are more frequent (per-tick state changes vs per-signal). |
| History lines cluttering chart | `InpShowHistoryLines = true` toggle. Object prefix `"VH_"` for bulk cleanup. |
| Strategy Tester mode confusion | `IsBacktestMode()` already defined. Virtual CSV logging ENABLED in tester (intentional — this IS backtest data). Main signal CSV logging stays DISABLED. |
| MQ4/MQ5 divergence | Shared `.mqh` for all logic. Only main files differ (`OnCalculate` vs `OnTick`, `OrdersHistoryTotal` vs `HistoryDealsTotal` in OnTester). |
| Sprint 5/6 concurrent dev conflicts | Sprint 5 and Sprint 6 are independent (different prerequisites). But both modify `Config.mqh` and `PanelDrawing.mqh`. If developed concurrently on same branch, merge conflicts will occur. **Recommend completing Sprint 5 first**, then Sprint 6. Sprint 6 PerfReport layout should go AFTER Sprint 5's Risk Summary section. |

---

## Dependencies on Existing Code (Pre-implementation Checklist)

From Spec v2.0 §13:

| Dependency | Status | Actual Location | Note |
|---|---|---|---|
| Session name from datetime | **Needs wrapper** | `SL_GetSessionName(int block)` in `SignalLogger.mqh` | Takes `int` block (0-3), NOT datetime. Use `SL_GetSessionName(GetSessionBlock(datetime))`. |
| Timeframe string | **Name differs** | `SL_GetTFName()` in `SignalLogger.mqh` | Plan spec said `GetTFString()` — does not exist. Use `SL_GetTFName()`. |
| New bar detection | **Does NOT exist** | — | No `IsNewBar()` in codebase. Existing pattern: compare `g_prevRatesTotal` vs `g_ratesTotal` (Globals.mqh lines 18-19). **Must create `IsNewBar()` helper or use existing pattern directly.** |
| `g_entryZones[]` populated before OnNewSignal() | Confirmed | `SLTP.mqh` → `Globals.mqh` | `EntryZone` struct has `.isValid` and `.price` fields. |
| `SignalData` fields | Confirmed | `Structs.mqh` | `signalTime`, `caseNumber`, `entryPrice`, `stopLoss`, `takeProfit1/2/3` all exist. Field is `isBuySignal` (NOT `isBuy`). |
| `IsBacktestMode()` macro | Confirmed | `Config.mqh` lines 322-329 | MT5: `MQLInfoInteger(MQL_TESTER)`, MT4: `IsTesting()`. |

---

## Files Changed Summary

| File | Action | Lines ± (est.) |
|---|---|---|
| `Include/QuantEdge/Core/Structs.mqh` | Add `VirtualPosition` struct | +35 |
| `Include/QuantEdge/Core/Globals.mqh` | Add virtual trade globals | +8 |
| `Include/QuantEdge/Core/Config.mqh` | Add Virtual History input group + PerfReport toggle | +10 |
| `Include/QuantEdge/Engine/VirtualTradeTracker.mqh` | **NEW** — core engine | +350 |
| `Include/QuantEdge/Data/SignalLogger.mqh` | Add virtual CSV functions | +80 |
| `Include/QuantEdge/Display/LineDrawing.mqh` | Add history line helpers | +25 |
| `Include/QuantEdge/Display/PanelDrawing.mqh` | Add PerfReport section | +100 |
| `QuantEdge_RSI.mq4` | Integrate virtual trade calls | +15 |
| `QuantEdge_RSI.mq5` | Integrate virtual trade calls | +15 |
| `Experts/QuantEdge_EA_Template.mq4` | Add OnTester() | +40 |
| `Experts/QuantEdge_EA_Template.mq5` | Add OnTester() | +45 |
| `tools/backtest_analyzer.py` | **NEW** — Python offline analysis | +500 |
| **Total** | | **+1,223** |

**Zero changes to:** `ProbabilityEngine.mqh`, `WalkForward.mqh`, `Normalize.mqh`, `SignalDetector.mqh`, buffer count (25).
