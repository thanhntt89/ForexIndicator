//+------------------------------------------------------------------+
//|                                            PanelDrawing.mqh       |
//|                         QuantEdge - Info Panel Drawing         |
//+------------------------------------------------------------------+
#ifndef QE_PANELDRAWING_MQH
#define QE_PANELDRAWING_MQH
#include "../Core/Config.mqh"
#include "../Core/Structs.mqh"
#include "../Core/Globals.mqh"
#include "../Core/MathUtils.mqh"
#include "../Signal/SignalCases.mqh"
#include "../Engine/MTFEngine.mqh"
#include "../Analysis/Normalize.mqh"
#include "../Engine/SLTP.mqh"
#include "../Analysis/IntermarketAnalysis.mqh"
#include "../Analysis/SessionStatistics.mqh"
#include "../Engine/WalkForward.mqh"
#include "../Analysis/ADXAnalysis.mqh"
#include "../Analysis/MACDAnalysis.mqh"
#include "../Analysis/US10YAnalysis.mqh"
#include "../Analysis/EconCalendar.mqh"
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
//| Trade Decision Summary — one line, trader reads it and knows      |
//| whether to enter. hasSig=false draws the neutral placeholder.     |
//+------------------------------------------------------------------+
void DrawTDSLine(int px,int pad,int fs,int &cy,bool hasSig,const SignalData &sig,
                  const TradeRecommendation &rec)
{
   if(!InpShowTDS) return;
   if(!hasSig)
   {
      CreateTextLabel(PREFIX_PANEL+"TDS", px+pad, cy, "-- No Active Signal --", clrGray, fs, true);
      cy += fs+6;
      return;
   }
   string dirTxt = sig.isBuySignal ? "BUY" : "SELL";
   double entry = (g_entryZones[0].isValid) ? g_entryZones[0].price : sig.entryPrice;
   color tdsClr = clrGray;
   if(rec.level == REC_STRONG_ENTRY || rec.level == REC_ENTRY)        tdsClr = clrLime;
   else if(rec.level == REC_CAUTION_ENTRY)                            tdsClr = clrYellow;
   else if(rec.level == REC_WAIT)                                     tdsClr = clrOrange;
   else if(rec.level == REC_AVOID || rec.level == REC_COUNTER_TREND)  tdsClr = clrRed;
   string tdsText = dirTxt+" "+DoubleToString(g_positionSize.recommendedLot,2)+" lot @ "+
      DoubleToString(entry,_Digits)+" | "+DoubleToString(g_currentProb.probTP1,0)+"% TP1 | EV "+
      (rec.ev>=0?"+":"")+DoubleToString(rec.ev,1)+"R | Risk "+DoubleToString(g_positionSize.adjustedRiskPct,1)+
      "% -> "+rec.label;
   int tdsFs = fs - 1;   // TDS line is the longest on the panel — shrink to keep it inside panel width
   CreateTextLabel(PREFIX_PANEL+"TDS", px+pad, cy, tdsText, tdsClr, tdsFs, true);
   cy += tdsFs+6;
}
//+------------------------------------------------------------------+
//| Quick Attribution Bar — compact 1-line probability waterfall,     |
//| same source data as DrawExplainPanel() but summarized to 5 steps. |
//+------------------------------------------------------------------+
void DrawAttributionBar(int px,int pad,int fs,int &cy)
{
   if(!InpShowAttribution) return;
   ExplainData e = g_explainData;
   double dMTF   = e.probAfterMTF   - e.probAfterBase;
   double dInter = e.probAfterInter - e.probAfterMTF;
   double dVol   = e.probAfterMktSt - e.probAfterInter;
   double dBrier = e.probAfterBrier - e.probAfterMktSt;
   double dDecay = e.probFinal      - e.probAfterBrier;
   string attrText = "Edge "+DoubleToString(e.probAfterBase,0)+"%"+
      " -> MTF "+(dMTF>=0?"+":"")+DoubleToString(dMTF,0)+"%"+
      " -> Inter "+(dInter>=0?"+":"")+DoubleToString(dInter,0)+"%"+
      " -> Vol "+(dVol>=0?"+":"")+DoubleToString(dVol,0)+"%"+
      " -> Brier "+(dBrier>=0?"+":"")+DoubleToString(dBrier,0)+"%"+
      " -> Decay "+(dDecay>=0?"+":"")+DoubleToString(dDecay,0)+"%"+
      " = "+DoubleToString(e.probFinal,0)+"%";
   CreateTextLabel(PREFIX_PANEL+"ATTR", px+pad, cy, attrText, InpPanelDimColor, fs-2, false);
   cy += fs+6;
}
//+------------------------------------------------------------------+
//| Confidence Meter — visual rectangle bar replacing text-art.       |
//+------------------------------------------------------------------+
void DrawConfidenceMeter(int px,int pad,int y,int width,int confidence)
{
   color fillClr = clrRed;
   if(confidence >= 70)      fillClr = clrLime;
   else if(confidence >= 50) fillClr = clrYellow;
   else if(confidence >= 30) fillClr = clrOrange;
   int fillW = (int)MathRound(width * MathMax(0,MathMin(100,confidence)) / 100.0);
   CreateRectangleLabel(PREFIX_PANEL+"CONF_BG",   px+pad, y, width, 14, clrDarkSlateGray, clrDarkSlateGray);
   CreateRectangleLabel(PREFIX_PANEL+"CONF_FILL", px+pad, y, fillW, 14, fillClr, fillClr);
   CreateTextLabel(PREFIX_PANEL+"CONF_TXT", px+pad+width+6, y-2,
      IntegerToString(confidence)+"/100", InpPanelTextColor, 8, false);
}
//+------------------------------------------------------------------+
//| Risk Summary — account state + risk budget + suggested size.      |
//| compact=true renders the 2-line Manual-panel form.                |
//+------------------------------------------------------------------+
void DrawRiskSummary(int px,int pad,int fs,int &cy,bool compact)
{
   if(!InpShowRiskSummary || IsBacktestMode()) return;
   int lh = fs+6;
   int    cbLvl  = g_portfolioRisk.cbLevel;
   string cbTag  = "GREEN"; color cbClr = clrLime;
   if(cbLvl == 1)      { cbTag = "YELLOW"; cbClr = clrYellow; }
   else if(cbLvl == 2) { cbTag = "ORANGE"; cbClr = clrOrange; }
   else if(cbLvl == 3) { cbTag = "RED";    cbClr = clrRed;    }
   double budgetLeft = InpMaxDailyRiskPct - g_portfolioRisk.dailyDrawdownPct;

   if(!compact)
   {
      double bal = AccountBalance();
      CreateTextLabel(PREFIX_PANEL+"RISK1", px+pad+3, cy,
         "Account: $"+DoubleToString(bal,2)+" | Today: "+
         (g_portfolioRisk.dailyPnLPips>=0?"+":"")+DoubleToString(g_portfolioRisk.dailyPnLPips,1)+" pips",
         InpPanelTextColor, fs-2, false);
      cy += lh;

      string rk2 = "Risk Budget: "+DoubleToString(budgetLeft,2)+"% remaining | Circuit: "+cbTag;
      if(g_portfolioRisk.circuitBreakerActive)
         rk2 = "CIRCUIT BREAKER - signals blocked [RED]";
      CreateTextLabel(PREFIX_PANEL+"RISK2", px+pad+3, cy, rk2, cbClr, fs-2, false);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"RISK3", px+pad+3, cy,
         "Suggested: "+DoubleToString(g_positionSize.recommendedLot,2)+" lot ("+
         DoubleToString(g_positionSize.adjustedRiskPct,1)+"% risk) | Kelly: "+
         DoubleToString(g_positionSize.kellyPct,0)+"%",
         InpPanelTextColor, fs-2, false);
      cy += lh;
   }
   else
   {
      double bal = AccountBalance();
      CreateTextLabel(PREFIX_PANEL+"RISK1", px+pad+3, cy,
         "$"+DoubleToString(bal,0)+" | Today "+
         (g_portfolioRisk.dailyPnLPips>=0?"+":"")+DoubleToString(g_portfolioRisk.dailyPnLPips,0)+
         "pips | Budget "+DoubleToString(budgetLeft,1)+"% | Circuit "+
         (g_portfolioRisk.circuitBreakerActive?"BLOCKED":cbTag),
         cbClr, fs-2, false);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"RISK2", px+pad+3, cy,
         DoubleToString(g_positionSize.recommendedLot,2)+" lot ("+
         DoubleToString(g_positionSize.adjustedRiskPct,1)+"%) | Kelly: "+
         DoubleToString(g_positionSize.kellyPct,0)+"%",
         InpPanelTextColor, fs-2, false);
      cy += lh;
   }
}

//+------------------------------------------------------------------+
//| Sprint 6: Virtual trade performance calculation + panel display   |
//+------------------------------------------------------------------+
VirtualPerfMetrics CalculateVirtualPerf()
{
   VirtualPerfMetrics m;
   ZeroMemory(m);

   double grossProfit = 0, grossLoss = 0;
   double returns[];
   int    retCount = 0;
   int    mktWins = 0, mktTotal = 0, pbWins = 0, pbTotal = 0;
   double cumPips = 0, peakPips = 0, maxDD = 0;
   double sumWinRR = 0;

   for(int i = 0; i < g_vpCount; i++)
   {
      if(g_virtualPositions[i].signalTime == 0)   continue;
      if(g_virtualPositions[i].finalOutcome == 0)  continue;
      if(!g_virtualPositions[i].isActivated)       continue;

      double slDist = MathAbs(g_virtualPositions[i].entryPrice - g_virtualPositions[i].stopLoss);
      if(slDist <= 0) continue;

      m.totalTrades++;

      double pnl;
      if(g_virtualPositions[i].isBuy)
         pnl = g_virtualPositions[i].closePrice - g_virtualPositions[i].entryPrice;
      else
         pnl = g_virtualPositions[i].entryPrice - g_virtualPositions[i].closePrice;

      double rReturn = pnl / slDist;

      bool isWin = (pnl > 0);
      if(isWin)
      {
         m.wins++;
         grossProfit += pnl;
         sumWinRR += MathAbs(g_virtualPositions[i].takeProfit1 - g_virtualPositions[i].entryPrice) / slDist;
      }
      else
      {
         m.losses++;
         grossLoss += MathAbs(pnl);
      }

      bool isMkt = (g_virtualPositions[i].zoneIndex == 0);
      if(isMkt) { mktTotal++; if(isWin) mktWins++; }
      else      { pbTotal++;  if(isWin) pbWins++;  }

      ArrayResize(returns, retCount + 1, 32);
      returns[retCount] = rReturn;
      retCount++;

      cumPips += pnl;
      if(cumPips > peakPips) peakPips = cumPips;
      double dd = peakPips - cumPips;
      if(dd > maxDD) maxDD = dd;
   }

   if(m.totalTrades > 0)
      m.winRate = (double)m.wins / m.totalTrades * 100.0;
   m.profitFactor = (grossLoss > 0) ? grossProfit / grossLoss : 0;
   if(peakPips > 0)
      m.maxDrawdownPct = maxDD / peakPips * 100.0;
   else if(maxDD > 0)
      m.maxDrawdownPct = 100.0;
   else
      m.maxDrawdownPct = 0;
   m.avgRR = (m.wins > 0) ? sumWinRR / m.wins : 0;
   m.marketWinRate  = (mktTotal > 0) ? (double)mktWins / mktTotal * 100.0 : 0;
   m.pullbackWinRate = (pbTotal > 0) ? (double)pbWins / pbTotal * 100.0 : 0;

   if(retCount > 1)
   {
      double sumR = 0, sumR2 = 0, sumNeg2 = 0;
      for(int j = 0; j < retCount; j++) sumR += returns[j];
      double meanR = sumR / retCount;
      for(int j = 0; j < retCount; j++)
      {
         double diff = returns[j] - meanR;
         sumR2 += diff * diff;
         if(returns[j] < 0) sumNeg2 += returns[j] * returns[j];
      }
      double stdR = MathSqrt(sumR2 / (retCount - 1));
      double downDev = MathSqrt(sumNeg2 / retCount);
      m.sharpe  = (stdR > 0) ? meanR / stdR : 0;
      m.sortino = (downDev > 0) ? meanR / downDev : 0;
      m.evPerTradeR = meanR;
   }

   return(m);
}

void DrawPerfReport(int px, int pad, int fs, int &cy, bool compact)
{
   if(!InpShowVirtualPerf || IsBacktestMode()) return;
   if(g_vpCount == 0) return;

   VirtualPerfMetrics pm = CalculateVirtualPerf();
   if(pm.totalTrades == 0) return;

   int lh = fs + 6;

   if(!compact)
   {
      CreateTextLabel(PREFIX_PANEL+"VP_H", px+pad+3, cy,
         "--- Virtual Perf ---", InpPanelDimColor, fs-2, false);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"VP1", px+pad+3, cy,
         "Trades: "+IntegerToString(pm.totalTrades)+
         " ("+IntegerToString(pm.wins)+"W "+IntegerToString(pm.losses)+"L)"
         +" | WR: "+DoubleToString(pm.winRate,1)+"%",
         InpPanelTextColor, fs-2, false);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"VP2", px+pad+3, cy,
         "PF: "+DoubleToString(pm.profitFactor,2)+
         " | Sharpe: "+DoubleToString(pm.sharpe,2)+
         " | Sortino: "+DoubleToString(pm.sortino,2),
         InpPanelTextColor, fs-2, false);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"VP3", px+pad+3, cy,
         "MaxDD: -"+DoubleToString(pm.maxDrawdownPct,1)+"%"+
         " | Avg RR: "+DoubleToString(pm.avgRR,1)+
         " | EV: "+(pm.evPerTradeR>=0?"+":"")+DoubleToString(pm.evPerTradeR,2)+"R",
         InpPanelTextColor, fs-2, false);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"VP4", px+pad+3, cy,
         "Market: "+DoubleToString(pm.marketWinRate,0)+"% WR"+
         " | Pullback: "+DoubleToString(pm.pullbackWinRate,0)+"% WR",
         InpPanelTextColor, fs-2, false);
      cy += lh;
   }
   else
   {
      CreateTextLabel(PREFIX_PANEL+"VP1", px+pad+3, cy,
         IntegerToString(pm.totalTrades)+" trades "+
         DoubleToString(pm.winRate,0)+"%WR PF:"+DoubleToString(pm.profitFactor,2)+
         " DD:-"+DoubleToString(pm.maxDrawdownPct,1)+"%",
         InpPanelTextColor, fs-2, false);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"VP2", px+pad+3, cy,
         "Mkt:"+DoubleToString(pm.marketWinRate,0)+"%"+
         " PB:"+DoubleToString(pm.pullbackWinRate,0)+"%"+
         " EV:"+(pm.evPerTradeR>=0?"+":"")+DoubleToString(pm.evPerTradeR,2)+"R",
         InpPanelTextColor, fs-2, false);
      cy += lh;
   }
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
                     InpUseSpreadRegime ||
                     InpUseADXFilter ||
                     InpUseMACDFilter ||
                     g_us10y.isAvailable ||
                     InpUseEconCalendar);
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
         if(InpUseADXFilter) calcY += lh;
         if(InpUseMACDFilter) calcY += lh;
         if(g_us10y.isAvailable) calcY += lh;
         if(InpUseEconCalendar) calcY += lh;
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
         "QuantEdge - Monitoring", InpPanelTitleColor, fs+1, true);
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
         if(InpUseADXFilter)
         {
            CreateTextLabel(PREFIX_PANEL+"V_ADX", px+pad+3, cy,
               GetADXDisplayText(1), GetADXDisplayColor(1), fs-2, false);
            cy += lh;
         }
         if(InpUseMACDFilter)
         {
            CreateTextLabel(PREFIX_PANEL+"V_MACD", px+pad+3, cy,
               GetMACDDisplayText(1), GetMACDDisplayColor(1), fs-2, false);
            cy += lh;
         }
         if(g_us10y.isAvailable)
         {
            CreateTextLabel(PREFIX_PANEL+"V_US10Y", px+pad+3, cy,
               GetUS10YDisplayText(), GetUS10YColor(true), fs-2, false);
            cy += lh;
         }
         if(InpUseEconCalendar)
         {
            CreateTextLabel(PREFIX_PANEL+"V_ECAL", px+pad+3, cy,
               GetEconCalendarDisplayText(), GetEconCalendarDisplayColor(), fs-2, false);
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
      // [CASE8-FIX2] Confidence + WAIT gate from real-signal nEff (T1+T2),
      // excluding Tier-3 deep-scan bars that inflate the pooled sample count.
      int recN = (int)MathRound(g_currentProb.nEffT1 + g_currentProb.nEffT2);
      rec = GetTradeRecommendation(
         sig.caseNumber, isBuy, g_currentProb.probTP1, g_currentProb.probSL,
         recN, mtfAgree, slDist, tp1Dist, sig.atrValue, sig.signalTime);
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
                      InpUseSpreadRegime ||
                      InpUseADXFilter ||
                      InpUseMACDFilter ||
                      g_us10y.isAvailable ||
                      InpUseEconCalendar);

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
   if(InpShowTDS)                        calcY += lh;  // TDS line (or invalidated placeholder)
   if(InpShowAttribution && !isInvalidated) calcY += lh;  // Attribution bar (hidden when invalidated)
   calcY += lh;
   calcY += detailCount * (lh - 2) + 2;
   calcY += lh;
   calcY += lh;
   if(isStale) calcY += lh;
   if(isInvalidated) calcY += lh;
   calcY += 3;
   calcY += lh;
   calcY += lh;
   if(!isInvalidated) calcY += lh;  // confidence meter row
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
      calcY += lh; // Kelly + P-value line
      calcY += lh; // Angle IC diagnostic line
   }
   // Position Sizing section
   if(InpUseKellyLot || g_outcomeCount > 0)
   {
      calcY += 3;
      calcY += lh;  // title
      if(InpUseKellyLot) calcY += lh;  // Kelly | Vol | Brier
      if(InpUseKellyLot) calcY += lh;  // Risk% -> Lot
      if(g_outcomeCount > 0) calcY += lh;  // W/L EV
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
      if(InpUseADXFilter) calcY += lh;
      if(InpUseMACDFilter) calcY += lh;
      if(g_us10y.isAvailable) calcY += lh;
      if(InpUseEconCalendar) calcY += lh;
      calcY += lh;  // vol-regime line (always shown)
      // [GMT-FIX-A1] GMT warning line for H4+ timeframes
      // Note: Period() returns minutes via MQLCompat; PERIOD_H4 is enum 16388 in MT5.
      // Compare against 240 (minutes) for cross-platform compatibility.
      if(Period() >= TF_H4) calcY += lh;
      if(g_brierMetrics.samples >= 5) calcY += lh;
      if(InpShowRiskSummary && !IsBacktestMode()) calcY += lh * 3;  // risk summary (3 lines, full mode)
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
   string titleText = "QuantEdge - " + dir;
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
   // [STALE-FIX] Mark a signal that cannot be taken right now (circuit breaker /
   // risk limits) so a blocked signal is never read as a fresh actionable entry.
   if(!isInvalidated && !CanTakeNewSignal())
   {
      titleText += " [BLOCKED]";
      titleClr = clrOrange;
   }
   CreateTextLabel(PREFIX_PANEL+"1_T", px+pad, cy, titleText, titleClr, fs+1, true);
   cy += titleBarH + 2 - 3;
   //--- TDS + ATTRIBUTION ---
   DrawTDSLine(px, pad, fs, cy, !isInvalidated, sig, rec);
   if(!isInvalidated) DrawAttributionBar(px, pad, fs, cy);
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
         ">> "+rec.label+" <<",
         rec.labelColor, fs+1, true);
      cy += lh;
      DrawConfidenceMeter(px, pad, cy, 80, rec.confidence);
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
   string sltpMode = (InpSLTPMode == SLTP_EV_OPTIMIZED) ? "[EV-OPT]" :
                      (InpSLTPMode == SLTP_DYNAMIC) ? "[DYN]" : "[FIX]";
   CreateTextLabel(PREFIX_PANEL+"5_A", px+pad, cy,
      "ATR:"+DoubleToString(sig.atrValue,_Digits)+
      " "+sltpMode+
      " SL:"+DoubleToString(GetDynamicSLRatio(),1)+
      " TP:"+DoubleToString(GetDynamicTP1Ratio(),1)+"/"+
      DoubleToString(GetDynamicTP2Ratio(),1)+"/"+
      DoubleToString(GetDynamicTP3Ratio(),1),
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
      // [CASE8-FIX3] Headline n + confidence from REAL-signal nEff (T1+T2), not the
      // Tier-3-inflated pool. Show "real/pool" so a thin case (e.g. Case 8) cannot
      // look data-rich. Confidence text already gates LOW DATA on n<minSamples.
      int realN = (int)MathRound(g_currentProb.nEffT1 + g_currentProb.nEffT2);
      string confTxt = GetConfidenceText(realN, g_currentProb.probTP1, confClr);
      string probTitle = "Prob [n="+IntegerToString(realN)+"/"+IntegerToString(g_currentProb.totalSamples)+"]  "+confTxt;
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

      // Kelly fraction + Permutation p-value
      string klLine = " Kelly:"+DoubleToString(g_walkForward.kellyFraction,1)+"%";
      if(g_walkForward.permPValue < 1.0)
         klLine += " | P-val:"+DoubleToString(g_walkForward.permPValue,3);
      if(g_walkForward.rollingCount >= 2)
         klLine += " | MedR:"+DoubleToString(g_walkForward.medianRatio,2);
      color klClr = clrOrange;
      if(g_walkForward.kellyFraction > 0 && g_walkForward.permPValue < 0.05)
         klClr = clrLime;
      else if(g_walkForward.permPValue < 0.10)
         klClr = clrYellow;
      CreateTextLabel(PREFIX_PANEL+"P_KL", px+pad, cy, klLine, klClr, fs-2, false);
      cy += lh;

      // [V11.36] Angle Information Coefficient (IC) diagnostic. Shows whether the
      // crossover angleStrength actually predicts outcomes on THIS symbol/TF, using
      // the SAME gate ProbabilityEngine applies to the angle edge (icSamples>=20 &&
      // infoCoeff>=0.05). Bands (WalkForward.mqh): IC>0.10 strong, 0.05-0.10 weak,
      // <0.05 noise, <0 inverse. When "off"/"n/a" the angle is only a detection
      // filter and adds NOTHING to the displayed confidence.
      {
         int    icN = g_walkForward.icSamples;
         double icV = g_walkForward.infoCoeff;
         string icLine = "";
         color  icClr  = InpPanelDimColor;
         if(icN < 10)
         {
            icLine = " AngIC: n/a (building, need 20+ resolved)";
            icClr  = InpPanelDimColor;
         }
         else
         {
            string icTag;
            if(icN < 20)         icTag = " (n<20, not applied)";
            else if(icV < 0.0)   icTag = " INVERSE!";
            else if(icV >= 0.05) icTag = " ON";
            else                 icTag = " off (noise)";
            icLine = " AngIC:" + DoubleToString(icV, 2)
                   + " n=" + IntegerToString(icN) + icTag;
            if(icN < 20)         icClr = InpPanelDimColor;
            else if(icV < 0.0)   icClr = clrOrange;
            else if(icV >= 0.10) icClr = clrLime;
            else if(icV >= 0.05) icClr = clrYellow;
            else                 icClr = InpPanelDimColor;
         }
         CreateTextLabel(PREFIX_PANEL+"P_IC", px+pad, cy, icLine, icClr, fs-2, false);
         cy += lh;
      }

      // XGBoost integration line (V12)
      if(InpProbMode != PROB_CALIBRATION)
      {
         string xLine = "";
         color  xClr  = InpPanelDimColor;

         if(g_currentProb.xgbProbTP1 <= 0 && !g_xgbLoaded)
         {
            xLine = " XGB: -- [no model]";
            xClr  = InpPanelDimColor;
         }
         else if(g_currentProb.xgbActive)
         {
            xLine = " XGB:" + DoubleToString(g_currentProb.xgbProbTP1, 1) + "%"
                  + " [w=" + DoubleToString(g_currentProb.xgbWeight, 2) + "]"
                  + " Brier:" + DoubleToString(g_xgbBrierScore, 3);
            xClr  = clrLime;
         }
         else if(g_xgbBrierSamples < MIN_XGB_BRIER_SAMPLES)
         {
            xLine = " XGB:" + DoubleToString(g_currentProb.xgbProbTP1, 1) + "%"
                  + " [shadow " + IntegerToString(g_xgbBrierSamples) + "/" + IntegerToString(MIN_XGB_BRIER_SAMPLES) + "]";
            xClr  = clrYellow;
         }
         else
         {
            xLine = " XGB:" + DoubleToString(g_currentProb.xgbProbTP1, 1) + "%"
                  + " [POOR] Brier:" + DoubleToString(g_xgbBrierScore, 3);
            xClr  = clrOrange;
         }

         string modeLabel = " Mode:" + XGBModeLabel();
         CreateTextLabel(PREFIX_PANEL+"P_XGB", px+pad, cy, modeLabel + xLine, xClr, fs-2, false);
         cy += lh;

         // A/B shadow (candidate) model line — Sprint 4, observational only.
         // Distinct from the "[shadow N/20]" warm-up tag above (that's the
         // champion's own Brier-qualification state, unrelated to this feature).
         if(InpEnableXGBShadow && g_xgbShadowLoaded)
         {
            string sLine = " Candidate:" + DoubleToString(g_xgbShadowProbTP1, 1) + "%"
                         + " Brier:" + DoubleToString(g_xgbShadowBrierScore, 3)
                         + " [n=" + IntegerToString(g_xgbShadowBrierSamples) + "]";
            color  sClr  = (g_xgbShadowBrierSamples >= MIN_XGB_BRIER_SAMPLES
                            && g_xgbShadowBrierScore < g_xgbBrierScore) ? clrLime : InpPanelDimColor;
            CreateTextLabel(PREFIX_PANEL+"P_XGBSHADOW", px+pad, cy, sLine, sClr, fs-2, false);
            cy += lh;
         }
      }

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
   // POSITION SIZING + TRADE SUMMARY
   //==========================================================
   if(InpUseKellyLot || g_outcomeCount > 0)
   {
      cy += 3;
      CreateTextLabel(PREFIX_PANEL+"PS_T", px+pad, cy,
         "Position Sizing", InpPanelTitleColor, fs-1, true);
      cy += lh;

      if(InpUseKellyLot)
      {
         string psLine1 = " Kelly:" + DoubleToString(g_positionSize.kellyPct, 1) + "%"
                        + " Vol:" + DoubleToString(g_positionSize.volScale, 1) + "x"
                        + " Brier:" + DoubleToString(g_positionSize.brierScale, 1) + "x"
                        + " DD:" + DoubleToString(g_positionSize.ddScale * 100, 0) + "%";
         color psClr1 = (g_positionSize.kellyPct > 1.0) ? clrLime
                      : (g_positionSize.kellyPct > 0)   ? clrYellow
                      : clrOrange;
         CreateTextLabel(PREFIX_PANEL+"PS_L1", px+pad, cy, psLine1, psClr1, fs-2, false);
         cy += lh;

         string psLine2 = " Risk:" + DoubleToString(g_positionSize.adjustedRiskPct, 2) + "%";
         if(g_positionSize.recommendedLot > 0)
            psLine2 += " -> " + DoubleToString(g_positionSize.recommendedLot, 2) + " lot";
         CreateTextLabel(PREFIX_PANEL+"PS_L2", px+pad, cy, psLine2, clrWhite, fs-2, false);
         cy += lh;
      }

      if(g_outcomeCount > 0)
      {
         int total = g_positionSize.totalWins + g_positionSize.totalLosses;
         string tsLine = " W/L:" + IntegerToString(g_positionSize.totalWins)
                       + "/" + IntegerToString(g_positionSize.totalLosses);
         if(total > 0)
            tsLine += " (" + DoubleToString(g_positionSize.winRate, 0) + "%)";
         tsLine += " EV:" + (g_positionSize.avgEV >= 0 ? "+" : "")
                 + DoubleToString(g_positionSize.avgEV, 2);
         color tsClr = (g_positionSize.winRate > 55) ? clrLime
                     : (g_positionSize.winRate > 45) ? clrYellow
                     : clrOrange;
         if(total == 0) tsClr = InpPanelDimColor;
         CreateTextLabel(PREFIX_PANEL+"PS_TS", px+pad, cy, tsLine, tsClr, fs-2, false);
         cy += lh;
      }
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
      // Unified regime display
      {
         color vrClr = clrGray;
         if(g_marketState.state == STATE_MEAN_REVERT)      vrClr = clrCyan;
         else if(g_marketState.state == STATE_TRENDING)     vrClr = clrLime;
         else if(g_marketState.state == STATE_VOLATILE)     vrClr = clrRed;
         else if(g_marketState.state == STATE_TRANSITION)   vrClr = clrYellow;
         string multStr = DoubleToString(g_marketState.probMultiplier, 2);
         CreateTextLabel(PREFIX_PANEL+"V_VR", px+pad+3, cy,
            "Regime:"+g_marketState.label+" (x"+multStr+") ATR:"+DoubleToString(g_volRegime.atrRatio, 2)+"x",
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
      if(InpUseADXFilter)
      {
         CreateTextLabel(PREFIX_PANEL+"V_ADX", px+pad+3, cy,
            GetADXDisplayText(1), GetADXDisplayColor(1), fs-2, false);
         cy += lh;
      }
      if(InpUseMACDFilter)
      {
         CreateTextLabel(PREFIX_PANEL+"V_MACD", px+pad+3, cy,
            GetMACDDisplayText(1), GetMACDDisplayColor(1), fs-2, false);
         cy += lh;
      }
      if(g_us10y.isAvailable)
      {
         CreateTextLabel(PREFIX_PANEL+"V_US10Y", px+pad+3, cy,
            GetUS10YDisplayText(), GetUS10YColor(isBuy), fs-2, false);
         cy += lh;
      }
      if(InpUseEconCalendar)
      {
         CreateTextLabel(PREFIX_PANEL+"V_ECAL", px+pad+3, cy,
            GetEconCalendarDisplayText(), GetEconCalendarDisplayColor(), fs-2, false);
         cy += lh;
      }
      // Brier Score calibration display
      if(g_brierMetrics.samples >= 5)
      {
         color brClr = clrLime;
         if(g_brierMetrics.brierScore >= 0.30)      brClr = clrRed;
         else if(g_brierMetrics.brierScore >= 0.25)  brClr = clrOrange;
         else if(g_brierMetrics.brierScore >= 0.20)  brClr = clrYellow;
         string brText = "Brier:" + DoubleToString(g_brierMetrics.brierScore, 3)
                       + " Cal:" + DoubleToString(g_brierMetrics.calibrationGap * 100, 1) + "%"
                       + " n=" + IntegerToString(g_brierMetrics.samples);
         if(g_brierMetrics.samples >= 20 && g_brierMetrics.brierScore > 0.20)
         {
            double shrk = MathMax(0.0, 1.0 - (g_brierMetrics.brierScore - 0.20) / 0.15);
            brText += " Shrk:" + DoubleToString(shrk * 100, 0) + "%";
         }
         if(!g_brierMetrics.isReliable && g_brierMetrics.samples >= 20)
            brText += " UNRELIABLE";
         CreateTextLabel(PREFIX_PANEL+"V_BR", px+pad+3, cy, brText, brClr, fs-2, false);
         cy += lh;
      }
      // Risk summary (account + budget + suggested size)
      DrawRiskSummary(px, pad, fs, cy, false);
      DrawPerfReport(px, pad, fs, cy, false);
   }
   //--- FOOTER ---
   CreateTextLabel(PREFIX_PANEL+"Z_F", px+pad, cy,
      "Drag title to move | Click arrow", InpPanelDimColor, fs-2, false);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Close button helper (OBJ_BUTTON for indicator panel)              |
//+------------------------------------------------------------------+
void CreateCloseButton(string name, int x, int y, int w, int h, string text, color bg, color brd)
{
   if(ObjectFind(name) < 0)
   {
      ObjectCreate(name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, brd);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
}

//+------------------------------------------------------------------+
//| Dashboard dispatcher — routes to Full or Manual panel by mode.    |
//| clearStale=true forces a delete-before-draw (needed while         |
//| dragging, where position changes but layout doesn't so the        |
//| normal layout-change detection inside each draw fn won't fire).   |
//+------------------------------------------------------------------+
void DrawDashboard(int signalIndex, bool clearStale = false)
{
   if(clearStale)
   {
      DeleteObjectsByPrefix(PREFIX_PANEL);
      if(InpDashboardMode == DASHBOARD_MANUAL)
         DeleteObjectsByPrefix(PREFIX_CLOSE);
   }

   if(InpDashboardMode == DASHBOARD_MANUAL)
      DrawManualPanel(signalIndex);
   else
      DrawInfoPanel(signalIndex);
}

//+------------------------------------------------------------------+
//| Manual Trading Dashboard — compact panel + close buttons          |
//+------------------------------------------------------------------+
void DrawManualPanel(int signalIndex)
{
   if(InpEAMode || !InpShowPanel) return;

   int px = g_panelPosX, py = g_panelPosY;
   int pw = InpPanelWidth, fs = InpPanelFontSize;
   int lh = fs + 6, pad = 8, titleBarH = lh + 6;

   // --- Collapsed state ---
   if(g_manualPanelCollapsed)
   {
      DeleteObjectsByPrefix(PREFIX_PANEL);
      DeleteObjectsByPrefix(PREFIX_CLOSE);
      int collW = pw, collH = titleBarH;
      CreateRectangleLabel(PREFIX_PANEL+"0_BG", px, py, collW, collH, InpPanelBgColor, InpPanelBorderColor);
      string collText = "QuantEdge";
      if(signalIndex >= 0 && signalIndex < g_signalCount)
      {
         SignalData cs = g_signals[signalIndex];
         collText += cs.isBuySignal ? "  BUY" : "  SELL";
         bool hasP = (InpShowProbability && g_currentProb.probTP1 > 0);
         if(hasP)
            collText += "  " + DoubleToString(g_currentProb.probTP1, 0) + "%";
      }
      else
         collText += "  -- no signal --";
      collText += "  [+]";
      CreateTextLabel(PREFIX_PANEL+"1_T", px+pad, py+3, collText, InpPanelTitleColor, fs, true);
      ChartRedraw();
      return;
   }

   // --- Height calculation ---
   int calcY = titleBarH + 2;

   bool hasSig = (signalIndex >= 0 && signalIndex < g_signalCount);
   bool hasProb = hasSig && (InpShowProbability && (g_currentProb.totalSamples >= GetMinSamplesForTimeframe() || g_currentProb.probTP1 > 0));
   bool hasMTF = (InpShowMTF && g_mtfCount > 0);
   bool hasZones = false;
   int visibleZones = 0;
   TradeRecommendation rec;
   bool isInvalidated = false;
   bool isBuy = false;

   if(hasSig)
   {
      SignalData sig = g_signals[signalIndex];
      isBuy = sig.isBuySignal;
      double curPrice = iClose(NULL, 0, 0);
      double slDist = MathAbs(sig.entryPrice - sig.stopLoss);

      if(isBuy && curPrice <= sig.stopLoss) isInvalidated = true;
      if(!isBuy && curPrice >= sig.stopLoss) isInvalidated = true;

      int mtfAgree = 0;
      if(hasMTF) mtfAgree = CalculateMTFAgreement();
      double tp1Dist = MathAbs(sig.takeProfit1 - sig.entryPrice);

      if(!isInvalidated)
      {
         int recN = (int)MathRound(g_currentProb.nEffT1 + g_currentProb.nEffT2);
         rec = GetTradeRecommendation(
            sig.caseNumber, isBuy, g_currentProb.probTP1, g_currentProb.probSL,
            recN, mtfAgree, slDist, tp1Dist, sig.atrValue, sig.signalTime);
      }

      hasZones = (InpEntryZoneCount >= 2 && g_validZoneCount >= 1 && !isInvalidated);
      if(hasZones)
         for(int z = 0; z < 5; z++)
            if(g_entryZones[z].isValid) visibleZones++;

      calcY += lh;      // signal banner
      calcY += lh;      // recommendation label
      if(!isInvalidated) calcY += lh;  // confidence meter row
      if(InpShowTDS)                          calcY += lh;  // TDS line (or invalidated placeholder)
      if(InpShowAttribution && !isInvalidated) calcY += lh;  // Attribution bar (hidden when invalidated)
      calcY += 3;
      calcY += lh;      // Entry
      calcY += lh;      // SL
      calcY += lh;      // TP1
      calcY += lh;      // TP2
      calcY += lh;      // TP3
      if(hasZones && visibleZones > 0)
      {
         calcY += 3;
         calcY += visibleZones * lh;
      }
      if(InpShowRiskSummary && !IsBacktestMode()) calcY += lh * 2;  // risk summary (2 lines, compact)
   }
   else
   {
      calcY += lh * 2;  // no signal text
   }

   if(hasMTF)
   {
      calcY += 3;
      calcY += lh;      // MTF title
      calcY += lh;      // alignment blocks (single row)
   }

   if(hasSig && hasProb && g_currentProb.elapsedBars > 0)
      calcY += lh;      // expiry line

   // Close buttons
   int btnH = 22, btnGap = 3;
   calcY += 3;
   calcY += btnH + btnGap;  // row 1: 4 buttons
   calcY += btnH;            // row 2: CLOSE ALL
   calcY += 4;               // bottom padding

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

   // --- Background ---
   color borderClr = isInvalidated ? clrRed : InpPanelBorderColor;
   CreateRectangleLabel(PREFIX_PANEL+"0_BG", px, py, pw, totalH, InpPanelBgColor, borderClr);
   CreateRectangleLabel(PREFIX_PANEL+"0_TB", px, py, pw, titleBarH, InpPanelBorderColor, InpPanelBorderColor);

   int cy = py + 3;

   // --- Title bar ---
   string titleText = "QuantEdge";
   color titleClr = InpPanelTitleColor;
   CreateTextLabel(PREFIX_PANEL+"1_T", px+pad, cy, titleText, titleClr, fs, true);
   CreateTextLabel(PREFIX_PANEL+"1_M", px+pw-65, cy, "MANUAL", C'120,160,200', fs-2, false);
   CreateTextLabel(PREFIX_PANEL+"1_C", px+pw-18, cy, "[-]", InpPanelDimColor, fs, false);
   cy += titleBarH + 2 - 3;

   // --- Signal content ---
   if(hasSig)
   {
      SignalData sig = g_signals[signalIndex];
      string dir = isBuy ? "BUY SIGNAL" : "SELL SIGNAL";
      color dirClr = isBuy ? InpPanelBuyColor : InpPanelSellColor;
      string caseName = "Case " + IntegerToString(sig.caseNumber) + ": " + GetCaseName(sig.caseNumber);

      if(isInvalidated)
      {
         dir = (isBuy ? "BUY" : "SELL") + " [INVALID]";
         dirClr = clrRed;
      }

      // Signal banner
      CreateTextLabel(PREFIX_PANEL+"2_SIG", px+pad, cy, dir + "  " + caseName, dirClr, fs, true);
      cy += lh;

      // Recommendation + confidence
      if(isInvalidated)
      {
         CreateTextLabel(PREFIX_PANEL+"2_REC", px+pad, cy,
            "SL BREACHED - Do NOT trade", clrRed, fs, true);
      }
      else
      {
         CreateTextLabel(PREFIX_PANEL+"2_REC", px+pad, cy, rec.label, rec.labelColor, fs, true);
      }
      cy += lh;
      if(!isInvalidated)
      {
         DrawConfidenceMeter(px, pad, cy, 80, rec.confidence);
         cy += lh;
      }

      // TDS + Attribution
      DrawTDSLine(px, pad, fs, cy, !isInvalidated, sig, rec);
      if(!isInvalidated) DrawAttributionBar(px, pad, fs, cy);

      // Price levels
      cy += 3;
      double slDist = MathAbs(sig.entryPrice - sig.stopLoss);
      double tp1Dist = MathAbs(sig.takeProfit1 - sig.entryPrice);
      double tp2Dist = MathAbs(sig.takeProfit2 - sig.entryPrice);
      double tp3Dist = MathAbs(sig.takeProfit3 - sig.entryPrice);
      double slPips = PriceToNormalizedPips(slDist);
      double tp1Pips = PriceToNormalizedPips(tp1Dist);
      double tp1R = PriceToRMultiple(tp1Dist, slDist);
      double tp2R = PriceToRMultiple(tp2Dist, slDist);
      double tp3R = PriceToRMultiple(tp3Dist, slDist);

      CreateTextLabel(PREFIX_PANEL+"3_EN", px+pad, cy,
         "Entry  " + DoubleToString(sig.entryPrice, _Digits), InpPanelTextColor, fs, true);
      cy += lh;

      CreateTextLabel(PREFIX_PANEL+"3_SL", px+pad, cy,
         "SL     " + DoubleToString(sig.stopLoss, _Digits) + "  " +
         DoubleToString(slPips, 0) + "p", clrRed, fs-1, false);
      cy += lh;

      string tp1prob = hasProb ? ("  P:" + DoubleToString(g_currentProb.probTP1, 0) + "%") : "";
      CreateTextLabel(PREFIX_PANEL+"3_T1", px+pad, cy,
         "TP1    " + DoubleToString(sig.takeProfit1, _Digits) +
         tp1prob + "  R:R 1:" + DoubleToString(tp1R, 1), clrLime, fs-1, false);
      cy += lh;

      string tp2prob = hasProb ? ("  P:" + DoubleToString(g_currentProb.probTP2, 0) + "%") : "";
      CreateTextLabel(PREFIX_PANEL+"3_T2", px+pad, cy,
         "TP2    " + DoubleToString(sig.takeProfit2, _Digits) +
         tp2prob + "  1:" + DoubleToString(tp2R, 1), C'70,200,110', fs-1, false);
      cy += lh;

      string tp3prob = hasProb ? ("  P:" + DoubleToString(g_currentProb.probTP3, 0) + "%") : "";
      CreateTextLabel(PREFIX_PANEL+"3_T3", px+pad, cy,
         "TP3    " + DoubleToString(sig.takeProfit3, _Digits) +
         tp3prob + "  1:" + DoubleToString(tp3R, 1), C'70,200,110', fs-1, false);
      cy += lh;

      // Entry zones (compact)
      if(hasZones && visibleZones > 0)
      {
         cy += 3;
         for(int z = 0; z < 5; z++)
         {
            if(!g_entryZones[z].isValid) continue;
            color zClr = g_entryZones[z].isRecommended ? GetZoneColor(z) : InpPanelDimColor;
            string evStar = (g_entryZones[z].expectedValue > 0) ? "*" : "";
            CreateTextLabel(PREFIX_PANEL+"EZ_"+IntegerToString(z), px+pad, cy,
               "Z" + IntegerToString(z+1) + " " +
               g_entryZones[z].zoneName + ":" + DoubleToString(g_entryZones[z].price, _Digits) +
               "  Reach:" + DoubleToString(g_entryZones[z].probReach*100, 0) + "%" +
               "  EV:" + DoubleToString(g_entryZones[z].expectedValue, 2) + "R" + evStar,
               zClr, fs-2, false);
            cy += lh;
         }
      }

      // Risk summary (compact form)
      DrawRiskSummary(px, pad, fs, cy, true);
      DrawPerfReport(px, pad, fs, cy, true);
   }
   else
   {
      // No signal state
      CreateTextLabel(PREFIX_PANEL+"2_NS", px+pad, cy,
         GetCleanSymbolName() + " | " + GetTimeframeString() + " | Waiting...",
         InpPanelDimColor, fs, false);
      cy += lh;
      CreateTextLabel(PREFIX_PANEL+"2_NS2", px+pad, cy,
         "Panel auto-updates when signal fires", InpPanelDimColor, fs-2, false);
      cy += lh;
   }

   // MTF alignment (single visual row)
   if(hasMTF)
   {
      cy += 3;
      int agreeCount = 0;
      string mtfLine = "MTF ";
      for(int t = 0; t < g_mtfCount; t++)
      {
         string tfTag = g_mtfData[t].tfName;
         if(g_mtfData[t].trend == 1)
         {
            mtfLine += "[" + tfTag + "+] ";
            if(hasSig && isBuy) agreeCount++;
         }
         else if(g_mtfData[t].trend == -1)
         {
            mtfLine += "[" + tfTag + "-] ";
            if(hasSig && !isBuy) agreeCount++;
         }
         else
            mtfLine += "[" + tfTag + " ] ";
      }
      string alignStr = IntegerToString(agreeCount) + "/" + IntegerToString(g_mtfCount) + " ALIGNED";
      color mtfClr = (agreeCount >= 3) ? clrLime : (agreeCount >= 2) ? clrYellow : InpPanelDimColor;
      CreateTextLabel(PREFIX_PANEL+"M_T", px+pad, cy, mtfLine, InpPanelDimColor, fs-2, false);
      cy += lh;
      CreateTextLabel(PREFIX_PANEL+"M_AG", px+pad, cy, alignStr, mtfClr, fs-1, true);
      cy += lh;
   }

   // Signal expiry
   if(hasSig && hasProb && g_currentProb.elapsedBars > 0)
   {
      int barsAgo = iBarShift(NULL, 0, g_signals[signalIndex].signalTime, false);
      if(barsAgo < 0) barsAgo = 0;
      int minsAgo = barsAgo * Period();
      string ageStr;
      if(minsAgo >= 60) ageStr = IntegerToString(minsAgo/60) + "h" + IntegerToString(minsAgo%60) + "m";
      else              ageStr = IntegerToString(minsAgo) + "m";

      string expLine = "Age:" + ageStr;
      if(g_currentProb.expiresMinutes > 0)
      {
         if(g_currentProb.expiresMinutes >= 60)
            expLine += "  Exp:~" + IntegerToString(g_currentProb.expiresMinutes/60) + "h" +
                       IntegerToString(g_currentProb.expiresMinutes%60) + "m";
         else
            expLine += "  Exp:~" + IntegerToString(g_currentProb.expiresMinutes) + "m";
      }
      double survPct = g_currentProb.survivalRatio * 100.0;
      expLine += "  Edge:" + DoubleToString(survPct, 0) + "%";
      color expClr = (survPct > 70) ? clrLime : (survPct > 40) ? clrYellow : (survPct > 20) ? clrOrange : clrRed;
      CreateTextLabel(PREFIX_PANEL+"P_EX", px+pad, cy, expLine, expClr, fs-2, false);
      cy += lh;
   }

   // --- Close buttons (horizontal layout) ---
   cy += 3;
   int btnW = (pw - 2*pad - 3*btnGap) / 4;  // 4 buttons per row
   int bx = px + pad;

   CreateCloseButton(PREFIX_CLOSE+"Profit", bx, cy, btnW, btnH,
      "Close Profit", C'22,110,66', C'56,196,122');
   CreateCloseButton(PREFIX_CLOSE+"Loss", bx+btnW+btnGap, cy, btnW, btnH,
      "Close Loss", C'120,40,48', C'214,84,92');
   CreateCloseButton(PREFIX_CLOSE+"BuyP", bx+2*(btnW+btnGap), cy, btnW, btnH,
      "Close Buy+", C'20,92,158', C'64,158,232');
   CreateCloseButton(PREFIX_CLOSE+"SellP", bx+3*(btnW+btnGap), cy, btnW, btnH,
      "Close Sell+", C'20,92,158', C'64,158,232');
   cy += btnH + btnGap;

   int allW = pw - 2*pad;
   CreateCloseButton(PREFIX_CLOSE+"All", bx, cy, allW, btnH,
      "CLOSE ALL", C'168,32,32', C'232,72,72');

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Explainability / Attribution Debug Panel                          |
//| Shows per-layer contribution to final probTP1.                    |
//| Activated by InpShowProbExplain. Zero logic change to pipeline.   |
//+------------------------------------------------------------------+
void DrawExplainPanel()
{
   if(!InpShowProbExplain) return;

   int pw = 380;
   int fs = InpPanelFontSize;
   int lh = fs + 6;
   int pad = 8;
   int px = g_panelPosX + InpPanelWidth + 10;
   int cy = g_panelPosY;

   ExplainData e = g_explainData;

   int rowCount = 20;
   int ph = lh * rowCount + pad * 2;
   CreateRectangleLabel(PREFIX_EXPLAIN+"BG", px, cy, pw, ph,
                        InpPanelBgColor, InpPanelBorderColor);

   cy += pad;
   CreateTextLabel(PREFIX_EXPLAIN+"T", px+pad, cy,
      "PROB ATTRIBUTION (debug)", InpPanelTitleColor, fs, true);
   cy += lh + 2;

   color cDim = InpPanelDimColor;
   color cTxt = InpPanelTextColor;

   CreateTextLabel(PREFIX_EXPLAIN+"H", px+pad, cy,
      "Step                      Value     Prob%    D%", cDim, fs-1, false);
   cy += lh;

   double prev = 0;
   string line;
   color  deltaClr;

   // --- Nhom A: Edge-space attribution ---
   CreateTextLabel(PREFIX_EXPLAIN+"A0", px+pad, cy,
      StringFormat("Base Edge        %.3f       %5.1f%%",
                   e.baseEdge, e.probAfterBase), cTxt, fs-1, false);
   cy += lh;
   prev = e.probAfterBase;

   // MTF
   {
      double d = e.probAfterMTF - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"A1", px+pad, cy,
         StringFormat("+ MTF            %+.3f      %5.1f%%  %+5.1f",
                      e.edgeMTF, e.probAfterMTF, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterMTF;
   }
   // Intermarket
   {
      double d = e.probAfterInter - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"A2", px+pad, cy,
         StringFormat("+ Intermarket    %+.3f      %5.1f%%  %+5.1f",
                      e.edgeInter, e.probAfterInter, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterInter;
   }
   // Angle
   {
      double d = e.probAfterAngle - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"A3", px+pad, cy,
         StringFormat("+ Angle Z        %+.3f      %5.1f%%  %+5.1f",
                      e.edgeAngle, e.probAfterAngle, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterAngle;
   }
   // MarketState
   {
      double d = e.probAfterMktSt - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"A4", px+pad, cy,
         StringFormat("x MktState       x%.2f      %5.1f%%  %+5.1f",
                      e.edgeMktSt, e.probAfterMktSt, d), deltaClr, fs-1, false);
      cy += lh;
   }

   // --- Nhom B: Gambler's Ruin corrections ---
   CreateTextLabel(PREFIX_EXPLAIN+"S1", px+pad, cy,
      "--- Gambler Ruin corrections ---", cDim, fs-1, false);
   cy += lh;

   CreateTextLabel(PREFIX_EXPLAIN+"B1", px+pad, cy,
      StringFormat("  FatTail   -%4.1f%%   VolClust -%4.1f%%   Spread -%4.1f%%",
                   e.fatTailPenalty * 100.0, e.volClusterPen * 100.0, e.spreadDrag * 100.0),
      clrTomato, fs-1, false);
   cy += lh;

   CreateTextLabel(PREFIX_EXPLAIN+"B2", px+pad, cy,
      StringFormat("Theoretical       ->  %5.1f%%", e.theoTP1), cTxt, fs-1, false);
   cy += lh;

   // --- Bayesian combine ---
   CreateTextLabel(PREFIX_EXPLAIN+"S2", px+pad, cy,
      "--- Bayesian Combine ---", cDim, fs-1, false);
   cy += lh;

   CreateTextLabel(PREFIX_EXPLAIN+"C1", px+pad, cy,
      StringFormat("Historical  %5.1f%%   Combined -> %5.1f%%",
                   e.histTP1, e.probAfterBayes), cTxt, fs-1, false);
   cy += lh;
   prev = e.probAfterBayes;

   // XGBoost
   {
      double d = e.probAfterXGB - prev;
      deltaClr = (MathAbs(d) > 0.05) ? ((d > 0) ? clrLime : clrTomato) : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"C2", px+pad, cy,
         StringFormat("XGBoost                  %5.1f%%  %+5.1f",
                      e.probAfterXGB, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterXGB;
   }

   // --- Nhom C: Confidence adjustments ---
   CreateTextLabel(PREFIX_EXPLAIN+"S3", px+pad, cy,
      "--- Confidence Adjustments ---", cDim, fs-1, false);
   cy += lh;

   // 1-Bar Confirm
   {
      double d = e.probAfterConfirm - prev;
      string chk = e.confirmHit ? "Y" : "N";
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"D1", px+pad, cy,
         StringFormat("1-Bar Confirm  %s         %5.1f%%  %+5.1f",
                      chk, e.probAfterConfirm, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterConfirm;
   }
   // ATR Spike
   {
      double d = e.probAfterSpike - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"D2", px+pad, cy,
         StringFormat("ATR Spike    %4.1fx        %5.1f%%  %+5.1f",
                      e.spikeRatio, e.probAfterSpike, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterSpike;
   }
   // Session WR
   {
      double d = e.probAfterSession - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"D3", px+pad, cy,
         StringFormat("Session WR   x%.2f        %5.1f%%  %+5.1f",
                      e.sessionRatio, e.probAfterSession, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterSession;
   }
   // Brier Shrink
   {
      double d = e.probAfterBrier - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"D4", px+pad, cy,
         StringFormat("Brier Shrink  %3.0f%%        %5.1f%%  %+5.1f",
                      e.brierShrink * 100.0, e.probAfterBrier, d), deltaClr, fs-1, false);
      cy += lh;
      prev = e.probAfterBrier;
   }
   // Time Decay
   {
      double d = e.probFinal - prev;
      deltaClr = (d > 0.05) ? clrLime : (d < -0.05) ? clrTomato : cDim;
      CreateTextLabel(PREFIX_EXPLAIN+"D5", px+pad, cy,
         StringFormat("Time Decay   S=%.2f       %5.1f%%  %+5.1f",
                      e.survivalRatio, e.probFinal, d), deltaClr, fs-1, false);
      cy += lh;
   }

   // --- FINAL ---
   CreateTextLabel(PREFIX_EXPLAIN+"FN", px+pad, cy,
      StringFormat("=== FINAL                %5.1f%% ===", e.probFinal),
      clrGold, fs, true);

   ChartRedraw();
}
#endif