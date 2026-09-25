#!/usr/bin/env python3
"""
dca_counterfactual.py -- replay an MT4 tester report under a capped DCA depth.

basket_analyzer.py answers "did the basket make money". This answers "what
would the SAME baskets have done with at most k negative-DCA legs", using only
prices the market actually traded:

  * a basket that never reached leg k+1 keeps its real outcome (unchanged legs);
  * a basket that did is closed at the fill price of leg k+1, with only the
    legs opened before it.

That makes the replay exact per basket. What it cannot model: new signals the
EA would have taken while a basket it now closes early was still open.

Extra spread is charged per kept leg, first-order (path effects ignored).

    python tools/dca_counterfactual.py logs/StrategyTester1.htm
    python tools/dca_counterfactual.py report.htm --split 2024-08-01 --spreads 0,0.2,0.4

Stdlib only.
"""

import argparse
import html
import math
import re
import statistics as st
import sys
from datetime import datetime
from pathlib import Path

OZ_PER_LOT = 100.0


def load_legs(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    opens, closes = {}, {}
    for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", text, re.S | re.I):
        c = [html.unescape(re.sub(r"<[^>]+>", "", x)).strip()
             for x in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S | re.I)]
        # MT4 report: open rows have 9 cells, close rows 10 (with Balance)
        if len(c) == 9 and c[2] in ("buy", "sell"):
            opens[int(c[3])] = dict(
                otime=datetime.strptime(c[1], "%Y.%m.%d %H:%M"),
                dir=1 if c[2] == "buy" else -1, lots=float(c[4]),
                oprice=float(c[5]), tp=float(c[7]), oraw=c[5])
        elif len(c) == 10 and c[0].isdigit():
            closes[int(c[3])] = dict(
                ctime=datetime.strptime(c[1], "%Y.%m.%d %H:%M"),
                cprice=float(c[5]), profit=float(c[8]), balance=float(c[9]))
    legs = []
    for k in sorted(opens):
        if k in closes:
            d = dict(order=k)
            d.update(opens[k])
            d.update(closes[k])
            legs.append(d)
    if not legs:
        sys.exit("No matched open/close rows -- is this an MT4 Strategy Tester report?")
    m = re.search(r"Spread</td>\s*<td[^>]*>\s*(?:Current\s*\()?(\d+)", text, re.I)
    spread_pts = int(m.group(1)) if m else None
    return legs, spread_pts


def group_baskets(legs, window_s):
    legs = sorted(legs, key=lambda r: (r["ctime"], r["order"]))
    groups, cur = [], []
    for r in legs:
        if cur and ((r["ctime"] - cur[-1]["ctime"]).total_seconds() > window_s
                    or r["dir"] != cur[0]["dir"]):
            groups.append(cur)
            cur = []
        cur.append(r)
    if cur:
        groups.append(cur)
    out = []
    for g in groups:
        g.sort(key=lambda r: r["otime"])
        orig, d = g[0], g[0]["dir"]
        neg = [x for x in g[1:] if (x["oprice"] - orig["oprice"]) * d < 0]
        pos = [x for x in g[1:] if (x["oprice"] - orig["oprice"]) * d >= 0]
        out.append(dict(legs=g, orig=orig, neg=neg, pos=pos, dir=d,
                        otime=orig["otime"], ctime=max(x["ctime"] for x in g),
                        pnl=sum(x["profit"] for x in g)))
    return out


def pnl_at(legs, price, d, spread):
    close = price - d * spread
    return sum(x["lots"] * OZ_PER_LOT * (close - x["oprice"]) * d for x in legs)


def cap_neg(baskets, k, spread, extra):
    rows = []
    for b in baskets:
        if len(b["neg"]) <= k:
            kept, pnl, cut = b["legs"], b["pnl"], False
        else:
            trig = b["neg"][k]
            kept = [x for x in b["legs"] if x["otime"] < trig["otime"] or x is b["orig"]]
            kept = [x for x in kept if x is not trig]
            pnl, cut = pnl_at(kept, trig["oprice"], b["dir"], spread), True
        pnl -= extra * sum(x["lots"] * OZ_PER_LOT for x in kept)
        rows.append(dict(otime=b["otime"], ctime=b["ctime"], pnl=pnl, cut=cut))
    return rows


def stats(rows):
    v = [r["pnl"] for r in rows]
    n = len(v)
    if n < 2:
        return None
    w = [x for x in v if x > 0]
    l = [x for x in v if x <= 0]
    gp, gl = sum(w), -sum(l)
    eq = peak = mdd = 0.0
    for r in sorted(rows, key=lambda r: r["ctime"]):
        eq += r["pnl"]
        peak = max(peak, eq)
        mdd = max(mdd, peak - eq)
    sd = st.stdev(v)
    return dict(n=n, wr=len(w) / n, pf=gp / gl if gl else float("inf"),
                net=gp - gl, mdd=mdd, rf=(gp - gl) / mdd if mdd else float("inf"),
                t=st.mean(v) / (sd / math.sqrt(n)) if sd else 0.0,
                worst=min(v), cuts=sum(r["cut"] for r in rows))


def main():
    ap = argparse.ArgumentParser(description="Replay DCA baskets under a capped negative-DCA depth.")
    ap.add_argument("report")
    ap.add_argument("--close-window", type=int, default=60)
    ap.add_argument("--split", default=None,
                    help="YYYY-MM-DD: report each half separately (default: midpoint by basket count)")
    ap.add_argument("--spreads", default="0,0.2,0.4",
                    help="Extra spread in $ per oz on top of the tester's, comma-separated")
    ap.add_argument("--kmax", type=int, default=10)
    args = ap.parse_args()

    legs, spread_pts = load_legs(args.report)
    baskets = group_baskets(legs, args.close_window)

    decimals = max(len(x["oraw"].split(".")[1]) if "." in x["oraw"] else 0 for x in legs)
    point = 10 ** -decimals
    if spread_pts is None:
        spread_pts = 50
        print("WARNING: tester spread not found in report header, assuming 50 points")
    # A leg of a BUY basket opens at ask; closing it at the same quote costs one spread.
    base_spread = spread_pts * point
    lots = {}
    for x in legs:
        lots[x["lots"]] = lots.get(x["lots"], 0) + 1
    top_lot, top_n = max(lots.items(), key=lambda kv: kv[1])

    print("=" * 96)
    print("legs %d  baskets %d  symbol digits %d (Point = %g)  tester spread %d pts = $%.3f"
          % (len(legs), len(baskets), decimals, point, spread_pts, base_spread))
    print("lot %.2f on %d of %d legs (%.0f%%)" % (top_lot, top_n, len(legs), top_n / len(legs) * 100))
    if decimals == 3:
        print("NOTE: 3-digit gold -- every *Pts / *Points input is 10x smaller in $ than on a 2-digit live feed.")

    if args.split:
        split = datetime.strptime(args.split, "%Y-%m-%d")
    else:
        split = sorted(b["otime"] for b in baskets)[len(baskets) // 2]
    print("halves split at %s" % split.strftime("%Y-%m-%d"))

    for extra in [float(s) for s in args.spreads.split(",")]:
        print("-" * 96)
        print("extra spread +$%.2f/oz" % extra)
        print("  k   cuts   WR      PF     net    maxDD     RF   worst      t  |  H1 PF   t   |  H2 PF   t")
        for k in range(0, args.kmax + 1):
            rows = cap_neg(baskets, k, base_spread, extra)
            a = stats(rows)
            h1 = stats([r for r in rows if r["otime"] < split])
            h2 = stats([r for r in rows if r["otime"] >= split])
            print(" %2d %5d %5.1f%% %6.2f %7.0f %8.0f %6.2f %7.0f %6.2f  | %5.2f %5.2f | %5.2f %5.2f"
                  % (k, a["cuts"], a["wr"] * 100, a["pf"], a["net"], a["mdd"], a["rf"],
                     a["worst"], a["t"], h1["pf"], h1["t"], h2["pf"], h2["t"]))
    print("=" * 96)
    print("k = max negative-DCA legs. Current preset InpNegDCAMaxOrders=10 is the k=10 row.")


if __name__ == "__main__":
    main()
