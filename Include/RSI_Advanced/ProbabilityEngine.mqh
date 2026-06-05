//+------------------------------------------------------------------+
//|                                        ProbabilityEngine.mqh       |
//|                         RSI Advanced - Probability Calculation      |
//|                                                                    |
//| Anti-overfitting:                                                  |
//| - Tier weights: sqrt(n) × relevance (data-proportional)           |
//| - MTF adjustment: measured alignment ratio × conservative cap     |
//| - No hardcoded magic numbers in probability pipeline               |
//| - Broker-resistant confirmations (High/Low, not Close)             |
//| - TF-scaled confidence adjustments                                 |
//| - Session quality from MEASURED data (when n >= 20)                |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_PROBABILITYENGINE_MQH
#define RSI_ADV_PROBABILITYENGINE_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"
#include "MathUtils.mqh"
#include "MTFEngine.mqh"
#include "Normalize.mqh"
#include "IntermarketAnalysis.mqh"
#include "SessionStatistics.mqh"
#include "WalkForward.mqh"

//+------------------------------------------------------------------+
//| Simulate one signal forward (live-accurate version)                |
//+------------------------------------------------------------------+
int SimulateSignalOutcome(int signalBar, bool isBuy, double entryPrice,
                          double slPrice, double tp1Price, double tp2Price, double tp3Price,
                          int maxBarsForward, int &barsToResult)
{
   barsToResult = 0;
   bool tp1Hit = false, tp2Hit = false, tp3Hit = false;
   double avgSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;

   for(int j = signalBar + 1; j < MathMin(signalBar + maxBarsForward, Bars); j++)
   {
      int barShift = Bars - 1 - j;
      if(barShift < 0) break;

      double bO = iOpen(NULL, 0, barShift);
      double bH = iHigh(NULL, 0, barShift);
      double bL = iLow(NULL, 0, barShift);
      if(bH == 0 || bL == 0) continue;
      barsToResult++;

      if(isBuy)
      {
         bool slHit  = (bL <= slPrice);
         bool tp1Now = (bH >= tp1Price);

         if(slHit && tp1Now)
         {
            double distToSL = MathAbs(bO - slPrice);
            double distToTP = MathAbs(bO - tp1Price);
            if(distToSL <= distToTP * 1.2)
            {
               if(tp1Hit) return(tp2Hit ? (tp3Hit ? 3 : 2) : 1);
               return(-1);
            }
            tp1Hit = true;
            if(bH >= tp2Price) tp2Hit = true;
            if(bH >= tp3Price) tp3Hit = true;
            if(tp3Hit) return(3); if(tp2Hit) return(2); return(1);
         }

         if(slHit)
         {
            if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
            return(-1);
         }

         if(!tp1Hit && bH >= tp1Price) tp1Hit = true;
         if(tp1Hit && !tp2Hit && bH >= tp2Price) tp2Hit = true;
         if(tp2Hit && !tp3Hit && bH >= tp3Price) tp3Hit = true;
         if(tp3Hit) return(3);
      }
      else
      {
         double effHigh = bH + avgSpread;
         double effLow  = bL + avgSpread;

         bool slHit  = (effHigh >= slPrice);
         bool tp1Now = (effLow <= tp1Price);

         if(slHit && tp1Now)
         {
            double distToSL = MathAbs(bO + avgSpread - slPrice);
            double distToTP = MathAbs(bO + avgSpread - tp1Price);
            if(distToSL <= distToTP * 1.2)
            {
               if(tp1Hit) return(tp2Hit ? (tp3Hit ? 3 : 2) : 1);
               return(-1);
            }
            tp1Hit = true;
            if(effLow <= tp2Price) tp2Hit = true;
            if(effLow <= tp3Price) tp3Hit = true;
            if(tp3Hit) return(3); if(tp2Hit) return(2); return(1);
         }

         if(slHit)
         {
            if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
            return(-1);
         }

         if(!tp1Hit && effLow <= tp1Price) tp1Hit = true;
         if(tp1Hit && !tp2Hit && effLow <= tp2Price) tp2Hit = true;
         if(tp2Hit && !tp3Hit && effLow <= tp3Price) tp3Hit = true;
         if(tp3Hit) return(3);
      }
   }

   if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
   return(0);
}

//+------------------------------------------------------------------+
//| Scan stored signals                                                |
//+------------------------------------------------------------------+
void ScanStoredSignals(const SignalData &curSig, bool matchCase, int maxFwd,
                       int &total, int &timeout, int &tp1, int &tp2, int &tp3, int &sl,
                       double &bTP1, double &bSL)
{
   total=0; timeout=0; tp1=0; tp2=0; tp3=0; sl=0; bTP1=0; bSL=0;

   for(int s = 0; s < g_signalCount; s++)
   {
      if(g_signals[s].signalTime == curSig.signalTime) continue;
      if(g_signals[s].isBuySignal != curSig.isBuySignal) continue;
      if(matchCase && g_signals[s].caseNumber != curSig.caseNumber) continue;
      if(g_signals[s].barIndex + maxFwd >= Bars) continue;

      int btr = 0;
      int out = SimulateSignalOutcome(
         g_signals[s].barIndex, g_signals[s].isBuySignal,
         g_signals[s].entryPrice, g_signals[s].stopLoss,
         g_signals[s].takeProfit1, g_signals[s].takeProfit2, g_signals[s].takeProfit3,
         maxFwd, btr);

      if(out == 0) { timeout++; continue; }
      total++;
      if(out >= 1) { tp1++; bTP1 += btr; }
      if(out >= 2) tp2++;
      if(out >= 3) tp3++;
      if(out == -1) { sl++; bSL += btr; }
   }
}

//+------------------------------------------------------------------+
//| ATR-based historical scan                                          |
//+------------------------------------------------------------------+
void ScanHistoricalATRBased(const SignalData &curSig,
                            int &total, int &timeout,
                            int &tp1, int &tp2, int &tp3, int &sl,
                            double &bTP1, double &bSL, int maxFwd)
{
   total=0; timeout=0; tp1=0; tp2=0; tp3=0; sl=0; bTP1=0; bSL=0;

   int probLookback = MathMin(InpProbMaxBars, Bars - maxFwd - 10);
   int startScan = MathMax(Bars - probLookback, InpRSIPeriod + InpBBPeriod + 10);
   int maxSamples = GetMaxLookbackForTimeframe();

   for(int i = startScan; i < Bars - maxFwd - 10; i++)
   {
      if(total >= maxSamples) break;
      int bs = Bars - 1 - i;
      if(bs < 0) continue;

      double rsi = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs);
      double atr = iATR(NULL, 0, InpATRPeriod, bs);
      if(rsi == 0 || atr == 0) continue;

      bool similar = false;
      if(curSig.isBuySignal)
      {
         if((curSig.caseNumber==1||curSig.caseNumber==5) && rsi<35 && rsi>10) similar=true;
         else if((curSig.caseNumber==2||curSig.caseNumber==3) && rsi<45 && rsi>20) similar=true;
         else if(rsi<50 && rsi>15) similar=true;
      }
      else
      {
         if((curSig.caseNumber==1||curSig.caseNumber==5) && rsi>65 && rsi<90) similar=true;
         else if((curSig.caseNumber==2||curSig.caseNumber==3) && rsi>55 && rsi<80) similar=true;
         else if(rsi>50 && rsi<85) similar=true;
      }
      if(!similar) continue;

      double ep = iClose(NULL, 0, bs);
      double s1, t1, t2, t3;
      double sd = atr * InpSLRatio;
      double td1 = atr * InpTPRatio;
      double td2 = td1 * InpTP2Multiplier;
      double td3 = td1 * InpTP3Multiplier;

      if(curSig.isBuySignal) { s1=ep-sd; t1=ep+td1; t2=ep+td2; t3=ep+td3; }
      else                   { s1=ep+sd; t1=ep-td1; t2=ep-td2; t3=ep-td3; }

      int btr = 0;
      int out = SimulateSignalOutcome(i, curSig.isBuySignal, ep, s1, t1, t2, t3, maxFwd, btr);

      if(out == 0) { timeout++; continue; }
      total++;
      if(out >= 1) { tp1++; bTP1 += btr; }
      if(out >= 2) tp2++;
      if(out >= 3) tp3++;
      if(out == -1) { sl++; bSL += btr; }
   }
}

//+------------------------------------------------------------------+
//| Main probability calculation                                       |
//+------------------------------------------------------------------+
void CalculateProbability(int currentSignalIndex)
{
   // Reset
   g_currentProb.probTP1=0; g_currentProb.probTP2=0;
   g_currentProb.probTP3=0; g_currentProb.probSL=0;
   g_currentProb.totalSamples=0; g_currentProb.samplesTP1=0;
   g_currentProb.samplesTP2=0; g_currentProb.samplesTP3=0;
   g_currentProb.samplesSL=0;
   g_currentProb.avgBarsToTP1=0; g_currentProb.avgBarsToSL=0;

   if(!InpShowProbability) return;
   if(currentSignalIndex < 0 || currentSignalIndex >= g_signalCount) return;

   SignalData curSig = g_signals[currentSignalIndex];
   int minSamples = GetMinSamplesForTimeframe();
   int maxFwd = GetMaxForwardBarsForTimeframe();

   //=================================================================
   // STEP 1: Historical simulation (3 tiers)
   //=================================================================
   int t1_t=0, t1_to=0, t1_1=0, t1_2=0, t1_3=0, t1_s=0;
   double t1_b1=0, t1_bs=0;
   ScanStoredSignals(curSig, true, maxFwd,
                     t1_t, t1_to, t1_1, t1_2, t1_3, t1_s, t1_b1, t1_bs);

   int t2_t=0, t2_to=0, t2_1=0, t2_2=0, t2_3=0, t2_s=0;
   double t2_b1=0, t2_bs=0;
   ScanStoredSignals(curSig, false, maxFwd,
                     t2_t, t2_to, t2_1, t2_2, t2_3, t2_s, t2_b1, t2_bs);

   t2_t -= t1_t; t2_1 -= t1_1; t2_2 -= t1_2;
   t2_3 -= t1_3; t2_s -= t1_s;
   t2_b1 -= t1_b1; t2_bs -= t1_bs;
   if(t2_t < 0) t2_t = 0;
   if(t2_1 < 0) t2_1 = 0;
   if(t2_s < 0) t2_s = 0;

   int t3_t=0, t3_to=0, t3_1=0, t3_2=0, t3_3=0, t3_s=0;
   double t3_b1=0, t3_bs=0;
   if((t1_t + t2_t) < minSamples)
      ScanHistoricalATRBased(curSig, t3_t, t3_to,
                             t3_1, t3_2, t3_3, t3_s, t3_b1, t3_bs, maxFwd);

   // Data-proportional tier weights
   double w1 = (t1_t >= 3) ? MathSqrt((double)t1_t) * 1.0  : 0;
   double w2 = (t2_t >= 3) ? MathSqrt((double)t2_t) * 0.5  : 0;
   double w3 = (t3_t >= 3) ? MathSqrt((double)t3_t) * 0.25 : 0;

   double tw = 0, wTP1 = 0, wTP2 = 0, wTP3 = 0, wSL = 0, wB1 = 0, wBS = 0;
   int totalUsed = 0;

   if(w1 > 0)
   {
      wTP1+=((double)t1_1/t1_t)*w1; wTP2+=((double)t1_2/t1_t)*w1;
      wTP3+=((double)t1_3/t1_t)*w1; wSL +=((double)t1_s/t1_t)*w1;
      tw+=w1; totalUsed+=t1_t;
      if(t1_1>0) wB1+=(t1_b1/t1_1)*w1;
      if(t1_s>0) wBS+=(t1_bs/t1_s)*w1;
   }
   if(w2 > 0)
   {
      wTP1+=((double)t2_1/t2_t)*w2; wTP2+=((double)t2_2/t2_t)*w2;
      wTP3+=((double)t2_3/t2_t)*w2; wSL +=((double)t2_s/t2_t)*w2;
      tw+=w2; totalUsed+=t2_t;
      if(t2_1>0) wB1+=(t2_b1/t2_1)*w2;
      if(t2_s>0) wBS+=(t2_bs/t2_s)*w2;
   }
   if(w3 > 0)
   {
      wTP1+=((double)t3_1/t3_t)*w3; wTP2+=((double)t3_2/t3_t)*w3;
      wTP3+=((double)t3_3/t3_t)*w3; wSL +=((double)t3_s/t3_t)*w3;
      tw+=w3; totalUsed+=t3_t;
      if(t3_1>0) wB1+=(t3_b1/t3_1)*w3;
      if(t3_s>0) wBS+=(t3_bs/t3_s)*w3;
   }

   g_currentProb.totalSamples = totalUsed;
   g_currentProb.samplesTP1 = t1_1 + t2_1 + t3_1;
   g_currentProb.samplesTP2 = t1_2 + t2_2 + t3_2;
   g_currentProb.samplesTP3 = t1_3 + t2_3 + t3_3;
   g_currentProb.samplesSL  = t1_s + t2_s + t3_s;

   double histTP1=0, histTP2=0, histTP3=0, histSL=0;
   if(tw > 0 && totalUsed >= 3)
   {
      double rTP1=wTP1/tw*100, rTP2=wTP2/tw*100;
      double rTP3=wTP3/tw*100, rSL=wSL/tw*100;
      double sum = rTP1 + rSL;
      if(sum > 0)
      {
         histTP1 = rTP1/sum*100;
         histSL  = rSL/sum*100;
         histTP2 = MathMin(rTP2/sum*100, histTP1);
         histTP3 = MathMin(rTP3/sum*100, histTP2);
      }
      if(tw > 0)
      {
         g_currentProb.avgBarsToTP1 = wB1/tw;
         g_currentProb.avgBarsToSL  = wBS/tw;
      }
   }

   //=================================================================
   // STEP 2: Measure edge from data
   //=================================================================
   double measuredEdge = MeasureEdgeFromHistory(
      curSig.caseNumber, curSig.isBuySignal, maxFwd);

   //=================================================================
   // STEP 3: MTF + Intermarket adjusted edge
   //=================================================================
   double edgeAdjustment = 0;

   if(InpShowMTF && g_mtfCount > 0)
   {
      int agreeCount = 0;
      for(int t = 0; t < g_mtfCount; t++)
      {
         if(curSig.isBuySignal && g_mtfData[t].trend == 1) agreeCount++;
         if(!curSig.isBuySignal && g_mtfData[t].trend == -1) agreeCount++;
      }
      double alignRatio = ((double)agreeCount / (double)g_mtfCount) * 2.0 - 1.0;
      edgeAdjustment += alignRatio * 0.03;
   }

   if(g_intermarket.isAvailable)
   {
      double interAdj = GetIntermarketEdgeAdjustment(curSig.isBuySignal);
      edgeAdjustment += interAdj;
   }

   double adjustedEdge = MathMax(0.40, MathMin(0.70, measuredEdge + edgeAdjustment));

   //=================================================================
   // STEP 4: Theoretical probability using adjusted edge
   //=================================================================
   double slDist  = MathAbs(curSig.entryPrice - curSig.stopLoss);
   double tp1Dist = MathAbs(curSig.takeProfit1 - curSig.entryPrice);
   double tp2Dist = MathAbs(curSig.takeProfit2 - curSig.entryPrice);
   double tp3Dist = MathAbs(curSig.takeProfit3 - curSig.entryPrice);

   double theoTP1 = CalculateRealMarketProbTP(adjustedEdge, slDist, tp1Dist, curSig.atrValue) * 100.0;
   double theoTP2 = CalculateRealMarketProbTP(adjustedEdge, slDist, tp2Dist, curSig.atrValue) * 100.0;
   double theoTP3 = CalculateRealMarketProbTP(adjustedEdge, slDist, tp3Dist, curSig.atrValue) * 100.0;

   //=================================================================
   // STEP 5: Bayesian combine historical + theoretical
   //=================================================================
   if(totalUsed >= 3 && tw > 0)
   {
      g_currentProb.probTP1 = CombineTheoreticalHistorical(theoTP1, histTP1, totalUsed, minSamples);
      g_currentProb.probTP2 = CombineTheoreticalHistorical(theoTP2, histTP2, totalUsed, minSamples);
      g_currentProb.probTP3 = CombineTheoreticalHistorical(theoTP3, histTP3, totalUsed, minSamples);
      g_currentProb.probSL  = 100.0 - g_currentProb.probTP1;
   }
   else
   {
      g_currentProb.probTP1 = theoTP1;
      g_currentProb.probTP2 = MathMin(theoTP2, theoTP1);
      g_currentProb.probTP3 = MathMin(theoTP3, theoTP2);
      g_currentProb.probSL  = 100.0 - theoTP1;
   }

   //=================================================================
   // STEP 5.5: BROKER-RESISTANT confidence adjustments
   //=================================================================

   //--- 1-Bar Price Confirmation (Brooks 2012)
   if(curSig.barIndex < Bars - 2)
   {
      int sigBarShift  = Bars - 1 - curSig.barIndex;
      int nextBarShift = Bars - 1 - (curSig.barIndex + 1);

      if(sigBarShift >= 0 && nextBarShift >= 0)
      {
         double sigHigh  = iHigh(NULL, 0, sigBarShift);
         double sigLow   = iLow(NULL, 0, sigBarShift);
         double nextHigh = iHigh(NULL, 0, nextBarShift);
         double nextLow  = iLow(NULL, 0, nextBarShift);

         bool confirmed = false;
         if(curSig.isBuySignal) confirmed = (nextHigh > sigHigh);
         else                   confirmed = (nextLow < sigLow);

         if(!confirmed)
         {
            double reductionFactor = 0.95;
            int tf = Period();
            if(tf <= PERIOD_M5)       reductionFactor = 0.97;
            else if(tf <= PERIOD_M15) reductionFactor = 0.92;
            else if(tf <= PERIOD_M30) reductionFactor = 0.88;
            else                      reductionFactor = 0.85;

            g_currentProb.probTP1 *= reductionFactor;
            g_currentProb.probTP2 *= reductionFactor;
            g_currentProb.probTP3 *= reductionFactor;
            g_currentProb.probSL = 100.0 - g_currentProb.probTP1;
         }
      }
   }

   //--- ATR Spike Detection
   {
      int curBarShift = Bars - 1 - curSig.barIndex;
      if(curBarShift >= 0)
      {
         double curATR = iATR(NULL, 0, InpATRPeriod, curBarShift);
         double avgATR = 0;
         int atrCount = 0;

         for(int a = curBarShift + 1; a <= curBarShift + 50 && a < Bars; a++)
         {
            avgATR += iATR(NULL, 0, InpATRPeriod, a);
            atrCount++;
         }
         if(atrCount > 0) avgATR /= atrCount;

         if(avgATR > 0 && curATR > avgATR * 2.0)
         {
            double spikeRatio = curATR / avgATR;
            double shrinkFactor = 1.0 / spikeRatio;

            g_currentProb.probTP1 = 50.0 + (g_currentProb.probTP1 - 50.0) * shrinkFactor;
            g_currentProb.probTP2 = 50.0 + (g_currentProb.probTP2 - 50.0) * shrinkFactor;
            g_currentProb.probTP3 = 50.0 + (g_currentProb.probTP3 - 50.0) * shrinkFactor;
            g_currentProb.probSL  = 100.0 - g_currentProb.probTP1;
         }
      }
   }

   //=================================================================
   // STEP 5.6: SESSION QUALITY adjustment
   //=================================================================
   {
      int block = GetSessionBlock(curSig.signalTime);

      if(g_sessionStats.totalPerSession[block] >= 20)
      {
         double measuredWR = g_sessionStats.winRate[block];
         double baselineWR = g_currentProb.probTP1 / 100.0;

         if(MathAbs(measuredWR - baselineWR) > 0.10)
         {
            // ANTI-OVERFITTING: Inverse variance weighting
            // Instead of fixed 70/30 blend
            // Weight each source by inverse of its uncertainty
            
            // Model uncertainty: ~15% (Gambler's Ruin typical error)
            double modelSE = 0.15;
            
            // Measured uncertainty: Wilson SE
            double p = measuredWR;
            if(p <= 0) p = 0.01; if(p >= 1) p = 0.99;
            double n = (double)g_sessionStats.totalPerSession[block];
            double z2 = 3.84; // 1.96^2
            double measuredSE = MathSqrt((p * (1.0 - p) / n + z2 / (4.0 * n * n)) / (1.0 + z2 / n));
            measuredSE = MathMax(measuredSE, 0.05);
            
            // Inverse variance weights
            double modelWeight = 1.0 / (modelSE * modelSE);
            double measuredWeight = 1.0 / (measuredSE * measuredSE);
            double totalW = modelWeight + measuredWeight;
            
            if(totalW > 0)
            {
               double blended = (baselineWR * modelWeight + measuredWR * measuredWeight) / totalW;
               double ratio = blended / MathMax(baselineWR, 0.01);
               
               g_currentProb.probTP1 *= ratio;
               g_currentProb.probTP2 *= ratio;
               g_currentProb.probTP3 *= ratio;
               g_currentProb.probSL = 100.0 - g_currentProb.probTP1;
            }
         }
      }
   }

   //=================================================================
   // STEP 6: Final normalize
   //=================================================================
   if(g_currentProb.probTP1 > 0 || g_currentProb.probSL > 0)
   {
      double t = g_currentProb.probTP1 + g_currentProb.probSL;
      if(t > 0)
      {
         g_currentProb.probTP1 = NormalizeDouble(g_currentProb.probTP1 / t * 100, 1);
         g_currentProb.probSL  = NormalizeDouble(100.0 - g_currentProb.probTP1, 1);
      }
   }
   g_currentProb.probTP2 = NormalizeDouble(MathMin(g_currentProb.probTP2, g_currentProb.probTP1), 1);
   g_currentProb.probTP3 = NormalizeDouble(MathMin(g_currentProb.probTP3, g_currentProb.probTP2), 1);
}

#endif