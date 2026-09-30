# Đánh giá backtest XAUUSD M15 — 2/2024 đến 12/2024

> **Ngày**: 2026-09-25
> **Nền tảng**: MT4, `QuantEdge_EA_Template.mq4`
> **Vốn**: $1,000 · **Spread**: Current (50 point, cố định) · **Model**: Every tick
> **Verdict**: ❌ **CHƯA đạt chuẩn chạy live** — xem §5
>
> ⚠️ **Đọc §10 trước**. Phân tích từng leg (2026-09-25) phát hiện backtest chạy vàng **3 chữ
> số** trong khi live là 2 chữ số → mọi input tính bằng point lệch 10×, và PosDCA (31% lợi
> nhuận backtest) gần như không chạy trên live. §1–§9 mô tả đúng report, nhưng report không mô
> tả EA live. Giải pháp và kế hoạch kiểm chứng mới ở §10.3–§10.4.
>
> **§11 (2026-09-29)**: backtest đầu tiên trên build ptscale với default mới — rủi ro đuôi giảm
> mạnh (MaxDD 25.6%, basket tệ nhất −$542). **§11.6**: chạy lại ở spread $0.40 → PF 1.35, H1 1.48 /
> H2 1.25; ước lượng "H2 PF 0.96" ở §11.3 là **sai**. Vẫn chưa đạt live (z 1.22, RF 1.97, DD 29%).

---

## 1. Kết quả thô

| Chỉ số | Giá trị |
|--------|---------|
| Net profit | **+$8,342.46** (+834%) |
| Gross profit / loss | $24,707.43 / −$16,364.97 |
| Profit Factor | **1.51** |
| Expected payoff | $5.26/lệnh |
| Total trades | 1,586 (1,139 thắng / 447 thua) |
| Win rate | **71.82%** |
| Maximal drawdown | **$4,914.90 (38.12%)** |
| Absolute drawdown | $262.36 |
| Lệnh thắng lớn nhất / thua lớn nhất | $144.57 / **−$353.05** |
| TB thắng / TB thua | $21.69 / −$36.61 |
| Chuỗi thắng dài nhất | 28 lệnh (+$531.95) |
| Chuỗi thua dài nhất | 20 lệnh (**−$3,122.64**) |

---

## 2. Phân tích edge

### 2.1 Edge dương và có ý nghĩa thống kê — *nếu* mẫu độc lập

```
payoff b      = avgWin / avgLoss = 21.69 / 36.61 = 0.592
breakeven WR  = 1 / (1 + b)      = 62.80%
WR thực tế    = 71.82%           (95% CI: 69.60% – 74.03%)
biên edge     = +9.02 pp
z-score       = 7.98
```

Expectancy $5.26/lệnh với độ lệch chuẩn ~$26.23 → **t-stat = 7.98**. Về mặt số học, đây không
phải may rủi.

**Nhưng** toàn bộ tính toán trên giả định 1,586 quan sát độc lập — và chúng không độc lập.

### 2.2 Mẫu không độc lập: WR 71.82% là con số per-LEG

Config bật `InpUsePositiveDCA = 1` (tối đa 4) và `InpUseNegativeDCA = 1` (tối đa 10). Một tín
hiệu có thể sinh tối đa **1 + 4 + 10 = 15** lệnh đóng. MT4 đếm mỗi leg là một "trade".

Legs của negative DCA mở ở giá **tốt hơn** lệnh gốc, nên khi basket hồi về TP1 thì chúng đóng
xanh trong khi lệnh gốc có thể vẫn đỏ. Điều này đẩy WR per-leg lên cao một cách hệ thống.

| Giả định legs/basket | Số basket độc lập |
|---------------------|-------------------|
| 2 | ~793 |
| 3 | ~529 |
| 4 | ~396 |
| 5 | ~317 |

→ Mọi chỉ số per-trade (WR, PF, t-stat) phải được đọc lại ở mức basket. Đây là việc **V1**.

---

## 3. Rủi ro — chỗ hỏng thật sự

### 3.1 Recovery factor 1.70 là con số quyết định

```
Recovery factor = net profit / max drawdown = 8,342 / 4,915 = 1.70
```

Chuẩn quant tối thiểu là **3.0**. Ở 1.70, lợi nhuận cả năm chỉ gấp 1.7 lần mức sụt vốn tệ nhất.

| Rủi ro đuôi | Giá trị | Quy ra vốn ban đầu |
|------------|---------|-------------------|
| Lệnh lỗ lớn nhất | −$353.05 | **35.3%** |
| Chuỗi lỗ tệ nhất | −$3,122.64 (20 lệnh) | **312%** |
| MaxDD | −$4,914.90 | 38.12% |

Chuỗi lỗ tệ nhất cần **144 lệnh thắng trung bình** để gỡ. Nó xảy ra ở giữa chu kỳ khi vốn đã
lớn nên sống sót — **nếu rơi vào đầu chu kỳ, tài khoản đã cháy**. Backtest không cho biết xác
suất của kịch bản đó.

### 3.2 MaxDD 38.12% là DD *không bị chặn*

Mọi circuit breaker đều tắt trong preset này:

| Input | Giá trị |
|-------|---------|
| `InpUseDailyLossCap` | 0 |
| `InpUseWeeklyDDStop` | 0 |
| `InpUseMonthlyDDStop` | 0 |
| `InpUseDCABackstopSL` | 0 |

Nghĩa là **không biết trần DD thật ở đâu** — 38.12% chỉ là mức tệ nhất *đã xảy ra*, không phải
mức tệ nhất *có thể xảy ra*.

### 3.3 Equity curve: short-gamma ở mức cực đoan

Đường đi lên mượt + 5–6 vách dốc đứng. Nguyên nhân cấu trúc: với `InpNegDCABEClose = 0`, một
basket thua chỉ còn **hai** lối thoát (`ManageDCA()`):

1. Giá quay về `g_dcaOriginalTP1` → `CloseEntireBasket()`
2. `CheckDrawdownCap()` cắt khi lỗ ≥ 15% balance

Cơ chế "đóng khi giá về avg entry" — van xả trung gian, thứ làm DCA có ý nghĩa — **đang tắt**.
Các vách dốc chính là DD-cap cut.

Chi phí mỗi lần cut tăng theo vốn:

| Vốn | 1 lần DD-cap cut (15%) |
|-----|------------------------|
| $1,000 | $150 |
| $3,000 | $450 |
| $6,000 | $900 |
| $9,342 | $1,401 |

MaxDD $4,915 ≈ 2.5× một lần cut đơn lẻ → drawdown tệ nhất là **nhiều cut chồng nhau**.

---

## 4. Sizing: rủi ro thật lệch xa mục tiêu khai báo

`CalculateLotFromRisk()` (`QuantEdge_EA_Template.mq4`) sàn lot ở:

```cpp
rawLot = MathMax(rawLot, MathMax(minLot, InpMinLotSize));   // = 0.03
```

Sàn này áp dụng **bất kể** `InpDefaultRiskPct = 0.5%`. XAUUSD với SL ≈ ATR ≈ $8:

| Vốn | Lot 0.03 → lỗ 1 SL | Rủi ro thật | So mục tiêu 0.5% |
|-----|--------------------|-------------|------------------|
| **$1,000** | $24 | **2.40%** | **4.8×** |
| $2,000 | $24 | 1.20% | 2.4× |
| $5,000 | $24 | 0.48% | ✓ |

**$1,000 là mức vốn live dự kiến.** Ở đó một leg đã ăn 2.4% vốn, và một basket 3–4 legs ăn
7–10% trước khi DD cap kịp cắt. Con số `InpDefaultRiskPct = 0.5` không phản ánh thực tế.

### Compounding bị chặn

`InpMaxLotSize = 0.1` giới hạn lot tối đa. Khi vốn tăng 1,000 → 9,342, rủi ro mỗi lệnh **giảm**
từ 8% xuống 0.86%. Đường equity gần như **tuyến tính**, không phải lãi kép.

→ Con số +834% **không lặp lại được** nếu bắt đầu ở mức vốn khác. Nó là artifact của việc
over-risk giai đoạn đầu.

---

## 5. Verdict: CHƯA đạt chuẩn live

| Tiêu chí quant | Ngưỡng | Thực tế | Đạt |
|----------------|--------|---------|-----|
| Recovery factor | ≥ 3.0 | 1.70 | ❌ |
| MaxDD | ≤ 20% | 38.12% | ❌ |
| Out-of-sample validation | Bắt buộc | Chưa có | ❌ |
| Spread thực tế | Bắt buộc | Fixed 50 pt | ❌ |
| Rủi ro thật/lệnh @ $1k | ≤ 1% | ~2.4% | ❌ |
| Mẫu độc lập | ≥ 100 | ~300–800 (chưa đo) | ⏳ |
| Profit Factor | ≥ 1.5 | 1.51 | ✓ |
| Edge thống kê | t > 2 | 7.98 (per-leg) | ✓* |

\* chỉ đúng nếu mẫu độc lập — chính là thứ chưa kiểm chứng.

**Không phải "chiến lược tệ"** — edge per-leg là thật về mặt số học. Vấn đề là chưa biết con số
đó có sống sót qua spread thật, qua out-of-sample, và qua việc quy về basket hay không.

---

## 6. Config: những gì đang tắt

Chỉ **3 gate** đang chạy: Gate 2 (confidence ≥ 50), Gate 3 (staleness), Gate 11 (EV > 0).

| Input | Giá trị | Hệ quả |
|-------|---------|--------|
| `InpMinRecLevel` | 6 = `REC_ANY` | Gate 1 tắt → nhận cả `AVOID` / `COUNTER_TREND` |
| `InpUseGate5Spread` | 0 | Spread không kiểm tra |
| `InpUseGate10PriceLoc` | 0 | Không chặn entry trôi xa |
| `InpUseGate12FillRR` | 0 | Không sàn R:R tại giá fill |
| `InpUseSessionFilter` | 0 | Trade cả Asian + LateNY (`PROJECT_STATUS.md` §2 ghi là tệ nhất) |
| `InpUseDailyLossCap` | 0 | Không circuit breaker ngày |
| `InpUseWeeklyDDStop` | 0 | Không stop tuần |
| `InpUseMonthlyDDStop` | 0 | Không stop tháng |
| `InpUseDCABackstopSL` | 0 | EA offline = basket không giới hạn |
| `InpNegDCABEClose` | 0 | Van xả breakeven của DCA tắt |

**Không bật hàng loạt ngay.** Mỗi cái đổi phân phối kết quả; phải đo từng bước (§7).

---

## 7. Quy trình kiểm chứng

Xếp theo **sức phủ định giảm dần** — bước đầu có thể phủ định toàn bộ mà không cần chạy lại
test nào.

### V1 — Đo lại ở mức basket ⬅ **làm trước tiên**

Logger CSV bị tắt trong tester (`SignalLogger.mqh:334`), nên nguồn duy nhất là MT4 report.

```bash
# MT4: chuột phải tab Results → Save as Report → report.htm
python tools/basket_analyzer.py report.htm --initial-deposit 1000

# nếu basket bị tách/gộp sai, chỉnh cửa sổ gom (giây)
python tools/basket_analyzer.py report.htm --close-window 120 --dump baskets.csv
```

Script gom leg → basket theo thời điểm đóng, vì `CloseEntireBasket()` đóng mọi leg trong một
vòng lặp nên chúng cách nhau vài giây.

**Tiêu chí dừng**: nếu **WR basket-level < 62.8%** → không có edge thật, mọi bước sau vô nghĩa.

### V2 — Chạy lại với spread thực tế

Hiện dùng `Current (50)`. Chạy lại với spread 80–100 point để mô phỏng rollover/news.

TP1 ≈ ATR×0.8 ≈ $6.4; spread $0.80 = **12.5% target**. Đây là chi phí trực tiếp ăn vào edge.

**Tiêu chí dừng**: nếu **PF < 1.2** → edge chủ yếu là ảo do spread rẻ.

### V3 — Phân tách out-of-sample

| Giai đoạn | Khoảng |
|-----------|--------|
| In-sample | 2/2024 – 8/2024 |
| Out-of-sample | 9/2024 – 12/2024 |

Chốt tham số trên IS, chạy OOS **một lần duy nhất, không chỉnh**.

**Tiêu chí dừng**: nếu **PF OOS < 1.2** hoặc DD OOS tệ hơn IS đáng kể → overfit.

> `InpUseWalkForward` + `InpOOSPercent = 20` (`Config.mqh:264`) là cơ chế nội bộ của indicator,
> **không thay thế** việc tách IS/OOS ở cấp backtest.

### V4 — Đo DD thật với circuit breaker bật

```
InpUseDailyLossCap   = 1,  InpMaxDailyLossPct  = 2
InpUseWeeklyDDStop   = 1,  InpMaxWeeklyDDPct   = 10
InpUseMonthlyDDStop  = 1,  InpMaxMonthlyDDPct  = 15
```

**Mục tiêu**: MaxDD ≤ 20%, Recovery factor ≥ 3.0. Chấp nhận net profit giảm.

### V5 — Kiểm chứng sizing ở vốn $1,000

Đọc lot thực tế từ report, so với lot mà 0.5% risk đáng ra phải cho. Hai hướng xử lý:

| Hướng | Thay đổi | Kết quả |
|-------|----------|---------|
| (a) | `InpMinLotSize` 0.03 → 0.01 | 1 leg = 0.8% vốn |
| (b) | Giữ 0.03, hạ `InpNegDCAMaxDDPct` | Thừa nhận rủi ro thật ~2.4%, siết trần basket |

---

## 8. V1 — Kết quả basket-level (2026-09-25)

> **Dữ liệu**: `logs/StrategyTester.htm`, gom bằng `tools/basket_analyzer.py --close-window 60`

### 8.1 Số liệu basket

| Chỉ số | Per-leg (MT4) | Per-basket | Thay đổi |
|--------|:------------:|:----------:|----------|
| Số mẫu | 1,586 | **403** | −74.6% |
| Win rate | 71.82% | **97.02%** | +25.2 pp |
| Avg win | $21.69 | **$53.00** | |
| Avg loss | −$36.61 | **−$1,031.72** | ×28 |
| Payoff b | 0.592 | **0.051** | −91.3% |
| Breakeven WR | 62.80% | **95.11%** | +32.3 pp |
| **Edge margin** | +9.02 pp | **+1.91 pp** | **−79%** |
| Profit Factor | 1.51 | **1.67** | |
| Recovery factor | 1.70 | **1.73** | |
| MaxDD | 38.12% | **37.45%** | |

**Edge co lại 79%** khi quy về đơn vị giao dịch đúng. Biên 1.91 pp trên 403 mẫu cho z = 2.26
(p ≈ 0.012 một phía) — kỹ thuật có ý nghĩa thống kê, nhưng **rất mỏng**.

95% CI cho WR basket: **95.36% – 98.68%**. Cận dưới (95.36%) chỉ hơn breakeven (95.11%) có
**0.25 pp** — thực chất không khác gì ranh giới may rủi.

### 8.2 Profile: short-gamma cực đoan

```
1 loss = 19.5 × avg win
→ cần 19–20 basket thắng liên tiếp chỉ để gỡ 1 basket thua
```

| Đặc điểm | Giá trị |
|-----------|---------|
| Avg legs/basket | 3.94 |
| Basket 1 leg (pure signal) | 18 (4.5%) |
| Basket ≥ 8 legs (full DCA) | 24 (6.0%) |
| Multi-leg losing (DD-cap cut) | **12 basket = 100% gross loss** |
| Avg DD-cap cut cost | **−$1,031.72** |
| Worst single basket | **−$1,938.08** (193.8% vốn) |
| Max consecutive losing baskets | 2 |

Chiến lược **không bao giờ thua nhỏ**: mọi basket thua đều là DD-cap cut ≥ 5 legs. Hoặc hồi
về TP1 (thắng), hoặc chạm DD-cap 15% (thua lớn). Không có trung gian.

### 8.3 Phân bổ theo tháng

| Tháng | Baskets | WR | Net P/L | DD-cap cuts |
|------:|--------:|-----:|--------:|:-----------:|
| 2024-02 | 18 | 88.9% | +$16 | 2 (nhỏ) |
| 2024-03 | 37 | 100% | +$1,398 | 0 |
| 2024-04 | 46 | 97.8% | +$2,477 | 1 |
| 2024-05 | 44 | 97.7% | +$1,412 | 1 |
| 2024-06 | 35 | 97.1% | +$347 | 1 |
| **2024-07** | 35 | **94.3%** | **−$602** | **2** |
| 2024-08 | 38 | 100% | +$2,412 | 0 |
| 2024-09 | 42 | 100% | +$1,700 | 0 |
| 2024-10 | 49 | 100% | +$2,705 | 0 |
| **2024-11** | 29 | **89.7%** | **−$3,106** | **3** |
| **2024-12** | 30 | **93.3%** | **−$415** | **2** |

4 tháng lợi nhuận tốt + 0 cut (Mar, Aug, Sep, Oct) → tạo cushion.
3 tháng lỗ ròng (Jul, Nov, Dec) → chỉ cần 2–3 cut/tháng là xoá lợi nhuận.

**Nov 2024**: 3 cut trong 9 ngày (6–14/11), tổng −$5,061 — xoá sạch lợi nhuận 2 tháng trước.

### 8.4 Stress test

| Kịch bản | Net profit còn lại |
|-----------|-------------------|
| Baseline (12 cuts) | +$8,343 |
| +3 cuts | +$5,248 |
| +6 cuts | +$2,153 |
| +9 cuts | −$942 ← **âm** |

Chỉ cần **9 DD-cap cuts thêm** (tổng 21 thay vì 12) trong 11 tháng là toàn bộ lợi nhuận biến
mất. Tương đương thêm ~1 cut/tháng.

### 8.5 Verdict V1

| Tiêu chí | Kết quả | Đánh giá |
|-----------|---------|----------|
| Edge basket-level dương? | ✓ (+1.91 pp) | **Có, nhưng mỏng** |
| Thống kê có ý nghĩa? | z = 2.26, p = 0.012 | **Biên giới** — cận dưới CI gần sát breakeven |
| Đủ mạnh để sống sót spread thật? | ❌ **KHÔNG** | **V2 trả lời: z tụt dưới 1.96** |

---

## 8b. V2 — Spread thực tế (spread 100 point, 2026-09-25)

> **Dữ liệu**: `logs/StrategyTester1.htm`, cùng config, chỉ đổi spread 50 → 100
>
> ⚠️ **Đính chính (§10.1)**: symbol trong tester là vàng **3 chữ số** (Point = $0.001), nên
> "spread 100" chỉ là **$0.10** — vẫn hẹp hơn spread live thật ($0.20–0.50). V2 **chưa** test
> spread thực tế. Mục §10 có bảng stress đúng ở $0.40.

### 8b.1 So sánh basket-level

| Chỉ số | Spread 50 | Spread 100 | Thay đổi |
|--------|:---------:|:----------:|----------|
| Baskets | 403 | 401 | −2 |
| WR basket | 97.02% | 97.51% | +0.49 pp |
| Breakeven WR | 95.11% | **96.10%** | +0.99 pp |
| **Edge margin** | +1.91 pp | **+1.41 pp** | **−26%** |
| Profit Factor | 1.67 | 1.59 | −4.8% |
| Net profit | $8,343 | $7,376 | −11.6% |
| Avg win | $53.00 | $51.02 | −3.7% |
| Avg loss | −$1,031.72 | **−$1,257.26** | **−21.9%** |
| MaxDD | 37.45% | **42.70%** | +5.25 pp |
| **Recovery factor** | 1.73 | **1.19** | **−31%** |
| DD-cap cuts | 12 | 10 | −2 |
| Worst basket | −$1,938 | **−$2,184** | −12.7% |

### 8b.2 Ý nghĩa thống kê — MẤT

```
n = 401   WR = 97.51%   BE = 96.10%   SE = 0.78%
z = 1.81   (p = 0.035 one-tailed)
95% CI: 95.98% – 99.04%
```

**z = 1.81 < 1.96**: edge **không có ý nghĩa thống kê ở 95%**.

Cận dưới CI (95.98%) **thấp hơn** breakeven WR (96.10%) → khoảng tin cậy **chồng lên**
breakeven. Không thể phân biệt edge thật và may rủi.

### 8b.3 Spread ảnh hưởng thế nào

- **Avg win giảm 3.7%**: mỗi basket thắng mất ~$2 do spread rộng hơn.
- **Avg loss tăng 21.9%**: DCA legs mở ở giá xấu hơn → basket thua nặng hơn $226/cut.
- **Recovery factor sụp 31%**: từ 1.73 → 1.19 — chỉ cần 1 cut thêm là PF xuống dưới 1.0.
- **Edge margin co 26%**: 1.91 pp → 1.41 pp, z tụt dưới ngưỡng ý nghĩa.

Spread không giết WR (vẫn 97.5%) — nó giết **payoff ratio**: mỗi lần thua đắt hơn nhiều
trong khi mỗi lần thắng gần như không đổi. Đây đúng là kiểu tổn thất mà short-gamma chịu
nặng nhất.

### 8b.4 Verdict V2

| Tiêu chí V2 | Ngưỡng | Thực tế | Đạt |
|-------------|--------|---------|-----|
| PF basket với spread thực tế | ≥ 1.3 | 1.59 | ✓ |
| Edge có ý nghĩa thống kê | z ≥ 1.96 | **z = 1.81** | **❌** |
| Recovery factor | ≥ 3.0 | **1.19** | **❌** |
| MaxDD | ≤ 20% | **42.70%** | **❌** |

**PF 1.59 vượt ngưỡng 1.3** — spread không giết chiến lược về mặt cơ học. Nhưng khi yêu cầu
**bằng chứng thống kê** rằng edge không phải may rủi, z = 1.81 không đủ. Recovery factor 1.19
nghĩa là lợi nhuận cả năm chỉ bằng 1.19 lần drawdown tệ nhất.

**Kết luận V2**: Edge **có thể tồn tại** nhưng **không chứng minh được** với dữ liệu hiện có.

---

**Khuyến nghị dừng quy trình V3–V5 như đang viết**: backtest hiện tại chạy một EA **khác** với
EA live (§10.1), nên kiểm chứng thêm trên nó là vô nghĩa. Xem §10.

---

## 9. Tiêu chí PASS (cập nhật sau V1+V2)

| # | Tiêu chí | Ngưỡng | Kết quả | Đạt |
|---|----------|--------|---------|-----|
| 1 | Edge basket-level dương | > 0 pp | +1.41 pp (spread 100) | ✓ |
| 2 | Edge có ý nghĩa thống kê | z ≥ 1.96 | **z = 1.81** | **❌** |
| 3 | PF basket spread thực tế | ≥ 1.3 | 1.59 | ✓ |
| 4 | PF out-of-sample | ≥ 1.2 | Chưa test (đã khuyến nghị dừng) | ⏸ |
| 5 | MaxDD | ≤ 20% | **42.70%** | **❌** |
| 6 | Recovery factor | ≥ 3.0 | **1.19** | **❌** |
| 7 | Rủi ro thật/lệnh @ $1k | ≤ 1% | **~2.4%** | **❌** |

**4 trong 7 tiêu chí FAIL** (2 nghiêm trọng: recovery factor và MaxDD). Chiến lược **chưa đạt
chuẩn live** ở dạng hiện tại.

---

## 10. Giải pháp quant — phân tích nhân quả trên từng leg (2026-09-25)

> **Dữ liệu**: cả hai report, parse **cả dòng open lẫn close** của 1,586 / 1,568 leg (giá vào,
> hướng, thời điểm). Tái tạo được bằng `tools/dca_counterfactual.py`.
>
> **Phương pháp**: counterfactual **chính xác** trên chính các basket đã chạy. Basket chưa bao
> giờ chạm leg thứ k+1 giữ nguyên kết quả thật; basket đã chạm thì đóng tại giá fill thật của
> leg k+1 — một mức giá thị trường **đã thực sự giao dịch**. Không nội suy, không giả định đường
> giá. Giới hạn: không mô hình được tín hiệu mới mà EA lẽ ra đã vào trong lúc basket cũ bị đóng
> sớm (thiên lệch nhỏ, cùng chiều bảo thủ).

### 10.1 Ba phát hiện thay đổi toàn bộ kết luận

#### F1 — Backtest chạy một EA KHÁC với EA live

Tester dùng vàng **3 chữ số** (giá `2033.505`, đo được Point = $0.001 từ chênh giá mở giữa hai
report). Live của mày là **2 chữ số** (`4268.91`, Point = $0.01). Mọi input tính bằng point lệch
**10 lần**:

| Input | Tester (3 digit) | Live (2 digit) | Hệ quả |
|-------|:---------------:|:--------------:|--------|
| Spread "100" | **$0.10** | $1.00 | V2 chưa hề test spread thật |
| `InpDCAMinSpacingPts = 1500` | **$1.50** | **$15.00** | Khoảng cách DCA khác 10× |
| `InpMaxSpreadPoints = 40` | $0.04 | $0.40 | Gate 5 khác 10× |
| `InpSlippage = 10` | $0.01 | $0.10 | |

Bằng chứng trực tiếp: khoảng cách tối thiểu giữa các leg DCA trong tester là **$1.50** (682/682
leg PosDCA cách nhau < $15). Trên screenshot live của mày, 3 leg cách nhau **$15.22 / $15.49** —
đúng $15.

Hệ quả nặng nhất: **PosDCA gần như chết trên live**. Nó chỉ thêm leg khi giá chưa qua nửa đường
tới TP1 (`InpPosDCAHalfClosePct = 50`); nửa đường TP1 trên M15 ≈ $3–8, nhỏ hơn $15 spacing. Trong
tester, 682 leg PosDCA đóng góp **$2,556 = 31% lợi nhuận**. Live sẽ không có phần này.

→ **Mọi con số backtest tới giờ (+834%, PF 1.51, V1, V2) là của một chiến lược live không chạy.**

#### F2 — Lợi nhuận là artifact của sizing, không phải edge

Hai sự thật đo được từ report:

| | Giá trị |
|---|---|
| Lot mọi leg | **0.03 trên 97% leg** — kẹt ở `InpMinLotSize` bất kể balance $1k hay $13k |
| Mỗi DD-cap cut | **đúng 15.0–15.2% balance lúc đó** (11/12 lần) |

Lời tính theo **$ cố định** (lot kẹt), lỗ tính theo **% balance** (DD cap). Nên breakeven WR
trôi theo balance:

| Balance | 1 lần cut | Avg win | 1 cut = ? win | Breakeven WR |
|--------:|----------:|--------:|--------------:|-------------:|
| $1,000 | $150 | $37 | 4.1 | **80.2%** |
| $2,000 | $300 | $37 | 8.1 | 89.0% |
| $7,500 | $1,125 | $53 | 21.3 | 95.5% |
| $11,000 | $1,650 | $55 | 29.8 | **96.8%** |

Chiến lược **tự làm yếu mình khi thắng**: balance càng lớn, cùng một tín hiệu cần WR càng cao.
Đây chính là lý do H2/2024 (balance $7k–13k) gãy trong khi H1 (balance $1k–7k) đẹp.

Kiểm chứng ngược: giữ nguyên mọi thứ, chỉ đổi DD cap từ 15% balance sang **$ cố định** (đúng
cái live $1,000 sẽ trải qua):

| DD cap | Cuts | PF | Net | MaxDD | H1 t | H2 t |
|--------|-----:|---:|----:|------:|-----:|-----:|
| 15% balance (thực tế backtest) | 10 | 1.59 | $7,376 | $6,211 | 3.59 | **−0.01** |
| $150 cố định | 47 | **2.26** | $8,864 | **$584** | 4.96 | **2.87** |
| $600 cố định | 10 | 2.90 | $12,656 | $1,360 | 5.87 | 2.12 |

(spread $0.10, `logs/StrategyTester1.htm`)

→ Tín hiệu **không hề chết ở H2**. Cái chết ở H2 là cơ chế sizing.

Thêm một điều từ code: `InpDefaultRiskPct = 0.5` **không** quyết định lot. EA dùng `riskPct`
do indicator gửi qua `BUF_REC_RISK` (half-Kelly, `Normalize.mqh:788-922`), và chỉ fallback về
0.5 khi indicator gửi 0 (`QuantEdge_EA_Template.mq4:2587-2589`). Nên con số rủi ro khai báo
trong preset không phản ánh rủi ro thật theo cả hai chiều.

#### F3 — Negative DCA sâu phá hủy edge ở mọi độ sâu k ≥ 2

Counterfactual chính xác, **PosDCA tắt** (= live thực tế theo F1), spread tester $0.10 và
spread gần thật $0.40. Mô phỏng Monte Carlo: block bootstrap (khối 10 basket, 3,000 đường),
rủi ro 1% vốn / 1R.

| NegDCA tối đa | Spread | WR | PF | t | H1 PF / t | H2 PF / t | DD p95 | P(DD>20%) |
|:---:|:---:|---:|---:|---:|:---:|:---:|---:|---:|
| 0 | $0.40 | 46.1% | 1.03 | 0.27 | 0.97 / −0.16 | 1.10 / 0.57 | 47.2% | 78.9% |
| **1** | $0.10 | 74.6% | 1.39 | **2.57** | 1.53 / 2.42 | 1.26 / 1.22 | 16.3% | 1.1% |
| **1** | **$0.40** | 72.6% | **1.27** | **1.85** | 1.39 / 1.85 | **1.16 / 0.78** | **18.7%** | **3.0%** |
| 2 | $0.40 | 82.5% | 1.12 | 0.73 | 1.41 / 1.63 | **0.87 / −0.61** | 19.6% | 3.7% |
| 3 | $0.40 | 87.3% | 1.27 | 1.34 | 1.56 / 1.82 | 1.02 / 0.09 | 12.2% | 0.0% |
| 5 | $0.40 | 92.0% | 1.62 | 2.18 | **2.48 / 3.19** | **1.11 / 0.31** | 8.2% | 0.0% |
| **10 (preset)** | $0.40 | 89.3% | 1.47 | 1.26 | 3.04 / 3.21 | **0.92 / −0.17** | — | — |

Đọc bảng:

- **k = 1 là cấu hình duy nhất dương ở cả hai nửa năm, ở cả hai mức spread.** Không phải cao
  nhất, nhưng là cái duy nhất ổn định.
- **k ≥ 5 là dấu hiệu overfit kinh điển**: H1 PF 2.5–4.4 (t > 3) rồi H2 PF ≈ 1.0 (t ≈ 0). Chuỗi
  DCA sâu "thắng" H1 vì H1 là thị trường tăng trơn — không phải vì nó có edge.
- **k = 0 không có edge** (PF 1.03). Tín hiệu một mình không đủ; leg DCA-1 **là một phần của
  edge**, không phải phụ kiện.
- Preset hiện tại (k=10) ở spread gần thật: **H2 PF 0.92 — thua**.

#### F4 — Tín hiệu SELL không có edge

Cùng k=1, spread $0.40:

| | n | PF | t | H1 PF | H2 PF |
|---|---:|---:|---:|---:|---:|
| BUY | 316 | 1.37 | 1.91 | 1.78 | 1.15 |
| SELL | 85 | **0.83** | −0.57 | 0.95 | **0.31** |

Năm 2024 vàng tăng ~27%. 79% basket là BUY. Thứ gọi là "edge" phần lớn là **beta của xu hướng
tăng**, và nó sẽ đảo dấu khi thị trường đổi pha. SELL chỉ có 85 mẫu nên chưa đủ để kết luận
"tín hiệu SELL hỏng" — nhưng đủ để kết luận **không có bằng chứng SELL có edge**.

### 10.2 Chẩn đoán gốc

Ba cơ chế cộng hưởng, không phải một:

1. **Lot sàn cố định × DD cap theo %** → payoff tự co lại khi balance tăng (F2).
2. **NegDCA 10 leg** → biến 1 tín hiệu thua thành −15% vốn thay vì −1R; và chính các leg sâu
   là nơi overfit vào H1 (F3).
3. **Dữ liệu tester 3-digit** → tất cả cảm nhận về hiệu năng từ trước tới giờ đến từ một EA có
   PosDCA dày đặc mà live không có (F1).

Tín hiệu indicator **có** edge dương nhỏ ở phía BUY (t ≈ 1.9–2.6 với DCA-1), nhưng **chưa đủ
mạnh để chứng minh** độc lập với xu hướng 2024.

### 10.3 Giải pháp — theo thứ tự làm

#### S0 — Làm cho backtest giống live (BẮT BUỘC TRƯỚC MỌI THỨ)

Không thay đổi chiến lược nào có nghĩa khi backtest chạy EA khác. Hai cách, chọn một:

✅ **Đã sửa trong code** — build `2026-09-25.2-ptscale`. Mọi input tính bằng point
(`InpDCAMinSpacingPts`, `InpMaxSpreadPoints`, `InpSlippage`, `InpNegDCABEOffsetPip`, sàn TP tối
thiểu 100 pt) giờ được hiểu là **point của vàng 2 chữ số** và tự nhân 10 khi symbol có 3 hoặc 5
chữ số. Live 2 chữ số **không đổi hành vi**; tester 3 chữ số giờ chạy đúng như live. OnInit in ra
`Digits=... scaled x...` để kiểm tra.

Hệ quả cần nhớ:

- **Report cũ không lặp lại được với build mới.** Chạy lại preset cũ trên build mới thì DCA cách
  $15 (như live), không phải $1.50. Đó chính là mục đích: W1 đo EA đang chạy live.
- **EA mà §10 đã phân tích** (DCA-1 ở ~50% SL, median $3.18 từ entry) cần
  `InpDCAMinSpacingPts = 150` (= $1.50 trên mọi feed). W2 dùng giá trị này.
- Spread tester: nhập **400** nếu symbol 3 chữ số, **40** nếu 2 chữ số (đều = $0.40).

Preset sẵn: `presets/W1_baseline.set`, `presets/W2_S1B.set` — sinh bằng
`tools/make_presets.py` từ đúng khối Parameters của report, nên W1 và W2 chỉ khác nhau đúng
các input của S0–S3.


#### S1 — Cấu trúc rủi ro: 1 tín hiệu = tối đa 2 leg, lỗ hữu hạn và biết trước

Chung cho mọi phương án:

| Input | Hiện tại | Đề xuất | Lý do (đo được) |
|-------|:-------:|:------:|-----------------|
| `InpNegDCAMaxOrders` | 10 | **1** | Duy nhất dương ở cả H1/H2, cả 2 spread (F3) |
| `InpUsePositiveDCA` | true | **false** | Đằng nào cũng chết trên live (F1); bật lại chỉ sau khi đo được trên dữ liệu 2-digit |
| `InpUseDCABackstopSL` | false | **true** | Có SL phía broker khi EA offline |
| `InpDCAMinSpacingPts` | 1500 | **150** (từ build ptscale: = $1.50 trên mọi feed) | Toàn bộ phân tích dựa trên spacing $1.50 của tester. Với 1500 = $15, DCA-1 chỉ vào khi giá đi ngược $15, trong khi tester vào ở median **$3.18** (≈ 50% SL). Basket live trong screenshot (DCA cách $15 / $30) là một chiến lược **chưa từng được backtest**. |

Lối thoát khi thua — hai phương án, **cùng spread $0.40**, lot sàn 0.01/leg:

| | S1-A: đóng basket tại mức DCA-2 | S1-B: giữ 2 leg tới DD cap |
|---|---|---|
| Cần sửa code? | **Có** (~20 dòng: khi giá chạm mức DCA-2 lẽ ra được đặt, đóng basket) | **Không** — `InpNegDCAMaxDDPct = 6` (≈ giá đi ngược $30 từ avg của 2 leg 0.01 @ $1k) |
| Độ chính xác ước lượng | **Chính xác** (đóng tại giá fill thật) | **Khoảng**: 64/401 basket (16%) không xác định được lối thoát |
| PF toàn kỳ | 1.27 | 1.46 – 1.70 |
| H1 / H2 PF | 1.39 / **1.16** | 1.89–2.13 / **1.13–1.36** |
| t toàn kỳ | 1.85 | 2.1 – 2.9 |
| Lỗ tệ nhất 1 basket | −$38 | −$61 |
| MC @ $1,000: DD p95 / P(DD>20%) | 29% / **22%** | 20–27% / **5–18%** |
| MC @ $2,000: DD p95 / P(DD>20%) | 16% / 1% | 11–15% / ≤1% |

(Monte Carlo: block bootstrap, khối 10 basket, 2,500 đường, 11 tháng, `logs/quant/`)

**Khuyến nghị: chạy S1-B ở W2 trước** — không cần sửa code, và chính backtest thật sẽ xoá khoảng
bất định 16% mà counterfactual không xoá được. Chỉ làm S1-A nếu W2 cho thấy S1-B có lỗ đuôi lớn.

> Tại sao không phải k=5 dù PF cao hơn? Vì toàn bộ lợi thế của k=5 nằm ở H1 (t=3.19) và biến
> mất ở H2 (t=0.31). Chọn k=5 là chọn theo in-sample.

#### S2 — Sizing và vốn

**Sự thật khó nghe: $1,000 là quá ít cho chiến lược này, kể cả ở lot sàn 0.01.** Monte Carlo
cho P(DD > 20%) trong 11 tháng là **5–22%** ở $1,000, và **≤ 1%** ở $2,000. Không có tham số
nào sửa được điều này — lot 0.01 là sàn của broker.

| Input | Hiện tại | Đề xuất |
|-------|:-------:|:------:|
| `InpMinLotSize` | 0.03 | **0.01** |
| `InpMaxLotSize` | 0.1 | **0.5** (để lot scale theo balance khi vốn lớn lên) |

Lựa chọn thực tế cho vốn $1,000:
1. Chấp nhận P(DD > 20%) cỡ 5–20% và coi $1,000 là tiền học phí, hoặc
2. Chạy cent account / demo tới khi đủ $2,000, hoặc
3. Chờ W3–W4 xác nhận edge rồi mới nạp thêm.

> Nguyên tắc: **lời và lỗ phải cùng đơn vị**. Nếu DD cap tính theo % balance thì lot cũng phải
> scale theo balance. Ở $1k–$1.6k lot sẽ kẹt ở 0.01, nên `InpNegDCAMaxDDPct` cần hạ dần khi
> balance tăng trong vùng đó — nếu không, F2 lặp lại.

#### S3 — Circuit breaker (chặn chuỗi, không phải chặn lệnh)

```
InpUseDailyLossCap  = true,  InpMaxDailyLossPct  = 8
InpUseWeeklyDDStop  = true,  InpMaxWeeklyDDPct   = 12
InpUseMonthlyDDStop = true,  InpMaxMonthlyDDPct  = 18
```

Các ngưỡng này **chỉ chặn tín hiệu mới** (`IsDailyLossCapHit()` và cùng loại), không đóng lệnh
đang mở. Đặt ở mức ≈ 1.3 / 2 / 3 lần một cú stop S1-B (6%) để chúng chỉ cắt **chuỗi** như cụm
Nov 2024 (3 cut trong 9 ngày), không cắt một lần thua đơn lẻ. Đặt chặt hơn một basket thì một
lần thua sẽ khoá EA cả ngày/tuần — mất tín hiệu tốt ngay sau đó.

#### S4 — Hướng tín hiệu: KIỂM CHỨNG, chưa hành động

F4 cho thấy SELL không có bằng chứng edge. **Không tắt SELL dựa trên 1 năm vàng tăng** — đó là
overfit ngược. Việc cần làm: chạy S0+S1 trên **2023** (vàng đi ngang/biến động) và **2025**. Nếu
SELL vẫn PF < 1 ở cả hai → tắt SELL hoặc chỉ cho SELL khi H4/D1 downtrend.

#### S5 — Những thứ tao KHÔNG khuyến nghị (đã kiểm chứng là sai hoặc chưa đủ bằng chứng)

| Ý tưởng | Vì sao không |
|---------|--------------|
| Bật `InpNegDCABEClose` (§10.1 cũ) | Không mô phỏng được chính xác từ report (thiếu đường giá sau leg cuối). Và với k=1 thì BEClose gần như không còn tác dụng. Tao rút lại khuyến nghị cũ. |
| Basket stop theo R (3R–15R) với DCA sâu | Kết quả phụ thuộc hoàn toàn vào đoạn giá không quan sát được sau leg cuối. Cận lạc quan PF 2.1–2.6, cận bi quan PF 0.55–1.9 — không kết luận được. |
| Stop chặt ($5–10 từ avg) | Cận lạc quan PF 1.9–2.3 nhưng cận bi quan PF 0.43–1.05. Ảo giác do report không ghi giá sau leg cuối. |
| Session filter | Không bucket giờ nào ổn định cả H1 lẫn H2 (n ≈ 60–136/bucket, t < 1.5). Bật lên là curve-fit. |
| Tối ưu TP:SL, ATR mult, spacing | Tối ưu trên dữ liệu 3-digit = tối ưu một EA không tồn tại. Chỉ làm sau S0. |

### 10.4 Kế hoạch kiểm chứng mới (thay V3–V5)

| Bước | Chạy gì | PASS nếu |
|------|---------|----------|
| **W1** | `presets/W1_baseline.set`, spread $0.40, 2024, build ptscale | — (baseline của EA đang chạy live) |
| **W2** | `presets/W2_S1B.set` (S0 + S1-B + S2 + S3), cùng điều kiện W1 | PF ≥ 1.2 **ở cả** Feb–Jul **và** Aug–Dec |
| **W3** | W2 trên **2023** (không chỉnh gì) | PF ≥ 1.15, không nửa năm nào PF < 1.0 |
| **W4** | W2 trên **2025** (không chỉnh gì) | Như W3 |
| **W5** | Demo live 4–8 tuần, $1,000, lot 0.01 | Slippage/spread thực ≤ giả định; PF trong khoảng của W2–W4 |

Mỗi report chạy qua:

```bash
python tools/basket_analyzer.py report.htm --initial-deposit 1000
python tools/dca_counterfactual.py report.htm --split <giữa kỳ> --spreads 0,0.3
```

**Tiêu chí dừng**: nếu W2 fail → tín hiệu indicator không có edge đủ dùng ở M15, vấn đề nằm ở
indicator chứ không ở EA. Khi đó quay lại tầng tín hiệu (`counter_review_anti_overfit.md`), không
chỉnh thêm tham số EA.

### 10.5 Kỳ vọng trung thực

Monte Carlo trên 2024 cho median +50% đến +120%/11 tháng ở $1,000. **Không tin con số đó.**
2024 là năm vàng tăng 27%, 79% basket là BUY, và SELL không có edge (F4) — con số này chứa
nhiều beta xu hướng. Nếu W2–W4 pass, kỳ vọng hợp lý là **PF 1.2–1.4, lợi nhuận 15–35%/năm, MaxDD
10–20%**. Đó là một chiến lược bình thường, sống được. +834% với MaxDD 38% không phải một phiên
bản tốt hơn của nó — đó là cùng một tín hiệu cộng với rủi ro ẩn và một tester chạy sai digits.

---

## 11. Backtest #3 — default mới trên build ptscale (2026-09-29)

> **Dữ liệu**: `logs/StrategyTester3.htm` — XAUUSD M15, 2/2024–12/2024, MT4, Every tick, $1,000,
> **spread 50 point trên vàng 3 chữ số = $0.05**.
> **EA**: default trong code sau V12.3 + V12.4, không phải preset W1/W2. Build ptscale đã được xác
> nhận: 110/110 khoảng cách DCA âm ≥ $15.00 (median $15.05), đúng như live.
>
> ```bash
> python tools/basket_analyzer.py logs/StrategyTester3.htm --initial-deposit 1000
> python tools/dca_counterfactual.py logs/StrategyTester3.htm --split 2024-08-01 --spreads 0,0.35
> python logs/quant/exits.py logs/StrategyTester3.htm          # lối thoát, độ sâu, BUY/SELL
> cd logs/quant && python cap_bounds.py ../StrategyTester3.htm  # stop cố định $, cận lạc quan/bi quan
> ```

### 11.1 Run này là gì, và không phải là gì

Run này **không phải W1** (§10.4). Nó khác W1 ở ba điểm đổi kết quả:

| | W1 (kế hoạch) | Run #3 |
|---|---|---|
| Spread | $0.40 | **$0.05** (rẻ hơn live 4–10 lần) |
| Gates | preset cũ: G1 tắt; G5, G10, G12, session tắt | default V12.3: G1=CAUTION; G5, G10, G12, session 7–20h bật |
| `InpNegDCABEClose` | false | **true** |

Run này cho biết default hiện tại chạy thế nào trên một EA giống live, **ở spread lý tưởng**. Nó
không trả lời W1 hay W2.

### 11.2 Kết quả, so với baseline cùng spread 50

| Chỉ số (basket-level) | Baseline #0 (3-digit, DCA $1.50) | Run #3 (ptscale, DCA $15) |
|---|:---:|:---:|
| Net profit | +$8,343 | **+$1,781** |
| Baskets / legs | 403 / 1,586 | 372 / 482 |
| Legs TB / basket | 3.94 | **1.30** |
| Leg PosDCA | 682 | **0** |
| WR / breakeven WR | 97.02% / 95.11% | 98.12% / 96.88% |
| Edge margin | +1.91 pp | +1.23 pp |
| z | 2.26 | **1.75** |
| Profit factor | 1.67 | 1.68 |
| MaxDD | 37.45% | **25.6%** |
| Recovery factor | 1.73 | 1.93 |
| Basket tệ nhất | −$1,938 | **−$542** |
| DD-cap cut | 12 | 6 (+1 đóng do hết kỳ test) |

Rủi ro đuôi giảm mạnh: basket tệ nhất chỉ còn khoảng 1/3.6 so với trước, MaxDD giảm 12 pp. **Edge thì không mạnh lên**: z vẫn dưới 1.96.
Lợi nhuận giảm 4.7 lần vì PosDCA không chạy (G1) và lot kẹt ở 0.03.

### 11.3 Phát hiện

#### G1 — Dự đoán của §10 đúng: PosDCA 0 leg, DCA âm sâu nhất 4 leg

0/482 leg là PosDCA. Với `InpPosDCAATRMult = 2.5`, leg DCA+1 cần giá đi thuận 2.5×ATR, nhưng
`ManagePositiveDCA()` dừng khi giá qua 50% đường tới TP1 (≈ 0.4×ATR). Nên nó **không thể kích
hoạt**, bất kể spacing là bao nhiêu (đã ghi ở mục "Ngoài phạm vi" của V12.3).

DCA âm: 110 leg trên 79 basket, sâu nhất 4 leg. Spacing $15 cộng với mức giá đi ngược tối đa ~$66
khiến `InpNegDCAMaxOrders = 10` chỉ còn là con số trên giấy.

#### G2 — Toàn bộ lỗ đến từ basket có từ 2 leg DCA âm trở lên

| Leg DCA âm | Baskets | Thắng / thua | Net |
|:---:|---:|:---:|---:|
| 0 | 293 | 293 / 0 | +$4,134 |
| 1 | 57 | 57 / 0 | +$201 |
| 2 | 16 | 14 / 2 | −$327 |
| 3 | 3 | 1 / 2 | −$714 |
| 4 | 3 | 0 / 3 | −$1,514 |

Không được đọc hàng "0 leg" thành "không DCA thì luôn thắng". Khi bật DCA, lệnh gốc gửi đi **không
có SL** (`sendSL = 0`), nên mọi lệnh đi sai đều biến thành basket DCA. Nhóm 0 leg vì thế chỉ gồm
những lệnh đã thắng sẵn. Muốn biết DCA thêm hay bớt bao nhiêu thì phải dùng counterfactual (G3).

#### G3 — Ở spacing $15, cấu hình ổn định nhất là 2 leg rồi cắt

Counterfactual chính xác: basket đóng tại giá fill thật của leg k+1. "+$0.35" nghĩa là tổng spread
$0.40.

| k | Spread | PF | Net | MaxDD | RF | Tệ nhất | H1 PF | H2 PF (t) |
|:---:|:---:|---:|---:|---:|---:|---:|---:|:---:|
| 0 | +$0.35 | 1.04 | 132 | 544 | 0.24 | −58 | 0.93 | 1.16 (0.75) |
| 1 | +$0.35 | 1.28 | 864 | 508 | 1.70 | −143 | 1.54 | 1.10 (0.33) |
| **2** | $0.05 | 2.17 | 2,377 | 455 | 5.23 | −274 | 4.09 | 1.48 (1.07) |
| **2** | **+$0.35** | **1.91** | 1,880 | 464 | 4.05 | −277 | 3.54 | **1.32 (0.72)** |
| 3 | +$0.35 | 1.57 | 1,432 | 828 | 1.73 | −459 | 3.34 | 1.03 (0.07) |
| 4 = thực tế | +$0.35 | 1.48 | 1,275 | 938 | 1.36 | −547 | 3.34 | **0.96 (−0.09)** |

- ~~Default hiện tại ở spread gần thật cho **H2 PF 0.96, tức là thua**.~~ **Đính chính (§11.6)**:
  chạy thật ở $0.40 cho H2 PF **1.25**. Hàng +$0.35 của bảng này giả định chuỗi lệnh không đổi khi
  tăng spread — sai, chỉ 61% basket trùng giữa hai run.
- k=2 là cấu hình **duy nhất** có H2 PF ≥ 1.2 ở spread $0.40.
- Điều này không mâu thuẫn với §10 (khi đó chọn k=1). §10 chạy spacing $1.50, DCA-1 vào ở ~$3 từ entry.
  Độ sâu k **không chuyển được** giữa các spacing khác nhau. Thứ chuyển được là **mức lỗ tối đa của
  một basket**: k=2 ở spacing $15 nghĩa là cắt khi giá đi ngược ~$45, lỗ ~$270 ở lot 0.03.

Kiểm tra chéo bằng stop cố định theo $ (`cap_bounds.py`). Cận bi quan giả định giá đi thêm một bậc
$15 sau leg bất lợi cuối cùng quan sát được (đi xa hơn thì leg kế tiếp đã phải fill). Spread $0.40:

| Stop basket | Cuts | PF lạc quan (H2) | PF bi quan (H2) |
|---|:---:|:---:|:---:|
| $150 cố định | 7–21 | 3.30 (2.24) | 1.19 (1.02) |
| $200 cố định | 7–21 | 2.55 (1.75) | **0.90 (0.78)** |
| **$300 cố định** | 5–6 | **2.06 (1.49)** | **1.78 (1.22)** |
| $400 cố định | 4–5 | 1.70 (1.15) | 1.45 (0.93) |
| 15% balance (thực tế) | 6 | 1.48 (0.96) | — |

Mức $150–200 không đáng tin: nó rơi vào khoảng giữa hai lần fill DCA, nơi report không ghi lại
đường giá, nên cận bi quan sụp. Mức $300 đứng vững ở cả hai cận, và trùng với k=2 (~$270). **Hai
phương pháp độc lập cùng chỉ về một chỗ: cắt basket quanh mức leg DCA-3.**

> **In-sample.** k=2 và $300 đều được chọn trên chính dữ liệu 2024. H2 t = 0.72 chưa có ý nghĩa
> thống kê. Đây là ứng viên để chạy W3/W4, chưa phải kết luận.

#### G4 — F2 lặp lại: lỗ tính theo % balance, lời tính theo lot cố định

Lot 0.03 trên **482/482** leg. Mỗi lần cắt đúng 15.0–15.4% balance tại thời điểm đó:

| Ngày cắt | Balance | Lỗ | Tương đương số basket thắng TB ($12.09) |
|---|---:|---:|---:|
| 2024-04-22 | $1,783 | −$268 | 22 |
| 2024-05-22 | $2,008 | −$303 | 25 |
| 2024-08-05 | $2,718 | −$418 | 35 |
| 2024-10-31 | $3,604 | −$542 | 45 |
| 2024-11-08 | $3,154 | −$474 | 39 |
| 2024-12-12 | $3,322 | −$498 | 41 |

Cả sáu lần là cùng một kiểu thua: BUY, 3–5 leg, giá đi ngược $45–66. Cái giá tăng gấp đôi chỉ vì
balance lớn lên. Đây là lý do cùng một tín hiệu cho H1 PF 3.86 nhưng H2 PF 1.07.

**Hệ quả cho S2**: phải đổi đơn vị của cap **trước** khi hạ lot về 0.01. Nếu không, hạ lot chia lời
cho 3 trong khi lỗ vẫn là 15% balance, tức là tệ hơn hiện tại.

#### G5 — SELL "thắng 100%" là nhờ ôm lệnh, không phải nhờ tín hiệu

| | n | PF thực tế | k=0 PF (t) | k=0 H1 / H2 |
|---|---:|:---:|:---:|:---:|
| BUY | 287 | 1.35 (cả 6 lần cắt) | 1.52 (2.70) | 1.44 / 1.59 |
| SELL | 85 | ∞ (0 thua) | **0.53 (−2.40)** | 0.61 / 0.33 |

(k=0 = tín hiệu không DCA, cắt ở giá fill DCA-1 ≈ $15 bất lợi; spread $0.05)

SELL không có lệnh thua nào chỉ vì mọi SELL đi sai đều được DCA/BE cứu trong một năm vàng tăng. Bản
thân tín hiệu SELL âm và có ý nghĩa thống kê (t = −2.4), bằng chứng mạnh hơn F4. BUY có edge riêng ở
cả hai nửa năm với stop $15, nhưng 2024 tăng 27%, nên phần này vẫn có thể là beta. S4 giữ nguyên:
quyết định ở W3 (2023).

#### G6 — Một nửa số basket bị đóng bởi tín hiệu ngược mà chính EA không vào lệnh

| Lối thoát | Baskets | Net | TB |
|---|---:|---:|---:|
| TP1 | 102 | +$2,637 | +$25.85 |
| Tín hiệu ngược (`OppositeCloseMinProfit`) | **191** | +$1,497 | +$7.84 |
| BE close DCA âm | 72 | +$278 | +$3.87 |
| DD cap 15% | 6 | −$2,502 | −$417 |
| Hết kỳ test (`close at stop`) | 1 | −$130 | — |

- `[OPPCLOSE-FIX]` hoạt động đúng: 0/191 lần đóng bị lỗ (thấp nhất +$0.18).
- 170/191 lần (89%) **không có lệnh ngược nào mở theo sau** trong 45 phút. Tín hiệu ngược đóng basket
  (bước này chạy trước mọi gate trong `TryExecuteSignal`), rồi chính nó bị gate từ chối. Có 34 lần
  đóng rơi vào ngoài giờ 7–20h, trong khi basket chỉ mở trong 7–19h. Nói cách khác, một tín hiệu
  không đủ chất lượng để vào lệnh vẫn đủ quyền đóng lệnh.
- Mỗi lần đóng như vậy chỉ ăn được median 18% quãng đường tới TP1.
- Report không đủ để kết luận việc này tốt hay xấu: không biết basket đó lẽ ra sẽ về TP hay đi vào
  DCA sâu. Cần A/B.

### 11.4 Đối chiếu tiêu chí PASS (§9)

| # | Tiêu chí | Ngưỡng | Run #3 | Đạt |
|---|---|---|---|:---:|
| 1 | Edge basket-level | > 0 | +1.23 pp | ✓ |
| 2 | Ý nghĩa thống kê | z ≥ 1.96 | 1.75 | ❌ |
| 3 | PF basket ở spread thật | ≥ 1.3 | ~1.48 (ước lượng +$0.35) | ✓* |
| 4 | PF cả hai nửa năm (W2) | ≥ 1.2 | H2 1.07 @ $0.05 (~~0.96 @ $0.40~~ → đo thật 1.25, §11.6) | ❌ |
| 5 | MaxDD | ≤ 20% | 25.6% | ❌ |
| 6 | Recovery factor | ≥ 3.0 | 1.93 | ❌ |
| 7 | Rủi ro thật @ $1k | ≤ 1% | lot 0.03 cố định; basket tệ nhất = 54% vốn đầu | ❌ |

\* ước lượng bậc một, chưa chạy thật.

Tốt hơn baseline cũ ở **mọi chỉ số rủi ro**, nhưng vẫn **chưa đạt chuẩn live**. Điểm gãy vẫn là H2.

### 11.5 Việc tiếp theo

Phiên này không sửa code.

1. **Chạy lại run #3 với spread 400** (= $0.40 trên symbol 3 chữ số), chỉ đổi đúng một input. Mục đích là xác
   nhận con số H2 PF 0.96 đang là ước lượng.
2. **W2 vẫn chạy như §10.4.** Run #3 không thay thế được nó.
3. **Ứng viên mới, W2b** (từ G3), giữ spacing $15 như live: `InpNegDCAMaxOrders = 2`,
   `InpUsePositiveDCA = false`, cộng thêm một lối thoát thua cố định. Lối thoát này **cần code**,
   vì `InpNegDCAMaxDDPct` chỉ tính theo % balance.
4. **Các thay đổi code cần user quyết (chưa làm)**:
   - (a) Cap lỗ basket theo đơn vị gắn với lot, ví dụ $/lot hoặc bội số R của leg gốc, thay cho
     hoặc bổ sung `InpNegDCAMaxDDPct`. Sửa G4 và là điều kiện để S2 không làm tệ hơn.
   - (b) S1-A: đóng basket khi giá chạm mức leg k+1 (§10.3).
   - (c) Input chỉ cho tín hiệu ngược đóng basket khi nó pass gate, để A/B G6.
5. **W3/W4 (2023, 2025) vẫn là bằng chứng quyết định.** Mọi con số ở §11.3 là in-sample 2024.

### 11.6 Run #4 — cùng run #3, spread 400 (= $0.40) (2026-09-29)

> **Dữ liệu**: `logs/StrategyTester4.htm`. Khối Parameters **giống hệt** run #3 (đã diff: 0 khác
> biệt). Chỉ đổi spread 50 → 400.

#### Kết quả

| Chỉ số (basket) | Run #3 ($0.05) | **Run #4 ($0.40)** | Ước lượng §11.3 cho $0.40 |
|---|:---:|:---:|:---:|
| Baskets | 372 | 339 | 372 |
| Net | +$1,781 | **+$1,105** | +$1,275 |
| PF | 1.68 | **1.35** | 1.48 |
| H1 PF / H2 PF | 3.86 / 1.07 | **1.48 / 1.25** | 3.34 / **0.96** |
| DD-cap cut | 6 | **12** | 6 |
| Lỗ TB 1 cut | −$417 | −$252 | — |
| Basket tệ nhất | −$542 | −$378 | −$547 |
| MaxDD (closed / MT4) | 25.6% | 22.6% / 25.5%, relative **29.1%** | — |
| Recovery factor | 1.93 | 1.97 | 1.36 |
| z (basket WR vs breakeven) | 1.75 | **1.22** | — |

#### Ước lượng của §11.3 sai — vì sao

Counterfactual giữ nguyên chuỗi basket và chỉ trừ thêm spread. Trong thực tế, chuỗi lệnh **đổi
hẳn**:

- Chỉ **226/372** basket của run #3 có basket cùng hướng, lệch không quá 30 phút ở run #4.
- 80/146 basket chỉ có ở run #3 bị mất vì lúc đó run #4 **đang bận** một basket khác (Gate 4 chặn).
  Chỉ 24 basket mất vì Gate 5 chặn TP1 < $5 (mình dự đoán 27).
- Spread đổi giá fill và thời điểm đóng, từ đó đổi basket nào đang mở khi tín hiệu tiếp theo tới.
  Ví dụ 2024-11-08 BUY: run #3 đóng ở TP (+$26.50) trong 9 giờ, run #4 cùng tín hiệu nhưng fill cao
  hơn $0.35, không kịp chạm TP, rồi bị kéo vào DD cap **−$340**. Ngược lại 2024-09-04 SELL: run #3
  gồng 4 leg rồi thoát ở BE (+$6.57), run #4 chạm cap trước **−$298**.

Hệ quả: **bảng k/spread trong §11.3 không đáng tin ở mức một nửa năm.** Độ nhiễu do path dependence
lớn hơn chính hiệu ứng spread cần đo. Những kết luận về thứ tự tương đối (k=2 tốt hơn k≥3) vẫn cần
được kiểm lại bằng run thật, không phải bằng replay.

#### Những gì run #4 xác nhận, và những gì nó sửa

| Phát hiện §11.3 | Sau run #4 |
|---|---|
| G1 PosDCA 0 leg | ✓ Vẫn 0/445 |
| G2 lỗ chỉ đến từ basket ≥ 2 DCA âm | ✓ 13/13 lần thua là basket 3–4 leg |
| G3 k=2 / ~$300 stop | **Yếu đi.** Counterfactual trên run #4: k=2 PF 1.49 (H1 1.48 / H2 1.50). $300 cố định PF 1.44, cận lạc quan và bi quan **trùng nhau** vì mọi cut đều ≥ $174. Vẫn hơn default, nhưng khoảng cách hẹp lại |
| G4 cap 15% × lot cố định | ✓ **Rõ hơn**: 12 cut, mỗi cut 15.0–15.2% balance, lỗ tăng dần −$174 → −$378. Tính P/L theo % balance: H1 PF 1.58, H2 PF 1.38, khoảng cách hai nửa gần như biến mất |
| G5 SELL không có edge | **Yếu đi.** k=0: SELL PF 0.74, t −0.99 (run #3: 0.53, t −2.40). Hướng vẫn âm nhưng không còn có ý nghĩa thống kê |
| G6 đóng do tín hiệu ngược | ✓ 169/339, 0 lần lỗ |

#### Đọc run #4

- H1 PF sụp từ 3.86 xuống 1.48. **H1 đẹp của run #3 phần lớn nhờ spread rẻ**: 7 cut rơi vào H1 thay vì 2.
  H2 cải thiện từ 1.07 lên 1.25 là do chuỗi lệnh đổi (hai nửa năm đều có 6–7 cut), không phải do
  spread cao giúp gì.
- Hai nửa năm giờ đã **cân bằng** (1.48 / 1.25). Đây là tín hiệu tốt hơn run #3, nơi H1 và H2 lệch
  nhau 3.6 lần.
- Nhưng **edge rất mỏng**: H2 lời gộp $2,236 / lỗ gộp $1,785. Thêm **1 cut $300 là PF 1.07, thêm 2 cut là
  PF 0.94**. Hai kết quả §11.3 bị lật khi chỉ đổi spread cho thấy 1–2 cut chênh lệch hoàn toàn nằm
  trong độ nhiễu.
- z = 1.22, t = 1.13 → **không phân biệt được với may rủi.**

#### Đối chiếu tiêu chí PASS (§9), run #4

| # | Tiêu chí | Ngưỡng | Run #4 | Đạt |
|---|---|---|---|:---:|
| 1 | Edge basket-level | > 0 | +1.27 pp | ✓ |
| 2 | Ý nghĩa thống kê | z ≥ 1.96 | **1.22** | ❌ |
| 3 | PF basket ở spread thật | ≥ 1.3 | 1.35 | ✓ |
| 4 | PF cả hai nửa năm | ≥ 1.2 | 1.48 / 1.25 | ✓ (sát ngưỡng, 1 cut là mất) |
| 5 | MaxDD | ≤ 20% | 25.5% (relative 29.1%) | ❌ |
| 6 | Recovery factor | ≥ 3.0 | 1.97 | ❌ |
| 7 | Rủi ro thật @ $1k | ≤ 1% | cut đầu tiên = 15% balance | ❌ |

**4/7 FAIL.** Tiêu chí 4 lần đầu tiên đạt, nhưng mong manh.

#### Cập nhật §11.5

1. ~~Chạy lại với spread 400~~ ✅ xong.
2. **Mọi run tiếp theo dùng spread 400.** Run #4 là baseline mới, thay run #3.
3. Ưu tiên đổi thứ tự: **(a) cap theo đơn vị gắn với lot** lên đầu. G4 là phát hiện duy nhất mạnh lên
   qua cả hai run, và hai nửa năm cân bằng lại khi tính theo % balance.
   ✅ **Đã code** (build `2026-09-29.2-rcap12`): `InpBasketMaxLossR`, mặc định **12** (user chọn). 13 lần thua của
   run #4 tương đương khoảng 3.5–24R (ước lượng SL từ tỉ lệ TP1/SL median 1.27 của report 3 chữ số cũ).
   Replay cho N = 10/12/15R ra PF bi quan 1.01/1.12/1.14, lạc quan 1.61/1.51/1.42, baseline 1.35.
   Khoảng này bao trùm baseline, nên chỉ backtest thật mới quyết được.
4. k=2 / S1-A vẫn là ứng viên, nhưng **chỉ quyết bằng run thật**. Không dùng counterfactual để chọn
   tham số nữa, vì §11.6 cho thấy sai số của nó ở mức 1 nửa năm lớn hơn khác biệt cần đo.

### 11.7 Run #5 — run #4 + `InpBasketMaxLossR = 12` (build `rcap12`, 2026-09-29)

> **Dữ liệu**: `logs/StrategyTester5.htm`. Diff Parameters với run #4: **chỉ** `InpBasketMaxLossR=12`.
> Spread 400 ($0.40).

#### Đây là một A/B sạch

Khác với run #3 → #4, lần này path dependence gần như bằng 0: **339/339** basket của run #4 có mặt ở
run #5 với cùng thời điểm mở và cùng hướng. Chỉ **4** basket đổi kết quả, cộng thêm 2 basket mới
(+$21, mở được vì một basket bị cắt sớm hơn). Mọi khác biệt dưới đây là tác động của cap R, không
phải nhiễu.

| Basket | Run #4 (cap 15%) | Run #5 (cap 12R) | Chênh |
|---|---|---|---:|
| 2024-10-23 BUY | 3 leg, BE close **+$4.50** | cắt 12R **−$210.33** | **−$214.83** |
| 2024-10-31 BUY | 4 leg, −$378.22 | 3 leg, −$197.04 | +$181.18 |
| 2024-11-08 BUY | 4 leg, −$340.20 | 3 leg, −$275.16 | +$65.04 |
| 2024-12-12 BUY | 4 leg, −$375.94 | 4 leg, −$359.62 | +$16.32 |
| 2 basket mới | — | +$21.21 | +$21.21 |
| **Tổng** | | | **+$68.93** |

Cap R cắt đúng 3 basket thua (tiết kiệm $263), nhưng cũng cắt **1 basket lẽ ra thắng** (−$215). Đó
chính là rủi ro mà cận bi quan của replay đã cảnh báo. 1R ngầm định của 4 lần cắt là $16–30, tức SL
$5.5–10, khớp với ước lượng SL median $7.7 ở §11.6.

#### Kết quả

| Chỉ số | Run #4 | **Run #5** |
|---|:---:|:---:|
| Net | +$1,105 | **+$1,174** |
| PF (basket) | 1.35 | **1.38** |
| H1 PF / H2 PF | 1.48 / 1.25 | **1.48 / 1.30** |
| Maximal DD (MT4, theo $) | $634 (25.5%) | **$464 (18.2%)** |
| DD sâu nhất theo % (relative, MT4) | 29.05% | **29.05%** (không đổi) |
| DD closed-balance theo % | 25.0% | 25.0% (không đổi) |
| Recovery factor (basket / equity) | 1.97 / 1.74 | **3.09 / 2.53** |
| z | 1.22 | 1.36 |

#### Cap R chỉ có tác dụng ở nửa sau — vì sao

Cả 4 basket đổi kết quả đều từ tháng 10 trở đi. H1 giống hệt run #4. Lý do: EA dùng cap **chặt hơn**,
và ở balance $1.2–1.4k (tháng 3–6), 15% balance = $174–218, **nhỏ hơn** 12R ($200–360 ở lot 0.03).
Cap R chỉ thắng khi balance đủ lớn để 15% vượt qua 12R, tức khoảng $2k trở lên.

Hệ quả:
- **Drawdown sâu nhất theo % không đổi**: 25–29% vào tháng 4/2024 (3 lần cắt 15% trong 12 ngày ở
  balance $1.2–1.35k). Cap R không chạm tới đoạn này.
- Cap R làm đúng việc được thiết kế cho nó: chặn lỗ basket **tăng theo balance** (G4). Basket
  tệ nhất ở H2 giảm từ −$378 xuống −$360, và từ tháng 10 không còn lần cắt nào vượt 12R.
- Đổi lại, tổng chênh lệch +$69 chỉ đến từ 4 basket, trong đó có 1 basket thắng bị cắt nhầm. **Chưa đủ để
  kết luận 12R là mức tối ưu**, chỉ biết rằng nó không làm tệ đi.

#### Đối chiếu tiêu chí PASS (§9)

| # | Tiêu chí | Ngưỡng | Run #4 | Run #5 | Đạt |
|---|---|---|---|---|:---:|
| 1 | Edge basket-level | > 0 | +1.27 pp | +1.47 pp | ✓ |
| 2 | Ý nghĩa thống kê | z ≥ 1.96 | 1.22 | 1.36 | ❌ |
| 3 | PF ở spread thật | ≥ 1.3 | 1.35 | 1.38 | ✓ |
| 4 | PF cả hai nửa năm | ≥ 1.2 | 1.48 / 1.25 | 1.48 / 1.30 | ✓ |
| 5 | MaxDD | ≤ 20% | 25.5% | 18.2% theo $, nhưng **29% theo %** (tháng 4) | ❌ |
| 6 | Recovery factor | ≥ 3.0 | 1.97 | 3.09 basket / 2.53 equity | ⚠️ |
| 7 | Rủi ro thật @ $1k | ≤ 1% | 1R ≈ 2–3% vốn | như cũ; 12R = 20–36% vốn | ❌ |

Tốt lên ở tiêu chí 6, còn 5 và 7 vẫn trượt vì **cùng một nguyên nhân**: lot 0.03 trên tài khoản $1k.
1R ≈ $17–30 đã là 2–3% vốn, nên cap nào (15% hay 12R) cũng tương đương 6–12R ở đầu kỳ.

#### Bước tiếp theo: run #6 = run #5 + `InpMinLotSize = 0.01`

G4 từng đặt điều kiện: **đổi đơn vị cap trước, rồi mới hạ lot**. Cap R đã có, nên giờ hạ lot là
an toàn:

- Lot gốc lúc đó do risk quyết định (`CalculateLotFromRisk`), không bị sàn 0.03 kéo lên nữa. Ở $1–2k và
  SL $5–10 thì phần lớn ra 0.01–0.02. Leg DCA = lot gốc × `NegDCALotRatio`, rồi áp sàn 0.01. Cấu trúc
  basket theo giá không đổi.
- 12R ở lot 0.01 = $65–120, nhỏ hơn 15% balance → **cap R sẽ là cap chạy thật trong cả năm**,
  kể cả tháng 4. Cap 15% lùi về làm lưới an toàn.
- 1R ≈ $6–10 = 0.6–1% vốn $1k → đạt tiêu chí 7 về mặt cấu trúc.
- P/L tính bằng $ sẽ nhỏ đi khoảng 3 lần. So với run #5 phải đọc theo % và theo R, không theo $.
- Đây là thay đổi một input, không cần code. Nó đổi đúng một hành vi theo giá: **cap R chạy cả năm
  thay vì chỉ từ tháng 10**. Những basket tháng 3–6 trước đây bị cắt ở 15% sẽ được gồng tới 12R, nên
  có thể hồi về BE hoặc lỗ sâu hơn trong đơn vị R. Run #6 đo đúng điều này.

### 11.8 Run #6 — không phải run đã đề xuất (2026-09-30)

> **Dữ liệu**: `logs/StrategyTester6.htm`. So với §11.7 đề xuất (run #5 + lot 0.01), run này khác
> ở **3 chỗ**:
>
> | Input | Đề xuất | Run #6 |
> |---|---|---|
> | Spread | 400 ($0.40) | **Current (50) = $0.05** |
> | `InpMinLotSize` | 0.01 | **0.03** (487/487 leg ở 0.03) |
> | `InpMinRecLevel` | 2 (CAUTION) | **6 (`REC_ANY`)** |
>
> Nên run #6 **không** trả lời câu hỏi lot 0.01. Diff Parameters với run #3 thì chỉ khác
> `InpMinRecLevel` (2 → 6) và `InpBasketMaxLossR` (tắt → 12), cùng spread $0.05. Mình đọc run #6 như
> một so sánh với run #3.

#### `InpMinRecLevel = 6` gần như không đổi gì trong tester

370/372 basket của run #3 xuất hiện lại ở run #6 với cùng thời điểm mở và cùng hướng. 13 basket mới
đều mở trong lúc run #3 **đang bận** một basket khác (Gate 4). Không có basket nào đến từ tín hiệu mà
Gate 1 trước đây chặn. Điều này khớp với `[RECLEVEL-COLDSTART-FIX]`: trong tester không có dữ liệu
outcome, nên floor của Gate 1 đã tự hạ xuống WAIT. Chuyển sang `ANY` chỉ còn mở thêm AVOID/
COUNTER_TREND, và loại tín hiệu này không xuất hiện ở đây.

→ Khác biệt giữa run #3 và run #6 **gần như hoàn toàn là tác động của cap 12R** (2 basket khác lệch
$0.03–0.27 do giá fill thay đổi theo tick).

#### Kết quả, so với run #3 (cùng spread $0.05)

| Chỉ số | Run #3 | **Run #6** |
|---|:---:|:---:|
| Baskets | 372 | 383 |
| Net | +$1,781 | **+$2,145** |
| PF (basket) | 1.68 | **1.91** |
| H1 PF / H2 PF | 3.86 / 1.07 | **4.03 / 1.25** |
| MaxDD closed-balance | 25.6% | **16.1%** |
| MT4 Maximal / Relative DD | $995 (27.6%) / 27.6% | **$624 (18.2%) / 18.4%** |
| Recovery factor (basket) | 1.93 | **3.88** |
| Basket tệ nhất | −$542 | −$463 |
| z / t | 1.75 / 1.61 | **2.78 / 2.37** |

#### 9 basket đổi kết quả do cap 12R

| Basket | Run #3 | Run #6 | Chênh |
|---|---|---|---:|
| 2024-10-31 BUY | 5 leg, −$541.50 | 3 leg, −$223.68 | **+$317.82** |
| 2024-12-12 BUY | 5 leg, −$498.42 | 4 leg, −$329.42 | **+$169.00** |
| 2024-05-22 BUY | 4 leg, −$302.73 | 3 leg, −$242.67 | +$60.06 |
| 2024-11-08 BUY | 5 leg, −$473.64 | 5 leg, −$463.14 | +$10.50 |
| 2024-07-03 SELL | 3 leg, **+$6.03** | 2 leg, **−$49.41** | −$55.44 |
| 2024-08-23 SELL | 3 leg, **+$4.68** | 2 leg, **−$104.82** | −$109.50 |
| 2024-10-01 SELL | 3 leg, **+$4.56** | 2 leg, **−$126.42** | −$130.98 |
| 2 basket lệch fill | | | +$0.30 |
| 13 mới − 2 mất | | | +$102.01 |
| **Tổng** | | | **+$363.85** |

Phát hiện mới: **cap R cắt nhầm 3 basket SELL có SL rất hẹp.** 1R ngầm định của chúng chỉ $4–11,
tức SL $1.4–3.5 và TP1 $2.8–5.3. 12R của lệnh SL $1.4 là giá đi ngược khoảng $16, **ngang một bậc DCA
$15**. Nên basket bị cắt ngay khi leg DCA-1 vừa vào, trong khi ở run #3 chúng gồng 3 leg và hồi về
BE. Cả 3 basket đều là SELL từ tín hiệu TP1 dưới $5.3.

Ở spread $0.40 (run #5), Gate 5 tương đối (`InpMaxSpreadPctOfTP1 = 8`) chặn TP1 dưới $5, nên 2/3 tín hiệu này
không bao giờ được vào lệnh. Đây là lý do run #5 chỉ có 1 lần cắt nhầm: cap R và Gate 5 đang ngầm
bảo vệ nhau.

**Rủi ro cấu trúc**: cap tính theo R không có sàn. Khi SL cấu trúc hẹp hơn khoảng spacing DCA / 12,
cap R sẽ cắt **trước hoặc ngay khi** DCA kịp vào. Cách sửa (chưa làm):
`cap = max(N × R, sàn theo giá)`, ví dụ sàn = 2 bậc DCA. Làm vậy thì những lệnh SL hẹp được gồng như
các lệnh khác.

#### Đọc run #6

- **Cap 12R giúp rõ ràng ở spread rẻ**: +$364, recovery factor 1.93 → 3.88, H2 PF 1.07 → 1.25, và
  lần đầu tiên **z = 2.78 > 1.96**.
- **Nhưng đây là spread $0.05.** Run #4 cho thấy chuyển sang $0.40 thì PF 1.68 → 1.35 và H1 sụp
  3.86 → 1.48. Áp một cách thô chi phí +$0.35/oz lên run #6 (giữ nguyên chuỗi lệnh, cách mà §11.6
  đã cho thấy là không đáng tin) ra PF ~1.68, H2 ~1.11. Không dùng con số này để kết luận. Nó chỉ nhắc
  rằng z = 2.78 ở $0.05 **không** chuyển thẳng sang $0.40.
- Cap 15% chạy **2 lần** (2024-04-22 ở balance $1,784 và 2024-08-05 ở $2,780), cap R chạy 7 lần, 1 basket
  đóng do hết kỳ test. *(Đính chính 2026-09-30: bản trước ghi "1 lần, 9/10 là cap R" vì lệnh lọc output
  dừng sớm.)*

#### Việc tiếp theo

1. **Run #6 đúng như dự định** (gọi là run #6b): run #5 + `InpMinLotSize = 0.01`, spread **400**,
   `InpMinRecLevel = 2`. Khuyến nghị: load từ report #5 để tránh lệch input.
2. Cân nhắc code **sàn giá cho cap R** (ở trên). Chỉ quan trọng khi Gate 5 không chặn tín hiệu TP1
   hẹp, tức là khi spread rẻ, hoặc trên live khi spread thấp.

### 11.9 Run #7 — run #6 + `InpMinLotSize = 0.01` (2026-09-30)

> **Dữ liệu**: `logs/StrategyTester7.htm`. Diff Parameters với run #5: **chỉ** `InpMinLotSize` 0.03 → 0.01.
> Vì run #5 và run #6 có cùng input, run #7 so thẳng được với **run #6**. Hai run khác nhau đúng lot
> sàn, cùng spread 50 = **$0.05**, không phải $0.40 như đề xuất ở §11.8. Report không có `InpResearchLog`,
> nên đây là build trước commit `3820a9e`.

#### Lot 0.01 có đúng như dự tính không

- 487/488 leg ở 0.01 (1 leg 0.02). Lot tính theo risk chỉ vượt sàn 0.01 một lần.
- **383/383** basket trùng thời điểm mở và hướng với run #6. 381 basket cho đúng P/L của run #6 chia 3.
  Như vậy lot nhỏ không làm đổi tín hiệu hay lệnh.
- Mọi lần cắt giờ đều là **cap 12R** (đúng dự tính của §11.7). Không còn lần nào cắt ở 15% balance.

#### 2 basket đổi kết quả

| Basket | Run #6 (lot 0.03) | Run #7 (lot 0.01) | Nguyên nhân |
|---|---|---|---|
| 2024-04-22 BUY | 3 leg, cắt ở 15% = −$267.63 (tương đương −$89 ở 0.01) | 4 leg, cắt 12R = **−$140.72** | 12R ($141) **rộng hơn** 15% cũ theo đơn vị lot → gồng thêm leg DCA-4, lỗ sâu hơn |
| 2024-08-05 BUY | 4 leg, cắt ở 15% = −$417.78 (tương đương −$139 ở 0.01) | 4 leg, đóng BE **+$2.14** | 12R ($166) rộng hơn mức lỗ thật lúc đó ($90) → không bị cắt, giá hồi về BE |

Cả hai là cùng một cơ chế: cap 12R ở lot 0.01 **rộng hơn** cap 15% cũ. Một lần có lợi (+$141), một lần
có hại (−$52). Tổng +$89, trong đó gần như toàn bộ đến từ **một** basket, ngày 5/8/2024, khi giá hồi về
sau khi basket đã âm $90.

#### Kết quả

| Chỉ số | Run #6 (lot 0.03) | Run #6 ÷ 3 | **Run #7 (lot 0.01)** |
|---|:---:|:---:|:---:|
| Net | +$2,145 | +$715 | **+$789** |
| PF (basket) | 1.91 | 1.91 | **2.11** |
| H1 PF / H2 PF | 4.03 / 1.25 | — | **2.95 / 1.64** |
| MaxDD closed-balance | 16.1% | — | **9.8%** |
| Recovery factor | 3.88 | — | **4.28** |
| Basket tệ nhất | −$463 (46% vốn) | — | **−$154 (15.4% vốn)** |
| z / t | 2.78 / 2.37 | — | **3.19 / 2.72** |
| Lần thua / breakeven | 10 / — | — | **9 / 18.9** |

Nếu basket 5/8 bị cắt như run #6: net +$647, PF 1.76, **H2 1.25**, z 2.32. Vậy phần H2 tăng lên 1.64
là do **một** basket.

#### Phần xu hướng

- Beta: EA trung bình chỉ còn net long **0.19 oz**, lời từ việc vàng tăng khoảng **$110 / $789** (14%, so với ~40% ở
  run #5). Đây là cải thiện thật: lot nhỏ hơn nên beta nhỏ hơn.
- Toàn bộ EA, trung hòa xu hướng: +$2.06/basket, CI 90% **+0.94 … +3.04**, P(≤ 0) ≈ 0%. Block bootstrap:
  P(mean ≤ 0) = 0.2%.
- **Chỉ tín hiệu (k=0)**, trung hòa xu hướng: **−$0.53**/basket (P ≤ 0 = 82%). SELL không DCA: PF 0.55.
  **Vẫn âm, như 4 run trước.**
- Mua 0.01 lot rồi giữ cả kỳ: +$572.

#### Đọc run #7

1. **Lot 0.01 cải thiện rủi ro rõ rệt**: basket tệ nhất từ 46% xuống 15% vốn, MaxDD từ 16% xuống 10%. Đây
   là điều đã dự tính ở §11.7 và giờ đo được thật.
2. **z = 3.19 vẫn đo ở spread $0.05.** Run #4 cho thấy chuyển sang $0.40 thì PF 1.68 → 1.35. Chi phí
   spread theo lot không đổi, nên cú sụt dự kiến tương tự. Mình **không** ước lượng con số này bằng
   replay (§11.6).
3. **Edge của EA đến từ cấu trúc thoát lệnh, không phải từ tín hiệu.** Tín hiệu thuần vẫn âm ở cả 5 run.
   Phần dương chỉ xuất hiện khi có DCA + BE, tức là nhờ việc giá vàng M15 hay quay đầu trong khoảng $15–45.
   Điều đó *có thể* là một đặc tính thật của vàng M15 (mean reversion ngắn hạn), nhưng mới chỉ thấy
   trên **một năm có trend tăng**. Muốn kiểm chứng phải chạy thêm 2023 và 2025.
4. 3 basket SELL có SL hẹp (7/3, 8/23, 10/1) vẫn bị cap R cắt nhầm: −$110, bằng 15% lợi nhuận. Sàn giá cho
   cap R (§11.8) vẫn là một ứng viên.

#### Việc tiếp theo

1. **Run #8 = run #7, chỉ đổi spread thành 400.** Đây là phép thử quyết định cho cấu hình hiện tại.
2. Nếu run #8 vẫn dương: chạy **cùng input đó trên 2023 và 2025** (W3/W4, §10.4). Không chỉnh thêm gì.
3. Bật `InpResearchLog = true` trong các run đó (build `3820a9e`) để có dữ liệu cho `tools/signal_edge.py`.

### 11.10 Run #8 và #9 — chạy lại run #6 và #5 (2026-09-30)

> `logs/StrategyTester8.htm`, `logs/StrategyTester9.htm`. Build sắp xếp gate (`02848f3`): có nhóm
> `inp_grp_g1…` nhưng chưa có `InpResearchLog`, nên không có research log.

- **Run #8**: Parameters giống hệt run #6 (lot 0.03, spread $0.05, `InpMinRecLevel=6`). 974/974 dòng lệnh
  trùng từng dòng.
- **Run #9**: giống run #5, chỉ khác `InpMinRecLevel` 2 → 6 (lot 0.03, spread $0.40). 890/890 dòng lệnh trùng.
- Thông tin mới duy nhất: **trong tester, `InpMinRecLevel` = 2 hay 6 không đổi bất kỳ lệnh nào**. Lần này
  biến được tách riêng (run #3 → #6 còn lẫn cap 12R). Gate 1 không kiểm chứng được bằng backtest; trên
  live, indicator có lịch sử outcome nên gate có thể chặn khác.
- Run cần có (lot 0.01 + spread $0.40, research log bật) **vẫn chưa có**. Lấy cấu hình run #9, đổi
  `InpMinLotSize = 0.01`, compile bản mới nhất, bật `InpResearchLog`, lưu thành `StrategyTester10.htm`.
  Sau khi compile phải kiểm tra lại tab Inputs: giữa run #7 và run #8, lot đã bị trả về 0.03.
  *(Preset `R10_lot001_spread040.set` ghi ở đây đã được thay bằng `presets/R10_cent10k.set`, xem §13.)*

---

## 13. Đánh giá theo quant + kế hoạch live cent $10k (2026-09-30)

> Mục tiêu của user: chạy live trên tài khoản cent 10,000 USC (≈ $100 tiền thật). Các chỉ số tính trên
> run #5 (default, lot 0.03, $0.40), #6 (lot 0.03, $0.05), #7 (lot 0.01, $0.05). Chưa có run nào gộp
> lot 0.01 + $0.40.

### 13.1 Bảng điểm quant

| Chỉ số | Run #5 | Run #6 | Run #7 | Chuẩn |
|---|:---:|:---:|:---:|:---:|
| Sharpe (ngày, năm hóa) | 1.28 | 2.41 | 2.78 | > 1 tốt, nhưng xem skew |
| Sortino | 1.42 | 2.70 | 3.13 | |
| Skew / kurtosis mỗi basket | −4.6 / 25 | −7.1 / 60 | −7.5 / 69 | ≈ 0 / 3 là bình thường |
| Lần thua tệ nhất (số lần thắng TB) | 27 | 38 | 38 | |
| PSR (Sharpe > 0) | 86.5% | 95.0% | 96.1% | ≥ 95% |
| **Deflated Sharpe** (N=10 / 30 thử) | **40% / 25%** | 71% / 58% | **77% / 66%** | ≥ 95% |
| MinTRL (95%) | 755 basket ≈ 2.0 năm | 384 ≈ 0.9 năm | 333 ≈ 0.8 năm | |
| MC 1 năm P(DD > 20%) | 91% | 79% | **13%** | |
| MC 1 năm P(lỗ cả năm) | 6.6% | 0.7% | 0.3% | |
| Thời gian dưới đỉnh dài nhất | 55 ngày | 40 ngày | 40 ngày | |

Đọc bảng:

1. **Skew −7.5 nghĩa là Sharpe ≈ 2.8 đang đánh giá quá cao.** Đây là profile bán quyền chọn: 97% lần thắng nhỏ,
   thỉnh thoảng một lần thua bằng 38 lần thắng. Sharpe coi hai chiều biến động như nhau nên không bắt được
   rủi ro đuôi này. Bảng dùng PSR/DSR vì chúng có hiệu chỉnh cho skew và kurtosis.
2. **Deflated Sharpe < 95% ở mọi run.** Từ §8 đến nay đã thử ít nhất 10–30 cấu hình (k, cap, lot, spread,
   các gate). Sau khi trừ hiệu ứng "chọn cái tốt nhất trong nhiều lần thử", xác suất edge thật chỉ còn
   66–77% ở spread $0.05, và **25–40% ở spread thật $0.40**.
3. **MinTRL**: cần 0.8–2 năm giao dịch live hoặc forward-test mới có thể xác nhận edge ở mức 95%. Đây
   là giới hạn thống kê, không có cách làm nhanh hơn.
4. Rủi ro đuôi chỉ về mức chấp nhận được khi **lot ở sàn** (run #7): P(DD > 20%) còn 13%, so với 79–91% ở
   lot 0.03.
5. Tín hiệu thuần vẫn âm (§12.1). Phần dương đến từ cấu trúc DCA + BE (mean reversion ngắn hạn của vàng),
   mới thấy trên một năm có trend.

**Kết luận**: đủ điều kiện **forward-test bằng tiền nhỏ, xem như học phí**. **Chưa** đủ điều kiện scale vốn.

### 13.2 Ba sai khác giữa backtest và live đã tìm thấy

| # | Sai khác | Ảnh hưởng | Xử lý |
|---|---|---|---|
| 1 | **Session filter lệch giờ**: tester đặt `InpTesterGMTOffset = 0`, trong khi server là UTC+2/+3 (đo được: giao dịch dừng từ 00:00 và mở lại lúc 01:00 giờ server) | Mọi backtest lọc phiên sớm 2–3 giờ so với live. Live không bao giờ vào lệnh ở server 07–09 (UTC 04–06), mà các giờ này chiếm **134/383 basket, +$269 = 34% lợi nhuận run #7** (ở run #5 thì −13%) | Preset R10 đặt `InpTesterGMTOffset = 2`: đúng tuyệt đối vào mùa đông, lệch 1 giờ vào mùa hè (tester không mô phỏng được DST). Live dùng `TimeGMT()` nên không bị ảnh hưởng |
| 2 | **Swap không được tính**: balance mỗi dòng đóng lệnh chênh với profit tối đa $0.01 | Run #7 có 96/488 leg qua đêm, 1.40 lot-đêm/năm. Ở swap $5–40/lot/đêm, chi phí bằng 1–7% lợi nhuận | Nhỏ, nhưng phải trừ khi so live với backtest |
| 3 | **Gate 1 (`InpMinRecLevel`) không có tác dụng trong tester** (§11.10): chưa có outcome nên floor tự hạ về WAIT | Trên live, indicator đã tích lũy outcome, nên `InpMinRecLevel = 2` (CAUTION) có thể chặn tín hiệu mà tester luôn cho qua | Preset R10 đặt `InpMinRecLevel = 3` (WAIT), đúng bằng floor tester đã thực sự dùng, để live lọc giống backtest |

### 13.3 Cấu hình R10: một file cho cả backtest và live

`presets/R10_cent10k.set`, sinh từ Parameters của run #9 (default + 12R), chỉ đổi:

| Input | Giá trị | Lý do |
|---|---|---|
| `InpMinLotSize` = `InpMaxLotSize` | **0.1** | Lot cố định. 0.1 lot trên 10,000 USC tương đương run #7 (0.01 lot trên $1,000) nhân 10: mọi leg ở sàn, cap 15% và 12R cùng nhân theo, **tỉ lệ % giống hệt run #7** |
| `InpMinRecLevel` | 3 (WAIT) | Sai khác #3 |
| `InpTesterGMTOffset` | 2 | Sai khác #1 (chỉ ảnh hưởng tester) |
| `InpUseDCABackstopSL` | true | SL phía broker ở 1.3 × cap basket, phòng khi EA/VPS mất kết nối |
| `InpResearchLog` | true | Có dữ liệu cho `signal_edge.py` |

Đơn vị kiểm tra: 0.1 lot vàng trên tài khoản cent = 10 oz = 10 USC mỗi $1 giá, bằng 0.1 USD thật mỗi $1 giá.
Tương đương về kinh tế với 0.001 lot trên tài khoản USD.

### 13.4 Lộ trình go-live

| Bước | Việc | Qua bước khi |
|---|---|---|
| **0** | Backtest R10: nạp preset, **Initial deposit 10000**, spread **400**, 2024.02–12, XAUUSD M15 | PF ≥ 1.25 **cả hai** nửa năm; relative DD ≤ 20%. Trượt → không live, quay lại §12.2 |
| **0b** | Cùng file, chạy **2023** và **2025**, không chỉnh gì | PF ≥ 1.15, không nửa năm nào < 1.0 |
| **1** | Trên broker cent: đọc thông số symbol (`XAUUSDc`): Digits, Point, lot min/step, contract size, stops level, **swap long/short**, spread thường và spread lúc rollover. Compile, xác nhận Journal in `Build=2026-09-30.2-research` và `Digits=... scaled x...` đúng | Thông số khớp với giả định (0.1 lot = 10 USC/$1, spread ≤ 40–50 cent) |
| **2** | Live, lot 0.1 cố định, VPS, 1 chart XAUUSDc M15 + indicator + EA với preset R10 | Theo dõi hằng tuần bằng `basket_analyzer.py` trên report Account History |
| **3** | Sau **≥ 100 basket** (~3 tháng): so live với backtest | Tỉ lệ thua, spread, slippage nằm trong khoảng của backtest (§13.5) |
| **4** | Sau **≥ 330 basket** (~10–12 tháng, MinTRL) | Chỉ lúc này mới xét tăng vốn hoặc chuyển sang tài khoản USD |

### 13.5 Quy tắc dừng (đặt trước, không đổi giữa chừng)

Dựa trên phân phối của run #7 (block bootstrap, 20,000 đường):

| Dấu hiệu | Ngưỡng | Ý nghĩa |
|---|---|---|
| Max DD tính từ đỉnh | **> 25%** (P = 4% nếu backtest đúng) | **Dừng**, không nạp thêm, phân tích lại |
| Max DD | > 20% (P = 12%) | Cảnh báo: rà soát spread/slippage thật |
| Số basket thua trong 100 basket đầu | **≥ 7** (P = 1%; backtest: 2.35/100, breakeven 4.8/100) | **Dừng**: tỉ lệ thua không còn như backtest |
| Số basket thua trong 100 basket đầu | ≥ 5 (P = 9%) | Cảnh báo |
| Một basket lỗ | > 12R | Lỗi cap / broker, **dừng ngay** để kiểm tra |
| Spread TB lúc vào lệnh | > $0.40 | Backtest đã quá lạc quan so với live |

Không bật Recovery Mode, không tăng lot sau chuỗi thua, không tắt cap để "gồng".

**Kỳ vọng trung thực**: backtest run #7 cho khoảng +80%/năm, nhưng đó là ở spread $0.05, trên 2024, trong
số nhiều cấu hình đã thử, và 34% lợi nhuận nằm ở khung giờ live sẽ không giao dịch. Live nhiều khả năng
thấp hơn đáng kể. Với ~$100 tiền thật, mục tiêu của 6–12 tháng đầu là **đo edge**, không phải kiếm lời.

---

## 12. Đánh giá độc lập: EA có edge thật không? (2026-09-30)

> Phần này nhìn lại toàn bộ §8–§11, kể cả những chỗ tham số được chọn trên chính dữ liệu 2024 (12R,
> k=2). Tính trên run #3–#6. Phần phân tích xu hướng và beta chạy bằng script ad-hoc, chưa có tool
> lưu lại. Phần đo tín hiệu thuần sẽ làm bằng `tools/signal_edge.py` (§12.3).

### 12.1 Kết luận: chưa có bằng chứng

| Kiểm tra | Kết quả | Ý nghĩa |
|---|---|---|
| Chỉ tín hiệu (k=0: không DCA, cắt ở bậc DCA-1 $15), trung hòa xu hướng (TB của BUY và SELL) | −$0.5 → −$1.8/basket, **âm ở cả 4 run** | Tín hiệu không dự báo được hướng giá |
| Random walk không drift, đúng cấu trúc TP1 / DCA $15 / BE / cap 12R của EA | WR **89–90%**, EV −$1.3 ($0) / −$3.5 ($0.40) mỗi basket | WR 96% chủ yếu là **cấu trúc**, không phải kỹ năng |
| Beta xu hướng (EA giữ net long TB 0.81 oz × vàng +29%) | ≈ **$470 / $1,174** của run #5 | ~40% lợi nhuận là giữ lệnh mua trong năm vàng tăng |
| Phần còn lại sau khi trung hòa xu hướng (run #5) | +$2.8/basket, CI 90%: −$3.3 … +$8.1 | P(≤ 0) ≈ 21% |
| Toàn bộ EA (block bootstrap, khối 10) | P(mean ≤ 0) = 6–9% | Chưa đạt ngưỡng 5% |
| Độ mong manh (run #5) | 14 basket thua; breakeven ở 19.3 | Chỉ cần thêm 5 lần thua |
| Mua 0.03 lot rồi giữ cả kỳ | +$1,747 (chưa trừ swap) | **Hơn** EA (+$1,105 / +$1,174 ở $0.40) |

Cấu trúc DCA + BE + TP chỉ **đổi hình dạng** phân phối (nhiều lần lời nhỏ, ít lần lỗ lớn), không đổi
kỳ vọng. Nó chỉ có lợi khi giá thật sự hay quay đầu trong biên độ $15–45. Điều đó có thể đúng, nhưng
dữ liệu chưa chứng minh được. Các lần cắt nặng nhất rơi vào những đợt trend mạnh (5/8/2024, sau bầu cử
Mỹ 11/2024), đúng loại rủi ro mà cấu trúc này yếu nhất.

"Chưa có bằng chứng" không có nghĩa là chắc chắn không có edge: 1 năm, 1 xu hướng, ~340 basket thì
chưa đủ để kết luận theo chiều nào. **Không tăng vốn dựa trên các run này.**

### 12.2 Công cụ cần thêm, theo thứ tự

Thêm indicator dạng momentum (MACD, Stochastic, CCI) vào RSI chỉ làm tăng overfit, vì chúng tương
quan cao với nhau. Thứ còn thiếu trước hết là công cụ đo, rồi mới đến bộ lọc có cơ sở vững:

1. **Research log trong tester + đo tín hiệu thuần** (§12.3). Làm trước tiên, vì các bước sau đều cần.
2. **Lọc theo xu hướng khung lớn**: chỉ vào lệnh cùng hướng D1 (time-series momentum, Moskowitz, Ooi
   và Pedersen 2012). Dữ liệu 2024 nghiêng về hướng này (BUY dương, SELL âm), nhưng phải kiểm lại trên 2023.
3. **Lọc chế độ thị trường** (Efficiency Ratio/ADX): RSI đảo chiều + DCA chỉ sống được khi thị trường
   đi ngang. Gate 8 đã có code nhưng đang tắt và chưa được đo.
4. **Sizing theo biến động** (lot theo ATR, rủi ro cố định %): hiện bị chặn bởi lot sàn 0.03 → run #6b.
5. **Lịch tin lịch sử** cho Gate 9: MT4 không có calendar API, nên hiện không backtest được.
6. **Đa dạng hóa** nhiều symbol/TF (IR ≈ IC × √N) sau khi tín hiệu đã chứng minh được edge.

Pipeline XGBoost/meta-labeling chỉ có ý nghĩa khi có hàng nghìn tín hiệu, tức là sau bước 1.

### 12.3 Research log + `tools/signal_edge.py`

**Vì sao cần**: logger CSV của indicator tắt trong tester (`SignalLogger.mqh:334`) để giữ tester nhanh
và không ghi đè dữ liệu live. Nên backtest không để lại bản ghi tín hiệu nào, chỉ có các lệnh mà DCA
tạo ra từ chúng. Tín hiệu bị gate chặn thì mất hẳn.

**EA** (build `2026-09-30.2-research`, mq4 + mq5): input `InpResearchLog` (mặc định **tắt**) ghi mỗi
nến đã đóng một dòng vào `<Common>\Files\QuantEdge_Research\bars_<SYMBOL>_<TF>_<ngày bắt đầu>.csv`:

- OHLC của nến, bid/ask ở tick đầu nến kế tiếp (giá EA có thể khớp lệnh).
- Case BUY/SELL, cùng ENTRY/SL/TP1–3, REC_LEVEL, CONFIDENCE, EV, RISK, PROB_TP1/SL/N trên nến có tín hiệu.
  Đây đúng là các giá trị EA đọc lúc ra quyết định, nên **không dùng dữ liệu tương lai**. File có đủ
  mọi tín hiệu, kể cả tín hiệu bị gate chặn.
- Không đổi hành vi giao dịch. Tắt trong optimization. Không cần sửa indicator.

**Tool**: so mỗi tín hiệu với **vào lệnh ngẫu nhiên cùng hướng, cùng giờ (±1h), cách 2–12 ngày quanh
tín hiệu** (pool đối xứng triệt tiêu xu hướng cục bộ; bỏ 2 ngày gần nhất để không trùng đường giá
của chính tín hiệu). Hai phép đo:

1. Lợi nhuận sau 15m / 1h / 4h / 1d, tính theo ATR, đã trừ spread.
2. Kết quả chạm SL/TP1 của chính tín hiệu, tính theo R, và đem so với vào lệnh ngẫu nhiên có cùng
   khoảng SL/TP.

Sau đó tool kiểm tra PROB_TP1/EV có xếp hạng tín hiệu tốt hơn chính hình học SL/TP không (Brier, AUC),
tách theo case / rec level / giờ / năm, và báo ngưỡng Bonferroni cho số phép thử. Sai số được cluster
theo tuần.

`python tools/signal_edge.py --selftest` kiểm chứng chính phương pháp trên dữ liệu giả:

- Trend +46–65%, **không** có edge: BUY lời thô +1.3–2.1 ATR/ngày, nhưng tool báo excess |t| < 1.6 → không báo nhầm.
- Edge cài sẵn: t 3.3–5.3 ở cả hai phép đo, AUC 0.56–0.60, còn hình học SL/TP ≈ 0.5 → phát hiện được.

**Cách chạy** (khuyến nghị MT5, "Every tick based on real ticks" để có spread thay đổi thật; MT4 thì
dùng spread 400 cố định và thêm `--spread 0.40`):

1. Compile EA. Bật `InpResearchLog = true`, giữ nguyên các input khác. Chạy dài nhất có thể:
   **2015 → 2025**, XAUUSD M15.
2. Log EA in đường dẫn file ngay khi bắt đầu chạy.
3. `python tools/signal_edge.py "<đường dẫn>\bars_XAUUSD_M15_2015xxxx.csv" --dump logs/signals.csv`

**Đọc kết quả**: cần excess dương **ở hầu hết các năm** và t > 1.96 trên toàn mẫu. Một ô trong bảng
breakdown chỉ đáng tin nếu vượt ngưỡng Bonferroni mà tool in ra. Nếu tín hiệu không vượt được vào lệnh
ngẫu nhiên, mọi tối ưu EA phía sau (DCA, cap, gate) chỉ là sắp xếp lại cùng một kỳ vọng.
