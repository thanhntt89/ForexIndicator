//+------------------------------------------------------------------+
//|                                        ProbabilityEngine.mqh       |
//|                         RSI Advanced - Probability Calculation      |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_PROBABILITYENGINE_MQH
#define RSI_ADV_PROBABILITYENGINE_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"
#include "MathUtils.mqh"
#include "MTFEngine.mqh"
#include "Normalize.mqh"

//+------------------------------------------------------------------+
//| Simulate one signal forward (live-accurate version)                |
//| Includes spread adjustment + conservative SL bias                  |
//+------------------------------------------------------------------+
int SimulateSignalOutcome(int signalBar, bool isBuy, double entryPrice,
                          double slPrice, double tp1Price, double tp2Price, double tp3Price,
                          int maxBarsForward, int &barsToResult)
{
   barsToResult = 0;
   bool tp1Hit = false, tp2Hit = false, tp3Hit = false;

   // Get average spread for realistic simulation
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
         // BUY: SL hit at bid (Low), TP hit at bid (High)
         bool slHit  = (bL <= slPrice);
         bool tp1Now = (bH >= tp1Price);

         if(slHit && tp1Now)
         {
            // Both hit same bar - CONSERVATIVE: if ambiguous, assume SL first
            double distToSL = MathAbs(bO - slPrice);
            double distToTP = MathAbs(bO - tp1Price);

            if(distToSL <= distToTP * 1.2)  // 1.2x bias toward SL
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
         // SELL: adjust for spread - SL at ask (High+spread), TP at ask (Low+spread)
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
      double sd = atr*InpSLRatio;
      double td1 = atr*InpTPRatio;
      double td2 = td1*InpTP2Multiplier;
      double td3 = td1*InpTP3Multiplier;

      if(curSig.isBuySignal)
      { s1=ep-sd; t1=ep+td1; t2=ep+td2; t3=ep+td3; }
      else
      { s1=ep+sd; t1=ep-td1; t2=ep-td2; t3=ep-td3; }

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
//| MTF confluence probability adjustment                              |
//+------------------------------------------------------------------+
void ApplyMTFConfluenceWeight()
{
   if(!InpShowMTF || g_mtfCount == 0 || g_activeSignalIndex < 0) return;
   if(g_currentProb.totalSamples < GetMinSamplesForTimeframe()) return;

   bool isBuy = g_signals[g_activeSignalIndex].isBuySignal;
   int ctxScore = GetMTFContextScore(isBuy);
   double factor = (double)ctxScore / 100.0;
   double adj = (factor >= 0) ? factor * factor * 12.0 : -(factor * factor) * 12.0;

   double adjTP1 = MathMax(5.0, MathMin(95.0, g_currentProb.probTP1 + adj));
   double adjSL  = MathMax(5.0, MathMin(95.0, g_currentProb.probSL  - adj));
   double sum = adjTP1 + adjSL;
   g_currentProb.probTP1 = adjTP1 / sum * 100.0;
   g_currentProb.probSL  = adjSL  / sum * 100.0;

   double boost = 1.0 + (adj / 100.0);
   g_currentProb.probTP2 = MathMin(g_currentProb.probTP2 * boost, g_currentProb.probTP1);
   g_currentProb.probTP3 = MathMin(g_currentProb.probTP3 * boost * 0.8, g_currentProb.probTP2);
}

//+------------------------------------------------------------------+
//| Main probability calculation                                       |
//|                                                                    |
//| Pipeline:                                                          |
//| 1. Historical simulation (3 tiers)                                 |
//| 2. Measure real edge from data                                     |
//| 3. Calculate theoretical prob with market corrections               |
//| 4. Bayesian combine historical + theoretical                       |
//| 5. MTF adjustment                                                  |
//| 6. Final normalize                                                 |
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
   // STEP 1: Get current MTF context
   //=================================================================
   int mtfContext = 0;  // -100 to +100
   bool mtfAligned = false;
   bool mtfAgainst = false;

   if(InpShowMTF && g_mtfCount > 0)
   {
      mtfContext = GetMTFContextScore(curSig.isBuySignal);
      mtfAligned = (mtfContext > 20);
      mtfAgainst = (mtfContext < -20);
   }

   //=================================================================
   // STEP 2: Historical simulation (3 tiers)
   // Weight signals by MTF similarity
   //=================================================================

   // Tier 1: Same case + direction
   int t1_t=0, t1_to=0, t1_1=0, t1_2=0, t1_3=0, t1_s=0;
   double t1_b1=0, t1_bs=0;
   ScanStoredSignals(curSig, true, maxFwd,
                     t1_t, t1_to, t1_1, t1_2, t1_3, t1_s, t1_b1, t1_bs);

   // Tier 2: Same direction only
   int t2_t=0, t2_to=0, t2_1=0, t2_2=0, t2_3=0, t2_s=0;
   double t2_b1=0, t2_bs=0;
   ScanStoredSignals(curSig, false, maxFwd,
                     t2_t, t2_to, t2_1, t2_2, t2_3, t2_s, t2_b1, t2_bs);

   // Remove tier 1 from tier 2
   t2_t -= t1_t; t2_1 -= t1_1; t2_2 -= t1_2;
   t2_3 -= t1_3; t2_s -= t1_s;
   t2_b1 -= t1_b1; t2_bs -= t1_bs;
   if(t2_t < 0) t2_t = 0;
   if(t2_1 < 0) t2_1 = 0;
   if(t2_s < 0) t2_s = 0;

   // Tier 3: ATR scan
   int t3_t=0, t3_to=0, t3_1=0, t3_2=0, t3_3=0, t3_s=0;
   double t3_b1=0, t3_bs=0;
   if((t1_t + t2_t) < minSamples)
      ScanHistoricalATRBased(curSig, t3_t, t3_to,
                             t3_1, t3_2, t3_3, t3_s, t3_b1, t3_bs, maxFwd);

   // Weighted combination
   double w1=3.0, w2=1.0, w3=0.5;
   double tw=0, wTP1=0, wTP2=0, wTP3=0, wSL=0, wB1=0, wBS=0;
   int totalUsed = 0;

   if(t1_t >= 3)
   {
      wTP1+=((double)t1_1/t1_t)*w1; wTP2+=((double)t1_2/t1_t)*w1;
      wTP3+=((double)t1_3/t1_t)*w1; wSL+=((double)t1_s/t1_t)*w1;
      tw+=w1; totalUsed+=t1_t;
      if(t1_1>0) wB1+=(t1_b1/t1_1)*w1;
      if(t1_s>0) wBS+=(t1_bs/t1_s)*w1;
   }
   if(t2_t >= 3)
   {
      wTP1+=((double)t2_1/t2_t)*w2; wTP2+=((double)t2_2/t2_t)*w2;
      wTP3+=((double)t2_3/t2_t)*w2; wSL+=((double)t2_s/t2_t)*w2;
      tw+=w2; totalUsed+=t2_t;
      if(t2_1>0) wB1+=(t2_b1/t2_1)*w2;
      if(t2_s>0) wBS+=(t2_bs/t2_s)*w2;
   }
   if(t3_t >= 3)
   {
      wTP1+=((double)t3_1/t3_t)*w3; wTP2+=((double)t3_2/t3_t)*w3;
      wTP3+=((double)t3_3/t3_t)*w3; wSL+=((double)t3_s/t3_t)*w3;
      tw+=w3; totalUsed+=t3_t;
      if(t3_1>0) wB1+=(t3_b1/t3_1)*w3;
      if(t3_s>0) wBS+=(t3_bs/t3_s)*w3;
   }

   // Store counts
   g_currentProb.totalSamples = totalUsed;
   g_currentProb.samplesTP1 = t1_1 + t2_1 + t3_1;
   g_currentProb.samplesTP2 = t1_2 + t2_2 + t3_2;
   g_currentProb.samplesTP3 = t1_3 + t2_3 + t3_3;
   g_currentProb.samplesSL  = t1_s + t2_s + t3_s;

   // Historical probabilities
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
   // STEP 3: Measure edge WITH MTF context
   //
   // Edge khi MTF aligned KHÁC edge khi MTF against
   // Đo riêng rồi dùng đúng edge cho context hiện tại
   //=================================================================
   double measuredEdge = MeasureEdgeFromHistory(
      curSig.caseNumber, curSig.isBuySignal, maxFwd);

   // MTF-adjusted edge:
   // - MTF aligned: edge gets BOOST (trades with trend more likely to win)
   // - MTF against: edge gets PENALTY (counter-trend trades less likely)
   // - MTF neutral: no change
   //
   // Research: trading with higher TF trend adds ~3-5% to win rate
   // Trading against higher TF trend reduces ~5-8%
   double mtfEdgeAdjustment = 0;
   if(InpShowMTF && g_mtfCount > 0)
   {
      double mtfFactor = (double)mtfContext / 100.0;  // -1.0 to +1.0

      // Non-linear: extreme alignment has more effect
      if(mtfFactor >= 0)
         mtfEdgeAdjustment = mtfFactor * mtfFactor * 0.05;   // max +5%
      else
         mtfEdgeAdjustment = -(mtfFactor * mtfFactor) * 0.08; // max -8%

      // Weight by number of TFs agreeing
      int agreeCount = 0;
      for(int t=0; t<g_mtfCount; t++)
      {
         if(curSig.isBuySignal && g_mtfData[t].trend == 1) agreeCount++;
         if(!curSig.isBuySignal && g_mtfData[t].trend == -1) agreeCount++;
      }
      double tfRatio = (double)agreeCount / (double)g_mtfCount;

      // All TFs agree → full adjustment
      // Mixed TFs → partial adjustment
      mtfEdgeAdjustment *= tfRatio;
   }

   double mtfAdjustedEdge = MathMax(0.40, MathMin(0.70, measuredEdge + mtfEdgeAdjustment));

   //=================================================================
   // STEP 4: Theoretical probability using MTF-adjusted edge
   //=================================================================
   double slDist  = MathAbs(curSig.entryPrice - curSig.stopLoss);
   double tp1Dist = MathAbs(curSig.takeProfit1 - curSig.entryPrice);
   double tp2Dist = MathAbs(curSig.takeProfit2 - curSig.entryPrice);
   double tp3Dist = MathAbs(curSig.takeProfit3 - curSig.entryPrice);

   // Use MTF-ADJUSTED edge in Gambler's Ruin formula
   double theoTP1 = CalculateRealMarketProbTP(mtfAdjustedEdge, slDist, tp1Dist, curSig.atrValue) * 100.0;
   double theoTP2 = CalculateRealMarketProbTP(mtfAdjustedEdge, slDist, tp2Dist, curSig.atrValue) * 100.0;
   double theoTP3 = CalculateRealMarketProbTP(mtfAdjustedEdge, slDist, tp3Dist, curSig.atrValue) * 100.0;

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
   // STEP 6: Final normalize
   // NOTE: NO separate MTF adjustment step anymore
   // MTF is already baked into edge (Step 3) and theoretical (Step 4)
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