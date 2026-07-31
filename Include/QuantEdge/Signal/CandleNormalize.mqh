//+------------------------------------------------------------------+
//|                                             CandleNormalize.mqh  |
//|       [GMT-FIX-B3] H4 candle normalization via H1 reconstruction |
//|                                                                  |
//| Reconstructs GMT+0-aligned H4 candles from H1 data when broker   |
//| uses non-zero GMT offset. This eliminates the 2h candle boundary |
//| shift that causes different RSI values across brokers.            |
//|                                                                  |
//| GMT+0 H4 boundaries: 00:00, 04:00, 08:00, 12:00, 16:00, 20:00  |
//| GMT+2 H4 boundaries: 02:00, 06:00, 10:00, 14:00, 18:00, 22:00  |
//| Without normalization, these produce completely different RSI.    |
//+------------------------------------------------------------------+
#ifndef QE_CANDLENORMALIZE_MQH
#define QE_CANDLENORMALIZE_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"
#include "../Analysis/Normalize.mqh"

//+------------------------------------------------------------------+
//| Structs and constants                                              |
//+------------------------------------------------------------------+
#define NORM_H4_MAX 500
#define NORM_RSI_MIN_CONVERGE 100
#define NORM_D1_MAX 200
#define NORM_D1_MIN_CONVERGE 30

struct NormH4Candle
{
   datetime openTime;
   double   open;
   double   high;
   double   low;
   double   close;
};

NormH4Candle g_normH4[NORM_H4_MAX];
double       g_normRSI[NORM_H4_MAX];
int          g_normH4Count  = 0;
int          g_normRSICount = 0;
datetime     g_normLastH1Time = 0;

NormH4Candle g_normD1[NORM_D1_MAX];
double       g_normD1RSI[NORM_D1_MAX];
int          g_normD1Count    = 0;
int          g_normD1RSICount = 0;

//+------------------------------------------------------------------+
//| ShouldNormalizeH4 — decide if normalization is needed              |
//| Returns true when: H4+ TF AND broker offset != 0 AND enabled      |
//+------------------------------------------------------------------+
bool ShouldNormalizeH4()
{
   // Only H4 and D1 need chart RSI normalization.
   // W1/MN1: 3h offset in 120h/720h candle = <2.5%, negligible RSI impact.
   // MTF H4/D1 slots on any chart TF are handled by g_gmtMTFNormNeeded.
   if(Period() != TF_H4 && Period() != TF_D1) return(false);

   int gmtOff = (InpForceGMTOffset != -99) ? InpForceGMTOffset : GetBrokerGMTOffset();
   g_gmtBrokerOffset = gmtOff;

   if(InpGMTNormalize == 0) return(false);
   if(InpGMTNormalize == 1) return(true);

   // Auto mode: normalize only when offset != 0
   return(gmtOff != 0);
}

//+------------------------------------------------------------------+
//| GetGMT0_H4Boundary — floor broker H1 time to GMT+0 H4 block      |
//| Returns the GMT+0 H4 candle open time for a given H1 bar time     |
//+------------------------------------------------------------------+
datetime GetGMT0_H4Boundary(datetime h1BrokerTime, int brokerOffset)
{
   // Convert broker time to UTC
   datetime utcTime = h1BrokerTime - brokerOffset * 3600;

   // Floor to 4-hour boundary in UTC
   // UTC hour = (utcTime % 86400) / 3600
   int utcHour = (int)((utcTime % 86400) / 3600);
   int h4Block = (utcHour / 4) * 4;

   // Reconstruct the floored time
   datetime dayStart = utcTime - (utcTime % 86400);
   return(dayStart + h4Block * 3600);
}

//+------------------------------------------------------------------+
//| BuildNormalizedH4Candles — fetch H1 data, group into GMT+0 H4     |
//| Cache guard: only rebuild when new H1 bar forms                    |
//+------------------------------------------------------------------+
void BuildNormalizedH4Candles()
{
   datetime curH1Time = iTime(NULL, TF_H1, 0);
   int curH1Bars = iBars(NULL, TF_H1);

   // Cache guard: skip rebuild ONLY when data is sufficient AND no new H1 bar
   // On MT5, H1 data loads asynchronously — first call may have few bars.
   // Keep rebuilding until we have enough candles for RSI convergence.
   bool dataInsufficient = (g_normH4Count < NORM_RSI_MIN_CONVERGE
                            && curH1Bars > (g_normH4Count + 10) * 4);
   if(curH1Time == g_normLastH1Time && g_normH4Count > 0 && !dataInsufficient)
      return;
   g_normLastH1Time = curH1Time;

   int gmtOff = (InpForceGMTOffset != -99) ? InpForceGMTOffset : GetBrokerGMTOffset();
   if(gmtOff == 0)
   {
      g_normH4Count = 0;
      g_normRSICount = 0;
      return;
   }

   // Fetch H1 bars (need 4x H4 bars + some extra for RSI warmup)
   int h1BarsNeeded = (NORM_H4_MAX + 20) * 4;
   int h1Available = iBars(NULL, TF_H1);
   if(h1Available < 100)
   {
      g_normH4Count = 0;
      g_normRSICount = 0;
      return;
   }
   int h1Count = MathMin(h1BarsNeeded, h1Available);

   // [PERF] Bulk-fetch all H1 OHLC+time in ONE CopyRates call instead of 5 single-element
   // CopyXXX per bar. On MT5 (broker GMT!=0, non-H1 chart) the old per-bar path issued
   // ~h1Count*5 (~10k) fallback copies on every rebuild -> the biggest TF-switch cost on
   // MT5 GMT+3. CopyRates works on MT4+MT5; TFPeriod() keeps the H1 arg correct on both.
   MqlRates h1r[];
   ArraySetAsSeries(h1r, true);   // index 0 = newest (matches iTime(NULL,TF_H1,shift))
   int h1Got = CopyRates(_Symbol, TFPeriod(TF_H1), 0, h1Count, h1r);
   if(h1Got <= 0)
   {
      // H1 not loaded yet (async on MT5) — leave counts at 0 so the next tick retries.
      g_normH4Count = 0;
      g_normRSICount = 0;
      return;
   }

   // Build H4 candles by grouping H1 bars into GMT+0 4-hour blocks
   // Scan from oldest to newest for proper OHLC construction
   g_normH4Count = 0;
   datetime prevBoundary = 0;

   for(int i = h1Got - 1; i >= 0; i--)
   {
      datetime h1Time  = h1r[i].time;
      double   h1Open  = h1r[i].open;
      double   h1High  = h1r[i].high;
      double   h1Low   = h1r[i].low;
      double   h1Close = h1r[i].close;

      if(h1Time == 0 || h1Open == 0) continue;

      datetime boundary = GetGMT0_H4Boundary(h1Time, gmtOff);

      if(boundary != prevBoundary)
      {
         // When full, drop oldest candle to keep newest NORM_H4_MAX candles.
         // Without this, the break discards the most recent ~20 candles,
         // causing GetNormH4Shift to map all recent bars to the same RSI.
         if(g_normH4Count >= NORM_H4_MAX)
         {
            for(int k = 0; k < NORM_H4_MAX - 1; k++)
               g_normH4[k] = g_normH4[k+1];
            g_normH4Count = NORM_H4_MAX - 1;
         }
         g_normH4[g_normH4Count].openTime = boundary;
         g_normH4[g_normH4Count].open     = h1Open;
         g_normH4[g_normH4Count].high     = h1High;
         g_normH4[g_normH4Count].low      = h1Low;
         g_normH4[g_normH4Count].close    = h1Close;
         g_normH4Count++;
         prevBoundary = boundary;
      }
      else if(g_normH4Count > 0)
      {
         // Extend current H4 candle
         int idx = g_normH4Count - 1;
         if(h1High > g_normH4[idx].high) g_normH4[idx].high = h1High;
         if(h1Low  < g_normH4[idx].low)  g_normH4[idx].low  = h1Low;
         g_normH4[idx].close = h1Close;
      }
   }

   // Compute RSI on normalized candles using Wilder smoothing
   ComputeNormalizedRSI();

   // Build D1 candles from normalized H4 for MTF engine use
   BuildNormalizedD1Candles();
}

//+------------------------------------------------------------------+
//| ComputeNormalizedRSI — Wilder smoothing RSI on synthetic closes    |
//+------------------------------------------------------------------+
void ComputeNormalizedRSI()
{
   g_normRSICount = 0;
   if(g_normH4Count < InpRSIPeriod + 1) return;

   // Not enough data for Wilder RSI to converge — fallback to native iRSI.
   // With only N-InpRSIPeriod smoothing bars, initial avg still has
   // (13/14)^(N-14) influence. Need ~100 candles for < 0.1% error.
   if(g_normH4Count < NORM_RSI_MIN_CONVERGE) return;

   ArrayInitialize(g_normRSI, 50.0);

   // First pass: simple average of gains/losses for initial RSI
   double avgGain = 0, avgLoss = 0;
   for(int i = 1; i <= InpRSIPeriod; i++)
   {
      double change = g_normH4[i].close - g_normH4[i-1].close;
      if(change > 0) avgGain += change;
      else           avgLoss -= change;
   }
   avgGain /= InpRSIPeriod;
   avgLoss /= InpRSIPeriod;

   if(avgLoss > 0)
      g_normRSI[InpRSIPeriod] = 100.0 - 100.0 / (1.0 + avgGain / avgLoss);
   else
      g_normRSI[InpRSIPeriod] = 100.0;

   // Wilder smoothing for subsequent bars
   for(int i = InpRSIPeriod + 1; i < g_normH4Count; i++)
   {
      double change = g_normH4[i].close - g_normH4[i-1].close;
      double gain = (change > 0) ? change : 0;
      double loss = (change < 0) ? -change : 0;

      avgGain = (avgGain * (InpRSIPeriod - 1) + gain) / InpRSIPeriod;
      avgLoss = (avgLoss * (InpRSIPeriod - 1) + loss) / InpRSIPeriod;

      if(avgLoss > 0)
         g_normRSI[i] = 100.0 - 100.0 / (1.0 + avgGain / avgLoss);
      else
         g_normRSI[i] = 100.0;
   }

   g_normRSICount = g_normH4Count;
}

//+------------------------------------------------------------------+
//| GetNormH4Shift — map broker bar time to normalized candle index    |
//| Returns shift (0=newest) or -1 if not found                        |
//| g_normH4[] is oldest-first, so we reverse-index for shift          |
//+------------------------------------------------------------------+
int GetNormH4Shift(datetime brokerBarTime)
{
   if(g_normH4Count <= 0) return(-1);

   int gmtOff = (InpForceGMTOffset != -99) ? InpForceGMTOffset : GetBrokerGMTOffset();
   // Use last H1 bar time within this H4 bar (+3h) to map broker H4 open time
   // to the correct UTC H4 block. Broker H4 bars may use midnight alignment
   // (e.g. 00,04,08,12,16,20 broker time) instead of UTC H4 alignment.
   // The last H1 bar (H4open+3h) always falls within the UTC H4 block that
   // contains the broker H4 bar's close, giving the correct 1:1 mapping.
   datetime target = GetGMT0_H4Boundary(brokerBarTime + 3*3600, gmtOff);

   // Binary search (g_normH4 is sorted ascending by openTime)
   int lo = 0, hi = g_normH4Count - 1, result = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) / 2;
      if(g_normH4[mid].openTime == target)
      {
         result = mid;
         break;
      }
      else if(g_normH4[mid].openTime < target)
         lo = mid + 1;
      else
         hi = mid - 1;
   }

   if(result < 0)
   {
      // Nearest match: use the bar just before target
      if(hi >= 0 && hi < g_normH4Count)
         result = hi;
      else
         return(-1);
   }

   // Convert ascending index to shift (0=newest)
   int shift = g_normH4Count - 1 - result;
   return(shift);
}

//+------------------------------------------------------------------+
//| GetNormRSIByShift — get normalized RSI by shift (0=newest)         |
//+------------------------------------------------------------------+
double GetNormRSIByShift(int shift)
{
   if(shift < 0 || g_normRSICount <= 0) return(EMPTY_VALUE);

   // shift 0 = newest = array index [g_normRSICount-1]
   int idx = g_normRSICount - 1 - shift;
   if(idx < InpRSIPeriod || idx >= g_normRSICount) return(EMPTY_VALUE);
   return(g_normRSI[idx]);
}

//+------------------------------------------------------------------+
//| BuildNormalizedD1Candles — group normalized H4 into GMT+0 D1      |
//| Each D1 candle = all H4 candles in the same UTC day (00:00-20:00) |
//+------------------------------------------------------------------+
void BuildNormalizedD1Candles()
{
   g_normD1Count = 0;
   g_normD1RSICount = 0;
   if(g_normH4Count < 6) return;

   datetime prevDay = 0;

   for(int i = 0; i < g_normH4Count; i++)
   {
      datetime dayBoundary = g_normH4[i].openTime - (g_normH4[i].openTime % 86400);

      if(dayBoundary != prevDay)
      {
         if(g_normD1Count >= NORM_D1_MAX)
         {
            for(int k = 0; k < NORM_D1_MAX - 1; k++)
               g_normD1[k] = g_normD1[k+1];
            g_normD1Count = NORM_D1_MAX - 1;
         }
         g_normD1[g_normD1Count].openTime = dayBoundary;
         g_normD1[g_normD1Count].open     = g_normH4[i].open;
         g_normD1[g_normD1Count].high     = g_normH4[i].high;
         g_normD1[g_normD1Count].low      = g_normH4[i].low;
         g_normD1[g_normD1Count].close    = g_normH4[i].close;
         g_normD1Count++;
         prevDay = dayBoundary;
      }
      else if(g_normD1Count > 0)
      {
         int idx = g_normD1Count - 1;
         if(g_normH4[i].high > g_normD1[idx].high) g_normD1[idx].high = g_normH4[i].high;
         if(g_normH4[i].low  < g_normD1[idx].low)  g_normD1[idx].low  = g_normH4[i].low;
         g_normD1[idx].close = g_normH4[i].close;
      }
   }

   ComputeNormalizedD1RSI();
}

//+------------------------------------------------------------------+
//| ComputeNormalizedD1RSI — Wilder smoothing RSI on D1 closes         |
//+------------------------------------------------------------------+
void ComputeNormalizedD1RSI()
{
   g_normD1RSICount = 0;
   if(g_normD1Count < InpRSIPeriod + 1) return;
   if(g_normD1Count < NORM_D1_MIN_CONVERGE) return;

   ArrayInitialize(g_normD1RSI, 50.0);

   double avgGain = 0, avgLoss = 0;
   for(int i = 1; i <= InpRSIPeriod; i++)
   {
      double change = g_normD1[i].close - g_normD1[i-1].close;
      if(change > 0) avgGain += change;
      else           avgLoss -= change;
   }
   avgGain /= InpRSIPeriod;
   avgLoss /= InpRSIPeriod;

   if(avgLoss > 0)
      g_normD1RSI[InpRSIPeriod] = 100.0 - 100.0 / (1.0 + avgGain / avgLoss);
   else
      g_normD1RSI[InpRSIPeriod] = 100.0;

   for(int i = InpRSIPeriod + 1; i < g_normD1Count; i++)
   {
      double change = g_normD1[i].close - g_normD1[i-1].close;
      double gain = (change > 0) ? change : 0;
      double loss = (change < 0) ? -change : 0;

      avgGain = (avgGain * (InpRSIPeriod - 1) + gain) / InpRSIPeriod;
      avgLoss = (avgLoss * (InpRSIPeriod - 1) + loss) / InpRSIPeriod;

      if(avgLoss > 0)
         g_normD1RSI[i] = 100.0 - 100.0 / (1.0 + avgGain / avgLoss);
      else
         g_normD1RSI[i] = 100.0;
   }

   g_normD1RSICount = g_normD1Count;
}

//+------------------------------------------------------------------+
//| GetNormD1Shift — map broker bar time to normalized D1 index        |
//| Returns shift (0=newest) or -1 if not found                        |
//+------------------------------------------------------------------+
int GetNormD1Shift(datetime brokerBarTime)
{
   if(g_normD1Count <= 0) return(-1);

   int gmtOff = (InpForceGMTOffset != -99) ? InpForceGMTOffset : GetBrokerGMTOffset();
   // Use midpoint of broker D1 bar (+12h) so we land in the UTC day that
   // contains the majority of this broker D1 bar's data. Without this,
   // midnight-aligned broker D1 at 00:00 converts to UTC 21:00 prev day
   // and floors to the wrong UTC day.
   datetime utcTime = brokerBarTime + 12*3600 - gmtOff * 3600;
   datetime target = utcTime - (utcTime % 86400);

   int lo = 0, hi = g_normD1Count - 1, result = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) / 2;
      if(g_normD1[mid].openTime == target)      { result = mid; break; }
      else if(g_normD1[mid].openTime < target)  lo = mid + 1;
      else                                      hi = mid - 1;
   }

   if(result < 0)
   {
      if(hi >= 0 && hi < g_normD1Count)
         result = hi;
      else
         return(-1);
   }

   return(g_normD1Count - 1 - result);
}

//+------------------------------------------------------------------+
//| GetNormD1RSIByShift — get normalized D1 RSI by shift (0=newest)    |
//+------------------------------------------------------------------+
double GetNormD1RSIByShift(int shift)
{
   if(shift < 0 || g_normD1RSICount <= 0) return(EMPTY_VALUE);
   int idx = g_normD1RSICount - 1 - shift;
   if(idx < InpRSIPeriod || idx >= g_normD1RSICount) return(EMPTY_VALUE);
   return(g_normD1RSI[idx]);
}

//+------------------------------------------------------------------+
//| GetNormMTF_RSI — normalized RSI for MTF engine slots               |
//| slot 4=H4, slot 5=D1. barShift = broker bar shift (0=newest)      |
//| Returns EMPTY_VALUE if normalized data not available               |
//+------------------------------------------------------------------+
double GetNormMTF_RSI(int slot, int tf, int barShift)
{
   if(slot == 4 && g_normRSICount > 0)
   {
      datetime bt = iTime(NULL, tf, barShift);
      if(bt > 0)
      {
         int ns = GetNormH4Shift(bt);
         if(ns >= 0) return(GetNormRSIByShift(ns));
      }
   }
   else if(slot == 5 && g_normD1RSICount > 0)
   {
      datetime bt = iTime(NULL, tf, barShift);
      if(bt > 0)
      {
         int ns = GetNormD1Shift(bt);
         if(ns >= 0) return(GetNormD1RSIByShift(ns));
      }
   }
   return(EMPTY_VALUE);
}

#endif
