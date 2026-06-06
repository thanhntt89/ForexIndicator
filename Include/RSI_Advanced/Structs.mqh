#ifndef RSI_ADV_STRUCTS_MQH
#define RSI_ADV_STRUCTS_MQH
#define SESSION_BLOCKS 4
#define CASE_COUNT     8

struct SignalData
{
   datetime signalTime;
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
   double overfitRatio;       // IS/OOS ratio (< 1.2 = robust)
   bool   isRobust;
   int    isSamples;
   int    oosSamples;
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

#endif