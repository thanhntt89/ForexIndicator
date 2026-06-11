//+------------------------------------------------------------------+
//|                                                 MathUtils.mqh      |
//|                         RSI Advanced - Math Helper Functions        |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_MATHUTILS_MQH
#define RSI_ADV_MATHUTILS_MQH

//+------------------------------------------------------------------+
//| Simple Moving Average (non-series array)                           |
//+------------------------------------------------------------------+
double CalculateSMA(const double &source[], int barIndex, int period)
{
   if(barIndex < period - 1) return(EMPTY_VALUE);
   double sum = 0.0;
   for(int j = 0; j < period; j++)
   {
      int idx = barIndex - j;
      if(idx < 0 || source[idx] == EMPTY_VALUE) return(EMPTY_VALUE);
      sum += source[idx];
   }
   return(sum / (double)period);
}

//+------------------------------------------------------------------+
//| Standard Deviation (non-series array)                              |
//+------------------------------------------------------------------+
double CalculateStdDev(const double &source[], int barIndex, int period, double mean)
{
   if(barIndex < period - 1) return(EMPTY_VALUE);
   double sumSq = 0.0;
   for(int j = 0; j < period; j++)
   {
      int idx = barIndex - j;
      if(idx < 0 || source[idx] == EMPTY_VALUE) return(EMPTY_VALUE);
      double diff = source[idx] - mean;
      sumSq += diff * diff;
   }
   return(MathSqrt(sumSq / (double)period));
}

//+------------------------------------------------------------------+
//| Period to string                                                   |
//+------------------------------------------------------------------+
string GetTimeframeString()
{
   switch(Period())
   {
      case TF_M1:  return("M1");
      case TF_M5:  return("M5");
      case TF_M15: return("M15");
      case TF_M30: return("M30");
      case TF_H1:  return("H1");
      case TF_H4:  return("H4");
      case TF_D1:  return("D1");
      case TF_W1:  return("W1");
      case TF_MN1: return("MN");
   }
   return(IntegerToString(Period()));
}

//+------------------------------------------------------------------+
//| Delete all objects with prefix                                     |
//+------------------------------------------------------------------+
#ifndef __MQL5__
void DeleteObjectsByPrefix(string prefix)
{
   ObjectsDeleteAll(0, prefix);
}
#endif

//+------------------------------------------------------------------+
//| Get minimum bars required                                          |
//+------------------------------------------------------------------+
int GetMinBarsRequired()
{
   return(InpRSIPeriod + InpBBPeriod + InpSwingLookback + 10);
}

//+------------------------------------------------------------------+
//| Probability bar visualization                                      |
//+------------------------------------------------------------------+
string ProbBar(double percent)
{
   int filled = (int)MathRound(percent / 10.0);
   if(filled < 0) filled = 0;
   if(filled > 10) filled = 10;
   string bar = "[";
   for(int i = 0; i < 10; i++)
      bar += (i < filled) ? "|" : ".";
   bar += "]";
   return(bar);
}

//+------------------------------------------------------------------+
//| Dynamic parameters by timeframe                                    |
//+------------------------------------------------------------------+
int GetMinSamplesForTimeframe()
{
   int tf = Period();
   if(tf <= PERIOD_M1)  return(50);
   if(tf <= PERIOD_M5)  return(40);
   if(tf <= PERIOD_M15) return(30);
   if(tf <= PERIOD_M30) return(25);
   if(tf <= TF_H1)  return(20);
   if(tf <= TF_H4)  return(15);
   return(10);
}

int GetMaxForwardBarsForTimeframe()
{
   int tf = Period();
   if(tf <= PERIOD_M1)  return(40);
   if(tf <= PERIOD_M5)  return(50);
   if(tf <= PERIOD_M15) return(60);
   if(tf <= PERIOD_M30) return(60);
   if(tf <= TF_H1)  return(80);
   if(tf <= TF_H4)  return(60);
   return(100);
}

int GetMaxLookbackForTimeframe()
{
   // [CROSS-BROKER-FIX] Fixed cap per TF — no Bars scaling.
   // Old: sqrt(available/5000)*baseCap → broker 65k bars got cap=300,
   // broker 30k got cap=288 → different sample sizes, different WR%.
   // New: fixed baseCap → both brokers collect same max samples.
   int tf = Period();
   if(tf <= PERIOD_M1)       return(300);
   if(tf <= PERIOD_M5)       return(250);
   if(tf <= PERIOD_M15)      return(200);
   if(tf <= PERIOD_M30)      return(200);
   if(tf <= TF_H1)           return(150);
   if(tf <= TF_H4)           return(120);
   return(100);
}

int GetEffectiveProbMaxBars()
{
   // [CROSS-BROKER-FIX] Time-based cap aligned with S7 hard prune maxDays.
   // Old: available*0.8 scaled with Bars → broker with 65k bars scanned 52k,
   // broker with 30k scanned 24k → completely different time periods.
   // New: fixed maxDays per TF → both brokers scan same calendar window.
   int maxDays = (Period() <= TF_M5) ? 60 : (Period() <= TF_H1) ? 180 : 365;
   int barsPerDay = 1440 / MathMax(Period(), 1);
   int timeBased = maxDays * barsPerDay;

   int available = Bars - GetMaxForwardBarsForTimeframe() - 50;
   if(available <= 0) return(InpProbMaxBars);

   return(MathMin(timeBased, MathMax(InpProbMaxBars, available)));
}

//+------------------------------------------------------------------+
//| Confidence text from sample size                                   |
//+------------------------------------------------------------------+
string GetConfidenceText(int sampleSize, double probability, color &outColor)
{
   int minReq = GetMinSamplesForTimeframe();
   if(sampleSize <= 0)
   {
      outColor = clrRed;
      return("NO DATA (theoretical only)");
   }
   if(sampleSize < minReq)
   {
      outColor = clrOrange;
      return("LOW DATA (n<" + IntegerToString(minReq) + ")");
   }
   double p = probability / 100.0;
   if(p <= 0) p = 0.01;
   if(p >= 1) p = 0.99;
   double me = 1.96 * MathSqrt(p * (1.0 - p) / (double)sampleSize) * 100.0;
   string conf;
   if(me <= 8)       { conf = "HIGH";      outColor = clrLime;   }
   else if(me <= 15) { conf = "MODERATE";   outColor = clrYellow; }
   else if(me <= 25) { conf = "LOW";        outColor = clrOrange; }
   else              { conf = "VERY LOW";   outColor = clrRed;    }
   conf += " (+-" + DoubleToString(me, 1) + "%)";
   return(conf);
}

//+------------------------------------------------------------------+
//| Chart pixel to time conversion                                     |
//+------------------------------------------------------------------+
datetime GetTimeFromBarPlusPixels(int pixelsRight)
{
   datetime barTime = iTime(NULL, 0, 0);
   double barPrice = iClose(NULL, 0, 0);
   int barPixelX = 0, barPixelY = 0;
   if(!ChartTimePriceToXY(0, 0, barTime, barPrice, barPixelX, barPixelY))
      return(barTime + Period() * 60 * 5);
   int targetX = barPixelX + pixelsRight;
   int subWindow = 0;
   datetime resultTime = 0;
   double resultPrice = 0;
   if(ChartXYToTimePrice(0, targetX, barPixelY, subWindow, resultTime, resultPrice))
      return(resultTime);
   return(barTime + Period() * 60 * 5);
}

//+------------------------------------------------------------------+
//| Max scan bars for TP measurement by timeframe                      |
//| Uses ALL available bars for maximum statistical reliability        |
//+------------------------------------------------------------------+
int GetTPMeasurementBars()
{
   // [CROSS-BROKER-FIX] Time-based cap for TP measurement scan.
   // Old: target capped by available=Bars-100 → different brokers, different scan depth.
   // New: time-based cap aligned with S7 maxDays → same calendar window.
   int tf = Period();
   int maxDays = (tf <= TF_M5) ? 60 : (tf <= TF_H1) ? 180 : 365;
   int barsPerDay = 1440 / MathMax(tf, 1);
   int timeBased = maxDays * barsPerDay;

   int available = Bars - 100;
   int target = 0;

   if(tf <= PERIOD_M1)       target = 3000;
   else if(tf <= PERIOD_M5)  target = 4000;
   else if(tf <= PERIOD_M15) target = 5000;
   else if(tf <= PERIOD_M30) target = 5000;
   else if(tf <= TF_H1)      target = 5000;
   else if(tf <= TF_H4)      target = 3000;
   else                      target = 2000;

   target = MathMin(target, timeBased);
   return(MathMin(target, MathMax(available, 500)));
}

#endif