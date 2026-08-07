//+------------------------------------------------------------------+
//|                                            ADXAnalysis.mqh        |
//|                         QuantEdge - ADX Trend Strength Filter    |
//|                                                                    |
//| ADX (Average Directional Index) measures trend STRENGTH            |
//| regardless of direction. ADX < 20 = sideway/noise.                 |
//| Wilder (1978) "New Concepts in Technical Trading Systems"          |
//+------------------------------------------------------------------+
#ifndef QE_ADXANALYSIS_MQH
#define QE_ADXANALYSIS_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| Get ADX value at given bar shift                                   |
//| Uses per-bar cache to avoid redundant iADX calls                   |
//+------------------------------------------------------------------+
double GetADXValue(int barShift)
{
   static double   s_adxValue = 0;
   static int      s_adxCachedShift = -1;
   static datetime s_adxCachedBar = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(barShift == s_adxCachedShift && curBar == s_adxCachedBar)
      return(s_adxValue);
   s_adxCachedShift = barShift;
   s_adxCachedBar = curBar;

   #ifdef __MQL5__
   int handle = iADX(NULL, PERIOD_CURRENT, InpADXPeriod);
   if(handle == INVALID_HANDLE) { s_adxValue = 0; return(0); }
   double buf[];
   if(CopyBuffer(handle, 0, barShift, 1, buf) > 0)
      s_adxValue = buf[0];
   else
      s_adxValue = 0;
   #else
   s_adxValue = iADX(NULL, 0, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, barShift);
   #endif

   return(s_adxValue);
}

//+------------------------------------------------------------------+
//| Get R-Squared (Coefficient of Determination) of linear regression |
//| fit over price. Measures trend LINEARITY (not strength).          |
//| Returns: 0.0 (random walk/chop) to 1.0 (perfect straight line)    |
//| Per-bar cached.                                                    |
//+------------------------------------------------------------------+
double GetRSquared(int barShift, int period = 14)
{
   static double   s_r2Value = 0;
   static int      s_r2CachedShift = -1;
   static datetime s_r2CachedBar = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(barShift == s_r2CachedShift && curBar == s_r2CachedBar)
      return(s_r2Value);
   s_r2CachedShift = barShift;
   s_r2CachedBar = curBar;

   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;

   for(int i = 1; i <= period; i++)
   {
      double y = iClose(NULL, 0, barShift + i);
      double x = (double)i;

      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
      sumY2 += y * y;
   }

   double n = (double)period;
   double denominator = (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY);

   if(denominator == 0.0) { s_r2Value = 0.0; return(0.0); }

   double numerator = (n * sumXY - sumX * sumY);
   double r2 = (numerator * numerator) / denominator;

   s_r2Value = MathMax(0.0, MathMin(r2, 1.0));
   return(s_r2Value);
}

//+------------------------------------------------------------------+
//| Get Kaufman Efficiency Ratio: net directional movement over       |
//| total path length. Measures trend SMOOTHNESS (not strength).      |
//| Returns: 0.0 (pure noise) to 1.0 (perfectly efficient/smooth)     |
//| Per-bar cached.                                                    |
//+------------------------------------------------------------------+
double GetEfficiencyRatio(int barShift, int period = 20)
{
   static double   s_erValue = 0;
   static int      s_erCachedShift = -1;
   static datetime s_erCachedBar = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(barShift == s_erCachedShift && curBar == s_erCachedBar)
      return(s_erValue);
   s_erCachedShift = barShift;
   s_erCachedBar = curBar;

   double change = MathAbs(iClose(NULL, 0, barShift + 1) - iClose(NULL, 0, barShift + period));

   double volatility = 0;
   for(int i = 1; i < period; i++)
      volatility += MathAbs(iClose(NULL, 0, barShift + i) - iClose(NULL, 0, barShift + i + 1));

   if(volatility <= 0.000001) { s_erValue = 0.0; return(0.0); }

   s_erValue = change / volatility;
   return(s_erValue);
}

//+------------------------------------------------------------------+
//| Detect fake trend (whipsaw): ADX high but price structure is      |
//| chop, not a real linear/efficient trend.                          |
//| Ported from EA project's M01_ClassifyRegimeV2 chop-filter logic.  |
//| Override: forceful momentum (ADX>25 rising fast) bypasses chop.  |
//+------------------------------------------------------------------+
bool IsFakeTrend(int barShift)
{
   double adx = GetADXValue(barShift);
   double r2  = GetRSquared(barShift);
   double er  = GetEfficiencyRatio(barShift);

   double adxSlope = GetADXValue(barShift) - GetADXValue(barShift + 1);
   bool isForceful = (adx > 25.0 && adxSlope > 0.03);

   if(adx >= 22.0 && r2 < 0.35 && er < 0.35 && !isForceful)
      return(true);

   return(false);
}

//+------------------------------------------------------------------+
//| Get ADX-based score for SignalEngine (0-100)                       |
//| Returns 50.0 (neutral) when ADX filter is off                     |
//+------------------------------------------------------------------+
double GetADXScore(int barShift)
{
   if(!InpUseADXFilter) return(50.0);

   double adx = GetADXValue(barShift);
   if(adx <= 0) return(50.0);

   if(IsFakeTrend(barShift)) return(30.0);   // High ADX but chop/whipsaw = not a real trend

   if(adx < 15)      return(10.0);   // Very weak trend = poor signal environment
   if(adx < 20)      return(30.0);   // Below threshold = likely sideway
   if(adx < 25)      return(50.0);   // Borderline
   if(adx < 35)      return(70.0);   // Good trend
   if(adx < 50)      return(85.0);   // Strong trend
   return(95.0);                      // Very strong trend
}

//+------------------------------------------------------------------+
//| Get ADX edge adjustment for ProbabilityEngine Step 3               |
//| Max ±2% edge. Case-specific damping:                               |
//| Case 1-3 (OB/OS, divergence): 0.4x (work in sideway)             |
//| Case 7-9 (sideway-prone): 1.0x (need ADX most)                    |
//| Others: 0.7x (moderate)                                            |
//+------------------------------------------------------------------+
double GetADXEdgeAdjustment(int caseNum, int barShift)
{
   if(!InpUseADXFilter) return(0);

   double adx = GetADXValue(barShift);
   if(adx <= 0) return(0);

   if(IsFakeTrend(barShift)) return(0);   // High ADX but chop/whipsaw = neutral edge

   // Normalize ADX to edge: ADX 20 = 0 (neutral), ADX 40+ = +0.02, ADX 10 = -0.02
   double norm = (adx - 20.0) / 20.0;
   norm = MathMax(-1.0, MathMin(1.0, norm));
   double rawEdge = norm * 0.02;

   // Case-specific damping
   double caseDamp;
   switch(caseNum)
   {
      case 1: case 2: case 3:
         caseDamp = 0.4;   // OB/OS + divergence work in sideway
         break;
      case 7: case 8: case 9:
         caseDamp = 1.0;   // Sideway-prone cases need full ADX filter
         break;
      default:
         caseDamp = 0.7;
         break;
   }

   return(rawEdge * caseDamp);
}

//+------------------------------------------------------------------+
//| Check if ADX passes gate threshold                                 |
//| For EA Gate 8                                                       |
//+------------------------------------------------------------------+
bool IsADXGatePassed(int barShift)
{
   if(!InpUseADXFilter) return(true);
   double adx = GetADXValue(barShift);
   if(adx < InpMinADXValue) return(false);
   if(IsFakeTrend(barShift)) return(false);   // High ADX but chop/whipsaw = fail gate
   return(true);
}

//+------------------------------------------------------------------+
//| Panel display text                                                  |
//+------------------------------------------------------------------+
string GetADXDisplayText(int barShift)
{
   if(!InpUseADXFilter) return("");

   double adx = GetADXValue(barShift);
   string strength;
   if(adx < 15)      strength = "NO TREND";
   else if(adx < 20) strength = "Weak";
   else if(adx < 25) strength = "Emerging";
   else if(adx < 35) strength = "Trending";
   else if(adx < 50) strength = "Strong";
   else               strength = "EXTREME";

   return("ADX: " + DoubleToString(adx, 1) + " [" + strength + "]");
}

//+------------------------------------------------------------------+
//| Panel display color                                                 |
//+------------------------------------------------------------------+
color GetADXDisplayColor(int barShift)
{
   double adx = GetADXValue(barShift);
   if(adx >= 25) return(clrLime);     // Good trend
   if(adx >= 20) return(clrYellow);   // Borderline
   return(clrRed);                     // Sideway
}

//+------------------------------------------------------------------+
//| Refresh ADX data (per-bar, called from main tick loop)             |
//+------------------------------------------------------------------+
void RefreshADXData()
{
   if(!InpUseADXFilter) return;
   GetADXValue(1);
}

//+------------------------------------------------------------------+
//| Publish gate state via GlobalVariable so the EA (separate program |
//| instance) can read it without duplicating ADX/R2/ER logic.        |
//+------------------------------------------------------------------+
void PublishADXGateState()
{
   if(!InpUseADXFilter) return;
   GlobalVariableSet("QE_ADXGatePassed_" + Symbol(), IsADXGatePassed(1) ? 1.0 : 0.0);
}

#endif
