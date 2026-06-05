//+------------------------------------------------------------------+
//|                                            SignalLogger.mqh        |
//|                         RSI Advanced - Signal Logging to CSV       |
//|                                                                    |
//| Ghi 2 file CSV pipe-delimited vào MQL4/Files/<InpLogFolder>/:      |
//|   signals_SYMBOL_TF_YYYY.csv  — 1 dòng mỗi tín hiệu mới          |
//|   outcomes_SYMBOL_TF_YYYY.csv — append khi outcome resolved        |
//|                                                                    |
//| AI đọc outcomes bằng: groupby(SIGNAL_ID).last() để lấy            |
//| trạng thái mới nhất, sau đó JOIN với signals trên SIGNAL_ID.       |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_SIGNALLOGGER_MQH
#define RSI_ADV_SIGNALLOGGER_MQH

#include "Config.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
//| State: tránh reinit header nhiều lần                               |
//+------------------------------------------------------------------+
static bool s_loggerReady     = false;
static bool s_signalHeaderOK  = false;
static bool s_outcomeHeaderOK = false;

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

//+------------------------------------------------------------------+
//| Helper: Mở file append — trả về handle hoặc INVALID_HANDLE        |
//| Tự tạo header nếu file chưa tồn tại                               |
//+------------------------------------------------------------------+
int SL_OpenAppend(string path, string header, bool &isNew)
{
   // Kiểm tra file tồn tại
   int fCheck = FileOpen(path, FILE_READ|FILE_ANSI|FILE_TXT);
   isNew = (fCheck == INVALID_HANDLE);
   if(!isNew) FileClose(fCheck);

   int mode = isNew ? (FILE_WRITE|FILE_ANSI|FILE_TXT)
                    : (FILE_READ|FILE_WRITE|FILE_ANSI|FILE_TXT);
   int fh = FileOpen(path, mode);
   if(fh == INVALID_HANDLE) return(INVALID_HANDLE);

   if(isNew)
   {
      FileWriteString(fh, header + "\n");
   }
   else
   {
      FileSeek(fh, 0, SEEK_END);
   }
   return(fh);
}

//+------------------------------------------------------------------+
//| Khởi tạo Logger — gọi từ OnInit()                                 |
//| Nếu fullReset=true: xoá và tạo lại file (khi fullRecalc)          |
//+------------------------------------------------------------------+
void LoggerInit(bool fullReset)
{
   if(!InpEnableSignalLog) return;

   // Tạo folder nếu chưa tồn tại (MQL4 tự tạo khi FileOpen)
   s_loggerReady = true;

   if(fullReset)
   {
      // Xoá file cũ → indicator recalc = ghi lại từ đầu, không duplicate
      string sigPath = SL_GetSignalPath();
      string outPath = SL_GetOutcomePath();

      if(FileIsExist(sigPath))  FileDelete(sigPath);
      if(FileIsExist(outPath))  FileDelete(outPath);

      s_signalHeaderOK  = false;
      s_outcomeHeaderOK = false;
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
                    int      sessionBlock)
{
   if(!InpEnableSignalLog || !s_loggerReady) return;

   string header =
      "SIGNAL_ID|SYMBOL|TF|SIGNAL_TIME|LOG_TIME|DIR|CASE_NUM|CASE_NAME"
      "|ENTRY|SL|TP1|TP2|TP3|ATR|SL_DIST_ATR|TP1_DIST_ATR|RR_RATIO|SESSION";

   bool isNew;
   int fh = SL_OpenAppend(SL_GetSignalPath(), header, isNew);
   if(fh == INVALID_HANDLE) return;

   // Tính các chỉ số phái sinh
   double slDist    = MathAbs(entry - sl);
   double tp1Dist   = MathAbs(tp1 - entry);
   double slDistATR = (atr > 0) ? NormalizeDouble(slDist / atr, 3)  : -1;
   double tp1DistATR= (atr > 0) ? NormalizeDouble(tp1Dist / atr, 3) : -1;
   double rrRatio   = (slDist > 0) ? NormalizeDouble(tp1Dist / slDist, 3) : -1;

   string row = SL_BuildSignalID(caseNum, isBuy, signalTime) + "|"
              + Symbol()                           + "|"
              + SL_GetTFName()                     + "|"
              + SL_FmtDT(signalTime)               + "|"
              + SL_FmtDT(TimeCurrent())            + "|"
              + (isBuy ? "BUY" : "SELL")           + "|"
              + IntegerToString(caseNum)            + "|"
              + SL_GetCaseName(caseNum)             + "|"
              + DoubleToString(entry, _Digits)      + "|"
              + DoubleToString(sl, _Digits)         + "|"
              + DoubleToString(tp1, _Digits)        + "|"
              + DoubleToString(tp2, _Digits)        + "|"
              + DoubleToString(tp3, _Digits)        + "|"
              + DoubleToString(atr, _Digits)        + "|"
              + DoubleToString(slDistATR, 3)        + "|"
              + DoubleToString(tp1DistATR, 3)       + "|"
              + DoubleToString(rrRatio, 3)          + "|"
              + SL_GetSessionName(sessionBlock);

   FileWriteString(fh, row + "\n");
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Ghi trạng thái PENDING vào outcomes_*.csv                         |
//| Gọi ngay sau LogSignalEntry()                                     |
//+------------------------------------------------------------------+
void LogOutcomePending(datetime signalTime, int caseNum, bool isBuy)
{
   if(!InpEnableSignalLog || !s_loggerReady) return;

   string header =
      "SIGNAL_ID|SYMBOL|SIGNAL_TIME|OUTCOME|OUTCOME_TIME"
      "|EXIT_PRICE|BARS_HELD|REASON|MFE|MAE";

   bool isNew;
   int fh = SL_OpenAppend(SL_GetOutcomePath(), header, isNew);
   if(fh == INVALID_HANDLE) return;

   string row = SL_BuildSignalID(caseNum, isBuy, signalTime) + "|"
              + Symbol()               + "|"
              + SL_FmtDT(signalTime)   + "|"
              + "PENDING|0|0|0|PENDING|0|0";

   FileWriteString(fh, row + "\n");
   FileClose(fh);
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
                        double   mae)
{
   if(!InpEnableSignalLog || !s_loggerReady) return;

   string header =
      "SIGNAL_ID|SYMBOL|SIGNAL_TIME|OUTCOME|OUTCOME_TIME"
      "|EXIT_PRICE|BARS_HELD|REASON|MFE|MAE";

   bool isNew;
   int fh = SL_OpenAppend(SL_GetOutcomePath(), header, isNew);
   if(fh == INVALID_HANDLE) return;

   string outcomeStr, reason;
   if(outcome == 1)       { outcomeStr = "TP1";      reason = "TP1_HIT";       }
   else if(outcome == -1) { outcomeStr = "SL";       reason = "SL_HIT";        }
   else if(outcome == -2) { outcomeStr = "REVERSAL"; reason = "COUNTER_SIGNAL";}
   else                   { outcomeStr = "UNKNOWN";  reason = "UNKNOWN";       }

   string row = SL_BuildSignalID(caseNum, isBuy, signalTime) + "|"
              + Symbol()                              + "|"
              + SL_FmtDT(signalTime)                 + "|"
              + outcomeStr                            + "|"
              + SL_FmtDT(outcomeTime)                + "|"
              + DoubleToString(exitPrice, _Digits)    + "|"
              + IntegerToString(barsHeld)             + "|"
              + reason                                + "|"
              + DoubleToString(mfe, _Digits)          + "|"
              + DoubleToString(mae, _Digits);

   FileWriteString(fh, row + "\n");
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Scan g_outcomes và log bất kỳ outcome nào mới được resolve        |
//| Gọi sau CheckPendingOutcomes() mỗi tick                           |
//+------------------------------------------------------------------+
void CheckAndLogNewlyResolved()
{
   if(!InpEnableSignalLog || !s_loggerReady) return;

   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0)        continue; // Còn pending
      if(g_outcomes[i].loggedToFile)        continue; // Đã log rồi

      // Tính số bars giữ lệnh
      int barsHeld = 0;
      if(g_outcomes[i].outcomeTime > 0 && g_outcomes[i].signalTime > 0)
         barsHeld = (int)MathRound(
            (double)(g_outcomes[i].outcomeTime - g_outcomes[i].signalTime)
            / (double)PeriodSeconds(Period()));

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

      LogOutcomeResolved(
         g_outcomes[i].signalTime,
         g_outcomes[i].caseNumber,
         g_outcomes[i].isBuy,
         g_outcomes[i].outcome,
         g_outcomes[i].outcomeTime,
         exitPrice,
         barsHeld,
         g_outcomes[i].mfe,
         g_outcomes[i].mae
      );

      g_outcomes[i].loggedToFile = true;
   }
}

#endif
