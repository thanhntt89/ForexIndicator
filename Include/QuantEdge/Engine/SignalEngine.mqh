//+------------------------------------------------------------------+
//|                                            SignalEngine.mqh        |
//|                         QuantEdge - Composite Signal Scoring     |
//+------------------------------------------------------------------+
#ifndef QE_SIGNALENGINE_MQH
#define QE_SIGNALENGINE_MQH

#include "../Core/Config.mqh"
#include "../Core/Structs.mqh"
#include "../Core/Globals.mqh"
#include "../Analysis/MarketRegime.mqh"
#include "../Analysis/VolumeAnalysis.mqh"
#include "../Analysis/VolatilityAnalysis.mqh"
#include "../Analysis/SessionFilter.mqh"
#include "../Analysis/ADXAnalysis.mqh"
#include "MTFEngine.mqh"

//+------------------------------------------------------------------+
//| Calculate composite signal score                                   |
//+------------------------------------------------------------------+
SignalScore CalculateSignalScore(int caseNum, bool isBuy, int barIndex,
                                 int totalBars, datetime signalTime,
                                 const double &green[],
                                 const double &bbUp[], const double &bbLo[],
                                 double srScoreInput = 50.0)
{
   SignalScore score;

   //--- RSI Base Score - THE MOST IMPORTANT
   double greenDelta = 0;
   if(barIndex >= 2 && green[barIndex-2] != EMPTY_VALUE)
      greenDelta = MathAbs(green[barIndex] - green[barIndex-2]);
   double adaptiveThresh = GetAdaptiveAngleThreshold(barIndex, green);
   
   // Base: how strong is the crossover relative to threshold
   score.rsiScore = MathMin((greenDelta / MathMax(adaptiveThresh, 0.1)) * 60.0, 85.0);
   
   // Bonus for extreme RSI zones
   if(green[barIndex] != EMPTY_VALUE)
   {
      if(isBuy && green[barIndex] < 30)  score.rsiScore += 15;
      if(isBuy && green[barIndex] < 20)  score.rsiScore += 10;
      if(!isBuy && green[barIndex] > 70) score.rsiScore += 15;
      if(!isBuy && green[barIndex] > 80) score.rsiScore += 10;
   }
   
   // Bonus for specific strong cases
   if(caseNum == 1 || caseNum == 2 || caseNum == 4)
      score.rsiScore += 10;  // These cases have built-in strong conditions
   
   score.rsiScore = MathMin(score.rsiScore, 100.0);

   //--- Volume (LOW weight - tick volume unreliable on forex)
   score.volumeScore = GetVolumeConfirmation(caseNum, isBuy, barIndex, totalBars) * 100.0;

   //--- Volatility
   score.volatilityScore = GetVolatilityConfirmation(caseNum, barIndex, totalBars, bbUp, bbLo) * 100.0;

   //--- Session
   score.sessionScore = GetSessionQuality(caseNum, signalTime) * 100.0;

   //--- MTF
   if(InpShowMTF && g_mtfCount > 0)
   {
      int ctxScore = GetMTFContextScore(isBuy);
      score.mtfScore = (double)(ctxScore + 100) / 2.0;
   }
   else
      score.mtfScore = 50.0;

   //--- S/R
   score.srScore = srScoreInput;

   //--- ADX (trend strength; 50.0 neutral / 0 weight when InpUseADXFilter=false)
   score.adxScore = GetADXScore(barIndex);

   //--- Weighted Total
   // RSI is DOMINANT - if RSI signal is clear, other factors are secondary
   if(InpUseADXFilter)
   {
      score.totalScore = score.rsiScore       * 0.45   // RSI dominant, trimmed for ADX
                       + score.volumeScore     * 0.08   // Low - unreliable tick vol
                       + score.volatilityScore * 0.12   // Medium - useful
                       + score.sessionScore    * 0.08   // Low - timezone issues
                       + score.mtfScore        * 0.12   // Medium - useful
                       + score.srScore         * 0.10   // Medium - when available
                       + score.adxScore        * 0.05;  // Trend-strength filter
   }
   else
   {
      score.totalScore = score.rsiScore       * 0.50   // RSI dominant
                       + score.volumeScore     * 0.08   // Low - unreliable tick vol
                       + score.volatilityScore * 0.12   // Medium - useful
                       + score.sessionScore    * 0.08   // Low - timezone issues
                       + score.mtfScore        * 0.12   // Medium - useful
                       + score.srScore         * 0.10;  // Medium - when available
   }

   //--- Quality classification
   if(score.totalScore >= 75)      { score.quality = "HIGH";     score.qualityColor = clrLime;   }
   else if(score.totalScore >= 55) { score.quality = "MODERATE"; score.qualityColor = clrYellow; }
   else if(score.totalScore >= 40) { score.quality = "LOW";      score.qualityColor = clrOrange; }
   else                            { score.quality = "REJECT";   score.qualityColor = clrRed;    }

   return(score);
}

// NOTE: StoreSignal() and FindSignalByArrowName() are in Globals.mqh
// Do NOT duplicate here

#endif