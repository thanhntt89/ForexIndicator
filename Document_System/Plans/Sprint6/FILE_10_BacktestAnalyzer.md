# Sprint 6 — File 10: `tools/backtest_analyzer.py`

> **Action:** NEW FILE (+418 lines)
> **Status:** DONE

---

## Business Purpose

Offline Python tool: đọc CSV trail từ indicator, tạo HTML report với embedded charts + JSON summary. Phân tích sâu hơn on-chart panel — monthly heatmaps, equity curves, drawdown analysis, session breakdown, Market vs Pullback comparison.

---

## Data Flow

```
MQL4/5 Indicator (runtime)
  ├─ signals_SYMBOL_TF_YYYY.csv       [existing]
  ├─ scoring_SYMBOL_TF_YYYY.csv       [existing]
  ├─ outcomes_SYMBOL_TF_YYYY.csv      [existing]
  └─ virtual_trades_SYMBOL_TF_YYYY.csv [Sprint 6 new]
        │
        ▼
backtest_analyzer.py
  ├─ Auto-discover CSVs by symbol/TF/year
  ├─ Join on SIGNAL_ID
  ├─ Generate matplotlib charts → base64 embed
  └─ Output:
       ├─ backtest_report_SYMBOL_TF.html
       └─ backtest_summary.json
```

---

## CLI Interface

```bash
# Single symbol/TF
python tools/backtest_analyzer.py --data-dir ./logs --symbol XAUUSD --tf H1

# All available combinations
python tools/backtest_analyzer.py --data-dir ./logs --all

# Custom output directory
python tools/backtest_analyzer.py --data-dir ./logs --all --output-dir ./reports
```

---

## Input

| File pattern | Required | Columns used |
|-------------|----------|--------------|
| `virtual_trades_*.csv` | Yes | All 24 columns |
| `signals_*.csv` | Optional | SIGNAL_ID + probability/signal fields |
| `scoring_*.csv` | Optional | SIGNAL_ID + XGB/calibration fields |
| `outcomes_*.csv` | Optional | SIGNAL_ID + realized outcome fields |

Join key: `SIGNAL_ID` (shared across all CSVs)

---

## Output

### HTML Report Sections

1. **Executive Summary** — total trades, WR, PF, Sharpe, Sortino, MaxDD, EV
2. **Equity Curve** — cumulative PnL over time (matplotlib line chart)
3. **Monthly Returns Heatmap** — month × year grid, color-coded by return
4. **Win Rate by Case** — bar chart, per signal case number
5. **Win Rate by Session** — bar chart, Asian/London/NewYork/Off-session
6. **Entry Type Comparison** — Market vs Pullback zones side-by-side
7. **Drawdown Analysis** — drawdown depth over time (matplotlib area chart)

### JSON Summary

```json
{
  "symbol": "XAUUSD",
  "tf": "H1",
  "total_trades": 147,
  "win_rate": 0.681,
  "profit_factor": 2.14,
  "sharpe": 1.85,
  "sortino": 2.31,
  "max_drawdown_pct": 3.2,
  "ev_per_trade_r": 0.42,
  "market_wr": 0.72,
  "pullback_wr": 0.61
}
```

---

## Key Functions

| Function | Mô tả |
|----------|--------|
| `find_csvs(data_dir, symbol, tf)` | Auto-discover CSV files matching pattern |
| `fig_to_base64(fig)` | Convert matplotlib figure → base64 string for HTML embed |
| `plot_equity_curve(df)` | Cumulative PnL line chart |
| `plot_monthly_heatmap(df)` | Month × year heatmap |
| `plot_wr_by_case(df)` | WR bar chart per case number |
| `plot_wr_by_session(df)` | WR bar chart per trading session |
| `plot_entry_type_comparison(df)` | Market vs Pullback comparison |
| `plot_drawdown(df)` | Drawdown depth area chart |
| `compute_summary(df)` | Dict with all numeric metrics |
| `generate_html_report(df, charts, summary, output_path)` | Assemble HTML with embedded charts |
| `main()` | CLI entry point, argparse |

---

## Dependencies

```
pandas, matplotlib, numpy
```

Đã có trong `requirements.txt` (shared với `quantedge_xgboost_train.py`). Không cần cài thêm.

---

## Design Decisions

1. **Embedded charts (base64)**: HTML report tự chứa, không cần web server hay external image files. Copy file đi đâu cũng mở được.
2. **Auto-discover CSVs**: user không cần nhớ exact filename — script scan `data_dir` theo pattern `virtual_trades_{symbol}_{tf}_*.csv`.
3. **Optional joins**: nếu `signals_*.csv` không có, report vẫn chạy chỉ từ `virtual_trades_*.csv`. Các sections phụ thuộc vào joined data sẽ bị skip.
4. **`matplotlib.use("Agg")`**: headless backend — chạy trên server/CI không cần display.
