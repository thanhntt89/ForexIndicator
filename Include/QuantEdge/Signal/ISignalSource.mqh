//+------------------------------------------------------------------+
//|                                            ISignalSource.mqh      |
//|                   QuantEdge - Signal Source Interface Contract    |
//+------------------------------------------------------------------+
#ifndef QE_ISIGNALSOURCE_MQH
#define QE_ISIGNALSOURCE_MQH

//+------------------------------------------------------------------+
//| SignalResult — standardized output from any signal strategy        |
//+------------------------------------------------------------------+
struct SignalResult
{
   int      caseNumber;      // 0 = no signal, 1-9 RSI, 11-19 MACD, 21-29 ICT
   bool     isBuy;
   double   indicatorValue;  // raw indicator at bar (RSI=green, MACD=histogram)
   double   angleStrength;   // raw momentum metric (strategy-specific scale)
   double   confidence;      // 0.0–1.0 normalized for cross-strategy comparison
};

// Each strategy MUST implement:
// SignalResult XXX_Detect(int i, int totalBars, const double &high[],
//                         const double &low[], const double &close[],
//                         const datetime &time[])
// string XXX_GetCaseName(int caseNum)
// string XXX_GetSourceName()
// void   XXX_Calculate(int startBar, int rates_total)

#endif
