# QuantEdge — Walk-Forward Validation & Anti-Overfitting

## 1. Tổng Quan

Walk-Forward Validation là cơ chế **chống overfitting** quan trọng nhất trong platform.
Source: `WalkForward.mqh` (28KB, 727 dòng)

### Lý thuyết gốc
- **Pardo (2008)**: "Evaluation and Optimization of Trading Strategies"
- Train trên dữ liệu cũ (In-Sample), validate trên dữ liệu mới (Out-of-Sample)
- Nếu IS >> OOS → hệ thống đã overfit vào dữ liệu quá khứ

## 2. Components

### 2.1 IS/OOS Split

```mql4
int GetTrainingSplitIndex()
```

- Chia signals thành 2 nhóm theo thời gian
- `InpOOSPercent = 20%` → 80% IS, 20% OOS
- Minimum: 10 signals IS, 5 signals OOS
- Nếu không đủ data → dùng tất cả (no split)

### 2.2 Overfit Detection

```
Condition 1: IS/OOS ratio < 1.15 (Pardo recommends <1.10)
Condition 2: IS - OOS < 7% absolute gap
Condition 3: OOS n ≥ 15 (Wilson CI ±20-25% khi n<15)

isRobust = !enoughOOS || (ratioOK && absoluteOK && hasWins)
```

| IS WR | OOS WR | Ratio | Gap | Verdict |
|-------|--------|-------|-----|---------|
| 65% | 60% | 1.08 | 5% | ✅ ROBUST |
| 70% | 55% | 1.27 | 15% | ❌ OVERFIT |
| 57% | 75% | 0.76 | -18% | ✅ ROBUST (OOS > IS = generalizes well) |

### 2.3 Rolling Walk-Forward (K Windows)

Thay vì 1 split duy nhất (có thể may mắn), chạy K windows chồng lấp:

```
Window 1: [▓▓▓▓▓▓▓▓░░]  IS=80% OOS=20%
Window 2: [░▓▓▓▓▓▓▓▓░]  Shift right
Window 3: [░░▓▓▓▓▓▓▓▓]  Shift right
```

Lấy **median ratio** của K windows → ổn định hơn single split.

### 2.4 Permutation Test (p-value)

Kiểm tra edge có **thật sự khác biệt thống kê** với random hay không:

```
1. Tính actual win rate
2. Shuffle outcomes 100 lần (random 50/50)
3. Đếm bao nhiêu lần shuffled WR ≥ actual WR
4. p-value = (countBetter + 1) / (nPerm + 1)
```

| p-value | Ý nghĩa |
|---------|---------|
| < 0.05 | Edge có ý nghĩa thống kê (strong) |
| 0.05-0.10 | Marginal (cần thêm data) |
| > 0.10 | Có thể là noise |

### 2.5 Information Coefficient (IC)

```
IC = Pearson(angleStrength, outcome ∈ {+1,-1})
```

| IC | Interpretation |
|----|---------------|
| > 0.10 | **STRONG** — angle predicts direction reliably |
| 0.05-0.10 | **WEAK** — marginal predictive power |
| < 0.05 | **NOISE** — angleStrength không predict được |
| < -0.05 | **INVERSE!** — strong angle = LOSSES (danger) |

### 2.6 Kelly Fraction (Half-Kelly)

```mql4
kelly = winRate - lossRate / rr
halfKelly = max(0, kelly × 0.5) × 100
kellyFraction = min(halfKelly, 5.0%)
```

- `winRate = probTP1 / 100`
- `rr = tpDist / slDist`
- Cap tại 5% (no insane sizing)
- **Hiện tại chỉ DISPLAY, chưa dùng cho lot sizing** → xem `02_LOT_SIZING.md`

### 2.7 Rolling Performance

```
last10WR  — Win rate 10 lệnh gần nhất
last20WR  — Win rate 20 lệnh gần nhất
last50WR  — Win rate 50 lệnh gần nhất
allTimeWR — Win rate tổng cộng

isDecreasing = (last10WR < last20WR < allTimeWR)
```

Khi `isDecreasing = true` → cảnh báo "Performance declining" trên panel.

## 3. Tác Động Lên Platform

| WF Output | Ảnh hưởng |
|-----------|----------|
| `isRobust = false` | Recommendation score -10 điểm |
| `kellyFraction` | Hiển thị trên panel (chưa dùng cho sizing) |
| `permPValue > 0.10` | Cảnh báo "Edge may be noise" |
| `IC < 0` | Cảnh báo "Angle inversely correlated" |
| `isDecreasing` | Visual warning trên panel |

## 4. Cần Cải Thiện

| Hạng mục | Mô tả |
|----------|-------|
| Kelly → PositionSizing | Kết nối Kelly output vào lot calculation |
| Adaptive IS/OOS split | Tự điều chỉnh % theo data volume |
| Per-case WF | Chạy WF riêng cho từng case (case 1 robust ≠ case 6 robust) |
| Regime-aware WF | Split theo vol regime, không chỉ theo thời gian |
