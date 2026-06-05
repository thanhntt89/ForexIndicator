# RSI Advanced V11.00 - Context Summary

## Project Structure:
20 files trong MQL4/Include/RSI_Advanced/ + 1 main .mq4

## Files:
Config.mqh, Structs.mqh, Globals.mqh, MathUtils.mqh, 
Normalize.mqh, RSICore.mqh, SwingDetection.mqh, SignalCases.mqh,
SLTP.mqh, MTFEngine.mqh, IntermarketAnalysis.mqh, 
SessionStatistics.mqh, WalkForward.mqh, ProbabilityEngine.mqh,
SignalEngine.mqh, ArrowManager.mqh, LineDrawing.mqh, 
PanelDrawing.mqh, ChartEvents.mqh
Main: RSI_AdvancedSignal.mq4

## Architecture:
- Signal Detection: V9.00 proven (7 cases, fixed swing depth)
- Adaptive angle threshold (Kaufman/Ehlers)
- SL/TP: 3 methods (ATR/Fibonacci/Hybrid) + Volume validation
- Entry Zones: Liquidity void detection, 2-5 zones, Kelly sizing
- Probability: 6-step pipeline (Historical→Edge→Theoretical→Bayesian→Confirmation→Session)
- Recommendation: EV-driven (Kelly criterion)
- Anti-overfitting: Continuous formulas, Wilson Score, data-proportional weights
- Normalization: Cross-instrument/broker/TF
- V11: Intermarket (EURUSD/DXY), Session stats, Walk-forward IS/OOS, 
  Spread regime, Rolling performance, Regime stability

## Scoring: 78.9/100 (Tier 2 Professional Algo)

## Công việc ĐANG LÀM:
- Vừa implement MeasureOptimalTPRatios (measured TP from data)
- Vừa thêm GetTPMeasurementBars() vào MathUtils.mqh
- Vừa update CalculateSLTP() dùng measured ratios
- CẦN COMPILE TEST

## Nguyên tắc quan trọng:
- Signal detection GIỮA NGUYÊN V9.00 (proven, không thay đổi)
- Tất cả improvements chỉ ở display/probability/SL-TP/zones
- Anti-overfitting: không hardcode, dùng data-driven
- Cross-broker: robust timezone, spread buffer, High/Low not Close
- SL validation: volume profile proxy, beyond high volume zone
- Entry zones: liquidity void, shared SL, lot sizing per zone

## Bugs đã fix:
- Signal detection khác bản cũ → revert về V9.00
- Panel position reset khi switch TF → GlobalVariable persist
- Zone lines không hiện → bỏ cache, draw mỗi tick
- SL invalidation check → <= thay < 
- Duplicate V11 update calls → removed
- Session blend overfitting → inverse variance weighting
- Zone quá gần SL → spread × 5 minimum distance
- SL buffer hardcoded → spread × 2 data-driven