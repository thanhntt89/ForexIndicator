# RSI Advanced — Product Description (MQL5 Market)
> **Paste this into the MQL5 Market "Description" field.**
> Price: $49 permanent | $19/month | $39/3 months

---

## RSI Advanced v10 — 9-Case Probabilistic RSI Signal Engine

**Most RSI indicators just draw a line. RSI Advanced tells you *whether* the signal has a real statistical edge — before you trade it.**

RSI Advanced is a professional-grade signal indicator that detects **9 distinct RSI market patterns**, estimates the **real win probability** of each signal using a Bayesian calibration engine, and automatically suppresses low-quality setups. Fully compatible with **MetaTrader 4 and MetaTrader 5**.

---

### ⚡ Why RSI Advanced is Different

Standard RSI crossover systems generate signals on every bar. RSI Advanced only shows a signal when **three independent gates** agree:

1. **Pattern Gate** — One of 9 statistically-defined RSI cases must match
2. **Probability Gate** — Bayesian win rate must exceed the minimum IC threshold
3. **Regime Gate** — Market session, volatility, and spread conditions must be favorable

If any gate fails, the panel clearly displays **"No Edge"** or **"WAIT"** — so you never guess.

---

### 📊 9 Signal Cases — Each Validated Independently

| Case | Pattern | Best Timeframe |
|------|---------|----------------|
| **Case 1** | OB/OS Bounce — reversal from extreme RSI zone | M15, H1 |
| **Case 2** | Divergence — price vs RSI diverge | H1, H4 |
| **Case 3** | Trend Continuation — RSI retest with momentum | M5, M15 |
| **Case 4** | Breakout Confirmation — RSI breakout with angle | M15, H1 |
| **Case 5** | Hidden Divergence — pullback in trend | M30, H1 |
| **Case 6** | Angle Continuation — steep green/red cross | M1, M5 |
| **Case 7** | Sideways Breakout — RSI escapes ranging zone | M5, M15 |
| **Case 8** | OB/OS Steep Crossover — strong angle required | M15, H1 |
| **Case 9** | Raw OB/OS Cross — self-adapting baseline | M15+ |

Each case can be **enabled/disabled individually** so you only trade patterns you understand.

---

### 🧠 Probability Engine — Know Your Edge Before Every Trade

RSI Advanced continuously tracks the outcome of every signal and updates a live probability model using:

- **Bayesian Calibration** — win rate estimate corrected for sample size
- **Information Coefficient (IC)** — measures signal predictive power (hidden when IC < 0.05)
- **Walk-Forward Window** — rolling re-train prevents curve-fitting to stale data
- **Brier Score** — objective calibration quality metric, shown on panel
- **Kelly Criterion** — optional position size suggestion based on measured edge

The panel displays: `Win: 52.4% | Loss: 47.6%` and `Prob [n=200]` so you always know the statistical basis.

---

### 📐 Smart SL/TP — Three Methods

| Method | Description |
|--------|-------------|
| **ATR-based** | Wilder ATR × ratio (default, adaptive to volatility) |
| **Fibonacci** | Key Fibonacci levels projected from signal bar |
| **Hybrid** | ATR confirmation + Fibonacci targets combined |

Three TP levels (TP1, TP2, TP3) are drawn automatically on the chart.

---

### 📡 Multi-Timeframe Confirmation (MTF)

RSI is independently calculated on **M30, H1, H4, D1** simultaneously. The panel shows each TF trend direction and an overall alignment score.

Trade only when TFs agree for the highest-confidence setups.

---

### 📋 Real-Time Info Panel

- Signal direction + Case number + Pattern name
- Estimated win probability with sample count
- SL distance in pips + R:R ratio
- Entry zones (multi-level, shaded on chart)
- Session quality: London / New York / Overlap / Asian
- Spread regime warning (high spread = signal suppressed)
- Portfolio risk tracker

---

### 📁 CSV Signal Logger

Every signal is automatically logged to a CSV file with: timestamp, case, session, RSI value, SL/TP prices, and outcome (auto-tracked). RAM queue + bulk flush — **zero chart lag**.

---

### ⚙️ Key Input Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `InpRSIPeriod` | RSI period | 14 |
| `InpEnableCase1..9` | Enable/disable each case individually | true |
| `InpSLRatio` | ATR multiplier for Stop Loss | 2.0 |
| `InpTPRatio` | ATR multiplier for Take Profit 1 | 4.0 |
| `InpShowMTF` | Enable Multi-Timeframe panel | true |
| `InpShowProbability` | Show probability section | true |
| `InpProbMode` | Bayesian / XGBoost / Ensemble | Ensemble |
| `InpAlertPopup` | Alert on new signal | true |
| `InpEAMode` | Disable visuals for EA use via iCustom | false |
| `InpAutoTFConfig` | Auto-tune parameters per timeframe | true |

---

### 🎯 Recommended Usage

| Style | Timeframe | Cases |
|-------|-----------|-------|
| Scalping | M1, M5 | Case 6, 7, 9 |
| Intraday | M15, M30 | Case 1, 3, 8 |
| Swing | H1, H4 | Case 2, 4, 5 |
| Best asset | **XAUUSD (Gold)** — extensively tested on live data |

---

### ✅ Platform & Requirements

- **MetaTrader 4** and **MetaTrader 5**
- **No DLLs required**, no external data feeds, no internet connection needed
- Compatible with all brokers and all symbols

---

### 💬 FAQ

**Q: Is this a repaint indicator?**
No. Signals are confirmed only on **closed bars**. The forming bar shows a provisional signal that is removed if conditions fail at close.

**Q: Can I use this with an EA?**
Yes. Set `InpEAMode = true`. Read buffers via `iCustom()`: buffer 5 = BuySignal case, buffer 6 = SellSignal case, buffers 7-10 = Entry / SL / TP1 / TP2 prices.

**Q: Does it work on all pairs?**
Yes. Symbol-agnostic. Best results observed on **XAUUSD** (Gold). Works on Forex, indices, and crypto.

**Q: What is "No Edge"?**
When the Bayesian gate determines the signal has no statistically significant edge (IC below threshold or insufficient samples), the panel shows "No Edge" and suppresses entry zones. This prevents trading marginal setups.

---

### 📦 Pricing

| Option | Price |
|--------|-------|
| **Permanent license** | **$49** |
| **Rent 1 month** | $19 |
| **Rent 3 months** | $39 |

---

*Version 10.20 | MT4 + MT5 | Last updated: July 2026 | Master Trading Wave*
