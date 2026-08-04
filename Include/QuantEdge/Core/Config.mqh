//+------------------------------------------------------------------+
//|                                                    Config.mqh      |
//|                         QuantEdge - Configuration & Inputs      |
//+------------------------------------------------------------------+
#ifndef QE_CONFIG_MQH
#define QE_CONFIG_MQH
#define VERSION "10.20"

//+------------------------------------------------------------------+
//| [GMT-FIX] Minute-based timeframe constants for Period() comparison |
//| Period() returns minutes via MQLCompat (MT5) / natively (MT4).     |
//| PERIOD_H1=16385, PERIOD_H4=16388 in MT5 — cannot compare with     |
//| Period() which returns 60, 240. Use TF_H1, TF_H4 etc. instead.    |
//+------------------------------------------------------------------+
#define TF_M1   1
#define TF_M5   5
#define TF_M15  15
#define TF_M30  30
#define TF_H1   60
#define TF_H4   240
#define TF_D1   1440
#define TF_W1   10080
#define TF_MN1  43200

//+------------------------------------------------------------------+
//| Object name prefixes                                               |
//+------------------------------------------------------------------+
#define PREFIX_ARROW  "QE_Arrow_"
#define PREFIX_PANEL  "QE_Panel_"
#define PREFIX_LINE   "QE_Line_"
#define PREFIX_PROB   "QE_Prob_"
#define PREFIX_ZONE   "QE_Zone_"
#define PREFIX_OSMON  "QE_OSMon_"
#define PREFIX_EXPLAIN "QE_Expl_"

enum ENUM_SLTP_METHOD
{
   SLTP_ATR        = 0,  // ATR-based (Wilder + Van Tharp)
   SLTP_FIBONACCI  = 1,  // Fibonacci (Gaucan + Osler)
   SLTP_HYBRID     = 2   // ATR + Fibonacci (Hybrid)
};

enum ENUM_SLTP_MODE
{
   SLTP_DYNAMIC      = 0,  // Dynamic (MAE/MFE percentile)
   SLTP_FIXED         = 1,  // Fixed (user input values)
   SLTP_EV_OPTIMIZED  = 2   // EV-Optimized (probability feedback)
};

enum ENUM_PROB_MODE
{
   PROB_CALIBRATION = 0,  // Calibration (Bayesian pipeline only)
   PROB_XGBOOST    = 1,  // XGBoost only
   PROB_ENSEMBLE   = 2   // Ensemble (Bayesian + XGBoost)
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
input bool               InpEAMode         = false;       // Disable visuals when loaded via iCustom (EA use)

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
//| INPUT GROUP: Session Hard Block                                    |
//+------------------------------------------------------------------+
input string inp_grp_sess_hard   = "=== Session Hard Block ==="; // ---
input bool   InpHardCase6Asian   = true;   // Block Case 6 in Asian/DeadZone session
input bool   InpHardCase6LateNY  = true;   // Block Case 6 in LateNY session

//+------------------------------------------------------------------+
//| INPUT GROUP: Case Filters                                          |
//+------------------------------------------------------------------+
input string inp_grp_filter = "========== Case Filters =========="; // ---
input bool InpEnableCase0   = true;  // Case 0: (deprecated, not wired - use Case 8)
input bool InpEnableCase1   = true;  // Case 1: OB/OS Bounce
input bool InpEnableCase2   = true;  // Case 2: Regular Divergence
input bool InpEnableCase3   = true;  // Case 3: Hidden Divergence
input bool InpEnableCase4   = true;  // Case 4: Strong Trend
input bool InpEnableCase5   = true;  // Case 5: Orange Near Level
input bool InpEnableCase6   = true;  // Case 6: Trend Continuation
input bool InpEnableCase7   = true;  // Case 7: Sideway Breakout
input bool InpEnableCase8   = true;  // Case 8: Basic Crossover (Green x Red + strong angle)
input bool   InpEnableCase9   = true;  // Case 9: Plain Green x Red crossover (NO angle gate, lowest priority) - isolates weak-angle crosses Case 8 skips, for its own probability
input bool InpMonitorOSCross= false; // [EXPERIMENT] Aqua/magenta dot on Green x Red in OB/OS zone. Now redundant with Case 9 (real signal); enable to overlay RAW pattern vs actionable Case 9 arrows

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
input ENUM_SLTP_MODE InpSLTPMode = SLTP_EV_OPTIMIZED; // SL/TP Mode
input bool   InpShowSLTPLines   = true;         // Show SL/TP lines
input bool   InpShowEntryLine   = true;         // Show Entry line
input int    InpATRPeriod       = 14;           // ATR Period
input double InpSLRatio         = 2.0;          // SL = ATR x this
input double InpTPRatio         = 4.0;          // TP1 = ATR x this
input double InpTP2Multiplier   = 1.5;          // TP2 = TP1 x this
input double InpTP3Multiplier   = 2.0;          // TP3 = TP1 x this
input double InpOptSLDeviation  = 0.5;          // EV-Opt: SL search range (0=none, 1=full)
input double InpOptTPDeviation  = 0.5;          // EV-Opt: TP search range (0=none, 1=full)
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
input bool   InpMTF_M5          = true;           // Show M5 (M1 only)
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
input ENUM_PROB_MODE InpProbMode  = PROB_CALIBRATION;  // Probability Mode (Calibration/XGBoost/Ensemble)
input int    InpProbMaxBars       = 1000;          // Max bars for probability scan
input color  InpProbTextColor     = clrWhite;      // Probability text color
input int    InpProbFontSize      = 8;             // Probability font size
input bool   InpShowProbExplain  = false;         // Show probability attribution panel (debug)

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
//| INPUT GROUP: GMT Normalization                                      |
//+------------------------------------------------------------------+
// [GMT-FIX-0] H4+ candle boundaries differ by broker GMT offset.
// GMT+0 broker H4 candles: 00:00,04:00,...,20:00 UTC
// GMT+2 broker H4 candles: 02:00,06:00,...,22:00 UTC (shifted 2h)
// This causes completely different RSI values and signal outcomes.
// Auto mode normalizes H4 candles to GMT+0 when broker offset != 0.
input string inp_grp_gmt         = "========== GMT Normalization =========="; // ---
input int    InpGMTNormalize     = -1;       // H4 Norm: -1=Auto, 0=Off, 1=Force
input int    InpForceGMTOffset   = -99;      // Force GMT offset (-99=Auto-detect)

//+------------------------------------------------------------------+
//| INPUT GROUP: Spread Regime                                         |
//+------------------------------------------------------------------+
input string inp_grp_spread      = "========== Spread Regime =========="; // ---
input bool   InpUseSpreadRegime  = true;          // Monitor spread anomalies
input double InpSpreadSpikeMulti = 2.0;           // Spread spike threshold (x average)

//+------------------------------------------------------------------+
//| INPUT GROUP: TF Auto-Config                                        |
//| When enabled, SL/TP ratios, method, case filters, cooldown, risk  |
//| are automatically adapted to the current chart timeframe using     |
//| the scalping intraday profile. Set to false to use manual inputs. |
//+------------------------------------------------------------------+
input string inp_grp_tfcfg       = "========== TF Auto-Config =========="; // ---
input bool   InpAutoTFConfig     = true;  // Auto-adapt SL/TP/cases per TF (scalping profile)

//+------------------------------------------------------------------+
//| INPUT GROUP: Signal Logging                                        |
//+------------------------------------------------------------------+
input string inp_grp_log        = "========== Signal Logging =========="; // ---
input bool   InpEnableSignalLog = true;                   // Enable signal logging to CSV (persists actual outcomes across TF switch/restart)
input string InpLogFolder       = "QuantEdge_RSI_Logs";   // Log folder (inside MQL4/Files/)


//+------------------------------------------------------------------+
//| INPUT GROUP: Risk Manager                                          |
//+------------------------------------------------------------------+
input string inp_grp_risk       = "========== Risk Manager =========="; // ---
input int    InpMaxOpenSignals   = 3;      // Max concurrent signals
input double InpMaxDailyRiskPct  = 2.0;    // Max total risk %
input int    InpMaxDailyTrades   = 15;     // Max trades per day
input double InpDDYellowPct     = 1.5;    // DD % -> Scale lot 50% (Yellow)
input double InpDDOrangePct     = 2.5;    // DD % -> Scale lot 25% (Orange)
input double InpDDRedPct        = 3.0;    // DD % -> Full STOP (Red)
input double InpMinRiskPct      = 0.25;   // Min risk % per trade (floor)
input bool   InpUseQualityAlloc = true;   // Scale risk by signal quality (probTP1)

//+------------------------------------------------------------------+
//| INPUT GROUP: Position Sizing                                       |
//+------------------------------------------------------------------+
input string inp_grp_possizing   = "========== Position Sizing =========="; // ---
input bool   InpUseKellyLot      = true;    // Use Kelly-adjusted lot sizing
input double InpMaxRiskPct       = 2.0;     // Max risk % per trade (hard cap)

//+------------------------------------------------------------------+
//| INPUT GROUP: Debug                                                 |
//+------------------------------------------------------------------+
input string inp_grp_debug      = "========== Debug =========="; // ---
input bool   InpDebugMode       = false;        // Print debug info to Experts tab
input bool   InpStrictDuplicate = false;        // Block duplicate direction signals

// Cross-platform backtest detection macro
#ifndef ISBACKTESTMODE_DEFINED
   #ifdef __MQL5__
      #define IsBacktestMode() ((bool)MQLInfoInteger(MQL_TESTER))
   #else
      #define IsBacktestMode() IsTesting()
   #endif
   #define ISBACKTESTMODE_DEFINED
#endif

#endif