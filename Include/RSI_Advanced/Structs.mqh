//+------------------------------------------------------------------+
//|                                                   Structs.mqh      |
//|                         RSI Advanced - Data Structures             |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_STRUCTS_MQH
#define RSI_ADV_STRUCTS_MQH

//+------------------------------------------------------------------+
//| Signal data                                                        |
//+------------------------------------------------------------------+
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
};

//+------------------------------------------------------------------+
//| Signal quality score breakdown                                     |
//+------------------------------------------------------------------+
struct SignalScore
{
   double totalScore;
   double rsiScore;
   double volumeScore;
   double volatilityScore;
   double sessionScore;   
   double mtfScore;
   double srScore;           // S/R confirmation score
   string quality;
   color  qualityColor;
};

//+------------------------------------------------------------------+
//| MTF status for one timeframe                                       |
//+------------------------------------------------------------------+
struct MTFStatus
{
   int    timeframe;
   string tfName;
   int    trend;         // 1=bull, -1=bear, 0=neutral
   double greenValue;
   double redValue;
   double orangeValue;
   double bbUpper;
   double bbLower;
   int    lastSignalCase;
   bool   lastSignalIsBuy;
   string statusText;
};

//+------------------------------------------------------------------+
//| Probability calculation result                                     |
//+------------------------------------------------------------------+
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

#endif