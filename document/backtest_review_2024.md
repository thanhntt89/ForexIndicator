# Đánh giá backtest XAUUSD M15 — 2/2024 đến 12/2024

> **Ngày**: 2026-09-25
> **Nền tảng**: MT4, `QuantEdge_EA_Template.mq4`
> **Vốn**: $1,000 · **Spread**: Current (50 point, cố định) · **Model**: Every tick
> **Verdict**: ❌ **CHƯA đạt chuẩn chạy live** — xem §5

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

## 8. Tiêu chí PASS để cân nhắc live

Tất cả phải đạt, không có ngoại lệ:

- [ ] WR basket-level > 62.8%
- [ ] PF với spread thực tế ≥ 1.3
- [ ] PF out-of-sample ≥ 1.2, không sụp so với IS
- [ ] MaxDD ≤ 20% với circuit breaker bật
- [ ] Recovery factor ≥ 3.0
- [ ] Rủi ro thật mỗi lệnh ≤ 1% ở vốn $1,000

Thiếu bất kỳ mục nào → chưa live, và ghi rõ thiếu cái gì.

---

## 9. Ngoài phạm vi (làm sau khi V1–V3 xong)

- **Tối ưu tham số**: tối ưu trước khi kiểm chứng là cách chắc chắn nhất để overfit.
- **Đổi TP:SL ratio**: `DCA_Scalping_Strategy.md` §4.3 có sẵn Alt A/B/C. Payoff hiện tại
  b = 0.592 đòi WR 62.8% — rất cao. Nâng b lên sẽ hạ ngưỡng này, nhưng cần baseline OOS trước.
- **Entry Zone system**: EA luôn ăn Z1 Market (EV thấp nhất) —
  `document/analysis_EA_market_entry.md` §4.3.
