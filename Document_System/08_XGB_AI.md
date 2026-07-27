# QuantEdge — XGBoost AI Integration

## 1. Tổng Quan

XGBoost là tầng AI bổ trợ cho pipeline Bayesian, hoạt động ở chế độ **ensemble**.
Source: `XGBIntegration.mqh` (5.5KB) + `XGBModel.mqh` (12.4KB)

```
                 Signal
                   │
        ┌──────────┼──────────┐
        ▼                     ▼
  Bayesian Pipeline      XGBoost Model
  (7-step, 81KB)        (binary tree)
        │                     │
        ▼                     ▼
   probBayesian           probXGB
        │                     │
        └──────────┬──────────┘
                   ▼
          Brier-Weighted Average
              probFinal
```

## 2. Ba Chế Độ (InpProbMode)

| Mode | Enum | Mô tả |
|------|------|-------|
| CALIBRATION | `PROB_CALIBRATION` | Chỉ Bayesian pipeline (mặc định) |
| XGBOOST | `PROB_XGBOOST` | Chỉ XGBoost (fallback CAL khi chưa ready) |
| ENSEMBLE | `PROB_ENSEMBLE` | Brier-weighted average cả hai |

## 3. XGBoost Features (19 inputs)

```mql4
XGBPredict(
   rsiValue,           // RSI tại signal bar
   angleStrength,       // Z-score góc RSI
   atrRatio,            // ATR / avgATR (vol regime)
   slATR,               // SL distance / ATR
   tp1ATR,              // TP1 distance / ATR
   rrRatio,             // TP1 / SL
   spreadPips,          // Spread tại signal (pips)
   sessionMinutes,      // Phút trong session
   caseNumber,          // Signal case 1-9
   isBuy,               // Direction
   sessionBlock,        // 0=Asian 1=London 2=Overlap 3=LateNY
   hour,                // Giờ trong ngày
   dayOfWeek,           // Thứ trong tuần
   marketRegime,        // Mean-revert/Trending/Volatile/Transition
   mtfScore,            // MTF agreement (0-100)
   spreadRatio,         // Current / avg spread
   wfRobust,            // Walk-Forward robust? (0/1)
   trendH4,             // MTF trend H4 (-1/0/1)
   trendH1              // MTF trend H1 (-1/0/1)
)
```

## 4. Ensemble: Brier-Weighted Average

```mql4
wBayes = 1 / max(brierBayesian, 0.10)²
wXGB   = 1 / max(brierXGB, 0.10)²

probFinal = (probBayesian × wBayes + probXGB × wXGB) / (wBayes + wXGB)
```

- Floor 0.10 → không model nào bị domination vĩnh viễn
- Model nào calibrate tốt hơn (Brier thấp hơn) → weight cao hơn

## 5. XGBoost Readiness Check

```mql4
bool XGBIsReady()
{
   if(!g_xgbLoaded) return false;               // Model file loaded?
   if(XGBFindModel(Symbol(), Period()) < 0)      // Model cho pair+TF này?
      return false;
   if(g_xgbBrierSamples < 20) return false;      // Đủ data đánh giá?
   if(g_xgbBrierScore > 0.25) return false;       // Calibration tốt hơn coin flip?
   return true;
}
```

Nếu chưa ready → auto-fallback về CALIBRATION mode.

## 6. Model File Format (XGBModel.mqh)

- Binary tree format đọc từ file `MQL4/Files/QuantEdge_XGB/`
- Mỗi model = 1 file per (Symbol, Period) pair
- Tree traversal: left if feature < threshold, right otherwise
- Ensemble of trees → average prediction

## 7. Auto-Training Pipeline

### Hiện trạng
- Python script riêng train XGBoost
- Export binary model → MetaTrader Files folder
- Indicator load model khi khởi động

### Cần cải thiện

| Hạng mục | Mô tả |
|----------|-------|
| Auto-export CSV | SignalLogger đã log → cần script tự training |
| Periodic retrain | Cron job retrain khi có > 50 outcomes mới |
| Model versioning | Lưu model versions + performance history |
| A/B testing | Shadow mode: chạy 2 models so sánh Brier |
| Feature importance | Export SHAP values → hiểu features nào quan trọng |

## 8. Training Data Requirements

| Metric | Minimum | Recommended |
|--------|---------|-------------|
| Total signals | 100 | 500+ |
| Resolved outcomes | 50 | 200+ |
| Per-case minimum | 10 | 30+ |
| Timeframe coverage | 1 TF | 2-3 TFs |
| Time span | 1 month | 3-6 months |

### Vấn Đề Hiện Tại
Lỗi `"Not enough data for walk-forward validation"` khi chạy training → cần tích lũy thêm data bằng cách chạy indicator trên demo account.
