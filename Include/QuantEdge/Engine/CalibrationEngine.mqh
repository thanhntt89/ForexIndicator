//+------------------------------------------------------------------+
//|                                        CalibrationEngine.mqh      |
//|                         QuantEdge - Brier Score Calibration     |
//|                                                                    |
//| Theory: Brier (1950) "Verification of Forecasts"                  |
//| Measures probability calibration: lower = better forecaster.      |
//|   0.00 = perfect calibration (impossible in practice)             |
//|   0.25 = coin flip (random, no skill)                             |
//|   0.33 = systematically wrong                                     |
//|                                                                    |
//| calibrationGap: mean(predicted) - mean(actual)                    |
//|   negative = overconfident (predicts higher than reality)         |
//|   positive = underconfident (predicts lower than reality)         |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_CALIBRATION_MQH
#define RSI_ADV_CALIBRATION_MQH

void UpdateBrierMetrics()
{
   double sumSqErr   = 0;
   double sumPred    = 0;
   double sumActual  = 0;
   int    matched    = 0;

   // Per-case accumulators (index by caseNumber 0-9)
   double caseSqErr[10];
   int    caseMatched[10];
   for(int c = 0; c < 10; c++) { caseSqErr[c] = 0; caseMatched[c] = 0; }

   for(int oi = 0; oi < g_outcomeCount; oi++)
   {
      if(g_outcomes[oi].outcome == 0) continue;

      datetime oTime = g_outcomes[oi].signalTime;
      bool     oIsBuy = g_outcomes[oi].isBuy;

      for(int si = g_signalCount - 1; si >= 0; si--)
      {
         if(g_signals[si].signalTime != oTime) continue;
         if(g_signals[si].isBuySignal != oIsBuy) continue;
         if(g_signals[si].predictedProb <= 0) break;

         double predicted = g_signals[si].predictedProb / 100.0;
         double actual    = (g_outcomes[oi].outcome > 0) ? 1.0 : 0.0;
         double sqErr     = (predicted - actual) * (predicted - actual);

         sumSqErr  += sqErr;
         sumPred   += predicted;
         sumActual += actual;
         matched++;

         int cn = g_signals[si].caseNumber;
         if(cn >= 0 && cn <= 9) { caseSqErr[cn] += sqErr; caseMatched[cn]++; }
         break;
      }
   }

   // Per-case Brier: score only meaningful with >=1 sample; consumer gates on samples>=20
   for(int c = 0; c < 10; c++)
   {
      g_brierCaseSamples[c] = caseMatched[c];
      g_brierCaseScore[c]   = (caseMatched[c] > 0) ? caseSqErr[c] / caseMatched[c] : 0.0;
   }

   g_brierMetrics.samples = matched;

   if(matched < 5)
   {
      g_brierMetrics.brierScore      = 0;
      g_brierMetrics.calibrationGap  = 0;
      g_brierMetrics.isReliable      = false;
      return;
   }

   g_brierMetrics.brierScore     = sumSqErr / matched;
   g_brierMetrics.calibrationGap = (sumPred / matched) - (sumActual / matched);
   g_brierMetrics.isReliable     = (g_brierMetrics.brierScore < 0.25 && matched >= 20);
}

#endif
