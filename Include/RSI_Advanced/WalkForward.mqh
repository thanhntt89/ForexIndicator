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
//| Information Coefficient (IC)                                       |
//|                                                                    |
//| Measures whether angleStrength (signal "score") actually predicts  |
//| trade outcomes. Computed as Pearson(angleStrength, outcome).       |
//|                                                                    |
//| Interpretation:                                                    |
//|   IC > 0.10: STRONG — angle predicts direction reliably            |
//|   IC 0.05-0.10: WEAK — marginal alpha in the score                 |
//|   IC < 0.05: NOISE — angleStrength has no predictive value         |
//|   IC < 0: INVERSE — strong angle correlates with LOSSES (warning!) |
//|                                                                    |
//| Uses IS-only signals (splitIdx parameter) to prevent lookahead.    |
//+------------------------------------------------------------------+
void CalculateInformationCoefficient(int splitIdx)
{
   // [PROB-FIX-6] Cache per (outcomeCount, splitIdx).
   // IC only changes when new outcomes are resolved or the IS/OOS split shifts.
   // Avoids O(outcomeCount × splitIdx) join on every new bar.
   static int s_icOutcomeCount = -1;
   static int s_icSplitIdx    = -1;
   if(s_icOutcomeCount == g_outcomeCount && s_icSplitIdx == splitIdx) return;
   s_icOutcomeCount = g_outcomeCount;
   s_icSplitIdx     = splitIdx;

   g_walkForward.infoCoeff  = 0.0;
   g_walkForward.icSamples  = 0;
   if(g_outcomeCount < 10 || g_signalCount < 5) return;

   // Collect matched (angleStrength, outcome) pairs.
   // Capped at 200 pairs: Pearson is stable at n=30+, and O(n×m) join
   // on large arrays would add latency. 200 covers ~1 year of M15 signals.
   // [FIX warning] Kh\u1edfi t\u1ea1o icX/icY = 0.0 \u2014 compiler c\u1ea3nh b\u00e1o "possible uninitialized"
   // v\u00ec kh\u00f4ng track \u0111\u01b0\u1ee3c guard i < n \u0111\u1ea3m b\u1ea3o ch\u1ec9 \u0111\u1ecdc sau khi \u0111\u00e3 ghi. Init s\u1eadch h\u01a1n.
   double icX[200], icY[200];
   ArrayInitialize(icX, 0.0);
   ArrayInitialize(icY, 0.0);
   int n = 0;

   for(int i = 0; i < g_outcomeCount && n < 200; i++)
   {
      if(g_outcomes[i].outcome == 0) continue;   // pending

      // Match outcome to its IS signal by signalTime
      for(int s = 0; s < splitIdx && s < g_signalCount; s++)
      {
         if(g_signals[s].signalTime != g_outcomes[i].signalTime) continue;
         if(g_signals[s].angleStrength <= 0.1) break;  // no usable score
         icX[n] = g_signals[s].angleStrength;
         icY[n] = (g_outcomes[i].outcome > 0) ? 1.0 : -1.0;
         n++;
         break;
      }
   }

   if(n < 10) return;
   g_walkForward.icSamples = n;

   // Pearson correlation
   double mx=0.0, my=0.0;
   for(int i=0; i<n; i++) { mx+=icX[i]; my+=icY[i]; }
   mx/=n; my/=n;

   double num=0.0, denX=0.0, denY=0.0;
   for(int i=0; i<n; i++)
   {
      double dx=icX[i]-mx, dy=icY[i]-my;
      num+=dx*dy; denX+=dx*dx; denY+=dy*dy;
   }
   if(denX<=0.0 || denY<=0.0) return;
   g_walkForward.infoCoeff = num / MathSqrt(denX * denY);
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
   g_walkForward.medianRatio = 1.0;
   g_walkForward.rollingCount = 0;
   g_walkForward.permPValue = 1.0;
   g_walkForward.kellyFraction = 0;

   if(!InpUseWalkForward) return;
   if(g_outcomeCount < 15) return;  // Need minimum data

   int splitIndex = GetTrainingSplitIndex();
   if(splitIndex >= g_outcomeCount) return;

   // Count IS wins/losses
   int isWins = 0, isLosses = 0;
   int oosWins = 0, oosLosses = 0;

   datetime splitTime = (splitIndex < g_signalCount) ?
      g_signals[splitIndex].signalTime : (datetime)0;

   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0) continue;
      bool isInSample = (g_outcomes[i].signalTime < splitTime);

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

   // Information Coefficient computation (called here so it shares the split index).
   CalculateInformationCoefficient(splitIndex);

   // Anti-overfitting: robustness check (Pardo 2008 standard).
   //
   // Condition 1 — ratio: IS win rate must not exceed OOS by more than 15%.
   //   Pardo recommends <1.10 for publication-quality; we use 1.15 for live.
   //
   // Condition 2 — absolute: IS must exceed OOS (one-sided, not MathAbs).
   //   OOS > IS is NOT overfit — it means the model generalizes well (or small
   //   OOS sample got lucky). Only penalize when IS > OOS by more than 7 points.
   //   Old code used MathAbs which falsely blocked IS=57%/OOS=75% as "overfit".
   //
   // Condition 3 — minimum OOS: with n<15 OOS, Wilson CI is ±20-25%.
   //   Any ratio/gap verdict is noise. Require n>=15 before declaring overfit.
   //   With n<15, default to robust (benefit of the doubt).
   bool ratioOK    = (g_walkForward.overfitRatio < 1.15);
   double isOosGap = g_walkForward.isWinRate - g_walkForward.oosWinRate;
   bool absoluteOK = (isOosGap < 7.0);
   bool hasWins    = (g_walkForward.isWinRate > 0 || g_walkForward.oosWinRate > 0);
   bool enoughOOS  = (g_walkForward.oosSamples >= 15);
   g_walkForward.isRobust = !enoughOOS || (ratioOK && absoluteOK && hasWins);

   CalculateRollingWalkForward();
   CalculatePermutationPValue();
}

//+------------------------------------------------------------------+
//| Rolling Walk-Forward: K overlapping windows for median overfit     |
//| ratio. Single split can be lucky; median of K splits is robust.   |
//+------------------------------------------------------------------+
void CalculateRollingWalkForward()
{
   g_walkForward.rollingCount = 0;
   g_walkForward.medianRatio  = g_walkForward.overfitRatio;
   for(int r = 0; r < 5; r++) g_walkForward.rollingRatios[r] = 1.0;

   if(!InpUseWalkForward || g_outcomeCount < 30) return;

   int K = 5;
   int minIS = 10, minOOS = 5;
   while(K > 2)
   {
      int windowSize = g_outcomeCount / K;
      int oosSize = (int)(windowSize * 0.2);
      int isSize  = windowSize - oosSize;
      if(isSize >= minIS && oosSize >= minOOS) break;
      K--;
   }
   if(K < 2) return;

   int step = (g_outcomeCount - g_outcomeCount / K) / MathMax(1, K - 1);
   if(step < 1) step = 1;
   int windowSize = g_outcomeCount / K;
   int validK = 0;

   for(int w = 0; w < K && validK < 5; w++)
   {
      int wStart = w * step;
      int wEnd   = MathMin(wStart + windowSize, g_outcomeCount);
      int splitPt = wStart + (int)((wEnd - wStart) * 0.8);

      int isW = 0, isL = 0, oosW = 0, oosL = 0;
      for(int i = wStart; i < wEnd; i++)
      {
         if(g_outcomes[i].outcome == 0) continue;
         if(i < splitPt)
         {
            if(g_outcomes[i].outcome > 0) isW++; else isL++;
         }
         else
         {
            if(g_outcomes[i].outcome > 0) oosW++; else oosL++;
         }
      }
      int isN = isW + isL, oosN = oosW + oosL;
      if(isN < minIS || oosN < minOOS) continue;

      double isWR  = (double)isW / (double)isN;
      double oosWR = (double)oosW / (double)oosN;
      double ratio = (oosWR > 0) ? isWR / oosWR : ((isWR > 0) ? 2.0 : 1.0);
      g_walkForward.rollingRatios[validK] = ratio;
      validK++;
   }

   g_walkForward.rollingCount = validK;
   if(validK < 2) return;

   // Median via insertion sort (K <= 5)
   double sorted[5];
   for(int i = 0; i < validK; i++) sorted[i] = g_walkForward.rollingRatios[i];
   for(int i = 1; i < validK; i++)
   {
      double key = sorted[i];
      int j = i - 1;
      while(j >= 0 && sorted[j] > key) { sorted[j+1] = sorted[j]; j--; }
      sorted[j+1] = key;
   }
   g_walkForward.medianRatio = sorted[validK / 2];

   if(g_walkForward.medianRatio >= 1.15)
      g_walkForward.isRobust = false;
}

//+------------------------------------------------------------------+
//| Permutation test: is edge statistically significant?               |
//| Shuffles outcome directions 100 times, counts how often shuffled  |
//| edge >= actual edge. p-value < 0.05 = significant.                |
//+------------------------------------------------------------------+
void CalculatePermutationPValue()
{
   static int    s_permN   = -1;
   static double s_permRes = 1.0;
   if(s_permN == g_outcomeCount)
   {
      g_walkForward.permPValue = s_permRes;
      return;
   }
   s_permN = g_outcomeCount;

   g_walkForward.permPValue = 1.0;
   if(g_outcomeCount < 20) { s_permRes = 1.0; return; }

   // Compute actual win rate from outcomes
   int wins = 0, total = 0;
   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0) continue;
      total++;
      if(g_outcomes[i].outcome > 0) wins++;
   }
   if(total < 10) { s_permRes = 1.0; return; }
   double actualWR = (double)wins / (double)total;

   // LCG random number generator (deterministic, no MathRand dependency)
   long seed = (long)g_signals[0].signalTime + (long)total;
   int nPerm = 100;
   int countBetter = 0;

   for(int p = 0; p < nPerm; p++)
   {
      int shuffledWins = 0;
      for(int i = 0; i < total; i++)
      {
         seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
         if((seed % 2) == 0) shuffledWins++;
      }
      double shuffledWR = (double)shuffledWins / (double)total;
      if(shuffledWR >= actualWR) countBetter++;
   }

   s_permRes = (double)(countBetter + 1) / (double)(nPerm + 1);
   g_walkForward.permPValue = s_permRes;
}

//+------------------------------------------------------------------+
//| Half-Kelly optimal position size from current probability + R:R   |
//+------------------------------------------------------------------+
void CalculateKellyFraction()
{
   g_walkForward.kellyFraction = 0;
   if(g_currentProb.probTP1 <= 0 || g_currentProb.probSL <= 0) return;
   if(g_activeSignalIndex < 0 || g_activeSignalIndex >= g_signalCount) return;

   double slDist = MathAbs(g_signals[g_activeSignalIndex].entryPrice
                         - g_signals[g_activeSignalIndex].stopLoss);
   double tpDist = MathAbs(g_signals[g_activeSignalIndex].takeProfit1
                         - g_signals[g_activeSignalIndex].entryPrice);
   if(slDist <= 0) return;

   double winRate  = g_currentProb.probTP1 / 100.0;
   double lossRate = 1.0 - winRate;
   double rr       = tpDist / slDist;
   if(rr <= 0) return;

   double kelly = winRate - lossRate / rr;
   double halfKelly = MathMax(0, kelly * 0.5) * 100.0;
   g_walkForward.kellyFraction = MathMin(halfKelly, 5.0);
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

   bool noWins = (g_walkForward.isWinRate == 0 && g_walkForward.oosWinRate == 0);
   string status;
   if(noWins)             status = "NO WIN DATA";
   else if(g_walkForward.isRobust) status = "ROBUST";
   else                   status = "OVERFIT WARNING";

   string ratioStr = noWins ? "N/A" : DoubleToString(g_walkForward.overfitRatio, 2);
   string wfLine = "IS:" + DoubleToString(g_walkForward.isWinRate, 1) + "%" +
                   "(n=" + IntegerToString(g_walkForward.isSamples) + ")" +
                   " | OOS:" + DoubleToString(g_walkForward.oosWinRate, 1) + "%" +
                   "(n=" + IntegerToString(g_walkForward.oosSamples) + ")" +
                   " | Ratio:" + ratioStr +
                   " [" + status + "]";

   // Append IC if computed
   if(g_walkForward.icSamples >= 10)
   {
      double ic = g_walkForward.infoCoeff;
      string icLabel;
      if(MathAbs(ic) < 0.05)       icLabel = "NOISE";
      else if(ic >= 0.10)           icLabel = "STRONG";
      else if(ic >= 0.05)           icLabel = "WEAK";
      else if(ic <= -0.05)          icLabel = "INVERSE!";
      else                          icLabel = "WEAK-";
      wfLine += " | IC:" + DoubleToString(ic, 3) + "[" + icLabel + "]";
   }
   return(wfLine);
}

//+------------------------------------------------------------------+
//| Get walk-forward display color                                     |
//+------------------------------------------------------------------+
color GetWalkForwardColor()
{
   if(!InpUseWalkForward) return(clrGray);
   if(g_walkForward.isSamples < 5 || g_walkForward.oosSamples < 3) return(clrGray);
   if(g_walkForward.isWinRate == 0 && g_walkForward.oosWinRate == 0) return(clrGray);
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
// [PERF-FIX P2-3] Cache CheckRegimeStability per-bar — was 100 iATR calls,
// and GetRegimeColor called it again (200 iATR total per panel draw).
string g_cachedRegimeText = "Regime: STABLE";
color  g_cachedRegimeColor = clrLime;
datetime g_regimeCacheBarTime = 0;

string CheckRegimeStability()
{
   datetime curBar = iTime(NULL, 0, 0);
   if(curBar == g_regimeCacheBarTime) return(g_cachedRegimeText);
   g_regimeCacheBarTime = curBar;

   string warnings = "";

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

   if(g_rollingPerf.totalTracked >= 20 && g_rollingPerf.totalTracked >= 10)
   {
      if(g_rollingPerf.last10WR < 20)
         warnings += "LOW RECENT WR ";
   }

   // [GMT-FIX-B4] Cross-TF data quality: H4 extreme WR but lower TFs have valid trends
   // suggests broker GMT offset is causing anomalous H4 simulation results.
   if(Period() >= TF_H4 && g_rollingPerf.totalTracked >= 10)
   {
      bool h4Extreme = (g_rollingPerf.allTimeWR < 15.0 || g_rollingPerf.allTimeWR > 90.0);
      if(h4Extreme && g_mtfCount > 0)
      {
         bool lowerTFOk = false;
         for(int m = 0; m < g_mtfCount; m++)
            if(g_mtfData[m].timeframe < TF_H4 && g_mtfData[m].trend != 0)
               lowerTFOk = true;
         if(lowerTFOk)
            warnings += "TF MISMATCH? ";
      }
   }

   if(StringLen(warnings) == 0)
   {
      g_cachedRegimeText = "Regime: STABLE";
      g_cachedRegimeColor = clrLime;
   }
   else
   {
      g_cachedRegimeText = "Regime: " + warnings;
      // [PERF-FIX P2-3] Compute color in same call to avoid double-call from GetRegimeColor
      if(StringFind(warnings, "SPIKE") >= 0) g_cachedRegimeColor = clrRed;
      else if(StringFind(warnings, "DEAD") >= 0) g_cachedRegimeColor = clrOrange;
      else if(StringFind(warnings, "LOW") >= 0) g_cachedRegimeColor = clrRed;
      else g_cachedRegimeColor = clrGray;
   }
   return(g_cachedRegimeText);
}

//+------------------------------------------------------------------+
//| Get regime stability color                                         |
//+------------------------------------------------------------------+
color GetRegimeColor()
{
   // [PERF-FIX P2-3] Uses cached color from CheckRegimeStability instead of re-calling it
   CheckRegimeStability();
   return(g_cachedRegimeColor);
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
   // [PROB-FIX-7] Per-bar cache — 50 iATR calls for avgATR; only recompute on new bar.
   // currentSpread updates every tick (live), avgSpread/ratio only need per-bar refresh.
   static datetime s_spreadBarTime = 0;
   datetime s_spreadCurBar = iTime(NULL, 0, 0);
   bool spreadNewBar = (s_spreadCurBar != s_spreadBarTime);
   if(spreadNewBar) s_spreadBarTime = s_spreadCurBar;

   g_spreadRegime.currentSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;

   if(!spreadNewBar)
   {
      // Tick-level: recompute ratio from live spread vs cached avgSpread
      if(g_spreadRegime.avgSpread > 0)
         g_spreadRegime.spreadRatio = g_spreadRegime.currentSpread / g_spreadRegime.avgSpread;
      g_spreadRegime.isSpike   = (g_spreadRegime.spreadRatio > InpSpreadSpikeMulti);
      g_spreadRegime.isExtreme = (g_spreadRegime.spreadRatio > InpSpreadSpikeMulti * 1.5);
      return;
   }

   // [PERF-FIX P2-3] Removed dead loop (lines 452-458) that summed currentSpread 50 times
   // producing sumSpread = 50 * currentSpread, which was never used.
   // ATR-based estimation below is the actual spread approximation.
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