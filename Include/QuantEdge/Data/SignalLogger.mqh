//+------------------------------------------------------------------+
//|                                            SignalLogger.mqh        |
//|                         QuantEdge - Signal Logging to CSV       |
//|                                                                    |
//| Ghi 3 file CSV comma-separated vào MQL4/Files/<InpLogFolder>/:      |
//|   signals_SYMBOL_TF_YYYY.csv  — 1 dòng mỗi tín hiệu mới          |
//|   scoring_SYMBOL_TF_YYYY.csv  — decision context per active signal |
//|   outcomes_SYMBOL_TF_YYYY.csv — append khi outcome resolved        |
//|                                                                    |
//| JOIN: signals ← scoring ← outcomes on SIGNAL_ID                    |
//+------------------------------------------------------------------+
#ifndef QE_SIGNALLOGGER_MQH
#define QE_SIGNALLOGGER_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"

#ifndef ISBACKTESTMODE_DEFINED
   #ifdef __MQL5__
      #define IsBacktestMode() ((bool)MQLInfoInteger(MQL_TESTER))
   #else
      #define IsBacktestMode() IsTesting()
   #endif
   #define ISBACKTESTMODE_DEFINED
#endif

//+------------------------------------------------------------------+
//| State: tránh reinit header nhiều lần                               |
//+------------------------------------------------------------------+
static bool     s_loggerReady        = false;
static bool     s_signalHeaderOK     = false;
static bool     s_outcomeHeaderOK    = false;
static datetime s_lastLoggedScoreTime = 0;  // module-level: can be reset by LoggerInit(true)

// Memory buffer for logs (Non-blocking queue)
static string s_signalQueue[];
static int    s_signalQueueCount = 0;

static string s_outcomeQueue[];
static int    s_outcomeQueueCount = 0;

static string s_scoringQueue[];
static int    s_scoringQueueCount = 0;

//+------------------------------------------------------------------+
//| Helper: Push a signal log row to memory queue                     |
//+------------------------------------------------------------------+
void QueueSignalRow(string row)
{
   int size = ArraySize(s_signalQueue);
   if(s_signalQueueCount >= size)
   {
      ArrayResize(s_signalQueue, size + 128);
   }
   s_signalQueue[s_signalQueueCount++] = row;
}

//+------------------------------------------------------------------+
//| Helper: Push an outcome log row to memory queue                  |
//+------------------------------------------------------------------+
void QueueOutcomeRow(string row)
{
   int size = ArraySize(s_outcomeQueue);
   if(s_outcomeQueueCount >= size)
   {
      ArrayResize(s_outcomeQueue, size + 128);
   }
   s_outcomeQueue[s_outcomeQueueCount++] = row;
}

void QueueScoringRow(string row)
{
   int size = ArraySize(s_scoringQueue);
   if(s_scoringQueueCount >= size)
   {
      ArrayResize(s_scoringQueue, size + 128);
   }
   s_scoringQueue[s_scoringQueueCount++] = row;
}

//+------------------------------------------------------------------+
//| Quant helpers — compute log fields from live data                  |
//+------------------------------------------------------------------+

// Find trend of a specific TF from g_mtfData[] (loop by timeframe value).
// Returns: 1=bull, -1=bear, 0=neutral/not loaded
int SL_GetMTFTrendForTF(int targetTF)
{
   for(int i = 0; i < g_mtfCount; i++)
      if(g_mtfData[i].timeframe == targetTF) return(g_mtfData[i].trend);
   return(0);
}

// ATR_RATIO: current ATR / 50-bar average ATR — numeric vol regime.
// 1.0 = normal, <0.7 = quiet, >1.5 = elevated, >1.8 = event
// Cache per bar — iATR with period 50 creates a separate indicator buffer;
// caching avoids redundant handle lookups when multiple signals fire on same bar.
double SL_GetATRRatio(int barShift)
{
   static int    s_lastShift = -1;
   static double s_lastRatio = 1.0;
   if(barShift == s_lastShift) return(s_lastRatio);
   s_lastShift = barShift;

   double cur = iATR(NULL, 0, InpATRPeriod, barShift);
   double avg = iATR(NULL, 0, 50,           barShift);
   s_lastRatio = (avg > 0 && cur > 0) ? NormalizeDouble(cur / avg, 3) : 1.0;
   return(s_lastRatio);
}

// Pip size without depending on Normalize.mqh
double SL_PipSize()
{
   string s = Symbol();
   if(StringFind(s,"XAU")>=0||StringFind(s,"GOLD")>=0) return(0.1);
   if(StringFind(s,"XAG")>=0||StringFind(s,"SILVER")>=0) return(0.01);
   if(StringFind(s,"BTC")>=0||StringFind(s,"ETH")>=0||StringFind(s,"LTC")>=0) return(1.0);
   if(StringFind(s,"JPY")>=0) return(_Digits<=2 ? _Point : (_Digits==3 ? _Point*10 : _Point));
   if(StringFind(s,"US30")>=0||StringFind(s,"NAS")>=0||StringFind(s,"SPX")>=0||
      StringFind(s,"DAX")>=0) return(1.0);
   return((_Digits==5||_Digits==3) ? _Point*10 : _Point);
}

// SPREAD_PIPS: absolute spread in pips (not ratio)
double SL_GetSpreadPips()
{
   double pip = SL_PipSize();
   if(pip <= 0) return(0);
   return(NormalizeDouble(MarketInfo(Symbol(), MODE_SPREAD) * _Point / pip, 2));
}

// TIME_IN_SESSION_MIN: minutes elapsed since the session opened
int SL_GetTimeInSessionMin(datetime signalTime, int sessionBlock)
{
   MqlDateTime mdt;
   TimeToStruct(signalTime, mdt);
   int sigMinUTC = GetUTCHour(signalTime) * 60 + mdt.min;
   int sessStartMin;
   switch(sessionBlock)
   {
      case 0: sessStartMin =  0*60; break; // Asian   00:00 UTC
      case 1: sessStartMin =  8*60; break; // London  08:00 UTC
      case 2: sessStartMin = 12*60; break; // Overlap 12:00 UTC
      case 3: sessStartMin = 16*60; break; // LateNY  16:00 UTC
      default: sessStartMin = 0; break;
   }
   int diff = sigMinUTC - sessStartMin;
   if(diff < 0) diff += 24 * 60;
   return(diff);
}

// Check if a TP level was hit between fromBarNS and toBarNS (inclusive).
// barNS = bar number from most-recent (0=current), same as Bars-1-i convention.
int SL_CheckTPHit(bool isBuy, double tpLevel, int fromBarNS, int toBarNS)
{
   if(tpLevel <= 0) return(0);
   int lo = MathMin(fromBarNS, toBarNS);
   int hi = MathMax(fromBarNS, toBarNS);
   for(int bs = lo; bs <= hi; bs++)
   {
      if(bs < 0 || bs >= Bars) continue;
      if(isBuy  && iHigh(NULL, 0, bs) >= tpLevel) return(1);
      if(!isBuy && iLow(NULL, 0, bs)  <= tpLevel) return(1);
   }
   return(0);
}

// P&L_PIPS: signed result in pips (positive = profit)
double SL_CalcPLPips(bool isBuy, double entry, double exitPrice)
{
   double pip = SL_PipSize();
   if(pip <= 0 || entry <= 0 || exitPrice <= 0) return(0);
   double delta = isBuy ? (exitPrice - entry) : (entry - exitPrice);
   return(NormalizeDouble(delta / pip, 1));
}

//+------------------------------------------------------------------+
//| Helper: Tên timeframe ngắn gọn                                    |
//+------------------------------------------------------------------+
string SL_GetTFName()
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
//| Helper: Tên tín hiệu case                                         |
//+------------------------------------------------------------------+
string SL_GetCaseName(int caseNum)
{
   switch(caseNum)
   {
      case 1: return("OBOSBounce");
      case 2: return("RegularDiv");
      case 3: return("HiddenDiv");
      case 4: return("StrongTrend");
      case 5: return("OrangeLevel");
      case 6: return("TrendCont");
      case 7: return("SidewayBreak");
      case 8: return("BasicCross");
      case 9: return("OBOSCross");
   }
   return("Case" + IntegerToString(caseNum));
}

//+------------------------------------------------------------------+
//| Helper: Tên phiên giao dịch                                        |
//+------------------------------------------------------------------+
string SL_GetSessionName(int block)
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
//| Helper: Định dạng datetime → string ISO                            |
//+------------------------------------------------------------------+
string SL_FmtDT(datetime dt)
{
   if(dt == 0) return("0");
   return(TimeToString(dt, TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Helper: Tạo SIGNAL_ID duy nhất                                    |
//| Format: SYMBOL_TF_DIR_CASE_EPOCH                                   |
//| Ví dụ:  XAUUSD_H1_BUY3_1717574400                                 |
//+------------------------------------------------------------------+
string SL_BuildSignalID(int caseNum, bool isBuy, datetime signalTime)
{
   return(Symbol() + "_" + SL_GetTFName()
          + "_" + (isBuy ? "BUY" : "SELL")
          + IntegerToString(caseNum)
          + "_" + IntegerToString((int)signalTime));
}

//+------------------------------------------------------------------+
//| Helper: Đường dẫn file theo năm                                    |
//+------------------------------------------------------------------+
string SL_GetSignalPath()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(InpLogFolder + "\\signals_"
          + Symbol() + "_" + SL_GetTFName()
          + "_" + IntegerToString(dt.year) + ".csv");
}

string SL_GetOutcomePath()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(InpLogFolder + "\\outcomes_"
          + Symbol() + "_" + SL_GetTFName()
          + "_" + IntegerToString(dt.year) + ".csv");
}

string SL_GetScoringPath()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(InpLogFolder + "\\scoring_"
          + Symbol() + "_" + SL_GetTFName()
          + "_" + IntegerToString(dt.year) + ".csv");
}

//+------------------------------------------------------------------+
//| Helper: Mở file append — trả về handle hoặc INVALID_HANDLE        |
//| Tự tạo header nếu file chưa tồn tại                               |
//+------------------------------------------------------------------+
int SL_OpenAppend(string path, string header, bool &isNew)
{
   int fCheck = FileOpen(path, FILE_READ|FILE_ANSI|FILE_TXT);
   isNew = (fCheck == INVALID_HANDLE);

   if(!isNew)
   {
      // Schema version check: count commas in stored header vs expected header.
      // If column count differs (old file), delete and recreate with new schema.
      string storedHeader = FileReadString(fCheck);
      FileClose(fCheck);
      int storedCols = 0, expectedCols = 0;
      for(int c = 0; c < StringLen(storedHeader); c++)
         if(StringGetCharacter(storedHeader, c) == ',') storedCols++;
      for(int c = 0; c < StringLen(header); c++)
         if(StringGetCharacter(header, c) == ',') expectedCols++;
      if(storedCols != expectedCols)
      {
         FileDelete(path);
         isNew = true;
      }
   }
   else FileClose(fCheck);

   int mode = isNew ? (FILE_WRITE|FILE_ANSI|FILE_TXT)
                    : (FILE_READ|FILE_WRITE|FILE_ANSI|FILE_TXT);
   int fh = FileOpen(path, mode);
   if(fh == INVALID_HANDLE) return(INVALID_HANDLE);

   if(isNew)
      FileWriteString(fh, header + "\n");
   else
      FileSeek(fh, 0, SEEK_END);

   return(fh);
}

//+------------------------------------------------------------------+
//| Khởi tạo Logger — gọi từ OnInit()                                 |
//| Nếu fullReset=true: xoá và tạo lại file (khi fullRecalc)          |
//+------------------------------------------------------------------+
void LoggerInit(bool fullReset)
{
   if(!InpEnableSignalLog) return;
   if(IsBacktestMode()) return;

   FolderCreate(InpLogFolder);  // create subfolder inside MQL4/Files/ if absent
   s_loggerReady = true;

   if(fullReset)
   {
      string sigPath = SL_GetSignalPath();
      string outPath = SL_GetOutcomePath();
      string scrPath = SL_GetScoringPath();

      if(FileIsExist(sigPath))  FileDelete(sigPath);
      if(FileIsExist(outPath))  FileDelete(outPath);
      if(FileIsExist(scrPath))  FileDelete(scrPath);

      s_signalHeaderOK    = false;
      s_outcomeHeaderOK   = false;
      s_lastLoggedScoreTime = 0;  // allow current active signal to be re-scored

      s_signalQueueCount  = 0;
      s_outcomeQueueCount = 0;
      s_scoringQueueCount = 0;
      ArrayResize(s_signalQueue,  0);
      ArrayResize(s_outcomeQueue, 0);
      ArrayResize(s_scoringQueue, 0);
   }
}

//+------------------------------------------------------------------+
//| Ghi tín hiệu mới vào signals_*.csv                                |
//| Gọi sau StoreSignal() khi bar đóng có tín hiệu                    |
//+------------------------------------------------------------------+
void LogSignalEntry(datetime signalTime,
                    int      caseNum,
                    bool     isBuy,
                    double   entry,
                    double   sl,
                    double   tp1,
                    double   tp2,
                    double   tp3,
                    double   atr,
                    int      sessionBlock,
                    double   angleZ,
                    // P1 additions:
                    double   rsiAtSignal,
                    double   atrRatio,
                    double   spreadPips,
                    int      d1Trend,
                    int      sltpMethod,
                    bool     autoConfig,
                    int      timeInSessionMin)
{
   if(!InpEnableSignalLog || !s_loggerReady || IsBacktestMode()) return;

   double slDist     = MathAbs(entry - sl);
   double tp1Dist    = MathAbs(tp1 - entry);
   double slDistATR  = (atr > 0) ? NormalizeDouble(slDist / atr, 3)  : -1;
   double tp1DistATR = (atr > 0) ? NormalizeDouble(tp1Dist / atr, 3) : -1;
   double rrRatio    = (slDist > 0) ? NormalizeDouble(tp1Dist / slDist, 3) : -1;

   MqlDateTime sigDt;
   TimeToStruct(signalTime, sigDt);

   string row = SL_BuildSignalID(caseNum, isBuy, signalTime) + ","
              + Symbol()                              + ","
              + SL_GetTFName()                        + ","
              + SL_FmtDT(signalTime)                  + ","
              + SL_FmtDT(TimeCurrent())               + ","
              + (isBuy ? "BUY" : "SELL")              + ","
              + IntegerToString(caseNum)               + ","
              + SL_GetCaseName(caseNum)                + ","
              + DoubleToString(entry, _Digits)         + ","
              + DoubleToString(sl, _Digits)            + ","
              + DoubleToString(tp1, _Digits)           + ","
              + DoubleToString(tp2, _Digits)           + ","
              + DoubleToString(tp3, _Digits)           + ","
              + DoubleToString(atr, _Digits)           + ","
              + DoubleToString(slDistATR, 3)           + ","
              + DoubleToString(tp1DistATR, 3)          + ","
              + DoubleToString(rrRatio, 3)             + ","
              + SL_GetSessionName(sessionBlock)        + ","
              + DoubleToString(angleZ, 2)              + ","
              + IntegerToString(sigDt.hour)            + ","
              + IntegerToString(sigDt.day_of_week)     + ","
              // P1 new columns:
              + DoubleToString(rsiAtSignal, 2)         + ","
              + DoubleToString(atrRatio, 3)            + ","
              + DoubleToString(spreadPips, 2)          + ","
              + IntegerToString(d1Trend)               + ","
              + IntegerToString(sltpMethod)            + ","
              + (autoConfig ? "1" : "0")               + ","
              + IntegerToString(timeInSessionMin);

   QueueSignalRow(row);
}

//+------------------------------------------------------------------+
//| Ghi trạng thái PENDING vào outcomes_*.csv                         |
//| Gọi ngay sau LogSignalEntry()                                     |
//+------------------------------------------------------------------+
void LogOutcomePending(datetime signalTime, int caseNum, bool isBuy)
{
   if(!InpEnableSignalLog || !s_loggerReady || IsBacktestMode()) return;

   string row = SL_BuildSignalID(caseNum, isBuy, signalTime) + ","
              + Symbol()               + ","
              + SL_FmtDT(signalTime)   + ","
              + "PENDING,0,0,0,PENDING,0,0,0,0,0"; // TP2_HIT,TP3_HIT,PL_PIPS = 0

   QueueOutcomeRow(row);
}

//+------------------------------------------------------------------+
//| Ghi outcome đã resolved vào outcomes_*.csv (append)               |
//| outcome: 1=TP1, -1=SL, -2=REVERSAL                               |
//+------------------------------------------------------------------+
void LogOutcomeResolved(datetime signalTime,
                        int      caseNum,
                        bool     isBuy,
                        int      outcome,
                        datetime outcomeTime,
                        double   exitPrice,
                        int      barsHeld,
                        double   mfe,
                        double   mae,
                        // P1/P3 additions:
                        int      tp2Hit,
                        int      tp3Hit,
                        double   plPips)
{
   if(!InpEnableSignalLog || !s_loggerReady || IsBacktestMode()) return;

   string outcomeStr, reason;
   if(outcome == 1)       { outcomeStr = "TP1";      reason = "TP1_HIT";       }
   else if(outcome == -1) { outcomeStr = "SL";       reason = "SL_HIT";        }
   else if(outcome == -2) { outcomeStr = "REVERSAL"; reason = "COUNTER_SIGNAL";}
   else                   { outcomeStr = "UNKNOWN";  reason = "UNKNOWN";       }

   string row = SL_BuildSignalID(caseNum, isBuy, signalTime) + ","
              + Symbol()                              + ","
              + SL_FmtDT(signalTime)                 + ","
              + outcomeStr                            + ","
              + SL_FmtDT(outcomeTime)                + ","
              + DoubleToString(exitPrice, _Digits)    + ","
              + IntegerToString(barsHeld)             + ","
              + reason                                + ","
              + DoubleToString(mfe, _Digits)          + ","
              + DoubleToString(mae, _Digits)          + ","
              // P1/P3 new columns:
              + IntegerToString(tp2Hit)               + ","
              + IntegerToString(tp3Hit)               + ","
              + DoubleToString(plPips, 1);

   QueueOutcomeRow(row);
}

//+------------------------------------------------------------------+
//| Scan g_outcomes và log bất kỳ outcome nào mới được resolve        |
//| Gọi sau CheckPendingOutcomes() mỗi tick                           |
//+------------------------------------------------------------------+
void CheckAndLogNewlyResolved()
{
   if(!InpEnableSignalLog || !s_loggerReady) return;

   // [PERF-FIX P1-2] Track start index to skip already-logged prefix.
   // Outcomes are append-only and loggedToFile is set in order, so once
   // an index is logged, all indices below it are also logged.
   static int s_logScanStart = 0;
   while(s_logScanStart < g_outcomeCount &&
         g_outcomes[s_logScanStart].loggedToFile)
      s_logScanStart++;

   for(int i = s_logScanStart; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0)        continue;
      if(g_outcomes[i].loggedToFile)        continue;

      // Tính số bars giữ lệnh
      int barsHeld = 0;
      if(g_outcomes[i].outcomeTime > 0 && g_outcomes[i].signalTime > 0)
         barsHeld = (int)MathRound(
            (double)(g_outcomes[i].outcomeTime - g_outcomes[i].signalTime)
            / (double)PeriodSeconds(PERIOD_CURRENT));

      // Giá exit = giá tại outcomeTime
      double exitPrice = 0;
      int outShift = iBarShift(NULL, 0, g_outcomes[i].outcomeTime, false);
      if(outShift >= 0)
         exitPrice = (g_outcomes[i].isBuy)
                     ? iHigh(NULL, 0, outShift)   // BUY hit TP = high
                     : iLow(NULL, 0, outShift);   // SELL hit TP = low
      if(g_outcomes[i].outcome == -1)
         exitPrice = (g_outcomes[i].isBuy)
                     ? iLow(NULL, 0, outShift)    // BUY hit SL = low
                     : iHigh(NULL, 0, outShift);  // SELL hit SL = high

      // TP2/TP3 hit detection — look up matching signal for TP2/TP3 levels
      int tp2Hit = 0, tp3Hit = 0;
      double plPips = 0;
      for(int s = 0; s < g_signalCount; s++)
      {
         if(g_signals[s].signalTime != g_outcomes[i].signalTime) continue;
         if(g_signals[s].isBuySignal != g_outcomes[i].isBuy)     continue;
         // Scan from signal bar+1 to outcome bar (inclusive) for TP2/TP3
         int sigBS  = Bars - 1 - g_signals[s].barIndex;
         int outBS  = (outShift >= 0) ? outShift : 0;
         int scanLo = MathMin(sigBS - 1, outBS);  // bar shifts go from sigBS-1 down
         int scanHi = outBS;
         if(scanLo >= 0)
         {
            tp2Hit = SL_CheckTPHit(g_signals[s].isBuySignal,
                                   g_signals[s].takeProfit2, scanHi, scanLo);
            tp3Hit = SL_CheckTPHit(g_signals[s].isBuySignal,
                                   g_signals[s].takeProfit3, scanHi, scanLo);
         }
         plPips = SL_CalcPLPips(g_outcomes[i].isBuy,
                                g_outcomes[i].entryPrice, exitPrice);
         break;
      }

      LogOutcomeResolved(
         g_outcomes[i].signalTime,
         g_outcomes[i].caseNumber,
         g_outcomes[i].isBuy,
         g_outcomes[i].outcome,
         g_outcomes[i].outcomeTime,
         exitPrice,
         barsHeld,
         g_outcomes[i].mfe,
         g_outcomes[i].mae,
         tp2Hit,
         tp3Hit,
         plPips
      );

      g_outcomes[i].loggedToFile = true;
   }
}

//+------------------------------------------------------------------+
//| Log scoring context for active signal (once per signal)           |
//| JOIN key: SIGNAL_ID matches signals_*.csv and outcomes_*.csv      |
//+------------------------------------------------------------------+
void LogScoringSnapshot(datetime signalTime, int caseNum, bool isBuy,
                        int score, string recLevel,
                        double probTP1, double probSL, int probSamples,
                        double ev, double rr,
                        int mtfAgreePct, string mtfTrend,
                        double angleZ, int hour, int dow,
                        double spreadRatio, bool wfRobust,
                        int h4Trend,
                        int h1Trend,
                        int rawT1, int rawT2, int countT3, double realPct,
                        double xgbProbTP1 = 0.0)
{
   if(!InpEnableSignalLog || !s_loggerReady || IsBacktestMode()) return;

   string row = SL_BuildSignalID(caseNum, isBuy, signalTime) + ","
              + IntegerToString(score)             + ","
              + recLevel                           + ","
              + DoubleToString(probTP1, 1)         + ","
              + DoubleToString(probSL, 1)          + ","
              + IntegerToString(probSamples)        + ","
              + DoubleToString(ev, 3)              + ","
              + DoubleToString(rr, 2)              + ","
              + IntegerToString(mtfAgreePct)        + ","
              + mtfTrend                           + ","
              + DoubleToString(angleZ, 2)          + ","
              + IntegerToString(hour)              + ","
              + IntegerToString(dow)               + ","
              + DoubleToString(spreadRatio, 2)     + ","
              + (wfRobust ? "1" : "0")             + ","
              + IntegerToString(h4Trend)           + ","
              + IntegerToString(h1Trend)           + ","
              + IntegerToString(rawT1)             + ","
              + IntegerToString(rawT2)             + ","
              + IntegerToString(countT3)           + ","
              + DoubleToString(realPct, 1)         + ","
              + DoubleToString(xgbProbTP1, 1);

   QueueScoringRow(row);
}

//+------------------------------------------------------------------+
//| Flush toàn bộ hàng đợi ghi log ra đĩa cứng                      |
//+------------------------------------------------------------------+
void FlushLogQueues()
{
   if(!InpEnableSignalLog || !s_loggerReady || IsBacktestMode()) return;

   // 1. Signal Queue
   if(s_signalQueueCount > 0)
   {
      string header = "SIGNAL_ID,SYMBOL,TF,SIGNAL_TIME,LOG_TIME,DIR,CASE_NUM,CASE_NAME"
                      ",ENTRY,SL,TP1,TP2,TP3,ATR,SL_DIST_ATR,TP1_DIST_ATR,RR_RATIO"
                      ",SESSION,ANGLE_Z,HOUR,DOW"
                      ",RSI_AT_SIGNAL,ATR_RATIO,SPREAD_PIPS,D1_TREND"
                      ",SLTP_METHOD,AUTO_CONFIG,TIME_IN_SESSION_MIN";
      bool isNew;
      int fh = SL_OpenAppend(SL_GetSignalPath(), header, isNew);
      if(fh != INVALID_HANDLE)
      {
         for(int i = 0; i < s_signalQueueCount; i++)
            FileWriteString(fh, s_signalQueue[i] + "\n");
         FileClose(fh);
         s_signalQueueCount = 0;
         ArrayResize(s_signalQueue, 0);
      }
   }

   // 2. Scoring Queue
   if(s_scoringQueueCount > 0)
   {
      string header = "SIGNAL_ID,SCORE,REC_LEVEL,PROB_TP1,PROB_SL,PROB_N,EV,RR"
                      ",MTF_AGREE_PCT,MTF_TREND,ANGLE_Z,HOUR,DOW,SPREAD_RATIO,WF_ROBUST"
                      ",MTF_H4_TREND,MTF_H1_TREND,RAW_T1,RAW_T2,COUNT_T3,REAL_PCT"
                      ",XGB_PROB_TP1";
      bool isNew;
      int fh = SL_OpenAppend(SL_GetScoringPath(), header, isNew);
      if(fh != INVALID_HANDLE)
      {
         for(int i = 0; i < s_scoringQueueCount; i++)
            FileWriteString(fh, s_scoringQueue[i] + "\n");
         FileClose(fh);
         s_scoringQueueCount = 0;
         ArrayResize(s_scoringQueue, 0);
      }
   }

   // 3. Outcome Queue
   if(s_outcomeQueueCount > 0)
   {
      string header = "SIGNAL_ID,SYMBOL,SIGNAL_TIME,OUTCOME,OUTCOME_TIME"
                      ",EXIT_PRICE,BARS_HELD,REASON,MFE,MAE"
                      ",TP2_HIT,TP3_HIT,PL_PIPS";
      bool isNew;
      int fh = SL_OpenAppend(SL_GetOutcomePath(), header, isNew);
      if(fh != INVALID_HANDLE)
      {
         for(int i = 0; i < s_outcomeQueueCount; i++)
            FileWriteString(fh, s_outcomeQueue[i] + "\n");
         FileClose(fh);
         s_outcomeQueueCount = 0;
         ArrayResize(s_outcomeQueue, 0);
      }
   }
}

#endif
