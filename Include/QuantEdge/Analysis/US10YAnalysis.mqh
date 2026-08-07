//+------------------------------------------------------------------+
//|                                          US10YAnalysis.mqh        |
//|                    QuantEdge - US10Y Treasury Yield Correlation  |
//|                                                                    |
//| Gold has strong inverse correlation with US real yields.           |
//| Rising yields → bearish gold (opportunity cost of holding gold).  |
//| Falling yields → bullish gold.                                     |
//+------------------------------------------------------------------+
#ifndef QE_US10YANALYSIS_MQH
#define QE_US10YANALYSIS_MQH

#include "../Core/Config.mqh"
#include "../Core/Structs.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| Detect which US10Y symbol is available on broker                  |
//+------------------------------------------------------------------+
void DetectUS10YSymbol()
{
   g_us10y.isAvailable = false;
   g_us10y.sourceSymbol = "";
   g_us10y.price = 0;
   g_us10y.trend = 0;
   g_us10y.correlationScore = 0;

   if(!InpUseUS10Y) return;

   // If user provided explicit symbol, try it first
   if(StringLen(InpUS10YSymbol) > 0)
   {
      double price = iClose(InpUS10YSymbol, Period(), 0);
      if(price > 0)
      {
         g_us10y.isAvailable = true;
         g_us10y.sourceSymbol = InpUS10YSymbol;
         return;
      }
   }

   // Try common US10Y symbol variants across brokers
   string us10ySymbols[] = {"US10Y", "US10Ym", "US10YR", "TNX", "USTBOND10Y",
                             "US10Y.", "US10Yc", "ZN", "US10YR.F", "US10Y.F"};

   for(int i = 0; i < ArraySize(us10ySymbols); i++)
   {
      double price = iClose(us10ySymbols[i], Period(), 0);
      if(price > 0)
      {
         g_us10y.isAvailable = true;
         g_us10y.sourceSymbol = us10ySymbols[i];
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate US10Y trend via SMA slope                                |
//| Returns: positive = yields rising, negative = yields falling      |
//+------------------------------------------------------------------+
void CalculateUS10YTrend()
{
   if(!g_us10y.isAvailable) return;

   string sym = g_us10y.sourceSymbol;
   int period = InpIntermarketPeriod;

   double sma0 = 0, smaPrev = 0;

   for(int i = 0; i < period; i++)
   {
      double price = iClose(sym, Period(), i);
      if(price <= 0) { g_us10y.trend = 0; return; }
      sma0 += price;
   }
   sma0 /= period;

   for(int i = 1; i <= period; i++)
   {
      double price = iClose(sym, Period(), i);
      if(price <= 0) { g_us10y.trend = 0; return; }
      smaPrev += price;
   }
   smaPrev /= period;

   g_us10y.price = iClose(sym, Period(), 0);

   double slope = sma0 - smaPrev;

   double symATR = iATR(sym, Period(), 14, 0);
   if(symATR > 0)
      g_us10y.trend = MathMax(-1.0, MathMin(1.0, slope / symATR));
   else
      g_us10y.trend = 0;
}

//+------------------------------------------------------------------+
//| Get US10Y alignment score with Gold signal                         |
//|                                                                    |
//| Gold INVERSE correlation with yields:                              |
//|   BUY Gold + yields falling (trend < 0) → ALIGNED (+)            |
//|   BUY Gold + yields rising (trend > 0) → AGAINST (-)             |
//|   SELL Gold + yields rising → ALIGNED (+)                          |
//|   SELL Gold + yields falling → AGAINST (-)                         |
//|                                                                    |
//| Returns: -1.0 to +1.0                                             |
//+------------------------------------------------------------------+
double GetUS10YScore(bool isBuyGold)
{
   if(!g_us10y.isAvailable) return(0);

   if(isBuyGold)
      g_us10y.correlationScore = -g_us10y.trend;   // Inverse
   else
      g_us10y.correlationScore = g_us10y.trend;    // Direct

   return(g_us10y.correlationScore);
}

//+------------------------------------------------------------------+
//| Get US10Y edge adjustment for probability                          |
//| Conservative: max ±2% edge adjustment                              |
//+------------------------------------------------------------------+
double GetUS10YEdgeAdjustment(bool isBuyGold)
{
   if(!g_us10y.isAvailable) return(0);

   double score = GetUS10YScore(isBuyGold);
   return(score * 0.02);
}

//+------------------------------------------------------------------+
//| Get US10Y display text for panel                                   |
//+------------------------------------------------------------------+
string GetUS10YDisplayText()
{
   if(!g_us10y.isAvailable)
      return("US10Y: N/A (symbol not found)");

   string trend;
   if(g_us10y.trend > 0.3)       trend = "Yields RISING";
   else if(g_us10y.trend > 0.1)  trend = "Yields rising";
   else if(g_us10y.trend < -0.3) trend = "Yields FALLING";
   else if(g_us10y.trend < -0.1) trend = "Yields falling";
   else                            trend = "Yields neutral";

   return(g_us10y.sourceSymbol + ": " + trend +
          " [" + DoubleToString(g_us10y.trend * 100, 1) + "%]");
}

//+------------------------------------------------------------------+
//| Get US10Y display color                                            |
//+------------------------------------------------------------------+
color GetUS10YColor(bool isBuyGold)
{
   double score = g_us10y.correlationScore;
   if(score > 0.2) return(clrLime);     // Aligned
   if(score < -0.2) return(clrRed);     // Against
   return(clrGray);                      // Neutral
}

//+------------------------------------------------------------------+
//| Refresh all US10Y data (per-bar, called from main tick loop)      |
//+------------------------------------------------------------------+
void RefreshUS10YData()
{
   if(!InpUseUS10Y)
   {
      g_us10y.isAvailable = false;
      return;
   }

   if(!g_us10y.isAvailable || StringLen(g_us10y.sourceSymbol) == 0)
      DetectUS10YSymbol();

   if(g_us10y.isAvailable)
   {
      static datetime s_u10LastBarTime = 0;
      datetime curBar = iTime(NULL, 0, 0);
      if(curBar == s_u10LastBarTime) return;
      s_u10LastBarTime = curBar;
      CalculateUS10YTrend();
   }
}

#endif
