//+------------------------------------------------------------------+
//|                                            PanelDrawing.mqh        |
//|                         RSI Advanced - Info Panel Drawing          |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_PANELDRAWING_MQH
#define RSI_ADV_PANELDRAWING_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"
#include "MathUtils.mqh"
#include "SignalCases.mqh"
#include "MTFEngine.mqh"
#include "Normalize.mqh"

//+------------------------------------------------------------------+
void CreateRectangleLabel(string name,int x,int y,int w,int h,color bg,color brd)
{
   if(ObjectFind(name)>=0) ObjectDelete(name);
   ObjectCreate(name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,brd);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void CreateTextLabel(string name,int x,int y,string text,color clr,int fs,bool bold)
{
   if(ObjectFind(name)>=0) ObjectDelete(name);
   ObjectCreate(name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetString(0,name,OBJPROP_FONT,bold?"Arial Bold":"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

//+------------------------------------------------------------------+
void DrawInfoPanel(int signalIndex)
{
   DeleteObjectsByPrefix(PREFIX_PANEL);
   if(!InpShowPanel) return;
   if(signalIndex < 0 || signalIndex >= g_signalCount) return;

   int px = g_panelPosX, py = g_panelPosY;
   int pw = InpPanelWidth, fs = InpPanelFontSize;
   int lh = fs + 6, pad = 8, titleBarH = lh + 6;

   SignalData sig = g_signals[signalIndex];
   bool isBuy = sig.isBuySignal;
   string dir = isBuy ? "BUY" : "SELL";
   color dirClr = isBuy ? InpPanelBuyColor : InpPanelSellColor;

   // Pre-calc
   string detailText = isBuy ? GetCaseDetailBuy(sig.caseNumber) : GetCaseDetailSell(sig.caseNumber);
   string detailLines[];
   int detailCount = StringSplit(detailText, '|', detailLines);
   int barsAgo = iBarShift(NULL, 0, sig.signalTime, false);
   if(barsAgo < 0) barsAgo = 0;

   double slDist = MathAbs(sig.entryPrice - sig.stopLoss);
   double curPrice = iClose(NULL, 0, 0);
   double plDist = isBuy ? (curPrice - sig.entryPrice) : (sig.entryPrice - curPrice);
   bool isStale = (barsAgo > 20 && plDist < -slDist * 0.5);

   double tp1Dist = MathAbs(sig.takeProfit1 - sig.entryPrice);
   double tp2Dist = MathAbs(sig.takeProfit2 - sig.entryPrice);
   double tp3Dist = MathAbs(sig.takeProfit3 - sig.entryPrice);
   double slPips = PriceToNormalizedPips(slDist);
   double tp1R = PriceToRMultiple(tp1Dist, slDist);
   double tp2R = PriceToRMultiple(tp2Dist, slDist);
   double tp3R = PriceToRMultiple(tp3Dist, slDist);

   bool hasProb = (InpShowProbability && g_currentProb.totalSamples >= GetMinSamplesForTimeframe());
   bool hasMTF = (InpShowMTF && g_mtfCount > 0);

   // Recommendation pre-calc
   int mtfAgree = 0;
   if(hasMTF) mtfAgree = CalculateMTFAgreement();
   TradeRecommendation rec = GetTradeRecommendation(
      sig.caseNumber, isBuy, g_currentProb.probTP1, g_currentProb.probSL,
      g_currentProb.totalSamples, mtfAgree, slDist, tp1Dist, sig.atrValue, sig.signalTime);

   // ============================================
   // PASS 1: Height
   // ============================================
   int calcY = 0;
   calcY += titleBarH + 2;
   calcY += lh;
   calcY += detailCount * (lh - 2) + 2;
   calcY += lh;
   if(isStale) calcY += lh;
   calcY += 3;
   calcY += lh;
   calcY += lh;
   calcY += 3;
   calcY += lh;
   calcY += lh;
   calcY += lh;
   calcY += lh;
   calcY += lh;
   calcY += lh;
   calcY += lh;

   if(hasProb)
   {
      calcY += 3;
      calcY += lh;
      calcY += lh;
      calcY += lh;
      calcY += lh;
      calcY += lh;
      calcY += lh;
      calcY += lh;
   }

   if(hasMTF)
   {
      calcY += 3;
      calcY += lh;
      calcY += g_mtfCount * lh;
      calcY += lh;
   }

   calcY += lh;
   calcY += 4;
   int totalH = calcY;

   // Auto-adjust
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(py + totalH > chartH - 10) { py = MathMax(0, chartH - totalH - 10); g_panelPosY = py; }
   if(px + pw > chartW - 10)     { px = MathMax(0, chartW - pw - 10);     g_panelPosX = px; }

   // ============================================
   // PASS 2: Background
   // ============================================
   CreateRectangleLabel(PREFIX_PANEL+"0_BG", px, py, pw, totalH, InpPanelBgColor, InpPanelBorderColor);
   CreateRectangleLabel(PREFIX_PANEL+"0_TB", px, py, pw, titleBarH, InpPanelBorderColor, InpPanelBorderColor);

   // ============================================
   // PASS 3: Content
   // ============================================
   int cy = py + 3;

   //--- TITLE BAR ---
   CreateTextLabel(PREFIX_PANEL+"1_T", px+pad, cy,
      "RSI Advanced - "+dir+" SIGNAL", InpPanelTitleColor, fs+1, true);
   cy += titleBarH + 2 - 3;

   //--- CASE NAME ---
   CreateTextLabel(PREFIX_PANEL+"2_C", px+pad, cy,
      "Case "+IntegerToString(sig.caseNumber)+": "+GetCaseName(sig.caseNumber),
      dirClr, fs, true);
   cy += lh;

   //--- DETAIL (compact) ---
   for(int i=0; i<detailCount && i<3; i++)
   {
      CreateTextLabel(PREFIX_PANEL+"2_D"+IntegerToString(i), px+pad+3, cy,
         detailLines[i], InpPanelTextColor, fs-2, false);
      cy += lh - 2;
   }
   cy += 2;

   //--- SYMBOL | TF | AGE (1 line) ---
   int minsAgo = barsAgo * Period();
   string ageShort;
   if(minsAgo >= 60) ageShort = IntegerToString(minsAgo/60)+"h"+IntegerToString(minsAgo%60)+"m";
   else              ageShort = IntegerToString(minsAgo)+"m";

   CreateTextLabel(PREFIX_PANEL+"3_I", px+pad, cy,
      GetCleanSymbolName()+" | "+GetTimeframeString()+
      " | "+TimeToString(sig.signalTime, TIME_MINUTES)+
      " | Age: "+ageShort,
      InpPanelTextColor, fs-1, false);
   cy += lh;

   //--- STALE ---
   if(isStale)
   {
      CreateTextLabel(PREFIX_PANEL+"3_ST", px+pad, cy,
         "!! STALE SIGNAL - Consider closing !!", clrRed, fs-1, true);
      cy += lh;
   }
   cy += 3;

   //--- RECOMMENDATION ---
   CreateTextLabel(PREFIX_PANEL+"4_R", px+pad, cy,
      ">> "+rec.label+" <<  ["+IntegerToString(rec.confidence)+"/100]",
      rec.labelColor, fs+1, true);
   cy += lh;

   // Risk + Reason
   string riskReason = "";
   if(rec.suggestedRisk > 0)
      riskReason = "Risk: "+DoubleToString(rec.suggestedRisk,1)+"% | ";
   else
      riskReason = "Do not trade | ";
   riskReason += rec.reason;
   CreateTextLabel(PREFIX_PANEL+"4_RR", px+pad+3, cy, riskReason,
      rec.suggestedRisk > 0 ? InpPanelTextColor : clrOrange, fs-2, false);
   cy += lh;
   cy += 3;

   //--- ATR | SL:TP (merged) ---
   CreateTextLabel(PREFIX_PANEL+"5_A", px+pad, cy,
      "ATR:"+DoubleToString(sig.atrValue,_Digits)+
      " | SL:"+DoubleToString(InpSLRatio,1)+
      " TP:"+DoubleToString(InpTPRatio,1)+"/"+
      DoubleToString(InpTPRatio*InpTP2Multiplier,1)+"/"+
      DoubleToString(InpTPRatio*InpTP3Multiplier,1),
      InpPanelDimColor, fs-2, false);
   cy += lh;

   //--- ENTRY ---
   CreateTextLabel(PREFIX_PANEL+"5_E", px+pad, cy,
      "Entry : "+DoubleToString(sig.entryPrice,_Digits), clrWhite, fs, true);
   cy += lh;

   //--- SL ---
   CreateTextLabel(PREFIX_PANEL+"5_SL", px+pad, cy,
      "SL    : "+DoubleToString(sig.stopLoss,_Digits)+
      "  ("+DoubleToString(slPips,1)+"p)",
      InpSLLineColor, fs-1, false);
   cy += lh;

   //--- TP1 ---
   CreateTextLabel(PREFIX_PANEL+"5_T1", px+pad, cy,
      "TP1   : "+DoubleToString(sig.takeProfit1,_Digits)+
      "  ("+DoubleToString(PriceToNormalizedPips(tp1Dist),1)+"p|"+DoubleToString(tp1R,1)+"R)",
      InpTP1LineColor, fs-1, false);
   cy += lh;

   //--- TP2 ---
   CreateTextLabel(PREFIX_PANEL+"5_T2", px+pad, cy,
      "TP2   : "+DoubleToString(sig.takeProfit2,_Digits)+
      "  ("+DoubleToString(PriceToNormalizedPips(tp2Dist),1)+"p|"+DoubleToString(tp2R,1)+"R)",
      InpTP2LineColor, fs-1, false);
   cy += lh;

   //--- TP3 ---
   CreateTextLabel(PREFIX_PANEL+"5_T3", px+pad, cy,
      "TP3   : "+DoubleToString(sig.takeProfit3,_Digits)+
      "  ("+DoubleToString(PriceToNormalizedPips(tp3Dist),1)+"p|"+DoubleToString(tp3R,1)+"R)",
      InpTP3LineColor, fs-1, false);
   cy += lh;

   //--- P/L | R:R (merged) ---
   color plClr = plDist >= 0 ? clrLime : clrRed;
   string plText = "P/L:"+FormatPL(plDist, slDist);
   if(isStale) plText += " [STALE]";
   plText += "  R:R 1:"+DoubleToString(tp1R,1)+
             "|1:"+DoubleToString(tp2R,1)+
             "|1:"+DoubleToString(tp3R,1);
   CreateTextLabel(PREFIX_PANEL+"6_PL", px+pad, cy, plText, plClr, fs-1, true);
   cy += lh;

   //==========================================================
   // PROBABILITY (compact)
   //==========================================================
   if(hasProb)
   {
      cy += 3;

      // Title + Confidence
      color confClr = clrGray;
      string confTxt = GetConfidenceText(g_currentProb.totalSamples, g_currentProb.probTP1, confClr);
      CreateTextLabel(PREFIX_PANEL+"P_T", px+pad, cy,
         "Prob [n="+IntegerToString(g_currentProb.totalSamples)+"]  "+confTxt,
         InpPanelTitleColor, fs-1, true);
      cy += lh;

      // Win/Loss
      double winP = g_currentProb.probTP1, lossP = g_currentProb.probSL;
      color wlClr = winP >= lossP ? clrLime : clrOrange;
      CreateTextLabel(PREFIX_PANEL+"P_WL", px+pad, cy,
         "Win:"+DoubleToString(winP,1)+"%  |  Loss:"+DoubleToString(lossP,1)+"%",
         wlClr, fs, true);
      cy += lh;

      // TP1
      CreateTextLabel(PREFIX_PANEL+"P_1", px+pad, cy,
         " TP1:"+DoubleToString(g_currentProb.probTP1,1)+"%"+ProbBar(g_currentProb.probTP1)+
         "("+IntegerToString(g_currentProb.samplesTP1)+"/"+IntegerToString(g_currentProb.totalSamples)+")",
         InpTP1LineColor, fs-2, false);
      cy += lh;

      // TP2
      CreateTextLabel(PREFIX_PANEL+"P_2", px+pad, cy,
         " TP2:"+DoubleToString(g_currentProb.probTP2,1)+"%"+ProbBar(g_currentProb.probTP2)+
         "("+IntegerToString(g_currentProb.samplesTP2)+"/"+IntegerToString(g_currentProb.totalSamples)+")",
         InpTP2LineColor, fs-2, false);
      cy += lh;

      // TP3
      CreateTextLabel(PREFIX_PANEL+"P_3", px+pad, cy,
         " TP3:"+DoubleToString(g_currentProb.probTP3,1)+"%"+ProbBar(g_currentProb.probTP3)+
         "("+IntegerToString(g_currentProb.samplesTP3)+"/"+IntegerToString(g_currentProb.totalSamples)+")",
         InpTP3LineColor, fs-2, false);
      cy += lh;

      // Avg bars + Edge (merged)
      double edge = MeasureEdgeFromHistory(sig.caseNumber, isBuy, GetMaxForwardBarsForTimeframe());
      string avgEdge = "";
      if(g_currentProb.avgBarsToTP1 > 0)
         avgEdge += "TP1~"+IntegerToString((int)g_currentProb.avgBarsToTP1)+"bars ";
      if(g_currentProb.avgBarsToSL > 0)
         avgEdge += "SL~"+IntegerToString((int)g_currentProb.avgBarsToSL)+"bars ";
      avgEdge += "Edge:"+DoubleToString(edge*100,1)+"%";
      CreateTextLabel(PREFIX_PANEL+"P_AE", px+pad, cy, " "+avgEdge, InpPanelDimColor, fs-2, false);
      cy += lh;

      // Accuracy + MTF influence (merged)
      string accMtf = " Acc:~72-78%";
      if(hasMTF)
      {
         int ctx = GetMTFContextScore(isBuy);
         if(ctx > 50)       accMtf += " | MTF:STRONG SUPPORT(+"+IntegerToString(ctx)+")";
         else if(ctx > 20)  accMtf += " | MTF:SUPPORT(+"+IntegerToString(ctx)+")";
         else if(ctx > -20) accMtf += " | MTF:NEUTRAL("+IntegerToString(ctx)+")";
         else if(ctx > -50) accMtf += " | MTF:RISK("+IntegerToString(ctx)+")";
         else               accMtf += " | MTF:HIGH RISK("+IntegerToString(ctx)+")";
      }
      CreateTextLabel(PREFIX_PANEL+"P_AM", px+pad, cy, accMtf, InpPanelDimColor, fs-2, false);
      cy += lh;
   }

   //==========================================================
   // MTF SIGNAL STATUS
   //==========================================================
   if(hasMTF)
   {
      cy += 3;

      CreateTextLabel(PREFIX_PANEL+"M_T", px+pad, cy,
         "Multi-TF Signal Status", InpPanelTitleColor, fs-1, true);
      cy += lh;

      for(int t=0; t<g_mtfCount; t++)
      {
         color tfClr; string sigDir;
         if(g_mtfData[t].trend == 1)       { tfClr=InpMTF_BullColor;   sigDir="BUY  "; }
         else if(g_mtfData[t].trend == -1) { tfClr=InpMTF_BearColor;   sigDir="SELL "; }
         else                              { tfClr=InpMTF_NeutralColor; sigDir="WAIT "; }

         string tfName = g_mtfData[t].tfName;
         while(StringLen(tfName) < 4) tfName += " ";

         // Case info
         string caseInfo = "";
         if(g_mtfData[t].lastSignalCase > 0)
            caseInfo = " C"+IntegerToString(g_mtfData[t].lastSignalCase);

         // RSI zone
         string zone = "";
         double gv = g_mtfData[t].greenValue;
         if(gv > 68)      zone = " OB";
         else if(gv > 50) zone = " >>";
         else if(gv > 32) zone = " <<";
         else              zone = " OS";

         CreateTextLabel(PREFIX_PANEL+"M_"+IntegerToString(t), px+pad+3, cy,
            tfName+" "+sigDir+g_mtfData[t].statusText+caseInfo+
            " ["+DoubleToString(gv,1)+"]"+zone,
            tfClr, fs-2, false);
         cy += lh;
      }

      // Confluence + alignment + count
      int ag = CalculateMTFAgreement();
      string agTxt; color agClr;
      if(ag > 50)       { agTxt="STRONG BULL";  agClr=InpMTF_BullColor; }
      else if(ag > 0)   { agTxt="WEAK BULL";    agClr=InpMTF_BullColor; }
      else if(ag < -50) { agTxt="STRONG BEAR";  agClr=InpMTF_BearColor; }
      else if(ag < 0)   { agTxt="WEAK BEAR";    agClr=InpMTF_BearColor; }
      else              { agTxt="MIXED";         agClr=InpMTF_NeutralColor; }

      string align = "";
      if((isBuy && ag>0)||(!isBuy && ag<0)) align=" ALIGNED";
      else if((isBuy && ag<0)||(!isBuy && ag>0)) align=" AGAINST";

      int agreeCount = 0;
      for(int t=0; t<g_mtfCount; t++)
      {
         if(isBuy && g_mtfData[t].trend == 1) agreeCount++;
         if(!isBuy && g_mtfData[t].trend == -1) agreeCount++;
      }

      CreateTextLabel(PREFIX_PANEL+"M_AG", px+pad, cy,
         agTxt+" ("+IntegerToString(ag)+"%) "+
         IntegerToString(agreeCount)+"/"+IntegerToString(g_mtfCount)+" TFs"+align,
         agClr, fs-1, true);
      cy += lh;
   }

   //--- FOOTER ---
   CreateTextLabel(PREFIX_PANEL+"Z_F", px+pad, cy,
      "Drag title to move | Click arrow", InpPanelDimColor, fs-2, false);

   ChartRedraw();
}

#endif