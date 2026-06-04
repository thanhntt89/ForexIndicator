//+------------------------------------------------------------------+
//|                                              WalkForward.mqh       |
//|                         RSI Advanced - Walk-Forward Validation      |
//|                                                                    |
//| Theory: Pardo (2008) "Evaluation and Optimization of Trading       |
//|         Strategies"                                                |
//|                                                                    |
//| IS/OOS split: Train on old data, validate on recent data           |
//| Rolling performance: Track actual outcomes over time                |
//| Stability check: Detect regime changes                              |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_WALKFORWARD_MQH
#define RSI_ADV_WALKFORWARD_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"
#include "MathUtils.mqh"

//+------------------------------------------------------------------+
//|     SECTION 1: IN-SAMPLE / OUT-OF-SAMPLE SPLIT                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get training split bar index                                       |
//| Signals before this bar = training (in-sample)                     |
//| Signals after this bar = validation (out-of-sample)                |
//+------------------------------------------------------------------+
int GetTrainingSplitIndex()
{
   if(!InpUseWalkForward || g_signalCount < 10)
      return(g_signalCount);  // Use all data if not enough

   double oosPercent = MathMax(10.0, MathMin(30.0, InpOOSPercent));
   int splitIndex = (int)(g_signalCount * (100.0 - oosPercent) / 100.0);

   // Minimum 5 signals in OOS set
   if(g_signalCount - splitIndex < 5)
      splitIndex = MathMax(0, g_signalCount - 5);

   // Minimum 10 signals in IS set
   if(splitIndex < 10)
      return(g_signalCount);  // Not enough data for split

   return(splitIndex);
}

//+------------------------------------------------------------------+
//| Calculate walk-forward metrics                                     |
//| Compare in-sample vs out-of-sample win rates                       |
//+------------------------------------------------------------------+
void CalculateWalkForwardMetrics()
{
   g_walkForward.isWinRate = 0;
   g_walkForward.oosWinRate = 0;
   g_walkForward.overfitRatio = 1.0;
   g_walkForward.isRobust = true;
   g_walkForward.isSamples = 0;
   g_walkForward.oosSamples = 0;

   if(!InpUseWalkForward) return;
   if(g_outcomeCount < 15) return;  // Need minimum data

   int splitIndex = GetTrainingSplitIndex();
   if(splitIndex >= g_outcomeCount) return;

   // Count IS wins/losses
   int isWins = 0, isLosses = 0;
   int oosWins = 0, oosLosses = 0;

   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0) continue;  // Pending

      // Determine if this outcome belongs to IS or OOS
      // Match by signal time against signal array split
      bool isInSample = true;

      // Find matching signal index
      for(int s = 0; s < g_signalCount; s++)
      {
         if(g_signals[s].signalTime == g_outcomes[i].signalTime)
         {
            isInSample = (s < splitIndex);
            break;
         }
      }

      if(isInSample)
      {
         if(g_outcomes[i].outcome > 0) isWins++;
         else isLosses++;
      }
      else
      {
         if(g_outcomes[i].outcome > 0) oosWins++;
         else oosLosses++;
      }
   }

   // Calculate win rates
   g_walkForward.isSamples = isWins + isLosses;
   g_walkForward.oosSamples = oosWins + oosLosses;

   if(g_walkForward.isSamples > 0)
      g_walkForward.isWinRate = (double)isWins / (double)g_walkForward.isSamples * 100.0;

   if(g_walkForward.oosSamples > 0)
      g_walkForward.oosWinRate = (double)oosWins / (double)g_walkForward.oosSamples * 100.0;

   // Overfitting ratio
   if(g_walkForward.oosWinRate > 0)
      g_walkForward.overfitRatio = g_walkForward.isWinRate / g_walkForward.oosWinRate;
   else if(g_walkForward.isWinRate > 0)
      g_walkForward.overfitRatio = 2.0;  // OOS zero but IS positive = overfit
   else
      g_walkForward.overfitRatio = 1.0;  // Both zero

   // Robust if ratio < 1.3 (IS not much better than OOS)
   g_walkForward.isRobust = (g_walkForward.overfitRatio < 1.3);
}

//+------------------------------------------------------------------+
//| Check if signal index is in training set (for probability engine)  |
//+------------------------------------------------------------------+
bool IsInTrainingSet(int signalIndex)
{
   if(!InpUseWalkForward) return(true);  // All data if WF disabled
   return(signalIndex < GetTrainingSplitIndex());
}

//+------------------------------------------------------------------+
//| Get walk-forward display text                                      |
//+------------------------------------------------------------------+
string GetWalkForwardDisplay()
{
   if(!InpUseWalkForward)
      return("Walk-Forward: OFF");

   if(g_walkForward.isSamples < 5 || g_walkForward.oosSamples < 3)
      return("Walk-Forward: Insufficient data (need more signals)");

   string status;
   if(g_walkForward.isRobust)
      status = "ROBUST";
   else
      status = "OVERFIT WARNING";

   return("IS:" + DoubleToString(g_walkForward.isWinRate, 1) + "%" +
          "(n=" + IntegerToString(g_walkForward.isSamples) + ")" +
          " | OOS:" + DoubleToString(g_walkForward.oosWinRate, 1) + "%" +
          "(n=" + IntegerToString(g_walkForward.oosSamples) + ")" +
          " | Ratio:" + DoubleToString(g_walkForward.overfitRatio, 2) +
          " [" + status + "]");
}

//+------------------------------------------------------------------+
//| Get walk-forward display color                                     |
//+------------------------------------------------------------------+
color GetWalkForwardColor()
{
   if(!InpUseWalkForward) return(clrGray);
   if(g_walkForward.isSamples < 5 || g_walkForward.oosSamples < 3) return(clrGray);
   if(g_walkForward.isRobust) return(clrLime);
   return(clrOrange);
}

//+------------------------------------------------------------------+
//|     SECTION 2: ROLLING PERFORMANCE TRACKER                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate rolling performance metrics                              |
//| Uses g_outcomes[] array with resolved outcomes                     |
//+------------------------------------------------------------------+
void CalculateRollingPerformance()
{
   g_rollingPerf.last10WR = 0;
   g_rollingPerf.last20WR = 0;
   g_rollingPerf.last50WR = 0;
   g_rollingPerf.allTimeWR = 0;
   g_rollingPerf.totalTracked = 0;
   g_rollingPerf.isDecreasing = false;

   if(!InpShowRollingPerf) return;

   // Count resolved outcomes (newest first)
   int resolved = 0;
   int wins10 = 0, total10 = 0;
   int wins20 = 0, total20 = 0;
   int wins50 = 0, total50 = 0;
   int winsAll = 0, totalAll = 0;

   // Scan from newest to oldest
   for(int i = g_outcomeCount - 1; i >= 0; i--)
   {
      if(g_outcomes[i].outcome == 0) continue;  // Pending

      resolved++;
      totalAll++;
      if(g_outcomes[i].outcome > 0) winsAll++;

      if(resolved <= 10)
      {
         total10++;
         if(g_outcomes[i].outcome > 0) wins10++;
      }
      if(resolved <= 20)
      {
         total20++;
         if(g_outcomes[i].outcome > 0) wins20++;
      }
      if(resolved <= 50)
      {
         total50++;
         if(g_outcomes[i].outcome > 0) wins50++;
      }
   }

   g_rollingPerf.totalTracked = totalAll;

   if(total10 > 0) g_rollingPerf.last10WR = (double)wins10 / total10 * 100.0;
   if(total20 > 0) g_rollingPerf.last20WR = (double)wins20 / total20 * 100.0;
   if(total50 > 0) g_rollingPerf.last50WR = (double)wins50 / total50 * 100.0;
   if(totalAll > 0) g_rollingPerf.allTimeWR = (double)winsAll / totalAll * 100.0;

   // Detect declining performance
   // Last 10 significantly worse than last 50
   if(total10 >= 5 && total50 >= 20)
      g_rollingPerf.isDecreasing = (g_rollingPerf.last10WR < g_rollingPerf.last50WR * 0.7);
}

//+------------------------------------------------------------------+
//| Get rolling performance display text                               |
//+------------------------------------------------------------------+
string GetRollingPerfDisplay()
{
   if(!InpShowRollingPerf)
      return("Rolling: OFF");

   if(g_rollingPerf.totalTracked < 5)
      return("Rolling: Tracking... (" + IntegerToString(g_rollingPerf.totalTracked) + " signals)");

   string result = "";

   if(g_rollingPerf.totalTracked >= 10)
      result += "10sig:" + DoubleToString(g_rollingPerf.last10WR, 0) + "% ";
   if(g_rollingPerf.totalTracked >= 20)
      result += "20sig:" + DoubleToString(g_rollingPerf.last20WR, 0) + "% ";
   if(g_rollingPerf.totalTracked >= 50)
      result += "50sig:" + DoubleToString(g_rollingPerf.last50WR, 0) + "% ";

   result += "All:" + DoubleToString(g_rollingPerf.allTimeWR, 0) + "%" +
             "(" + IntegerToString(g_rollingPerf.totalTracked) + ")";

   if(g_rollingPerf.isDecreasing)
      result += " !! DECLINING !!";

   return(result);
}

//+------------------------------------------------------------------+
//| Get rolling performance color                                      |
//+------------------------------------------------------------------+
color GetRollingPerfColor()
{
   if(g_rollingPerf.isDecreasing) return(clrRed);
   if(g_rollingPerf.totalTracked < 5) return(clrGray);
   if(g_rollingPerf.allTimeWR >= 45) return(clrLime);
   if(g_rollingPerf.allTimeWR >= 35) return(clrYellow);
   return(clrOrange);
}

//+------------------------------------------------------------------+
//|     SECTION 3: PARAMETER STABILITY CHECK                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if market regime has changed                                 |
//| Compare current ATR/kurtosis with historical average                |
//| Returns warning text if regime shift detected                      |
//+------------------------------------------------------------------+
string CheckRegimeStability()
{
   string warnings = "";

   // Current ATR vs average
   double curATR = iATR(NULL, 0, 14, 0);
   double avgATR = 0;
   int atrCnt = 0;
   for(int i = 1; i <= 100 && i < Bars; i++)
   {
      avgATR += iATR(NULL, 0, 14, i);
      atrCnt++;
   }
   if(atrCnt > 0) avgATR /= atrCnt;

   if(avgATR > 0)
   {
      double atrRatio = curATR / avgATR;
      if(atrRatio > 2.0)
         warnings += "VOL SPIKE(" + DoubleToString(atrRatio, 1) + "x) ";
      else if(atrRatio < 0.4)
         warnings += "VOL DEAD(" + DoubleToString(atrRatio, 1) + "x) ";
   }

   // Check if recent signals are performing differently
   if(g_rollingPerf.totalTracked >= 20 && g_rollingPerf.totalTracked >= 10)
   {
      if(g_rollingPerf.last10WR < 20)
         warnings += "LOW RECENT WR ";
   }

   if(StringLen(warnings) == 0)
      return("Regime: STABLE");

   return("Regime: " + warnings);
}

//+------------------------------------------------------------------+
//| Get regime stability color                                         |
//+------------------------------------------------------------------+
color GetRegimeColor()
{
   string status = CheckRegimeStability();
   if(StringFind(status, "STABLE") >= 0) return(clrLime);
   if(StringFind(status, "SPIKE") >= 0) return(clrRed);
   if(StringFind(status, "DEAD") >= 0) return(clrOrange);
   if(StringFind(status, "LOW") >= 0) return(clrRed);
   return(clrGray);
}

//+------------------------------------------------------------------+
//|     SECTION 4: SPREAD REGIME                                        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Update spread regime data                                          |
//| Track rolling average spread and detect anomalies                   |
//+------------------------------------------------------------------+
void UpdateSpreadRegime()
{
   g_spreadRegime.currentSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;

   // Rolling average from recent bars ATR proxy
   // Since we can't track tick-by-tick spread in indicator,
   // use spread at each bar as approximation
   double sumSpread = 0;
   int count = 0;

   // Sample spread at recent bar closes (approximation)
   // Real spread tracking would need tick data
   for(int i = 1; i <= 50 && i < Bars; i++)
   {
      // Use current spread as proxy (MT4 limitation)
      // In reality this should be historical spread data
      sumSpread += g_spreadRegime.currentSpread;
      count++;
   }

   // Better approximation: use ATR ratio as spread proxy
   // When ATR spikes, spread usually widens
   double curATR = iATR(NULL, 0, 14, 0);
   double avgATR = 0;
   int atrCnt = 0;
   for(int i = 1; i <= 50 && i < Bars; i++)
   {
      avgATR += iATR(NULL, 0, 14, i);
      atrCnt++;
   }
   if(atrCnt > 0) avgATR /= atrCnt;

   // Estimate average spread from current spread × ATR ratio
   if(avgATR > 0 && curATR > 0)
   {
      double normalizedSpread = g_spreadRegime.currentSpread * (avgATR / curATR);
      g_spreadRegime.avgSpread = normalizedSpread;
   }
   else
   {
      g_spreadRegime.avgSpread = g_spreadRegime.currentSpread;
   }

   // Calculate ratio
   if(g_spreadRegime.avgSpread > 0)
      g_spreadRegime.spreadRatio = g_spreadRegime.currentSpread / g_spreadRegime.avgSpread;
   else
      g_spreadRegime.spreadRatio = 1.0;

   // Detect anomalies
   g_spreadRegime.isSpike = (g_spreadRegime.spreadRatio > InpSpreadSpikeMulti);
   g_spreadRegime.isExtreme = (g_spreadRegime.spreadRatio > InpSpreadSpikeMulti * 1.5);
}

//+------------------------------------------------------------------+
//| Get spread regime confidence penalty                               |
//| Returns: 0 = no penalty, negative = reduce confidence              |
//+------------------------------------------------------------------+
int GetSpreadRegimePenalty()
{
   if(!InpUseSpreadRegime) return(0);

   if(g_spreadRegime.isExtreme) return(-15);
   if(g_spreadRegime.isSpike) return(-5);
   return(0);
}

//+------------------------------------------------------------------+
//| Get spread display text                                            |
//+------------------------------------------------------------------+
string GetSpreadDisplay()
{
   if(!InpUseSpreadRegime)
      return("Spread: OFF");

   string status = "NORMAL";
   if(g_spreadRegime.isExtreme) status = "EXTREME";
   else if(g_spreadRegime.isSpike) status = "SPIKE";

   return("Spread: " + status +
          " (" + DoubleToString(g_spreadRegime.spreadRatio, 1) + "x)");
}

//+------------------------------------------------------------------+
//| Get spread display color                                           |
//+------------------------------------------------------------------+
color GetSpreadColor()
{
   if(g_spreadRegime.isExtreme) return(clrRed);
   if(g_spreadRegime.isSpike) return(clrOrange);
   return(clrGray);
}

#endif