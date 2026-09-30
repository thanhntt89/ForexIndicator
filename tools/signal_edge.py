#!/usr/bin/env python3
"""
signal_edge.py -- does the indicator's signal predict price, before any DCA?

Every backtest so far measured the whole EA at once: signal + DCA + BE
close + basket cap + 2024's +28% gold trend. This measures the signal alone.

Input is the per-bar log the EA writes with InpResearchLog=true
(<Common>\\Files\\QuantEdge_Research\\bars_<SYMBOL>_<TF>_<start>.csv): OHLC of
every closed bar, the bid/ask at the next bar's first tick (the fill the EA
would get) and, on signal bars, the indicator's SL/TP/probability/EV.

Each signal is compared with RANDOM ENTRIES in the same direction, at the
same clock hour +-1, drawn from 2 to 12 days either side of it (by default):

  1. forward return after h bars -- enter at the next quote, exit h bars
     later (BUY pays the ask, SELL buys back at the ask) -- in ATR units;
  2. the signal's own SL/TP1 first-touch result, in R, with the random
     entries using the same SL and TP distances.

A pool centred on the signal takes out the local trend (in 2024 any BUY
made money); matching the hour takes out session volatility; skipping the
nearest 2 days keeps random entries from sharing the signal's own forward
path. Standard errors are clustered by ISO week, because signals bunch
together and their windows overlap. Last, it checks whether PROB_TP1 and EV
rank signals better than the SL/TP geometry alone does.

    python tools/signal_edge.py bars_XAUUSD_M15_20150102.csv [more.csv ...]
    python tools/signal_edge.py bars.csv --spread 0.40 --split 2021-01-01
    python tools/signal_edge.py --selftest

Stdlib only.
"""

import argparse
import csv
import math
import random
import sys
from collections import defaultdict
from datetime import datetime, timedelta

SIG_FIELDS = ("ENTRY", "SL", "TP1", "TP2", "TP3", "REC_LEVEL", "CONFIDENCE", "EV",
              "RISK_PCT", "PROB_TP1", "PROB_SL", "PROB_N")
REC_NAMES = {0: "STRONG", 1: "ENTRY", 2: "CAUTION", 3: "WAIT", 4: "AVOID", 5: "COUNTER"}
CASE_NAMES = {1: "OBOSBounce", 2: "RegularDiv", 3: "HiddenDiv", 4: "StrongTrend",
              5: "OrangeLevel", 6: "TrendCont", 7: "SidewayBreak", 8: "BasicCross",
              9: "OBOSCross"}
NULL_TPSL_DRAWS = 30      # random entries simulated per signal for the SL/TP1 null


def num(s):
    s = (s or "").strip()
    try:
        return float(s) if s else None
    except ValueError:
        return None


def p_one_sided(t):
    return 0.5 * math.erfc(t / math.sqrt(2.0))


def t_for_p(p):
    lo, hi = 0.0, 10.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if p_one_sided(mid) > p:
            lo = mid
        else:
            hi = mid
    return hi


def parse_row(r):
    """CSV dict -> (high, low, close, bid, ask, buy_case, sell_case, signal fields or None).
    Compact, so a 10-year M15 log fits in memory."""
    bc, sc = int(num(r.get("BUY_CASE")) or 0), int(num(r.get("SELL_CASE")) or 0)
    sig = {k: num(r.get(k)) for k in SIG_FIELDS} if (bc > 0 or sc > 0) else None
    return (float(r["HIGH"]), float(r["LOW"]), float(r["CLOSE"]),
            num(r.get("BID")), num(r.get("ASK")), bc, sc, sig)


def load(paths):
    by_time = {}
    need = {"BAR_TIME", "OPEN", "HIGH", "LOW", "CLOSE", "BID", "ASK", "BUY_CASE", "SELL_CASE"}
    for path in paths:
        with open(path, newline="", encoding="utf-8", errors="replace") as f:
            rd = csv.DictReader(f)
            miss = need - set(rd.fieldnames or ())
            if miss:
                sys.exit("%s: missing column(s) %s -- not an InpResearchLog file?"
                         % (path, ", ".join(sorted(miss))))
            for r in rd:
                try:
                    t = datetime.strptime(r["BAR_TIME"].strip(), "%Y.%m.%d %H:%M")
                    by_time[t] = parse_row(r)     # overlapping runs: the later file wins
                except (ValueError, KeyError, TypeError):
                    continue
    times = sorted(by_time)
    return [by_time[t] for t in times], times


def wilder_atr(h, l, c, period=14):
    out, a = [], None
    for i in range(len(c)):
        tr = h[i] - l[i] if i == 0 else max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1]))
        a = tr if a is None else (a * (period - 1) + tr) / period
        out.append(a)
    return out


class Market:
    """Closed bars in time order, plus the executable quote after each one.

    Row i's BID/ASK were logged at the first tick of bar i+1, so a signal on
    bar i fills at bid[i] / ask[i] and an exit h bars later at bid[i+h] /
    ask[i+h]. OHLC are bid prices.
    """

    def __init__(self, bars, times, spread=None):
        self.t = times
        self.n = len(bars)
        self.h = [b[0] for b in bars]
        self.l = [b[1] for b in bars]
        self.c = [b[2] for b in bars]
        bid = [b[3] for b in bars]
        ask = [b[4] for b in bars]
        spreads = sorted(a - b for a, b in zip(ask, bid) if a and b and a > b)
        med = spreads[len(spreads) // 2] if spreads else 0.0
        self.spread_median = med if spread is None else spread
        self.bid, self.ask = [], []
        for i in range(self.n):
            b = bid[i] if bid[i] and bid[i] > 0 else self.c[i]
            if spread is not None:
                a = b + spread
            else:
                a = ask[i] if ask[i] and ask[i] > b else b + med
            self.bid.append(b)
            self.ask.append(a)
        self.atr = wilder_atr(self.h, self.l, self.c)

    def fwd(self, i, d, h):
        k = i + h
        if k >= self.n or self.atr[i] <= 0:
            return None
        raw = (self.bid[k] - self.ask[i]) if d > 0 else (self.bid[i] - self.ask[k])
        return raw / self.atr[i]

    def first_touch(self, i, d, risk, reward, maxbars):
        """Enter at the quote after bar i with SL `risk` and TP `reward` away.
        Returns (R, kind); kind is tp / sl / amb (both inside one bar, booked
        as SL) / to (timeout, marked to market)."""
        e = self.ask[i] if d > 0 else self.bid[i]
        s = self.ask[i] - self.bid[i]
        end = min(self.n - 1, i + maxbars)
        if d > 0:
            sl, tp = e - risk, e + reward
            for k in range(i + 1, end + 1):
                hs, ht = self.l[k] <= sl, self.h[k] >= tp
                if hs or ht:
                    return (-1.0, "amb") if hs and ht else ((-1.0, "sl") if hs else (reward / risk, "tp"))
            return ((self.bid[end] - e) / risk, "to")
        sl, tp = e + risk, e - reward
        for k in range(i + 1, end + 1):
            hs, ht = self.h[k] + s >= sl, self.l[k] + s <= tp
            if hs or ht:
                return (-1.0, "amb") if hs and ht else ((-1.0, "sl") if hs else (reward / risk, "tp"))
        return ((e - self.ask[end]) / risk, "to")

    def candidates(self, i, near, far, last):
        """Random-entry pool for the signal on bar i: bars more than `near`
        and at most `far` bars away, on both sides, within +-1 clock hour.

        `near` covers the longest forward window, so no random entry's path
        overlaps the signal's own -- otherwise the pool would share in the
        very move being scored. A pool symmetric around the signal cancels
        the local trend; the hour match cancels session volatility."""
        hh = self.t[i].hour
        lo, hi = max(0, i - far), min(last, i + far + 1)
        away = [j for j in range(lo, hi) if abs(j - i) > near]
        pool = [j for j in away if (self.t[j].hour - hh) % 24 in (0, 1, 23)]
        return pool if len(pool) >= 8 else away


def clustered(vals, keys):
    """Mean with a cluster-robust standard error (clusters = ISO weeks)."""
    n = len(vals)
    if n < 2:
        return None
    m = sum(vals) / n
    g = defaultdict(float)
    for v, k in zip(vals, keys):
        g[k] += v - m
    clusters = len(g)
    var = sum(x * x for x in g.values()) / (n * n)
    if clusters > 1:
        var *= clusters / (clusters - 1.0)
    se = math.sqrt(var)
    t = m / se if se > 0 else 0.0
    return dict(n=n, mean=m, se=se, t=t, p=p_one_sided(t), clusters=clusters)


def analyze(bars, times, args):
    mk = Market(bars, times, args.spread)
    horizons = sorted(set(args.horizons))
    near = max(max(horizons), args.maxbars)
    last = mk.n - near - 1
    if last < 200:
        sys.exit("only %d bars -- the backtest is too short for these horizons" % mk.n)
    gaps = sorted((b - a).total_seconds() for a, b in zip(times, times[1:]))
    bars_per_day = 86400.0 / max(60.0, gaps[len(gaps) // 2])
    far = near + int(args.null_days * bars_per_day)
    rng = random.Random(args.seed)
    null_fwd = {(d, h): [mk.fwd(i, d, h) for i in range(last)] for d in (1, -1) for h in horizons}

    sigs = []
    for i in range(last):
        bc, sc, fields = bars[i][5], bars[i][6], bars[i][7]
        if fields is None or mk.atr[i] <= 0:
            continue
        s = dict(i=i, t=times[i], d=1 if bc > 0 else -1, case=bc if bc > 0 else sc)
        s.update(fields)
        iy, iw, _ = times[i].isocalendar()
        s["week"] = (iy, iw)
        cand = mk.candidates(i, near, far, last)
        if not cand:
            continue
        for h in horizons:
            f = null_fwd[(s["d"], h)]
            nv = [f[j] for j in cand if f[j] is not None]
            s["ret%d" % h] = mk.fwd(i, s["d"], h)
            s["null%d" % h] = sum(nv) / len(nv) if nv else None
        s["R"] = None
        if s["SL"] and s["TP1"]:
            e = mk.ask[i] if s["d"] > 0 else mk.bid[i]
            risk, reward = (e - s["SL"]) * s["d"], (s["TP1"] - e) * s["d"]
            if risk > 0 and reward > 0:
                s["risk"], s["reward"] = risk, reward
                s["R"], s["kind"] = mk.first_touch(i, s["d"], risk, reward, args.maxbars)
                draws = cand if len(cand) <= NULL_TPSL_DRAWS else rng.sample(cand, NULL_TPSL_DRAWS)
                res = [mk.first_touch(j, s["d"], risk, reward, args.maxbars) for j in draws]
                s["nullR"] = sum(x[0] for x in res) / len(res)
                dec = [x for x in res if x[1] != "to"]
                s["pnull"] = sum(1 for x in dec if x[1] == "tp") / len(dec) if dec else None
        sigs.append(s)
    return mk, horizons, sigs


def fwd_summary(S, h):
    use = [s for s in S if s.get("ret%d" % h) is not None and s.get("null%d" % h) is not None]
    c = clustered([s["ret%d" % h] - s["null%d" % h] for s in use], [s["week"] for s in use])
    if c:
        c["raw"] = sum(s["ret%d" % h] for s in use) / len(use)
        c["null"] = sum(s["null%d" % h] for s in use) / len(use)
    return c


def tpsl_summary(S):
    use = [s for s in S if s.get("R") is not None]
    c = clustered([s["R"] - s["nullR"] for s in use], [s["week"] for s in use])
    if not c:
        return None
    dec = [s for s in use if s["kind"] != "to"]
    pn = [s["pnull"] for s in dec if s.get("pnull") is not None]
    c["wr"] = sum(1 for s in dec if s["kind"] == "tp") / len(dec) if dec else None
    c["nullwr"] = sum(pn) / len(pn) if pn else None
    c["be"] = sum(s["risk"] / (s["risk"] + s["reward"]) for s in use) / len(use)
    c["R"] = sum(s["R"] for s in use) / len(use)
    c["nullR"] = sum(s["nullR"] for s in use) / len(use)
    c["to"] = sum(1 for s in use if s["kind"] == "to") / len(use)
    c["amb"] = sum(1 for s in use if s["kind"] == "amb") / len(use)
    return c


def auc(scores, labels):
    pairs = sorted(zip(scores, labels))
    npos = sum(y for _, y in pairs)
    nneg = len(pairs) - npos
    if npos == 0 or nneg == 0:
        return None
    rank_sum, i = 0.0, 0
    while i < len(pairs):
        j = i
        while j + 1 < len(pairs) and pairs[j + 1][0] == pairs[i][0]:
            j += 1
        r = (i + j) / 2.0 + 1
        rank_sum += r * sum(y for _, y in pairs[i:j + 1])
        i = j + 1
    return (rank_sum - npos * (npos + 1) / 2.0) / (npos * nneg)


def calibration(S):
    use = [s for s in S if s.get("R") is not None and s["kind"] != "to" and s.get("PROB_TP1") is not None]
    if len(use) < 30:
        return None
    y = [1 if s["kind"] == "tp" else 0 for s in use]
    ybar = sum(y) / len(y)
    pm = [min(max(s["PROB_TP1"] / 100.0, 0.0), 1.0) for s in use]
    pn = [s["pnull"] if s.get("pnull") is not None else ybar for s in use]
    bs = lambda p: sum((a - b) ** 2 for a, b in zip(p, y)) / len(y)
    return dict(n=len(use), ybar=ybar, bs_model=bs(pm), bs_null=bs(pn), bs_clim=ybar * (1 - ybar),
                auc_model=auc(pm, y), auc_null=auc(pn, y), pm=pm, y=y)


def hlabel(h, bar_min):
    m = h * bar_min
    return "%dm" % m if m < 60 else ("%gh" % (m / 60.0) if m < 1440 else "%gd" % (m / 1440.0))


def fcell(c):
    if not c:
        return "%5s %6s %6s %7s %5s" % ("-", "-", "-", "-", "-")
    return "%5d %6.3f %6.3f %+7.3f %5.2f" % (c["n"], c["raw"], c["null"], c["mean"], c["t"])


def report(mk, horizons, S, args):
    bar_min = max(1, round(sorted((b - a).total_seconds() / 60.0
                                  for a, b in zip(mk.t, mk.t[1:]))[len(mk.t) // 2]))
    mh = args.main_h if args.main_h in horizons else horizons[len(horizons) // 2]
    buys = [s for s in S if s["d"] > 0]
    sells = [s for s in S if s["d"] < 0]
    print("=" * 108)
    print("bars %d  %s -> %s  (%d-min)   signals %d  (BUY %d / SELL %d)   spread $%.3f%s   SL/TP window %d bars"
          % (mk.n, mk.t[0].strftime("%Y-%m-%d"), mk.t[-1].strftime("%Y-%m-%d"), bar_min, len(S),
             len(buys), len(sells), mk.spread_median,
             " (--spread)" if args.spread is not None else " (median logged)", args.maxbars))
    print("null = random entries, same direction, same clock hour +-1, from %d bars up to %g days on either"
          " side (no overlap with the signal's own window); t-stats clustered by ISO week"
          % (max(max(horizons), args.maxbars), args.null_days))

    print("\n1. FORWARD RETURN vs RANDOM ENTRY  (ATR units, net of spread)")
    print("   horizon |  BUY:  n    raw   null  excess     t |  SELL: n    raw   null  excess     t |"
          "  ALL: excess     t       p")
    for h in horizons:
        a = fwd_summary(S, h)
        tail = ("%+12.3f %5.2f %7.4f" % (a["mean"], a["t"], a["p"])) if a else ""
        print("   %-7s | %s | %s | %s" % (hlabel(h, bar_min), fcell(fwd_summary(buys, h)),
                                          fcell(fwd_summary(sells, h)), tail))

    print("\n2. SL / TP1 FIRST TOUCH  (R multiples; null = same SL/TP distances from random entries)")
    print("            n     WR  nullWR   BE-WR   meanR   nullR  excess     t       p  timeout   amb")
    for name, sub in (("BUY", buys), ("SELL", sells), ("ALL", S)):
        c = tpsl_summary(sub)
        if not c:
            print("   %-5s  (no SL/TP data)" % name)
            continue
        print("   %-5s %5d  %5.1f%%  %5.1f%%  %5.1f%%  %+6.3f  %+6.3f  %+6.3f %5.2f %7.4f   %5.1f%% %4.1f%%"
              % (name, c["n"], 100 * (c["wr"] or 0), 100 * (c["nullwr"] or 0), 100 * c["be"],
                 c["R"], c["nullR"], c["mean"], c["t"], c["p"], 100 * c["to"], 100 * c["amb"]))

    print("\n3. DO PROB_TP1 AND EV CARRY INFORMATION?")
    cal = calibration(S)
    if not cal:
        print("   fewer than 30 decided signals with PROB_TP1 -- skipped")
    else:
        skill = 1 - cal["bs_model"] / cal["bs_null"] if cal["bs_null"] > 0 else 0.0
        print("   Brier  model %.4f | SL/TP geometry alone %.4f | base rate %.4f   -> skill vs geometry %+.1f%%"
              % (cal["bs_model"], cal["bs_null"], cal["bs_clim"], 100 * skill))
        print("   AUC    model %s | SL/TP geometry alone %s   (0.5 = no ranking power)"
              % ("%.3f" % cal["auc_model"] if cal["auc_model"] is not None else "-",
                 "%.3f" % cal["auc_null"] if cal["auc_null"] is not None else "-"))
        print("   PROB_TP1 bucket      n   said   got")
        for lo, hi in ((0, 45), (45, 55), (55, 65), (65, 75), (75, 101)):
            idx = [k for k, p in enumerate(cal["pm"]) if lo <= 100 * p < hi]
            if idx:
                print("   %3d-%-3d%%        %5d  %4.0f%%  %4.0f%%"
                      % (lo, min(hi, 100), len(idx), 100 * sum(cal["pm"][k] for k in idx) / len(idx),
                         100 * sum(cal["y"][k] for k in idx) / len(idx)))
    ev_rows = [s for s in S if s.get("R") is not None and s.get("EV") is not None]
    if ev_rows:
        print("   EV bucket (R)        n   meanR  excessR     t")
        for lo, hi, lab in ((-9e9, 0, "< 0"), (0, 0.1, "0-0.1"), (0.1, 0.3, "0.1-0.3"), (0.3, 9e9, ">= 0.3")):
            sub = [s for s in ev_rows if lo <= s["EV"] < hi]
            c = tpsl_summary(sub)
            if c:
                print("   %-10s     %5d  %+6.3f  %+6.3f  %5.2f" % (lab, c["n"], c["R"], c["mean"], c["t"]))

    print("\n4. BREAKDOWN  (forward excess at %s in ATR; SL/TP1 excess in R)" % hlabel(mh, bar_min))
    if args.split:
        cut = datetime.strptime(args.split, "%Y-%m-%d")
        period = lambda s: ("< " if s["t"] < cut else ">= ") + args.split
    else:
        period = lambda s: str(s["t"].year)
    rec = lambda s: REC_NAMES.get(int(s["REC_LEVEL"]), "?") if s.get("REC_LEVEL") is not None else "n/a"
    groups = (("direction x case", lambda s: "%s %d %s" % ("BUY " if s["d"] > 0 else "SELL", s["case"],
                                                            CASE_NAMES.get(s["case"], ""))),
              ("rec level", rec),
              ("server hour", lambda s: "%02d-%02d" % (4 * (s["t"].hour // 4), 4 * (s["t"].hour // 4) + 3)),
              ("period", period))
    tested = 0
    for gname, key in groups:
        buckets = defaultdict(list)
        for s in S:
            buckets[key(s)].append(s)
        print("   %-24s     n   fwd excess     t |    WR  nullWR  excessR     t" % gname)
        for lab in sorted(buckets):
            sub = buckets[lab]
            if len(sub) < args.min_n:
                print("     %-22s %5d   (n < %d)" % (lab, len(sub), args.min_n))
                continue
            f, c = fwd_summary(sub, mh), tpsl_summary(sub)
            tested += 2
            print("     %-22s %5d   %+8.3f  %5.2f | %s"
                  % (lab, len(sub), f["mean"] if f else 0, f["t"] if f else 0,
                     "%5.1f%%  %5.1f%%  %+7.3f  %5.2f" % (100 * (c["wr"] or 0), 100 * (c["nullwr"] or 0),
                                                           c["mean"], c["t"]) if c else "-"))
    if tested:
        print("   %d tests above: at 5%% family-wise (Bonferroni) a cell needs t > %.2f, not 1.65."
              % (tested, t_for_p(0.05 / tested)))

    print("\nVERDICT")
    f, c = fwd_summary(S, mh), tpsl_summary(S)
    years = defaultdict(list)
    for s in S:
        years[period(s)].append(s)
    per = [fwd_summary(v, mh) for v in years.values() if len(v) >= args.min_n]
    per = [x for x in per if x]
    pos = sum(1 for x in per if x["mean"] > 0)
    if f:
        print("   forward @%s : excess %+.3f ATR   t %.2f   p %.4f" % (hlabel(mh, bar_min), f["mean"], f["t"], f["p"]))
    if c:
        print("   SL/TP1     : excess %+.3f R     t %.2f   p %.4f" % (c["mean"], c["t"], c["p"]))
    if per:
        print("   periods with positive forward excess: %d / %d" % (pos, len(per)))
    sig = (f and f["t"] >= 1.96) or (c and c["t"] >= 1.96)
    if not sig:
        print("   -> no evidence the signal times entries better than random entries in the same week and hour.")
    elif per and pos < len(per) * 0.75:
        print("   -> significant on the pooled sample but not stable across periods -- unproven.")
    else:
        print("   -> evidence of a timing edge. Confirm on data that was not used to design the indicator.")
    print("=" * 108)


def dump(S, horizons, path):
    cols = ["time", "dir", "case", "rec", "prob_tp1", "ev"]
    for h in horizons:
        cols += ["ret%d" % h, "null%d" % h]
    cols += ["kind", "R", "nullR", "pnull"]
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for s in S:
            row = [s["t"].strftime("%Y-%m-%d %H:%M"), s["d"], s["case"], s.get("REC_LEVEL"),
                   s.get("PROB_TP1"), s.get("EV")]
            for h in horizons:
                row += [s.get("ret%d" % h), s.get("null%d" % h)]
            row += [s.get("kind"), s.get("R"), s.get("nullR"), s.get("pnull")]
            w.writerow(["" if v is None else (round(v, 5) if isinstance(v, float) else v) for v in row])
    print("per-signal table -> %s" % path)


def synth(seed, drift, edge, nbars=40000, boost_bars=48):
    """Random-walk M15 bars with signals at random bars. With edge > 0 half
    the signals are followed by `edge` of extra drift per bar for boost_bars
    bars in their direction, and only those get PROB_TP1 = 70."""
    rng = random.Random(seed)
    t, step, p = datetime(2021, 1, 4), timedelta(minutes=15), 2000.0
    rows, times, boost, bdir = [], [], 0, 0
    for _ in range(nbars):
        while t.weekday() >= 5:
            t += step
        mu = drift + (edge * bdir if boost > 0 else 0.0)
        boost = max(0, boost - 1)
        path = [p]
        for _ in range(3):
            path.append(path[-1] + rng.gauss(mu / 3.0, 1.0 / math.sqrt(3.0)))
        o, c = p, path[-1]
        hi = max(path) + abs(rng.gauss(0, 0.2))
        lo = min(path) - abs(rng.gauss(0, 0.2))
        row = {"BAR_TIME": t.strftime("%Y.%m.%d %H:%M"), "OPEN": "%.3f" % o, "HIGH": "%.3f" % hi,
               "LOW": "%.3f" % lo, "CLOSE": "%.3f" % c, "BID": "%.3f" % c, "ASK": "%.3f" % (c + 0.3),
               "BUY_CASE": "0", "SELL_CASE": "0"}
        if rng.random() < 0.02:
            d = 1 if rng.random() < 0.5 else -1
            row["BUY_CASE" if d > 0 else "SELL_CASE"] = "1"
            boosted = edge > 0 and rng.random() < 0.5
            if boosted:
                boost, bdir = boost_bars, d
            row.update(SL="%.3f" % (c - d * 6.0), TP1="%.3f" % (c + d * 6.0),
                       PROB_TP1="70" if boosted else ("40" if edge > 0 else rng.choice(("40", "70"))), EV="0")
        rows.append(parse_row(row))
        times.append(t)
        p = c
        t += step
    return rows, times


def selftest():
    """The method must (a) NOT call a strong trend an edge -- a naive test
    would, since every BUY wins in a rising market -- and (b) find an edge
    that is really there, in both the forward-return and the SL/TP tests,
    and see that PROB_TP1 ranks the good signals."""
    args = argparse.Namespace(horizons=[1, 4, 16, 96], main_h=16, maxbars=192, spread=None,
                              seed=1, split=None, min_n=30, null_days=10)
    ok = True
    for seed in (11, 12, 13):
        bars, times = synth(seed, drift=0.03, edge=0.0)
        mk, hs, S = analyze(bars, times, args)
        raw = fwd_summary([s for s in S if s["d"] > 0], 96)["raw"]
        f, c, cal = fwd_summary(S, 16), tpsl_summary(S), calibration(S)
        good = raw > 0.3 and abs(f["t"]) < 3 and abs(c["t"]) < 3 and abs(cal["auc_model"] - 0.5) < 0.06
        ok &= good
        print("no edge, gold-like trend %+.0f%% (seed %d): BUY raw 1d %+.2f ATR, but excess fwd t %+.2f,"
              " SL/TP t %+.2f, AUC %.3f  %s" % (100 * (bars[-1][2] / 2000 - 1), seed, raw, f["t"], c["t"],
                                                cal["auc_model"], "PASS" if good else "FAIL"))
    # Detection bar: t > 2 on both tests, AUC > 0.54 (the no-edge runs sit
    # within 0.5 +- 0.02). The generator's ceiling is about AUC 0.61 before
    # overlapping signals dilute it, so demanding more would test the
    # generator, not the method.
    # Every synthetic signal has the same SL/TP distances, so the geometry-only
    # baseline must have no ranking power (AUC ~0.5). If it ranks, random
    # entries are leaking the signal's own outcome -- the pool overlaps its path.
    for seed in (21, 22):
        bars, times = synth(seed, drift=0.0, edge=0.08)
        mk, hs, S = analyze(bars, times, args)
        f, c, cal = fwd_summary(S, 16), tpsl_summary(S), calibration(S)
        good = (f["t"] > 2 and c["t"] > 2 and cal["auc_model"] > 0.54
                and abs(cal["auc_null"] - 0.5) < 0.06)
        ok &= good
        print("planted edge (seed %d): fwd excess %+.3f ATR (t %.2f), SL/TP1 excess %+.3f R (t %.2f),"
              " AUC model %.3f / geometry %.3f  %s" % (seed, f["mean"], f["t"], c["mean"], c["t"],
                                                      cal["auc_model"], cal["auc_null"],
                                                      "PASS" if good else "FAIL"))
    print("selftest %s" % ("PASSED" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="Does the signal predict price better than random entries?")
    ap.add_argument("files", nargs="*", help="research log CSV(s) from InpResearchLog")
    ap.add_argument("--horizons", default="1,4,16,96", help="forward horizons in bars (default 1,4,16,96)")
    ap.add_argument("--main-h", type=int, default=16, help="horizon used in the breakdown and verdict")
    ap.add_argument("--maxbars", type=int, default=192, help="bars an SL/TP1 trade may stay open")
    ap.add_argument("--spread", type=float, default=None, help="override the logged spread ($ per unit)")
    ap.add_argument("--split", default=None, help="YYYY-MM-DD: two periods instead of calendar years")
    ap.add_argument("--min-n", type=int, default=30, help="smallest breakdown cell reported")
    ap.add_argument("--null-days", type=float, default=10,
                    help="random entries are drawn up to this many days beyond the signal's window")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--dump", default=None, help="write the per-signal table to this CSV")
    ap.add_argument("--selftest", action="store_true", help="check the method on synthetic data")
    args = ap.parse_args()
    if args.selftest:
        sys.exit(selftest())
    if not args.files:
        ap.error("give at least one research log CSV (or --selftest)")
    args.horizons = [int(x) for x in args.horizons.split(",") if x.strip()]
    rows, times = load(args.files)
    mk, horizons, S = analyze(rows, times, args)
    if not S:
        sys.exit("no signals in the log -- was InpResearchLog on and the indicator loading?")
    report(mk, horizons, S, args)
    if args.dump:
        dump(S, horizons, args.dump)


if __name__ == "__main__":
    main()
