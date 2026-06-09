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
   double icX[200], icY[200];
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

   // Anti-overfitting: dual-condition robustness check (Pardo 2008 standard).
   //
   // Condition 1 — ratio: IS win rate must not exceed OOS by more than 15%.
   //   Previous threshold 1.3 (30% gap) was too generous: a strategy with
   //   IS=65% and OOS=50% had ratio=1.30 and was labeled ROBUST, but a 15-point
   //   drop from IS to OOS indicates meaningful overfitting on the training period.
   //   Pardo recommends <1.10 for publication-quality robustness; we use 1.15
   //   as a practical threshold for live indicators with moderate sample sizes.
   //
   // Condition 2 — absolute: even if ratio <1.15, a 7-point absolute gap still
   //   signals degraded live performance. E.g. IS=55% / OOS=48% → ratio=1.14
   //   (passes condition 1 alone), but 48% OOS is barely above coin-flip.
   bool ratioOK    = (g_walkForward.overfitRatio < 1.15);
   bool absoluteOK = (MathAbs(g_walkForward.isWinRate - g_walkForward.oosWinRate) < 7.0);
   bool hasWins    = (g_walkForward.isWinRate > 0 || g_walkForward.oosWinRate > 0);
   g_walkForward.isRobust = (ratioOK && absoluteOK && hasWins);
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