#ifndef RSI_ADV_NORMALIZE_MQH
#define RSI_ADV_NORMALIZE_MQH

#include "Config.mqh"
#include "Globals.mqh"

// Forward declarations - these modules include Normalize.mqh's dependencies
// but Normalize.mqh does NOT include them to avoid circular dependency
// Functions from these modules are called in GetTradeRecommendation
// They must be included BEFORE Normalize.mqh in the main .mq4 file

//+------------------------------------------------------------------+
//|        SECTION 1: INSTRUMENT DETECTION                             |
//+------------------------------------------------------------------+
enum ENUM_INSTRUMENT_TYPE
{
   INST_FOREX_MAJOR, INST_FOREX_CROSS, INST_GOLD, INST_SILVER,
   INST_INDEX, INST_CRYPTO, INST_OIL, INST_OTHER
};

// [PERF-FIX P0-1] Cached globals — symbol never changes during indicator lifetime.
// DetectInstrumentType had 14+ StringFind calls, called 5-10x/tick transitively.
// GetCleanSymbolName and GetBrokerGMTOffset also constant per session.
ENUM_INSTRUMENT_TYPE g_cachedInstType = INST_OTHER;
bool   g_instTypeCached = false;
string g_cachedCleanSymbol = "";
bool   g_cleanSymbolCached = false;
int    g_cachedBrokerGMT = 2;
bool   g_brokerGMTCached = false;

ENUM_INSTRUMENT_TYPE _DetectInstrumentTypeImpl()
{
   string sym = Symbol();
   if(StringFind(sym,"XAU")>=0||StringFind(sym,"GOLD")>=0) return(INST_GOLD);
   if(StringFind(sym,"XAG")>=0||StringFind(sym,"SILVER")>=0) return(INST_SILVER);
   if(StringFind(sym,"BTC")>=0||StringFind(sym,"ETH")>=0||
      StringFind(sym,"LTC")>=0||StringFind(sym,"XRP")>=0) return(INST_CRYPTO);
   if(StringFind(sym,"OIL")>=0||StringFind(sym,"WTI")>=0||
      StringFind(sym,"BRENT")>=0||StringFind(sym,"CL")>=0) return(INST_OIL);
   if(StringFind(sym,"US30")>=0||StringFind(sym,"NAS")>=0||StringFind(sym,"SPX")>=0||
      StringFind(sym,"DAX")>=0||StringFind(sym,"USTEC")>=0||StringFind(sym,"US500")>=0||
      StringFind(sym,"JP225")>=0||StringFind(sym,"UK100")>=0) return(INST_INDEX);
   if(StringLen(sym)>=6)
   {
      string base=StringSubstr(sym,0,3), quote=StringSubstr(sym,3,3);
      bool bM=(base=="EUR"||base=="USD"||base=="GBP"||base=="JPY"||base=="CHF");
      bool qM=(quote=="EUR"||quote=="USD"||quote=="GBP"||quote=="JPY"||quote=="CHF");
      if(bM&&qM) return(INST_FOREX_MAJOR);
      if(bM||qM) return(INST_FOREX_CROSS);
   }
   return(INST_OTHER);
}

ENUM_INSTRUMENT_TYPE DetectInstrumentType()
{
   // [PERF-FIX P0-1] Return cached result — eliminates 70-140 StringFind/tick
   if(g_instTypeCached) return(g_cachedInstType);
   g_cachedInstType = _DetectInstrumentTypeImpl();
   g_instTypeCached = true;
   return(g_cachedInstType);
}

//+------------------------------------------------------------------+
//|        SECTION 2: DISPLAY NORMALIZATION                            |
//+------------------------------------------------------------------+
double GetNormalizedPipSize()
{
   ENUM_INSTRUMENT_TYPE t=DetectInstrumentType();
   switch(t)
   {
      case INST_FOREX_MAJOR: case INST_FOREX_CROSS:
         return(StringFind(Symbol(),"JPY")>=0?0.01:0.0001);
      case INST_GOLD:return(0.1); case INST_SILVER:return(0.01);
      case INST_CRYPTO:return(1.0); case INST_INDEX:return(1.0);
      case INST_OIL:return(0.01); default:return(_Point*10);
   }
}

double PriceToNormalizedPips(double dist)
{
   double ps=GetNormalizedPipSize();
   return(ps==0?0:dist/ps);
}

double PriceToRMultiple(double dist, double slDist)
{
   return(slDist==0?0:dist/slDist);
}

string FormatPL(double plDist, double slDist)
{
   double pips=PriceToNormalizedPips(MathAbs(plDist));
   double r=PriceToRMultiple(plDist,slDist);
   string sign=plDist>=0?"+":"-";
   return(sign+DoubleToString(pips,1)+" pips ("+(r>=0?"+":"")+DoubleToString(r,2)+"R)");
}

string GetCleanSymbolName()
{
   // [PERF-FIX P0-1] Cache result — symbol never changes, was rebuilt every tick
   if(g_cleanSymbolCached) return(g_cachedCleanSymbol);
   string sym=Symbol();
   int dot=StringFind(sym,".");
   if(dot>0) sym=StringSubstr(sym,0,dot);
   int len=StringLen(sym);
   if(len>3)
   {
      string last=StringSubstr(sym,len-1);
      if((last=="c"||last=="m")&&len>6) sym=StringSubstr(sym,0,len-1);
   }
   g_cachedCleanSymbol = sym;
   g_cleanSymbolCached = true;
   return(sym);
}

//+------------------------------------------------------------------+
//|        SECTION 3: TIMEZONE                                         |
//+------------------------------------------------------------------+
// [BUG-FIX 1] DST-aware EU broker offset helper.
// Brokers using EET (UTC+2 winter / UTC+3 summer): IC Markets, Pepperstone,
// XM, FXPro, ThinkMarkets. Hardcoding = 2 year-round was wrong for March–October
// (EU DST active), causing session blocks to map into wrong hour buckets for ~7 months/year.
// EU DST rule: last Sunday in March 02:00 → last Sunday in October 03:00.
int GuessEUBrokerOffset(datetime dt)
{
   // [FIX compile] Dùng MqlDateTime struct thay TimeMonth/TimeDay/TimeDayOfWeek
   // — MT5 không có các hàm standalone đó, MqlDateTime tương thích cả MT4+MT5.
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   int month = mdt.mon;
   int day   = mdt.day;
   int dow   = mdt.day_of_week; // 0=Sunday
   // Summer (DST active): April through September always UTC+3
   if(month > 3 && month < 10) return(3);
   // March: DST starts on last Sunday (day >= 25 is safe last-week guard)
   if(month == 3 && day >= 25 && dow == 0) return(3);
   // October: DST ends on last Sunday; before last week still UTC+3
   if(month == 10 && day < 25)             return(3);
   if(month == 10 && day >= 25 && dow > 0) return(3);
   // Winter (DST inactive): UTC+2
   return(2);
}

int GetBrokerGMTOffset()
{
   // [BUG-FIX Warning] Time-based cache invalidation instead of count-based.
   // Old logic: flush every 1000 calls ≈ 10 min on M1 — unnecessarily frequent.
   // New logic: re-check at most once per hour — sufficient because DST only
   // changes twice per year. Avoids thundering-herd re-computation on M1.
   static datetime s_lastCheck = 0;
   if(g_brokerGMTCached && TimeCurrent() - s_lastCheck < 3600)
      return(g_cachedBrokerGMT);
   s_lastCheck = TimeCurrent();

   datetime brokerTime = TimeCurrent();
   datetime gmtTime = TimeGMT();

   if(gmtTime == 0 || gmtTime < D'2020.01.01')
   {
      if(g_brokerGMTCached) return(g_cachedBrokerGMT);
      string server = AccountServer();
      StringToLower(server);

      int result = 2;
      if(StringFind(server, "exness") >= 0)      result = 0;
      // [BUG-FIX 1] EU/AU brokers (EET): use DST-aware offset instead of hardcode = 2.
      // Hardcode = 2 was wrong from March to October each year (UTC+3 in summer).
      else if(StringFind(server, "icmarket") >= 0)     result = GuessEUBrokerOffset(TimeCurrent());
      else if(StringFind(server, "thinkmarket") >= 0)  result = GuessEUBrokerOffset(TimeCurrent());
      else if(StringFind(server, "xm") >= 0)           result = GuessEUBrokerOffset(TimeCurrent());
      else if(StringFind(server, "fxpro") >= 0)        result = GuessEUBrokerOffset(TimeCurrent());
      else if(StringFind(server, "pepperstone") >= 0)  result = GuessEUBrokerOffset(TimeCurrent());
      else if(StringFind(server, "oanda") >= 0)        result = 0;
      else if(StringFind(server, "fxcm") >= 0)         result = 0;
      else if(StringFind(server, "alpari") >= 0)       result = 3;

      g_cachedBrokerGMT = result;
      g_brokerGMTCached = true;
      return(result);
   }

   int offsetSeconds = (int)(brokerTime - gmtTime);
   int offsetHours = offsetSeconds / 3600;

   if(offsetHours < -12 || offsetHours > 14)
      offsetHours = 2;

   g_cachedBrokerGMT = offsetHours;
   g_brokerGMTCached = true;
   return(offsetHours);
}

int GetUTCHour(datetime localTime)
{
   int h=TimeHour(localTime)-GetBrokerGMTOffset();
   if(h<0) h+=24; if(h>=24) h-=24;
   return(h);
}

// [BUG-FIX 2] Full UTC datetime conversion — GetUTCHour() returns only the hour
// (0-23) which loses day information when the broker clock crosses midnight relative
// to UTC. Example: broker GMT+3, server shows 01:00 Jan 16 → UTC = 22:00 Jan 15.
// GetUTCHour correctly returns 22 but iBarShift() needs the full UTC datetime
// (Jan 15 22:00) to locate the right H4 candle; hour-only causes an off-by-one
// day error. Primary path uses TimeGMT() system call for accuracy; fallback uses
// the cached broker GMT offset when TimeGMT() is unavailable.
datetime GetUTCDatetime(datetime localTime)
{
   // DST-aware: use GuessEUBrokerOffset for the specific historical time,
   // not current offset. Fixes 1-hour error for signals stored in opposite DST season.
   int offHours = GuessEUBrokerOffset(localTime);
   return(localTime - offHours * 3600);
}

// [GENERALIZED] NormalizeCandleToUTC(brokerCandleOpen, tf)
// Tổng quát cho mọi timeframe (M1 → MN1) — không chỉ H4.
//
// Vấn đề gốc: mỗi broker mở candle tại giờ local khác nhau tùy GMT offset.
//   GMT+2: H4 opens 00/04/08/12/16/20 local = 22/02/06/10/14/18 UTC (sai nếu GMT≠0)
//   GMT+3: H4 opens 01/05/09/13/17/21 local = same UTC boundaries ✓ (nếu offset đúng)
// Sau khi convert về UTC, dùng integer floor để snap về boundary chuẩn:
//   H4 → 0,4,8,12,16,20  |  H1 → 0..23  |  M15 → 0,15,30,45  |  M5 → 0,5,10...
//
// Tham số: tf = PERIOD_M1/M5/M15/M30/H1/H4/D1/W1/MN1 hoặc 0 = current chart TF.
// Dùng: g_signals[idx].signalTimeUTC = NormalizeCandleToUTC(iTime(NULL, tf, shift), tf);
datetime NormalizeCandleToUTC(datetime brokerCandleOpen, int tf = 0)
{
   if(tf <= 0) tf = Period();

   // Step 1: Convert broker local time → full UTC datetime
   datetime utcTime = GetUTCDatetime(brokerCandleOpen);

   // ── Sub-day timeframes (M1..H4): dùng integer epoch arithmetic ──────────
   // UTC epoch bắt đầu 1970.01.01 00:00:00 UTC (Thursday).
   // Floor theo giây: (utcSec / tfSec) * tfSec cho đúng boundary chuẩn UTC
   // mà không cần tính riêng hour/min/sec. Hoạt động cho mọi tf là bội số phút.
   if(tf < 1440) // < PERIOD_D1
   {
      long tfSec   = (long)tf * 60;           // tf in seconds
      long utcSec  = (long)utcTime;
      long snapped = (utcSec / tfSec) * tfSec; // floor to nearest boundary
      return((datetime)snapped);
   }

   // ── D1: floor về 00:00:00 UTC cùng ngày ─────────────────────────────────
   if(tf == 1440) // PERIOD_D1
   {
      long utcSec  = (long)utcTime;
      // [FIX compile] MQL không hỗ trợ 'L' suffix cho long literal (không như C/C++).
      // Dùng biến long hoặc cast (long) thay thế.
      long d1Sec   = (long)86400;
      long snapped = (utcSec / d1Sec) * d1Sec;
      return((datetime)snapped);
   }

   // ── W1: floor về Monday 00:00:00 UTC của tuần đó ────────────────────────
   // Unix epoch 1970.01.01 là Thursday (day_of_week=4). Monday cách 3 ngày trước.
   // Offset về Monday: (utcSec + 3*86400) floor theo 7*86400, rồi trừ 3*86400.
   if(tf == 10080) // PERIOD_W1
   {
      long utcSec    = (long)utcTime;
      // [FIX compile] MQL không hỗ trợ 'L' suffix — dùng biến long thay thế.
      long weekSec   = (long)7 * (long)86400;  // 604800
      long monOffset = (long)3 * (long)86400;  // 259200 — shift Thu epoch → Mon
      long snapped   = ((utcSec + monOffset) / weekSec) * weekSec - monOffset;
      return((datetime)snapped);
   }

   // ── MN1: floor về ngày 1 của tháng 00:00:00 UTC ─────────────────────────
   // Cần MqlDateTime vì tháng có độ dài khác nhau (28/29/30/31 ngày).
   if(tf == 43200) // PERIOD_MN1
   {
      MqlDateTime mdt;
      TimeToStruct(utcTime, mdt);
      mdt.day  = 1;
      mdt.hour = 0;
      mdt.min  = 0;
      mdt.sec  = 0;
      return(StructToTime(mdt));
   }

   // Fallback: trả về UTC time không snap (timeframe lạ không xác định)
   return(utcTime);
}

// [BACKWARD COMPAT] NormalizeH4CandleToUTC — wrapper gọi NormalizeCandleToUTC với PERIOD_H4.
// Giữ lại để code cũ đang dùng hàm này không cần sửa.
datetime NormalizeH4CandleToUTC(datetime brokerCandleOpen)
{
   return(NormalizeCandleToUTC(brokerCandleOpen, 240)); // 240 = PERIOD_H4
}

//+------------------------------------------------------------------+
//|        SECTION 4: SIGNAL PARAMETER NORMALIZATION                   |
//+------------------------------------------------------------------+
double GetNormalizedAngleThreshold(int barIndex, const double &greenBuffer[])
{
   if(barIndex<20) return(InpAngleThreshold);
   double sum=0,sumSq=0; int count=0;
   for(int j=0;j<20;j++)
   {
      int idx=barIndex-j;
      if(idx<1||greenBuffer[idx]==EMPTY_VALUE||greenBuffer[idx-1]==EMPTY_VALUE) continue;
      double d=greenBuffer[idx]-greenBuffer[idx-1];
      sum+=d; sumSq+=d*d; count++;
   }
   if(count<10) return(InpAngleThreshold);
   double var=(sumSq/count)-(sum/count)*(sum/count);
   double sd=MathSqrt(MathMax(var,0));
   double adaptive=MathMax(sd*1.5,2.0);
   return(adaptive*0.7+InpAngleThreshold*0.3);
}

int GetNormalizedSwingDepth()
{
   int tf=Period();
   if(tf<=PERIOD_M5) return(InpSwingDepth);
   if(tf<=PERIOD_M15) return(MathMax(InpSwingDepth,3));
   if(tf<=PERIOD_M30) return(MathMax(InpSwingDepth,4));
   if(tf<=TF_H1) return(MathMax(InpSwingDepth,5));
   if(tf<=TF_H4) return(MathMax(InpSwingDepth,6));
   return(MathMax(InpSwingDepth,8));
}

int GetNormalizedSwingLookback()
{
   int tf=Period(), minMin=240;
   if(tf<=PERIOD_M5) minMin=120;
   if(tf>=TF_H1) minMin=720;
   if(tf>=TF_H4) minMin=2880;
   int minBars=minMin/Period();
   return(MathMax(InpSwingLookback,minBars));
}

int GetNormalizedSLLookback()
{
   int tf=Period(), minMin=60;
   if(tf<=PERIOD_M1) minMin=30;
   if(tf>=TF_H1) minMin=480;
   if(tf>=TF_H4) minMin=1440;
   return(MathMax(InpSLSwingLookback,minMin/Period()));
}

double GetNormalizedSpreadBuffer()
{
   double spread=MarketInfo(Symbol(),MODE_SPREAD)*_Point;
   double atr=iATR(NULL,0,InpATRPeriod,0);
   if(atr==0) return(spread);
   double pct=spread/atr;
   if(pct<0.05) return(spread);
   if(pct<0.15) return(spread*1.5);
   return(spread*2.0);
}

double GetMinSLDistance()
{
   double atrMin=iATR(NULL,0,InpATRPeriod,0);
   double brokerMin=MathMax(MarketInfo(Symbol(),MODE_STOPLEVEL),
                            MarketInfo(Symbol(),MODE_FREEZELEVEL))*_Point;
   return(MathMax(atrMin,brokerMin));
}

//+------------------------------------------------------------------+
//|        SECTION 5: SESSION QUALITY                                  |
//+------------------------------------------------------------------+
double GetSessionQualityNormalized(int caseNum, datetime signalTime)
{
   if(DetectInstrumentType() == INST_CRYPTO) return(0.5);

   int hour = GetUTCHour(signalTime);

   bool isAsian    = (hour >= 0 && hour < 8);
   bool isLondon   = (hour >= 8 && hour < 12);
   bool isOverlap  = (hour >= 12 && hour < 16);
   bool isLateNY   = (hour >= 16 && hour < 22);
   bool isDeadZone = (hour >= 22);

   if(isDeadZone) return(0.3);

   switch(caseNum)
   {
      case 1: case 5:
         if(isAsian) return(0.6); if(isLondon) return(0.5);
         if(isOverlap) return(0.45); return(0.55);
      case 2: case 3:
         if(isAsian) return(0.45); if(isLondon) return(0.7);
         if(isOverlap) return(0.65); return(0.5);
      case 4: case 7:
         if(isAsian) return(0.35); if(isLondon) return(0.75);
         if(isOverlap) return(0.7); return(0.45);
      case 6:
         if(isAsian) return(0.45); if(isLondon) return(0.65);
         if(isOverlap) return(0.7); return(0.5);
   }
   return(0.5);
}

//+------------------------------------------------------------------+
//|        SECTION 7: MARKET CORRECTIONS                               |
//+------------------------------------------------------------------+
double GetFatTailPenalty()
{
   // [PERF-FIX P2-6] Cache per-bar — 500 iClose calls, values change only on new bar
   static datetime s_ftpBarTime = 0;
   static double   s_ftpResult  = 0.05;
   datetime curBar = iTime(NULL, 0, 0);
   if(curBar == s_ftpBarTime) return(s_ftpResult);
   s_ftpBarTime = curBar;

   int lookback = MathMin(500, Bars - 2);
   double sumR = 0, sumR2 = 0, sumR4 = 0;
   int count = 0;
   for(int i = 1; i <= lookback; i++)
   {
      double c0 = iClose(NULL, 0, i);
      double c1 = iClose(NULL, 0, i + 1);
      if(c1 == 0) continue;
      double ret = (c0 - c1) / c1;
      sumR += ret; sumR2 += ret * ret; sumR4 += ret * ret * ret * ret;
      count++;
   }
   if(count < 50) { s_ftpResult = 0.05; return(s_ftpResult); }
   double mean = sumR / count;
   double variance = (sumR2 / count) - (mean * mean);
   if(variance <= 0) { s_ftpResult = 0.05; return(s_ftpResult); }
   double kurtosis = (sumR4 / count) / (variance * variance) - 3.0;
   double penalty = 0.003 * (1.0 + MathMax(kurtosis, 0) / 3.0);
   s_ftpResult = MathMin(penalty, 0.15);
   return(s_ftpResult);
}

double GetVolClusterPenalty()
{
   // [PERF-FIX P2-6] Cache per-bar — 200 iClose calls, values change only on new bar
   static datetime s_vcpBarTime = 0;
   static double   s_vcpResult  = 0.03;
   datetime curBar = iTime(NULL, 0, 0);
   if(curBar == s_vcpBarTime) return(s_vcpResult);
   s_vcpBarTime = curBar;

   int lookback = MathMin(200, Bars - 3);
   double sumXY = 0, sumX = 0, sumY = 0, sumX2 = 0, sumY2 = 0;
   int count = 0;
   for(int i = 1; i < lookback; i++)
   {
      double c0 = iClose(NULL, 0, i);
      double c1 = iClose(NULL, 0, i + 1);
      double c2 = iClose(NULL, 0, i + 2);
      if(c1 == 0 || c2 == 0) continue;
      double x = MathAbs((c0 - c1) / c1);
      double y = MathAbs((c1 - c2) / c2);
      sumXY += x * y; sumX += x; sumY += y;
      sumX2 += x * x; sumY2 += y * y; count++;
   }
   if(count < 50) { s_vcpResult = 0.03; return(s_vcpResult); }
   double numr = sumXY / count - (sumX / count) * (sumY / count);
   double denX = sumX2 / count - (sumX / count) * (sumX / count);
   double denY = sumY2 / count - (sumY / count) * (sumY / count);
   if(denX <= 0 || denY <= 0) { s_vcpResult = 0.03; return(s_vcpResult); }
   double corr = numr / MathSqrt(denX * denY);
   s_vcpResult = MathMax(0, MathMin(MathAbs(corr) * 0.10, 0.12));
   return(s_vcpResult);
}

double GetSpreadDrag(double atrValue)
{
   if(atrValue <= 0) return(0);
   double spread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
   return(MathMin(spread / atrValue, 0.15));
}

//+------------------------------------------------------------------+
//|        SECTION 8: PROBABILITY MATH                                 |
//+------------------------------------------------------------------+
double CalculateGamblersRuin(double edge, double slDist, double tpDist, double atrVal)
{
   if(slDist <= 0 || tpDist <= 0 || atrVal <= 0) return(0);
   double slU = slDist / atrVal, tpU = tpDist / atrVal;
   double mu = 2.0 * edge - 1.0;
   if(MathAbs(mu) < 0.001) return(slU / (slU + tpU));
   double r = MathExp(-2.0 * mu);
   double rSL = MathPow(r, slU), rT = MathPow(r, slU + tpU);
   if(MathAbs(1.0 - rT) < 1e-10) return(slU / (slU + tpU));
   return((1.0 - rSL) / (1.0 - rT));
}

double CalculateRealMarketProbTP(double edge, double slDist, double tpDist, double atrVal)
{
   double raw = CalculateGamblersRuin(edge, slDist, tpDist, atrVal);
   double corrected = raw * (1.0 - GetFatTailPenalty())
                          * (1.0 - GetVolClusterPenalty())
                          * (1.0 - GetSpreadDrag(atrVal));
   return(MathMax(0.01, MathMin(0.99, corrected)));
}

//+------------------------------------------------------------------+
//|        SECTION 9: EDGE MEASUREMENT                                 |
//+------------------------------------------------------------------+
double MeasureEdgeFromHistory(int caseNum, bool isBuy, int maxForward)
{
   // [PROB-FIX-1] Cache full result per (caseNum, isBuy, signalCount, maxForward).
   // Phase 2 deep-scans thousands of historical bars outside InpMaxBars — those bars
   // don't change between new bars. Only recompute when g_signalCount increases
   // (new signal detected) or other key inputs change. ~99% cost reduction on M1.
   static int    s_efhN      = -1;
   static int    s_efhCase   = -99;
   static bool   s_efhBuy    = false;
   static int    s_efhMaxFwd = -1;
   static double s_efhResult = 0.51;
   if(s_efhN == g_signalCount && s_efhCase == caseNum &&
      s_efhBuy == isBuy && s_efhMaxFwd == maxForward)
      return(s_efhResult);
   s_efhN      = g_signalCount;
   s_efhCase   = caseNum;
   s_efhBuy    = isBuy;
   s_efhMaxFwd = maxForward;

   int correctCount=0, totalCount=0;

   // Anti-overfitting: only use in-sample (training) signals to measure edge.
   // OOS signals are held out for walk-forward validation; including them would
   // cause the edge estimate to be validated on the same data it's measured from.
   int splitIdx = g_signalCount;
   if(InpUseWalkForward && g_signalCount >= 10)
   {
      double oosPct = MathMax(10.0, MathMin(30.0, (double)InpOOSPercent));
      splitIdx = (int)(g_signalCount * (100.0 - oosPct) / 100.0);
      if(splitIdx < 5) splitIdx = g_signalCount;
   }

   for(int s=0; s<g_signalCount; s++)
   {
      if(s >= splitIdx) continue;              // IS only: skip OOS signals
      if(g_signals[s].isBuySignal!=isBuy) continue;
      if(caseNum>0 && g_signals[s].caseNumber!=caseNum) continue;
      if(g_signals[s].barIndex+maxForward>=Bars) continue;
      double entry=g_signals[s].entryPrice, atr=g_signals[s].atrValue;
      double sl=g_signals[s].stopLoss;
      if(atr==0) continue;

      int outcome;
      if(g_signals[s].edgeCachedOutcome != 99)
      {
         outcome = g_signals[s].edgeCachedOutcome;
      }
      else
      {
         outcome = 0;
         for(int b=g_signals[s].barIndex+1; b<g_signals[s].barIndex+maxForward && b<Bars; b++)
         {
            int bs=Bars-1-b; if(bs<0) break;
            double bH=iHigh(NULL,0,bs), bL=iLow(NULL,0,bs);
            if(isBuy)
            {
               if(bL<=sl)        { outcome=-1; break; }
               if(bH>=entry+atr) { outcome= 1; break; }
            }
            else
            {
               if(bH>=sl)        { outcome=-1; break; }
               if(bL<=entry-atr) { outcome= 1; break; }
            }
         }
         g_signals[s].edgeCachedOutcome = outcome;
      }
      if(outcome!=0) { totalCount++; if(outcome==1) correctCount++; }
   }

   // [CROSS-BROKER-FIX v2] Time-based boundary + NEW→OLD scan for Phase 2.
   // v1 (time cap only) still took oldest qualifying bars first → different
   // brokers sample different time periods. NEW→OLD ensures both start from
   // the most recent deep-scan bars and collect the same recent data.
   int edgeMaxDays = (Period() <= TF_M5) ? 60 : (Period() <= TF_H1) ? 180 : 365;
   datetime edgeCutoffTime = TimeCurrent() - edgeMaxDays * 86400;
   int phase1Start=MathMax(0, Bars-InpMaxBars);
   int deepEnd=Bars-maxForward-10;
   int deepUpperBound = MathMin(phase1Start, deepEnd);
   for(int i=deepUpperBound-1; i>=InpRSIPeriod+10; i--)
   {
      if(totalCount>=2000) break;
      int bs=Bars-1-i; if(bs<0) continue;
      // NEW→OLD: once past cutoff, all remaining bars are older
      if(iTime(NULL, 0, bs) < edgeCutoffTime) break;
      double rsi=iRSI(NULL,0,InpRSIPeriod,InpPrice,bs);
      double atr=iATR(NULL,0,InpATRPeriod,bs);
      if(rsi==0 || atr==0) continue;
      bool rel=false;
      if(isBuy) {
         if((caseNum==1||caseNum==5) && rsi<33 && rsi>12) rel=true;
         else if((caseNum==2||caseNum==3) && rsi<42 && rsi>18) rel=true;
         else if((caseNum==4||caseNum==7) && rsi>47 && rsi<53) rel=true;
         else if(caseNum==6 && rsi>42 && rsi<62) rel=true;
         else if(caseNum<=0 && rsi<48 && rsi>18) rel=true;
      } else {
         if((caseNum==1||caseNum==5) && rsi>67 && rsi<88) rel=true;
         else if((caseNum==2||caseNum==3) && rsi>58 && rsi<82) rel=true;
         else if((caseNum==4||caseNum==7) && rsi>47 && rsi<53) rel=true;
         else if(caseNum==6 && rsi>38 && rsi<58) rel=true;
         else if(caseNum<=0 && rsi>52 && rsi<82) rel=true;
      }
      if(!rel) continue;
      double rsiPrev=iRSI(NULL,0,InpRSIPeriod,InpPrice,bs+1);
      if(rsiPrev==0) continue;
      if(isBuy && rsi<=rsiPrev) continue;
      if(!isBuy && rsi>=rsiPrev) continue;
      double entry=iClose(NULL,0,bs);
      // SL-aware: compute SL from ATR × ratio (same as CalculateSLTP_ATR default)
      double sl = isBuy ? entry - atr*InpSLRatio : entry + atr*InpSLRatio;
      int outcome=0;
      for(int b=i+1; b<i+maxForward && b<deepEnd; b++)
      {
         int bsh=Bars-1-b; if(bsh<0) break;
         double bH=iHigh(NULL,0,bsh), bL=iLow(NULL,0,bsh);
         if(isBuy)
         {
            if(bL<=sl)        { outcome=-1; break; }
            if(bH>=entry+atr) { outcome= 1; break; }
         }
         else
         {
            if(bH>=sl)        { outcome=-1; break; }
            if(bL<=entry-atr) { outcome= 1; break; }
         }
      }
      if(outcome!=0) { totalCount++; if(outcome==1) correctCount++; }
   }

   // [PROB-FIX-1] Store result in cache before every return path
   if(totalCount<5) { s_efhResult = 0.51; return(s_efhResult); }
   double edge=(double)correctCount/(double)totalCount;
   double shrink=50.0/(50.0+(double)totalCount);
   edge=edge*(1.0-shrink)+0.50*shrink;
   // Anti-overfitting: clamp to realistic edge range for liquid markets.
   // Empirical research (Menkhoff 2010, Osler 2000): sustained edge >0.62 is
   // not achievable in XAUUSD/Forex. Upper bound 0.70 allows Gambler's Ruin
   // to output P(TP)≈84% — unrealistic and causes overconfident position sizing.
   // [0.48, 0.62] matches actual profitable system edge distributions.
   s_efhResult = MathMax(0.48, MathMin(0.62, edge));
   return(s_efhResult);
}

//+------------------------------------------------------------------+
//|        SECTION 10: BAYESIAN COMBINATION                            |
//+------------------------------------------------------------------+
// [S6] histSamples accepts n_eff (double) for weighted sample support
double CombineTheoreticalHistorical(double theoProb, double histProb,
                                     double histSamples, int minSamples)
{
   if(histSamples <= 0) return(theoProb);
   double p = histProb / 100.0;
   if(p <= 0) p = 0.01; if(p >= 1) p = 0.99;
   double n = histSamples;

   double z = 1.96;
   double z2 = z * z;
   double pWilson = (p * n + z2 / 2.0) / (n + z2);
   double wilsonSE = MathSqrt((p * (1.0 - p) / n + z2 / (4.0 * n * n)) / (1.0 + z2 / n));
   wilsonSE = MathMax(wilsonSE, 0.05);

   double theoSE = 0.15;

   double credibility = MathMin(1.0, (double)histSamples / (double)minSamples);

   double adjustedHistSE = wilsonSE / MathMax(credibility, 0.1);

   double histWeight = 1.0 / (adjustedHistSE * adjustedHistSE);
   double theoWeight = 1.0 / (theoSE * theoSE);

   // [GMT-FIX-A2a] Cap histWeight when 0% historical but theory says viable.
   // Broker GMT offset shifts H4 candle boundaries → different RSI → 0% WR in
   // simulation. Without cap, histWeight crushes theoretical ~42% to ~10%.
   if(histProb < 5.0 && theoProb > 30.0 && histWeight > theoWeight)
   {
      histWeight = theoWeight;
      g_gmtDataQualityWarn = true;
      g_gmtWarnReason = "Hist WR<5% capped";
   }

   double totalWeight = histWeight + theoWeight;
   if(totalWeight <= 0) return(theoProb);

   double combined = (theoProb * theoWeight + histProb * histWeight) / totalWeight;
   return(MathMax(1.0, MathMin(99.0, combined)));
}

//+------------------------------------------------------------------+
//|        SECTION 11: RECOMMENDATION ENGINE (V11 integrated)          |
//|                                                                    |
//| Score components:                                                  |
//|   EV score (0-50): mathematical expected value                     |
//|   Data confidence (0-25): statistical confidence                   |
//|   MTF alignment (0-15): multi-timeframe                            |
//|   Intermarket (0-10): DXY/EURUSD correlation                      |
//|   Walk-forward bonus/penalty: ±5-10                                |
//|   Spread regime penalty: 0 to -15                                  |
//+------------------------------------------------------------------+
enum ENUM_RECOMMENDATION
{
   REC_STRONG_ENTRY, REC_ENTRY, REC_CAUTION_ENTRY,
   REC_WAIT, REC_AVOID, REC_COUNTER_TREND
};

struct TradeRecommendation
{
   ENUM_RECOMMENDATION level;
   string label;
   string reason;
   color  labelColor;
   int    confidence;
   double suggestedRisk;
   double ev;
   double mtfAlignRatio;
};

TradeRecommendation GetTradeRecommendation(
   int caseNum, bool isBuy, double probTP1, double probSL,
   int probSamples, int mtfAgreement,
   double slDist, double tp1Dist, double atrValue, datetime signalTime)
{
   TradeRecommendation rec;
   rec.confidence = 0;
   rec.suggestedRisk = 0;
   string reasons = "";

   double rr = (slDist > 0) ? tp1Dist / slDist : 0;
   double winRate = probTP1 / 100.0;
   double lossRate = 1.0 - winRate;

   // EV (pure math)
   double ev = (winRate * rr) - (lossRate * 1.0);

   // Half-Kelly
   double kellyFraction = 0;
   if(rr > 0 && ev > 0)
      kellyFraction = (ev / rr) * 0.5;
   kellyFraction = MathMax(0, MathMin(kellyFraction, 0.03));

   // Data confidence
   double dataConfidence = 0;
   if(probSamples > 0)
   {
      double se = MathSqrt(winRate * (1.0 - winRate) / (double)probSamples);
      if(se > 0) dataConfidence = MathMin(1.0, 0.05 / se);
   }

   // MTF alignment
   double mtfAlignmentRatio = 0;
   bool mtfAligned = false;
   bool mtfAgainst = false;
   if(InpShowMTF && g_mtfCount > 0)
   {
      int agreeCount = 0;
      for(int t = 0; t < g_mtfCount; t++)
      {
         if(isBuy && g_mtfData[t].trend == 1) agreeCount++;
         if(!isBuy && g_mtfData[t].trend == -1) agreeCount++;
      }
      mtfAlignmentRatio = (double)agreeCount / (double)g_mtfCount;
      mtfAligned = (mtfAlignmentRatio >= 0.5);
      mtfAgainst = (mtfAlignmentRatio < 0.25 && g_mtfCount >= 2);
   }

   // ============================================
   // SCORE COMPONENTS
   // ============================================

   // EV score (0-50): continuous mapping
   double evNorm = MathMax(0.0, MathMin(1.0, (ev + 0.2) / 0.7));
   int evScore = (int)MathRound(evNorm * 50.0);

   // Data confidence (0-25)
   int dataScore = (int)(dataConfidence * 25);

   // MTF alignment (0-5, reduced from 15).
   // Anti-double-counting: MTF alignment already adjusts edge (+/-3%) in
   // ProbabilityEngine.mqh Step 3 via edgeAdjustment → Gambler's Ruin → probTP1.
   // probTP1 feeds evScore (0-50) so MTF is already priced in. Keeping the
   // full ×15 weight counted it twice, inflating scores for MTF-aligned signals.
   int mtfScore = (int)(mtfAlignmentRatio * 5);

   // Intermarket alignment (0-10) - V11
   int interScore = 0;
   if(g_intermarket.isAvailable)
   {
      double interAlign = g_intermarket.correlationScore;
      // +1.0 aligned → +10, -1.0 against → 0, 0 neutral → +5
      interScore = (int)((interAlign + 1.0) / 2.0 * 10.0);

      if(interAlign > 0.3) reasons += "USD aligned|";
      else if(interAlign < -0.3) reasons += "USD against|";
   }

   // Spread regime penalty - V11 (reduced from -15/-5 to -7/-2).
   // Anti-double-counting: spread cost already reduces probTP1 via GetSpreadDrag()
   // in ProbabilityEngine.mqh Step 4 (CalculateRealMarketProbTP). That reduction
   // flows into evScore through the lower win probability. Applying the full
   // -15/-5 here counted spread twice, disproportionately killing EV on wide-spread
   // instruments. Residual -7/-2 accounts for liquidity risk not captured by
   // static spread drag (sudden spike beyond measured ATR ratio).
   int spreadPenalty = 0;
   if(InpUseSpreadRegime)
   {
      if(g_spreadRegime.isExtreme)
      {
         spreadPenalty = -7;
         reasons += "Spread EXTREME|";
      }
      else if(g_spreadRegime.isSpike)
      {
         spreadPenalty = -2;
         reasons += "Spread SPIKE|";
      }
   }

   // Walk-forward robustness - V11
   int wfScore = 0;
   if(InpUseWalkForward && g_walkForward.oosSamples >= 3)
   {
      bool wfNoData = (g_walkForward.isWinRate == 0 && g_walkForward.oosWinRate == 0);
      if(wfNoData)
      {
         // Fresh install — no history yet, no penalty/bonus
      }
      else if(g_walkForward.isRobust)
      {
         wfScore = 5;
         reasons += "WF robust|";
      }
      else
      {
         wfScore = -10;
         reasons += "WF overfit warning|";
      }
   }

   int totalScore = evScore + dataScore + mtfScore + interScore + wfScore + spreadPenalty;

   // Reasons
   reasons += "EV:" + DoubleToString(ev, 2) + "R|";
   reasons += "R:R 1:" + DoubleToString(rr, 1) + "|";
   reasons += "Win:" + DoubleToString(probTP1, 1) + "%|";
   if(mtfAligned) reasons += "MTF aligned|";
   if(mtfAgainst) reasons += "MTF against|";

   // Classification
   rec.confidence = MathMax(0, MathMin(100, totalScore));

   if(totalScore >= 75 && ev > 0.15)
   {
      rec.level = REC_STRONG_ENTRY;
      rec.label = "STRONG ENTRY";
      rec.labelColor = clrLime;
      rec.suggestedRisk = MathMin(kellyFraction * 100, 2.0);
   }
   else if(totalScore >= 55 && ev > 0.05)
   {
      rec.level = REC_ENTRY;
      rec.label = "ENTRY";
      rec.labelColor = clrLime;
      rec.suggestedRisk = MathMin(kellyFraction * 100, 1.5);
   }
   else if(totalScore >= 35 && ev > 0)
   {
      rec.level = REC_CAUTION_ENTRY;
      rec.label = "CAUTION ENTRY";
      rec.labelColor = clrYellow;
      rec.suggestedRisk = MathMin(kellyFraction * 100, 1.0);
   }
   else if(ev > -0.05)
   {
      rec.level = REC_WAIT;
      rec.label = "WAIT";
      rec.labelColor = clrOrange;
      rec.suggestedRisk = 0;
   }
   else
   {
      if(mtfAgainst)
      { rec.level = REC_COUNTER_TREND; rec.label = "AVOID (Counter Trend)"; }
      else
      { rec.level = REC_AVOID; rec.label = "AVOID"; }
      rec.labelColor = clrRed;
      rec.suggestedRisk = 0;
   }

   // Hard gate: insufficient historical data → cap positive recommendations at WAIT.
   // Theoretical probability (Gambler's Ruin) can give optimistic 60-70% with zero evidence.
   // Only real historical simulation data validates the probability.
   int minReqSamples = GetMinSamplesForTimeframe();
   if(probSamples < minReqSamples)
   {
      if(rec.level == REC_STRONG_ENTRY || rec.level == REC_ENTRY || rec.level == REC_CAUTION_ENTRY)
      {
         rec.level = REC_WAIT;
         rec.label = "WAIT (Low Data n=" + IntegerToString(probSamples) + ")";
         rec.labelColor = clrOrange;
         rec.suggestedRisk = 0;
         reasons = "n=" + IntegerToString(probSamples) + "<" + IntegerToString(minReqSamples) + " min|Theoretical prob only|";
         reasons += "EV:" + DoubleToString(ev, 2) + "R|";
      }
   }

   // Top 3 reasons
   string rLines[];
   int rCnt = StringSplit(reasons, '|', rLines);
   rec.reason = "";
   int shown = 0;
   for(int i = 0; i < rCnt && shown < 3; i++)
      if(StringLen(rLines[i]) > 0)
      { if(shown > 0) rec.reason += " | "; rec.reason += rLines[i]; shown++; }

   rec.ev = ev;
   rec.mtfAlignRatio = mtfAlignmentRatio;
   return(rec);
}

#endif