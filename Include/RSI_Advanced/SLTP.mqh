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

double GetATRValue(int barShift)
{ return(iATR(NULL, 0, InpATRPeriod, barShift)); }

//+------------------------------------------------------------------+
//|        SWING FINDING FOR FIBONACCI                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Find nearest significant swing low before barIndex                 |
//+------------------------------------------------------------------+
double FindNearestSwingLow(const double &lo[], int barIndex, int lookback)
{
   double swingLow = lo[barIndex];
   int swingBar = barIndex;
   int depth = 3;
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
         break;  // Nearest swing low found
      }
   }
   return(swingLow);
}

//+------------------------------------------------------------------+
//| Find nearest significant swing high before barIndex                |
//+------------------------------------------------------------------+
double FindNearestSwingHigh(const double &hi[], int barIndex, int lookback)
{
   double swingHigh = hi[barIndex];
   int swingBar = barIndex;
   int depth = 3;
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

//+------------------------------------------------------------------+
//| Find swing range (highest high and lowest low) for Fibonacci       |
//+------------------------------------------------------------------+
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
                       double &outATR)
{
   int bs = total - 1 - barNS;
   outATR = GetATRValue(bs);

   double atrSL = outATR * InpSLRatio;
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
      double swingSL = FindNearestSwingLow(lo, barNS, slLookback) - totalBuf;
      outSL = MathMin(swingSL, entry - atrSL);
      if(entry - outSL < minSL) outSL = entry - minSL;
      outTP1 = entry + tp1D;
      outTP2 = entry + tp2D;
      outTP3 = entry + tp3D;
   }
   else
   {
      int slLookback = GetNormalizedSLLookback();
      double swingSL = FindNearestSwingHigh(hi, barNS, slLookback) + totalBuf;
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

   if(swingRange < outATR)
      swingRange = outATR;

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
                           double &outATR)
{
   int bs = total - 1 - barNS;
   outATR = GetATRValue(bs);
   double spreadBuf = GetNormalizedSpreadBuffer();
   double structBuf = outATR * 0.1;
   double totalBuf = spreadBuf + structBuf;
   double minSL = GetMinSLDistance();

   double atrSLDist = outATR * InpSLRatio;
   double atrTP1 = outATR * InpTPRatio;
   double atrTP2 = outATR * InpTPRatio * InpTP2Multiplier;
   double atrTP3 = outATR * InpTPRatio * InpTP3Multiplier;

   int fibLookback = MathMax(InpSLSwingLookback, 30);
   double swingHigh = 0, swingLow = 0;
   FindSwingRange(isBuy, barNS, hi, lo, fibLookback, swingHigh, swingLow);
   double swingRange = MathMax(swingHigh - swingLow, outATR);

   double maxSLDist = outATR * (InpSLRatio + 0.5);

   if(isBuy)
   {
      double fibSL = swingHigh - swingRange * 0.786 - spreadBuf;
      double atrSL = entry - atrSLDist;
      int slLookback = GetNormalizedSLLookback();
      double swingSL = FindNearestSwingLow(lo, barNS, slLookback) - totalBuf;

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
      double swingSL = FindNearestSwingHigh(hi, barNS, slLookback) + totalBuf;

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
//|        MAIN ENTRY POINT - Routes to selected method                |
//+------------------------------------------------------------------+
void CalculateSLTP(bool isBuy, int barNS, double entry,
                   const double &hi[], const double &lo[], int total,
                   double &outSL, double &outTP1, double &outTP2, double &outTP3,
                   double &outATR)
{
   switch(InpSLTPMethod)
   {
      case SLTP_FIBONACCI:
         CalculateSLTP_Fibonacci(isBuy, barNS, entry, hi, lo, total,
                                 outSL, outTP1, outTP2, outTP3, outATR);
         break;
      case SLTP_HYBRID:
         CalculateSLTP_Hybrid(isBuy, barNS, entry, hi, lo, total,
                              outSL, outTP1, outTP2, outTP3, outATR);
         break;
      default: // SLTP_ATR
         CalculateSLTP_ATR(isBuy, barNS, entry, hi, lo, total,
                           outSL, outTP1, outTP2, outTP3, outATR);
         break;
   }
}

//+------------------------------------------------------------------+
//|     ██  ENTRY ZONE SYSTEM  ██                                      |
//|                                                                    |
//| Theory: Price Distribution (Dalton 1993) + Liquidity Voids (ICT)   |
//| Risk: Van Tharp (1998) Fixed Fractional                            |
//| Sizing: Kelly (1956) Half-Kelly                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Price Distribution Analysis - ANTI-OVERFITTING                     |
//|                                                                    |
//| Method: Price Time at Level (proxy cho Volume Profile)             |
//| Search ranges: equal division (no hardcoded boundaries)            |
//| Default prob: linear decay (no magic numbers)                      |
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

   // TIME AT LEVEL: proportion of bar time in each zone
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

         double timeFraction = overlap / barRange;
         zoneTime[z] += timeFraction;
         totalTime += timeFraction;
      }
   }

   if(totalTime <= 0) return;

   // Normalize
   for(int z = 0; z < microZones; z++)
      zoneTime[z] /= totalTime;

   // ANTI-OVERFITTING: Equal division search ranges
   // No hardcoded {0.15,0.35,0.55,0.75} boundaries
   int maxPullbackZones = numZonesRequested - 1;
   if(maxPullbackZones > 4) maxPullbackZones = 4;

   double rangeStart = 0.10;
   double rangeEnd   = 0.90;
   double segmentSize = (rangeEnd - rangeStart) / MathMax(maxPullbackZones, 1);

   // Fibonacci fallback levels (math constants, not tuned)
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
         // Fibonacci fallback
         int fibIdx = MathMin(req, 3);
         if(isBuy)
            zonePrices[req] = entryPrice - rangeSize * fibFallback[fibIdx];
         else
            zonePrices[req] = entryPrice + rangeSize * fibFallback[fibIdx];

         // ANTI-OVERFITTING: Linear decay probability (not hardcoded array)
         double progress = (double)(req + 1) / (double)(maxPullbackZones + 1);
         zoneProbs[req] = MathMax(0.10, 0.65 * (1.0 - progress));
      }
   }
}

//+------------------------------------------------------------------+
//| Validate SL against high volume zones                              |
//| ANTI-OVERFITTING: threshold = mean + stddev (statistical)          |
//| Not hardcoded 1.5× multiplier                                     |
//+------------------------------------------------------------------+
double ValidateSLAgainstVolume(bool isBuy, double currentSL, double entryPrice,
                                const double &hi[], const double &lo[],
                                int barIndex, int lookback, double atr)
{
   // Scan range WIDER than just Entry→SL
   // Use ±2 ATR from entry to capture full volume context
   // Old: only scanned Entry→SL range (too narrow)
   double scanRange = atr * 2.0;
   double rangeHigh, rangeLow;
   
   if(isBuy)
   {
      rangeHigh = entryPrice + atr * 0.5;  // Include some above entry
      rangeLow  = currentSL - atr * 0.5;   // Include some below SL
   }
   else
   {
      rangeHigh = currentSL + atr * 0.5;
      rangeLow  = entryPrice - atr * 0.5;
   }
   
   double rangeSize = rangeHigh - rangeLow;
   if(rangeSize <= 0) return(currentSL);

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

   // Find SL zone
   int slZone = -1;
   for(int z = 0; z < microZones; z++)
   {
      double zLow  = rangeLow + z * zoneHeight;
      double zHigh = zLow + zoneHeight;
      if(currentSL >= zLow && currentSL <= zHigh)
      { slZone = z; break; }
   }

   if(slZone < 0) return(currentSL);

   // Statistical threshold
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

   // SL NOT in high volume → OK
   if(slZoneTime <= highVolThreshold) return(currentSL);

   // SL in high volume → push BEYOND the high volume cluster
   if(isBuy)
   {
      // BUY SL below entry → push further DOWN past high volume edge
      for(int z = slZone - 1; z >= 0; z--)
      {
         if(zoneTime[z] <= meanTime)
         {
            // Found low volume zone = edge of cluster
            double newSL = rangeLow + z * zoneHeight;
            newSL -= atr * 0.1;  // Small buffer beyond edge
            
            // Only move FURTHER from entry (more protection)
            if(newSL < currentSL) return(newSL);
            break;
         }
      }
      // All zones below are high volume → push to bottom of scan range
      double bottomSL = rangeLow - atr * 0.1;
      if(bottomSL < currentSL) return(bottomSL);
   }
   else
   {
      // SELL SL above entry → push further UP past high volume edge
      for(int z = slZone + 1; z < microZones; z++)
      {
         if(zoneTime[z] <= meanTime)
         {
            double newSL = rangeLow + (z + 1) * zoneHeight;
            newSL += atr * 0.1;
            
            if(newSL > currentSL) return(newSL);
            break;
         }
      }
      double topSL = rangeHigh + atr * 0.1;
      if(topSL > currentSL) return(topSL);
   }

   return(currentSL);
}

//+------------------------------------------------------------------+
//| Measure zone reach probability from historical signals             |
//+------------------------------------------------------------------+
double MeasureZoneReachProb(bool isBuy, double entryPrice, double zonePrice,
                             double moveHeight, int maxForward)
{
   if(moveHeight <= 0) return(0.5);

   double retraceLevel = MathAbs(entryPrice - zonePrice) / moveHeight;
   int reachedCount = 0;
   int totalCount = 0;

   for(int s = 0; s < g_signalCount; s++)
   {
      if(g_signals[s].isBuySignal != isBuy) continue;
      if(g_signals[s].barIndex + maxForward >= Bars) continue;

      double sigEntry = g_signals[s].entryPrice;
      double sigMove = MathAbs(sigEntry - g_signals[s].stopLoss);
      if(sigMove <= 0) continue;

      double extremePrice = sigEntry;

      for(int b = g_signals[s].barIndex + 1;
          b < g_signals[s].barIndex + maxForward && b < Bars; b++)
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

//+------------------------------------------------------------------+
//| Get zone color by index                                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| ANTI-OVERFITTING: Mathematical risk distribution                   |
//| Inverse index weighting (no arbitrary 0.40+0.10/N formula)        |
//| Zone 1 weight=N, Zone 2=N-1, ..., Zone N=1                        |
//| Total = N×(N+1)/2                                                  |
//+------------------------------------------------------------------+
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
//| MAIN: Calculate all entry zones for a signal                       |
//|                                                                    |
//| Called from RSI_AdvancedSignal.mq4 after signal detection          |
//| Populates g_entryZones[], g_validZoneCount, g_recommendedZoneCount |
//|                                                                    |
//| SL validation: If SL sits in high volume zone → push beyond       |
//| to avoid stop hunting (Dalton 1993)                                |
//+------------------------------------------------------------------+
void CalculateEntryZones(bool isBuy, int barIndex,
                          double marketEntry, double sl, double tp1,
                          double atr,
                          const double &hi[], const double &lo[],
                          int totalBars)
{
   g_validZoneCount = 0;
   g_recommendedZoneCount = 0;

   // Initialize all zones as invalid
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
   
   // ANTI-OVERFITTING: Min SL from broker data, not hardcoded ratio
   double brokerMinSL = MarketInfo(Symbol(), MODE_STOPLEVEL) * _Point;
   double spreadMinSL = MarketInfo(Symbol(), MODE_SPREAD) * _Point * 3;
   double minSLDist = MathMax(brokerMinSL, spreadMinSL);
   minSLDist = MathMax(minSLDist, atr * 0.2);  // Absolute floor

   int maxFwd = GetMaxForwardBarsForTimeframe();

   if(moveHeight <= 0) return;

   //--- Validate SL against high volume zones (prevent stop hunt)
   //--- effectiveSL used for zone calculations
   //--- Original SL in SignalData stays on chart unchanged
   double effectiveSL = ValidateSLAgainstVolume(isBuy, sl, marketEntry,
                                                 hi, lo, barIndex,
                                                 InpPriceDistLookback, atr);

   // Only accept if pushed FURTHER from entry (more protection)
   if(isBuy)
      effectiveSL = MathMin(effectiveSL, sl);   // Lower = further for BUY
   else
      effectiveSL = MathMax(effectiveSL, sl);   // Higher = further for SELL

   // Recalculate moveHeight with validated SL
   moveHeight = MathAbs(marketEntry - effectiveSL);
   if(moveHeight <= 0) return;

   //--- Get pullback zone prices from price distribution
   //--- Uses effectiveSL as range boundary
   double pullbackPrices[];
   double pullbackProbs[];
   AnalyzePriceDistribution(isBuy, barIndex, marketEntry, effectiveSL,
                             hi, lo, InpPriceDistLookback,
                             maxZones, pullbackPrices, pullbackProbs);

   //--- Adaptive zone count based on market condition
   double curATR = iATR(NULL, 0, InpATRPeriod, totalBars - 1 - barIndex);
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

   //--- Measure edge for probability calculations
   double edge = MeasureEdgeFromHistory(0, isBuy, maxFwd);

   //--- Calculate risk shares
   double shares[];
   CalculateRiskShares(adaptiveMax, shares);

   double accountBalance = AccountBalance();
   if(accountBalance <= 0) accountBalance = 1000;
   double totalRisk = accountBalance * InpTotalRiskPercent / 100.0;

   //--- Zone 1: Market entry (always valid)
   g_entryZones[0].price = marketEntry;
   g_entryZones[0].zoneName = "Market";
   g_entryZones[0].probReach = 0.95;
   g_entryZones[0].isValid = true;
   g_validZoneCount = 1;

   //--- Zones 2+: Pullback entries from price distribution
   for(int z = 1; z < adaptiveMax; z++)
   {
      if(z - 1 < ArraySize(pullbackPrices) && pullbackPrices[z - 1] > 0)
         g_entryZones[z].price = pullbackPrices[z - 1];
      else
         g_entryZones[z].price = 0;

      g_entryZones[z].zoneName = "PB-Z" + IntegerToString(z + 1);

      // Validate: zone price must be between entry and effectiveSL
      if(g_entryZones[z].price <= 0)
      { g_entryZones[z].isValid = false; continue; }

      if(isBuy)
      {
         if(g_entryZones[z].price >= marketEntry || g_entryZones[z].price <= effectiveSL)
         { g_entryZones[z].isValid = false; continue; }
      }
      else
      {
         if(g_entryZones[z].price <= marketEntry || g_entryZones[z].price >= effectiveSL)
         { g_entryZones[z].isValid = false; continue; }
      }

      g_entryZones[z].isValid = true;
      g_validZoneCount++;

      // Reach probability
      if(z - 1 < ArraySize(pullbackProbs) && pullbackProbs[z - 1] > 0)
         g_entryZones[z].probReach = pullbackProbs[z - 1];
      else
         g_entryZones[z].probReach = MeasureZoneReachProb(
            isBuy, marketEntry, g_entryZones[z].price, moveHeight, maxFwd);
   }

   //--- Calculate metrics for all valid zones
   g_recommendedZoneCount = 0;

   for(int z = 0; z < adaptiveMax; z++)
   {
      if(!g_entryZones[z].isValid) continue;

      // SL/TP distances from this zone (using effectiveSL)
      if(isBuy)
      {
         g_entryZones[z].slDistance = g_entryZones[z].price - effectiveSL;
         g_entryZones[z].tp1Distance = tp1 - g_entryZones[z].price;
      }
      else
      {
         g_entryZones[z].slDistance = effectiveSL - g_entryZones[z].price;
         g_entryZones[z].tp1Distance = g_entryZones[z].price - tp1;
      }

      // Validate minimum SL distance (skip Zone 1 - always valid)
      if(g_entryZones[z].slDistance < minSLDist && z > 0)
      {
         g_entryZones[z].isValid = false;
         g_validZoneCount--;
         continue;
      }

      // R:R ratio
      g_entryZones[z].rrRatio = (g_entryZones[z].slDistance > 0) ?
         g_entryZones[z].tp1Distance / g_entryZones[z].slDistance : 0;

      // P(TP1) from this zone using Gambler's Ruin
      g_entryZones[z].probTP1 = CalculateRealMarketProbTP(
         edge, g_entryZones[z].slDistance, g_entryZones[z].tp1Distance, atr) * 100.0;

      // Expected Value = P(reach) × [P(win) × R:R - P(loss) × 1.0]
      double winRate = g_entryZones[z].probTP1 / 100.0;
      g_entryZones[z].expectedValue = g_entryZones[z].probReach *
         (winRate * g_entryZones[z].rrRatio - (1.0 - winRate) * 1.0);

      // Recommend if EV positive OR Zone 1 (market baseline)
      g_entryZones[z].isRecommended = (g_entryZones[z].expectedValue > 0 || z == 0);
      if(g_entryZones[z].isRecommended) g_recommendedZoneCount++;

      // Risk share
      g_entryZones[z].riskShare = (z < ArraySize(shares)) ? shares[z] : 0;

      // Lot size calculation
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

   //--- Ensure minimum 2 recommended zones
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

   //--- Redistribute risk to recommended zones only
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
            if(ts > 0)
               pv = tv * (g_entryZones[z].slDistance / ts);
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