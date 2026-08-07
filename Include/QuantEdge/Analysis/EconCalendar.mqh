//+------------------------------------------------------------------+
//|                                            EconCalendar.mqh       |
//|                    QuantEdge - Economic Calendar Blackout Gate   |
//|                                                                    |
//| Hard gate: block trading ±N minutes around high-impact USD/XAU     |
//| events (NFP/FOMC/CPI). Price gaps discontinuously during these     |
//| windows — every probability model becomes meaningless.            |
//|                                                                    |
//| MT5: uses built-in MqlCalendarValue API (accurate, automatic).    |
//| MT4: no built-in calendar API — blackout gate always passes        |
//| (no blocking) until a data source is decided.                     |
//+------------------------------------------------------------------+
#ifndef QE_ECONCALENDAR_MQH
#define QE_ECONCALENDAR_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"

#ifdef __MQL5__

//+------------------------------------------------------------------+
//| Check if current time falls within ±InpEconBlackoutMin of a       |
//| high-impact calendar event for the account's currencies.          |
//+------------------------------------------------------------------+
bool IsInEconBlackout()
{
   if(!InpUseEconCalendar) return(false);

   datetime now = TimeCurrent();
   datetime from = now - InpEconBlackoutMin * 60;
   datetime to   = now + InpEconBlackoutMin * 60;

   MqlCalendarValue values[];
   string baseCurrency  = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_BASE);
   string profitCurrency = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT);

   int count = CalendarValueHistory(values, from, to, NULL, NULL);
   if(count <= 0) return(false);

   for(int i = 0; i < count; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;
      if(event.importance != CALENDAR_IMPORTANCE_HIGH) continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;

      if(country.currency == baseCurrency || country.currency == profitCurrency)
         return(true);
   }

   return(false);
}

#else // MT4: no built-in calendar API — always pass (no blackout)

bool IsInEconBlackout()
{
   return(false);
}

#endif

//+------------------------------------------------------------------+
//| For EA Gate 9: returns true if trading is currently allowed        |
//| (i.e. NOT in a blackout window)                                    |
//+------------------------------------------------------------------+
bool IsEconGatePassed()
{
   if(!InpUseEconCalendar) return(true);
   return(!IsInEconBlackout());
}

//+------------------------------------------------------------------+
//| Panel display text                                                  |
//+------------------------------------------------------------------+
string GetEconCalendarDisplayText()
{
   if(!InpUseEconCalendar) return("");
   return(IsInEconBlackout() ? "Econ Calendar: BLACKOUT" : "Econ Calendar: Clear");
}

//+------------------------------------------------------------------+
//| Panel display color                                                 |
//+------------------------------------------------------------------+
color GetEconCalendarDisplayColor()
{
   return(IsInEconBlackout() ? clrRed : clrLime);
}

//+------------------------------------------------------------------+
//| Publish blackout state via GlobalVariable so the EA (separate       |
//| program instance) can read it without duplicating calendar logic. |
//+------------------------------------------------------------------+
void PublishEconBlackoutState()
{
   if(!InpUseEconCalendar) return;
   GlobalVariableSet("QE_EconBlackout_" + Symbol(), IsInEconBlackout() ? 1.0 : 0.0);
}

#endif
