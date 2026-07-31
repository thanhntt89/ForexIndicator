//+------------------------------------------------------------------+
//|                                            SessionFilter.mqh       |
//+------------------------------------------------------------------+
#ifndef QE_SESSIONFILTER_MQH
#define QE_SESSIONFILTER_MQH

#include "../Core/Config.mqh"
#include "Normalize.mqh"
#include "IntermarketAnalysis.mqh"

double GetSessionQuality(int caseNum, datetime signalTime)
{
   if(!InpUseSessionFilter) return(0.5);
   
   // Use UTC hour instead of broker local time
   int hour = GetUTCHour(signalTime);
   
   bool isAsian    = (hour >= 0 && hour < 8);
   bool isLondon   = (hour >= 8 && hour < 12);
   bool isOverlap  = (hour >= 12 && hour < 16);
   bool isLateNY   = (hour >= 16 && hour < 22);
   bool isDeadZone = (hour >= 22);
   
   // Crypto = 24/7, no session preference
   if(DetectInstrumentType() == INST_CRYPTO) return(0.5);
   
   if(isDeadZone) return(0.2);

   switch(caseNum)
   {
      case 1: case 5: case 9:
         if(isAsian) return(0.7); if(isLondon) return(0.5);
         if(isOverlap) return(0.4); return(0.6);
      case 2: case 3:
         if(isAsian) return(0.4); if(isLondon) return(0.8);
         if(isOverlap) return(0.7); return(0.5);
      case 4: case 7: case 8:
         if(isAsian) return(0.3); if(isLondon) return(0.9);
         if(isOverlap) return(0.8); return(0.4);
      case 6:
         if(isAsian) return(0.4); if(isLondon) return(0.7);
         if(isOverlap) return(0.8); return(0.5);
   }
   return(0.5);
}

#endif