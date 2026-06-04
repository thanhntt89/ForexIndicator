# RSI Advanced V11 - Improvement Specification
## Multi-Source Data + Walk-Forward Validation

---

## 1. OVERVIEW

### Current State: V10.20 (74.3/100)
### Target State: V11.00 (78-80/100)

### Goals:
1. Add independent data sources (+8-14% signal accuracy)
2. Add walk-forward validation (+5-8 robustness points)
3. Reach Tier 2 Professional Algo level (75-85%)

---

## 2. NEW DATA SOURCES

### 2.1 Intermarket Correlation (Priority 1)

**Theory**: Murphy (1991) "Intermarket Technical Analysis"

**Rationale**:
- Gold (XAUUSD) has inverse correlation with USD
- DXY correlation with Gold: -0.85
- EURUSD correlation with Gold: +0.80 (inverse of USD)
- When RSI signals BUY Gold AND USD weakening → stronger signal
- When RSI signals BUY Gold AND USD strengthening → weaker signal

**Implementation**:
- Primary: Read DXY via `iClose("DXYm", period, shift)` or `iClose("USDX", ...)`
- Fallback: Read EURUSD via `iClose("EURUSD", period, shift)` as inverse proxy

Calculate:
- `intermarketTrend` = SMA(20) slope of DXY/EURUSD
- `intermarketScore` = alignment with signal direction (-1.0 to +1.0)

Integration points:
- `ProbabilityEngine`: adjust edge by ±2% based on intermarket alignment
- `Normalize/Recommendation`: add intermarket factor to EV score
- `PanelDrawing`: display intermarket status

**Symbols to check** (broker-dependent):
- DXY variants: `"DXYm"`, `"USDX"`, `"DXY"`, `"DX"`, `"USDIndex"`
- Fallback: `"EURUSD"`, `"EURUSDm"`, `"EURUSDc"`

**Expected impact**: +5-7% signal accuracy

---

### 2.2 Time-of-Day Statistical Edge (Priority 2)

**Theory**: Andersen & Bollerslev (1998) "Intraday Periodicity"

**Rationale**:
- Market behavior differs by session
- Each Case type has different win rate per session
- MEASURED from actual data, not hardcoded

**Implementation**:

Track 4 session blocks (UTC):
- Asian: 0-8
- London: 8-12
- Overlap: 12-16
- LateNY: 16-22

For each stored signal:
- Determine which session it occurred in
- Track outcome (TP1 hit or SL hit)

Calculate per-case per-session win rate:
- `sessionWinRate[caseNum][sessionBlock]` = wins / total

Integration:
- `ProbabilityEngine`: weight by session-specific win rate
- `Recommendation`: session quality from MEASURED data (not hardcoded)

**Expected impact**: +3-5% probability accuracy

---

### 2.3 Spread Regime Detection (Priority 4)

**Theory**: O'Hara (1995) "Market Microstructure Theory"

**Rationale**:
- Spread widening = market stress / news / low liquidity
- Signals during spread anomaly less reliable
- NOT used as filter (spread data broker-dependent)
- ONLY used as confidence adjustment

**Implementation**:

Track spread:
- Rolling average: last 100 ticks spread
- Current spread vs average

Conditions:
- If spread > average × 2.0 → `SPREAD_SPIKE`
- If spread > average × 3.0 → `SPREAD_EXTREME`

Integration:
- Recommendation score: -5 points during spike, -15 during extreme
- Panel: display "SPREAD: NORMAL / SPIKE / EXTREME"

**Expected impact**: +3-4% recommendation accuracy

---

## 3. WALK-FORWARD VALIDATION

### 3.1 In-Sample / Out-of-Sample Split (Priority 3)

**Theory**: Pardo (2008) "Evaluation and Optimization of Trading Strategies"

**Rationale**:
- All current probability calculated from SAME data used for signals
- In-sample bias: metrics look better than reality
- Need separate validation set to detect overfitting

**Implementation**:

Split available signals:
- Training set: oldest 80% of signals
- Validation set: newest 20% of signals
- `splitIndex = g_signalCount × 0.8`

Probability engine changes:
- `MeasureEdgeFromHistory`: only scan bars before `splitBar`
- `ScanStoredSignals`: only use signals with index < `splitIndex`
- `ScanHistoricalATRBased`: only scan bars before `splitBar`

Validation metrics (calculated on newest 20%):
- `OOS_winRate` = wins in validation set / total in validation set
- `IS_winRate` = wins in training set / total in training set
- Overfitting ratio = IS_winRate / OOS_winRate
  - If ratio > 1.5 → WARNING: possible overfitting
  - If ratio < 1.2 → GOOD: model is robust

Display:
```
"IS:42% | OOS:38% | Ratio:1.11 [ROBUST]"
```

**Expected impact**: +3-4 robustness points

---

### 3.2 Rolling Performance Tracker (Priority 5)

**Theory**: Standard portfolio management practice

**Rationale**:
- Track actual signal outcomes over time
- Detect declining performance early
- Alert trader when model may need recalibration

**Implementation**:

For each signal, track outcome:
- Store: signalTime, direction, case, entryPrice, SL, TP1
- Monitor: did price hit TP1 or SL first?

When outcome determined:
- Store result in GlobalVariable array
- Update rolling metrics

Rolling metrics:
- Last 10 signals win rate
- Last 20 signals win rate
- Last 50 signals win rate
- All-time win rate

Declining performance detection:
- If `last10_WR < last50_WR × 0.7` → "PERFORMANCE DECLINING"
- If `last20_WR < 30%` → "LOW WIN RATE WARNING"

Display on panel:
```
"Performance: 10sig:45% | 20sig:42% | 50sig:40%"
```

**Expected impact**: +2-3 robustness points

---

### 3.3 Parameter Stability Check (Priority 6)

**Theory**: Regime detection in quantitative finance

**Rationale**:
- Market regime changes invalidate model assumptions
- Edge measured in trending market ≠ edge in ranging market
- Need to detect when conditions change

**Implementation**:

Every 50 bars:
- Re-measure: edge, kurtosis, vol clustering, ATR state
- Compare with previous measurement

Conditions:
- If edge changed > 10%: "EDGE SHIFT"
- If kurtosis changed > 50%: "DISTRIBUTION CHANGE"
- If ATR changed > 40%: "VOLATILITY REGIME CHANGE"

Display warning on panel when detected.

**Expected impact**: +1-2 robustness points

---

## 4. DATA STRUCTURES

```mql4
// Intermarket data
struct IntermarketData
{
   double dxyPrice;
   double dxyTrend;         // SMA slope: +1 rising, -1 falling
   double correlationScore; // -1.0 to +1.0 alignment with signal
   bool   isAvailable;      // DXY/EURUSD found on broker
   string sourceSymbol;     // Which symbol used
};

// Session statistics
struct SessionStats
{
   int    wins[4];          // Per session block: Asian/London/Overlap/LateNY
   int    losses[4];
   double winRate[4];       // Calculated win rate per session
};

// Walk-forward metrics
struct WalkForwardData
{
   double isWinRate;        // In-sample win rate
   double oosWinRate;       // Out-of-sample win rate
   double overfitRatio;     // IS/OOS ratio
   bool   isRobust;         // ratio < 1.2
   int    isSamples;
   int    oosSamples;
};

// Rolling performance
struct RollingPerformance
{
   double last10WR;
   double last20WR;
   double last50WR;
   double allTimeWR;
   int    totalTracked;
   bool   isDecreasing;     // Performance declining warning
};

// Spread regime
struct SpreadRegime
{
   double currentSpread;
   double avgSpread;
   double spreadRatio;
   bool   isSpike;          // > 2× average
   bool   isExtreme;        // > 3× average
};
```

---

## 5. FILES TO CREATE / MODIFY

### New files:
- `IntermarketAnalysis.mqh`  → DXY/EURUSD correlation engine
- `SessionStatistics.mqh`    → Time-of-day win rate tracking
- `WalkForward.mqh`          → IS/OOS split + rolling tracker + stability check

### Modified files:
- `Config.mqh`               → Add inputs for intermarket/session/WF/spread
- `Structs.mqh`              → Add new data structures
- `Globals.mqh`              → Add global instances of new structs
- `ProbabilityEngine.mqh`    → IS/OOS split, session-weighted probability
- `Normalize.mqh`            → Intermarket + spread in recommendation
- `PanelDrawing.mqh`         → Display new metrics
- `RSI_Advanced.mq4`         → Include new modules, call new functions

---

## 6. TASK LIST

### Task 1: Structs + Config + Globals (Foundation)
- Files: `Structs.mqh`, `Config.mqh`, `Globals.mqh`
- Add: New structs, new inputs, new global variables
- Effort: LOW
- Test: Compile only

### Task 2: IntermarketAnalysis.mqh (Priority 1)
- Create new file
- Functions:
  - `DetectIntermarketSymbol()` → find DXY/EURUSD on broker
  - `CalculateIntermarketTrend()` → SMA slope
  - `GetIntermarketScore()` → alignment with signal
- Effort: MEDIUM
- Test: Panel shows intermarket data

### Task 3: SessionStatistics.mqh (Priority 2)
- Create new file
- Functions:
  - `UpdateSessionStats()` → track outcomes per session
  - `GetSessionWinRate()` → measured win rate for current session
  - `GetSessionBlock()` → determine current session
- Effort: LOW
- Test: Panel shows session stats

### Task 4: WalkForward.mqh - IS/OOS Split (Priority 3)
- Create new file
- Functions:
  - `CalculateWalkForwardMetrics()` → IS/OOS split + ratios
  - `GetTrainingSplitBar()` → bar index for split point
  - `IsOverfitting()` → check IS vs OOS ratio
- Effort: MEDIUM
- Test: Panel shows IS/OOS metrics

### Task 5: Spread Regime Detection (Priority 4)
- Modify: `Normalize.mqh` (add spread tracking)
- Functions:
  - `UpdateSpreadRegime()` → track rolling spread
  - `GetSpreadRegimeScore()` → confidence adjustment
- Effort: LOW
- Test: Panel shows spread status

### Task 6: ProbabilityEngine Integration
- Modify: `ProbabilityEngine.mqh`
- Changes:
  - Edge measurement respects IS/OOS split
  - Historical simulation uses training set only
  - Session-specific win rate weighting
  - Intermarket edge adjustment
- Effort: MEDIUM
- Test: Probability values change with new data

### Task 7: Recommendation Integration
- Modify: `Normalize.mqh` (`GetTradeRecommendation`)
- Changes:
  - Add intermarket factor to EV score
  - Add session factor (measured, not hardcoded)
  - Add spread regime penalty
  - Add overfitting warning
- Effort: MEDIUM
- Test: Recommendation score changes

### Task 8: Panel Display
- Modify: `PanelDrawing.mqh`
- Changes:
  - Display intermarket status
  - Display session win rate
  - Display IS/OOS metrics
  - Display spread status
  - Display rolling performance
- Effort: MEDIUM
- Test: Visual check all new sections

### Task 9: Main Integration
- Modify: `RSI_Advanced.mq4`
- Changes:
  - Include new modules
  - Call intermarket update
  - Call session stats update
  - Call spread update
  - Call walk-forward metrics
- Effort: LOW
- Test: Full integration test

### Task 10: Rolling Performance (Priority 5)
- Modify: `WalkForward.mqh`
- Add:
  - `TrackSignalOutcome()` → monitor each signal
  - `CalculateRollingMetrics()` → last 10/20/50 WR
  - `DetectPerformanceDecline()` → warning
- Effort: HIGH
- Test: Performance tracks over time

### Task 11: Stability Check (Priority 6)
- Modify: `WalkForward.mqh`
- Add:
  - `CheckParameterStability()` → compare current vs previous
  - `DetectRegimeChange()` → alert when assumptions change
- Effort: MEDIUM
- Test: Regime change detection

---

## 7. EXPECTED OUTCOMES

### Score improvement:
- Signal Generation: 29 → 36 (+7)
  - +4 Intermarket correlation
  - +2 Session statistics
  - +1 Spread regime
- Robustness: 33 → 41 (+8)
  - +3 IS/OOS validation
  - +2 Rolling tracker
  - +1 Stability check
  - +2 Multi-source cross-validation
- **Total: 260 → 276/350 = 78.9%**

### Performance improvement:
- Win rate (ENTRY signals only): 45-55% → 50-60%
- Recommendation accuracy: 75-80% → 82-88%
- False signal reduction: -15-20%
- Overfitting detection: YES (new capability)

---

## 8. ANTI-OVERFITTING MEASURES FOR V11

1. Intermarket: uses EXTERNAL data (not derived from same price)
2. Session stats: MEASURED from actual outcomes (not hardcoded)
3. IS/OOS split: validates on UNSEEN data
4. Rolling tracker: detects REAL-TIME performance decline
5. Spread regime: uses BROKER data (not price-derived)
6. All new parameters: data-driven or mathematical constants
7. No new hardcoded thresholds without justification

---

## 9. LIMITATIONS

- Intermarket: DXY may not be available on all brokers → EURUSD fallback
- Session stats: needs minimum 50 signals per session to be reliable
- IS/OOS split: needs minimum 100 total signals to be meaningful
- Rolling tracker: first 50 signals → insufficient data warning
- Spread regime: tick data quality varies by broker
