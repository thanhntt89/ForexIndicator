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
datetime g_lastAlertTime   = 0;

//+------------------------------------------------------------------+
//| Signal storage                                                     |
//+------------------------------------------------------------------+
SignalData g_signals[];
int        g_signalCount       = 0;
int        g_activeSignalIndex = -1;

//+------------------------------------------------------------------+
//| MTF data                                                           |
//+------------------------------------------------------------------+
MTFStatus       g_mtfData[5];
int             g_mtfCount = 0;

//+------------------------------------------------------------------+
//| Probability data                                                   |
//+------------------------------------------------------------------+
ProbabilityData g_currentProb;

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
                 double entry, double sl, double tp1, double tp2, double tp3, double atr)
{
   g_signalCount++;
   ArrayResize(g_signals, g_signalCount);
   int idx = g_signalCount - 1;
   g_signals[idx].signalTime  = t;
   g_signals[idx].barIndex    = barIdx;
   g_signals[idx].caseNumber  = caseNum;
   g_signals[idx].isBuySignal = isBuy;
   g_signals[idx].entryPrice  = entry;
   g_signals[idx].stopLoss    = sl;
   g_signals[idx].takeProfit1 = tp1;
   g_signals[idx].takeProfit2 = tp2;
   g_signals[idx].takeProfit3 = tp3;
   g_signals[idx].atrValue    = atr;
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
   int      outcome;        // 1=TP1 hit, -1=SL hit, 0=pending
   datetime outcomeTime;
};

SignalOutcome g_outcomes[];
int           g_outcomeCount = 0;


#endif