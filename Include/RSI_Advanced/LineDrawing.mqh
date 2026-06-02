//+------------------------------------------------------------------+
//|                                             LineDrawing.mqh        |
//|                         RSI Advanced - SL/TP Lines & Labels        |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_LINEDRAWING_MQH
#define RSI_ADV_LINEDRAWING_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"
#include "MathUtils.mqh"

//+------------------------------------------------------------------+
void CreateHorizontalLine(string name, double price, color clr, int style, int width, string tip)
{
   if(ObjectFind(name) >= 0) ObjectDelete(name);
   ObjectCreate(name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

//+------------------------------------------------------------------+
void CreatePriceTag(string name, string text, double price, color clr)
{
   if(ObjectFind(name) >= 0) ObjectDelete(name);
   double offset = iATR(NULL, 0, 14, 0) * 0.2;
   datetime tagTime = GetTimeFromBarPlusPixels(30);
   ObjectCreate(name, OBJ_TEXT, 0, tagTime, price + offset);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void CreateProbLabel(string name, string text, double price, color clr, datetime dummy, int fs)
{
   if(ObjectFind(name) >= 0) ObjectDelete(name);
   double offset = iATR(NULL, 0, 14, 0) * 0.2;
   datetime probTime = GetTimeFromBarPlusPixels(180);
   ObjectCreate(name, OBJ_TEXT, 0, probTime, price + offset);
   ObjectSetString(0, name, OBJPROP_TEXT, "  " + text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void DrawSLTPLines(int sigIdx)
{
   DeleteObjectsByPrefix(PREFIX_LINE);
   if(!InpShowSLTPLines || sigIdx < 0 || sigIdx >= g_signalCount) return;
   SignalData sig = g_signals[sigIdx];

   if(InpShowEntryLine)
   {
      CreateHorizontalLine(PREFIX_LINE+"ENTRY", sig.entryPrice, InpEntryLineColor, STYLE_DOT, 1, "ENTRY");
      CreatePriceTag(PREFIX_LINE+"T_EN", "ENTRY "+DoubleToString(sig.entryPrice,_Digits), sig.entryPrice, InpEntryLineColor);
   }
   CreateHorizontalLine(PREFIX_LINE+"SL", sig.stopLoss, InpSLLineColor, InpSLTPLineStyle, InpSLTPLineWidth, "SL");
   CreatePriceTag(PREFIX_LINE+"T_SL", "SL "+DoubleToString(sig.stopLoss,_Digits), sig.stopLoss, InpSLLineColor);

   CreateHorizontalLine(PREFIX_LINE+"TP1", sig.takeProfit1, InpTP1LineColor, InpSLTPLineStyle, InpSLTPLineWidth, "TP1");
   CreatePriceTag(PREFIX_LINE+"T_T1", "TP1 "+DoubleToString(sig.takeProfit1,_Digits), sig.takeProfit1, InpTP1LineColor);

   CreateHorizontalLine(PREFIX_LINE+"TP2", sig.takeProfit2, InpTP2LineColor, InpSLTPLineStyle, InpSLTPLineWidth, "TP2");
   CreatePriceTag(PREFIX_LINE+"T_T2", "TP2 "+DoubleToString(sig.takeProfit2,_Digits), sig.takeProfit2, InpTP2LineColor);

   CreateHorizontalLine(PREFIX_LINE+"TP3", sig.takeProfit3, InpTP3LineColor, InpSLTPLineStyle, InpSLTPLineWidth, "TP3");
   CreatePriceTag(PREFIX_LINE+"T_T3", "TP3 "+DoubleToString(sig.takeProfit3,_Digits), sig.takeProfit3, InpTP3LineColor);
}

//+------------------------------------------------------------------+
void DrawProbabilityLabels()
{
   DeleteObjectsByPrefix(PREFIX_PROB);
   if(!InpShowProbability || g_activeSignalIndex < 0 || g_activeSignalIndex >= g_signalCount) return;
   if(g_currentProb.totalSamples < GetMinSamplesForTimeframe()) return;

   SignalData sig = g_signals[g_activeSignalIndex];
   int fs = InpProbFontSize;
   datetime dummy = 0;
   string ni = " [n=" + IntegerToString(g_currentProb.totalSamples) + "]";

   CreateProbLabel(PREFIX_PROB+"SL", "SL  "+DoubleToString(g_currentProb.probSL,1)+"%"+ni, sig.stopLoss, InpSLLineColor, dummy, fs);

   string t1 = "TP1  "+DoubleToString(g_currentProb.probTP1,1)+"%";
   if(g_currentProb.avgBarsToTP1 > 0) t1 += "  ~"+IntegerToString((int)g_currentProb.avgBarsToTP1)+" bars";
   CreateProbLabel(PREFIX_PROB+"TP1", t1, sig.takeProfit1, InpTP1LineColor, dummy, fs);
   CreateProbLabel(PREFIX_PROB+"TP2", "TP2  "+DoubleToString(g_currentProb.probTP2,1)+"%", sig.takeProfit2, InpTP2LineColor, dummy, fs);
   CreateProbLabel(PREFIX_PROB+"TP3", "TP3  "+DoubleToString(g_currentProb.probTP3,1)+"%", sig.takeProfit3, InpTP3LineColor, dummy, fs);
   CreateProbLabel(PREFIX_PROB+"EN", "Win: "+DoubleToString(g_currentProb.probTP1,1)+"% | Loss: "+DoubleToString(g_currentProb.probSL,1)+"%", sig.entryPrice, clrWhite, dummy, fs);
}

#endif