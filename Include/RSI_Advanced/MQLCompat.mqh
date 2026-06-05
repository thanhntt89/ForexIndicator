//+------------------------------------------------------------------+
//|                                                    MQLCompat.mqh |
//|                     Bridge header between MQL4 and MQL5          |
//+------------------------------------------------------------------+
#ifndef MQL_COMPAT_MQH
#define MQL_COMPAT_MQH

#ifdef __MQL5__

//====================================================================
// 0. ERROR LOGGING WITH LIMITS
//====================================================================
void LogCompatError(string msg, int err)
{
   static int count = 0;
   if(count < 50)
   {
      Print("[MQLCompat Error] ", msg, " | GetLastError: ", err);
      count++;
   }
}

//====================================================================
// 1. DATA TYPES AND TIMEFRAME CONVERSION
//====================================================================
#define Period() _MQL4Period()

int _MQL4Period()
{
   ENUM_TIMEFRAMES tf = ::Period();
   switch(tf)
   {
      case PERIOD_M1:  return 1;
      case PERIOD_M2:  return 2;
      case PERIOD_M3:  return 3;
      case PERIOD_M4:  return 4;
      case PERIOD_M5:  return 5;
      case PERIOD_M6:  return 6;
      case PERIOD_M10: return 10;
      case PERIOD_M12: return 12;
      case PERIOD_M15: return 15;
      case PERIOD_M20: return 20;
      case PERIOD_M30: return 30;
      case PERIOD_H1:  return 60;
      case PERIOD_H2:  return 120;
      case PERIOD_H3:  return 180;
      case PERIOD_H4:  return 240;
      case PERIOD_H6:  return 360;
      case PERIOD_H8:  return 480;
      case PERIOD_H12: return 720;
      case PERIOD_D1:  return 1440;
      case PERIOD_W1:  return 10080;
      case PERIOD_MN1: return 43200;
   }
   return 1;
}

ENUM_TIMEFRAMES MinutesToTimeframe(int minutes)
{
   if(minutes <= 0) return (ENUM_TIMEFRAMES)::Period();
   switch(minutes)
   {
      case 1:     return PERIOD_M1;
      case 2:     return PERIOD_M2;
      case 3:     return PERIOD_M3;
      case 4:     return PERIOD_M4;
      case 5:     return PERIOD_M5;
      case 6:     return PERIOD_M6;
      case 10:    return PERIOD_M10;
      case 12:    return PERIOD_M12;
      case 15:    return PERIOD_M15;
      case 20:    return PERIOD_M20;
      case 30:    return PERIOD_M30;
      case 60:    return PERIOD_H1;
      case 120:   return PERIOD_H2;
      case 180:   return PERIOD_H3;
      case 240:   return PERIOD_H4;
      case 360:   return PERIOD_H6;
      case 480:   return PERIOD_H8;
      case 720:   return PERIOD_H12;
      case 1440:  return PERIOD_D1;
      case 10080: return PERIOD_W1;
      case 43200: return PERIOD_MN1;
   }
   return (ENUM_TIMEFRAMES)minutes;
}

//====================================================================
// 2. DATA ACCESS WRAPPERS (iHigh, iLow, iClose, iTime, iBarShift, iBars)
//====================================================================
double iHigh(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   double val[];
   if(CopyHigh(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0) return val[0];
   LogCompatError("CopyHigh failed for " + symbol + " tf: " + IntegerToString(timeframe) + " shift: " + IntegerToString(shift), GetLastError());
   return 0;
}

double iLow(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   double val[];
   if(CopyLow(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0) return val[0];
   LogCompatError("CopyLow failed for " + symbol + " tf: " + IntegerToString(timeframe) + " shift: " + IntegerToString(shift), GetLastError());
   return 0;
}

double iClose(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   double val[];
   if(CopyClose(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0) return val[0];
   LogCompatError("CopyClose failed for " + symbol + " tf: " + IntegerToString(timeframe) + " shift: " + IntegerToString(shift), GetLastError());
   return 0;
}

datetime iTime(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   datetime val[];
   if(CopyTime(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0) return val[0];
   LogCompatError("CopyTime failed for " + symbol + " tf: " + IntegerToString(timeframe) + " shift: " + IntegerToString(shift), GetLastError());
   return 0;
}

int iBarShift(string symbol, int timeframe, datetime time, bool exact=false)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   ENUM_TIMEFRAMES tf = MinutesToTimeframe(timeframe);
   datetime times[];
   if(CopyTime(symbol, tf, 0, 1, times) <= 0) return -1;
   
   datetime curTime = times[0];
   if(time > curTime) return 0;
   
   int copied = CopyTime(symbol, tf, time, curTime, times);
   if(copied <= 0) return -1;
   
   if(exact && times[0] != time) return -1;
   return copied - 1;
}

int iBars(string symbol, int timeframe)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   return ::iBars(symbol, MinutesToTimeframe(timeframe));
}

//====================================================================
// 3. INDICATOR CACHING FOR MT5 (Avoid Handle Leaks)
//====================================================================
extern int g_prevRatesTotal;

struct IndicatorHandleCache
{
   string key;
   int handle;
};

static IndicatorHandleCache g_handleCache[];
static int g_handleCacheCount = 0;

int GetCachedIndicatorHandle(string key, int type, string symbol, ENUM_TIMEFRAMES tf, int p1=0, int p2=0)
{
   for(int i = 0; i < g_handleCacheCount; i++)
   {
      if(g_handleCache[i].key == key) return g_handleCache[i].handle;
   }
   
   int handle = INVALID_HANDLE;
   if(type == 1) // ATR
   {
      handle = iATR(symbol, tf, p1);
   }
   else if(type == 2) // RSI
   {
      handle = iRSI(symbol, tf, p1, (ENUM_APPLIED_PRICE)p2);
   }
   
   if(handle != INVALID_HANDLE)
   {
      ArrayResize(g_handleCache, g_handleCacheCount + 1);
      g_handleCache[g_handleCacheCount].key = key;
      g_handleCache[g_handleCacheCount].handle = handle;
      g_handleCacheCount++;
   }
   return handle;
}

double iATR(string symbol, int timeframe, int period, int shift)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   ENUM_TIMEFRAMES tf = MinutesToTimeframe(timeframe);
   string key = "ATR_" + symbol + "_" + IntegerToString(tf) + "_" + IntegerToString(period);
   int handle = GetCachedIndicatorHandle(key, 1, symbol, tf, period);
   if(handle == INVALID_HANDLE)
   {
      g_prevRatesTotal = 0;
      LogCompatError("iATR handle creation failed for " + symbol + " tf: " + IntegerToString(timeframe), GetLastError());
      return EMPTY_VALUE;
   }
   
   double val[];
   if(CopyBuffer(handle, 0, shift, 1, val) > 0) return val[0];
   
   if(BarsCalculated(handle) <= 0)
      g_prevRatesTotal = 0; // Only force recalculation if data is truly not ready yet
      
   LogCompatError("iATR CopyBuffer failed for " + symbol + " tf: " + IntegerToString(timeframe) + " shift: " + IntegerToString(shift), GetLastError());
   return EMPTY_VALUE;
}

double iRSI(string symbol, int timeframe, int period, int applied_price, int shift)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   ENUM_TIMEFRAMES tf = MinutesToTimeframe(timeframe);
   string key = "RSI_" + symbol + "_" + IntegerToString(tf) + "_" + IntegerToString(period) + "_" + IntegerToString(applied_price);
   int handle = GetCachedIndicatorHandle(key, 2, symbol, tf, period, applied_price);
   if(handle == INVALID_HANDLE)
   {
      g_prevRatesTotal = 0;
      LogCompatError("iRSI handle creation failed for " + symbol + " tf: " + IntegerToString(timeframe), GetLastError());
      return EMPTY_VALUE;
   }
   
   double val[];
   if(CopyBuffer(handle, 0, shift, 1, val) > 0) return val[0];
   
   if(BarsCalculated(handle) <= 0)
      g_prevRatesTotal = 0; // Only force recalculation if data is truly not ready yet
      
   LogCompatError("iRSI CopyBuffer failed for " + symbol + " tf: " + IntegerToString(timeframe) + " shift: " + IntegerToString(shift), GetLastError());
   return EMPTY_VALUE;
}

//====================================================================
// 4. MARKET INFO & ACCOUNT CONSTANTS / WRAPPERS
//====================================================================
#define MODE_ASK          1
#define MODE_BID          2
#define MODE_SPREAD       3
#define MODE_STOPLEVEL    4
#define MODE_TICKVALUE    5
#define MODE_TICKSIZE     6
#define MODE_LOTSIZE      7
#define MODE_MINLOT       8
#define MODE_MAXLOT       9
#define MODE_LOTSTEP      10
#define MODE_FREEZELEVEL  11

double MarketInfo(string symbol, int type)
{
   if(symbol == NULL || symbol == "") symbol = Symbol();
   switch(type)
   {
      case MODE_ASK:         return SymbolInfoDouble(symbol, SYMBOL_ASK);
      case MODE_BID:         return SymbolInfoDouble(symbol, SYMBOL_BID);
      case MODE_SPREAD:      return SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      case MODE_STOPLEVEL:   return SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      case MODE_FREEZELEVEL: return SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      case MODE_TICKVALUE:   return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      case MODE_TICKSIZE:    return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      case MODE_LOTSIZE:     return SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      case MODE_MINLOT:      return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      case MODE_MAXLOT:      return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      case MODE_LOTSTEP:     return SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   }
   return 0;
}

#define Bars   iBars(Symbol(), (ENUM_TIMEFRAMES)::Period())

string AccountServer()
{
   return AccountInfoString(ACCOUNT_SERVER);
}

double AccountBalance()
{
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

//====================================================================
// 5. CHART OBJECTS OVERLOADS
//====================================================================
bool ObjectCreate(string name, ENUM_OBJECT type, int window, datetime time1, double price1, datetime time2=0, double price2=0, datetime time3=0, double price3=0)
{
   return ::ObjectCreate(0, name, type, window, time1, price1, time2, price2, time3, price3);
}

int ObjectFind(string name)
{
   return (int)::ObjectFind(0, name);
}

bool ObjectDelete(string name)
{
   return ::ObjectDelete(0, name);
}

bool ObjectMove(string name, int point, datetime time, double price)
{
   return ::ObjectMove(0, name, point, time, price);
}

int ObjectsTotal(int type=-1)
{
   return ::ObjectsTotal(0, -1, type);
}

string ObjectName(int index)
{
   return ::ObjectName(0, index, -1, -1);
}

//====================================================================
// 6. TIME EXTRACTION FUNCTIONS
//====================================================================
int TimeHour(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.hour;
}

int TimeMinute(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.min;
}

int TimeSecond(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.sec;
}

int TimeDay(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.day;
}

int TimeMonth(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.mon;
}

int TimeYear(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.year;
}

int TimeDayOfWeek(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.day_of_week;
}

//====================================================================
// 7. SETUP & MISC HELPERS
//====================================================================
void SetIndexEmptyValue(int index, double value)
{
   PlotIndexSetDouble(index, PLOT_EMPTY_VALUE, value);
}

void SetIndexDrawBegin(int index, int bars)
{
   PlotIndexSetInteger(index, PLOT_DRAW_BEGIN, bars);
}

void IndicatorShortName(string name)
{
   IndicatorSetString(INDICATOR_SHORTNAME, name);
}

void IndicatorDigits(int digits)
{
   IndicatorSetInteger(INDICATOR_DIGITS, digits);
}

#endif // __MQL5__

#endif // MQL_COMPAT_MQH
