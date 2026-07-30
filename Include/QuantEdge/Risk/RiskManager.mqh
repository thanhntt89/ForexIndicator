//+------------------------------------------------------------------+
//|                                            RiskManager.mqh        |
//|                         QuantEdge - Portfolio Risk Manager      |
//|                                                                    |
//| Manages concurrent signal exposure, daily trade limits, and       |
//| circuit breaker for drawdown protection.                          |
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
   g_portfolioRisk.maxDailyDD           = InpMaxDailyDrawdown;
   g_portfolioRisk.circuitBreakerActive = false;
   g_portfolioRisk.dailyTradeCount      = 0;
   g_portfolioRisk.maxDailyTrades       = InpMaxDailyTrades;
   g_portfolioRisk.lastResetDate        = 0;
}

void ResetDailyCounters()
{
   g_portfolioRisk.dailyPnLPips         = 0;
   g_portfolioRisk.dailyDrawdownPct     = 0;
   g_portfolioRisk.circuitBreakerActive = false;
   g_portfolioRisk.dailyTradeCount      = 0;
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

   if(g_portfolioRisk.dailyDrawdownPct >= g_portfolioRisk.maxDailyDD)
      g_portfolioRisk.circuitBreakerActive = true;

   g_portfolioRisk.totalExposurePct = pending * GetActiveRiskPct();
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
