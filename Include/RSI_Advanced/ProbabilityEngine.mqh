//+------------------------------------------------------------------+
//|                                        ProbabilityEngine.mqh       |
//|                         RSI Advanced - Probability Calculation      |
//+------------------------------------------------------------------+
//|                                                                    |
//| PROBABILITY CALCULATION PIPELINE                                   |
//| ================================                                   |
//|                                                                    |
//| Pipeline: 6 steps, moi step dieu chinh xac suat tu step truoc.    |
//| Output cuoi cung: probTP1, probTP2, probTP3, probSL (tong = 100%) |
//|                                                                    |
//| ================================================================= |
//| STEP 1: HISTORICAL SIMULATION (3 tiers)                            |
//| ================================================================= |
//|                                                                    |
//| Thu thap du lieu lich su bang 3 tang uu tien:                      |
//|                                                                    |
//| Tier 1: Stored signals CUNG case number (cung BUY/SELL + caseNum) |
//|   - Scan tat ca signal da luu trong g_signals[]                    |
//|   - Chi lay signal cung direction va cung case voi signal hien tai |
//|   - Moi signal duoc chay SimulateSignalOutcome() de xem ket qua   |
//|   - Weight: w1 = n^0.75 × 1.0 (tin nhieu nhat, cung case)        |
//|                                                                    |
//| Tier 2: Stored signals TAT CA cases (cung BUY/SELL, khac case)    |
//|   - Giong Tier 1 nhung bo dieu kien caseNumber                    |
//|   - Tru di ket qua da dem o Tier 1 (tranh double-count)           |
//|   - Weight: w2 = sqrt(n) × 0.5 (it tin hon, khac case)           |
//|                                                                    |
//| Tier 3: ATR-based historical scan (chi chay khi Tier 1+2 it mau) |
//|   - Scan lich su gia (khong can signal da luu)                    |
//|   - Tim bar co RSI tuong tu signal hien tai                       |
//|   - Tu bar do, tao TP/SL tu ATR va simulate ket qua              |
//|   - Co angle-tier filter: chi so sanh bar co angle tuong tu       |
//|   - Weight: w3 = sqrt(n) × 0.25 (it tin nhat, du lieu tho)       |
//|                                                                    |
//| Ket qua Tier: histTP1, histSL (weighted average cua 3 tiers)      |
//|   histTP1 = sum(tier_ratio × weight) / sum(weight) × 100          |
//|   histSL  = 100 - histTP1                                         |
//|                                                                    |
//| Dong thoi tinh:                                                    |
//|   avgBarsToTP1 = so nen trung binh de dat TP1                     |
//|   avgBarsToSL  = so nen trung binh de dat SL                      |
//|   (dung cho time-decay o Step 5.7)                                |
//|                                                                    |
//| ================================================================= |
//| STEP 2: EDGE MEASUREMENT                                          |
//| ================================================================= |
//|                                                                    |
//| Do "edge" tu du lieu signal da luu:                                |
//|   - Voi moi signal cung direction (va cung case neu co):          |
//|     + Tu entry, gia co vuot entry + 1×ATR hay khong?              |
//|     + edge = correctCount / totalCount                             |
//|   - edge = 0.5 nghia la khong co loi the (50/50)                  |
//|   - edge > 0.5 nghia la co loi the thuc su                        |
//|                                                                    |
//| ================================================================= |
//| STEP 3: EDGE ADJUSTMENTS (MTF + Intermarket + Angle)               |
//| ================================================================= |
//|                                                                    |
//| Dieu chinh edge dua tren cac yeu to bo sung:                      |
//|                                                                    |
//| a) MTF (Multi-Timeframe):                                         |
//|   alignRatio = (agreeCount / totalTF) × 2 - 1   [-1.0, +1.0]     |
//|   edgeAdj += alignRatio × 0.03                                    |
//|   → Neu da so TF dong y: +3% edge, nguoc lai: -3%                |
//|                                                                    |
//| b) Intermarket (DXY/EURUSD correlation):                           |
//|   edgeAdj += intermarketEdge  (tu GetIntermarketEdgeAdjustment)   |
//|                                                                    |
//| c) Angle Strength (Z-score goc RSI):                               |
//|   angleAdj = clamp((Z - 1.0) × 0.03, -0.03, +0.04)              |
//|   Divergence cases (2,3): damp 40% (structure > angle)            |
//|   edgeAdj += angleAdj × caseDamp                                  |
//|                                                                    |
//| adjustedEdge = clamp(edge + edgeAdj, 0.40, 0.85)                  |
//|                                                                    |
//| ================================================================= |
//| STEP 4: THEORETICAL PROBABILITY (Gambler's Ruin)                   |
//| ================================================================= |
//|                                                                    |
//| Chuyen edge thanh xac suat dat TP, dua tren khoang cach SL/TP:    |
//|                                                                    |
//| Gambler's Ruin formula:                                            |
//|   slU = slDist / ATR        (SL tinh bang don vi ATR)             |
//|   tpU = tpDist / ATR        (TP tinh bang don vi ATR)             |
//|   mu  = 2 × edge - 1        (drift)                               |
//|   r   = exp(-2 × mu)                                              |
//|   P(TP) = (1 - r^slU) / (1 - r^(slU+tpU))                       |
//|                                                                    |
//| Real-market corrections (nhan voi P(TP)):                          |
//|   × (1 - FatTailPenalty)     kurtosis > 3 → phat tail risk       |
//|   × (1 - VolClusterPenalty)  vol autocorrelation → cluster risk   |
//|   × (1 - SpreadDrag)         spread / ATR → chi phi giao dich     |
//|                                                                    |
//| theoTP1 = GamblersRuin(edge, SL, TP1) × corrections              |
//| theoTP2 = GamblersRuin(edge, SL, TP2) × corrections              |
//| theoTP3 = GamblersRuin(edge, SL, TP3) × corrections              |
//|                                                                    |
//| ================================================================= |
//| STEP 5: BAYESIAN COMBINE (Historical + Theoretical)                |
//| ================================================================= |
//|                                                                    |
//| Ket hop 2 nguon: ly thuyet (Step 4) va lich su (Step 1)           |
//| bang Bayesian weighted average voi Wilson Score SE:                 |
//|                                                                    |
//|   pWilson = (p×n + z²/2) / (n + z²)          z = 1.96 (95% CI)  |
//|   wilsonSE = sqrt((p(1-p)/n + z²/4n²) / (1 + z²/n))             |
//|   wilsonSE = max(wilsonSE, 0.05)              (floor)             |
//|   theoSE   = 0.15                             (model uncertainty) |
//|                                                                    |
//|   credibility = n/minSamples                  (0 → 1.0)           |
//|   adjustedSE  = wilsonSE / credibility                            |
//|                                                                    |
//|   histWeight = 1/adjustedSE²                                      |
//|   theoWeight = 1/theoSE²                                          |
//|   combined = (theo×theoW + hist×histW) / (theoW + histW)          |
//|                                                                    |
//| Khi n lon: hist chiem uu the (tin du lieu thuc)                   |
//| Khi n nho: theo chiem uu the (tin model)                          |
//|                                                                    |
//| ================================================================= |
//| STEP 5.5: CONFIDENCE ADJUSTMENTS                                   |
//| ================================================================= |
//|                                                                    |
//| a) 1-Bar Price Confirmation (Brooks 2012):                         |
//|   BUY:  nextBar.High > signalBar.High  → confirmed               |
//|   SELL: nextBar.Low  < signalBar.Low   → confirmed               |
//|   Khong confirmed → probTP × reductionFactor (0.85 ~ 0.97 theo TF)|
//|                                                                    |
//| b) ATR Spike Detection:                                            |
//|   curATR > avgATR(50) × 2.0 → volatility spike                   |
//|   shrinkFactor = 1 / spikeRatio                                   |
//|   prob = 50 + (prob - 50) × shrinkFactor  (keo ve 50%)           |
//|                                                                    |
//| ================================================================= |
//| STEP 5.6: SESSION QUALITY (Bayesian blend)                         |
//| ================================================================= |
//|                                                                    |
//| Neu co du lieu win rate thuc te theo session (n >= 20):            |
//|   measuredWR = win rate thuc do duoc (theo session + case)        |
//|   baselineWR = probTP1 hien tai / 100                             |
//|                                                                    |
//| Chi blend khi |measuredWR - baselineWR| > 10% (loc noise)        |
//|                                                                    |
//|   Wilson SE cho measured data + modelSE = 0.15                    |
//|   blended = (baseline×modelW + measured×measuredW) / totalW       |
//|   ratio   = blended / baseline                                    |
//|   probTP1 *= ratio, probTP2 *= ratio, probTP3 *= ratio            |
//|                                                                    |
//| ================================================================= |
//| STEP 5.7: TIME-DECAY / SURVIVAL ANALYSIS                          |
//| ================================================================= |
//|                                                                    |
//| Xac suat DONG (thay doi theo thoi gian), khong con tinh.          |
//| Dua tren Weibull survival model:                                   |
//|                                                                    |
//|   S(t) = exp(-(t / lambda)^k)                                     |
//|                                                                    |
//|   t      = so nen da troi qua tu khi signal xuat hien            |
//|   lambda = so nen trung binh de dat ket qua (tu Step 1)           |
//|   k      = shape parameter (hinh dang duong cong phan ra)         |
//|                                                                    |
//| Cho TP (edge phai giam khi qua lau):                               |
//|   k_tp = 1.50 (H1+), 1.40 (M15), 1.30 (M5), 1.20 (M1)           |
//|   lambda_tp = avgBarsToTP1                                         |
//|   → Increasing hazard: cang lau cang kho dat TP                  |
//|   → t = avgTP: S = 36.8% | t = 2×avgTP: S = 5.9%                |
//|                                                                    |
//| Cho SL (nguy hiem giam neu song sot qua giai doan dau):           |
//|   k_sl = 0.80 (H1+), 0.75 (M15), 0.70 (M5), 0.65 (M1)           |
//|   lambda_sl = avgBarsToSL                                          |
//|   → Decreasing hazard: song qua danger zone → it bi SL hon       |
//|   → t = avgSL: S = 37% | t = 2×avgSL: S = 19%                   |
//|                                                                    |
//| Bayesian update:                                                   |
//|   P(TP | survived t bars) =                                        |
//|       P(TP) × S_tp(t)                                             |
//|       ─────────────────────────────                                |
//|       P(TP) × S_tp(t) + P(SL) × S_sl(t)                          |
//|                                                                    |
//| Vi du voi avgTP=38, avgSL=10, base Win=39%:                       |
//|   t=0:   Win 39.0% (moi, chua thay doi)                          |
//|   t=5:   Win 48.4% (song qua SL zone → edge tang)               |
//|   t=10:  Win 53.8% (vuot avg SL → edge cao nhat)                 |
//|   t=38:  Win 40.8% (tai avg TP → bat dau giam)                   |
//|   t=60:  Win 29.3% (qua han → edge fading)                       |
//|   t=80:  Win 10.3% (gan het → nen thoat)                         |
//|                                                                    |
//| survivalRatio = sqrt(S_tp × S_sl)                                  |
//|   1.0 = signal moi, 0.0 = edge da het hoan toan                  |
//|   Panel hien thi mau theo survivalRatio:                           |
//|   >70% xanh la | >40% vang | >20% cam | <=20% do                 |
//|                                                                    |
//| ================================================================= |
//| STEP 6: FINAL NORMALIZE                                            |
//| ================================================================= |
//|                                                                    |
//| Chuan hoa de dam bao:                                              |
//|   probTP1 + probSL = 100%                                         |
//|   probTP2 <= probTP1                                               |
//|   probTP3 <= probTP2                                               |
//|                                                                    |
//| ================================================================= |
//| ANTI-OVERFITTING MEASURES                                          |
//| ================================================================= |
//|                                                                    |
//| - Tier weights: sqrt(n) × relevance (data-proportional)           |
//| - MTF adjustment: measured alignment ratio × conservative cap     |
//| - Gambler's Ruin: market-corrected (fat tail, vol cluster, spread)|
//| - Broker-resistant confirmations (High/Low, not Close)             |
//| - TF-scaled confidence adjustments                                 |
//| - Session quality from MEASURED data (when n >= 20)                |
//| - Time-decay: Weibull survival, not arbitrary linear discount      |
//| - Wilson Score SE with floor 0.05 (never trust data 100%)         |
//| - Edge hard clamp [0.40, 0.85] (prevent extreme predictions)      |
//|                                                                    |
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
   // Use real broker spread instead of hardcoded ATR percentage.
   // Old code used spreadPct=0.03 for gold = 3% ATR, but actual spread
   // on XAUUSD M1 is 0.20-0.50 USD vs ATR 0.50-1.50 = 13-100% ATR.
   double avgSpread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
   if(avgSpread <= 0)
   {
      double simATR = iATR(NULL, 0, 14, Bars - 1 - signalBar);
      if(simATR > 0)
         avgSpread = simATR * 0.05;
   }

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
         // BUY: entered at ASK, exit at BID. Chart candles = BID prices.
         // TP hit when BID (bH) reaches target — NO spread adjustment needed.
         // SL hit when BID (bL) drops to SL — NO spread adjustment needed.
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
      
      //Patch #1 — Fix Timeout
      int timeBasedMax = 1440 / MathMax(Period(), 1);
      timeBasedMax = MathMax(timeBasedMax, maxFwd);
      if(g_signals[s].barIndex + timeBasedMax >= Bars) continue;
      int btr = 0;
      int out = SimulateSignalOutcome(
         g_signals[s].barIndex, g_signals[s].isBuySignal,
         g_signals[s].entryPrice, g_signals[s].stopLoss,
         g_signals[s].takeProfit1, g_signals[s].takeProfit2, g_signals[s].takeProfit3,
         timeBasedMax, btr);
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

   int probLookback = MathMin(GetEffectiveProbMaxBars(), Bars - maxFwd - 10);
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

      // --- Angle-tier stratification (Spec: AngleStrength_Probability_Spec.md)
      // Only compare bars with similar angle momentum to current signal.
      // Divergence cases (2,3) rely on price structure, not angle → skip filter.
      // Falls back to full pool when curSig.angleStrength is not computed (= 0).
      if(curSig.angleStrength > 0.5 &&
         curSig.caseNumber != 2 && curSig.caseNumber != 3)
      {
         // Proxy for historical bar's angle: RSI change over 2 bars / ATR-scaled
         double rsiPrev2 = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs + 2);
         double histAngle = 0.0;
         if(rsiPrev2 > 0 && atr > 0)
            histAngle = MathAbs(rsi - rsiPrev2) / MathMax(atr * 0.5, 0.01);

         bool curStrong  = (curSig.angleStrength >= 1.0);
         bool histStrong = (histAngle >= 1.0);
         // Exclude bars from the opposite angle tier
         if(curStrong != histStrong) continue;
      }

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
//| Vol-Regime Classifier                                              |
//|                                                                    |
//| Classify market state using ATR ratio + session time.              |
//| Gold M1 has 3 distinct behaviors:                                  |
//|   Pre-London (0-8h UTC): quiet, mean-reverting → RSI works well   |
//|   London open (8-12h): directional breakout → neutral             |
//|   NY overlap (12-17h): high vol, unpredictable → reduce edge      |
//|                                                                    |
//| ATR ratio = ATR(14, current) / SMA(ATR(14), 50 bars)              |
//|   < 0.6: QUIET (low vol relative to norm)                         |
//|   0.6-1.8: NORMAL or TRENDING (depends on session)                |
//|   > 1.8: EVENT (spike/news)                                       |
//+------------------------------------------------------------------+
void UpdateVolRegime()
{
   double curATR = iATR(NULL, 0, InpATRPeriod, 0);
   if(curATR <= 0)
   {
      g_volRegime.regime = VOL_NORMAL;
      g_volRegime.atrRatio = 1.0;
      g_volRegime.label = "NORMAL";
      return;
   }

   double avgATR = 0;
   int count = 0;
   int lookback = MathMin(50, Bars - 2);
   for(int i = 1; i <= lookback; i++)
   {
      double a = iATR(NULL, 0, InpATRPeriod, i);
      if(a > 0) { avgATR += a; count++; }
   }
   if(count > 0) avgATR /= count;
   if(avgATR <= 0) avgATR = curATR;

   double ratio = curATR / avgATR;
   g_volRegime.atrRatio = ratio;

   int session = GetSessionBlock(TimeCurrent());

   if(ratio > 1.8)
   {
      g_volRegime.regime = VOL_EVENT;
      g_volRegime.label = "EVENT";
   }
   else if(ratio < 0.6)
   {
      g_volRegime.regime = VOL_QUIET;
      g_volRegime.label = "QUIET";
   }
   else if(ratio > 1.2 && (session == 1 || session == 2))
   {
      g_volRegime.regime = VOL_TRENDING;
      g_volRegime.label = "TRENDING";
   }
   else
   {
      g_volRegime.regime = VOL_NORMAL;
      g_volRegime.label = "NORMAL";
   }
}

//+------------------------------------------------------------------+
//| Vol-regime edge adjustment for Step 3                              |
//+------------------------------------------------------------------+
double GetVolRegimeEdgeAdjustment()
{
   switch(g_volRegime.regime)
   {
      case VOL_QUIET:    return(+0.02);  // mean-revert favors RSI OB/OS signals
      case VOL_EVENT:    return(-0.05);  // unpredictable spike, reduce confidence
      case VOL_TRENDING: return( 0.00);  // directional market, neutral for RSI
      default:           return( 0.00);  // NORMAL: no adjustment
   }
}

//+------------------------------------------------------------------+
//| Time-Decay / Survival Analysis                                     |
//|                                                                    |
//| Concept: Conditional probability given signal has NOT hit TP/SL    |
//| after N bars. Uses Weibull survival model:                         |
//|                                                                    |
//|   S(t) = exp(-(t/lambda)^k)                                       |
//|                                                                    |
//| where:                                                             |
//|   t      = elapsed bars since signal                               |
//|   lambda = scale parameter (avg bars to result)                    |
//|   k      = shape parameter (controls decay curve)                  |
//|            k < 1: decreasing hazard (less likely to hit over time) |
//|            k = 1: constant hazard (exponential decay)              |
//|            k > 1: increasing hazard (more likely to hit over time) |
//|                                                                    |
//| For TP: k=1.5 (TP becomes LESS likely as time passes — edge fades)|
//| For SL: k=0.8 (SL hazard slightly decreases — if survived early   |
//|         danger zone, price may have moved away from SL)            |
//|                                                                    |
//| Final adjusted probability:                                        |
//|   P_adj(TP) = P_base(TP) × S_tp(t) / [P_base(TP)×S_tp(t) +      |
//|                                         P_base(SL)×S_sl(t)]       |
//|                                                                    |
//| This means:                                                        |
//|   - Fresh signal (t=0): no change                                  |
//|   - t < avgBarsToSL: SL survival zone — if survived, edge UP      |
//|   - t ~ avgBarsToTP1: peak TP window, then edge starts fading      |
//|   - t >> avgBarsToTP1: edge mostly gone, probability drops          |
//+------------------------------------------------------------------+
void ApplyTimeDecay(int elapsedBars)
{
   // Need avg bars data to compute decay
   double avgTP = g_currentProb.avgBarsToTP1;
   double avgSL = g_currentProb.avgBarsToSL;
   if(avgTP <= 0 && avgSL <= 0) return;
   if(elapsedBars <= 0) return;

   if(g_currentProb.originalProbTP1 <= 0)
   {
      g_currentProb.originalProbTP1 = g_currentProb.probTP1;
      g_currentProb.originalProbTP2 = g_currentProb.probTP2;
      g_currentProb.originalProbTP3 = g_currentProb.probTP3;
   }

   // Store elapsed for panel display
   g_currentProb.elapsedBars = elapsedBars;

   double t = (double)elapsedBars;

   //--- Weibull survival: S(t) = exp(-(t/lambda)^k)
   //    lambda = avg bars to result (scale)
   //    k_tp: TP edge fades as time passes (increasing hazard)
   //    k_sl: SL risk slightly decreases after initial danger zone
   //    TF-adaptive: M1/M5 manual trader needs slower decay
   int tf = Period();
   double k_tp = 1.5;
   if(tf <= PERIOD_M1)       k_tp = 1.2;
   else if(tf <= PERIOD_M5)  k_tp = 1.3;
   else if(tf <= PERIOD_M15) k_tp = 1.4;
   double k_sl = 0.8;
   if(tf <= PERIOD_M1)       k_sl = 0.65;
   else if(tf <= PERIOD_M5)  k_sl = 0.70;
   else if(tf <= PERIOD_M15) k_sl = 0.75;

   // TP survival: how much TP-edge remains at time t
   // lambda_tp = avgBarsToTP1; if not available, use 2x avgSL as rough estimate
   double lambda_tp = (avgTP > 0) ? avgTP : avgSL * 2.0;
   double S_tp = MathExp(-MathPow(t / lambda_tp, k_tp));

   // SL survival: probability of NOT hitting SL by time t
   // lambda_sl = avgBarsToSL; if not available, use avgTP/3 as rough estimate
   double lambda_sl = (avgSL > 0) ? avgSL : lambda_tp / 3.0;
   double S_sl = MathExp(-MathPow(t / lambda_sl, k_sl));

   // Clamp survival to [0.05, 1.0] — never fully zero (still possible to hit)
   S_tp = MathMax(0.05, MathMin(1.0, S_tp));
   S_sl = MathMax(0.05, MathMin(1.0, S_sl));

   //--- Bayes update: P(TP|survived t bars) = P(TP)*S_tp / [P(TP)*S_tp + P(SL)*S_sl]
   double pTP = g_currentProb.probTP1 / 100.0;
   double pSL = g_currentProb.probSL / 100.0;

   double numerator   = pTP * S_tp;
   double denominator = pTP * S_tp + pSL * S_sl;

   if(denominator <= 0) return;

   double adjTP1 = (numerator / denominator) * 100.0;
   double adjSL  = 100.0 - adjTP1;

   // Survival ratio: overall edge remaining (geometric mean of both survivals)
   // 1.0 = fresh signal, 0.0 = edge completely exhausted
   g_currentProb.survivalRatio = MathSqrt(S_tp * S_sl);

   // Estimate minutes until edge drops below ~15% (survival ≈ 0.15)
   // Solve: exp(-(t_exp/lambda_tp)^k_tp) = 0.15 → t_exp = lambda_tp × (-ln(0.15))^(1/k_tp)
   double t_exp = lambda_tp * MathPow(-MathLog(0.15), 1.0 / k_tp);
   int barsRemain = (int)(t_exp - t);
   if(barsRemain < 0) barsRemain = 0;
   g_currentProb.expiresMinutes = barsRemain * Period();

   // Scale TP2/TP3 proportionally to TP1 change
   double ratio = (g_currentProb.probTP1 > 0)
      ? adjTP1 / g_currentProb.probTP1
      : 1.0;

   g_currentProb.decayedProbTP1 = NormalizeDouble(adjTP1, 1);
   g_currentProb.decayedProbSL  = NormalizeDouble(adjSL, 1);

   // Apply decay to main probability fields (replaces static values)
   g_currentProb.probTP1 = NormalizeDouble(adjTP1, 1);
   g_currentProb.probTP2 = NormalizeDouble(MathMin(g_currentProb.probTP2 * ratio, adjTP1), 1);
   g_currentProb.probTP3 = NormalizeDouble(MathMin(g_currentProb.probTP3 * ratio, g_currentProb.probTP2), 1);
   g_currentProb.probSL  = NormalizeDouble(adjSL, 1);
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
   g_currentProb.decayedProbTP1=0; g_currentProb.decayedProbSL=0;
   g_currentProb.survivalRatio=1.0; g_currentProb.elapsedBars=0;
   g_currentProb.expiresMinutes=0;
   g_currentProb.originalProbTP1=0; g_currentProb.originalProbTP2=0; g_currentProb.originalProbTP3=0;

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
   // Patch #3 — Tier 1 weight từ N^0.5 lên N^0.75
   double w1 = (t1_t >= 3) ? MathPow((double)t1_t, 0.75) * 1.0  : 0;
   double w2 = (t2_t >= 3) ? MathSqrt((double)t2_t)      * 0.5  : 0;
   double w3 = (t3_t >= 3) ? MathSqrt((double)t3_t)      * 0.25 : 0;

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

   int minBayesian = MathMax(10, GetMinSamplesForTimeframe() / 3);
   double histTP1=0, histTP2=0, histTP3=0, histSL=0;
   if(tw > 0 && totalUsed >= minBayesian)
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

   // --- Angle strength edge adjustment (Spec: AngleStrength_Probability_Spec.md)
   // Z > 1.0 = stronger angle than average → +edge; Z < 1.0 = weaker → -edge
   // Divergence cases (2,3) damped to 40% because structure matters more than angle
   // Formula: adj = (Z - 1.0) × 0.03, clamped [-0.03, +0.04]
   if(curSig.angleStrength > 0.1)
   {
      double caseDamp = (curSig.caseNumber == 2 || curSig.caseNumber == 3) ? 0.4 : 1.0;
      double angleAdj = MathMax(-0.03, MathMin(0.04, (curSig.angleStrength - 1.0) * 0.03));
      edgeAdjustment += angleAdj * caseDamp;
   }

   // --- Vol-regime edge adjustment
   // QUIET market: RSI OB/OS signals more reliable (+2% edge)
   // EVENT/spike: reduce confidence (-5% edge)
   UpdateVolRegime();
   edgeAdjustment += GetVolRegimeEdgeAdjustment();

   //Patch #2 — Hard Clamp [0.40, 0.85]
   double adjustedEdge = MathMax(0.40, MathMin(0.85, measuredEdge + edgeAdjustment));

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
   if(totalUsed >= minBayesian && tw > 0)
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

   //--- ATR Spike Detection (skip when Vol-regime already penalized as EVENT)
   if(g_volRegime.regime != VOL_EVENT)
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
      int ci = MathMax(0, MathMin(curSig.caseNumber - 1, CASE_COUNT - 1));

      bool hasCaseData    = (g_sessionStats.totalPerCase[block][ci] >= 20 &&
                             g_sessionStats.winRatePerCase[block][ci] >= 0.0);
      bool hasSessionData = (g_sessionStats.totalPerSession[block] >= 20);

      if(hasCaseData || hasSessionData)
      {
         double measuredWR = hasCaseData
            ? g_sessionStats.winRatePerCase[block][ci]
            : g_sessionStats.winRate[block];
         double baselineWR = g_currentProb.probTP1 / 100.0;

         // Chỉ blend khi 2 nguồn lệch nhau đáng kể.
         // 0.10 = ngưỡng 10%: nếu model nói 60% mà data thực nói 65% → bỏ qua (noise).
         // Nếu model nói 60% mà data thực nói 72% → blend (có thông tin thực sự).
         // Tăng 0.10 → blend ít hơn, tin model nhiều hơn.
         // Giảm 0.10 → blend nhiều hơn, nhạy hơn với data thực (dễ overfit nếu mẫu nhỏ).
         if(MathAbs(measuredWR - baselineWR) > 0.10)
         {
            // Độ không chắc chắn cố định của model lý thuyết (Gambler's Ruin).
            // 0.15 = giả định model sai lệch trung bình ±15% so với thực tế.
            // Tăng 0.15 → model bị tin ít hơn, data thực chiếm trọng số cao hơn.
            // Giảm 0.15 → model bị tin nhiều hơn, data thực ít ảnh hưởng hơn.
            double modelSE = 0.15;

            // p = win rate thực đo được, dùng để tính độ dao động nhị thức.
            // Clamp [0.01, 0.99] tránh chia cho 0 khi p=0 hoặc p=1
            // (xảy ra khi session toàn thắng hoặc toàn thua → không có ý nghĩa thống kê).
            double p = measuredWR;
            if(p <= 0) p = 0.01; if(p >= 1) p = 0.99;

            // n = số mẫu thực tế dùng để đo win rate.
            // n càng lớn → measuredSE càng nhỏ → data thực được tin nhiều hơn.
            // n càng nhỏ → measuredSE càng lớn → model lý thuyết chiếm ưu thế.
            double n = hasCaseData
               ? (double)g_sessionStats.totalPerCase[block][ci]
               : (double)g_sessionStats.totalPerSession[block];

            // z2 = 1.96² = 3.84, ngưỡng của Wilson Score Interval tại confidence 95%.
            // Không cần thay đổi trừ khi muốn đổi confidence level:
            // 90% → z2 = 2.69 | 95% → z2 = 3.84 | 99% → z2 = 6.63
            // Tăng z2 → interval rộng hơn → measuredSE lớn hơn → model được tin hơn.
            double z2 = 3.84;

            // Wilson Score SE: công thức chuẩn đo độ không chắc chắn của win rate thực.
            // Khác binomial SE thuần (sqrt(p*(1-p)/n)) ở chỗ có hiệu chỉnh z2/(4n²)
            // giúp chính xác hơn khi n nhỏ hoặc p gần 0/1.
            // Kết quả: n=20, p=0.60 → SE≈0.107 | n=50 → SE≈0.068 | n=200 → SE≈0.034
            double measuredSE = MathSqrt((p * (1.0 - p) / n + z2 / (4.0 * n * n)) / (1.0 + z2 / n));

            // Floor 0.05: dù n rất lớn, không bao giờ tin data thực tuyệt đối 100%.
            // Giữ lại ít nhất SE=5% để model lý thuyết luôn có tiếng nói.
            // Tăng 0.05 → giới hạn mức độ tin data thực dù có ngàn mẫu.
            // Giảm 0.05 → cho phép data thực dominate hoàn toàn khi n rất lớn.
            measuredSE = MathMax(measuredSE, 0.05);

            double modelWeight    = 1.0 / (modelSE * modelSE);
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
   // STEP 5.7: TIME-DECAY (Survival Analysis)
   //=================================================================
   // Elapsed bars since signal → adjust probability using Weibull model.
   // After SL survival zone: edge increases slightly (survived danger).
   // After avg TP window: edge fades — signal is aging out.
   {
      int barsAgo = iBarShift(NULL, 0, curSig.signalTime, false);
      if(barsAgo < 0) barsAgo = 0;
      if(barsAgo > 0 && (g_currentProb.avgBarsToTP1 > 0 || g_currentProb.avgBarsToSL > 0))
         ApplyTimeDecay(barsAgo);
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