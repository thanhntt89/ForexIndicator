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
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN");
   }
   return(IntegerToString(Period()));
}

//+------------------------------------------------------------------+
//| Delete all objects with prefix                                     |
//+------------------------------------------------------------------+
#ifndef __MQL5__
void DeleteObjectsByPrefix(string prefix)
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(name);
   }
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
   if(tf <= PERIOD_H1)  return(20);
   if(tf <= PERIOD_H4)  return(15);
   return(10);
}

int GetMaxForwardBarsForTimeframe()
{
   int tf = Period();
   if(tf <= PERIOD_M1)  return(40);
   if(tf <= PERIOD_M5)  return(50);
   if(tf <= PERIOD_M15) return(60);
   if(tf <= PERIOD_M30) return(60);
   if(tf <= PERIOD_H1)  return(80);
   if(tf <= PERIOD_H4)  return(60);
   return(100);
}

int GetMaxLookbackForTimeframe()
{
   int tf = Period();
   if(tf <= PERIOD_M1)  return(300);
   if(tf <= PERIOD_M5)  return(250);
   if(tf <= PERIOD_M15) return(200);
   if(tf <= PERIOD_M30) return(200);
   if(tf <= PERIOD_H1)  return(150);
   if(tf <= PERIOD_H4)  return(120);
   return(100);
}

//+------------------------------------------------------------------+
//| Confidence text from sample size                                   |
//+------------------------------------------------------------------+
string GetConfidenceText(int sampleSize, double probability, color &outColor)
{
   double p = probability / 100.0;
   if(p <= 0) p = 0.01;
   if(p >= 1) p = 0.99;
   double me = 0;
   if(sampleSize > 0)
      me = 1.96 * MathSqrt(p * (1.0 - p) / (double)sampleSize) * 100.0;
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
   int tf = Period();
   int available = Bars - 100;
   int target = 0;

   if(tf <= PERIOD_M1)       target = 3000;
   else if(tf <= PERIOD_M5)  target = 4000;
   else if(tf <= PERIOD_M15) target = 5000;
   else if(tf <= PERIOD_M30) target = 5000;
   else if(tf <= PERIOD_H1)  target = 5000;
   else if(tf <= PERIOD_H4)  target = 3000;
   else                      target = 2000;

   return(MathMin(target, MathMax(available, 500)));
}

#endif