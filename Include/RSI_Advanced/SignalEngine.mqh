//+------------------------------------------------------------------+
//|                                            SignalEngine.mqh        |
//|                         RSI Advanced - Composite Signal Scoring     |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_SIGNALENGINE_MQH
#define RSI_ADV_SIGNALENGINE_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"
#include "MarketRegime.mqh"
#include "VolumeAnalysis.mqh"
#include "VolatilityAnalysis.mqh"
#include "SessionFilter.mqh"
#include "MTFEngine.mqh"

//+------------------------------------------------------------------+
//| Calculate composite signal score                                   |
//+------------------------------------------------------------------+
SignalScore CalculateSignalScore(int caseNum, bool isBuy, int barIndex,
                                 int totalBars, datetime signalTime,
                                 double srScoreInput = 50.0)
{
   SignalScore score;

   //--- RSI Base Score - THE MOST IMPORTANT
   double greenDelta = 0;
   if(barIndex >= 2 && BufferGreen[barIndex-2] != EMPTY_VALUE)
      greenDelta = MathAbs(BufferGreen[barIndex] - BufferGreen[barIndex-2]);
   double adaptiveThresh = GetAdaptiveAngleThreshold(barIndex);
   
   // Base: how strong is the crossover relative to threshold
   score.rsiScore = MathMin((greenDelta / MathMax(adaptiveThresh, 0.1)) * 60.0, 85.0);
   
   // Bonus for extreme RSI zones
   if(BufferGreen[barIndex] != EMPTY_VALUE)
   {
      if(isBuy && BufferGreen[barIndex] < 30)  score.rsiScore += 15;
      if(isBuy && BufferGreen[barIndex] < 20)  score.rsiScore += 10;
      if(!isBuy && BufferGreen[barIndex] > 70) score.rsiScore += 15;
      if(!isBuy && BufferGreen[barIndex] > 80) score.rsiScore += 10;
   }
   
   // Bonus for specific strong cases
   if(caseNum == 1 || caseNum == 2 || caseNum == 4)
      score.rsiScore += 10;  // These cases have built-in strong conditions
   
   score.rsiScore = MathMin(score.rsiScore, 100.0);

   //--- Volume (LOW weight - tick volume unreliable on forex)
   score.volumeScore = GetVolumeConfirmation(caseNum, isBuy, barIndex, totalBars) * 100.0;

   //--- Volatility
   score.volatilityScore = GetVolatilityConfirmation(caseNum, barIndex, totalBars) * 100.0;

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

   //--- Weighted Total
   // RSI is DOMINANT - if RSI signal is clear, other factors are secondary
   // Old weights caused good RSI signals to be rejected by weak volume/session
   //
   // New philosophy:
   //   RSI alone >= 70 → signal should ALWAYS pass (score >= 70 * 0.50 = 35 minimum)
   //   Other factors can BOOST but should not KILL a valid RSI signal
   
   score.totalScore = score.rsiScore       * 0.50   // RSI dominant
                    + score.volumeScore     * 0.08   // Low - unreliable tick vol
                    + score.volatilityScore * 0.12   // Medium - useful
                    + score.sessionScore    * 0.08   // Low - timezone issues
                    + score.mtfScore        * 0.12   // Medium - useful
                    + score.srScore         * 0.10;  // Medium - when available

   //--- Quality classification
   if(score.totalScore >= 75)      { score.quality = "HIGH";     score.qualityColor = clrLime;   }
   else if(score.totalScore >= 55) { score.quality = "MODERATE"; score.qualityColor = clrYellow; }
   else if(score.totalScore >= 40) { score.quality = "LOW";      score.qualityColor = clrOrange; }
   else                            { score.quality = "REJECT";   score.qualityColor = clrRed;    }

   return(score);
}

//+------------------------------------------------------------------+
//| Store signal                                                       |
//+------------------------------------------------------------------+
void StoreSignal(datetime t, int barIdx, int caseNum, bool isBuy,
                 double entry, double sl, double tp1, double tp2, double tp3, double atr)
{
   g_signalCount++;
   ArrayResize(g_signals, g_signalCount);
   int idx = g_signalCount - 1;
   g_signals[idx].signalTime  = t;
   g_signals[idx].barIndex    = barIdx;
   g_signals[idx].caseNumber  = caseNum;
   g_signals[idx].isBuySignal = isBuy;
   g_signals[idx].entryPrice  = entry;
   g_signals[idx].stopLoss    = sl;
   g_signals[idx].takeProfit1 = tp1;
   g_signals[idx].takeProfit2 = tp2;
   g_signals[idx].takeProfit3 = tp3;
   g_signals[idx].atrValue    = atr;
}

//+------------------------------------------------------------------+
//| Find signal by arrow object name                                   |
//+------------------------------------------------------------------+
int FindSignalByArrowName(string arrowName)
{
   string parts[];
   int cnt = StringSplit(arrowName, '_', parts);
   if(cnt < 5) return(-1);
   bool isBuy = (parts[2] == "BUY");
   int caseNum = (int)StringToInteger(parts[3]);
   datetime sigTime = (datetime)StringToInteger(parts[4]);
   for(int i = g_signalCount - 1; i >= 0; i--)
      if(g_signals[i].signalTime == sigTime && g_signals[i].caseNumber == caseNum && g_signals[i].isBuySignal == isBuy)
         return(i);
   return(-1);
}

#endif