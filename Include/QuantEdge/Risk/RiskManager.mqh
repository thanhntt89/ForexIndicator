//+------------------------------------------------------------------+
//|                                            RiskManager.mqh        |
//|                         QuantEdge - Portfolio Risk Manager      |
//|                                                                    |
//| Multi-level circuit breaker with drawdown scaling.                 |
//| Green(100%) -> Yellow(50%) -> Orange(25%) -> Red(STOP).           |
//| Only gates LIVE signals (recent bars), not historical arrows.     |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_RISKMANAGER_MQH
#define RSI_ADV_RISKMANAGER_MQH

void InitPortfolioRisk()
{
   g_portfolioRisk.openSignals          = 0;
   g_portfolioRisk.maxSignals           = InpMaxOpenSignals;
   g_portfolioRisk.totalExposurePct     = 0;
   g_portfolioRisk.maxExposurePct       = InpMaxDailyRiskPct;
   g_portfolioRisk.dailyPnLPips         = 0;
   g_portfolioRisk.dailyDrawdownPct     = 0;
   g_portfolioRisk.circuitBreakerActive = false;
   g_portfolioRisk.dailyTradeCount      = 0;
   g_portfolioRisk.maxDailyTrades       = InpMaxDailyTrades;
   g_portfolioRisk.lastResetDate        = 0;
   g_portfolioRisk.ddScale              = 1.0;
   g_portfolioRisk.cbLevel              = 0;
   g_portfolioRisk.equityHWM            = 0;
   g_portfolioRisk.rollingMaxDD         = 0;
}

void ResetDailyCounters()
{
   g_portfolioRisk.dailyPnLPips         = 0;
   g_portfolioRisk.dailyDrawdownPct     = 0;
   g_portfolioRisk.circuitBreakerActive = false;
   g_portfolioRisk.dailyTradeCount      = 0;
   g_portfolioRisk.ddScale              = 1.0;
   g_portfolioRisk.cbLevel              = 0;
   g_portfolioRisk.equityHWM            = 0;
   g_portfolioRisk.rollingMaxDD         = 0;
}

void UpdatePortfolioRisk()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = TimeCurrent() - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   if(g_portfolioRisk.lastResetDate != today)
   {
      ResetDailyCounters();
      g_portfolioRisk.lastResetDate = today;
   }

   int pending = 0;
   double dayPL = 0;
   double dayLoss = 0;
   for(int i = 0; i < g_outcomeCount; i++)
   {
      if(g_outcomes[i].outcome == 0)
      {
         pending++;
         continue;
      }
      if(g_outcomes[i].outcomeTime >= today)
      {
         double pl = 0;
         if(g_outcomes[i].outcome > 0)
            pl = g_outcomes[i].mfe;
         else
            pl = -g_outcomes[i].mae;
         dayPL += pl;
         if(pl < 0) dayLoss += pl;
      }
   }
   g_portfolioRisk.openSignals = pending;
   g_portfolioRisk.dailyPnLPips = dayPL;

   double acctBal = AccountBalance();
   if(acctBal > 0)
      g_portfolioRisk.dailyDrawdownPct = MathAbs(dayLoss) / acctBal * 100.0;

   // --- Equity high-water mark (intraday) ---
   double equity = AccountEquity();
   if(equity > g_portfolioRisk.equityHWM)
      g_portfolioRisk.equityHWM = equity;

   // --- Rolling max DD from last 10 resolved outcomes ---
   double peakPL = 0, maxDD = 0, runningPL = 0;
   int counted = 0;
   for(int j = g_outcomeCount - 1; j >= 0 && counted < 10; j--)
   {
      if(g_outcomes[j].outcome == 0) continue;
      counted++;
      double pl = 0;
      if(g_outcomes[j].outcome > 0)
         pl = g_outcomes[j].mfe;
      else
         pl = -g_outcomes[j].mae;
      runningPL += pl;
      if(runningPL > peakPL) peakPL = runningPL;
      double dd = peakPL - runningPL;
      if(dd > maxDD) maxDD = dd;
   }
   if(acctBal > 0 && counted > 0)
      g_portfolioRisk.rollingMaxDD = maxDD / acctBal * 100.0;

   // --- Multi-level circuit breaker ---
   double dd = g_portfolioRisk.dailyDrawdownPct;
   if(dd >= InpDDRedPct)
   {
      g_portfolioRisk.cbLevel = 3;
      g_portfolioRisk.ddScale = 0.0;
      g_portfolioRisk.circuitBreakerActive = true;
   }
   else if(dd >= InpDDOrangePct)
   {
      g_portfolioRisk.cbLevel = 2;
      g_portfolioRisk.ddScale = 0.25;
      g_portfolioRisk.circuitBreakerActive = false;
   }
   else if(dd >= InpDDYellowPct)
   {
      g_portfolioRisk.cbLevel = 1;
      g_portfolioRisk.ddScale = 0.50;
      g_portfolioRisk.circuitBreakerActive = false;
   }
   else
   {
      g_portfolioRisk.cbLevel = 0;
      g_portfolioRisk.ddScale = 1.0;
      g_portfolioRisk.circuitBreakerActive = false;
   }

   g_portfolioRisk.totalExposurePct = pending * GetEffectiveRiskPct();
}

bool CanTakeNewSignal()
{
   if(g_portfolioRisk.circuitBreakerActive) return(false);
   if(g_portfolioRisk.openSignals >= g_portfolioRisk.maxSignals) return(false);
   if(g_portfolioRisk.totalExposurePct >= g_portfolioRisk.maxExposurePct) return(false);
   if(g_portfolioRisk.dailyTradeCount >= g_portfolioRisk.maxDailyTrades) return(false);
   return(true);
}

void OnNewSignalAccepted()
{
   g_portfolioRisk.dailyTradeCount++;
}

#endif
