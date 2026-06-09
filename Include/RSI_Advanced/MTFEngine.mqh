//+------------------------------------------------------------------+
//|                                               MTFEngine.mqh        |
//|                         RSI Advanced - Multi-Timeframe Engine       |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_MTFENGINE_MQH
#define RSI_ADV_MTFENGINE_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
double CalculateMTF_SMA_RSI_Shifted(int timeframe, int period, int shift)
{
   double sum = 0;
   for(int j = 0; j < period; j++)
   {
      double rsiVal = iRSI(NULL, timeframe, InpRSIPeriod, InpPrice, shift + j);
      if(rsiVal == 0) return(0);
      sum += rsiVal;
   }
   return(sum / (double)period);
}

double CalculateMTF_SMA_RSI(int timeframe, int period)
{
   return(CalculateMTF_SMA_RSI_Shifted(timeframe, period, 0));
}

//+------------------------------------------------------------------+
int GetMTFTrend(int timeframe)
{
   double greenVal = CalculateMTF_SMA_RSI(timeframe, InpFastMAPeriod);
   double redVal   = CalculateMTF_SMA_RSI(timeframe, InpSignalMAPeriod);
   if(greenVal == 0 || redVal == 0) return(0);

   double greenDelta = greenVal - CalculateMTF_SMA_RSI_Shifted(timeframe, InpFastMAPeriod, 2);
   if(greenVal > redVal && greenDelta >= InpAngleThreshold * 0.5) return(1);
   if(greenVal < redVal && greenDelta <= -InpAngleThreshold * 0.5) return(-1);
   return(0);
}

//+------------------------------------------------------------------+
string GetMTFStatusText(int trend, double greenVal, double redVal, double orangeVal)
{
   if(trend == 1)
   {
      if(greenVal > 68) return("BULL (Overbought)");
      if(greenVal > 50) return("BULL (Strong)");
      return("BULL (Weak)");
   }
   if(trend == -1)
   {
      if(greenVal < 32) return("BEAR (Oversold)");
      if(greenVal < 50) return("BEAR (Strong)");
      return("BEAR (Weak)");
   }
   if(MathAbs(greenVal - redVal) < 3) return("NEUTRAL (Sideway)");
   return("NEUTRAL");
}

//+------------------------------------------------------------------+
datetime g_mtfLastBarTime[6];
bool     g_mtfCacheValid[6];

void InitMTFCache()
{
   for(int i = 0; i < 6; i++)
   { g_mtfLastBarTime[i] = 0; g_mtfCacheValid[i] = false; }
}

void CheckAndAddMTF(int timeframe, string tfName, bool enabled, int currentTF)
{
   if(!enabled || timeframe <= currentTF || g_mtfCount >= 6) return;
   if(iBars(NULL, timeframe) < InpBBPeriod + InpRSIPeriod + 5) return;

   int idx = g_mtfCount;
   datetime htfBarTime = iTime(NULL, timeframe, 0);
   if(g_mtfCacheValid[idx] && htfBarTime == g_mtfLastBarTime[idx])
   {
      g_mtfCount++;
      return;
   }
   g_mtfLastBarTime[idx] = htfBarTime;
   g_mtfCacheValid[idx]  = true;

   g_mtfData[idx].timeframe   = timeframe;
   g_mtfData[idx].tfName      = tfName;
   g_mtfData[idx].greenValue  = CalculateMTF_SMA_RSI(timeframe, InpFastMAPeriod);
   g_mtfData[idx].redValue    = CalculateMTF_SMA_RSI(timeframe, InpSignalMAPeriod);
   g_mtfData[idx].orangeValue = CalculateMTF_SMA_RSI(timeframe, InpBBPeriod);
   g_mtfData[idx].trend       = GetMTFTrend(timeframe);
   g_mtfData[idx].statusText  = GetMTFStatusText(g_mtfData[idx].trend, g_mtfData[idx].greenValue, g_mtfData[idx].redValue, g_mtfData[idx].orangeValue);
   g_mtfCount++;
}

void RefreshMTFData()
{
   g_mtfCount = 0;
   int currentTF = Period();
   CheckAndAddMTF(PERIOD_M5,  "M5",  InpMTF_M5,  currentTF);
   CheckAndAddMTF(PERIOD_M15, "M15", InpMTF_M15, currentTF);
   CheckAndAddMTF(PERIOD_M30, "M30", InpMTF_M30, currentTF);
   CheckAndAddMTF(PERIOD_H1,  "H1",  InpMTF_H1,  currentTF);
   CheckAndAddMTF(PERIOD_H4,  "H4",  InpMTF_H4,  currentTF);
   CheckAndAddMTF(PERIOD_D1,  "D1",  InpMTF_D1,  currentTF);
}

//+------------------------------------------------------------------+
int CalculateMTFAgreement()
{
   if(g_mtfCount == 0) return(0);
   double bullW = 0, bearW = 0, totalW = 0;
   for(int i = 0; i < g_mtfCount; i++)
   {
      double w = 1.0;
      if(g_mtfData[i].timeframe >= PERIOD_H4) w = 3.0;
      else if(g_mtfData[i].timeframe >= PERIOD_H1) w = 2.0;
      else if(g_mtfData[i].timeframe >= PERIOD_M30) w = 1.5;
      else if(g_mtfData[i].timeframe >= PERIOD_M15) w = 1.0;
      // M5: w = 1.0 (default, immediate next TF for M1)
      if(g_mtfData[i].trend == 1) bullW += w;
      if(g_mtfData[i].trend == -1) bearW += w;
      totalW += w;
   }
   if(totalW == 0) return(0);
   return((int)MathRound(((bullW - bearW) / totalW) * 100.0));
}

//+------------------------------------------------------------------+
int GetMTFContextScore(bool isBuySignal)
{
   if(!InpShowMTF || g_mtfCount == 0) return(0);
   double score = 0, totalWeight = 0;
   for(int i = 0; i < g_mtfCount; i++)
   {
      double w = 1.0;
      if(g_mtfData[i].timeframe >= PERIOD_H4) w = 3.0;
      else if(g_mtfData[i].timeframe >= PERIOD_H1) w = 2.0;
      else if(g_mtfData[i].timeframe >= PERIOD_M30) w = 1.5;
      else if(g_mtfData[i].timeframe >= PERIOD_M15) w = 1.0;
      // M5: w = 1.0 (default, immediate next TF for M1)

      double alignment = isBuySignal ? (double)g_mtfData[i].trend : -(double)g_mtfData[i].trend;
      double strength = MathAbs(g_mtfData[i].greenValue - 50.0) / 50.0;
      alignment *= (1.0 + strength);
      score += alignment * w;
      totalWeight += w;
   }
   if(totalWeight == 0) return(0);
   return(MathMax(-100, MathMin(100, (int)MathRound((score / totalWeight) * 100.0))));
}

#endif