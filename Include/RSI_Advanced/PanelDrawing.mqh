//+------------------------------------------------------------------+
//|                                            PanelDrawing.mqh       |
//|                         RSI Advanced - Info Panel Drawing         |
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
#include "SLTP.mqh"
#include "IntermarketAnalysis.mqh"
#include "SessionStatistics.mqh"
#include "WalkForward.mqh"
//+------------------------------------------------------------------+
void CreateRectangleLabel(string name,int x,int y,int w,int h,color bg,color brd)
{
   if(ObjectFind(name)>=0)
   {
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,brd);
      return;
   }
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
   if(ObjectFind(name)>=0)
   {
      ObjectSetString(0,name,OBJPROP_TEXT,text);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetString(0,name,OBJPROP_FONT,bold?"Arial Bold":"Arial");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
      return;
   }
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
   if(InpEAMode || !InpShowPanel) return;
   if(signalIndex < 0 || signalIndex >= g_signalCount)
   {
      static int s_lastNoSigHeight = 0;
      int px = g_panelPosX, py = g_panelPosY;
      int pw = InpPanelWidth, fs = InpPanelFontSize;
      int lh = fs + 6, pad = 8, titleBarH = lh + 6;
      bool hasMTF = (InpShowMTF && g_mtfCount > 0);
      bool hasV11 = (g_intermarket.isAvailable ||
                     g_outcomeCount > 0 ||
                     g_walkForward.isSamples > 0 ||
                     InpUseSpreadRegime);
      int calcY = titleBarH + 2 + lh + lh;
      if(hasMTF) { calcY += 3 + lh + g_mtfCount * lh + lh; }
      if(hasV11)
      {
         calcY += 3 + lh;
         if(g_intermarket.isAvailable) calcY += lh;
         if(g_outcomeCount > 0) calcY += lh;
         if(g_walkForward.isSamples > 0 || g_walkForward.oosSamples > 0) calcY += lh;
         if(InpUseSpreadRegime) calcY += lh;
         if(g_rollingPerf.totalTracked > 0) calcY += lh;
         calcY += lh;  // vol-regime line (always shown)
      }
      calcY += lh + 4;
      int totalH = calcY;
      if(!g_panelUserMoved)
      {
         int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         if(chartH > 100 && chartW > 100)
         {
            if(py + totalH > chartH - 10) { py = MathMax(0, chartH - totalH - 10); g_panelPosY = py; }
            if(px + pw > chartW - 10)     { px = MathMax(0, chartW - pw - 10);     g_panelPosX = px; }
         }
      }
      if(totalH != s_lastNoSigHeight) { DeleteObjectsByPrefix(PREFIX_PANEL); s_lastNoSigHeight = totalH; }
      CreateRectangleLabel(PREFIX_PANEL+"0_BG", px, py, pw, totalH, InpPanelBgColor, InpPanelBorderColor);
      CreateRectangleLabel(PREFIX_PANEL+"0_TB", px, py, pw, titleBarH, InpPanelBorderColor, InpPanelBorderColor);
      int cy = py + 3;
      CreateTextLabel(PREFIX_PANEL+"1_T", px+pad, cy,
         "RSI Advanced - Monitoring", InpPanelTitleColor, fs+1, true);
      cy += titleBarH + 2 - 3;
      CreateTextLabel(PREFIX_PANEL+"2_SYM", px+pad, cy,
         GetCleanSymbolName()+" | "+GetTimeframeString()+" | No active signal",
         InpPanelTextColor, fs-1, false);
      cy += lh;
      {
         int gmtOff2 = GetBrokerGMTOffset();
         datetime utcNow = TimeCurrent() - gmtOff2 * 3600;
         string gmtSign2 = (gmtOff2 >= 0) ? "+" : "";
         CreateTextLabel(PREFIX_PANEL+"2_TM", px+pad, cy,
            "Server: "+TimeToString(TimeCurrent(), TIME_MINUTES)+
            " | UTC: "+TimeToString(utcNow, TIME_MINUTES)+
            " (GMT"+gmtSign2+IntegerToString(gmtOff2)+")",
            InpPanelDimColor, fs-2, false);
         cy += lh;
      }
      if(hasMTF)
      {
         cy += 3;
         CreateTextLabel(PREFIX_PANEL+"M_T", px+pad, cy,
            "Multi-TF Signal Status", InpPanelTitleColor, fs-1, true);
         cy += lh;
         for(int t=0; t<g_mtfCount; t++)
         {
            color tfClr; string sigDir2;
            if(g_mtfData[t].trend == 1)       { tfClr=InpMTF_BullColor;   sigDir2="BUY  "; }
            else if(g_mtfData[t].trend == -1) { tfClr=InpMTF_BearColor;   sigDir2="SELL "; }
            else                              { tfClr=InpMTF_NeutralColor; sigDir2="WAIT "; }
            string tfName = g_mtfData[t].tfName;
            while(StringLen(tfName) < 4) tfName += " ";
            string caseInfo = "";
            if(g_mtfData[t].lastSignalCase > 0) caseInfo = " C"+IntegerToString(g_mtfData[t].lastSignalCase);
            double gv = g_mtfData[t].greenValue;
            string zone2 = "";
            if(gv > 68) zone2 = " OB"; else if(gv > 50) zone2 = " >>";
            else if(gv > 32) zone2 = " <<"; else zone2 = " OS";
            CreateTextLabel(PREFIX_PANEL+"M_"+IntegerToString(t), px+pad+3, cy,
               tfName+" "+sigDir2+g_mtfData[t].statusText+caseInfo+" ["+DoubleToString(gv,1)+"]"+zone2,
               tfClr, fs-2, false);
            cy += lh;
         }
         int ag = CalculateMTFAgreement();
         string agTxt; color agClr;
         if(ag > 50)       { agTxt="STRONG BULL";  agClr=InpMTF_BullColor; }
         else if(ag > 0)   { agTxt="WEAK BULL";    agClr=InpMTF_BullColor; }
         else if(ag < -50) { agTxt="STRONG BEAR";  agClr=InpMTF_BearColor; }
         else if(ag < 0)   { agTxt="WEAK BEAR";    agClr=InpMTF_BearColor; }
         else              { agTxt="MIXED";         agClr=InpMTF_NeutralColor; }
         CreateTextLabel(PREFIX_PANEL+"M_AG", px+pad, cy,
            agTxt+" ("+IntegerToString(ag)+"%)",
            agClr, fs-1, true);
         cy += lh;
      }
      if(hasV11)
      {
         cy += 3;
         CreateTextLabel(PREFIX_PANEL+"V_T", px+pad, cy,
            "Market Status", InpPanelTitleColor, fs-1, true);
         cy += lh;
         if(g_intermarket.isAvailable)
         {
            string interText = GetIntermarketDisplayText();
            color interClr = (g_intermarket.dxyTrend > 0.2) ? clrLime :
                             (g_intermarket.dxyTrend < -0.2) ? clrOrange : clrGray;
            CreateTextLabel(PREFIX_PANEL+"V_IM", px+pad+3, cy, interText, interClr, fs-2, false);
            cy += lh;
         }
         // Vol-regime display
         {
            color vrClr = clrGray;
            if(g_volRegime.regime == VOL_QUIET)         vrClr = clrLime;
            else if(g_volRegime.regime == VOL_EVENT)     vrClr = clrRed;
            else if(g_volRegime.regime == VOL_TRENDING)  vrClr = clrYellow;
            CreateTextLabel(PREFIX_PANEL+"V_VR", px+pad+3, cy,
               "Vol:"+g_volRegime.label+" (ATR:"+DoubleToString(g_volRegime.atrRatio, 2)+"x)",
               vrClr, fs-2, false);
            cy += lh;
         }
         if(g_outcomeCount > 0)
         {
            CreateTextLabel(PREFIX_PANEL+"V_SS", px+pad+3, cy,
               GetCurrentSessionDisplay(), InpPanelDimColor, fs-2, false);
            cy += lh;
         }
         if(g_walkForward.isSamples > 0 || g_walkForward.oosSamples > 0)
         {
            CreateTextLabel(PREFIX_PANEL+"V_WF", px+pad+3, cy,
               GetWalkForwardDisplay(), GetWalkForwardColor(), fs-2, false);
            cy += lh;
         }
         if(InpUseSpreadRegime)
         {
            string spreadText = GetSpreadDisplay();
            // [PERF-FIX P0-2] Use cached regime color instead of calling GetRegimeColor separately
            string regimeText = CheckRegimeStability();
            color spreadClr = GetSpreadColor();
            color regimeClr = g_cachedRegimeColor;
            color combinedClr = (spreadClr==clrRed||regimeClr==clrRed) ? clrRed :
                                (spreadClr==clrOrange||regimeClr==clrOrange) ? clrOrange : clrGray;
            CreateTextLabel(PREFIX_PANEL+"V_SR", px+pad+3, cy,
               spreadText+" | "+regimeText, combinedClr, fs-2, false);
            cy += lh;
         }
         if(g_rollingPerf.totalTracked > 0)
         {
            CreateTextLabel(PREFIX_PANEL+"V_RP", px+pad+3, cy,
               GetRollingPerfDisplay(), GetRollingPerfColor(), fs-2, false);
            cy += lh;
         }
      }
      CreateTextLabel(PREFIX_PANEL+"Z_F", px+pad, cy,
         "Waiting for signal...", InpPanelDimColor, fs-2, false);
      ChartRedraw();
      return;
   }

   // Track layout changes to avoid unnecessary delete/recreate
   static int  s_lastPanelHeight = 0;
   static int  s_lastSignalIndex = -1;
   static bool s_lastInvalidated = false;
   static bool s_lastSuppressZones = false;
   static bool s_lastHasProb = false;
   static bool s_lastHasMTF = false;
   static bool s_lastHasV11 = false;
   static int  s_lastMTFCount = 0;
   static int  s_lastVisibleZones = 0;

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
   static bool s_panelInvalidSticky = false;
   if(signalIndex != s_lastSignalIndex) s_panelInvalidSticky = false;
   bool rawInvalid = false;
   if(isBuy && curPrice <= sig.stopLoss) rawInvalid = true;
   if(!isBuy && curPrice >= sig.stopLoss) rawInvalid = true;
   bool isInvalidated = rawInvalid;
   if(s_panelInvalidSticky && !rawInvalid)
   {
      double margin = sig.atrValue * 0.1;
      if(isBuy && curPrice < sig.stopLoss + margin) isInvalidated = true;
      if(!isBuy && curPrice > sig.stopLoss - margin) isInvalidated = true;
   }
   s_panelInvalidSticky = isInvalidated;
   bool hasProb = (InpShowProbability && (g_currentProb.totalSamples >= GetMinSamplesForTimeframe() || g_currentProb.probTP1 > 0));
   bool hasMTF = (InpShowMTF && g_mtfCount > 0);
   bool hasZones = (InpEntryZoneCount >= 2 && g_validZoneCount >= 1 && !isInvalidated);
   int mtfAgree = 0;
   if(hasMTF) mtfAgree = CalculateMTFAgreement();
   TradeRecommendation rec;
   if(!isInvalidated)
   {
      rec = GetTradeRecommendation(
         sig.caseNumber, isBuy, g_currentProb.probTP1, g_currentProb.probSL,
         g_currentProb.totalSamples, mtfAgree, slDist, tp1Dist, sig.atrValue, sig.signalTime);
   }
   // V11: Suppress entry zones when recommendation is AVOID/WAIT/COUNTER_TREND
   bool suppressZones = false;
   if(!isInvalidated)
   {
      if(rec.level == REC_AVOID || rec.level == REC_COUNTER_TREND || rec.level == REC_WAIT)
         suppressZones = true;
   }
   int visibleZones = 0;
   if(hasZones)
   {
      for(int z = 0; z < 5; z++)
         if(g_entryZones[z].isValid) visibleZones++;
   }
   // V11: Check which advanced metrics have data
   bool hasV11Data = (g_intermarket.isAvailable ||
                      g_outcomeCount > 0 ||
                      g_walkForward.isSamples > 0 ||
                      InpUseSpreadRegime);

   // Detect layout change → need full redraw (delete stale objects)
   bool layoutChanged = false;
   if(signalIndex != s_lastSignalIndex)     layoutChanged = true;
   if(isInvalidated != s_lastInvalidated)   layoutChanged = true;
   if(suppressZones != s_lastSuppressZones) layoutChanged = true;
   if(hasProb != s_lastHasProb)             layoutChanged = true;
   if(hasMTF != s_lastHasMTF)               layoutChanged = true;
   if(hasV11Data != s_lastHasV11)           layoutChanged = true;
   if(g_mtfCount != s_lastMTFCount)         layoutChanged = true;
   if(visibleZones != s_lastVisibleZones)   layoutChanged = true;

   if(layoutChanged)
   {
      DeleteObjectsByPrefix(PREFIX_PANEL);
      s_lastSignalIndex   = signalIndex;
      s_lastInvalidated   = isInvalidated;
      s_lastSuppressZones = suppressZones;
      s_lastHasProb       = hasProb;
      s_lastHasMTF        = hasMTF;
      s_lastHasV11        = hasV11Data;
      s_lastMTFCount      = g_mtfCount;
      s_lastVisibleZones  = visibleZones;
   }

   // ============================================
   // PASS 1: Height
   // ============================================
   int calcY = 0;
   calcY += titleBarH + 2;
   calcY += lh;
   calcY += detailCount * (lh - 2) + 2;
   calcY += lh;
   calcY += lh;
   if(isStale) calcY += lh;
   if(isInvalidated) calcY += lh;
   calcY += 3;
   calcY += lh;
   calcY += lh;
   calcY += 3;
   calcY += lh;
   calcY += lh;
   if(hasZones && !suppressZones)
   {
      calcY += 3;
      calcY += lh;
      calcY += visibleZones * lh;
      calcY += lh;
   }
   else if(hasZones && suppressZones)
   {
      calcY += 3;
      calcY += lh;     // "Entry Zones: SUPPRESSED"
      calcY += lh;     // reason line
      calcY += lh;     // metrics line
   }
   if(hasProb)
   {
      calcY += 3;
      calcY += lh; calcY += lh; calcY += lh;
      calcY += lh; calcY += lh; calcY += lh; calcY += lh;
      calcY += lh; // time-decay line
      calcY += lh; // DQ metrics line
   }
   if(hasMTF)
   {
      calcY += 3;
      calcY += lh;
      calcY += g_mtfCount * lh;
      calcY += lh;
   }
   // V11 metrics - only count sections with data
   if(hasV11Data)
   {
      calcY += 3;
      calcY += lh;    // title
      if(g_intermarket.isAvailable) calcY += lh;
      if(g_outcomeCount > 0) calcY += lh;
      if(g_walkForward.isSamples > 0 || g_walkForward.oosSamples > 0) calcY += lh;
      if(InpUseSpreadRegime) calcY += lh;
      if(g_rollingPerf.totalTracked > 0) calcY += lh;
      calcY += lh;  // vol-regime line (always shown)
      // [GMT-FIX-A1] GMT warning line for H4+ timeframes
      // Note: Period() returns minutes via MQLCompat; PERIOD_H4 is enum 16388 in MT5.
      // Compare against 240 (minutes) for cross-platform compatibility.
      if(Period() >= TF_H4) calcY += lh;
   }
   calcY += lh + 4;
   int totalH = calcY;
   if(!g_panelUserMoved)
   {
      int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      if(chartH > 100 && chartW > 100)
      {
         if(py + totalH > chartH - 10) { py = MathMax(0, chartH - totalH - 10); g_panelPosY = py; }
         if(px + pw > chartW - 10)     { px = MathMax(0, chartW - pw - 10);     g_panelPosX = px; }
      }
   }
   // ============================================
   // PASS 2: Background
   // ============================================
   color borderClr = isInvalidated ? clrRed : InpPanelBorderColor;
   CreateRectangleLabel(PREFIX_PANEL+"0_BG", px, py, pw, totalH, InpPanelBgColor, borderClr);
   CreateRectangleLabel(PREFIX_PANEL+"0_TB", px, py, pw, titleBarH, InpPanelBorderColor, InpPanelBorderColor);
   // ============================================
   // PASS 3: Content
   // ============================================
   int cy = py + 3;
   //--- TITLE ---
   string titleText = "RSI Advanced - " + dir;
   color titleClr = InpPanelTitleColor;
   if(isInvalidated)
   {
      titleText += " SIGNAL [INVALID]";
      titleClr = clrRed;
   }
   else if(rec.level == REC_AVOID || rec.level == REC_COUNTER_TREND || rec.level == REC_WAIT)
   {
      titleText += " (No Edge)";
      titleClr = (rec.level == REC_WAIT) ? clrOrange : clrRed;
   }
   else
   {
      titleText += " SIGNAL";
      if(rec.level == REC_STRONG_ENTRY || rec.level == REC_ENTRY)
         titleClr = clrLime;
      else
         titleClr = clrYellow;
   }
   CreateTextLabel(PREFIX_PANEL+"1_T", px+pad, cy, titleText, titleClr, fs+1, true);
   cy += titleBarH + 2 - 3;
   //--- CASE ---
   CreateTextLabel(PREFIX_PANEL+"2_C", px+pad, cy,
      "Case "+IntegerToString(sig.caseNumber)+": "+GetCaseName(sig.caseNumber),
      dirClr, fs, true);
   cy += lh;
   //--- DETAIL ---
   for(int i=0; i<detailCount && i<3; i++)
   {
      CreateTextLabel(PREFIX_PANEL+"2_D"+IntegerToString(i), px+pad+3, cy,
         detailLines[i], InpPanelTextColor, fs-2, false);
      cy += lh - 2;
   }
   cy += 2;
   //--- INFO LINE ---
   int minsAgo = barsAgo * Period();
   string ageShort;
   if(minsAgo >= 60) ageShort = IntegerToString(minsAgo/60)+"h"+IntegerToString(minsAgo%60)+"m";
   else              ageShort = IntegerToString(minsAgo)+"m";
   CreateTextLabel(PREFIX_PANEL+"3_I", px+pad, cy,
      GetCleanSymbolName()+" | "+GetTimeframeString()+
      " | "+TimeToString(sig.signalTime, TIME_MINUTES)+" | Age: "+ageShort,
      InpPanelTextColor, fs-1, false);
   cy += lh;
   {
      int gmtOff2 = GetBrokerGMTOffset();
      datetime utcNow = TimeCurrent() - gmtOff2 * 3600;
      string gmtSign2 = (gmtOff2 >= 0) ? "+" : "";
      CreateTextLabel(PREFIX_PANEL+"3_TM", px+pad, cy,
         "Server: "+TimeToString(TimeCurrent(), TIME_MINUTES)+
         " | UTC: "+TimeToString(utcNow, TIME_MINUTES)+
         " (GMT"+gmtSign2+IntegerToString(gmtOff2)+")",
         InpPanelDimColor, fs-2, false);
      cy += lh;
   }
   //--- STALE ---
   if(isStale && !isInvalidated)
   {
      CreateTextLabel(PREFIX_PANEL+"3_ST", px+pad, cy,
         "!! STALE SIGNAL - Consider closing !!", clrRed, fs-1, true);
      cy += lh;
   }
   //--- INVALIDATED ---
   if(isInvalidated)
   {
      CreateTextLabel(PREFIX_PANEL+"3_INV", px+pad, cy,
         "!! PRICE BREACHED SL - Signal invalidated !!", clrRed, fs-1, true);
      cy += lh;
   }
   cy += 3;
   //--- RECOMMENDATION ---
   if(isInvalidated)
   {
      CreateTextLabel(PREFIX_PANEL+"4_R", px+pad, cy,
         ">> SL BREACHED - Do NOT trade <<", clrRed, fs+1, true);
      cy += lh;
      CreateTextLabel(PREFIX_PANEL+"4_RR", px+pad+3, cy,
         "Waiting for new signal...", clrOrange, fs-2, false);
      cy += lh;
   }
   else
   {
      CreateTextLabel(PREFIX_PANEL+"4_R", px+pad, cy,
         ">> "+rec.label+" <<  ["+IntegerToString(rec.confidence)+"/100]",
         rec.labelColor, fs+1, true);
      cy += lh;
      string riskReason = "";
      if(rec.suggestedRisk > 0) riskReason = "Risk:"+DoubleToString(rec.suggestedRisk,1)+"% | ";
      else riskReason = "Do not trade | ";
      riskReason += rec.reason;
      CreateTextLabel(PREFIX_PANEL+"4_RR", px+pad+3, cy, riskReason,
         rec.suggestedRisk > 0 ? InpPanelTextColor : clrOrange, fs-2, false);
      cy += lh;
   }
   cy += 3;
   //--- ATR + SL:TP ---
   CreateTextLabel(PREFIX_PANEL+"5_A", px+pad, cy,
      "ATR:"+DoubleToString(sig.atrValue,_Digits)+
      " | SL:"+DoubleToString(InpSLRatio,1)+
      " TP:"+DoubleToString(InpTPRatio,1)+"/"+
      DoubleToString(InpTPRatio*InpTP2Multiplier,1)+"/"+
      DoubleToString(InpTPRatio*InpTP3Multiplier,1),
      InpPanelDimColor, fs-2, false);
   cy += lh;
   //--- P/L + R:R ---
   color plClr = plDist >= 0 ? clrLime : clrRed;
   string plText = "P/L:"+FormatPL(plDist, slDist);
   if(isInvalidated) plText += " [SL HIT]";
   else if(isStale)  plText += " [STALE]";
   plText += "  R:R 1:"+DoubleToString(tp1R,1)+
             "|1:"+DoubleToString(tp2R,1)+
             "|1:"+DoubleToString(tp3R,1);
   CreateTextLabel(PREFIX_PANEL+"6_PL", px+pad, cy, plText, plClr, fs-1, true);
   cy += lh;
   //==========================================================
   // ENTRY ZONES
   //==========================================================
   if(hasZones && !suppressZones)
   {
      cy += 3;
      CreateTextLabel(PREFIX_PANEL+"EZ_T", px+pad, cy,
         "Entry Zones ("+IntegerToString(g_recommendedZoneCount)+
         " rec | Risk:"+DoubleToString(InpTotalRiskPercent,1)+"%)",
         InpPanelTitleColor, fs-1, true);
      cy += lh;
      double bestEV = -999;
      int bestZone = 0;
      for(int z = 0; z < 5; z++)
      {
         if(!g_entryZones[z].isValid) continue;
         if(g_entryZones[z].expectedValue > bestEV)
         { bestEV = g_entryZones[z].expectedValue; bestZone = z; }
         color zClr = GetZoneColor(z);
         if(!g_entryZones[z].isRecommended) zClr = InpPanelDimColor;
         string evStar = (g_entryZones[z].expectedValue > 0) ? " *" : "";
         string zLine = "Z"+IntegerToString(z+1)+" "+
            g_entryZones[z].zoneName+":"+DoubleToString(g_entryZones[z].price, _Digits)+
            " "+DoubleToString(g_entryZones[z].lotSize, 2)+"lot"+
            " R:R1:"+DoubleToString(g_entryZones[z].rrRatio, 1)+
            " Reach:"+DoubleToString(g_entryZones[z].probReach*100, 0)+"%"+
            " Win:"+DoubleToString(g_entryZones[z].probTP1, 0)+"%"+
            " EV:"+DoubleToString(g_entryZones[z].expectedValue, 2)+"R"+evStar;
         CreateTextLabel(PREFIX_PANEL+"EZ_"+IntegerToString(z), px+pad+3, cy, zLine, zClr, fs-2, false);
         cy += lh;
      }
      string bestText = "Best: Z"+IntegerToString(bestZone+1);
      if(bestEV > 0) bestText += " EV+"+DoubleToString(bestEV, 2)+"R";
      else bestText += " (no positive EV)";
      CreateTextLabel(PREFIX_PANEL+"EZ_B", px+pad, cy, bestText,
         bestEV > 0 ? clrLime : clrOrange, fs-2, true);
      cy += lh;
   }
   else if(hasZones && suppressZones)
   {
      cy += 3;
      CreateTextLabel(PREFIX_PANEL+"EZ_T", px+pad, cy,
         "Entry Zones: SUPPRESSED", clrGray, fs-1, true);
      cy += lh;
      CreateTextLabel(PREFIX_PANEL+"EZ_R1", px+pad+3, cy,
         "Score "+IntegerToString(rec.confidence)+"/100 below entry threshold (35)",
         clrGray, fs-2, false);
      cy += lh;
      string metLine = "Win:"+DoubleToString(g_currentProb.probTP1,1)+"%";
      double evCalc = 0;
      if(slDist > 0)
         evCalc = (g_currentProb.probTP1/100.0 * tp1Dist/slDist) - ((1.0 - g_currentProb.probTP1/100.0) * 1.0);
      metLine += " | EV:"+DoubleToString(evCalc,2)+"R";
      if(g_walkForward.oosSamples >= 3 && !g_walkForward.isRobust) metLine += " | WF overfit";
      if(g_spreadRegime.isExtreme) metLine += " | Spread extreme";
      else if(g_spreadRegime.isSpike) metLine += " | Spread spike";
      CreateTextLabel(PREFIX_PANEL+"EZ_R2", px+pad+3, cy,
         metLine, clrOrange, fs-2, false);
      cy += lh;
   }
   //==========================================================
   // PROBABILITY
   //==========================================================
   if(hasProb)
   {
      cy += 3;
      // Determine active TP (same logic as LineDrawing)
      int activeTP = 0;
      if(!g_tpHit[0])      activeTP = 1;
      else if(!g_tpHit[1]) activeTP = 2;
      else if(!g_tpHit[2]) activeTP = 3;

      color confClr = clrGray;
      string confTxt = GetConfidenceText(g_currentProb.totalSamples, g_currentProb.probTP1, confClr);
      string probTitle = "Prob [n="+IntegerToString(g_currentProb.totalSamples)+"]  "+confTxt;
      if(activeTP >= 2) probTitle += "  >>TP"+IntegerToString(activeTP);
      CreateTextLabel(PREFIX_PANEL+"P_T", px+pad, cy,
         probTitle, InpPanelTitleColor, fs-1, true);
      cy += lh;

      // Win/Loss: shift to active TP's conditional probability
      double winP = g_currentProb.probTP1, lossP = g_currentProb.probSL;
      double origWinP = g_currentProb.originalProbTP1;
      if(g_tpHit[0] && g_currentProb.samplesTP1 > 0)
      {
         // P(TP2|TP1 hit) = samplesTP2 / samplesTP1
         winP = (g_currentProb.samplesTP2 * 100.0) / g_currentProb.samplesTP1;
         origWinP = winP;
         lossP = 100.0 - winP;
         if(g_tpHit[1] && g_currentProb.samplesTP2 > 0)
         {
            winP = (g_currentProb.samplesTP3 * 100.0) / g_currentProb.samplesTP2;
            origWinP = winP;
            lossP = 100.0 - winP;
         }
      }
      color wlClr = winP >= lossP ? clrLime : clrOrange;
      string wlText;
      if(activeTP == 1 && g_currentProb.originalProbTP1 > 0 && g_currentProb.elapsedBars > 0)
         wlText = "Win:"+DoubleToString(g_currentProb.originalProbTP1,1)+
                  "%->"+DoubleToString(g_currentProb.probTP1,1)+"%  |  Loss:"+DoubleToString(g_currentProb.probSL,1)+"%";
      else
         wlText = "Win:"+DoubleToString(winP,1)+"%  |  Loss:"+DoubleToString(lossP,1)+"%";
      CreateTextLabel(PREFIX_PANEL+"P_WL", px+pad, cy, wlText, wlClr, fs, true);
      cy += lh;

      // TP1 line: show original (pre-decay) prob when HIT
      string tp1Txt; color tp1Clr;
      if(g_tpHit[0])
      {
         double tp1Show = (g_currentProb.originalProbTP1 > 0) ? g_currentProb.originalProbTP1 : g_currentProb.probTP1;
         tp1Txt = " TP1:HIT "+DoubleToString(tp1Show,1)+"%"
                 +"("+IntegerToString(g_currentProb.samplesTP1)+"/"+IntegerToString(g_currentProb.totalSamples)+")";
         tp1Clr = clrLime;
      }
      else
      {
         tp1Txt = " TP1:"+DoubleToString(g_currentProb.probTP1,1)+"%"+ProbBar(g_currentProb.probTP1)
                 +"("+IntegerToString(g_currentProb.samplesTP1)+"/"+IntegerToString(g_currentProb.totalSamples)+")";
         tp1Clr = InpTP1LineColor;
      }
      CreateTextLabel(PREFIX_PANEL+"P_1", px+pad, cy, tp1Txt, tp1Clr, fs-2, false);
      cy += lh;

      // TP2 line: conditional P(TP2|TP1) when TP1 hit
      string tp2Txt; color tp2Clr;
      if(g_tpHit[1])
      {
         double tp2Show = (g_currentProb.originalProbTP2 > 0) ? g_currentProb.originalProbTP2 : g_currentProb.probTP2;
         tp2Txt = " TP2:HIT "+DoubleToString(tp2Show,1)+"%"
                 +"("+IntegerToString(g_currentProb.samplesTP2)+"/"+IntegerToString(g_currentProb.totalSamples)+")";
         tp2Clr = clrLime;
      }
      else if(g_tpHit[0] && g_currentProb.samplesTP1 > 0)
      {
         double condTP2 = (g_currentProb.samplesTP2 * 100.0) / g_currentProb.samplesTP1;
         tp2Txt = " TP2:"+DoubleToString(condTP2,1)+"%"+ProbBar(condTP2)
                 +"("+IntegerToString(g_currentProb.samplesTP2)+"/"+IntegerToString(g_currentProb.samplesTP1)+") <<";
         tp2Clr = InpTP2LineColor;
      }
      else
      {
         tp2Txt = " TP2:"+DoubleToString(g_currentProb.probTP2,1)+"%"+ProbBar(g_currentProb.probTP2)
                 +"("+IntegerToString(g_currentProb.samplesTP2)+"/"+IntegerToString(g_currentProb.totalSamples)+")";
         tp2Clr = InpTP2LineColor;
      }
      CreateTextLabel(PREFIX_PANEL+"P_2", px+pad, cy, tp2Txt, tp2Clr, fs-2, false);
      cy += lh;

      // TP3 line: conditional P(TP3|TP2) when TP2 hit, or P(TP3|TP1) when only TP1 hit
      string tp3Txt; color tp3Clr;
      if(g_tpHit[2])
      {
         double tp3Show = (g_currentProb.originalProbTP3 > 0) ? g_currentProb.originalProbTP3 : g_currentProb.probTP3;
         tp3Txt = " TP3:HIT "+DoubleToString(tp3Show,1)+"%"
                 +"("+IntegerToString(g_currentProb.samplesTP3)+"/"+IntegerToString(g_currentProb.totalSamples)+")";
         tp3Clr = clrLime;
      }
      else if(g_tpHit[1] && g_currentProb.samplesTP2 > 0)
      {
         double condTP3 = (g_currentProb.samplesTP3 * 100.0) / g_currentProb.samplesTP2;
         tp3Txt = " TP3:"+DoubleToString(condTP3,1)+"%"+ProbBar(condTP3)
                 +"("+IntegerToString(g_currentProb.samplesTP3)+"/"+IntegerToString(g_currentProb.samplesTP2)+") <<";
         tp3Clr = InpTP3LineColor;
      }
      else if(g_tpHit[0] && g_currentProb.samplesTP1 > 0)
      {
         double condTP3 = (g_currentProb.samplesTP3 * 100.0) / g_currentProb.samplesTP1;
         tp3Txt = " TP3:"+DoubleToString(condTP3,1)+"%"+ProbBar(condTP3)
                 +"("+IntegerToString(g_currentProb.samplesTP3)+"/"+IntegerToString(g_currentProb.samplesTP1)+")";
         tp3Clr = InpTP3LineColor;
      }
      else
      {
         tp3Txt = " TP3:"+DoubleToString(g_currentProb.probTP3,1)+"%"+ProbBar(g_currentProb.probTP3)
                 +"("+IntegerToString(g_currentProb.samplesTP3)+"/"+IntegerToString(g_currentProb.totalSamples)+")";
         tp3Clr = InpTP3LineColor;
      }
      CreateTextLabel(PREFIX_PANEL+"P_3", px+pad, cy, tp3Txt, tp3Clr, fs-2, false);
      cy += lh;
      double edge = g_cachedEdge;
      string avgEdge = "";
      if(g_currentProb.avgBarsToTP1 > 0) avgEdge += "TP1~"+IntegerToString((int)g_currentProb.avgBarsToTP1)+"bars ";
      if(g_currentProb.avgBarsToSL > 0) avgEdge += "SL~"+IntegerToString((int)g_currentProb.avgBarsToSL)+"bars ";
      avgEdge += "Edge:"+DoubleToString(edge*100,1)+"%";
      CreateTextLabel(PREFIX_PANEL+"P_AE", px+pad, cy, " "+avgEdge, InpPanelDimColor, fs-2, false);
      cy += lh;

      // Data quality breakdown (V11.30)
      string dqLine = " T1:"+IntegerToString((int)MathRound(g_currentProb.nEffT1))
                     +"("+IntegerToString(g_currentProb.rawCountT1)+")"
                     +" T2:"+IntegerToString((int)MathRound(g_currentProb.nEffT2))
                     +"("+IntegerToString(g_currentProb.rawCountT2)+")"
                     +" T3:"+IntegerToString(g_currentProb.countT3)
                     +" Real:"+IntegerToString((int)g_currentProb.realPct)+"%"
                     +" Span:"+IntegerToString((int)g_currentProb.oldestDays)+"d";
      color dqClr = (g_currentProb.realPct >= 50) ? clrLime
                  : (g_currentProb.realPct >= 20) ? clrYellow
                  : clrOrange;
      CreateTextLabel(PREFIX_PANEL+"P_DQ", px+pad, cy, dqLine, dqClr, fs-2, false);
      cy += lh;

      // Time-decay survival line: shows elapsed bars vs avg and remaining edge %
      if(g_currentProb.elapsedBars > 0 && g_currentProb.survivalRatio < 1.0)
      {
         string decayLine = " Elapsed:"+IntegerToString(g_currentProb.elapsedBars)+"bars";
         double survPct = g_currentProb.survivalRatio * 100.0;
         string edgeLabel = suppressZones ? "Signal-life" : "Edge-left";
         decayLine += " | "+edgeLabel+":"+DoubleToString(survPct, 0)+"%";
         if(g_currentProb.expiresMinutes > 0)
         {
            if(g_currentProb.expiresMinutes >= 60)
               decayLine += " | Expires ~"+IntegerToString(g_currentProb.expiresMinutes/60)+"h"+IntegerToString(g_currentProb.expiresMinutes%60)+"m";
            else
               decayLine += " | Expires ~"+IntegerToString(g_currentProb.expiresMinutes)+"m";
         }
         else
            decayLine += " | EXPIRED";

         // Color: green = fresh, yellow = fading, orange = weak, red = expired
         color decayClr;
         if(survPct > 70)      decayClr = clrLime;
         else if(survPct > 40) decayClr = clrYellow;
         else if(survPct > 20) decayClr = clrOrange;
         else                  decayClr = clrRed;

         CreateTextLabel(PREFIX_PANEL+"P_TD", px+pad, cy, decayLine, decayClr, fs-2, false);
         cy += lh;
      }
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
   // MTF
   //==========================================================
   if(hasMTF)
   {
      cy += 3;
      CreateTextLabel(PREFIX_PANEL+"M_T", px+pad, cy,
         "Multi-TF Signal Status", InpPanelTitleColor, fs-1, true);
      cy += lh;
      for(int t=0; t<g_mtfCount; t++)
      {
         color tfClr; string sigDir2;
         if(g_mtfData[t].trend == 1)       { tfClr=InpMTF_BullColor;   sigDir2="BUY  "; }
         else if(g_mtfData[t].trend == -1) { tfClr=InpMTF_BearColor;   sigDir2="SELL "; }
         else                              { tfClr=InpMTF_NeutralColor; sigDir2="WAIT "; }
         string tfName = g_mtfData[t].tfName;
         while(StringLen(tfName) < 4) tfName += " ";
         string caseInfo = "";
         if(g_mtfData[t].lastSignalCase > 0) caseInfo = " C"+IntegerToString(g_mtfData[t].lastSignalCase);
         double gv = g_mtfData[t].greenValue;
         string zone2 = "";
         if(gv > 68) zone2 = " OB"; else if(gv > 50) zone2 = " >>";
         else if(gv > 32) zone2 = " <<"; else zone2 = " OS";
         CreateTextLabel(PREFIX_PANEL+"M_"+IntegerToString(t), px+pad+3, cy,
            tfName+" "+sigDir2+g_mtfData[t].statusText+caseInfo+" ["+DoubleToString(gv,1)+"]"+zone2,
            tfClr, fs-2, false);
         cy += lh;
      }
      // [PERF-FIX P0-2] Reuse mtfAgree from line 269 instead of calling CalculateMTFAgreement() again
      int ag = mtfAgree;
      string agTxt; color agClr;
      if(ag > 50)       { agTxt="STRONG BULL";  agClr=InpMTF_BullColor; }
      else if(ag > 0)   { agTxt="WEAK BULL";    agClr=InpMTF_BullColor; }
      else if(ag < -50) { agTxt="STRONG BEAR";  agClr=InpMTF_BearColor; }
      else if(ag < 0)   { agTxt="WEAK BEAR";    agClr=InpMTF_BearColor; }
      else              { agTxt="MIXED";         agClr=InpMTF_NeutralColor; }
      int agreeCount = 0;
      for(int t=0; t<g_mtfCount; t++)
      {
         if(isBuy && g_mtfData[t].trend == 1) agreeCount++;
         if(!isBuy && g_mtfData[t].trend == -1) agreeCount++;
      }
      string alignTxt = "";
      if((isBuy && ag>0)||(!isBuy && ag<0))
         alignTxt = IntegerToString(agreeCount)+"/"+IntegerToString(g_mtfCount)+" TFs ALIGNED";
      else if((isBuy && ag<0)||(!isBuy && ag>0))
         alignTxt = IntegerToString(g_mtfCount-agreeCount)+"/"+IntegerToString(g_mtfCount)+" TFs AGAINST";
      else
         alignTxt = IntegerToString(agreeCount)+"/"+IntegerToString(g_mtfCount)+" TFs NEUTRAL";
      CreateTextLabel(PREFIX_PANEL+"M_AG", px+pad, cy,
         agTxt+" ("+IntegerToString(ag)+"%) "+alignTxt,
         agClr, fs-1, true);
      cy += lh;
   }
   //==========================================================
   // V11: ADVANCED METRICS (auto-hide empty sections)
   //==========================================================
   if(hasV11Data)
   {
      cy += 3;
      CreateTextLabel(PREFIX_PANEL+"V_T", px+pad, cy,
         "Advanced Metrics", InpPanelTitleColor, fs-1, true);
      cy += lh;
      if(g_intermarket.isAvailable)
      {
         string interText = GetIntermarketDisplayText();
         color interClr = GetIntermarketColor(isBuy);
         CreateTextLabel(PREFIX_PANEL+"V_IM", px+pad+3, cy, interText, interClr, fs-2, false);
         cy += lh;
      }
      // Vol-regime display
      {
         color vrClr = clrGray;
         if(g_volRegime.regime == VOL_QUIET)         vrClr = clrLime;
         else if(g_volRegime.regime == VOL_EVENT)     vrClr = clrRed;
         else if(g_volRegime.regime == VOL_TRENDING)  vrClr = clrYellow;
         CreateTextLabel(PREFIX_PANEL+"V_VR", px+pad+3, cy,
            "Vol:"+g_volRegime.label+" (ATR:"+DoubleToString(g_volRegime.atrRatio, 2)+"x)",
            vrClr, fs-2, false);
         cy += lh;
      }
      if(g_outcomeCount > 0)
      {
         string sesText = GetCurrentSessionDisplay();
         CreateTextLabel(PREFIX_PANEL+"V_SS", px+pad+3, cy, sesText, InpPanelDimColor, fs-2, false);
         cy += lh;
      }
      if(g_walkForward.isSamples > 0 || g_walkForward.oosSamples > 0)
      {
         string wfText = GetWalkForwardDisplay();
         color wfClr = GetWalkForwardColor();
         CreateTextLabel(PREFIX_PANEL+"V_WF", px+pad+3, cy, wfText, wfClr, fs-2, false);
         cy += lh;
      }
      if(InpUseSpreadRegime)
      {
         string spreadText = GetSpreadDisplay();
         color spreadClr = GetSpreadColor();
         // [PERF-FIX P0-2] CheckRegimeStability caches result; GetRegimeColor uses cached color.
         // Single call gets both text and color without re-computing 100 iATR.
         string regimeText = CheckRegimeStability();
         color regimeClr = g_cachedRegimeColor;
         color combinedClr = (spreadClr==clrRed||regimeClr==clrRed) ? clrRed :
                             (spreadClr==clrOrange||regimeClr==clrOrange) ? clrOrange : clrGray;
         CreateTextLabel(PREFIX_PANEL+"V_SR", px+pad+3, cy,
            spreadText+" | "+regimeText, combinedClr, fs-2, false);
         cy += lh;
      }
      // [GMT-FIX-A1] Broker GMT offset + normalization status for H4+ timeframes
      // Orange = candle boundaries shifted (signals may differ across brokers)
      // Lime = normalization active (RSI computed on GMT+0-aligned H4 candles)
      // [DQ] = data quality warning (Bayesian/Session guards activated)
      if(Period() >= TF_H4)
      {
         int gmtOff = GetBrokerGMTOffset();
         string gmtText = "Broker:GMT" + ((gmtOff >= 0) ? "+" : "") + IntegerToString(gmtOff);
         color gmtClr = clrGray;
         if(g_gmtNormActive && Period() == TF_H4)
         {
            if(g_normRSICount >= NORM_RSI_MIN_CONVERGE)
            {
               gmtClr = clrLime;
               gmtText += " | H4 Normalized";
            }
            else
            {
               gmtClr = clrYellow;
               gmtText += " | H4 Norm(loading " + IntegerToString(g_normH4Count) + "/" +
                          IntegerToString(NORM_RSI_MIN_CONVERGE) + ")";
            }
         }
         else if(g_gmtNormActive && Period() == TF_D1)
         {
            if(g_normD1RSICount >= NORM_D1_MIN_CONVERGE)
            {
               gmtClr = clrLime;
               gmtText += " | D1 Normalized";
            }
            else
            {
               gmtClr = clrYellow;
               gmtText += " | D1 Norm(loading " + IntegerToString(g_normD1Count) + "/" +
                          IntegerToString(NORM_D1_MIN_CONVERGE) + ")";
            }
         }
         else if(gmtOff != 0)
         {
            gmtClr = clrOrange;
            gmtText += " | H4 SHIFTED " + IntegerToString(MathAbs(gmtOff)) + "h";
         }
         if(g_gmtDataQualityWarn)
            gmtText += " [DQ]";
         CreateTextLabel(PREFIX_PANEL+"V_GMT", px+pad+3, cy, gmtText, gmtClr, fs-2, false);
         cy += lh;
      }
      if(g_rollingPerf.totalTracked > 0)
      {
         string rpText = GetRollingPerfDisplay();
         color rpClr = GetRollingPerfColor();
         CreateTextLabel(PREFIX_PANEL+"V_RP", px+pad+3, cy, rpText, rpClr, fs-2, false);
         cy += lh;
      }
   }
   //--- FOOTER ---
   CreateTextLabel(PREFIX_PANEL+"Z_F", px+pad, cy,
      "Drag title to move | Click arrow", InpPanelDimColor, fs-2, false);
   ChartRedraw();
}
#endif