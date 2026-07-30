//+------------------------------------------------------------------+
//|                                        ProbabilityEngine.mqh       |
//|                         QuantEdge - Probability Calculation      |
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
//|   - Weight: w3 = sqrt(n) × 0.15 (it tin nhat, du lieu tho)       |
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
//| adjustedEdge = clamp(edge + edgeAdj, 0.48, TF-ceiling)            |
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
//| - Edge TF-adaptive clamp [0.48, 0.56-0.65] per timeframe          |
//|                                                                    |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_PROBABILITYENGINE_MQH
#define RSI_ADV_PROBABILITYENGINE_MQH

#include "../Core/Config.mqh"
#include "../Core/Structs.mqh"
#include "../Core/Globals.mqh"
#include "../Core/MathUtils.mqh"
#include "MTFEngine.mqh"
#include "../Analysis/Normalize.mqh"
#include "../Analysis/IntermarketAnalysis.mqh"
#include "../Analysis/SessionStatistics.mqh"
#include "WalkForward.mqh"

//+------------------------------------------------------------------+
//| D0-aligned entry time for GMT-normalized H4 charts                 |
//| Native iTime returns broker-local bar time (e.g. 12:00 GMT+3).    |
//| With normalization the signal belongs to a D0 bar (e.g. 08:00 UTC)|
//| so entry must be at the NEXT D0 slot, not next native slot.        |
//+------------------------------------------------------------------+
datetime GetD0AlignedEntry(datetime sigTime)
{
   if(!g_gmtNormActive || Period() < TF_H4)
      return(sigTime + Period() * 60);
   int gmt = GetBrokerGMTOffset();
   int perSec = Period() * 60;
   datetime utc = sigTime - gmt * 3600;
   int secInDay = (int)(utc % 86400);
   if(secInDay < 0) secInDay += 86400;
   int d0Slot = secInDay / perSec;
   datetime dayStart = utc - secInDay;
   datetime utcEntry = dayStart + (d0Slot + 1) * perSec;
   return(utcEntry + gmt * 3600);
}

//+------------------------------------------------------------------+
//| Simulate one signal forward (live-accurate version)                |
//+------------------------------------------------------------------+
int SimulateSignalOutcome(int signalBar, bool isBuy, double entryPrice,
                          double slPrice, double tp1Price, double tp2Price, double tp3Price,
                          int maxBarsForward, int &barsToResult,
                          double knownSpread = 0.0)
{
   barsToResult = 0;

   // [H1-SIM] Use H1-resolution for H4+: 4x finer SL/TP detection.
   // Fall back to H4-bar sim when H1 data doesn't cover the signal's time range.
   if(Period() >= TF_H4)
   {
      datetime sigTime = iTime(NULL, 0, Bars - 1 - signalBar);
      if(sigTime > 0)
      {
         datetime entryChk = GetD0AlignedEntry(sigTime);
         int h1Chk = iBarShift(NULL, TF_H1, entryChk);
         if(h1Chk >= 0)
         {
            datetime h1Time = iTime(NULL, TF_H1, h1Chk);
            if(MathAbs((long)h1Time - (long)entryChk) <= 7200)
               return(SimulateSignalOutcomeH1(sigTime, isBuy, entryPrice, slPrice,
                      tp1Price, tp2Price, tp3Price, maxBarsForward, barsToResult, knownSpread));
         }
      }
   }

   bool tp1Hit = false, tp2Hit = false, tp3Hit = false;
   // [S2] Use spread captured at signal time if available, else fall back to live spread
   double avgSpread = (knownSpread > 0) ? knownSpread : MarketInfo(Symbol(), MODE_SPREAD) * _Point;
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
         // SELL: entered at BID, exit at BID.
         // SL hit when ASK (= BID + spread) reaches slPrice — use effHigh.
         // TP hit when BID drops to tp1Price — use bL (raw BID), NOT bL+spread.
         // [FIX] Previously effLow (=bL+spread) was used for TP, requiring price
         // to travel one extra spread below target. This created a systematic
         // downward bias: SELL win rate understated vs BUY by ~1 spread/ATR.
         double effHigh = bH + avgSpread;

         bool slHit  = (effHigh >= slPrice);
         bool tp1Now = (bL <= tp1Price);   // [FIX] was: effLow <= tp1Price

         if(slHit && tp1Now)
         {
            double distToSL = MathAbs(bO + avgSpread - slPrice);
            double distToTP = MathAbs(bO - tp1Price);   // [FIX] was: bO+spread, use BID open
            if(distToSL <= distToTP * 1.2)
            {
               if(tp1Hit) return(tp2Hit ? (tp3Hit ? 3 : 2) : 1);
               return(-1);
            }
            tp1Hit = true;
            if(bL <= tp2Price) tp2Hit = true;   // [FIX] was: effLow
            if(bL <= tp3Price) tp3Hit = true;   // [FIX] was: effLow
            if(tp3Hit) return(3); if(tp2Hit) return(2); return(1);
         }

         if(slHit)
         {
            if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
            return(-1);
         }

         if(!tp1Hit && bL <= tp1Price) tp1Hit = true;             // [FIX] was: effLow
         if(tp1Hit && !tp2Hit && bL <= tp2Price) tp2Hit = true;   // [FIX] was: effLow
         if(tp2Hit && !tp3Hit && bL <= tp3Price) tp3Hit = true;   // [FIX] was: effLow
         if(tp3Hit) return(3);
      }
   }

   if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
   return(0);
}

//+------------------------------------------------------------------+
//| [GMT-FIX-C5] H1-resolution simulation for H4+ timeframes          |
//| When GMT normalization is active, use H1 bars for SL/TP detection  |
//| giving 4x resolution vs H4 bars. Converts barsToResult to H4 eq.  |
//+------------------------------------------------------------------+
int SimulateSignalOutcomeH1(datetime sigTime, bool isBuy, double entryPrice,
                            double slPrice, double tp1Price, double tp2Price, double tp3Price,
                            int maxBarsForward, int &barsToResult,
                            double knownSpread = 0.0)
{
   barsToResult = 0;
   bool tp1Hit = false, tp2Hit = false, tp3Hit = false;

   double avgSpread = (knownSpread > 0) ? knownSpread : MarketInfo(Symbol(), MODE_SPREAD) * _Point;
   if(avgSpread <= 0)
   {
      double simATR = iATR(NULL, TF_H1, 14, 0);
      if(simATR > 0) avgSpread = simATR * 0.05;
   }

   int barsPerParent = MathMax(Period() / TF_H1, 1);

   // Entry is at the NEXT parent-TF bar open, not the signal bar itself.
   // D0-aligned: on GMT+3 broker, native bar 12:00→entry 16:00 is WRONG.
   // Correct: D0 slot 08:00-12:00→entry 15:00 (=12:00 UTC in server time).
   datetime entryTime = GetD0AlignedEntry(sigTime);
   int h1Entry = iBarShift(NULL, TF_H1, entryTime);
   if(h1Entry < 0) return(0);

   int maxH1Bars = maxBarsForward * barsPerParent;
   int h1Count = 0;

   for(int j = h1Entry; j >= 0 && h1Count < maxH1Bars; j--)
   {
      double bH = iHigh(NULL, TF_H1, j);
      double bL = iLow(NULL, TF_H1, j);
      double bO = iOpen(NULL, TF_H1, j);
      if(bH == 0 || bL == 0) continue;
      h1Count++;

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
               if(tp1Hit) { barsToResult = (h1Count + barsPerParent - 1) / barsPerParent; return(tp2Hit ? (tp3Hit ? 3 : 2) : 1); }
               barsToResult = (h1Count + barsPerParent - 1) / barsPerParent; return(-1);
            }
            tp1Hit = true;
            if(bH >= tp2Price) tp2Hit = true;
            if(bH >= tp3Price) tp3Hit = true;
            barsToResult = (h1Count + barsPerParent - 1) / barsPerParent;
            if(tp3Hit) return(3); if(tp2Hit) return(2); return(1);
         }

         if(slHit)
         {
            barsToResult = (h1Count + barsPerParent - 1) / barsPerParent;
            if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
            return(-1);
         }

         if(!tp1Hit && bH >= tp1Price) tp1Hit = true;
         if(tp1Hit && !tp2Hit && bH >= tp2Price) tp2Hit = true;
         if(tp2Hit && !tp3Hit && bH >= tp3Price) tp3Hit = true;
         if(tp3Hit) { barsToResult = (h1Count + barsPerParent - 1) / barsPerParent; return(3); }
      }
      else
      {
         double effHigh = bH + avgSpread;
         bool slHit  = (effHigh >= slPrice);
         bool tp1Now = (bL <= tp1Price);

         if(slHit && tp1Now)
         {
            double distToSL = MathAbs(bO + avgSpread - slPrice);
            double distToTP = MathAbs(bO - tp1Price);
            if(distToSL <= distToTP * 1.2)
            {
               if(tp1Hit) { barsToResult = (h1Count + barsPerParent - 1) / barsPerParent; return(tp2Hit ? (tp3Hit ? 3 : 2) : 1); }
               barsToResult = (h1Count + barsPerParent - 1) / barsPerParent; return(-1);
            }
            tp1Hit = true;
            if(bL <= tp2Price) tp2Hit = true;
            if(bL <= tp3Price) tp3Hit = true;
            barsToResult = (h1Count + barsPerParent - 1) / barsPerParent;
            if(tp3Hit) return(3); if(tp2Hit) return(2); return(1);
         }

         if(slHit)
         {
            barsToResult = (h1Count + barsPerParent - 1) / barsPerParent;
            if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
            return(-1);
         }

         if(!tp1Hit && bL <= tp1Price) tp1Hit = true;
         if(tp1Hit && !tp2Hit && bL <= tp2Price) tp2Hit = true;
         if(tp2Hit && !tp3Hit && bL <= tp3Price) tp3Hit = true;
         if(tp3Hit) { barsToResult = (h1Count + barsPerParent - 1) / barsPerParent; return(3); }
      }
   }

   barsToResult = (h1Count + barsPerParent - 1) / barsPerParent;
   if(tp3Hit) return(3); if(tp2Hit) return(2); if(tp1Hit) return(1);
   return(0);
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

   // [PROB-FIX-2] Cache per (signalTime, isBuy, caseNum, Bars).
   // Historical bars don't change — result is stable for the same signal.
   static datetime s_t3SigTime = 0;
   static bool     s_t3Buy     = false;
   static int      s_t3Case    = -1;
   static int      s_t3Bars    = -1;
   static int      s_t3Total=0, s_t3To=0, s_t3TP1=0, s_t3TP2=0, s_t3TP3=0, s_t3SL=0;
   static double   s_t3B1=0, s_t3BS=0;
   // [PROB-FIX-2b] Coarse Bars invalidation: Tier3 historical data shifts by 1 each bar,
   // but the pool is large (hundreds of bars) — recomputing every bar is wasteful.
   // Grace window of 20 bars: statistically negligible drift vs. avoiding O(n) scan/bar.
   if(s_t3SigTime == curSig.signalTime && s_t3Buy == curSig.isBuySignal &&
      s_t3Case == curSig.caseNumber && Bars - s_t3Bars < 20)
   {
      total=s_t3Total; timeout=s_t3To; tp1=s_t3TP1; tp2=s_t3TP2;
      tp3=s_t3TP3;     sl=s_t3SL;     bTP1=s_t3B1;  bSL=s_t3BS;
      return;
   }

   int probLookback = MathMin(GetEffectiveProbMaxBars(), Bars - maxFwd - 10);
   int startScan = MathMax(Bars - probLookback, InpRSIPeriod + InpBBPeriod + 10);
   int maxSamples = GetMaxLookbackForTimeframe();

   // [CROSS-BROKER-FIX v2] Time-based hard stop + NEW→OLD scan direction.
   // v1 fix (time cap) was insufficient: OLD→NEW scan collects first maxSamples
   // from the OLDEST bars. Broker with 40k bars samples 5-6 months ago,
   // broker with 10k bars samples 5-7 weeks ago → completely different WR.
   // NEW→OLD: both brokers start from the same recent boundary and collect
   // the same recent qualifying bars → consistent samples.
   int t3MaxDays = (Period() <= TF_M5) ? 60 : (Period() <= TF_H1) ? 180 : 365;
   datetime t3CutoffTime = TimeCurrent() - t3MaxDays * 86400;

   // Dedup guard: stop BEFORE the range already covered by g_signals[] (Tier 1/2).
   int tier3End = MathMin(Bars - maxFwd - 10, MathMax(0, Bars - InpMaxBars));

   for(int i = tier3End - 1; i >= startScan; i--)
   {
      if(total >= maxSamples) break;
      int bs = Bars - 1 - i;
      if(bs < 0) continue;

      // NEW→OLD: once we hit a bar older than cutoff, all remaining are older
      if(iTime(NULL, 0, bs) < t3CutoffTime) break;

      double rsi = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs);
      double atr = iATR(NULL, 0, InpATRPeriod, bs);
      if(rsi == 0 || atr == 0) continue;

      // [ANTI-OVERFIT] Unified RSI windows — all cases use same wide fallback.
      // Old per-case windows (Case 1/5: 25pt, Case 2/3: 25pt, Case 6: 35pt)
      // caused different sample populations when case detection differed between
      // brokers. Unified window = same samples regardless of case number.
      bool similar = false;
      if(curSig.isBuySignal)
      {
         if(rsi<50 && rsi>15) similar=true;
      }
      else
      {
         if(rsi>50 && rsi<85) similar=true;
      }
      if(!similar) continue;

      // --- Angle-tier stratification (Spec: AngleStrength_Probability_Spec.md)
      // [ANTI-OVERFIT] Dead zone [0.3, 0.7]: skip filter when angleStrength
      // is ambiguous. Old sharp threshold at 0.5 caused binary flip between
      // brokers (0.49 vs 0.51 → completely different sample populations).
      // Only filter when angle is clearly strong (>0.7) or clearly weak (<0.3).
      if(curSig.angleStrength > 0.7 &&
         curSig.caseNumber != 2 && curSig.caseNumber != 3)
      {
         double rsiPrev2 = iRSI(NULL, 0, InpRSIPeriod, InpPrice, bs + 2);
         double histAngle = 0.0;
         if(rsiPrev2 > 0 && atr > 0)
            histAngle = MathAbs(rsi - rsiPrev2) / MathMax(atr * 0.5, 0.01);

         bool curStrong  = (curSig.angleStrength >= 1.5);
         bool histStrong = (histAngle >= 1.5);
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
      int out = SimulateSignalOutcome(i, curSig.isBuySignal, ep, s1, t1, t2, t3, maxFwd, btr, curSig.spreadAtSignal);

      if(out == 0) { timeout++; continue; }
      total++;
      if(out >= 1) { tp1++; bTP1 += btr; }
      if(out >= 2) tp2++;
      if(out >= 3) tp3++;
      if(out == -1) { sl++; bSL += btr; }
   }
   // [PROB-FIX-2] Store computed results in cache
   s_t3SigTime = curSig.signalTime; s_t3Buy = curSig.isBuySignal;
   s_t3Case    = curSig.caseNumber; s_t3Bars = Bars;
   s_t3Total=total; s_t3To=timeout; s_t3TP1=tp1; s_t3TP2=tp2;
   s_t3TP3=tp3;     s_t3SL=sl;     s_t3B1=bTP1;  s_t3BS=bSL;
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
   // [PROB-FIX-3] Per-bar cache — 50 iATR calls per run; only recompute on new bar.
   static datetime s_volBarTime = 0;
   datetime s_volCurBar = iTime(NULL, 0, 0);
   if(s_volCurBar == s_volBarTime) return;
   s_volBarTime = s_volCurBar;

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
   return(0.0);
}

void UpdateMarketState()
{
   static datetime s_msLastBar = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(curBar == s_msLastBar) return;
   s_msLastBar = curBar;

   double atr = g_volRegime.atrRatio;
   int trend = DetectMarketRegime(0);
   double bbPct = GetBBWidthPercentile(0, 50);
   bool spreadBad = (g_spreadRegime.isSpike || g_spreadRegime.isExtreme);

   if(atr > 1.5 || spreadBad)
   {
      g_marketState.state = STATE_VOLATILE;
      g_marketState.probMultiplier = 0.80;
      g_marketState.confidence = MathMin(atr / 2.0, 1.0);
      g_marketState.label = "VOLATILE";
   }
   else if(bbPct < 30 && atr < 0.8 && trend == 0)
   {
      g_marketState.state = STATE_MEAN_REVERT;
      g_marketState.probMultiplier = 1.10;
      g_marketState.confidence = (30.0 - bbPct) / 30.0;
      g_marketState.label = "MEAN_REVERT";
   }
   else if(atr >= 0.9 && atr <= 1.5 && trend != 0 && bbPct > 40)
   {
      g_marketState.state = STATE_TRENDING;
      g_marketState.probMultiplier = 1.05;
      g_marketState.confidence = MathMin(MathAbs(atr - 1.0) + 0.5, 1.0);
      g_marketState.label = "TRENDING";
   }
   else
   {
      g_marketState.state = STATE_TRANSITION;
      g_marketState.probMultiplier = 0.95;
      g_marketState.confidence = 0.3;
      g_marketState.label = "TRANSITION";
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
//| [PROB-FIX-5 + S5] Single-pass Tier1+Tier2 weighted scan          |
//| [S5] Continuous similarity weighting: session + angle Gaussian   |
//| [S6] Tracks sumW2 for effective sample size (n_eff)              |
//+------------------------------------------------------------------+
// [BUG#3-FIX] Added t1_rawN/t2_rawN: raw integer signal counts independent of similarity
// weights. Previously (t1_tw + t2_tw) < minSamples was used to trigger Tier 3, but tw is
// a weighted sum — 5 signals with weight 0.1 each gives tw=0.5 which falsely looks like
// "not enough data". Raw counts correctly measure how many distinct signals were available.
void ScanStoredSignalsBoth(const SignalData &curSig, int maxFwd,
   double &t1_tw, int &t1_to, double &t1_w1, double &t1_w2, double &t1_w3, double &t1_ws,
   double &t1_b1, double &t1_bs, double &t1_sumW2, int &t1_rawN,
   double &t2_tw, int &t2_to, double &t2_w1, double &t2_w2, double &t2_w3, double &t2_ws,
   double &t2_b1, double &t2_bs, double &t2_sumW2, int &t2_rawN)
{
   t1_tw=0; t1_to=0; t1_w1=0; t1_w2=0; t1_w3=0; t1_ws=0; t1_b1=0; t1_bs=0; t1_sumW2=0; t1_rawN=0;
   t2_tw=0; t2_to=0; t2_w1=0; t2_w2=0; t2_w3=0; t2_ws=0; t2_b1=0; t2_bs=0; t2_sumW2=0; t2_rawN=0;

   // [S4-FIX] Pre-build outcome override map: O(signalCount + outcomeCount) single pass
   // instead of O(signalCount × outcomeCount) nested loop.
   // Both g_signals[] and g_outcomes[] are chronologically ordered — two-pointer merge.
   // [PERF-FIX] Static array: ArrayResize is O(n) heap alloc called every bar on M1 with
   // many signals. Resize only when g_signalCount grows; ArrayFill still needed each call
   // to clear stale overrides from the previous signal set.
   static int outcomeOverride[];
   static int s_oaAllocSize = 0;
   if(g_signalCount > s_oaAllocSize)
   {
      ArrayResize(outcomeOverride, g_signalCount);
      s_oaAllocSize = g_signalCount;
   }
   ArrayFill(outcomeOverride, 0, g_signalCount, 0);
   {
      int oIdx = 0;
      for(int s = 0; s < g_signalCount && oIdx < g_outcomeCount; s++)
      {
         // Advance outcome pointer to match or pass signal time
         while(oIdx < g_outcomeCount &&
               g_outcomes[oIdx].signalTime < g_signals[s].signalTime)
            oIdx++;
         if(oIdx < g_outcomeCount &&
            g_outcomes[oIdx].signalTime == g_signals[s].signalTime &&
            g_outcomes[oIdx].outcome != 0)
            outcomeOverride[s] = g_outcomes[oIdx].outcome;
      }
   }

   // [ISSUE #5 FIX] Use signalTimeUTC for session block comparison.
   // signalTimeUTC is pre-converted to UTC boundary at signal creation (StoreSignal).
   // Avoids re-running GetUTCHour(broker_time) which can be wrong when GMT offset cache
   // is stale, and eliminates the cross-midnight day-loss bug (Bug 2 root cause).
   // Fallback to broker-time conversion for old signals loaded from binary (signalTimeUTC==0).
   int curBlock = (curSig.signalTimeUTC > 0)
                  ? GetSessionBlockUTC(curSig.signalTimeUTC)
                  : GetSessionBlock(curSig.signalTime);

   for(int s = 0; s < g_signalCount; s++)
   {
      if(g_signals[s].signalTime == curSig.signalTime) continue;
      if(g_signals[s].isBuySignal != curSig.isBuySignal) continue;

      // [FIX-P0] Same forward-window cap as the Tier1+2 scan (symmetric window).
      int timeBasedMax = 1440 / MathMax(Period(), 1);
      timeBasedMax = MathMin(timeBasedMax, maxFwd * 3);
      timeBasedMax = MathMax(timeBasedMax, maxFwd);
      if(g_signals[s].barIndex + timeBasedMax >= Bars) continue;

      int out, btr;
      if(g_signals[s].simCachedTP != 99)
      {
         out = g_signals[s].simCachedTP;
         btr = g_signals[s].simCachedBTR;
      }
      else if(g_signals[s].barIndex == -1)
      {
         // [BINARY-CACHE-GUARD] Stale barIndex from binary load; outcome unknown → skip.
         continue;
      }
      else
      {
         btr = 0;
         out = SimulateSignalOutcome(
            g_signals[s].barIndex, g_signals[s].isBuySignal,
            g_signals[s].entryPrice, g_signals[s].stopLoss,
            g_signals[s].takeProfit1, g_signals[s].takeProfit2, g_signals[s].takeProfit3,
            timeBasedMax, btr, g_signals[s].spreadAtSignal);
         g_signals[s].simCachedTP  = out;
         g_signals[s].simCachedBTR = btr;
      }

      // [S4] Override simulation with actual outcome — O(1) via pre-built map
      if(outcomeOverride[s] != 0)
      {
         if(outcomeOverride[s] > 0 && out <= 0) out = 1;
         if(outcomeOverride[s] < 0 && out >= 1) out = -1;
      }

      // [S5] Continuous similarity weight
      double w = 1.0;
      // [ISSUE #5 FIX] Use signalTimeUTC for historical signal session block.
      // Same rationale as curBlock above: avoid broker-time re-conversion per-signal.
      int histBlock = (g_signals[s].signalTimeUTC > 0)
                      ? GetSessionBlockUTC(g_signals[s].signalTimeUTC)
                      : GetSessionBlock(g_signals[s].signalTime);
      int sessDiff = MathAbs(curBlock - histBlock);
      if(sessDiff > 2) sessDiff = 4 - sessDiff;
      w *= (sessDiff == 0) ? 1.0 : (sessDiff == 1) ? 0.7 : 0.4;

      if(curSig.angleStrength > 0.1 && g_signals[s].angleStrength > 0.1)
      {
         double dz = curSig.angleStrength - g_signals[s].angleStrength;
         w *= MathExp(-0.5 * dz * dz / 4.0); // Gaussian kernel sigma=2.0
      }

      // [S7] Recency decay: halflife varies by TF — regime changes faster on lower TFs.
      // [FIX-S7a] daysDiff < 0 means historical signal is timestamped after curSig (data
      // anomaly or bar-shift edge case). Skip rather than amplify weight (exp(-negative)>1).
      // [FIX-S7b] Hard prune by TF: signals older than maxDays are skipped entirely to
      // avoid iterating effectively-zero-weight entries that waste CPU on large histories.
      double daysDiff = (double)(curSig.signalTime - g_signals[s].signalTime) / 86400.0;
      if(daysDiff < 0) continue;   // [FIX-S7a] anomaly guard
      {
         // [GMT-FIX] Compare minutes, not ENUM_TIMEFRAMES (PERIOD_H1=16385 in MT5)
         int maxDays = (Period() <= TF_M5) ? 60 : (Period() <= TF_H1) ? 180 : 365;
         if(daysDiff > maxDays) continue;   // [FIX-S7b] TF-scaled hard prune
      }
      if(daysDiff > 0)
      {
         double halfLife = (Period() <= TF_M5) ? 60.0 : (Period() <= TF_H1) ? 90.0 : 120.0;
         w *= MathExp(-0.693 * daysDiff / halfLife);
      }

      // [S8] RSI proximity Gaussian kernel — TF-adaptive sigma.
      // sigma=12 for M1/M5, sigma=8 for M15+ (H4+ was 5 but caused n=0 squeeze).
      if(curSig.rsiAtSignal > 0 && g_signals[s].rsiAtSignal > 0)
      {
         double dr = curSig.rsiAtSignal - g_signals[s].rsiAtSignal;
         double sigma_rsi = (Period() <= TF_M5) ? 12.0 : 8.0;
         w *= MathExp(-0.5 * dr * dr / (sigma_rsi * sigma_rsi));
      }

      // [S9] ATR regime similarity: log-ratio with sigma_log=0.7
      if(curSig.atrValue > 0 && g_signals[s].atrValue > 0)
      {
         double logR = MathLog(curSig.atrValue / g_signals[s].atrValue);
         w *= MathExp(-logR * logR / 0.96);
      }

      bool sameCase = (g_signals[s].caseNumber == curSig.caseNumber);

      // Accumulate into Tier2 (all cases) — weighted
      if(out == 0) { t2_to++; if(sameCase) t1_to++; continue; }
      t2_tw += w;
      t2_rawN++;          // [BUG#3-FIX] raw count: 1 per signal regardless of weight
      t2_sumW2 += w * w;
      if(out >= 1) { t2_w1 += w; t2_b1 += btr * w; }
      if(out >= 2) t2_w2 += w;
      if(out >= 3) t2_w3 += w;
      if(out == -1) { t2_ws += w; t2_bs += btr * w; }

      // Accumulate into Tier1 (same-case subset) — weighted
      if(sameCase)
      {
         t1_tw += w;
         t1_rawN++;       // [BUG#3-FIX] raw count same-case
         t1_sumW2 += w * w;
         if(out >= 1) { t1_w1 += w; t1_b1 += btr * w; }
         if(out >= 2) t1_w2 += w;
         if(out >= 3) t1_w3 += w;
         if(out == -1) { t1_ws += w; t1_bs += btr * w; }
      }
   }

   // Subtract Tier1 from Tier2 → Tier2 becomes "other-case only"
   t2_tw -= t1_tw; t2_w1 -= t1_w1; t2_w2 -= t1_w2;
   t2_w3 -= t1_w3; t2_ws -= t1_ws;
   t2_b1 -= t1_b1; t2_bs -= t1_bs;
   t2_sumW2 -= t1_sumW2;
   t2_rawN  -= t1_rawN;   // [BUG#3-FIX] subtract same-case raw count
   if(t2_tw < 0) t2_tw = 0; if(t2_w1 < 0) t2_w1 = 0;
   if(t2_w2 < 0) t2_w2 = 0; if(t2_w3 < 0) t2_w3 = 0;
   if(t2_ws < 0) t2_ws = 0; if(t2_b1 < 0) t2_b1 = 0;
   if(t2_bs < 0) t2_bs = 0; if(t2_sumW2 < 0) t2_sumW2 = 0;
   if(t2_rawN < 0) t2_rawN = 0;
}

//+------------------------------------------------------------------+
//| Main probability calculation                                       |
//+------------------------------------------------------------------+
void CalculateProbability(int currentSignalIndex)
{
   static int      s_probCachedSigIdx  = -1;
   static datetime s_probCachedBarTime = 0;
   datetime curBar = iTime(NULL, 0, 0);
   if(currentSignalIndex == s_probCachedSigIdx && curBar == s_probCachedBarTime)
      return;
   s_probCachedSigIdx  = currentSignalIndex;
   s_probCachedBarTime = curBar;

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
   g_currentProb.rawCountT1=0; g_currentProb.rawCountT2=0; g_currentProb.countT3=0;
   g_currentProb.nEffT1=0; g_currentProb.nEffT2=0; g_currentProb.timeoutCount=0;
   g_currentProb.oldestDays=0; g_currentProb.realPct=0;
   g_currentProb.wrT1=0; g_currentProb.wrT2=0; g_currentProb.wrT3=0;
   g_currentProb.xgbProbTP1=0; g_currentProb.xgbWeight=0;
   g_currentProb.bayesianWeight=1.0; g_currentProb.xgbActive=false;

   // [GMT-FIX-A2c] Reset data quality warning each recalc cycle
   g_gmtDataQualityWarn = false;
   g_gmtWarnReason = "";

   if(!InpShowProbability) return;
   if(currentSignalIndex < 0 || currentSignalIndex >= g_signalCount) return;

   SignalData curSig = g_signals[currentSignalIndex];
   int minSamples = GetMinSamplesForTimeframe();
   int maxFwd = GetMaxForwardBarsForTimeframe();

   //=================================================================
   // STEP 1: Historical simulation (3 tiers) — [S5] weighted scan
   //=================================================================
   double t1_tw=0, t1_w1=0, t1_w2=0, t1_w3=0, t1_ws=0;
   double t1_b1=0, t1_bs=0, t1_sumW2=0;
   int t1_to=0, t1_rawN=0;   // [BUG#3-FIX] raw count for Tier 3 trigger
   double t2_tw=0, t2_w1=0, t2_w2=0, t2_w3=0, t2_ws=0;
   double t2_b1=0, t2_bs=0, t2_sumW2=0;
   int t2_to=0, t2_rawN=0;   // [BUG#3-FIX] raw count for Tier 3 trigger
   ScanStoredSignalsBoth(curSig, maxFwd,
      t1_tw, t1_to, t1_w1, t1_w2, t1_w3, t1_ws, t1_b1, t1_bs, t1_sumW2, t1_rawN,
      t2_tw, t2_to, t2_w1, t2_w2, t2_w3, t2_ws, t2_b1, t2_bs, t2_sumW2, t2_rawN);

   int t3_t=0, t3_to=0, t3_1=0, t3_2=0, t3_3=0, t3_s=0;
   double t3_b1=0, t3_bs=0;
   // Tier 3 gate: use preliminary nEff (not raw count) — raw count ignores S5-S9 weighting.
   // H4 1500bars: rawCount12=40+ but nEff=6 → raw gate says "enough data", nEff says "starving".
   // [FIX-TIER-TW] H4+ lowered from 1.5→1.0: S5-S9 weighting crushes tw heavily
   // on sparse H4 data. MT4 had tw=1.45 (12 raw signals) excluded at 1.5 threshold
   // while MT5 had tw=1.53 included → completely opposite results from 0.08 diff.
   double tierMinTw = (Period() >= TF_H4) ? 1.0 : 3.0;
   double pre_sw  = ((t1_tw >= tierMinTw) ? t1_tw : 0) + ((t2_tw >= tierMinTw) ? t2_tw : 0);
   double pre_sw2 = ((t1_tw >= tierMinTw) ? t1_sumW2 : 0) + ((t2_tw >= tierMinTw) ? t2_sumW2 : 0);
   double prelimNEff = (pre_sw2 > 0) ? (pre_sw * pre_sw) / pre_sw2 : 0;

   if(prelimNEff < minSamples * 2)
      ScanHistoricalATRBased(curSig, t3_t, t3_to,
                             t3_1, t3_2, t3_3, t3_s, t3_b1, t3_bs, maxFwd);

   double w1 = (t1_tw >= tierMinTw) ? MathPow(t1_tw, 0.75) * 1.0  : 0;
   double w2 = (t2_tw >= tierMinTw) ? MathSqrt(t2_tw)      * 0.5  : 0;
   double t3Scale = (prelimNEff < minSamples) ? 1.0 :
                    MathMax(0.0, 1.0 - (prelimNEff - (double)minSamples) / (double)minSamples);
   double w3 = (t3_t >= 3) ? MathSqrt((double)t3_t) * 0.15 * t3Scale : 0;

   // [FIX-T3-CAP] Tier 3 (ATR scan) must not outweigh real signal data (Tier 1/2).
   // Problem: sqrt(203)*0.15 = 2.14 > w1=1.38 → Tier 3 WR=17.7% dominates histTP1.
   // Tier 3 lacks actual signal conditions — mostly mid-trend bars where SL hits,
   // so its WR can be worse than random walk. Cap at 50% of best real-signal tier.
   double wReal = MathMax(w1, w2);
   if(wReal > 0 && w3 > wReal * 0.5)
      w3 = wReal * 0.5;
   // [FIX-T3-FALLBACK] When both real tiers fall below tierMinTw (wReal=0) but raw
   // signals DO exist, Tier 3 gets unlimited weight. Cap at 0.5 absolute — Tier 3
   // alone (no real-signal anchor) should never drive strong recommendations.
   else if(wReal == 0 && (t1_rawN + t2_rawN) >= 3 && w3 > 0.5)
      w3 = 0.5;

   double tw = 0, wTP1 = 0, wTP2 = 0, wTP3 = 0, wSL = 0, wB1 = 0, wBS = 0;
   double totalSumW = 0, totalSumW2 = 0;

   if(w1 > 0)
   {
      wTP1+=(t1_w1/t1_tw)*w1; wTP2+=(t1_w2/t1_tw)*w1;
      wTP3+=(t1_w3/t1_tw)*w1; wSL +=(t1_ws/t1_tw)*w1;
      tw+=w1; totalSumW+=t1_tw; totalSumW2+=t1_sumW2;
      if(t1_w1>0) wB1+=(t1_b1/t1_w1)*w1;
      if(t1_ws>0) wBS+=(t1_bs/t1_ws)*w1;
   }
   if(w2 > 0)
   {
      wTP1+=(t2_w1/t2_tw)*w2; wTP2+=(t2_w2/t2_tw)*w2;
      wTP3+=(t2_w3/t2_tw)*w2; wSL +=(t2_ws/t2_tw)*w2;
      tw+=w2; totalSumW+=t2_tw; totalSumW2+=t2_sumW2;
      if(t2_w1>0) wB1+=(t2_b1/t2_w1)*w2;
      if(t2_ws>0) wBS+=(t2_bs/t2_ws)*w2;
   }
   if(w3 > 0)
   {
      wTP1+=((double)t3_1/t3_t)*w3; wTP2+=((double)t3_2/t3_t)*w3;
      wTP3+=((double)t3_3/t3_t)*w3; wSL +=((double)t3_s/t3_t)*w3;
      tw+=w3; totalSumW+=(double)t3_t; totalSumW2+=(double)t3_t;
      if(t3_1>0) wB1+=(t3_b1/t3_1)*w3;
      if(t3_s>0) wBS+=(t3_bs/t3_s)*w3;
   }

   // [S6] Effective sample size for weighted data
   double nEff = (totalSumW2 > 0) ? (totalSumW * totalSumW) / totalSumW2 : 0;
   int totalUsed = (int)MathRound(nEff);

   g_currentProb.totalSamples = totalUsed;
   g_currentProb.samplesTP1 = (int)MathRound(t1_w1 + t2_w1) + t3_1;
   g_currentProb.samplesTP2 = (int)MathRound(t1_w2 + t2_w2) + t3_2;
   g_currentProb.samplesTP3 = (int)MathRound(t1_w3 + t2_w3) + t3_3;
   g_currentProb.samplesSL  = (int)MathRound(t1_ws + t2_ws) + t3_s;

   int minBayesian = MathMax(10, GetMinSamplesForTimeframe() / 3);
   double histTP1=0, histTP2=0, histTP3=0, histSL=0;
   // avgBarsToTP1/SL: simple weighted average — not gated by minBayesian.
   if(tw > 0)
   {
      g_currentProb.avgBarsToTP1 = wB1/tw;
      g_currentProb.avgBarsToSL  = wBS/tw;
   }

   // ATR-distance fallback: fires when tw=0 (all tiers below weight threshold due to
   // S5-S9 heavy discounting on H4+) OR wB1=0 (all simulations timed out).
   // Without this, avgBarsToTP1 stays 0 → ApplyTimeDecay never fires → no Edge display.
   // Random walk scaling: E[bars] = (distance/ATR)^2 — price diffuses as sqrt(N),
   // so reaching D ATR takes D^2 bars on average. Linear (D/ATR) assumes straight-line
   // movement and underestimates severely (4 bars vs 16 for TP1=4×ATR).
   if(g_currentProb.avgBarsToTP1 <= 0 && g_currentProb.avgBarsToSL <= 0 && curSig.atrValue > 0)
   {
      double tp1Dist = MathAbs(curSig.takeProfit1 - curSig.entryPrice);
      double slDist  = MathAbs(curSig.stopLoss    - curSig.entryPrice);
      if(tp1Dist > 0)
      {
         double tp1R = tp1Dist / curSig.atrValue;
         double slR  = slDist  / MathMax(curSig.atrValue, 0.0001);
         g_currentProb.avgBarsToTP1 = MathMax(2.0, tp1R * tp1R);
         g_currentProb.avgBarsToSL  = MathMax(2.0, slR  * slR);
      }
   }

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
   }

   // Data quality metrics (V11.30)
   double t1NE = (t1_sumW2 > 0) ? t1_tw*t1_tw/t1_sumW2 : 0;
   double t2NE = (t2_sumW2 > 0) ? t2_tw*t2_tw/t2_sumW2 : 0;
   double t1WR = (t1_tw > 0) ? t1_w1/t1_tw*100.0 : 0;
   double t2WR = (t2_tw > 0) ? t2_w1/t2_tw*100.0 : 0;
   double t3WR = (t3_t > 0) ? (double)t3_1/t3_t*100.0 : 0;
   g_currentProb.rawCountT1  = t1_rawN;
   g_currentProb.rawCountT2  = t2_rawN;
   g_currentProb.countT3     = t3_t;
   g_currentProb.nEffT1      = t1NE;
   g_currentProb.nEffT2      = t2NE;
   g_currentProb.timeoutCount = t1_to + t2_to + t3_to;
   g_currentProb.wrT1 = t1WR;
   g_currentProb.wrT2 = t2WR;
   g_currentProb.wrT3 = t3WR;
   double realN = t1NE + t2NE;
   g_currentProb.realPct = (totalUsed > 0) ? realN / totalUsed * 100.0 : 0;
   // Oldest contributing signal age
   double oldDays = 0;
   for(int sOld = 0; sOld < g_signalCount; sOld++)
   {
      if(g_signals[sOld].isBuySignal != curSig.isBuySignal) continue;
      double dd = (double)(curSig.signalTime - g_signals[sOld].signalTime) / 86400.0;
      if(dd > oldDays) oldDays = dd;
   }
   g_currentProb.oldestDays = oldDays;

   // [DEBUG] Per-tier breakdown
   if(InpDebugMode)
   {
      Print("[PROB-TIER] ChartSig=", g_signalCount,
            " | T1(case): raw=", t1_rawN, " nEff=", DoubleToString(t1NE,1),
            " tw=", DoubleToString(t1_tw,2), " WR=", DoubleToString(t1WR,1), "%",
            " | T2(other): raw=", t2_rawN, " nEff=", DoubleToString(t2NE,1),
            " tw=", DoubleToString(t2_tw,2), " WR=", DoubleToString(t2WR,1), "%",
            " | T3(ATR): n=", t3_t, " WR=", DoubleToString(t3WR,1), "%",
            " | nEff=", totalUsed, " histTP1=", DoubleToString(histTP1,1), "%",
            " w1=", DoubleToString(w1,2), " w2=", DoubleToString(w2,2),
            " w3=", DoubleToString(w3,2));
   }

   //=================================================================
   // STEP 2: Measure edge from data
   //=================================================================
   double measuredEdge = MeasureEdgeFromHistory(
      curSig.caseNumber, curSig.isBuySignal, maxFwd);
   g_cachedEdge = measuredEdge;

   //=================================================================
   // STEP 3: MTF + Intermarket adjusted edge
   //=================================================================
   double edgeAdjustment = 0;
   double _exMtfAdj = 0, _exInterAdj = 0, _exAngleAdj = 0;

   if(InpShowMTF && g_mtfCount > 0)
   {
      int agreeCount = 0;
      for(int t = 0; t < g_mtfCount; t++)
      {
         if(curSig.isBuySignal && g_mtfData[t].trend == 1) agreeCount++;
         if(!curSig.isBuySignal && g_mtfData[t].trend == -1) agreeCount++;
      }
      double alignRatio = ((double)agreeCount / (double)g_mtfCount) * 2.0 - 1.0;
      _exMtfAdj = alignRatio * 0.03;
      edgeAdjustment += _exMtfAdj;
   }

   if(g_intermarket.isAvailable)
   {
      double interAdj = GetIntermarketEdgeAdjustment(curSig.isBuySignal);
      _exInterAdj = interAdj;
      edgeAdjustment += interAdj;
   }

   // --- Angle strength edge adjustment (Spec: AngleStrength_Probability_Spec.md)
   // Z > 1.0 = stronger angle than average → +edge; Z < 1.0 = weaker → -edge
   // Divergence cases (2,3) damped to 40% because structure matters more than angle
   // Formula: adj = (Z - 1.0) × 0.03, clamped [-0.03, +0.04]
   // [S1] IC gate: only apply angle edge when IC confirms angleStrength predicts outcome
   if(curSig.angleStrength > 0.1 &&
      g_walkForward.icSamples >= 20 && g_walkForward.infoCoeff >= 0.05)
   {
      double caseDamp = (curSig.caseNumber == 2 || curSig.caseNumber == 3) ? 0.4 : 1.0;
      double angleAdj = MathMax(-0.03, MathMin(0.04, (curSig.angleStrength - 1.0) * 0.03));
      _exAngleAdj = angleAdj * caseDamp;
      edgeAdjustment += _exAngleAdj;
   }

   // --- Vol-regime edge adjustment
   // QUIET market: RSI OB/OS signals more reliable (+2% edge)
   // EVENT/spike: reduce confidence (-5% edge)
   UpdateVolRegime();
   edgeAdjustment += GetVolRegimeEdgeAdjustment();

   // [FIX-P1] TF-adaptive edge ceiling: M1=0.56, M5=0.58, M15=0.60, M30=0.62, H1=0.63, H4+=0.65
   // Lower TFs: higher noise, larger proportional spread cost, shorter signal persistence.
   // Menkhoff 2010 (daily), Kozhan & Salmon 2012 (intraday): M1 edge rarely >55-56%.
   // Old flat 0.65 → Gambler's Ruin P(TP1)=72% on M1, unrealistic. Now capped per TF.
   double edgeCeiling = 0.65;
   {
      int tfCeil = Period();
      if(tfCeil <= TF_M1)       edgeCeiling = 0.56;
      else if(tfCeil <= TF_M5)  edgeCeiling = 0.58;
      else if(tfCeil <= TF_M15) edgeCeiling = 0.60;
      else if(tfCeil <= TF_M30) edgeCeiling = 0.62;
      else if(tfCeil <= TF_H1)  edgeCeiling = 0.63;
   }
   double adjustedEdge = MathMax(0.48, MathMin(edgeCeiling, measuredEdge + edgeAdjustment));
   double _exEdgeBeforeMktSt = adjustedEdge;

   UpdateMarketState();
   adjustedEdge = MathMax(0.48, MathMin(edgeCeiling, adjustedEdge * g_marketState.probMultiplier));

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

   //--- Attribution: cumulative Gambler's Ruin recalc per edge step (Nhóm A)
   if(InpShowProbExplain)
   {
      g_explainData.baseEdge = measuredEdge;
      g_explainData.edgeMTF   = _exMtfAdj;
      g_explainData.edgeInter = _exInterAdj;
      g_explainData.edgeAngle = _exAngleAdj;
      g_explainData.edgeMktSt = g_marketState.probMultiplier;

      double _eBase = MathMax(0.48, MathMin(edgeCeiling, measuredEdge));
      g_explainData.probAfterBase = CalculateRealMarketProbTP(_eBase, slDist, tp1Dist, curSig.atrValue) * 100.0;

      double _eMTF = MathMax(0.48, MathMin(edgeCeiling, measuredEdge + _exMtfAdj));
      g_explainData.probAfterMTF = CalculateRealMarketProbTP(_eMTF, slDist, tp1Dist, curSig.atrValue) * 100.0;

      double _eInter = MathMax(0.48, MathMin(edgeCeiling, measuredEdge + _exMtfAdj + _exInterAdj));
      g_explainData.probAfterInter = CalculateRealMarketProbTP(_eInter, slDist, tp1Dist, curSig.atrValue) * 100.0;

      double _eAngle = MathMax(0.48, MathMin(edgeCeiling, measuredEdge + _exMtfAdj + _exInterAdj + _exAngleAdj));
      g_explainData.probAfterAngle = CalculateRealMarketProbTP(_eAngle, slDist, tp1Dist, curSig.atrValue) * 100.0;

      double _eMktSt = MathMax(0.48, MathMin(edgeCeiling, _exEdgeBeforeMktSt * g_marketState.probMultiplier));
      g_explainData.probAfterMktSt = CalculateRealMarketProbTP(_eMktSt, slDist, tp1Dist, curSig.atrValue) * 100.0;

      g_explainData.fatTailPenalty = GetFatTailPenalty();
      g_explainData.volClusterPen = GetVolClusterPenalty();
      g_explainData.spreadDrag    = GetSpreadDrag(curSig.atrValue);
      g_explainData.probAfterCorrections = theoTP1;
      g_explainData.theoTP1 = theoTP1;
      g_explainData.histTP1 = histTP1;
   }

   //=================================================================
   // STEP 5: Bayesian combine historical + theoretical
   //=================================================================
   if(totalUsed >= minBayesian && tw > 0)
   {
      // [S6] Pass nEff (double) for proper Wilson SE with weighted samples
      g_currentProb.probTP1 = CombineTheoreticalHistorical(theoTP1, histTP1, nEff, minSamples);
      g_currentProb.probTP2 = CombineTheoreticalHistorical(theoTP2, histTP2, nEff, minSamples);
      g_currentProb.probTP3 = CombineTheoreticalHistorical(theoTP3, histTP3, nEff, minSamples);
      g_currentProb.probSL  = 100.0 - g_currentProb.probTP1;
   }
   else
   {
      g_currentProb.probTP1 = theoTP1;
      g_currentProb.probTP2 = MathMin(theoTP2, theoTP1);
      g_currentProb.probTP3 = MathMin(theoTP3, theoTP2);
      g_currentProb.probSL  = 100.0 - theoTP1;
   }

   if(InpShowProbExplain)
      g_explainData.probAfterBayes = g_currentProb.probTP1;

   //=================================================================
   // STEP 5.1: XGBoost integration (V12)
   // Mode: CALIBRATION — skip entirely (Bayesian only, default)
   //       XGBOOST    — override probTP1 with XGBPredict()
   //       ENSEMBLE   — Brier-weighted avg of Bayesian + XGBoost
   //=================================================================
   if(InpProbMode != PROB_CALIBRATION)
   {
      double xgbProb = XGBGetPrediction(curSig);
      g_currentProb.xgbProbTP1 = xgbProb;
      g_xgbProbTP1 = xgbProb;

      if(InpProbMode == PROB_XGBOOST)
      {
         if(XGBIsReady())
         {
            g_currentProb.probTP1 = xgbProb;
            g_currentProb.probSL  = 100.0 - xgbProb;
            g_currentProb.xgbActive = true;
            g_currentProb.xgbWeight = 1.0;
            g_currentProb.bayesianWeight = 0.0;
         }
         // else: fallback — keep Bayesian probTP1 as-is
      }
      else // PROB_ENSEMBLE
      {
         if(XGBIsReady())
         {
            double wBayes = 0, wXGB = 0;
            double combined = CombineXGBWithBayesian(
               g_currentProb.probTP1, xgbProb, wBayes, wXGB);
            g_currentProb.probTP1 = combined;
            g_currentProb.probSL  = 100.0 - combined;
            g_currentProb.xgbActive = true;
            g_currentProb.xgbWeight = wXGB;
            g_currentProb.bayesianWeight = wBayes;
         }
         // else: fallback — keep Bayesian probTP1 as-is
      }
   }

   if(InpShowProbExplain)
      g_explainData.probAfterXGB = g_currentProb.probTP1;

   //=================================================================
   // STEP 5.5: BROKER-RESISTANT confidence adjustments
   //=================================================================

   //--- 1-Bar Price Confirmation (Brooks 2012)
   bool _exConfirmed = true;
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
         _exConfirmed = confirmed;

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

   if(InpShowProbExplain)
   {
      g_explainData.probAfterConfirm = g_currentProb.probTP1;
      g_explainData.confirmHit = _exConfirmed;
   }

   //--- ATR Spike Detection (skip when Vol-regime already penalized as EVENT)
   // [PROB-FIX-4] Cache signal-bar ATR ratio per signal index.
   // Signal bar is a closed historical bar — its avgATR context never changes.
   static int    s_spikeIdx    = -2;
   static double s_spikeCurATR = 0;
   static double s_spikeAvgATR = 0;
   if(g_volRegime.regime != VOL_EVENT)
   {
      if(currentSignalIndex != s_spikeIdx)
      {
         s_spikeIdx    = currentSignalIndex;
         s_spikeCurATR = 0;
         s_spikeAvgATR = 0;
         int curBarShift = Bars - 1 - curSig.barIndex;
         if(curBarShift >= 0)
         {
            s_spikeCurATR = iATR(NULL, 0, InpATRPeriod, curBarShift);
            int atrCount  = 0;
            for(int a = curBarShift + 1; a <= curBarShift + 50 && a < Bars; a++)
            { s_spikeAvgATR += iATR(NULL, 0, InpATRPeriod, a); atrCount++; }
            if(atrCount > 0) s_spikeAvgATR /= atrCount;
         }
      }
      if(s_spikeAvgATR > 0 && s_spikeCurATR > s_spikeAvgATR * 2.0)
      {
         double spikeRatio   = s_spikeCurATR / s_spikeAvgATR;
         double shrinkFactor = 1.0 / spikeRatio;
         g_currentProb.probTP1 = 50.0 + (g_currentProb.probTP1 - 50.0) * shrinkFactor;
         g_currentProb.probTP2 = 50.0 + (g_currentProb.probTP2 - 50.0) * shrinkFactor;
         g_currentProb.probTP3 = 50.0 + (g_currentProb.probTP3 - 50.0) * shrinkFactor;
         g_currentProb.probSL  = 100.0 - g_currentProb.probTP1;
      }
   }

   if(InpShowProbExplain)
   {
      g_explainData.probAfterSpike = g_currentProb.probTP1;
      g_explainData.spikeRatio = (s_spikeAvgATR > 0) ? s_spikeCurATR / s_spikeAvgATR : 0;
   }

   //=================================================================
   // STEP 5.6: SESSION QUALITY adjustment
   //=================================================================
   double _exSessionRatio = 1.0;
   {
      int block = GetSessionBlock(curSig.signalTime);
      int ci = MathMax(0, MathMin(curSig.caseNumber - 1, CASE_COUNT - 1));

      // [ANTI-OVERFIT] n>=50 (was 20): 20 samples per (session×case) cell
      // is statistically noisy — Wilson SE≈0.107 at p=0.60, n=20.
      // At n=50, SE≈0.068 — much more reliable calibration signal.
      bool hasCaseData    = (g_sessionStats.totalPerCase[block][ci] >= 50 &&
                             g_sessionStats.winRatePerCase[block][ci] >= 0.0);
      bool hasSessionData = (g_sessionStats.totalPerSession[block] >= 50);

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

               // [ANTI-OVERFIT] Cap ratio to [0.85, 1.15] — prevent session stats
               // from reversing trading decisions. Old [0.30, inf) allowed 3x crush
               // or unlimited boost → same signal showed AVOID on one broker, ENTRY
               // on another due to different per-terminal outcome CSVs.
               // ±15% max adjustment preserves calibration value without overfitting.
               if(ratio < 0.85)
               {
                  ratio = 0.85;
                  g_gmtDataQualityWarn = true;
                  g_gmtWarnReason = "Session ratio floored";
               }
               if(ratio > 1.15) ratio = 1.15;

               g_currentProb.probTP1 *= ratio;
               g_currentProb.probTP2 *= ratio;
               g_currentProb.probTP3 *= ratio;
               g_currentProb.probSL = 100.0 - g_currentProb.probTP1;
               _exSessionRatio = ratio;
            }
         }
      }
   }

   if(InpShowProbExplain)
   {
      g_explainData.probAfterSession = g_currentProb.probTP1;
      g_explainData.sessionRatio = _exSessionRatio;
   }

   //=================================================================
   // STEP 5.65: BRIER CALIBRATION SHRINK
   //=================================================================
   // When Brier Score shows probability is unreliable, shrink toward 50%.
   // shrinkFactor ramps linearly: Brier 0.20→1.0 (no shrink), 0.35→0.0 (full shrink to 50%).
   // 0 free parameters: 0.20 = well-calibrated threshold, 0.35 = worse than random (0.25) + margin.
   // Requires minimum 20 resolved samples — below that, Brier is noise.
   //
   // PER-CASE (anti-overconfidence for new/low-frequency cases like Case 8):
   // - Case has >=20 resolved outcomes  -> shrink on THIS case's own Brier (isolated).
   // - Case has <20 resolved outcomes   -> calibration UNVALIDATED: (a) still apply the
   //   global Brier shrink if the global forecaster is unreliable, then (b) an uncertainty
   //   shrink ramping 0.5→1.0 with validation count, so a brand-new case cannot display a
   //   high-confidence number before its own predictions are validated.
   {
      int    cbn        = curSig.caseNumber;
      int    caseBrierN = (cbn >= 0 && cbn <= 9) ? g_brierCaseSamples[cbn] : 0;
      double caseBrier  = (cbn >= 0 && cbn <= 9) ? g_brierCaseScore[cbn]   : 0.0;

      double shrink = 1.0;   // 1.0 = no shrink
      if(caseBrierN >= 20)
      {
         if(caseBrier > 0.20)
            shrink = MathMax(0.0, 1.0 - (caseBrier - 0.20) / 0.15);
      }
      else
      {
         // (a) global Brier shrink (legacy behavior) when global is unreliable
         if(g_brierMetrics.samples >= 20 && g_brierMetrics.brierScore > 0.20)
            shrink = MathMax(0.0, 1.0 - (g_brierMetrics.brierScore - 0.20) / 0.15);
         // (b) uncertainty shrink for an unvalidated case (compounds with (a))
         double valRatio = (double)caseBrierN / 20.0;   // 0..1
         shrink *= (0.5 + 0.5 * valRatio);              // [0.5,1.0]
      }

      if(shrink < 1.0)
      {
         g_currentProb.probTP1 = 50.0 + (g_currentProb.probTP1 - 50.0) * shrink;
         g_currentProb.probTP2 = 50.0 + (g_currentProb.probTP2 - 50.0) * shrink;
         g_currentProb.probTP3 = 50.0 + (g_currentProb.probTP3 - 50.0) * shrink;
         g_currentProb.probSL  = 100.0 - g_currentProb.probTP1;
      }
      if(InpShowProbExplain)
      {
         g_explainData.probAfterBrier = g_currentProb.probTP1;
         g_explainData.brierShrink = shrink;
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
      if(InpDebugMode && Period() >= TF_H4)
         Print("[EDGE-DBG TF=", Period(), "] barsAgo=", barsAgo,
               " avgTP1=", g_currentProb.avgBarsToTP1, " avgSL=", g_currentProb.avgBarsToSL,
               " tw=", DoubleToString(tw,3), " wB1=", DoubleToString(wB1,3),
               " t1tw=", DoubleToString(t1_tw,2), " t2tw=", DoubleToString(t2_tw,2),
               " t3t=", t3_t, " t3b1=", DoubleToString(t3_b1,1),
               " prelimNEff=", DoubleToString(prelimNEff,1), " minSmp=", minSamples, " probTP1=", g_currentProb.probTP1);
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

   if(InpShowProbExplain)
   {
      g_explainData.probFinal = g_currentProb.probTP1;
      g_explainData.survivalRatio = g_currentProb.survivalRatio;
   }

   CalculateKellyFraction();
}

#endif