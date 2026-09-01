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

//+------------------------------------------------------------------+
//| Buffer index constants (from 12_EA_EXPORT_CONTRACT.md)            |
//+------------------------------------------------------------------+
#define BUF_BUY_SIGNAL       5
#define BUF_SELL_SIGNAL      6
#define BUF_ENTRY            7
#define BUF_SL               8
#define BUF_TP1              9
#define BUF_TP2              10
#define BUF_PROB_TP1         11
#define BUF_PROB_SAMPLES     15
#define BUF_PROB_DECAYED_TP1 16
#define BUF_PROB_SURVIVAL    17
#define BUF_PROB_EXPIRES_MIN 18
#define BUF_REC_LEVEL        21
#define BUF_REC_CONFIDENCE   22
#define BUF_REC_EV           23
#define BUF_REC_RISK         24

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
   REC_COUNTER_TREND = 5   // COUNTER_TREND — Opposite
};

//+------------------------------------------------------------------+
//| INPUT GROUP: EA Settings                                          |
//+------------------------------------------------------------------+
input string inp_grp_ea          = "========== EA Settings =========="; // ---
input string InpIndicatorName    = "QuantEdge_RSI";     // Indicator name (compiled .ex4)
input bool   InpEnableAutoTrading= true;                // Enable live order placement
input int    InpMagicNumber      = 20260805;            // Magic number for order identification
input int    InpSlippage         = 3;                   // Max slippage (points)
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
input ENUM_REC_LEVEL InpMinRecLevel = REC_WAIT;           // Min recommendation level (worst allowed)
input bool   InpAllowCaution     = true;                // Allow CAUTION_ENTRY level trades
input bool   InpUseGate2Confidence = true;              // Enable Gate 2: Confidence check
input int    InpMinConfidence    = 0;                   // Min confidence score (0-100)
input bool   InpUseGate3Staleness  = true;              // Enable Gate 3: Staleness check
input double InpMaxSurvivalFloor = 0.15;                // Signal expired when survival < this
input bool   InpUseGate5Spread     = false;             // Enable Gate 5: Spread check (also requires InpMaxSpreadPoints > 0)
input int    InpMaxSpreadPoints  = 0;                   // Max spread (points, 0=no check)

//+------------------------------------------------------------------+
//| INPUT GROUP: Session Filter                                        |
//+------------------------------------------------------------------+
input string inp_grp_session     = "========== Session Filter =========="; // ---
input bool   InpUseSessionFilter = false;               // Enable session filter (Gate 6)
input int    InpSessionStartHour = 7;                   // Session start hour (GMT)
input int    InpSessionEndHour   = 20;                  // Session end hour (GMT)

//+------------------------------------------------------------------+
//| INPUT GROUP: Daily Loss Cap                                        |
//+------------------------------------------------------------------+
input string inp_grp_daily       = "========== Daily Loss Cap =========="; // ---
input bool   InpUseDailyLossCap  = false;               // Enable daily loss cap (Gate 7)
input int    InpMaxDailyLosses   = 3;                   // Max consecutive losses per day (0=no limit)
input double InpMaxDailyLossPct  = 2.0;                 // Max daily loss % of balance (0=no limit)

//+------------------------------------------------------------------+
//| INPUT GROUP: Advanced Gates (ADX / Economic Calendar)              |
//| Mirror the indicator's own flags — the indicator publishes gate    |
//| state via GlobalVariable; the EA just reads it. Default OFF.       |
//| Note: MT4 has no calendar API — indicator always publishes 0       |
//| (clear) for QE_EconBlackout_<symbol>, so Gate 9 always passes.     |
//+------------------------------------------------------------------+
input string inp_grp_retry        = "========== Signal Retry =========="; // ---
input bool   InpUseSignalRetry    = true;               // Retry cached signal every tick while still valid
input int    InpRetryMaxBars      = 5;                  // Max bars to keep retrying after signal appeared

input string inp_grp_priceloc     = "========== Price Location Gate (10) =========="; // ---
input bool   InpUseGate10PriceLoc  = false;             // Enable Gate 10: Price Location filter (master switch)
input bool   InpUsePriceLocSLSide  = true;              // Case 1: Allow entry when price between SL-Entry (probSL<50%, within 50%)
input bool   InpUsePriceLocTPSide  = true;              // Case 2: Allow entry when price between Entry-TP1 (probSL<50%, within 50%)
input double InpPriceLocMaxPct     = 50.0;              // Max % distance from reference edge (0-100)
input double InpPriceLocMaxProbSL  = 50.0;              // Max prob SL % allowed (0-100)

input string inp_grp_advgates    = "========== Advanced Gates =========="; // ---
input bool   InpUseADXGate       = false;               // Enable ADX trend-strength gate (Gate 8)
input bool   InpUseEconCalGate   = false;               // Enable economic calendar blackout gate (Gate 9)

//+------------------------------------------------------------------+
//| INPUT GROUP: Trade Management                                      |
//+------------------------------------------------------------------+
input string inp_grp_mgmt        = "========== Trade Management =========="; // ---
input bool   InpUsePartialClose  = true;                // Split into TP1 (60%) + TP2 (40%) legs
input double InpTP1LotRatio      = 0.6;                 // TP1 leg lot ratio (0.1-0.9)
input bool   InpUseTrailing      = true;                // Enable ATR trailing stop on TP2 leg
input double InpTrailATRMult     = 1.5;                 // Trailing distance = ATR × this multiplier
input int    InpTrailATRPeriod   = 14;                  // ATR period for trailing calculation

//+------------------------------------------------------------------+
//| INPUT GROUP: Positive DCA (Trend Direction)                       |
//+------------------------------------------------------------------+
input string inp_grp_posdca       = "========== Positive DCA =========="; // ---
input bool   InpUsePositiveDCA    = true;                // Enable positive DCA (add in trend direction)
input int    InpPosDCAMaxOrders   = 4;                   // Max positive DCA orders (1-10)
input double InpPosDCAHalfClosePct= 50.0;                // Stop adding DCA above this % of Entry→TP1 distance

//+------------------------------------------------------------------+
//| INPUT GROUP: Negative DCA (Against Trend / Recovery)              |
//+------------------------------------------------------------------+
input string inp_grp_negdca       = "========== Negative DCA =========="; // ---
input bool   InpUseNegativeDCA    = true;                // Enable negative DCA (add against trend)
input int    InpNegDCAMaxOrders   = 5;                   // Max negative DCA orders (1-10)
input double InpNegDCATriggerPct  = 50.0;                // Trigger when price moves this % toward SL
input double InpNegDCAATRMult     = 0.5;                 // DCA spacing = ATR × this multiplier
input double InpNegDCAMaxDDPct    = 15.0;                // Hard drawdown cap (% of balance) — applies to ENTIRE basket whenever ANY DCA mode is active, close all if exceeded
input bool   InpNegDCABEClose     = true;                // Close negative DCA basket when price returns to avg entry (breakeven)
input double InpNegDCABEOffsetPip = 0.0;                 // Breakeven offset in pips (0=exact breakeven, >0=require profit)
input double InpDCAProfitLockR    = 0.2;                 // Min basket profit (in R, vs original entry→SL risk) required before entry-return close fires
input double InpDCAMinSpacingPts = 500;                 // Min distance between DCA orders (points, 500=$5 XAUUSD)
input int    InpDCAMinIntervalMin= 5;                   // Min time between DCA orders (minutes, 0=no check)

//+------------------------------------------------------------------+
//| INPUT GROUP: Risk & Lot Sizing                                    |
//+------------------------------------------------------------------+
input string inp_grp_risk        = "========== Risk & Lot Sizing =========="; // ---
input double InpDefaultRiskPct   = 0.5;                 // Fallback risk % when indicator returns 0
input double InpMaxLotSize       = 1.0;                 // Max lot size (hard cap)
input double InpMinLotSize       = 0.01;                // Min lot size

//+------------------------------------------------------------------+
//| INPUT GROUP: Recovery Mode                                         |
//+------------------------------------------------------------------+
input string inp_grp_recovery    = "========== Recovery Mode =========="; // ---
input bool   InpUseRecoveryMode  = true;                 // Enable Recovery Mode (boost lot after DCA cutloss)
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
input int    Ind_BrierMinSamples = 20;             // Brier: min resolved samples per case (0=disable shrink)
input double Ind_BrierFloorShrink= 0.50;           // Brier: uncertainty floor when samples=0 (0.50=halve, 0.75=mild, 1.0=off)

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
#define MAGIC_POS_DCA_OFFSET  200000
#define MAGIC_NEG_DCA_OFFSET  300000

int      g_dailyLossCount   = 0;
double   g_dailyLossAmount  = 0;
datetime g_dailyResetDate   = 0;

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
double   g_sigRecLevel    = 0;
double   g_sigConfidence  = 0;
double   g_sigEV          = 0;
double   g_sigRiskPct     = 0;
double   g_sigProbTP1     = 0;
bool     g_sigTP1Hit      = false;
bool     g_sigSLHit       = false;

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
   return iCustom(Symbol(), Period(), InpIndicatorName,
                  "", // inp_grp_core separator
                  Ind_RSIPeriod, Ind_FastMAPeriod, Ind_SignalMAPeriod,
                  Ind_BBPeriod, Ind_BBDeviation, PRICE_CLOSE,
                  Ind_EAMode,
                  bufferIndex, 1);
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
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      int mag = OrderMagicNumber();
      if(mag != InpMagicNumber && mag != magicTP2)
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
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();
      if(mag == InpMagicNumber || mag == magicTP2)
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

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();

      bool isOriginal = (mag == InpMagicNumber || mag == magicTP2);
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
   datetime today = StringToTime(TimeToString(TimeGMT(), TIME_DATE));
   if(today != g_dailyResetDate)
   {
      g_dailyLossCount  = 0;
      g_dailyLossAmount = 0;
      g_dailyResetDate  = today;
   }

   static int s_lastHistTotal = 0;
   int histTotal = OrdersHistoryTotal();
   if(histTotal == s_lastHistTotal)
      return;

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

      datetime closeTime = OrderCloseTime();
      datetime closeDay  = StringToTime(TimeToString(closeTime, TIME_DATE));
      if(closeDay != g_dailyResetDate)
         continue;

      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      if(pnl < 0)
      {
         g_dailyLossCount++;
         g_dailyLossAmount += MathAbs(pnl);
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

//+------------------------------------------------------------------+
//| ATR trailing stop for TP2 legs                                     |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   if(!InpUseTrailing)
      return;

   int magicTP2 = InpMagicNumber + MAGIC_TP2_OFFSET;
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
      if(OrderMagicNumber() != magicTP2)
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

   double gridStep = entryToTP1 / (InpPosDCAMaxOrders + 1);

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

      double level = g_dcaOriginalEntry + idx * gridStep;
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
   ObjectsDeleteAll(0, QEEA_PREFIX);
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
         " MaxSpread=", InpMaxSpreadPoints);
   Print("[QuantEdge EA] SignalRetry=", InpUseSignalRetry, " RetryMaxBars=", InpRetryMaxBars);
   Print("[QuantEdge EA] PriceLocSLSide=", InpUsePriceLocSLSide, " PriceLocTPSide=", InpUsePriceLocTPSide,
         " MaxPct=", InpPriceLocMaxPct, " MaxProbSL=", InpPriceLocMaxProbSL);
   Print("[QuantEdge EA] SessionFilter=", InpUseSessionFilter, " DailyLossCap=", InpUseDailyLossCap);
   Print("[QuantEdge EA] PartialClose=", InpUsePartialClose, " Trailing=", InpUseTrailing);
   Print("[QuantEdge EA] PositiveDCA=", InpUsePositiveDCA, " NegativeDCA=", InpUseNegativeDCA);
   Print("[QuantEdge EA] ===================");

   if(!InpEnableAutoTrading)
   {
      Print("[QuantEdge EA] *** WARNING: AutoTrading=OFF — no orders will be placed! Set InpEnableAutoTrading=true ***");
      Comment("QuantEdge EA: AutoTrading OFF — no orders placed");
   }
   else
      Print("[QuantEdge EA] LIVE MODE — auto-trading enabled.");

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

   // Track TP1 hit — doesn't invalidate signal but blocks TP-side entry
   if(!g_sigTP1Hit && g_sigTP1 > 0)
   {
      bool tp1Hit = (g_sigDirection > 0) ? (mktNow >= g_sigTP1) : (mktNow <= g_sigTP1);
      if(tp1Hit)
      {
         Print("[QuantEdge EA] Retry: TP1 reached (",
               DoubleToString(g_sigTP1, Digits), ") — TP-side entry disabled");
         g_sigTP1Hit = true;
      }
   }

   if(InpUseGate3Staleness)
   {
      double survival = ReadBuffer(BUF_PROB_SURVIVAL);
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

   // --- Gate 1: Recommendation Level ---
   bool g1_pass = true;
   if(InpUseGate1RecLevel)
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
   bool g3_pass = true;
   double survival = ReadBuffer(BUF_PROB_SURVIVAL);
   if(InpUseGate3Staleness && survival != EMPTY_VALUE && survival < InpMaxSurvivalFloor)
      g3_pass = false;

   // --- Gate 4: No Duplicate Position ---
   bool g4_pass = !HasOpenPosition(direction) && !g_dcaActive;
   if(!isRetry && g_dcaActive && !HasOpenPosition(direction))
      Print("[QuantEdge EA] Gate 4 blocked: DCA basket active (dir=",
            (g_dcaDirection > 0 ? "BUY" : "SELL"),
            ") — waiting for basket to close before accepting new signal.");

   // --- Gate 5: Spread ---
   bool g5_pass = true;
   if(InpUseGate5Spread && InpMaxSpreadPoints > 0)
   {
      double spread = MarketInfo(Symbol(), MODE_SPREAD);
      if(spread > InpMaxSpreadPoints)
         g5_pass = false;
   }

   // --- Gate 6: Session Filter ---
   bool g6_pass = IsWithinSession();

   // --- Gate 7: Daily Loss Cap ---
   bool g7_pass = !IsDailyLossCapHit();

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
      double probSL   = (probTP1 != EMPTY_VALUE) ? (100.0 - probTP1) : 100.0;
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
   }

   bool allPass = g1_pass && g2_pass && g3_pass && g4_pass && g5_pass && g6_pass && g7_pass && g8_pass && g9_pass && g10_pass;

   string dirStr  = (direction > 0) ? "BUY" : "SELL";

   if(!isRetry)
   {
      string gateStr = StringFormat("G1:%s G2:%s G3:%s G4:%s G5:%s G6:%s G7:%s G8:%s G9:%s G10:%s",
         g1_pass?"PASS":"FAIL", g2_pass?"PASS":"FAIL", g3_pass?"PASS":"FAIL",
         g4_pass?"PASS":"FAIL", g5_pass?"PASS":"FAIL", g6_pass?"PASS":"FAIL",
         g7_pass?"PASS":"FAIL", g8_pass?"PASS":"FAIL", g9_pass?"PASS":"FAIL",
         g10_pass?"PASS":"FAIL");

      Print("[QuantEdge EA] ", dirStr, " Case=", caseNum,
            " Rec=", RecLevelName(recLevelInt), " Conf=", (int)MathRound(confidence),
            " EV=", DoubleToString(ev, 2), "R Prob=", DoubleToString(probTP1, 1), "%",
            " Risk=", DoubleToString(riskPct, 2), "% | ", gateStr,
            " => ", (allPass ? "TRADE" : "SKIP"));
   }

   if(!allPass)
      return false;

   // --- Compute lot size ---
   double effectiveRisk = riskPct;
   if(effectiveRisk <= 0 && InpDefaultRiskPct > 0)
      effectiveRisk = InpDefaultRiskPct;

   double slDistance = MathAbs(entry - sl) / Point;
   double lot = CalculateLotFromRisk(effectiveRisk, slDistance);
   if(lot <= 0)
   {
      Print("[QuantEdge EA] Lot calculation returned 0 — cannot trade.");
      return false;
   }

   CheckRecoveryAutoOff();
   lot = ApplyRecoveryMultiplier(lot);

   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MathMax(MarketInfo(Symbol(), MODE_MINLOT), InpMinLotSize);

   if(!InpEnableAutoTrading)
   {
      if(InpUsePartialClose && tp2 != EMPTY_VALUE && tp2 > 0)
         Print("[QuantEdge EA] Would ", dirStr, " ", DoubleToString(lot, 2), " lot (split TP1+TP2) @ ",
               DoubleToString(entry, Digits), " SL=", DoubleToString(sl, Digits),
               " TP1=", DoubleToString(tp1, Digits), " TP2=", DoubleToString(tp2, Digits),
               " — auto-trading OFF.");
      else
         Print("[QuantEdge EA] Would ", dirStr, " ", DoubleToString(lot, 2), " lot @ ",
               DoubleToString(entry, Digits), " SL=", DoubleToString(sl, Digits),
               " TP=", DoubleToString(tp1, Digits), " — auto-trading OFF.");
      return false;
   }

   if(isRetry)
      Print("[QuantEdge EA] RETRY fill: cached signal Case=", caseNum, " ", dirStr,
            " gates now PASS — placing order.");

   // --- Adjust SL/TP relative to current market price ---
   double marketPrice = (direction > 0) ? Ask : Bid;
   double priceShift  = marketPrice - entry;
   double adjSL  = NormalizeDouble(sl  + priceShift, Digits);
   double adjTP1 = NormalizeDouble(tp1 + priceShift, Digits);
   double adjTP2 = (tp2 != EMPTY_VALUE && tp2 > 0)
                   ? NormalizeDouble(tp2 + priceShift, Digits) : 0;

   double stoplevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(direction > 0)
   {
      if(adjSL >= Bid - stoplevel)  adjSL  = NormalizeDouble(Bid - stoplevel - Point, Digits);
      if(adjTP1 <= Ask + stoplevel) adjTP1 = NormalizeDouble(Ask + stoplevel + Point, Digits);
      if(adjTP2 > 0 && adjTP2 <= Ask + stoplevel) adjTP2 = NormalizeDouble(Ask + stoplevel + Point, Digits);
   }
   else
   {
      if(adjSL <= Ask + stoplevel)  adjSL  = NormalizeDouble(Ask + stoplevel + Point, Digits);
      if(adjTP1 >= Bid - stoplevel) adjTP1 = NormalizeDouble(Bid - stoplevel - Point, Digits);
      if(adjTP2 > 0 && adjTP2 >= Bid - stoplevel) adjTP2 = NormalizeDouble(Bid - stoplevel - Point, Digits);
   }

   bool   dcaGateActive = (InpUsePositiveDCA || InpUseNegativeDCA);
   double sendSL = dcaGateActive ? 0.0 : adjSL;

   // --- Place order(s) ---
   string comment1 = StringFormat("QE C%d %s", caseNum, RecLevelName(recLevelInt));
   bool   useSplit = InpUsePartialClose && adjTP2 > 0
                     && lot >= minLot * 2.0;

   if(useSplit)
   {
      double lot1 = MathFloor(lot * InpTP1LotRatio / lotStep) * lotStep;
      double lot2 = MathFloor(lot * (1.0 - InpTP1LotRatio) / lotStep) * lotStep;
      lot1 = MathMax(lot1, minLot);
      lot2 = MathMax(lot2, minLot);
      lot1 = MathMin(lot1, InpMaxLotSize);
      lot2 = MathMin(lot2, InpMaxLotSize);

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
      else       Print("[QuantEdge EA] TP1 placed: ticket=", t1, " ", dirStr, " ", DoubleToString(lot1, 2), " lot");

      if(t2 < 0) Print("[QuantEdge EA] TP2 OrderSend failed: error ", GetLastError());
      else       Print("[QuantEdge EA] TP2 placed: ticket=", t2, " ", dirStr, " ", DoubleToString(lot2, 2), " lot (trailing)");
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
         Print("[QuantEdge EA] Order placed: ticket=", ticket, " ", dirStr, " ", DoubleToString(lot, 2),
               " lot @ ", DoubleToString((direction > 0 ? Ask : Bid), Digits));
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
   ManageTrailing();
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

      double buyCase  = ReadBuffer(BUF_BUY_SIGNAL);
      double sellCase = ReadBuffer(BUF_SELL_SIGNAL);

      bool hasBuy  = (buyCase  != EMPTY_VALUE && buyCase  > 0);
      bool hasSell = (sellCase != EMPTY_VALUE && sellCase > 0);

      if(hasBuy || hasSell)
      {
         int    direction = hasBuy ? 1 : -1;
         int    caseNum   = (int)(hasBuy ? buyCase : sellCase);
         double entry     = ReadBuffer(BUF_ENTRY);
         double sl2       = ReadBuffer(BUF_SL);
         double tp1       = ReadBuffer(BUF_TP1);
         double tp2       = ReadBuffer(BUF_TP2);
         double recLevel  = ReadBuffer(BUF_REC_LEVEL);
         double confidence= ReadBuffer(BUF_REC_CONFIDENCE);
         double ev        = ReadBuffer(BUF_REC_EV);
         double riskPct   = ReadBuffer(BUF_REC_RISK);
         double probTP1   = ReadBuffer(BUF_PROB_TP1);

         if(recLevel != EMPTY_VALUE && confidence != EMPTY_VALUE)
         {
            g_sigValid      = true;
            g_sigTP1Hit     = false;
            g_sigSLHit      = false;
            g_sigDirection  = direction;
            g_sigCaseNum    = caseNum;
            g_sigEntry      = entry;
            g_sigSL         = sl2;
            g_sigTP1        = tp1;
            g_sigTP2        = tp2;
            g_sigRecLevel   = recLevel;
            g_sigConfidence = confidence;
            g_sigEV         = ev;
            g_sigRiskPct    = riskPct;
            g_sigProbTP1    = probTP1;

            double arrowPrice = (direction > 0) ? iLow(Symbol(), Period(), 1)
                                                : iHigh(Symbol(), Period(), 1);
            DrawSignalArrow(iTime(Symbol(), Period(), 1), arrowPrice, direction > 0, caseNum);

            if(TryExecuteSignal(false))
               return;
         }
         else
         {
            Print("[QuantEdge EA] Signal detected (Case ", caseNum,
                  ") but probability buffers empty — skipping.");
         }
      }
   }

   // --- Tick-level retry: cached signal still valid, no position yet ---
   if(InpUseSignalRetry && g_sigValid && !HasOpenPosition(g_sigDirection))
   {
      if(InpRetryMaxBars > 0)
      {
         int barsSinceSignal = iBarShift(Symbol(), Period(), g_lastBarTime, false);
         if(barsSinceSignal > InpRetryMaxBars)
         {
            Print("[QuantEdge EA] Retry expired: ", barsSinceSignal,
                  " bars since signal (max ", InpRetryMaxBars, ")");
            g_sigValid = false;
            return;
         }
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
//| Sprint 6: Custom fitness for Strategy Tester optimizer             |
//| Select "Custom max" in optimization settings to use this.         |
//| Returns EV * sqrt(N) — rewards edge AND sample size together.     |
//+------------------------------------------------------------------+
double OnTester()
{
   int wins = 0, losses = 0;
   double totalProfit = 0, totalLoss = 0;
   int magicTP2 = InpMagicNumber + MAGIC_TP2_OFFSET;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();
      if(!IsOurMagic(mag)) continue;
      if(OrderType() > OP_SELL) continue;

      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      if(pnl >= 0)
      {
         wins++;
         totalProfit += pnl;
      }
      else
      {
         losses++;
         totalLoss += MathAbs(pnl);
      }
   }

   int n = wins + losses;
   if(n == 0) return(-999);

   double wr     = (double)wins / n;
   double avgWin = (wins > 0) ? totalProfit / wins : 0;
   double avgLos = (losses > 0) ? totalLoss / losses : 0;
   double ev     = wr * avgWin - (1.0 - wr) * avgLos;

   return(ev * MathSqrt((double)n));
}
//+------------------------------------------------------------------+
