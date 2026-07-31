//+------------------------------------------------------------------+
//|                                       IntermarketAnalysis.mqh      |
//|                         QuantEdge - Intermarket Correlation      |
//|                                                                    |
//| Theory: Murphy (1991) "Intermarket Technical Analysis"             |
//| Gold inverse correlation with USD: -0.85                           |
//| EURUSD proxy for inverse DXY: correlation +0.80 with Gold          |
//+------------------------------------------------------------------+
#ifndef QE_INTERMARKET_MQH
#define QE_INTERMARKET_MQH

#include "../Core/Config.mqh"
#include "../Core/Structs.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| Detect which intermarket symbol is available on broker             |
//| Try DXY variants first, fallback to EURUSD                        |
//+------------------------------------------------------------------+
void DetectIntermarketSymbol()
{
   g_intermarket.isAvailable = false;
   g_intermarket.sourceSymbol = "";
   g_intermarket.dxyPrice = 0;
   g_intermarket.dxyTrend = 0;
   g_intermarket.correlationScore = 0;

   if(!InpUseIntermarket) return;

   // Try DXY variants (direct USD index)
   string dxySymbols[] = {"DXYm", "USDX", "DXY", "DX", "USDIndex",
                           "DXY.","USDX.","DXYc","USDXm"};

   for(int i = 0; i < ArraySize(dxySymbols); i++)
   {
      double price = iClose(dxySymbols[i], Period(), 0);
      if(price > 0)
      {
         g_intermarket.isAvailable = true;
         g_intermarket.sourceSymbol = dxySymbols[i];
         return;
      }
   }

   // Fallback: EURUSD as inverse DXY proxy
   string eurSymbols[] = {"EURUSD", "EURUSDm", "EURUSDc", "EURUSD.",
                           "EURUSDb", "EURUSDpro"};

   for(int i = 0; i < ArraySize(eurSymbols); i++)
   {
      double price = iClose(eurSymbols[i], Period(), 0);
      if(price > 0)
      {
         g_intermarket.isAvailable = true;
         g_intermarket.sourceSymbol = eurSymbols[i];
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if source symbol is EURUSD (inverse proxy)                   |
//+------------------------------------------------------------------+
bool IsEURUSDProxy()
{
   if(StringLen(g_intermarket.sourceSymbol) < 3) return(false);
   string sym = g_intermarket.sourceSymbol;
   StringToUpper(sym);
   return(StringFind(sym, "EUR") >= 0);
}

//+------------------------------------------------------------------+
//| Calculate intermarket trend via SMA slope                          |
//| Returns: positive = USD strengthening, negative = USD weakening    |
//| For EURUSD proxy: inverted (EUR up = USD down)                     |
//+------------------------------------------------------------------+
void CalculateIntermarketTrend()
{
   if(!g_intermarket.isAvailable) return;

   string sym = g_intermarket.sourceSymbol;
   int period = InpIntermarketPeriod;

   // Get current and previous SMA values
   double sma0 = 0, smaPrev = 0;

   for(int i = 0; i < period; i++)
   {
      double price = iClose(sym, Period(), i);
      if(price <= 0) { g_intermarket.dxyTrend = 0; return; }
      sma0 += price;
   }
   sma0 /= period;

   for(int i = 1; i <= period; i++)
   {
      double price = iClose(sym, Period(), i);
      if(price <= 0) { g_intermarket.dxyTrend = 0; return; }
      smaPrev += price;
   }
   smaPrev /= period;

   // Current price
   g_intermarket.dxyPrice = iClose(sym, Period(), 0);

   // SMA slope = direction of USD
   double slope = sma0 - smaPrev;

   // Normalize slope to -1.0 to +1.0 range
   // Use ATR of intermarket symbol as scale
   double interATR = iATR(sym, Period(), 14, 0);
   if(interATR > 0)
      g_intermarket.dxyTrend = MathMax(-1.0, MathMin(1.0, slope / interATR));
   else
      g_intermarket.dxyTrend = 0;

   // If EURUSD proxy: INVERT (EUR up = USD down)
   if(IsEURUSDProxy())
      g_intermarket.dxyTrend = -g_intermarket.dxyTrend;
}

//+------------------------------------------------------------------+
//| Get intermarket alignment score with Gold signal                   |
//|                                                                    |
//| Gold INVERSE correlation with USD:                                 |
//|   BUY Gold + USD weakening (dxyTrend < 0) → ALIGNED (+)          |
//|   BUY Gold + USD strengthening (dxyTrend > 0) → AGAINST (-)      |
//|   SELL Gold + USD strengthening → ALIGNED (+)                      |
//|   SELL Gold + USD weakening → AGAINST (-)                          |
//|                                                                    |
//| Returns: -1.0 to +1.0                                             |
//|   +1.0 = perfectly aligned (strong confirmation)                   |
//|   -1.0 = perfectly against (counter-signal)                        |
//|    0.0 = neutral (no intermarket edge)                             |
//+------------------------------------------------------------------+
double GetIntermarketScore(bool isBuyGold)
{
   if(!g_intermarket.isAvailable) return(0);

   // Gold inverse with USD:
   // BUY Gold benefits from USD FALLING (dxyTrend negative)
   // SELL Gold benefits from USD RISING (dxyTrend positive)

   if(isBuyGold)
      g_intermarket.correlationScore = -g_intermarket.dxyTrend;  // Inverse
   else
      g_intermarket.correlationScore = g_intermarket.dxyTrend;   // Direct

   return(g_intermarket.correlationScore);
}

//+------------------------------------------------------------------+
//| Get intermarket edge adjustment for probability                    |
//| Conservative: max ±2% edge adjustment                              |
//|                                                                    |
//| Based on: correlation -0.85 between Gold and USD                   |
//| Strong alignment adds ~2% to directional edge                      |
//| Strong divergence reduces ~2% from edge                            |
//+------------------------------------------------------------------+
double GetIntermarketEdgeAdjustment(bool isBuyGold)
{
   if(!g_intermarket.isAvailable) return(0);

   double score = GetIntermarketScore(isBuyGold);

   // Max ±2% edge adjustment (conservative)
   // Score -1 to +1 → adjustment -0.02 to +0.02
   return(score * 0.02);
}

//+------------------------------------------------------------------+
//| Get intermarket display text for panel                             |
//+------------------------------------------------------------------+
string GetIntermarketDisplayText()
{
   if(!g_intermarket.isAvailable)
      return("Intermarket: N/A (no DXY/EURUSD)");

   string trend;

   if(g_intermarket.dxyTrend > 0.3)
      trend = "USD STRONG";
   else if(g_intermarket.dxyTrend > 0.1)
      trend = "USD rising";
   else if(g_intermarket.dxyTrend < -0.3)
      trend = "USD WEAK";
   else if(g_intermarket.dxyTrend < -0.1)
      trend = "USD falling";
   else
      trend = "USD neutral";

   return(g_intermarket.sourceSymbol + ": " + trend +
          " [" + DoubleToString(g_intermarket.dxyTrend * 100, 1) + "%]");
}

//+------------------------------------------------------------------+
//| Get intermarket display color                                      |
//+------------------------------------------------------------------+
color GetIntermarketColor(bool isBuyGold)
{
   double score = g_intermarket.correlationScore;
   if(score > 0.2) return(clrLime);     // Aligned
   if(score < -0.2) return(clrRed);     // Against
   return(clrGray);                      // Neutral
}

//+------------------------------------------------------------------+
//| Refresh all intermarket data                                       |
//| Call this once per tick or per bar from main indicator              |
//+------------------------------------------------------------------+
void RefreshIntermarketData()
{
   if(!InpUseIntermarket)
   {
      g_intermarket.isAvailable = false;
      return;
   }

   if(!g_intermarket.isAvailable || StringLen(g_intermarket.sourceSymbol) == 0)
      DetectIntermarketSymbol();

   if(g_intermarket.isAvailable)
   {
      static datetime s_imLastBarTime = 0;
      datetime curBar = iTime(NULL, 0, 0);
      if(curBar == s_imLastBarTime) return;
      s_imLastBarTime = curBar;
      CalculateIntermarketTrend();
   }
}

#endif