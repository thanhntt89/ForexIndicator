//+------------------------------------------------------------------+
//|                                              SignalCases.mqh       |
//|                         QuantEdge - 7 Case Detection Functions  |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_SIGNALCASES_MQH
#define RSI_ADV_SIGNALCASES_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"
#include "SwingDetection.mqh"

//+------------------------------------------------------------------+
//| Case names                                                         |
//+------------------------------------------------------------------+
string GetCaseName(int caseNum)
{
   switch(caseNum)
   {
      case 1: return("OB/OS Bounce");
      case 2: return("Regular Divergence");
      case 3: return("Hidden Divergence");
      case 4: return("Strong Trend");
      case 5: return("Orange Near Level");
      case 6: return("Trend Continuation");
      case 7: return("Sideway Breakout");
      case 8: return("Basic Crossover");
      case 9: return("Plain Cross");
   }
   return("Unknown");
}

//+------------------------------------------------------------------+
//| Case detail descriptions (2 lines each)                            |
//+------------------------------------------------------------------+
string GetCaseDetailBuy(int caseNum)
{
   switch(caseNum)
   {
      case 1: return("Green < BB Lower & < 32, cross back above 32|=> Sellers exhausted, reversal UP expected");
      case 2: return("Price: Lower Low / RSI: Higher Low (divergence)|=> Selling weakening, Green cross up Red 12-2h ~90%");
      case 3: return("Price: Higher Low / RSI: Lower Low (hidden div)|=> Uptrend still strong, Green cross up Red 12-2h");
      case 4: return("Green cross ABOVE 50 & breaks BB Upper|=> Strong UPTREND incoming, prioritize BUY ~90%");
      case 5: return("Orange near 32 (oversold) + Green cross up Red|=> Strong angle confirmed, combine higher TF ~90%");
      case 6: return("Green & Red above Orange, pullback held|=> Bounce up, trend continuation, hold/add BUY");
      case 7: return("Multiple crosses inside BB (sideway confirmed)|=> Green breaks BB Upper, breakout UP");
      case 8: return("Green crosses above Red with strong angle 12-2h|=> Core RSI Advanced rule, potential uptrend");
      case 9: return("Plain Green crosses above Red (no strong-angle gate)|=> Bare crossover Case 8 skips (weak angle), tracked with own probability");
   }
   return("");
}

string GetCaseDetailSell(int caseNum)
{
   switch(caseNum)
   {
      case 1: return("Green > BB Upper & > 68, cross back below 68|=> Buyers exhausted, reversal DOWN expected");
      case 2: return("Price: Higher High / RSI: Lower High (divergence)|=> Buying weakening, Green cross down Red 4-6h ~90%");
      case 3: return("Price: Lower High / RSI: Higher High (hidden div)|=> Downtrend still strong, Green cross down Red 4-6h");
      case 4: return("Green cross BELOW 50 & breaks BB Lower|=> Strong DOWNTREND incoming, prioritize SELL ~90%");
      case 5: return("Orange near 68 (overbought) + Green cross down Red|=> Strong angle confirmed, combine higher TF ~90%");
      case 6: return("Green & Red below Orange, pullback held|=> Bounce down, trend continuation, hold/add SELL");
      case 7: return("Multiple crosses inside BB (sideway confirmed)|=> Green breaks BB Lower, breakout DOWN");
      case 8: return("Green crosses below Red with strong angle 4-6h|=> Core RSI Advanced rule, potential downtrend");
      case 9: return("Plain Green crosses below Red (no strong-angle gate)|=> Bare crossover Case 8 skips (weak angle), tracked with own probability");
   }
   return("");
}

//+------------------------------------------------------------------+
//| CASE 1: OB/OS Bounce                                               |
//+------------------------------------------------------------------+
bool CheckCase1_Buy(int i)
{
   if(i < 2) return(false);
   if(BufferGreen[i-1] == EMPTY_VALUE || BufferBBLower[i-1] == EMPTY_VALUE) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferBBLower[i] == EMPTY_VALUE) return(false);
   return((BufferGreen[i-1] < 32.0) && (BufferGreen[i-1] < BufferBBLower[i-1]) &&
          (BufferGreen[i] >= 32.0) && (BufferGreen[i] >= BufferBBLower[i]));
}

bool CheckCase1_Sell(int i)
{
   if(i < 2) return(false);
   if(BufferGreen[i-1] == EMPTY_VALUE || BufferBBUpper[i-1] == EMPTY_VALUE) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferBBUpper[i] == EMPTY_VALUE) return(false);
   return((BufferGreen[i-1] > 68.0) && (BufferGreen[i-1] > BufferBBUpper[i-1]) &&
          (BufferGreen[i] <= 68.0) && (BufferGreen[i] <= BufferBBUpper[i]));
}

//+------------------------------------------------------------------+
//| CASE 2: Regular Divergence                                         |
//+------------------------------------------------------------------+
bool CheckCase2_Buy(int i, const double &lowPrices[])
{
   int swNew = -1, swOld = -1;
   FindTwoSwingLows(lowPrices, BufferGreen, i, InpSwingLookback, InpSwingDepth, swNew, swOld);
   if(swNew < 0 || swOld < 0) return(false);
   if(BufferGreen[swNew] == EMPTY_VALUE || BufferGreen[swOld] == EMPTY_VALUE) return(false);
   return(lowPrices[swNew] < lowPrices[swOld] && BufferGreen[swNew] > BufferGreen[swOld]);
}

bool CheckCase2_Sell(int i, const double &highPrices[])
{
   int swNew = -1, swOld = -1;
   FindTwoSwingHighs(highPrices, BufferGreen, i, InpSwingLookback, InpSwingDepth, swNew, swOld);
   if(swNew < 0 || swOld < 0) return(false);
   if(BufferGreen[swNew] == EMPTY_VALUE || BufferGreen[swOld] == EMPTY_VALUE) return(false);
   return(highPrices[swNew] > highPrices[swOld] && BufferGreen[swNew] < BufferGreen[swOld]);
}

//+------------------------------------------------------------------+
//| CASE 3: Hidden Divergence                                          |
//+------------------------------------------------------------------+
bool CheckCase3_Buy(int i, const double &lowPrices[])
{
   int swNew = -1, swOld = -1;
   FindTwoSwingLows(lowPrices, BufferGreen, i, InpSwingLookback, InpSwingDepth, swNew, swOld);
   if(swNew < 0 || swOld < 0) return(false);
   if(BufferGreen[swNew] == EMPTY_VALUE || BufferGreen[swOld] == EMPTY_VALUE) return(false);
   return(lowPrices[swNew] > lowPrices[swOld] && BufferGreen[swNew] < BufferGreen[swOld]);
}

bool CheckCase3_Sell(int i, const double &highPrices[])
{
   int swNew = -1, swOld = -1;
   FindTwoSwingHighs(highPrices, BufferGreen, i, InpSwingLookback, InpSwingDepth, swNew, swOld);
   if(swNew < 0 || swOld < 0) return(false);
   if(BufferGreen[swNew] == EMPTY_VALUE || BufferGreen[swOld] == EMPTY_VALUE) return(false);
   return(highPrices[swNew] < highPrices[swOld] && BufferGreen[swNew] > BufferGreen[swOld]);
}

//+------------------------------------------------------------------+
//| CASE 4: Strong Trend                                               |
//+------------------------------------------------------------------+
bool CheckCase4_Buy(int i)
{
   if(i < 2 || BufferGreen[i-1] == EMPTY_VALUE || BufferGreen[i] == EMPTY_VALUE || BufferBBUpper[i] == EMPTY_VALUE) return(false);
   return((BufferGreen[i-1] < 50.0) && (BufferGreen[i] >= 50.0) && (BufferGreen[i] > BufferBBUpper[i]));
}

bool CheckCase4_Sell(int i)
{
   if(i < 2 || BufferGreen[i-1] == EMPTY_VALUE || BufferGreen[i] == EMPTY_VALUE || BufferBBLower[i] == EMPTY_VALUE) return(false);
   return((BufferGreen[i-1] > 50.0) && (BufferGreen[i] <= 50.0) && (BufferGreen[i] < BufferBBLower[i]));
}

//+------------------------------------------------------------------+
//| CASE 5: Orange Near Level                                          |
//+------------------------------------------------------------------+
bool CheckCase5_Buy(int i)
{
   if(BufferOrange[i] == EMPTY_VALUE) return(false);
   return(MathAbs(BufferOrange[i] - 32.0) <= InpOrangeTolerance);
}

bool CheckCase5_Sell(int i)
{
   if(BufferOrange[i] == EMPTY_VALUE) return(false);
   return(MathAbs(BufferOrange[i] - 68.0) <= InpOrangeTolerance);
}

//+------------------------------------------------------------------+
//| CASE 6: Trend Continuation                                        |
//+------------------------------------------------------------------+
bool CheckCase6_Buy(int i)
{
   if(i < 5) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferRed[i] == EMPTY_VALUE || BufferOrange[i] == EMPTY_VALUE || BufferGreen[i-1] == EMPTY_VALUE) return(false);
   if(BufferGreen[i] <= BufferOrange[i] || BufferRed[i] <= BufferOrange[i]) return(false);

   int searchEnd = MathMax(i - 10, 0);
   for(int j = i - 1; j >= searchEnd; j--)
   {
      if(BufferGreen[j] == EMPTY_VALUE || BufferOrange[j] == EMPTY_VALUE) continue;
      double dist = BufferGreen[j] - BufferOrange[j];
      if(dist >= -1.0 && dist <= 3.0)
      {
         bool ok = true;
         for(int k = j; k >= MathMax(j - 3, 0); k--)
            if(BufferGreen[k] != EMPTY_VALUE && BufferOrange[k] != EMPTY_VALUE && BufferGreen[k] < BufferOrange[k] - 2.0) { ok = false; break; }
         if(ok && BufferGreen[i] > BufferGreen[i-1]) return(true);
      }
   }
   return(false);
}

bool CheckCase6_Sell(int i)
{
   if(i < 5) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferRed[i] == EMPTY_VALUE || BufferOrange[i] == EMPTY_VALUE || BufferGreen[i-1] == EMPTY_VALUE) return(false);
   if(BufferGreen[i] >= BufferOrange[i] || BufferRed[i] >= BufferOrange[i]) return(false);

   int searchEnd = MathMax(i - 10, 0);
   for(int j = i - 1; j >= searchEnd; j--)
   {
      if(BufferGreen[j] == EMPTY_VALUE || BufferOrange[j] == EMPTY_VALUE) continue;
      double dist = BufferOrange[j] - BufferGreen[j];
      if(dist >= -1.0 && dist <= 3.0)
      {
         bool ok = true;
         for(int k = j; k >= MathMax(j - 3, 0); k--)
            if(BufferGreen[k] != EMPTY_VALUE && BufferOrange[k] != EMPTY_VALUE && BufferGreen[k] > BufferOrange[k] + 2.0) { ok = false; break; }
         if(ok && BufferGreen[i] < BufferGreen[i-1]) return(true);
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| CASE 7: Sideway Breakout                                           |
//+------------------------------------------------------------------+
int CountCrossoversInsideBB(int fromBar, int lookbackBars)
{
   int cnt = 0, startBar = MathMax(fromBar - lookbackBars, 1);
   for(int j = startBar; j <= fromBar; j++)
   {
      if(BufferGreen[j] == EMPTY_VALUE || BufferGreen[j-1] == EMPTY_VALUE) continue;
      if(BufferRed[j] == EMPTY_VALUE || BufferRed[j-1] == EMPTY_VALUE) continue;
      if(BufferBBUpper[j] == EMPTY_VALUE || BufferBBLower[j] == EMPTY_VALUE) continue;
      bool cu = (BufferGreen[j-1] <= BufferRed[j-1]) && (BufferGreen[j] > BufferRed[j]);
      bool cd = (BufferGreen[j-1] >= BufferRed[j-1]) && (BufferGreen[j] < BufferRed[j]);
      if((cu || cd) && BufferGreen[j] <= BufferBBUpper[j] && BufferGreen[j] >= BufferBBLower[j]) cnt++;
   }
   return(cnt);
}

bool CheckCase7_Buy(int i)
{
   if(i < InpSidewayCount + 5) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferBBUpper[i] == EMPTY_VALUE) return(false);
   if(BufferGreen[i-1] == EMPTY_VALUE || BufferBBUpper[i-1] == EMPTY_VALUE) return(false);
   return(BufferGreen[i] > BufferBBUpper[i] && BufferGreen[i-1] <= BufferBBUpper[i-1] &&
          CountCrossoversInsideBB(i - 1, InpSwingLookback) >= InpSidewayCount);
}

bool CheckCase7_Sell(int i)
{
   if(i < InpSidewayCount + 5) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferBBLower[i] == EMPTY_VALUE) return(false);
   if(BufferGreen[i-1] == EMPTY_VALUE || BufferBBLower[i-1] == EMPTY_VALUE) return(false);
   return(BufferGreen[i] < BufferBBLower[i] && BufferGreen[i-1] >= BufferBBLower[i-1] &&
          CountCrossoversInsideBB(i - 1, InpSwingLookback) >= InpSidewayCount);
}

//+------------------------------------------------------------------+
//| Crossover confirmation (2-bar)                                     |
//+------------------------------------------------------------------+
bool ConfirmedCrossUp(int i)
{
   if(i < 3) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferGreen[i-1] == EMPTY_VALUE || BufferGreen[i-2] == EMPTY_VALUE) return(false);
   if(BufferRed[i] == EMPTY_VALUE || BufferRed[i-1] == EMPTY_VALUE || BufferRed[i-2] == EMPTY_VALUE) return(false);
   bool wasBelowRecently = (BufferGreen[i-1] <= BufferRed[i-1]) || (BufferGreen[i-2] <= BufferRed[i-2]);
   return(wasBelowRecently && (BufferGreen[i] > BufferRed[i]) && (BufferGreen[i] > BufferGreen[i-1]));
}

bool ConfirmedCrossDown(int i)
{
   if(i < 3) return(false);
   if(BufferGreen[i] == EMPTY_VALUE || BufferGreen[i-1] == EMPTY_VALUE || BufferGreen[i-2] == EMPTY_VALUE) return(false);
   if(BufferRed[i] == EMPTY_VALUE || BufferRed[i-1] == EMPTY_VALUE || BufferRed[i-2] == EMPTY_VALUE) return(false);
   bool wasAboveRecently = (BufferGreen[i-1] >= BufferRed[i-1]) || (BufferGreen[i-2] >= BufferRed[i-2]);
   return(wasAboveRecently && (BufferGreen[i] < BufferRed[i]) && (BufferGreen[i] < BufferGreen[i-1]));
}

//+------------------------------------------------------------------+
//| CASE 8: Basic Crossover (core RSI rule)                           |
//| Green crosses above/below Red with 2-bar confirmation + rising/   |
//| falling momentum. The strong-angle gate is applied in the main    |
//| loop (same as Case 2/3/5). Lowest scan priority: only fires when  |
//| no higher-quality pattern (Case 6/2/4/3/1/5/7) matched the bar.   |
//+------------------------------------------------------------------+
bool CheckCase8_Buy(int i)
{
   return(ConfirmedCrossUp(i));
}

bool CheckCase8_Sell(int i)
{
   return(ConfirmedCrossDown(i));
}

//+------------------------------------------------------------------+
//| CASE 9: Plain Green x Red crossover (experimental, lowest prio).  |
//| The bare RSI-Advanced crossover: green crosses Red with 2-bar     |
//| confirmation + rising green (ConfirmedCrossUp/Down), but WITHOUT   |
//| Case 8's strong-angle gate. Because Case 8 (steep cross) has      |
//| higher priority, Case 9 catches the WEAK/plain crosses Case 8     |
//| rejects — isolating them so the probability engine tracks their   |
//| OWN Tier-1 win-rate separately. No zone / no angle filter.        |
//| Grouped reversal-family (tight SL / momentum-turn) for now.       |
//+------------------------------------------------------------------+
bool CheckCase9_Buy(int i)
{
   return(ConfirmedCrossUp(i));
}

bool CheckCase9_Sell(int i)
{
   return(ConfirmedCrossDown(i));
}

#endif