//+------------------------------------------------------------------+
//|                                         RSI_AdvancedSignal.mq4     |
//|                         RSI Advanced - Main Indicator File          |
//|                         Master Trading Wave Community               |
//|                                                                    |
//| Signal Detection: V9.00 proven logic                               |
//| + Adaptive angle threshold (Kaufman 1995, Ehlers 2001)            |
//| + Realistic entry price (open[i+1] / ask / bid)                   |
//| + Signal only on closed bars                                       |
//+------------------------------------------------------------------+
#property copyright "Master Trading Wave"
#property link      "https://mastertradingwave.com"
#property version "9.00"
#property strict

#property indicator_separate_window
#property indicator_minimum  0
#property indicator_maximum  100
#property indicator_buffers  7

#property indicator_label1  "RSI Fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "BB Upper"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDeepSkyBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "BB Lower"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDeepSkyBlue
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "Baseline"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrOrange
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#property indicator_label6  "BuySignal"
#property indicator_type6   DRAW_NONE

#property indicator_label7  "SellSignal"
#property indicator_type7   DRAW_NONE

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

//--- Includes
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
#include <RSI_Advanced/ProbabilityEngine.mqh>
#include <RSI_Advanced/ArrowManager.mqh>
#include <RSI_Advanced/LineDrawing.mqh>
#include <RSI_Advanced/PanelDrawing.mqh>
#include <RSI_Advanced/ChartEvents.mqh>

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRSIPeriod < 2 || InpFastMAPeriod < 1 || InpSignalMAPeriod < 1 || InpBBPeriod < 2)
      return(INIT_PARAMETERS_INCORRECT);
   if(InpBBDeviation <= 0 || InpSLRatio <= 0 || InpTPRatio <= 0)
      return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0, BufferGreen);
   SetIndexBuffer(1, BufferRed);
   SetIndexBuffer(2, BufferBBUpper);
   SetIndexBuffer(3, BufferBBLower);
   SetIndexBuffer(4, BufferOrange);
   SetIndexBuffer(5, BufferBuySignal);
   SetIndexBuffer(6, BufferSellSignal);

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
   ArrayResize(g_signals, 0);

   LoadPanelPosition();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SavePanelPosition();
   DeleteObjectsByPrefix(PREFIX_ARROW);
   DeleteObjectsByPrefix(PREFIX_PANEL);
   DeleteObjectsByPrefix(PREFIX_LINE);
   DeleteObjectsByPrefix(PREFIX_PROB);
   Comment("");
   ArrayFree(g_rawRSI);
   ArrayResize(g_signals, 0);
   g_signalCount    = 0;
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
   ArraySetAsSeries(time, false);
   ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low, false);
   ArraySetAsSeries(close, false);

   int minBars = GetMinBarsRequired();
   if(rates_total < minBars) return(0);

   //--- Array management
   bool fullRecalc = false;
   if(prev_calculated <= 0 || rates_total != g_prevRatesTotal)
   {
      ArrayResize(g_rawRSI, rates_total);
      ArrayInitialize(g_rawRSI, EMPTY_VALUE);
      fullRecalc = true;
      DeleteObjectsByPrefix(PREFIX_ARROW);
      DeleteObjectsByPrefix(PREFIX_LINE);
      DeleteObjectsByPrefix(PREFIX_PANEL);
      DeleteObjectsByPrefix(PREFIX_PROB);
      g_signalCount       = 0;
      g_activeSignalIndex = -1;
      ArrayResize(g_signals, 0);
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
   //
   // Logic: V9.00 proven (fixed swing depth/lookback)
   // Enhancement: Adaptive angle threshold (Kaufman/Ehlers/Pardo)
   // Enhancement: Signals only on closed bars
   // Enhancement: Realistic entry price
   //=================================================================
   for(int i = sigStart; i < rates_total; i++)
   {
      BufferBuySignal[i]  = EMPTY_VALUE;
      BufferSellSignal[i] = EMPTY_VALUE;

      // Is this bar still forming?
      bool isCurrentBar = (i == rates_total - 1);

      // Validate buffers
      if(BufferGreen[i]   == EMPTY_VALUE || BufferGreen[i-1]  == EMPTY_VALUE) continue;
      if(BufferRed[i]     == EMPTY_VALUE || BufferRed[i-1]    == EMPTY_VALUE) continue;
      if(BufferOrange[i]  == EMPTY_VALUE) continue;
      if(BufferBBUpper[i] == EMPTY_VALUE || BufferBBLower[i]  == EMPTY_VALUE) continue;

      // Crossover detection (V9.00)
      bool greenCrossUp   = (BufferGreen[i-1] <= BufferRed[i-1]) && (BufferGreen[i] > BufferRed[i]);
      bool greenCrossDown = (BufferGreen[i-1] >= BufferRed[i-1]) && (BufferGreen[i] < BufferRed[i]);

      // Angle strength - ADAPTIVE threshold
      // Kaufman (1995): "Fixed thresholds fail across different volatility regimes"
      // Ehlers (2001): "Thresholds should be expressed in terms of noise level"
      // stddev × 1.5 = "strong" relative to normal RSI movement
      double greenDelta = 0.0;
      if(i >= 2 && BufferGreen[i-2] != EMPTY_VALUE)
         greenDelta = BufferGreen[i] - BufferGreen[i-2];

      double adaptiveThresh = GetNormalizedAngleThreshold(i, BufferGreen);
      bool strongAngleUp    = (greenDelta >= adaptiveThresh);
      bool strongAngleDown  = (greenDelta <= -adaptiveThresh);

      // Case detection (V9.00 logic, fixed depth/lookback)
      int buySignal  = 0;
      int sellSignal = 0;

      // Case 1: OB/OS Bounce
      if(InpEnableCase1 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase1_Buy(i))  buySignal  = 1;
         if(CheckCase1_Sell(i)) sellSignal = 1;
      }

      // Case 2: Regular Divergence
      if(InpEnableCase2 && buySignal == 0 && sellSignal == 0)
      {
         if(greenCrossUp && strongAngleUp && CheckCase2_Buy(i, low))
            buySignal = 2;
         if(greenCrossDown && strongAngleDown && CheckCase2_Sell(i, high))
            sellSignal = 2;
      }

      // Case 3: Hidden Divergence
      if(InpEnableCase3 && buySignal == 0 && sellSignal == 0)
      {
         if(greenCrossUp && strongAngleUp && CheckCase3_Buy(i, low))
            buySignal = 3;
         if(greenCrossDown && strongAngleDown && CheckCase3_Sell(i, high))
            sellSignal = 3;
      }

      // Case 4: Strong Trend
      if(InpEnableCase4 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase4_Buy(i))  buySignal  = 4;
         if(CheckCase4_Sell(i)) sellSignal = 4;
      }

      // Case 5: Orange Near Level
      if(InpEnableCase5 && buySignal == 0 && sellSignal == 0)
      {
         if(greenCrossUp && strongAngleUp && CheckCase5_Buy(i))
            buySignal = 5;
         if(greenCrossDown && strongAngleDown && CheckCase5_Sell(i))
            sellSignal = 5;
      }

      // Case 6: Trend Continuation
      if(InpEnableCase6 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase6_Buy(i))  buySignal  = 6;
         if(CheckCase6_Sell(i)) sellSignal = 6;
      }

      // Case 7: Sideway Breakout
      if(InpEnableCase7 && buySignal == 0 && sellSignal == 0)
      {
         if(CheckCase7_Buy(i))  buySignal  = 7;
         if(CheckCase7_Sell(i)) sellSignal = 7;
      }

      //--- Current bar: buffer only, no arrow/signal storage
      if(isCurrentBar)
      {
         if(buySignal > 0) BufferBuySignal[i] = (double)buySignal;
         if(sellSignal > 0) BufferSellSignal[i] = (double)sellSignal;

         // Tentative alert
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

      //--- Closed bars: create arrow + store signal + realistic entry
      if(buySignal > 0)
      {
         BufferBuySignal[i] = (double)buySignal;
         CreateSignalArrow(time[i], low[i], true, buySignal);

         // Elder (1993) Confirmation Entry:
         // Use open of next bar as base entry
         // Add micro-confirmation: if open > close of signal bar → stronger
         double baseEntry = (i < rates_total - 1) ? open[i + 1] : close[i];
         
         // Connors (1995): Small buffer above signal bar close
         // But CAPPED to prevent pushing entry too far
         double atrNow = iATR(NULL, 0, InpATRPeriod, rates_total - 1 - i);
         double maxSlippage = atrNow * 0.15;  // Max 15% ATR above open
         double entryPrice = MathMin(baseEntry + maxSlippage, close[i] + atrNow * 0.3);
         entryPrice = MathMax(entryPrice, baseEntry);  // At least open price

         double sl, tp1, tp2, tp3, atrVal;
         CalculateSLTP(true, i, entryPrice, high, low, rates_total,
                       sl, tp1, tp2, tp3, atrVal);

         // VALIDATE: Force minimum R:R = 1:1.0
         // If swing SL too far → cap SL at ATR × SL_Ratio from entry
         double slDist  = MathAbs(entryPrice - sl);
         double tp1Dist = MathAbs(tp1 - entryPrice);
         double maxSLDist = atrVal * InpSLRatio;
         
         if(slDist > maxSLDist * 1.5)
         {
            // SL too far from entry → cap at ATR-based SL
            sl = entryPrice - maxSLDist;
         }
         
         // Recalculate after cap
         slDist = MathAbs(entryPrice - sl);
         if(slDist > 0 && tp1Dist / slDist < 1.0)
         {
            // Still bad R:R → force SL = TP1 distance (R:R = 1:1)
            sl = entryPrice - tp1Dist;
         }

         StoreSignal(time[i], i, buySignal, true, entryPrice,
                     sl, tp1, tp2, tp3, atrVal);
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
         
         if(slDist > maxSLDist * 1.5)
         {
            sl = entryPrice + maxSLDist;
         }
         
         slDist = MathAbs(sl - entryPrice);
         if(slDist > 0 && tp1Dist / slDist < 1.0)
         {
            sl = entryPrice + tp1Dist;
         }

         StoreSignal(time[i], i, sellSignal, false, entryPrice,
                     sl, tp1, tp2, tp3, atrVal);
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

   //=================================================================
   // UPDATE DISPLAY
   //=================================================================
   if(g_signalCount > 0)
   {
      g_activeSignalIndex = g_signalCount - 1;

      if(InpShowMTF) RefreshMTFData();
      if(InpShowProbability) CalculateProbability(g_activeSignalIndex);

      DrawInfoPanel(g_activeSignalIndex);
      DrawSLTPLines(g_activeSignalIndex);

      if(InpShowProbability) DrawProbabilityLabels();
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
