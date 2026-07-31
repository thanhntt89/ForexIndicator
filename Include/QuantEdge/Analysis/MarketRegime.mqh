//+------------------------------------------------------------------+
//|                                            MarketRegime.mqh        |
//|                         QuantEdge - Market Regime Detection      |
//+------------------------------------------------------------------+
#ifndef QE_MARKETREGIME_MQH
#define QE_MARKETREGIME_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| Detect market regime: 1=uptrend, -1=downtrend, 0=ranging           |
//+------------------------------------------------------------------+
int DetectMarketRegime(int barIndex, const double &orange[], const double &bbUp[], const double &bbLo[])
{
   if(!InpUseRegimeFilter) return(0);
   if(barIndex < 20) return(0);
   if(orange[barIndex] == EMPTY_VALUE || orange[barIndex-10] == EMPTY_VALUE) return(0);

   double orangeSlope = orange[barIndex] - orange[barIndex-10];
   double bbWidth = 0;
   if(bbUp[barIndex] != EMPTY_VALUE && bbLo[barIndex] != EMPTY_VALUE)
      bbWidth = bbUp[barIndex] - bbLo[barIndex];

   double avgBBWidth = 0;
   int cnt = 0;
   for(int j = 0; j < 20; j++)
   {
      int idx = barIndex - j;
      if(idx < 0) break;
      if(bbUp[idx] != EMPTY_VALUE && bbLo[idx] != EMPTY_VALUE)
      {
         avgBBWidth += bbUp[idx] - bbLo[idx];
         cnt++;
      }
   }
   if(cnt > 0) avgBBWidth /= cnt;

   if(MathAbs(orangeSlope) > 5.0 && bbWidth >= avgBBWidth * 0.8)
      return(orangeSlope > 0 ? 1 : -1);

   return(0);
}

//+------------------------------------------------------------------+
//| Adaptive angle threshold based on RSI volatility                   |
//+------------------------------------------------------------------+
// [PERF-FIX P2-5] Cache per barIndex — called from both CalculateSignalScore()
// and CalculateAngleStrength(), so 20-bar variance loop ran twice per signal bar.
double GetAdaptiveAngleThreshold(int barIndex, const double &green[])
{
   static int    s_aatGen     = -1;
   static int    s_aatLastBar = -1;
   static double s_aatResult  = 0;
   if(s_aatGen != g_tfGeneration) { s_aatGen = g_tfGeneration; s_aatLastBar = -1; }
   if(barIndex == s_aatLastBar) return(s_aatResult);
   s_aatLastBar = barIndex;

   if(barIndex < 20) { s_aatResult = InpAngleThreshold; return(s_aatResult); }
   double sum = 0, sumSq = 0;
   int count = 0;
   for(int j = 0; j < 20; j++)
   {
      int idx = barIndex - j;
      if(idx < 1 || green[idx] == EMPTY_VALUE || green[idx-1] == EMPTY_VALUE) continue;
      double delta = green[idx] - green[idx-1];
      sum += delta; sumSq += delta * delta; count++;
   }
   if(count < 10) { s_aatResult = InpAngleThreshold; return(s_aatResult); }
   double variance = (sumSq / count) - ((sum / count) * (sum / count));
   double stddev = MathSqrt(MathMax(variance, 0));
   s_aatResult = MathMax(stddev * 1.5, 2.0);
   return(s_aatResult);
}

//+------------------------------------------------------------------+
//| Angle Z-score of Green at crossover bar                           |
//| Formula: |Green[i] - Green[i-2]| / adaptiveThresh                |
//| Z > 1.5 = strong angle (12h-2h clock equivalent)                 |
//| Z 1.0-1.5 = moderate (2h-3h)                                     |
//| Z < 0.5  = weak/sideway (3h-6h) → low probability                |
//| Returns 0.0 if insufficient data                                  |
//+------------------------------------------------------------------+
double CalculateAngleStrength(int barIndex, const double &green[])
{
   if(barIndex < 3) return(0.0);
   if(green[barIndex]   == EMPTY_VALUE) return(0.0);
   if(green[barIndex-2] == EMPTY_VALUE) return(0.0);

   // Momentum over 2 bars — more stable than 1 bar, less lag than 3 bars
   double greenDelta2 = MathAbs(green[barIndex] - green[barIndex-2]);

   // Adaptive threshold (same denominator as GetAdaptiveAngleThreshold)
   double adaptiveThresh = GetAdaptiveAngleThreshold(barIndex, green);
   if(adaptiveThresh <= 0.0) return(0.0);

   // Z-score: how many "standard deviations" above the recent average crossover
   double zScore = greenDelta2 / adaptiveThresh;
   return(MathMin(zScore, 5.0)); // Cap at 5.0 to prevent outlier distortion
}

#endif