#ifndef POSITION_SIZING_MQH
#define POSITION_SIZING_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"

struct PositionSizeData
{
   double kellyPct;
   double volScale;
   double brierScale;
   double ddScale;
   double qualityScale;
   double adjustedRiskPct;
   double recommendedLot;
   double maxLot;
   double minLot;
   int    totalWins;
   int    totalLosses;
   double winRate;
   double avgEV;
};

PositionSizeData g_positionSize;

double GetEffectiveRiskPct()
{
   if(InpUseKellyLot && g_positionSize.adjustedRiskPct > 0)
      return g_positionSize.adjustedRiskPct;
   return GetActiveRiskPct();
}

void CalculatePositionSize()
{
   g_positionSize.kellyPct = 0;
   g_positionSize.volScale = 1.0;
   g_positionSize.brierScale = 1.0;
   g_positionSize.ddScale = 1.0;
   g_positionSize.qualityScale = 1.0;
   g_positionSize.adjustedRiskPct = GetActiveRiskPct();
   g_positionSize.recommendedLot = 0;
   g_positionSize.minLot = MarketInfo(Symbol(), MODE_MINLOT);
   g_positionSize.maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   g_positionSize.totalWins = 0;
   g_positionSize.totalLosses = 0;
   g_positionSize.winRate = 0;
   g_positionSize.avgEV = 0;

   // --- Trade Summary from outcomes ---
   int wins = 0, losses = 0;
   double sumEV = 0;
   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0) continue;
      if(g_outcomes[i].outcome == 1)
         wins++;
      else
         losses++;

      if(g_outcomes[i].entryPrice > 0 && g_outcomes[i].stopLoss > 0)
      {
         double slDist = MathAbs(g_outcomes[i].entryPrice - g_outcomes[i].stopLoss);
         if(slDist > 0)
         {
            double tp1Dist = MathAbs(g_outcomes[i].takeProfit1 - g_outcomes[i].entryPrice);
            double rr = tp1Dist / slDist;
            if(g_outcomes[i].outcome == 1)
               sumEV += rr;
            else
               sumEV -= 1.0;
         }
      }
   }
   g_positionSize.totalWins = wins;
   g_positionSize.totalLosses = losses;
   int total = wins + losses;
   if(total > 0)
   {
      g_positionSize.winRate = (double)wins / total * 100.0;
      g_positionSize.avgEV = sumEV / total;
   }

   if(!InpUseKellyLot) return;

   double baseRisk = GetActiveRiskPct();

   // --- Kelly scaling ---
   double kellyPct = g_walkForward.kellyFraction;
   g_positionSize.kellyPct = kellyPct;
   double kellyRisk = baseRisk;
   if(kellyPct > 0)
      kellyRisk = MathMin(kellyPct, baseRisk);
   else
      kellyRisk = baseRisk * 0.25;

   // --- Vol scaling ---
   double volScale = 1.0;
   double atrR = g_volRegime.atrRatio;
   if(atrR > 1.8)
      volScale = 0.5;
   else if(atrR > 1.5)
      volScale = 0.7;
   else if(atrR < 0.6)
      volScale = 1.0;
   g_positionSize.volScale = volScale;

   // --- Brier scaling ---
   double brierScale = 1.0;
   if(g_brierMetrics.samples >= 20)
   {
      double bs = g_brierMetrics.brierScore;
      if(bs >= 0.30)
         brierScale = 0.5;
      else if(bs >= 0.20)
         brierScale = 1.0 - (bs - 0.20) / 0.20;
      else
         brierScale = 1.0;
   }
   g_positionSize.brierScale = brierScale;

   // --- DD scaling (from RiskManager multi-level CB) ---
   double ddScl = g_portfolioRisk.ddScale;
   if(ddScl <= 0) ddScl = 0.0;
   g_positionSize.ddScale = ddScl;

   // --- Signal quality allocation ---
   double qualityScale = 1.0;
   if(InpUseQualityAlloc && g_activeSignalIndex >= 0
      && g_activeSignalIndex < g_signalCount)
   {
      double prob = g_currentProb.probTP1;
      if(prob > 0 && prob < 100)
      {
         double edge = (prob / 100.0 - 0.5) * 2.0;
         qualityScale = 1.0 + edge;
         if(qualityScale < 0.5) qualityScale = 0.5;
         if(qualityScale > 2.0) qualityScale = 2.0;
      }
   }
   g_positionSize.qualityScale = qualityScale;

   // --- Final adjusted risk ---
   double adjusted = kellyRisk * volScale * brierScale * ddScl * qualityScale;
   adjusted = MathMax(adjusted, InpMinRiskPct);
   adjusted = MathMin(adjusted, InpMaxRiskPct);
   if(ddScl <= 0) adjusted = 0;
   g_positionSize.adjustedRiskPct = adjusted;

   // --- Recommended lot for market entry ---
   if(g_activeSignalIndex >= 0 && g_activeSignalIndex < g_signalCount)
   {
      double slDist = MathAbs(g_signals[g_activeSignalIndex].entryPrice
                            - g_signals[g_activeSignalIndex].stopLoss);
      if(slDist > 0 && adjusted > 0)
      {
         double accountBalance = AccountBalance();
         if(accountBalance <= 0) accountBalance = 1000;
         double riskAmount = accountBalance * adjusted / 100.0;

         double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
         double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
         if(tickSize > 0 && tickValue > 0)
         {
            double pipValue = tickValue * (slDist / tickSize);
            if(pipValue > 0)
               g_positionSize.recommendedLot = NormalizeDouble(riskAmount / pipValue, 2);
         }

         g_positionSize.recommendedLot = MathMax(g_positionSize.recommendedLot, g_positionSize.minLot);
         g_positionSize.recommendedLot = MathMin(g_positionSize.recommendedLot, g_positionSize.maxLot);
      }
   }
}

#endif
