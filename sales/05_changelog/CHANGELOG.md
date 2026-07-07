# RSI Advanced — Changelog for MQL5 Market

## v11.36 (2026-07-01)
- Added Case 9: OB/OS Raw Crossover (plain green-cross-red in OB/OS zone)
- Added AngIC diagnostic panel: shows infoCoeff + icSamples for angle edge per symbol/TF
- Added OS-Cross monitor markers (debug overlay, default OFF)
- Fixed dual-indexing scheme to support up to 9 cases without OOB crash

## v11.35 (2026-07-01)
- Dead code cleanup: removed all unreachable branches confirmed by static analysis
- Verified all priority table items fully implemented (S1-S9 pipeline complete)
- MTF throttle optimized for MQL4 performance

## v11.31 (2026-06-10)
- Signal logging enabled by default (InpEnableSignalLog = true)
- RAM Queue + Bulk Flush anti-lag system for CSV logger
- Walk-Forward calibration rolling window stabilized
- Session Statistics binary file invalidation warning added

## v11.20 (2026-05-xx)
- Brier Score calibration engine complete (S1-S6)
- IC gate: suppress signals below IC threshold
- Kelly Criterion panel display
- MTF confirmation gate (optional)

## v10.20 (2026-04-xx)
- Dual-platform build pipeline (mq4 + mq5 from shared Include/)
- MQLCompat.mqh layer for MT4/MT5 code sharing
- Initial 8-case signal detection engine
- Session quality filter (London/NY/Overlap/Asian)
