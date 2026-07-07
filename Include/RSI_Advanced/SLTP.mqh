//+------------------------------------------------------------------+
//|                                                     SLTP.mqh       |
//|                         RSI Advanced - SL/TP Calculation            |
//|                                                                    |
//| Method 0: ATR-based (Wilder 1978 + Van Tharp 1998)                |
//| Method 1: Fibonacci (Gaucan 2011 + Osler 2000)                    |
//| Method 2: Hybrid ATR + Fibonacci                                   |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_SLTP_MQH
#define RSI_ADV_SLTP_MQH

#include "Config.mqh"
#include "Globals.mqh"
#include "Normalize.mqh"
#include "IntermarketAnalysis.mqh"
#include "WalkForward.mqh"
#include "TFConfig.mqh"

double GetATRValue(int barShift)
{ return(iATR(NULL, 0, InpATRPeriod, barShift)); }

//+------------------------------------------------------------------+
//|        SWING FINDING FOR FIBONACCI                                 |
//+------------------------------------------------------------------+

double FindNearestSwingLow(const double &lo[], int barIndex, int lookback, int totalBars)
{
   double swingLow = lo[barIndex];
   int swingBar = barIndex;
   
   int bs = totalBars - 1 - barIndex;
   if(bs <= 0) bs = 1;
   double curATR = iATR(NULL, 0, InpATRPeriod, bs);
   double avgATR = iATR(NULL, 0, InpATRPeriod * 3, bs); // proxy avg
   int depth = (avgATR > 0 && curATR / avgATR > 1.3) ? 5 : 3;
   // Khi thị trường volatile (ATR spike) → depth=5 → swing khó tạo hơn → SL ổn định hơn

   int start = MathMax(barIndex - lookback, depth);
   int end = barIndex - depth;
   if(end < start) return(lo[barIndex]);

   for(int i = end; i >= start; i--)
   {
      bool isSwing = true;
      for(int d = 1; d <= depth; d++)
      {
         int left = i - d, right = i + d;
         if(left < 0 || right > barIndex) { isSwing = false; break; }
         if(lo[i] > lo[left] || lo[i] > lo[right]) { isSwing = false; break; }
      }
      if(isSwing && lo[i] < swingLow)
      {
         swingLow = lo[i];
         swingBar = i;
         break;
      }
   }
   return(swingLow);
}

double FindNearestSwingHigh(const double &hi[], int barIndex, int lookback, int totalBars)
{
   double swingHigh = hi[barIndex];
   int swingBar = barIndex;
   
   int bs = totalBars - 1 - barIndex;
   if(bs <= 0) bs = 1;
   double curATR = iATR(NULL, 0, InpATRPeriod, bs);
   double avgATR = iATR(NULL, 0, InpATRPeriod * 3, bs); // proxy avg
   int depth = (avgATR > 0 && curATR / avgATR > 1.3) ? 5 : 3;
   
   int start = MathMax(barIndex - lookback, depth);
   int end = barIndex - depth;
   if(end < start) return(hi[barIndex]);

   for(int i = end; i >= start; i--)
   {
      bool isSwing = true;
      for(int d = 1; d <= depth; d++)
      {
         int left = i - d, right = i + d;
         if(left < 0 || right > barIndex) { isSwing = false; break; }
         if(hi[i] < hi[left] || hi[i] < hi[right]) { isSwing = false; break; }
      }
      if(isSwing && hi[i] > swingHigh)
      {
         swingHigh = hi[i];
         swingBar = i;
         break;
      }
   }
   return(swingHigh);
}

void FindSwingRange(bool isBuy, int barIndex,
                    const double &hi[], const double &lo[],
                    int lookback,
                    double &swingHigh, double &swingLow)
{
   int start = MathMax(barIndex - lookback, 0);
   swingHigh = hi[barIndex];
   swingLow = lo[barIndex];

   for(int j = barIndex; j >= start; j--)
   {
      if(hi[j] > swingHigh) swingHigh = hi[j];
      if(lo[j] < swingLow) swingLow = lo[j];
   }
}

//+------------------------------------------------------------------+
//| SL multiplier per case × TF group                                  |
//| Returns multiplier to apply on InpSLRatio.                         |
//| Bounded [0.70, 1.40] — never extreme override of user config.      |
//| Logic:                                                             |
//|   Reversal (1/5): tight — entry at extreme, invalidation clear     |
//|   Divergence (2/3): moderate — lag means needs small extra room    |
//|   Trend (4): wide — pullbacks before continuation are normal       |
//|   TrendCont (6): wide — continuation has shallow pullback risk     |
//|   Sideway (7): tightest — breaks cleanly or fails fast             |
//|   Higher TF: slightly wider (more structural noise per ATR)        |
//+------------------------------------------------------------------+
double GetCaseTFSLMultiplier(int caseNum, int tf)
{
   double mult = 1.0;
   if(tf <= TF_M5)
   {
      if(caseNum==1||caseNum==5||caseNum==9) mult=0.80;
      else if(caseNum==2||caseNum==3) mult=0.95;
      else if(caseNum==4) mult=1.05;
      else if(caseNum==6) mult=1.10;
      else if(caseNum==7) mult=0.70;
   }
   else if(tf <= TF_M30)
   {
      if(caseNum==1||caseNum==5||caseNum==9) mult=0.85;
      else if(caseNum==2||caseNum==3) mult=1.00;
      else if(caseNum==4) mult=1.10;
      else if(caseNum==6) mult=1.10;
      else if(caseNum==7) mult=0.80;
   }
   else if(tf <= TF_H1)
   {
      if(caseNum==1||caseNum==5||caseNum==9) mult=0.90;
      else if(caseNum==2||caseNum==3) mult=1.00;
      else if(caseNum==4) mult=1.15;
      else if(caseNum==6) mult=1.10;
      else if(caseNum==7) mult=0.85;
   }
   else if(tf <= TF_H4)
   {
      if(caseNum==1||caseNum==5||caseNum==9) mult=0.95;
      else if(caseNum==2||caseNum==3) mult=1.05;
      else if(caseNum==4) mult=1.20;
      else if(caseNum==6) mult=1.15;
      else if(caseNum==7) mult=0.90;
   }
   else // D1+
   {
      if(caseNum==1||caseNum==5||caseNum==9) mult=1.00;
      else if(caseNum==2||caseNum==3) mult=1.10;
      else if(caseNum==4) mult=1.25;
      else if(caseNum==6) mult=1.20;
      else if(caseNum==7) mult=0.95;
      else mult=1.05;
   }
   return(MathMax(0.70, MathMin(1.40, mult)));
}

//+------------------------------------------------------------------+
//|        METHOD 0: ATR-BASED (Wilder + Van Tharp)                    |
//+------------------------------------------------------------------+
void CalculateSLTP_ATR(bool isBuy, int barNS, double entry,
                       const double &hi[], const double &lo[], int total,
                       double &outSL, double &outTP1, double &outTP2, double &outTP3,
                       double &outATR, int caseNum = 0)
{
   int bs = total - 1 - barNS;
   outATR = GetATRValue(bs);

   double slRatio = GetActiveSLRatio() * GetCaseTFSLMultiplier(caseNum, Period());

   double atrSL = outATR * slRatio;
   double spreadBuf = GetNormalizedSpreadBuffer();
   double structBuf = outATR * 0.1;
   double totalBuf = spreadBuf + structBuf;

   double tp1D = outATR * GetActiveTPRatio();
   double tp2D = outATR * GetActiveTPRatio() * GetActiveTP2Mult();
   double tp3D = outATR * GetActiveTPRatio() * GetActiveTP3Mult();
   double minSL = GetMinSLDistance();

   if(isBuy)
   {
      int slLookback = GetNormalizedSLLookback();
      double swingSL = FindNearestSwingLow(lo, barNS, slLookback, total) - totalBuf;
      outSL = MathMin(swingSL, entry - atrSL);
      if(entry - outSL < minSL) outSL = entry - minSL;
      outTP1 = entry + tp1D;
      outTP2 = entry + tp2D;
      outTP3 = entry + tp3D;
   }
   else
   {
      int slLookback = GetNormalizedSLLookback();
      double swingSL = FindNearestSwingHigh(hi, barNS, slLookback, total) + totalBuf;
      outSL = MathMax(swingSL, entry + atrSL);
      if(outSL - entry < minSL) outSL = entry + minSL;
      outTP1 = entry - tp1D;
      outTP2 = entry - tp2D;
      outTP3 = entry - tp3D;
   }
}

//+------------------------------------------------------------------+
//|        METHOD 1: FIBONACCI (Gaucan 2011 + Osler 2000)              |
//+------------------------------------------------------------------+
void CalculateSLTP_Fibonacci(bool isBuy, int barNS, double entry,
                              const double &hi[], const double &lo[], int total,
                              double &outSL, double &outTP1, double &outTP2, double &outTP3,
                              double &outATR)
{
   int bs = total - 1 - barNS;
   outATR = GetATRValue(bs);
   double spreadBuf = GetNormalizedSpreadBuffer();
   double minSL = GetMinSLDistance();

   int fibLookback = MathMax(GetActiveSLSwingLB(), 30);
   double swingHigh = 0, swingLow = 0;
   FindSwingRange(isBuy, barNS, hi, lo, fibLookback, swingHigh, swingLow);
   double swingRange = swingHigh - swingLow;

   if(swingRange < outATR) swingRange = outATR;

   if(isBuy)
   {
      double fib786 = swingHigh - swingRange * 0.786;
      outSL = fib786 - spreadBuf;
      if(entry - outSL < minSL) outSL = entry - minSL;
      outTP1 = entry + swingRange * 1.0;
      outTP2 = entry + swingRange * 1.618;
      outTP3 = entry + swingRange * 2.618;
   }
   else
   {
      double fib786 = swingLow + swingRange * 0.786;
      outSL = fib786 + spreadBuf;
      if(outSL - entry < minSL) outSL = entry + minSL;
      outTP1 = entry - swingRange * 1.0;
      outTP2 = entry - swingRange * 1.618;
      outTP3 = entry - swingRange * 2.618;
   }
}

//+------------------------------------------------------------------+
//|        METHOD 2: HYBRID ATR + FIBONACCI                            |
//+------------------------------------------------------------------+
void CalculateSLTP_Hybrid(bool isBuy, int barNS, double entry,
                           const double &hi[], const double &lo[], int total,
                           double &outSL, double &outTP1, double &outTP2, double &outTP3,
                           double &outATR, int caseNum = 0)
{
   int bs = total - 1 - barNS;
   outATR = GetATRValue(bs);
   double spreadBuf = GetNormalizedSpreadBuffer();
   double structBuf = outATR * 0.1;
   double totalBuf = spreadBuf + structBuf;
   double minSL = GetMinSLDistance();

   double slRatio = GetActiveSLRatio() * GetCaseTFSLMultiplier(caseNum, Period());

   double atrSLDist = outATR * slRatio;
   double atrTP1 = outATR * GetActiveTPRatio();
   double atrTP2 = outATR * GetActiveTPRatio() * GetActiveTP2Mult();
   double atrTP3 = outATR * GetActiveTPRatio() * GetActiveTP3Mult();

   int fibLookback = MathMax(GetActiveSLSwingLB(), 30);
   double swingHigh = 0, swingLow = 0;
   FindSwingRange(isBuy, barNS, hi, lo, fibLookback, swingHigh, swingLow);
   double swingRange = MathMax(swingHigh - swingLow, outATR);
   double maxSLDist = outATR * (slRatio + 0.5);

   if(isBuy)
   {
      double fibSL = swingHigh - swingRange * 0.786 - spreadBuf;
      double atrSL = entry - atrSLDist;
      int slLookback = GetNormalizedSLLookback();
      double swingSL = FindNearestSwingLow(lo, barNS, slLookback, total) - totalBuf;
      outSL = MathMin(fibSL, MathMin(atrSL, swingSL));
      if(entry - outSL > maxSLDist) outSL = entry - maxSLDist;
      if(entry - outSL < minSL) outSL = entry - minSL;
      double fibTP1 = entry + swingRange * 1.0;
      double fibTP2 = entry + swingRange * 1.618;
      double fibTP3 = entry + swingRange * 2.618;
      outTP1 = MathMax(fibTP1, entry + atrTP1);
      outTP2 = MathMax(fibTP2, entry + atrTP2);
      outTP3 = MathMax(fibTP3, entry + atrTP3);
   }
   else
   {
      double fibSL = swingLow + swingRange * 0.786 + spreadBuf;
      double atrSL = entry + atrSLDist;
      int slLookback = GetNormalizedSLLookback();
      double swingSL = FindNearestSwingHigh(hi, barNS, slLookback, total) + totalBuf;
      outSL = MathMax(fibSL, MathMax(atrSL, swingSL));
      if(outSL - entry > maxSLDist) outSL = entry + maxSLDist;
      if(outSL - entry < minSL) outSL = entry + minSL;
      double fibTP1 = entry - swingRange * 1.0;
      double fibTP2 = entry - swingRange * 1.618;
      double fibTP3 = entry - swingRange * 2.618;
      outTP1 = MathMin(fibTP1, entry - atrTP1);
      outTP2 = MathMin(fibTP2, entry - atrTP2);
      outTP3 = MathMin(fibTP3, entry - atrTP3);
   }
}

//+------------------------------------------------------------------+
//| Measure optimal TP ratios from ACTUAL market data                   |
//| Phase 1: Actual signals (highest quality)                          |
//| Phase 2: Deep history scan (max samples via GetTPMeasurementBars)  |
//| Returns percentile-based ratios: 50th, 75th, 90th                 |
//+------------------------------------------------------------------+
// [BUG2-FIX] RSI range filter for Phase 2 deep scan, per case and filter level.
// Level 1: case-specific (most accurate, fewest samples).
// Level 2: case-group reversal vs trend (fallback).
// Level 3: direction-only (original broad filter, last resort).
bool _TPRatioRSIFilter(double rsi, double rsiPrev, bool isBuy, int caseNum, int level)
{
   if(level == 1)
   {
      if(isBuy) {
         if((caseNum==1||caseNum==5||caseNum==9) && rsi<33 && rsi>12 && rsi>rsiPrev) return(true);
         if((caseNum==2||caseNum==3) && rsi<42 && rsi>18 && rsi>rsiPrev) return(true);
         if((caseNum==4||caseNum==7) && rsi>47 && rsi<53 && rsi>rsiPrev) return(true);
         if(caseNum==6 && rsi>42 && rsi<62 && rsi>rsiPrev) return(true);
         if(caseNum<=0 && rsi<48 && rsi>18 && rsi>rsiPrev) return(true);
      } else {
         if((caseNum==1||caseNum==5||caseNum==9) && rsi>67 && rsi<88 && rsi<rsiPrev) return(true);
         if((caseNum==2||caseNum==3) && rsi>58 && rsi<82 && rsi<rsiPrev) return(true);
         if((caseNum==4||caseNum==7) && rsi>47 && rsi<53 && rsi<rsiPrev) return(true);
         if(caseNum==6 && rsi>38 && rsi<58 && rsi<rsiPrev) return(true);
         if(caseNum<=0 && rsi>52 && rsi<82 && rsi<rsiPrev) return(true);
      }
      return(false);
   }
   if(level == 2)
   {
      // Reversal group (1/2/3/5): extreme RSI. Trend group (4/6/7): mid RSI.
      bool isReversal=(caseNum==1||caseNum==2||caseNum==3||caseNum==5||caseNum==9);
      bool isTrend=(caseNum==4||caseNum==6||caseNum==7);
      if(isBuy) {
         if(isReversal && rsi<42 && rsi>12 && rsi>rsiPrev) return(true);
         if(isTrend    && rsi<55 && rsi>35 && rsi>rsiPrev) return(true);
         if(!isReversal && !isTrend && rsi<48 && rsi>18 && rsi>rsiPrev) return(true);
      } else {
         if(isReversal && rsi>58 && rsi<88 && rsi<rsiPrev) return(true);
         if(isTrend    && rsi>45 && rsi<65 && rsi<rsiPrev) return(true);
         if(!isReversal && !isTrend && rsi>52 && rsi<82 && rsi<rsiPrev) return(true);
      }
      return(false);
   }
   // Level 3: direction-only (original behavior)
   if(isBuy  && rsi<45 && rsi>15 && rsi>rsiPrev) return(true);
   if(!isBuy && rsi>55 && rsi<85 && rsi<rsiPrev) return(true);
   return(false);
}

// [BUG2-FIX] Minimum moveCount per level per TF before using that level's result.
int _TPRatioMinSamples(int level, int tf)
{
   if(level == 1)
   {
      if(tf <= TF_M5)  return(60);
      if(tf <= TF_H1)  return(25);
      if(tf <= TF_H4)  return(15);
      return(10);
   }
   if(level == 2)
   {
      if(tf <= TF_M5)  return(100);
      if(tf <= TF_H1)  return(45);
      if(tf <= TF_H4)  return(25);
      return(15);
   }
   // Level 3
   return(30);
}

void MeasureOptimalTPRatios(bool isBuy, int barIndex, int totalBars,
                             double &tp1Ratio, double &tp2Ratio, double &tp3Ratio,
                             int caseNum = 0)
{
   tp1Ratio = GetActiveTPRatio();
   tp2Ratio = GetActiveTPRatio() * GetActiveTP2Mult();
   tp3Ratio = GetActiveTPRatio() * GetActiveTP3Mult();

   int tf     = Period();

   // [PERF] Memo-cache the deep NEW->OLD history scan. Its result depends only on
   // (isBuy, caseNum, tf, totalBars): the barIndex arg is unused, Phase 1 is skipped
   // during fullRecalc, and Phase 2 is pure history. CalculateSLTP calls this once per
   // signal, so on a fullRecalc rebuild (N signals) an uncached scan re-walks thousands
   // of bars N times -> the dominant TF-switch cost on BOTH MT4 and MT5. totalBars
   // (=rates_total) is the invalidation token: constant within one OnCalculate pass, and
   // bumps on every new bar and on TF switch. Small table keyed by (caseNum,dir) because
   // the detection loop interleaves cases/directions (a single slot would thrash).
   // Mirrors the MeasureEdgeFromHistory cache (Normalize.mqh).
   static int    s_tpTf   = -1;
   static int    s_tpBars = -1;
   static bool   s_tpValid[20];   // index = caseNum*2 + (isBuy?1:0); caseNum 0..9
   static double s_tpV1[20];
   static double s_tpV2[20];
   static double s_tpV3[20];
   if(s_tpTf != tf || s_tpBars != totalBars)
   {
      for(int _c = 0; _c < 20; _c++) s_tpValid[_c] = false;
      s_tpTf   = tf;
      s_tpBars = totalBars;
   }
   int s_tpSlot = (caseNum >= 0 && caseNum <= 9) ? (caseNum * 2 + (isBuy ? 1 : 0)) : -1;
   if(s_tpSlot >= 0 && s_tpValid[s_tpSlot])
   {
      tp1Ratio = s_tpV1[s_tpSlot];
      tp2Ratio = s_tpV2[s_tpSlot];
      tp3Ratio = s_tpV3[s_tpSlot];
      return;
   }

   int maxFwd = GetMaxForwardBarsForTimeframe();
   int timeBasedMax = MathMax(1440 / MathMax(tf, 1), maxFwd);

   // IS/OOS split — same as MeasureEdgeFromHistory, measure on IS signals only
   int splitIdx = g_signalCount;
   if(InpUseWalkForward && g_signalCount >= 10)
   {
      double oosPct = MathMax(10.0, MathMin(30.0, (double)InpOOSPercent));
      splitIdx = (int)(g_signalCount * (100.0 - oosPct) / 100.0);
      if(splitIdx < 5) splitIdx = g_signalCount;
   }

   // Time-based cutoff (same window as MeasureEdgeFromHistory)
   int edgeMaxDays = (tf <= TF_M5) ? 60 : (tf <= TF_H1) ? 180 : 365;
   datetime edgeCutoffTime = TimeCurrent() - edgeMaxDays * 86400;

   // Try levels 1→2→3, accept first that has enough samples
   for(int level = 1; level <= 3; level++)
   {
      double moveRatios[];
      int moveCount = 0;

      //--- Phase 1: Actual IS signals
      for(int s = 0; s < splitIdx; s++)
      {
         if(g_signals[s].isBuySignal != isBuy) continue;
         if(g_signals[s].barIndex + timeBasedMax >= Bars) continue;
         double sigEntry = g_signals[s].entryPrice;
         double sigATR   = g_signals[s].atrValue;
         double sigSL    = g_signals[s].stopLoss;
         if(sigATR <= 0) continue;
         // Case filter for Phase 1 actual signals
         if(level == 1 && caseNum > 0 && g_signals[s].caseNumber != caseNum) continue;
         if(level == 2)
         {
            bool isRev=(caseNum==1||caseNum==2||caseNum==3||caseNum==5||caseNum==9);
            bool isTrend=(caseNum==4||caseNum==6||caseNum==7||caseNum==8);
            bool sigRev=(g_signals[s].caseNumber==1||g_signals[s].caseNumber==2||
                         g_signals[s].caseNumber==3||g_signals[s].caseNumber==5||g_signals[s].caseNumber==9);
            bool sigTrend=(g_signals[s].caseNumber==4||g_signals[s].caseNumber==6||
                           g_signals[s].caseNumber==7||g_signals[s].caseNumber==8);
            if(isRev && !sigRev) continue;
            if(isTrend && !sigTrend) continue;
         }

         double maxFav = 0;
         for(int b = g_signals[s].barIndex + 1;
            b < g_signals[s].barIndex + timeBasedMax && b < Bars; b++)
         {
            int bs = Bars - 1 - b; if(bs < 0) break;
            double bH = iHigh(NULL, 0, bs), bL = iLow(NULL, 0, bs);
            double fav = isBuy ? (bH - sigEntry) : (sigEntry - bL);
            if(fav > maxFav) maxFav = fav;
            if(isBuy  && bL <= sigSL) break;
            if(!isBuy && bH >= sigSL) break;
         }
         if(maxFav > 0)
         {
            moveCount++;
            ArrayResize(moveRatios, moveCount, 64);
            moveRatios[moveCount-1] = maxFav / sigATR;
         }
      }

      //--- Phase 2: Deep history NEW→OLD with time cutoff
      int phase1Start  = MathMax(0, Bars - InpMaxBars);
      int deepEnd      = totalBars - maxFwd - 10;
      int deepUpperBound = MathMin(phase1Start, deepEnd);

      for(int i = deepUpperBound-1; i >= InpRSIPeriod+10 && moveCount < 500; i--)
      {
         int bs = totalBars - 1 - i; if(bs < 0) continue;
         if(iTime(NULL, 0, bs) < edgeCutoffTime) break; // NEW→OLD: all remaining are older

         double rsi     = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs);
         double rsiPrev = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs+1);
         double atr     = iATR(NULL, 0, InpATRPeriod, bs);
         if(rsi==0 || rsiPrev==0 || atr==0) continue;

         if(!_TPRatioRSIFilter(rsi, rsiPrev, isBuy, caseNum, level)) continue;

         double entryP = iClose(NULL, 0, bs);
         double slDist = atr * GetActiveSLRatio();
         double maxFav = 0;
         for(int b = i+1; b < i+timeBasedMax && b < deepEnd; b++)
         {
            int fbs = totalBars - 1 - b; if(fbs < 0) break;
            double bH = iHigh(NULL, 0, fbs), bL = iLow(NULL, 0, fbs);
            double fav = isBuy ? (bH - entryP) : (entryP - bL);
            if(fav > maxFav) maxFav = fav;
            if(isBuy  && (entryP - bL) > slDist) break;
            if(!isBuy && (bH - entryP) > slDist) break;
         }
         if(maxFav > 0)
         {
            moveCount++;
            ArrayResize(moveRatios, moveCount, 64);
            moveRatios[moveCount-1] = maxFav / atr;
         }
      }

      // Accept this level if enough samples; else try next level
      if(moveCount < _TPRatioMinSamples(level, tf)) continue;

      ArraySort(moveRatios);
      int tgt[3];
      tgt[0] = MathMax(0, MathMin((int)(moveCount*0.50), moveCount-1));
      tgt[1] = MathMax(0, MathMin((int)(moveCount*0.75), moveCount-1));
      tgt[2] = MathMax(0, MathMin((int)(moveCount*0.90), moveCount-1));
      tp1Ratio = moveRatios[tgt[0]];
      tp2Ratio = moveRatios[tgt[1]];
      tp3Ratio = moveRatios[tgt[2]];

      tp1Ratio = MathMax(tp1Ratio, GetActiveSLRatio());
      if(tp2Ratio <= tp1Ratio) tp2Ratio = tp1Ratio * 1.5;
      if(tp3Ratio <= tp2Ratio) tp3Ratio = tp2Ratio * 1.3;
      break; // accepted this level — store into cache below
   }
   // Level 4: not enough data at any level — parametric values (set at top) stand.

   // [PERF] Store into memo cache before returning. Covers both the level-accept break
   // above and the parametric fall-through, so every path populates the cache.
   if(s_tpSlot >= 0)
   {
      s_tpValid[s_tpSlot] = true;
      s_tpV1[s_tpSlot]    = tp1Ratio;
      s_tpV2[s_tpSlot]    = tp2Ratio;
      s_tpV3[s_tpSlot]    = tp3Ratio;
   }
}


//+------------------------------------------------------------------+
//|        MAIN ENTRY POINT - Routes to selected method                |
//+------------------------------------------------------------------+
void CalculateSLTP(bool isBuy, int barNS, double entry,
                   const double &hi[], const double &lo[], int total,
                   double &outSL, double &outTP1, double &outTP2, double &outTP3,
                   double &outATR, int caseNum = 0)
{
   // Measure optimal TP ratios from actual market data (case-specific, IS-only, NEW→OLD)
   double optTP1, optTP2, optTP3;
   MeasureOptimalTPRatios(isBuy, barNS, total, optTP1, optTP2, optTP3, caseNum);

   // Calculate SL/TP using selected method
   switch(GetActiveSLTPMethod())
   {
      case SLTP_FIBONACCI:
         CalculateSLTP_Fibonacci(isBuy, barNS, entry, hi, lo, total,
                                 outSL, outTP1, outTP2, outTP3, outATR);
         break;
      case SLTP_HYBRID:
         CalculateSLTP_Hybrid(isBuy, barNS, entry, hi, lo, total,
                              outSL, outTP1, outTP2, outTP3, outATR, caseNum);
         break;
      default:
         CalculateSLTP_ATR(isBuy, barNS, entry, hi, lo, total,
                           outSL, outTP1, outTP2, outTP3, outATR, caseNum);
         break;
   }

   // [BUG1-FIX] Bayesian shrinkage + conservative gate.
   // Old code: always replace with measured TP regardless of direction.
   // New: blend measured toward parametric (shrinkage), then only apply if blended
   // is CLOSER to entry than method TP (conservative — measured may only tighten, not widen).
   // Shrinkage prior k scales with TF: higher TF has fewer samples → heavier prior.
   // Clip: [InpSLRatio*0.8, InpTPRatio*2.0] prevents extreme outlier regimes.
   int tf = Period();
   double k_tf = (tf <= TF_M5) ? 50 : (tf <= TF_M30) ? 80 :
                 (tf <= TF_H1) ? 180 : (tf <= TF_H4) ? 300 : 600;

   // Approximate moveCount credibility from ratio (MeasureOptimalTPRatios already
   // only returns non-parametric when samples passed minSamples threshold).
   // Use ratio deviation as proxy: if optTP1==InpTPRatio, no data was applied (L4).
   bool measuredApplied = (MathAbs(optTP1 - GetActiveTPRatio()) > 0.01 ||
                           MathAbs(optTP2 - GetActiveTPRatio()*GetActiveTP2Mult()) > 0.01);
   if(measuredApplied)
   {
      // Estimate sample count proxy from level used (conservative: assume min threshold)
      int minSamp = _TPRatioMinSamples(1, tf); // level 1 min as conservative proxy
      double credibility = MathMin(1.0, (double)minSamp / (minSamp + k_tf));

      double b1 = optTP1 * credibility + GetActiveTPRatio() * (1.0 - credibility);
      double b2 = optTP2 * credibility + GetActiveTPRatio()*GetActiveTP2Mult()*(1.0-credibility);
      double b3 = optTP3 * credibility + GetActiveTPRatio()*GetActiveTP3Mult()*(1.0-credibility);

      // Hard clip: measured ratio bounded within [SLRatio*0.8, TPRatio*2.0]
      b1 = MathMax(GetActiveSLRatio()*0.8, MathMin(GetActiveTPRatio()*2.0, b1));
      b2 = MathMax(b1, MathMin(GetActiveTPRatio()*2.5, b2));
      b3 = MathMax(b2, MathMin(GetActiveTPRatio()*3.0, b3));

      double mTP1 = entry + (isBuy ? 1.0 : -1.0) * outATR * b1;
      double mTP2 = entry + (isBuy ? 1.0 : -1.0) * outATR * b2;
      double mTP3 = entry + (isBuy ? 1.0 : -1.0) * outATR * b3;

      // Conservative gate: only apply if blended TP is closer to entry than method TP.
      // Closer = more achievable = lower risk of TP not being hit.
      if(isBuy)
      {
         if(mTP1 < outTP1) outTP1 = mTP1;
         if(mTP2 < outTP2) outTP2 = mTP2;
         if(mTP3 < outTP3) outTP3 = mTP3;
         if(outTP2 <= outTP1) outTP2 = outTP1 + outATR * 0.5;
         if(outTP3 <= outTP2) outTP3 = outTP2 + outATR * 0.5;
      }
      else
      {
         if(mTP1 > outTP1) outTP1 = mTP1;
         if(mTP2 > outTP2) outTP2 = mTP2;
         if(mTP3 > outTP3) outTP3 = mTP3;
         if(outTP2 >= outTP1) outTP2 = outTP1 - outATR * 0.5;
         if(outTP3 >= outTP2) outTP3 = outTP2 - outATR * 0.5;
      }
   }
}

//+------------------------------------------------------------------+
//|     ██  ENTRY ZONE SYSTEM  ██                                      |
//+------------------------------------------------------------------+

void AnalyzePriceDistribution(bool isBuy, int barIndex,
                               double entryPrice, double slPrice,
                               const double &hi[], const double &lo[],
                               int lookback, int numZonesRequested,
                               double &zonePrices[], double &zoneProbs[])
{
   ArrayResize(zonePrices, numZonesRequested);
   ArrayResize(zoneProbs, numZonesRequested);
   ArrayInitialize(zonePrices, 0);
   ArrayInitialize(zoneProbs, 0);

   double rangeHigh = isBuy ? entryPrice : slPrice;
   double rangeLow  = isBuy ? slPrice : entryPrice;
   double rangeSize = rangeHigh - rangeLow;
   if(rangeSize <= 0) return;

   int microZones = 20;
   double zoneHeight = rangeSize / microZones;
   double zoneTime[];
   ArrayResize(zoneTime, microZones);
   ArrayInitialize(zoneTime, 0);

   int startBar = MathMax(barIndex - lookback, 0);
   double totalTime = 0;

   for(int b = startBar; b <= barIndex; b++)
   {
      double barRange = hi[b] - lo[b];
      if(barRange <= 0) continue;

      // MQL5 only: weight each bar by sqrt(tickVolume) to approximate
      // a Volume Profile (VPOC) instead of a pure Time Price Opportunity
      // (TPO) chart. sqrt() dampens extreme volume spikes (news events)
      // while still giving more weight to high-activity price levels.
      // MQL4 falls back to weight=1.0 (tick volume is unreliable there).
      double volWeight = 1.0;
#ifdef __MQL5__
      int barShift = Bars - 1 - b;
      if(barShift >= 0)
      {
         long bVol = (long)iVolume(NULL, 0, barShift);
         if(bVol > 0) volWeight = MathSqrt((double)bVol);
      }
#endif

      for(int z = 0; z < microZones; z++)
      {
         double zLow  = rangeLow + z * zoneHeight;
         double zHigh = zLow + zoneHeight;
         double overlap = MathMin(zHigh, hi[b]) - MathMax(zLow, lo[b]);
         if(overlap <= 0) continue;
         double timeFraction = overlap / barRange * volWeight;
         zoneTime[z] += timeFraction;
         totalTime += timeFraction;
      }
   }
   if(totalTime <= 0) return;

   for(int z = 0; z < microZones; z++)
      zoneTime[z] /= totalTime;

   int maxPullbackZones = numZonesRequested - 1;
   if(maxPullbackZones > 4) maxPullbackZones = 4;
   double rangeStart = 0.10;
   double rangeEnd   = 0.90;
   double segmentSize = (rangeEnd - rangeStart) / MathMax(maxPullbackZones, 1);
   double fibFallback[] = {0.382, 0.618, 0.786, 0.886};

   for(int req = 0; req < maxPullbackZones; req++)
   {
      double sLow  = rangeStart + req * segmentSize;
      double sHigh = sLow + segmentSize;
      double lowestTime = 999;
      int lowestIdx = -1;

      for(int z = 0; z < microZones; z++)
      {
         double zoneRatio = ((double)z + 0.5) / microZones;
         if(isBuy) zoneRatio = 1.0 - zoneRatio;
         if(zoneRatio >= sLow && zoneRatio <= sHigh)
         {
            if(zoneTime[z] < lowestTime)
            {
               lowestTime = zoneTime[z];
               lowestIdx = z;
            }
         }
      }

      if(lowestIdx >= 0 && totalTime > 5)
      {
         zonePrices[req] = rangeLow + (lowestIdx + 0.5) * zoneHeight;
         double avgTime = 1.0 / microZones;
         double timeRatio = lowestTime / MathMax(avgTime, 0.001);
         zoneProbs[req] = MathMax(0.10, MathMin(0.90, 1.0 - timeRatio));
      }
      else
      {
         int fibIdx = MathMin(req, 3);
         if(isBuy)
            zonePrices[req] = entryPrice - rangeSize * fibFallback[fibIdx];
         else
            zonePrices[req] = entryPrice + rangeSize * fibFallback[fibIdx];
         double progress = (double)(req + 1) / (double)(maxPullbackZones + 1);
         zoneProbs[req] = MathMax(0.10, 0.65 * (1.0 - progress));
      }
   }
}

//+------------------------------------------------------------------+
//| Validate SL against high volume zones                              |
//| DATA-DRIVEN buffer: spread × 2 (not hardcoded ATR ratio)          |
//+------------------------------------------------------------------+
double ValidateSLAgainstVolume(bool isBuy, double currentSL, double entryPrice,
                                const double &hi[], const double &lo[],
                                int barIndex, int lookback, double atr)
{
   double scanRange = atr * 2.0;
   double rangeHigh, rangeLow;

   if(isBuy)
   {
      rangeHigh = entryPrice + atr * 0.5;
      rangeLow  = currentSL - atr * 0.5;
   }
   else
   {
      rangeHigh = currentSL + atr * 0.5;
      rangeLow  = entryPrice - atr * 0.5;
   }

   double rangeSize = rangeHigh - rangeLow;
   if(rangeSize <= 0) return(currentSL);

   // DATA-DRIVEN SL buffer: MAX of spread × 2 or ATR × 0.1
   // spread × 2 covers typical spread widening during stop hunt
   // Not hardcoded ratio - derived from actual broker spread
   double slBuffer = MathMax(MarketInfo(Symbol(), MODE_SPREAD) * _Point * 2.0, atr * 0.1);

   int microZones = 20;
   double zoneHeight = rangeSize / microZones;
   double zoneTime[];
   ArrayResize(zoneTime, microZones);
   ArrayInitialize(zoneTime, 0);

   int startBar = MathMax(barIndex - lookback, 0);
   double totalTime = 0;

   for(int b = startBar; b <= barIndex; b++)
   {
      double barRange = hi[b] - lo[b];
      if(barRange <= 0) continue;
      for(int z = 0; z < microZones; z++)
      {
         double zLow  = rangeLow + z * zoneHeight;
         double zHigh = zLow + zoneHeight;
         double overlap = MathMin(zHigh, hi[b]) - MathMax(zLow, lo[b]);
         if(overlap <= 0) continue;
         zoneTime[z] += overlap / barRange;
         totalTime += overlap / barRange;
      }
   }
   if(totalTime <= 0) return(currentSL);

   int slZone = -1;
   for(int z = 0; z < microZones; z++)
   {
      double zLow  = rangeLow + z * zoneHeight;
      double zHigh = zLow + zoneHeight;
      if(currentSL >= zLow && currentSL <= zHigh)
      { slZone = z; break; }
   }
   if(slZone < 0) return(currentSL);

   double sumTime = 0, sumTimeSq = 0;
   int validZones = 0;
   for(int z = 0; z < microZones; z++)
   {
      if(zoneTime[z] > 0)
      {
         sumTime += zoneTime[z];
         sumTimeSq += zoneTime[z] * zoneTime[z];
         validZones++;
      }
   }

   double meanTime = (validZones > 0) ? sumTime / validZones : 0;
   double varTime = (validZones > 1) ?
      (sumTimeSq / validZones) - (meanTime * meanTime) : 0;
   double stdTime = MathSqrt(MathMax(varTime, 0));
   double highVolThreshold = meanTime + stdTime;
   double slZoneTime = zoneTime[slZone];

   if(slZoneTime <= highVolThreshold) return(currentSL);

   if(isBuy)
   {
      for(int z = slZone - 1; z >= 0; z--)
      {
         if(zoneTime[z] <= meanTime)
         {
            double newSL = rangeLow + z * zoneHeight;
            newSL -= slBuffer;
            if(newSL < currentSL) return(newSL);
            break;
         }
      }
      double bottomSL = rangeLow - slBuffer;
      if(bottomSL < currentSL) return(bottomSL);
   }
   else
   {
      for(int z = slZone + 1; z < microZones; z++)
      {
         if(zoneTime[z] <= meanTime)
         {
            double newSL = rangeLow + (z + 1) * zoneHeight;
            newSL += slBuffer;
            if(newSL > currentSL) return(newSL);
            break;
         }
      }
      double topSL = rangeHigh + slBuffer;
      if(topSL > currentSL) return(topSL);
   }

   return(currentSL);
}

//+------------------------------------------------------------------+
double MeasureZoneReachProb(bool isBuy, double entryPrice, double zonePrice,
                             double moveHeight, int maxForward)
{
   if(moveHeight <= 0) return(0.5);
   double retraceLevel = MathAbs(entryPrice - zonePrice) / moveHeight;
   int reachedCount = 0;
   int totalCount = 0;
   int timeBasedMax = 1440 / MathMax(Period(), 1);
   timeBasedMax = MathMax(timeBasedMax, maxForward);

   for(int s = 0; s < g_signalCount; s++)
   {
      if(g_signals[s].isBuySignal != isBuy) continue;
      if(g_signals[s].barIndex + timeBasedMax >= Bars) continue;
      double sigEntry = g_signals[s].entryPrice;
      double sigMove = MathAbs(sigEntry - g_signals[s].stopLoss);
      if(sigMove <= 0) continue;
      double extremePrice = sigEntry;

      for(int b = g_signals[s].barIndex + 1;
          b < g_signals[s].barIndex + timeBasedMax && b < Bars; b++)
      {
         int bs = Bars - 1 - b;
         if(bs < 0) break;
         if(isBuy)
         {
            double barLow = iLow(NULL, 0, bs);
            if(barLow < extremePrice) extremePrice = barLow;
         }
         else
         {
            double barHigh = iHigh(NULL, 0, bs);
            if(barHigh > extremePrice) extremePrice = barHigh;
         }
      }
      double actualRetrace = MathAbs(sigEntry - extremePrice) / sigMove;
      totalCount++;
      if(actualRetrace >= retraceLevel) reachedCount++;
   }
   if(totalCount < 5) return(0.5);
   return((double)reachedCount / (double)totalCount);
}

color GetZoneColor(int zoneIndex)
{
   switch(zoneIndex)
   {
      case 0: return(InpZone1Color);
      case 1: return(InpZone2Color);
      case 2: return(InpZone3Color);
      case 3: return(InpZone4Color);
      case 4: return(InpZone5Color);
   }
   return(clrGray);
}

void CalculateRiskShares(int zoneCount, double &shares[])
{
   ArrayResize(shares, zoneCount);
   if(zoneCount <= 0) return;
   if(zoneCount == 1) { shares[0] = 1.0; return; }
   double totalWeight = zoneCount * (zoneCount + 1) / 2.0;
   for(int i = 0; i < zoneCount; i++)
      shares[i] = (double)(zoneCount - i) / totalWeight;
}

//+------------------------------------------------------------------+
//| MAIN: Calculate all entry zones                                    |
//+------------------------------------------------------------------+
void CalculateEntryZones(bool isBuy, int barIndex,
                          double marketEntry, double sl, double tp1,
                          double atr,
                          const double &hi[], const double &lo[],
                          int totalBars)
{
   g_validZoneCount = 0;
   g_recommendedZoneCount = 0;

   for(int z = 0; z < 5; z++)
   {
      g_entryZones[z].price = 0;
      g_entryZones[z].slDistance = 0;
      g_entryZones[z].tp1Distance = 0;
      g_entryZones[z].riskShare = 0;
      g_entryZones[z].lotSize = 0;
      g_entryZones[z].rrRatio = 0;
      g_entryZones[z].probReach = 0;
      g_entryZones[z].probTP1 = 0;
      g_entryZones[z].expectedValue = 0;
      g_entryZones[z].isValid = false;
      g_entryZones[z].isRecommended = false;
      g_entryZones[z].zoneName = "";
   }

   int maxZones = MathMax(2, MathMin(5, GetActiveZoneCount()));
   double moveHeight = MathAbs(marketEntry - sl);

   // DATA-DRIVEN minSLDist: from broker data, not hardcoded ratio
   // spread × 5 = zone must survive 5× spread movement
   // This ensures meaningful trade distance
   double brokerMinSL = MarketInfo(Symbol(), MODE_STOPLEVEL) * _Point;
   double spreadMinSL = MarketInfo(Symbol(), MODE_SPREAD) * _Point * 5.0;
   double minSLDist = MathMax(brokerMinSL, spreadMinSL);

   int maxFwd = GetMaxForwardBarsForTimeframe();
   if(moveHeight <= 0) return;

   double effectiveSL = ValidateSLAgainstVolume(isBuy, sl, marketEntry,
                                                 hi, lo, barIndex,
                                                 GetActivePriceDistLB(), atr);

   if(isBuy)
      effectiveSL = MathMin(effectiveSL, sl);
   else
      effectiveSL = MathMax(effectiveSL, sl);

   moveHeight = MathAbs(marketEntry - effectiveSL);
   if(moveHeight <= 0) return;

   double pullbackPrices[];
   double pullbackProbs[];
   // Use original sl (chart-drawn boundary) for zone placement so no zone appears
   // beyond the visible SL line. effectiveSL may be expanded by ValidateSLAgainstVolume
   // and is kept only for per-zone slDistance (lot sizing).
   AnalyzePriceDistribution(isBuy, barIndex, marketEntry, sl,
                             hi, lo, GetActivePriceDistLB(),
                             maxZones, pullbackPrices, pullbackProbs);

   int bar = totalBars - 1 - barIndex;
   if(bar <= 0) bar =1;                             
   double curATR = iATR(NULL, 0, InpATRPeriod, bar);
   double avgATR = 0;
   int atrCnt = 0;
   for(int a = 1; a <= 50; a++)
   {
      int bs = totalBars - 1 - barIndex + a;
      if(bs >= Bars || bs < 0) break;
      avgATR += iATR(NULL, 0, InpATRPeriod, bs);
      atrCnt++;
   }
   if(atrCnt > 0) avgATR /= atrCnt;

   int adaptiveMax = maxZones;
   if(avgATR > 0)
   {
      double atrRatio = curATR / avgATR;
      if(atrRatio > 1.5) adaptiveMax = MathMin(maxZones + 1, 5);
      if(atrRatio < 0.5) adaptiveMax = MathMax(2, maxZones - 1);
   }
   adaptiveMax = MathMin(adaptiveMax, maxZones);

   double edge = MeasureEdgeFromHistory(0, isBuy, maxFwd);

   double shares[];
   CalculateRiskShares(adaptiveMax, shares);

   double accountBalance = AccountBalance();
   if(accountBalance <= 0) accountBalance = 1000;
   double totalRisk = accountBalance * GetActiveRiskPct() / 100.0;

   g_entryZones[0].price = marketEntry;
   g_entryZones[0].zoneName = "Market";
   g_entryZones[0].probReach = 0.95;
   g_entryZones[0].isValid = true;
   g_validZoneCount = 1;

   for(int z = 1; z < adaptiveMax; z++)
   {
      if(z - 1 < ArraySize(pullbackPrices) && pullbackPrices[z - 1] > 0)
         g_entryZones[z].price = pullbackPrices[z - 1];
      else
         g_entryZones[z].price = 0;

      g_entryZones[z].zoneName = "PB-Z" + IntegerToString(z + 1);

      if(g_entryZones[z].price <= 0)
      { g_entryZones[z].isValid = false; continue; }

      // Validate against original sl (chart-drawn line), not effectiveSL.
      // A zone must lie strictly between marketEntry and the visible SL.
      if(isBuy)
      {
         if(g_entryZones[z].price >= marketEntry || g_entryZones[z].price <= sl)
         { g_entryZones[z].isValid = false; continue; }
      }
      else
      {
         if(g_entryZones[z].price <= marketEntry || g_entryZones[z].price >= sl)
         { g_entryZones[z].isValid = false; continue; }
      }

      g_entryZones[z].isValid = true;
      g_validZoneCount++;

      double rawReach;
      if(z - 1 < ArraySize(pullbackProbs) && pullbackProbs[z - 1] > 0)
         rawReach = pullbackProbs[z - 1];
      else
         rawReach = MeasureZoneReachProb(
            isBuy, marketEntry, g_entryZones[z].price, moveHeight, maxFwd);

      // Distance decay: zones farther from entry are harder to reach.
      // Exponential decay: distFraction=0 (at entry) → decay=1.0 (no reduction)
      //                    distFraction=1 (at SL)     → decay=0.135 (86% reduction)
      // This ensures Z2 (close to entry) always has higher probReach than Z3 (far),
      // correctly reflecting that a 9-pip pullback is more likely than a 65-pip pullback.
      double distFraction = (moveHeight > 0)
         ? MathAbs(marketEntry - g_entryZones[z].price) / moveHeight
         : 0;
      double distDecay = MathExp(-distFraction * 2.0);
      g_entryZones[z].probReach = MathMax(0.05, MathMin(0.90, rawReach * distDecay));
   }

   g_recommendedZoneCount = 0;

   for(int z = 0; z < adaptiveMax; z++)
   {
      if(!g_entryZones[z].isValid) continue;

      // Use original sl for slDistance: this matches the actual SL order placed
      // and makes R:R / lot size consistent with what the trader sees on chart.
      if(isBuy)
      {
         g_entryZones[z].slDistance = g_entryZones[z].price - sl;
         g_entryZones[z].tp1Distance = tp1 - g_entryZones[z].price;
      }
      else
      {
         g_entryZones[z].slDistance = sl - g_entryZones[z].price;
         g_entryZones[z].tp1Distance = g_entryZones[z].price - tp1;
      }

      if(g_entryZones[z].slDistance < minSLDist && z > 0)
      {
         g_entryZones[z].isValid = false;
         g_validZoneCount--;
         continue;
      }

      g_entryZones[z].rrRatio = (g_entryZones[z].slDistance > 0) ?
         g_entryZones[z].tp1Distance / g_entryZones[z].slDistance : 0;

      g_entryZones[z].probTP1 = CalculateRealMarketProbTP(
         edge, g_entryZones[z].slDistance, g_entryZones[z].tp1Distance, atr) * 100.0;

      double winRate = g_entryZones[z].probTP1 / 100.0;
      g_entryZones[z].expectedValue = g_entryZones[z].probReach *
         (winRate * g_entryZones[z].rrRatio - (1.0 - winRate) * 1.0);

      g_entryZones[z].isRecommended = (g_entryZones[z].expectedValue > 0 || z == 0);
      if(g_entryZones[z].isRecommended) g_recommendedZoneCount++;

      g_entryZones[z].riskShare = (z < ArraySize(shares)) ? shares[z] : 0;

      double pipValue = 0;
      double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
      double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
      if(tickSize > 0)
         pipValue = tickValue * (g_entryZones[z].slDistance / tickSize);

      if(pipValue > 0)
         g_entryZones[z].lotSize = NormalizeDouble(
            (totalRisk * g_entryZones[z].riskShare) / pipValue, 2);
      else
         g_entryZones[z].lotSize = MarketInfo(Symbol(), MODE_MINLOT);

      double minLot = MarketInfo(Symbol(), MODE_MINLOT);
      g_entryZones[z].lotSize = MathMax(g_entryZones[z].lotSize, minLot);
   }

   if(g_recommendedZoneCount < 2)
   {
      for(int z = 0; z < adaptiveMax && g_recommendedZoneCount < 2; z++)
      {
         if(g_entryZones[z].isValid && !g_entryZones[z].isRecommended)
         {
            g_entryZones[z].isRecommended = true;
            g_recommendedZoneCount++;
         }
      }
   }

   double totalRecShare = 0;
   for(int z = 0; z < adaptiveMax; z++)
      if(g_entryZones[z].isRecommended)
         totalRecShare += g_entryZones[z].riskShare;

   if(totalRecShare > 0 && MathAbs(totalRecShare - 1.0) > 0.01)
   {
      for(int z = 0; z < adaptiveMax; z++)
      {
         if(g_entryZones[z].isRecommended)
         {
            g_entryZones[z].riskShare /= totalRecShare;
            double pv = 0;
            double tv = MarketInfo(Symbol(), MODE_TICKVALUE);
            double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
            if(ts > 0) pv = tv * (g_entryZones[z].slDistance / ts);
            if(pv > 0)
               g_entryZones[z].lotSize = NormalizeDouble(
                  (totalRisk * g_entryZones[z].riskShare) / pv, 2);
            double ml = MarketInfo(Symbol(), MODE_MINLOT);
            g_entryZones[z].lotSize = MathMax(g_entryZones[z].lotSize, ml);
         }
         else
         {
            g_entryZones[z].riskShare = 0;
            g_entryZones[z].lotSize = 0;
         }
      }
   }
}

#endif