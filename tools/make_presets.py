#!/usr/bin/env python3
"""
make_presets.py -- write MT4 .set files for the W1/W2 verification runs.

Every input is copied verbatim from the Parameters block of a tester report,
so W1 reproduces that run exactly and W2 differs from it ONLY in the S1-S3
inputs listed below. That keeps the comparison a controlled experiment.

    python tools/make_presets.py logs/StrategyTester1.htm
    # -> presets/W1_baseline.set, presets/W2_S1B.set

Load in MT4: Strategy Tester -> Expert properties -> Inputs -> Load.
Stdlib only.
"""

import html
import re
import sys
from pathlib import Path

# backtest_review_2024.md section 10.3, S0 + S1-B + S2 + S3
W2_OVERRIDES = {
    # S0: the analysed baskets had DCA-1 at ~50% of SL (median $3.18 from entry),
    # which only a $1.50 spacing floor allows. 150 = $1.50 on any feed since the
    # ptscale build; 1500 ($15) would block DCA-1 on almost every basket.
    "InpDCAMinSpacingPts": "150",
    "InpNegDCAMaxOrders": "1",
    "InpUsePositiveDCA": "false",
    "InpNegDCAMaxDDPct": "6",
    "InpUseDCABackstopSL": "true",
    "InpMinLotSize": "0.01",
    "InpMaxLotSize": "0.5",
    "InpUseDailyLossCap": "true",
    "InpMaxDailyLossPct": "8",
    "InpUseWeeklyDDStop": "true",
    "InpMaxWeeklyDDPct": "12",
    "InpUseMonthlyDDStop": "true",
    "InpMaxMonthlyDDPct": "18",
}


def read_params(report):
    text = Path(report).read_text(encoding="utf-8", errors="replace")
    m = re.search(r"Parameters</td>\s*<td[^>]*>(.*?)</td>", text, re.S | re.I)
    if not m:
        sys.exit("No Parameters block in %s" % report)
    raw = html.unescape(re.sub(r"<[^>]+>", "", m.group(1)))
    params = []
    for item in raw.split(";"):
        item = item.strip()
        if "=" not in item:
            continue
        k, v = item.split("=", 1)
        params.append((k.strip(), v.strip().strip('"')))
    return params


def write_set(path, params, overrides, header):
    keys = {k for k, _ in params}
    missing = [k for k in overrides if k not in keys]
    if missing:
        sys.exit("Override keys not in report (renamed input?): %s" % ", ".join(missing))
    lines = ["; %s" % h for h in header]
    for k, v in params:
        if k.startswith("inp_grp_"):
            continue
        lines.append("%s=%s" % (k, overrides.get(k, v)))
    path.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    params = read_params(sys.argv[1])
    out = Path(__file__).resolve().parent.parent / "presets"
    out.mkdir(exist_ok=True)

    common = ["Source: %s" % Path(sys.argv[1]).name,
              "Tester: XAUUSD M15, 2024.02.01-2024.12.31, Every tick",
              "Tester spread: 40 on a 2-digit symbol, 400 on a 3-digit symbol (= $0.40)",
              "Needs EA build 2026-09-25.2-ptscale or later (point inputs auto-scale)"]
    write_set(out / "W1_baseline.set", params, {},
              ["W1: current preset unchanged, at realistic spread.",
               "With the ptscale build this is the EA that runs LIVE ($15 DCA spacing),",
               "not the one in the old 3-digit report ($1.50) -- results will differ."] + common)
    write_set(out / "W2_S1B.set", params, W2_OVERRIDES,
              ["W2: W1 + S0/S1-B/S2/S3 (backtest_review_2024.md 10.3)",
               "Changed vs W1: " + ", ".join("%s=%s" % kv for kv in W2_OVERRIDES.items())]
              + common)
    print("wrote %s and %s" % (out / "W1_baseline.set", out / "W2_S1B.set"))


if __name__ == "__main__":
    main()
