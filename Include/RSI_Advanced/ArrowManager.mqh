//+------------------------------------------------------------------+
//|                                            ArrowManager.mqh        |
//|                         RSI Advanced - Arrow Object Management     |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_ARROWMANAGER_MQH
#define RSI_ADV_ARROWMANAGER_MQH

#include "Config.mqh"
#include "SignalCases.mqh"

//+------------------------------------------------------------------+
void CreateSignalArrow(datetime barTime, double price, bool isBuy, int caseNum)
{
   if(InpEAMode) return;
   string name = PREFIX_ARROW + (isBuy ? "BUY_" : "SELL_")
               + IntegerToString(caseNum) + "_"
               + IntegerToString((int)barTime);
   if(ObjectFind(name) >= 0) ObjectDelete(name);
   double offset = InpArrowOffset * _Point;

   if(isBuy)
   {
      ObjectCreate(name, OBJ_ARROW, 0, barTime, price - offset);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 233);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpBuyArrowColor);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_TOP);
   }
   else
   {
      ObjectCreate(name, OBJ_ARROW, 0, barTime, price + offset);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpSellArrowColor);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   }
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpArrowSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
      (isBuy?"BUY":"SELL") + " Case " + IntegerToString(caseNum) + ": " + GetCaseName(caseNum) + " [Click]");
}

//+------------------------------------------------------------------+
//| [EXPERIMENT] OB/OS-zone crossover monitor marker.                 |
//| Draws a small dot where Green crosses Red while INSIDE the        |
//| oversold (<32, buy) or overbought (>68, sell) zone. This is the   |
//| user-proposed "cross inside 32" rule, shown as an OBSERVATIONAL   |
//| marker only: it is NOT wired into buySignal / probability / SLTP, |
//| so it cannot affect any trade decision. Purpose: eyeball how      |
//| often the pattern fires and whether it precedes real reversals,   |
//| per timeframe. Distinct prefix + look so it never collides with   |
//| the real signal arrows.                                           |
//+------------------------------------------------------------------+
void DrawOSCrossMonitor(int i, const datetime &time[], const double &low[], const double &high[])
{
   if(InpEAMode || !InpMonitorOSCross) return;
   if(i < 1) return;
   if(BufferGreen[i] == EMPTY_VALUE || BufferGreen[i-1] == EMPTY_VALUE) return;
   if(BufferRed[i]   == EMPTY_VALUE || BufferRed[i-1]   == EMPTY_VALUE) return;

   bool crossUp   = (BufferGreen[i-1] <= BufferRed[i-1]) && (BufferGreen[i] > BufferRed[i]);
   bool crossDown = (BufferGreen[i-1] >= BufferRed[i-1]) && (BufferGreen[i] < BufferRed[i]);
   bool osBuy  = crossUp   && BufferGreen[i] < 32.0;   // green crosses up red inside oversold
   bool obSell = crossDown && BufferGreen[i] > 68.0;   // green crosses down red inside overbought
   if(!osBuy && !obSell) return;

   string name = PREFIX_OSMON + (osBuy ? "B_" : "S_") + IntegerToString((int)time[i]);
   if(ObjectFind(name) >= 0) return;   // already drawn for this bar

   double offset = InpArrowOffset * _Point * 1.8;
   double price  = osBuy ? (low[i] - offset) : (high[i] + offset);
   ObjectCreate(name, OBJ_ARROW, 0, time[i], price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);                        // small dot
   ObjectSetInteger(0, name, OBJPROP_COLOR, osBuy ? clrAqua : clrMagenta);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, osBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
      (osBuy ? "OS-Cross BUY monitor" : "OB-Cross SELL monitor") + " (experimental, not a system signal)");
}

#endif