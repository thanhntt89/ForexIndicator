# Phân tích chất lượng điểm vào lệnh Market của EA

> **Ngày**: 2026-09-24
> **Phạm vi**: `Experts/QuantEdge_EA_Template.mq4` / `.mq5`
> **Build tag sau fix**: `2026-09-24.1-entryqual`
> **Không đụng**: indicator (`QuantEdge_RSI.mq4/.mq5`), `Include/QuantEdge/`

---

## 0. Bối cảnh

Tín hiệu từ indicator chạy đúng và EA đã vào lệnh, nhưng một số lệnh market mở ở vị trí vô lý
so với điểm entry mà indicator công bố. Truy vết toàn bộ đường đi tín hiệu:

```
QuantEdge_RSI.mq5:585-640   tính entry/SL/TP tại bar đóng
      ↓
PublishSignalToGV()          ghi GlobalVariable QE_Sig*_<symbol>
      ↓
EA OnTick() new-bar          ReadSignalFromGV() → arm g_sig*
      ↓
EA TryExecuteSignal()        10 gate → CalculateLotFromRisk() → Buy()/Sell()
      ↓
EA tick-level retry          lặp lại mỗi tick trong InpRetryMaxBars
```

Kết luận: **không phải vấn đề tham số mà là 7 lỗi logic** trong EA, cộng với việc gần như toàn
bộ bộ lọc chất lượng đang tắt theo mặc định. Bộ lọc duy nhất thực sự hoạt động là
`Confidence >= 50`.

---

## 1. Nhóm A — Bug logic

### A1. Vào lại đúng tín hiệu cũ sau khi basket đã đóng (nghiêm trọng nhất)

**Triệu chứng**: trên chart chỉ thấy **1 mũi tên nhưng có 2 lệnh**, lệnh thứ hai mở ở giá đã
chạy xa $6-7 so với entry công bố.

**Nguyên nhân**: ba điều kiện cộng hưởng:

1. Indicator chỉ xóa GV ở `OnDeinit` (`QuantEdge_RSI.mq5:1139` `CleanupSignalGV`) — GV của tín
   hiệu cũ **nằm lại vô thời hạn** sau khi EA đã vào lệnh.
2. EA không lưu "tín hiệu nào đã trade" — `grep lastTraded` trả về 0 kết quả.
3. `ReadSignalFromGV()` (`EA.mq5:356`) chỉ kiểm tra `iBarShift(sigTime) <= scanLimit`.

Luồng thực tế:

| Bar | Sự kiện |
|-----|---------|
| N | GV publish signal → EA vào lệnh → `g_sigValid = false` (`:2634`) |
| N+1 | TP1 hit → `CloseEntireBasket()` + `ClearDCAState()` → `g_dcaActive = false` |
| N+2 | `ReadSignalFromGV()` đọc **lại đúng GV cũ**, `iBarShift = 2 <= scanLimit = 5` → pass |
| N+2 | `g_sigValid = true` lần nữa → Gate 4 pass (không còn position) → **vào lại** |

Arrow không vẽ lại vì `DrawSignalArrow()` dedup theo `ObjectFind` → nhìn chart không phát hiện được.

**Giải pháp**: thêm `datetime g_lastTradedSigTime`, set khi fill thành công, persist qua GV
riêng `QE_LastSig_<symbol>_<magic>`.

> Quan trọng: **không** lưu trong `SaveDCAState()`. `ClearDCAState()` chạy đúng lúc basket đóng —
> tức đúng lúc còn cần nhớ tín hiệu đã trade. Lưu chung sẽ xóa mất và bug tái hiện.

Chặn arm ở cả 3 điểm: `OnInit` GV path, `OnInit` iCustom scan, `OnTick` new-bar.

---

### A2. Vào lệnh sau khi giá đã chạm TP1

**Nguyên nhân**: `IsSignalStillValid()` (`EA.mq5:2196-2204`) phát hiện TP1 hit, set
`g_sigTP1Hit = true`, nhưng **vẫn `return true`**. Cờ này chỉ được đọc bên trong khối Gate 10 —
mà Gate 10 mặc định **OFF** (`:151`).

→ Giá đã đi hết Entry→TP1 (động lượng cạn), EA vẫn retry và vào market, rồi dịch TP1 lên cao
thêm một đoạn nữa bằng `priceShift`.

**Giải pháp**: `g_sigTP1Hit` → `g_sigValid = false; return false`, độc lập với Gate 10. Thêm
input `InpInvalidateOnTP1 = true` làm lối thoát.

---

### A3. Gate 10 hở khi giá ra ngoài dải SL–TP1

**Nguyên nhân**: `EA.mq5:2374-2409`

```cpp
if(priceBetweenSLEntry)      { ...kiểm tra drift... }
else if(priceBetweenEntryTP) { ...kiểm tra drift... }
// KHÔNG có else → g10_pass giữ nguyên = true
```

Giá **vượt TP1** hoặc **thủng SL** → cả hai nhánh false → `g10_pass` vẫn `true` → gate cho qua.
Gate được thiết kế để chặn entry xa lại không chặn đúng trường hợp xa nhất.

**Phụ**: `probSL = 100.0 - probTP1` (`:2356`) sai khái niệm — "không chạm TP1" ≠ "chạm SL".
Giá có thể lang thang giữa SL và TP1 tới hết đời tín hiệu. Buffer `BUF_PROB_SL` (index 14) có
sẵn trong contract nhưng EA không khai báo.

**Giải pháp**: thêm nhánh `else { g10_pass = false; }` kèm log; khai báo `#define BUF_PROB_SL 14`
và đọc giá trị thật.

---

### A4. Gate 3 (staleness) thực tế không bao giờ chạy

**Nguyên nhân**: `ReadBuffer()` mặc định shift = 1 (`EA.mq5:340`). Nhưng indicator ghi
`BufferProbSurvivalRatio` **chỉ tại bar của signal** (`QuantEdge_RSI.mq5:976`), mọi bar khác là
`EMPTY_VALUE` (`:526`).

→ Khi signal ở shift ≥ 2 — đúng giai đoạn retry, lúc cần chống stale nhất — `survival` trả
`EMPTY_VALUE`, điều kiện `survival != EMPTY_VALUE` false → **gate bị bỏ qua hoàn toàn**
(`EA:2209` trong `IsSignalStillValid`, `EA:2305` trong `TryExecuteSignal`).

**Giải pháp**: helper `ReadSignalBuffer(int idx)` tính shift từ `g_sigBarTime` qua `iBarShift()`.
Indicator refresh buffer tại `sigBarIdx` mỗi lần redraw (`QuantEdge_RSI.mq5:966-985`) nên giá
trị đọc được luôn là số liệu decay mới nhất, không phải snapshot lúc tạo tín hiệu.

---

### A5. `priceShift` dịch cả SL/TP — phá cấu trúc SL

**Nguyên nhân**: `EA.mq5:2494-2500`

```cpp
priceShift = marketPrice - entry;
adjSL  = sl  + priceShift;
adjTP1 = tp1 + priceShift;
```

SL gốc được tính từ **swing low thực tế** (`SLTP.mqh:242` `MathMin(swingSL, entry - atrSL)`).
Dịch cả khối giữ nguyên khoảng cách R nhưng SL **không còn nằm dưới đáy cấu trúc** nữa. Retry
5 bar M15 = 75 phút, XAU chạy $3-5 → SL bị kéo lên trên đáy → dính stop bởi nhiễu bình thường.

**Phụ — spread bias có hệ thống**: BUY dùng `marketPrice = Ask`, còn `entry` được publish theo
`open[i+1]` (bid-based). Nên `priceShift` của BUY **cộng thêm nguyên spread** vào SL. SL của
BUY luôn chặt hơn SELL một spread, mọi lệnh, mọi lúc.

**Giải pháp**: giữ SL/TP ở mức cấu trúc **tuyệt đối**, chỉ clamp theo `SYMBOL_TRADE_STOPS_LEVEL`.
Bỏ hoàn toàn biến `priceShift` → spread bias tự biến mất.

Tính lại lot từ khoảng cách **thật**: `slDistanceActual = |marketPrice - adjSL| / _Point`.

| Tình huống | Trước | Sau |
|-----------|-------|-----|
| Vào ngay | SL đúng swing, R đúng | như cũ |
| Vào muộn $3 | SL kéo lên $3 (trên swing), R sổ sách không đổi nhưng R thật sai | SL giữ nguyên, khoảng cách rộng hơn → **lot nhỏ hơn**, R sổ sách khớp R thật |

Thêm input `InpUseStructuralSLTP = true` để rollback không cần sửa code.

**Hệ quả cần chặn**: vào muộn làm reward còn lại co lại trong khi risk giữ nguyên → xử lý bằng
Gate 12 (§2.3).

---

### A6. Order bị từ chối vẫn được tính là đã vào lệnh

**Nguyên nhân**: `EA.mq5:2560-2601` in lỗi khi `!result` nhưng **vẫn chạy tiếp** xuống khối
init DCA state (`:2606`):

```cpp
if(!result)
   Print("[QuantEdge EA] Order failed: ", ...);   // chỉ log, không return
else { ... }

// --- Initialize DCA state after successful order placement ---
if(InpUsePositiveDCA || InpUseNegativeDCA)
{
   g_dcaActive = true;    // ← chạy kể cả khi order bị reject
   ...
}
g_sigValid = false;
return true;               // ← báo "đã vào lệnh"
```

Hậu quả — không có position nào nhưng EA tin là có basket:
- Gate 4 (`!g_dcaActive`) chặn **mọi tín hiệu mới**
- `ApplyDCABackstopSL()` làm việc với state ảo
- Tín hiệu bị đánh dấu đã tiêu thụ (`g_sigValid = false`) dù chưa vào được lệnh
- `ManageDCA()` có dọn được qua nhánh `!HasAnyOriginalPosition() && !HasAnyDCAPosition()`
  (`:1499`), nhưng tín hiệu thì đã mất

**Giải pháp**: biến `bool anyLegFilled`. Chỉ init DCA state, set `g_lastTradedSigTime`,
`g_sigValid = false` và `return true` khi có ít nhất một leg fill thật. Thất bại → `return false`
để retry tiếp tục ở tick sau.

---

### A7. Gate 9 bật nhưng không có dữ liệu để đọc

**Nguyên nhân**: `PublishEconBlackoutState()` (`EconCalendar.mqh:96-99`) return sớm khi
`InpUseEconCalendar == false` — và đó chính là **default của indicator** (`Config.mqh:297`).

EA đọc `GlobalVariableCheck("QE_EconBlackout_" + Symbol())` → false → `g9_pass` giữ `true` →
gate im lặng không làm gì. **Bật Gate 9 bên EA một mình là vô nghĩa.**

ADX không bị lỗi này: `InpUseADXFilter = true` mặc định (`Config.mqh:285`) nên
`QE_ADXGatePassed_` có được publish.

**Giải pháp**: không sửa indicator (ngoài phạm vi). EA log cảnh báo **một lần** ở `OnInit` khi
Gate 9 bật mà GV vắng mặt, nêu rõ phải bật `InpUseEconCalendar` bên indicator.

---

## 2. Nhóm B — Gate chất lượng

### 2.1 Gate 5 mở rộng — spread tương đối

Spread tuyệt đối không phản ánh chi phí thật. M15 XAU: TP1 ≈ ATR×0.8 ≈ $6.4. Spread
$0.30–0.80 lúc rollover/news = **5–12% target**, chưa kể slippage.

```
spreadPct = spreadPrice / |tp1 - entry| * 100
fail khi spreadPct > InpMaxSpreadPctOfTP1 (default 8.0)
```

Tự co giãn theo ATR — ATR to thì TP1 to, ngưỡng tuyệt đối tự nới. Không cần tune lại theo regime.

### 2.2 Gate 11 mới — EV

Indicator tính EV đầy đủ rồi EA chỉ `Print`. Không có gate nào dùng.

```
fail khi ev != EMPTY_VALUE && ev < InpMinEV (default 0.0)
```

Dùng `<` chứ không `<=` để tránh chặn oan trường hợp `ev == 0` do buffer fallback
(`EA.mq5:2769` gán `ev = 0` khi buffer chưa sẵn sàng).

### 2.3 Gate 12 mới — R:R còn lại tại giá fill

Đi kèm A5. Đo trực tiếp cái mình quan tâm thay vì đoán ngưỡng khoảng cách:

```
remainRR = |tp1 - marketPrice| / |marketPrice - adjSL|
fail khi remainRR < InpMinFillRR (default 0.5)
```

Đây là hàng rào chính chống "vào muộn": drift càng nhiều → reward co lại, risk giãn ra → RR còn
lại càng tệ → gate tự chặn.

---

## 3. Bảng đổi default

| Input | Cũ | Mới | Lý do |
|-------|-----|-----|-------|
| `InpMinRecLevel` | `REC_ANY` | `REC_CAUTION_ENTRY` | `REC_ANY` tắt Gate 1 hoàn toàn → vào cả `AVOID` và `COUNTER_TREND`, theo contract là **EV ≤ −0.05R** |
| `InpUseGate5Spread` | `false` | `true` | |
| `InpMaxSpreadPoints` | `0` | `40` | ~$0.40 XAU |
| `InpUseGate10PriceLoc` | `false` | `true` | |
| `InpPriceLocMaxPct` | `50` | `25` | 50% Entry→SL là quá muộn |
| `InpRetryMaxBars` | `5` | `2` | 75 phút → 30 phút trên M15 |
| `InpUseSessionFilter` | `false` | `true` | `PROJECT_STATUS.md`: Case 6 rất tệ ở Asian + LateNY |
| `InpUseRecoveryMode` | `true` | `false` | Nhân lot ×1.3 ngay sau cutloss = tăng size đúng lúc regime bất lợi |
| `InpUseEconCalGate` | `false` | giữ `false` | Vô nghĩa nếu indicator chưa bật — xem A7 |

**Input mới**:

| Input | Default | Mục đích |
|-------|---------|----------|
| `InpInvalidateOnTP1` | `true` | A2 — hủy tín hiệu khi TP1 đã chạm |
| `InpUseStructuralSLTP` | `true` | A5 — giữ SL/TP cấu trúc, `false` = hành vi cũ |
| `InpMaxSpreadPctOfTP1` | `8.0` | B1 — spread tương đối |
| `InpUseGate11EV` | `true` | B2 |
| `InpMinEV` | `0.0` | B2 |
| `InpUseGate12FillRR` | `true` | B3 |
| `InpMinFillRR` | `0.5` | B3 |

> **Lưu ý vận hành**: chart đang chạy giữ set đã lưu trong `.chr`. Chỉ chart **attach mới** mới
> ăn default mới. Muốn áp dụng cho chart cũ thì phải chỉnh tay trong cửa sổ input hoặc
> remove/re-attach EA.

---

## 3b. Hồi quy đã sửa — mất mũi tên trên chart (build `.2-arrowfix`)

**Triệu chứng**: sau khi áp bản `.1-entryqual`, mũi tên tín hiệu không còn hiện trên chart, dù
panel SL/TP/EN vẫn vẽ đúng.

**Nguyên nhân**: guard chặn re-arm của A1 đặt **trước** chỗ vẽ mũi tên. Nhưng mũi tên là chú
thích "ở đây từng có tín hiệu" — nó không liên quan tới việc EA còn được phép trade tín hiệu
đó hay không. Với `InpEAMode = true` indicator không vẽ gì (`QuantEdge_RSI.mq5:398`), nên EA là
thứ duy nhất vẽ được. Bỏ luôn việc vẽ cùng với việc chặn re-arm khiến mọi tín hiệu đã trade
biến mất khỏi chart — tức gần như toàn bộ.

Vấn đề sâu hơn: việc vẽ **vốn đã** gắn sai chỗ từ trước. Nó nằm tại các điểm arm tín hiệu, mà
các điểm đó bị chi phối bởi những điều kiện không liên quan gì tới hiển thị:
- `OnInit` scan bị bỏ qua khi `InpUseSignalRetry = false` hoặc khi đã có position
- Scan dừng ở tín hiệu đầu tiên còn trade được (`break`)
- Cửa sổ quét chỉ `InpRetryMaxBars` — mà lần này tao giảm 5 → 2

**Giải pháp**: tách thành `RedrawSignalArrows()` chạy độc lập:
- Quét `max(InpRetryMaxBars, 200)` bar, không dừng ở tín hiệu đầu
- Gọi vô điều kiện ở `OnInit` (không phụ thuộc retry/position)
- Vẽ ở `OnTick` **trước** guard re-arm
- Retry mỗi tick tới khi indicator tính xong (`g_arrowSweepDone`)

**Chi tiết dễ sai**: probe readiness phải dùng buffer 0 (`BufferGreen`, RSI fast line) chứ
không dùng signal buffer. Signal buffer trả `EMPTY_VALUE` ở mọi bar **không có tín hiệu** —
không phân biệt được với đọc lỗi, nên 200 bar im lặng sẽ khiến sweep retry mãi mỗi tick.
Contract ghi rõ buffer 0 có giá trị "Every bar" (`12_EA_EXPORT_CONTRACT.md:33`).

`OnDeinit` đã có guard `reason != REASON_CHARTCHANGE` từ commit `95b9516` — không phải nguyên
nhân lần này, nhưng comment ở đó đã lỗi thời và được cập nhật.

---

## 3c. Mũi tên vẫn không hiện — 2 bug độc lập (build `.3-arrowvis`)

Sau `.2-arrowfix` mũi tên vẫn mất. Lần này **không phải** do thay đổi của branch — hai bug tồn
tại từ commit `64946e9` (lần đầu thêm `DrawSignalArrow` vào EA), chỉ chưa ai để ý.

### Bug 1 — offset sai đơn vị + thiếu ANCHOR

```cpp
double offset = InpArrowOffsetPts * _Point;   // 10 * 0.01 = $0.10 trên XAUUSD
ObjectCreate(0, name, OBJ_ARROW, 0, barTime, price - offset);
// không set OBJPROP_ANCHOR
```

Hai vấn đề cộng lại:
- `_Point` trên XAUUSD = 0.01 → offset = **$0.10**. Trên chart phạm vi ~$150 thì $0.10 là 0.07%
  chiều cao chart — mũi tên nằm ngay trên thân nến.
- Không set `OBJPROP_ANCHOR` → MT4/MT5 mặc định `ANCHOR_CENTER`, tâm glyph đè đúng vào giá.

Indicator **không** bị: `CreateSignalArrow()` (`ArrowManager.mqh:26,33`) set `ANCHOR_TOP` /
`ANCHOR_BOTTOM` — đúng lý do này.

**Sửa**: mirror anchor của indicator; offset lấy `max(InpArrowOffsetPts × Point, barRange × 0.5)`
để tự co giãn theo symbol, giữ input làm mức sàn thay vì toàn bộ khoảng cách.

### Bug 2 — không `ChartRedraw`

Object tạo từ EA **không được vẽ** cho tới khi chart repaint. Indicator được repaint tự động sau
`OnCalculate`; EA thì không. EA chỉ gọi `ChartRedraw` bên trong `QEEA_CreatePanel()` — nên mũi
tên tồn tại trong object list nhưng không bao giờ hiện ra.

**Sửa**: `ChartRedraw` sau sweep và sau mỗi lần vẽ mũi tên mới ở `OnTick`.

### Lưu ý khi chart có cả indicator standalone

Việc chart hiện lines (SL / Z2 / Z3 / EN / TP1) nghĩa là có một instance indicator chạy với
`InpEAMode = false` — mọi hàm vẽ đều gated trên cờ này (`LineDrawing.mqh:28`,
`PanelDrawing.mqh:363`). Instance đó tự vẽ `QE_Arrow_` của riêng nó, độc lập với `QEEA_Arr_` của
EA. Hai bộ mũi tên dùng prefix khác nhau nên không xung đột, nhưng khi debug phải xác định đang
thiếu bộ nào.

`QEEA_CleanupOrphanedIndicatorObjects()` chỉ xóa `QE_Line_` / `QE_Zone_`, **không** xóa
`QE_Arrow_` — không phải nguyên nhân. `QEEA_DeletePanel()` xóa theo tên cụ thể chứ không theo
prefix `QEEA_`, nên cũng không chạm `QEEA_Arr_`.

---

## 3d. Quyết định: mũi tên thuộc indicator, EA không vẽ (build `.4-noeaarrow`)

Theo yêu cầu: **EA chỉ nhận tín hiệu, indicator vẽ mũi tên.** Toàn bộ cơ chế vẽ mũi tên đã bị
xóa khỏi EA (−376 dòng).

**Đã xóa khỏi cả `.mq4` và `.mq5`**:
- 5 input: `InpShowSignalArrows`, `InpArrowSize`, `InpArrowOffsetPts`, `InpBuyArrowColor`,
  `InpSellArrowColor`
- 3 hàm: `DrawSignalArrow()`, `RedrawSignalArrows()`, `CleanupSignalArrows()`
- Biến `g_arrowSweepDone` + 4 điểm gọi vẽ (2 ở `OnInit`, 2 ở `OnTick`)

**Thêm mới**: `QEEA_CleanupLegacyArrows()` — quét xóa object `QEEA_Arr_` do build cũ để lại, gọi
ở cả `OnInit` và `OnDeinit`. Không có nó thì chart nâng cấp tại chỗ vẫn hiện bộ mũi tên mồ côi
mà không còn gì quản.

> Điều này cũng làm §3b và §3c thành lịch sử: cả hai đều là bug trong code EA vẽ mũi tên, mà
> code đó giờ không còn. Giữ lại để ghi nhận bối cảnh, nhưng không còn áp dụng.

### ⚠️ Việc cần indicator: `DeleteOppositeArrows()` xóa lịch sử mũi tên

**Chưa sửa** — nằm trong indicator, ngoài phạm vi yêu cầu. Nhưng đây là nguyên nhân khiến chart
chỉ hiện được rất ít mũi tên:

```cpp
// ArrowManager.mqh:75
void DeleteOppositeArrows(bool newSignalIsBuy)
{
   if(InpEAMode) return;
   string killPrefix = PREFIX_ARROW + (newSignalIsBuy ? "SELL_" : "BUY_");
   DeleteObjectsByPrefix(killPrefix);   // xóa TOÀN BỘ mũi tên chiều đối lập
}
```

Gọi ở `QuantEdge_RSI.mq5:591` và `:690` mỗi khi có tín hiệu mới ở 2 bar cuối. Nên mỗi tín hiệu
BUY xóa **mọi** mũi tên SELL trên chart và ngược lại — không chỉ mũi tên gần nhất mà cả lịch sử.

Trên XAUUSD M15 với 7 case đang bật, tín hiệu đổi chiều liên tục, nên chart thường chỉ giữ được
mũi tên của chuỗi cùng chiều gần nhất.

Nếu mày muốn thấy đầy đủ lịch sử mũi tên, có 2 hướng:
- Chỉ xóa mũi tên đối lập **trong N bar gần nhất** thay vì toàn bộ prefix
- Hoặc bỏ hẳn `DeleteOppositeArrows` — `CreateSignalArrow()` vốn đã dedup theo tên object

---

## 3e. Nguyên nhân gốc: `InpEAMode` chặn cả mũi tên (build `.5-eaarrow`)

Sau `.4-noeaarrow` vẫn không thấy mũi tên. Manh mối quyết định là câu **"chỉ báo đang dùng
config mặc định của EA"** — nghĩa là instance duy nhất trên chart là bản headless mà EA nạp qua
`iCustom` với `Ind_EAMode = true`, **không** phải một indicator standalone.

Nên trạng thái thực tế là:

| Ai | Có vẽ mũi tên? |
|----|----------------|
| EA | Không — đã xóa ở `.4-noeaarrow` theo yêu cầu |
| Indicator (qua `iCustom`, `InpEAMode=true`) | Không — `CreateSignalArrow()` return ngay ở dòng đầu (`ArrowManager.mqh:14`) |

→ **Không ai vẽ cả.** Đây là hệ quả trực tiếp của `.4`: trước đó EA che lấp việc indicator
headless không vẽ.

Đây cũng giải thích luôn §3b/§3c/§3d đã chẩn đoán lệch hướng: tao suy ra "có indicator standalone
đang chạy" từ việc chart hiện lines SL/Z2/Z3/EN/TP1. Nhưng chart ở §3b **là ảnh cũ** từ lúc còn
indicator standalone; ảnh sau khi chuyển sang EA-only thì lines cũng mất — chi tiết đó tao đã bỏ
qua.

### Giải pháp: tách mũi tên khỏi `InpEAMode`

`InpEAMode` tồn tại để bỏ phần chart furniture đắt đỏ — panel, SL/TP lines, zones, explain box.
Mũi tên thì chỉ là vài object `OBJ_ARROW` tạo một lần mỗi tín hiệu, gộp chung vào cùng một cờ là
quá thô.

Thêm `InpArrowsInEAMode = true` (`Config.mqh:139`) và đổi 3 gate trong `ArrowManager.mqh`:

```cpp
if(InpEAMode && !InpArrowsInEAMode) return;   // thay cho: if(InpEAMode) return;
```

Áp cho `CreateSignalArrow()`, `CleanupOldArrows()` và `DeleteArrowForSignal()` — ba hàm phải
cùng nhịp, nếu vẽ mà không prune thì mũi tên tích tụ vô hạn.

**Cố ý KHÔNG đổi `DeleteOppositeArrows()`**: nó vẫn return sớm trong EA mode. Nghĩa là chart chạy
EA giữ được **đầy đủ lịch sử mũi tên** cả hai chiều — đúng điều mày muốn — trong khi chart
standalone giữ hành vi cũ (mỗi tín hiệu mới xóa mũi tên chiều đối lập). Xem §3d về vấn đề này.

**Không phá vỡ `iCustom`**: EA chỉ truyền 7 tham số đầu, dừng ở `InpEAMode` (input thứ 8).
`InpArrowsInEAMode` nằm ở dòng 139, sau đó rất xa, nên thứ tự tham số không đổi và input mới
lấy default `true`.

Cả hai nền tảng dùng chung `Config.mqh` + `ArrowManager.mqh` nên không cần sửa riêng `.mq4`/`.mq5`.

---

## 3f. Backtest không vào lệnh nào — 2 bug (build `.6-backtest`)

### Bug 1 — Gate 10 từ chối đúng entry tốt nhất (do tao gây ra ở `.1-entryqual`)

Nhánh `else` tao thêm ở §A3 đúng về ý định nhưng sai về ranh giới. Điều kiện phân loại dùng
**strict inequality cả hai phía**:

```cpp
priceBetweenSLEntry = (mktNow <  entry && mktNow > sl);
priceBetweenEntryTP = (mktNow >  entry && mktNow < tp1);
```

Khi `mktNow == entry` **chính xác**, cả hai đều false → rơi vào nhánh `else` "ngoài dải" → bị
từ chối.

Đây **không phải** trường hợp hiếm. Indicator đặt `entry = open[i+1]` (`QuantEdge_RSI.mq5:593`)
— tức giá mở của **chính bar mà EA đánh giá**. Ở tick đầu tiên của bar đó, `Bid`/`Ask` bằng đúng
giá open. Nên gate từ chối đúng cái entry **tươi nhất, ít trôi nhất** — 0% drift.

Trong backtest với mô hình "Open prices only" hoặc "1 minute OHLC", EA gần như **chỉ** thấy tick
tại giá open → gate chặn gần hết. Live thì tick liên tục nên giá lệch khỏi entry ngay, che mất
bug này.

**Sửa**: đổi thành `>=` / `<=` ở nhánh TP-side để "đứng đúng entry" = drift 0%, đi qua nhánh
TP-side và pass.

### Bug 2 — `TimeGMT()` không được mô phỏng trong Strategy Tester

`IsWithinSession()` (Gate 6) và `UpdateDailyLossTracking()` (Gate 7) đều dùng `TimeGMT()`.
Nhưng tester **không mô phỏng** hàm này:

| Nền tảng | `TimeGMT()` trong tester |
|----------|--------------------------|
| MT4 | Giờ đồng hồ PC thật — hoàn toàn không liên quan bar đang mô phỏng |
| MT5 | Bám theo server time, không phải thời điểm của bar |

Nên Gate 6 đánh giá **sai thời điểm**. Chạy backtest lúc 2 giờ sáng với session filter 07–20
thì Gate 6 từ chối **toàn bộ** — trông y hệt "EA không bao giờ trade". Mà `InpUseSessionFilter`
vừa được tao bật mặc định ở `.1-entryqual`, nên bug này mới lộ ra.

`UpdateDailyLossTracking()` cũng tính sai mốc reset ngày/tuần/tháng vì cùng lý do.

**Sửa**: `QEEA_TimeGMT()` — trong tester dùng `TimeCurrent()` (thời gian mô phỏng) trừ
`InpTesterGMTOffset`; live giữ nguyên `TimeGMT()`. Thêm input `InpTesterGMTOffset = 0` để khai
báo offset server→GMT của broker khi backtest (ví dụ broker EET mùa đông = 2).

> Nếu backtest vẫn lệch phiên, chỉnh `InpTesterGMTOffset` cho khớp broker. `SETTINGS DUMP` giờ
> in cả cửa sổ phiên lẫn offset để đối chiếu.

### Cách xác nhận

`SETTINGS DUMP` in `SessionFilter=true (7-20 GMT) TesterGMTOffset=0`. Trong log tester, gate log
giờ phải hiện `G6:PASS` trong khung giờ và `G10:PASS` ở bar có tín hiệu. Nếu vẫn `SKIP` toàn bộ,
đọc cột nào `FAIL` — mỗi gate có dòng `Gate N FAIL` riêng kèm số liệu.

---

## 4. Ngoài phạm vi (không sửa lần này)

### 4.1 Tham số DCA lệch với tài liệu chiến lược

`document/DCA_Scalping_Strategy.md` §5.2 khuyến nghị, nhưng code đang đặt khác:

| Tham số | Code | Doc khuyến nghị |
|---------|------|-----------------|
| `InpNegDCAMaxOrders` | `10` | `3` |
| `InpNegDCAMaxDDPct` | `15.0` | `5.0` |

Doc §13 lập luận: DD-cap cut ở 15% (~$1,500) ăn hết 20-40 trade thắng. Ở 5% thì cost per cut
giảm 3× và recovery nhanh hơn.

### 4.2 Positive DCA là dead code trên M15

Doc §5.1: spacing ATR×2.5 (~$20) vượt xa TP1 (~$6.4) → grid level không bao giờ trigger trước
khi basket đóng ở TP1. `InpUsePositiveDCA` vẫn đang `true`.

### 4.3 Nhóm C — Entry Zone system bị bỏ phí

Indicator tính đầy đủ multi-zone với reach probability và EV riêng từng zone
(`SLTP.mqh:1213` `CalculateEntryZones`, `Document_System/09_ENTRY_ZONES.md`):

```
Z1 Market: 2345.00  R:R 1:2.0  Reach 95%  EV +0.83R
Z2 PB-Z2:  2343.50  R:R 1:2.5  Reach 72%  EV +0.92R   ← EV cao hơn
Z3 PB-Z3:  2341.00  R:R 1:3.2  Reach 35%  EV +0.56R
```

Nhưng EA không tiếp cận được:
- Buffer contract 0–24 **không có zone price** (`Document_System/12_EA_EXPORT_CONTRACT.md`)
- GV bridge chỉ publish Entry/SL/TP1-3 (`QuantEdge_RSI.mq5:1115`)
- EA **không có lệnh chờ nào** — `grep "BUY_LIMIT|OP_BUYLIMIT|pending"` = 0 kết quả

→ EA luôn ăn Z1 Market (reach 95%, **EV thấp nhất**), zone pullback EV tốt hơn thì không với tới.

Cần: mở rộng GV bridge + contract doc, thêm `BUY_LIMIT`/`SELL_LIMIT` tại zone EV cao nhất, quản
lý hết hạn lệnh chờ. Đây là cải thiện lớn nhất về *chất lượng* điểm vào nhưng cũng tốn công nhất.

---

## 5. Tasklist

| # | Task | Trạng thái |
|---|------|-----------|
| T1 | Viết tài liệu này | ✅ |
| T2 | `#define BUF_PROB_SL 14` + helper `ReadSignalBuffer()` | ✅ |
| T3 | A1: `g_lastTradedSigTime` + persist GV + chặn arm 3 điểm | ✅ |
| T4 | A2: `IsSignalStillValid()` invalidate khi TP1 hit | ✅ |
| T5 | A4: Gate 3 + retry đọc buffer tại shift của signal | ✅ |
| T6 | A3: Gate 10 nhánh `else` + dùng `BUF_PROB_SL` | ✅ |
| T7 | A5: bỏ `priceShift`, giữ SL/TP cấu trúc, tính lại lot | ✅ |
| T8 | A6: `anyLegFilled` — chỉ consume khi fill thật | ✅ |
| T9 | B1–B3: Gate 5 mở rộng, Gate 11 (EV), Gate 12 (fill RR) | ✅ |
| T10 | A7: cảnh báo `OnInit` khi Gate 9 bật mà GV vắng | ✅ |
| T11 | B4: đổi default + input mới + bump `EA_BUILD_TAG` | ✅ |
| T12 | Đối chiếu `.mq4` ↔ `.mq5` | ✅ |
| T13 | Ghi changelog | ✅ |

---

## 6. Kiểm chứng

### 6.1 Trước khi compile

```bash
cd /f/Jimmii/Projects/RSI_Advanced
for f in Experts/QuantEdge_EA_Template.mq4 Experts/QuantEdge_EA_Template.mq5; do
  echo "=== $f ==="
  for pat in ReadSignalBuffer g_lastTradedSigTime IsSignalAlreadyTraded              InpUseStructuralSLTP g11_pass g12_pass anyLegFilled              "outside SL-TP1 band" BUF_PROB_SL priceShift; do
    printf "  %-24s %s
" "$pat" "$(grep -c "$pat" $f)"
  done
done
```

Kết quả mong đợi — hai file khớp nhau ở mọi marker, riêng `ReadSignalBuffer` lệch 1
(mq5 = 16, mq4 = 15) vì mq5 có thêm `AutoFixMissingTP()` mà MT4 không cần.

`priceShift` phải = **5** ở cả hai file, **không phải 0** — 5 lần đó nằm trong nhánh `else`
của `if(InpUseStructuralSLTP)`, tức đường rollback về hành vi cũ.

Mỗi input mới phải xuất hiện ≥ 2 lần (khai báo + nơi đọc), nếu không MT4/MT5 sẽ cảnh báo
"declared but never used":

```bash
for p in InpMaxSpreadPctOfTP1 InpUseGate11EV InpMinEV InpUseGate12FillRR          InpMinFillRR InpInvalidateOnTP1 InpUseStructuralSLTP; do
  printf "%-24s %s
" "$p" "$(grep -c "$p" Experts/QuantEdge_EA_Template.mq4)"
done
```

Đếm gate trong chuỗi `allPass` và trong `StringFormat` của gate log phải khớp (G1–G12).

### 6.2 Sau khi compile

Dòng đầu log khi attach phải in `Build=2026-09-24.1-entryqual`. Nếu vẫn tag cũ → đang test trên
binary chưa recompile.

### 6.3 Demo, `InpEnableAutoTrading = false` trước

`SETTINGS DUMP` phải phản ánh default mới. Gate log giờ có `G11`/`G12`. Đọc dòng
`Would BUY/SELL …` để xem entry/SL/TP/lot dự kiến mà không đặt lệnh thật.

### 6.4 Kiểm chứng từng fix qua log

| Fix | Dấu hiệu cần thấy |
|-----|-------------------|
| A1 | Sau khi basket đóng ở TP1: **không còn** `Signal found via GV bridge` cho cùng case/bar đó. Thay vào đó: `already traded — skip re-arm` |
| A2 | Giá vượt TP1 khi retry → `signal invalidated — TP1 reached`, và **không** có `RETRY fill` sau đó |
| A3 | Giá ra ngoài dải SL–TP1 → `Gate 10 FAIL (outside SL-TP1 band)`, `G10:FAIL` |
| A4 | Signal ở shift ≥ 2: `G3` có lúc `FAIL`; trước đây luôn `PASS` |
| A5 | `Would …` in SL **đúng bằng** giá trị indicator vẽ trên chart (không lệch theo giá hiện tại); lot thay đổi theo độ trôi |
| A6 | Giả lập reject → thấy `Order failed` mà **không** có `DCA state initialized` |
| A7 | Bật `InpUseEconCalGate` → `OnInit` in `Gate 9 enabled but GV missing` |
| B2/B3 | EV âm → `G11:FAIL`; vào muộn RR mỏng → `G12:FAIL` |

### 6.5 Live

`InpEnableAutoTrading = true`, quan sát ≥ 10 tín hiệu: mỗi arrow trên chart tương ứng **đúng
một** lệnh, giá mở lệnh nằm trong `InpPriceLocMaxPct` (25%) so với entry indicator công bố.
