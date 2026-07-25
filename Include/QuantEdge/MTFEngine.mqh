//+------------------------------------------------------------------+
//|                                               MTFEngine.mqh        |
//|                         RSI Advanced - Multi-Timeframe Engine       |
//|                                                                    |
//| Architecture: RAM buffer system                                    |
//|   g_mtfRamGreen/Red/Orange[slot][barIdx]  — 250 bars per TF       |
//|   barIdx 0 = most recent HTF bar (mirror of MT4 shift=0)          |
//|   Buffers built once on fullRecalc, updated O(BBPeriod) per       |
//|   new HTF bar. Zero iRSI() calls per tick on same HTF bar.         |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_MTFENGINE_MQH
#define RSI_ADV_MTFENGINE_MQH

#include "Config.mqh"
#include "Structs.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
//| Slot helpers — inline lookup tables                               |
//+------------------------------------------------------------------+
int MTFSlotTF(int slot)
{
   if(slot == 0) return(TF_M5);
   if(slot == 1) return(TF_M15);
   if(slot == 2) return(TF_M30);
   if(slot == 3) return(TF_H1);
   if(slot == 4) return(TF_H4);
   if(slot == 5) return(TF_D1);
   return(0);
}

bool MTFSlotEnabled(int slot)
{
   if(slot == 0) return(InpMTF_M5);
   if(slot == 1) return(InpMTF_M15);
   if(slot == 2) return(InpMTF_M30);
   if(slot == 3) return(InpMTF_H1);
   if(slot == 4) return(InpMTF_H4);
   if(slot == 5) return(InpMTF_D1);
   return(false);
}

string MTFSlotName(int slot)
{
   if(slot == 0) return("M5");
   if(slot == 1) return("M15");
   if(slot == 2) return("M30");
   if(slot == 3) return("H1");
   if(slot == 4) return("H4");
   if(slot == 5) return("D1");
   return("??");
}

//+------------------------------------------------------------------+
//| Build RAM buffer for one slot from historical iRSI data            |
//| Fetches rawRSI[] once, computes all 3 SMAs in one pass            |
//| Called once per fullRecalc (or lazy-init on first tick)            |
//+------------------------------------------------------------------+
void MTF_BuildRamBuffer(int slot, int tf)
{
   g_mtfRamReady[slot]    = false;
   g_mtfRamCount[slot]    = 0;
   g_mtfRamLastTime[slot] = 0;

   if(tf <= Period()) return;

   int htfBars = iBars(NULL, tf);
   int minNeed = InpBBPeriod + InpRSIPeriod + 10;
   if(htfBars < minNeed) return;

   // [PERF] Build only a few recent bars (see MTF_INIT_BUILD_BARS): GetMTFTrend reads only
   // indices [0] and [2], so loading all MTF_RAM_BARS was ~7x wasted HTF iRSI reads and
   // stalled every TF switch / attach for seconds. The buffer still grows over the session.
   int barsToLoad = MathMin(MTF_INIT_BUILD_BARS, htfBars - minNeed);
   if(barsToLoad <= 0) return;

   // Fetch raw RSI array once — shift 0=most recent, higher=older
   // Need barsToLoad + (BBPeriod-1) for SMA of oldest bar
   int rawCount = barsToLoad + InpBBPeriod;
   double rawRSI[];
   ArrayResize(rawRSI, rawCount);

   bool useNorm = (g_gmtMTFNormNeeded && (slot == 4 || slot == 5));
   for(int b = 0; b < rawCount; b++)
   {
      double v = EMPTY_VALUE;
      if(useNorm) v = GetNormMTF_RSI(slot, tf, b);
      if(v == EMPTY_VALUE) v = iRSI(NULL, tf, InpRSIPeriod, InpPrice, b);
      rawRSI[b] = (v <= 0 || v == EMPTY_VALUE) ? 50.0 : v;
   }

   // Compute 3 SMAs for each bar, store with bar 0 = most recent
   for(int s = 0; s < barsToLoad; s++)
   {
      double gv = 0, rv = 0, ov = 0;
      for(int j = 0; j < InpFastMAPeriod;   j++) gv += rawRSI[s + j];
      for(int j = 0; j < InpSignalMAPeriod; j++) rv += rawRSI[s + j];
      for(int j = 0; j < InpBBPeriod;       j++) ov += rawRSI[s + j];
      g_mtfRamGreen  [slot][s] = gv / InpFastMAPeriod;
      g_mtfRamRed    [slot][s] = rv / InpSignalMAPeriod;
      g_mtfRamOrange [slot][s] = ov / InpBBPeriod;
      g_mtfRamBarTime[slot][s] = iTime(NULL, tf, s);
   }

   g_mtfRamCount[slot]    = barsToLoad;
   g_mtfRamLastTime[slot] = g_mtfRamBarTime[slot][0];
   g_mtfRamReady[slot]    = true;
}

//+------------------------------------------------------------------+
//| Update one slot when a new HTF bar has opened                      |
//| Shift existing data right, compute new bar at index 0             |
//| Cost: O(count) shift + InpBBPeriod+1 iRSI calls                  |
//+------------------------------------------------------------------+
void MTF_UpdateRamBuffer(int slot, int tf)
{
   if(!g_mtfRamReady[slot]) return;

   datetime newBarTime = iTime(NULL, tf, 0);
   if(newBarTime == g_mtfRamLastTime[slot]) return;  // Same HTF bar, no update needed

   // Shift existing bars right by 1 (drop oldest if buffer full)
   int n = MathMin(g_mtfRamCount[slot], MTF_RAM_BARS - 1);
   for(int i = n; i > 0; i--)
   {
      g_mtfRamGreen  [slot][i] = g_mtfRamGreen  [slot][i-1];
      g_mtfRamRed    [slot][i] = g_mtfRamRed    [slot][i-1];
      g_mtfRamOrange [slot][i] = g_mtfRamOrange [slot][i-1];
      g_mtfRamBarTime[slot][i] = g_mtfRamBarTime[slot][i-1];
   }
   if(g_mtfRamCount[slot] < MTF_RAM_BARS) g_mtfRamCount[slot]++;

   // Fetch raw RSI for new bar at shift=0, need BBPeriod bars of history
   int rawNeeded = InpBBPeriod + 1;
   double rawRSI[];
   ArrayResize(rawRSI, rawNeeded);
   bool useNorm = (g_gmtMTFNormNeeded && (slot == 4 || slot == 5));
   for(int j = 0; j < rawNeeded; j++)
   {
      double v = EMPTY_VALUE;
      if(useNorm) v = GetNormMTF_RSI(slot, tf, j);
      if(v == EMPTY_VALUE) v = iRSI(NULL, tf, InpRSIPeriod, InpPrice, j);
      rawRSI[j] = (v <= 0 || v == EMPTY_VALUE) ? 50.0 : v;
   }

   double gv = 0, rv = 0, ov = 0;
   for(int j = 0; j < InpFastMAPeriod;   j++) gv += rawRSI[j];
   for(int j = 0; j < InpSignalMAPeriod; j++) rv += rawRSI[j];
   for(int j = 0; j < InpBBPeriod;       j++) ov += rawRSI[j];

   g_mtfRamGreen  [slot][0] = gv / InpFastMAPeriod;
   g_mtfRamRed    [slot][0] = rv / InpSignalMAPeriod;
   g_mtfRamOrange [slot][0] = ov / InpBBPeriod;
   g_mtfRamBarTime[slot][0] = newBarTime;
   g_mtfRamLastTime[slot]   = newBarTime;
}

//+------------------------------------------------------------------+
//| Initialize all enabled MTF RAM buffers                             |
//| Call from fullRecalc block in OnCalculate                          |
//+------------------------------------------------------------------+
void MTF_InitRamBuffers()
{
   for(int s = 0; s < 6; s++)
   {
      g_mtfRamReady[s]    = false;
      g_mtfRamCount[s]    = 0;
      g_mtfRamLastTime[s] = 0;
      if(MTFSlotEnabled(s)) MTF_BuildRamBuffer(s, MTFSlotTF(s));
   }
}

//+------------------------------------------------------------------+
//| Update all enabled RAM buffers — call once per tick before        |
//| CheckAndAddMTF. Only acts when new HTF bar has formed.            |
//| Falls back to lazy build if slot not yet initialized.             |
//+------------------------------------------------------------------+
void MTF_UpdateAllRamBuffers()
{
   for(int s = 0; s < 6; s++)
   {
      if(!MTFSlotEnabled(s)) continue;
      int tf = MTFSlotTF(s);
      if(tf <= Period()) continue;
      if(!g_mtfRamReady[s])
      {
         MTF_BuildRamBuffer(s, tf);  // Lazy init if missed fullRecalc
         continue;
      }
      MTF_UpdateRamBuffer(s, tf);
   }
}

//+------------------------------------------------------------------+
//| Get trend from RAM buffer slot                                     |
//| greenDelta uses bar[2] vs bar[0] (same 2-bar lookback as before)  |
//+------------------------------------------------------------------+
int GetMTFTrend(int slot)
{
   if(!g_mtfRamReady[slot] || g_mtfRamCount[slot] < 1) return(0);
   double gv = g_mtfRamGreen[slot][0];
   double rv = g_mtfRamRed  [slot][0];
   if(gv == 0 || rv == 0) return(0);
   double greenOld  = (g_mtfRamCount[slot] >= 3) ? g_mtfRamGreen[slot][2] : gv;
   double greenDelta = gv - greenOld;
   if(gv > rv && greenDelta >= InpAngleThreshold * 0.5) return(1);
   if(gv < rv && greenDelta <= -InpAngleThreshold * 0.5) return(-1);
   return(0);
}

//+------------------------------------------------------------------+
string GetMTFStatusText(int trend, double greenVal, double redVal, double orangeVal)
{
   if(trend == 1)
   {
      if(greenVal > 68) return("BULL (Overbought)");
      if(greenVal > 50) return("BULL (Strong)");
      return("BULL (Weak)");
   }
   if(trend == -1)
   {
      if(greenVal < 32) return("BEAR (Oversold)");
      if(greenVal < 50) return("BEAR (Strong)");
      return("BEAR (Weak)");
   }
   if(MathAbs(greenVal - redVal) < 3) return("NEUTRAL (Sideway)");
   return("NEUTRAL");
}

//+------------------------------------------------------------------+
//| Add one MTF slot to g_mtfData[] — reads entirely from RAM buffer  |
//| Zero iRSI() calls; cost = O(1) array reads                       |
//+------------------------------------------------------------------+
void CheckAndAddMTF(int slot, string tfName, bool enabled, int currentTF)
{
   int tf = MTFSlotTF(slot);
   if(!enabled || tf <= currentTF || g_mtfCount >= 6) return;
   if(!g_mtfRamReady[slot] || g_mtfRamCount[slot] < 1) return;

   int idx = g_mtfCount;
   double gv = g_mtfRamGreen  [slot][0];
   double rv = g_mtfRamRed    [slot][0];
   double ov = g_mtfRamOrange [slot][0];
   if(gv == 0 && rv == 0) return;

   g_mtfData[idx].timeframe   = tf;
   g_mtfData[idx].tfName      = tfName;
   g_mtfData[idx].greenValue  = gv;
   g_mtfData[idx].redValue    = rv;
   g_mtfData[idx].orangeValue = ov;
   g_mtfData[idx].trend       = GetMTFTrend(slot);
   g_mtfData[idx].statusText  = GetMTFStatusText(g_mtfData[idx].trend, gv, rv, ov);
   g_mtfCount++;
}

//+------------------------------------------------------------------+
//| Refresh all MTF data for current tick                              |
//| 1. Update RAM buffers (only triggers on new HTF bar open)         |
//| 2. Populate g_mtfData[] from RAM (O(1) per slot, no iRSI)        |
//+------------------------------------------------------------------+
void RefreshMTFData()
{
   MTF_UpdateAllRamBuffers();

   g_mtfCount = 0;
   int currentTF = Period();
   CheckAndAddMTF(0, "M5",  InpMTF_M5,  currentTF);
   CheckAndAddMTF(1, "M15", InpMTF_M15, currentTF);
   CheckAndAddMTF(2, "M30", InpMTF_M30, currentTF);
   CheckAndAddMTF(3, "H1",  InpMTF_H1,  currentTF);
   CheckAndAddMTF(4, "H4",  InpMTF_H4,  currentTF);
   CheckAndAddMTF(5, "D1",  InpMTF_D1,  currentTF);
}

//+------------------------------------------------------------------+
int CalculateMTFAgreement()
{
   if(g_mtfCount == 0) return(0);
   double bullW = 0, bearW = 0, totalW = 0;
   for(int i = 0; i < g_mtfCount; i++)
   {
      double w = 1.0;
      if(g_mtfData[i].timeframe >= TF_H4)  w = 3.0;
      else if(g_mtfData[i].timeframe >= TF_H1)  w = 2.0;
      else if(g_mtfData[i].timeframe >= TF_M30) w = 1.5;
      if(g_mtfData[i].trend ==  1) bullW += w;
      if(g_mtfData[i].trend == -1) bearW += w;
      totalW += w;
   }
   if(totalW == 0) return(0);
   return((int)MathRound(((bullW - bearW) / totalW) * 100.0));
}

//+------------------------------------------------------------------+
int GetMTFContextScore(bool isBuySignal)
{
   if(!InpShowMTF || g_mtfCount == 0) return(0);
   double score = 0, totalWeight = 0;
   for(int i = 0; i < g_mtfCount; i++)
   {
      double w = 1.0;
      if(g_mtfData[i].timeframe >= TF_H4)  w = 3.0;
      else if(g_mtfData[i].timeframe >= TF_H1)  w = 2.0;
      else if(g_mtfData[i].timeframe >= TF_M30) w = 1.5;
      else if(g_mtfData[i].timeframe >= TF_M15) w = 1.0;
      double alignment = isBuySignal ? (double)g_mtfData[i].trend : -(double)g_mtfData[i].trend;
      double strength  = MathAbs(g_mtfData[i].greenValue - 50.0) / 50.0;
      alignment *= (1.0 + strength);
      score       += alignment * w;
      totalWeight += w;
   }
   if(totalWeight == 0) return(0);
   return(MathMax(-100, MathMin(100, (int)MathRound((score / totalWeight) * 100.0))));
}

#endif
