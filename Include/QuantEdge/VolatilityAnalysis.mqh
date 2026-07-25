//+------------------------------------------------------------------+
//|                                        VolatilityAnalysis.mqh      |
//|                         QuantEdge - Volatility Structure         |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_VOLATILITYANALYSIS_MQH
#define RSI_ADV_VOLATILITYANALYSIS_MQH

#include "Config.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
//| BB Width Percentile (0-100)                                        |
//+------------------------------------------------------------------+
double GetBBWidthPercentile(int barIndex, int lookback)
{
   if(BufferBBUpper[barIndex] == EMPTY_VALUE || BufferBBLower[barIndex] == EMPTY_VALUE) return(50.0);
   double curWidth = BufferBBUpper[barIndex] - BufferBBLower[barIndex];
   int countBelow = 0, total = 0;
   for(int j = 1; j <= lookback; j++)
   {
      int idx = barIndex - j;
      if(idx < 0) break;
      if(BufferBBUpper[idx] == EMPTY_VALUE || BufferBBLower[idx] == EMPTY_VALUE) continue;
      if((BufferBBUpper[idx] - BufferBBLower[idx]) < curWidth) countBelow++;
      total++;
   }
   if(total == 0) return(50.0);
   return((double)countBelow / (double)total * 100.0);
}

//+------------------------------------------------------------------+
//| ATR state relative to average                                      |
//+------------------------------------------------------------------+
double GetATRState(int barShift)
{
   static double   s_atrResult = 1.0;
   static int       s_atrCachedShift = -1;
   static datetime  s_atrCachedBar = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(barShift == s_atrCachedShift && curBar == s_atrCachedBar)
      return(s_atrResult);
   s_atrCachedShift = barShift;
   s_atrCachedBar = curBar;

   double curATR = iATR(NULL, 0, InpATRPeriod, barShift);
   double avgATR = 0;
   int cnt = 0;
   for(int j = barShift + 1; j <= barShift + 50 && j < Bars; j++)
   {
      avgATR += iATR(NULL, 0, InpATRPeriod, j);
      cnt++;
   }
   if(cnt == 0 || avgATR == 0) { s_atrResult = 1.0; return(1.0); }
   s_atrResult = curATR / (avgATR / cnt);
   return(s_atrResult);
}

//+------------------------------------------------------------------+
//| Volatility confirmation score (0.0 - 1.0)                         |
//+------------------------------------------------------------------+
double GetVolatilityConfirmation(int caseNum, int barIndex, int totalBars)
{
   if(!InpUseVolatFilter) return(0.5);
   int barShift = totalBars - 1 - barIndex;
   double bbPct = GetBBWidthPercentile(barIndex, 50);
   double atrSt = GetATRState(barShift);
   double score = 0.5;
   switch(caseNum)
   {
      case 1: case 2: case 3:
         if(atrSt > 1.2) score = 0.7;
         else if(atrSt < 0.7) score = 0.3;
         break;
      case 4: case 7:
         if(bbPct < 30 && atrSt > 1.0) score = 0.9;
         else if(bbPct < 50) score = 0.6;
         else score = 0.4;
         break;
      case 5: score = 0.5; break;
      case 6:
         if(atrSt > 0.8 && atrSt < 1.5) score = 0.7;
         else score = 0.4;
         break;
   }
   return(score);
}

#endif