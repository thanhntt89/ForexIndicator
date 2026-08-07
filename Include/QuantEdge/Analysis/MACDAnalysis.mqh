//+------------------------------------------------------------------+
//|                                           MACDAnalysis.mqh        |
//|                    QuantEdge - MACD Confirmation Filter          |
//|                                                                    |
//| NOT a new signal source — a confidence modifier only.             |
//| Detects when RSI signals a reversal (OB/OS) but MACD histogram    |
//| shows the underlying trend is still accelerating (false reversal). |
//+------------------------------------------------------------------+
#ifndef QE_MACDANALYSIS_MQH
#define QE_MACDANALYSIS_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| Get MACD histogram value (main - signal) at given bar shift        |
//| Per-bar cached.                                                    |
//+------------------------------------------------------------------+
double GetMACDHistogram(int barShift)
{
   static double   s_macdHist = 0;
   static int      s_macdCachedShift = -1;
   static datetime s_macdCachedBar = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(barShift == s_macdCachedShift && curBar == s_macdCachedBar)
      return(s_macdHist);
   s_macdCachedShift = barShift;
   s_macdCachedBar = curBar;

   #ifdef __MQL5__
   int handle = iMACD(NULL, PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) { s_macdHist = 0; return(0); }
   double mainBuf[], signalBuf[];
   if(CopyBuffer(handle, 0, barShift, 1, mainBuf) > 0 &&
      CopyBuffer(handle, 1, barShift, 1, signalBuf) > 0)
      s_macdHist = mainBuf[0] - signalBuf[0];
   else
      s_macdHist = 0;
   #else
   double macdMain   = iMACD(NULL, 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, barShift);
   double macdSignal = iMACD(NULL, 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, barShift);
   s_macdHist = macdMain - macdSignal;
   #endif

   return(s_macdHist);
}

//+------------------------------------------------------------------+
//| Get MACD histogram slope (current - previous bar histogram)        |
//| Positive = histogram expanding up, negative = expanding down       |
//+------------------------------------------------------------------+
double GetMACDHistogramSlope(int barShift)
{
   return(GetMACDHistogram(barShift) - GetMACDHistogram(barShift + 1));
}

//+------------------------------------------------------------------+
//| Get confidence modifier for ProbabilityEngine Step 5.5             |
//|                                                                    |
//| If RSI signals a reversal (isBuySignal) but MACD histogram is      |
//| still trending in the OPPOSITE direction of the reversal (i.e.     |
//| momentum has not actually turned) → confidence penalty ×0.90.      |
//| Otherwise → no modifier (×1.0).                                    |
//+------------------------------------------------------------------+
double GetMACDConfidenceModifier(bool isBuySignal, int barShift)
{
   if(!InpUseMACDFilter) return(1.0);

   double hist  = GetMACDHistogram(barShift);
   double slope = GetMACDHistogramSlope(barShift);

   // Buy reversal signal but MACD histogram still falling (bears still in control)
   if(isBuySignal && hist < 0 && slope < 0)
      return(0.90);

   // Sell reversal signal but MACD histogram still rising (bulls still in control)
   if(!isBuySignal && hist > 0 && slope > 0)
      return(0.90);

   return(1.0);
}

//+------------------------------------------------------------------+
//| Panel display text                                                  |
//+------------------------------------------------------------------+
string GetMACDDisplayText(int barShift)
{
   if(!InpUseMACDFilter) return("");

   double hist = GetMACDHistogram(barShift);
   string dir = (hist >= 0) ? "Bullish" : "Bearish";

   return("MACD Hist: " + DoubleToString(hist, 5) + " [" + dir + "]");
}

//+------------------------------------------------------------------+
//| Panel display color                                                 |
//+------------------------------------------------------------------+
color GetMACDDisplayColor(int barShift)
{
   double hist = GetMACDHistogram(barShift);
   if(hist > 0) return(clrLime);
   if(hist < 0) return(clrRed);
   return(clrGray);
}

//+------------------------------------------------------------------+
//| Refresh MACD data (per-bar, called from main tick loop)            |
//+------------------------------------------------------------------+
void RefreshMACDData()
{
   if(!InpUseMACDFilter) return;
   GetMACDHistogram(1);
}

#endif
