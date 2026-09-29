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
