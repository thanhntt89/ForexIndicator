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
#include "Normalize.mqh"
#include "IntermarketAnalysis.mqh"
#include "WalkForward.mqh"

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
//|        METHOD 0: ATR-BASED (Wilder + Van Tharp)                    |
//+------------------------------------------------------------------+
void CalculateSLTP_ATR(bool isBuy, int barNS, double entry,
                       const double &hi[], const double &lo[], int total,
                       double &outSL, double &outTP1, double &outTP2, double &outTP3,
                       double &outATR, int caseNum = 0)
{
   int bs = total - 1 - barNS;
   outATR = GetATRValue(bs);

   // [CASE-SL] Case+TF SL ratio override — tighter/wider stop by case
   double slRatio = InpSLRatio;
   if(caseNum == 7 && Period() == TF_M5) slRatio = 1.2;  // Sideway break M5: tight stop
   if(caseNum == 6 && Period() == TF_M5) slRatio = 2.2;  // Trend cont M5: wide stop

   double atrSL = outATR * slRatio;
   double spreadBuf = GetNormalizedSpreadBuffer();
   double structBuf = outATR * 0.1;
   double totalBuf = spreadBuf + structBuf;

   double tp1D = outATR * InpTPRatio;
   double tp2D = outATR * InpTPRatio * InpTP2Multiplier;
   double tp3D = outATR * InpTPRatio * InpTP3Multiplier;
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

   int fibLookback = MathMax(InpSLSwingLookback, 30);
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

   // [CASE-SL] Case+TF SL ratio override
   double slRatio = InpSLRatio;
   if(caseNum == 7 && Period() == TF_M5) slRatio = 1.2;
   if(caseNum == 6 && Period() == TF_M5) slRatio = 2.2;

   double atrSLDist = outATR * slRatio;
   double atrTP1 = outATR * InpTPRatio;
   double atrTP2 = outATR * InpTPRatio * InpTP2Multiplier;
   double atrTP3 = outATR * InpTPRatio * InpTP3Multiplier;

   int fibLookback = MathMax(InpSLSwingLookback, 30);
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
void MeasureOptimalTPRatios(bool isBuy, int barIndex, int totalBars,
                             double &tp1Ratio, double &tp2Ratio, double &tp3Ratio)
{
   tp1Ratio = InpTPRatio;
   tp2Ratio = InpTPRatio * InpTP2Multiplier;
   tp3Ratio = InpTPRatio * InpTP3Multiplier;

   int maxFwd = GetMaxForwardBarsForTimeframe();
   int tpScanBars = GetTPMeasurementBars();

   double moveRatios[];
   int moveCount = 0;
   int timeBasedMax = 1440 / MathMax(_Period, 1);

   //--- Phase 1: Actual signals
   for(int s = 0; s < g_signalCount; s++)
   {
      if(g_signals[s].isBuySignal != isBuy) continue;
      
      timeBasedMax = MathMax(timeBasedMax, maxFwd);
      if(g_signals[s].barIndex + timeBasedMax >= Bars) continue;

      double sigEntry = g_signals[s].entryPrice;
      double sigATR   = g_signals[s].atrValue;
      double sigSL    = g_signals[s].stopLoss;
      if(sigATR <= 0) continue;

      double maxFav = 0;
      for(int b = g_signals[s].barIndex + 1;
         b < g_signals[s].barIndex + timeBasedMax && b < Bars; b++)
      {
         int bs = Bars - 1 - b;
         if(bs < 0) break;
         double bH = iHigh(NULL, 0, bs);
         double bL = iLow(NULL, 0, bs);
         double fav = isBuy ? (bH - sigEntry) : (sigEntry - bL);
         if(fav > maxFav) maxFav = fav;
         if(isBuy && bL <= sigSL) break;
         if(!isBuy && bH >= sigSL) break;
      }

      if(maxFav > 0)
      {
         moveCount++;
         // [PERF-FIX P2-4] Reserve 64 slots to avoid O(n) realloc per signal
         ArrayResize(moveRatios, moveCount, 64);
         moveRatios[moveCount - 1] = maxFav / sigATR;
      }
   }

   //--- Phase 2: Deep history (all available bars per TF)
   int deepStart = MathMax(InpRSIPeriod + 10, totalBars - tpScanBars);
   if(deepStart < 0) deepStart = 0;
   int deepEnd = totalBars - maxFwd - 10;

   for(int i = deepStart; i < deepEnd && moveCount < 500; i++)
   {
      int bs = totalBars - 1 - i;
      if(bs < 0) continue;

      double rsi = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs);
      double atr = iATR(NULL, 0, InpATRPeriod, bs);
      if(rsi == 0 || atr == 0) continue;

      bool rel = false;
      if(isBuy && rsi < 45 && rsi > 15) rel = true;
      if(!isBuy && rsi > 55 && rsi < 85) rel = true;
      if(!rel) continue;

      double rsiPrev = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs + 1);
      if(rsiPrev == 0) continue;
      if(isBuy && rsi <= rsiPrev) continue;
      if(!isBuy && rsi >= rsiPrev) continue;

      double entryP = iClose(NULL, 0, bs);
      double slDist = atr * InpSLRatio;
      double maxFav = 0;

      for(int b = i + 1; b < i + timeBasedMax && b < deepEnd; b++)
      {
         int fbs = totalBars - 1 - b;
         if(fbs < 0) break;
         double bH = iHigh(NULL, 0, fbs);
         double bL = iLow(NULL, 0, fbs);
         double fav = isBuy ? (bH - entryP) : (entryP - bL);
         if(fav > maxFav) maxFav = fav;
         if(isBuy && (entryP - bL) > slDist) break;
         if(!isBuy && (bH - entryP) > slDist) break;
      }

      if(maxFav > 0)
      {
         moveCount++;
         // [PERF-FIX P2-4] Reserve 64 slots to avoid O(n) realloc per deep-history bar
         ArrayResize(moveRatios, moveCount, 64);
         moveRatios[moveCount - 1] = maxFav / atr;
      }
   }

   if(moveCount < 30) return;

   // [PERF-FIX P3] Replace O(n^2) partial selection sort with O(n log n) ArraySort.
   // The old code ran nested loops up to target index for 3 percentiles.
   ArraySort(moveRatios);
   int targets[3];
   targets[0] = MathMax(0, MathMin((int)(moveCount * 0.50), moveCount - 1));
   targets[1] = MathMax(0, MathMin((int)(moveCount * 0.75), moveCount - 1));
   targets[2] = MathMax(0, MathMin((int)(moveCount * 0.90), moveCount - 1));
   double results[3] = {0, 0, 0};
   for(int t = 0; t < 3; t++)
      results[t] = moveRatios[targets[t]];

   tp1Ratio = results[0];
   tp2Ratio = results[1];
   tp3Ratio = results[2];

   tp1Ratio = MathMax(tp1Ratio, InpSLRatio);
   if(tp2Ratio <= tp1Ratio) tp2Ratio = tp1Ratio * 1.5;
   if(tp3Ratio <= tp2Ratio) tp3Ratio = tp2Ratio * 1.3;
}


//+------------------------------------------------------------------+
//|        MAIN ENTRY POINT - Routes to selected method                |
//+------------------------------------------------------------------+
void CalculateSLTP(bool isBuy, int barNS, double entry,
                   const double &hi[], const double &lo[], int total,
                   double &outSL, double &outTP1, double &outTP2, double &outTP3,
                   double &outATR, int caseNum = 0)
{
   // Measure optimal TP ratios from actual market data
   double optTP1, optTP2, optTP3;
   MeasureOptimalTPRatios(isBuy, barNS, total, optTP1, optTP2, optTP3);

   // Calculate SL/TP using selected method
   switch(InpSLTPMethod)
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

   // Apply measured TP if significantly different from method TP
   // Use CLOSER TP (more achievable)
   // Ngưỡng tương đối 15% thay vì tuyệt đối
   if(MathAbs(optTP1 - InpTPRatio) / MathMax(InpTPRatio, 0.1) > 0.15)
   {
      double mTP1 = entry + (isBuy ? 1 : -1) * outATR * optTP1;
      double mTP2 = entry + (isBuy ? 1 : -1) * outATR * optTP2;
      double mTP3 = entry + (isBuy ? 1 : -1) * outATR * optTP3;

      if(isBuy)
      {
         outTP1 = mTP1;
         outTP2 = mTP2;
         outTP3 = mTP3;
         if(outTP2 < outTP1) outTP2 = outTP1 + outATR * 0.5;
         if(outTP3 < outTP2) outTP3 = outTP2 + outATR * 0.5;
      }
      else
      {
         outTP1 = mTP1;
         outTP2 = mTP2;
         outTP3 = mTP3;
         if(outTP2 > outTP1) outTP2 = outTP1 - outATR * 0.5;
         if(outTP3 > outTP2) outTP3 = outTP2 - outATR * 0.5;
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

   int maxZones = MathMax(2, MathMin(5, InpEntryZoneCount));
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
                                                 InpPriceDistLookback, atr);

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
                             hi, lo, InpPriceDistLookback,
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
   double totalRisk = accountBalance * InpTotalRiskPercent / 100.0;

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

      if(z - 1 < ArraySize(pullbackProbs) && pullbackProbs[z - 1] > 0)
         g_entryZones[z].probReach = pullbackProbs[z - 1];
      else
         g_entryZones[z].probReach = MeasureZoneReachProb(
            isBuy, marketEntry, g_entryZones[z].price, moveHeight, maxFwd);
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