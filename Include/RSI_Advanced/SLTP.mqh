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

   // Wilder (1978): ATR-based SL
   double atrSL = outATR * InpSLRatio;

   // Brooks (2012): Structure-based SL with buffer
   double spreadBuf = GetNormalizedSpreadBuffer();
   double structBuf = outATR * 0.1;
   double totalBuf = spreadBuf + structBuf;

   // Van Tharp (1998): R-multiple TP
   double tp1D = outATR * InpTPRatio;
   double tp2D = outATR * InpTPRatio * InpTP2Multiplier;
   double tp3D = outATR * InpTPRatio * InpTP3Multiplier;

   double minSL = GetMinSLDistance();

   if(isBuy)
   {
      // Swing SL
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
//|                                                                    |
//| SL: Beyond 0.786 retracement (deepest reasonable pullback)         |
//| TP1: 1.0 extension (100% measured move)                            |
//| TP2: 1.618 extension (Golden ratio - strongest Fib level)          |
//| TP3: 2.618 extension (extreme extension)                           |
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

   // Find swing range for Fibonacci calculation
   int fibLookback = MathMax(InpSLSwingLookback, 30);
   double swingHigh = 0, swingLow = 0;
   FindSwingRange(isBuy, barNS, hi, lo, fibLookback, swingHigh, swingLow);

   double swingRange = swingHigh - swingLow;

   // Minimum swing range = 1 ATR (prevent tiny Fib levels)
   if(swingRange < outATR)
      swingRange = outATR;

   if(isBuy)
   {
      // BUY: Swing was LOW → HIGH, entry near HIGH
      // Retracement from HIGH back down
      // SL below 0.786 retracement
      double fib786 = swingHigh - swingRange * 0.786;
      outSL = fib786 - spreadBuf;
      if(entry - outSL < minSL) outSL = entry - minSL;

      // Extensions from swing LOW projected UP from entry
      // TP1 = 1.0 extension (equal measured move)
      outTP1 = entry + swingRange * 1.0;
      // TP2 = 1.618 extension (Golden ratio)
      outTP2 = entry + swingRange * 1.618;
      // TP3 = 2.618 extension
      outTP3 = entry + swingRange * 2.618;
   }
   else
   {
      // SELL: Swing was HIGH → LOW, entry near LOW
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
//|                                                                    |
//| SL: Fibonacci structure + ATR backup                               |
//|     Use FURTHER of (Fib SL, ATR SL) for more protection           |
//|     Cap at ATR × 2.5 to prevent huge SL                           |
//|                                                                    |
//| TP: Fibonacci extension AS TARGET, ATR AS MINIMUM                  |
//|     TP = MAX(Fib extension, ATR minimum)                           |
//|     Ensures R:R never worse than ATR method                        |
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

   // ATR-based values
   double atrSLDist = outATR * InpSLRatio;
   double atrTP1 = outATR * InpTPRatio;
   double atrTP2 = outATR * InpTPRatio * InpTP2Multiplier;
   double atrTP3 = outATR * InpTPRatio * InpTP3Multiplier;

   // Fibonacci values
   int fibLookback = MathMax(InpSLSwingLookback, 30);
   double swingHigh = 0, swingLow = 0;
   FindSwingRange(isBuy, barNS, hi, lo, fibLookback, swingHigh, swingLow);
   double swingRange = MathMax(swingHigh - swingLow, outATR);

   // Max SL cap = ATR × 2.5 (prevent oversized SL)
   double maxSLDist = outATR * (InpSLRatio + 0.5);

   if(isBuy)
   {
      // SL: FURTHER of (Fib 0.786, ATR SL, Swing low) → more protection
      double fibSL = swingHigh - swingRange * 0.786 - spreadBuf;
      double atrSL = entry - atrSLDist;

      int slLookback = GetNormalizedSLLookback();
      double swingSL = FindNearestSwingLow(lo, barNS, slLookback) - totalBuf;

      // Take the FURTHEST (lowest) SL for maximum protection
      outSL = MathMin(fibSL, MathMin(atrSL, swingSL));

      // Cap SL distance
      if(entry - outSL > maxSLDist)
         outSL = entry - maxSLDist;
      if(entry - outSL < minSL)
         outSL = entry - minSL;

      // TP: MAX of (Fib extension, ATR minimum) → best target
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

      if(outSL - entry > maxSLDist)
         outSL = entry + maxSLDist;
      if(outSL - entry < minSL)
         outSL = entry + minSL;

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

#endif