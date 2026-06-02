//+------------------------------------------------------------------+
//|                                                   RSICore.mqh      |
//|                         RSI Advanced - Core RSI Line Calculation    |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_RSICORE_MQH
#define RSI_ADV_RSICORE_MQH

#include "Config.mqh"
#include "MathUtils.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
//| Calculate all RSI Advanced lines                                   |
//+------------------------------------------------------------------+
void CalculateRSILines(int startBar, int rates_total)
{
   // Raw RSI
   for(int i = startBar; i < rates_total; i++)
   {
      int barShift = rates_total - 1 - i;
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