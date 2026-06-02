//+------------------------------------------------------------------+
//|                                                   Globals.mqh      |
//|                         RSI Advanced - Global Variables             |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_GLOBALS_MQH
#define RSI_ADV_GLOBALS_MQH

#include "Structs.mqh"

//+------------------------------------------------------------------+
//| Indicator Buffers (defined in main .mq4, referenced here)        |
//+------------------------------------------------------------------+
// extern double BufferGreen[];
// extern double BufferRed[];
// extern double BufferBBUpper[];
// extern double BufferBBLower[];
// extern double BufferOrange[];
// extern double BufferBuySignal[];
// extern double BufferSellSignal[];


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
int        g_signalCount      = 0;
int        g_activeSignalIndex= -1;

//+------------------------------------------------------------------+
//| Cooldown tracking                                                  |
//+------------------------------------------------------------------+
int g_lastBuyBar  = -9999;
int g_lastSellBar = -9999;

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
//| Panel state                                                        |
//+------------------------------------------------------------------+
int  g_panelPosX     = 20;
int  g_panelPosY     = 60;
bool g_panelDragging = false;
int  g_dragOffsetX   = 0;
int  g_dragOffsetY   = 0;

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
   }
   else
   {
      g_panelPosX = InpPanelDefaultX;
      g_panelPosY = InpPanelDefaultY;
   }
}

#endif