# QuantEdge — Probability Pipeline (7 Steps)

## Tổng Quan

Pipeline xác suất 7 bước biến raw RSI signal thành con số % đáng tin cậy.
Source: `ProbabilityEngine.mqh` (81KB, 1711 dòng)

```
Signal → [Step 1: Historical] → [Step 2: Edge] → [Step 3: Adjustments]
       → [Step 4: Gambler's Ruin] → [Step 5: Bayesian Combine]
       → [Step 5.5-5.7: Corrections] → [Step 6: Normalize]
       → probTP1, probTP2, probTP3, probSL
```

## Step 1: Historical Simulation (3 Tiers)

Thu thập dữ liệu lịch sử bằng 3 tầng ưu tiên:

| Tier | Nguồn dữ liệu | Weight | Mô tả |
|------|---------------|--------|-------|
| T1 | Stored signals CÙNG case | `n^0.75 × 1.0` | Tin nhiều nhất: cùng direction + cùng caseNumber |
| T2 | Stored signals TẤT CẢ cases | `√n × 0.5` | Ít tin hơn: cùng direction, khác case |
| T3 | ATR-based historical scan | `√n × 0.15` | Ít tin nhất: scan giá thô, RSI tương tự |

**Output:** `histTP1`, `histSL` (weighted average)

## Step 2: Edge Measurement

Đo "lợi thế thống kê" từ dữ liệu signal đã lưu:
- Giá có vượt entry + 1×ATR không?
- `edge = correctCount / totalCount`
- `edge = 0.5` → không có lợi thế (50/50)
- `edge > 0.5` → có lợi thế thực sự

## Step 3: Edge Adjustments

| Yếu tố | Công thức | Tác động |
|---------|----------|---------|
| MTF Agreement | `alignRatio × 0.03` | ±3% edge |
| Intermarket (DXY) | `intermarketEdge` | ±2% edge |
| Angle Strength | `clamp((Z-1.0)×0.03, -0.03, +0.04)` | ±3-4% edge |
| Market State | `stateMultiplier` | Scale theo Mean-revert/Trending |

`adjustedEdge = clamp(edge + edgeAdj, 0.48, TF-ceiling)`

## Step 4: Theoretical Probability (Gambler's Ruin)

Chuyển edge thành xác suất TP, dựa trên khoảng cách SL/TP:

```
slU = slDist / ATR          (SL tính bằng đơn vị ATR)
tpU = tpDist / ATR          (TP tính bằng đơn vị ATR)
mu  = 2 × edge - 1          (drift)
r   = exp(-2 × mu)

P(TP) = (1 - r^slU) / (1 - r^(slU + tpU))
```

**Real-market corrections:**
- `× (1 - FatTailPenalty)` — kurtosis > 3 → phạt tail risk
- `× (1 - VolClusterPenalty)` — vol autocorrelation
- `× (1 - SpreadDrag)` — spread / ATR → chi phí giao dịch

## Step 5: Bayesian Combine

Kết hợp lý thuyết (Step 4) + lịch sử (Step 1) bằng Wilson Score SE:

```
pWilson   = (p×n + z²/2) / (n + z²)           z = 1.96 (95% CI)
wilsonSE  = sqrt((p(1-p)/n + z²/4n²) / (1 + z²/n))
theoSE    = 0.15                               (model uncertainty)

histWeight = 1 / adjustedSE²
theoWeight = 1 / theoSE²
combined   = (theo×theoW + hist×histW) / (theoW + histW)
```

**Khi n lớn:** historical data chiếm ưu thế (tin dữ liệu thực)
**Khi n nhỏ:** theoretical model chiếm ưu thế (tin model)

## Step 5.5: Confidence Adjustments

### 1-Bar Price Confirmation (Brooks 2012)
```
BUY:  nextBar.High > signalBar.High  → confirmed
SELL: nextBar.Low  < signalBar.Low   → confirmed
Không confirmed → prob × reductionFactor (0.85 ~ 0.97 theo TF)
```

### ATR Spike Detection
```
curATR > avgATR(50) × 2.0 → volatility spike
prob = 50 + (prob - 50) × (1 / spikeRatio)    // kéo về 50%
```

## Step 5.6: Session Quality

Blend xác suất với win rate thực tế theo session (khi n ≥ 20):
```
measuredWR = win rate đo được (theo session × case)
baseline   = probTP1 hiện tại
ratio      = blended / baseline
probTP1   *= ratio
```

## Step 5.7: Time-Decay / Survival Analysis (Weibull)

```
S(t) = exp(-(t / λ)^k)

TP: k = 1.50 (H1+), 1.40 (M15), 1.30 (M5), 1.20 (M1)  → Increasing hazard
SL: k = 0.80 (H1+), 0.75 (M15), 0.70 (M5), 0.65 (M1)  → Decreasing hazard

P(TP | survived t bars) = P(TP)×S_tp(t) / [P(TP)×S_tp(t) + P(SL)×S_sl(t)]
```

**Ví dụ (avgTP=38, avgSL=10, base Win=39%):**
| Bars elapsed | Win% | Trạng thái |
|-------------|------|-----------|
| 0 | 39.0% | Mới |
| 5 | 48.4% | Sống qua SL zone |
| 10 | 53.8% | Vượt avg SL → edge cao nhất |
| 38 | 40.8% | Tại avg TP → bắt đầu giảm |
| 60 | 29.3% | Quá hạn |
| 80 | 10.3% | Gần hết → nên thoát |

## Step 6: Final Normalize

```
probTP1 + probSL = 100%
probTP2 ≤ probTP1
probTP3 ≤ probTP2
```

## PROB ATTRIBUTION Panel (Debug View)

Khi `InpShowProbExplain = true`, hiển thị pipeline waterfall:
```
Base Edge → MTF Gate → Intermarket Gate → Angle Gate
→ Market State → Gambler Ruin → Bayesian Combine
→ Session WR → Brier Shrink → Time Decay → FINAL
```

## Anti-Overfitting Measures

| Biện pháp | Mô tả |
|-----------|-------|
| Tier weights `√n × relevance` | Data-proportional, không fixed |
| Edge TF-adaptive clamp | `[0.48, 0.56-0.65]` per TF |
| Wilson Score SE floor 0.05 | Không bao giờ tin data 100% |
| Gambler's Ruin corrections | Fat tail + Vol cluster + Spread |
| Session from MEASURED data | Chỉ khi n ≥ 20 |
| Time-decay Weibull | Không phải linear discount tùy ý |
