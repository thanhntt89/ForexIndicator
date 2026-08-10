//+------------------------------------------------------------------+
//|                                        VirtualTradeTracker.mqh     |
//|                    QuantEdge - Virtual Trade Simulation Engine    |
//|                                                                    |
//| Sprint 6: Tracks virtual positions per signal (Market + Pullback  |
//| zones). 2-tier architecture: Tier 1 (every tick, arithmetic only) |
//| / Tier 2 (bar close, chart redraw + CSV flush).                   |
//+------------------------------------------------------------------+
#ifndef QE_VIRTUAL_TRADE_TRACKER_MQH
#define QE_VIRTUAL_TRADE_TRACKER_MQH

//+------------------------------------------------------------------+
//| VP_AddPosition — circular buffer insert                            |
//| Prefers recycling a resolved slot; if none, overwrites writeHead. |
//+------------------------------------------------------------------+
int VP_AddPosition(VirtualPosition &pos)
{
   for(int i = 0; i < g_vpCount; i++)
   {
      if(g_virtualPositions[i].finalOutcome != 0 && g_virtualPositions[i].signalTime > 0)
      {
         g_virtualPositions[i] = pos;
         return(i);
      }
   }
   if(g_vpCount < MAX_VIRTUAL_POS)
   {
      g_virtualPositions[g_vpCount] = pos;
      g_vpCount++;
      return(g_vpCount - 1);
   }
   int slot = g_vpWriteHead;
   g_virtualPositions[slot] = pos;
   g_vpWriteHead = (g_vpWriteHead + 1) % MAX_VIRTUAL_POS;
   return(slot);
}

//+------------------------------------------------------------------+
//| OnNewSignal — spawns virtual positions for all valid zones         |
//| Called ONCE per genuinely new signal (guarded in File 6).          |
//+------------------------------------------------------------------+
void OnNewSignal(const SignalData &sig)
{
   if(!InpEnableVirtualTrades) return;
   if(g_validZoneCount <= 0)   return;

   int sessBlock = GetSessionBlock(sig.signalTime);
   string sessName = SL_GetSessionName(sessBlock);

   for(int z = 0; z < g_validZoneCount; z++)
   {
      if(!g_entryZones[z].isValid) continue;

      VirtualPosition vp;
      ZeroMemory(vp);

      vp.signalTime    = sig.signalTime;
      vp.signalCaseNum = sig.caseNumber;
      vp.zoneIndex     = z;
      vp.entryType     = g_entryZones[z].zoneName;
      vp.entryPrice    = g_entryZones[z].price;
      vp.isBuy         = sig.isBuySignal;
      vp.sessionName   = sessName;

      double slDist  = g_entryZones[z].slDistance;
      double tp1Dist = g_entryZones[z].tp1Distance;
      if(vp.isBuy)
      {
         vp.stopLoss    = vp.entryPrice - slDist;
         vp.takeProfit1 = vp.entryPrice + tp1Dist;
         vp.takeProfit2 = vp.entryPrice + tp1Dist * g_cfgTP2Mult;
         vp.takeProfit3 = vp.entryPrice + tp1Dist * g_cfgTP3Mult;
      }
      else
      {
         vp.stopLoss    = vp.entryPrice + slDist;
         vp.takeProfit1 = vp.entryPrice - tp1Dist;
         vp.takeProfit2 = vp.entryPrice - tp1Dist * g_cfgTP2Mult;
         vp.takeProfit3 = vp.entryPrice - tp1Dist * g_cfgTP3Mult;
      }

      if(z == 0)
      {
         vp.isActivated    = true;
         vp.activationTime = sig.signalTime;
      }

      vp.objectName = "VH_" + IntegerToString((long)sig.signalTime) + "_Z" + IntegerToString(z);

      VP_AddPosition(vp);
   }
}

//+------------------------------------------------------------------+
//| VP_CheckActivation — pullback zone activation                      |
//+------------------------------------------------------------------+
void VP_CheckActivation(int idx, double bid, double ask)
{
   if(g_virtualPositions[idx].isActivated) return;

   if(g_virtualPositions[idx].isBuy)
   {
      if(ask <= g_virtualPositions[idx].entryPrice)
      {
         g_virtualPositions[idx].isActivated    = true;
         g_virtualPositions[idx].activationTime = TimeCurrent();
      }
   }
   else
   {
      if(bid >= g_virtualPositions[idx].entryPrice)
      {
         g_virtualPositions[idx].isActivated    = true;
         g_virtualPositions[idx].activationTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| VP_HitTP — update maxTPReached (monotonic high-water mark)         |
//+------------------------------------------------------------------+
void VP_HitTP(int idx, int tpLevel, datetime t, double price)
{
   if(tpLevel <= g_virtualPositions[idx].maxTPReached) return;

   g_virtualPositions[idx].maxTPReached = tpLevel;
   if(tpLevel >= 1 && tpLevel <= 3)
      g_virtualPositions[idx].tpTime[tpLevel] = t;
   g_virtualPositions[idx].needsRedraw = true;

   if(tpLevel == 3)
   {
      g_virtualPositions[idx].finalOutcome = 1;
      g_virtualPositions[idx].outcomeTime  = t;
      g_virtualPositions[idx].closePrice   = price;
      g_virtualPositions[idx].needsLog     = true;
   }
}

//+------------------------------------------------------------------+
//| VP_UpdateMFE_MAE — track excursion in price units                  |
//+------------------------------------------------------------------+
void VP_UpdateMFE_MAE(int idx, double bid, double ask)
{
   if(!g_virtualPositions[idx].isActivated) return;

   double checkPrice = g_virtualPositions[idx].isBuy ? bid : ask;
   double excursion = g_virtualPositions[idx].isBuy
      ? (checkPrice - g_virtualPositions[idx].entryPrice)
      : (g_virtualPositions[idx].entryPrice - checkPrice);

   if(excursion > g_virtualPositions[idx].mfe)
      g_virtualPositions[idx].mfe = excursion;

   double adverse = -excursion;
   if(adverse > g_virtualPositions[idx].mae)
      g_virtualPositions[idx].mae = adverse;
}

//+------------------------------------------------------------------+
//| VP_CheckSLTP — check TP3→TP2→TP1→SL (high levels first)           |
//+------------------------------------------------------------------+
void VP_CheckSLTP(int idx, double bid, double ask)
{
   if(!g_virtualPositions[idx].isActivated) return;

   datetime now = TimeCurrent();
   double checkPrice = g_virtualPositions[idx].isBuy ? bid : ask;

   if(g_virtualPositions[idx].isBuy)
   {
      if(checkPrice >= g_virtualPositions[idx].takeProfit3) VP_HitTP(idx, 3, now, checkPrice);
      if(checkPrice >= g_virtualPositions[idx].takeProfit2) VP_HitTP(idx, 2, now, checkPrice);
      if(checkPrice >= g_virtualPositions[idx].takeProfit1) VP_HitTP(idx, 1, now, checkPrice);

      if(checkPrice <= g_virtualPositions[idx].stopLoss)
      {
         g_virtualPositions[idx].finalOutcome = -1;
         g_virtualPositions[idx].outcomeTime  = now;
         g_virtualPositions[idx].closePrice   = checkPrice;
         g_virtualPositions[idx].needsRedraw  = true;
         g_virtualPositions[idx].needsLog     = true;
      }
   }
   else
   {
      if(checkPrice <= g_virtualPositions[idx].takeProfit3) VP_HitTP(idx, 3, now, checkPrice);
      if(checkPrice <= g_virtualPositions[idx].takeProfit2) VP_HitTP(idx, 2, now, checkPrice);
      if(checkPrice <= g_virtualPositions[idx].takeProfit1) VP_HitTP(idx, 1, now, checkPrice);

      if(checkPrice >= g_virtualPositions[idx].stopLoss)
      {
         g_virtualPositions[idx].finalOutcome = -1;
         g_virtualPositions[idx].outcomeTime  = now;
         g_virtualPositions[idx].closePrice   = checkPrice;
         g_virtualPositions[idx].needsRedraw  = true;
         g_virtualPositions[idx].needsLog     = true;
      }
   }
}

//+------------------------------------------------------------------+
//| UpdateVirtualPositions_Tick — Tier 1: every tick, arithmetic only  |
//+------------------------------------------------------------------+
void UpdateVirtualPositions_Tick(double bid, double ask)
{
   for(int i = 0; i < g_vpCount; i++)
   {
      if(g_virtualPositions[i].finalOutcome != 0) continue;
      if(g_virtualPositions[i].signalTime == 0)   continue;

      VP_CheckActivation(i, bid, ask);
      VP_CheckSLTP(i, bid, ask);
      VP_UpdateMFE_MAE(i, bid, ask);
   }
}

//+------------------------------------------------------------------+
//| VP_GetOutcomeColor — green if any TP was reached, red otherwise   |
//+------------------------------------------------------------------+
color VP_GetOutcomeColor(const VirtualPosition &vp)
{
   return(vp.maxTPReached > 0) ? InpColorVirtualTP : InpColorVirtualSL;
}

//+------------------------------------------------------------------+
//| UpdateVirtualPositions_OnBar — Tier 2: chart redraw + CSV flush   |
//+------------------------------------------------------------------+
void UpdateVirtualPositions_OnBar()
{
   for(int i = 0; i < g_vpCount; i++)
   {
      if(g_virtualPositions[i].signalTime == 0) continue;

      if(g_virtualPositions[i].needsRedraw)
      {
         color clr = VP_GetOutcomeColor(g_virtualPositions[i]);

         datetime t2 = (g_virtualPositions[i].outcomeTime > 0)
                        ? g_virtualPositions[i].outcomeTime : TimeCurrent();
         double   p2 = (g_virtualPositions[i].closePrice  > 0)
                        ? g_virtualPositions[i].closePrice  : MarketInfo(Symbol(), MODE_BID);

         if(!g_virtualPositions[i].historyDrawn)
         {
            CreateHistoryLine(g_virtualPositions[i].objectName,
                              g_virtualPositions[i].activationTime,
                              g_virtualPositions[i].entryPrice,
                              t2, p2, clr,
                              InpHistoryLineWidth, InpHistoryLineStyle);
            g_virtualPositions[i].historyDrawn = true;
         }
         else
         {
            UpdateHistoryLineEnd(g_virtualPositions[i].objectName, t2, p2, clr);
         }
         g_virtualPositions[i].needsRedraw = false;
      }

      if(g_virtualPositions[i].needsLog)
      {
         double atr = 0;
         for(int s = g_signalCount - 1; s >= 0; s--)
         {
            if(g_signals[s].signalTime == g_virtualPositions[i].signalTime &&
               g_signals[s].caseNumber == g_virtualPositions[i].signalCaseNum)
            {
               atr = g_signals[s].atrValue;
               break;
            }
         }
         AppendVirtualTradeLog(g_virtualPositions[i], atr);
         g_virtualPositions[i].needsLog = false;
      }
   }

   FlushPendingCSVLogs();
}

//+------------------------------------------------------------------+
//| VP_CloseAllBySignal — reversal close for an old signal's trades   |
//| Called BEFORE OnNewSignal() when direction reverses.               |
//+------------------------------------------------------------------+
void VP_CloseAllBySignal(datetime oldSignalTime, double bid, double ask)
{
   datetime now = TimeCurrent();
   for(int i = 0; i < g_vpCount; i++)
   {
      if(g_virtualPositions[i].signalTime != oldSignalTime) continue;
      if(g_virtualPositions[i].finalOutcome != 0)           continue;

      g_virtualPositions[i].finalOutcome = -2;
      g_virtualPositions[i].outcomeTime  = now;
      g_virtualPositions[i].closePrice   = g_virtualPositions[i].isBuy ? bid : ask;

      if(g_virtualPositions[i].isActivated)
      {
         g_virtualPositions[i].needsRedraw = true;
         g_virtualPositions[i].needsLog    = true;
      }
   }
}

#endif
