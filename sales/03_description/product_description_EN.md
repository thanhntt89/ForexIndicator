# RSI Advanced — Product Description (MQL5 Market)
> Paste this into the MQL5 Market "Description" field.
> Supports both MT4 and MT5.

---

## RSI Advanced v11 — Smart Multi-Case RSI Signal Indicator

**RSI Advanced** is not a standard RSI indicator. It is a **probabilistic signal engine** built on top of RSI that detects 9 distinct market scenarios (Cases), self-calibrates signal confidence using **Bayesian probability & Information Coefficient (IC)**, and adapts to real market regimes in real time.

Compatible with **MetaTrader 4 (MT4)** and **MetaTrader 5 (MT5)**.

---

### 9 Signal Cases — Each Statistically Validated Independently

| Case | Description                           | Best Timeframe |
|------|---------------------------------------|---------------|
| Case 1 | OB/OS Bounce (reversal from extreme) | M15+         |
| Case 2 | Divergence (price vs RSI)            | H1+           |
| Case 3 | Trend Continuation                   | M5, M15       |
| Case 4 | Breakout Confirmation                | M15, H1       |
| Case 5 | Hidden Divergence (pull-back)        | M30+          |
| Case 6 | Trend Continuation (angle-based)     | M1, M5        |
| Case 7 | Sideway Breakout                     | M5, M15       |
| Case 8 | OB/OS Crossover (steep angle)        | M15, H1       |
| Case 9 | OB/OS Raw Crossover (self-measuring) | M15+          |

---

### Adaptive Probability Engine
- Walk-Forward Calibration: continuously re-trains on live results using a rolling window
- Brier Score & IC Gate: signals shown only when IC >= 0.05 and n >= 20 samples
- Kelly Criterion display: optional optimal position size suggestion based on measured edge

### Quantitative Panel
- Real-time probability estimate, IC coefficient, sample count per case
- Color-coded: Strong / Weak / Inverse / Noise / n.a.
- Session quality filter: London / New York / Overlap / Asian

### Multi-Timeframe Awareness
- Each timeframe computes RSI independently (true MTF behavior)
- Built-in MTF confirmation gate (optional)
- Session-based signal quality adjustment

### Trade History Logger (CSV)
- Logs every signal: Case, RSI at signal, Session, SL/TP levels, MFE, MAE
- RAM Queue + Bulk Flush — zero chart lag

---

### Inputs & Configuration

| Parameter              | Description                                     | Default |
|------------------------|-------------------------------------------------|---------|
| InpRSI_Period          | RSI period                                      | 14      |
| InpEnableCase1..9      | Enable/disable each case individually           | true    |
| InpMinIC               | Minimum IC threshold to show signal             | 0.05    |
| InpMinSamples          | Minimum sample count for calibration            | 20      |
| InpSessionFilter       | Enable session quality filter                   | true    |
| InpEnableSignalLog     | Enable CSV logging                              | true    |

---

### Platform Requirements
- MetaTrader 4 or MetaTrader 5
- Windows (MT4/MT5 native)
- No DLLs required, no external data feeds

---

### Recommended Usage
- Scalping: M1, M5 — Case 6, Case 7
- Intraday: M15, M30 — Case 1, Case 3, Case 8
- Swing entries: H1, H4 — Case 2, Case 5
- Best asset: XAUUSD (Gold) — extensively tested

---

Version: 11.36 | Last updated: July 2026
