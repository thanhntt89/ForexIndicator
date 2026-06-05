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
#include "SLTP.mqh"
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
   DeleteObjectsByPrefix(PREFIX_ZONE);  // Clean zone lines when redrawing
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
//+------------------------------------------------------------------+
//|     ██  ENTRY ZONE LINES  ██                                       |
//|                                                                    |
//| Draws horizontal lines + labels for each valid entry zone          |
//| Valid zones: solid line                                            |
//| EV negative zones: dashed line (dimmer color)                      |
//| V11: Accepts suppress parameter to hide zones when AVOID/WAIT      |
//+------------------------------------------------------------------+
void DrawZoneLines(bool suppress = false)
{
   DeleteObjectsByPrefix(PREFIX_ZONE);

   // V11: If suppressed (AVOID/WAIT), just clean and return - no lines drawn
   if(suppress) return;

   if(InpEntryZoneCount < 2) return;
   if(g_validZoneCount < 1) return;
   double offset = iATR(NULL, 0, 14, 0) * 0.2;
   datetime tagTime = GetTimeFromBarPlusPixels(30);
   datetime probTime = GetTimeFromBarPlusPixels(200);
   for(int z = 0; z < 5; z++)
   {
      if(!g_entryZones[z].isValid) continue;
      if(g_entryZones[z].price <= 0) continue;
      // Skip Zone 1 if entry line already drawn by DrawSLTPLines
      if(z == 0 && InpShowEntryLine) continue;
      string zName = PREFIX_ZONE + IntegerToString(z);
      color zColor = GetZoneColor(z);
      int zStyle = g_entryZones[z].isRecommended ? STYLE_DASH : STYLE_DOT;
      // Dim color for non-recommended zones
      if(!g_entryZones[z].isRecommended)
         zColor = InpPanelDimColor;
      //--- Zone horizontal line
      CreateHorizontalLine(zName + "_L", g_entryZones[z].price,
         zColor, zStyle, 1,
         g_entryZones[z].zoneName + " " +
         DoubleToString(g_entryZones[z].price, _Digits));
      //--- Zone price tag (left side, near current bar)
      string tagText = "Z" + IntegerToString(z + 1) + " " +
                        DoubleToString(g_entryZones[z].price, _Digits);
      if(g_entryZones[z].lotSize > 0)
         tagText += " " + DoubleToString(g_entryZones[z].lotSize, 2) + "lot";
      if(g_entryZones[z].isRecommended && g_entryZones[z].rrRatio > 0)
         tagText += " R:R1:" + DoubleToString(g_entryZones[z].rrRatio, 1);
      if(ObjectFind(zName + "_T") >= 0) ObjectDelete(zName + "_T");
      ObjectCreate(zName + "_T", OBJ_TEXT, 0, tagTime, g_entryZones[z].price + offset);
      ObjectSetString(0, zName + "_T", OBJPROP_TEXT, tagText);
      ObjectSetInteger(0, zName + "_T", OBJPROP_COLOR, zColor);
      ObjectSetString(0, zName + "_T", OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, zName + "_T", OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, zName + "_T", OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, zName + "_T", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, zName + "_T", OBJPROP_HIDDEN, true);
      //--- Zone probability tag (right side, further from bar)
      string probText = "P:" + DoubleToString(g_entryZones[z].probReach * 100, 0) + "%";
      if(g_entryZones[z].expectedValue > 0)
         probText += " EV+" + DoubleToString(g_entryZones[z].expectedValue, 2) + "R *";
      else if(g_entryZones[z].expectedValue != 0)
         probText += " EV" + DoubleToString(g_entryZones[z].expectedValue, 2) + "R";
      if(ObjectFind(zName + "_P") >= 0) ObjectDelete(zName + "_P");
      ObjectCreate(zName + "_P", OBJ_TEXT, 0, probTime, g_entryZones[z].price + offset);
      ObjectSetString(0, zName + "_P", OBJPROP_TEXT, probText);
      ObjectSetInteger(0, zName + "_P", OBJPROP_COLOR, zColor);
      ObjectSetString(0, zName + "_P", OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, zName + "_P", OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, zName + "_P", OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, zName + "_P", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, zName + "_P", OBJPROP_HIDDEN, true);
   }
}
#endif