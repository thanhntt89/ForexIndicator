//+------------------------------------------------------------------+
//|                                                   Globals.mqh      |
//|                         RSI Advanced - Global Variables             |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_GLOBALS_MQH
#define RSI_ADV_GLOBALS_MQH

#include "Structs.mqh"

//+------------------------------------------------------------------+
//| Internal RSI data                                                  |
//+------------------------------------------------------------------+
double g_rawRSI[];

//+------------------------------------------------------------------+
//| State tracking                                                     |
//+------------------------------------------------------------------+
int      g_prevRatesTotal  = 0;
int      g_ratesTotal      = 0;
datetime g_lastAlertTime   = 0;

//+------------------------------------------------------------------+
//| Signal storage                                                     |
//+------------------------------------------------------------------+
SignalData g_signals[];
int        g_signalCount       = 0;
int        g_activeSignalIndex = -1;
bool       g_userSelectedSignal = false;  // User clicked an arrow → don't auto-override

//+------------------------------------------------------------------+
//| MTF data                                                           |
//+------------------------------------------------------------------+
MTFStatus       g_mtfData[6];
int             g_mtfCount = 0;

//+------------------------------------------------------------------+
//| MTF RAM Buffers — per-TF RSI history in RAM, no file I/O          |
//| Slot: 0=M5 1=M15 2=M30 3=H1 4=H4 5=D1                           |
//| barIdx 0 = most recent HTF bar, higher = older                    |
//+------------------------------------------------------------------+
#define MTF_RAM_BARS 250
double   g_mtfRamGreen  [6][MTF_RAM_BARS];
double   g_mtfRamRed    [6][MTF_RAM_BARS];
double   g_mtfRamOrange [6][MTF_RAM_BARS];
datetime g_mtfRamBarTime[6][MTF_RAM_BARS];
int      g_mtfRamCount  [6];
datetime g_mtfRamLastTime[6];
bool     g_mtfRamReady  [6];

//+------------------------------------------------------------------+
//| Probability data                                                   |
//+------------------------------------------------------------------+
ProbabilityData g_currentProb;
double          g_cachedEdge = 0.51;
BrierMetrics    g_brierMetrics;
// Per-case Brier calibration (index by caseNumber 0-8). Lets the shrink isolate
// a single case's calibration instead of pooling all cases globally.
double          g_brierCaseScore[9];   // mean squared error per case (0 = no data)
int             g_brierCaseSamples[9]; // resolved outcomes matched per case

//+------------------------------------------------------------------+
//| Entry Zone data                                                    |
//+------------------------------------------------------------------+
EntryZone g_entryZones[5];
int       g_validZoneCount       = 0;
int       g_recommendedZoneCount = 0;
bool      g_forceZoneRedraw      = false;

//+------------------------------------------------------------------+
//| Panel state                                                        |
//+------------------------------------------------------------------+
int  g_panelPosX     = 20;
int  g_panelPosY     = 60;
bool g_panelDragging = false;
int  g_dragOffsetX   = 0;
int  g_dragOffsetY   = 0;

bool g_panelUserMoved = false;   // User đã drag panel → don't auto-adjust

//+------------------------------------------------------------------+
//| Panel position persistence                                         |
//+------------------------------------------------------------------+
string PanelGVName_X() { return("RSIAdv_PanelX_" + Symbol()); }
string PanelGVName_Y() { return("RSIAdv_PanelY_" + Symbol()); }

void SavePanelPosition()
{
   GlobalVariableSet(PanelGVName_X(), (double)g_panelPosX);
   GlobalVariableSet(PanelGVName_Y(), (double)g_panelPosY);
}

void LoadPanelPosition()
{
   if(GlobalVariableCheck(PanelGVName_X()) && GlobalVariableCheck(PanelGVName_Y()))
   {
      g_panelPosX = (int)GlobalVariableGet(PanelGVName_X());
      g_panelPosY = (int)GlobalVariableGet(PanelGVName_Y());
      if(g_panelPosX < 0 || g_panelPosX > 2000) g_panelPosX = InpPanelDefaultX;
      if(g_panelPosY < 0 || g_panelPosY > 2000) g_panelPosY = InpPanelDefaultY;
      g_panelUserMoved = true;  // ← THÊM: đã có saved position = user đã move trước đó
   }
   else
   {
      g_panelPosX = InpPanelDefaultX;
      g_panelPosY = InpPanelDefaultY;
      g_panelUserMoved = false;
   }
}

//+------------------------------------------------------------------+
//| Signal storage functions                                           |
//+------------------------------------------------------------------+
void StoreSignal(datetime t, int barIdx, int caseNum, bool isBuy,
                 double entry, double sl, double tp1, double tp2, double tp3,
                 double atr, double angleZ = 0.0,
                 double spread = 0.0, int sessBlock = -1, double rsiVal = 0.0)
{
   g_signalCount++;
   ArrayResize(g_signals, g_signalCount, 128);
   int idx = g_signalCount - 1;
   g_signals[idx].signalTime    = t;
   // [ISSUE #4 FIX] Compute and store UTC-normalized time at signal creation.
   // NormalizeCandleToUTC converts broker local time → UTC → snaps to standard
   // TF boundary. Stored once here so all downstream consumers (GetSessionBlock,
   // ScanStoredSignalsBoth) use consistent UTC time without re-converting each call.
   g_signals[idx].signalTimeUTC = NormalizeCandleToUTC(t, Period());
   g_signals[idx].barIndex      = barIdx;
   g_signals[idx].caseNumber    = caseNum;
   g_signals[idx].isBuySignal   = isBuy;
   g_signals[idx].entryPrice    = entry;
   g_signals[idx].stopLoss      = sl;
   g_signals[idx].takeProfit1   = tp1;
   g_signals[idx].takeProfit2   = tp2;
   g_signals[idx].takeProfit3   = tp3;
   g_signals[idx].atrValue      = atr;
   g_signals[idx].angleStrength = angleZ;
   g_signals[idx].rsiPeriod     = InpRSIPeriod;
   g_signals[idx].simCachedTP       = 99;
   g_signals[idx].simCachedBTR      = 0;
   g_signals[idx].edgeCachedOutcome = 99;
   // [S2/S3] Context fields
   g_signals[idx].spreadAtSignal = spread;
   g_signals[idx].sessionBlock   = (sessBlock >= 0) ? sessBlock : GetSessionBlock(t);
   g_signals[idx].rsiAtSignal    = rsiVal;
   g_signals[idx].predictedProb  = 0;
}

int FindSignalByArrowName(string arrowName)
{
   string parts[];
   int cnt = StringSplit(arrowName, '_', parts);
   if(cnt < 5) return(-1);
   bool isBuy = (parts[2] == "BUY");
   int caseNum = (int)StringToInteger(parts[3]);
   datetime sigTime = (datetime)StringToInteger(parts[4]);
   for(int i = g_signalCount - 1; i >= 0; i--)
      if(g_signals[i].signalTime == sigTime &&
         g_signals[i].caseNumber == caseNum &&
         g_signals[i].isBuySignal == isBuy)
         return(i);
   return(-1);
}


//+------------------------------------------------------------------+
//| V11: Multi-Source + Walk-Forward data                               |
//+------------------------------------------------------------------+
IntermarketData   g_intermarket;
SessionStats      g_sessionStats;
WalkForwardData   g_walkForward;
RollingPerformance g_rollingPerf;
SpreadRegime      g_spreadRegime;
VolRegimeData     g_volRegime;
MarketStateData   g_marketState;
PortfolioRisk     g_portfolioRisk;

// [GMT-FIX-0] GMT normalization state
bool   g_gmtNormActive      = false;   // true when H4 normalization is active
int    g_gmtBrokerOffset    = 0;       // cached broker GMT offset for display
bool   g_gmtDataQualityWarn = false;   // true when Bayesian/Session guards fired
string g_gmtWarnReason      = "";      // reason text for data quality warning
bool   g_normRecalcDone     = false;   // true after first fullRecalc with normalized RSI ready
bool   g_gmtMTFNormNeeded  = false;   // true when offset != 0 — MTF H4/D1 slots use normalized RSI

//--- Signal outcome tracking for rolling performance
struct SignalOutcome
{
   datetime signalTime;
   int      caseNumber;
   bool     isBuy;
   int      sessionBlock;   // 0=Asian, 1=London, 2=Overlap, 3=LateNY
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   int      outcome;        // 1=TP1 hit, -1=SL hit, -2=Reversal, 0=pending
   datetime outcomeTime;
   double   mfe;            // Max Favorable Excursion from entry price
   double   mae;            // Max Adverse Excursion from entry price
   bool     loggedToFile;  // Prevent duplicate outcome logging
};

SignalOutcome g_outcomes[];
int           g_outcomeCount = 0;

//+------------------------------------------------------------------+
//| Active signal TP hit tracking (locked once touched)                |
//+------------------------------------------------------------------+
bool     g_tpHit[3]     = {false, false, false};  // TP1, TP2, TP3
datetime g_tpHitTime[3] = {0, 0, 0};
int      g_tpTrackingSigIndex = -1;                // reset when signal changes

void ResetTPTracking(int newSigIndex)
{
   g_tpTrackingSigIndex = newSigIndex;
   for(int i = 0; i < 3; i++) { g_tpHit[i] = false; g_tpHitTime[i] = 0; }
}

void UpdateTPHitStatus(int sigIdx)
{
   if(sigIdx < 0 || sigIdx >= g_signalCount) return;
   if(sigIdx != g_tpTrackingSigIndex) ResetTPTracking(sigIdx);

   SignalData sig = g_signals[sigIdx];
   double curPrice = (sig.isBuySignal)
      ? MarketInfo(Symbol(), MODE_BID)
      : MarketInfo(Symbol(), MODE_ASK);

   if(sig.isBuySignal)
   {
      if(!g_tpHit[0] && curPrice >= sig.takeProfit1) { g_tpHit[0] = true; g_tpHitTime[0] = TimeCurrent(); }
      if(!g_tpHit[1] && curPrice >= sig.takeProfit2) { g_tpHit[1] = true; g_tpHitTime[1] = TimeCurrent(); }
      if(!g_tpHit[2] && curPrice >= sig.takeProfit3) { g_tpHit[2] = true; g_tpHitTime[2] = TimeCurrent(); }
   }
   else
   {
      if(!g_tpHit[0] && curPrice <= sig.takeProfit1) { g_tpHit[0] = true; g_tpHitTime[0] = TimeCurrent(); }
      if(!g_tpHit[1] && curPrice <= sig.takeProfit2) { g_tpHit[1] = true; g_tpHitTime[1] = TimeCurrent(); }
      if(!g_tpHit[2] && curPrice <= sig.takeProfit3) { g_tpHit[2] = true; g_tpHitTime[2] = TimeCurrent(); }
   }
}

//+------------------------------------------------------------------+
//| TF Auto-Config computed globals                                    |
//| Set by ApplyTFAutoConfig() in TFConfig.mqh.                       |
//| When InpAutoTFConfig=false these mirror the manual input values.  |
//+------------------------------------------------------------------+
double g_cfgSLRatio        = 2.0;
double g_cfgTPRatio        = 4.0;
double g_cfgTP2Mult        = 1.5;
double g_cfgTP3Mult        = 2.0;
int    g_cfgSLTPMethod     = 2;   // SLTP_HYBRID
int    g_cfgSLSwingLB      = 20;
double g_cfgMinScore       = 40.0;
int    g_cfgCooldownBars   = 5;
int    g_cfgMinMTFAgree    = 40;
double g_cfgRiskPct        = 1.0;
int    g_cfgZoneCount      = 3;
int    g_cfgPriceDistLB    = 50;
bool   g_cfgCaseEnabled[9];  // index 0-8 → Case 0-8 (Case 8 = Basic Crossover)

#endif