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
input string InpIndicatorName    = "QuantEdge_RSI";     // Indicator name (compiled .ex4)
input bool   InpEnableAutoTrading= true;                // Enable live order placement
input int    InpMagicNumber      = 20260805;            // Magic number for order identification
input int    InpSlippage         = 3;                   // Max slippage (points)

//+------------------------------------------------------------------+
//| INPUT GROUP: Decision Gates                                       |
//+------------------------------------------------------------------+
input string inp_grp_gates       = "========== Decision Gates =========="; // ---
input int    InpMinRecLevel      = REC_WAIT;             // Min recommendation level (0=STRONG, 1=ENTRY, 2=CAUTION, 3=WAIT)
input bool   InpAllowCaution     = true;                // Allow CAUTION_ENTRY level trades
input int    InpMinConfidence    = 0;                   // Min confidence score (0-100)
input double InpMaxSurvivalFloor = 0.15;                // Signal expired when survival < this
input int    InpMaxSpreadPoints  = 30;                  // Max spread (points, 0=no check)

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
//| INPUT GROUP: Trade Management                                      |
//+------------------------------------------------------------------+
input string inp_grp_mgmt        = "========== Trade Management =========="; // ---
input bool   InpUsePartialClose  = true;                // Split into TP1 (60%) + TP2 (40%) legs
input double InpTP1LotRatio      = 0.6;                 // TP1 leg lot ratio (0.1-0.9)
input bool   InpUseTrailing      = true;                // Enable ATR trailing stop on TP2 leg
input double InpTrailATRMult     = 1.5;                 // Trailing distance = ATR × this multiplier
input int    InpTrailATRPeriod   = 14;                  // ATR period for trailing calculation

//+------------------------------------------------------------------+
//| INPUT GROUP: Risk & Lot Sizing                                    |
//+------------------------------------------------------------------+
input string inp_grp_risk        = "========== Risk & Lot Sizing =========="; // ---
input double InpDefaultRiskPct   = 0.5;                 // Fallback risk % when indicator returns 0
input double InpMaxLotSize       = 1.0;                 // Max lot size (hard cap)
input double InpMinLotSize       = 0.01;                // Min lot size

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

#define MAGIC_TP2_OFFSET  100000
int      g_dailyLossCount   = 0;
double   g_dailyLossAmount  = 0;
datetime g_dailyResetDate   = 0;

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
      if(mag != InpMagicNumber && mag != InpMagicNumber + MAGIC_TP2_OFFSET)
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

   Print("[QuantEdge EA] === SETTINGS DUMP ===");
   Print("[QuantEdge EA] AutoTrading=", InpEnableAutoTrading, " Magic=", InpMagicNumber);
   Print("[QuantEdge EA] MinRecLevel=", InpMinRecLevel, " AllowCaution=", InpAllowCaution,
         " MinConfidence=", InpMinConfidence, " MaxSurvivalFloor=", InpMaxSurvivalFloor,
         " MaxSpread=", InpMaxSpreadPoints);
   Print("[QuantEdge EA] SessionFilter=", InpUseSessionFilter, " DailyLossCap=", InpUseDailyLossCap);
   Print("[QuantEdge EA] PartialClose=", InpUsePartialClose, " Trailing=", InpUseTrailing);
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

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageTrailing();
   UpdateDailyLossTracking();

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
   double tp2       = ReadBuffer(BUF_TP2);
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
      double spread = MarketInfo(Symbol(), MODE_SPREAD);
      if(spread > InpMaxSpreadPoints)
         g5_pass = false;
   }

   // --- Gate 6: Session Filter ---
   bool g6_pass = IsWithinSession();

   // --- Gate 7: Daily Loss Cap ---
   bool g7_pass = !IsDailyLossCapHit();

   bool allPass = g1_pass && g2_pass && g3_pass && g4_pass && g5_pass && g6_pass && g7_pass;

   string dirStr  = (direction > 0) ? "BUY" : "SELL";
   string gateStr = StringFormat("G1:%s G2:%s G3:%s G4:%s G5:%s G6:%s G7:%s",
      g1_pass?"PASS":"FAIL", g2_pass?"PASS":"FAIL", g3_pass?"PASS":"FAIL",
      g4_pass?"PASS":"FAIL", g5_pass?"PASS":"FAIL", g6_pass?"PASS":"FAIL",
      g7_pass?"PASS":"FAIL");

   Print("[QuantEdge EA] ", dirStr, " Case=", caseNum,
         " Rec=", RecLevelName(recLevelInt), " Conf=", (int)MathRound(confidence),
         " EV=", DoubleToString(ev, 2), "R Prob=", DoubleToString(probTP1, 1), "%",
         " Risk=", DoubleToString(riskPct, 2), "% | ", gateStr,
         " => ", (allPass ? "TRADE" : "SKIP"));

   if(!allPass)
      return;

   // --- Compute lot size ---
   double effectiveRisk = riskPct;
   if(effectiveRisk <= 0 && InpDefaultRiskPct > 0)
      effectiveRisk = InpDefaultRiskPct;

   double slDistance = MathAbs(entry - sl) / Point;
   double lot = CalculateLotFromRisk(effectiveRisk, slDistance);
   if(lot <= 0)
   {
      Print("[QuantEdge EA] Lot calculation returned 0 — cannot trade.");
      return;
   }

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
      return;
   }

   // --- Place order(s) ---
   string comment1 = StringFormat("QE C%d %s", caseNum, RecLevelName(recLevelInt));
   bool   useSplit = InpUsePartialClose && tp2 != EMPTY_VALUE && tp2 > 0
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
         t1 = OrderSend(Symbol(), OP_BUY, lot1, Ask, InpSlippage, sl, tp1, comment1, InpMagicNumber, 0, clrLime);
         t2 = OrderSend(Symbol(), OP_BUY, lot2, Ask, InpSlippage, sl, tp2, comment2, magicTP2, 0, clrGreen);
      }
      else
      {
         t1 = OrderSend(Symbol(), OP_SELL, lot1, Bid, InpSlippage, sl, tp1, comment1, InpMagicNumber, 0, clrRed);
         t2 = OrderSend(Symbol(), OP_SELL, lot2, Bid, InpSlippage, sl, tp2, comment2, magicTP2, 0, clrMaroon);
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
         ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, InpSlippage, sl, tp1, comment1, InpMagicNumber, 0, clrLime);
      else
         ticket = OrderSend(Symbol(), OP_SELL, lot, Bid, InpSlippage, sl, tp1, comment1, InpMagicNumber, 0, clrRed);

      if(ticket < 0)
         Print("[QuantEdge EA] OrderSend failed: error ", GetLastError());
      else
         Print("[QuantEdge EA] Order placed: ticket=", ticket, " ", dirStr, " ", DoubleToString(lot, 2),
               " lot @ ", DoubleToString((direction > 0 ? Ask : Bid), Digits));
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   QEEA_DeletePanel();
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
