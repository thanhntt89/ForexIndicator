//+------------------------------------------------------------------+
//|                                         SessionStatistics.mqh      |
//|                         QuantEdge - Time-of-Day Win Rate         |
//|                                                                    |
//| Theory: Andersen & Bollerslev (1998) "Intraday Periodicity"        |
//| Market behavior differs by session                                 |
//| Win rate MEASURED from actual signal outcomes, not hardcoded        |
//+------------------------------------------------------------------+
#ifndef QE_SESSIONSTATS_MQH
#define QE_SESSIONSTATS_MQH

#include "../Core/Config.mqh"
#include "../Core/Structs.mqh"

#ifndef ISBACKTESTMODE_DEFINED
   #ifdef __MQL5__
      #define IsBacktestMode() ((bool)MQLInfoInteger(MQL_TESTER))
   #else
      #define IsBacktestMode() IsTesting()
   #endif
   #define ISBACKTESTMODE_DEFINED
#endif
#include "../Core/Globals.mqh"
#include "Normalize.mqh"
#include "IntermarketAnalysis.mqh"

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

// [ISSUE #5 FIX] GetSessionBlockUTC — accepts pre-converted UTC datetime (signalTimeUTC).
// Unlike GetSessionBlock() which calls GetUTCHour() to convert broker time → UTC each call,
// this variant reads the hour directly from an already-UTC timestamp. Use whenever the
// signal has signalTimeUTC set (> 0) to avoid redundant timezone conversion and eliminate
// broker-offset error accumulation.
int GetSessionBlockUTC(datetime utcTime)
{
   // Guard: if UTC time is zero (old binary-loaded signal without signalTimeUTC),
   // fall back to epoch → maps to Asian (hour 0). Caller should prefer GetSessionBlock()
   // for signals where signalTimeUTC == 0.
   if(utcTime <= 0) return(0);

   MqlDateTime mdt;
   TimeToStruct(utcTime, mdt);
   int h = mdt.hour;

   if(h >= 0  && h < 8)  return(0);  // Asian
   if(h >= 8  && h < 12) return(1);  // London
   if(h >= 12 && h < 16) return(2);  // Overlap
   if(h >= 16 && h < 22) return(3);  // LateNY
   return(0);  // Dead zone (22-23) → Asian
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
   static int s_statsGen           = -1;
   static int s_lastProcessedCount = 0;
   if(s_statsGen != g_tfGeneration) { s_statsGen = g_tfGeneration; s_lastProcessedCount = -1; }

   int resolvedNow = 0;
   for(int i = 0; i < g_outcomeCount; i++)
      if(g_outcomes[i].outcome != 0) resolvedNow++;

   if(resolvedNow == s_lastProcessedCount) return;
   s_lastProcessedCount = resolvedNow;

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
double GetMeasuredSessionQuality(int caseNum, datetime signalTime, datetime signalTimeUTC = 0)
{
   // [ISSUE #5 FIX] Use signalTimeUTC for session block comparison.
   // signalTimeUTC is pre-converted to UTC boundary at signal creation (StoreSignal).
   // Avoids re-running GetUTCHour(broker_time) which can be wrong when GMT offset cache
   // is stale, and eliminates the cross-midnight day-loss bug (Bug 2 root cause).
   // Fallback to broker-time conversion for old signals loaded from binary (signalTimeUTC==0).
   int block = (signalTimeUTC > 0)
                  ? GetSessionBlockUTC(signalTimeUTC)
                  : GetSessionBlock(signalTime);

   int minSamples = 5;

   // If enough measured data → use measured win rate
   if(g_sessionStats.totalPerSession[block] >= minSamples)
      return(g_sessionStats.winRate[block]);

   // Fallback to normalized (timezone-adjusted) quality
   return(GetSessionQualityNormalized(caseNum, signalTime));
}

//+------------------------------------------------------------------+
//| Sort g_outcomes[] ascending by signalTime (insertion sort)        |
//| [BUG#2-FIX] The two-pointer merge in ScanStoredSignalsBoth        |
//| assumes g_outcomes[] is chronologically ordered. This invariant   |
//| holds for live signals (appended in order) but may break when     |
//| outcomes are loaded from CSV where file order ≠ signal order.     |
//| Called once after bulk CSV load in LoadOutcomesFromCSV().         |
//| O(n²) is acceptable: outcome count is hundreds, not thousands.   |
//+------------------------------------------------------------------+
void SortOutcomesByTime()
{
   for(int i = 1; i < g_outcomeCount; i++)
   {
      SignalOutcome key = g_outcomes[i];
      int j = i - 1;
      while(j >= 0 && g_outcomes[j].signalTime > key.signalTime)
      {
         g_outcomes[j + 1] = g_outcomes[j];
         j--;
      }
      g_outcomes[j + 1] = key;
   }
}

//+------------------------------------------------------------------+
//| Track a new signal for session statistics                          |
//| Called when signal is created                                      |
//+------------------------------------------------------------------+
void TrackSignalForSession(datetime signalTime, int caseNum, bool isBuy,
                            double entryPrice, double sl, double tp1,
                            bool willLog = true)
{
   // Skip if already tracked (e.g., loaded from CSV on startup — prevents double-counting)
   for(int i = 0; i < g_outcomeCount; i++)
      if(g_outcomes[i].signalTime == signalTime &&
         g_outcomes[i].caseNumber == caseNum &&
         g_outcomes[i].isBuy == isBuy)
         return;

   g_outcomeCount++;
   // [PERF-FIX P2-4] Reserve 32 extra slots to avoid O(n) realloc on every signal
   ArrayResize(g_outcomes, g_outcomeCount, 32);

   int idx = g_outcomeCount - 1;
   g_outcomes[idx].signalTime   = signalTime;
   g_outcomes[idx].caseNumber   = caseNum;
   g_outcomes[idx].isBuy        = isBuy;
   // [ISSUE #5 FIX] Use GetSessionBlock(signalTime) here — TrackSignalForSession
   // receives broker-local signalTime, not signalTimeUTC (no access to SignalData).
   // The session bucket will be overridden by the correct UTC block in UpdateSessionStats
   // which reads from g_outcomes[].sessionBlock set at outcome-resolve time.
   g_outcomes[idx].sessionBlock = GetSessionBlock(signalTime);
   g_outcomes[idx].entryPrice   = entryPrice;
   g_outcomes[idx].stopLoss     = sl;
   g_outcomes[idx].takeProfit1  = tp1;
   g_outcomes[idx].outcome      = 0;  // Pending
   g_outcomes[idx].outcomeTime  = 0;
   g_outcomes[idx].mfe          = 0;
   g_outcomes[idx].mae          = 0;
   // [DEDUP] Only forward signals (willLog) are CSV-logged. Historical signals are marked
   // as already-logged so CheckAndLogNewlyResolved won't re-write duplicate outcome rows on
   // every fullRecalc (the CSV is no longer wiped). g_outcomes still holds them for the live
   // session/probability calc (which re-resolves every session regardless of this flag).
   g_outcomes[idx].loggedToFile = !willLog;
}

//+------------------------------------------------------------------+
//| Check pending signal outcomes                                      |
//| Scan HISTORICAL bars (not just current price)                      |
//| to resolve outcomes that already happened                          |
//+------------------------------------------------------------------+
void CheckPendingOutcomes()
{
   static datetime s_cpLastBarTime = 0;
   datetime curBarTime = iTime(NULL, 0, 0);
   bool cpNewBar = (curBarTime != s_cpLastBarTime);
   if(cpNewBar) s_cpLastBarTime = curBarTime;

   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome != 0) continue;

      if(!cpNewBar)
      {
         double barHigh = iHigh(NULL, 0, 0);
         double barLow  = iLow(NULL, 0, 0);
         if(g_outcomes[i].isBuy)
         {
            double favor = barHigh - g_outcomes[i].entryPrice;
            double advers= g_outcomes[i].entryPrice - barLow;
            if(favor  > g_outcomes[i].mfe) g_outcomes[i].mfe = favor;
            if(advers > g_outcomes[i].mae) g_outcomes[i].mae = advers;
            if(barLow <= g_outcomes[i].stopLoss)
            { g_outcomes[i].outcome = -1; g_outcomes[i].outcomeTime = curBarTime; }
            else if(barHigh >= g_outcomes[i].takeProfit1)
            { g_outcomes[i].outcome = 1; g_outcomes[i].outcomeTime = curBarTime; }
         }
         else
         {
            double favor = g_outcomes[i].entryPrice - barLow;
            double advers= barHigh - g_outcomes[i].entryPrice;
            if(favor  > g_outcomes[i].mfe) g_outcomes[i].mfe = favor;
            if(advers > g_outcomes[i].mae) g_outcomes[i].mae = advers;
            if(barHigh >= g_outcomes[i].stopLoss)
            { g_outcomes[i].outcome = -1; g_outcomes[i].outcomeTime = curBarTime; }
            else if(barLow <= g_outcomes[i].takeProfit1)
            { g_outcomes[i].outcome = 1; g_outcomes[i].outcomeTime = curBarTime; }
         }
         continue;
      }

      int sigBarShift = iBarShift(NULL, 0, g_outcomes[i].signalTime, false);
      if(sigBarShift < 0) continue;

      for(int b = sigBarShift - 1; b >= 0; b--)
      {
         double barHigh = iHigh(NULL, 0, b);
         double barLow  = iLow(NULL, 0, b);

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
            if(barLow <= g_outcomes[i].stopLoss)
            { g_outcomes[i].outcome = -1; g_outcomes[i].outcomeTime = iTime(NULL, 0, b); break; }
            if(barHigh >= g_outcomes[i].takeProfit1)
            { g_outcomes[i].outcome = 1; g_outcomes[i].outcomeTime = iTime(NULL, 0, b); break; }
         }
         else
         {
            if(barHigh >= g_outcomes[i].stopLoss)
            { g_outcomes[i].outcome = -1; g_outcomes[i].outcomeTime = iTime(NULL, 0, b); break; }
            if(barLow <= g_outcomes[i].takeProfit1)
            { g_outcomes[i].outcome = 1; g_outcomes[i].outcomeTime = iTime(NULL, 0, b); break; }
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

//+------------------------------------------------------------------+
//| Local TF name helper (avoids cross-include with SignalLogger.mqh) |
//+------------------------------------------------------------------+
string SS_GetTFName()
{
   switch(Period())
   {
      case 1:    return("M1");
      case 5:    return("M5");
      case 15:   return("M15");
      case 30:   return("M30");
      case 60:   return("H1");
      case 240:  return("H4");
      case 1440: return("D1");
      case 10080:return("W1");
      case 43200:return("MN");
   }
   return("TF" + IntegerToString(Period()));
}

//+------------------------------------------------------------------+
//| Parse SIGNAL_ID → caseNum, sessionBlock, isBuy, sigTime           |
//| Format: SYMBOL_TF_BUY3_1717574400                                 |
//+------------------------------------------------------------------+
bool ParseOutcomeSignalID(string sid, int &caseNum, int &sessionBlock,
                           bool &isBuy, datetime &sigTime)
{
   int len = StringLen(sid);

   // Find last underscore → epoch part
   int lastUs = -1;
   for(int i = len-1; i >= 0; i--)
      if(StringGetCharacter(sid, i) == '_') { lastUs = i; break; }
   if(lastUs < 0) return(false);

   sigTime = (datetime)StringToInteger(StringSubstr(sid, lastUs+1));
   if(sigTime <= 0) return(false);
   sessionBlock = GetSessionBlock(sigTime);

   string rest = StringSubstr(sid, 0, lastUs);  // e.g. "XAUUSD_H1_BUY3"

   // Find second-to-last underscore → dirCase part
   int secUs = -1;
   int rlen = StringLen(rest);
   for(int i = rlen-1; i >= 0; i--)
      if(StringGetCharacter(rest, i) == '_') { secUs = i; break; }
   if(secUs < 0) return(false);

   string dirCase = StringSubstr(rest, secUs+1);  // e.g. "BUY3" or "SELL12"

   if(StringFind(dirCase, "BUY") == 0)
   {
      isBuy   = true;
      caseNum = (int)StringToInteger(StringSubstr(dirCase, 3));
   }
   else if(StringFind(dirCase, "SELL") == 0)
   {
      isBuy   = false;
      caseNum = (int)StringToInteger(StringSubstr(dirCase, 4));
   }
   else
      return(false);

   return(caseNum >= 1 && caseNum <= CASE_COUNT);
}

//+------------------------------------------------------------------+
//| Read outcomes_*.csv → populate g_outcomes[] as pre-resolved entries|
//| Reads current year + previous year files.                          |
//| Must be called AFTER InitSessionStats() and LoggerInit().          |
//| Calls UpdateSessionStats() internally to rebuild g_sessionStats.   |
//+------------------------------------------------------------------+
void LoadSessionStatsFromOutcomesCSV()
{
   if(!InpEnableSignalLog || IsBacktestMode()) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string tfName = SS_GetTFName();

   for(int y = 0; y < 2; y++)
   {
      int year = dt.year - y;
      string path = InpLogFolder + "\\outcomes_" + Symbol()
                    + "_" + tfName + "_" + IntegerToString(year) + ".csv";

      int fh = FileOpen(path, FILE_READ|FILE_CSV|FILE_ANSI, ',');
      if(fh == INVALID_HANDLE) continue;

      // Skip header line
      do { FileReadString(fh); } while(!FileIsLineEnding(fh) && !FileIsEnding(fh));

      while(!FileIsEnding(fh))
      {
         // outcomes CSV columns (0-indexed):
         // 0:SIGNAL_ID  1:SYMBOL  2:SIGNAL_TIME  3:OUTCOME  4:OUTCOME_TIME
         // 5:EXIT_PRICE  6:BARS_HELD  7:REASON  8:MFE  9:MAE
         string signalId   = FileReadString(fh);   // 0
         if(signalId == "" || FileIsEnding(fh)) break;
         FileReadString(fh);                        // 1: SYMBOL (skip)
         FileReadString(fh);                        // 2: SIGNAL_TIME (skip)
         string outcome    = FileReadString(fh);    // 3: OUTCOME
         string outTimeStr = FileReadString(fh);    // 4: OUTCOME_TIME
         FileReadString(fh);                        // 5: EXIT_PRICE (skip)
         FileReadString(fh);                        // 6: BARS_HELD (skip)
         FileReadString(fh);                        // 7: REASON (skip)
         string mfeStr     = FileReadString(fh);    // 8: MFE
         string maeStr     = FileReadString(fh);    // 9: MAE
         while(!FileIsLineEnding(fh) && !FileIsEnding(fh)) FileReadString(fh);

         if(outcome == "PENDING" || outcome == "UNKNOWN" || outcome == "") continue;

         int outcomeCode = 0;
         if(outcome == "TP1" || outcome == "TP2" || outcome == "TP3") outcomeCode = 1;
         else if(outcome == "SL")       outcomeCode = -1;
         else if(outcome == "REVERSAL") outcomeCode = -2;
         else continue;

         int cn = 0, blk = 0;
         bool ib = false;
         datetime st = 0;
         if(!ParseOutcomeSignalID(signalId, cn, blk, ib, st)) continue;

         // Append as pre-resolved entry (dedup in TrackSignalForSession prevents double-count)
         g_outcomeCount++;
         // [PERF-FIX P2-4] Reserve 64 extra slots during CSV bulk load to avoid O(n) per row
         ArrayResize(g_outcomes, g_outcomeCount, 64);
         int idx = g_outcomeCount - 1;
         g_outcomes[idx].signalTime   = st;
         g_outcomes[idx].caseNumber   = cn;
         g_outcomes[idx].isBuy        = ib;
         g_outcomes[idx].sessionBlock = blk;
         g_outcomes[idx].entryPrice   = 0;
         g_outcomes[idx].stopLoss     = 0;
         g_outcomes[idx].takeProfit1  = 0;
         g_outcomes[idx].outcome      = outcomeCode;
         g_outcomes[idx].outcomeTime  = StringToTime(outTimeStr);
         g_outcomes[idx].mfe          = StringToDouble(mfeStr);
         g_outcomes[idx].mae          = StringToDouble(maeStr);
         g_outcomes[idx].loggedToFile = true;   // already in CSV — skip re-logging
      }
      FileClose(fh);
   }

   // [BUG#2-FIX] Enforce chronological order after CSV load.
   // CSV rows are written in outcome-resolve order, not signal-time order — a signal
   // from bar 100 that resolves on bar 200 can appear in the file after a signal from
   // bar 150 that resolves on bar 160. The two-pointer merge in ScanStoredSignalsBoth
   // requires g_outcomes[] sorted by signalTime; without this sort it would miss matches.
   SortOutcomesByTime();

   // [DEDUP] Remove duplicate resolved outcomes with the same (signalTime, case, dir).
   // The outcomes CSV is no longer wiped on fullRecalc, so the same outcome can be
   // re-logged across sessions (each run re-resolves historical signals). Without this,
   // UpdateSessionStats + the probability hybrid would double-count. Sorted-by-time above,
   // so duplicates of one signal are contiguous -> single O(n) compaction pass.
   {
      int _w = 0;
      for(int _r = 0; _r < g_outcomeCount; _r++)
      {
         bool _dup = false;
         for(int _k = _w - 1; _k >= 0 && g_outcomes[_k].signalTime == g_outcomes[_r].signalTime; _k--)
            if(g_outcomes[_k].caseNumber == g_outcomes[_r].caseNumber &&
               g_outcomes[_k].isBuy      == g_outcomes[_r].isBuy)
            { _dup = true; break; }
         if(_dup) continue;
         if(_w != _r) g_outcomes[_w] = g_outcomes[_r];
         _w++;
      }
      g_outcomeCount = _w;
      ArrayResize(g_outcomes, g_outcomeCount);
   }

   UpdateSessionStats();  // Rebuild g_sessionStats from all loaded outcomes (deduped)
}

//+------------------------------------------------------------------+
//| Binary snapshot path: one file per symbol+TF                      |
//+------------------------------------------------------------------+
string SS_GetBinaryPath()
{
   return(InpLogFolder + "\\RSI_SESS_" + Symbol() + "_" + SS_GetTFName() + ".bin");
}

string SIG_GetBinaryPath()
{
   return(InpLogFolder + "\\RSI_SIG_" + Symbol() + "_" + SS_GetTFName() + ".bin");
}

//+------------------------------------------------------------------+
//| Save g_sessionStats to binary file — called from OnDeinit only    |
//+------------------------------------------------------------------+
void SaveSessionStatsBinary()
{
   if(IsBacktestMode()) return;
   int fh = FileOpen(SS_GetBinaryPath(), FILE_WRITE|FILE_BIN);
   if(fh == INVALID_HANDLE) return;
   FileWriteStruct(fh, g_sessionStats);
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Load g_sessionStats from binary file — microseconds vs CSV seconds |
//| Returns true if loaded successfully                                |
//+------------------------------------------------------------------+
bool LoadSessionStatsBinary()
{
   if(IsBacktestMode()) return(false);
   int fh = FileOpen(SS_GetBinaryPath(), FILE_READ|FILE_BIN);
   if(fh == INVALID_HANDLE) return(false);
   bool ok = (FileReadStruct(fh, g_sessionStats) == sizeof(g_sessionStats));
   FileClose(fh);
   return(ok);
}

//+------------------------------------------------------------------+
//| Save g_signals[] to binary — called from OnDeinit                 |
//| Capped at 5000 newest signals to prevent unbounded file growth.   |
//+------------------------------------------------------------------+
// [STRUCT-VERSION] Binary magic: thay đổi khi SignalData struct thay đổi size.
// LoadAndMergeSignalsBinary sẽ reject file cũ thay vì đọc data corrupt.
// Lịch sử:
//   v1 = 0x52534901 (RSI\x01): struct gốc không có signalTimeUTC
//   v2 = 0x52534902 (RSI\x02): thêm signalTimeUTC (datetime = 8 bytes) — ISSUE #4 FIX
//   v3 = 0x52534903 (RSI\x03): thêm predictedProb (double = 8 bytes) — Brier calibration
#define SIG_BINARY_MAGIC 0x52534903

void SaveSignalsBinary()
{
   if(IsBacktestMode() || g_signalCount == 0) return;
   int fh = FileOpen(SIG_GetBinaryPath(), FILE_WRITE|FILE_BIN);
   if(fh == INVALID_HANDLE) return;
   // Write version magic + struct size as header for forward/backward compat detection
   FileWriteInteger(fh, SIG_BINARY_MAGIC);
   FileWriteInteger(fh, (int)sizeof(SignalData));
   int start = MathMax(0, g_signalCount - 5000);
   int count = g_signalCount - start;
   FileWriteInteger(fh, count);
   for(int i = start; i < g_signalCount; i++)
      FileWriteStruct(fh, g_signals[i]);
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Load old signals from binary and prepend to g_signals[].          |
//| Call AFTER fullRecalc has populated g_signals[] with recent data.  |
//| Only prepends signals older than the current scan window (no       |
//| duplicates). Only signals with a cached sim outcome are loaded     |
//| (barIndex will be set to -1; ProbabilityEngine guards this).       |
//+------------------------------------------------------------------+
void LoadAndMergeSignalsBinary()
{
   if(IsBacktestMode()) return;
   int fh = FileOpen(SIG_GetBinaryPath(), FILE_READ|FILE_BIN);
   if(fh == INVALID_HANDLE) return;

   // [STRUCT-VERSION] Read and validate magic + struct size.
   // File cũ (trước ISSUE #4): không có header → magic sẽ đọc được số signals (~vài trăm),
   // hoàn toàn khác SIG_BINARY_MAGIC → detect được và reject an toàn.
   // File với struct khác size (thêm/bớt field) → structSize mismatch → reject.
   int magic      = FileReadInteger(fh);
   int structSize = FileReadInteger(fh);
   if(magic != SIG_BINARY_MAGIC || structSize != (int)sizeof(SignalData))
   {
      FileClose(fh);
      // Xóa file stale để tránh lần sau load lại — sẽ được rebuild tự động sau OnDeinit.
      FileDelete(SIG_GetBinaryPath());
      Print("[SIG-BIN] Stale binary (magic=", IntegerToString(magic, 8, 16),
            " size=", structSize, " expected=", sizeof(SignalData),
            ") — deleted, will rebuild on next session.");
      return;
   }

   int savedCount = FileReadInteger(fh);
   if(savedCount <= 0 || savedCount > 100000) { FileClose(fh); return; }

   SignalData saved[];
   ArrayResize(saved, savedCount);
   int readOk = 0;
   for(int i = 0; i < savedCount; i++)
   {
      if(FileReadStruct(fh, saved[i]) != (uint)sizeof(SignalData)) break;
      readOk++;
   }
   FileClose(fh);
   if(readOk == 0) return;

   // Only accept signals older than the current scan window start.
   datetime cutoff = (g_signalCount > 0) ? g_signals[0].signalTime : TimeCurrent();

   // Count qualifying old signals: older than cutoff AND outcome already cached.
   // barIndex from the old session is stale; ProbabilityEngine skips simulation
   // for signals where barIndex==-1 and simCachedTP==99.
   int oldCount = 0;
   for(int i = 0; i < readOk; i++)
      if(saved[i].signalTime < cutoff && saved[i].simCachedTP != 99)
         oldCount++;

   if(oldCount == 0) return;

   // Expand array and shift current signals right to make room.
   int newTotal = oldCount + g_signalCount;
   ArrayResize(g_signals, newTotal);
   for(int i = g_signalCount - 1; i >= 0; i--)
      g_signals[i + oldCount] = g_signals[i];

   // Insert old signals at front; mark barIndex=-1 (stale).
   // signalTimeUTC từ binary đã được lưu đúng (struct v2) — dùng trực tiếp không cần recompute.
   int pos = 0;
   for(int i = 0; i < readOk; i++)
   {
      if(saved[i].signalTime < cutoff && saved[i].simCachedTP != 99)
      {
         g_signals[pos]          = saved[i];
         g_signals[pos].barIndex = -1;  // stale; ProbabilityEngine must not access bar arrays
         pos++;
      }
   }
   g_signalCount = newTotal;
}

#endif