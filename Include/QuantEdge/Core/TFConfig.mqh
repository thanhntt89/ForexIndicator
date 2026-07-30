#ifndef RSI_ADV_TFCONFIG_MQH
#define RSI_ADV_TFCONFIG_MQH

#include "Config.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
//| TFConfig.mqh — Auto-adaptive configuration per timeframe          |
//|                                                                    |
//| When InpAutoTFConfig = true, all SL/TP/method/case/risk params    |
//| are overridden by the scalping intraday profile below.            |
//| When false, manual inputs are used as-is (original behavior).     |
//|                                                                    |
//| Profile target: XAUUSD intraday scalping, exit same session.      |
//| SL/TP values are multipliers of ATR — actual pips scale with ATR. |
//|                                                                    |
//| Timeframe groups:                                                  |
//|   M1        — ultra-fast scalp, Case 6/7 only, Overlap session    |
//|   M5        — fast scalp, Case 1/5/6/7                            |
//|   M15       — standard scalp, Case 1/4/5/6/7                     |
//|   M30       — short intraday, Case 1/2/4/5/6/7                   |
//|   H1        — intraday position, all cases                        |
//|   H4+       — context/direction only, conservative targets        |
//+------------------------------------------------------------------+

// Helper: return InpEnableCaseX for a given case index (manual mode)
bool _GetInputCase(int c)
{
   switch(c)
   {
      case 0: return(InpEnableCase0);
      case 1: return(InpEnableCase1);
      case 2: return(InpEnableCase2);
      case 3: return(InpEnableCase3);
      case 4: return(InpEnableCase4);
      case 5: return(InpEnableCase5);
      case 6: return(InpEnableCase6);
      case 7: return(InpEnableCase7);
      case 8: return(InpEnableCase8);
      case 9: return(InpEnableCase9);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Apply scalping profile to g_cfg* based on Period().               |
//| Call once in OnInit(). Period() is fixed per chart attachment.    |
//+------------------------------------------------------------------+
void ApplyTFAutoConfig()
{
   int tf = Period();

   // --- Always init case array first (all enabled by default) ---
   for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = true;

   if(!InpAutoTFConfig)
   {
      // Manual mode: mirror inputs into g_cfg* so getters are consistent
      g_cfgSLRatio      = InpSLRatio;
      g_cfgTPRatio      = InpTPRatio;
      g_cfgTP2Mult      = InpTP2Multiplier;
      g_cfgTP3Mult      = InpTP3Multiplier;
      g_cfgSLTPMethod   = (int)InpSLTPMethod;
      g_cfgSLSwingLB    = InpSLSwingLookback;
      g_cfgMinScore     = InpMinSignalScore;
      g_cfgCooldownBars = InpCooldownBars;
      g_cfgMinMTFAgree  = InpMinMTFAgreement;
      g_cfgRiskPct      = InpTotalRiskPercent;
      g_cfgZoneCount    = InpEntryZoneCount;
      g_cfgPriceDistLB  = InpPriceDistLookback;
      for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = _GetInputCase(c);
      return;
   }

   // ---------------------------------------------------------------
   // AUTO MODE — scalping intraday profile
   // ---------------------------------------------------------------

   if(tf <= TF_M1)
   {
      // M1: ultra-fast, 2 pip TP1, strict session filter
      g_cfgSLRatio      = 0.8;
      g_cfgTPRatio      = 1.0;
      g_cfgTP2Mult      = 2.0;
      g_cfgTP3Mult      = 3.5;
      g_cfgSLTPMethod   = 0;   // ATR only
      g_cfgSLSwingLB    = 8;
      g_cfgMinScore     = 55.0;
      g_cfgCooldownBars = 5;
      g_cfgMinMTFAgree  = 55;
      g_cfgRiskPct      = 0.3;
      g_cfgZoneCount    = 2;
      g_cfgPriceDistLB  = 30;
      // Cases: 6 and 7 only — fast breakout/continuation
      for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = false;
      g_cfgCaseEnabled[6] = true;
      g_cfgCaseEnabled[7] = true;
   }
   else if(tf <= TF_M5)
   {
      // M5: fast scalp batch-close (3 lots)
      // XAUUSD ATR(14)~$3: TP1~$2.1, TP2~$3.6, TP3~$6.3, SL~$3
      g_cfgSLRatio      = 1.0;
      g_cfgTPRatio      = 0.7;     // TP1 = ultra-quick (was 1.2)
      g_cfgTP2Mult      = 1.7;     // TP2 = 1.19 ATR (was 2.0 → 2.4 ATR)
      g_cfgTP3Mult      = 3.0;     // TP3 = 2.1 ATR (was 3.5 → 4.2 ATR)
      g_cfgSLTPMethod   = 0;   // ATR
      g_cfgSLSwingLB    = 10;
      g_cfgMinScore     = 55.0;    // Strict for noisy TF (was 52)
      g_cfgCooldownBars = 5;
      g_cfgMinMTFAgree  = 50;
      g_cfgRiskPct      = 0.3;     // Per lot (3 lots = 0.9% total)
      g_cfgZoneCount    = 2;
      g_cfgPriceDistLB  = 30;      // Tighter (was 40)
      // Cases: 1, 5, 6, 7
      for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = false;
      g_cfgCaseEnabled[1] = true;
      g_cfgCaseEnabled[5] = true;
      g_cfgCaseEnabled[6] = true;
      g_cfgCaseEnabled[7] = true;
   }
   else if(tf <= TF_M15)
   {
      // M15: scalping batch-close (3 lots: TP1 quick, TP2 swing, TP3 runner)
      // XAUUSD ATR(14)~$8: TP1~$6.4, TP2~$12, TP3~$20, SL~$8
      g_cfgSLRatio      = 1.0;
      g_cfgTPRatio      = 0.8;     // TP1 = quick scalp target (was 1.5)
      g_cfgTP2Mult      = 1.5;     // TP2 = 1.2 ATR (was 2.0 → 3.0 ATR)
      g_cfgTP3Mult      = 2.5;     // TP3 = 2.0 ATR (was 3.5 → 5.25 ATR)
      g_cfgSLTPMethod   = 0;   // ATR
      g_cfgSLSwingLB    = 12;
      g_cfgMinScore     = 50.0;    // Stricter for faster trades (was 48)
      g_cfgCooldownBars = 3;       // Faster re-entry (was 4)
      g_cfgMinMTFAgree  = 45;
      g_cfgRiskPct      = 0.5;     // Per lot (3 lots = 1.5% total, was 0.7%)
      g_cfgZoneCount    = 3;
      g_cfgPriceDistLB  = 40;      // Tighter price distribution (was 50)
      // Cases: 1, 4, 5, 6, 7, 8 (fast-resolving patterns + basic crossover)
      for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = false;
      g_cfgCaseEnabled[1] = true;
      g_cfgCaseEnabled[4] = true;
      g_cfgCaseEnabled[5] = true;
      g_cfgCaseEnabled[6] = true;
      g_cfgCaseEnabled[7] = true;
      g_cfgCaseEnabled[8] = true;
      g_cfgCaseEnabled[9] = true;   // Case 9: OB/OS crossover (experimental) - enabled where Case 8 is
   }
   else if(tf <= TF_M30)
   {
      // M30: short intraday, 34 pip TP1
      g_cfgSLRatio      = 1.2;
      g_cfgTPRatio      = 2.0;
      g_cfgTP2Mult      = 2.0;
      g_cfgTP3Mult      = 3.5;
      g_cfgSLTPMethod   = 0;   // ATR
      g_cfgSLSwingLB    = 15;
      g_cfgMinScore     = 45.0;
      g_cfgCooldownBars = 3;
      g_cfgMinMTFAgree  = 45;
      g_cfgRiskPct      = 1.0;
      g_cfgZoneCount    = 3;
      g_cfgPriceDistLB  = 50;
      // Cases: 1, 2, 4, 5, 6, 7, 8
      for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = false;
      g_cfgCaseEnabled[1] = true;
      g_cfgCaseEnabled[2] = true;
      g_cfgCaseEnabled[4] = true;
      g_cfgCaseEnabled[5] = true;
      g_cfgCaseEnabled[6] = true;
      g_cfgCaseEnabled[7] = true;
      g_cfgCaseEnabled[8] = true;
      g_cfgCaseEnabled[9] = true;   // Case 9: OB/OS crossover (experimental) - enabled where Case 8 is
   }
   else if(tf <= TF_H1)
   {
      // H1: intraday position, 54 pip TP1
      g_cfgSLRatio      = 1.5;
      g_cfgTPRatio      = 2.0;
      g_cfgTP2Mult      = 2.5;
      g_cfgTP3Mult      = 4.0;
      g_cfgSLTPMethod   = 0;   // ATR
      g_cfgSLSwingLB    = 20;
      g_cfgMinScore     = 42.0;
      g_cfgCooldownBars = 3;
      g_cfgMinMTFAgree  = 40;
      g_cfgRiskPct      = 1.0;
      g_cfgZoneCount    = 3;
      g_cfgPriceDistLB  = 60;
      // Cases: all (incl. 8 = gated basic crossover) except 0 (legacy, unwired)
      // and 3 (hidden div slow)
      for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = true;
      g_cfgCaseEnabled[0] = false;
      g_cfgCaseEnabled[3] = false;
   }
   else // H4+
   {
      // H4+: context/direction, conservative target
      g_cfgSLRatio      = 1.5;
      g_cfgTPRatio      = 2.0;
      g_cfgTP2Mult      = 2.5;
      g_cfgTP3Mult      = 4.0;
      g_cfgSLTPMethod   = 2;   // HYBRID (swing-based better for H4 structure)
      g_cfgSLSwingLB    = 20;
      g_cfgMinScore     = 38.0;
      g_cfgCooldownBars = 2;
      g_cfgMinMTFAgree  = 35;
      g_cfgRiskPct      = 1.5;
      g_cfgZoneCount    = 3;
      g_cfgPriceDistLB  = 80;
      // Cases: 1, 4, 5, 6, 7, 8 (no divergence — too slow; basic crossover via Case 8)
      for(int c = 0; c < 10; c++) g_cfgCaseEnabled[c] = false;
      g_cfgCaseEnabled[1] = true;
      g_cfgCaseEnabled[4] = true;
      g_cfgCaseEnabled[5] = true;
      g_cfgCaseEnabled[6] = true;
      g_cfgCaseEnabled[7] = true;
      g_cfgCaseEnabled[8] = true;
      g_cfgCaseEnabled[9] = true;   // Case 9: OB/OS crossover (experimental) - enabled where Case 8 is
   }

   // User input overrides: if user explicitly disabled a case, respect it
   // even in auto mode. Auto profile sets defaults; user input is final veto.
   for(int c2 = 0; c2 < 10; c2++)
      if(!_GetInputCase(c2)) g_cfgCaseEnabled[c2] = false;
}

//+------------------------------------------------------------------+
//| Getter functions — use these everywhere instead of InpXxx         |
//| Return auto-config value when InpAutoTFConfig=true,               |
//| otherwise return manual input value.                              |
//+------------------------------------------------------------------+
double GetActiveSLRatio()       { return(InpAutoTFConfig ? g_cfgSLRatio      : InpSLRatio); }
double GetActiveTPRatio()       { return(InpAutoTFConfig ? g_cfgTPRatio      : InpTPRatio); }
double GetActiveTP2Mult()       { return(InpAutoTFConfig ? g_cfgTP2Mult      : InpTP2Multiplier); }
double GetActiveTP3Mult()       { return(InpAutoTFConfig ? g_cfgTP3Mult      : InpTP3Multiplier); }
int    GetActiveSLTPMethod()    { return(InpAutoTFConfig ? g_cfgSLTPMethod   : (int)InpSLTPMethod); }
int    GetActiveSLSwingLB()     { return(InpAutoTFConfig ? g_cfgSLSwingLB    : InpSLSwingLookback); }
double GetActiveMinScore()      { return(InpAutoTFConfig ? g_cfgMinScore     : InpMinSignalScore); }
int    GetActiveCooldownBars()  { return(InpAutoTFConfig ? g_cfgCooldownBars : InpCooldownBars); }
int    GetActiveMinMTFAgree()   { return(InpAutoTFConfig ? g_cfgMinMTFAgree  : InpMinMTFAgreement); }
double GetActiveRiskPct()       { return(InpAutoTFConfig ? g_cfgRiskPct      : InpTotalRiskPercent); }
int    GetActiveZoneCount()     { return(InpAutoTFConfig ? g_cfgZoneCount    : InpEntryZoneCount); }
int    GetActivePriceDistLB()   { return(InpAutoTFConfig ? g_cfgPriceDistLB  : InpPriceDistLookback); }

bool GetActiveCaseEnabled(int caseNum)
{
   if(caseNum < 0 || caseNum > 9) return(true);
   return(InpAutoTFConfig ? g_cfgCaseEnabled[caseNum] : _GetInputCase(caseNum));
}

#endif
