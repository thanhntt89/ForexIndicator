#ifndef RSI_ADV_STRUCTS_MQH
#define RSI_ADV_STRUCTS_MQH
#define SESSION_BLOCKS 4
#define CASE_COUNT     9

struct SignalData
{
   datetime signalTime;    // Broker local time at signal bar open (raw, as seen by iTime())
   // [ISSUE #4 FIX] signalTimeUTC: broker local time converted to UTC and snapped to
   // standard TF boundary via NormalizeCandleToUTC(). This eliminates broker-timezone
   // dependency: GMT+2 and GMT+3 brokers produce the same signalTimeUTC for the same
   // market event. Used by GetSessionBlock() and ScanStoredSignalsBoth() for session
   // comparison. Zero = not yet computed (backward compat with binary-loaded old signals).
   datetime signalTimeUTC;
   int      barIndex;
   int      caseNumber;
   bool     isBuySignal;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   double   takeProfit2;
   double   takeProfit3;
   double   atrValue;
   double   angleStrength; // Z-score of Green momentum at crossover bar
                           // 0.0 = not computed; >1.5 = strong (12h-2h); <0.5 = weak (sideway)
   int      rsiPeriod;     // InpRSIPeriod active at signal detection time.
                           // Used to detect Tier 3 parameter contamination:
                           // if current InpRSIPeriod != stored rsiPeriod, Tier 3
                           // historical scan would use a different period than what
                           // produced the original signal — invalidating comparability.
   // --- Per-signal simulation cache (RAM only, rebuilt on fullRecalc) ---
   // Avoids re-running SimulateSignalOutcome for resolved historical signals.
   // Once a signal has all forward bars available, its outcome is deterministic.
   // ScanStoredSignalsBoth: multi-level outcome (-1=SL, 0=timeout, 1/2/3=TP)
   int      simCachedTP;      // 99 = not cached
   int      simCachedBTR;     // bars-to-result for above
   // MeasureEdgeFromHistory: binary outcome (-1=SL first, 1=target first)
   int      edgeCachedOutcome; // 99 = not cached
   // --- [S2/S3] Context fields for data quality improvement ---
   double   spreadAtSignal;    // broker spread at signal detection (SELL simulation fix)
   int      sessionBlock;      // 0=Asian 1=London 2=Overlap 3=LateNY at signal time
   double   rsiAtSignal;       // BufferGreen[i] — exact RSI value at signal bar
   double   predictedProb;    // probTP1 at signal creation time (for Brier Score calibration)
   double   xgbPredictedProb; // XGBoost probTP1 at signal creation (for XGB Brier tracking)
};

struct BrierMetrics
{
   double brierScore;      // Mean squared error: 0=perfect, 0.25=random coin flip
   int    samples;         // Resolved outcomes that had a stored probability
   double calibrationGap;  // mean(predicted) - mean(actual), negative = overconfident
   bool   isReliable;      // brierScore < 0.25 && samples >= 20
};

struct SignalScore
{
   double totalScore;
   double rsiScore;
   double volumeScore;
   double volatilityScore;
   double sessionScore;
   double mtfScore;
   double srScore;
   string quality;
   color  qualityColor;
};

struct MTFStatus
{
   int    timeframe;
   string tfName;
   int    trend;
   double greenValue;
   double redValue;
   double orangeValue;
   double bbUpper;
   double bbLower;
   int    lastSignalCase;
   bool   lastSignalIsBuy;
   string statusText;
};

struct ProbabilityData
{
   double probTP1;
   double probTP2;
   double probTP3;
   double probSL;
   int    totalSamples;
   int    samplesTP1;
   int    samplesTP2;
   int    samplesTP3;
   int    samplesSL;
   double avgBarsToTP1;
   double avgBarsToSL;
   // Time-decay (survival analysis): probability adjusted by elapsed bars
   double decayedProbTP1;    // probTP1 after time-decay adjustment
   double decayedProbSL;     // probSL after time-decay adjustment
   double survivalRatio;     // 0.0-1.0: how much edge remains (1.0 = fresh, 0.0 = expired)
   int    elapsedBars;       // bars since signal appeared
   int    expiresMinutes;    // estimated minutes until edge drops below 15%
   double originalProbTP1;  // pre-decay probabilities (for display: "68%<-72%")
   double originalProbTP2;
   double originalProbTP3;
   // Data quality metrics (V11.30)
   int    rawCountT1;     // Tier 1 (same-case) raw signal count
   int    rawCountT2;     // Tier 2 (other-case) raw signal count
   int    countT3;        // Tier 3 (ATR scan) sample count
   double nEffT1;         // Tier 1 effective N
   double nEffT2;         // Tier 2 effective N
   int    timeoutCount;   // Signals that timed out (no TP/SL hit)
   double oldestDays;     // Age of oldest contributing signal (days)
   double realPct;        // % of nEff from real signals: (nEffT1+nEffT2)/totalSamples
   double wrT1;           // Tier 1 win rate (TP1 hit %)
   double wrT2;           // Tier 2 win rate
   double wrT3;           // Tier 3 win rate
   // XGBoost integration (V12)
   double xgbProbTP1;     // XGBoost model probability (0-100, 0 = not computed)
   double xgbWeight;      // XGBoost weight in ensemble (0.0 = shadow/off)
   double bayesianWeight; // Bayesian weight in ensemble (1.0 when XGB off)
   bool   xgbActive;      // true = XGBoost contributing to combined prob
};

struct EntryZone
{
   double price;           // Entry price for this zone
   double slDistance;       // Distance from zone price to SL
   double tp1Distance;     // Distance from zone price to TP1
   double riskShare;       // Fraction of total risk (0.0 - 1.0)
   double lotSize;         // Calculated lot size
   double rrRatio;         // R:R ratio from this zone
   double probReach;       // P(price reaches this zone) 0.0-1.0
   double probTP1;         // P(TP1 hit | entered at this zone) 0-100
   double expectedValue;   // EV per trade from this zone (in R)
   bool   isValid;         // Zone is valid (SL distance OK, price in range)
   bool   isRecommended;   // Zone has positive EV or is Zone 1
   string zoneName;        // "Market", "PB-Zone2", etc
};

//+------------------------------------------------------------------+
//| V11: Multi-Source + Walk-Forward structures                        |
//+------------------------------------------------------------------+

struct IntermarketData
{
   double dxyPrice;           // DXY or EURUSD price
   double dxyTrend;           // SMA slope: positive=rising, negative=falling
   double correlationScore;   // -1.0 to +1.0 alignment with signal
   bool   isAvailable;        // DXY/EURUSD found on broker
   string sourceSymbol;       // Which symbol used
};

struct SessionStats
{
   int    wins[SESSION_BLOCKS]; // Per session: Asian/London/Overlap/LateNY
   int    losses[SESSION_BLOCKS];
   double winRate[SESSION_BLOCKS]; // Calculated win rate per session
   int    totalPerSession[SESSION_BLOCKS];

   // 2D: per session × per case
   int    winsPerCase[SESSION_BLOCKS][CASE_COUNT];
   int    lossesPerCase[SESSION_BLOCKS][CASE_COUNT];
   double winRatePerCase[SESSION_BLOCKS][CASE_COUNT];
   int    totalPerCase[SESSION_BLOCKS][CASE_COUNT];
};

struct WalkForwardData
{
   double isWinRate;          // In-sample win rate
   double oosWinRate;         // Out-of-sample win rate
   double overfitRatio;       // IS/OOS ratio (< 1.15 = robust per Pardo 2008)
   bool   isRobust;
   int    isSamples;
   int    oosSamples;
   // Information Coefficient: Pearson correlation between angleStrength and outcome.
   // IC > 0.10 = strong alpha (signal score predicts direction reliably).
   // IC 0.05-0.10 = weak alpha (marginal predictive power).
   // IC < 0.05 = noise (angleStrength does NOT predict outcomes — review signal cases).
   // Computed on IS-only resolved signals to avoid lookahead bias.
   double infoCoeff;          // Pearson(angleStrength, outcome ∈ {+1,-1})
   int    icSamples;          // Sample count (IS resolved signals with angleStrength > 0)
   double rollingRatios[5];   // K rolling overfit ratios (median used for robustness)
   double medianRatio;        // Median of rolling overfit ratios
   int    rollingCount;       // Number of completed rolling windows
   double permPValue;         // Permutation test p-value for edge significance
   double kellyFraction;      // Half-Kelly optimal position size (%)
};

struct RollingPerformance
{
   double last10WR;
   double last20WR;
   double last50WR;
   double allTimeWR;
   int    totalTracked;
   bool   isDecreasing;       // Performance declining warning
};

struct SpreadRegime
{
   double currentSpread;
   double avgSpread;
   double spreadRatio;
   bool   isSpike;            // > 2x average
   bool   isExtreme;          // > 3x average
};

// Vol-regime: ATR ratio classifies market state for edge adjustment
// QUIET: ATR < 60% of avg → mean-reverting, RSI signals stronger
// NORMAL: ATR between 60-180% → standard conditions
// TRENDING: ATR high + London/NY session → directional breakout
// EVENT: ATR > 180% → spike/news, unpredictable
enum ENUM_VOL_REGIME
{
   VOL_QUIET    = 0,
   VOL_NORMAL   = 1,
   VOL_TRENDING = 2,
   VOL_EVENT    = 3
};

struct VolRegimeData
{
   ENUM_VOL_REGIME regime;
   double          atrRatio;   // current ATR / avg ATR(50)
   string          label;      // display text
};

enum ENUM_MARKET_STATE
{
   STATE_MEAN_REVERT = 0,
   STATE_TRENDING    = 1,
   STATE_VOLATILE    = 2,
   STATE_TRANSITION  = 3
};

struct MarketStateData
{
   ENUM_MARKET_STATE state;
   double confidence;
   double probMultiplier;
   string label;
};

struct PortfolioRisk
{
   int      openSignals;
   int      maxSignals;
   double   totalExposurePct;
   double   maxExposurePct;
   double   dailyPnLPips;
   double   dailyDrawdownPct;
   double   maxDailyDD;
   bool     circuitBreakerActive;
   int      dailyTradeCount;
   int      maxDailyTrades;
   datetime lastResetDate;
};

#endif