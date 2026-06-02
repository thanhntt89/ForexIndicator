//+------------------------------------------------------------------+
//|                                            MarketRegime.mqh        |
//|                         RSI Advanced - Market Regime Detection      |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_MARKETREGIME_MQH
#define RSI_ADV_MARKETREGIME_MQH

#include "Config.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
//| Detect market regime: 1=uptrend, -1=downtrend, 0=ranging           |
//+------------------------------------------------------------------+
int DetectMarketRegime(int barIndex)
{
   if(!InpUseRegimeFilter) return(0);
   if(barIndex < 20) return(0);
   if(BufferOrange[barIndex] == EMPTY_VALUE || BufferOrange[barIndex-10] == EMPTY_VALUE) return(0);

   double orangeSlope = BufferOrange[barIndex] - BufferOrange[barIndex-10];
   double bbWidth = 0;
   if(BufferBBUpper[barIndex] != EMPTY_VALUE && BufferBBLower[barIndex] != EMPTY_VALUE)
      bbWidth = BufferBBUpper[barIndex] - BufferBBLower[barIndex];

   double avgBBWidth = 0;
   int cnt = 0;
   for(int j = 0; j < 20; j++)
   {
      int idx = barIndex - j;
      if(idx < 0) break;
      if(BufferBBUpper[idx] != EMPTY_VALUE && BufferBBLower[idx] != EMPTY_VALUE)
      {
         avgBBWidth += BufferBBUpper[idx] - BufferBBLower[idx];
         cnt++;
      }
   }
   if(cnt > 0) avgBBWidth /= cnt;

   if(MathAbs(orangeSlope) > 5.0 && bbWidth >= avgBBWidth * 0.8)
      return(orangeSlope > 0 ? 1 : -1);

   return(0);
}

//+------------------------------------------------------------------+
//| Adaptive angle threshold based on RSI volatility                   |
//+------------------------------------------------------------------+
double GetAdaptiveAngleThreshold(int barIndex)
{
   if(barIndex < 20) return(InpAngleThreshold);
   double sum = 0, sumSq = 0;
   int count = 0;
   for(int j = 0; j < 20; j++)
   {
      int idx = barIndex - j;
      if(idx < 1 || BufferGreen[idx] == EMPTY_VALUE || BufferGreen[idx-1] == EMPTY_VALUE) continue;
      double delta = BufferGreen[idx] - BufferGreen[idx-1];
      sum += delta; sumSq += delta * delta; count++;
   }
   if(count < 10) return(InpAngleThreshold);
   double variance = (sumSq / count) - ((sum / count) * (sum / count));
   double stddev = MathSqrt(MathMax(variance, 0));
   return(MathMax(stddev * 1.5, 2.0));
}

#endif