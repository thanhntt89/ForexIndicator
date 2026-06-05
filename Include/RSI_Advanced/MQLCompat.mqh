//+------------------------------------------------------------------+
//|                                                    MQLCompat.mqh |
//|                     Bridge header between MQL4 and MQL5          |
//|                                                                  |
//| Include FIRST in main .mq5 file, BEFORE all other includes      |
//| All MQL4 functions used across codebase are wrapped here         |
//|                                                                  |
//| V2: Added batch price cache to eliminate per-bar CopyBuffer      |
//|     Reduces thousands of CopyBuffer calls to ~10 per tick        |
//+------------------------------------------------------------------+
#ifndef MQL_COMPAT_MQH
#define MQL_COMPAT_MQH

#ifdef __MQL5__

//====================================================================
// 1. TIMEFRAME CONVERSION (no dependencies, safe first)
//====================================================================
ENUM_TIMEFRAMES MinutesToTimeframe(int minutes)
{
   if(minutes <= 0) return(_Period);
   switch(minutes)
   {
      case 1:     return(PERIOD_M1);
      case 2:     return(PERIOD_M2);
      case 3:     return(PERIOD_M3);
      case 4:     return(PERIOD_M4);
      case 5:     return(PERIOD_M5);
      case 6:     return(PERIOD_M6);
      case 10:    return(PERIOD_M10);
      case 12:    return(PERIOD_M12);
      case 15:    return(PERIOD_M15);
      case 20:    return(PERIOD_M20);
      case 30:    return(PERIOD_M30);
      case 60:    return(PERIOD_H1);
      case 120:   return(PERIOD_H2);
      case 180:   return(PERIOD_H3);
      case 240:   return(PERIOD_H4);
      case 360:   return(PERIOD_H6);
      case 480:   return(PERIOD_H8);
      case 720:   return(PERIOD_H12);
      case 1440:  return(PERIOD_D1);
      case 10080: return(PERIOD_W1);
      case 43200: return(PERIOD_MN1);
   }
   return(_Period);
}

//====================================================================
// 2. Period() OVERRIDE
//====================================================================
int _MQL4Period()
{
   ENUM_TIMEFRAMES tf = _Period;
   switch(tf)
   {
      case PERIOD_M1:  return(1);
      case PERIOD_M2:  return(2);
      case PERIOD_M3:  return(3);
      case PERIOD_M4:  return(4);
      case PERIOD_M5:  return(5);
      case PERIOD_M6:  return(6);
      case PERIOD_M10: return(10);
      case PERIOD_M12: return(12);
      case PERIOD_M15: return(15);
      case PERIOD_M20: return(20);
      case PERIOD_M30: return(30);
      case PERIOD_H1:  return(60);
      case PERIOD_H2:  return(120);
      case PERIOD_H3:  return(180);
      case PERIOD_H4:  return(240);
      case PERIOD_H6:  return(360);
      case PERIOD_H8:  return(480);
      case PERIOD_H12: return(720);
      case PERIOD_D1:  return(1440);
      case PERIOD_W1:  return(10080);
      case PERIOD_MN1: return(43200);
   }
   return(1);
}
#define Period() _MQL4Period()

//====================================================================
// 3. INDICATOR HANDLE CACHE
//====================================================================
struct HandleCacheEntry
{
   string key;
   int    handle;
};

HandleCacheEntry g_handleCache[];
int              g_handleCacheCount = 0;

int GetCachedIndicatorHandle(string key, int type, string symbol,
                              ENUM_TIMEFRAMES tf, int p1, int p2 = 0)
{
   for(int i = 0; i < g_handleCacheCount; i++)
   {
      if(g_handleCache[i].key == key)
         return(g_handleCache[i].handle);
   }

   int handle = INVALID_HANDLE;
   if(type == 1)      handle = ::iATR(symbol, tf, p1);
   else if(type == 2) handle = ::iRSI(symbol, tf, p1, (ENUM_APPLIED_PRICE)p2);

   if(handle == INVALID_HANDLE) return(INVALID_HANDLE);

   ArrayResize(g_handleCache, g_handleCacheCount + 1);
   g_handleCache[g_handleCacheCount].key = key;
   g_handleCache[g_handleCacheCount].handle = handle;
   g_handleCacheCount++;
   return(handle);
}

void ReleaseAllHandles()
{
   for(int i = 0; i < g_handleCacheCount; i++)
   {
      if(g_handleCache[i].handle != INVALID_HANDLE)
         IndicatorRelease(g_handleCache[i].handle);
   }
   ArrayResize(g_handleCache, 0);
   g_handleCacheCount = 0;
}

//====================================================================
// 4. BATCH PRICE CACHE
//    Instead of calling CopyClose/CopyHigh/CopyLow per bar,
//    cache the entire array once per tick, then read from cache.
//    This reduces thousands of CopyBuffer calls to ~5 per tick.
//====================================================================

// Cache for current symbol, current timeframe
double _cache_close[];
double _cache_high[];
double _cache_low[];
double _cache_open[];
long   _cache_volume[];
datetime _cache_time[];
int    _cache_size = 0;
uint   _cache_tick = 0;        // GetTickCount when cache was built
bool   _cache_valid = false;

// Cache for indicator buffers (RSI, ATR on current symbol/TF)
double _cache_rsi[];
int    _cache_rsi_size = 0;
int    _cache_rsi_handle = INVALID_HANDLE;

double _cache_atr[];
int    _cache_atr_size = 0;
int    _cache_atr_handle = INVALID_HANDLE;

void _RefreshPriceCache()
{
   // Only refresh once per tick (same GetTickCount)
   uint tick = GetTickCount();
   if(_cache_valid && tick == _cache_tick) return;

   int totalBars = ::Bars(_Symbol, _Period);
   if(totalBars <= 0) return;

   int copyCount = MathMin(totalBars, 10000);

   ArraySetAsSeries(_cache_close, true);
   ArraySetAsSeries(_cache_high, true);
   ArraySetAsSeries(_cache_low, true);
   ArraySetAsSeries(_cache_open, true);
   ArraySetAsSeries(_cache_volume, true);
   ArraySetAsSeries(_cache_time, true);

   int copied = CopyClose(_Symbol, _Period, 0, copyCount, _cache_close);
   if(copied <= 0) return;

   CopyHigh(_Symbol, _Period, 0, copyCount, _cache_high);
   CopyLow(_Symbol, _Period, 0, copyCount, _cache_low);
   CopyOpen(_Symbol, _Period, 0, copyCount, _cache_open);
   CopyTickVolume(_Symbol, _Period, 0, copyCount, _cache_volume);
   CopyTime(_Symbol, _Period, 0, copyCount, _cache_time);

   _cache_size = copied;
   _cache_tick = tick;
   _cache_valid = true;
}

void _RefreshRSICache(int handle)
{
   if(handle == INVALID_HANDLE) return;
   if(handle == _cache_rsi_handle && _cache_rsi_size > 0 && GetTickCount() == _cache_tick) return;

   int totalBars = ::Bars(_Symbol, _Period);
   int copyCount = MathMin(totalBars, 10000);

   ArraySetAsSeries(_cache_rsi, true);
   int copied = CopyBuffer(handle, 0, 0, copyCount, _cache_rsi);
   if(copied > 0)
   {
      _cache_rsi_size = copied;
      _cache_rsi_handle = handle;
   }
}

void _RefreshATRCache(int handle)
{
   if(handle == INVALID_HANDLE) return;
   if(handle == _cache_atr_handle && _cache_atr_size > 0 && GetTickCount() == _cache_tick) return;

   int totalBars = ::Bars(_Symbol, _Period);
   int copyCount = MathMin(totalBars, 10000);

   ArraySetAsSeries(_cache_atr, true);
   int copied = CopyBuffer(handle, 0, 0, copyCount, _cache_atr);
   if(copied > 0)
   {
      _cache_atr_size = copied;
      _cache_atr_handle = handle;
   }
}

void InvalidatePriceCache()
{
   _cache_valid = false;
   _cache_rsi_handle = INVALID_HANDLE;
   _cache_atr_handle = INVALID_HANDLE;
   _cache_rsi_size = 0;
   _cache_atr_size = 0;
}

//====================================================================
// 5. INDICATOR WRAPPER FUNCTIONS (with batch cache)
//====================================================================

//--- iRSI: uses batch cache for current symbol/TF
double iRSI(string symbol, int timeframe, int period,
            int applied_price, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;
   ENUM_TIMEFRAMES tf = MinutesToTimeframe(timeframe);

   string key = "RSI_" + symbol + "_" + IntegerToString((int)tf) + "_" +
                IntegerToString(period) + "_" + IntegerToString(applied_price);

   int handle = GetCachedIndicatorHandle(key, 2, symbol, tf, period, applied_price);
   if(handle == INVALID_HANDLE) return(0);

   // Use batch cache for current symbol + current TF (most common case)
   if(symbol == _Symbol && tf == _Period)
   {
      _RefreshPriceCache();
      _RefreshRSICache(handle);
      if(shift >= 0 && shift < _cache_rsi_size)
         return(_cache_rsi[shift]);
   }

   // Fallback: single CopyBuffer for other symbols/TFs
   double val[];
   ArraySetAsSeries(val, true);
   if(CopyBuffer(handle, 0, shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

//--- iATR: uses batch cache for current symbol/TF
double iATR(string symbol, int timeframe, int period, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;
   ENUM_TIMEFRAMES tf = MinutesToTimeframe(timeframe);

   string key = "ATR_" + symbol + "_" + IntegerToString((int)tf) + "_" +
                IntegerToString(period);

   int handle = GetCachedIndicatorHandle(key, 1, symbol, tf, period);
   if(handle == INVALID_HANDLE) return(0);

   // Use batch cache for current symbol + current TF
   if(symbol == _Symbol && tf == _Period)
   {
      _RefreshPriceCache();
      _RefreshATRCache(handle);
      if(shift >= 0 && shift < _cache_atr_size)
         return(_cache_atr[shift]);
   }

   // Fallback
   double val[];
   ArraySetAsSeries(val, true);
   if(CopyBuffer(handle, 0, shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

//====================================================================
// 6. PRICE DATA WRAPPER FUNCTIONS (with batch cache)
//====================================================================

double iClose(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;

   // Use batch cache for current symbol + current TF
   if(symbol == _Symbol && MinutesToTimeframe(timeframe) == _Period)
   {
      _RefreshPriceCache();
      if(shift >= 0 && shift < _cache_size)
         return(_cache_close[shift]);
   }

   // Fallback
   double val[];
   ArraySetAsSeries(val, true);
   if(CopyClose(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

double iOpen(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;

   if(symbol == _Symbol && MinutesToTimeframe(timeframe) == _Period)
   {
      _RefreshPriceCache();
      if(shift >= 0 && shift < _cache_size)
         return(_cache_open[shift]);
   }

   double val[];
   ArraySetAsSeries(val, true);
   if(CopyOpen(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

double iHigh(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;

   if(symbol == _Symbol && MinutesToTimeframe(timeframe) == _Period)
   {
      _RefreshPriceCache();
      if(shift >= 0 && shift < _cache_size)
         return(_cache_high[shift]);
   }

   double val[];
   ArraySetAsSeries(val, true);
   if(CopyHigh(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

double iLow(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;

   if(symbol == _Symbol && MinutesToTimeframe(timeframe) == _Period)
   {
      _RefreshPriceCache();
      if(shift >= 0 && shift < _cache_size)
         return(_cache_low[shift]);
   }

   double val[];
   ArraySetAsSeries(val, true);
   if(CopyLow(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

long iVolume(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;

   if(symbol == _Symbol && MinutesToTimeframe(timeframe) == _Period)
   {
      _RefreshPriceCache();
      if(shift >= 0 && shift < _cache_size)
         return(_cache_volume[shift]);
   }

   long val[];
   ArraySetAsSeries(val, true);
   if(CopyTickVolume(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

datetime iTime(string symbol, int timeframe, int shift)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;

   if(symbol == _Symbol && MinutesToTimeframe(timeframe) == _Period)
   {
      _RefreshPriceCache();
      if(shift >= 0 && shift < _cache_size)
         return(_cache_time[shift]);
   }

   datetime val[];
   ArraySetAsSeries(val, true);
   if(CopyTime(symbol, MinutesToTimeframe(timeframe), shift, 1, val) > 0)
      return(val[0]);
   return(0);
}

//====================================================================
// 7. iBars AND iBarShift - MUST be BEFORE #define Bars
//====================================================================

int iBars(string symbol, int timeframe)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;
   return(::Bars(symbol, MinutesToTimeframe(timeframe)));
}

int iBarShift(string symbol, int timeframe, datetime time, bool exact = false)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;
   ENUM_TIMEFRAMES tf = MinutesToTimeframe(timeframe);

   // Use cache for current symbol/TF
   if(symbol == _Symbol && tf == _Period)
   {
      _RefreshPriceCache();
      for(int i = 0; i < _cache_size; i++)
      {
         if(_cache_time[i] <= time)
         {
            if(exact && _cache_time[i] != time) return(-1);
            return(i);
         }
      }
      return(-1);
   }

   // Fallback for other symbols
   datetime barTime[];
   ArraySetAsSeries(barTime, true);
   int totalBars = ::Bars(symbol, tf);
   int copyCount = MathMin(totalBars, 10000);
   if(CopyTime(symbol, tf, 0, copyCount, barTime) <= 0) return(-1);

   for(int i = 0; i < copyCount; i++)
   {
      if(barTime[i] <= time)
      {
         if(exact && barTime[i] != time) return(-1);
         return(i);
      }
   }
   return(-1);
}

//====================================================================
// 8. Bars MACRO - MUST be AFTER iBars/iBarShift definitions
//====================================================================
int _compat_GetBars()
{
   return(::Bars(_Symbol, _Period));
}
#define Bars _compat_GetBars()

//====================================================================
// 9. MarketInfo WRAPPER
//====================================================================
#define MODE_ASK          10
#define MODE_BID          11
#define MODE_SPREAD       12
#define MODE_STOPLEVEL    13
#define MODE_FREEZELEVEL  14
#define MODE_POINT        16
#define MODE_MINLOT       17
#define MODE_MAXLOT       18
#define MODE_LOTSTEP      19
#define MODE_TICKVALUE     26
#define MODE_TICKSIZE      27
#define MODE_LOTSIZE       28

double MarketInfo(string symbol, int type)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;
   switch(type)
   {
      case MODE_ASK:         return(SymbolInfoDouble(symbol, SYMBOL_ASK));
      case MODE_BID:         return(SymbolInfoDouble(symbol, SYMBOL_BID));
      case MODE_SPREAD:      return((double)SymbolInfoInteger(symbol, SYMBOL_SPREAD));
      case MODE_STOPLEVEL:   return((double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL));
      case MODE_FREEZELEVEL: return((double)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL));
      case MODE_POINT:       return(SymbolInfoDouble(symbol, SYMBOL_POINT));
      case MODE_MINLOT:      return(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));
      case MODE_MAXLOT:      return(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX));
      case MODE_LOTSTEP:     return(SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));
      case MODE_TICKVALUE:   return(SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE));
      case MODE_TICKSIZE:    return(SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE));
      case MODE_LOTSIZE:     return(SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE));
   }
   return(0);
}

//====================================================================
// 10. TIME FUNCTIONS
//====================================================================

int TimeHour(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return(dt.hour);
}

int TimeMinute(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return(dt.min);
}

int TimeDay(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return(dt.day);
}

int TimeDayOfWeek(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return(dt.day_of_week);
}

//====================================================================
// 11. ACCOUNT FUNCTIONS
//====================================================================

string AccountServer()
{
   return(AccountInfoString(ACCOUNT_SERVER));
}

double AccountBalance()
{
   return(AccountInfoDouble(ACCOUNT_BALANCE));
}

double AccountEquity()
{
   return(AccountInfoDouble(ACCOUNT_EQUITY));
}

double AccountFreeMargin()
{
   return(AccountInfoDouble(ACCOUNT_MARGIN_FREE));
}

//====================================================================
// 12. INDICATOR SETUP FUNCTIONS
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

//====================================================================
// 13. DeleteObjectsByPrefix - MUST be BEFORE Object macros
//====================================================================
void DeleteObjectsByPrefix(string prefix)
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string oname = ObjectName(0, i);
      if(StringFind(oname, prefix) == 0)
         ObjectDelete(0, oname);
   }
}

//====================================================================
// 14. OBJECT FUNCTION MACROS - MUST be LAST
//====================================================================
#define ObjectFind(name)                      ObjectFind(0, name)
#define ObjectDelete(name)                    ObjectDelete(0, name)
#define ObjectCreate(name, type, sub, t1, p1) ObjectCreate(0, name, type, sub, t1, p1)

#endif // __MQL5__

#endif // MQL_COMPAT_MQH