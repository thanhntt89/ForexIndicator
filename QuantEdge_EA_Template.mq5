//+------------------------------------------------------------------+
//|                                      QuantEdge_EA_Template.mq5   |
//|                         Reference EA for QuantEdge RSI Indicator  |
//+------------------------------------------------------------------+
//  REFERENCE / SKELETON — review before enabling live trading.
//  This EA reads QuantEdge RSI indicator buffers via iCustom() handle
//  + CopyBuffer() and makes trade decisions based on recommendation
//  level, confidence, staleness, spread, and duplicate-position checks.
//
//  InpEnableAutoTrading defaults to FALSE. With auto-trading off,
//  the EA logs gate decisions to the Experts tab without placing
//  orders. Flip to TRUE only after demo-account validation.
//
//  Buffer contract: Document_System/12_EA_EXPORT_CONTRACT.md
//+------------------------------------------------------------------+
#property copyright "QuantEdge"
#property version   "1.00"

#include <Trade/Trade.mqh>

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
#define REC_STRONG_ENTRY  0
#define REC_ENTRY         1
#define REC_CAUTION_ENTRY 2
#define REC_WAIT          3
#define REC_AVOID         4
#define REC_COUNTER_TREND 5

//+------------------------------------------------------------------+
//| INPUT GROUP: EA Settings                                          |
//+------------------------------------------------------------------+
input string inp_grp_ea          = "========== EA Settings =========="; // ---
input string InpIndicatorName    = "QuantEdge_RSI";     // Indicator name (compiled .ex5)
input bool   InpEnableAutoTrading= false;               // Enable live order placement (default OFF)
input ulong  InpMagicNumber      = 20260805;            // Magic number for order identification
input ulong  InpSlippage         = 3;                   // Max slippage (points)

//+------------------------------------------------------------------+
//| INPUT GROUP: Decision Gates                                       |
//+------------------------------------------------------------------+
input string inp_grp_gates       = "========== Decision Gates =========="; // ---
input int    InpMinRecLevel      = REC_ENTRY;           // Min recommendation level (0=STRONG, 1=ENTRY, 2=CAUTION)
input bool   InpAllowCaution     = false;               // Allow CAUTION_ENTRY level trades
input int    InpMinConfidence    = 65;                  // Min confidence score (0-100)
input double InpMaxSurvivalFloor = 0.15;                // Signal expired when survival < this
input int    InpMaxSpreadPoints  = 30;                  // Max spread (points, 0=no check)

//+------------------------------------------------------------------+
//| INPUT GROUP: Risk & Lot Sizing                                    |
//+------------------------------------------------------------------+
input string inp_grp_risk        = "========== Risk & Lot Sizing =========="; // ---
input double InpMaxLotSize       = 1.0;                 // Max lot size (hard cap)
input double InpMinLotSize       = 0.01;                // Min lot size

//+------------------------------------------------------------------+
//| INPUT GROUP: Indicator Params (must match loaded indicator)       |
//+------------------------------------------------------------------+
input string inp_grp_ind         = "========== Indicator Params =========="; // ---
input int    Ind_RSIPeriod       = 14;
input int    Ind_FastMAPeriod    = 2;
input int    Ind_SignalMAPeriod  = 7;
input int    Ind_BBPeriod        = 34;
input double Ind_BBDeviation     = 1.685;
input bool   Ind_EAMode          = true;  // Always true — suppresses indicator visuals

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
int      g_hIndicator = INVALID_HANDLE;
datetime g_lastBarTime = 0;
CTrade   g_trade;

//+------------------------------------------------------------------+
//| Read one indicator buffer value at shift=1                        |
//+------------------------------------------------------------------+
double ReadBuffer(int bufferIndex)
{
   double buf[1];
   if(CopyBuffer(g_hIndicator, bufferIndex, 1, 1, buf) != 1)
      return EMPTY_VALUE;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Calculate lot size from risk percent and SL distance              |
//+------------------------------------------------------------------+
double CalculateLotFromRisk(double riskPct, double slDistancePoints)
{
   if(riskPct <= 0 || slDistancePoints <= 0)
      return 0;

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double lotStep  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);

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
//+------------------------------------------------------------------+
bool HasOpenPosition(int direction)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol())
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(direction > 0 && posType == POSITION_TYPE_BUY)
         return true;
      if(direction < 0 && posType == POSITION_TYPE_SELL)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_hIndicator = iCustom(Symbol(), Period(), InpIndicatorName,
                           "", // inp_grp_core separator
                           Ind_RSIPeriod, Ind_FastMAPeriod, Ind_SignalMAPeriod,
                           Ind_BBPeriod, Ind_BBDeviation, PRICE_CLOSE,
                           Ind_EAMode);

   if(g_hIndicator == INVALID_HANDLE)
   {
      Print("[QuantEdge EA] ERROR: Cannot create indicator handle for '", InpIndicatorName, "'.");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);

   if(!InpEnableAutoTrading)
      Print("[QuantEdge EA] SKELETON MODE — logging decisions only. Set InpEnableAutoTrading=true for live trading.");
   else
      Print("[QuantEdge EA] LIVE MODE — auto-trading enabled. Magic=", InpMagicNumber);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(Symbol(), Period(), 0);
   if(currentBarTime == g_lastBarTime)
      return;
   g_lastBarTime = currentBarTime;

   double buyCase  = ReadBuffer(BUF_BUY_SIGNAL);
   double sellCase = ReadBuffer(BUF_SELL_SIGNAL);

   bool hasBuy  = (buyCase  != EMPTY_VALUE && buyCase  > 0);
   bool hasSell = (sellCase != EMPTY_VALUE && sellCase > 0);

   if(!hasBuy && !hasSell)
      return;

   int    direction = hasBuy ? 1 : -1;
   int    caseNum   = (int)(hasBuy ? buyCase : sellCase);
   double entry     = ReadBuffer(BUF_ENTRY);
   double sl        = ReadBuffer(BUF_SL);
   double tp1       = ReadBuffer(BUF_TP1);
   double recLevel  = ReadBuffer(BUF_REC_LEVEL);
   double confidence= ReadBuffer(BUF_REC_CONFIDENCE);
   double ev        = ReadBuffer(BUF_REC_EV);
   double riskPct   = ReadBuffer(BUF_REC_RISK);
   double survival  = ReadBuffer(BUF_PROB_SURVIVAL);
   double expiresMin= ReadBuffer(BUF_PROB_EXPIRES_MIN);
   double probTP1   = ReadBuffer(BUF_PROB_TP1);

   if(recLevel == EMPTY_VALUE || confidence == EMPTY_VALUE)
   {
      Print("[QuantEdge EA] Signal detected (Case ", caseNum, ") but probability buffers empty — skipping.");
      return;
   }

   int recLevelInt = (int)MathRound(recLevel);

   // --- Gate 1: Recommendation Level ---
   bool g1_pass = false;
   if(recLevelInt <= InpMinRecLevel)
      g1_pass = true;
   if(recLevelInt == REC_CAUTION_ENTRY && InpAllowCaution)
      g1_pass = true;

   // --- Gate 2: Confidence ---
   bool g2_pass = ((int)MathRound(confidence) >= InpMinConfidence);

   // --- Gate 3: Staleness ---
   bool g3_pass = true;
   if(survival != EMPTY_VALUE && survival < InpMaxSurvivalFloor)
      g3_pass = false;

   // --- Gate 4: No Duplicate Position ---
   bool g4_pass = !HasOpenPosition(direction);

   // --- Gate 5: Spread ---
   bool g5_pass = true;
   if(InpMaxSpreadPoints > 0)
   {
      double spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints)
         g5_pass = false;
   }

   bool allPass = g1_pass && g2_pass && g3_pass && g4_pass && g5_pass;

   string dirStr  = (direction > 0) ? "BUY" : "SELL";
   string gateStr = StringFormat("G1:%s G2:%s G3:%s G4:%s G5:%s",
      g1_pass?"PASS":"FAIL", g2_pass?"PASS":"FAIL", g3_pass?"PASS":"FAIL",
      g4_pass?"PASS":"FAIL", g5_pass?"PASS":"FAIL");

   Print("[QuantEdge EA] ", dirStr, " Case=", caseNum,
         " Rec=", RecLevelName(recLevelInt), " Conf=", (int)MathRound(confidence),
         " EV=", DoubleToString(ev, 2), "R Prob=", DoubleToString(probTP1, 1), "%",
         " Risk=", DoubleToString(riskPct, 2), "% | ", gateStr,
         " => ", (allPass ? "TRADE" : "SKIP"));

   if(!allPass)
      return;

   // --- Compute lot size ---
   double slDistance = MathAbs(entry - sl) / _Point;
   double lot = CalculateLotFromRisk(riskPct, slDistance);
   if(lot <= 0)
   {
      Print("[QuantEdge EA] Lot calculation returned 0 — cannot trade.");
      return;
   }

   if(!InpEnableAutoTrading)
   {
      Print("[QuantEdge EA] Would ", dirStr, " ", DoubleToString(lot, 2), " lot @ ",
            DoubleToString(entry, _Digits), " SL=", DoubleToString(sl, _Digits),
            " TP=", DoubleToString(tp1, _Digits), " — auto-trading OFF.");
      return;
   }

   // --- Place order ---
   string comment = StringFormat("QE C%d %s", caseNum, RecLevelName(recLevelInt));

   bool result = false;
   if(direction > 0)
      result = g_trade.Buy(lot, Symbol(), 0, sl, tp1, comment);
   else
      result = g_trade.Sell(lot, Symbol(), 0, sl, tp1, comment);

   if(!result)
      Print("[QuantEdge EA] Order failed: ", g_trade.ResultRetcodeDescription());
   else
      Print("[QuantEdge EA] Order placed: ticket=", g_trade.ResultOrder(), " ", dirStr, " ",
            DoubleToString(lot, 2), " lot @ ", DoubleToString(g_trade.ResultPrice(), _Digits));
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hIndicator != INVALID_HANDLE)
   {
      IndicatorRelease(g_hIndicator);
      g_hIndicator = INVALID_HANDLE;
   }
   Print("[QuantEdge EA] Deinit, reason=", reason);
}
//+------------------------------------------------------------------+
