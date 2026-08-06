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
//| INPUT GROUP: Close Panel                                          |
//+------------------------------------------------------------------+
input string inp_grp_panel       = "========== Close Panel =========="; // ---
input bool   InpShowClosePanel   = true;                // Show close-order panel on chart

//+------------------------------------------------------------------+
//| Close panel object name prefix + constants                        |
//+------------------------------------------------------------------+
#define QEEA_PREFIX        "QEEA_"
#define QEEA_HEADER         QEEA_PREFIX + "Header"
#define QEEA_HEADER_TXT      QEEA_PREFIX + "HeaderTxt"
#define QEEA_BG              QEEA_PREFIX + "Bg"
#define QEEA_BTN_PROFIT_ALL   QEEA_PREFIX + "BtnProfitAll"
#define QEEA_BTN_LOSS_ALL     QEEA_PREFIX + "BtnLossAll"
#define QEEA_BTN_BUY_PROFIT    QEEA_PREFIX + "BtnBuyProfit"
#define QEEA_BTN_SELL_PROFIT   QEEA_PREFIX + "BtnSellProfit"
#define QEEA_BTN_CLOSE_ALL      QEEA_PREFIX + "BtnCloseAll"

#define QEEA_PANEL_WIDTH    150
#define QEEA_HEADER_H       20
#define QEEA_BTN_H          24
#define QEEA_BTN_GAP        4
#define QEEA_PAD            5

//+------------------------------------------------------------------+
//| Close criteria ordinals                                           |
//+------------------------------------------------------------------+
#define CRIT_ALL_PROFIT   0
#define CRIT_ALL_LOSS     1
#define CRIT_BUY_PROFIT   2
#define CRIT_SELL_PROFIT  3
#define CRIT_CLOSE_ALL    4

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
int      g_hIndicator = INVALID_HANDLE;
datetime g_lastBarTime = 0;
CTrade   g_trade;

int      g_panelPosX = 20;
int      g_panelPosY = 20;
bool     g_panelDragging = false;
int      g_dragOffsetX = 0;
int      g_dragOffsetY = 0;
bool     g_panelCollapsed = false;

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
//| Close panel: object creation helpers (local, minimal)              |
//+------------------------------------------------------------------+
void QEEA_CreateRect(string name, int x, int y, int w, int h, color bg, color brd)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, brd);
}

void QEEA_CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 9)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

void QEEA_CreateButton(string name, int x, int y, int w, int h, string text, color bg, color brd)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, brd);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
}

//+------------------------------------------------------------------+
//| Close panel: position persistence (per-symbol, per-magic keys)    |
//+------------------------------------------------------------------+
string QEEA_PanelGVName_X() { return "QE_EA_PanelX_" + Symbol() + "_" + IntegerToString(InpMagicNumber); }
string QEEA_PanelGVName_Y() { return "QE_EA_PanelY_" + Symbol() + "_" + IntegerToString(InpMagicNumber); }

void QEEA_SavePanelPosition()
{
   GlobalVariableSet(QEEA_PanelGVName_X(), (double)g_panelPosX);
   GlobalVariableSet(QEEA_PanelGVName_Y(), (double)g_panelPosY);
}

void QEEA_LoadPanelPosition()
{
   if(GlobalVariableCheck(QEEA_PanelGVName_X()) && GlobalVariableCheck(QEEA_PanelGVName_Y()))
   {
      g_panelPosX = (int)GlobalVariableGet(QEEA_PanelGVName_X());
      g_panelPosY = (int)GlobalVariableGet(QEEA_PanelGVName_Y());
   }
}

//+------------------------------------------------------------------+
//| Close panel: draw (expanded or collapsed)                         |
//+------------------------------------------------------------------+
void QEEA_CreatePanel()
{
   if(!InpShowClosePanel)
   {
      ObjectsDeleteAll(0, QEEA_PREFIX);
      return;
   }

   if(g_panelCollapsed)
   {
      ObjectDelete(0, QEEA_BG);
      ObjectDelete(0, QEEA_BTN_PROFIT_ALL);
      ObjectDelete(0, QEEA_BTN_LOSS_ALL);
      ObjectDelete(0, QEEA_BTN_BUY_PROFIT);
      ObjectDelete(0, QEEA_BTN_SELL_PROFIT);
      ObjectDelete(0, QEEA_BTN_CLOSE_ALL);

      QEEA_CreateRect(QEEA_HEADER, g_panelPosX, g_panelPosY, QEEA_PANEL_WIDTH, QEEA_HEADER_H,
                       C'40,44,53', C'67,70,81');
      QEEA_CreateLabel(QEEA_HEADER_TXT, g_panelPosX + QEEA_PAD, g_panelPosY + 4,
                        "QuantEdge EA [+]", clrWhite, 9);
      return;
   }

   int panelH = QEEA_HEADER_H + QEEA_PAD * 2 + 5 * QEEA_BTN_H + 4 * QEEA_BTN_GAP;

   QEEA_CreateRect(QEEA_BG, g_panelPosX, g_panelPosY, QEEA_PANEL_WIDTH, panelH,
                    C'25,28,36', C'67,70,81');
   QEEA_CreateRect(QEEA_HEADER, g_panelPosX, g_panelPosY, QEEA_PANEL_WIDTH, QEEA_HEADER_H,
                    C'54,58,69', C'67,70,81');
   QEEA_CreateLabel(QEEA_HEADER_TXT, g_panelPosX + QEEA_PAD, g_panelPosY + 4,
                     ":::: QuantEdge EA [-]", clrSilver, 9);

   int by = g_panelPosY + QEEA_HEADER_H + QEEA_PAD;
   int bw = QEEA_PANEL_WIDTH - QEEA_PAD * 2;
   int bx = g_panelPosX + QEEA_PAD;

   QEEA_CreateButton(QEEA_BTN_PROFIT_ALL, bx, by, bw, QEEA_BTN_H,
                      "Close All Profit", C'27,58,46', C'47,107,79');
   by += QEEA_BTN_H + QEEA_BTN_GAP;

   QEEA_CreateButton(QEEA_BTN_LOSS_ALL, bx, by, bw, QEEA_BTN_H,
                      "Close All Loss", C'58,27,30', C'107,47,54');
   by += QEEA_BTN_H + QEEA_BTN_GAP;

   QEEA_CreateButton(QEEA_BTN_BUY_PROFIT, bx, by, bw, QEEA_BTN_H,
                      "Close Buy Profit", C'22,50,74', C'47,93,138');
   by += QEEA_BTN_H + QEEA_BTN_GAP;

   QEEA_CreateButton(QEEA_BTN_SELL_PROFIT, bx, by, bw, QEEA_BTN_H,
                      "Close Sell Profit", C'22,50,74', C'47,93,138');
   by += QEEA_BTN_H + QEEA_BTN_GAP;

   QEEA_CreateButton(QEEA_BTN_CLOSE_ALL, bx, by, bw, QEEA_BTN_H,
                      "CLOSE ALL", C'90,26,26', C'163,58,58');

   ChartRedraw(0);
}

void QEEA_DeletePanel()
{
   ObjectsDeleteAll(0, QEEA_PREFIX);
}

//+------------------------------------------------------------------+
//| Close positions matching criteria, with MessageBox confirmation   |
//+------------------------------------------------------------------+
void ClosePositionsByCriteria(int criteria)
{
   ulong  tickets[];
   double totalProfit = 0;
   int    count = 0;

   ArrayResize(tickets, PositionsTotal());

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
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      bool matches = false;
      switch(criteria)
      {
         case CRIT_ALL_PROFIT:  matches = (profit > 0); break;
         case CRIT_ALL_LOSS:    matches = (profit < 0); break;
         case CRIT_BUY_PROFIT:  matches = (posType == POSITION_TYPE_BUY  && profit > 0); break;
         case CRIT_SELL_PROFIT: matches = (posType == POSITION_TYPE_SELL && profit > 0); break;
         case CRIT_CLOSE_ALL:   matches = true; break;
      }

      if(matches)
      {
         tickets[count] = ticket;
         totalProfit += profit;
         count++;
      }
   }

   if(count == 0)
   {
      Print("[QuantEdge EA] Close panel: no matching positions for criteria=", criteria);
      return;
   }

   string label;
   switch(criteria)
   {
      case CRIT_ALL_PROFIT:  label = "profitable position(s)"; break;
      case CRIT_ALL_LOSS:    label = "losing position(s)"; break;
      case CRIT_BUY_PROFIT:  label = "profitable BUY position(s)"; break;
      case CRIT_SELL_PROFIT: label = "profitable SELL position(s)"; break;
      default:               label = "position(s)"; break;
   }

   string msg = StringFormat("Close %d %s on %s?\nTotal P/L: %s%.2f USD\n\nThis action cannot be undone.",
                              count, label, Symbol(),
                              (totalProfit >= 0 ? "+" : ""), totalProfit);

   int result = MessageBox(msg, "QuantEdge EA", MB_OKCANCEL | MB_ICONQUESTION);
   if(result != IDOK)
   {
      Print("[QuantEdge EA] Close panel: user cancelled criteria=", criteria);
      return;
   }

   for(int i = 0; i < count; i++)
   {
      if(g_trade.PositionClose(tickets[i]))
         Print("[QuantEdge EA] Closed ticket=", tickets[i]);
      else
         Print("[QuantEdge EA] Failed to close ticket=", tickets[i], ": ", g_trade.ResultRetcodeDescription());
   }
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

   QEEA_LoadPanelPosition();
   QEEA_CreatePanel();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

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
   QEEA_DeletePanel();
   Print("[QuantEdge EA] Deinit, reason=", reason);
}

//+------------------------------------------------------------------+
//| Chart event: button clicks + panel drag                           |
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

      int criteria = -1;
      if(sparam == QEEA_BTN_PROFIT_ALL)   criteria = CRIT_ALL_PROFIT;
      else if(sparam == QEEA_BTN_LOSS_ALL)    criteria = CRIT_ALL_LOSS;
      else if(sparam == QEEA_BTN_BUY_PROFIT)  criteria = CRIT_BUY_PROFIT;
      else if(sparam == QEEA_BTN_SELL_PROFIT) criteria = CRIT_SELL_PROFIT;
      else if(sparam == QEEA_BTN_CLOSE_ALL)   criteria = CRIT_CLOSE_ALL;

      if(criteria >= 0)
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ClosePositionsByCriteria(criteria);
         return;
      }
   }

   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      if(!InpShowClosePanel || g_panelCollapsed) return;

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
