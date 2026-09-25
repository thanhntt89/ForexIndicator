#!/usr/bin/env python3
"""
basket_analyzer.py — regroup MT4 Strategy Tester legs into DCA baskets.

WHY THIS EXISTS
---------------
MT4 counts every closed order as one "trade". With PosDCA (max 4) and NegDCA
(max 10) enabled, a single signal can produce up to 15 of them. The tester's
headline win rate is therefore a PER-LEG figure, and DCA legs opened at better
prices close green whenever the basket recovers -- which inflates it relative
to the only number that matters for edge: did the BASKET make money.

The strategy's own CloseEntireBasket() / CloseNegDCABasket() shut every leg in
one pass, so legs belonging to one basket share a close time to within a few
seconds. That is what this script groups on.

The indicator's CSV logger is disabled under the tester
(SignalLogger.mqh: `if(IsBacktestMode()) return;`), so the MT4 report is the
only source of per-trade data.

Deliberately stdlib-only: no pandas, no lxml, nothing to install.

USAGE
-----
    # MT4: right-click the Results tab -> Save as Report -> report.htm
    python tools/basket_analyzer.py path/to/report.htm

    # or paste the Results tab into a .csv/.tsv and pass that
    python tools/basket_analyzer.py results.csv --initial-deposit 1000

    # tune grouping if baskets look split/merged
    python tools/basket_analyzer.py report.htm --close-window 120
"""

import argparse
import csv
import html
import re
import sys
from datetime import datetime
from pathlib import Path


# --- Magic-number map, mirrors IsOurMagic() in QuantEdge_EA_Template.mq4 ----
# Plain literals because the EA is a separate program with no shared include;
# if the offsets there change, change them here too.
MAGIC_TP2_OFFSET = 100000
MAGIC_TP3_OFFSET = 150000
MAGIC_POS_DCA_OFFSET = 200000
MAGIC_NEG_DCA_OFFSET = 300000

CLOSE_TYPES = {"close", "s/l", "t/p", "sl", "tp", "close at stop"}
OPEN_TYPES = {"buy", "sell"}

COLUMN_ALIASES = {
    "time": "time", "thời gian": "time", "open time": "time",
    "type": "type", "loại": "type",
    "order": "order", "lệnh": "order", "#": "order", "ticket": "order",
    "size": "size", "volume": "size", "khối lượng": "size", "lots": "size",
    "price": "price", "giá": "price",
    "profit": "profit", "lợi nhuận": "profit",
    "balance": "balance", "số dư": "balance",
    "magic": "magic", "magic number": "magic",
    "comment": "comment", "ghi chú": "comment",
}


def classify_magic(magic, base_magic):
    """Name the leg type for a magic number, or None if it is not ours."""
    if magic is None or base_magic is None:
        return None
    d = magic - base_magic
    if d == 0:
        return "ORIGINAL"
    if d == MAGIC_TP2_OFFSET:
        return "TP2"
    if d == MAGIC_TP3_OFFSET:
        return "TP3"
    if MAGIC_POS_DCA_OFFSET <= d < MAGIC_POS_DCA_OFFSET + 100:
        return "POS_DCA_%d" % (d - MAGIC_POS_DCA_OFFSET)
    if MAGIC_NEG_DCA_OFFSET <= d < MAGIC_NEG_DCA_OFFSET + 100:
        return "NEG_DCA_%d" % (d - MAGIC_NEG_DCA_OFFSET)
    return None


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------

def strip_tags(cell):
    return html.unescape(re.sub(r"<[^>]+>", "", cell)).strip()


def parse_mt4_html(path):
    """Pull the widest <tr> table out of an MT4 tester report."""
    text = path.read_text(encoding="utf-8", errors="replace")
    rows = []
    for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", text, re.S | re.I):
        cells = [strip_tags(td) for td in
                 re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S | re.I)]
        if cells:
            rows.append(cells)
    if not rows:
        sys.exit("No HTML table rows found in %s" % path)

    # Header = first row that names both a time and a type column.
    header_idx = None
    for i, r in enumerate(rows):
        low = [c.lower() for c in r]
        if any(c in ("time", "thời gian") for c in low) and \
           any(c in ("type", "loại") for c in low):
            header_idx = i
            break
    if header_idx is None:
        sys.exit(
            "Could not find the trade table in %s.\n"
            "Make sure this is the Strategy Tester report (Save as Report), "
            "not the optimisation report." % path
        )

    header = rows[header_idx]
    width = len(header)
    body = [r for r in rows[header_idx + 1:] if len(r) == width]
    return header, body


def parse_delimited(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters="\t,;")
        delim = dialect.delimiter
    except Exception:
        delim = "\t" if "\t" in sample else ","
    rows = [r for r in csv.reader(text.splitlines(), delimiter=delim) if r]
    if not rows:
        sys.exit("Empty file: %s" % path)
    return rows[0], rows[1:]


def to_float(v):
    if v is None:
        return None
    s = re.sub(r"[^\d.\-]", "", str(v))
    if s in ("", "-", "."):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def parse_time(v):
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d %H:%M",
                "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            return datetime.strptime(str(v).strip(), fmt)
        except ValueError:
            continue
    return None


def normalise(header, body):
    """Map MT4's (localisable) headers onto a fixed schema."""
    idx = {}
    for i, name in enumerate(header):
        key = COLUMN_ALIASES.get(str(name).strip().lower())
        if key and key not in idx:
            idx[key] = i

    if "type" not in idx:
        sys.exit("No 'Type' column -- is this really the trade table?")

    out = []
    for r in body:
        rec = {}
        for key, i in idx.items():
            v = r[i] if i < len(r) else None
            if key == "time":
                rec[key] = parse_time(v)
            elif key == "type":
                rec[key] = str(v).strip().lower()
            elif key in ("size", "price", "profit", "balance", "magic", "order"):
                rec[key] = to_float(v)
            else:
                rec[key] = v
        out.append(rec)
    return out


def build_trades(rows):
    """
    Collapse MT4's open/close event rows into one record per closed trade.

    MT4 lists each order twice: a 'buy'/'sell' open row and a
    'close'/'s/l'/'t/p' row carrying the realised profit. Keep the close rows
    and pull the open time from the matching order id.
    """
    opens = {}
    for r in rows:
        if r.get("type") in OPEN_TYPES and r.get("order") is not None:
            opens[r["order"]] = r

    closes = [r for r in rows if r.get("type") in CLOSE_TYPES]

    if not closes:
        # Some report variants already use one row per trade.
        closes = [r for r in rows if r.get("profit") is not None]
        if not closes:
            sys.exit("No closed trades found in the report.")
        for r in closes:
            r["open_time"] = r.get("time")
            r["close_time"] = r.get("time")
        return closes

    for r in closes:
        src = opens.get(r.get("order"))
        r["open_time"] = src.get("time") if src else None
        r["direction"] = src.get("type") if src else None
        r["close_time"] = r.get("time")
    return [r for r in closes if r.get("profit") is not None
            and r.get("close_time") is not None]


# --------------------------------------------------------------------------
# Grouping + stats
# --------------------------------------------------------------------------

def group_baskets(trades, window_s):
    """
    Assign a basket id by close-time proximity.

    CloseEntireBasket() and CloseNegDCABasket() close every leg in one loop,
    so a basket's legs land within seconds of each other. A leg that exits on
    its own (a lone TP1 hit) becomes a one-leg basket, which is correct --
    that IS the whole trade.
    """
    ts = sorted(trades, key=lambda r: r["close_time"])
    bid = 0
    prev = None
    for r in ts:
        if prev is not None and (r["close_time"] - prev).total_seconds() > window_s:
            bid += 1
        r["basket_id"] = bid
        prev = r["close_time"]
    return ts


def quantile(sorted_vals, q):
    if not sorted_vals:
        return float("nan")
    i = q * (len(sorted_vals) - 1)
    lo, hi = int(i), min(int(i) + 1, len(sorted_vals) - 1)
    frac = i - lo
    return sorted_vals[lo] * (1 - frac) + sorted_vals[hi] * frac


def summarise(legs, initial_deposit):
    buckets = {}
    for r in legs:
        b = buckets.setdefault(r["basket_id"], {"pnl": 0.0, "legs": 0, "close": None})
        b["pnl"] += r["profit"]
        b["legs"] += 1
        if b["close"] is None or r["close_time"] > b["close"]:
            b["close"] = r["close_time"]

    baskets = sorted(buckets.values(), key=lambda b: b["close"])
    n = len(baskets)
    if n == 0:
        sys.exit("No baskets formed -- check --close-window.")

    wins = [b for b in baskets if b["pnl"] > 0]
    losses = [b for b in baskets if b["pnl"] <= 0]

    wr = len(wins) / n
    gross_p = sum(b["pnl"] for b in wins)
    gross_l = abs(sum(b["pnl"] for b in losses))
    pf = gross_p / gross_l if gross_l else float("inf")
    avg_w = gross_p / len(wins) if wins else 0.0
    avg_l = sum(b["pnl"] for b in losses) / len(losses) if losses else 0.0
    payoff = avg_w / abs(avg_l) if avg_l else float("inf")
    be_wr = 1 / (1 + payoff) if payoff not in (0, float("inf")) else float("nan")

    equity = initial_deposit
    peak = initial_deposit
    max_dd = 0.0
    max_dd_pct = 0.0
    for b in baskets:
        equity += b["pnl"]
        peak = max(peak, equity)
        dd = peak - equity
        if dd > max_dd:
            max_dd = dd
            max_dd_pct = dd / peak * 100 if peak else 0.0

    net = sum(b["pnl"] for b in baskets)
    pnls = sorted(b["pnl"] for b in baskets)

    line = "=" * 68
    print(line)
    print("BASKET-LEVEL RESULTS  (one row per DCA basket, not per leg)")
    print(line)
    print("  legs (MT4 'trades')        %d" % len(legs))
    print("  baskets (independent)      %d" % n)
    print("  avg legs per basket        %.2f" % (len(legs) / n))
    print()
    print("  win rate  (basket)         %.2f%%" % (wr * 100))
    print("  breakeven WR needed        %.2f%%   (payoff b=%.3f)" % (be_wr * 100, payoff))
    margin = (wr - be_wr) * 100
    print("  edge margin                %+.2f pp   %s"
          % (margin, "<-- NO EDGE" if margin <= 0 else ""))
    print()
    print("  profit factor (basket)     %.2f" % pf)
    print("  net profit                 %.2f" % net)
    print("  avg win / avg loss         %.2f / %.2f" % (avg_w, avg_l))
    print()
    print("  max drawdown               %.2f  (%.2f%%)" % (max_dd, max_dd_pct))
    rf = net / max_dd if max_dd else float("inf")
    print("  recovery factor            %.2f   %s"
          % (rf, "<-- below the 3.0 benchmark" if rf < 3.0 else ""))
    print()
    print("  basket P/L distribution:")
    for q in (0.01, 0.05, 0.25, 0.50, 0.75, 0.95, 0.99):
        print("    p%-3d  %10.2f" % (int(q * 100), quantile(pnls, q)))
    print("    worst %10.2f   (%.1f%% of initial deposit)"
          % (pnls[0], abs(pnls[0]) / initial_deposit * 100))
    print("    best  %10.2f" % pnls[-1])
    print()
    print("  legs per basket:")
    counts = {}
    for b in baskets:
        counts[b["legs"]] = counts.get(b["legs"], 0) + 1
    for k in sorted(counts):
        print("    %2d legs : %5d baskets" % (k, counts[k]))
    print()

    # A DD-cap cut shows up as a deep, multi-leg loss.
    deep = [b for b in baskets if b["legs"] >= 3 and b["pnl"] < 0]
    if deep:
        tot = sum(b["pnl"] for b in deep)
        print("  multi-leg losing baskets (likely DD-cap cuts): %d" % len(deep))
        print("    total cost %.2f   mean %.2f   worst %.2f"
              % (tot, tot / len(deep), min(b["pnl"] for b in deep)))
        print("    %.1f%% of baskets but %.1f%% of gross loss"
              % (len(deep) / n * 100,
                 abs(tot) / gross_l * 100 if gross_l else 0.0))
    print(line)
    return baskets


def main():
    ap = argparse.ArgumentParser(
        description="Regroup MT4 tester legs into DCA baskets."
    )
    ap.add_argument("report", help="MT4 .htm report, or Results pasted to .csv/.tsv")
    ap.add_argument("--initial-deposit", type=float, default=1000.0)
    ap.add_argument(
        "--close-window", type=int, default=60,
        help="Seconds within which legs count as one basket (default 60). "
             "Raise it if baskets look split; lower it if unrelated trades merge.",
    )
    ap.add_argument("--dump", help="Write the per-basket table to this CSV")
    args = ap.parse_args()

    path = Path(args.report)
    if not path.exists():
        sys.exit("Not found: %s" % path)

    if path.suffix.lower() in (".htm", ".html"):
        header, body = parse_mt4_html(path)
    else:
        header, body = parse_delimited(path)

    rows = normalise(header, body)
    trades = build_trades(rows)
    legs = group_baskets(trades, args.close_window)
    baskets = summarise(legs, args.initial_deposit)

    if args.dump:
        with open(args.dump, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["basket_id", "legs", "pnl", "close_time"])
            for i, b in enumerate(baskets):
                w.writerow([i, b["legs"], "%.2f" % b["pnl"], b["close"]])
        print("per-basket table -> %s" % args.dump)


if __name__ == "__main__":
    main()
