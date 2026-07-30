//+------------------------------------------------------------------+
//|                                                   RSICore.mqh      |
//|                         QuantEdge - Core RSI Line Calculation    |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_RSICORE_MQH
#define RSI_ADV_RSICORE_MQH

#include "../Core/Config.mqh"
#include "../Core/MathUtils.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| Calculate all RSI Advanced lines                                   |
//+------------------------------------------------------------------+
void CalculateRSILines(int startBar, int rates_total)
{
   // Raw RSI — route through normalized GMT+0 H4 candles when active
   for(int i = startBar; i < rates_total; i++)
   {
      int barShift = rates_total - 1 - i;
      // [GMT-FIX-B3] Use pre-computed RSI from GMT+0-aligned candles.
      // Must check Period() to route to correct normalized dataset:
      // H4 chart → g_normRSI (built from H1 data, UTC H4 aligned)
      // D1 chart → g_normD1RSI (built from normalized H4, UTC day aligned)
      // Other TFs use native iRSI (H1 boundaries are same for all brokers).
      if(g_gmtNormActive && g_normRSICount > 0 && Period() == TF_H4)
      {
         int normShift = GetNormH4Shift(iTime(NULL, 0, barShift));
         double normVal = (normShift >= 0) ? GetNormRSIByShift(normShift) : EMPTY_VALUE;
         g_rawRSI[i] = (normVal != EMPTY_VALUE) ? normVal
                      : iRSI(NULL, 0, InpRSIPeriod, InpPrice, barShift);
      }
      else if(g_gmtMTFNormNeeded && g_normD1RSICount > 0 && Period() == TF_D1)
      {
         int normShift = GetNormD1Shift(iTime(NULL, 0, barShift));
         double normVal = (normShift >= 0) ? GetNormD1RSIByShift(normShift) : EMPTY_VALUE;
         g_rawRSI[i] = (normVal != EMPTY_VALUE) ? normVal
                      : iRSI(NULL, 0, InpRSIPeriod, InpPrice, barShift);
      }
      else
         g_rawRSI[i] = iRSI(NULL, 0, InpRSIPeriod, InpPrice, barShift);
   }

   // Green = SMA(Fast) of RSI
   int firstGreen = MathMax(startBar, InpRSIPeriod + InpFastMAPeriod - 1);
   for(int i = firstGreen; i < rates_total; i++)
      BufferGreen[i] = CalculateSMA(g_rawRSI, i, InpFastMAPeriod);

   // Red = SMA(Signal) of RSI
   int firstRed = MathMax(startBar, InpRSIPeriod + InpSignalMAPeriod - 1);
   for(int i = firstRed; i < rates_total; i++)
      BufferRed[i] = CalculateSMA(g_rawRSI, i, InpSignalMAPeriod);

   // Orange = SMA(BB) of RSI = BB Middle
   int firstOrange = MathMax(startBar, InpRSIPeriod + InpBBPeriod - 1);
   for(int i = firstOrange; i < rates_total; i++)
      BufferOrange[i] = CalculateSMA(g_rawRSI, i, InpBBPeriod);

   // Bollinger Bands
   for(int i = firstOrange; i < rates_total; i++)
   {
      double mid = BufferOrange[i];
      if(mid == EMPTY_VALUE) { BufferBBUpper[i] = EMPTY_VALUE; BufferBBLower[i] = EMPTY_VALUE; continue; }
      double sd = CalculateStdDev(g_rawRSI, i, InpBBPeriod, mid);
      if(sd == EMPTY_VALUE)  { BufferBBUpper[i] = EMPTY_VALUE; BufferBBLower[i] = EMPTY_VALUE; continue; }
      BufferBBUpper[i] = MathMin(mid + InpBBDeviation * sd, 100.0);
      BufferBBLower[i] = MathMax(mid - InpBBDeviation * sd, 0.0);
   }
}

#endif