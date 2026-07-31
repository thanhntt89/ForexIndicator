//+------------------------------------------------------------------+
//| XGBIntegration.mqh — XGBoost ↔ Bayesian ensemble logic           |
//|                                                                    |
//| Three modes via InpProbMode:                                       |
//|   CALIBRATION — existing Bayesian pipeline only (default)          |
//|   XGBOOST     — XGBoost model only                                 |
//|   ENSEMBLE    — Brier-weighted average of both                     |
//|                                                                    |
//| Brier-weighted combination: w = 1/max(brier, 0.10)^2              |
//| Model with lower Brier (better calibration) gets higher weight.   |
//| Auto-fallback to CALIBRATION when XGB Brier not ready.            |
//+------------------------------------------------------------------+
#ifndef QE_XGBINTEGRATION_MQH
#define QE_XGBINTEGRATION_MQH

#include "XGBModel.mqh"

//+------------------------------------------------------------------+
//| XGBGetPrediction — collect features and call XGBPredict()         |
//+------------------------------------------------------------------+
double XGBGetPrediction(const SignalData &sig,
                        const double &orange[], const double &bbUp[], const double &bbLo[])
{
   double slDist   = MathAbs(sig.entryPrice - sig.stopLoss);
   double tp1Dist  = MathAbs(sig.takeProfit1 - sig.entryPrice);
   double atrSafe  = MathMax(sig.atrValue, 0.0001);
   double slATR    = slDist / atrSafe;
   double tp1ATR   = tp1Dist / atrSafe;
   double rrRatio  = (slDist > 0) ? tp1Dist / slDist : 0;

   MqlDateTime sigDt;
   TimeToStruct(sig.signalTime, sigDt);

   return XGBPredict(
      sig.rsiAtSignal,
      sig.angleStrength,
      g_volRegime.atrRatio,
      slATR,
      tp1ATR,
      rrRatio,
      sig.spreadAtSignal / MarketInfo(Symbol(), MODE_POINT),
      SL_GetTimeInSessionMin(sig.signalTime, sig.sessionBlock),
      sig.caseNumber,
      sig.isBuySignal ? 1 : 0,
      sig.sessionBlock,
      sigDt.hour,
      sigDt.day_of_week,
      DetectMarketRegime(Bars - 1, orange, bbUp, bbLo),
      (g_mtfCount > 0) ? (int)(100.0 * g_intermarket.correlationScore) : 50,
      g_spreadRegime.spreadRatio,
      g_walkForward.isRobust ? 1 : 0,
      SL_GetMTFTrendForTF(TF_H4),
      SL_GetMTFTrendForTF(TF_H1)
   );
}

//+------------------------------------------------------------------+
//| CombineXGBWithBayesian — Brier-weighted model averaging           |
//|                                                                    |
//| w = 1 / max(brier, 0.10)^2                                       |
//| Floor 0.10 prevents either model from permanent domination.       |
//| Returns combined probability (0-100).                              |
//+------------------------------------------------------------------+
double CombineXGBWithBayesian(double probBayesian, double probXGB,
                               double &outWBayes, double &outWXGB)
{
   double brierBayes = MathMax(g_brierMetrics.brierScore, 0.10);
   double brierXGB   = MathMax(g_xgbBrierScore, 0.10);

   double wBayes = 1.0 / (brierBayes * brierBayes);
   double wXGB   = 1.0 / (brierXGB * brierXGB);
   double totalW = wBayes + wXGB;

   outWBayes = wBayes / totalW;
   outWXGB   = wXGB / totalW;

   return (probBayesian * wBayes + probXGB * wXGB) / totalW;
}

//+------------------------------------------------------------------+
//| XGBIsReady — can XGBoost contribute to decisions?                 |
//| Requires: trained model + enough Brier samples + Brier < 0.25    |
//+------------------------------------------------------------------+
bool XGBIsReady()
{
   if(!g_xgbLoaded) return false;
   if(XGBFindModel(Symbol(), Period()) < 0) return false;
   if(g_xgbBrierSamples < 20) return false;
   if(g_xgbBrierScore > 0.25) return false;
   return true;
}

//+------------------------------------------------------------------+
//| XGBModeLabel — human-readable string for current effective mode   |
//+------------------------------------------------------------------+
string XGBModeLabel()
{
   if(InpProbMode == PROB_CALIBRATION)
      return "CALIBRATION";
   if(InpProbMode == PROB_XGBOOST)
   {
      if(!XGBIsReady()) return "XGBOOST (fallback CAL)";
      return "XGBOOST";
   }
   // ENSEMBLE
   if(!XGBIsReady()) return "ENSEMBLE (fallback CAL)";
   return "ENSEMBLE";
}

//+------------------------------------------------------------------+
//| UpdateXGBBrierMetrics — track XGBoost prediction accuracy         |
//| Mirrors UpdateBrierMetrics() but uses xgbPredictedProb field.     |
//+------------------------------------------------------------------+
void UpdateXGBBrierMetrics()
{
   if(InpProbMode == PROB_CALIBRATION) return;

   double sumSqErr = 0;
   int    matched  = 0;

   for(int oi = 0; oi < g_outcomeCount; oi++)
   {
      if(g_outcomes[oi].outcome == 0) continue;

      datetime oTime  = g_outcomes[oi].signalTime;
      bool     oIsBuy = g_outcomes[oi].isBuy;

      for(int si = g_signalCount - 1; si >= 0; si--)
      {
         if(g_signals[si].signalTime != oTime) continue;
         if(g_signals[si].isBuySignal != oIsBuy) continue;
         if(g_signals[si].xgbPredictedProb <= 0) break;

         double predicted = g_signals[si].xgbPredictedProb / 100.0;
         double actual    = (g_outcomes[oi].outcome > 0) ? 1.0 : 0.0;
         sumSqErr += (predicted - actual) * (predicted - actual);
         matched++;
         break;
      }
   }

   g_xgbBrierSamples = matched;
   g_xgbBrierScore   = (matched >= 5) ? sumSqErr / matched : 0.25;
}

#endif
