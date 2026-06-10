# RSI Advanced - Probability Algorithm Report

> Version: V10.20 | Date: 2026-06-10
> File: `Include/RSI_Advanced/ProbabilityEngine.mqh`
> Dependencies: `Normalize.mqh`, `MathUtils.mqh`, `IntermarketAnalysis.mqh`, `SessionStatistics.mqh`, `WalkForward.mqh`

---

## 1. Pipeline Overview

The probability engine operates as a **6-step sequential pipeline**. Each step transforms or refines the output from the previous step. The final output is a set of probabilities: `probTP1`, `probTP2`, `probTP3`, `probSL` where `probTP1 + probSL = 100%`.

```
Signal Input
    |
    v
[Step 1] Historical Simulation (3 Tiers)
    |   -> histTP1, histSL, avgBarsToTP1, avgBarsToSL
    v
[Step 2] Edge Measurement
    |   -> measuredEdge (0.48 - 0.62)
    v
[Step 3] Edge Adjustments (MTF + Intermarket + Angle + Vol-Regime)
    |   -> adjustedEdge (0.48 - 0.65)
    v
[Step 4] Theoretical Probability (Gambler's Ruin + Market Corrections)
    |   -> theoTP1, theoTP2, theoTP3
    v
[Step 5] Bayesian Combine (Historical + Theoretical)
    |   -> probTP1 (combined)
    |
    +--[Step 5.5] Confidence Adjustments (Price Confirm + ATR Spike)
    +--[Step 5.6] Session Quality (Bayesian blend with measured WR)
    +--[Step 5.7] Time-Decay / Survival Analysis (Weibull model)
    |
    v
[Step 6] Final Normalize
    |   -> probTP1 + probSL = 100%, TP2 <= TP1, TP3 <= TP2
    v
Output: g_currentProb
```

---

## 2. Data Sources Used in Probability Calculation

### 2.1 Primary Data Sources

| # | Data Source | Type | Used In | Config Parameter |
|---|-----------|------|---------|-----------------|
| 1 | Stored Signals (`g_signals[]`) | Internal array | Step 1 Tier 1+2, Step 2 | `InpMaxBars` (scan range) |
| 2 | Historical Price Bars (`iHigh/iLow/iOpen/iClose`) | MT4/MT5 bar data | Step 1 Tier 3, Step 2, Step 5.5 | `InpProbMaxBars` |
| 3 | RSI Indicator (`iRSI`) | Technical indicator | Step 1 Tier 3, Step 2 | `InpRSIPeriod`, `InpPrice` |
| 4 | ATR Indicator (`iATR`) | Technical indicator | Steps 1-5, Vol-Regime | `InpATRPeriod` |
| 5 | MTF Data (`g_mtfData[]`) | Multi-TF analysis | Step 3 | `InpShowMTF` |
| 6 | Intermarket Data (`g_intermarket`) | DXY/EURUSD | Step 3 | `InpUseIntermarket` |
| 7 | Signal Outcomes (`g_outcomes[]`) | Tracked results | Step 5.6 | `InpEnableSignalLog` |
| 8 | Session Statistics (`g_sessionStats`) | Per-session WR | Step 5.6 | Automatic |
| 9 | Walk-Forward Data (`g_walkForward`) | IS/OOS split | Step 2, Step 3 | `InpUseWalkForward` |
| 10 | Vol-Regime (`g_volRegime`) | ATR ratio classifier | Step 3 | Automatic |
| 11 | Spread Regime (`g_spreadRegime`) | Spread monitor | Step 4 | `InpUseSpreadRegime` |
| 12 | Angle Strength (Z-score) | Per-signal metric | Step 1 Tier 3, Step 3 | `InpAngleThreshold` |

### 2.2 Secondary/Context Data

| # | Data Source | Purpose |
|---|-----------|---------|
| 13 | Broker GMT Offset | H4+ candle normalization |
| 14 | Fat-Tail Kurtosis (500 bars) | Market correction in Gambler's Ruin |
| 15 | Volatility Autocorrelation (200 bars) | Vol-cluster penalty |
| 16 | Live Spread (`MODE_SPREAD`) | Spread drag correction |
| 17 | Signal Time (`signalTime`) | Session block, time-decay |
| 18 | Signal Case Number | Tier 1 filtering, session WR lookup |

---

## 3. Sample Size Configuration

### 3.1 Minimum Samples Required (`GetMinSamplesForTimeframe`)

The system dynamically adjusts minimum sample thresholds based on timeframe, because higher TFs generate fewer signals:

| Timeframe | Min Samples | Min Bayesian (1/3) | Rationale |
|-----------|-------------|---------------------|-----------|
| M1 | 50 | 17 | High frequency, many signals available |
| M5 | 40 | 14 | Moderate frequency |
| M15 | 30 | 10 | Standard intraday |
| M30 | 25 | 9 | Fewer signals per day |
| H1 | 20 | 7 | ~24 bars/day |
| H4 | 15 | 5 | ~6 bars/day |
| D1+ | 10 | 4 | 1 bar/day, data scarce |

**Min Bayesian** = threshold for using historical data in Bayesian combine (Step 5). Below this, only theoretical probability is used.

### 3.2 Maximum Forward Bars for Simulation (`GetMaxForwardBarsForTimeframe`)

| Timeframe | Max Forward Bars | Equivalent Time |
|-----------|-----------------|-----------------|
| M1 | 40 | ~40 minutes |
| M5 | 50 | ~4 hours |
| M15 | 60 | ~15 hours |
| M30 | 60 | ~30 hours |
| H1 | 80 | ~3.3 days |
| H4 | 60 | ~10 days |
| D1+ | 100 | ~100 days |

### 3.3 Maximum Lookback for Tier 3 Scan (`GetMaxLookbackForTimeframe`)

Base cap scaled by `sqrt(available_bars / 5000)`, capped at 2.5x:

| Timeframe | Base Cap | Max (with scaling) |
|-----------|----------|-------------------|
| M1 | 300 | 750 |
| M5 | 250 | 625 |
| M15 | 200 | 500 |
| M30 | 200 | 500 |
| H1 | 150 | 375 |
| H4 | 120 | 300 |
| D1+ | 100 | 250 |

### 3.4 Effective Probability Max Bars (`GetEffectiveProbMaxBars`)

```
Input: InpProbMaxBars (default: 1000)
Auto:  min(available × 0.8, 30000)
Final: max(InpProbMaxBars, Auto)
```

### 3.5 Recency Decay Hard Prune (Signal Age Limit)

| Timeframe | Max Signal Age (days) |
|-----------|----------------------|
| M1-M5 | 60 |
| M15-H1 | 180 |
| H4+ | 365 |

Signals older than this limit are completely skipped in Tier 1/2 scans.

---

## 4. Detailed Description of Each Data Signal

### 4.1 Step 1: Historical Simulation — 3-Tier System

#### Tier 1: Same-Case Stored Signals
- **Signal**: All signals in `g_signals[]` with **same direction** (BUY/SELL) AND **same case number**
- **Selection criteria**: Exact match on `isBuySignal` + `caseNumber`
- **Processing**: Each signal is forward-simulated using `SimulateSignalOutcome()` to check if TP1/TP2/TP3/SL was hit within `maxForwardBars`
- **Weight formula**: `w1 = n^0.75 x 1.0`
- **Rationale**: Same case = same market pattern = highest relevance
- **Similarity weighting (S5-S9)**:
  - Session block Gaussian: same block=1.0, +-1=0.7, +-2=0.4
  - Angle strength Gaussian kernel (sigma=2.0)
  - Recency half-life decay: `exp(-0.693 x days/60)`
  - RSI proximity Gaussian: sigma = 12 (M1/M5), 8 (M15-H1), 5 (H4+)
  - ATR regime log-ratio: `exp(-logR^2 / 0.96)`

#### Tier 2: All-Case Stored Signals
- **Signal**: All signals with **same direction** but **different case number**
- **Selection criteria**: Match `isBuySignal`, any `caseNumber`
- **Processing**: Same simulation, minus Tier 1 results (avoid double-counting)
- **Weight formula**: `w2 = sqrt(n) x 0.5`
- **Rationale**: Same direction provides useful data when same-case samples are scarce; reduced weight because pattern differs

#### Tier 3: ATR-Based Historical Scan
- **Trigger**: Only activates when `rawCount(Tier1 + Tier2) < minSamples`
- **Signal**: Raw price bars with RSI in similar zone to current signal
- **Selection criteria**:
  - RSI value in case-specific range (e.g., Case 1/5 BUY: RSI 10-35)
  - Angle-tier stratification: only compare bars with similar momentum (strong vs. weak)
  - Scans bars **outside** InpMaxBars range (avoids overlap with Tier 1/2)
- **Processing**: Creates synthetic TP/SL from ATR ratios, simulates forward
- **Weight formula**: `w3 = sqrt(n) x 0.15`
- **Rationale**: Fallback for rare signals with few stored matches; lowest weight because no confirmed signal pattern

#### Tier 3 RSI Filter Ranges by Case:

| Case | Direction | RSI Range |
|------|-----------|-----------|
| 1, 5 (OB/OS) | BUY | 10 - 35 |
| 1, 5 (OB/OS) | SELL | 65 - 90 |
| 2, 3 (Divergence) | BUY | 20 - 45 |
| 2, 3 (Divergence) | SELL | 55 - 80 |
| Other | BUY | 15 - 50 |
| Other | SELL | 50 - 85 |

#### Effective Sample Size (S6)

Weighted data uses **effective sample size** instead of raw count:

```
n_eff = (sum_w)^2 / sum_w2
```

This prevents heavily-discounted signals from inflating the apparent sample count.

### 4.2 Step 2: Edge Measurement

- **Signal**: Stored signals (same case + direction) + deep historical RSI scan
- **Method**: Binary outcome test — from each signal's entry, did price reach `entry ± 1xATR` before hitting SL?
- **Edge** = `correctCount / totalCount` with Bayesian shrinkage toward 0.50
- **Anti-overfit**: Only uses In-Sample signals (Walk-Forward split)
- **Clamp**: [0.48, 0.62] — empirical ceiling for liquid markets (Menkhoff 2010)
- **Shrinkage**: `edge = edge × (1 - 50/(50+n)) + 0.50 × 50/(50+n)`

### 4.3 Step 3: Edge Adjustments

#### a) MTF Alignment
- **Signal**: `g_mtfData[].trend` for all configured timeframes
- **Formula**: `alignRatio = (agreeCount/totalTF) × 2 - 1` (range: -1.0 to +1.0)
- **Adjustment**: `edgeAdj += alignRatio × 0.03`
- **Max effect**: +3% edge (all TFs agree) to -3% (all TFs disagree)
- **Rationale**: Multi-timeframe confluence is the strongest filter for false signals in technical analysis. If higher TFs confirm direction, the trade has structural support.

#### b) Intermarket Correlation
- **Signal**: DXY/EURUSD price trend (SMA slope normalized by ATR)
- **Formula**: `interAdj = correlationScore × 0.02`
- **Max effect**: +-2% edge
- **Rationale**: Gold has -0.85 correlation with USD (Murphy 1991). USD weakness confirms Gold buy signals, USD strength confirms Gold sell signals.

#### c) Angle Strength (Z-score)
- **Signal**: `curSig.angleStrength` — Z-score of RSI Green line momentum at crossover
- **Gate**: Only applies when IC (Information Coefficient) >= 0.05 AND icSamples >= 20
- **Formula**: `angleAdj = clamp((Z - 1.0) × 0.03, -0.03, +0.04)`
- **Divergence damping**: Cases 2,3 apply only 40% of angle adjustment
- **Rationale**: Strong RSI momentum (Z > 1.0) indicates conviction in the move. But for divergence patterns, price structure matters more than speed, hence the damping.

#### d) Vol-Regime
- **Signal**: `g_volRegime.regime` (QUIET/NORMAL/TRENDING/EVENT)
- **Classification**: ATR(14) / SMA(ATR(14), 50 bars)
- **Adjustments**:
  - QUIET (ratio < 0.6): +2% edge (mean-reversion favorable)
  - EVENT (ratio > 1.8): -5% edge (unpredictable spike)
  - TRENDING: 0% (neutral)
  - NORMAL: 0% (no adjustment)
- **Rationale**: Low-vol environments favor RSI OB/OS signals (mean-reverting). High-vol spikes are noise that invalidates technical patterns.

#### Final Edge Clamp: [0.48, 0.65]

### 4.4 Step 4: Theoretical Probability (Gambler's Ruin)

- **Model**: Random walk with drift (Gambler's Ruin formula)
- **Input**: adjustedEdge, SL distance, TP distance (in ATR units)
- **Formula**:
  ```
  mu = 2 × edge - 1 (drift)
  r = exp(-2 × mu)
  P(TP) = (1 - r^slU) / (1 - r^(slU + tpU))
  ```
- **Market Corrections** (multiplicative penalties on P(TP)):
  1. **Fat-Tail Penalty**: `0.003 × (1 + max(excess_kurtosis, 0) / 3)`, cap 15%
     - Computed from 500 bars of return kurtosis
     - Higher kurtosis = more extreme moves = TP less reliable
  2. **Vol-Cluster Penalty**: Autocorrelation of |returns| over 200 bars × 0.10, cap 12%
     - High vol-autocorrelation means clustering → stops get hit in bursts
  3. **Spread Drag**: `min(spread/ATR, 0.15)`
     - Transaction cost as fraction of ATR reduces effective win probability

### 4.5 Step 5: Bayesian Combine

Combines theoretical (Step 4) and historical (Step 1) probabilities:

- **Method**: Inverse-variance weighted average with Wilson Score SE
- **Wilson Score**: `pW = (p×n + z²/2) / (n + z²)` with z=1.96 (95% CI)
- **Wilson SE**: `sqrt((p(1-p)/n + z²/4n²) / (1 + z²/n))`, floor 0.05
- **Credibility**: ramps from 0 to 1 as `n/minSamples`, continues to 1.0 at `3×minSamples`
- **Theoretical SE**: Fixed at 0.15 (model uncertainty)

**Behavior**:
- Few samples (n < minSamples): Theory dominates
- Many samples (n >> minSamples): Historical data dominates
- Equal samples: Blended proportionally to certainty

### 4.6 Step 5.5: Confidence Adjustments

#### a) 1-Bar Price Confirmation (Brooks 2012)
- **Signal**: Next bar after signal must confirm direction
  - BUY: `nextBar.High > signalBar.High`
  - SELL: `nextBar.Low < signalBar.Low`
- **Penalty if NOT confirmed**: TF-adaptive reduction factor:
  - M5: ×0.97 (3% reduction)
  - M15: ×0.92
  - M30: ×0.88
  - H1+: ×0.85 (15% reduction)
- **Rationale**: Price action confirmation is the single strongest short-term predictor. Higher TFs penalize more because one failed bar represents more time.

#### b) ATR Spike Detection
- **Signal**: Signal-bar ATR vs. 50-bar average ATR
- **Trigger**: Signal ATR > 2× average ATR
- **Adjustment**: Shrink probability toward 50%: `prob = 50 + (prob-50)/spikeRatio`
- **Skipped when**: Vol-regime already classified as EVENT (avoid double-penalizing)
- **Rationale**: Extreme volatility at signal time makes SL/TP calculations unreliable.

### 4.7 Step 5.6: Session Quality (Bayesian Blend)

- **Signal**: `g_sessionStats.winRatePerCase[block][case]` or `winRate[block]`
- **Activation**: n >= 20 resolved outcomes in this session + case combination
- **Noise filter**: Only blends when `|measuredWR - baselineWR| > 10%`
- **Method**: Wilson Score SE + model SE (0.15) weighted blend
- **Rationale**: Trading sessions have measurably different characteristics (Andersen & Bollerslev 1998). London/NY overlap has different dynamics than Asian session. Using **measured** win rates (not hardcoded) prevents assumption drift.

### 4.8 Step 5.7: Time-Decay (Weibull Survival Model)

- **Signal**: Elapsed bars since signal appeared
- **Model**: Weibull survival function: `S(t) = exp(-(t/lambda)^k)`
- **Parameters**:

| Parameter | TF <= M1 | TF <= M5 | TF <= M15 | TF >= H1 |
|-----------|----------|----------|-----------|----------|
| k_tp (TP hazard) | 1.20 | 1.30 | 1.40 | 1.50 |
| k_sl (SL hazard) | 0.65 | 0.70 | 0.75 | 0.80 |

- **Bayesian update**:
  ```
  P(TP | survived t bars) = P(TP)×S_tp(t) / [P(TP)×S_tp(t) + P(SL)×S_sl(t)]
  ```
- **Survival ratio**: `sqrt(S_tp × S_sl)` — overall edge remaining (0.0-1.0)
- **Expiry estimate**: Solve `S_tp(t_exp) = 0.15` for remaining bars

**Example with avgTP=38, avgSL=10, base Win=39%**:
| Elapsed Bars | Adjusted Win% | Interpretation |
|-------------|---------------|----------------|
| 0 | 39.0% | Fresh signal |
| 5 | 48.4% | Survived SL danger zone |
| 10 | 53.8% | Peak (past avg SL time) |
| 38 | 40.8% | At avg TP time, fading |
| 60 | 29.3% | Well past, edge dying |
| 80 | 10.3% | Should exit |

- **Rationale**: Probability is not static. If price hasn't hit SL after the typical SL-hit window, the danger has likely passed (SL survival = edge up). Conversely, if price hasn't hit TP after the typical TP-hit window, the edge is expiring (time decay = edge down). Weibull k>1 for TP creates increasing hazard (less likely over time), k<1 for SL creates decreasing hazard (survived = safer).

---

## 5. Data Relationship Diagram

```
                    ┌─────────────────────────────────────────────────┐
                    │             PROBABILITY OUTPUT                    │
                    │  probTP1, probTP2, probTP3, probSL              │
                    │  survivalRatio, expiresMinutes                  │
                    └──────────────────────┬──────────────────────────┘
                                           │
                              [Step 6: Normalize]
                                           │
                    ┌──────────────────────┴──────────────────────────┐
                    │                                                  │
              [Step 5.7]                                    [Step 5.6]
           Time-Decay/Survival                          Session Quality
                    │                                         │
            ┌───────┴───────┐                     ┌──────────┴──────────┐
            │               │                     │                     │
      avgBarsToTP1    avgBarsToSL          g_sessionStats       g_outcomes[]
      (from Step 1)   (from Step 1)     (measured win rate)   (tracked results)
            │               │                     │
            │         [Step 5.5]                   │
            │    Confidence Adjustments            │
            │         │          │                 │
            │   Price Confirm  ATR Spike           │
            │     (Brooks)    Detection            │
            │                                      │
                    [Step 5: Bayesian Combine]
                    ┌───────────┴───────────┐
                    │                       │
          Historical Prob              Theoretical Prob
          (from Step 1)               (from Step 4)
                    │                       │
                    │            [Step 4: Gambler's Ruin]
                    │            ┌─────┬──────┬──────┐
                    │            │     │      │      │
                    │      adjustedEdge │  Fat-Tail  Spread
                    │      (Step 3)    │  Penalty   Drag
                    │            │   Vol-Cluster
                    │            │   Penalty
                    │            │
                    │     [Step 3: Edge Adjustments]
                    │     ┌──────┼──────┬──────┐
                    │     │      │      │      │
                    │   MTF    Inter  Angle  Vol-Regime
                    │  Align  market  Z-score  ATR ratio
                    │     │      │      │      │
                    │     │      │      │      │
                    │   g_mtfData  g_intermarket │
                    │  (M5..D1)   (DXY/EUR)     │
                    │                            │
                    │            [Step 2: Edge Measurement]
                    │                     │
                    │              measuredEdge
                    │              (0.48 - 0.62)
                    │                     │
          [Step 1: Historical Simulation]  │
          ┌───────────┬──────────────────┘
          │           │           │
       Tier 1      Tier 2      Tier 3
    Same-Case   All-Cases   ATR-Historical
    Signals     Signals     Bar Scan
    (w=1.0)     (w=0.5)    (w=0.15)
          │           │           │
          └─────┬─────┘           │
                │                 │
         g_signals[]        Raw price bars
      (stored signals)    (iRSI, iATR, iHigh/Low)
```

### 5.1 Influence Weight Map (How Much Each Factor Affects Final Probability)

```
DIRECT INFLUENCE ON PROBABILITY (probTP1):
──────────────────────────────────────────

[Historical Data]──────────────────────────── 30-70% weight
  │                                           (depends on sample size)
  ├── Tier 1: Same-case signals ──── n^0.75 × 1.0 ──── HIGHEST
  │     ├── Session similarity ──── ×0.4 to ×1.0
  │     ├── RSI proximity ──── Gaussian(sigma=5-12)
  │     ├── ATR regime match ──── log-ratio kernel
  │     ├── Angle similarity ──── Gaussian(sigma=2)
  │     └── Recency decay ──── halflife=60 days
  │
  ├── Tier 2: Other-case signals ── sqrt(n) × 0.5 ──── MEDIUM
  │     └── (same similarity weights as Tier 1)
  │
  └── Tier 3: Raw ATR scan ──── sqrt(n) × 0.15 ──── LOWEST
        ├── RSI zone filter (case-specific)
        └── Angle-tier stratification

[Theoretical Model]────────────────────────── 30-70% weight
  │                                           (inverse of historical)
  ├── Gambler's Ruin ──── P(TP) = f(edge, SL/ATR, TP/ATR)
  │     ├── Fat-tail penalty ──── -0.3% to -15%
  │     ├── Vol-cluster penalty ── 0% to -12%
  │     └── Spread drag ────────── 0% to -15%
  │
  └── Edge (0.48 - 0.65)
        ├── Measured from history ──── base (0.48-0.62)
        ├── MTF alignment ──────────── ±3%
        ├── Intermarket ────────────── ±2%
        ├── Angle Z-score ──────────── -3% to +4%
        └── Vol-regime ─────────────── -5% to +2%

[Post-Combine Adjustments]─────────────────── -3% to -15%
  │
  ├── 1-Bar Price Confirm ──── ×0.85 to ×0.97 if NOT confirmed
  ├── ATR Spike ──────────────── shrink toward 50%
  ├── Session Quality ─────────── ratio × probTP (if |diff| > 10%)
  └── Time-Decay ──────────────── Weibull survival (dynamic over time)
```

---

## 6. Signal Selection Rationale

### 6.1 Why 3-Tier Historical System?

| Tier | Data Quality | Data Quantity | When Used |
|------|-------------|---------------|-----------|
| Tier 1 (Same-case) | Highest — exact pattern match | Lowest — few same-case signals | Always (if available) |
| Tier 2 (All-case) | Medium — same direction, different pattern | Medium | Always (supplements Tier 1) |
| Tier 3 (ATR scan) | Lowest — no confirmed signal pattern | Highest — thousands of bars | Only when Tier 1+2 have < minSamples |

**Rationale**: The system faces a **bias-variance tradeoff**. Tier 1 has lowest bias (exact match) but highest variance (few samples). Tier 3 has lowest variance (many samples) but highest bias (no pattern match). The weighted combination optimizes for both.

### 6.2 Why Gambler's Ruin Model?

- **Selected over**: Fixed probability tables, Monte Carlo simulation, historical-only
- **Reason**: Gambler's Ruin naturally encodes the **geometric relationship** between SL and TP distances. A trade with SL=2xATR and TP=4xATR has fundamentally different probability than SL=1xATR, TP=2xATR, even with the same edge. Historical data alone cannot capture this relationship with small samples.
- **Market corrections** (fat-tail, vol-cluster, spread) bridge the gap between the theoretical random-walk assumption and real market behavior.

### 6.3 Why Wilson Score SE (Not Binomial SE)?

- Standard binomial SE `sqrt(p(1-p)/n)` underestimates uncertainty when n is small or p is near 0/1
- Wilson Score adds a correction term `z²/4n²` that prevents the interval from collapsing at extreme values
- Floor of 0.05 ensures the model is **never trusted 100%** even with large samples

### 6.4 Why Weibull Survival (Not Linear Decay)?

- **Linear decay**: Assumes edge decreases at constant rate — unrealistic. A signal surviving 1 bar and 100 bars should not lose the same % of edge per bar.
- **Exponential decay**: Assumes constant hazard — misses the "danger zone" concept (SL is more likely to be hit early).
- **Weibull**: Captures **two asymmetric behaviors**:
  - TP: increasing hazard (k>1) — the longer you wait, the less likely TP will be reached
  - SL: decreasing hazard (k<1) — if you survived the early danger, SL risk diminishes
- TF-adaptive shape parameters reflect that manual traders on M1/M5 hold positions differently than swing traders on H4.

### 6.5 Why Session-Specific Win Rate?

- **Not hardcoded**: Previous versions used fixed session multipliers (Asian=0.6, London=0.75, etc.). This created broker-specific and symbol-specific inaccuracy.
- **Measured**: Current system counts actual TP1 hits and SL hits per session block from `g_outcomes[]`. This adapts to each symbol's session behavior.
- **Noise filter**: Only blends when `|measured - model| > 10%` to prevent small random variations from distorting the probability.

### 6.6 Why Information Coefficient Gate for Angle?

- Angle strength is a derived signal — its predictive value is not guaranteed
- IC measures `Pearson(angleStrength, outcome{+1,-1})` on **in-sample** data only
- Gate: IC >= 0.05 AND icSamples >= 20
- If angle doesn't predict outcomes (IC < 0.05), the edge adjustment is disabled
- Prevents overfitting to a decorrelation signal that happens to look good on small samples

---

## 7. Anti-Overfitting Measures Summary

| # | Measure | Location | Description |
|---|---------|----------|-------------|
| 1 | Tier weights proportional to data quality | Step 1 | `sqrt(n) × relevance` prevents small datasets from dominating |
| 2 | Edge clamp [0.48, 0.62] | Step 2 | No edge above 62% — matches empirical market research |
| 3 | Adjusted edge clamp [0.48, 0.65] | Step 3 | Conservative adjustments cannot create unrealistic edge |
| 4 | MTF cap ±3% | Step 3 | Multi-TF alignment is confirmation, not the signal itself |
| 5 | IC gate for angle | Step 3 | Only uses angle when statistically validated |
| 6 | Fat-tail + vol-cluster penalties | Step 4 | Adjusts theoretical model for real market conditions |
| 7 | Wilson Score SE floor 0.05 | Step 5 | Never 100% trusts data, always retains model uncertainty |
| 8 | Walk-Forward IS/OOS split | Step 2 | Edge measured only on training data |
| 9 | Bayesian shrinkage | Step 2 | Small samples shrunk toward 0.50 (neutral) |
| 10 | Price confirmation (Brooks) | Step 5.5 | Uses High/Low (broker-resistant), not Close |
| 11 | Session blend noise filter >10% | Step 5.6 | Prevents small fluctuations from distorting probability |
| 12 | Session ratio floor 0.30 | Step 5.6 | Prevents 0% session WR from crushing probability entirely |
| 13 | Weibull TF-adaptive parameters | Step 5.7 | Different decay curves for different trading styles |
| 14 | Effective sample size n_eff | Step 1 | Prevents similarity-weighted data from inflating sample count |
| 15 | Tier 3 dedup boundary | Step 1 | Stops Tier 3 before g_signals[] range to avoid double-counting |

---

## 8. Configuration Parameters Reference

### Core Probability Parameters

| Parameter | Default | Effect | Location |
|-----------|---------|--------|----------|
| `InpShowProbability` | true | Master switch for probability engine | Config.mqh |
| `InpProbMaxBars` | 1000 | Base max bars for Tier 3 historical scan | Config.mqh |
| `InpRSIPeriod` | 14 | RSI period for similarity filtering | Config.mqh |
| `InpATRPeriod` | 14 | ATR period for distance normalization | Config.mqh |
| `InpSLRatio` | 2.0 | SL = ATR × this (affects Gambler's Ruin) | Config.mqh |
| `InpTPRatio` | 4.0 | TP1 = ATR × this | Config.mqh |
| `InpTP2Multiplier` | 1.5 | TP2 = TP1 × this | Config.mqh |
| `InpTP3Multiplier` | 2.0 | TP3 = TP1 × this | Config.mqh |

### Toggle Parameters (Enable/Disable Data Sources)

| Parameter | Default | Controls |
|-----------|---------|----------|
| `InpShowMTF` | true | MTF alignment in edge adjustment |
| `InpUseIntermarket` | true | DXY/EURUSD correlation analysis |
| `InpUseWalkForward` | true | IS/OOS split for anti-overfit |
| `InpUseSpreadRegime` | true | Spread anomaly detection |
| `InpOOSPercent` | 20.0 | Out-of-sample percentage (10-30%) |
| `InpSpreadSpikeMulti` | 2.0 | Spread spike threshold multiplier |

### Hardcoded Constants (Not User-Configurable)

| Constant | Value | Purpose |
|----------|-------|---------|
| Tier 1 weight multiplier | 1.0 | Full trust for same-case data |
| Tier 2 weight multiplier | 0.5 | Half trust for cross-case data |
| Tier 3 weight multiplier | 0.15 | Low trust for raw ATR scan |
| Wilson z | 1.96 | 95% confidence interval |
| Wilson SE floor | 0.05 | Minimum uncertainty |
| Theoretical SE | 0.15 | Model uncertainty |
| Edge shrinkage n | 50 | Bayesian prior strength |
| Session blend threshold | 10% | Noise filter |
| Session ratio floor | 0.30 | Minimum blend ratio |
| Max IC pairs | 200 | Cap for computational efficiency |
| Recency half-life | 60 days | Signal age decay |

---

## 9. Complete Data Flow Diagram (Mermaid)

```mermaid
graph TD
    subgraph "INPUT DATA"
        SIG[g_signals<br/>Stored Signals]
        BARS[Price Bars<br/>OHLC + RSI + ATR]
        MTF[g_mtfData<br/>Multi-TF Trends]
        IM[g_intermarket<br/>DXY/EURUSD]
        OUT[g_outcomes<br/>Signal Results]
        SESS[g_sessionStats<br/>Win Rates per Session]
        WF[g_walkForward<br/>IS/OOS Split]
        VOL[g_volRegime<br/>ATR Ratio]
        SPR[g_spreadRegime<br/>Spread Monitor]
        ANG[angleStrength<br/>RSI Z-score]
    end

    subgraph "STEP 1: Historical Simulation"
        T1[Tier 1: Same-Case<br/>w = n^0.75 x 1.0]
        T2[Tier 2: All-Cases<br/>w = sqrt n x 0.5]
        T3[Tier 3: ATR Scan<br/>w = sqrt n x 0.15]
        HIST[histTP1 / histSL<br/>avgBarsToTP1 / avgBarsToSL]
    end

    subgraph "STEP 2-3: Edge"
        EDGE[measuredEdge<br/>0.48 - 0.62]
        ADJ[adjustedEdge<br/>0.48 - 0.65]
    end

    subgraph "STEP 4: Theory"
        GR[Gambler's Ruin<br/>P TP = f edge SL TP]
        COR[Market Corrections<br/>Fat-tail / Vol-cluster / Spread]
        THEO[theoTP1 / theoTP2 / theoTP3]
    end

    subgraph "STEP 5: Combine"
        BAY[Bayesian Combine<br/>Wilson Score SE]
        PROB[probTP1 initial]
    end

    subgraph "STEP 5.5-5.7: Adjust"
        PC[Price Confirmation<br/>Brooks 2012]
        AS[ATR Spike<br/>Detection]
        SQ[Session Quality<br/>Bayesian Blend]
        TD[Time-Decay<br/>Weibull Survival]
    end

    subgraph "OUTPUT"
        FINAL[probTP1 / probTP2 / probTP3 / probSL<br/>survivalRatio / expiresMinutes]
    end

    SIG --> T1
    SIG --> T2
    BARS --> T3
    ANG --> T1
    ANG --> T3
    T1 --> HIST
    T2 --> HIST
    T3 --> HIST

    SIG --> EDGE
    BARS --> EDGE
    WF --> EDGE

    EDGE --> ADJ
    MTF --> ADJ
    IM --> ADJ
    ANG --> ADJ
    VOL --> ADJ

    ADJ --> GR
    SPR --> COR
    BARS --> COR
    GR --> THEO
    COR --> THEO

    HIST --> BAY
    THEO --> BAY
    BAY --> PROB

    PROB --> PC
    BARS --> PC
    PC --> AS
    BARS --> AS
    AS --> SQ
    SESS --> SQ
    OUT --> SQ
    SQ --> TD
    HIST --> TD
    TD --> FINAL
end
```

---

*Report generated from source code analysis of RSI Advanced V10.20*
*Files analyzed: ProbabilityEngine.mqh, Config.mqh, Structs.mqh, MathUtils.mqh, Normalize.mqh, IntermarketAnalysis.mqh, SessionStatistics.mqh, WalkForward.mqh*
