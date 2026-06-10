//+------------------------------------------------------------------+
//|                                         RSI_Advanced.mq5           |
//|                         RSI Advanced - MT5 Version                 |
//|                         Master Trading Wave Community               |
//|                                                                    |
//| Architecture:                                                      |
//|   MQLCompat.mqh wraps all MQL4 functions for MQL5                  |
//|   All .mqh logic files remain unchanged                            |
//|   This file replaces RSI_Advanced.mq4 for MT5 compilation          |
//+------------------------------------------------------------------+
#property copyright "Master Trading Wave"
#property link      "https://mastertradingwave.com"
#property version "10.20"
#property strict
#property indicator_separate_window
#property indicator_minimum    0
#property indicator_maximum    100
#property indicator_buffers    7
#property indicator_plots      7

//--- Plot 1: RSI Fast (Green)
#property indicator_label1     "RSI Fast"
#property indicator_type1      DRAW_LINE
#property indicator_color1     clrLime
#property indicator_style1     STYLE_SOLID
#property indicator_width1     2

//--- Plot 2: Signal (Red)
#property indicator_label2     "Signal"
#property indicator_type2      DRAW_LINE
#property indicator_color2     clrRed
#property indicator_style2     STYLE_SOLID
#property indicator_width2     2

//--- Plot 3: BB Upper
#property indicator_label3     "BB Upper"
#property indicator_type3      DRAW_LINE
#property indicator_color3     clrDeepSkyBlue
#property indicator_style3     STYLE_SOLID
#property indicator_width3     1

//--- Plot 4: BB Lower
#property indicator_label4     "BB Lower"
#property indicator_type4      DRAW_LINE
#property indicator_color4     clrDeepSkyBlue
#property indicator_style4     STYLE_SOLID
#property indicator_width4     1

//--- Plot 5: Baseline (Orange)
#property indicator_label5     "Baseline"
#property indicator_type5      DRAW_LINE
#property indicator_color5     clrOrange
#property indicator_style5     STYLE_SOLID
#property indicator_width5     2

//--- Plot 6: BuySignal (hidden data buffer)
#property indicator_label6     "BuySignal"
#property indicator_type6      DRAW_NONE

//--- Plot 7: SellSignal (hidden data buffer)
#property indicator_label7     "SellSignal"
#property indicator_type7      DRAW_NONE

//--- Level lines
#property indicator_level1     20
#property indicator_level2     32
#property indicator_level3     50
#property indicator_level4     68
#property indicator_level5     80
#property indicator_levelcolor clrGray
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

//--- Buffers
double BufferGreen[];
double BufferRed[];
double BufferBBUpper[];
double BufferBBLower[];
double BufferOrange[];
double BufferBuySignal[];
double BufferSellSignal[];

//--- Includes: MQLCompat MUST be first (wraps MQL4 functions)
#include <RSI_Advanced/MQLCompat.mqh>
#include <RSI_Advanced/Config.mqh>
#include <RSI_Advanced/Structs.mqh>
#include <RSI_Advanced/Globals.mqh>
#include <RSI_Advanced/MathUtils.mqh>
#include <RSI_Advanced/Normalize.mqh>
#include <RSI_Advanced/RSICore.mqh>
#include <RSI_Advanced/SwingDetection.mqh>
#include <RSI_Advanced/SignalCases.mqh>
#include <RSI_Advanced/SLTP.mqh>
#include <RSI_Advanced/MTFEngine.mqh>
#include <RSI_Advanced/IntermarketAnalysis.mqh>
#include <RSI_Advanced/SessionStatistics.mqh>
#include <RSI_Advanced/WalkForward.mqh>
#include <RSI_Advanced/ProbabilityEngine.mqh>
#include <RSI_Advanced/ArrowManager.mqh>
#include <RSI_Advanced/LineDrawing.mqh>
#include <RSI_Advanced/PanelDrawing.mqh>
#include <RSI_Advanced/ChartEvents.mqh>
#include <RSI_Advanced/SignalLogger.mqh>

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRSIPeriod < 2 || InpFastMAPeriod < 1 || InpSignalMAPeriod < 1 || InpBBPeriod < 2)
      return(INIT_PARAMETERS_INCORRECT);
   if(InpBBDeviation <= 0 || InpSLRatio <= 0 || InpTPRatio <= 0)
      return(INIT_PARAMETERS_INCORRECT);

   //--- MQL5 SetIndexBuffer requires INDICATOR_DATA / INDICATOR_CALCULATIONS
   SetIndexBuffer(0, BufferGreen,     INDICATOR_DATA);
   SetIndexBuffer(1, BufferRed,       INDICATOR_DATA);
   SetIndexBuffer(2, BufferBBUpper,   INDICATOR_DATA);
   SetIndexBuffer(3, BufferBBLower,   INDICATOR_DATA);
   SetIndexBuffer(4, BufferOrange,    INDICATOR_DATA);
   SetIndexBuffer(5, BufferBuySignal, INDICATOR_DATA);
   SetIndexBuffer(6, BufferSellSignal,INDICATOR_DATA);

   //--- MQL5: arrays are non-series by default in indicators
   //--- Match MQL4 behavior (non-series)
   ArraySetAsSeries(BufferGreen, false);
   ArraySetAsSeries(BufferRed, false);
   ArraySetAsSeries(BufferBBUpper, false);
   ArraySetAsSeries(BufferBBLower, false);
   ArraySetAsSeries(BufferOrange, false);
   ArraySetAsSeries(BufferBuySignal, false);
   ArraySetAsSeries(BufferSellSignal, false);

   int mb = GetMinBarsRequired();
   for(int i = 0; i < 7; i++)
   {
      SetIndexEmptyValue(i, EMPTY_VALUE);
      SetIndexDrawBegin(i, mb);
   }

   IndicatorShortName("RSI Advanced (" + IntegerToString(InpRSIPeriod) +
                      ") SL:" + DoubleToString(InpSLRatio, 1) +
                      " TP:" + DoubleToString(InpTPRatio, 1));
   IndicatorDigits(2);

   g_prevRatesTotal    = 0;
   g_lastAlertTime     = 0;
   g_signalCount       = 0;
   g_activeSignalIndex = -1;
   g_outcomeCount      = 0;
   ArrayResize(g_signals, 0);
   ArrayResize(g_outcomes, 0);

   InitSessionStats();
   LoadPanelPosition();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   LoggerInit(false);
   // Only load cached session stats on recompile/param change (quick restart).
   // TF switch / remove / chart close → fullRecalc rebuilds everything fresh.
   int prevReason = UninitializeReason();
   if(prevReason == REASON_RECOMPILE || prevReason == REASON_PARAMETERS)
   {
      if(!LoadSessionStatsBinary())
         LoadSessionStatsFromOutcomesCSV();
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Signals binary: always save (accumulates history across restarts).
   // Session stats binary: save only on recompile/param change (quick restart).
   SaveSignalsBinary();
   if(reason == REASON_RECOMPILE || reason == REASON_PARAMETERS)
   {
      SaveSessionStatsBinary();
   }
   else
   {
      // REASON_REMOVE, REASON_CHARTCHANGE, REASON_CHARTCLOSE →
      // delete session stats binary so next attach rebuilds outcomes fresh.
      FileDelete(SS_GetBinaryPath());
   }
   FlushLogQueues();
   ReleaseAllHandles();

   SavePanelPosition();
   DeleteObjectsByPrefix(PREFIX_ARROW);
   DeleteObjectsByPrefix(PREFIX_PANEL);
   DeleteObjectsByPrefix(PREFIX_LINE);
   DeleteObjectsByPrefix(PREFIX_PROB);
   DeleteObjectsByPrefix(PREFIX_ZONE);
   Comment("");
   ArrayFree(g_rawRSI);
   ArrayResize(g_signals, 0);
   ArrayResize(g_outcomes, 0);
   g_signalCount    = 0;
   g_outcomeCount   = 0;
   g_prevRatesTotal = 0;
   ChartRedraw();
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   HandleChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   #ifdef __MQL5__
   InvalidatePriceCache();  // Force refresh at start of each OnCalculate
   #endif
   
   ArraySetAsSeries(time, false);
   ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low, false);
   ArraySetAsSeries(close, false);

   int minBars = GetMinBarsRequired();
   if(rates_total < minBars) return(0);

   //--- Array management
   // fullRecalc only on first load or when history is shortened (bar indices would shift).
   // New bar added (rates_total increased) keeps cached signals — incremental path handles it.
   bool fullRecalc = (prev_calculated <= 0 || rates_total < g_prevRatesTotal);
   if(fullRecalc)
   {
      ArrayResize(g_rawRSI, rates_total);
      ArrayInitialize(g_rawRSI, EMPTY_VALUE);
      DeleteObjectsByPrefix(PREFIX_ARROW);
      DeleteObjectsByPrefix(PREFIX_LINE);
      DeleteObjectsByPrefix(PREFIX_PANEL);
      DeleteObjectsByPrefix(PREFIX_PROB);
      DeleteObjectsByPrefix(PREFIX_ZONE);
      g_signalCount       = 0;
      g_activeSignalIndex = -1;
      ArrayResize(g_signals, 0);
      MTF_InitRamBuffers();  // Rebuild MTF RAM buffers from historical iRSI data
   }
   else if(rates_total > g_prevRatesTotal)
   {
      int oldSize = ArraySize(g_rawRSI);
      ArrayResize(g_rawRSI, rates_total);
      for(int k = oldSize; k < rates_total; k++)
         g_rawRSI[k] = EMPTY_VALUE;
   }
   else if(ArraySize(g_rawRSI) != rates_total)
      ArrayResize(g_rawRSI, rates_total);

   g_prevRatesTotal = rates_total;

   //--- Calculation range
   int startBar;
   if(fullRecalc)
   {
      startBar = MathMax(InpRSIPeriod, rates_total - InpMaxBars);
      ArrayInitialize(BufferGreen, EMPTY_VALUE);
      ArrayInitialize(BufferRed, EMPTY_VALUE);
      ArrayInitialize(BufferBBUpper, EMPTY_VALUE);
      ArrayInitialize(BufferBBLower, EMPTY_VALUE);
      ArrayInitialize(BufferOrange, EMPTY_VALUE);
      ArrayInitialize(BufferBuySignal, EMPTY_VALUE);
      ArrayInitialize(BufferSellSignal, EMPTY_VALUE);
   }
   else
   {
      int lb = MathMax(InpBBPeriod, MathMax(InpSwingLookback,
               MathMax(InpFastMAPeriod, InpSignalMAPeriod)));
      startBar = MathMax(InpRSIPeriod, prev_calculated - 1 - lb);
      startBar = MathMax(startBar, rates_total - InpMaxBars);
   }

   //--- MT5: Ensure indicator handles are ready before calculation
   if(fullRecalc)
   {
      InvalidatePriceCache();
      int barsNeeded = rates_total - startBar;
      string rsiKey = "RSI_" + _Symbol + "_" + IntegerToString((int)_Period) + "_" +
                      IntegerToString(InpRSIPeriod) + "_" + IntegerToString((int)InpPrice);
      int rsiHandle = GetCachedIndicatorHandle(rsiKey, 2, _Symbol, _Period, InpRSIPeriod, (int)InpPrice);
      if(rsiHandle != INVALID_HANDLE)
      {
         int barsCalc = BarsCalculated(rsiHandle);
         if(barsCalc < barsNeeded)
            return(0);
      }
   }
   //--- Calculate RSI lines
   CalculateRSILines(startBar, rates_total);

   //--- Signal detection range
   int sigStart = MathMax(startBar, InpRSIPeriod + InpBBPeriod + 2);
   sigStart = MathMax(sigStart, InpRSIPeriod + InpSignalMAPeriod + 2);

   if(!fullRecalc)
   {
      int keepCount = 0;
      for(int s = 0; s < g_signalCount; s++)
      {
         if(g_signals[s].barIndex < sigStart)
            keepCount++;
         else
            break;
      }
      g_signalCount = keepCount;
      ArrayResize(g_signals, g_signalCount);
   }

   //=================================================================
   // SIGNAL DETECTION
   //=================================================================
   for(int i = sigStart; i < rates_total; i++)
   {
      BufferBuySignal[i]  = EMPTY_VALUE;
      BufferSellSignal[i] = EMPTY_VALUE;
      bool isCurrentBar = (i == rates_total - 1);

      if(BufferGreen[i]   == EMPTY_VALUE || BufferGreen[i-1]  == EMPTY_VALUE) continue;
      if(BufferRed[i]     == EMPTY_VALUE || BufferRed[i-1]    == EMPTY_VALUE) continue;
      if(BufferOrange[i]  == EMPTY_VALUE) continue;
      if(BufferBBUpper[i] == EMPTY_VALUE || BufferBBLower[i]  == EMPTY_VALUE) continue;

      bool greenCrossUp   = (BufferGreen[i-1] <= BufferRed[i-1]) && (BufferGreen[i] > BufferRed[i]);
      bool greenCrossDown = (BufferGreen[i-1] >= BufferRed[i-1]) && (BufferGreen[i] < BufferRed[i]);

      double greenDelta = 0.0;
      if(i >= 2 && BufferGreen[i-2] != EMPTY_VALUE)
         greenDelta = BufferGreen[i] - BufferGreen[i-2];

      double adaptiveThresh = GetNormalizedAngleThreshold(i, BufferGreen);
      bool strongAngleUp    = (greenDelta >= adaptiveThresh);
      bool strongAngleDown  = (greenDelta <= -adaptiveThresh);

      // Cooldown: skip if too close to previous signal
      if(InpCooldownBars > 0 && g_signalCount > 0)
      {
         int lastBar = g_signals[g_signalCount-1].barIndex;
         if(i - lastBar < InpCooldownBars) continue;
      }

      int buySignal  = 0;
      int sellSignal = 0;
      // Priority: Case 6→2→4→3→1→5→7 (optimized for M1/M5)
      if(InpEnableCase6 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase6_Buy(i))       buySignal  = 6;
         else if(CheckCase6_Sell(i)) sellSignal = 6;
      }
      if(InpEnableCase2 && buySignal == 0 && sellSignal == 0)
      {
         if(greenCrossUp && strongAngleUp && CheckCase2_Buy(i, low))          buySignal = 2;
         else if(greenCrossDown && strongAngleDown && CheckCase2_Sell(i, high)) sellSignal = 2;
      }
      if(InpEnableCase4 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase4_Buy(i))       buySignal  = 4;
         else if(CheckCase4_Sell(i)) sellSignal = 4;
      }
      if(InpEnableCase3 && buySignal == 0 && sellSignal == 0)
      {
         if(greenCrossUp && strongAngleUp && CheckCase3_Buy(i, low))          buySignal = 3;
         else if(greenCrossDown && strongAngleDown && CheckCase3_Sell(i, high)) sellSignal = 3;
      }
      if(InpEnableCase1 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase1_Buy(i))       buySignal  = 1;
         else if(CheckCase1_Sell(i)) sellSignal = 1;
      }
      if(InpEnableCase5 && buySignal == 0 && sellSignal == 0)
      {
         if(greenCrossUp && strongAngleUp && CheckCase5_Buy(i))          buySignal = 5;
         else if(greenCrossDown && strongAngleDown && CheckCase5_Sell(i)) sellSignal = 5;
      }
      if(InpEnableCase7 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase7_Buy(i))       buySignal  = 7;
         else if(CheckCase7_Sell(i)) sellSignal = 7;
      }

      //--- Current bar: buffer only
      if(isCurrentBar)
      {
         if(buySignal > 0) BufferBuySignal[i] = (double)buySignal;
         if(sellSignal > 0) BufferSellSignal[i] = (double)sellSignal;
         if((buySignal > 0 || sellSignal > 0) && time[i] != g_lastAlertTime)
         {
            g_lastAlertTime = time[i];
            string alertMsg = Symbol() + " " + GetTimeframeString() + " [FORMING]: ";
            if(buySignal > 0)
               alertMsg += "BUY Case " + IntegerToString(buySignal) +
                           " (" + GetCaseName(buySignal) + ")";
            if(sellSignal > 0)
               alertMsg += "SELL Case " + IntegerToString(sellSignal) +
                           " (" + GetCaseName(sellSignal) + ")";
            if(InpAlertPopup) Alert(alertMsg);
            if(InpAlertSound) PlaySound(InpAlertSoundFile);
         }
         continue;
      }

      if(buySignal > 0)
      {
         BufferBuySignal[i] = (double)buySignal;
         CreateSignalArrow(time[i], low[i], true, buySignal);
         double baseEntry = (i < rates_total - 1) ? open[i + 1] : close[i];
         double atrNow = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
         double maxSlippage = atrNow * 0.15;
         double entryPrice = MathMin(baseEntry + maxSlippage, close[i] + atrNow * 0.3);
         entryPrice = MathMax(entryPrice, baseEntry);
         double sl, tp1, tp2, tp3, atrVal;
         CalculateSLTP(true, i, entryPrice, high, low, rates_total,
                       sl, tp1, tp2, tp3, atrVal);
         double slDist  = MathAbs(entryPrice - sl);
         double tp1Dist = MathAbs(tp1 - entryPrice);
         double maxSLDist = atrVal * InpSLRatio;
         if(slDist > maxSLDist * 1.5) sl = entryPrice - maxSLDist;
         slDist = MathAbs(entryPrice - sl);
         if(slDist > 0 && tp1Dist / slDist < 1.0) sl = entryPrice - tp1Dist;
         // SL floor: signal bar ATR may be tiny (quiet moment before a spike).
         // Without floor, SL = 2 pts vs TP1 = 55 pts → Gambler's Ruin outputs W:1%,
         // wasting signal display. Minimum = 30% of current-bar ATR × ratio.
         {
            double curATR = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
            double minSLDist = curATR * InpSLRatio * 0.3;
            slDist = MathAbs(entryPrice - sl);
            if(slDist < minSLDist) { sl = entryPrice - minSLDist; slDist = minSLDist; }
         }
         double angleZ = CalculateAngleStrength(i); // Z-score of Green momentum
         double curSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
         int sigSessBlock = GetSessionBlock(time[i]);
         StoreSignal(time[i], i, buySignal, true, entryPrice, sl, tp1, tp2, tp3, atrVal, angleZ,
                     curSpread, sigSessBlock, BufferGreen[i]);
         TrackSignalForSession(time[i], buySignal, true, entryPrice, sl, tp1);
         LogSignalEntry(time[i], buySignal, true, entryPrice, sl, tp1, tp2, tp3, atrVal,
                        sigSessBlock, angleZ);
         LogOutcomePending(time[i], buySignal, true);
      }
      if(sellSignal > 0)
      {
         BufferSellSignal[i] = (double)sellSignal;
         CreateSignalArrow(time[i], high[i], false, sellSignal);
         double baseEntry = (i < rates_total - 1) ? open[i + 1] : close[i];
         double atrNow = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
         double maxSlippage = atrNow * 0.15;
         double entryPrice = MathMax(baseEntry - maxSlippage, close[i] - atrNow * 0.3);
         entryPrice = MathMin(entryPrice, baseEntry);
         double sl, tp1, tp2, tp3, atrVal;
         CalculateSLTP(false, i, entryPrice, high, low, rates_total,
                       sl, tp1, tp2, tp3, atrVal);
         double slDist  = MathAbs(sl - entryPrice);
         double tp1Dist = MathAbs(entryPrice - tp1);
         double maxSLDist = atrVal * InpSLRatio;
         if(slDist > maxSLDist * 1.5) sl = entryPrice + maxSLDist;
         slDist = MathAbs(sl - entryPrice);
         if(slDist > 0 && tp1Dist / slDist < 1.0) sl = entryPrice + tp1Dist;
         // SL floor: same as BUY — prevent degenerate SL from low-ATR signal bar.
         {
            double curATR = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
            double minSLDist = curATR * InpSLRatio * 0.3;
            slDist = MathAbs(sl - entryPrice);
            if(slDist < minSLDist) { sl = entryPrice + minSLDist; slDist = minSLDist; }
         }
         double angleZ = CalculateAngleStrength(i); // Z-score of Green momentum
         double curSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
         int sigSessBlock = GetSessionBlock(time[i]);
         StoreSignal(time[i], i, sellSignal, false, entryPrice, sl, tp1, tp2, tp3, atrVal, angleZ,
                     curSpread, sigSessBlock, BufferGreen[i]);
         TrackSignalForSession(time[i], sellSignal, false, entryPrice, sl, tp1);
         LogSignalEntry(time[i], sellSignal, false, entryPrice, sl, tp1, tp2, tp3, atrVal,
                        sigSessBlock, angleZ);
         LogOutcomePending(time[i], sellSignal, false);
      }

      //--- Alert on newly closed bar
      if(i == rates_total - 2 && (buySignal > 0 || sellSignal > 0))
      {
         if(time[i] != g_lastAlertTime)
         {
            g_lastAlertTime = time[i];
            string alertMsg = Symbol() + " " + GetTimeframeString() + " RSI Advanced: ";
            if(buySignal > 0)
               alertMsg += "BUY Case " + IntegerToString(buySignal) +
                           " (" + GetCaseName(buySignal) + ")";
            if(sellSignal > 0)
               alertMsg += "SELL Case " + IntegerToString(sellSignal) +
                           " (" + GetCaseName(sellSignal) + ")";
            if(InpAlertPopup) Alert(alertMsg);
            if(InpAlertSound) PlaySound(InpAlertSoundFile);
         }
      }
   }

   // After fullRecalc scan: load old signals from binary and merge.
   // These signals predate the current InpMaxBars window and give Tier 1/2
   // access to historical data without rescanning the entire price history.
   if(fullRecalc)
      LoadAndMergeSignalsBinary();

   //=================================================================
   // V11: Update multi-source data
   //=================================================================
   static datetime s_lastBarTime = 0;
   datetime currentBarTime = iTime(NULL, 0, 0);
   bool isNewBar = (currentBarTime != s_lastBarTime);

   // Lightweight: every tick
   RefreshIntermarketData();
   CheckPendingOutcomes();
   CheckAndLogNewlyResolved();

   // Heavy: only per new bar
   if(isNewBar)
   {
      UpdateSpreadRegime();
      s_lastBarTime = currentBarTime;
      FlushLogQueues();
      UpdateSessionStats();
      CalculateRollingPerformance();
      CalculateWalkForwardMetrics();

      // Memory management: cap outcomes at 500
      if(g_outcomeCount > 500)
      {
         int removeCount = g_outcomeCount - 500;
         for(int i2 = 0; i2 < 500; i2++)
            g_outcomes[i2] = g_outcomes[i2 + removeCount];
         g_outcomeCount = 500;
         ArrayResize(g_outcomes, 500);
      }
   }

   //=================================================================
   // UPDATE DISPLAY
   //=================================================================
   if(g_signalCount > 0)
   {
      // Declare all display-state statics first so they're in scope for the whole block
      static uint    s_lastDrawTick = 0;
      static double  s_lastDrawPrice = 0;
      static int     s_lastDrawSignalIdx = -1;
      static bool    s_lastInvalidated = false;
      static bool    s_sltpDrawn = false;
      static bool    s_zonesDrawn = false;
      static bool    s_lastSuppressMode = false;
      static bool    s_invalidatedSticky = false;

      // Auto-switch to latest signal when new signal appears
      static int s_prevSignalCount = 0;
      if(g_signalCount > s_prevSignalCount && s_prevSignalCount > 0)
         g_userSelectedSignal = false;
      s_prevSignalCount = g_signalCount;

      if(!g_userSelectedSignal)
         g_activeSignalIndex = g_signalCount - 1;
      else if(g_activeSignalIndex < 0 || g_activeSignalIndex >= g_signalCount)
      {
         g_activeSignalIndex = g_signalCount - 1;
         g_userSelectedSignal = false;
      }
      if(g_activeSignalIndex != s_lastDrawSignalIdx)
         s_invalidatedSticky = false;
      SignalData activeSig = g_signals[g_activeSignalIndex];
      double curPrice = iClose(NULL, 0, 0);

      bool rawInvalidated = false;
      if(activeSig.isBuySignal && curPrice <= activeSig.stopLoss)
         rawInvalidated = true;
      if(!activeSig.isBuySignal && curPrice >= activeSig.stopLoss)
         rawInvalidated = true;

      bool signalInvalidated = rawInvalidated;
      if(s_invalidatedSticky && !rawInvalidated)
      {
         double margin = activeSig.atrValue * 0.1;
         if(activeSig.isBuySignal && curPrice < activeSig.stopLoss + margin)
            signalInvalidated = true;
         if(!activeSig.isBuySignal && curPrice > activeSig.stopLoss - margin)
            signalInvalidated = true;
      }

      if(signalInvalidated && !s_invalidatedSticky)
      {
         DeleteObjectsByPrefix(PREFIX_PROB);
         DeleteObjectsByPrefix(PREFIX_ZONE);
         g_validZoneCount = 0;
         g_recommendedZoneCount = 0;
         s_sltpDrawn  = false;
         s_zonesDrawn = false;

         // Auto-switch to latest signal when current is invalidated
         if(g_userSelectedSignal && g_signalCount > 0 &&
            g_activeSignalIndex < g_signalCount - 1)
         {
            g_activeSignalIndex = g_signalCount - 1;
            g_userSelectedSignal = false;
         }
      }
      s_invalidatedSticky = signalInvalidated;

      //--- Throttle: only redraw display at controlled intervals

      uint currentTick = GetTickCount();
      bool forceRedraw = false;

      // Force redraw conditions:
      // 1. New signal appeared
      if(g_activeSignalIndex != s_lastDrawSignalIdx)
         forceRedraw = true;
      // 2. Invalidation state changed
      if(signalInvalidated != s_lastInvalidated)
         forceRedraw = true;
      // 3. New bar (isNewBar already calculated above)
      if(isNewBar)
         forceRedraw = true;
      // 4. Price moved > 10% ATR — threshold was 0.5% (0.005) which fired every tick
      double priceDelta = MathAbs(curPrice - s_lastDrawPrice);
      if(activeSig.atrValue > 0 && priceDelta > activeSig.atrValue * 0.1)
         forceRedraw = true;
      // 5. Minimum time between redraws: 200ms
      if(!forceRedraw && (currentTick - s_lastDrawTick) < 200)
      {
         // Skip redraw this tick
      }
      else
      {
         // Proceed with redraw
         s_lastDrawTick = currentTick;
         s_lastDrawPrice = curPrice;
         s_lastDrawSignalIdx = g_activeSignalIndex;
         s_lastInvalidated = signalInvalidated;

         if(InpShowMTF && (isNewBar || forceRedraw)) RefreshMTFData();
         if(InpShowProbability) CalculateProbability(g_activeSignalIndex);
         if(g_intermarket.isAvailable)
            GetIntermarketScore(activeSig.isBuySignal);

         bool suppressDisplay = false;
         if(!signalInvalidated)
         {
            int mtfAgree = 0;
            if(InpShowMTF && g_mtfCount > 0) mtfAgree = CalculateMTFAgreement();
            double slDist  = MathAbs(activeSig.entryPrice - activeSig.stopLoss);
            double tp1Dist = MathAbs(activeSig.takeProfit1 - activeSig.entryPrice);
            TradeRecommendation rec = GetTradeRecommendation(
               activeSig.caseNumber, activeSig.isBuySignal,
               g_currentProb.probTP1, g_currentProb.probSL,
               g_currentProb.totalSamples, mtfAgree,
               slDist, tp1Dist, activeSig.atrValue, activeSig.signalTime);
            if(rec.level == REC_AVOID || rec.level == REC_COUNTER_TREND || rec.level == REC_WAIT)
               suppressDisplay = true;

            if(InpEnableSignalLog && activeSig.signalTime != s_lastLoggedScoreTime)
            {
               s_lastLoggedScoreTime = activeSig.signalTime;
               MqlDateTime sigDt;
               TimeToStruct(activeSig.signalTime, sigDt);
               int mtfAgreePctLog = (int)(rec.mtfAlignRatio * 100);
               string mtfTrendStr = (mtfAgreePctLog > 50) ? "BULL" : (mtfAgreePctLog < -50 ? "BEAR" : "NEUTRAL");
               double rrLog = (slDist > 0) ? tp1Dist / slDist : 0;
               LogScoringSnapshot(
                  activeSig.signalTime, activeSig.caseNumber, activeSig.isBuySignal,
                  rec.confidence, rec.label,
                  g_currentProb.probTP1, g_currentProb.probSL, g_currentProb.totalSamples,
                  rec.ev, rrLog, mtfAgreePctLog, mtfTrendStr,
                  activeSig.angleStrength, sigDt.hour, sigDt.day_of_week,
                  g_spreadRegime.spreadRatio, g_walkForward.isRobust);
            }
         }

         DrawInfoPanel(g_activeSignalIndex);

         bool modeChanged = (suppressDisplay != s_lastSuppressMode);
         s_lastSuppressMode = suppressDisplay;

         if(!signalInvalidated)
         {
            if(!s_sltpDrawn || forceRedraw || modeChanged)
            {
               DrawSLTPLines(g_activeSignalIndex, suppressDisplay);
               s_sltpDrawn = true;
            }

            bool needZoneRedraw = !s_zonesDrawn
                                  || g_activeSignalIndex != s_lastDrawSignalIdx
                                  || isNewBar;
            if(!suppressDisplay && needZoneRedraw)
            {
               CalculateEntryZones(
                  activeSig.isBuySignal, activeSig.barIndex,
                  activeSig.entryPrice, activeSig.stopLoss, activeSig.takeProfit1,
                  activeSig.atrValue, high, low, rates_total);
               DrawZoneLines(false);
               s_zonesDrawn = true;
            }
            else if(suppressDisplay && s_zonesDrawn)
            {
               DeleteObjectsByPrefix(PREFIX_ZONE);
               s_zonesDrawn = false;
            }

            if(InpShowProbability) DrawProbabilityLabels(suppressDisplay);
         }
         else
         {
            if(!s_sltpDrawn || forceRedraw)
            {
               DrawSLTPLines(g_activeSignalIndex, true);
               s_sltpDrawn = true;
            }
            if(s_zonesDrawn)
            {
               DeleteObjectsByPrefix(PREFIX_ZONE);
               s_zonesDrawn = false;
            }
         }
      }
   }
   else
   {
      if(InpShowMTF) RefreshMTFData();
      DrawInfoPanel(-1);
   }

   if(s_scoringQueueCount > 0) FlushLogQueues();

   return(rates_total);
}
//+------------------------------------------------------------------+
