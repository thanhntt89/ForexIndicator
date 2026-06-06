//+------------------------------------------------------------------+
//|                                         SessionStatistics.mqh      |
//|                         RSI Advanced - Time-of-Day Win Rate         |
//|                                                                    |
//| Theory: Andersen & Bollerslev (1998) "Intraday Periodicity"        |
//| Market behavior differs by session                                 |
//| Win rate MEASURED from actual signal outcomes, not hardcoded        |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_SESSIONSTATS_MQH
#define RSI_ADV_SESSIONSTATS_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"
#include "Normalize.mqh"
#include "IntermarketAnalysis.mqh"
#include "WalkForward.mqh"

//+------------------------------------------------------------------+
//| Session block definitions (UTC)                                    |
//|   0 = Asian:   00:00 - 07:59 UTC                                  |
//|   1 = London:  08:00 - 11:59 UTC                                  |
//|   2 = Overlap: 12:00 - 15:59 UTC                                  |
//|   3 = LateNY:  16:00 - 21:59 UTC                                  |
//|   Dead zone (22:00-23:59) mapped to Asian (0)                      |
//+------------------------------------------------------------------+
int GetSessionBlock(datetime signalTime)
{
   int utcHour = GetUTCHour(signalTime);

   if(utcHour >= 0 && utcHour < 8)   return(0);  // Asian
   if(utcHour >= 8 && utcHour < 12)  return(1);  // London
   if(utcHour >= 12 && utcHour < 16) return(2);  // Overlap
   if(utcHour >= 16 && utcHour < 22) return(3);  // LateNY

   return(0);  // Dead zone → map to Asian
}

//+------------------------------------------------------------------+
//| Session block name for display                                     |
//+------------------------------------------------------------------+
string GetSessionBlockName(int block)
{
   switch(block)
   {
      case 0: return("Asian");
      case 1: return("London");
      case 2: return("Overlap");
      case 3: return("LateNY");
   }
   return("Unknown");
}

//+------------------------------------------------------------------+
//| Initialize session stats to zero                                   |
//+------------------------------------------------------------------+
void InitSessionStats()
{
   for(int i = 0; i < 4; i++)
   {
      g_sessionStats.wins[i] = 0;
      g_sessionStats.losses[i] = 0;
      g_sessionStats.winRate[i] = 0;
      g_sessionStats.totalPerSession[i] = 0;
   }
}

//+------------------------------------------------------------------+
//| Update session statistics from tracked signal outcomes             |
//| Scans g_outcomes[] array for completed trades                      |
//+------------------------------------------------------------------+
void UpdateSessionStats()
{
   InitSessionStats();
   
   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0) continue;  // Pending, skip

      int block = g_outcomes[i].sessionBlock;
      if(block < 0 || block > 3) continue;

      g_sessionStats.totalPerSession[block]++;
       // --- PATCH #4 ---
      int ci = MathMax(0, MathMin(g_outcomes[i].caseNumber - 1, CASE_COUNT - 1));
      g_sessionStats.totalPerCase[block][ci]++;

      if(g_outcomes[i].outcome > 0)
      {
        g_sessionStats.wins[block]++;
        g_sessionStats.winsPerCase[block][ci]++;
      }   
      else
      {
         g_sessionStats.losses[block]++;
         g_sessionStats.lossesPerCase[block][ci]++;
      }
   }

   // Calculate win rates
   for(int i = 0; i < 4; i++)
   {
        if(g_sessionStats.totalPerSession[i] > 0)
            g_sessionStats.winRate[i] = (double)g_sessionStats.wins[i] /
                                        (double)g_sessionStats.totalPerSession[i];
        else
            g_sessionStats.winRate[i] = 0.5;  // Default neutral when no data
     
        for(int ci = 0; ci < CASE_COUNT; ci++)
        {
            if(g_sessionStats.totalPerCase[i][ci] > 0)
                g_sessionStats.winRatePerCase[i][ci] =
                (double)g_sessionStats.winsPerCase[i][ci] /
                (double)g_sessionStats.totalPerCase[i][ci];
            else
                g_sessionStats.winRatePerCase[i][ci] = -1.0;
        }
   }
}

//+------------------------------------------------------------------+
//| Get MEASURED session quality for current signal                    |
//| Returns: 0.0 - 1.0                                                |
//|                                                                    |
//| If sufficient data (>= 5 signals in this session):                 |
//|   Return MEASURED win rate (data-driven, not hardcoded)            |
//| If insufficient data:                                              |
//|   Return normalized session quality (from Normalize.mqh)           |
//+------------------------------------------------------------------+
double GetMeasuredSessionQuality(int caseNum, datetime signalTime)
{
   int block = GetSessionBlock(signalTime);
   int minSamples = 5;

   // If enough measured data → use measured win rate
   if(g_sessionStats.totalPerSession[block] >= minSamples)
      return(g_sessionStats.winRate[block]);

   // Fallback to normalized (timezone-adjusted) quality
   return(GetSessionQualityNormalized(caseNum, signalTime));
}

//+------------------------------------------------------------------+
//| Track a new signal for session statistics                          |
//| Called when signal is created                                      |
//+------------------------------------------------------------------+
void TrackSignalForSession(datetime signalTime, int caseNum, bool isBuy,
                            double entryPrice, double sl, double tp1)
{
   g_outcomeCount++;
   ArrayResize(g_outcomes, g_outcomeCount);

   int idx = g_outcomeCount - 1;
   g_outcomes[idx].signalTime   = signalTime;
   g_outcomes[idx].caseNumber   = caseNum;
   g_outcomes[idx].isBuy        = isBuy;
   g_outcomes[idx].sessionBlock = GetSessionBlock(signalTime);
   g_outcomes[idx].entryPrice   = entryPrice;
   g_outcomes[idx].stopLoss     = sl;
   g_outcomes[idx].takeProfit1  = tp1;
   g_outcomes[idx].outcome      = 0;  // Pending
   g_outcomes[idx].outcomeTime  = 0;
   g_outcomes[idx].mfe          = 0;
   g_outcomes[idx].mae          = 0;
   g_outcomes[idx].loggedToFile = false;
}

//+------------------------------------------------------------------+
//| Check pending signal outcomes                                      |
//| Scan HISTORICAL bars (not just current price)                      |
//| to resolve outcomes that already happened                          |
//+------------------------------------------------------------------+
void CheckPendingOutcomes()
{
   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome != 0) continue;  // Already resolved

      // Find signal bar index
      int sigBarShift = iBarShift(NULL, 0, g_outcomes[i].signalTime, false);
      if(sigBarShift < 0) continue;

      // Scan bars from signal to current
      for(int b = sigBarShift - 1; b >= 0; b--)
      {
         double barHigh = iHigh(NULL, 0, b);
         double barLow  = iLow(NULL, 0, b);

         // Track MFE / MAE while pending
         if(g_outcomes[i].isBuy)
         {
            double favor = barHigh - g_outcomes[i].entryPrice;
            double advers= g_outcomes[i].entryPrice - barLow;
            if(favor  > g_outcomes[i].mfe) g_outcomes[i].mfe = favor;
            if(advers > g_outcomes[i].mae) g_outcomes[i].mae = advers;
         }
         else
         {
            double favor = g_outcomes[i].entryPrice - barLow;
            double advers= barHigh - g_outcomes[i].entryPrice;
            if(favor  > g_outcomes[i].mfe) g_outcomes[i].mfe = favor;
            if(advers > g_outcomes[i].mae) g_outcomes[i].mae = advers;
         }

         if(g_outcomes[i].isBuy)
         {
            // BUY: SL hit when low <= SL
            if(barLow <= g_outcomes[i].stopLoss)
            {
               g_outcomes[i].outcome = -1;
               g_outcomes[i].outcomeTime = iTime(NULL, 0, b);
               break;
            }
            // BUY: TP1 hit when high >= TP1
            if(barHigh >= g_outcomes[i].takeProfit1)
            {
               g_outcomes[i].outcome = 1;
               g_outcomes[i].outcomeTime = iTime(NULL, 0, b);
               break;
            }
         }
         else
         {
            // SELL: SL hit when high >= SL
            if(barHigh >= g_outcomes[i].stopLoss)
            {
               g_outcomes[i].outcome = -1;
               g_outcomes[i].outcomeTime = iTime(NULL, 0, b);
               break;
            }
            // SELL: TP1 hit when low <= TP1
            if(barLow <= g_outcomes[i].takeProfit1)
            {
               g_outcomes[i].outcome = 1;
               g_outcomes[i].outcomeTime = iTime(NULL, 0, b);
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get session display text for panel                                 |
//+------------------------------------------------------------------+
string GetSessionStatsDisplay()
{
   string result = "";

   for(int i = 0; i < 4; i++)
   {
      if(g_sessionStats.totalPerSession[i] > 0)
      {
         if(StringLen(result) > 0) result += " | ";
         result += GetSessionBlockName(i) + ":" +
                   DoubleToString(g_sessionStats.winRate[i] * 100, 0) + "%" +
                   "(" + IntegerToString(g_sessionStats.totalPerSession[i]) + ")";
      }
   }

   if(StringLen(result) == 0)
      result = "No session data yet";

   return(result);
}

//+------------------------------------------------------------------+
//| Get current session info for display                               |
//+------------------------------------------------------------------+
string GetCurrentSessionDisplay()
{
   int block = GetSessionBlock(TimeCurrent());
   string name = GetSessionBlockName(block);

   double wr = g_sessionStats.winRate[block];
   int n = g_sessionStats.totalPerSession[block];

   if(n >= 5)
      return("Session: " + name + " WR:" + DoubleToString(wr * 100, 1) + "% (n=" + IntegerToString(n) + ")");
   else
      return("Session: " + name + " (insufficient data, n=" + IntegerToString(n) + ")");
}

#endif