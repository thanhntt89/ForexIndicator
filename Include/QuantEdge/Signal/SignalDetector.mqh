//+------------------------------------------------------------------+
//|                                          SignalDetector.mqh       |
//|               QuantEdge - Signal Detection Orchestrator          |
//|                                                                    |
//| Platform-level gates (cooldown) + strategy chain.                 |
//| Adding a new strategy = include XXXStrategy.mqh + add call here. |
//+------------------------------------------------------------------+
#ifndef QE_SIGNALDETECTOR_MQH
#define QE_SIGNALDETECTOR_MQH

#include "RSIStrategy.mqh"

//+------------------------------------------------------------------+
//| SignalDetector_Detect — platform gates then strategy chain         |
//+------------------------------------------------------------------+
SignalResult SignalDetector_Detect(int i, int rates_total,
                                   const double &high[], const double &low[],
                                   const double &close[], const datetime &time[])
{
   SignalResult empty;
   empty.caseNumber     = 0;
   empty.isBuy          = false;
   empty.indicatorValue = 0.0;
   empty.angleStrength  = 0.0;
   empty.confidence     = 0.0;

   //--- Platform gate: cooldown
   int _cooldown = GetActiveCooldownBars();
   if(_cooldown > 0 && g_signalCount > 0)
   {
      int lastBar = g_signals[g_signalCount-1].barIndex;
      int stableAnchor = rates_total - 500;
      if(InpMaxBars > 500 && lastBar < stableAnchor && i >= stableAnchor)
      { /* crossing anchor — don't carry cooldown from deep history */ }
      else if(i - lastBar < _cooldown)
         return(empty);
   }

   //--- Strategy chain (first-match wins)
   SignalResult result = RSI_Detect(i, rates_total, high, low, close, time);
   if(result.caseNumber != 0) return(result);

   // Future: MACD, ICT, Price Action strategies
   // result = MACD_Detect(i, rates_total, high, low, close, time);
   // if(result.caseNumber != 0) return(result);

   return(empty);
}

//+------------------------------------------------------------------+
//| SignalDetector_Calculate — compute all strategy indicators         |
//+------------------------------------------------------------------+
void SignalDetector_Calculate(int startBar, int rates_total)
{
   RSI_Calculate(startBar, rates_total);
   // Future: MACD_Calculate(startBar, rates_total);
}

//+------------------------------------------------------------------+
//| SignalDetector_GetCaseName — route by case range                   |
//+------------------------------------------------------------------+
string SignalDetector_GetCaseName(int caseNum)
{
   if(caseNum >= 1 && caseNum <= 9)   return(RSI_GetCaseName(caseNum));
   // if(caseNum >= 11 && caseNum <= 19) return(MACD_GetCaseName(caseNum));
   return("Unknown");
}

//+------------------------------------------------------------------+
//| SignalDetector_GetSourceName — route by case range                 |
//+------------------------------------------------------------------+
string SignalDetector_GetSourceName(int caseNum)
{
   if(caseNum >= 1 && caseNum <= 9)   return(RSI_GetSourceName());
   // if(caseNum >= 11 && caseNum <= 19) return(MACD_GetSourceName());
   return("Unknown");
}

#endif
