#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zone_edge.py - RSI Advanced: measure per-(case x direction x RSI-zone) edge.

Solution A: instead of splitting crossovers into separate CASES (which fragments
data and duplicates Case 1/5), we keep the existing cases and segment their
OUTCOMES by the RSI value logged at each signal (RSI_AT_SIGNAL column). This
answers the real question directly:

  - Does a BUY cross in the OVERSOLD zone (<32) have edge?
  - Does a SELL cross in the OVERBOUGHT zone (>68) have edge?
  - Do MID-zone (32-68) crosses have edge?

...for every case, AND aggregated across cases (case-agnostic "pure zone edge").

It joins:  signals_*.csv  (SIGNAL_ID, CASE_NUM, CASE_NAME, DIR, RSI_AT_SIGNAL)
     with  outcomes_*.csv (SIGNAL_ID, OUTCOME, PL_PIPS, MFE, MAE, BARS_HELD)
on SIGNAL_ID.

Usage:
  python zone_edge.py --dir "C:/.../MQL5/Files/RSI_Advanced_Logs"
  python zone_edge.py --dir <logs> --symbol XAUUSD --tf H1
  python zone_edge.py --dir <logs> --min 20     # only show buckets with >=20 resolved

OUTCOME encoding (from SignalLogger / ScanStoredSignalsBoth):
  -1 = SL hit, 0 = timeout/pending, 1/2/3 = TP1/TP2/TP3 hit.
Win-rate = TP / (TP + SL); avg PL uses PL_PIPS over resolved rows.
"""

import argparse
import csv
import glob
import os
from collections import defaultdict


def zone_of(rsi):
    """Bucket the RSI-green value at signal into OS / MID / OB."""
    if rsi is None:
        return "?"
    if rsi < 32.0:
        return "OS(<32)"
    if rsi > 68.0:
        return "OB(>68)"
    return "MID(32-68)"


def fnum(s):
    """Parse a float; return None on blank/garbage."""
    if s is None:
        return None
    s = s.strip()
    if s == "" or s.lower() in ("nan", "null", "na"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def load_csv(paths):
    """Read + concatenate rows (as dicts) from a list of CSV files sharing a header."""
    rows = []
    for p in paths:
        try:
            with open(p, "r", encoding="utf-8-sig", newline="") as f:
                rows.extend(list(csv.DictReader(f)))
        except OSError as e:
            print(f"  [warn] cannot read {p}: {e}")
    return rows


def find(logdir, prefix, symbol, tf):
    pat = f"{prefix}_*.csv"
    files = glob.glob(os.path.join(logdir, pat))
    if symbol:
        files = [f for f in files if symbol.upper() in os.path.basename(f).upper()]
    if tf:
        # match _<TF>_ to avoid H1 matching H14 etc.
        files = [f for f in files if f"_{tf.upper()}_" in os.path.basename(f).upper()]
    return sorted(files)


class Bucket:
    __slots__ = ("n", "tp", "sl", "to", "pl", "mfe", "mae")

    def __init__(self):
        self.n = 0          # total joined signals
        self.tp = 0         # OUTCOME >= 1
        self.sl = 0         # OUTCOME == -1
        self.to = 0         # OUTCOME == 0 (timeout/pending)
        self.pl = []        # PL_PIPS of resolved rows
        self.mfe = []
        self.mae = []

    def add(self, outcome, pl, mfe, mae):
        self.n += 1
        if outcome is None:
            return
        oi = int(round(outcome))
        if oi >= 1:
            self.tp += 1
        elif oi == -1:
            self.sl += 1
        else:
            self.to += 1
        if pl is not None:
            self.pl.append(pl)
        if mfe is not None:
            self.mfe.append(mfe)
        if mae is not None:
            self.mae.append(mae)

    @property
    def resolved(self):
        return self.tp + self.sl

    def winrate(self):
        d = self.tp + self.sl
        return (100.0 * self.tp / d) if d else None

    def avg(self, arr):
        return (sum(arr) / len(arr)) if arr else None


def _fmt(v, nd=1, suffix=""):
    return f"{v:.{nd}f}{suffix}" if v is not None else "-"


def print_table(title, groups, keycols, minres):
    print(f"\n=== {title} ===")
    hdr = keycols + ["N", "Resolved", "TP", "SL", "TO", "Win%", "AvgPL(pip)", "MFE", "MAE", "MFE/MAE"]
    widths = [max(len(h), 10) for h in hdr]
    line = "  ".join(h.ljust(w) for h, w in zip(hdr, widths))
    print(line)
    print("-" * len(line))
    # sort by resolved desc
    for key in sorted(groups, key=lambda k: -groups[k].resolved):
        b = groups[key]
        if b.resolved < minres:
            continue
        mfe, mae = b.avg(b.mfe), b.avg(b.mae)
        ratio = (mfe / mae) if (mfe is not None and mae not in (None, 0)) else None
        cells = list(key) + [
            str(b.n), str(b.resolved), str(b.tp), str(b.sl), str(b.to),
            _fmt(b.winrate(), 1, "%"), _fmt(b.avg(b.pl), 1),
            _fmt(mfe, 1), _fmt(mae, 1), _fmt(ratio, 2),
        ]
        print("  ".join(str(c).ljust(w) for c, w in zip(cells, widths)))


def main():
    ap = argparse.ArgumentParser(description="RSI Advanced per-case x zone edge analysis")
    ap.add_argument("--dir", default=".", help="folder with signals_*.csv / outcomes_*.csv")
    ap.add_argument("--symbol", default="", help="filter symbol substring, e.g. XAUUSD")
    ap.add_argument("--tf", default="", help="filter timeframe, e.g. H1")
    ap.add_argument("--min", type=int, default=1, help="min resolved count to display a bucket")
    args = ap.parse_args()

    sig_files = find(args.dir, "signals", args.symbol, args.tf)
    out_files = find(args.dir, "outcomes", args.symbol, args.tf)
    if not sig_files:
        print(f"No signals_*.csv in {os.path.abspath(args.dir)} (symbol={args.symbol!r} tf={args.tf!r})")
        return
    print(f"signals files : {[os.path.basename(f) for f in sig_files]}")
    print(f"outcomes files: {[os.path.basename(f) for f in out_files]}")

    signals = load_csv(sig_files)
    outcomes = load_csv(out_files)

    # index outcomes by SIGNAL_ID
    out_by_id = {}
    for r in outcomes:
        sid = (r.get("SIGNAL_ID") or "").strip()
        if sid:
            out_by_id[sid] = r  # last write wins (resolved overwrites pending)

    # dedup signals by SIGNAL_ID (last-write-wins). Logs are no longer wiped on TF switch,
    # so the signals CSV can contain repeat rows for the same signal across sessions —
    # count each signal exactly once to avoid skewing win-rate / EV.
    sig_by_id = {}
    for s in signals:
        sid = (s.get("SIGNAL_ID") or "").strip()
        if sid:
            sig_by_id[sid] = s

    by_full = defaultdict(Bucket)   # (case, dir, zone)
    by_zone = defaultdict(Bucket)   # (zone, dir)  -- case-agnostic
    unmatched = 0

    for s in sig_by_id.values():
        sid = (s.get("SIGNAL_ID") or "").strip()
        o = out_by_id.get(sid)
        if o is None:
            unmatched += 1
            continue
        case = (s.get("CASE_NUM") or "?").strip()
        cname = (s.get("CASE_NAME") or "").strip()
        direction = (s.get("DIR") or "?").strip().upper()
        rsi = fnum(s.get("RSI_AT_SIGNAL"))
        z = zone_of(rsi)
        outcome = fnum(o.get("OUTCOME"))
        pl = fnum(o.get("PL_PIPS"))
        mfe = fnum(o.get("MFE"))
        mae = fnum(o.get("MAE"))

        case_lbl = f"{case}:{cname}" if cname else case
        by_full[(case_lbl, direction, z)].add(outcome, pl, mfe, mae)
        by_zone[(z, direction)].add(outcome, pl, mfe, mae)

    print(f"\nsignals={len(sig_by_id)} (raw rows={len(signals)})  outcomes={len(outcomes)}  "
          f"joined={len(sig_by_id) - unmatched}  unmatched(no outcome yet)={unmatched}")

    # Case-agnostic zone edge: the direct answer to "does an OS-buy / OB-sell / MID cross pay?"
    print_table("PURE ZONE EDGE (all cases pooled, by RSI zone x direction)",
                by_zone, ["Zone", "Dir"], args.min)

    # Per-case detail
    print_table("PER CASE x DIRECTION x ZONE",
                by_full, ["Case", "Dir", "Zone"], args.min)

    print("\nNotes:")
    print("  * Win% = TP/(TP+SL); TO = timeout/pending (excluded from Win%).")
    print("  * AvgPL(pip) is realized P/L per signal (the honest edge). >0 = positive expectancy.")
    print("  * MFE/MAE >1 = signals ran further in favor than against (structural quality).")
    print("  * Buckets with few resolved (< ~30) are noisy - use --min to hide them.")


if __name__ == "__main__":
    main()
