# Chiến Lược DCA Scalping Intraday — QuantEdge EA

**Phiên bản:** 2.1  
**Cập nhật:** 2026-09-14  
**Công cụ:** XAUUSD  
**Khung thời gian:** M15  
**Trạng thái:** DRAFT — chờ indicator backtest data trước khi finalize target

---

## Mục Lục

0. [PREREQUISITE: Indicator Backtest](#0-prerequisite-indicator-backtest)
1. [Tổng quan chiến lược](#1-tổng-quan-chiến-lược)
2. [Thị trường & Công cụ](#2-thị-trường--công-cụ)
3. [Tín hiệu vào lệnh](#3-tín-hiệu-vào-lệnh)
4. [Quản lý SL/TP](#4-quản-lý-sltp)
5. [Chiến lược DCA](#5-chiến-lược-dca)
6. [Quản lý vốn & Lot](#6-quản-lý-vốn--lot)
7. [Quản lý rủi ro](#7-quản-lý-rủi-ro)
8. [Bộ lọc phiên giao dịch](#8-bộ-lọc-phiên-giao-dịch)
9. [Recovery Mode](#9-recovery-mode)
10. [Mục tiêu hiệu suất & Benchmark](#10-mục-tiêu-hiệu-suất--benchmark)
11. [Tham số khuyến nghị](#11-tham-số-khuyến-nghị)
12. [Quy trình Backtest & Tối ưu](#12-quy-trình-backtest--tối-ưu)
13. [Phụ lục A: Phân tích toán học EV & Target](#13-phụ-lục-a-phân-tích-toán-học-ev--target)
14. [Phụ lục B: Counter-Evidence từ EAGoldMaster](#14-phụ-lục-b-counter-evidence-từ-eagoldmaster)

---

## 0. PREREQUISITE: Indicator Backtest

> **KHÔNG ĐƯỢC triển khai strategy hay finalize target trước khi hoàn thành section này.**

### 0.1 Tại sao cần prerequisite

Toàn bộ strategy dựa trên tín hiệu QuantEdge RSI indicator. Nếu indicator không có edge dương, mọi thiết kế DCA/gate/sizing downstream đều vô nghĩa — chỉ trì hoãn và phóng đại thua lỗ.

Tài liệu v1.0 đã mắc lỗi này: đặt target 30%/tháng rồi xây strategy xung quanh, nhưng chính phần phân tích toán (§13 cũ) tự chứng minh target bất khả thi với cấu trúc payoff hiện tại. Target phải **derived** từ measured edge, không phải assumed.

### 0.2 Yêu cầu backtest indicator standalone

| Metric | Yêu cầu | Phương pháp |
|--------|---------|------------|
| Win Rate theo từng case | Đo WR per Case (1,4,5,6,7,8,9) | EA chạy TP_DEFAULT, DCA OFF, backtest M15 Every Tick ≥ 6 tháng |
| Profit Factor theo từng case | PF per Case | Cùng backtest trên |
| Sample size | ≥ 100 trades per case | Mở rộng thời gian nếu thiếu |
| Session breakdown | WR/PF per session block | Phân loại theo Asian/London/NY/LateNY |

### 0.3 Gate quyết định

| Kết quả | Hành động |
|---------|----------|
| **Tất cả cases PF < 1.0** | STOP — indicator chưa sẵn sàng cho DCA strategy |
| **Một số cases PF ≥ 1.3** | Chỉ bật những cases đó, tắt phần còn lại |
| **WR < 56% trên mọi case** | DCA scalping (b=0.8) KHÔNG viable → cần tăng TP1:SL ratio trước |
| **PF ≥ 1.3 + WR ≥ 58%** | Tiến hành strategy design, derive target từ measured WR/PF |

### 0.4 So sánh bắt buộc với EAGoldMaster

Hệ thống EAGoldMaster (trong cùng project workspace) đã test DCA scalping trên XAUUSD với kết quả:
- `Allow_Scalping = false` — PF=0.515 trên 880 trades (**thua hệ thống**)
- `Allow_DCA = false` — đang bị tắt để baseline test
- Asian session PF=0.79 (-$681), NY session PF=0.74 (-$1,145)

QuantEdge indicator dùng RSI signal engine khác (không phải HMM/Bayesian phase), nhưng cùng instrument và cùng concept. **Cần trả lời trước khi tiến hành**: QuantEdge có WR/PF nào, đo trên bao nhiêu trade, và tại sao nó tránh được bẫy mà EAGoldMaster đã đo?

---

## 1. Tổng quan chiến lược

### 1.1 Triết lý

DCA Scalping Intraday kết hợp 2 kỹ thuật:
- **Scalping**: TP ngắn, tần suất cao, tận dụng biến động trong ngày
- **DCA (Dollar Cost Averaging)**: Thêm lệnh khi giá chạy ngược, lot **giảm dần**, chờ recovery về breakeven

Chiến lược KHÔNG phải martingale — lot không tăng lũy tiến. Negative DCA dùng lot giảm dần (75%→50%→25%) để kiểm soát exposure.

### 1.2 Luồng hoạt động chính

```
Indicator phát tín hiệu (BUY/SELL)
  → EA đọc qua iCustom() (buffer 5-25)
  → Signal đi qua 10-Gate Decision Pipeline
  → Tính lot dựa trên risk%/SL distance
  → Đặt lệnh gốc (Original Position)
  → DCA Engine quản lý:
     ├── Negative DCA: thêm lệnh khi giá chạy ngược, lot giảm dần
     └── Basket Management: đóng toàn bộ khi đạt mục tiêu hoặc cap DD
```

### 1.3 Mục tiêu (Data-Driven — chờ §0 hoàn thành)

| Chỉ tiêu | Công thức | Ví dụ (WR=60%, b=0.8) |
|-----------|-----------|------------------------|
| **EV per signal** | `WR × b − (1−WR) × 1` (đơn vị R) | 0.60×0.8 − 0.40×1 = **0.08R** |
| **Monthly return** | `EV × trades/tháng × risk%` | 0.08 × 110 × 1% = **8.8%/tháng** |
| **Kelly fraction** | `WR − (1−WR)/b` | 0.60 − 0.40/0.8 = **10%** |
| **Max DD** | Derived từ Kelly/risk% | < 15-20% |

> **QUAN TRỌNG**: Target return **KHÔNG ĐƯỢC đặt trước**. Nó là output của measured WR/PF, không phải input. Bảng trên chỉ là ví dụ — số thực sẽ khác sau khi chạy §0.

### 1.4 Breakeven Analysis (hằng số cấu trúc)

Với cấu hình M15 hiện tại:
- TP1 = ATR × 0.8, SL = ATR × 1.0 → payoff ratio **b = 0.8**
- Breakeven WR = `1 / (1 + b)` = `1 / 1.8` = **55.56%**
- **Bất kỳ WR nào ≤ 55.56% đều có EV ≤ 0** — dù DCA hay sizing như thế nào

Đây là hằng số cấu trúc — không phụ thuộc ATR, lot, hay account size. DCA không tạo edge mới, nó chỉ thay đổi distribution (nhiều win nhỏ, ít loss lớn).

---

## 2. Thị trường & Công cụ

### 2.1 Tại sao XAUUSD?

| Đặc điểm | Giá trị | Lợi ích cho scalping |
|-----------|---------|----------------------|
| Avg Daily Range | $25-40 | Đủ không gian cho nhiều tín hiệu M15 |
| ATR(14) trên M15 | ~$6-12 | TP1 reachable ($5-10), SL reasonable ($6-12) |
| Spread (ECN) | $0.10-0.30 | Chấp nhận được cho TP1 ~$5-8 |
| Trading hours | 23h/ngày | Nhiều phiên có volatility |

### 2.2 Khung thời gian M15

- **Tín hiệu đủ nhanh**: 3-8 signals/ngày (vs M5: nhiều noise, H1: ít signals)
- **TP reachable**: TP1 = 0.8 × ATR ≈ $5-8, thường đạt trong 1-4 nến
- **Lọc noise**: M15 RSI smoother hơn M1/M5
- **Cooldown hợp lý**: 3 bars = 45 phút giữa các tín hiệu

### 2.3 Phân tích phiên giao dịch

| Phiên | GMT | Đặc điểm | Phù hợp scalping? |
|-------|-----|----------|-------------------|
| **Asian** | 00:00-07:00 | Range hẹp $5-15, low vol | **Hạn chế** — EAGoldMaster PF=0.79 |
| **London** | 07:00-12:00 | Breakout $15-25, strong trend | **Tốt nhất** |
| **NY Overlap** | 12:00-16:00 | Cao nhất vol $20-30 | **Rất tốt** |
| **Late NY** | 16:00-21:00 | Giảm dần $8-15 | **Cần validate** — EAGoldMaster PF=0.74 |
| **Dead Zone** | 21:00-00:00 | Rất thấp $3-8 | **Tránh** |

> **Cảnh báo**: Bảng trên ghi "Tốt nhất" cho London/NY Overlap nhưng đây là **giả thiết cần kiểm chứng** bằng indicator backtest (§0). EAGoldMaster evidence cho thấy cả Asian lẫn NY đều lỗ — QuantEdge có thể khác nhưng cần data chứng minh.

---

## 3. Tín hiệu vào lệnh

### 3.1 Nguồn tín hiệu

Tín hiệu từ QuantEdge RSI indicator, EA đọc qua `iCustom()`:

| Buffer | Nội dung | Cách sử dụng |
|--------|----------|-------------|
| 5 (BuySignal) | Case number (1-9) | Xác định loại tín hiệu BUY |
| 6 (SellSignal) | Case number (1-9) | Xác định loại tín hiệu SELL |
| 7 (Entry) | Giá entry | Entry price |
| 8 (SL) | Stop Loss | SL price |
| 9 (TP1) | Take Profit 1 | Scalp target |
| 10 (TP2) | Take Profit 2 | Swing target |
| 25 (TP3) | Take Profit 3 | Runner target |
| 11 (ProbTP1) | P(TP1 hit) 0-100% | Bộ lọc chất lượng |
| 21 (RecLevel) | 0-5 (STRONG→AVOID) | Gate quyết định |
| 22 (RecConfidence) | 0-100 | Confidence score |
| 23 (RecEV) | Expected Value (R) | EV dương mới vào lệnh |
| 24 (RecRisk) | Risk % đề xuất | Lot sizing |
| 17 (SurvivalRatio) | 0.0-1.0 | Edge còn fresh? |

### 3.2 Signal Cases cho M15

M15 auto-config bật 7/10 cases:

| Case | Tên | Mô tả | Tần suất |
|------|-----|-------|---------|
| 1 | OB/OS Bounce | RSI vượt vùng quá bán/quá mua rồi quay lại | Thường |
| 4 | Strong Trend | RSI xuyên 50 + phá BB Upper/Lower | Ít, chất lượng cao |
| 5 | Orange Near Level | Baseline gần 32/68 + Green cross Red | Thường |
| 6 | Trend Continuation | Pullback về baseline rồi bounce tiếp | **Phổ biến nhất** |
| 7 | Sideway Breakout | Nhiều cross trong BB → phá BB | Ít |
| 8 | Basic Crossover | Green cross Red + momentum xác nhận | Thường |
| 9 | Plain Cross | Green cross Red, không cần angle mạnh | Experimental |

**Cases bị tắt trên M15**: 0 (deprecated), 2 (Regular Divergence — quá chậm), 3 (Hidden Divergence — quá chậm).

**Thứ tự ưu tiên quét** (chỉ các case được bật): Case 6 > 4 > 1 > 5 > 7 > 8 > 9.

> **Chờ §0**: Sau khi có backtest per-case, các case có PF < 1.0 cần bị tắt. Bảng trên sẽ được cập nhật.

### 3.3 Gate Pipeline (10 cửa lọc)

| Gate | Mô tả | Khuyến nghị M15 | Tham số |
|------|--------|-----------------|---------|
| **G1** | Recommendation Level | **ON** | MinRecLevel = `ENTRY` |
| **G2** | Confidence Score | **ON** | MinConfidence = `55` |
| **G3** | Staleness / Survival | **ON** | MaxSurvivalFloor = `0.15` |
| **G4** | No Duplicate Position | **Luôn ON** | DCA có magic riêng |
| **G5** | Max Spread | **ON** | MaxSpreadPoints = `50` ($0.50) |
| **G6** | Session Filter | **ON** | StartHour=7, EndHour=20 (GMT) |
| **G7** | Daily Loss Cap | **ON** | MaxDailyLosses=3, MaxDailyLossPct=3.0% |
| **G8** | ADX Trend Strength | **OFF** | Tích hợp trong indicator |
| **G9** | Economic Calendar | **Cần implement** | Xem §8.4 |
| **G10** | Price Location | **OFF** | Chưa đủ validation |

### 3.4 Signal Retry

- EA cache tín hiệu sau khi xuất hiện
- Retry mỗi tick nếu chưa vào lệnh (do spread/gate block tạm thời)
- Hết hạn sau `RetryMaxBars = 5` nến (75 phút trên M15)
- Hủy khi: giá chạm SL, TP1 đã đạt, survival ratio < floor

---

## 4. Quản lý SL/TP

### 4.1 Phương pháp tính SLTP

M15 auto-config dùng **ATR-based method** (SLTP_ATR = 0):

| Level | Công thức | Ví dụ (ATR=$8) | Mục đích |
|-------|-----------|-----------------|---------|
| **SL** | Entry ± ATR × 1.0 | ~$8 | 1 ATR breathing room |
| **TP1** | Entry ± ATR × 0.8 | ~$6.4 | Scalp target |
| **TP2** | TP1 × 1.5 = ATR × 1.2 | ~$9.6 | Swing target |
| **TP3** | TP1 × 2.5 = ATR × 2.0 | ~$16 | Runner target |

### 4.2 Phân tích payoff ratio (CRITICAL)

```
b = TP1/SL = 0.8/1.0 = 0.8

Breakeven WR = 1/(1+b) = 1/1.8 = 55.56%

Kelly f* theo WR:
  WR=55% → f* = 55% − 45%/0.8 = −1.25%  ← EV ÂM, Kelly nói đừng vào lệnh
  WR=56% → f* = 56% − 44%/0.8 = +1.0%   ← Vừa dương, edge mỏng
  WR=58% → f* = 58% − 42%/0.8 = +5.5%
  WR=60% → f* = 60% − 40%/0.8 = +10.0%
  WR=65% → f* = 65% − 35%/0.8 = +21.25%
```

> **Kết luận**: Với b=0.8, chiến lược CHỈ profitable khi WR > 55.56%. Edge rất mỏng ở WR 56-58%. Cần WR ≥ 60% để có Kelly fraction đáng kể (≥10%). **Nếu indicator backtest cho WR ≤ 56% → cần tăng TP1:SL ratio trước khi DCA có ý nghĩa.**

### 4.3 Lựa chọn TP:SL ratio

Nếu measured WR < 58%, cân nhắc thay đổi cấu trúc:

| Option | TP ratio | SL ratio | b | Breakeven WR | Trade-off |
|--------|----------|----------|---|-------------|-----------|
| Hiện tại | 0.8 | 1.0 | 0.8 | 55.56% | Cần WR cao |
| **Alt A** | 1.2 | 1.0 | 1.2 | 45.45% | WR thấp hơn OK, TP xa hơn |
| **Alt B** | 1.0 | 0.8 | 1.25 | 44.44% | SL chặt, bị stop-out nhiều hơn |
| **Alt C** | 1.5 | 1.0 | 1.5 | 40.00% | TP rất xa, WR sẽ giảm mạnh |

> **Chờ §0**: Decision giữa các option phụ thuộc measured WR tại mỗi TP:SL ratio.

### 4.4 Giới hạn TP (Hard Caps)

| Layer | Cơ chế | M15 Limit |
|-------|--------|-----------|
| **[TP-CAP]** | Fibonacci/Hybrid: TP ≤ 3× parametric ratio | TP1 ≤ ATR × 2.4 |
| **[SCALP-HARD-CAP]** | Cuối `CalculateSLTP()` | TP1 ≤ ATR × 3.0 |
| **ATR method** | Trực tiếp | TP1 = ATR × 0.8 (typical) |

### 4.5 TP Mode cho DCA Scalping

**Khuyến nghị: `TP_DEFAULT` (mode 0)**

- Tất cả lot tại TP1 → đóng nhanh, high win rate
- DCA engine quản lý basket close riêng
- TP_DYNAMIC (split + trail) conflict với DCA basket management

---

## 5. Chiến lược DCA

### 5.1 Positive DCA — TẮT trên M15

> **Kết luận từ review v1.0**: Positive DCA trên M15 scalping là **dead code**. Spacing ATR×2.5 (~$20) vượt xa TP1 (~$6.4) → grid level không bao giờ trigger trước khi basket đóng ở TP1. Toàn bộ subsystem (4 orders, cutoff logic, half-close) là complexity thừa cho M15.

| Tham số | Giá trị | Lý do |
|---------|---------|-------|
| **Enable** | **OFF** | Spacing > TP1 → không bao giờ trigger |

Positive DCA có thể hữu ích trên H1/H4 với TP rộng hơn. Nếu muốn thử trên M15, cần chuyển sang TP2/TP3 mode (TP_DYNAMIC) — nhưng cần test xung đột với basket management trước.

### 5.2 Negative DCA — Recovery Basket

**Mục đích**: Khi giá chạy ngược, thêm lệnh ở giá tốt hơn với lot giảm dần, chờ giá quay lại breakeven.

#### ⚠️ Cảnh báo cấu trúc: Short-Gamma Profile

Negative DCA là cấu trúc **short-gamma**: thắng nhỏ đều đặn (breakeven close), thỉnh thoảng ăn một cú lỗ đuôi lớn (DD-cap cut). Đây là đặc tính cố hữu:

- **Adverse selection**: DD-cap cut xảy ra trong strong trend — chính xác khi basket đã DCA sâu nhất → lỗ lớn nhất đúng lúc sai nhất (negative convexity kép)
- **Asymmetry chi phí**: Một DD-cap cut ($500-$1,500) ăn hết 7-40 trade thắng ($38-77/trade)
- **DCA không tạo edge**: Nó chỉ redistribute loss distribution — nhiều BE nhỏ đổi lấy ít loss lớn. Nếu signal không có edge dương, DCA chỉ trì hoãn thua lỗ

#### Quy tắc

| Tham số | Giá trị | Giải thích |
|---------|---------|-----------|
| Enable | **ON** (conditional — chỉ khi §0 pass) | Bật negative DCA |
| Max Orders | **3** | Tight: chỉ 3 DCA orders |
| Trigger | **50%** Entry→SL | Bắt đầu khi giá đi 50% về phía SL |
| Spacing | **ATR × 2.5** | ~$20 giữa các lệnh |
| Lot giảm dần | **75% → 50% → 25%** | Exposure giảm theo số lệnh |
| Breakeven Close | **ON** | Đóng basket khi giá quay về avg entry |
| BE Offset | **5 pips** | Cần breakeven + 5 pips mới đóng |
| Profit Lock | **1.0R** | Basket cần profit ≥ 1R trước entry-return close |
| DD Cap | **5%** balance | **Tight** — giới hạn cost per DD-cut |
| Min Spacing | **1500 points** (~$15) | Tối thiểu giữa lệnh |
| Min Interval | **5 phút** | Tối thiểu giữa lệnh |

> **Thay đổi quan trọng vs v1.0**: DD cap giảm từ 15% → **5%**, Max orders giảm từ 10 → **3**. Lý do: §13 chứng minh DD-cap cut $1,500 (15%) quá đắt — một lần cut ăn 20-40 trade thắng. Với 5% ($500), cost per cut giảm 3× và recovery nhanh hơn.

#### Lot giảm dần (Pyramid ngược)

| DCA Order # | Lot Ratio | Ví dụ (gốc 0.06) |
|-------------|-----------|-------------------|
| 1 | 75% | 0.05 |
| 2 | 50% | 0.03 |
| 3 | 25% | 0.02 |

**Tổng exposure tối đa** (gốc + 2 neg DCA hiệu dụng — xem phân tích bên dưới):
```
0.06 + 0.05 + 0.03 = 0.14 lot  (effective, DCA #3 không kịp fire)
Tương đương 2.33× lot gốc
```

#### Thực tế: Max Orders hiệu dụng = 2 (DD cap cắt trước DCA #3)

Mô phỏng đường giá đi ngược liên tục (worst-case):

```
Với base lot 0.10, DD cap $500 ($10k × 5%):

Giá đi ngược $x từ Entry:
  $4.00  → Trigger (50% SL) — bắt đầu DCA engine
  $24.00 → DCA #1 fire (ATR×2.5=$20 từ trigger)
           Basket: 0.10 + 0.075 = 0.175 lot
           Floating DD = 0.10×$24 + 0.075×$0 = $2,400 + $0 = $2,400
  
  DD cap fires khi: 0.10×x + 0.075×(x−24) = $500
    → 0.175x − 1.8 = 500
    → x = $28.69 ← DD CAP CẮT TẠI ĐÂY
  
  DCA #2 sẽ fire tại: $24 + $20 = $44.00
  DCA #3 sẽ fire tại: $44 + $20 = $64.00
  
  → DD cap cắt tại $28.69, trước khi DCA #2 kịp fire ($44)
  → Với lot 0.10: CHỈ CÓ 1 DCA order được đặt trước worst-case cut

Với base lot 0.06 (ví dụ account nhỏ hơn):
  Basket sau DCA #1: 0.06 + 0.045 = 0.105 lot
  Basket sau DCA #2: 0.06 + 0.045 + 0.03 = 0.135 lot
  
  DD cap fires khi (sau DCA #2):
    0.06×x + 0.045×(x−24) + 0.03×(x−44) = $500
    → 0.135x − 2.4 = $500 → x = $37.19
    Nhưng DCA #2 fire tại x=$44 > $37.19 → DCA #2 CŨNG không kịp fire

  DD cap fires khi (sau DCA #1 only):
    0.06×x + 0.045×(x−24) = $500
    → 0.105x − 1.08 = $500 → x = $47.72
    DCA #2 fire tại x=$44 < $47.72 → DCA #2 KỊP fire

  DD cap fires khi (sau DCA #2):
    0.135×x − (0.045×24 + 0.03×44) = $500
    → 0.135x − 2.4 = $500 → x = $37.19... 
    Nhưng lúc này cần recalc vì DCA #2 đã fire tại $44:
    0.06×44 + 0.045×(44−24) + 0.03×(44−44) = 2.64 + 0.9 + 0 = $3.54
    Chưa đến $500 → giá tiếp tục
    DD cap fires khi: 0.06×x + 0.045×(x−24) + 0.03×(x−44) = $500
    → 0.135x − 2.4 = $500 → x = $37.19... 
    
  Kết quả lot 0.06: DCA #1 + #2 kịp fire, DCA #3 tại $64 KHÔNG kịp (cap ở ~$47)
```

> **Kết luận**: `MaxOrders=3` là tham số an toàn trên giấy, nhưng:
> - Với **lot 0.10**: effective max = **1** DCA order (DD cap ở ~$29 < DCA #2 ở $44)
> - Với **lot 0.06**: effective max = **2** DCA orders (DD cap ở ~$47 < DCA #3 ở $64)
> - DCA #3 **không bao giờ** được đặt trong cả hai trường hợp
>
> Đây là **tin tốt về an toàn** (DD cap hoạt động đúng vai trò), nhưng nghĩa là khả năng "trung bình giá" yếu hơn con số trên giấy — ít tầng DCA hơn = ít room cho giá quay về avg entry.
>
> **Yêu cầu cho Monte Carlo**: Simulator PHẢI check DD cap tick-by-tick **TRƯỚC** khi đặt DCA order tiếp theo — không giả định cả 3 orders luôn được đặt đủ rồi mới check DD.

#### Luồng xử lý

```
Lệnh gốc mở tại Entry, SL cách $8
  → Giá đi ngược 50% (= $4 về SL)
  → TRIGGER: bắt đầu neg DCA
  → Mỗi lần giá đi thêm ATR×2.5 (~$20) → mở DCA mới (lot giảm dần)
  → Kiểm tra mỗi tick:
     1. DD > 5% balance? → CẮT LỖ TOÀN BỘ basket
     2. Giá quay về avg entry + 5 pips + profit ≥ 1R? → ĐÓNG basket
     3. Giá chạm TP1 gốc? → ĐÓNG basket
```

#### CHƯA GIẢI QUYẾT: DD-cut frequency

Con số "DD-cut xảy ra < 2-3% signals" trong v1.0 **KHÔNG có cơ sở** — nó được backed-into để math ra dương. Cần:

1. **Monte Carlo simulation**: Random walk / GBM trên XAUUSD M15 data thật, với spacing ATR×2.5, trigger 50%, max 3 orders → đo % cases price không quay lại avg entry và hit DD cap
2. **Hoặc backtest thực tế**: Chạy EA với DCA ON, đếm DD-cut events / total baskets
3. **Nếu DD-cut > 5% signals** → negative DCA không viable với tham số này

### 5.3 Basket Close Priority

```
1. DD Cap vượt 5% → CLOSE ALL (safety first)
2. Weekly/Monthly DD cap vượt → CLOSE ALL (§7 Layer 5-6)
3. Tín hiệu ngược chiều + basket đang lời → CLOSE ALL
4. Giá đạt TP1 → CLOSE ALL (profit target)
5. Breakeven + profit lock → CLOSE ALL (recovery thành công)
6. Không còn position nào → AUTO RESET state
```

### 5.4 Opposite Signal Handling

- **Basket đang lời**: Đóng toàn bộ basket, cho phép mở lệnh ngược
- **Basket đang lỗ**: KHÔNG đóng, giữ basket, BLOCK tín hiệu ngược (Gate 4)

---

## 6. Quản lý vốn & Lot

### 6.1 Risk-Based Lot Sizing

```
Lot = (Balance × Risk%) / (SL_distance_points × TickValue)
```

| Tham số | Giá trị | Giải thích |
|---------|---------|-----------|
| Risk% mặc định | **1.0%** | Tăng từ 0.5% (v1.0) vì DD cap giảm từ 15%→5% |
| Risk% từ indicator | Buffer 24 (0-2%) | Điều chỉnh theo chất lượng tín hiệu |
| Min Lot | **0.01** | Flexible hơn cho small accounts |
| Max Lot | **0.10** | Trần tối đa |

> **Lý do tăng risk% từ 0.5% → 1.0%**: Với DD cap giảm 3× (15%→5%), per-signal risk có thể tăng mà vẫn giữ worst-case DD chấp nhận được. Tuy nhiên, cần kiểm tra Kelly fraction từ backtest — nếu Kelly < 5% thì risk% 1.0% vẫn quá aggressive.

### 6.2 Ví dụ tính lot

```
Account: $10,000
Risk: 1.0% = $100
SL distance: $8 (ATR × 1.0)
XAUUSD: 1 lot = 100 oz → $1 move = $100/lot

Lot = $100 / ($8 × 100) = $100 / $800 = 0.125
  → Round down → 0.12 lot
  → Capped: max(0.01, min(0.12, 0.10)) = 0.10 lot

Effective risk% = 0.10 × $800 / $10,000 = 0.80% (KHÔNG PHẢI 1.0% cấu hình)
```

> **Lưu ý lot-cap drift**: Khi lot lý thuyết > MaxLot, risk% thực tế < risk% cấu hình. Ở ví dụ trên: effective risk = **0.80%**, không phải 1.0%. §13.3 Scenario A dùng effective risk (→ 7.04%/tháng), §10.2 dùng nominal (→ 8.8%) — chênh 20%. Khi backtest, **log effective risk% mỗi trade** để so sánh chính xác với công thức derive-target.

### 6.3 Total Exposure Management

| Scenario | Max Positions | Max Lot | Max Loss |
|----------|---------------|---------|----------|
| Signal only (no DCA) | 1 | 0.10 | 1.0% balance ($100) |
| + Negative DCA (effective) | 2-3 (xem §5.2) | 0.145-0.175 | DD cap 5% ($500) |

> **Lưu ý**: Max positions phụ thuộc base lot — lot lớn hơn → DD cap cắt sớm hơn → ít DCA orders kịp fire. Với lot 0.10: effective 2 positions (gốc + 1 DCA). Với lot 0.06: effective 3 positions (gốc + 2 DCA). Xem phân tích chi tiết tại §5.2.

### 6.4 Account Size Recommendations

| Account | Min Lot | Risk% | Max DD-cut | Ghi chú |
|---------|---------|-------|-----------|---------|
| $1,000 | 0.01 | 1.0% | $50 (5%) | Rất tight |
| $5,000 | 0.01 | 1.0% | $250 | Cơ bản |
| $10,000 | 0.01 | 1.0% | $500 | **Khuyến nghị tối thiểu** |
| $25,000+ | 0.01 | 1.0% | $1,250 | Comfortable |

---

## 7. Quản lý rủi ro

### 7.1 Các lớp bảo vệ (7 Defense Layers)

```
Layer 1: SL riêng lệnh gốc (ATR × 1.0)
  ↓
Layer 2: DCA Basket DD Cap (5% balance)
  ↓
Layer 3: Daily Loss Cap (3% balance / 3 losing signals)
  ↓
Layer 4: Weekly DD Stop (10% balance)    ← MỚI
  ↓
Layer 5: Monthly DD Stop (15% balance)   ← MỚI
  ↓
Layer 6: Recovery Mode Circuit Breaker (2 consecutive losses → off)
  ↓
Layer 7: Manual Close Panel (emergency)
```

### 7.2 Chi tiết từng lớp

#### Layer 1: SL riêng lệnh gốc
- SL = ATR × 1.0 (~$8)
- Chỉ áp dụng khi KHÔNG có DCA active
- Khi DCA active: SL lệnh gốc = 0 (managed by basket DD cap)

#### Layer 2: DCA Basket DD Cap
- **5% balance** (cấu hình qua `InpNegDCAMaxDDPct`)
- Kiểm tra MỖI TICK
- Tính trên floating P&L toàn bộ basket
- Vượt → đóng TOÀN BỘ ngay lập tức
- Ví dụ: Account $10,000 → max loss = $500/basket

#### Layer 3: Daily Loss Cap
- Max losing signals/ngày: **3** (giảm từ 5 trong v1.0)
- Max loss/ngày: **3%** balance (giảm từ 5%)
- Reset mỗi ngày GMT 00:00
- Khi đạt cap → BLOCK tất cả tín hiệu mới đến hết ngày
- **Đo realized P&L** (lệnh đã đóng), KHÔNG đo floating P&L của basket đang mở

> **Tương tác Layer 2 ↔ Layer 3** (quan trọng cho spec code):
> Daily cap 3% và basket DD cap 5% **không mâu thuẫn** — chúng đo hai thứ khác nhau:
> - Layer 2 (DD cap): check **floating** P&L mỗi tick → cắt basket khi float ≥ -5%
> - Layer 3 (Daily cap): check **realized** P&L → block tín hiệu mới khi tổng lỗ đóng ≥ -3%
>
> **Ví dụ chuỗi sự kiện**:
> 1. Basket mở, giá chạy ngược → floating DD = -4% → Layer 3 chưa trigger (chưa realized)
> 2. Floating DD = -5% → **Layer 2 fires** → close basket → realized = -5%
> 3. Realized -5% > daily cap 3% → **Layer 3 fires** → block mọi signal hết ngày
>
> **Hệ quả**: Daily cap 3% **không phải trần cứng 3% trên equity**. Nó là "tối đa 1 basket DD-cut/ngày" — vì một DD-cut đã = 5% realized, vượt daily cap 3%, tự động block. Worst-case daily = **-5%** (1 basket), không phải -3%.
>
> **Spec code**: Dev PHẢI implement daily cap trên realized P&L, KHÔNG phải floating. Nếu implement trên floating → Layer 2 (5%) bị shadowed bởi Layer 3 (3%) → basket không bao giờ đạt DD cap → tham số 5% thành dead code.

#### ⚠️ Rủi ro vận hành: SL=0 khi DCA active (Layer 2 là software-only)

Layer 1 nói: "Khi DCA active: SL lệnh gốc = 0" — tức **toàn bộ basket không có stop-loss nào đặt trên broker**. DD cap (Layer 2) là vòng lặp tick-by-tick trong EA. Nếu:
- VPS treo / terminal crash đúng lúc basket đang mở
- Mất kết nối internet kéo dài
- Weekend gap (XAUUSD mở cửa khác giá đóng cửa Friday)

→ Không có gì chặn basket lại cho tới khi EA sống lại. Worst-case: loss không giới hạn.

**Giải pháp: Broker-side Backstop SL**

Đặt SL cứng trên broker cho MỖI position trong basket, tính từ DD cap ÷ tổng lot:

```
BackstopSL_distance = DD_cap_dollars / total_basket_lot / point_value

Ví dụ (sau DCA #1, lot 0.10):
  Total lot = 0.10 + 0.075 = 0.175
  BackstopSL = $500 / 0.175 / 100 = $28.57 từ avg entry
  → Đặt SL cho tất cả positions cách avg entry $28.57

Sau mỗi DCA order mới: recalculate và OrderModify() tất cả SL trong basket
```

- **Đây là safety net**, KHÔNG thay thế DD cap — EA vẫn đóng chính xác tại 5% tick-by-tick
- Backstop SL chỉ fire khi EA offline → wide hơn DD cap một chút (slippage buffer)
- **Cần implement trước khi demo**, không chờ go-live

#### Layer 4: Weekly DD Stop ← MỚI
- **10% balance** trong 1 tuần rolling
- Khi vượt → BLOCK trading đến tuần sau
- Ngăn chặn 2+ DD-cap cuts liên tiếp trong tuần

#### Layer 5: Monthly DD Stop ← MỚI
- **15% balance** trong 1 tháng rolling
- Khi vượt → BLOCK trading đến tháng sau
- **Đây là hard limit cuối cùng** — đảm bảo monthly DD < target bất kể gì xảy ra

> v1.0 thiếu Layer 4-5 và tự tính ra "2 ngày tệ nhất = -34% vượt target 30%" mà không có lớp chặn. Đây là lỗ hổng nghiêm trọng — EAGoldMaster đã có `DD_Weekly_Stop_Pct` và `DD_Monthly_Stop_Pct` trong M08_SafetySystem.

#### Layer 6: Recovery Circuit Breaker
- Xem §9

#### Layer 7: Manual Close Panel
- 5 nút: Close All Profit / Loss / Buy Profit / Sell Profit / CLOSE ALL

### 7.3 Bảng tóm tắt risk limits

| Risk Metric | Limit | Đo trên | Hành động |
|-------------|-------|---------|-----------|
| Per-signal risk | 1.0% balance | — | Lot sizing tự điều chỉnh |
| Per-basket DD | 5% balance | **Floating** (mỗi tick) | Close entire basket |
| Daily loss (count) | 3 signals | **Realized** (đã đóng) | Block signals hết ngày |
| Daily loss (%) | 3% balance | **Realized** | Block signals hết ngày |
| **Weekly DD** | **10% balance** | **Realized** | **Block trading hết tuần** |
| **Monthly DD** | **15% balance** | **Realized** | **Block trading hết tháng** |
| Recovery consecutive loss | 2 | — | Tắt recovery mode |

> **Worst-case daily = -5%** (1 basket DD-cut), không phải -3%. Xem §7.2 Layer 3 giải thích tương tác.

### 7.4 Worst-Case Analysis (sửa lại)

```
Scenario xấu nhất trong 1 ngày:
  09:00 — Basket mở, giá chạy ngược
  10:15 — Floating DD = -5% → Layer 2 (basket DD cap) fires → CLOSE basket
  10:15 — Realized loss = -5% > daily cap 3% → Layer 3 fires → BLOCK signals hết ngày
  → Max daily loss = -5% (1 basket DD-cut, daily cap chặn basket thứ 2)

Scenario xấu nhất trong 1 tuần:
  Ngày 1: DD-cap cut = -5%, daily cap blocks → hết ngày
  Ngày 2: DD-cap cut = -5% → tổng tuần = -10%
  → Weekly DD stop fires → BLOCK hết tuần
  → Max weekly loss = -10%

Scenario xấu nhất trong 1 tháng:
  Tuần 1: -10% (2 DD-cuts) → weekly stop
  Tuần 2: bị block (weekly stop còn hiệu lực)
  Tuần 3: -5% (1 DD-cut) → tổng tháng = -15%
  → Monthly DD stop fires → BLOCK hết tháng
  → Max monthly loss = -15% (WITHIN target)
```

---

## 8. Bộ lọc phiên giao dịch

### 8.1 Session Filter Settings

| Tham số | Giá trị | Mục đích |
|---------|---------|---------|
| Enable | **ON** | Gate 6 |
| Start Hour | **7** (GMT) | Bắt đầu London session |
| End Hour | **20** (GMT) | Kết thúc Late NY |

### 8.2 Session-Specific Behavior

| Phiên | Giờ GMT | Chiến thuật |
|-------|---------|------------|
| **London Open** | 07:00-09:00 | Breakout trades, Case 4/7 |
| **London Mid** | 09:00-12:00 | Trend continuation, Case 6 |
| **NY Overlap** | 12:00-16:00 | High volatility, tất cả cases |
| **Late NY** | 16:00-20:00 | Giảm dần, Case 1/5/6 |
| **Ngoài 07-20 GMT** | | **KHÔNG GIAO DỊCH** |

### 8.3 Special Case Hard Blocks

- **Case 6** bị block trong **Asian** và **Late NY** (cấu hình qua `InpHardCase6Asian`, `InpHardCase6LateNY`)
- Lý do: Trend Continuation cần momentum, phiên yếu → false signals

### 8.4 News Avoidance

Gate 9 (Economic Calendar) hiện tại **OFF** vì cần data feed external.

**Giải pháp cần implement** (v1.0 nói "xử lý manual" — mâu thuẫn với mục tiêu automated):
- **Option A**: Implement Gate 9 đọc MQL5 calendar API (MQL5 built-in)
- **Option B**: External service ghi news schedule vào file, EA đọc file
- **Option C**: Tạm thời, thêm `InpNewsBlackoutMinutes` — block N phút quanh known high-impact times (NFP: first Friday, FOMC: 8x/year)

> Cho đến khi implement, **không claim EA là "tự thích nghi"** — nó cần manual intervention cho news.

---

## 9. Recovery Mode

### 9.1 Đánh giá trung thực

Recovery Mode (×1.3 lot sau DD-cap cut) dựa trên giả định ngầm: "sau khi cut thì regime sẽ thuận lợi hơn" → tức là mean-reversion-of-edge. **Không có bằng chứng nào cho giả định này.**

Về bản chất, đây là **revenge sizing** được đóng gói lịch sự: tăng size ngay sau cú lỗ lớn nhất. Circuit breaker (2 consecutive loss → off) giảm thiểu damage nhưng không thay đổi vấn đề gốc.

### 9.2 Khuyến nghị: OFF mặc định

| Tham số | Giá trị | Lý do |
|---------|---------|-------|
| **Enable** | **OFF** | Không có evidence cho mean-reversion-of-edge |

### 9.3 Điều kiện để BẬT Recovery Mode

Recovery Mode CHỈ nên được bật nếu backtest chứng minh:
1. **Post-DD-cut WR cao hơn baseline WR** — evidence rằng regime thuận lợi hơn sau cut
2. **Recovery trades có PF > 1.3** — edge thực sự cải thiện
3. **Circuit breaker đã test**: Monte Carlo xác nhận worst-case recovery sequence vẫn trong budget

Nếu không có evidence trên → giữ Recovery OFF. Chấp nhận DD-cut như chi phí bình thường, hồi vốn bằng edge thường, không tăng size.

### 9.4 Cơ chế (nếu bật)

```
DD Cap Cut → Basket closed → Recovery activated
  → Record pre-loss equity
  → Next signal: lot × 1.3 (MAX, không phải 1.5 hay 2.0)
  → Circuit breaker:
     - 2 consecutive losses → OFF (cứng)
     - 3 trades total không recovery → OFF (timeout ngắn)
  → Equity hồi → OFF
```

---

## 10. Mục tiêu hiệu suất & Benchmark

### 10.1 KPIs (Data-Driven — chờ §0)

> **v1.0 đặt target WR ≥ 55% — nằm DƯỚI breakeven WR 55.56%.** Toàn bộ vùng "acceptable" cũ (50-55%) có EV âm. Bảng dưới sửa lại.

| Chỉ tiêu | Minimum Viable | Target | Ghi chú |
|-----------|---------------|--------|---------|
| Win Rate | > 56% | ≥ 60% | BE = 55.56% với b=0.8 |
| Profit Factor | > 1.1 | ≥ 1.3 | PF < 1 = thua |
| Monthly Return | **Derived từ data** | **Derived** | Xem §13 công thức |
| Max DD (monthly) | < 15% | < 10% | Hard-coded Layer 5 |
| Sharpe Ratio (ann.) | ≥ 1.0 | ≥ 2.0 | |
| Avg Trade Duration | < 4 giờ | < 2 giờ | Scalping = nhanh |
| Max Consecutive Losses | ≤ 5 | ≤ 3 | |
| DCA Recovery Rate | ≥ 60% | ≥ 75% | % basket close ở BE+ |
| **DD-cut Rate** | **< 5%** | **< 2%** | **% signals dẫn đến DD-cap cut** |

### 10.2 Công thức derive monthly return

```
Monthly Return = EV_per_signal × signals_per_month × risk%

Trong đó:
  EV_per_signal (R) = WR × b − (1−WR) × 1
  signals_per_month ≈ signals_per_day × 22
  risk% = Kelly_fraction / 2 (half-Kelly cho conservative)

Ví dụ (WR=60%, b=0.8, 5 signals/ngày):
  EV = 0.60×0.8 − 0.40×1 = 0.08R
  Signals/tháng = 5 × 22 = 110
  Kelly = 10% → Half-Kelly = 5%
  Monthly = 0.08 × 110 × 5% = 0.44 = 44%  ← theoretical max, thực tế thấp hơn nhiều
  
  Với risk% cấu hình 1%:
  Monthly = 0.08 × 110 × 1% = 8.8%  ← nominal, giả định lot không bị cap

  ⚠️ Nếu lot-cap kích hoạt (0.125→0.10), effective risk = 0.80%:
  Monthly = 0.08 × 110 × 0.8% = 7.04%  ← khớp §13.3 Scenario A

  Trừ DCA drag (ước tính -2% đến -5% tùy DD-cut rate):
  Realistic monthly ≈ 3-5% (effective risk) đến 4-7% (nominal risk)
```

### 10.3 Backtest Validation Criteria

Chiến lược PASS nếu đạt TẤT CẢ trong column "Minimum Viable" (§10.1).

**Thời gian backtest**: ≥ 6 tháng M15 XAUUSD  
**Chất lượng data**: **Every Tick bắt buộc** (DCA logic path-dependent — giá giữa nến ảnh hưởng trigger/DD cap. Open Prices cho kết quả sai lệch.)

---

## 11. Tham số khuyến nghị

### 11.1 Profile: Baseline (bắt đầu tại đây)

```
=== EA Settings ===
InpEnableAutoTrading = true
InpMagicNumber       = 20260901

=== Decision Gates ===
InpUseGate1RecLevel  = true
InpMinRecLevel       = ENTRY          // Chỉ STRONG + ENTRY
InpAllowCaution      = false
InpUseGate2Confidence= true
InpMinConfidence     = 55
InpUseGate3Staleness = true
InpMaxSurvivalFloor  = 0.15
InpUseGate5Spread    = true
InpMaxSpreadPoints   = 50             // $0.50
InpUseSessionFilter  = true
InpSessionStartHour  = 7
InpSessionEndHour    = 20
InpUseDailyLossCap   = true
InpMaxDailyLosses    = 3
InpMaxDailyLossPct   = 3.0

=== Trade Management ===
InpTPMode            = TP_DEFAULT     // Tất cả lot tại TP1
InpUseSignalRetry    = true
InpRetryMaxBars      = 5

=== Positive DCA ===
InpUsePositiveDCA    = false          // TẮT trên M15 (spacing > TP1)

=== Negative DCA ===
InpUseNegativeDCA    = true           // ON (conditional — cần §0 pass)
InpNegDCAMaxOrders   = 3              // Safety param; effective max = 1-2 tùy lot (§5.2)
InpNegDCATriggerPct  = 50.0
InpNegDCAATRMult     = 2.5
InpNegDCAMaxDDPct    = 5.0            // 5% (giảm từ 15%)
InpNegDCABEClose     = true
InpNegDCABEOffsetPip = 5.0
InpDCAProfitLockR    = 1.0
InpDCAMinSpacingPts  = 1500
InpDCAMinIntervalMin = 5

=== Risk & Lot ===
InpDefaultRiskPct    = 1.0            // Tăng từ 0.5% vì DD cap nhỏ hơn
InpMaxLotSize        = 0.10
InpMinLotSize        = 0.01

=== Recovery ===
InpUseRecoveryMode   = false          // OFF mặc định — cần evidence trước

=== Weekly/Monthly DD Stop (CẦN IMPLEMENT) ===
// InpMaxWeeklyDDPct  = 10.0          // Block trading nếu weekly DD > 10%
// InpMaxMonthlyDDPct = 15.0          // Block trading nếu monthly DD > 15%
```

### 11.2 Thay đổi so với v1.0

| Tham số | v1.0 | v2.0 | Lý do |
|---------|------|------|-------|
| Positive DCA | ON | **OFF** | Spacing > TP1 → dead code |
| Neg DCA Max Orders | 5-10 | **3** (effective 1-2) | DD cap cắt trước order #3 (§5.2) |
| DD Cap | 15% | **5%** | 15% quá đắt per-cut |
| Daily Loss Cap | 5/5% | **3/3%** | Chặt hơn, ngăn 2 DD-cuts/ngày |
| Risk% | 0.5% | **1.0%** | DD cap nhỏ hơn cho phép risk cao hơn |
| Recovery Mode | ON | **OFF** | Revenge sizing, cần evidence |
| Weekly DD Stop | — | **10%** | Mới, ngăn chuỗi thua tuần |
| Monthly DD Stop | — | **15%** | Mới, hard limit cuối cùng |
| Fitness Function | EV×√N | **Calmar** | Cần phạt tail risk |
| Backtest Mode | Open Prices OK | **Every Tick** | DCA path-dependent |

---

## 12. Quy trình Backtest & Tối ưu

### 12.1 Quy trình 3 bước (PREREQUISITE FIRST)

```
STEP 1: Indicator Standalone Backtest (§0)
  → EA chạy DCA OFF, TP_DEFAULT
  → Đo WR/PF per case, per session
  → Gate: PF ≥ 1.3 trên ≥ 1 case?

STEP 2: DCA Backtest  
  → Bật DCA với Baseline profile (§11.1)
  → Every Tick mode
  → Đo DD-cut rate, DCA Recovery Rate, monthly return

STEP 3: Walk-Forward Validation
  → 3 windows OOS
  → OOS results consistent?
```

### 12.2 Walk-Forward Optimization

```
Tổng data: 12 tháng
  Window 1: IS = tháng 1-4, OOS = tháng 5-6
  Window 2: IS = tháng 3-6, OOS = tháng 7-8
  Window 3: IS = tháng 5-8, OOS = tháng 9-12

Kết quả OOS phải consistent qua 3 windows.
```

### 12.3 Tham số tối ưu hóa

| Tham số | Range | Step | Optimize? |
|---------|-------|------|-----------|
| `InpNegDCAMaxOrders` | 2-5 | 1 | Có |
| `InpNegDCATriggerPct` | 30-70 | 10 | Có |
| `InpNegDCAATRMult` | 1.5-4.0 | 0.5 | Có |
| `InpNegDCAMaxDDPct` | 3-8 | 1 | Có |
| `InpMinConfidence` | 50-65 | 5 | Có |
| `InpMinRecLevel` | 1-3 | 1 | Có |
| Risk%, Lot caps | — | — | **Không** |
| Session hours | — | — | **Không** |
| Indicator params | — | — | **Không** |

### 12.4 Fitness Function

> **v1.0 dùng `EV × √N`** — không phạt tail/DD. Với chiến lược short-gamma (neg DCA), optimizer sẽ chọn tham số "chưa gặp" DD-cap trong in-sample.

**Khuyến nghị: Calmar Ratio hoặc Sortino Ratio**

```c
// OnTester() — Calmar proxy with guards
double OnTester()
{
   if(TesterStatistics(STAT_TRADES) < 30) return 0;  // tránh ratio ảo từ ít trade
   double netProfit = TesterStatistics(STAT_PROFIT);
   double maxDD    = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   if(maxDD < 0.1) return 0;  // STAT_EQUITY_DD_RELATIVE trả về % (vd 15.5), không phải fraction
   return netProfit / maxDD;
}
```

### 12.5 Phòng chống Overfit

- **Ít tham số optimize**: 6 tham số → ít degrees of freedom
- **Walk-Forward**: 3 windows OOS validation
- **Robust region**: Chọn tham số ở vùng flat, không peak spike
- **Monte Carlo**: Shuffle trade order, kiểm tra DD distribution
- **Cross-reference**: So sánh kết quả với EAGoldMaster findings (§14)

### 12.6 Checklist trước khi Go Live

- [ ] **§0 PASS**: Indicator standalone PF ≥ 1.3 trên ≥ 1 case, WR > 56%
- [ ] **§0 Compare**: QuantEdge results vs EAGoldMaster — explain difference
- [ ] Backtest DCA profile ≥ 6 tháng Every Tick
- [ ] DD-cut rate < 5%?
- [ ] DCA Recovery Rate > 60%?
- [ ] Walk-Forward 3 windows OOS consistent?
- [ ] Monthly DD < 15% across all windows?
- [ ] Win Rate > 56% (above breakeven 55.56%)?
- [ ] Profit Factor > 1.1?
- [ ] Demo account ≥ 2 tuần: consistent với backtest?
- [ ] Spread impact: test với spread $0.30?
- [ ] Backtest period chứa high-impact news (NFP, FOMC)?
- [ ] Weekly/Monthly DD stop đã implement?
- [ ] Broker-side backstop SL cho DCA basket đã implement? (§7.2)

---

## 13. Phụ lục A: Phân tích toán học EV & Target

### 13.1 Hằng số cấu trúc

```
TP1 = ATR × 0.8, SL = ATR × 1.0
  → payoff ratio b = 0.8 (bất biến theo ATR, lot, account size)
  → Breakeven WR = 1/(1+0.8) = 55.56%
  → EV(R) = WR × 0.8 − (1−WR) × 1
```

### 13.2 EV per signal theo Win Rate

| WR | EV (R) | Kelly f* | Verdict |
|----|--------|----------|---------|
| 50% | -0.10 | -12.5% | Lỗ, đừng trade |
| 52% | -0.064 | -8.0% | Lỗ |
| 54% | -0.028 | -3.5% | Lỗ |
| 55% | -0.01 | -1.25% | Lỗ (dưới breakeven) |
| **55.56%** | **0.00** | **0%** | **Breakeven** |
| 56% | +0.008 | +1.0% | Vừa dương, edge rất mỏng |
| 58% | +0.044 | +5.5% | Edge mỏng nhưng dương |
| **60%** | **+0.08** | **+10%** | **Edge decent** |
| 62% | +0.116 | +14.5% | Edge tốt |
| 65% | +0.17 | +21.25% | Edge mạnh |

### 13.3 Scenario Analysis (hoàn chỉnh, không "???")

**Giả sử**: Account $10,000, Risk 1%, lot ~0.12 (capped 0.10), ATR=$8

#### Scenario A: Signal only (DCA OFF), WR=60%

```
TP1 profit = $6.4 × 10 (0.10 lot) = $64/trade
SL loss    = $8.0 × 10 = $80/trade
EV/trade   = 0.60 × $64 − 0.40 × $80 = $38.4 − $32 = $6.4

5 signals/ngày → $6.4 × 5 = $32/ngày
22 days → $32 × 22 = $704/tháng = 7.04%/tháng
```

#### Scenario B: DCA ON (tight: DD cap 5%, max 3 orders), WR=60%

```
Phân bố 100 signals:
  55 TP1 hit trực tiếp (55%): 55 × $64 = $3,520
  25 DCA triggered → recovery breakeven+ (25%): 25 × $10 = $250
  10 DCA triggered → DD cap cut (10%): 10 × $500 = $5,000
  10 SL hit trước DCA trigger (10%): 10 × $80 = $800

Net per 100 signals = $3,520 + $250 − $5,000 − $800 = -$2,030

→ -$2,030/100 signals = -$20.3/signal → LỖ
```

#### Scenario C: DCA ON, DD-cut rate chỉ 3%

```
Phân bố 100 signals:
  55 TP1 direct (55%): 55 × $64 = $3,520
  32 DCA recovery (32%): 32 × $10 = $320
  3 DD cap cut (3%): 3 × $500 = $1,500
  10 SL hit (10%): 10 × $80 = $800

Net = $3,520 + $320 − $1,500 − $800 = +$1,540/100 signals
= +$15.4/signal

5 signals/ngày × 22 days = 110 signals/tháng
Monthly = 110 × $15.4 = $1,694 = 16.9%/tháng
```

#### Scenario D: DCA ON, DD-cut rate 1%, DCA recovery yield $20

```
Phân bố 100 signals:
  55 TP1 direct (55%): 55 × $64 = $3,520
  34 DCA recovery (34%): 34 × $20 = $680
  1 DD cap cut (1%): 1 × $500 = $500
  10 SL hit (10%): 10 × $80 = $800

Net = $3,520 + $680 − $500 − $800 = +$2,900/100 signals
= +$29/signal

Monthly = 110 × $29 = $3,190 = 31.9%/tháng
```

#### Lưu ý về mô hình 4-bucket

Phân bố 4 bucket (TP1 direct / DCA recovery / DD-cut / fast SL) tự洽 với baseline WR=60%:
```
would-be-winner trong DCA zone = 60% (WR) − 55% (clean TP1) = 5%
would-be-loser trong DCA zone  = 40% (loss) − 10% (fast SL)  = 30%
Tổng DCA zone = 35% ✓ (khớp 25-34% recovery + phần DD-cut)
```

Tuy nhiên, con số "$10-$20/signal" cho DCA recovery là **trung bình phẳng** che giấu phân bố **bimodal**:

| Nhóm con | % signals | P&L thực tế | Giải thích |
|----------|-----------|-------------|-----------|
| **(a)** Would-be-winner dipped rồi quay | ~5% | **> TP1** ($64+) | Giá quay mạnh, DCA lots cũng ăn lời → profit > signal thường |
| **(b)** Would-be-loser được DCA cứu | ~25-30% | **≈ BE+5pips** ($5-10) | Giá chỉ hồi vừa đủ avg entry, profit = offset nhỏ |

Weighted avg: (5% × $80 + 25% × $8) / 30% ≈ $20 — khớp con số dùng trong Scenario D. Nhưng:
- Nhóm (a) đóng góp upside bất ngờ mà trung bình phẳng bỏ qua
- Nhóm (b) chiếm phần lớn nhưng profit gần zero

**Yêu cầu cho Monte Carlo / backtest**: Log P&L mỗi basket riêng lẻ thành **phân phối liên tục**, không gán trước 2 con số trung bình. Nếu không → vô tình bù phần (a) vào phần (b) hoặc ngược lại.

### 13.4 Phân tích sensitivity: DD-cut rate là biến quyết định

```
Với WR=60%, 0.10 lot, 5 sig/ngày, DD cap $500:

DD-cut rate | DCA recovery | Monthly Return | Verdict
1%          | 34%          | +31.9%         | Rất tốt (nhưng 1% realistic?)
3%          | 32%          | +16.9%         | Tốt
5%          | 30%          | +6.9%          | Chấp nhận
7%          | 28%          | -3.1%          | LỖ
10%         | 25%          | -$20.3/sig     | THẢM HỌA
```

> **Kết luận**: DD-cut rate là biến số #1 quyết định chiến lược sống hay chết. Threshold: < 5% mới dương. CẦN Monte Carlo simulation trên XAUUSD data thật để đo con số này, không thể giả định.

### 13.5 So sánh v1.0 vs v2.0

| Tham số | v1.0 | v2.0 | Impact |
|---------|------|------|--------|
| DD cap | 15% ($1,500) | 5% ($500) | Per-cut cost giảm 3× |
| Max neg DCA | 10 | 3 | Ít positions → ít adverse selection |
| Risk% | 0.5% | 1.0% | Per-win profit tăng 2× |
| Cost per cut / wins needed to recover | $1,500 / 39 wins | $500 / 8 wins | **Recovery 5× nhanh hơn** |

v2.0 tight config giảm magnitude per-cut nhưng DD-cut **rate** có thể tăng (ít DCA orders = ít cơ hội recovery trước khi hit cap). Trade-off này cần backtest để validate.

### 13.6 Target 30%/tháng: Khả thi hay không?

```
30%/tháng trên $10k = $3,000/tháng
Duy trì 12 tháng = (1.3)^12 = +2,330%/năm
Với DD cap 15% → Return/DD ratio = 2,330/15 = 155× → KHÔNG TỒN TẠI trong thực tế

So sánh:
  Renaissance Medallion Fund: ~66%/năm, DD ~10% → Return/DD ≈ 7×
  Top quant funds: 30-50%/năm → Return/DD ≈ 3-5×
```

**Kết luận**: 30%/tháng sustained là target marketing, không phải target risk-derived. Realistic range cho thin-edge scalping:

| Scenario | WR | DD-cut rate | Monthly | Annual |
|----------|----|----|---------|--------|
| Conservative | 58% | 5% | 3-5% | 40-80% |
| Moderate | 60% | 3% | 8-12% | 150-290% |
| Optimistic | 62% | 2% | 15-20% | 435-790% |
| **Fantasy** | **65%** | **1%** | **30%+** | **2,000%+** |

> Moderate (8-12%/tháng) đã là **cực kỳ tốt** so với bất kỳ quant fund nào. Đặt target ở đây nếu WR ≥ 60% confirmed.

---

## 14. Phụ lục B: Counter-Evidence từ EAGoldMaster

### 14.1 Evidence tóm tắt

EAGoldMaster (cùng workspace, khác signal engine) đã test DCA scalping trên XAUUSD:

| Feature | Kết quả | Code Reference |
|---------|---------|---------------|
| Scalping mode | PF=0.515, 880 trades → **DISABLED** | `Allow_Scalping = false` |
| DCA | Đang bị tắt baseline test | `Allow_DCA = false` |
| Asian session | PF=0.79, -$681 → **DISABLED** | `Allow_Asian_Scalp = false` |
| NY session | PF=0.74, -$1,145 → **DISABLED** | `Allow_NY_Trade = false` |
| Signal score 60-70 | PF=0.58 → thua | `Min_Signal_Score = 75.0` |
| Signal score 70-80 | PF=0.98 → hòa vốn | Cao nhất cũng chỉ BE |

### 14.2 Ý nghĩa cho QuantEdge

1. **Khác signal engine** (HMM/Bayesian vs RSI) → kết quả không transfer trực tiếp
2. **Nhưng cùng instrument + concept** → nâng ngưỡng bằng chứng cao:
   - QuantEdge CẦN chứng minh nó có edge mà EAGoldMaster không có
   - Cụ thể: WR/PF theo case, theo session, sample size
3. **Câu hỏi cần trả lời trước khi build**:
   - QuantEdge Case 6 (phổ biến nhất) có PF bao nhiêu trên M15?
   - Asian/Late NY sessions: QuantEdge có tránh được PF < 1 không?
   - DCA recovery rate trên QuantEdge: bao nhiêu % basket close ở BE+?

### 14.3 Bài học áp dụng

- **Đừng assume edge** — đo trước, design sau
- **Session filter là critical** — EAGoldMaster thua ở 2/4 sessions
- **Signal quality gate quan trọng hơn DCA design** — nếu PF < 1 ở input, DCA chỉ khuếch đại thua lỗ
- **DCA không phải magic** — nó là tool quản lý loss distribution, không phải nguồn edge

---

## Tóm tắt & Action Items

### Thay đổi chính v1.0 → v2.0

1. **Target**: Bỏ 30%/tháng cố định → derive từ measured WR/PF (realistic: 5-12%/tháng)
2. **Prerequisite**: Bắt buộc indicator backtest standalone trước khi design
3. **Positive DCA**: TẮT trên M15 (dead code)
4. **Negative DCA**: Tight hơn (3 orders, DD cap 5% thay vì 10 orders, 15%)
5. **Recovery Mode**: OFF mặc định, cần evidence trước khi bật
6. **Defense**: Thêm Weekly/Monthly DD stop (Layer 4-5)
7. **Fitness**: Calmar/Sortino thay EV×√N
8. **Backtest**: Every Tick bắt buộc (path-dependent)
9. **Counter-evidence**: Reference EAGoldMaster findings
10. **Toán học**: Hoàn chỉnh, không "???" — trình bày kết quả âm thẳng thắn

### Action Items

```
STEP 0 (BLOCKING): Indicator Backtest Standalone
  → Chạy EA, DCA OFF, TP_DEFAULT, M15 XAUUSD, Every Tick, ≥ 6 tháng
  → Report: WR/PF per case, per session
  → Gate decision: proceed or stop

STEP 1: DCA Parameter Validation  
  → Monte Carlo hoặc backtest DD-cut rate
  → Nếu DD-cut > 5% → điều chỉnh tham số hoặc bỏ neg DCA

STEP 2: Implement Weekly/Monthly DD Stop + Backstop SL
  → Thêm InpMaxWeeklyDDPct, InpMaxMonthlyDDPct vào EA
  → Implement broker-side backstop SL cho DCA basket (§7.2)
  → Backstop SL = DD_cap / total_lot, recalc sau mỗi DCA order

STEP 3: Implement News Gate (Gate 9)
  → MQL5 calendar API hoặc file-based

STEP 4: Fitness Function
  → Đổi OnTester() sang Calmar proxy

STEP 5: Walk-Forward Validation
  → 3 windows, Every Tick

STEP 6: Demo Account
  → ≥ 2 tuần, compare với backtest
```

---

*Document v2.1 — sửa 6 điểm tự洽 từ review vòng 2: DCA #3 dead parameter, daily/basket cap ordering, effective risk%, DCA P&L bimodal, broker-side backstop SL, OnTester() guards. Chờ §0 hoàn thành trước khi finalize.*
