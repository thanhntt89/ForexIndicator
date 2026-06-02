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
//|        SECTION 3: TIMEZONE NORMALIZATION                           |
//+------------------------------------------------------------------+
int GetBrokerGMTOffset()
{
   datetime bt=TimeCurrent(), gt=TimeGMT();
   if(gt==0) return(0);
   int off=(int)(bt-gt)/3600;
   return(off<-12||off>14?0:off);
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
double GetSessionQualityNormalized(int caseNum, datetime signalTime)
{
   if(DetectInstrumentType()==INST_CRYPTO) return(0.5);
   int hour=GetUTCHour(signalTime);
   bool isAsian=(hour>=0&&hour<8), isLondon=(hour>=8&&hour<12),
        isOverlap=(hour>=12&&hour<16), isLateNY=(hour>=16&&hour<22);
   if(hour>=22) return(0.2);
   switch(caseNum)
   {
      case 1:case 5: if(isAsian)return(0.7);if(isLondon)return(0.5);if(isOverlap)return(0.4);return(0.6);
      case 2:case 3: if(isAsian)return(0.4);if(isLondon)return(0.8);if(isOverlap)return(0.7);return(0.5);
      case 4:case 7: if(isAsian)return(0.3);if(isLondon)return(0.9);if(isOverlap)return(0.8);return(0.4);
      case 6: if(isAsian)return(0.4);if(isLondon)return(0.7);if(isOverlap)return(0.8);return(0.5);
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
//|        SECTION 7: MARKET CORRECTION FACTORS                        |
//+------------------------------------------------------------------+
double GetFatTailPenalty()
{
   int lookback=MathMin(500,Bars-2);
   double sumR=0,sumR2=0,sumR4=0; int count=0;
   for(int i=1;i<=lookback;i++)
   {
      double c0=iClose(NULL,0,i),c1=iClose(NULL,0,i+1);
      if(c1==0) continue;
      double ret=(c0-c1)/c1;
      sumR+=ret;sumR2+=ret*ret;sumR4+=ret*ret*ret*ret;count++;
   }
   if(count<50) return(0.08);
   double mean=sumR/count, var=(sumR2/count)-(mean*mean);
   if(var<=0) return(0.08);
   double kurt=(sumR4/count)/(var*var)-3.0;
   if(kurt<=0)return(0.03);if(kurt<=3)return(0.05);
   if(kurt<=6)return(0.08);if(kurt<=10)return(0.10);
   return(0.12);
}

double GetVolClusterPenalty()
{
   int lookback=MathMin(200,Bars-3);
   double sumXY=0,sumX=0,sumY=0,sumX2=0,sumY2=0;int count=0;
   for(int i=1;i<lookback;i++)
   {
      double c0=iClose(NULL,0,i),c1=iClose(NULL,0,i+1),c2=iClose(NULL,0,i+2);
      if(c1==0||c2==0) continue;
      double x=MathAbs((c0-c1)/c1),y=MathAbs((c1-c2)/c2);
      sumXY+=x*y;sumX+=x;sumY+=y;sumX2+=x*x;sumY2+=y*y;count++;
   }
   if(count<50) return(0.05);
   double numr=sumXY/count-(sumX/count)*(sumY/count);
   double denX=sumX2/count-(sumX/count)*(sumX/count);
   double denY=sumY2/count-(sumY/count)*(sumY/count);
   if(denX<=0||denY<=0) return(0.05);
   double corr=numr/MathSqrt(denX*denY);
   if(corr<=0.1)return(0.02);if(corr<=0.3)return(0.04);
   if(corr<=0.5)return(0.06);return(0.08);
}

double GetSpreadDrag(double atrValue)
{
   if(atrValue<=0) return(0.03);
   double spread=MarketInfo(Symbol(),MODE_SPREAD)*_Point;
   return(MathMin((spread/atrValue)*0.5,0.10));
}

//+------------------------------------------------------------------+
//|        SECTION 8: PROBABILITY MATH                                 |
//+------------------------------------------------------------------+
double CalculateGamblersRuin(double edge,double slDist,double tpDist,double atrVal)
{
   if(slDist<=0||tpDist<=0||atrVal<=0) return(0);
   double slU=slDist/atrVal, tpU=tpDist/atrVal;
   double mu=2.0*edge-1.0;
   if(MathAbs(mu)<0.001) return(slU/(slU+tpU));
   double r=MathExp(-2.0*mu);
   double rSL=MathPow(r,slU), rT=MathPow(r,slU+tpU);
   if(MathAbs(1.0-rT)<1e-10) return(slU/(slU+tpU));
   return((1.0-rSL)/(1.0-rT));
}

double CalculateRealMarketProbTP(double edge,double slDist,double tpDist,double atrVal)
{
   double raw=CalculateGamblersRuin(edge,slDist,tpDist,atrVal);
   double corrected=raw*(1.0-GetFatTailPenalty())*(1.0-GetVolClusterPenalty())*(1.0-GetSpreadDrag(atrVal));
   return(MathMax(0.05,MathMin(0.95,corrected)));
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
//|        SECTION 10: BAYESIAN COMBINATION                            |
//+------------------------------------------------------------------+
double CombineTheoreticalHistorical(double theoProb,double histProb,
                                     int histSamples,int minSamples)
{
   if(histSamples<=0) return(theoProb);
   double p=histProb/100.0;
   if(p<=0)p=0.01;if(p>=1)p=0.99;
   double histSE=MathSqrt(p*(1.0-p)/(double)histSamples);
   double theoSE=0.15;
   double hW=0,tW=0;
   if(histSE>0) hW=1.0/(histSE*histSE);
   if(theoSE>0) tW=1.0/(theoSE*theoSE);
   double total=hW+tW;
   if(total<=0) return(theoProb);
   return(MathMax(1.0,MathMin(99.0,(theoProb*tW+histProb*hW)/total)));
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

TradeRecommendation GetTradeRecommendation(
   int caseNum,bool isBuy,double probTP1,double probSL,
   int probSamples,int mtfAgreement,
   double slDist,double tp1Dist,double atrValue,datetime signalTime)
{
   TradeRecommendation rec;
   rec.confidence=0; rec.suggestedRisk=0;
   int score=50;
   string reasons="";

   // Factor 1: Win probability (±25)
   if(probTP1>=60){score+=25;reasons+="High win prob ("+DoubleToString(probTP1,1)+"%)|";}
   else if(probTP1>=50){score+=15;reasons+="Moderate win prob ("+DoubleToString(probTP1,1)+"%)|";}
   else if(probTP1>=40){score+=5;reasons+="Low win prob ("+DoubleToString(probTP1,1)+"%)|";}
   else{score-=15;reasons+="Poor win prob ("+DoubleToString(probTP1,1)+"%)|";}

   // Factor 2: R:R (±15)
   double rr = (slDist > 0) ? tp1Dist / slDist : 0;
   if(rr >= 2.0)      { score += 15; reasons += "Good R:R 1:" + DoubleToString(rr,1) + "|"; }
   else if(rr >= 1.5)  { score += 8;  reasons += "OK R:R 1:" + DoubleToString(rr,1) + "|"; }
   else if(rr >= 1.0)  { score += 0; }
   else if(rr > 0)     { score -= 15; reasons += "Poor R:R 1:" + DoubleToString(rr,1) + "|"; }
   else                { score -= 25; reasons += "Invalid R:R|"; }

   // Factor 3: MTF (±20)
   bool aligned=(isBuy&&mtfAgreement>0)||(!isBuy&&mtfAgreement<0);
   bool against=(isBuy&&mtfAgreement<-30)||(!isBuy&&mtfAgreement>30);
   if(aligned&&MathAbs(mtfAgreement)>50){score+=20;reasons+="MTF strongly aligned|";}
   else if(aligned){score+=10;reasons+="MTF aligned|";}
   else if(against){score-=20;reasons+="MTF AGAINST signal|";}

   // Factor 4: Case quality (±10)
   if(caseNum==2){score+=10;reasons+="Strong case (divergence)|";}
   else if(caseNum==4){score+=8;reasons+="Strong case (trend)|";}
   else if(caseNum==1||caseNum==5){score+=5;reasons+="Moderate case (reversal)|";}
   else if(caseNum==6||caseNum==7) score+=3;

   // Factor 5: Samples (±10)
   int minS=GetMinSamplesForTimeframe();
   if(probSamples>=minS*3){score+=10;reasons+="High data confidence|";}
   else if(probSamples>=minS) score+=5;
   else if(probSamples>0) score-=5;
   else{score-=10;reasons+="No historical data|";}

   // Factor 6: Session (±10)
   double sesQ=GetSessionQualityNormalized(caseNum,signalTime);
   if(sesQ>=0.7) score+=10;
   else if(sesQ<0.4){score-=10;reasons+="Poor session|";}

   // Factor 7: Counter-trend stack
   if(against&&probTP1<45){score-=15;reasons+="COUNTER-TREND + low prob|";}

   rec.confidence=MathMax(0,MathMin(100,score));

   if(score>=85){rec.level=REC_STRONG_ENTRY;rec.label="STRONG ENTRY";rec.labelColor=clrLime;rec.suggestedRisk=2.0;}
   else if(score>=70){rec.level=REC_ENTRY;rec.label="ENTRY";rec.labelColor=clrLime;rec.suggestedRisk=1.5;}
   else if(score>=55){rec.level=REC_CAUTION_ENTRY;rec.label="CAUTION ENTRY";rec.labelColor=clrYellow;rec.suggestedRisk=1.0;}
   else if(score>=40){rec.level=REC_WAIT;rec.label="WAIT";rec.labelColor=clrOrange;rec.suggestedRisk=0;}
   else{
      if(against){rec.level=REC_COUNTER_TREND;rec.label="AVOID (Counter Trend)";rec.labelColor=clrRed;}
      else{rec.level=REC_AVOID;rec.label="AVOID";rec.labelColor=clrRed;}
      rec.suggestedRisk=0;
   }

   string rLines[];int rCnt=StringSplit(reasons,'|',rLines);
   rec.reason="";int shown=0;
   for(int i=0;i<rCnt&&shown<3;i++)
      if(StringLen(rLines[i])>0){if(shown>0)rec.reason+=" | ";rec.reason+=rLines[i];shown++;}

   return(rec);
}

#endif