//+------------------------------------------------------------------+
//|                                            VolumeAnalysis.mqh      |
//|                         QuantEdge - Volume Confirmation         |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_VOLUMEANALYSIS_MQH
#define RSI_ADV_VOLUMEANALYSIS_MQH

#include "../Core/Config.mqh"

//+------------------------------------------------------------------+
//| Volume relative to average                                         |
//+------------------------------------------------------------------+
double GetVolumeRatio(int barShift, int lookback)
{
   double curVol = (double)iVolume(NULL, 0, barShift);
   if(curVol == 0) return(0);
   double avgVol = 0;
   int cnt = 0;
   for(int j = barShift + 1; j <= barShift + lookback && j < Bars; j++)
   {
      avgVol += (double)iVolume(NULL, 0, j);
      cnt++;
   }
   if(cnt == 0 || avgVol == 0) return(1.0);
   return(curVol / (avgVol / cnt));
}

//+------------------------------------------------------------------+
//| Volume trend: 1=increasing, -1=decreasing, 0=flat                 |
//+------------------------------------------------------------------+
int GetVolumeTrend(int barShift, int lookback)
{
   if(lookback < 4) return(0);
   double firstHalf = 0, secondHalf = 0;
   int half = lookback / 2;
   for(int j = 0; j < half; j++)
   {
      int idx = barShift + j;
      if(idx >= Bars) break;
      secondHalf += (double)iVolume(NULL, 0, idx);
   }
   for(int j = half; j < lookback; j++)
   {
      int idx = barShift + j;
      if(idx >= Bars) break;
      firstHalf += (double)iVolume(NULL, 0, idx);
   }
   if(firstHalf == 0) return(0);
   double ratio = secondHalf / firstHalf;
   if(ratio > 1.2) return(1);
   if(ratio < 0.8) return(-1);
   return(0);
}

//+------------------------------------------------------------------+
//| Volume confirmation score per case (0.0 - 1.0)                    |
//+------------------------------------------------------------------+
double GetVolumeConfirmation(int caseNum, bool isBuy, int barNonSeries, int totalBars)
{
   if(!InpUseVolumeFilter) return(0.5);
   int barShift = totalBars - 1 - barNonSeries;
   if(barShift < 0 || barShift >= Bars) return(0.5);
   double volRatio = GetVolumeRatio(barShift, 20);
   int volTrend = GetVolumeTrend(barShift, 10);
   double score = 0.5;
   switch(caseNum)
   {
      case 1: case 5:
         if(volRatio > 1.5) score = 0.8;
         else if(volRatio > 1.2) score = 0.65;
         else if(volRatio < 0.7) score = 0.2;
         break;
      case 2: case 3:
         if(volTrend == -1) score = 0.8;
         else if(volTrend == 0) score = 0.5;
         else score = 0.3;
         break;
      case 4:
         if(volRatio > 1.3 && volTrend == 1) score = 0.9;
         else if(volRatio > 1.0) score = 0.6;
         else score = 0.3;
         break;
      case 6:
         if(volTrend == 1 && volRatio > 1.0) score = 0.75;
         else if(volTrend == -1) score = 0.3;
         else score = 0.5;
         break;
      case 7:
         if(volRatio > 1.5) score = 0.85;
         else if(volRatio > 1.2) score = 0.65;
         else score = 0.25;
         break;
   }
   return(score);
}

#endif