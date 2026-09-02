//+------------------------------------------------------------------+
//|                                         QuantEdge_RSI.mq5           |
//|                         QuantEdge_RSI - MT5 Version                 |
//|                         Master Trading Wave Community               |
//|                                                                    |
//| Architecture:                                                      |
//|   MQLCompat.mqh wraps all MQL4 functions for MQL5                  |
//|   All .mqh logic files remain unchanged                            |
//|   This file replaces QuantEdge_RSI.mq4 for MT5 compilation          |
//+------------------------------------------------------------------+
#property description "QuantEdge RSI Signal Engine"
#property description " "
#property description "Signal Detection: V9.00 proven logic"
#property description "+ Adaptive angle threshold (Kaufman 1995, Ehlers 2001)"
#property description "+ Realistic entry price (open[i+1] / ask / bid)"
#property description "+ Signal only on closed bars"
#property description "+ Multi-Entry Zone System (Dalton 1993, Van Tharp 1998)"
#property description "+ V11: Intermarket + Session + WalkForward + Spread"
#property copyright "Master Trading Wave"
#property link      "https://mastertradingwave.com"
#property version "10.20"
#property strict
#property indicator_separate_window
#property indicator_minimum    0
#property indicator_maximum    100
#property indicator_buffers    25
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

//--- Buffers 8-25: data-only (no plot), readable by EA via CopyBuffer/iCustom

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
//--- SLTP output buffers (readable by EA via iCustom)
double BufferEntry[];  // 7: entry price at signal bar
double BufferSL[];     // 8: stop loss price
double BufferTP1[];    // 9: take profit 1 price
double BufferTP2[];    // 10: take profit 2 price
//--- Probability/Recommendation output buffers (readable by EA via iCustom)
double BufferProbTP1[];            // 11
double BufferProbTP2[];            // 12
double BufferProbTP3[];            // 13
double BufferProbSL[];             // 14
double BufferProbSamples[];        // 15
double BufferProbDecayedTP1[];     // 16
double BufferProbSurvivalRatio[];  // 17
double BufferProbExpiresMin[];     // 18
double BufferXGBProbTP1[];         // 19
double BufferXGBActive[];          // 20
double BufferRecLevel[];           // 21
double BufferRecConfidence[];      // 22
double BufferRecEV[];              // 23
double BufferRecSuggestedRisk[];   // 24

//--- Includes: MQLCompat MUST be first (wraps MQL4 functions)
#include <QuantEdge/Core/MQLCompat.mqh>
#include <QuantEdge/Core/Config.mqh>
#include <QuantEdge/Core/Structs.mqh>
#include <QuantEdge/Core/Globals.mqh>
#include <QuantEdge/Core/MathUtils.mqh>
#include <QuantEdge/Analysis/Normalize.mqh>
#include <QuantEdge/Signal/CandleNormalize.mqh>
#include <QuantEdge/Signal/SignalDetector.mqh>
#include <QuantEdge/Engine/SLTP.mqh>
#include <QuantEdge/Engine/SLTPOptimizer.mqh>
#include <QuantEdge/Engine/MTFEngine.mqh>
#include <QuantEdge/Analysis/IntermarketAnalysis.mqh>
#include <QuantEdge/Analysis/SessionStatistics.mqh>
#include <QuantEdge/Engine/WalkForward.mqh>
#include <QuantEdge/Engine/ProbabilityEngine.mqh>
#include <QuantEdge/Engine/CalibrationEngine.mqh>
#include <QuantEdge/AI/XGBIntegration.mqh>
#include <QuantEdge/Display/ArrowManager.mqh>
#include <QuantEdge/Display/LineDrawing.mqh>
#include <QuantEdge/Display/PanelDrawing.mqh>
#include <QuantEdge/Display/ChartEvents.mqh>
#include <QuantEdge/Data/SignalLogger.mqh>
#include <QuantEdge/Engine/VirtualTradeTracker.mqh>

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRSIPeriod < 2 || InpFastMAPeriod < 1 || InpSignalMAPeriod < 1 || InpBBPeriod < 2)
      return(INIT_PARAMETERS_INCORRECT);
   if(InpBBDeviation <= 0 || InpSLRatio <= 0 || InpTPRatio <= 0)
      return(INIT_PARAMETERS_INCORRECT);

   int totalBars = iBars(_Symbol, 0);
   if(totalBars > 100000)
      PrintFormat("[QuantEdge] WARNING: %d bars loaded — high memory usage (%d MB for %d buffers). "
                  "Reduce Tools → Options → Charts → Max bars in chart to 50000-65000.",
                  totalBars, totalBars * 25 * 8 / 1024 / 1024, 25);

   //--- MQL5 SetIndexBuffer requires INDICATOR_DATA / INDICATOR_CALCULATIONS
   SetIndexBuffer(0, BufferGreen,     INDICATOR_DATA);
   SetIndexBuffer(1, BufferRed,       INDICATOR_DATA);
   SetIndexBuffer(2, BufferBBUpper,   INDICATOR_DATA);
   SetIndexBuffer(3, BufferBBLower,   INDICATOR_DATA);
   SetIndexBuffer(4, BufferOrange,    INDICATOR_DATA);
   SetIndexBuffer(5, BufferBuySignal, INDICATOR_DATA);
   SetIndexBuffer(6, BufferSellSignal,INDICATOR_DATA);
   SetIndexBuffer(7,  BufferEntry,    INDICATOR_DATA);
   SetIndexBuffer(8,  BufferSL,       INDICATOR_DATA);
   SetIndexBuffer(9,  BufferTP1,      INDICATOR_DATA);
   SetIndexBuffer(10, BufferTP2,      INDICATOR_DATA);
   SetIndexBuffer(11, BufferProbTP1,           INDICATOR_DATA);
   SetIndexBuffer(12, BufferProbTP2,           INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, BufferProbTP3,           INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, BufferProbSL,            INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, BufferProbSamples,       INDICATOR_DATA);
   SetIndexBuffer(16, BufferProbDecayedTP1,    INDICATOR_DATA);
   SetIndexBuffer(17, BufferProbSurvivalRatio, INDICATOR_DATA);
   SetIndexBuffer(18, BufferProbExpiresMin,    INDICATOR_DATA);
   SetIndexBuffer(19, BufferXGBProbTP1,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(20, BufferXGBActive,         INDICATOR_CALCULATIONS);
   SetIndexBuffer(21, BufferRecLevel,          INDICATOR_DATA);
   SetIndexBuffer(22, BufferRecConfidence,     INDICATOR_DATA);
   SetIndexBuffer(23, BufferRecEV,             INDICATOR_DATA);
   SetIndexBuffer(24, BufferRecSuggestedRisk,  INDICATOR_DATA);

   //--- MQL5: arrays are non-series by default in indicators
   //--- Match MQL4 behavior (non-series)
   ArraySetAsSeries(BufferGreen, false);
   ArraySetAsSeries(BufferRed, false);
   ArraySetAsSeries(BufferBBUpper, false);
   ArraySetAsSeries(BufferBBLower, false);
   ArraySetAsSeries(BufferOrange, false);
   ArraySetAsSeries(BufferBuySignal, false);
   ArraySetAsSeries(BufferSellSignal, false);
   ArraySetAsSeries(BufferEntry, false);
   ArraySetAsSeries(BufferSL, false);
   ArraySetAsSeries(BufferTP1, false);
   ArraySetAsSeries(BufferTP2, false);
   ArraySetAsSeries(BufferProbTP1, false);
   ArraySetAsSeries(BufferProbTP2, false);
   ArraySetAsSeries(BufferProbTP3, false);
   ArraySetAsSeries(BufferProbSL, false);
   ArraySetAsSeries(BufferProbSamples, false);
   ArraySetAsSeries(BufferProbDecayedTP1, false);
   ArraySetAsSeries(BufferProbSurvivalRatio, false);
   ArraySetAsSeries(BufferProbExpiresMin, false);
   ArraySetAsSeries(BufferXGBProbTP1, false);
   ArraySetAsSeries(BufferXGBActive, false);
   ArraySetAsSeries(BufferRecLevel, false);
   ArraySetAsSeries(BufferRecConfidence, false);
   ArraySetAsSeries(BufferRecEV, false);
   ArraySetAsSeries(BufferRecSuggestedRisk, false);

   int mb = GetMinBarsRequired();
   for(int i = 0; i < 25; i++)
   {
      SetIndexEmptyValue(i, EMPTY_VALUE);
      SetIndexDrawBegin(i, mb);
   }

   IndicatorShortName("QuantEdge (" + IntegerToString(InpRSIPeriod) +
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
   InitVirtualCSV();

   // Apply auto TF config profile (scalping params per TF when InpAutoTFConfig=true)
   ApplyTFAutoConfig();

   // [GMT-FIX-B3] Initialize H4 candle normalization
   g_gmtNormActive = ShouldNormalizeH4();
   g_gmtBrokerOffset = GetBrokerGMTOffset();
   g_normRecalcDone = false;
   g_gmtMTFNormNeeded = (g_gmtBrokerOffset != 0);
   if(g_gmtNormActive || g_gmtMTFNormNeeded) BuildNormalizedH4Candles();

   // Restore stats on restart AND on TF/symbol switch.
   //   RECOMPILE/PARAMETERS/CHARTCHANGE: load session-stats binary (fast warm restart).
   //   Binary paths are TF-specific Ã¢â‚¬â€ no cross-TF contamination.
   //   Dedup in TrackSignalForSession() prevents double-count when fullRecalc re-tracks.
   int prevReason = UninitializeReason();
   if(prevReason == REASON_RECOMPILE || prevReason == REASON_PARAMETERS ||
      prevReason == REASON_CHARTCHANGE)
   {
      if(!LoadSessionStatsBinary())
         LoadSessionStatsFromOutcomesCSV();
   }
   LoadXGBModels();
   if(InpEnableXGBShadow) LoadXGBShadowModel();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Signals binary: always save (accumulates history across restarts).
   SaveSignalsBinary();
   // [PERF] Session stats binary: save on RECOMPILE/PARAMETERS/CHARTCHANGE for fast warm
   // restart. Binary paths are TF-specific so no cross-TF contamination. fullRecalc + dedup
   // in TrackSignalForSession refreshes any stale data. Only delete on full REMOVE/CLOSE.
   if(reason == REASON_RECOMPILE || reason == REASON_PARAMETERS ||
      reason == REASON_CHARTCHANGE)
   {
      SaveSessionStatsBinary();
   }
   else
   {
      FileDelete(SS_GetBinaryPath());
   }
   FlushLogQueues();
   CloseVirtualCSV();
   // [TF-FIX] Release handles on ANY deinit, including CHARTCHANGE.
   // Stale handles from a prior TF session can return BarsCalculated=-1
   // on switch-back, causing infinite return(0) bounce.
   ReleaseAllHandles();

   SavePanelPosition();
   // [TF-FIX] Only delete chart objects on full remove/close/recompile.
   // CHARTCHANGE: fullRecalc in OnCalculate will clean up once handles are ready,
   // preventing the blank-chart window during BarsCalculated bounce.
   if(reason != REASON_CHARTCHANGE)
   {
      DeleteObjectsByPrefix(PREFIX_ARROW);
      DeleteObjectsByPrefix(PREFIX_OSMON);
      DeleteObjectsByPrefix(PREFIX_PANEL);
      DeleteObjectsByPrefix(PREFIX_EXPLAIN);
      DeleteObjectsByPrefix(PREFIX_LINE);
      DeleteObjectsByPrefix(PREFIX_PROB);
      DeleteObjectsByPrefix(PREFIX_ZONE);
      DeleteObjectsByPrefix(PREFIX_CLOSE);
   }
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
   g_ratesTotal = rates_total;
   CheckXGBReload();
   if(InpEnableXGBShadow) CheckXGBShadowReload();
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
   // New bar added (rates_total increased) keeps cached signals Ã¢â‚¬â€ incremental path handles it.
   bool fullRecalc = (prev_calculated <= 0 || rates_total < g_prevRatesTotal);

   // [TF-FIX] Check handle readiness BEFORE destructive cleanup.
   // Without this, each return(0) bounce wipes objects/signals, leaving the chart blank
   // for multiple ticks until BarsCalculated catches up.
   // Safety: cap bounces at 50 to avoid infinite loop on truly dead handles.
   static int s_handleBounceCount = 0;
   if(fullRecalc && s_handleBounceCount < 50)
   {
      InvalidatePriceCache();
      int barsNeededPre = rates_total - MathMax(InpRSIPeriod, rates_total - InpMaxBars);
      string rsiKeyPre = "RSI_" + _Symbol + "_" + IntegerToString((int)_Period) + "_" +
                         IntegerToString(InpRSIPeriod) + "_" + IntegerToString((int)InpPrice);
      int rsiHandlePre = GetCachedIndicatorHandle(rsiKeyPre, 2, _Symbol, _Period, InpRSIPeriod, (int)InpPrice);
      if(rsiHandlePre != INVALID_HANDLE && BarsCalculated(rsiHandlePre) < barsNeededPre)
      {
         s_handleBounceCount++;
         return(0);
      }

      string atrKeyPre = "ATR_" + _Symbol + "_" + IntegerToString((int)_Period) + "_" +
                         IntegerToString(InpATRPeriod);
      int atrHandlePre = GetCachedIndicatorHandle(atrKeyPre, 1, _Symbol, _Period, InpATRPeriod);
      if(atrHandlePre != INVALID_HANDLE && BarsCalculated(atrHandlePre) < barsNeededPre)
      {
         s_handleBounceCount++;
         return(0);
      }
      s_handleBounceCount = 0;
   }
   else if(fullRecalc)
   {
      s_handleBounceCount = 0;
   }

   if(fullRecalc)
   {
      g_tfGeneration++;
      ArrayResize(g_rawRSI, rates_total);
      ArrayInitialize(g_rawRSI, EMPTY_VALUE);
      DeleteObjectsByPrefix(PREFIX_ARROW);
      DeleteObjectsByPrefix(PREFIX_OSMON);
      DeleteObjectsByPrefix(PREFIX_LINE);
      DeleteObjectsByPrefix(PREFIX_PANEL);
      DeleteObjectsByPrefix(PREFIX_EXPLAIN);
      DeleteObjectsByPrefix(PREFIX_PROB);
      DeleteObjectsByPrefix(PREFIX_ZONE);
      g_signalCount       = 0;
      g_activeSignalIndex = -1;
      g_userSelectedSignal = false;   // [STALE-FIX2] clear any pin on full rebuild
      ArrayResize(g_signals, 0);
      LoggerInit(false);  // [PERF] do NOT wipe CSV logs on fullRecalc (was ~3s FileDelete + data loss
                          //        every TF switch). Forward-only logging below prevents dup rows.
      // [PERF] BuildNormalizedH4Candles already called in OnInit; line 337 refreshes per-tick.
      MTF_InitRamBuffers();  // Rebuild MTF RAM buffers from historical iRSI data
   }
   else if(rates_total > g_prevRatesTotal)
   {
      int oldSize = ArraySize(g_rawRSI);
      ArrayResize(g_rawRSI, rates_total);
      for(int k = oldSize; k < rates_total; k++)
         g_rawRSI[k] = EMPTY_VALUE;
      int cutoffIdx = MathMax(0, rates_total - 1 - InpMaxBars);
      CleanupOldArrows(time[cutoffIdx]);
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
      ArrayInitialize(BufferEntry, EMPTY_VALUE);
      ArrayInitialize(BufferSL, EMPTY_VALUE);
      ArrayInitialize(BufferTP1, EMPTY_VALUE);
      ArrayInitialize(BufferTP2, EMPTY_VALUE);
      ArrayInitialize(BufferProbTP1, EMPTY_VALUE);
      ArrayInitialize(BufferProbTP2, EMPTY_VALUE);
      ArrayInitialize(BufferProbTP3, EMPTY_VALUE);
      ArrayInitialize(BufferProbSL, EMPTY_VALUE);
      ArrayInitialize(BufferProbSamples, EMPTY_VALUE);
      ArrayInitialize(BufferProbDecayedTP1, EMPTY_VALUE);
      ArrayInitialize(BufferProbSurvivalRatio, EMPTY_VALUE);
      ArrayInitialize(BufferProbExpiresMin, EMPTY_VALUE);
      ArrayInitialize(BufferXGBProbTP1, EMPTY_VALUE);
      ArrayInitialize(BufferXGBActive, EMPTY_VALUE);
      ArrayInitialize(BufferRecLevel, EMPTY_VALUE);
      ArrayInitialize(BufferRecConfidence, EMPTY_VALUE);
      ArrayInitialize(BufferRecEV, EMPTY_VALUE);
      ArrayInitialize(BufferRecSuggestedRisk, EMPTY_VALUE);
   }
   else
   {
      int lb = MathMax(InpBBPeriod, MathMax(InpSwingLookback,
               MathMax(InpFastMAPeriod, InpSignalMAPeriod)));
      startBar = MathMax(InpRSIPeriod, prev_calculated - 1 - lb);
      startBar = MathMax(startBar, rates_total - InpMaxBars);
   }

   // [TF-FIX] Handle readiness check moved before destructive cleanup (see above).
   // [GMT-FIX-B3] Refresh normalized H4 candles (internal cache guard skips if no new H1 bar)
   if(g_gmtNormActive || g_gmtMTFNormNeeded) BuildNormalizedH4Candles();

   // [GMT-FIX-B3b] Force full recalc when normalization becomes ready.
   // On MT5, H1 data loads async Ã¢â‚¬â€ first fullRecalc uses native iRSI (wrong GMT).
   // Check buffer directly.
   // Fix: return(0) to force prev_calculated=0 on next tick Ã¢â€ â€™ full RSI + MTF redraw.
   if((g_gmtNormActive || g_gmtMTFNormNeeded) && g_normRSICount > 0 && !g_normRecalcDone)
   {
      g_normRecalcDone = true;
      if(!fullRecalc) return(0);
   }

   //--- Calculate RSI lines
   SignalDetector_Calculate(startBar, rates_total);

   //--- Signal detection range
   int sigStart = MathMax(startBar, InpRSIPeriod + InpBBPeriod + 2);
   sigStart = MathMax(sigStart, InpRSIPeriod + InpSignalMAPeriod + 2);

   if(!fullRecalc)
   {
      while(g_signalCount > 0 && g_signals[g_signalCount-1].barIndex >= rates_total - 1)
         g_signalCount--;
      ArrayResize(g_signals, g_signalCount);
   }

   //=================================================================
   // SIGNAL DETECTION
   //=================================================================
   int _storedIdx = 0;
   while(_storedIdx < g_signalCount && g_signals[_storedIdx].barIndex < sigStart)
      _storedIdx++;

   for(int i = sigStart; i < rates_total; i++)
   {
      BufferBuySignal[i]  = EMPTY_VALUE;
      BufferSellSignal[i] = EMPTY_VALUE;
      BufferEntry[i]      = EMPTY_VALUE;
      BufferSL[i]         = EMPTY_VALUE;
      BufferTP1[i]        = EMPTY_VALUE;
      BufferTP2[i]        = EMPTY_VALUE;
      BufferProbTP1[i]           = EMPTY_VALUE;
      BufferProbTP2[i]           = EMPTY_VALUE;
      BufferProbTP3[i]           = EMPTY_VALUE;
      BufferProbSL[i]            = EMPTY_VALUE;
      BufferProbSamples[i]       = EMPTY_VALUE;
      BufferProbDecayedTP1[i]    = EMPTY_VALUE;
      BufferProbSurvivalRatio[i] = EMPTY_VALUE;
      BufferProbExpiresMin[i]    = EMPTY_VALUE;
      BufferXGBProbTP1[i]        = EMPTY_VALUE;
      BufferXGBActive[i]         = EMPTY_VALUE;
      BufferRecLevel[i]          = EMPTY_VALUE;
      BufferRecConfidence[i]     = EMPTY_VALUE;
      BufferRecEV[i]             = EMPTY_VALUE;
      BufferRecSuggestedRisk[i]  = EMPTY_VALUE;
      if(_storedIdx < g_signalCount && g_signals[_storedIdx].barIndex == i)
      {
         while(_storedIdx < g_signalCount && g_signals[_storedIdx].barIndex == i)
         {
            if(g_signals[_storedIdx].isBuySignal)
               BufferBuySignal[i] = (double)g_signals[_storedIdx].caseNumber;
            else
               BufferSellSignal[i] = (double)g_signals[_storedIdx].caseNumber;
            BufferEntry[i] = g_signals[_storedIdx].entryPrice;
            BufferSL[i]    = g_signals[_storedIdx].stopLoss;
            BufferTP1[i]   = g_signals[_storedIdx].takeProfit1;
            BufferTP2[i]   = g_signals[_storedIdx].takeProfit2;
            _storedIdx++;
         }
         continue;
      }
      bool isCurrentBar = (i == rates_total - 1);


      if(!isCurrentBar) DrawOSCrossMonitor(i, time, low, high);

      SignalResult signal = SignalDetector_Detect(i, rates_total, high, low, close, time);
      if(signal.caseNumber == 0) continue;

      int buySignal  = signal.isBuy  ? signal.caseNumber : 0;
      int sellSignal = !signal.isBuy ? signal.caseNumber : 0;

      //--- Current bar: buffer + alert only
      if(isCurrentBar)
      {
         if(buySignal > 0) BufferBuySignal[i] = (double)buySignal;
         if(sellSignal > 0) BufferSellSignal[i] = (double)sellSignal;
         if(time[i] != g_lastAlertTime)
         {
            g_lastAlertTime = time[i];
            string alertMsg = Symbol() + " " + GetTimeframeString() + " [FORMING]: ";
            if(buySignal > 0)
               alertMsg += "BUY Case " + IntegerToString(buySignal) +
                           " (" + SignalDetector_GetCaseName(buySignal) + ")";
            if(sellSignal > 0)
               alertMsg += "SELL Case " + IntegerToString(sellSignal) +
                           " (" + SignalDetector_GetCaseName(sellSignal) + ")";
            if(InpAlertPopup) Alert(alertMsg);
            if(InpAlertSound) PlaySound(InpAlertSoundFile);
         }
         continue;
      }

      if(buySignal > 0)
      {
         BufferBuySignal[i] = (double)buySignal;
         if(!fullRecalc && i >= rates_total - 2) DeleteOppositeArrows(true);
         CreateSignalArrow(time[i], low[i], true, buySignal);
         double baseEntry = (i < rates_total - 1) ? open[i + 1] : close[i];
         double atrNow = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
         double maxSlippage = atrNow * 0.15;
         double entryPrice = MathMin(baseEntry + maxSlippage, close[i] + atrNow * 0.3);
         entryPrice = MathMax(entryPrice, baseEntry);
         double sl, tp1, tp2, tp3, atrVal;
         CalculateSLTP(true, i, entryPrice, high, low, rates_total,
                       sl, tp1, tp2, tp3, atrVal, buySignal);
         double slDist  = MathAbs(entryPrice - sl);
         double tp1Dist = MathAbs(tp1 - entryPrice);
         double maxSLDist = atrVal * InpSLRatio;
         if(slDist > maxSLDist * 1.5) sl = entryPrice - maxSLDist;
         slDist = MathAbs(entryPrice - sl);
         if(slDist > 0 && tp1Dist / slDist < 1.0) sl = entryPrice - tp1Dist;
         {
            double curATR = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
            double minSLDist = curATR * InpSLRatio * 0.3;
            slDist = MathAbs(entryPrice - sl);
            if(slDist < minSLDist) { sl = entryPrice - minSLDist; slDist = minSLDist; }
         }
         if(InpSLTPMode == SLTP_EV_OPTIMIZED)
         {
            int maxFwd = GetMaxForwardBarsForTimeframe();
            double edgeBuy = MeasureEdgeFromHistory(buySignal, true, maxFwd,
                                                     BufferOrange, BufferBBUpper, BufferBBLower);
            int slLB = GetNormalizedSLLookback();
            double swSL = FindNearestSwingLow(low, i, slLB, rates_total)
                          - GetNormalizedSpreadBuffer() - atrVal * 0.1;
            double vSL = ValidateSLAgainstVolume(true, sl, entryPrice,
                                                  high, low, i, GetActivePriceDistLB(), atrVal);
            SLTPOptResult optRes;
            OptimizeSLTP_EV(true, entryPrice, sl, tp1, tp2, tp3, atrVal, edgeBuy, buySignal,
                            swSL, vSL, sl, tp1, tp2, tp3, optRes);
            slDist  = MathAbs(entryPrice - sl);
            tp1Dist = MathAbs(tp1 - entryPrice);
         }
         double angleZ = signal.angleStrength;
         double curSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
         int sigSessBlock = GetSessionBlock(time[i]);
         StoreSignal(time[i], i, buySignal, true, entryPrice, sl, tp1, tp2, tp3, atrVal, angleZ,
                     curSpread, sigSessBlock, signal.indicatorValue);
         TrackSignalForSession(time[i], buySignal, true, entryPrice, sl, tp1, (i >= rates_total - 2));
         BufferEntry[i] = entryPrice;
         BufferSL[i]    = sl;
         BufferTP1[i]   = tp1;
         BufferTP2[i]   = tp2;
         // [PERF] Probability/recommendation: forward-only in live, all bars in tester
         if(i >= rates_total - 2 || IsBacktestMode())
         {
            int newSigIdx = g_signalCount - 1;
            CalculateProbability(newSigIdx, BufferOrange, BufferBBUpper, BufferBBLower);
            int mtfAgreeBuy = 0;
            if(InpShowMTF && g_mtfCount > 0) mtfAgreeBuy = CalculateMTFAgreement();
            TradeRecommendation recBuy = GetTradeRecommendation(
               buySignal, true, g_currentProb.probTP1, g_currentProb.probSL,
               g_currentProb.totalSamples, mtfAgreeBuy, slDist, tp1Dist, atrVal, time[i]);
            BufferProbTP1[i]            = g_currentProb.probTP1;
            BufferProbTP2[i]            = g_currentProb.probTP2;
            BufferProbTP3[i]            = g_currentProb.probTP3;
            BufferProbSL[i]             = g_currentProb.probSL;
            BufferProbSamples[i]        = g_currentProb.totalSamples;
            BufferProbDecayedTP1[i]     = g_currentProb.decayedProbTP1;
            BufferProbSurvivalRatio[i]  = g_currentProb.survivalRatio;
            BufferProbExpiresMin[i]     = g_currentProb.expiresMinutes;
            BufferXGBProbTP1[i]         = g_currentProb.xgbProbTP1;
            BufferXGBActive[i]          = g_currentProb.xgbActive ? 1.0 : 0.0;
            BufferRecLevel[i]           = (double)recBuy.level;
            BufferRecConfidence[i]      = recBuy.confidence;
            BufferRecEV[i]              = recBuy.ev;
            BufferRecSuggestedRisk[i]   = recBuy.suggestedRisk;
         }
         // [PERF] Log signal + pending ONLY for the just-closed bar (forward-only). Re-logging
         // every historical signal on each fullRecalc is what forced the slow CSV wipe in
         // LoggerInit(true); logging once (when the bar closes) removes both cost and dup rows.
         if(i >= rates_total - 2)
         {
            int    _bs        = rates_total - 1 - i;
            double _atrRatio  = SL_GetATRRatio(_bs);
            double _spreadPips= SL_GetSpreadPips();
            int    _d1Trend   = SL_GetMTFTrendForTF(TF_D1);
            int    _timeInSess= SL_GetTimeInSessionMin(time[i], sigSessBlock);
            LogSignalEntry(time[i], buySignal, true, entryPrice, sl, tp1, tp2, tp3, atrVal,
                           sigSessBlock, angleZ,
                           signal.indicatorValue, _atrRatio, _spreadPips, _d1Trend,
                           GetActiveSLTPMethod(), (bool)InpAutoTFConfig, _timeInSess);
            LogOutcomePending(time[i], buySignal, true);
         }
      }
      if(sellSignal > 0)
      {
         BufferSellSignal[i] = (double)sellSignal;
         if(!fullRecalc && i >= rates_total - 2) DeleteOppositeArrows(false);
         CreateSignalArrow(time[i], high[i], false, sellSignal);
         double baseEntry = (i < rates_total - 1) ? open[i + 1] : close[i];
         double atrNow = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
         double maxSlippage = atrNow * 0.15;
         double entryPrice = MathMax(baseEntry - maxSlippage, close[i] - atrNow * 0.3);
         entryPrice = MathMin(entryPrice, baseEntry);
         double sl, tp1, tp2, tp3, atrVal;
         CalculateSLTP(false, i, entryPrice, high, low, rates_total,
                       sl, tp1, tp2, tp3, atrVal, sellSignal);
         double slDist  = MathAbs(sl - entryPrice);
         double tp1Dist = MathAbs(entryPrice - tp1);
         double maxSLDist = atrVal * InpSLRatio;
         if(slDist > maxSLDist * 1.5) sl = entryPrice + maxSLDist;
         slDist = MathAbs(sl - entryPrice);
         if(slDist > 0 && tp1Dist / slDist < 1.0) sl = entryPrice + tp1Dist;
         {
            double curATR = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
            double minSLDist = curATR * InpSLRatio * 0.3;
            slDist = MathAbs(sl - entryPrice);
            if(slDist < minSLDist) { sl = entryPrice + minSLDist; slDist = minSLDist; }
         }
         if(InpSLTPMode == SLTP_EV_OPTIMIZED)
         {
            int maxFwd = GetMaxForwardBarsForTimeframe();
            double edgeSell = MeasureEdgeFromHistory(sellSignal, false, maxFwd,
                                                      BufferOrange, BufferBBUpper, BufferBBLower);
            int slLB = GetNormalizedSLLookback();
            double swSL = FindNearestSwingHigh(high, i, slLB, rates_total)
                          + GetNormalizedSpreadBuffer() + atrVal * 0.1;
            double vSL = ValidateSLAgainstVolume(false, sl, entryPrice,
                                                  high, low, i, GetActivePriceDistLB(), atrVal);
            SLTPOptResult optRes;
            OptimizeSLTP_EV(false, entryPrice, sl, tp1, tp2, tp3, atrVal, edgeSell, sellSignal,
                            swSL, vSL, sl, tp1, tp2, tp3, optRes);
            slDist  = MathAbs(sl - entryPrice);
            tp1Dist = MathAbs(entryPrice - tp1);
         }
         double angleZ = signal.angleStrength;
         double curSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
         int sigSessBlock = GetSessionBlock(time[i]);
         StoreSignal(time[i], i, sellSignal, false, entryPrice, sl, tp1, tp2, tp3, atrVal, angleZ,
                     curSpread, sigSessBlock, signal.indicatorValue);
         TrackSignalForSession(time[i], sellSignal, false, entryPrice, sl, tp1, (i >= rates_total - 2));
         BufferEntry[i] = entryPrice;
         BufferSL[i]    = sl;
         BufferTP1[i]   = tp1;
         BufferTP2[i]   = tp2;
         // [PERF] Probability/recommendation: forward-only in live, all bars in tester
         if(i >= rates_total - 2 || IsBacktestMode())
         {
            int newSigIdx = g_signalCount - 1;
            CalculateProbability(newSigIdx, BufferOrange, BufferBBUpper, BufferBBLower);
            int mtfAgreeSell = 0;
            if(InpShowMTF && g_mtfCount > 0) mtfAgreeSell = CalculateMTFAgreement();
            TradeRecommendation recSell = GetTradeRecommendation(
               sellSignal, false, g_currentProb.probTP1, g_currentProb.probSL,
               g_currentProb.totalSamples, mtfAgreeSell, slDist, tp1Dist, atrVal, time[i]);
            BufferProbTP1[i]            = g_currentProb.probTP1;
            BufferProbTP2[i]            = g_currentProb.probTP2;
            BufferProbTP3[i]            = g_currentProb.probTP3;
            BufferProbSL[i]             = g_currentProb.probSL;
            BufferProbSamples[i]        = g_currentProb.totalSamples;
            BufferProbDecayedTP1[i]     = g_currentProb.decayedProbTP1;
            BufferProbSurvivalRatio[i]  = g_currentProb.survivalRatio;
            BufferProbExpiresMin[i]     = g_currentProb.expiresMinutes;
            BufferXGBProbTP1[i]         = g_currentProb.xgbProbTP1;
            BufferXGBActive[i]          = g_currentProb.xgbActive ? 1.0 : 0.0;
            BufferRecLevel[i]           = (double)recSell.level;
            BufferRecConfidence[i]      = recSell.confidence;
            BufferRecEV[i]              = recSell.ev;
            BufferRecSuggestedRisk[i]   = recSell.suggestedRisk;
         }
         // [PERF] Forward-only logging (see buy branch): log once when the bar closes.
         if(i >= rates_total - 2)
         {
            int    _bs        = rates_total - 1 - i;
            double _atrRatio  = SL_GetATRRatio(_bs);
            double _spreadPips= SL_GetSpreadPips();
            int    _d1Trend   = SL_GetMTFTrendForTF(TF_D1);
            int    _timeInSess= SL_GetTimeInSessionMin(time[i], sigSessBlock);
            LogSignalEntry(time[i], sellSignal, false, entryPrice, sl, tp1, tp2, tp3, atrVal,
                           sigSessBlock, angleZ,
                           signal.indicatorValue, _atrRatio, _spreadPips, _d1Trend,
                           GetActiveSLTPMethod(), (bool)InpAutoTFConfig, _timeInSess);
            LogOutcomePending(time[i], sellSignal, false);
         }
      }

      //--- Alert on newly closed bar
      if(i == rates_total - 2 && (buySignal > 0 || sellSignal > 0))
      {
         if(time[i] != g_lastAlertTime)
         {
            g_lastAlertTime = time[i];
            string alertMsg = Symbol() + " " + GetTimeframeString() + " QuantEdge: ";
            if(buySignal > 0)
               alertMsg += "BUY Case " + IntegerToString(buySignal) +
                           " (" + SignalDetector_GetCaseName(buySignal) + ")";
            if(sellSignal > 0)
               alertMsg += "SELL Case " + IntegerToString(sellSignal) +
                           " (" + SignalDetector_GetCaseName(sellSignal) + ")";
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
   RefreshUS10YData();
   RefreshADXData();
   RefreshMACDData();
   PublishADXGateState();
   PublishEconBlackoutState();
   CheckPendingOutcomes();
   CheckAndLogNewlyResolved();
   if(InpEnableVirtualTrades)
      UpdateVirtualPositions_Tick(MarketInfo(Symbol(), MODE_BID), MarketInfo(Symbol(), MODE_ASK));

   // Heavy: only per new bar
   if(isNewBar)
   {
      UpdateSpreadRegime();
      s_lastBarTime = currentBarTime;
      FlushLogQueues();
      if(InpEnableVirtualTrades)
         UpdateVirtualPositions_OnBar();
      UpdateSessionStats();
      CalculateRollingPerformance();
      CalculateWalkForwardMetrics();
      UpdateBrierMetrics();
      UpdateXGBBrierMetrics();
      if(InpEnableXGBShadow) UpdateXGBShadowBrierMetrics();

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
      static uint    s_lastDrawTick = 0;
      static double  s_lastDrawPrice = 0;
      static int     s_lastDrawSignalIdx = -1;
      static bool    s_sltpDrawn = false;
      static bool    s_zonesDrawn = false;
      static bool    s_lastSuppressMode = false;

      // Auto-switch to latest signal when new signal appears
      static int s_prevSignalCount = 0;
      static datetime s_prevNewestTime = 0;
      datetime newestTime = (g_signalCount > 0) ? g_signals[g_signalCount-1].signalTime : 0;
      // [STALE-FIX2] Release any override when a genuinely NEWER signal exists.
      // Count alone is masked by the per-tick prune+re-detect (g_signalCount stays
      // constant across ticks); the newest signalTime advancing is NOT masked.
      if((g_signalCount > s_prevSignalCount && s_prevSignalCount > 0) ||
         (newestTime > s_prevNewestTime && s_prevNewestTime > 0))
      {
         g_userSelectedSignal = false;
      }
      s_prevSignalCount = g_signalCount;
      s_prevNewestTime  = newestTime;

      double curPrice = iClose(NULL, 0, 0);

      if(!g_userSelectedSignal)
         g_activeSignalIndex = g_signalCount - 1;
      else if(g_activeSignalIndex < 0 || g_activeSignalIndex >= g_signalCount)
      {
         g_activeSignalIndex = g_signalCount - 1;
         g_userSelectedSignal = false;
      }
      if(g_activeSignalIndex != s_lastDrawSignalIdx)
      {
         s_zonesDrawn = false;
         s_sltpDrawn  = false;
      }
      SignalData activeSig = g_signals[g_activeSignalIndex];

      //--- Throttle: only redraw display at controlled intervals

      uint currentTick = GetTickCount();
      bool forceRedraw = false;

      if(g_activeSignalIndex != s_lastDrawSignalIdx)
         forceRedraw = true;
      if(isNewBar)
         forceRedraw = true;
      double priceDelta = MathAbs(curPrice - s_lastDrawPrice);
      if(activeSig.atrValue > 0 && priceDelta > activeSig.atrValue * 0.1)
         forceRedraw = true;
      if(!forceRedraw && (currentTick - s_lastDrawTick) < 200)
      {
         // Skip redraw this tick
      }
      else
      {
         s_lastDrawTick = currentTick;
         s_lastDrawPrice = curPrice;
         s_lastDrawSignalIdx = g_activeSignalIndex;

         if(InpShowMTF && (isNewBar || forceRedraw)) RefreshMTFData();
         if(InpShowProbability) CalculateProbability(g_activeSignalIndex, BufferOrange, BufferBBUpper, BufferBBLower);
         if(InpShowProbability && g_activeSignalIndex >= 0 &&
            g_signals[g_activeSignalIndex].predictedProb <= 0 && g_currentProb.probTP1 > 0)
            g_signals[g_activeSignalIndex].predictedProb = g_currentProb.probTP1;
         if(InpProbMode != PROB_CALIBRATION && g_activeSignalIndex >= 0 &&
            g_signals[g_activeSignalIndex].xgbPredictedProb <= 0 && g_currentProb.xgbProbTP1 > 0)
            g_signals[g_activeSignalIndex].xgbPredictedProb = g_currentProb.xgbProbTP1;
         if(InpEnableXGBShadow && g_activeSignalIndex >= 0 &&
            g_signals[g_activeSignalIndex].xgbShadowPredictedProb <= 0 && g_xgbShadowProbTP1 > 0)
            g_signals[g_activeSignalIndex].xgbShadowPredictedProb = g_xgbShadowProbTP1;
         if(g_intermarket.isAvailable)
            GetIntermarketScore(activeSig.isBuySignal);

         bool suppressDisplay = false;
         int mtfAgree = 0;
         if(InpShowMTF && g_mtfCount > 0) mtfAgree = CalculateMTFAgreement();
         double slDist  = MathAbs(activeSig.entryPrice - activeSig.stopLoss);
         double tp1Dist = MathAbs(activeSig.takeProfit1 - activeSig.entryPrice);
         int recN = (int)MathRound(g_currentProb.nEffT1 + g_currentProb.nEffT2);
         TradeRecommendation rec = GetTradeRecommendation(
            activeSig.caseNumber, activeSig.isBuySignal,
            g_currentProb.probTP1, g_currentProb.probSL,
            recN, mtfAgree,
            slDist, tp1Dist, activeSig.atrValue, activeSig.signalTime);
         if(rec.level == REC_AVOID || rec.level == REC_COUNTER_TREND || rec.level == REC_WAIT)
            suppressDisplay = true;
         // Keep chart zone lines in sync with dashboard: dashboard hides its
         // Entry Zones section once SL is breached (PanelDrawing.mqh isInvalidated),
         // so suppress chart zone lines on the same condition.
         bool isInvalidated = false;
         if(activeSig.isBuySignal  && curPrice <= activeSig.stopLoss) isInvalidated = true;
         if(!activeSig.isBuySignal && curPrice >= activeSig.stopLoss) isInvalidated = true;
         if(isInvalidated) suppressDisplay = true;

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
               g_spreadRegime.spreadRatio, g_walkForward.isRobust,
               SL_GetMTFTrendForTF(TF_H4), SL_GetMTFTrendForTF(TF_H1),
               g_currentProb.rawCountT1, g_currentProb.rawCountT2,
               g_currentProb.countT3, g_currentProb.realPct,
               g_currentProb.xgbProbTP1,
               InpUseADXFilter ? GetADXValue(1) : 0.0,
               InpUseMACDFilter ? GetMACDHistogram(1) : 0.0,
               InpUseMACDFilter ? GetMACDHistogramSlope(1) : 0.0,
               g_us10y.isAvailable ? g_us10y.trend : 0.0);
         }

         // Indicator's own panel/dashboard only makes sense on a live chart;
         // when driven by an EA in Strategy Tester, suppress it entirely.
         if(!IsBacktestMode())
         {
            DrawDashboard(g_activeSignalIndex);
            if(InpDashboardMode != DASHBOARD_MANUAL && InpShowProbExplain && g_activeSignalIndex >= 0)
               DrawExplainPanel();
         }

         bool modeChanged = (suppressDisplay != s_lastSuppressMode);
         s_lastSuppressMode = suppressDisplay;

         if(!s_sltpDrawn || forceRedraw || modeChanged)
         {
            DrawSLTPLines(g_activeSignalIndex, suppressDisplay);
            s_sltpDrawn = true;
         }

         if(s_zonesDrawn && g_validZoneCount > 0 &&
            MathAbs(g_entryZones[0].price - activeSig.entryPrice) > _Point)
            s_zonesDrawn = false;
         bool needZoneRedraw = !s_zonesDrawn
                               || g_activeSignalIndex != s_lastDrawSignalIdx;

         // Virtual trade tracking must see EVERY new signal for accurate backtest
         // stats, independent of whether display is suppressed (AVOID/WAIT/COUNTER_TREND).
         static datetime s_lastVirtualSignalTime = 0;
         bool isNewVirtualSignal = InpEnableVirtualTrades
                                   && activeSig.signalTime != s_lastVirtualSignalTime;

         // CalculateEntryZones() populates g_entryZones[], needed both for drawing
         // and for OnNewSignal() (Pullback zone positions) below.
         if(needZoneRedraw || isNewVirtualSignal)
         {
            CalculateEntryZones(
               activeSig.isBuySignal, activeSig.barIndex,
               activeSig.entryPrice, activeSig.stopLoss, activeSig.takeProfit1,
               activeSig.atrValue, high, low, rates_total,
               BufferOrange, BufferBBUpper, BufferBBLower);
         }
         if(!suppressDisplay && needZoneRedraw)
         {
            DrawZoneLines(false);
            s_zonesDrawn = true;
         }

         if(isNewVirtualSignal)
         {
            if(s_lastVirtualSignalTime > 0)
               VP_CloseAllBySignal(s_lastVirtualSignalTime, MarketInfo(Symbol(), MODE_BID), MarketInfo(Symbol(), MODE_ASK));
            OnNewSignal(activeSig);
            s_lastVirtualSignalTime = activeSig.signalTime;
         }

         if(suppressDisplay && s_zonesDrawn)
         {
            DeleteObjectsByPrefix(PREFIX_ZONE);
            s_zonesDrawn = false;
         }

         if(InpShowProbability) DrawProbabilityLabels(suppressDisplay);
         ChartRedraw();
      }
   }
   else
   {
      if(InpShowMTF) RefreshMTFData();
      if(!IsBacktestMode())
      {
         DrawDashboard(-1);
         if(InpDashboardMode != DASHBOARD_MANUAL && InpShowProbExplain)
            DeleteObjectsByPrefix(PREFIX_EXPLAIN);
      }
   }

   if(s_scoringQueueCount > 0) FlushLogQueues();

   return(rates_total);
}
//+------------------------------------------------------------------+
