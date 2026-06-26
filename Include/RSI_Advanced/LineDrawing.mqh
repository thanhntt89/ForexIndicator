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

double GetCachedATROffset()
{
   static double  s_cachedOffset = 0;
   static datetime s_cachedBar   = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(curBar != s_cachedBar)
   {
      s_cachedBar = curBar;
      s_cachedOffset = iATR(NULL, 0, 14, 0) * 0.2;
   }
   return(s_cachedOffset);
}
#include "SLTP.mqh"
//+------------------------------------------------------------------+
void CreateHorizontalLine(string name, double price, color clr, int style, int width, string tip)
{
   if(InpEAMode) return;
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
// offsetSign: +1 = text above line (ANCHOR_LEFT_LOWER), -1 = text below line (ANCHOR_LEFT_UPPER)
void CreatePriceTag(string name, string text, double price, color clr, int offsetSign = 1)
{
   if(ObjectFind(name) >= 0) ObjectDelete(name);
   double offset = GetCachedATROffset() * offsetSign;
   datetime tagTime = GetTimeFromBarPlusPixels(30);
   ObjectCreate(name, OBJ_TEXT, 0, tagTime, price + offset);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   int anchor = (offsetSign >= 0) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}
//+------------------------------------------------------------------+
void CreateProbLabel(string name, string text, double price, color clr, datetime dummy, int fs)
{
   if(ObjectFind(name) >= 0) ObjectDelete(name);
   double offset = GetCachedATROffset();
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
// dimMode=true: AVOID/WAIT — draw only entry line in dim color, hide SL/TP lines
void DrawSLTPLines(int sigIdx, bool dimMode = false)
{
   DeleteObjectsByPrefix(PREFIX_ZONE);
   if(!InpShowSLTPLines || sigIdx < 0 || sigIdx >= g_signalCount) return;
   SignalData sig = g_signals[sigIdx];

   // EN text: offset toward TP (away from SL). SL text: offset away from entry.
   // BUY:  TP is above entry → EN above (+1), SL below (-1)
   // SELL: TP is below entry → EN below (-1), SL above (+1)
   int enSign = sig.isBuySignal ? +1 : -1;
   int slSign = sig.isBuySignal ? -1 : +1;

   if(dimMode)
   {
      // Full setup shown dim — trader sees risk/reward context without it being a trade signal
      CreateHorizontalLine(PREFIX_LINE+"ENTRY", sig.entryPrice, InpPanelDimColor, STYLE_DOT, 1, "");
      CreatePriceTag(PREFIX_LINE+"T_EN", "EN "+DoubleToString(sig.entryPrice,_Digits), sig.entryPrice, InpPanelDimColor, enSign);
      CreateHorizontalLine(PREFIX_LINE+"SL", sig.stopLoss, InpPanelDimColor, STYLE_DOT, 1, "");
      CreatePriceTag(PREFIX_LINE+"T_SL", "SL "+DoubleToString(sig.stopLoss,_Digits), sig.stopLoss, InpPanelDimColor, slSign);
      CreateHorizontalLine(PREFIX_LINE+"TP1", sig.takeProfit1, InpPanelDimColor, STYLE_DOT, 1, "");
      CreatePriceTag(PREFIX_LINE+"T_T1", "TP1 "+DoubleToString(sig.takeProfit1,_Digits), sig.takeProfit1, InpPanelDimColor);
      CreateHorizontalLine(PREFIX_LINE+"TP2", sig.takeProfit2, InpPanelDimColor, STYLE_DOT, 1, "");
      CreatePriceTag(PREFIX_LINE+"T_T2", "TP2 "+DoubleToString(sig.takeProfit2,_Digits), sig.takeProfit2, InpPanelDimColor);
      CreateHorizontalLine(PREFIX_LINE+"TP3", sig.takeProfit3, InpPanelDimColor, STYLE_DOT, 1, "");
      CreatePriceTag(PREFIX_LINE+"T_T3", "TP3 "+DoubleToString(sig.takeProfit3,_Digits), sig.takeProfit3, InpPanelDimColor);
      return;
   }

   if(InpShowEntryLine)
   {
      color entryClr = InpEntryLineColor;
      if(g_currentProb.elapsedBars > 0 && g_currentProb.survivalRatio < 1.0)
      {
         double edgePct = g_currentProb.survivalRatio * 100.0;
         if(edgePct > 70)      entryClr = clrLime;
         else if(edgePct > 40) entryClr = clrYellow;
         else if(edgePct > 20) entryClr = clrOrange;
         else                  entryClr = clrRed;
      }
      CreateHorizontalLine(PREFIX_LINE+"ENTRY", sig.entryPrice, entryClr, STYLE_DOT, 1, "ENTRY");
      CreatePriceTag(PREFIX_LINE+"T_EN", "EN "+DoubleToString(sig.entryPrice,_Digits), sig.entryPrice, entryClr, enSign);
   }
   CreateHorizontalLine(PREFIX_LINE+"SL", sig.stopLoss, InpSLLineColor, InpSLTPLineStyle, InpSLTPLineWidth, "SL");
   CreatePriceTag(PREFIX_LINE+"T_SL", "SL "+DoubleToString(sig.stopLoss,_Digits), sig.stopLoss, InpSLLineColor, slSign);
   CreateHorizontalLine(PREFIX_LINE+"TP1", sig.takeProfit1, InpTP1LineColor, InpSLTPLineStyle, InpSLTPLineWidth, "TP1");
   CreatePriceTag(PREFIX_LINE+"T_T1", "TP1 "+DoubleToString(sig.takeProfit1,_Digits), sig.takeProfit1, InpTP1LineColor);
   CreateHorizontalLine(PREFIX_LINE+"TP2", sig.takeProfit2, InpTP2LineColor, InpSLTPLineStyle, InpSLTPLineWidth, "TP2");
   CreatePriceTag(PREFIX_LINE+"T_T2", "TP2 "+DoubleToString(sig.takeProfit2,_Digits), sig.takeProfit2, InpTP2LineColor);
   CreateHorizontalLine(PREFIX_LINE+"TP3", sig.takeProfit3, InpTP3LineColor, InpSLTPLineStyle, InpSLTPLineWidth, "TP3");
   CreatePriceTag(PREFIX_LINE+"T_T3", "TP3 "+DoubleToString(sig.takeProfit3,_Digits), sig.takeProfit3, InpTP3LineColor);
}
//+------------------------------------------------------------------+
// dimMode=true: AVOID/WAIT — all labels shown near entry line, all in dim color
void DrawProbabilityLabels(bool dimMode = false)
{
   DeleteObjectsByPrefix(PREFIX_PROB);
   if(!InpShowProbability || g_activeSignalIndex < 0 || g_activeSignalIndex >= g_signalCount) return;
   if(g_currentProb.probTP1 <= 0 && g_currentProb.probSL <= 0) return;
   SignalData sig = g_signals[g_activeSignalIndex];
   string ni = (g_currentProb.totalSamples > 0)
      ? " [n=" + IntegerToString(g_currentProb.totalSamples) + "]"
      : " [theo]";

   if(dimMode)
   {
      string dimTxt = "EN " + DoubleToString(sig.entryPrice,_Digits)
                    + " | W:" + DoubleToString(g_currentProb.probTP1,1)
                    + "% L:" + DoubleToString(g_currentProb.probSL,1) + "%"
                    + ni;
      ObjectSetString(0, PREFIX_LINE+"T_EN", OBJPROP_TEXT, dimTxt);
      ObjectSetInteger(0, PREFIX_LINE+"T_EN", OBJPROP_FONTSIZE, 8);
      return;
   }

   // SL: append prob to price tag
   ObjectSetString(0, PREFIX_LINE+"T_SL", OBJPROP_TEXT,
      "SL " + DoubleToString(sig.stopLoss,_Digits) + "  " +
      DoubleToString(g_currentProb.probSL,1) + "%" + ni);

   UpdateTPHitStatus(g_activeSignalIndex);

   int activeTP = 0;
   if(!g_tpHit[0])      activeTP = 1;
   else if(!g_tpHit[1]) activeTP = 2;
   else if(!g_tpHit[2]) activeTP = 3;

   bool hasDecay = (g_currentProb.originalProbTP1 > 0 && g_currentProb.elapsedBars > 0);
   double edgePct = g_currentProb.survivalRatio * 100.0;

   // TP1
   string p1 = "";
   color  c1 = InpTP1LineColor;
   if(g_tpHit[0])
   {
      p1 = "HIT " + DoubleToString(g_currentProb.probTP1,1) + "%";
      c1 = clrLime;
   }
   else if(hasDecay && activeTP == 1)
   {
      p1 = DoubleToString(g_currentProb.originalProbTP1,1) + "%->" + DoubleToString(g_currentProb.probTP1,1) + "%";
      if(g_currentProb.avgBarsToTP1 > 0)
         p1 += " ~" + IntegerToString((int)g_currentProb.avgBarsToTP1) + "bars";
      p1 += " Edge:" + DoubleToString(edgePct, 0) + "%";
      c1 = (g_currentProb.probTP1 >= g_currentProb.originalProbTP1) ? clrLime : clrOrange;
   }
   else
   {
      p1 = DoubleToString(g_currentProb.probTP1,1) + "%";
      if(g_currentProb.avgBarsToTP1 > 0)
         p1 += " ~" + IntegerToString((int)g_currentProb.avgBarsToTP1) + "bars";
   }
   ObjectSetString(0, PREFIX_LINE+"T_T1", OBJPROP_TEXT,
      "TP1 " + DoubleToString(sig.takeProfit1,_Digits) + "  " + p1);
   ObjectSetInteger(0, PREFIX_LINE+"T_T1", OBJPROP_COLOR, c1);

   // TP2
   string p2 = "";
   color  c2 = InpTP2LineColor;
   if(g_tpHit[1])
   {
      p2 = "HIT " + DoubleToString(g_currentProb.probTP2,1) + "%";
      c2 = clrLime;
   }
   else if(hasDecay && activeTP == 2)
   {
      p2 = DoubleToString(g_currentProb.originalProbTP2,1) + "%->" + DoubleToString(g_currentProb.probTP2,1) + "%";
      p2 += " Edge:" + DoubleToString(edgePct, 0) + "%";
      c2 = (g_currentProb.probTP2 >= g_currentProb.originalProbTP2) ? clrLime : clrOrange;
   }
   else
      p2 = DoubleToString(g_currentProb.probTP2,1) + "%";
   ObjectSetString(0, PREFIX_LINE+"T_T2", OBJPROP_TEXT,
      "TP2 " + DoubleToString(sig.takeProfit2,_Digits) + "  " + p2);
   ObjectSetInteger(0, PREFIX_LINE+"T_T2", OBJPROP_COLOR, c2);

   // TP3
   string p3 = "";
   color  c3 = InpTP3LineColor;
   if(g_tpHit[2])
   {
      p3 = "HIT " + DoubleToString(g_currentProb.probTP3,1) + "%";
      c3 = clrLime;
   }
   else if(hasDecay && activeTP == 3)
   {
      p3 = DoubleToString(g_currentProb.originalProbTP3,1) + "%->" + DoubleToString(g_currentProb.probTP3,1) + "%";
      p3 += " Edge:" + DoubleToString(edgePct, 0) + "%";
      c3 = (g_currentProb.probTP3 >= g_currentProb.originalProbTP3) ? clrLime : clrOrange;
   }
   else
      p3 = DoubleToString(g_currentProb.probTP3,1) + "%";
   ObjectSetString(0, PREFIX_LINE+"T_T3", OBJPROP_TEXT,
      "TP3 " + DoubleToString(sig.takeProfit3,_Digits) + "  " + p3);
   ObjectSetInteger(0, PREFIX_LINE+"T_T3", OBJPROP_COLOR, c3);

   // ENTRY: win/loss
   ObjectSetString(0, PREFIX_LINE+"T_EN", OBJPROP_TEXT,
      "EN " + DoubleToString(sig.entryPrice,_Digits) +
      " | W:" + DoubleToString(g_currentProb.probTP1,1) +
      "% L:" + DoubleToString(g_currentProb.probSL,1) + "%");
   ObjectSetInteger(0, PREFIX_LINE+"T_EN", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PREFIX_LINE+"T_EN", OBJPROP_FONTSIZE, 8);
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
   // Zone label offset: use a tiny fraction of ATR, capped at 1% of zone spacing.
   // ATR*0.2 (old) was fine for XAUUSD (~2 pip) but pushed BTC labels ~100 pts
   // above their lines, making Z2 text appear at Z3's level.
   // With ANCHOR_LEFT_LOWER, offset=0 already places text ABOVE the line price.
   // We add only a tiny nudge so the text bottom doesn't sit exactly on the line.
   double atrOffset   = iATR(NULL, 0, 14, 0) * 0.02;  // 2% of ATR (was 20%)
   datetime tagTime = GetTimeFromBarPlusPixels(30);
   for(int z = 0; z < 5; z++)
   {
      if(!g_entryZones[z].isValid) continue;
      if(g_entryZones[z].price <= 0) continue;
      if(z == 0 && InpShowEntryLine) continue;
      string zName = PREFIX_ZONE + IntegerToString(z);
      color zColor = GetZoneColor(z);
      int zStyle = g_entryZones[z].isRecommended ? STYLE_DASH : STYLE_DOT;
      if(!g_entryZones[z].isRecommended)
         zColor = InpPanelDimColor;
      CreateHorizontalLine(zName + "_L", g_entryZones[z].price,
         zColor, zStyle, 1,
         g_entryZones[z].zoneName + " " +
         DoubleToString(g_entryZones[z].price, _Digits));
      //--- Zone label anchored exactly at zone line with minimal nudge
      string tagText = "Z" + IntegerToString(z + 1) + " " +
                        DoubleToString(g_entryZones[z].price, _Digits);
      if(g_entryZones[z].lotSize > 0)
         tagText += " " + DoubleToString(g_entryZones[z].lotSize, 2) + "lot";
      if(g_entryZones[z].isRecommended && g_entryZones[z].rrRatio > 0)
         tagText += " R:R1:" + DoubleToString(g_entryZones[z].rrRatio, 1);
      tagText += "  Reach:" + DoubleToString(g_entryZones[z].probReach * 100, 0) + "%";
      tagText += " Win:" + DoubleToString(g_entryZones[z].probTP1, 0) + "%";
      if(g_entryZones[z].expectedValue > 0)
         tagText += " EV+" + DoubleToString(g_entryZones[z].expectedValue, 2) + "R *";
      else if(g_entryZones[z].expectedValue != 0)
         tagText += " EV" + DoubleToString(g_entryZones[z].expectedValue, 2) + "R";
      if(ObjectFind(zName + "_T") >= 0) ObjectDelete(zName + "_T");
      ObjectCreate(zName + "_T", OBJ_TEXT, 0, tagTime, g_entryZones[z].price + atrOffset);
      ObjectSetString(0, zName + "_T", OBJPROP_TEXT, tagText);
      ObjectSetInteger(0, zName + "_T", OBJPROP_COLOR, zColor);
      ObjectSetString(0, zName + "_T", OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, zName + "_T", OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, zName + "_T", OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, zName + "_T", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, zName + "_T", OBJPROP_HIDDEN, true);
   }
}

#endif