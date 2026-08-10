#!/usr/bin/env python3
"""
backtest_analyzer.py — Offline backtest report for QuantEdge_RSI Sprint 6

Reads CSV trail (signals, scoring, outcomes, virtual_trades), joins on
SIGNAL_ID, and produces an HTML report with embedded charts + a JSON summary.

Usage:
    python tools/backtest_analyzer.py --data-dir ./logs --symbol XAUUSD --tf H1
    python tools/backtest_analyzer.py --data-dir ./logs --all

Requirements:
    pip install pandas matplotlib numpy  (already in requirements.txt)
"""

import argparse
import json
import os
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import numpy as np
import pandas as pd
from io import BytesIO
import base64


def find_csvs(data_dir: str, symbol: str, tf: str):
    """Auto-discover CSV files matching symbol/tf pattern."""
    p = Path(data_dir)
    result = {}
    for kind in ["signals", "scoring", "outcomes", "virtual_trades"]:
        pattern = f"{kind}_{symbol}_{tf}_*.csv"
        files = sorted(p.glob(pattern))
        if files:
            dfs = [pd.read_csv(f) for f in files]
            result[kind] = pd.concat(dfs, ignore_index=True)
    return result


def fig_to_base64(fig) -> str:
    buf = BytesIO()
    fig.savefig(buf, format="png", dpi=100, bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return base64.b64encode(buf.read()).decode("utf-8")


def plot_equity_curve(vt: pd.DataFrame) -> str:
    """Cumulative PnL in pips from virtual trades."""
    vt = vt.sort_values("OUTCOME_TIME").copy()
    vt["PNL_PIPS"] = np.where(
        vt["DIR"] == "BUY",
        vt["EXIT_PRICE"] - vt["ENTRY_PRICE"],
        vt["ENTRY_PRICE"] - vt["EXIT_PRICE"],
    )
    vt["CUM_PNL"] = vt["PNL_PIPS"].cumsum()

    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(range(len(vt)), vt["CUM_PNL"], color="#2196F3", linewidth=1.5)
    ax.fill_between(range(len(vt)), vt["CUM_PNL"], alpha=0.15, color="#2196F3")
    ax.set_xlabel("Trade #")
    ax.set_ylabel("Cumulative PnL (price units)")
    ax.set_title("Equity Curve")
    ax.grid(True, alpha=0.3)
    return fig_to_base64(fig)


def plot_monthly_heatmap(vt: pd.DataFrame) -> str:
    """Monthly returns heatmap."""
    vt = vt.copy()
    vt["OUTCOME_DT"] = pd.to_datetime(vt["OUTCOME_TIME"], errors="coerce")
    vt = vt.dropna(subset=["OUTCOME_DT"])
    vt["PNL"] = np.where(
        vt["DIR"] == "BUY",
        vt["EXIT_PRICE"] - vt["ENTRY_PRICE"],
        vt["ENTRY_PRICE"] - vt["EXIT_PRICE"],
    )
    vt["YEAR"] = vt["OUTCOME_DT"].dt.year
    vt["MONTH"] = vt["OUTCOME_DT"].dt.month

    pivot = vt.pivot_table(values="PNL", index="YEAR", columns="MONTH", aggfunc="sum", fill_value=0)
    month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    all_months = list(range(1, 13))
    for m in all_months:
        if m not in pivot.columns:
            pivot[m] = 0
    pivot = pivot[all_months]
    pivot.columns = month_names

    fig, ax = plt.subplots(figsize=(10, max(3, len(pivot) * 0.8)))
    cmap = plt.cm.RdYlGn
    im = ax.imshow(pivot.values, cmap=cmap, aspect="auto")
    ax.set_xticks(range(12))
    ax.set_xticklabels(month_names)
    ax.set_yticks(range(len(pivot)))
    ax.set_yticklabels(pivot.index)
    for i in range(len(pivot)):
        for j in range(12):
            val = pivot.values[i, j]
            ax.text(j, i, f"{val:.0f}", ha="center", va="center", fontsize=8,
                    color="black" if abs(val) < pivot.values.max() * 0.6 else "white")
    ax.set_title("Monthly Returns (price units)")
    fig.colorbar(im, ax=ax, shrink=0.8)
    return fig_to_base64(fig)


def plot_wr_by_case(vt: pd.DataFrame) -> str:
    """Win rate by case number."""
    vt = vt.copy()
    vt["WIN"] = (vt["MAX_TP_REACHED"] > 0).astype(int)
    grouped = vt.groupby("CASE_NUM").agg(
        total=("WIN", "count"),
        wins=("WIN", "sum")
    ).reset_index()
    grouped["WR"] = grouped["wins"] / grouped["total"] * 100

    fig, ax = plt.subplots(figsize=(8, 4))
    bars = ax.bar(grouped["CASE_NUM"].astype(str), grouped["WR"], color="#4CAF50", alpha=0.8)
    for bar, n in zip(bars, grouped["total"]):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1,
                f"n={n}", ha="center", fontsize=8)
    ax.set_xlabel("Case Number")
    ax.set_ylabel("Win Rate (%)")
    ax.set_title("Win Rate by Signal Case")
    ax.set_ylim(0, 100)
    ax.grid(True, alpha=0.3, axis="y")
    return fig_to_base64(fig)


def plot_wr_by_session(vt: pd.DataFrame) -> str:
    """Win rate by session."""
    vt = vt.copy()
    vt["WIN"] = (vt["MAX_TP_REACHED"] > 0).astype(int)
    grouped = vt.groupby("SESSION").agg(
        total=("WIN", "count"),
        wins=("WIN", "sum")
    ).reset_index()
    grouped["WR"] = grouped["wins"] / grouped["total"] * 100

    fig, ax = plt.subplots(figsize=(8, 4))
    colors = ["#FF9800", "#2196F3", "#9C27B0", "#607D8B"]
    bars = ax.bar(grouped["SESSION"], grouped["WR"],
                  color=colors[:len(grouped)], alpha=0.8)
    for bar, n in zip(bars, grouped["total"]):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1,
                f"n={n}", ha="center", fontsize=8)
    ax.set_ylabel("Win Rate (%)")
    ax.set_title("Win Rate by Session")
    ax.set_ylim(0, 100)
    ax.grid(True, alpha=0.3, axis="y")
    return fig_to_base64(fig)


def plot_entry_type_comparison(vt: pd.DataFrame) -> str:
    """Market vs Pullback zone performance."""
    vt = vt.copy()
    vt["WIN"] = (vt["MAX_TP_REACHED"] > 0).astype(int)
    vt["TYPE"] = np.where(vt["ENTRY_TYPE"] == "Market", "Market", "Pullback")
    grouped = vt.groupby("TYPE").agg(
        total=("WIN", "count"),
        wins=("WIN", "sum")
    ).reset_index()
    grouped["WR"] = grouped["wins"] / grouped["total"] * 100

    fig, ax = plt.subplots(figsize=(6, 4))
    colors = ["#2196F3", "#FF9800"]
    bars = ax.bar(grouped["TYPE"], grouped["WR"], color=colors[:len(grouped)], alpha=0.8)
    for bar, row in zip(bars, grouped.itertuples()):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1,
                f"n={row.total} ({row.wins}W)", ha="center", fontsize=9)
    ax.set_ylabel("Win Rate (%)")
    ax.set_title("Market vs Pullback Entry")
    ax.set_ylim(0, 100)
    ax.grid(True, alpha=0.3, axis="y")
    return fig_to_base64(fig)


def plot_drawdown(vt: pd.DataFrame) -> str:
    """Drawdown chart from equity curve."""
    vt = vt.sort_values("OUTCOME_TIME").copy()
    vt["PNL"] = np.where(
        vt["DIR"] == "BUY",
        vt["EXIT_PRICE"] - vt["ENTRY_PRICE"],
        vt["ENTRY_PRICE"] - vt["EXIT_PRICE"],
    )
    cum = vt["PNL"].cumsum()
    peak = cum.cummax()
    dd = cum - peak

    fig, ax = plt.subplots(figsize=(10, 3))
    ax.fill_between(range(len(dd)), dd, color="#F44336", alpha=0.4)
    ax.plot(range(len(dd)), dd, color="#F44336", linewidth=1)
    ax.set_xlabel("Trade #")
    ax.set_ylabel("Drawdown (price units)")
    ax.set_title("Drawdown Analysis")
    ax.grid(True, alpha=0.3)
    return fig_to_base64(fig)


def compute_summary(vt: pd.DataFrame) -> dict:
    """Compute summary statistics."""
    vt = vt.copy()
    vt["PNL"] = np.where(
        vt["DIR"] == "BUY",
        vt["EXIT_PRICE"] - vt["ENTRY_PRICE"],
        vt["ENTRY_PRICE"] - vt["EXIT_PRICE"],
    )
    vt["WIN"] = (vt["MAX_TP_REACHED"] > 0).astype(int)

    n = len(vt)
    wins = vt["WIN"].sum()
    losses = n - wins
    wr = wins / n * 100 if n > 0 else 0

    gross_profit = vt.loc[vt["PNL"] > 0, "PNL"].sum()
    gross_loss = vt.loc[vt["PNL"] < 0, "PNL"].abs().sum()
    pf = gross_profit / gross_loss if gross_loss > 0 else 0

    cum = vt["PNL"].cumsum()
    peak = cum.cummax()
    max_dd = (cum - peak).min()

    returns = vt["PNL"].values
    if len(returns) > 1:
        mean_r = returns.mean()
        std_r = returns.std(ddof=1)
        sharpe = mean_r / std_r * np.sqrt(252) if std_r > 0 else 0
        neg = returns[returns < 0]
        down_dev = np.sqrt((neg ** 2).mean()) if len(neg) > 0 else 0
        sortino = mean_r / down_dev * np.sqrt(252) if down_dev > 0 else 0
    else:
        sharpe = sortino = 0
        mean_r = 0

    mkt = vt[vt["ENTRY_TYPE"] == "Market"]
    pb = vt[vt["ENTRY_TYPE"] != "Market"]
    mkt_wr = mkt["WIN"].mean() * 100 if len(mkt) > 0 else 0
    pb_wr = pb["WIN"].mean() * 100 if len(pb) > 0 else 0

    return {
        "total_trades": int(n),
        "wins": int(wins),
        "losses": int(losses),
        "win_rate": round(wr, 2),
        "profit_factor": round(pf, 3),
        "sharpe": round(sharpe, 3),
        "sortino": round(sortino, 3),
        "max_drawdown": round(float(max_dd), 2),
        "ev_per_trade": round(float(mean_r), 4),
        "market_wr": round(mkt_wr, 2),
        "pullback_wr": round(pb_wr, 2),
        "total_pnl": round(float(cum.iloc[-1]) if len(cum) > 0 else 0, 2),
    }


def generate_html_report(symbol: str, tf: str, csvs: dict, output_dir: str):
    """Generate the full HTML report."""
    vt = csvs.get("virtual_trades")
    if vt is None or len(vt) == 0:
        print(f"[WARN] No virtual_trades data for {symbol}_{tf}, skipping.")
        return

    resolved = vt[vt["FINAL_OUTCOME"] != "PENDING"].copy()
    if len(resolved) == 0:
        print(f"[WARN] No resolved virtual trades for {symbol}_{tf}.")
        return

    summary = compute_summary(resolved)

    charts = {}
    charts["equity"] = plot_equity_curve(resolved)
    charts["monthly"] = plot_monthly_heatmap(resolved)
    charts["drawdown"] = plot_drawdown(resolved)
    charts["wr_case"] = plot_wr_by_case(resolved)
    charts["wr_session"] = plot_wr_by_session(resolved)
    charts["entry_type"] = plot_entry_type_comparison(resolved)

    wr_by_dir = resolved.groupby("DIR").agg(
        n=("MAX_TP_REACHED", "count"),
        wins=("MAX_TP_REACHED", lambda x: (x > 0).sum())
    ).reset_index()
    wr_by_dir["WR"] = (wr_by_dir["wins"] / wr_by_dir["n"] * 100).round(1)
    dir_rows = ""
    for _, r in wr_by_dir.iterrows():
        dir_rows += f"<tr><td>{r['DIR']}</td><td>{r['n']}</td><td>{r['wins']}</td><td>{r['WR']}%</td></tr>"

    html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Backtest Report — {symbol} {tf}</title>
<style>
body {{ font-family: 'Segoe UI', Tahoma, sans-serif; max-width: 1100px; margin: 0 auto; padding: 20px; background: #1a1a2e; color: #e0e0e0; }}
h1 {{ color: #FFD700; border-bottom: 2px solid #333; padding-bottom: 10px; }}
h2 {{ color: #4CAF50; margin-top: 30px; }}
.summary-grid {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin: 20px 0; }}
.metric {{ background: #16213e; padding: 15px; border-radius: 8px; text-align: center; }}
.metric .value {{ font-size: 24px; font-weight: bold; color: #FFD700; }}
.metric .label {{ font-size: 12px; color: #888; margin-top: 5px; }}
img {{ max-width: 100%; border-radius: 8px; margin: 10px 0; }}
table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
th, td {{ padding: 8px 12px; text-align: center; border: 1px solid #333; }}
th {{ background: #16213e; color: #4CAF50; }}
tr:nth-child(even) {{ background: #1a1a2e; }}
tr:nth-child(odd) {{ background: #16213e; }}
.positive {{ color: #4CAF50; }}
.negative {{ color: #F44336; }}
.footer {{ margin-top: 40px; padding-top: 10px; border-top: 1px solid #333; color: #666; font-size: 12px; }}
</style>
</head>
<body>
<h1>QuantEdge RSI — Backtest Report</h1>
<p><strong>{symbol}</strong> | <strong>{tf}</strong> | {summary['total_trades']} virtual trades analyzed</p>

<h2>Executive Summary</h2>
<div class="summary-grid">
  <div class="metric"><div class="value">{summary['total_trades']}</div><div class="label">Total Trades</div></div>
  <div class="metric"><div class="value">{summary['win_rate']}%</div><div class="label">Win Rate</div></div>
  <div class="metric"><div class="value">{summary['profit_factor']}</div><div class="label">Profit Factor</div></div>
  <div class="metric"><div class="value">{summary['sharpe']}</div><div class="label">Sharpe Ratio</div></div>
  <div class="metric"><div class="value">{summary['sortino']}</div><div class="label">Sortino Ratio</div></div>
  <div class="metric"><div class="value class="{('positive' if summary['max_drawdown'] >= 0 else 'negative')}">{summary['max_drawdown']}</div><div class="label">Max Drawdown</div></div>
  <div class="metric"><div class="value">{summary['market_wr']}%</div><div class="label">Market WR</div></div>
  <div class="metric"><div class="value">{summary['pullback_wr']}%</div><div class="label">Pullback WR</div></div>
</div>

<h2>Equity Curve</h2>
<img src="data:image/png;base64,{charts['equity']}" alt="Equity Curve">

<h2>Monthly Returns</h2>
<img src="data:image/png;base64,{charts['monthly']}" alt="Monthly Heatmap">

<h2>Drawdown Analysis</h2>
<img src="data:image/png;base64,{charts['drawdown']}" alt="Drawdown">

<h2>Win Rate by Case</h2>
<img src="data:image/png;base64,{charts['wr_case']}" alt="WR by Case">

<h2>Win Rate by Session</h2>
<img src="data:image/png;base64,{charts['wr_session']}" alt="WR by Session">

<h2>Win Rate by Direction</h2>
<table>
<tr><th>Direction</th><th>Trades</th><th>Wins</th><th>Win Rate</th></tr>
{dir_rows}
</table>

<h2>Market vs Pullback Entry</h2>
<img src="data:image/png;base64,{charts['entry_type']}" alt="Entry Type Comparison">

<div class="footer">
Generated by QuantEdge RSI Backtest Analyzer (Sprint 6) |
EV/trade: {summary['ev_per_trade']} | Total PnL: {summary['total_pnl']}
</div>
</body>
</html>"""

    report_path = os.path.join(output_dir, f"backtest_report_{symbol}_{tf}.html")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[OK] Report: {report_path}")

    json_path = os.path.join(output_dir, f"backtest_summary_{symbol}_{tf}.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"symbol": symbol, "timeframe": tf, **summary}, f, indent=2)
    print(f"[OK] Summary: {json_path}")


def main():
    parser = argparse.ArgumentParser(description="QuantEdge RSI Backtest Analyzer")
    parser.add_argument("--data-dir", required=True, help="Directory containing CSV files")
    parser.add_argument("--symbol", default=None, help="Symbol (e.g., XAUUSD)")
    parser.add_argument("--tf", default=None, help="Timeframe (e.g., H1)")
    parser.add_argument("--all", action="store_true", help="Process all symbol/tf combos found")
    parser.add_argument("--output-dir", default=None, help="Output directory (default: data-dir)")
    args = parser.parse_args()

    data_dir = args.data_dir
    output_dir = args.output_dir or data_dir

    if not os.path.isdir(data_dir):
        print(f"[ERROR] Data directory not found: {data_dir}")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)

    if args.all:
        vt_files = list(Path(data_dir).glob("virtual_trades_*_*.csv"))
        combos = set()
        for f in vt_files:
            parts = f.stem.replace("virtual_trades_", "").rsplit("_", 1)
            if len(parts) >= 2:
                sym_tf = parts[0].rsplit("_", 1)
                if len(sym_tf) == 2:
                    combos.add((sym_tf[0], sym_tf[1]))
        if not combos:
            print("[WARN] No virtual_trades CSV files found.")
            sys.exit(0)
        for sym, tf in sorted(combos):
            print(f"\n--- Processing {sym} {tf} ---")
            csvs = find_csvs(data_dir, sym, tf)
            generate_html_report(sym, tf, csvs, output_dir)
    else:
        if not args.symbol or not args.tf:
            print("[ERROR] Specify --symbol and --tf, or use --all")
            sys.exit(1)
        csvs = find_csvs(data_dir, args.symbol, args.tf)
        generate_html_report(args.symbol, args.tf, csvs, output_dir)


if __name__ == "__main__":
    main()
