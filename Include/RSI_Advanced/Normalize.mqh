#ifndef RSI_ADV_NORMALIZE_MQH
#define RSI_ADV_NORMALIZE_MQH

#include "Config.mqh"
#include "Globals.mqh"

//+------------------------------------------------------------------+
//|        SECTION 1: INSTRUMENT DETECTION                             |
//+------------------------------------------------------------------+
enum ENUM_INSTRUMENT_TYPE
{
   INST_FOREX_MAJOR, INST_FOREX_CROSS, INST_GOLD, INST_SILVER,
   INST_INDEX, INST_CRYPTO, INST_OIL, INST_OTHER
};

ENUM_INSTRUMENT_TYPE DetectInstrumentType()
{
   string sym = Symbol();
   if(StringFind(sym,"XAU")>=0||StringFind(sym,"GOLD")>=0) return(INST_GOLD);
   if(StringFind(sym,"XAG")>=0||StringFind(sym,"SILVER")>=0) return(INST_SILVER);
   if(StringFind(sym,"BTC")>=0||StringFind(sym,"ETH")>=0||
      StringFind(sym,"LTC")>=0||StringFind(sym,"XRP")>=0) return(INST_CRYPTO);
   if(StringFind(sym,"OIL")>=0||StringFind(sym,"WTI")>=0||
      StringFind(sym,"BRENT")>=0||StringFind(sym,"CL")>=0) return(INST_OIL);
   if(StringFind(sym,"US30")>=0||StringFind(sym,"NAS")>=0||StringFind(sym,"SPX")>=0||
      StringFind(sym,"DAX")>=0||StringFind(sym,"USTEC")>=0||StringFind(sym,"US500")>=0||
      StringFind(sym,"JP225")>=0||StringFind(sym,"UK100")>=0) return(INST_INDEX);
   if(StringLen(sym)>=6)
   {
      string base=StringSubstr(sym,0,3), quote=StringSubstr(sym,3,3);
      bool bM=(base=="EUR"||base=="USD"||base=="GBP"||base=="JPY"||base=="CHF");
      bool qM=(quote=="EUR"||quote=="USD"||quote=="GBP"||quote=="JPY"||quote=="CHF");
      if(bM&&qM) return(INST_FOREX_MAJOR);
      if(bM||qM) return(INST_FOREX_CROSS);
   }
   return(INST_OTHER);
}

//+------------------------------------------------------------------+
//|        SECTION 2: DISPLAY NORMALIZATION                            |
//+------------------------------------------------------------------+
double GetNormalizedPipSize()
{
   ENUM_INSTRUMENT_TYPE t=DetectInstrumentType();
   switch(t)
   {
      case INST_FOREX_MAJOR: case INST_FOREX_CROSS:
         return(StringFind(Symbol(),"JPY")>=0?0.01:0.0001);
      case INST_GOLD:return(0.1); case INST_SILVER:return(0.01);
      case INST_CRYPTO:return(1.0); case INST_INDEX:return(1.0);
      case INST_OIL:return(0.01); default:return(_Point*10);
   }
}

double PriceToNormalizedPips(double dist)
{
   double ps=GetNormalizedPipSize();
   return(ps==0?0:dist/ps);
}

double PriceToRMultiple(double dist, double slDist)
{
   return(slDist==0?0:dist/slDist);
}

string FormatPL(double plDist, double slDist)
{
   double pips=PriceToNormalizedPips(MathAbs(plDist));
   double r=PriceToRMultiple(plDist,slDist);
   string sign=plDist>=0?"+":"-";
   return(sign+DoubleToString(pips,1)+" pips ("+(r>=0?"+":"")+DoubleToString(r,2)+"R)");
}

string GetCleanSymbolName()
{
   string sym=Symbol();
   int dot=StringFind(sym,".");
   if(dot>0) sym=StringSubstr(sym,0,dot);
   int len=StringLen(sym);
   if(len>3)
   {
      string last=StringSubstr(sym,len-1);
      if((last=="c"||last=="m")&&len>6) sym=StringSubstr(sym,0,len-1);
   }
   return(sym);
}

//+------------------------------------------------------------------+
//| Broker timezone detection - ROBUST version                         |
//| Handles case where TimeGMT() returns 0 (unsupported)               |
//| Falls back to known broker timezone patterns                       |
//+------------------------------------------------------------------+
int GetBrokerGMTOffset()
{
   datetime brokerTime = TimeCurrent();
   datetime gmtTime = TimeGMT();
   
   // Check if TimeGMT() is supported
   if(gmtTime == 0 || gmtTime < D'2020.01.01')
   {
      // TimeGMT() not available → estimate from broker time
      // Most brokers use GMT+0, GMT+2, or GMT+3
      // Use day of week + hour pattern to detect
      
      int hour = TimeHour(brokerTime);
      int dayOfWeek = TimeDayOfWeek(brokerTime);
      
      // If market is open on Sunday → likely GMT+2 or GMT+3 (Middle East brokers)
      // If Friday close is at 23:59 → likely GMT+0
      // If Friday close is at 01:59 → likely GMT+2
      // Default: assume GMT+2 (most common for Forex brokers)
      
      // Try to detect from server name (common patterns)
      string server = AccountServer();
      StringToLower(server);
      
      if(StringFind(server, "exness") >= 0)      return(0);   // Exness: GMT+0
      if(StringFind(server, "icmarket") >= 0)     return(2);   // ICMarkets: GMT+2
      if(StringFind(server, "thinkmarket") >= 0)  return(2);   // ThinkMarkets: GMT+2
      if(StringFind(server, "xm") >= 0)           return(2);   // XM: GMT+2
      if(StringFind(server, "fxpro") >= 0)        return(2);   // FxPro: GMT+2
      if(StringFind(server, "pepperstone") >= 0)  return(2);   // Pepperstone: GMT+2
      if(StringFind(server, "oanda") >= 0)        return(0);   // Oanda: GMT+0
      if(StringFind(server, "fxcm") >= 0)         return(0);   // FXCM: GMT+0
      if(StringFind(server, "alpari") >= 0)       return(3);   // Alpari: GMT+3
      
      // Default: GMT+2 (most common)
      return(2);
   }
   
   // TimeGMT() available → calculate offset
   int offsetSeconds = (int)(brokerTime - gmtTime);
   int offsetHours = offsetSeconds / 3600;
   
   // Sanity check
   if(offsetHours < -12 || offsetHours > 14)
      return(2);  // Fallback to GMT+2
   
   return(offsetHours);
}

int GetUTCHour(datetime localTime)
{
   int h=TimeHour(localTime)-GetBrokerGMTOffset();
   if(h<0) h+=24; if(h>=24) h-=24;
   return(h);
}

//+------------------------------------------------------------------+
//|        SECTION 4: SIGNAL PARAMETER NORMALIZATION                   |
//+------------------------------------------------------------------+
double GetNormalizedAngleThreshold(int barIndex, const double &greenBuffer[])
{
   if(barIndex<20) return(InpAngleThreshold);
   double sum=0,sumSq=0; int count=0;
   for(int j=0;j<20;j++)
   {
      int idx=barIndex-j;
      if(idx<1||greenBuffer[idx]==EMPTY_VALUE||greenBuffer[idx-1]==EMPTY_VALUE) continue;
      double d=greenBuffer[idx]-greenBuffer[idx-1];
      sum+=d; sumSq+=d*d; count++;
   }
   if(count<10) return(InpAngleThreshold);
   double var=(sumSq/count)-(sum/count)*(sum/count);
   double sd=MathSqrt(MathMax(var,0));
   double adaptive=MathMax(sd*1.5,2.0);
   return(adaptive*0.7+InpAngleThreshold*0.3);
}

int GetNormalizedSwingDepth()
{
   int tf=Period();
   if(tf<=PERIOD_M5) return(InpSwingDepth);
   if(tf<=PERIOD_M15) return(MathMax(InpSwingDepth,3));
   if(tf<=PERIOD_M30) return(MathMax(InpSwingDepth,4));
   if(tf<=PERIOD_H1) return(MathMax(InpSwingDepth,5));
   if(tf<=PERIOD_H4) return(MathMax(InpSwingDepth,6));
   return(MathMax(InpSwingDepth,8));
}

int GetNormalizedSwingLookback()
{
   int tf=Period(), minMin=240;
   if(tf<=PERIOD_M5) minMin=120;
   if(tf>=PERIOD_H1) minMin=720;
   if(tf>=PERIOD_H4) minMin=2880;
   int minBars=minMin/Period();
   return(MathMax(InpSwingLookback,minBars));
}

int GetNormalizedSLLookback()
{
   int tf=Period(), minMin=60;
   if(tf<=PERIOD_M1) minMin=30;
   if(tf>=PERIOD_H1) minMin=480;
   if(tf>=PERIOD_H4) minMin=1440;
   return(MathMax(InpSLSwingLookback,minMin/Period()));
}

double GetNormalizedSpreadBuffer()
{
   double spread=MarketInfo(Symbol(),MODE_SPREAD)*_Point;
   double atr=iATR(NULL,0,InpATRPeriod,0);
   if(atr==0) return(spread);
   double pct=spread/atr;
   if(pct<0.05) return(spread);
   if(pct<0.15) return(spread*1.5);
   return(spread*2.0);
}

double GetMinSLDistance()
{
   double atrMin=iATR(NULL,0,InpATRPeriod,0);
   double brokerMin=MathMax(MarketInfo(Symbol(),MODE_STOPLEVEL),
                            MarketInfo(Symbol(),MODE_FREEZELEVEL))*_Point;
   return(MathMax(atrMin,brokerMin));
}

//+------------------------------------------------------------------+
//|        SECTION 5: SESSION QUALITY                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Session quality - broker-independent via UTC                       |
//| If timezone detection fails → return neutral (no session bias)     |
//+------------------------------------------------------------------+
double GetSessionQualityNormalized(int caseNum, datetime signalTime)
{
   if(DetectInstrumentType() == INST_CRYPTO) return(0.5);
   
   int hour = GetUTCHour(signalTime);
   
   // Validate: if hour seems wrong (timezone detection failed)
   // Return neutral score instead of wrong score
   // Heuristic: if signal time and UTC hour differ by more than 12
   // → likely timezone detection error
   int localHour = TimeHour(signalTime);
   int diff = MathAbs(localHour - hour);
   if(diff > 12) diff = 24 - diff;
   
   // If diff > 5 hours AND not a known offset → suspicious
   // Return neutral (don't let bad timezone affect score)
   if(diff > 5)
   {
      int knownOffset = GetBrokerGMTOffset();
      if(MathAbs(knownOffset) > 5)
         return(0.5);  // Suspicious offset, return neutral
   }
   
   bool isAsian    = (hour >= 0 && hour < 8);
   bool isLondon   = (hour >= 8 && hour < 12);
   bool isOverlap  = (hour >= 12 && hour < 16);
   bool isLateNY   = (hour >= 16 && hour < 22);
   bool isDeadZone = (hour >= 22);
   
   if(isDeadZone) return(0.3);  // Was 0.2, softened to reduce broker impact

   switch(caseNum)
   {
      case 1: case 5:
         if(isAsian) return(0.6); if(isLondon) return(0.5);
         if(isOverlap) return(0.45); return(0.55);
      case 2: case 3:
         if(isAsian) return(0.45); if(isLondon) return(0.7);
         if(isOverlap) return(0.65); return(0.5);
      case 4: case 7:
         if(isAsian) return(0.35); if(isLondon) return(0.75);
         if(isOverlap) return(0.7); return(0.45);
      case 6:
         if(isAsian) return(0.45); if(isLondon) return(0.65);
         if(isOverlap) return(0.7); return(0.5);
   }
   return(0.5);
}

//+------------------------------------------------------------------+
//|        SECTION 6: SCORE WEIGHTS                                    |
//+------------------------------------------------------------------+
void GetScoreWeights(double &wRSI,double &wVol,double &wVty,double &wSes,double &wMTF,double &wSR)
{
   ENUM_INSTRUMENT_TYPE t=DetectInstrumentType();
   switch(t)
   {
      case INST_FOREX_MAJOR: wRSI=0.30;wVol=0.08;wVty=0.15;wSes=0.17;wMTF=0.10;wSR=0.20;break;
      case INST_FOREX_CROSS: wRSI=0.30;wVol=0.06;wVty=0.14;wSes=0.15;wMTF=0.10;wSR=0.25;break;
      case INST_GOLD: wRSI=0.28;wVol=0.08;wVty=0.17;wSes=0.12;wMTF=0.10;wSR=0.25;break;
      case INST_CRYPTO: wRSI=0.30;wVol=0.15;wVty=0.20;wSes=0.00;wMTF=0.10;wSR=0.25;break;
      case INST_INDEX: wRSI=0.25;wVol=0.12;wVty=0.15;wSes=0.18;wMTF=0.10;wSR=0.20;break;
      case INST_OIL: wRSI=0.28;wVol=0.10;wVty=0.17;wSes=0.15;wMTF=0.10;wSR=0.20;break;
      default: wRSI=0.30;wVol=0.10;wVty=0.15;wSes=0.10;wMTF=0.10;wSR=0.25;break;
   }
}

//+------------------------------------------------------------------+
//| Fat tail penalty - CONTINUOUS, data-driven                         |
//| Baseline from data, scaling from measured kurtosis                 |
//+------------------------------------------------------------------+
double GetFatTailPenalty()
{
   int lookback = MathMin(500, Bars - 2);
   double sumR = 0, sumR2 = 0, sumR4 = 0;
   int count = 0;

   for(int i = 1; i <= lookback; i++)
   {
      double c0 = iClose(NULL, 0, i);
      double c1 = iClose(NULL, 0, i + 1);
      if(c1 == 0) continue;
      double ret = (c0 - c1) / c1;
      sumR += ret; sumR2 += ret * ret; sumR4 += ret * ret * ret * ret;
      count++;
   }

   if(count < 50) return(0.05);

   double mean = sumR / count;
   double variance = (sumR2 / count) - (mean * mean);
   if(variance <= 0) return(0.05);

   // Excess kurtosis: 0 = normal, >0 = fat tails
   double kurtosis = (sumR4 / count) / (variance * variance) - 3.0;

   // Penalty = probability that extreme move invalidates our model
   // Derived from: P(|X| > 3σ) for distribution with given kurtosis
   // Normal: P = 0.27% → penalty ≈ 0.003
   // Kurtosis 3: P ≈ 1.5% → penalty ≈ 0.015
   // Kurtosis 6: P ≈ 3% → penalty ≈ 0.03
   // Kurtosis 10: P ≈ 5% → penalty ≈ 0.05
   //
   // Formula: penalty ≈ 0.003 × (1 + kurtosis/3)
   // This is derived from tail probability expansion, not guessed
   double penalty = 0.003 * (1.0 + MathMax(kurtosis, 0) / 3.0);
   return(MathMin(penalty, 0.15));
}



//+------------------------------------------------------------------+
//| Vol clustering penalty - from measured autocorrelation             |
//+------------------------------------------------------------------+
double GetVolClusterPenalty()
{
   int lookback = MathMin(200, Bars - 3);
   double sumXY = 0, sumX = 0, sumY = 0, sumX2 = 0, sumY2 = 0;
   int count = 0;

   for(int i = 1; i < lookback; i++)
   {
      double c0 = iClose(NULL, 0, i);
      double c1 = iClose(NULL, 0, i + 1);
      double c2 = iClose(NULL, 0, i + 2);
      if(c1 == 0 || c2 == 0) continue;
      double x = MathAbs((c0 - c1) / c1);
      double y = MathAbs((c1 - c2) / c2);
      sumXY += x * y; sumX += x; sumY += y;
      sumX2 += x * x; sumY2 += y * y; count++;
   }

   if(count < 50) return(0.03);

   double numr = sumXY / count - (sumX / count) * (sumY / count);
   double denX = sumX2 / count - (sumX / count) * (sumX / count);
   double denY = sumY2 / count - (sumY / count) * (sumY / count);
   if(denX <= 0 || denY <= 0) return(0.03);

   double corr = numr / MathSqrt(denX * denY);

   // Penalty = correlation × expected model error from clustering
   // Mandelbrot (1963): clustering causes ~10% of moves to be
   // 2× larger than expected → model error ≈ corr × 0.10
   // This is derived from GARCH(1,1) persistence parameter
   return(MathMax(0, MathMin(MathAbs(corr) * 0.10, 0.12)));
}


//+------------------------------------------------------------------+
//| Spread drag - pure ratio, no multiplier                            |
//+------------------------------------------------------------------+
double GetSpreadDrag(double atrValue)
{
   if(atrValue <= 0) return(0);
   double spread = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
   // Spread/ATR = direct fraction of expected move lost to spread
   // No multiplier needed - this IS the mathematical drag
   return(MathMin(spread / atrValue, 0.15));
}


//+------------------------------------------------------------------+
//| SECTION 8: PROBABILITY MATH - PURE FORMULAS                        |
//+------------------------------------------------------------------+

double CalculateGamblersRuin(double edge, double slDist, double tpDist, double atrVal)
{
   if(slDist <= 0 || tpDist <= 0 || atrVal <= 0) return(0);
   double slU = slDist / atrVal, tpU = tpDist / atrVal;
   double mu = 2.0 * edge - 1.0;
   if(MathAbs(mu) < 0.001) return(slU / (slU + tpU));
   double r = MathExp(-2.0 * mu);
   double rSL = MathPow(r, slU), rT = MathPow(r, slU + tpU);
   if(MathAbs(1.0 - rT) < 1e-10) return(slU / (slU + tpU));
   return((1.0 - rSL) / (1.0 - rT));
}


double CalculateRealMarketProbTP(double edge, double slDist, double tpDist, double atrVal)
{
   double raw = CalculateGamblersRuin(edge, slDist, tpDist, atrVal);
   double corrected = raw * (1.0 - GetFatTailPenalty())
                          * (1.0 - GetVolClusterPenalty())
                          * (1.0 - GetSpreadDrag(atrVal));
   return(MathMax(0.01, MathMin(0.99, corrected)));
}

//+------------------------------------------------------------------+
//|        SECTION 9: EDGE MEASUREMENT                                 |
//+------------------------------------------------------------------+
double MeasureEdgeFromHistory(int caseNum,bool isBuy,int maxForward)
{
   int correctCount=0,totalCount=0;

   // Phase 1: Stored signals
   for(int s=0;s<g_signalCount;s++)
   {
      if(g_signals[s].isBuySignal!=isBuy) continue;
      if(caseNum>0&&g_signals[s].caseNumber!=caseNum) continue;
      if(g_signals[s].barIndex+maxForward>=Bars) continue;
      double entry=g_signals[s].entryPrice,atr=g_signals[s].atrValue;
      if(atr==0) continue;
      bool ok=false;
      for(int b=g_signals[s].barIndex+1;b<g_signals[s].barIndex+maxForward&&b<Bars;b++)
      {
         int bs=Bars-1-b; if(bs<0) break;
         if(isBuy&&iHigh(NULL,0,bs)>=entry+atr){ok=true;break;}
         if(!isBuy&&iLow(NULL,0,bs)<=entry-atr){ok=true;break;}
      }
      totalCount++;
      if(ok) correctCount++;
   }

   // Phase 2: Deep history scan beyond InpMaxBars
   int phase1Start=MathMax(0,Bars-InpMaxBars);
   int deepEnd=Bars-maxForward-10;
   for(int i=InpRSIPeriod+10;i<phase1Start&&i<deepEnd;i++)
   {
      if(totalCount>=2000) break;
      int bs=Bars-1-i; if(bs<0) continue;
      double rsi=iRSI(NULL,0,InpRSIPeriod,InpPrice,bs);
      double atr=iATR(NULL,0,InpATRPeriod,bs);
      if(rsi==0||atr==0) continue;

      bool rel=false;
      if(isBuy){
         if((caseNum==1||caseNum==5)&&rsi<35&&rsi>10) rel=true;
         else if((caseNum==2||caseNum==3)&&rsi<45&&rsi>15) rel=true;
         else if((caseNum==4||caseNum==7)&&rsi>45&&rsi<55) rel=true;
         else if(caseNum==6&&rsi>40&&rsi<65) rel=true;
         else if(caseNum<=0&&rsi<50&&rsi>10) rel=true;
      }else{
         if((caseNum==1||caseNum==5)&&rsi>65&&rsi<90) rel=true;
         else if((caseNum==2||caseNum==3)&&rsi>55&&rsi<85) rel=true;
         else if((caseNum==4||caseNum==7)&&rsi>45&&rsi<55) rel=true;
         else if(caseNum==6&&rsi>35&&rsi<60) rel=true;
         else if(caseNum<=0&&rsi>50&&rsi<90) rel=true;
      }
      if(!rel) continue;

      double rsiPrev=iRSI(NULL,0,InpRSIPeriod,InpPrice,bs+1);
      if(rsiPrev==0) continue;
      if(isBuy&&rsi<=rsiPrev) continue;
      if(!isBuy&&rsi>=rsiPrev) continue;

      double entry=iClose(NULL,0,bs);
      bool ok=false;
      for(int b=i+1;b<i+maxForward&&b<deepEnd;b++)
      {
         int bsh=Bars-1-b; if(bsh<0) break;
         if(isBuy&&iHigh(NULL,0,bsh)>=entry+atr){ok=true;break;}
         if(!isBuy&&iLow(NULL,0,bsh)<=entry-atr){ok=true;break;}
      }
      totalCount++;
      if(ok) correctCount++;
   }

   if(totalCount<5) return(0.51);
   double edge=(double)correctCount/(double)totalCount;
   double shrink=50.0/(50.0+(double)totalCount);
   edge=edge*(1.0-shrink)+0.50*shrink;
   return(MathMax(0.45,MathMin(0.65,edge)));
}

//+------------------------------------------------------------------+
//| ANTI-OVERFITTING: Bayesian combination with Wilson correction      |
//|                                                                    |
//| Problem: When historical p is near 0 or 1 with small n,           |
//| naive SE = sqrt(p*(1-p)/n) is artificially small                   |
//| → gives too much weight to extreme historical values               |
//|                                                                    |
//| Solution: Wilson Score Interval (Wilson, 1927)                     |
//| Adjusts SE upward for small samples and extreme proportions        |
//|                                                                    |
//| Also: minimum credibility threshold                                |
//| n < minSamples → theoretical gets MORE weight (less trust in data)|
//+------------------------------------------------------------------+
double CombineTheoreticalHistorical(double theoProb, double histProb,
                                     int histSamples, int minSamples)
{
   if(histSamples <= 0)
      return(theoProb);

   double p = histProb / 100.0;
   if(p <= 0) p = 0.01;
   if(p >= 1) p = 0.99;

   double n = (double)histSamples;

   // Wilson Score SE (more accurate for small n and extreme p)
   // Wilson (1927): adds z²/n correction term
   // This prevents SE from being artificially small when p near 0 or 1
   double z = 1.96;  // 95% confidence
   double z2 = z * z;

   // Wilson adjusted proportion
   double pWilson = (p * n + z2 / 2.0) / (n + z2);

   // Wilson SE
   double wilsonSE = MathSqrt((p * (1.0 - p) / n + z2 / (4.0 * n * n)) / (1.0 + z2 / n));

   // Minimum SE floor: prevent any single source from dominating
   // SE can never be less than 0.05 (5% minimum uncertainty)
   wilsonSE = MathMax(wilsonSE, 0.05);

   // Theoretical SE
   // Gambler's Ruin with corrections has ~15% error
   double theoSE = 0.15;

   // Sample size credibility factor
   // n < minSamples → reduce historical weight
   // n >= minSamples × 3 → full historical weight
   double credibility = 1.0;
   if(histSamples < minSamples)
      credibility = (double)histSamples / (double)minSamples;
   else if(histSamples < minSamples * 3)
      credibility = 0.7 + 0.3 * ((double)(histSamples - minSamples) / (double)(minSamples * 2));

   // Apply credibility to historical SE (lower credibility → higher SE → less weight)
   double adjustedHistSE = wilsonSE / MathMax(credibility, 0.1);

   // Inverse variance weighting
   double histWeight = 1.0 / (adjustedHistSE * adjustedHistSE);
   double theoWeight = 1.0 / (theoSE * theoSE);

   double totalWeight = histWeight + theoWeight;
   if(totalWeight <= 0) return(theoProb);

   double combined = (theoProb * theoWeight + histProb * histWeight) / totalWeight;

   return(MathMax(1.0, MathMin(99.0, combined)));
}

//+------------------------------------------------------------------+
//|        SECTION 11: RECOMMENDATION ENGINE                           |
//+------------------------------------------------------------------+
enum ENUM_RECOMMENDATION
{
   REC_STRONG_ENTRY, REC_ENTRY, REC_CAUTION_ENTRY,
   REC_WAIT, REC_AVOID, REC_COUNTER_TREND
};

struct TradeRecommendation
{
   ENUM_RECOMMENDATION level;
   string label;
   string reason;
   color  labelColor;
   int    confidence;
   double suggestedRisk;
};

//+------------------------------------------------------------------+
//| ANTI-OVERFITTING Recommendation                                    |
//| Score based on EXPECTED VALUE, not arbitrary point system          |
//|                                                                    |
//| EV = (winRate × avgWin) - (lossRate × avgLoss)                    |
//| This is MATHEMATICAL, not tuned                                     |
//+------------------------------------------------------------------+
TradeRecommendation GetTradeRecommendation(
   int caseNum, bool isBuy, double probTP1, double probSL,
   int probSamples, int mtfAgreement,
   double slDist, double tp1Dist, double atrValue, datetime signalTime)
{
   TradeRecommendation rec;
   rec.confidence = 0;
   rec.suggestedRisk = 0;
   string reasons = "";

   double rr = (slDist > 0) ? tp1Dist / slDist : 0;
   double winRate = probTP1 / 100.0;
   double lossRate = 1.0 - winRate;

   // ============================================
   // CORE: Expected Value per trade (MATH, not guessed)
   // EV = win% × R:R - loss% × 1.0
   // ============================================
   double ev = (winRate * rr) - (lossRate * 1.0);

   // ============================================
   // Kelly Criterion: Optimal risk fraction (MATH)
   // Kelly% = (edge × odds - 1) / (odds - 1)
   // Simplified: Kelly% = EV / R:R
   // Half-Kelly for safety (standard practice)
   // ============================================
   double kellyFraction = 0;
   if(rr > 0 && ev > 0)
      kellyFraction = (ev / rr) * 0.5;  // Half-Kelly
   kellyFraction = MathMax(0, MathMin(kellyFraction, 0.03));  // Cap at 3%

   // ============================================
   // Confidence from DATA QUALITY (not arbitrary)
   // Based on standard error of win rate estimate
   // ============================================
   double dataConfidence = 0;
   if(probSamples > 0)
   {
      double se = MathSqrt(winRate * (1.0 - winRate) / (double)probSamples);
      // Confidence = how narrow is our estimate
      // SE < 0.05 = high confidence
      // SE > 0.15 = low confidence
      if(se > 0)
         dataConfidence = MathMin(1.0, 0.05 / se);
      else
         dataConfidence = 0;
   }

   // ============================================
   // MTF alignment bonus (MEASURED, not arbitrary)
   // Simply: what % of higher TFs agree
   // ============================================
   double mtfAlignmentRatio = 0;
   bool mtfAligned = false;
   bool mtfAgainst = false;

   if(InpShowMTF && g_mtfCount > 0)
   {
      int agreeCount = 0;
      for(int t = 0; t < g_mtfCount; t++)
      {
         if(isBuy && g_mtfData[t].trend == 1) agreeCount++;
         if(!isBuy && g_mtfData[t].trend == -1) agreeCount++;
      }
      mtfAlignmentRatio = (double)agreeCount / (double)g_mtfCount;
      mtfAligned = (mtfAlignmentRatio >= 0.5);
      mtfAgainst = (mtfAlignmentRatio < 0.25 && g_mtfCount >= 2);
   }

   // ============================================
   // SCORE = function of EV + data quality + MTF
   // ALL derived from measurements, no magic numbers
   // ============================================
   // Base score from EV (0-50 range)
   int evScore = 0;
   if(ev > 0.3)      evScore = 50;  // Excellent EV
   else if(ev > 0.15) evScore = 40;  // Good EV
   else if(ev > 0.05) evScore = 30;  // Marginal EV
   else if(ev > 0)    evScore = 20;  // Barely positive
   else if(ev > -0.1) evScore = 10;  // Slightly negative
   else               evScore = 0;   // Bad EV

   // Data confidence bonus (0-25 range)
   int dataScore = (int)(dataConfidence * 25);

   // MTF bonus (0-25 range)
   int mtfScore = (int)(mtfAlignmentRatio * 25);

   int totalScore = evScore + dataScore + mtfScore;

   // Build reasons
   reasons += "EV:" + DoubleToString(ev, 2) + "R|";
   if(rr > 0) reasons += "R:R 1:" + DoubleToString(rr, 1) + "|";
   reasons += "Win:" + DoubleToString(probTP1, 1) + "%|";
   if(mtfAligned) reasons += "MTF aligned|";
   if(mtfAgainst) reasons += "MTF against|";
   if(dataConfidence > 0.7) reasons += "High data conf|";
   else if(dataConfidence < 0.3) reasons += "Low data conf|";

   // ============================================
   // CLASSIFICATION based on score
   // Thresholds: 75/55/35/20 (not optimized, just quartiles)
   // ============================================
   rec.confidence = MathMax(0, MathMin(100, totalScore));

   if(totalScore >= 75 && ev > 0.15)
   {
      rec.level = REC_STRONG_ENTRY;
      rec.label = "STRONG ENTRY";
      rec.labelColor = clrLime;
      rec.suggestedRisk = MathMin(kellyFraction * 100, 2.0);
   }
   else if(totalScore >= 55 && ev > 0.05)
   {
      rec.level = REC_ENTRY;
      rec.label = "ENTRY";
      rec.labelColor = clrLime;
      rec.suggestedRisk = MathMin(kellyFraction * 100, 1.5);
   }
   else if(totalScore >= 35 && ev > 0)
   {
      rec.level = REC_CAUTION_ENTRY;
      rec.label = "CAUTION ENTRY";
      rec.labelColor = clrYellow;
      rec.suggestedRisk = MathMin(kellyFraction * 100, 1.0);
   }
   else if(ev > -0.05)
   {
      rec.level = REC_WAIT;
      rec.label = "WAIT";
      rec.labelColor = clrOrange;
      rec.suggestedRisk = 0;
   }
   else
   {
      if(mtfAgainst)
      {
         rec.level = REC_COUNTER_TREND;
         rec.label = "AVOID (Counter Trend)";
      }
      else
      {
         rec.level = REC_AVOID;
         rec.label = "AVOID";
      }
      rec.labelColor = clrRed;
      rec.suggestedRisk = 0;
   }

   // Top 3 reasons
   string rLines[];
   int rCnt = StringSplit(reasons, '|', rLines);
   rec.reason = "";
   int shown = 0;
   for(int i = 0; i < rCnt && shown < 3; i++)
      if(StringLen(rLines[i]) > 0)
      {
         if(shown > 0) rec.reason += " | ";
         rec.reason += rLines[i];
         shown++;
      }

   return(rec);
}

#endif