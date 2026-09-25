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
