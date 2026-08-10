# Sprint 6 — File 3: `Include/QuantEdge/Data/SignalLogger.mqh`

> **Action:** MODIFY (+100 lines)
> **Status:** DONE

---

## Business Purpose

Persist mỗi virtual trade đã closed ra CSV file, để Python analyzer (File 10) có thể tính performance stats offline. CSV dùng chung `SIGNAL_ID` join key với `signals_*.csv` / `scoring_*.csv` / `outcomes_*.csv` (đã có từ trước).

---

## Data Flow

```
OnInit() [File 6]
  └─ InitVirtualCSV()      → mở persistent file handle

Tier 2 bar close [File 4]
  └─ AppendVirtualTradeLog(pos, atr)  → ghi 1 CSV row
  └─ FlushPendingCSVLogs()            → flush mỗi 10 rows

OnDeinit() [File 6]
  └─ CloseVirtualCSV()     → flush + đóng handle
```

---

## Input

| Parameter | Type | Source |
|-----------|------|--------|
| `pos` | `const VirtualPosition &` | Từ `g_virtualPositions[i]` khi `needsLog == true` |
| `atr` | `double` | Lookup ngược từ `g_signals[]` matching `signalTime + caseNumber` |

---

## Output

File: `MQL4|5/Files/{InpLogFolder}/virtual_trades_{SYMBOL}_{TF}_{YEAR}.csv`

### 24 Columns

```
SIGNAL_ID, SYMBOL, TF, SIGNAL_TIME, CASE_NUM, CASE_NAME, DIR, SESSION,
ENTRY_TYPE, ENTRY_PRICE, ACTIVATION_TIME,
SL, TP1, TP2, TP3, ATR,
MAX_TP_REACHED, FINAL_OUTCOME, OUTCOME_TIME,
EXIT_PRICE, BARS_HELD, MFE_PIPS, MAE_PIPS, RR_RATIO
```

- `SIGNAL_ID` = `SL_BuildSignalID(caseNum, isBuy, signalTime)` — JOIN key với existing CSVs
- `FINAL_OUTCOME` = "TP" | "SL" | "REVERSAL" | "PENDING"
- `BARS_HELD` = `(outcomeTime - activationTime) / PeriodSeconds(PERIOD_CURRENT)` — dùng `activationTime` (không phải `signalTime`) cho pullback entries
- `MFE_PIPS` / `MAE_PIPS` = `PriceToPips(pos.mfe/mae)`
- `RR_RATIO` = TP1 distance / SL distance (planned TP1 RR, không phải realized)

---

## Functions

| Function | Lines | Mô tả |
|----------|-------|--------|
| `VH_GetPath()` | 705-712 | Build CSV path: `{folder}/virtual_trades_{Symbol}_{TF}_{Year}.csv` |
| `PriceToPips(double priceUnits)` | 714-719 | Convert price units → pips via `SL_PipSize()` |
| `InitVirtualCSV()` | 721-736 | Create folder, open file (append mode), write header if new |
| `AppendVirtualTradeLog(const VirtualPosition &pos, double atr)` | 738-784 | Format 1 CSV row, write to handle |
| `FlushPendingCSVLogs()` | 786-792 | `FileFlush()` mỗi 10 pending rows |
| `CloseVirtualCSV()` | 794-801 | Final flush + `FileClose()` |

---

## Design Decisions

1. **Persistent file handle** (`s_vhFileHandle`): khác signal/outcome logger (open+close per flush). Virtual trades close thường xuyên hơn (mỗi TP3/SL/Reversal), persistent handle + batch flush 10 rows tránh I/O thrashing.
2. **`VH_FLUSH_EVERY 10`**: flush sau 10 rows tích lũy, balance giữa data safety và I/O overhead.
3. **CSV KHÔNG bị suppress trong backtest** (`IsBacktestMode()`): ngược với main signal logger. Virtual trades LÀ backtest data — suppress trong backtest mode = vô nghĩa.
4. **Reuse existing helpers**: `SL_OpenAppend()`, `SL_BuildSignalID()`, `SL_FmtDT()`, `SL_GetCaseName()`, `SL_GetTFName()`, `SL_PipSize()` — zero code duplication.
5. **`atr` parameter**: VirtualPosition struct không chứa ATR (tránh duplicate data). Caller lookup ATR từ `g_signals[]` tại Tier 2 time.
