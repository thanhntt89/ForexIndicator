//+------------------------------------------------------------------+
//|                                                    Config.mqh      |
//|                         RSI Advanced - Configuration & Inputs      |
//+------------------------------------------------------------------+
#ifndef RSI_ADV_CONFIG_MQH
#define RSI_ADV_CONFIG_MQH
#define VERSION "10.20"

//+------------------------------------------------------------------+
//| Object name prefixes                                               |
//+------------------------------------------------------------------+
#define PREFIX_ARROW  "RSIAdv_Arrow_"
#define PREFIX_PANEL  "RSIAdv_Panel_"
#define PREFIX_LINE   "RSIAdv_Line_"
#define PREFIX_PROB   "RSIAdv_Prob_"
#define PREFIX_ZONE   "RSIAdv_Zone_"

enum ENUM_SLTP_METHOD
{
   SLTP_ATR        = 0,  // ATR-based (Wilder + Van Tharp)
   SLTP_FIBONACCI  = 1,  // Fibonacci (Gaucan + Osler)
   SLTP_HYBRID     = 2   // ATR + Fibonacci (Hybrid)
};

//+------------------------------------------------------------------+
//| INPUT GROUP: RSI Core Settings                                     |
//+------------------------------------------------------------------+
input string             inp_grp_core      = "========== RSI Core =========="; // ---
input int                InpRSIPeriod      = 14;          // RSI Period
input int                InpFastMAPeriod   = 2;           // Fast MA Period (Green line)
input int                InpSignalMAPeriod = 7;           // Signal MA Period (Red line)
input int                InpBBPeriod       = 34;          // Bollinger / Baseline Period
input double             InpBBDeviation    = 1.685;       // BB Deviation (Fibonacci)
input ENUM_APPLIED_PRICE InpPrice          = PRICE_CLOSE; // Applied Price

//+------------------------------------------------------------------+
//| INPUT GROUP: Signal Detection                                      |
//+------------------------------------------------------------------+
input string inp_grp_signal    = "========== Signal Detection =========="; // ---
input int    InpMaxBars        = 500;    // Max bars for indicator lines
input int    InpSwingDepth     = 3;      // Swing High/Low depth
input int    InpSwingLookback  = 30;     // Lookback for divergence
input double InpAngleThreshold = 4.0;    // Min RSI delta for angle (base)
input double InpOrangeTolerance= 5.0;    // Orange near level tolerance
input int    InpSidewayCount   = 4;      // Min crossovers for sideway
input int    InpCooldownBars   = 5;      // Minimum bars between signals

//+------------------------------------------------------------------+
//| INPUT GROUP: Signal Quality                                        |
//+------------------------------------------------------------------+
input string inp_grp_quality     = "========== Signal Quality =========="; // ---
input double InpMinSignalScore   = 40.0;   // Minimum score to show signal (0-100)
input bool   InpUseVolumeFilter  = true;   // Use volume confirmation
input bool   InpUseVolatFilter   = true;   // Use volatility confirmation
input bool   InpUseSessionFilter = true;   // Use session time filter
input bool   InpUseRegimeFilter  = false;  // Use market regime filter

//+------------------------------------------------------------------+
//| INPUT GROUP: Case Filters                                          |
//+------------------------------------------------------------------+
input string inp_grp_filter = "========== Case Filters =========="; // ---
input bool InpEnableCase0   = true;  // Case 0: Basic Crossover (core rule)
input bool InpEnableCase1   = true;  // Case 1: OB/OS Bounce
input bool InpEnableCase2   = true;  // Case 2: Regular Divergence
input bool InpEnableCase3   = true;  // Case 3: Hidden Divergence
input bool InpEnableCase4   = true;  // Case 4: Strong Trend
input bool InpEnableCase5   = true;  // Case 5: Orange Near Level
input bool InpEnableCase6   = true;  // Case 6: Trend Continuation
input bool InpEnableCase7   = true;  // Case 7: Sideway Breakout

//+------------------------------------------------------------------+
//| INPUT GROUP: Arrow Display                                         |
//+------------------------------------------------------------------+
input string inp_grp_arrow    = "========== Arrow Display =========="; // ---
input int    InpArrowSize     = 2;         // Arrow size (1-5)
input int    InpArrowOffset   = 10;        // Arrow offset (points)
input color  InpBuyArrowColor = clrLime;   // Buy arrow color
input color  InpSellArrowColor= clrRed;    // Sell arrow color

//+------------------------------------------------------------------+
//| INPUT GROUP: SL/TP Configuration                                   |
//+------------------------------------------------------------------+
input string inp_grp_sltp       = "========== SL/TP Config =========="; // ---
input ENUM_SLTP_METHOD InpSLTPMethod = SLTP_HYBRID;  // SL/TP Method
input bool   InpShowSLTPLines   = true;         // Show SL/TP lines
input bool   InpShowEntryLine   = true;         // Show Entry line
input int    InpATRPeriod       = 14;           // ATR Period
input double InpSLRatio         = 2.0;          // SL = ATR x this
input double InpTPRatio         = 4.0;          // TP1 = ATR x this
input double InpTP2Multiplier   = 1.5;          // TP2 = TP1 x this
input double InpTP3Multiplier   = 2.0;          // TP3 = TP1 x this
input int    InpSLSwingLookback = 20;           // Bars lookback for swing SL
input color  InpEntryLineColor  = clrWhite;     // Entry line color
input color  InpSLLineColor     = clrRed;       // SL line color
input color  InpTP1LineColor    = clrLime;      // TP1 line color
input color  InpTP2LineColor    = clrDodgerBlue; // TP2 line color
input color  InpTP3LineColor    = clrGold;      // TP3 line color
input int    InpSLTPLineStyle   = STYLE_DASH;   // SL/TP line style
input int    InpSLTPLineWidth   = 1;            // SL/TP line width

//+------------------------------------------------------------------+
//| INPUT GROUP: Entry Zones                                           |
//+------------------------------------------------------------------+
input string inp_grp_zones       = "========== Entry Zones =========="; // ---
input int    InpEntryZoneCount   = 3;                // Max entry zones (2-5)
input double InpTotalRiskPercent = 1.0;              // Total risk % of account
input int    InpPriceDistLookback= 50;               // Price distribution lookback bars
input color  InpZone1Color       = clrWhite;         // Zone 1 (Market) color
input color  InpZone2Color       = clrAqua;    // Zone 2 color
input color  InpZone3Color       = clrDeepSkyBlue;     // Zone 3 color
input color  InpZone4Color       = clrMediumOrchid;     // Zone 4 color
input color  InpZone5Color       = clrHotPink; // Zone 5 color

//+------------------------------------------------------------------+
//| INPUT GROUP: Info Panel                                            |
//+------------------------------------------------------------------+
input string inp_grp_panel      = "========== Info Panel =========="; // ---
input bool   InpShowPanel       = true;           // Show info panel
input int    InpPanelDefaultX   = 20;             // Panel default X
input int    InpPanelDefaultY   = 60;             // Panel default Y
input int    InpPanelWidth      = 330;            // Panel width
input color  InpPanelBgColor    = C'20,25,35';    // Background
input color  InpPanelBorderColor= C'60,70,90';    // Border
input color  InpPanelTitleColor = clrGold;        // Title
input color  InpPanelTextColor  = clrWhite;       // Text
input color  InpPanelBuyColor   = clrLime;        // Buy highlight
input color  InpPanelSellColor  = clrRed;         // Sell highlight
input color  InpPanelDimColor   = clrDarkGray;    // Dim text
input int    InpPanelFontSize   = 9;              // Font size

//+------------------------------------------------------------------+
//| INPUT GROUP: Multi-Timeframe                                       |
//+------------------------------------------------------------------+
input string inp_grp_mtf        = "========== Multi-Timeframe =========="; // ---
input bool   InpShowMTF         = true;           // Show MTF status
input bool   InpMTF_M15         = true;           // Show M15
input bool   InpMTF_M30         = true;           // Show M30
input bool   InpMTF_H1          = true;           // Show H1
input bool   InpMTF_H4          = true;           // Show H4
input bool   InpMTF_D1          = true;           // Show D1
input color  InpMTF_BullColor   = clrLime;        // Bullish color
input color  InpMTF_BearColor   = clrRed;         // Bearish color
input color  InpMTF_NeutralColor= clrGray;        // Neutral color
input int    InpMinMTFAgreement = 40;              // Min MTF agreement % to confirm signal (0=off)

//+------------------------------------------------------------------+
//| INPUT GROUP: Probability Engine                                    |
//+------------------------------------------------------------------+
input string inp_grp_prob         = "========== Probability =========="; // ---
input bool   InpShowProbability   = true;          // Show probability
input int    InpProbMaxBars       = 1000;          // Max bars for probability scan
input color  InpProbTextColor     = clrWhite;      // Probability text color
input int    InpProbFontSize      = 8;             // Probability font size

//+------------------------------------------------------------------+
//| INPUT GROUP: Alerts                                                |
//+------------------------------------------------------------------+
input string inp_grp_alert      = "========== Alerts =========="; // ---
input bool   InpAlertPopup      = false;         // Alert popup
input bool   InpAlertSound      = false;         // Play sound
input string InpAlertSoundFile  = "alert.wav";   // Sound file

//+------------------------------------------------------------------+
//| INPUT GROUP: Intermarket Analysis                                  |
//+------------------------------------------------------------------+
input string inp_grp_inter       = "========== Intermarket =========="; // ---
input bool   InpUseIntermarket   = true;          // Use intermarket correlation (DXY/EURUSD)
input int    InpIntermarketPeriod= 20;            // Intermarket SMA period for trend

//+------------------------------------------------------------------+
//| INPUT GROUP: Walk-Forward Validation                                |
//+------------------------------------------------------------------+
input string inp_grp_wf          = "========== Walk-Forward =========="; // ---
input bool   InpUseWalkForward   = true;          // Enable IS/OOS validation
input double InpOOSPercent       = 20.0;          // Out-of-sample % (10-30)
input bool   InpShowRollingPerf  = true;          // Show rolling performance

//+------------------------------------------------------------------+
//| INPUT GROUP: Spread Regime                                         |
//+------------------------------------------------------------------+
input string inp_grp_spread      = "========== Spread Regime =========="; // ---
input bool   InpUseSpreadRegime  = true;          // Monitor spread anomalies
input double InpSpreadSpikeMulti = 2.0;           // Spread spike threshold (x average)

//+------------------------------------------------------------------+
//| INPUT GROUP: Signal Logging                                        |
//+------------------------------------------------------------------+
input string inp_grp_log        = "========== Signal Logging =========="; // ---
input bool   InpEnableSignalLog = false;                  // Enable signal logging to CSV
input string InpLogFolder       = "RSI_Advanced_Logs";    // Log folder (inside MQL4/Files/)


//+------------------------------------------------------------------+
//| INPUT GROUP: Debug                                                 |
//+------------------------------------------------------------------+
input string inp_grp_debug      = "========== Debug =========="; // ---
input bool   InpDebugMode       = false;        // Print debug info to Experts tab
input bool   InpStrictDuplicate = false;        // Block duplicate direction signals

#endif