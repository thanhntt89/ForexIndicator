//+------------------------------------------------------------------+
//|                                      QuantEdge_EA_Template.mq4   |
//|                         Reference EA for QuantEdge RSI Indicator  |
//+------------------------------------------------------------------+
//  REFERENCE / SKELETON — review before enabling live trading.
//  This EA reads QuantEdge RSI indicator buffers via iCustom() and
//  makes trade decisions based on recommendation level, confidence,
//  signal staleness, spread, and duplicate-position checks.
//
//  InpEnableAutoTrading defaults to FALSE. With auto-trading off,
//  the EA logs gate decisions to the Experts tab without placing
//  orders. Flip to TRUE only after demo-account validation.
//
//  Buffer contract: Document_System/12_EA_EXPORT_CONTRACT.md
//+------------------------------------------------------------------+
#property copyright "QuantEdge"
#property version   "1.00"
#property strict

// [BUILD-TAG] Bump on every meaningful EA change and check this against the
// FIRST line printed on chart load — repeatedly "the fix isn't showing up"
// reports turned out to be testing against a not-yet-recompiled binary, with
// no way to tell from the log alone. This settles it at a glance.
#define EA_BUILD_TAG "2026-09-24.2-arrowfix"

// [ORPHAN-CLEANUP] Indicator-owned object prefixes (mirrors Config.mqh —
// the EA is a separate compiled program with no shared include, so these
// are duplicated literals, not a shared constant. Keep in sync if the
// indicator's prefixes ever change).
// A standalone QuantEdge_RSI instance previously attached to this same
// chart can leave SL/TP/Zone objects behind if it's removed at the exact
// moment MT4/5 reports the deinit reason as REASON_CHARTCHANGE instead of
// a real removal — the indicator's own "don't wipe on a plain TF switch"
// guard then skips cleanup, and nothing is left running to ever clean them
// up. Wipe them once at EA startup so the EA, when it's the only program
// left on the chart, doesn't inherit stale clutter from a prior instance.
#define QE_IND_PREFIX_LINE "QE_Line_"
#define QE_IND_PREFIX_ZONE "QE_Zone_"
void QEEA_CleanupOrphanedIndicatorObjects()
{
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, QE_IND_PREFIX_LINE) == 0 || StringFind(name, QE_IND_PREFIX_ZONE) == 0)
         ObjectDelete(name);
   }
}

//+------------------------------------------------------------------+
//| Buffer index constants (from 12_EA_EXPORT_CONTRACT.md)            |
//+------------------------------------------------------------------+
#define BUF_RSI_FAST         0
#define BUF_BUY_SIGNAL       5
#define BUF_SELL_SIGNAL      6
#define BUF_ENTRY            7
#define BUF_SL               8
#define BUF_TP1              9
#define BUF_TP2              10
#define BUF_PROB_TP1         11
#define BUF_PROB_SL          14
#define BUF_PROB_SAMPLES     15
#define BUF_PROB_DECAYED_TP1 16
#define BUF_PROB_SURVIVAL    17
#define BUF_PROB_EXPIRES_MIN 18
#define BUF_REC_LEVEL        21
#define BUF_REC_CONFIDENCE   22
#define BUF_REC_EV           23
#define BUF_REC_RISK         24
#define BUF_TP3              25

//+------------------------------------------------------------------+
//| Recommendation level ordinals (mirrors ENUM_RECOMMENDATION)       |
//+------------------------------------------------------------------+
enum ENUM_REC_LEVEL
{
   REC_STRONG_ENTRY  = 0,  // STRONG — Best quality
   REC_ENTRY         = 1,  // ENTRY — Good
   REC_CAUTION_ENTRY = 2,  // CAUTION — Acceptable
   REC_WAIT          = 3,  // WAIT — Low quality
   REC_AVOID         = 4,  // AVOID — Skip
   REC_COUNTER_TREND = 5,  // COUNTER_TREND — Opposite
   REC_ANY           = 6   // ANY — Force entry on ALL signals
};

//+------------------------------------------------------------------+
//| INPUT GROUP: EA Settings                                          |
//+------------------------------------------------------------------+
input string inp_grp_ea          = "========== EA Settings =========="; // ---
input string InpIndicatorName    = "QuantEdge_RSI";     // Indicator name (compiled .ex4)
input bool   InpEnableAutoTrading= true;                // Enable live order placement
input int    InpMagicNumber      = 20260805;            // Magic number for order identification
input int    InpSlippage         = 10;                   // Max slippage (points)
input bool   InpShowSignalArrows = true;                // Draw signal arrows on chart
input int    InpArrowSize        = 2;                   // Arrow size (1-5)
input int    InpArrowOffsetPts   = 10;                  // Arrow offset from price (points)
input color  InpBuyArrowColor    = clrLime;             // Buy arrow color
input color  InpSellArrowColor   = clrRed;              // Sell arrow color

//+------------------------------------------------------------------+
//| INPUT GROUP: Decision Gates                                       |
//+------------------------------------------------------------------+
input string inp_grp_gates       = "========== Decision Gates =========="; // ---
input bool   InpUseGate1RecLevel = true;                // Enable Gate 1: Recommendation Level check
input ENUM_REC_LEVEL InpMinRecLevel = REC_CAUTION_ENTRY;  // Min recommendation level (worst allowed)
input bool   InpAllowCaution     = true;                // Allow CAUTION_ENTRY level trades
input bool   InpUseGate2Confidence = true;              // Enable Gate 2: Confidence check
input int    InpMinConfidence    = 50;                  // Min confidence score (0-100)
input bool   InpUseGate3Staleness  = true;              // Enable Gate 3: Staleness check
input double InpMaxSurvivalFloor = 0.15;                // Signal expired when survival < this
input bool   InpUseGate5Spread     = true;              // Enable Gate 5: Spread check (absolute and/or % of TP1)
input int    InpMaxSpreadPoints  = 40;                  // Max spread (points, 0=no absolute check)
input double InpMaxSpreadPctOfTP1 = 8.0;                // Max spread as % of Entry->TP1 distance (0=no check)
input bool   InpUseGate11EV      = true;                // Enable Gate 11: Expected Value check
input double InpMinEV            = 0.0;                 // Min EV in R-multiples (signal rejected below this)
input bool   InpUseGate12FillRR  = true;                // Enable Gate 12: remaining R:R at fill price
input double InpMinFillRR        = 0.5;                 // Min (TP1-market)/(market-SL) required to fill

//+------------------------------------------------------------------+
//| INPUT GROUP: Session Filter                                        |
//+------------------------------------------------------------------+
input string inp_grp_session     = "========== Session Filter =========="; // ---
input bool   InpUseSessionFilter = true;                // Enable session filter (Gate 6)
input int    InpSessionStartHour = 7;                   // Session start hour (GMT)
input int    InpSessionEndHour   = 20;                  // Session end hour (GMT)

//+------------------------------------------------------------------+
//| INPUT GROUP: Daily Loss Cap                                        |
//+------------------------------------------------------------------+
input string inp_grp_daily       = "========== Daily / Weekly / Monthly Loss Cap =========="; // ---
input bool   InpUseDailyLossCap  = false;               // Enable daily loss cap (Gate 7)
input int    InpMaxDailyLosses   = 0;                   // Max consecutive losses per day (0=no limit)
input double InpMaxDailyLossPct  = 0.0;                 // Max daily loss % of balance (0=no limit)
input bool   InpUseWeeklyDDStop  = false;               // Enable weekly DD stop (Gate 7b)
input double InpMaxWeeklyDDPct   = 10.0;                // Max weekly loss % of balance (0=no limit)
input bool   InpUseMonthlyDDStop = false;               // Enable monthly DD stop (Gate 7c)
input double InpMaxMonthlyDDPct  = 15.0;                // Max monthly loss % of balance (0=no limit)

//+------------------------------------------------------------------+
//| INPUT GROUP: Advanced Gates (ADX / Economic Calendar)              |
//| Mirror the indicator's own flags — the indicator publishes gate    |
//| state via GlobalVariable; the EA just reads it. Default OFF.       |
//| Note: MT4 has no calendar API — indicator always publishes 0       |
//| (clear) for QE_EconBlackout_<symbol>, so Gate 9 always passes.     |
//+------------------------------------------------------------------+
input string inp_grp_retry        = "========== Signal Retry =========="; // ---
input bool   InpUseSignalRetry    = true;               // Retry cached signal every tick while still valid
input int    InpRetryMaxBars      = 2;                  // Max bars to keep retrying after signal appeared
input bool   InpInvalidateOnTP1   = true;               // Drop the cached signal once price has reached TP1

input string inp_grp_priceloc     = "========== Price Location Gate (10) =========="; // ---
input bool   InpUseGate10PriceLoc  = true;              // Enable Gate 10: Price Location filter (master switch)
input bool   InpUsePriceLocSLSide  = true;              // Case 1: Allow entry when price between SL-Entry (probSL<max, within max%)
input bool   InpUsePriceLocTPSide  = true;              // Case 2: Allow entry when price between Entry-TP1 (probSL<max, within max%)
input double InpPriceLocMaxPct     = 25.0;              // Max % distance from reference edge (0-100)
input double InpPriceLocMaxProbSL  = 50.0;              // Max prob SL % allowed (0-100)

input string inp_grp_advgates    = "========== Advanced Gates =========="; // ---
input bool   InpUseADXGate       = false;               // Enable ADX trend-strength gate (Gate 8)
input bool   InpUseEconCalGate   = false;               // Enable economic calendar blackout gate (Gate 9)

//+------------------------------------------------------------------+
//| TP Mode selector                                                   |
//+------------------------------------------------------------------+
enum ENUM_TP_MODE
{
   TP_DEFAULT  = 0,  // Default — all lot at TP1
   TP_USE_TP2  = 1,  // TP2 — all lot at TP2
   TP_USE_TP3  = 2,  // TP3 — all lot at TP3
   TP_DYNAMIC  = 3   // Dynamic — split TP1 leg + TP2 trailing
};

//+------------------------------------------------------------------+
//| INPUT GROUP: Trade Management                                      |
//+------------------------------------------------------------------+
input string inp_grp_mgmt        = "========== Trade Management =========="; // ---
input ENUM_TP_MODE InpTPMode     = TP_DEFAULT;           // TP Mode: Default(TP1) / TP2 / TP3 / Dynamic(split+trail)
input bool   InpUseStructuralSLTP = true;               // Keep SL/TP at the indicator's structural prices (false=shift with market)
input double InpTP1LotRatio      = 0.6;                 // [Dynamic] TP1 leg lot ratio (0.1-0.9)
input bool   InpUseTrailing      = true;                // [Dynamic] Enable ATR trailing stop on TP2 leg
input double InpTrailATRMult     = 1.5;                 // Trailing distance = ATR × this multiplier
input int    InpTrailATRPeriod   = 14;                  // ATR period for trailing calculation

//+------------------------------------------------------------------+
//| INPUT GROUP: Positive DCA (Trend Direction)                       |
//+------------------------------------------------------------------+
input string inp_grp_posdca       = "========== Positive DCA =========="; // ---
input bool   InpUsePositiveDCA    = true;                // Enable positive DCA (add in trend direction)
input int    InpPosDCAMaxOrders   = 4;                   // Max positive DCA orders (1-10)
input double InpPosDCAATRMult    = 2.5;                  // Pos DCA spacing = ATR × this multiplier
input double InpPosDCAHalfClosePct= 50.0;                // Stop adding DCA above this % of Entry→TP1 distance

//+------------------------------------------------------------------+
//| INPUT GROUP: Negative DCA (Against Trend / Recovery)              |
//+------------------------------------------------------------------+
input string inp_grp_negdca       = "========== Negative DCA =========="; // ---
input bool   InpUseNegativeDCA    = true;                // Enable negative DCA (add against trend)
input int    InpNegDCAMaxOrders   = 10;                  // Max negative DCA orders (1-10)
input double InpNegDCATriggerPct  = 50.0;                // Trigger when price moves this % toward SL
input double InpNegDCAATRMult     = 2.5;                 // Neg DCA spacing = ATR × this multiplier
input double InpNegDCAMaxDDPct    = 15.0;                // Hard drawdown cap (% of balance) — applies to ENTIRE basket whenever ANY DCA mode is active, close all if exceeded
input bool   InpNegDCABEClose     = true;                // Close negative DCA basket when price returns to avg entry (breakeven)
input double InpNegDCABEOffsetPip = 5.0;                 // Breakeven offset in pips (0=exact breakeven, >0=require profit)
input double InpDCAProfitLockR    = 1.0;                 // Min basket profit (in R, vs original entry→SL risk) required before entry-return close fires
input double InpDCAMinSpacingPts = 1500;                 // Min distance between DCA orders (points, 500=$5 XAUUSD)
input int    InpDCAMinIntervalMin= 5;                   // Min time between DCA orders (minutes, 0=no check)
input bool   InpUseDCABackstopSL  = false;               // Broker-side SL safety net for DCA basket (protects if EA goes offline) — opt-in
input double InpDCABackstopBufferMult = 1.3;             // Backstop distance = DD-cap distance × this (wider than EA's own tick-cap so it doesn't fire under normal operation)

//+------------------------------------------------------------------+
//| INPUT GROUP: Risk & Lot Sizing                                    |
//+------------------------------------------------------------------+
input string inp_grp_risk        = "========== Risk & Lot Sizing =========="; // ---
input double InpDefaultRiskPct   = 0.5;                 // Fallback risk % when indicator returns 0
input double InpMaxLotSize       = 0.1;                 // Max lot size (hard cap)
input double InpMinLotSize       = 0.03;                // Min lot size

//+------------------------------------------------------------------+
//| INPUT GROUP: Recovery Mode                                         |
//+------------------------------------------------------------------+
input string inp_grp_recovery    = "========== Recovery Mode =========="; // ---
input bool   InpUseRecoveryMode  = false;                // Enable Recovery Mode (boost lot after DCA cutloss)
input double InpRecoveryLotMult  = 1.3;                  // Lot multiplier during recovery (1.1-2.0)
input int    InpRecoveryMaxTrades= 5;                    // Max trades in recovery mode before auto-off
input int    InpRecoveryMaxConsLoss = 2;                  // Max consecutive losses in recovery — auto-off (circuit breaker)

//+------------------------------------------------------------------+
//| INPUT GROUP: Indicator Params (must match loaded indicator)       |
//| Pass-through to iCustom(). Change only if your indicator uses     |
//| non-default settings — otherwise leave defaults.                  |
//+------------------------------------------------------------------+
input string inp_grp_ind         = "========== Indicator Params =========="; // ---
input int    Ind_RSIPeriod       = 14;
input int    Ind_FastMAPeriod    = 2;
input int    Ind_SignalMAPeriod  = 7;
input int    Ind_BBPeriod        = 34;
input double Ind_BBDeviation     = 1.685;
input bool   Ind_EAMode          = true;  // Always true — suppresses indicator visuals

//+------------------------------------------------------------------+
//| INPUT GROUP: Indicator Probability Override                        |
//| Passed to indicator via GlobalVariable (not iCustom params).       |
//+------------------------------------------------------------------+
input string inp_grp_indprob     = "========== Indicator Prob Override =========="; // ---
input int    Ind_BrierMinSamples = 0;              // Brier: min resolved samples per case (0=disable shrink)
input double Ind_BrierFloorShrink= 1.00;           // Brier: uncertainty floor when samples=0 (0.50=halve, 0.75=mild, 1.0=off)

//+------------------------------------------------------------------+
//| INPUT GROUP: Close Panel                                          |
//+------------------------------------------------------------------+
input string inp_grp_panel       = "========== Close Panel =========="; // ---
input bool   InpShowClosePanel   = true;                // Show close-order panel on chart

//+------------------------------------------------------------------+
//| Close panel object-name constants                                 |
//+------------------------------------------------------------------+
#define QEEA_PREFIX          "QEEA_"
#define QEEA_HEADER          (QEEA_PREFIX + "Header")
#define QEEA_HEADER_TXT      (QEEA_PREFIX + "HeaderTxt")
#define QEEA_BG              (QEEA_PREFIX + "Bg")
#define QEEA_BTN_PROFIT_ALL  (QEEA_PREFIX + "BtnProfitAll")
#define QEEA_BTN_LOSS_ALL    (QEEA_PREFIX + "BtnLossAll")
#define QEEA_BTN_BUY_PROFIT  (QEEA_PREFIX + "BtnBuyProfit")
#define QEEA_BTN_SELL_PROFIT (QEEA_PREFIX + "BtnSellProfit")
#define QEEA_BTN_CLOSE_ALL   (QEEA_PREFIX + "BtnCloseAll")

#define QEEA_PANEL_WIDTH  150
#define QEEA_HEADER_H     20
#define QEEA_BTN_H        24
#define QEEA_BTN_GAP      4
#define QEEA_PAD          5

#define CRIT_ALL_PROFIT   0
#define CRIT_ALL_LOSS     1
#define CRIT_BUY_PROFIT   2
#define CRIT_SELL_PROFIT  3
#define CRIT_CLOSE_ALL    4

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;

int  g_panelPosX      = 20;
int  g_panelPosY      = 20;
bool g_panelDragging  = false;
int  g_dragOffsetX    = 0;
int  g_dragOffsetY    = 0;
bool g_panelCollapsed = false;

#define MAGIC_TP2_OFFSET      100000
#define MAGIC_TP3_OFFSET      150000
#define MAGIC_POS_DCA_OFFSET  200000
#define MAGIC_NEG_DCA_OFFSET  300000

int      g_dailyLossCount   = 0;
double   g_dailyLossAmount  = 0;
datetime g_dailyResetDate   = 0;
double   g_weeklyLossAmount  = 0;
datetime g_weeklyResetDate   = 0;
double   g_monthlyLossAmount = 0;
datetime g_monthlyResetDate  = 0;

//+------------------------------------------------------------------+
//| Signal retry state — cached from last valid signal for tick retry  |
//+------------------------------------------------------------------+
bool     g_sigValid       = false;
int      g_sigDirection   = 0;
int      g_sigCaseNum     = 0;
double   g_sigEntry       = 0;
double   g_sigSL          = 0;
double   g_sigTP1         = 0;
double   g_sigTP2         = 0;
double   g_sigTP3         = 0;
double   g_sigRecLevel    = 0;
double   g_sigConfidence  = 0;
double   g_sigEV          = 0;
double   g_sigRiskPct     = 0;
double   g_sigProbTP1     = 0;
bool     g_sigTP1Hit      = false;
bool     g_sigSLHit       = false;
datetime g_sigBarTime     = 0;   // Bar time of the signal itself (for RetryMaxBars expiry)

//+------------------------------------------------------------------+
//| [REARM-FIX] Bar time of the last signal we actually FILLED.       |
//|                                                                   |
//| The indicator's GV bridge is only cleared in its OnDeinit, so a   |
//| signal's GVs sit there indefinitely after the EA has traded it.   |
//| Once the basket closed (TP1 hit, say), ClearDCAState() released   |
//| Gate 4, the next new bar re-read those SAME stale GVs, and the EA |
//| re-entered the exact same signal at a price that had already run  |
//| far away. The chart showed one arrow and two trades, because      |
//| DrawSignalArrow() de-dupes by object name.                        |
//|                                                                   |
//| Deliberately NOT stored via SaveDCAState(): ClearDCAState() fires |
//| precisely when the basket closes, which is exactly the moment we  |
//| still need this memory. It gets its own GV key instead.           |
//+------------------------------------------------------------------+
datetime g_lastTradedSigTime = 0;

// [ARROW-FIX] Whether the startup arrow sweep has actually run. OnInit often
// fires before the indicator has calculated, so CopyBuffer/iCustom there
// returns nothing and the sweep draws zero arrows; OnTick retries until one
// pass sees real data.
bool     g_arrowSweepDone = false;

//+------------------------------------------------------------------+
//| DCA state tracking                                                |
//+------------------------------------------------------------------+
bool     g_dcaActive          = false;   // Is DCA state tracking active
int      g_dcaDirection       = 0;       // 1=BUY basket, -1=SELL basket
double   g_dcaOriginalEntry   = 0;       // Original signal entry price (market-adjusted)
double   g_dcaOriginalSL      = 0;       // Original signal SL price (market-adjusted)
double   g_dcaOriginalTP1     = 0;       // Original signal TP1 price (market-adjusted)
double   g_dcaOriginalLot     = 0;       // Original total lot size (pre-split)
bool     g_dcaTP1HalfClosed   = false;   // Has the TP1-level half-close been executed
bool     g_dcaNegTriggered    = false;   // Has negative DCA trigger fired
double   g_dcaNegTriggerPrice = 0;       // Price at which negative DCA was first triggered
datetime g_dcaLastOrderTime   = 0;       // Time of last DCA order placed

// Recovery Mode state
bool     g_recoveryActive     = false;    // Is recovery mode currently active
double   g_recoveryPreLossEq  = 0;        // Equity level before cutloss (recovery target)
int      g_recoveryTradeCount = 0;        // Trades placed since recovery activated
int      g_recoveryConsLoss   = 0;        // Consecutive losses during recovery

//+------------------------------------------------------------------+
//| Read one indicator buffer value at shift=1                        |
//+------------------------------------------------------------------+
double ReadBuffer(int bufferIndex)
{
   return ReadBufferAt(bufferIndex, 1);
}

double ReadBufferAt(int bufferIndex, int shift)
{
   return iCustom(Symbol(), Period(), InpIndicatorName,
                  "", // inp_grp_core separator
                  Ind_RSIPeriod, Ind_FastMAPeriod, Ind_SignalMAPeriod,
                  Ind_BBPeriod, Ind_BBDeviation, PRICE_CLOSE,
                  Ind_EAMode,
                  bufferIndex, shift);
}

//+------------------------------------------------------------------+
//| [GATE3-FIX] Read a buffer AT THE CACHED SIGNAL'S OWN BAR.         |
//|                                                                   |
//| The probability/recommendation buffers are written ONLY on the    |
//| signal's bar — every other bar holds EMPTY_VALUE. ReadBuffer()    |
//| hardcodes shift=1, so once the signal is two or more bars back    |
//| (exactly the retry window Gate 3 exists to police) it read an     |
//| empty slot, the "!= EMPTY_VALUE" guard went false, and the gate   |
//| silently passed every time. Resolve the shift from the signal's   |
//| own bar time instead. The indicator refreshes these buffers at    |
//| the signal bar on each redraw, so this returns the CURRENT        |
//| decayed values, not a snapshot from when the signal formed.       |
//+------------------------------------------------------------------+
double ReadSignalBuffer(int bufferIndex)
{
   if(g_sigBarTime == 0)
      return ReadBuffer(bufferIndex);
   int shift = iBarShift(Symbol(), Period(), g_sigBarTime, false);
   if(shift < 0)
      return EMPTY_VALUE;
   return ReadBufferAt(bufferIndex, shift);
}

//+------------------------------------------------------------------+
//| Read signal from GV bridge (published by standalone indicator)    |
//+------------------------------------------------------------------+
bool ReadSignalFromGV(double &outBuyCase, double &outSellCase, int &outShift,
                      double &outEntry, double &outSL, double &outTP1, double &outTP2, double &outTP3,
                      double &outRecLevel, double &outConf, double &outEV, double &outRisk, double &outProbTP1)
{
   string sym = Symbol();
   if(!GlobalVariableCheck("QE_SigDir_" + sym))
      return false;

   double dir     = GlobalVariableGet("QE_SigDir_"     + sym);
   double caseDbl = GlobalVariableGet("QE_SigCase_"    + sym);
   double sigTime = GlobalVariableGet("QE_SigTime_"    + sym);
   if(dir == 0 || caseDbl == 0 || sigTime == 0)
      return false;

   int shift = iBarShift(Symbol(), Period(), (datetime)sigTime, false);
   int scanLimit = (InpRetryMaxBars > 0) ? InpRetryMaxBars : 5;
   if(shift < 1 || shift > scanLimit)
      return false;

   outShift   = shift;
   outEntry   = GlobalVariableCheck("QE_SigEntry_"   + sym) ? GlobalVariableGet("QE_SigEntry_"   + sym) : EMPTY_VALUE;
   outSL      = GlobalVariableCheck("QE_SigSL_"      + sym) ? GlobalVariableGet("QE_SigSL_"      + sym) : EMPTY_VALUE;
   outTP1     = GlobalVariableCheck("QE_SigTP1_"     + sym) ? GlobalVariableGet("QE_SigTP1_"     + sym) : EMPTY_VALUE;
   outTP2     = GlobalVariableCheck("QE_SigTP2_"     + sym) ? GlobalVariableGet("QE_SigTP2_"     + sym) : EMPTY_VALUE;
   outTP3     = GlobalVariableCheck("QE_SigTP3_"     + sym) ? GlobalVariableGet("QE_SigTP3_"     + sym) : EMPTY_VALUE;
   outRecLevel= GlobalVariableCheck("QE_SigRecLv_"   + sym) ? GlobalVariableGet("QE_SigRecLv_"   + sym) : EMPTY_VALUE;
   outConf    = GlobalVariableCheck("QE_SigConf_"    + sym) ? GlobalVariableGet("QE_SigConf_"    + sym) : EMPTY_VALUE;
   outEV      = GlobalVariableCheck("QE_SigEV_"      + sym) ? GlobalVariableGet("QE_SigEV_"      + sym) : EMPTY_VALUE;
   outRisk    = GlobalVariableCheck("QE_SigRisk_"    + sym) ? GlobalVariableGet("QE_SigRisk_"    + sym) : EMPTY_VALUE;
   outProbTP1 = GlobalVariableCheck("QE_SigProbTP1_" + sym) ? GlobalVariableGet("QE_SigProbTP1_" + sym) : EMPTY_VALUE;

   if(dir > 0)
   {
      outBuyCase  = caseDbl;
      outSellCase = EMPTY_VALUE;
   }
   else
   {
      outBuyCase  = EMPTY_VALUE;
      outSellCase = caseDbl;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size from risk percent and SL distance              |
//+------------------------------------------------------------------+
double CalculateLotFromRisk(double riskPct, double slDistancePoints)
{
   if(riskPct <= 0 || slDistancePoints <= 0)
      return 0;

   double balance   = AccountBalance();
   double tickVal   = MarketInfo(Symbol(), MODE_TICKVALUE);
   double lotStep   = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot    = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot    = MarketInfo(Symbol(), MODE_MAXLOT);

   if(tickVal <= 0 || lotStep <= 0)
      return 0;

   double riskAmount = balance * riskPct / 100.0;
   double rawLot     = riskAmount / (slDistancePoints * tickVal);

   rawLot = MathFloor(rawLot / lotStep) * lotStep;
   rawLot = MathMax(rawLot, MathMax(minLot, InpMinLotSize));
   rawLot = MathMin(rawLot, MathMin(maxLot, InpMaxLotSize));

   return NormalizeDouble(rawLot, 2);
}

//+------------------------------------------------------------------+
//| Get recommendation level name for logging                         |
//+------------------------------------------------------------------+
string RecLevelName(int level)
{
   switch(level)
   {
      case REC_STRONG_ENTRY:  return "STRONG_ENTRY";
      case REC_ENTRY:         return "ENTRY";
      case REC_CAUTION_ENTRY: return "CAUTION_ENTRY";
      case REC_WAIT:          return "WAIT";
      case REC_AVOID:         return "AVOID";
      case REC_COUNTER_TREND: return "COUNTER_TREND";
      case REC_ANY:           return "ANY";
      default:                return "UNKNOWN(" + IntegerToString(level) + ")";
   }
}

//+------------------------------------------------------------------+
//| Check if we already have a position in the same direction         |
//| Considers both TP1 (InpMagicNumber) and TP2 leg magic numbers.   |
//+------------------------------------------------------------------+
bool HasOpenPosition(int direction)
{
   int magicTP2 = InpMagicNumber + MAGIC_TP2_OFFSET;
   int magicTP3 = InpMagicNumber + MAGIC_TP3_OFFSET;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      int mag = OrderMagicNumber();
      if(mag != InpMagicNumber && mag != magicTP2 && mag != magicTP3)
         continue;

      if(direction > 0 && OrderType() == OP_BUY)
         return true;
      if(direction < 0 && OrderType() == OP_SELL)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| DCA HELPER FUNCTIONS                                              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if a magic number belongs to our EA (any leg type)          |
//+------------------------------------------------------------------+
bool IsOurMagic(int magic)
{
   if(magic == InpMagicNumber)                      return true;
   if(magic == InpMagicNumber + MAGIC_TP2_OFFSET)    return true;
   if(magic == InpMagicNumber + MAGIC_TP3_OFFSET)    return true;
   if(magic >= InpMagicNumber + MAGIC_POS_DCA_OFFSET &&
      magic <  InpMagicNumber + MAGIC_POS_DCA_OFFSET + 100)
      return true;
   if(magic >= InpMagicNumber + MAGIC_NEG_DCA_OFFSET &&
      magic <  InpMagicNumber + MAGIC_NEG_DCA_OFFSET + 100)
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| Count open DCA positions of a specific type (POS or NEG offset)   |
//+------------------------------------------------------------------+
int CountDCAPositions(int dcaType)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();
      if(mag >= InpMagicNumber + dcaType &&
         mag <  InpMagicNumber + dcaType + 100)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if ANY original position (TP1 or TP2 leg) exists           |
//+------------------------------------------------------------------+
bool HasAnyOriginalPosition()
{
   int magicTP2 = InpMagicNumber + MAGIC_TP2_OFFSET;
   int magicTP3 = InpMagicNumber + MAGIC_TP3_OFFSET;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();
      if(mag == InpMagicNumber || mag == magicTP2 || mag == magicTP3)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if ANY DCA position (positive or negative) exists          |
//+------------------------------------------------------------------+
bool HasAnyDCAPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();
      if(mag >= InpMagicNumber + MAGIC_POS_DCA_OFFSET &&
         mag <  InpMagicNumber + MAGIC_NEG_DCA_OFFSET + 100)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sum floating P/L (profit + swap + commission) for our EA         |
//+------------------------------------------------------------------+
double CalculateBasketPnL()
{
   double total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOurMagic(OrderMagicNumber())) continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return total;
}

//+------------------------------------------------------------------+
//| Weighted average entry price for original + negative DCA basket   |
//+------------------------------------------------------------------+
double CalculateNegDCAAvgEntry()
{
   double totalLots = 0;
   double weightedPrice = 0;
   int magicTP2 = InpMagicNumber + MAGIC_TP2_OFFSET;
   int magicTP3 = InpMagicNumber + MAGIC_TP3_OFFSET;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();

      bool isOriginal = (mag == InpMagicNumber || mag == magicTP2 || mag == magicTP3);
      bool isNegDCA   = (mag >= InpMagicNumber + MAGIC_NEG_DCA_OFFSET &&
                         mag <  InpMagicNumber + MAGIC_NEG_DCA_OFFSET + 100);
      if(!isOriginal && !isNegDCA) continue;

      double lots  = OrderLots();
      double entry = OrderOpenPrice();
      totalLots     += lots;
      weightedPrice += lots * entry;
   }

   if(totalLots <= 0) return 0;
   return weightedPrice / totalLots;
}

//+------------------------------------------------------------------+
//| Weighted average entry + total lot across the ENTIRE basket       |
//| (any leg: original, TP2, TP3, positive DCA, negative DCA) — wider |
//| scope than CalculateNegDCAAvgEntry(), matches CheckDrawdownCap()'s|
//| basket-wide CalculateBasketPnL() coverage.                        |
//+------------------------------------------------------------------+
double CalculateBasketAvgEntry(double &totalLotOut)
{
   double totalLots = 0;
   double weightedPrice = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOurMagic(OrderMagicNumber())) continue;

      double lots  = OrderLots();
      double entry = OrderOpenPrice();
      totalLots     += lots;
      weightedPrice += lots * entry;
   }
   totalLotOut = totalLots;
   if(totalLots <= 0) return 0;
   return weightedPrice / totalLots;
}

//+------------------------------------------------------------------+
//| Broker-side backstop SL for the entire DCA basket — a safety net  |
//| for when the EA itself is offline (VPS crash, disconnect, weekend |
//| gap). CheckDrawdownCap() is the primary, tick-by-tick, exact cap; |
//| this sets a wider hard SL on every leg so a cut still happens if  |
//| the EA can't run its own check.                                   |
//+------------------------------------------------------------------+
void ApplyDCABackstopSL()
{
   if(!InpUseDCABackstopSL || !g_dcaActive)
      return;
   if(InpNegDCAMaxDDPct <= 0)
      return;

   double balance = AccountBalance();
   if(balance <= 0)
      return;

   double totalLot = 0;
   double avgEntry = CalculateBasketAvgEntry(totalLot);
   if(totalLot <= 0 || avgEntry <= 0)
      return;

   double tickVal = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickVal <= 0)
      return;

   double ddCapDollars   = balance * InpNegDCAMaxDDPct / 100.0;
   double distancePoints = ddCapDollars / (totalLot * tickVal);
   double distancePrice  = distancePoints * Point * InpDCABackstopBufferMult;

   double backstopSL = (g_dcaDirection > 0)
                        ? NormalizeDouble(avgEntry - distancePrice, Digits)
                        : NormalizeDouble(avgEntry + distancePrice, Digits);

   // Respect broker min-stop-distance from current price
   double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(g_dcaDirection > 0 && backstopSL >= Bid - stoplevel)
      backstopSL = NormalizeDouble(Bid - stoplevel - Point, Digits);
   if(g_dcaDirection < 0 && backstopSL <= Ask + stoplevel)
      backstopSL = NormalizeDouble(Ask + stoplevel + Point, Digits);

   // Apply to every basket leg — only ever tighten, never widen, an existing SL
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOurMagic(OrderMagicNumber())) continue;

      double curSL = OrderStopLoss();
      bool needsUpdate = (curSL == 0) ||
                          (g_dcaDirection > 0 && backstopSL > curSL) ||
                          (g_dcaDirection < 0 && backstopSL < curSL);
      if(!needsUpdate) continue;

      if(!OrderModify(OrderTicket(), OrderOpenPrice(), backstopSL, OrderTakeProfit(), 0, clrYellow))
         Print("[QuantEdge EA] Backstop SL modify FAILED ticket=", OrderTicket(), ": error ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Lot ratio for negative DCA order at given index (1-based)        |
//| idx 1 -> 75%, idx 2 -> 50%, idx 3+ -> 25%                        |
//+------------------------------------------------------------------+
double NegDCALotRatio(int index)
{
   switch(index)
   {
      case 1:  return 0.75;
      case 2:  return 0.50;
      default: return 0.25;
   }
}

//+------------------------------------------------------------------+
//| [REARM-FIX] Persistence for the last-traded signal bar time.      |
//| Separate GV key from the DCA block — see g_lastTradedSigTime.     |
//+------------------------------------------------------------------+
string LastSigGVName()
{
   return "QE_LastSig_" + Symbol() + "_" + IntegerToString(InpMagicNumber);
}

void SaveLastTradedSigTime()
{
   GlobalVariableSet(LastSigGVName(), (double)g_lastTradedSigTime);
}

void LoadLastTradedSigTime()
{
   string nm = LastSigGVName();
   if(GlobalVariableCheck(nm))
      g_lastTradedSigTime = (datetime)GlobalVariableGet(nm);
}

//+------------------------------------------------------------------+
//| True when this signal bar has already produced a filled order.    |
//| Checked at every point where a signal gets armed.                 |
//+------------------------------------------------------------------+
bool IsSignalAlreadyTraded(datetime sigBarTime)
{
   return (g_lastTradedSigTime != 0 && sigBarTime == g_lastTradedSigTime);
}

//+------------------------------------------------------------------+
//| DCA state persistence via terminal GlobalVariables                |
//+------------------------------------------------------------------+
string DCA_GVPrefix()
{
   return "QE_DCA_" + Symbol() + "_" + IntegerToString(InpMagicNumber) + "_";
}

void SaveDCAState()
{
   string pfx = DCA_GVPrefix();
   GlobalVariableSet(pfx + "Active",        g_dcaActive ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "Direction",     (double)g_dcaDirection);
   GlobalVariableSet(pfx + "Entry",         g_dcaOriginalEntry);
   GlobalVariableSet(pfx + "SL",            g_dcaOriginalSL);
   GlobalVariableSet(pfx + "TP1",           g_dcaOriginalTP1);
   GlobalVariableSet(pfx + "Lot",           g_dcaOriginalLot);
   GlobalVariableSet(pfx + "TP1HalfClosed", g_dcaTP1HalfClosed ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "NegTriggered",  g_dcaNegTriggered ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "NegTrigPrice",  g_dcaNegTriggerPrice);
   GlobalVariableSet(pfx + "LastDCATime",   (double)g_dcaLastOrderTime);
}

void LoadDCAState()
{
   string pfx = DCA_GVPrefix();
   if(!GlobalVariableCheck(pfx + "Active"))
      return;
   g_dcaActive          = (GlobalVariableGet(pfx + "Active") != 0.0);
   g_dcaDirection        = (int)GlobalVariableGet(pfx + "Direction");
   g_dcaOriginalEntry    = GlobalVariableGet(pfx + "Entry");
   g_dcaOriginalSL       = GlobalVariableGet(pfx + "SL");
   g_dcaOriginalTP1      = GlobalVariableGet(pfx + "TP1");
   g_dcaOriginalLot      = GlobalVariableGet(pfx + "Lot");
   g_dcaTP1HalfClosed    = (GlobalVariableGet(pfx + "TP1HalfClosed") != 0.0);
   g_dcaNegTriggered     = (GlobalVariableGet(pfx + "NegTriggered") != 0.0);
   g_dcaNegTriggerPrice  = GlobalVariableGet(pfx + "NegTrigPrice");
   g_dcaLastOrderTime    = (datetime)GlobalVariableGet(pfx + "LastDCATime");
}

void ClearDCAState()
{
   g_dcaActive           = false;
   g_dcaDirection        = 0;
   g_dcaOriginalEntry    = 0;
   g_dcaOriginalSL       = 0;
   g_dcaOriginalTP1      = 0;
   g_dcaOriginalLot      = 0;
   g_dcaTP1HalfClosed    = false;
   g_dcaNegTriggered     = false;
   g_dcaNegTriggerPrice  = 0;
   g_dcaLastOrderTime    = 0;

   string pfx = DCA_GVPrefix();
   GlobalVariableDel(pfx + "Active");
   GlobalVariableDel(pfx + "Direction");
   GlobalVariableDel(pfx + "Entry");
   GlobalVariableDel(pfx + "SL");
   GlobalVariableDel(pfx + "TP1");
   GlobalVariableDel(pfx + "Lot");
   GlobalVariableDel(pfx + "TP1HalfClosed");
   GlobalVariableDel(pfx + "NegTriggered");
   GlobalVariableDel(pfx + "NegTrigPrice");
   GlobalVariableDel(pfx + "LastDCATime");
}

//+------------------------------------------------------------------+
//| Session filter: check if current GMT hour is within trade window   |
//+------------------------------------------------------------------+
bool IsWithinSession()
{
   if(!InpUseSessionFilter)
      return true;
   int hourGMT = TimeHour(TimeGMT());
   if(InpSessionStartHour <= InpSessionEndHour)
      return(hourGMT >= InpSessionStartHour && hourGMT < InpSessionEndHour);
   return(hourGMT >= InpSessionStartHour || hourGMT < InpSessionEndHour);
}

//+------------------------------------------------------------------+
//| Daily loss tracking: reset on new day, update on closed losses     |
//+------------------------------------------------------------------+
void UpdateDailyLossTracking()
{
   datetime nowGMT = TimeGMT();
   datetime today  = StringToTime(TimeToString(nowGMT, TIME_DATE));

   // Week start = Monday 00:00 GMT of the current week
   int dow = TimeDayOfWeek(today); // 0=Sunday..6=Saturday
   int daysSinceMonday = (dow == 0) ? 6 : (dow - 1);
   datetime weekStart = today - daysSinceMonday * 86400;

   // Month start = 1st day of current month, 00:00 GMT
   datetime monthStart = StringToTime(StringFormat("%04d.%02d.01", TimeYear(today), TimeMonth(today)));

   if(today != g_dailyResetDate)
   {
      g_dailyLossCount  = 0;
      g_dailyLossAmount = 0;
      g_dailyResetDate  = today;
   }
   if(weekStart != g_weeklyResetDate)
   {
      g_weeklyLossAmount = 0;
      g_weeklyResetDate  = weekStart;
   }
   if(monthStart != g_monthlyResetDate)
   {
      g_monthlyLossAmount = 0;
      g_monthlyResetDate  = monthStart;
   }

   static int s_lastHistTotal = 0;
   int histTotal = OrdersHistoryTotal();
   if(histTotal == s_lastHistTotal)
      return;

   // Incremental scan — each new closed order is visited exactly once, right
   // when it closes ("now"), so it's bucketed into daily/weekly/monthly in
   // the same pass without ever rescanning old history.
   for(int i = s_lastHistTotal; i < histTotal; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      int mag = OrderMagicNumber();
      if(!IsOurMagic(mag))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      if(pnl >= 0)
         continue;

      double absLoss = MathAbs(pnl);
      datetime closeTime = OrderCloseTime();

      g_monthlyLossAmount += absLoss;
      if(closeTime >= g_weeklyResetDate) g_weeklyLossAmount += absLoss;

      datetime closeDay = StringToTime(TimeToString(closeTime, TIME_DATE));
      if(closeDay == g_dailyResetDate)
      {
         g_dailyLossCount++;
         g_dailyLossAmount += absLoss;
      }
   }
   s_lastHistTotal = histTotal;
}

bool IsDailyLossCapHit()
{
   if(!InpUseDailyLossCap)
      return false;
   if(InpMaxDailyLosses > 0 && g_dailyLossCount >= InpMaxDailyLosses)
      return true;
   if(InpMaxDailyLossPct > 0)
   {
      double maxLoss = AccountBalance() * InpMaxDailyLossPct / 100.0;
      if(g_dailyLossAmount >= maxLoss)
         return true;
   }
   return false;
}

bool IsWeeklyDDStopHit()
{
   if(!InpUseWeeklyDDStop || InpMaxWeeklyDDPct <= 0)
      return false;
   static bool s_wasHit = false;
   double maxLoss = AccountBalance() * InpMaxWeeklyDDPct / 100.0;
   bool hit = (g_weeklyLossAmount >= maxLoss);
   if(hit && !s_wasHit)
      Print("[QuantEdge EA] EXIT: WEEKLY DD STOP — loss=", DoubleToString(g_weeklyLossAmount, 2),
            " exceeds ", DoubleToString(InpMaxWeeklyDDPct, 1), "% of balance (",
            DoubleToString(maxLoss, 2), "). Blocking new signals until next week.");
   s_wasHit = hit;
   return hit;
}

bool IsMonthlyDDStopHit()
{
   if(!InpUseMonthlyDDStop || InpMaxMonthlyDDPct <= 0)
      return false;
   static bool s_wasHit = false;
   double maxLoss = AccountBalance() * InpMaxMonthlyDDPct / 100.0;
   bool hit = (g_monthlyLossAmount >= maxLoss);
   if(hit && !s_wasHit)
      Print("[QuantEdge EA] EXIT: MONTHLY DD STOP — loss=", DoubleToString(g_monthlyLossAmount, 2),
            " exceeds ", DoubleToString(InpMaxMonthlyDDPct, 1), "% of balance (",
            DoubleToString(maxLoss, 2), "). Blocking new signals until next month.");
   s_wasHit = hit;
   return hit;
}

//+------------------------------------------------------------------+
//| ATR trailing stop for TP2 and TP3 legs                            |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   if(!InpUseTrailing)
      return;

   int magicTP2 = InpMagicNumber + MAGIC_TP2_OFFSET;
   int magicTP3 = InpMagicNumber + MAGIC_TP3_OFFSET;
   double atr = iATR(Symbol(), 0, InpTrailATRPeriod, 0);
   if(atr <= 0)
      return;
   double trailDist = atr * InpTrailATRMult;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      int mag = OrderMagicNumber();
      if(mag != magicTP2 && mag != magicTP3)
         continue;

      if(OrderType() == OP_BUY)
      {
         double newSL = NormalizeDouble(Bid - trailDist, Digits);
         if(newSL > OrderOpenPrice() && newSL > OrderStopLoss())
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrLime);
      }
      else if(OrderType() == OP_SELL)
      {
         double newSL = NormalizeDouble(Ask + trailDist, Digits);
         if(newSL < OrderOpenPrice() && (OrderStopLoss() == 0 || newSL < OrderStopLoss()))
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrRed);
      }
   }
}

//+------------------------------------------------------------------+
//| DCA MANAGEMENT — positive (trend) + negative (recovery) baskets   |
//| See document/DCA_Flowcharts.md and DCA_Function_Specs.md          |
//+------------------------------------------------------------------+

bool IsDCACooldownOK()
{
   if(InpDCAMinIntervalMin <= 0)
      return true;
   if(g_dcaLastOrderTime == 0)
      return true;
   return (TimeCurrent() - g_dcaLastOrderTime) >= InpDCAMinIntervalMin * 60;
}

bool IsDCASpacingOK(double currentPrice)
{
   if(InpDCAMinSpacingPts <= 0)
      return true;
   double minDist = InpDCAMinSpacingPts * Point;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOurMagic(OrderMagicNumber())) continue;
      if(MathAbs(currentPrice - OrderOpenPrice()) < minDist)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Recovery Mode: activate after DCA cutloss                         |
//+------------------------------------------------------------------+
void ActivateRecoveryMode()
{
   if(!InpUseRecoveryMode) return;
   g_recoveryActive     = true;
   g_recoveryPreLossEq  = AccountEquity();
   g_recoveryTradeCount = 0;
   g_recoveryConsLoss   = 0;
   SaveRecoveryState();
   Print("[QuantEdge EA] RECOVERY MODE ON — target equity=",
         DoubleToString(g_recoveryPreLossEq, 2),
         " lot×", DoubleToString(InpRecoveryLotMult, 2),
         " max ", InpRecoveryMaxTrades, " trades, breaker ", InpRecoveryMaxConsLoss, " loss");
}

void DeactivateRecoveryMode(string reason)
{
   g_recoveryActive     = false;
   g_recoveryPreLossEq  = 0;
   g_recoveryTradeCount = 0;
   g_recoveryConsLoss   = 0;
   ClearRecoveryState();
   Print("[QuantEdge EA] RECOVERY MODE OFF — ", reason);
}

void CheckRecoveryAutoOff()
{
   if(!g_recoveryActive) return;

   if(AccountEquity() >= g_recoveryPreLossEq)
   {
      DeactivateRecoveryMode("equity recovered to " + DoubleToString(g_recoveryPreLossEq, 2));
      return;
   }
   if(g_recoveryTradeCount >= InpRecoveryMaxTrades)
   {
      DeactivateRecoveryMode("max trades reached (" + IntegerToString(InpRecoveryMaxTrades) + ")");
      return;
   }
   if(g_recoveryConsLoss >= InpRecoveryMaxConsLoss)
   {
      DeactivateRecoveryMode("circuit breaker — " + IntegerToString(g_recoveryConsLoss) + " consecutive losses");
      return;
   }
}

double ApplyRecoveryMultiplier(double baseLot)
{
   if(!g_recoveryActive) return baseLot;
   double boosted = baseLot * InpRecoveryLotMult;
   boosted = MathMin(boosted, InpMaxLotSize);
   return NormalizeDouble(boosted, 2);
}

void SaveRecoveryState()
{
   string pfx = "QE_Recovery_" + Symbol() + "_";
   GlobalVariableSet(pfx + "Active",     g_recoveryActive ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "PreLossEq",  g_recoveryPreLossEq);
   GlobalVariableSet(pfx + "TradeCount", (double)g_recoveryTradeCount);
   GlobalVariableSet(pfx + "ConsLoss",   (double)g_recoveryConsLoss);
}

void LoadRecoveryState()
{
   string pfx = "QE_Recovery_" + Symbol() + "_";
   if(!GlobalVariableCheck(pfx + "Active")) return;
   g_recoveryActive     = (GlobalVariableGet(pfx + "Active") != 0.0);
   g_recoveryPreLossEq  = GlobalVariableGet(pfx + "PreLossEq");
   g_recoveryTradeCount = (int)GlobalVariableGet(pfx + "TradeCount");
   g_recoveryConsLoss   = (int)GlobalVariableGet(pfx + "ConsLoss");
   if(g_recoveryActive)
      Print("[QuantEdge EA] Recovery state restored: target=",
            DoubleToString(g_recoveryPreLossEq, 2),
            " trades=", g_recoveryTradeCount, " consLoss=", g_recoveryConsLoss);
}

void ClearRecoveryState()
{
   string pfx = "QE_Recovery_" + Symbol() + "_";
   GlobalVariableDel(pfx + "Active");
   GlobalVariableDel(pfx + "PreLossEq");
   GlobalVariableDel(pfx + "TradeCount");
   GlobalVariableDel(pfx + "ConsLoss");
}

//+------------------------------------------------------------------+
//| Positive DCA: add orders as price moves toward TP1               |
//+------------------------------------------------------------------+
void ManagePositiveDCA()
{
   if(!InpUsePositiveDCA || !g_dcaActive)
      return;

   double entryToTP1 = g_dcaOriginalTP1 - g_dcaOriginalEntry;
   if(MathAbs(entryToTP1) < Point)
      return;

   double price = (g_dcaDirection > 0) ? Ask : Bid;

   // TP1 now closes the entire basket (see ManageDCA() -> TP1 basket-close),
   // so grid orders stop being added past that point without needing a
   // separate half-close/lock step here.

   if(InpPosDCAMaxOrders <= 0)
      return;

   double halfwayPrice = g_dcaOriginalEntry + entryToTP1 * (InpPosDCAHalfClosePct / 100.0);
   bool beyondHalf = (g_dcaDirection > 0) ? (price > halfwayPrice) : (price < halfwayPrice);
   if(beyondHalf)
      return;

   double atrSpacing = iATR(Symbol(), 0, 14, 0) * InpPosDCAATRMult;
   if(atrSpacing <= 0)
      return;

   for(int idx = 1; idx <= InpPosDCAMaxOrders; idx++)
   {
      int dcaMagic = InpMagicNumber + MAGIC_POS_DCA_OFFSET + idx;

      bool exists = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != Symbol()) continue;
         if(OrderMagicNumber() == dcaMagic) { exists = true; break; }
      }
      if(exists) continue;

      double level = (g_dcaDirection > 0)
                      ? g_dcaOriginalEntry + idx * atrSpacing
                      : g_dcaOriginalEntry - idx * atrSpacing;
      bool triggered = (g_dcaDirection > 0) ? (price >= level) : (price <= level);
      if(!triggered) continue;

      if(!IsDCACooldownOK() || !IsDCASpacingOK(price))
         continue;

      double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
      if(lotStep <= 0) continue;
      double minLot  = MathMax(MarketInfo(Symbol(), MODE_MINLOT), InpMinLotSize);
      double dcaLot  = MathFloor(g_dcaOriginalLot / lotStep) * lotStep;
      dcaLot = MathMax(dcaLot, minLot);
      dcaLot = MathMin(dcaLot, InpMaxLotSize);

      string comment = StringFormat("QE DCA+%d", idx);

      double dcaTP = g_dcaOriginalTP1;

      int ticket = -1;
      if(g_dcaDirection > 0)
         ticket = OrderSend(Symbol(), OP_BUY, dcaLot, Ask, InpSlippage, 0, dcaTP, comment, dcaMagic, 0, clrLime);
      else
         ticket = OrderSend(Symbol(), OP_SELL, dcaLot, Bid, InpSlippage, 0, dcaTP, comment, dcaMagic, 0, clrRed);

      if(ticket >= 0)
      {
         g_dcaLastOrderTime = TimeCurrent();
         SaveDCAState();
         Print("[QuantEdge EA] Positive DCA+", idx, " placed: ",
               (g_dcaDirection > 0 ? "BUY" : "SELL"), " ", DoubleToString(dcaLot, 2),
               " lot, magic=", dcaMagic,
               " TP=", DoubleToString(dcaTP, Digits));
         break;
      }
      else
         Print("[QuantEdge EA] Positive DCA+", idx, " FAILED: error ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Close the ENTIRE EA basket on negative-DCA breakeven — original,  |
//| negative DCA, AND positive DCA (if running concurrently). Ends    |
//| the DCA cycle completely so the next signal starts clean.         |
//+------------------------------------------------------------------+
void CloseNegDCABasket()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();
      if(!IsOurMagic(mag)) continue;

      int ticket = OrderTicket();
      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      if(OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrYellow))
         Print("[QuantEdge EA] Neg DCA basket close: ticket=", ticket, " magic=", mag);
      else
         Print("[QuantEdge EA] Neg DCA basket close FAILED: ticket=", ticket,
               " error ", GetLastError());
   }
   ClearDCAState();
}

//+------------------------------------------------------------------+
//| Emergency: close ALL positions belonging to our EA (drawdown cap)|
//+------------------------------------------------------------------+
void CloseEntireBasket()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOurMagic(OrderMagicNumber())) continue;

      int ticket = OrderTicket();
      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      if(OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrYellow))
         Print("[QuantEdge EA] Basket emergency close: ticket=", ticket);
      else
         Print("[QuantEdge EA] Basket emergency close FAILED: ticket=", ticket,
               " error ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Basket-wide drawdown safety valve — applies whenever ANY DCA mode |
//| is active (positive-only, negative-only, or both). Independent   |
//| of InpUseNegativeDCA so a positive-DCA-only setup with SL=0       |
//| orders still has a hard loss limit.                               |
//+------------------------------------------------------------------+
bool CheckDrawdownCap()
{
   if(InpNegDCAMaxDDPct <= 0)
      return false;

   double balance = AccountBalance();
   if(balance <= 0)
      return false;

   double basketPnL = CalculateBasketPnL();
   double maxLoss    = balance * InpNegDCAMaxDDPct / 100.0;
   if(basketPnL < 0 && MathAbs(basketPnL) >= maxLoss)
   {
      Print("[QuantEdge EA] EXIT: DRAWDOWN CAP — basket P/L=", DoubleToString(basketPnL, 2),
            " exceeds ", DoubleToString(InpNegDCAMaxDDPct, 1), "% of balance (",
            DoubleToString(maxLoss, 2), "). Closing entire basket.");
      g_recoveryPreLossEq = AccountEquity();
      CloseEntireBasket();
      ClearDCAState();
      ActivateRecoveryMode();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close everything if price has returned to the original entry     |
//| zone (within current spread) AND the basket is still profitable. |
//| Covers both: positive-DCA that ran toward TP1 then reversed back |
//| to entry, and negative-DCA that recovered back up to entry —     |
//| either way, lock the profit before it erodes further.            |
//+------------------------------------------------------------------+
bool CheckEntryReturnProfitClose()
{
   if(g_dcaOriginalEntry <= 0)
      return false;

   // Only meaningful once price has actually moved far enough to trigger
   // at least one DCA leg — otherwise the original position always starts
   // "near entry" and would close instantly on the first tick it ticks
   // positive.
   if(!HasAnyDCAPosition())
      return false;

   double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
   double price = (g_dcaDirection > 0) ? Bid : Ask;

   bool nearEntry = MathAbs(price - g_dcaOriginalEntry) <= MathMax(spread, Point);
   if(!nearEntry)
      return false;

   double basketPnL = CalculateBasketPnL();

   // Require at least 0.2R of basket profit before locking in — a bare
   // P/L > 0 was closing baskets on a few cents of cross-leg price
   // skew (e.g. a losing original leg offset by a slightly-more-profitable
   // DCA- leg), which is too thin given the risk already taken on by
   // adding to the position. Falls back to "any profit" only when the
   // original SL/tick value can't be resolved (e.g. positive-DCA-only
   // setups with no SL on any leg).
   double minProfitTarget = 0;
   double slDistance = MathAbs(g_dcaOriginalEntry - g_dcaOriginalSL);
   if(slDistance > 0)
   {
      double tickVal = MarketInfo(Symbol(), MODE_TICKVALUE);
      if(tickVal > 0)
      {
         double oneR = (slDistance / Point) * tickVal * g_dcaOriginalLot;
         minProfitTarget = oneR * InpDCAProfitLockR;
      }
   }

   if(basketPnL > minProfitTarget)
   {
      Print("[QuantEdge EA] EXIT: ENTRY-RETURN PROFIT LOCK — price near entry (",
            DoubleToString(g_dcaOriginalEntry, Digits), "), basket P/L=",
            DoubleToString(basketPnL, 2), " > target ", DoubleToString(minProfitTarget, 2),
            " (", DoubleToString(InpDCAProfitLockR, 2), "R). Closing entire basket.");
      CloseEntireBasket();
      ClearDCAState();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Negative DCA: add orders as price moves against position          |
//+------------------------------------------------------------------+
void ManageNegativeDCA()
{
   if(!InpUseNegativeDCA || !g_dcaActive)
      return;

   // --- Basket Breakeven Check (priority 1) ---
   if(InpNegDCABEClose && g_dcaNegTriggered && CountDCAPositions(MAGIC_NEG_DCA_OFFSET) > 0)
   {
      double avgEntry = CalculateNegDCAAvgEntry();
      if(avgEntry > 0)
      {
         double beTarget = (g_dcaDirection > 0)
                           ? avgEntry + InpNegDCABEOffsetPip * Point * 10
                           : avgEntry - InpNegDCABEOffsetPip * Point * 10;
         bool atBreakeven = (g_dcaDirection > 0) ? (Bid >= beTarget) : (Ask <= beTarget);
         if(atBreakeven)
         {
            double basketPnL = CalculateBasketPnL();
            Print("[QuantEdge EA] EXIT: Negative DCA breakeven — avg=",
                  DoubleToString(avgEntry, Digits), " target=",
                  DoubleToString(beTarget, Digits), " basket P/L=",
                  DoubleToString(basketPnL, 2), ". Closing entire basket.");
            CloseNegDCABasket();
            return;
         }
      }
   }

   // --- Trigger Check (priority 2) ---
   double entryToSL = g_dcaOriginalSL - g_dcaOriginalEntry;
   double triggerPrice = g_dcaOriginalEntry + entryToSL * (InpNegDCATriggerPct / 100.0);

   if(!g_dcaNegTriggered)
   {
      bool triggered = (g_dcaDirection > 0) ? (Ask <= triggerPrice) : (Bid >= triggerPrice);
      if(!triggered)
         return;

      g_dcaNegTriggered    = true;
      g_dcaNegTriggerPrice = triggerPrice;
      SaveDCAState();
      Print("[QuantEdge EA] Negative DCA TRIGGERED at price ",
            DoubleToString((g_dcaDirection > 0 ? Ask : Bid), Digits),
            " (trigger level=", DoubleToString(triggerPrice, Digits), ")");
   }

   // --- Place orders (priority 3) ---
   double atr = iATR(Symbol(), 0, InpTrailATRPeriod, 0);
   double atrSpacing = atr * InpNegDCAATRMult;
   if(atrSpacing <= 0)
      return;

   double price = (g_dcaDirection > 0) ? Ask : Bid;

   for(int idx = 1; idx <= InpNegDCAMaxOrders; idx++)
   {
      int dcaMagic = InpMagicNumber + MAGIC_NEG_DCA_OFFSET + idx;

      bool exists = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != Symbol()) continue;
         if(OrderMagicNumber() == dcaMagic) { exists = true; break; }
      }
      if(exists) continue;

      double level = (g_dcaDirection > 0)
                      ? g_dcaNegTriggerPrice - (idx - 1) * atrSpacing
                      : g_dcaNegTriggerPrice + (idx - 1) * atrSpacing;

      bool triggered = (g_dcaDirection > 0) ? (price <= level) : (price >= level);
      if(!triggered) continue;

      if(!IsDCACooldownOK() || !IsDCASpacingOK(price))
         continue;

      double ratio   = NegDCALotRatio(idx);
      double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
      if(lotStep <= 0) continue;
      double minLot  = MathMax(MarketInfo(Symbol(), MODE_MINLOT), InpMinLotSize);
      double dcaLot  = MathFloor(g_dcaOriginalLot * ratio / lotStep) * lotStep;
      dcaLot = MathMax(dcaLot, minLot);
      dcaLot = MathMin(dcaLot, InpMaxLotSize);

      string comment = StringFormat("QE DCA-%d", idx);

      double dcaTP = g_dcaOriginalTP1;

      int ticket = -1;
      if(g_dcaDirection > 0)
         ticket = OrderSend(Symbol(), OP_BUY, dcaLot, Ask, InpSlippage, 0, dcaTP, comment, dcaMagic, 0, clrLime);
      else
         ticket = OrderSend(Symbol(), OP_SELL, dcaLot, Bid, InpSlippage, 0, dcaTP, comment, dcaMagic, 0, clrRed);

      if(ticket >= 0)
      {
         g_dcaLastOrderTime = TimeCurrent();
         SaveDCAState();
         Print("[QuantEdge EA] Negative DCA-", idx, " placed: ",
               (g_dcaDirection > 0 ? "BUY" : "SELL"), " ", DoubleToString(dcaLot, 2),
               " lot (", DoubleToString(ratio * 100, 0), "%), magic=", dcaMagic,
               " TP=", DoubleToString(dcaTP, Digits));
         break;
      }
      else
         Print("[QuantEdge EA] Negative DCA-", idx, " FAILED: error ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Main DCA management — called every tick, before bar guard        |
//+------------------------------------------------------------------+
void ManageDCA()
{
   if(!InpUsePositiveDCA && !InpUseNegativeDCA)
      return;

   if(g_dcaActive)
   {
      if(!HasAnyOriginalPosition() && !HasAnyDCAPosition())
      {
         Print("[QuantEdge EA] EXIT: All positions closed externally — resetting DCA state.");
         ClearDCAState();
         return;
      }
   }

   if(!g_dcaActive)
      return;

   // --- Basket-wide drawdown cap (priority 1, safety valve) ---
   // Runs regardless of which DCA mode(s) are enabled, so a
   // positive-DCA-only setup (no SL on any leg) still has a hard
   // loss limit. See CheckDrawdownCap().
   if(CheckDrawdownCap())
      return;

   // --- Broker-side backstop SL — keeps a hard SL in sync on every leg  ---
   // --- while the basket is open, as a safety net if the EA goes       ---
   // --- offline (VPS crash, disconnect, weekend gap). Does not replace ---
   // --- CheckDrawdownCap() above, which is the primary, exact cap.     ---
   ApplyDCABackstopSL();

   // --- Entry-return profit lock (priority 2): price back near the      ---
   // --- original entry AND basket still profitable — lock it in before  ---
   // --- further reversal erodes the gain.                               ---
   if(CheckEntryReturnProfitClose())
      return;

   // --- TP1 reached: close the entire basket — original + all DCA legs ---
   // (priority 3). g_dcaTP1HalfClosed doubles as a guard here: if
   // CloseEntireBasket() only partially fills (broker reject on one leg),
   // it stays false and this check retries next tick instead of ClearDCAState()
   // masking a stuck position.
   if(!g_dcaTP1HalfClosed && g_dcaOriginalTP1 > 0)
   {
      bool tp1Reached = (g_dcaDirection > 0) ? (Bid >= g_dcaOriginalTP1)
                                              : (Ask <= g_dcaOriginalTP1);
      if(tp1Reached)
      {
         double basketPnL2 = CalculateBasketPnL();
         Print("[QuantEdge EA] EXIT: TP1 REACHED — TP1=",
               DoubleToString(g_dcaOriginalTP1, Digits), " basket P/L=",
               DoubleToString(basketPnL2, 2), ". Closing entire basket.");
         CloseEntireBasket();
         ClearDCAState();
         return;
      }
   }

   ManagePositiveDCA();
   ManageNegativeDCA();
}

//+------------------------------------------------------------------+
//| Close panel — object drawing helpers                              |
//+------------------------------------------------------------------+
void QEEA_CreateRect(string name, int x, int y, int w, int h, color bg, color brd)
{
   if(ObjectFind(name) < 0)
   {
      ObjectCreate(name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(name, OBJPROP_SELECTABLE, false);
      ObjectSet(name, OBJPROP_HIDDEN, true);
      ObjectSet(name, OBJPROP_BACK, false);
   }
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSet(name, OBJPROP_XSIZE, w);
   ObjectSet(name, OBJPROP_YSIZE, h);
   ObjectSet(name, OBJPROP_BGCOLOR, bg);
   ObjectSet(name, OBJPROP_COLOR, brd);
   ObjectSet(name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet(name, OBJPROP_WIDTH, 1);
}

void QEEA_CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 9)
{
   if(ObjectFind(name) < 0)
   {
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(name, OBJPROP_SELECTABLE, false);
      ObjectSet(name, OBJPROP_HIDDEN, true);
      ObjectSet(name, OBJPROP_BACK, false);
   }
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSetText(name, text, fontSize, "Arial", clr);
}

void QEEA_CreateButton(string name, int x, int y, int w, int h, string text, color bg, color brd)
{
   if(ObjectFind(name) < 0)
   {
      ObjectCreate(name, OBJ_BUTTON, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(name, OBJPROP_HIDDEN, true);
      ObjectSet(name, OBJPROP_BACK, false);
      ObjectSet(name, OBJPROP_STATE, false);
   }
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSet(name, OBJPROP_XSIZE, w);
   ObjectSet(name, OBJPROP_YSIZE, h);
   ObjectSet(name, OBJPROP_BGCOLOR, bg);
   ObjectSet(name, OBJPROP_COLOR, brd);
   ObjectSetText(name, text, 9, "Arial", clrWhite);
}

//+------------------------------------------------------------------+
//| Close panel — position persistence (GlobalVariable)                |
//+------------------------------------------------------------------+
string QEEA_PanelGVName_X() { return "QE_EA_PanelX_" + Symbol() + "_" + IntegerToString(InpMagicNumber); }
string QEEA_PanelGVName_Y() { return "QE_EA_PanelY_" + Symbol() + "_" + IntegerToString(InpMagicNumber); }

void QEEA_SavePanelPosition()
{
   GlobalVariableSet(QEEA_PanelGVName_X(), g_panelPosX);
   GlobalVariableSet(QEEA_PanelGVName_Y(), g_panelPosY);
}

void QEEA_LoadPanelPosition()
{
   if(GlobalVariableCheck(QEEA_PanelGVName_X()))
      g_panelPosX = (int)GlobalVariableGet(QEEA_PanelGVName_X());
   if(GlobalVariableCheck(QEEA_PanelGVName_Y()))
      g_panelPosY = (int)GlobalVariableGet(QEEA_PanelGVName_Y());
}

//+------------------------------------------------------------------+
//| Close panel — draw / delete                                       |
//+------------------------------------------------------------------+
void QEEA_CreatePanel()
{
   if(!InpShowClosePanel)
   {
      QEEA_DeletePanel();
      return;
   }

   if(g_panelCollapsed)
   {
      ObjectDelete(QEEA_BG);
      ObjectDelete(QEEA_BTN_PROFIT_ALL);
      ObjectDelete(QEEA_BTN_LOSS_ALL);
      ObjectDelete(QEEA_BTN_BUY_PROFIT);
      ObjectDelete(QEEA_BTN_SELL_PROFIT);
      ObjectDelete(QEEA_BTN_CLOSE_ALL);

      QEEA_CreateRect(QEEA_HEADER, g_panelPosX, g_panelPosY, QEEA_PANEL_WIDTH, QEEA_HEADER_H, C'54,58,69', C'67,70,81');
      QEEA_CreateLabel(QEEA_HEADER_TXT, g_panelPosX + QEEA_PAD, g_panelPosY + 4, "QuantEdge EA [+]", clrSilver);
      ChartRedraw();
      return;
   }

   int panelH = QEEA_HEADER_H + QEEA_PAD * 2 + 5 * QEEA_BTN_H + 4 * QEEA_BTN_GAP;

   QEEA_CreateRect(QEEA_HEADER, g_panelPosX, g_panelPosY, QEEA_PANEL_WIDTH, QEEA_HEADER_H, C'54,58,69', C'67,70,81');
   QEEA_CreateLabel(QEEA_HEADER_TXT, g_panelPosX + QEEA_PAD, g_panelPosY + 4, ":::: QuantEdge EA [-]", clrSilver);

   QEEA_CreateRect(QEEA_BG, g_panelPosX, g_panelPosY + QEEA_HEADER_H, QEEA_PANEL_WIDTH, panelH - QEEA_HEADER_H, C'19,23,34', C'67,70,81');

   int btnX = g_panelPosX + QEEA_PAD;
   int btnW = QEEA_PANEL_WIDTH - QEEA_PAD * 2;
   int y0   = g_panelPosY + QEEA_HEADER_H + QEEA_PAD;

   QEEA_CreateButton(QEEA_BTN_PROFIT_ALL,  btnX, y0,                                       btnW, QEEA_BTN_H, "Close All Profit",  C'22,110,66', C'56,196,122');
   QEEA_CreateButton(QEEA_BTN_LOSS_ALL,    btnX, y0 + 1*(QEEA_BTN_H + QEEA_BTN_GAP),        btnW, QEEA_BTN_H, "Close All Loss",    C'120,40,46', C'214,84,92');
   QEEA_CreateButton(QEEA_BTN_BUY_PROFIT,  btnX, y0 + 2*(QEEA_BTN_H + QEEA_BTN_GAP),        btnW, QEEA_BTN_H, "Close Buy Profit",  C'20,92,158', C'64,158,232');
   QEEA_CreateButton(QEEA_BTN_SELL_PROFIT, btnX, y0 + 3*(QEEA_BTN_H + QEEA_BTN_GAP),        btnW, QEEA_BTN_H, "Close Sell Profit", C'20,92,158', C'64,158,232');
   QEEA_CreateButton(QEEA_BTN_CLOSE_ALL,   btnX, y0 + 4*(QEEA_BTN_H + QEEA_BTN_GAP),        btnW, QEEA_BTN_H, "CLOSE ALL",         C'168,32,32', C'232,72,72');

   ChartRedraw();
}

void QEEA_DeletePanel()
{
   ObjectDelete(QEEA_BG);
   ObjectDelete(QEEA_HEADER);
   ObjectDelete(QEEA_HEADER_TXT);
   ObjectDelete(QEEA_BTN_PROFIT_ALL);
   ObjectDelete(QEEA_BTN_LOSS_ALL);
   ObjectDelete(QEEA_BTN_BUY_PROFIT);
   ObjectDelete(QEEA_BTN_SELL_PROFIT);
   ObjectDelete(QEEA_BTN_CLOSE_ALL);
}

//+------------------------------------------------------------------+
//| Shared label/confirm/execute helpers — matching logic lives in    |
//| each dedicated close function below, not here.                   |
//+------------------------------------------------------------------+
string CloseCriteriaLabel(int criteria)
{
   switch(criteria)
   {
      case CRIT_ALL_PROFIT:  return "profitable position(s)";
      case CRIT_ALL_LOSS:    return "losing position(s)";
      case CRIT_BUY_PROFIT:  return "profitable BUY position(s)";
      case CRIT_SELL_PROFIT: return "profitable SELL position(s)";
      default:               return "position(s)";
   }
}

bool ConfirmClose(int criteria, int count, double totalProfit)
{
   string msg = StringFormat("Close %d %s on %s?\nTotal P/L: %s%.2f USD\n\nThis action cannot be undone.",
                              count, CloseCriteriaLabel(criteria), Symbol(),
                              (totalProfit >= 0 ? "+" : ""), totalProfit);
   int result = MessageBox(msg, "QuantEdge EA", MB_OKCANCEL | MB_ICONQUESTION);
   if(result != IDOK)
   {
      Print("[QuantEdge EA] Close panel: user cancelled criteria=", criteria);
      return false;
   }
   return true;
}

void ExecuteClose(int &tickets[], int count)
{
   for(int j = 0; j < count; j++)
   {
      if(!OrderSelect(tickets[j], SELECT_BY_TICKET))
      {
         Print("[QuantEdge EA] Failed to select ticket=", tickets[j], " for closing");
         continue;
      }

      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      if(OrderClose(tickets[j], OrderLots(), closePrice, InpSlippage, clrRed))
         Print("[QuantEdge EA] Closed ticket=", tickets[j]);
      else
         Print("[QuantEdge EA] Failed to close ticket=", tickets[j], ": error ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Close ALL profitable positions (Buy + Sell), any magic number.    |
//| confirm=true shows MessageBox (EA's own panel button); confirm=   |
//| false skips it (indicator's Manual panel already confirmed).     |
//+------------------------------------------------------------------+
void CloseAllProfit(bool confirm = true)
{
   int    tickets[];
   double totalProfit = 0;
   int    count = 0;
   ArrayResize(tickets, OrdersTotal());

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit > 0)
      {
         tickets[count] = OrderTicket();
         totalProfit += profit;
         count++;
      }
   }

   if(count == 0) { Print("[QuantEdge EA] Close panel: no matching positions for CloseAllProfit"); return; }
   if(confirm && !ConfirmClose(CRIT_ALL_PROFIT, count, totalProfit)) return;

   Print("[QuantEdge EA] CloseAllProfit: closing ", count, " position(s), total P/L=", DoubleToString(totalProfit, 2));
   ExecuteClose(tickets, count);
}

//+------------------------------------------------------------------+
//| Close ALL losing positions (Buy + Sell), any magic number.        |
//+------------------------------------------------------------------+
void CloseAllLoss(bool confirm = true)
{
   int    tickets[];
   double totalProfit = 0;
   int    count = 0;
   ArrayResize(tickets, OrdersTotal());

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit < 0)
      {
         tickets[count] = OrderTicket();
         totalProfit += profit;
         count++;
      }
   }

   if(count == 0) { Print("[QuantEdge EA] Close panel: no matching positions for CloseAllLoss"); return; }
   if(confirm && !ConfirmClose(CRIT_ALL_LOSS, count, totalProfit)) return;

   Print("[QuantEdge EA] CloseAllLoss: closing ", count, " position(s), total P/L=", DoubleToString(totalProfit, 2));
   ExecuteClose(tickets, count);
}

//+------------------------------------------------------------------+
//| Close profitable BUY positions only, any magic number.            |
//+------------------------------------------------------------------+
void CloseBuyProfit(bool confirm = true)
{
   int    tickets[];
   double totalProfit = 0;
   int    count = 0;
   ArrayResize(tickets, OrdersTotal());

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(OrderType() == OP_BUY && profit > 0)
      {
         tickets[count] = OrderTicket();
         totalProfit += profit;
         count++;
      }
   }

   if(count == 0) { Print("[QuantEdge EA] Close panel: no matching positions for CloseBuyProfit"); return; }
   if(confirm && !ConfirmClose(CRIT_BUY_PROFIT, count, totalProfit)) return;

   Print("[QuantEdge EA] CloseBuyProfit: closing ", count, " position(s), total P/L=", DoubleToString(totalProfit, 2));
   ExecuteClose(tickets, count);
}

//+------------------------------------------------------------------+
//| Close profitable SELL positions only, any magic number.           |
//+------------------------------------------------------------------+
void CloseSellProfit(bool confirm = true)
{
   int    tickets[];
   double totalProfit = 0;
   int    count = 0;
   ArrayResize(tickets, OrdersTotal());

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(OrderType() == OP_SELL && profit > 0)
      {
         tickets[count] = OrderTicket();
         totalProfit += profit;
         count++;
      }
   }

   if(count == 0) { Print("[QuantEdge EA] Close panel: no matching positions for CloseSellProfit"); return; }
   if(confirm && !ConfirmClose(CRIT_SELL_PROFIT, count, totalProfit)) return;

   Print("[QuantEdge EA] CloseSellProfit: closing ", count, " position(s), total P/L=", DoubleToString(totalProfit, 2));
   ExecuteClose(tickets, count);
}

//+------------------------------------------------------------------+
//| Close ALL positions regardless of P/L, any magic number.          |
//+------------------------------------------------------------------+
void CloseAllPositions(bool confirm = true)
{
   int    tickets[];
   double totalProfit = 0;
   int    count = 0;
   ArrayResize(tickets, OrdersTotal());

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      tickets[count] = OrderTicket();
      totalProfit += profit;
      count++;
   }

   if(count == 0) { Print("[QuantEdge EA] Close panel: no matching positions for CloseAllPositions"); return; }
   if(confirm && !ConfirmClose(CRIT_CLOSE_ALL, count, totalProfit)) return;

   Print("[QuantEdge EA] CloseAllPositions: closing ", count, " position(s), total P/L=", DoubleToString(totalProfit, 2));
   ExecuteClose(tickets, count);
}

//+------------------------------------------------------------------+
//| Dispatch by criteria ordinal — used by the indicator GlobalVariable|
//| poll (see OnTick()) so criteria->fn mapping lives in one place.   |
//+------------------------------------------------------------------+
void ClosePositionsByCriteria(int criteria, bool confirm = true)
{
   switch(criteria)
   {
      case CRIT_ALL_PROFIT:  CloseAllProfit(confirm);  break;
      case CRIT_ALL_LOSS:    CloseAllLoss(confirm);    break;
      case CRIT_BUY_PROFIT:  CloseBuyProfit(confirm);  break;
      case CRIT_SELL_PROFIT: CloseSellProfit(confirm); break;
      case CRIT_CLOSE_ALL:   CloseAllPositions(confirm); break;
      default: Print("[QuantEdge EA] ClosePositionsByCriteria: unknown criteria=", criteria); break;
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[QuantEdge EA] Build=", EA_BUILD_TAG);
   QEEA_CleanupOrphanedIndicatorObjects();

   double testRead = ReadBuffer(BUF_REC_LEVEL);
   if(GetLastError() == ERR_INDICATOR_CANNOT_LOAD)
   {
      Print("[QuantEdge EA] ERROR: Cannot load indicator '", InpIndicatorName, "'. Check .ex4 exists.");
      return INIT_FAILED;
   }

   // Pass Brier settings to indicator via GlobalVariable
   GlobalVariableSet("QE_BrierMinN_"  + Symbol(), (double)Ind_BrierMinSamples);
   GlobalVariableSet("QE_BrierFloor_" + Symbol(), Ind_BrierFloorShrink);

   Print("[QuantEdge EA] === SETTINGS DUMP ===");
   Print("[QuantEdge EA] AutoTrading=", InpEnableAutoTrading, " Magic=", InpMagicNumber);
   Print("[QuantEdge EA] MinRecLevel=", InpMinRecLevel, " AllowCaution=", InpAllowCaution,
         " MinConfidence=", InpMinConfidence, " MaxSurvivalFloor=", InpMaxSurvivalFloor,
         " MaxSpread=", InpMaxSpreadPoints, " MaxSpreadPctOfTP1=", InpMaxSpreadPctOfTP1);
   Print("[QuantEdge EA] SignalRetry=", InpUseSignalRetry, " RetryMaxBars=", InpRetryMaxBars,
         " InvalidateOnTP1=", InpInvalidateOnTP1);
   Print("[QuantEdge EA] Gate10=", InpUseGate10PriceLoc,
         " PriceLocSLSide=", InpUsePriceLocSLSide, " PriceLocTPSide=", InpUsePriceLocTPSide,
         " MaxPct=", InpPriceLocMaxPct, " MaxProbSL=", InpPriceLocMaxProbSL);
   Print("[QuantEdge EA] Gate11EV=", InpUseGate11EV, " MinEV=", InpMinEV,
         " Gate12FillRR=", InpUseGate12FillRR, " MinFillRR=", InpMinFillRR,
         " StructuralSLTP=", InpUseStructuralSLTP);
   Print("[QuantEdge EA] SessionFilter=", InpUseSessionFilter, " DailyLossCap=", InpUseDailyLossCap);
   Print("[QuantEdge EA] TPMode=", EnumToString(InpTPMode),
         " TP1Ratio=", InpTP1LotRatio,
         " Trailing=", InpUseTrailing);
   Print("[QuantEdge EA] PositiveDCA=", InpUsePositiveDCA, " PosDCA_ATR=", InpPosDCAATRMult,
         " NegativeDCA=", InpUseNegativeDCA, " NegDCA_ATR=", InpNegDCAATRMult);
   Print("[QuantEdge EA] ===================");

   if(!InpEnableAutoTrading)
   {
      Print("[QuantEdge EA] *** WARNING: AutoTrading=OFF — no orders will be placed! Set InpEnableAutoTrading=true ***");
      Comment("QuantEdge EA: AutoTrading OFF — no orders placed");
   }
   else
      Print("[QuantEdge EA] LIVE MODE — auto-trading enabled.");

   // [GATE9-WARN] Gate 9 reads a GlobalVariable that the INDICATOR only
   // publishes when its own InpUseEconCalendar is on — and that input ships
   // off (Config.mqh). With the GV absent the EA's GlobalVariableCheck fails
   // and g9_pass stays true, so enabling the gate here alone silently does
   // nothing while looking like active protection. Say so once at startup.
   if(InpUseEconCalGate && !GlobalVariableCheck("QE_EconBlackout_" + Symbol()))
      Print("[QuantEdge EA] *** WARNING: Gate 9 enabled but GV 'QE_EconBlackout_",
            Symbol(), "' is missing — the gate will pass everything. ",
            "Enable InpUseEconCalendar on the indicator to make it effective. ***");

   QEEA_LoadPanelPosition();
   QEEA_CreatePanel();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   // Restore DCA state (survives EA reload / chart change / terminal restart)
   LoadDCAState();
   if(g_dcaActive)
      Print("[QuantEdge EA] DCA state restored: dir=", (g_dcaDirection > 0 ? "BUY" : "SELL"),
            " entry=", DoubleToString(g_dcaOriginalEntry, Digits),
            " refSL=", DoubleToString(g_dcaOriginalSL, Digits),
            " TP1=", DoubleToString(g_dcaOriginalTP1, Digits));

   LoadRecoveryState();
   LoadLastTradedSigTime();
   if(g_lastTradedSigTime != 0)
      Print("[QuantEdge EA] Last traded signal bar restored: ",
            TimeToString(g_lastTradedSigTime), " (will not be re-armed)");

   // [ARROW-FIX] Rebuild the arrow history, independently of the trade-arming
   // scan below. See RedrawSignalArrows(). May be a no-op here if the
   // indicator has not calculated yet; OnTick retries until it succeeds.
   g_arrowSweepDone = RedrawSignalArrows();

   // Scan for existing active signal on startup (within RetryMaxBars)
   if(!InpUseSignalRetry)
      Print("[QuantEdge EA] Startup: signal scan skipped — InpUseSignalRetry=false.");
   else if(HasOpenPosition(1) || HasOpenPosition(-1))
      Print("[QuantEdge EA] Startup: signal scan skipped — a position with our magic is already open on this symbol.");
   else
   {
      int scanLimit = (InpRetryMaxBars > 0) ? InpRetryMaxBars : 5;
      bool foundAtStartup = false;

      // 1. Try GV bridge
      double buyCase = EMPTY_VALUE, sellCase = EMPTY_VALUE;
      int    gvShift = -1;
      double gvEntry = EMPTY_VALUE, gvSL = EMPTY_VALUE;
      double gvTP1 = EMPTY_VALUE, gvTP2 = EMPTY_VALUE, gvTP3 = EMPTY_VALUE;
      double gvRecLv = EMPTY_VALUE, gvConf = EMPTY_VALUE;
      double gvEV = EMPTY_VALUE, gvRisk = EMPTY_VALUE, gvProbTP1 = EMPTY_VALUE;

      if(!IsTesting() &&
         ReadSignalFromGV(buyCase, sellCase, gvShift,
                          gvEntry, gvSL, gvTP1, gvTP2, gvTP3,
                          gvRecLv, gvConf, gvEV, gvRisk, gvProbTP1) &&
         !IsSignalAlreadyTraded(iTime(Symbol(), Period(), gvShift)))
      {
         foundAtStartup = true;
         bool hasBuy  = (buyCase  != EMPTY_VALUE && buyCase  > 0);
         int  direction = hasBuy ? 1 : -1;
         int  caseNum   = (int)(hasBuy ? buyCase : sellCase);
         double recLevel   = (gvRecLv != EMPTY_VALUE) ? gvRecLv : (double)REC_WAIT;
         double confidence = (gvConf  != EMPTY_VALUE) ? gvConf  : 0;

         g_sigValid      = true;
         g_sigTP1Hit     = false;
         g_sigSLHit      = false;
         g_sigDirection  = direction;
         g_sigCaseNum    = caseNum;
         g_sigEntry      = (gvEntry != EMPTY_VALUE) ? gvEntry : ((direction > 0) ? Ask : Bid);
         g_sigSL         = (gvSL    != EMPTY_VALUE) ? gvSL    : 0;
         g_sigTP1        = (gvTP1   != EMPTY_VALUE) ? gvTP1   : 0;
         g_sigTP2        = (gvTP2   != EMPTY_VALUE) ? gvTP2   : 0;
         g_sigTP3        = (gvTP3   != EMPTY_VALUE) ? gvTP3   : 0;
         g_sigRecLevel   = recLevel;
         g_sigConfidence = confidence;
         g_sigEV         = (gvEV      != EMPTY_VALUE) ? gvEV      : 0;
         g_sigRiskPct    = (gvRisk    != EMPTY_VALUE) ? gvRisk    : 0;
         g_sigProbTP1    = (gvProbTP1 != EMPTY_VALUE) ? gvProbTP1 : 0;
         g_lastBarTime   = iTime(Symbol(), Period(), gvShift);
         g_sigBarTime    = iTime(Symbol(), Period(), gvShift);

         double arrowPrice = (direction > 0) ? iLow(Symbol(), Period(), gvShift)
                                             : iHigh(Symbol(), Period(), gvShift);
         DrawSignalArrow(iTime(Symbol(), Period(), gvShift), arrowPrice, direction > 0, caseNum);

         Print("[QuantEdge EA] Startup: found active signal via GV bridge at bar[", gvShift, "] — ",
               (direction > 0 ? "BUY" : "SELL"), " Case=", caseNum,
               " Conf=", (int)MathRound(confidence), " EV=", DoubleToString(g_sigEV, 2), "R");
      }

      // 2. Fallback: iCustom buffer scan
      if(!foundAtStartup)
      {
         for(int i = 1; i <= scanLimit; i++)
         {
            buyCase  = ReadBufferAt(BUF_BUY_SIGNAL, i);
            sellCase = ReadBufferAt(BUF_SELL_SIGNAL, i);
            bool hasBuy  = (buyCase  != EMPTY_VALUE && buyCase  > 0);
            bool hasSell = (sellCase != EMPTY_VALUE && sellCase > 0);
            if(!hasBuy && !hasSell) continue;
            // [REARM-FIX] Skip a bar we have already traded — keep scanning
            // back in case an older, untraded signal is still in the window.
            if(IsSignalAlreadyTraded(iTime(Symbol(), Period(), i))) continue;
            foundAtStartup = true;

            double recLevel   = ReadBufferAt(BUF_REC_LEVEL, i);
            double confidence = ReadBufferAt(BUF_REC_CONFIDENCE, i);
            if(recLevel == EMPTY_VALUE)   recLevel   = (double)REC_WAIT;
            if(confidence == EMPTY_VALUE) confidence = 0;

            int    direction = hasBuy ? 1 : -1;
            int    caseNum   = (int)(hasBuy ? buyCase : sellCase);
            g_sigValid      = true;
            g_sigTP1Hit     = false;
            g_sigSLHit      = false;
            g_sigDirection  = direction;
            g_sigCaseNum    = caseNum;
            g_sigEntry      = ReadBufferAt(BUF_ENTRY, i);
            g_sigSL         = ReadBufferAt(BUF_SL, i);
            g_sigTP1        = ReadBufferAt(BUF_TP1, i);
            g_sigTP2        = ReadBufferAt(BUF_TP2, i);
            g_sigTP3        = ReadBufferAt(BUF_TP3, i);
            g_sigRecLevel   = recLevel;
            g_sigConfidence = confidence;
            g_sigEV         = ReadBufferAt(BUF_REC_EV, i);
            g_sigRiskPct    = ReadBufferAt(BUF_REC_RISK, i);
            g_sigProbTP1    = ReadBufferAt(BUF_PROB_TP1, i);
            g_lastBarTime   = iTime(Symbol(), Period(), i);
            g_sigBarTime    = iTime(Symbol(), Period(), i);

            double arrowPrice = (direction > 0) ? iLow(Symbol(), Period(), i)
                                                : iHigh(Symbol(), Period(), i);
            DrawSignalArrow(iTime(Symbol(), Period(), i), arrowPrice, direction > 0, caseNum);

            Print("[QuantEdge EA] Startup: found active signal via iCustom at bar[", i, "] — ",
                  (direction > 0 ? "BUY" : "SELL"), " Case=", caseNum,
                  " Conf=", (int)MathRound(confidence), " EV=", DoubleToString(g_sigEV, 2), "R");
            break;
         }
      }
      if(!foundAtStartup)
         Print("[QuantEdge EA] Startup: no active signal within shift 1..", scanLimit,
               " (indicator dashboard may show an older signal outside this scan window — "
               "see InpRetryMaxBars).");
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Signal arrow drawing — EA draws arrows so indicator can run in    |
//| headless iCustom mode (InpEAMode=true) without visual overhead.   |
//+------------------------------------------------------------------+
#define EA_ARROW_PREFIX  "QEEA_Arr_"

void DrawSignalArrow(datetime barTime, double price, bool isBuy, int caseNum)
{
   if(!InpShowSignalArrows) return;

   string name = EA_ARROW_PREFIX + (isBuy ? "B_" : "S_")
               + IntegerToString(caseNum) + "_"
               + IntegerToString((int)barTime);
   if(ObjectFind(name) >= 0) return;

   double offset = InpArrowOffsetPts * Point;

   if(isBuy)
   {
      ObjectCreate(name, OBJ_ARROW, 0, barTime, price - offset);
      ObjectSet(name, OBJPROP_ARROWCODE, 233);
      ObjectSet(name, OBJPROP_COLOR, InpBuyArrowColor);
   }
   else
   {
      ObjectCreate(name, OBJ_ARROW, 0, barTime, price + offset);
      ObjectSet(name, OBJPROP_ARROWCODE, 234);
      ObjectSet(name, OBJPROP_COLOR, InpSellArrowColor);
   }
   ObjectSet(name, OBJPROP_WIDTH, InpArrowSize);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
   ObjectSet(name, OBJPROP_HIDDEN, false);
}

//+------------------------------------------------------------------+
//| [ARROW-FIX] Rebuild the whole visible arrow history from the      |
//| indicator's signal buffers.                                       |
//|                                                                   |
//| With InpEAMode=true the indicator suppresses its own visuals, so  |
//| the EA owns these markers entirely. They used to be drawn only at |
//| the points where a signal gets ARMED for trading, which is the    |
//| wrong trigger for a chart annotation: the arming scan stops at the|
//| first tradable signal, skips bars already traded, and is gated on |
//| InpUseSignalRetry and on there being no open position. Any signal |
//| that fell outside those conditions was never marked, so the chart |
//| looked as though no signal had ever occurred there.               |
//|                                                                   |
//| Returns true once it has seen readable buffer data, so the caller |
//| can retry while the indicator is still warming up. DrawSignalArrow|
//| de-dupes by object name, so repeat passes are cheap and harmless. |
//+------------------------------------------------------------------+
bool RedrawSignalArrows()
{
   if(!InpShowSignalArrows) return true;

   int scanBars = MathMax(InpRetryMaxBars, 200);
   int avail    = iBars(Symbol(), Period()) - 1;
   if(avail < 1) return false;
   if(scanBars > avail) scanBars = avail;

   // Readiness probe. The signal buffers hold EMPTY_VALUE on every bar
   // WITHOUT a signal, which is indistinguishable from a failed read — so
   // they cannot tell us whether the indicator has calculated yet. The RSI
   // fast line carries a value on every bar, so use that as the probe and
   // bail out (caller retries) while it is still empty.
   if(ReadBufferAt(BUF_RSI_FAST, 1) == EMPTY_VALUE)
      return false;

   int  drawn = 0;

   for(int a = 1; a <= scanBars; a++)
   {
      double abc = ReadBufferAt(BUF_BUY_SIGNAL, a);
      double asc = ReadBufferAt(BUF_SELL_SIGNAL, a);

      bool aHasBuy  = (abc != EMPTY_VALUE && abc > 0);
      bool aHasSell = (asc != EMPTY_VALUE && asc > 0);
      if(!aHasBuy && !aHasSell) continue;

      int    aDir   = aHasBuy ? 1 : -1;
      int    aCase  = (int)(aHasBuy ? abc : asc);
      double aPrice = (aDir > 0) ? iLow(Symbol(), Period(), a)
                                 : iHigh(Symbol(), Period(), a);
      DrawSignalArrow(iTime(Symbol(), Period(), a), aPrice, aDir > 0, aCase);
      drawn++;
   }

   if(drawn > 0)
      Print("[QuantEdge EA] Redrew ", drawn, " signal arrow(s) within shift 1..", scanBars);

   return true;
}

void CleanupSignalArrows()
{
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, EA_ARROW_PREFIX) == 0)
         ObjectDelete(name);
   }
}

//+------------------------------------------------------------------+
//| Check if the cached signal is still valid (price hasn't hit SL,   |
//| survival not expired, within max retry bars).                      |
//+------------------------------------------------------------------+
bool IsSignalStillValid()
{
   if(!g_sigValid)
      return false;

   double mktNow = (g_sigDirection > 0) ? Bid : Ask;

   // Track SL hit — invalidates signal entirely
   bool slHit = (g_sigDirection > 0) ? (mktNow <= g_sigSL) : (mktNow >= g_sigSL);
   if(slHit)
   {
      Print("[QuantEdge EA] Retry: signal invalidated — price hit SL (",
            DoubleToString(g_sigSL, Digits), ")");
      g_sigValid = false;
      g_sigSLHit = true;
      return false;
   }

   // [TP1-FIX] Track TP1 hit. This used to only raise a flag and still
   // return true — and the flag was read ONLY inside Gate 10, which ships
   // disabled. The net effect was that a signal whose whole Entry->TP1 move
   // had already played out stayed eligible, so the EA entered at market
   // right as the momentum was spent, then pushed TP1 further out again.
   // Invalidate outright instead; the flag is kept for Gate 10's logging.
   if(!g_sigTP1Hit && g_sigTP1 > 0)
   {
      bool tp1Hit = (g_sigDirection > 0) ? (mktNow >= g_sigTP1) : (mktNow <= g_sigTP1);
      if(tp1Hit)
      {
         g_sigTP1Hit = true;
         if(InpInvalidateOnTP1)
         {
            Print("[QuantEdge EA] Retry: signal invalidated — TP1 reached (",
                  DoubleToString(g_sigTP1, Digits), ") before entry");
            g_sigValid = false;
            return false;
         }
         Print("[QuantEdge EA] Retry: TP1 reached (",
               DoubleToString(g_sigTP1, Digits), ") — TP-side entry disabled");
      }
   }

   if(InpUseGate3Staleness)
   {
      double survival = ReadSignalBuffer(BUF_PROB_SURVIVAL);
      if(survival != EMPTY_VALUE && survival < InpMaxSurvivalFloor)
      {
         Print("[QuantEdge EA] Retry: signal invalidated — survival expired (",
               DoubleToString(survival, 3), " < ", DoubleToString(InpMaxSurvivalFloor, 3), ")");
         g_sigValid = false;
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Run all gates and place order if passed. Returns true if order     |
//| was placed (signal consumed).                                      |
//| isRetry: true when called from tick-level retry (suppresses log   |
//| spam — only logs on state changes, not every tick).                |
//+------------------------------------------------------------------+
bool TryExecuteSignal(bool isRetry)
{
   int    direction  = g_sigDirection;
   int    caseNum    = g_sigCaseNum;
   double entry      = g_sigEntry;
   double sl         = g_sigSL;
   double tp1        = g_sigTP1;
   double tp2        = g_sigTP2;
   double tp3        = g_sigTP3;
   int    recLevelInt= (int)MathRound(g_sigRecLevel);
   double confidence = g_sigConfidence;
   double ev         = g_sigEV;
   double riskPct    = g_sigRiskPct;
   double probTP1    = g_sigProbTP1;

   // --- Opposite-signal basket close ---
   if(!isRetry && g_dcaActive && direction != g_dcaDirection)
   {
      double basketPnL = CalculateBasketPnL();
      if(basketPnL > 0)
      {
         Print("[QuantEdge EA] Opposite-direction signal (new=", (direction > 0 ? "BUY" : "SELL"),
               ", basket=", (g_dcaDirection > 0 ? "BUY" : "SELL"), "), basket P/L=",
               DoubleToString(basketPnL, 2), " > 0. CLOSING ENTIRE BASKET.");
         CloseEntireBasket();
         ClearDCAState();
      }
      else
      {
         Print("[QuantEdge EA] Opposite-direction signal ignored — basket P/L=",
               DoubleToString(basketPnL, 2), " <= 0, keeping basket open.");
      }
   }

   // --- Validate signal data (reject garbage from indicator buffers) ---
   {
      double stopLevelPts = MarketInfo(Symbol(), MODE_STOPLEVEL);
      double minTPDist = MathMax(stopLevelPts * Point, 100 * Point);

      bool tpInvalid = (tp1 <= 0)
                     || (MathAbs(tp1 - entry) < minTPDist)
                     || (direction > 0 && tp1 <= entry)
                     || (direction < 0 && tp1 >= entry);

      bool slGarbage = (sl > 0 && MathAbs(sl - entry) / entry > 0.20);

      if(tpInvalid || slGarbage)
      {
         if(!isRetry)
            Print("[QuantEdge EA] Signal data not ready: entry=", DoubleToString(entry, Digits),
                  " SL=", DoubleToString(sl, Digits),
                  " TP1=", DoubleToString(tp1, Digits),
                  " (TP dist=", DoubleToString(MathAbs(tp1 - entry) / Point, 0), " pts",
                  " min=", DoubleToString(minTPDist / Point, 0), " pts)",
                  tpInvalid ? " [TP invalid]" : "",
                  slGarbage ? " [SL garbage]" : "",
                  " — will retry.");
         if(tpInvalid) g_sigTP1 = 0;
         if(slGarbage) g_sigSL  = 0;
         return false;
      }
   }

   // --- Gate 1: Recommendation Level ---
   bool g1_pass = true;
   if(InpUseGate1RecLevel && InpMinRecLevel != REC_ANY)
   {
      g1_pass = false;
      if(recLevelInt <= InpMinRecLevel)
         g1_pass = true;
      if(recLevelInt == REC_CAUTION_ENTRY && InpAllowCaution)
         g1_pass = true;
   }

   // --- Gate 2: Confidence ---
   bool g2_pass = !InpUseGate2Confidence || ((int)MathRound(confidence) >= InpMinConfidence);

   // --- Gate 3: Staleness (re-read live survival for retry) ---
   // [GATE3-FIX] Read at the signal's own bar — see ReadSignalBuffer().
   bool g3_pass = true;
   double survival = ReadSignalBuffer(BUF_PROB_SURVIVAL);
   if(InpUseGate3Staleness && survival != EMPTY_VALUE && survival < InpMaxSurvivalFloor)
      g3_pass = false;

   // --- Gate 4: No Duplicate Position ---
   bool g4_pass = !HasOpenPosition(direction) && !g_dcaActive;
   if(!isRetry && g_dcaActive && !HasOpenPosition(direction))
      Print("[QuantEdge EA] Gate 4 blocked: DCA basket active (dir=",
            (g_dcaDirection > 0 ? "BUY" : "SELL"),
            ") — waiting for basket to close before accepting new signal.");

   // --- Gate 5: Spread (absolute points and/or % of the TP1 target) ---
   // A fixed point cap says nothing about whether the spread is affordable:
   // on M15 XAUUSD TP1 is roughly ATR*0.8 (~$6.4), so a $0.30-$0.80 rollover
   // spread eats 5-12% of the target before slippage. The percentage check
   // scales itself with ATR, so it does not need re-tuning per volatility
   // regime the way the absolute cap does.
   bool g5_pass = true;
   if(InpUseGate5Spread)
   {
      double spreadPts = MarketInfo(Symbol(), MODE_SPREAD);

      if(InpMaxSpreadPoints > 0 && spreadPts > InpMaxSpreadPoints)
      {
         g5_pass = false;
         if(!isRetry)
            Print("[QuantEdge EA] Gate 5 FAIL (absolute): spread=", DoubleToString(spreadPts, 0),
                  " pts > ", InpMaxSpreadPoints, " pts");
      }

      double tp1DistG5 = MathAbs(tp1 - entry);
      if(g5_pass && InpMaxSpreadPctOfTP1 > 0 && tp1DistG5 > 0)
      {
         double spreadPct = (spreadPts * Point) / tp1DistG5 * 100.0;
         if(spreadPct > InpMaxSpreadPctOfTP1)
         {
            g5_pass = false;
            if(!isRetry)
               Print("[QuantEdge EA] Gate 5 FAIL (relative): spread=", DoubleToString(spreadPct, 1),
                     "% of Entry->TP1 > ", DoubleToString(InpMaxSpreadPctOfTP1, 1), "%");
         }
      }
   }

   // --- Gate 6: Session Filter ---
   bool g6_pass = IsWithinSession();

   // --- Gate 7: Daily / Weekly / Monthly Loss Cap ---
   bool g7_pass = !IsDailyLossCapHit() && !IsWeeklyDDStopHit() && !IsMonthlyDDStopHit();

   // --- Gate 8: ADX Trend Strength ---
   bool g8_pass = true;
   if(InpUseADXGate)
   {
      string adxGateVar = "QE_ADXGatePassed_" + Symbol();
      if(GlobalVariableCheck(adxGateVar))
         g8_pass = (GlobalVariableGet(adxGateVar) != 0.0);
   }

   // --- Gate 9: Economic Calendar Blackout ---
   bool g9_pass = true;
   if(InpUseEconCalGate)
   {
      string econGateVar = "QE_EconBlackout_" + Symbol();
      if(GlobalVariableCheck(econGateVar))
         g9_pass = (GlobalVariableGet(econGateVar) == 0.0);
   }

   // --- Gate 10: Price Location ---
   bool g10_pass = true;
   if(InpUseGate10PriceLoc)
   {
      double mktNow   = (direction > 0) ? Ask : Bid;
      // [PROBSL-FIX] Read the indicator's own P(SL) instead of deriving it as
      // 100 - P(TP1). Those are not complements: price can drift between the
      // two levels and expire without touching either, so the old expression
      // systematically overstated the SL risk and mis-scored this gate.
      double probSLBuf = ReadSignalBuffer(BUF_PROB_SL);
      double probSL   = (probSLBuf != EMPTY_VALUE && probSLBuf >= 0) ? probSLBuf
                        : ((probTP1 != EMPTY_VALUE) ? (100.0 - probTP1) : 100.0);
      double distES   = MathAbs(entry - sl);
      double distET   = MathAbs(tp1 - entry);

      bool priceBetweenSLEntry = false;
      bool priceBetweenEntryTP = false;

      if(direction > 0)
      {
         priceBetweenSLEntry = (mktNow < entry && mktNow > sl);
         priceBetweenEntryTP = (mktNow > entry && mktNow < tp1);
      }
      else
      {
         priceBetweenSLEntry = (mktNow > entry && mktNow < sl);
         priceBetweenEntryTP = (mktNow < entry && mktNow > tp1);
      }

      if(priceBetweenSLEntry)
      {
         if(InpUsePriceLocSLSide && !g_sigSLHit)
         {
            double driftFromEntry = MathAbs(mktNow - entry);
            double driftPct = (distES > 0) ? (driftFromEntry / distES * 100.0) : 100.0;
            g10_pass = (probSL < InpPriceLocMaxProbSL && driftPct <= InpPriceLocMaxPct);
            if(!g10_pass && !isRetry)
               Print("[QuantEdge EA] Gate 10 FAIL (SL-side): probSL=", DoubleToString(probSL, 1),
                     "% drift=", DoubleToString(driftPct, 1), "% of Entry→SL");
         }
         else
         {
            g10_pass = false;
            if(g_sigSLHit && !isRetry)
               Print("[QuantEdge EA] Gate 10 FAIL: SL was already hit — SL-side entry disabled");
         }
      }
      else if(priceBetweenEntryTP)
      {
         if(InpUsePriceLocTPSide && !g_sigTP1Hit)
         {
            double driftFromEntry = MathAbs(mktNow - entry);
            double driftPct = (distET > 0) ? (driftFromEntry / distET * 100.0) : 100.0;
            g10_pass = (probSL < InpPriceLocMaxProbSL && driftPct <= InpPriceLocMaxPct);
            if(!g10_pass && !isRetry)
               Print("[QuantEdge EA] Gate 10 FAIL (TP-side): probSL=", DoubleToString(probSL, 1),
                     "% drift=", DoubleToString(driftPct, 1), "% of Entry→TP1");
         }
         else
         {
            g10_pass = false;
            if(g_sigTP1Hit && !isRetry)
               Print("[QuantEdge EA] Gate 10 FAIL: TP1 was already hit — TP-side entry disabled");
         }
      }
      else
      {
         // [GATE10-FIX] Price is OUTSIDE the SL..TP1 band entirely — it has
         // either blown through SL or run past TP1. Both branches above are
         // false there, and without this else the gate kept its initial
         // "pass", so the one filter meant to reject distant entries let
         // through the most distant case of all.
         g10_pass = false;
         if(!isRetry)
            Print("[QuantEdge EA] Gate 10 FAIL (outside SL-TP1 band): market=",
                  DoubleToString(mktNow, Digits),
                  " SL=", DoubleToString(sl, Digits),
                  " Entry=", DoubleToString(entry, Digits),
                  " TP1=", DoubleToString(tp1, Digits));
      }
   }

   // --- Gate 11: Expected Value ---
   // The indicator computes EV per signal and the EA used to merely print it.
   // Strict '<' so an EV of exactly 0 coming from the buffer-fallback path
   // (see the buffersIncomplete block in OnTick) is not rejected as if the
   // indicator had actually scored it at zero.
   bool g11_pass = true;
   if(InpUseGate11EV && ev != EMPTY_VALUE && ev < InpMinEV)
   {
      g11_pass = false;
      if(!isRetry)
         Print("[QuantEdge EA] Gate 11 FAIL: EV=", DoubleToString(ev, 2),
               "R < min ", DoubleToString(InpMinEV, 2), "R");
   }

   //--- Resolve the SL/TP prices we would actually send ----------------
   // [SLTP-STRUCT-FIX] Hoisted above the gate aggregation because Gate 12
   // scores the R:R that remains at the real fill price, which needs the
   // final SL.
   //
   // The old code shifted the whole SL/TP block by (market - entry) so the
   // R distance stayed constant. But SL is not an arbitrary offset: it comes
   // from an actual swing level (SLTP.mqh CalculateSLTP_*). Sliding it along
   // with price lifts it off that structure, and after a few bars of retry
   // the stop sits inside ordinary noise instead of below the swing that
   // justified it. That shift also carried a systematic bias — BUY measured
   // from Ask while the published entry is bid-based, so every BUY had a
   // full spread added to its stop distance and none of the SELLs did.
   //
   // Keep the structural prices and let the lot size absorb the drift
   // instead: entering later means a wider stop, hence a smaller position,
   // so the risk actually taken matches the risk on paper.
   double marketPrice = (direction > 0) ? Ask : Bid;

   double adjSL, adjTP1, adjTP2, adjTP3;
   if(InpUseStructuralSLTP)
   {
      adjSL  = NormalizeDouble(sl, Digits);
      adjTP1 = NormalizeDouble(tp1, Digits);
      adjTP2 = (tp2 != EMPTY_VALUE && tp2 > 0) ? NormalizeDouble(tp2, Digits) : 0;
      adjTP3 = (tp3 != EMPTY_VALUE && tp3 > 0) ? NormalizeDouble(tp3, Digits) : 0;
   }
   else
   {
      double priceShift = marketPrice - entry;
      adjSL  = NormalizeDouble(sl  + priceShift, Digits);
      adjTP1 = NormalizeDouble(tp1 + priceShift, Digits);
      adjTP2 = (tp2 != EMPTY_VALUE && tp2 > 0)
               ? NormalizeDouble(tp2 + priceShift, Digits) : 0;
      adjTP3 = (tp3 != EMPTY_VALUE && tp3 > 0)
               ? NormalizeDouble(tp3 + priceShift, Digits) : 0;
   }

   double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(direction > 0)
   {
      if(adjSL >= Bid - stoplevel)  adjSL  = NormalizeDouble(Bid - stoplevel - Point, Digits);
      if(adjTP1 <= Ask + stoplevel) adjTP1 = NormalizeDouble(Ask + stoplevel + Point, Digits);
      if(adjTP2 > 0 && adjTP2 <= Ask + stoplevel) adjTP2 = NormalizeDouble(Ask + stoplevel + Point, Digits);
      if(adjTP3 > 0 && adjTP3 <= Ask + stoplevel) adjTP3 = NormalizeDouble(Ask + stoplevel + Point, Digits);
   }
   else
   {
      if(adjSL <= Ask + stoplevel)  adjSL  = NormalizeDouble(Ask + stoplevel + Point, Digits);
      if(adjTP1 >= Bid - stoplevel) adjTP1 = NormalizeDouble(Bid - stoplevel - Point, Digits);
      if(adjTP2 > 0 && adjTP2 >= Bid - stoplevel) adjTP2 = NormalizeDouble(Bid - stoplevel - Point, Digits);
      if(adjTP3 > 0 && adjTP3 >= Bid - stoplevel) adjTP3 = NormalizeDouble(Bid - stoplevel - Point, Digits);
   }

   // --- Gate 12: remaining R:R at the fill price ---
   // The companion to keeping SL structural. Drifting away from the signal
   // shrinks the reward still on the table while the risk stays put, so
   // measure the payoff that is actually left rather than guessing at a
   // distance threshold.
   bool g12_pass = true;
   double fillRR = 0;
   if(InpUseGate12FillRR)
   {
      double riskLeft   = MathAbs(marketPrice - adjSL);
      double rewardLeft = MathAbs(adjTP1 - marketPrice);
      fillRR = (riskLeft > 0) ? (rewardLeft / riskLeft) : 0;
      if(riskLeft <= 0 || fillRR < InpMinFillRR)
      {
         g12_pass = false;
         if(!isRetry)
            Print("[QuantEdge EA] Gate 12 FAIL: remaining R:R=", DoubleToString(fillRR, 2),
                  " < min ", DoubleToString(InpMinFillRR, 2),
                  " (market=", DoubleToString(marketPrice, Digits),
                  " SL=", DoubleToString(adjSL, Digits),
                  " TP1=", DoubleToString(adjTP1, Digits), ")");
      }
   }

   bool allPass = g1_pass && g2_pass && g3_pass && g4_pass && g5_pass && g6_pass
                  && g7_pass && g8_pass && g9_pass && g10_pass && g11_pass && g12_pass;

   string dirStr  = (direction > 0) ? "BUY" : "SELL";

   {
      string gateStr = StringFormat("G1:%s G2:%s G3:%s G4:%s G5:%s G6:%s G7:%s G8:%s G9:%s G10:%s G11:%s G12:%s",
         g1_pass?"PASS":"FAIL", g2_pass?"PASS":"FAIL", g3_pass?"PASS":"FAIL",
         g4_pass?"PASS":"FAIL", g5_pass?"PASS":"FAIL", g6_pass?"PASS":"FAIL",
         g7_pass?"PASS":"FAIL", g8_pass?"PASS":"FAIL", g9_pass?"PASS":"FAIL",
         g10_pass?"PASS":"FAIL", g11_pass?"PASS":"FAIL", g12_pass?"PASS":"FAIL");

      // [GATE-LOG-FIX] A signal picked up via the tick-level retry path (e.g.
      // right after OnInit's startup rescan on EA reload/TF switch) is
      // isRetry=true for its ENTIRE lifetime — before this fix its gate
      // outcome was NEVER printed, so a signal silently stuck on SKIP looked
      // identical to "no signal" in the log. Always print on fresh
      // detection; on retry, print only when the outcome actually changes
      // (gate flips, or direction/case changes) so nothing is spammed every
      // tick, but a currently-blocked signal is still visible at least once
      // and again whenever its blocking reason changes.
      string gateKey = StringFormat("%s|%d|%s|%s", dirStr, caseNum, gateStr, allPass ? "TRADE" : "SKIP");
      static string s_lastGateKey = "";
      if(!isRetry || gateKey != s_lastGateKey)
      {
         Print("[QuantEdge EA] ", dirStr, " Case=", caseNum,
               " Rec=", RecLevelName(recLevelInt), " Conf=", (int)MathRound(confidence),
               " EV=", DoubleToString(ev, 2), "R Prob=", DoubleToString(probTP1, 1), "%",
               " Risk=", DoubleToString(riskPct, 2), "% | ", gateStr,
               " => ", (allPass ? "TRADE" : "SKIP"), isRetry ? " (retry)" : "");
         s_lastGateKey = gateKey;
      }
   }

   if(!allPass)
      return false;

   // --- Compute lot size ---
   double effectiveRisk = riskPct;
   if(effectiveRisk <= 0 && InpDefaultRiskPct > 0)
      effectiveRisk = InpDefaultRiskPct;

   // [SLTP-STRUCT-FIX] Size off the distance we are ACTUALLY exposed to —
   // fill price to the final stop — not the signal's original entry-to-SL
   // span. With a structural stop those two diverge as soon as price drifts,
   // and using the stale span would silently inflate the real risk on every
   // late entry.
   double slDistance = MathAbs(marketPrice - adjSL) / Point;
   double lot = CalculateLotFromRisk(effectiveRisk, slDistance);
   if(lot <= 0)
   {
      Print("[QuantEdge EA] Lot calculation returned 0 — cannot trade.",
            " effectiveRisk=", DoubleToString(effectiveRisk, 2),
            "% slDist=", DoubleToString(slDistance, 1),
            " market=", DoubleToString(marketPrice, Digits),
            " adjSL=", DoubleToString(adjSL, Digits),
            " tickVal=", DoubleToString(MarketInfo(Symbol(), MODE_TICKVALUE), 4),
            " balance=", DoubleToString(AccountBalance(), 2));
      return false;
   }

   CheckRecoveryAutoOff();
   lot = ApplyRecoveryMultiplier(lot);

   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MathMax(MarketInfo(Symbol(), MODE_MINLOT), InpMinLotSize);

   if(!InpEnableAutoTrading)
   {
      string tpModeStr = (InpTPMode == TP_DYNAMIC) ? "Dynamic" :
                         (InpTPMode == TP_USE_TP2)  ? "TP2" :
                         (InpTPMode == TP_USE_TP3)  ? "TP3" : "Default";
      Print("[QuantEdge EA] Would ", dirStr, " ", DoubleToString(lot, 2), " lot [", tpModeStr, "] @ ",
            DoubleToString(marketPrice, Digits),
            " SL=", DoubleToString(adjSL, Digits),
            " TP1=", DoubleToString(adjTP1, Digits),
            " TP2=", DoubleToString(adjTP2, Digits),
            " TP3=", DoubleToString(adjTP3, Digits),
            " slDist=", DoubleToString(slDistance, 0), "pts",
            " fillRR=", DoubleToString(fillRR, 2),
            " — auto-trading OFF.");
      return false;
   }

   if(isRetry)
      Print("[QuantEdge EA] RETRY fill: cached signal Case=", caseNum, " ", dirStr,
            " gates now PASS — placing order.");

   bool   dcaGateActive = (InpUsePositiveDCA || InpUseNegativeDCA);
   double sendSL = dcaGateActive ? 0.0 : adjSL;

   // --- Place order(s) based on TP Mode ---
   string comment1 = StringFormat("QE C%d %s", caseNum, RecLevelName(recLevelInt));

   // [FILL-FIX] Track whether any leg actually made it to the broker. The
   // code below used to fall straight through to the DCA-state block after
   // merely PRINTING a rejection, so a refused order still set
   // g_dcaActive=true and returned true. The EA then believed it held a
   // basket that did not exist: Gate 4 blocked every subsequent signal,
   // ApplyDCABackstopSL() worked against phantom state, and the signal was
   // marked consumed even though nothing was ever opened.
   bool anyLegFilled = false;

   if(InpTPMode == TP_DYNAMIC)
   {
      // Dynamic: split TP1 leg + TP2 trailing leg
      bool useSplit = adjTP2 > 0 && lot >= minLot * 2.0;

      if(useSplit)
      {
         double lot1 = MathFloor(lot * InpTP1LotRatio / lotStep) * lotStep;
         double lot2 = MathFloor(lot * (1.0 - InpTP1LotRatio) / lotStep) * lotStep;
         lot1 = MathMax(lot1, minLot); lot1 = MathMin(lot1, InpMaxLotSize);
         lot2 = MathMax(lot2, minLot); lot2 = MathMin(lot2, InpMaxLotSize);

         string comment2 = StringFormat("QE2 C%d %s", caseNum, RecLevelName(recLevelInt));
         int magicTP2    = InpMagicNumber + MAGIC_TP2_OFFSET;

         int t1 = -1, t2 = -1;
         if(direction > 0)
         {
            t1 = OrderSend(Symbol(), OP_BUY, lot1, Ask, InpSlippage, sendSL, adjTP1, comment1, InpMagicNumber, 0, clrLime);
            t2 = OrderSend(Symbol(), OP_BUY, lot2, Ask, InpSlippage, sendSL, adjTP2, comment2, magicTP2, 0, clrGreen);
         }
         else
         {
            t1 = OrderSend(Symbol(), OP_SELL, lot1, Bid, InpSlippage, sendSL, adjTP1, comment1, InpMagicNumber, 0, clrRed);
            t2 = OrderSend(Symbol(), OP_SELL, lot2, Bid, InpSlippage, sendSL, adjTP2, comment2, magicTP2, 0, clrMaroon);
         }

         if(t1 < 0) Print("[QuantEdge EA] TP1 OrderSend failed: error ", GetLastError());
         else     { Print("[QuantEdge EA] TP1 placed: ticket=", t1, " ", dirStr, " ", DoubleToString(lot1, 2), " lot");
                    anyLegFilled = true; }

         if(t2 < 0) Print("[QuantEdge EA] TP2 OrderSend failed: error ", GetLastError());
         else     { Print("[QuantEdge EA] TP2 placed: ticket=", t2, " ", dirStr, " ", DoubleToString(lot2, 2), " lot (trailing)");
                    anyLegFilled = true; }
      }
      else
      {
         int ticket = -1;
         if(direction > 0)
            ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, InpSlippage, sendSL, adjTP1, comment1, InpMagicNumber, 0, clrLime);
         else
            ticket = OrderSend(Symbol(), OP_SELL, lot, Bid, InpSlippage, sendSL, adjTP1, comment1, InpMagicNumber, 0, clrRed);

         if(ticket < 0)
            Print("[QuantEdge EA] OrderSend failed: error ", GetLastError());
         else
         {
            Print("[QuantEdge EA] Order placed: ticket=", ticket, " ", dirStr, " ", DoubleToString(lot, 2),
                  " lot @ ", DoubleToString((direction > 0 ? Ask : Bid), Digits));
            anyLegFilled = true;
         }
      }
   }
   else
   {
      // Default / TP2 / TP3: single order, full lot, one TP
      double selectedTP = adjTP1;
      string tpLabel = "TP1";
      if(InpTPMode == TP_USE_TP2 && adjTP2 > 0)
      {  selectedTP = adjTP2; tpLabel = "TP2"; }
      else if(InpTPMode == TP_USE_TP3 && adjTP3 > 0)
      {  selectedTP = adjTP3; tpLabel = "TP3"; }

      int ticket = -1;
      if(direction > 0)
         ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, InpSlippage, sendSL, selectedTP, comment1, InpMagicNumber, 0, clrLime);
      else
         ticket = OrderSend(Symbol(), OP_SELL, lot, Bid, InpSlippage, sendSL, selectedTP, comment1, InpMagicNumber, 0, clrRed);

      if(ticket < 0)
         Print("[QuantEdge EA] OrderSend failed: error ", GetLastError());
      else
      {
         Print("[QuantEdge EA] Order placed [", tpLabel, "]: ticket=", ticket, " ", dirStr, " ", DoubleToString(lot, 2),
               " lot @ ", DoubleToString((direction > 0 ? Ask : Bid), Digits),
               " TP=", DoubleToString(selectedTP, Digits));
         anyLegFilled = true;
      }
   }

   // [FILL-FIX] Nothing reached the broker — leave every bit of state alone
   // (no DCA basket, signal NOT consumed) so the retry path can try again on
   // the next tick instead of the signal vanishing into a phantom basket.
   if(!anyLegFilled)
   {
      Print("[QuantEdge EA] No leg filled — DCA state not initialized, signal kept for retry.");
      return false;
   }

   // --- Initialize DCA state after successful order placement ---
   if(InpUsePositiveDCA || InpUseNegativeDCA)
   {
      g_dcaActive          = true;
      g_dcaDirection       = direction;
      g_dcaOriginalEntry   = marketPrice;
      g_dcaOriginalSL      = adjSL;
      g_dcaOriginalTP1     = adjTP1;
      g_dcaOriginalLot     = lot;
      g_dcaTP1HalfClosed   = false;
      g_dcaNegTriggered    = false;
      g_dcaNegTriggerPrice = 0;
      SaveDCAState();

      Print("[QuantEdge EA] DCA state initialized: entry=", DoubleToString(marketPrice, Digits),
            " refSL=", DoubleToString(adjSL, Digits),
            " (order SL sent=", DoubleToString(sendSL, Digits), ")",
            " TP1=", DoubleToString(adjTP1, Digits),
            " lot=", DoubleToString(lot, 2));
   }

   if(g_recoveryActive)
   {
      g_recoveryTradeCount++;
      SaveRecoveryState();
      Print("[QuantEdge EA] Recovery trade #", g_recoveryTradeCount,
            "/", InpRecoveryMaxTrades, " lot=", DoubleToString(lot, 2));
   }

   // [REARM-FIX] Remember which signal bar this fill came from, so the stale
   // GV bridge cannot re-arm the very same signal once the basket closes.
   g_lastTradedSigTime = g_sigBarTime;
   SaveLastTradedSigTime();

   g_sigValid = false;
   return true;
}

//+------------------------------------------------------------------+
//| Track recovery trade outcomes — detect consecutive losses          |
//+------------------------------------------------------------------+
void TrackRecoveryOutcome()
{
   if(!g_recoveryActive) return;

   static int s_lastHistoryCount = 0;
   int histCount = OrdersHistoryTotal();
   if(histCount <= s_lastHistoryCount)
   {
      s_lastHistoryCount = histCount;
      return;
   }

   for(int i = histCount - 1; i >= s_lastHistoryCount; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOurMagic(OrderMagicNumber())) continue;

      if(OrderProfit() >= 0)
         g_recoveryConsLoss = 0;
      else
         g_recoveryConsLoss++;

      SaveRecoveryState();
   }
   s_lastHistoryCount = histCount;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // [ARROW-FIX] OnInit usually runs before the indicator has calculated, so
   // its arrow sweep reads nothing. Retry here until one pass sees real
   // buffer data, then stop.
   if(!g_arrowSweepDone)
      g_arrowSweepDone = RedrawSignalArrows();

   if(InpTPMode == TP_DYNAMIC) ManageTrailing();
   ManageDCA();
   UpdateDailyLossTracking();
   TrackRecoveryOutcome();
   CheckRecoveryAutoOff();

   // Poll for close commands from indicator's Manual Trading panel
   string closeGV = "QE_CloseCmd_" + Symbol();
   if(GlobalVariableCheck(closeGV))
   {
      int cmd = (int)GlobalVariableGet(closeGV) - 1;
      GlobalVariableDel(closeGV);
      if(cmd >= 0 && cmd <= 4)
      {
         Print("[QuantEdge EA] Close command received from indicator: criteria=", cmd);
         ClosePositionsByCriteria(cmd, false);
      }
   }

   // --- New bar: check for fresh signal from indicator ---
   datetime currentBarTime = iTime(Symbol(), Period(), 0);
   bool isNewBar = (currentBarTime != g_lastBarTime);

   if(isNewBar)
   {
      g_lastBarTime = currentBarTime;

      int scanLimit = (InpRetryMaxBars > 0) ? InpRetryMaxBars : 5;
      int foundShift = -1;
      double buyCase = EMPTY_VALUE, sellCase = EMPTY_VALUE;
      double entry = EMPTY_VALUE, sl2 = EMPTY_VALUE;
      double tp1 = EMPTY_VALUE, tp2 = EMPTY_VALUE, tp3 = EMPTY_VALUE;
      double recLevel = EMPTY_VALUE, confidence = EMPTY_VALUE;
      double ev = EMPTY_VALUE, riskPct = EMPTY_VALUE, probTP1 = EMPTY_VALUE;
      bool fromGV = false;

      // 1. Try GV bridge (standalone indicator publishes its signal)
      if(!IsTesting())
      {
         fromGV = ReadSignalFromGV(buyCase, sellCase, foundShift,
                                   entry, sl2, tp1, tp2, tp3,
                                   recLevel, confidence, ev, riskPct, probTP1);
      }

      // 2. Fallback: iCustom buffer scan (tester, or indicator not on chart)
      if(!fromGV)
      {
         for(int s = 1; s <= scanLimit; s++)
         {
            double bc = ReadBufferAt(BUF_BUY_SIGNAL, s);
            double sc = ReadBufferAt(BUF_SELL_SIGNAL, s);
            bool hb = (bc != EMPTY_VALUE && bc > 0);
            bool hs = (sc != EMPTY_VALUE && sc > 0);
            if(hb || hs)
            {
               foundShift = s;
               buyCase  = bc;
               sellCase = sc;
               break;
            }
         }
         if(foundShift > 0)
         {
            entry      = ReadBufferAt(BUF_ENTRY, foundShift);
            sl2        = ReadBufferAt(BUF_SL, foundShift);
            tp1        = ReadBufferAt(BUF_TP1, foundShift);
            tp2        = ReadBufferAt(BUF_TP2, foundShift);
            tp3        = ReadBufferAt(BUF_TP3, foundShift);
            recLevel   = ReadBufferAt(BUF_REC_LEVEL, foundShift);
            confidence = ReadBufferAt(BUF_REC_CONFIDENCE, foundShift);
            ev         = ReadBufferAt(BUF_REC_EV, foundShift);
            riskPct    = ReadBufferAt(BUF_REC_RISK, foundShift);
            probTP1    = ReadBufferAt(BUF_PROB_TP1, foundShift);
         }
      }

      bool hasBuy  = (buyCase  != EMPTY_VALUE && buyCase  > 0);
      bool hasSell = (sellCase != EMPTY_VALUE && sellCase > 0);

      // [REARM-FIX] The indicator's GVs outlive the trade they describe, so a
      // signal we already filled would be re-detected here every new bar and
      // re-entered as soon as Gate 4 freed up (basket closed). Reject it on
      // its bar time before anything else touches g_sig*.
      datetime foundBarTime = (foundShift > 0) ? iTime(Symbol(), Period(), foundShift) : 0;

      // [ARROW-FIX] Draw BEFORE the re-arm guard. The arrow is a chart
      // annotation of "a signal happened here", independent of whether this
      // EA may still trade it — and with InpEAMode=true the indicator draws
      // nothing, so the EA is the only thing that can. Skipping the draw
      // along with the re-arm made the marker disappear from the chart for
      // every signal already traded, which is most of them.
      if((hasBuy || hasSell) && foundShift > 0)
      {
         int    arrowDir = hasBuy ? 1 : -1;
         int    arrowCase = (int)(hasBuy ? buyCase : sellCase);
         double arrPrice = (arrowDir > 0) ? iLow(Symbol(), Period(), foundShift)
                                          : iHigh(Symbol(), Period(), foundShift);
         DrawSignalArrow(foundBarTime, arrPrice, arrowDir > 0, arrowCase);
      }

      if((hasBuy || hasSell) && IsSignalAlreadyTraded(foundBarTime))
      {
         static datetime s_lastSkipLogged = 0;
         if(s_lastSkipLogged != foundBarTime)
         {
            s_lastSkipLogged = foundBarTime;
            Print("[QuantEdge EA] Signal at shift=", foundShift,
                  " already traded — skip re-arm (bar=", TimeToString(foundBarTime), ")");
         }
         hasBuy  = false;
         hasSell = false;
      }

      if(hasBuy || hasSell)
      {
         int    direction = hasBuy ? 1 : -1;
         int    caseNum   = (int)(hasBuy ? buyCase : sellCase);

         bool buffersIncomplete = (recLevel == EMPTY_VALUE || confidence == EMPTY_VALUE
                                   || entry == EMPTY_VALUE || sl2 == EMPTY_VALUE);
         if(buffersIncomplete)
         {
            recLevel   = (recLevel   != EMPTY_VALUE) ? recLevel   : (double)REC_WAIT;
            confidence = (confidence != EMPTY_VALUE) ? confidence : 0;
            ev         = (ev         != EMPTY_VALUE) ? ev         : 0;
            riskPct    = (riskPct    != EMPTY_VALUE) ? riskPct    : 0;
            probTP1    = (probTP1    != EMPTY_VALUE) ? probTP1    : 0;
            if(entry == EMPTY_VALUE)
               entry = (direction > 0) ? Ask : Bid;
            if(sl2 == EMPTY_VALUE) sl2 = 0;
            if(tp1 == EMPTY_VALUE) tp1 = 0;
            if(tp2 == EMPTY_VALUE) tp2 = 0;
            if(tp3 == EMPTY_VALUE) tp3 = 0;
            Print("[QuantEdge EA] Signal detected (Case ", caseNum,
                  ") at bar[", foundShift, "] — buffers pending, will retry on next tick.");
         }
         if(tp3 == EMPTY_VALUE) tp3 = 0;

         Print("[QuantEdge EA] Signal found ", (fromGV ? "via GV bridge" : "via iCustom scan"),
               " at shift=", foundShift, " — ",
               (direction > 0 ? "BUY" : "SELL"), " Case=", caseNum,
               " Entry=", DoubleToString(entry, Digits),
               " RecLevel=", (recLevel == EMPTY_VALUE ? "EMPTY" : IntegerToString((int)recLevel)),
               " Conf=", (confidence == EMPTY_VALUE ? "EMPTY" : IntegerToString((int)MathRound(confidence))));

         g_sigValid      = true;
         g_sigTP1Hit     = false;
         g_sigSLHit      = false;
         g_sigDirection  = direction;
         g_sigCaseNum    = caseNum;
         g_sigEntry      = entry;
         g_sigSL         = sl2;
         g_sigTP1        = tp1;
         g_sigTP2        = tp2;
         g_sigTP3        = tp3;
         g_sigRecLevel   = recLevel;
         g_sigConfidence = confidence;
         g_sigEV         = ev;
         g_sigRiskPct    = riskPct;
         g_sigProbTP1    = probTP1;
         g_sigBarTime    = iTime(Symbol(), Period(), foundShift);

         double arrowPrice = (direction > 0) ? iLow(Symbol(), Period(), foundShift)
                                             : iHigh(Symbol(), Period(), foundShift);
         DrawSignalArrow(iTime(Symbol(), Period(), foundShift), arrowPrice, direction > 0, caseNum);

         if(TryExecuteSignal(false))
            return;
      }
      else if(!g_sigValid)
      {
         Print("[QuantEdge EA] New bar: no signal in shift 1..", scanLimit,
               " (indicator dashboard may show an older signal outside this scan window — "
               "see InpRetryMaxBars).");
      }
   }

   // --- Tick-level retry: cached signal still valid, no position yet ---
   if(InpUseSignalRetry && g_sigValid && !HasOpenPosition(g_sigDirection))
   {
      if(InpRetryMaxBars > 0)
      {
         // [RETRY-FIX] Use the signal's own bar time, not g_lastBarTime (which is
         // always the CURRENT bar's open time — comparing it to itself always
         // yields shift 0, so this check never fired and retries never expired
         // by bar count, only by survival-probability decay (Gate 3).
         int barsSinceSignal = iBarShift(Symbol(), Period(), g_sigBarTime, false);
         if(barsSinceSignal > InpRetryMaxBars)
         {
            Print("[QuantEdge EA] Retry expired: ", barsSinceSignal,
                  " bars since signal (max ", InpRetryMaxBars, ")");
            g_sigValid = false;
            return;
         }
      }

      // Re-read buffers if they were initially empty/fallback.
      // [GATE3-FIX] At the signal's own bar, not a hardcoded shift=1 — these
      // buffers only ever carry data there.
      if(g_sigRecLevel == (double)REC_WAIT && g_sigConfidence == 0 && g_sigEV == 0)
      {
         double rl = ReadSignalBuffer(BUF_REC_LEVEL);
         double cf = ReadSignalBuffer(BUF_REC_CONFIDENCE);
         if(rl != EMPTY_VALUE && cf != EMPTY_VALUE)
         {
            g_sigRecLevel   = rl;
            g_sigConfidence = cf;
            double ev2 = ReadSignalBuffer(BUF_REC_EV);
            double rk2 = ReadSignalBuffer(BUF_REC_RISK);
            double pt2 = ReadSignalBuffer(BUF_PROB_TP1);
            if(ev2 != EMPTY_VALUE) g_sigEV      = ev2;
            if(rk2 != EMPTY_VALUE) g_sigRiskPct  = rk2;
            if(pt2 != EMPTY_VALUE) g_sigProbTP1  = pt2;
         }
      }
      // Re-read entry/sl/tp if they were fallback values
      if(g_sigSL == 0 || g_sigTP1 == 0)
      {
         double en2 = ReadSignalBuffer(BUF_ENTRY);
         double sl3 = ReadSignalBuffer(BUF_SL);
         double t12 = ReadSignalBuffer(BUF_TP1);
         double t22 = ReadSignalBuffer(BUF_TP2);
         double t32 = ReadSignalBuffer(BUF_TP3);
         if(en2 != EMPTY_VALUE && en2 > 0) g_sigEntry = en2;
         if(sl3 != EMPTY_VALUE && sl3 > 0) g_sigSL    = sl3;
         if(t12 != EMPTY_VALUE && t12 > 0) g_sigTP1   = t12;
         if(t22 != EMPTY_VALUE && t22 > 0) g_sigTP2   = t22;
         if(t32 != EMPTY_VALUE && t32 > 0) g_sigTP3   = t32;
      }

      if(IsSignalStillValid())
         TryExecuteSignal(true);
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_dcaActive)
      SaveDCAState();

   QEEA_DeletePanel();
   // [ARROW-FIX] Only wipe drawn signal-arrow history on a real removal/
   // recompile/close, not on REASON_CHARTCHANGE (TF switch) — the same
   // pattern the indicator itself already uses for its own arrow prefix.
   // Wiping unconditionally here meant every TF switch discarded the arrow
   // history, even for signals that had already become closed trades.
   // OnInit's arrow sweep can now rebuild the visible window from the
   // indicator's buffers, but only as far back as those buffers reach, so
   // keeping the drawn objects across a TF switch is still the cheaper and
   // more complete path.
   if(reason != REASON_CHARTCHANGE)
      CleanupSignalArrows();
   GlobalVariableDel("QE_BrierMinN_"  + Symbol());
   GlobalVariableDel("QE_BrierFloor_" + Symbol());
   Print("[QuantEdge EA] Deinit, reason=", reason);
}

//+------------------------------------------------------------------+
//| Chart event handler — close-panel buttons + drag                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == QEEA_HEADER_TXT || sparam == QEEA_HEADER)
      {
         g_panelCollapsed = !g_panelCollapsed;
         QEEA_CreatePanel();
         return;
      }

      if(sparam == QEEA_BTN_PROFIT_ALL)
      {
         ObjectSet(sparam, OBJPROP_STATE, false);
         CloseAllProfit();
         return;
      }
      if(sparam == QEEA_BTN_LOSS_ALL)
      {
         ObjectSet(sparam, OBJPROP_STATE, false);
         CloseAllLoss();
         return;
      }
      if(sparam == QEEA_BTN_BUY_PROFIT)
      {
         ObjectSet(sparam, OBJPROP_STATE, false);
         CloseBuyProfit();
         return;
      }
      if(sparam == QEEA_BTN_SELL_PROFIT)
      {
         ObjectSet(sparam, OBJPROP_STATE, false);
         CloseSellProfit();
         return;
      }
      if(sparam == QEEA_BTN_CLOSE_ALL)
      {
         ObjectSet(sparam, OBJPROP_STATE, false);
         CloseAllPositions();
         return;
      }
   }

   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      if(!InpShowClosePanel || g_panelCollapsed)
         return;

      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      int mouseFlags = (int)StringToInteger(sparam);
      bool leftDown = ((mouseFlags & 1) == 1);

      if(g_panelDragging)
      {
         if(leftDown)
         {
            int newX = mouseX - g_dragOffsetX;
            int newY = mouseY - g_dragOffsetY;
            if(newX < 0) newX = 0;
            if(newY < 0) newY = 0;

            if(newX != g_panelPosX || newY != g_panelPosY)
            {
               g_panelPosX = newX;
               g_panelPosY = newY;

               static uint s_lastDrag = 0;
               uint now = GetTickCount();
               if(now - s_lastDrag > 40)
               {
                  s_lastDrag = now;
                  QEEA_CreatePanel();
               }
            }
         }
         else
         {
            g_panelDragging = false;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
            QEEA_SavePanelPosition();
            QEEA_CreatePanel();
         }
      }
      else if(leftDown)
      {
         if(mouseX >= g_panelPosX && mouseX <= g_panelPosX + QEEA_PANEL_WIDTH &&
            mouseY >= g_panelPosY && mouseY <= g_panelPosY + QEEA_HEADER_H)
         {
            g_panelDragging = true;
            g_dragOffsetX = mouseX - g_panelPosX;
            g_dragOffsetY = mouseY - g_panelPosY;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
      }

      if(!g_panelDragging && !leftDown)
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
   }
}

//+------------------------------------------------------------------+
//| Custom fitness for Strategy Tester optimizer.                     |
//| Select "Custom max" in optimization settings to use this.         |
//| Calmar-proxy: netProfit / maxDD — penalizes drawdown/tail risk,   |
//| unlike the prior EV*sqrt(N) which only rewarded edge+sample size. |
//| Guards: minimum trade count (avoid ratio noise from tiny samples) |
//| and minimum DD floor (STAT_EQUITY_DD_RELATIVE returns a percent,  |
//| e.g. 15.5, not a 0-1 fraction — avoid divide-by-near-zero).       |
//+------------------------------------------------------------------+
double OnTester()
{
   if(TesterStatistics(STAT_TRADES) < 30) return 0;

   double netProfit = TesterStatistics(STAT_PROFIT);
   double maxDD     = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   if(maxDD < 0.1) return 0;

   return netProfit / maxDD;
}
//+------------------------------------------------------------------+
