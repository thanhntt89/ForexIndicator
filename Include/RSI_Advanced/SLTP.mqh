#ifndef RSI_ADV_SLTP_MQH
#define RSI_ADV_SLTP_MQH

#include "Config.mqh"
#include "Normalize.mqh"

double GetATRValue(int barShift)
{ return(iATR(NULL, 0, InpATRPeriod, barShift)); }

//+------------------------------------------------------------------+
//| Find swing-based SL with ATR buffer                                |
//| Al Brooks (2012): "Place stops beyond structure + buffer"          |
//| Buffer prevents stop hunting at exact swing level                   |
//+------------------------------------------------------------------+
double FindSwingBasedSL(bool isBuy, int fromBar,
                        const double &hi[], const double &lo[], int total)
{
   double sl = 0;
   int lb = GetNormalizedSLLookback();
   int start = MathMax(fromBar - lb, 0);
   
   // Spread buffer (Normalize.mqh: accounts for broker spread)
   double spreadBuf = GetNormalizedSpreadBuffer();
   
   // Structure buffer (Brooks 2012): ATR × 0.1 beyond swing level
   // Prevents stop hunting at exact structure level
   double atr = iATR(NULL, 0, InpATRPeriod, total - 1 - fromBar);
   double structureBuffer = atr * 0.1;
   
   double totalBuffer = spreadBuf + structureBuffer;

   if(isBuy)
   {
      sl = lo[fromBar];
      for(int j = fromBar; j >= start; j--)
         if(lo[j] < sl) sl = lo[j];
      sl -= totalBuffer;
   }
   else
   {
      sl = hi[fromBar];
      for(int j = fromBar; j >= start; j--)
         if(hi[j] > sl) sl = hi[j];
      sl += totalBuffer;
   }
   return(sl);
}

//+------------------------------------------------------------------+
//| Calculate SL/TP                                                    |
//| SL: Wilder (1978) ATR + Brooks (2012) Structure                    |
//| TP: Van Tharp (1998) R-multiple method                             |
//| Minimum SL: accounts for broker stop level                         |
//+------------------------------------------------------------------+
void CalculateSLTP(bool isBuy, int barNS, double entry,
                   const double &hi[], const double &lo[], int total,
                   double &outSL, double &outTP1, double &outTP2, double &outTP3,
                   double &outATR)
{
   int bs = total - 1 - barNS;
   outATR = GetATRValue(bs);
   
   // Wilder (1978): ATR-based SL distance
   // Van Tharp (1998): 1.5-2.0 × ATR for short-term
   double atrSL = outATR * InpSLRatio;
   
   // Brooks (2012): Structure-based SL with buffer
   double swSL = FindSwingBasedSL(isBuy, barNS, hi, lo, total);
   
   // Van Tharp (1998): TP as R-multiples
   double tp1D = outATR * InpTPRatio;
   double tp2D = outATR * InpTPRatio * InpTP2Multiplier;
   double tp3D = outATR * InpTPRatio * InpTP3Multiplier;
   
   // Minimum SL (accounts for broker restrictions)
   double minSL = GetMinSLDistance();

   if(isBuy)
   {
      // SL = further from entry (more protection)
      outSL = MathMin(swSL, entry - atrSL);
      if(entry - outSL < minSL) outSL = entry - minSL;
      outTP1 = entry + tp1D;
      outTP2 = entry + tp2D;
      outTP3 = entry + tp3D;
   }
   else
   {
      outSL = MathMax(swSL, entry + atrSL);
      if(outSL - entry < minSL) outSL = entry + minSL;
      outTP1 = entry - tp1D;
      outTP2 = entry - tp2D;
      outTP3 = entry - tp3D;
   }
}

#endif