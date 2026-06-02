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

#endif