//+------------------------------------------------------------------+
//|                                               SLTPOptimizer.mqh  |
//|             QuantEdge - EV-Optimized SL/TP via Gambler's Ruin    |
//|                                                                    |
//| Grid search SL × Newton TP, golden-section refinement.            |
//| Uses CalculateRealMarketProbTP (O(1), stateless) as objective.    |
//| ~100-200 calls per signal, sub-millisecond total.                  |
//+------------------------------------------------------------------+
#ifndef QE_SLTP_OPTIMIZER_MQH
#define QE_SLTP_OPTIMIZER_MQH

#include "../Core/Config.mqh"
#include "../Core/Structs.mqh"
#include "../Analysis/Normalize.mqh"

double _ComputeEV(double edge, double slDist, double tpDist, double atrVal)
{
   double p = CalculateRealMarketProbTP(edge, slDist, tpDist, atrVal);
   double rr = tpDist / MathMax(slDist, atrVal * 0.01);
   return(p * rr - (1.0 - p));
}

//+------------------------------------------------------------------+
//| Newton's method: find TP distance that maximizes EV               |
//| for fixed SL distance and edge.                                    |
//| EV = P(TP) × (TP/SL) − (1 − P(TP))                              |
//| P(TP) = Gambler's Ruin with market corrections                    |
//+------------------------------------------------------------------+
double FindOptimalTP_Newton(double edge, double slDist, double atrVal,
                            int &callCount, int maxIter = 8)
{
   double mu = 2.0 * edge - 1.0;
   if(MathAbs(mu) < 0.001)
      return(slDist * 2.0);

   double s = slDist / MathMax(atrVal, 0.0001);
   double t = s * MathMax(1.0, 1.0 / (2.0 * MathAbs(mu)));
   t = MathMax(s, MathMin(s * 8.0, t));

   for(int iter = 0; iter < maxIter; iter++)
   {
      double tDist = t * atrVal;
      double ev0 = _ComputeEV(edge, slDist, tDist, atrVal);
      callCount++;

      double dt = MathMax(atrVal * 0.01, tDist * 0.01);
      double evP = _ComputeEV(edge, slDist, tDist + dt, atrVal);
      double evM = _ComputeEV(edge, slDist, tDist - dt, atrVal);
      callCount += 2;

      double dEV  = (evP - evM) / (2.0 * dt);
      double d2EV = (evP - 2.0 * ev0 + evM) / (dt * dt);

      if(MathAbs(dEV) < 1e-10) break;
      if(MathAbs(d2EV) < 1e-15) break;

      double step = -dEV / d2EV;
      step = MathMax(-tDist * 0.3, MathMin(tDist * 0.3, step));
      tDist += step;

      tDist = MathMax(slDist, MathMin(slDist * 8.0, tDist));
      t = tDist / MathMax(atrVal, 0.0001);
   }
   return(t * atrVal);
}

//+------------------------------------------------------------------+
//| Golden-section refinement around best TP                           |
//+------------------------------------------------------------------+
double _GoldenRefineTP(double edge, double slDist, double tpCenter,
                       double atrVal, int &callCount, int maxIter = 5)
{
   double lo = tpCenter * 0.92;
   double hi = tpCenter * 1.08;
   lo = MathMax(slDist, lo);
   hi = MathMin(slDist * 8.0, hi);

   for(int iter = 0; iter < maxIter; iter++)
   {
      double tp1 = lo + 0.382 * (hi - lo);
      double tp2 = lo + 0.618 * (hi - lo);
      double ev1 = _ComputeEV(edge, slDist, tp1, atrVal);
      double ev2 = _ComputeEV(edge, slDist, tp2, atrVal);
      callCount += 2;
      if(ev1 > ev2)
         hi = tp2;
      else
         lo = tp1;
   }
   return((lo + hi) / 2.0);
}

//+------------------------------------------------------------------+
//| Main optimizer: grid SL × Newton TP → best EV                     |
//+------------------------------------------------------------------+
void OptimizeSLTP_EV(
   bool   isBuy,
   double entry,
   double initialSL,
   double initialTP1,
   double initialTP2,
   double initialTP3,
   double atrVal,
   double edge,
   int    caseNum,
   double swingSLPrice,
   double volumeSLPrice,
   double &outSL,
   double &outTP1,
   double &outTP2,
   double &outTP3,
   SLTPOptResult &result)
{
   result.gridCalls = 0;
   result.structurallyClipped = false;
   result.optEV = -999;

   if(edge < 0.50 || atrVal <= 0)
   {
      outSL  = initialSL;
      outTP1 = initialTP1;
      outTP2 = initialTP2;
      outTP3 = initialTP3;
      result.optEV = 0;
      result.initialEV = 0;
      result.evImprovement = 0;
      return;
   }

   double initialSLDist = MathAbs(entry - initialSL);
   double initialTPDist = MathAbs(initialTP1 - entry);
   double initialEV = _ComputeEV(edge, initialSLDist, initialTPDist, atrVal);
   result.gridCalls++;
   result.initialEV = initialEV;

   double caseMult = GetCaseTFSLMultiplier(caseNum, Period());
   double slCenter = atrVal * GetActiveSLRatio() * caseMult;
   double slMin = atrVal * 0.5;
   double slMax = atrVal * 5.0;

   double devSL = MathMax(0.0, MathMin(1.0, InpOptSLDeviation));
   double devTP = MathMax(0.0, MathMin(1.0, InpOptTPDeviation));
   double slSearchLo = MathMax(slMin, slCenter * (1.0 - devSL));
   double slSearchHi = MathMin(slMax, slCenter * (1.0 + devSL));
   if(initialSLDist > 0)
   {
      slSearchLo = MathMin(slSearchLo, initialSLDist * 0.85);
      slSearchHi = MathMax(slSearchHi, initialSLDist * 1.15);
      slSearchLo = MathMax(slMin, slSearchLo);
      slSearchHi = MathMin(slMax, slSearchHi);
   }
   if(slSearchLo >= slSearchHi)
   {
      slSearchLo = MathMax(slMin, slCenter * 0.8);
      slSearchHi = MathMin(slMax, slCenter * 1.2);
   }

   double tpLoBound = initialTPDist * (1.0 - devTP);
   double tpHiBound = initialTPDist * (1.0 + devTP);

   int numSLSteps = 12;
   double slStep = (slSearchHi - slSearchLo) / MathMax(numSLSteps, 1);
   double bestEV = -999;
   double bestSLDist = initialSLDist;
   double bestTPDist = initialTPDist;

   for(int s = 0; s <= numSLSteps; s++)
   {
      double slDist = slSearchLo + s * slStep;
      if(slDist <= 0) continue;

      double tpNewton = FindOptimalTP_Newton(edge, slDist, atrVal, result.gridCalls);

      double tpMults[] = {0.85, 0.92, 1.0, 1.08, 1.15};
      for(int m = 0; m < 5; m++)
      {
         double tpDist = tpNewton * tpMults[m];
         if(tpDist < slDist) continue;
         if(tpDist > slDist * 8.0) continue;
         if(devTP < 1.0 && (tpDist < tpLoBound || tpDist > tpHiBound)) continue;

         double ev = _ComputeEV(edge, slDist, tpDist, atrVal);
         result.gridCalls++;
         if(ev > bestEV)
         {
            bestEV = ev;
            bestSLDist = slDist;
            bestTPDist = tpDist;
         }
      }
   }

   bestTPDist = _GoldenRefineTP(edge, bestSLDist, bestTPDist, atrVal, result.gridCalls);
   bestEV = _ComputeEV(edge, bestSLDist, bestTPDist, atrVal);
   result.gridCalls++;

   // --- Structural constraints ---
   double structSLDist = bestSLDist;
   if(isBuy)
   {
      double swingDist = entry - swingSLPrice;
      double volDist   = entry - volumeSLPrice;
      if(swingDist > 0 && swingDist > structSLDist)
      {
         structSLDist = swingDist;
         result.structurallyClipped = true;
      }
      if(volDist > 0 && volDist > structSLDist)
      {
         structSLDist = volDist;
         result.structurallyClipped = true;
      }
   }
   else
   {
      double swingDist = swingSLPrice - entry;
      double volDist   = volumeSLPrice - entry;
      if(swingDist > 0 && swingDist > structSLDist)
      {
         structSLDist = swingDist;
         result.structurallyClipped = true;
      }
      if(volDist > 0 && volDist > structSLDist)
      {
         structSLDist = volDist;
         result.structurallyClipped = true;
      }
   }

   if(result.structurallyClipped)
   {
      bestSLDist = structSLDist;
      bestTPDist = FindOptimalTP_Newton(edge, bestSLDist, atrVal, result.gridCalls);
      bestTPDist = _GoldenRefineTP(edge, bestSLDist, bestTPDist, atrVal, result.gridCalls);
      bestEV = _ComputeEV(edge, bestSLDist, bestTPDist, atrVal);
      result.gridCalls++;
   }

   // --- Fallback: if optimization made EV worse, keep initial ---
   if(bestEV <= initialEV)
   {
      outSL  = initialSL;
      outTP1 = initialTP1;
      outTP2 = initialTP2;
      outTP3 = initialTP3;
      bestSLDist = initialSLDist;
      bestTPDist = initialTPDist;
      bestEV = initialEV;
   }
   else
   {
      double dir = isBuy ? 1.0 : -1.0;
      outSL  = entry - dir * bestSLDist;
      outTP1 = entry + dir * bestTPDist;
      outTP2 = entry + dir * bestTPDist * GetActiveTP2Mult();
      outTP3 = entry + dir * bestTPDist * GetActiveTP3Mult();
   }

   result.optSLDist = bestSLDist;
   result.optTPDist = bestTPDist;
   result.optEV = bestEV;
   result.optProbTP = CalculateRealMarketProbTP(edge, bestSLDist, bestTPDist, atrVal);
   result.optRR = bestTPDist / MathMax(bestSLDist, atrVal * 0.01);
   double q = 1.0 - result.optProbTP;
   result.kellyFraction = (result.optRR > 0)
      ? MathMax(0, (result.optProbTP * result.optRR - q) / result.optRR) * 0.5
      : 0;
   result.evImprovement = (MathAbs(initialEV) > 0.001)
      ? (bestEV - initialEV) / MathAbs(initialEV)
      : 0;
}

#endif
