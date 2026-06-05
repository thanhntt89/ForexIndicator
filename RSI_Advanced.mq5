//+------------------------------------------------------------------+
//|                                         RSI_Advanced.mq5           |
//|                         RSI Advanced - MT5 Wrapper File            |
//|                         Master Trading Wave Community               |
//+------------------------------------------------------------------+
#property copyright "Master Trading Wave"
#property link      "https://mastertradingwave.com"
#property version "10.20"

#property indicator_separate_window
#property indicator_minimum  0
#property indicator_maximum  100
#property indicator_buffers  7
#property indicator_plots    5

//--- Plot 1 (RSI Fast)
#property indicator_label1  "RSI Fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2 (Signal)
#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- Plot 3 (BB Upper)
#property indicator_label3  "BB Upper"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDeepSkyBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- Plot 4 (BB Lower)
#property indicator_label4  "BB Lower"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDeepSkyBlue
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

//--- Plot 5 (Baseline)
#property indicator_label5  "Baseline"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrOrange
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#define __MQL5__
#include <RSI_Advanced/MQLCompat.mqh>
#include "RSI_Advanced.mq4"
