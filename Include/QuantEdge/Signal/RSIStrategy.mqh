//+------------------------------------------------------------------+
//|                                             RSIStrategy.mqh       |
//|                     QuantEdge - RSI Signal Strategy (Cases 1-9)  |
//+------------------------------------------------------------------+
#ifndef QE_RSISTRATEGY_MQH
#define QE_RSISTRATEGY_MQH

#include "ISignalSource.mqh"
#include "RSICore.mqh"
#include "SwingDetection.mqh"
#include "SignalCases.mqh"
#include "../Analysis/MarketRegime.mqh"
#include "../Analysis/Normalize.mqh"

//+------------------------------------------------------------------+
//| RSI_Detect — single-pass case chain returning SignalResult         |
//+------------------------------------------------------------------+
SignalResult RSI_Detect(int i, int rates_total,
                        const double &high[], const double &low[],
                        const double &close[], const datetime &time[])
{
   SignalResult result;
   result.caseNumber     = 0;
   result.isBuy          = false;
   result.indicatorValue = 0.0;
   result.angleStrength  = 0.0;
   result.confidence     = 0.0;

   //--- Buffer validation
   if(BufferGreen[i]   == EMPTY_VALUE || BufferGreen[i-1]  == EMPTY_VALUE) return(result);
   if(BufferRed[i]     == EMPTY_VALUE || BufferRed[i-1]    == EMPTY_VALUE) return(result);
   if(BufferOrange[i]  == EMPTY_VALUE) return(result);
   if(BufferBBUpper[i] == EMPTY_VALUE || BufferBBLower[i]  == EMPTY_VALUE) return(result);

   //--- Crossover detection
   bool greenCrossUp   = (BufferGreen[i-1] <= BufferRed[i-1]) && (BufferGreen[i] > BufferRed[i]);
   bool greenCrossDown = (BufferGreen[i-1] >= BufferRed[i-1]) && (BufferGreen[i] < BufferRed[i]);

   //--- Angle computation
   double greenDelta = 0.0;
   if(i >= 2 && BufferGreen[i-2] != EMPTY_VALUE)
      greenDelta = BufferGreen[i] - BufferGreen[i-2];
   double adaptiveThresh = GetNormalizedAngleThreshold(i, BufferGreen);
   bool strongAngleUp    = (greenDelta >= adaptiveThresh);
   bool strongAngleDown  = (greenDelta <= -adaptiveThresh);

   //--- Session block (for Case 6 filter)
   int _sb = GetSessionBlock(time[i]);

   //--- Case priority chain: 6→2→4→3→1→5→7→8→9
   int buySignal  = 0;
   int sellSignal = 0;

   if(GetActiveCaseEnabled(6) && buySignal == 0 && sellSignal == 0)
   {
      if(CheckCase6_Buy(i))       buySignal  = 6;
      else if(CheckCase6_Sell(i)) sellSignal = 6;
   }
   if(GetActiveCaseEnabled(2) && buySignal == 0 && sellSignal == 0)
   {
      if(greenCrossUp && strongAngleUp && CheckCase2_Buy(i, low))          buySignal = 2;
      else if(greenCrossDown && strongAngleDown && CheckCase2_Sell(i, high)) sellSignal = 2;
   }
   if(GetActiveCaseEnabled(4) && buySignal == 0 && sellSignal == 0)
   {
      if(CheckCase4_Buy(i))       buySignal  = 4;
      else if(CheckCase4_Sell(i)) sellSignal = 4;
   }
   if(GetActiveCaseEnabled(3) && buySignal == 0 && sellSignal == 0)
   {
      if(greenCrossUp && strongAngleUp && CheckCase3_Buy(i, low))          buySignal = 3;
      else if(greenCrossDown && strongAngleDown && CheckCase3_Sell(i, high)) sellSignal = 3;
   }
   if(GetActiveCaseEnabled(1) && buySignal == 0 && sellSignal == 0)
   {
      if(CheckCase1_Buy(i))       buySignal  = 1;
      else if(CheckCase1_Sell(i)) sellSignal = 1;
   }
   if(GetActiveCaseEnabled(5) && buySignal == 0 && sellSignal == 0)
   {
      if(greenCrossUp && strongAngleUp && CheckCase5_Buy(i))          buySignal = 5;
      else if(greenCrossDown && strongAngleDown && CheckCase5_Sell(i)) sellSignal = 5;
   }
   if(GetActiveCaseEnabled(7) && buySignal == 0 && sellSignal == 0)
   {
      if(CheckCase7_Buy(i))       buySignal  = 7;
      else if(CheckCase7_Sell(i)) sellSignal = 7;
   }
   if(GetActiveCaseEnabled(8) && buySignal == 0 && sellSignal == 0)
   {
      if(greenCrossUp && strongAngleUp && CheckCase8_Buy(i))            buySignal  = 8;
      else if(greenCrossDown && strongAngleDown && CheckCase8_Sell(i))  sellSignal = 8;
   }
   if(GetActiveCaseEnabled(9) && buySignal == 0 && sellSignal == 0)
   {
      if(greenCrossUp && CheckCase9_Buy(i))            buySignal  = 9;
      else if(greenCrossDown && CheckCase9_Sell(i))    sellSignal = 9;
   }

   //--- Session-hard filter: Case 6 blocked in Asian/LateNY
   if(buySignal == 6 || sellSignal == 6)
   {
      if((InpHardCase6Asian  && _sb == 0) ||
         (InpHardCase6LateNY && _sb == 3))
      { buySignal = 0; sellSignal = 0; }
   }

   if(buySignal == 0 && sellSignal == 0) return(result);

   //--- Fill result
   int caseNum = (buySignal > 0) ? buySignal : sellSignal;
   double angleZ = CalculateAngleStrength(i, BufferGreen);

   result.caseNumber     = caseNum;
   result.isBuy          = (buySignal > 0);
   result.indicatorValue = BufferGreen[i];
   result.angleStrength  = angleZ;
   result.confidence     = MathMin(angleZ / 3.0, 1.0);

   return(result);
}

//+------------------------------------------------------------------+
string RSI_GetCaseName(int caseNum) { return(GetCaseName(caseNum)); }
string RSI_GetSourceName()          { return("RSI"); }
void   RSI_Calculate(int startBar, int rates_total) { CalculateRSILines(startBar, rates_total); }

#endif
