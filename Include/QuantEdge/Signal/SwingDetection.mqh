//+------------------------------------------------------------------+
//|                                            SwingDetection.mqh      |
//|                         QuantEdge - Swing High/Low Detection     |
//|                                                                    |
//| Theory: Fractal Market Hypothesis (Peters, 1994)                   |
//| - Market structure is fractal = same pattern at all scales         |
//| - Fixed depth works across all timeframes                          |
//| - Changing depth changes WHAT we detect, not HOW WELL              |
//|                                                                    |
//| Reference: Wilder (1978) RSI divergence uses "most recent swing"  |
//| without specifying timeframe-dependent depth                       |
//+------------------------------------------------------------------+
#ifndef QE_SWINGDETECTION_MQH
#define QE_SWINGDETECTION_MQH

void FindTwoSwingLows(const double &price[], const double &rsiData[],
                      int barIndex, int lookback, int depth,
                      int &swingNew, int &swingOld)
{
   swingNew = -1;
   swingOld = -1;
   int searchStart = MathMax(barIndex - lookback, depth);
   int searchEnd   = barIndex - depth;
   if(searchEnd < searchStart) return;

   for(int i = searchEnd; i >= searchStart; i--)
   {
      if(rsiData[i] == EMPTY_VALUE) continue;
      bool isSwing = true;
      for(int d = 1; d <= depth; d++)
      {
         int left  = i - d;
         int right = i + d;
         if(left < 0 || right > barIndex) { isSwing = false; break; }
         if(price[i] > price[left] || price[i] > price[right]) { isSwing = false; break; }
      }
      if(isSwing)
      {
         if(swingNew < 0) swingNew = i;
         else if(swingOld < 0) { swingOld = i; break; }
      }
   }
}

void FindTwoSwingHighs(const double &price[], const double &rsiData[],
                       int barIndex, int lookback, int depth,
                       int &swingNew, int &swingOld)
{
   swingNew = -1;
   swingOld = -1;
   int searchStart = MathMax(barIndex - lookback, depth);
   int searchEnd   = barIndex - depth;
   if(searchEnd < searchStart) return;

   for(int i = searchEnd; i >= searchStart; i--)
   {
      if(rsiData[i] == EMPTY_VALUE) continue;
      bool isSwing = true;
      for(int d = 1; d <= depth; d++)
      {
         int left  = i - d;
         int right = i + d;
         if(left < 0 || right > barIndex) { isSwing = false; break; }
         if(price[i] < price[left] || price[i] < price[right]) { isSwing = false; break; }
      }
      if(isSwing)
      {
         if(swingNew < 0) swingNew = i;
         else if(swingOld < 0) { swingOld = i; break; }
      }
   }
}

#endif