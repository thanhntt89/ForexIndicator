# DCA Strategy Implementation Plan for QuantEdge EA

## Design Documents

- [DCA_Flowcharts.md](DCA_Flowcharts.md) — Flowcharts & sequence diagrams (Mermaid): OnTick flow, state machine, lifecycle diagrams cho positive/negative DCA, edge cases, combined scenarios
- [DCA_Function_Specs.md](DCA_Function_Specs.md) — Detailed function specifications: 17 functions với parameters, preconditions, postconditions, edge cases, MQ4 delta
- [DCA_Test_Matrix.md](DCA_Test_Matrix.md) — Test scenarios matrix: 40+ test cases chia 10 groups (backward compat, happy path, edge cases, combined, persistence, lot sizing, strategy tester)

## Context

EA hiện tại chỉ mở 1 position/direction (với optional TP1/TP2 60/40 split). Không có DCA, grid, hay martingale. Yêu cầu thêm 2 loại DCA:
- **Positive DCA**: thêm lệnh theo chiều thuận khi giá chạy đúng hướng → maximize profit
- **Negative DCA**: thêm lệnh theo chiều ngược khi giá chạy sai hướng → recovery basket

Các quyết định đã xác nhận:
- Positive DCA: chia đều Entry→TP1, max 4 lệnh (configurable)
- Negative DCA: max 5 lệnh, lot giảm dần (75%→50%→25%→25%), spacing ATR-based
- Đóng negative basket khi average entry breakeven
- DCA orders KHÔNG split TP1/TP2
- Hard drawdown cap bắt buộc

## Files cần sửa

- `Experts/QuantEdge_EA_Template.mq5` — primary implementation
- `Experts/QuantEdge_EA_Template.mq4` — mirror MQ4 (API khác, logic giống)

Không cần sửa indicator, include files, hay panel code.

## Implementation Steps

### Step 1: Constants & Input Parameters

Thêm sau `#define MAGIC_TP2_OFFSET 100000`:

```
#define MAGIC_POS_DCA_OFFSET  200000
#define MAGIC_NEG_DCA_OFFSET  300000
```

Magic scheme:
| Loại | Magic |
|------|-------|
| Original TP1 | `InpMagicNumber` |
| Original TP2 | `InpMagicNumber + 100000` |
| Positive DCA #i | `InpMagicNumber + 200000 + i` |
| Negative DCA #i | `InpMagicNumber + 300000 + i` |

Thêm 2 input groups sau "Trade Management":

```
// === Positive DCA ===
InpUsePositiveDCA     = false      // Enable positive DCA
InpPosDCAMaxOrders    = 4          // Max orders (1-10)
InpPosDCAHalfClosePct = 50.0       // Stop adding above this % of Entry→TP1

// === Negative DCA ===
InpUseNegativeDCA     = false      // Enable negative DCA
InpNegDCAMaxOrders    = 5          // Max orders (1-10)
InpNegDCATriggerPct   = 50.0       // Trigger at this % toward SL
InpNegDCAATRMult      = 0.5        // Spacing = ATR × multiplier
InpNegDCAMaxDDPct     = 5.0        // Hard drawdown cap (% balance)
```

Cả 2 feature default **OFF** → backward compatible.

### Step 2: Global State Variables

```
g_dcaActive          = false    // DCA tracking active
g_dcaDirection       = 0        // 1=BUY, -1=SELL
g_dcaOriginalEntry   = 0        // Actual fill price (market-adjusted)
g_dcaOriginalSL      = 0        // Adjusted SL
g_dcaOriginalTP1     = 0        // Adjusted TP1
g_dcaOriginalLot     = 0        // Total lot (pre-split)
g_dcaTP1HalfClosed   = false    // Half-close đã thực hiện chưa
g_dcaNegTriggered    = false    // Negative DCA đã trigger chưa
g_dcaNegTriggerPrice = 0        // Price tại thời điểm trigger
```

State persist qua GlobalVariables (key = `QE_DCA_{Symbol}_{Magic}_*`) → survive EA reload.

### Step 3: Helper Functions

1. **`IsOurMagic(magic)`** — check magic thuộc bất kỳ leg nào (original, TP2, pos DCA, neg DCA). Dùng để thay thế magic filter rải rác trong `UpdateDailyLossTracking()` và `OnTester()`.

2. **`CountDCAPositions(dcaType)`** — đếm positions theo DCA type.

3. **`HasAnyOriginalPosition()`** — check còn lệnh gốc (TP1 hoặc TP2).

4. **`HasAnyDCAPosition()`** — check còn bất kỳ DCA order nào.

5. **`CalculateBasketPnL()`** — tổng floating P&L tất cả positions của EA.

6. **`CalculateNegDCAAvgEntry()`** — weighted average entry (lot × price) cho original + neg DCA basket.

7. **`NegDCALotRatio(index)`** — trả ratio: idx 1→75%, 2→50%, 3+→25%.

8. **`SaveDCAState()` / `LoadDCAState()` / `ClearDCAState()`** — persist/restore/clear qua GlobalVariables.

### Step 4: Core DCA Logic

#### 4a. `ManagePositiveDCA()` — chạy mỗi tick

Logic flow:
1. Nếu chưa half-close VÀ giá đã chạm TP1 → gọi `ExecutePosDCAHalfClose()`
2. Nếu giá vượt 50% Entry→TP1 → dừng, không thêm lệnh
3. Tính grid: `spacing = (TP1 - Entry) / (maxOrders + 1)`
4. Với mỗi grid level chưa có lệnh: nếu giá đã vượt qua → mở lệnh
   - Lot = `g_dcaOriginalLot` (giữ nguyên)
   - SL = `g_dcaOriginalSL` (cùng SL lệnh gốc)
   - TP = 0 (managed bởi half-close logic)
   - Magic = `InpMagicNumber + 200000 + index`

#### 4b. `ExecutePosDCAHalfClose()` — khi giá chạm TP1

Logic flow:
1. Thu thập tất cả positive DCA positions (ticket + entry price)
2. Sort theo entry: BUY → entry cao nhất (ít lời nhất) đầu tiên
3. Đóng ceil(count/2) lệnh đầu (ít lời nhất)
4. Lệnh còn lại: move SL → `Entry_gốc + (TP1 - Entry_gốc) × 0.5` (khóa lời)

#### 4c. `ManageNegativeDCA()` — chạy mỗi tick

Logic flow:
1. **Drawdown cap check TRƯỚC** — nếu basket loss > X% balance → `CloseEntireBasket()` + `ClearDCAState()` → return
2. **Breakeven check** — nếu đã trigger VÀ có neg DCA orders VÀ giá đạt average entry → `CloseNegDCABasket()` (đóng original + neg DCA)
3. **Trigger check** — nếu chưa trigger: giá vượt 50% Entry→SL → set triggered = true
4. **Place orders** — spacing = `ATR(14) × InpNegDCAATRMult`, mỗi level chưa có lệnh:
   - Lot = `g_dcaOriginalLot × NegDCALotRatio(index)`
   - SL = 0, TP = 0 (managed bởi basket breakeven + drawdown cap)
   - Magic = `InpMagicNumber + 300000 + index`

#### 4d. `ManageDCA()` — wrapper, gọi từ OnTick()

- Auto-detect reset: nếu `g_dcaActive` nhưng không còn position nào → `ClearDCAState()`
- Gọi `ManagePositiveDCA()` rồi `ManageNegativeDCA()`

### Step 5: Integration vào OnTick()

```
void OnTick()
{
   ManageTrailing();    // existing
   ManageDCA();         // NEW — per-tick, trước bar guard
   UpdateDailyLossTracking();
   // ... existing bar guard, signal check, gate pipeline ...
}
```

Sau khi đặt lệnh thành công (cuối signal pipeline), khởi tạo DCA state:
```
g_dcaActive = true;
g_dcaDirection = direction;
g_dcaOriginalEntry = marketPrice;  // actual fill, not indicator entry
g_dcaOriginalSL = adjSL;
g_dcaOriginalTP1 = adjTP1;
g_dcaOriginalLot = lot;            // pre-split total
SaveDCAState();
```

### Step 6: Update Magic Filters

Thay magic filter trong `UpdateDailyLossTracking()` và `OnTester()`:

Before: `if(magic != InpMagicNumber && magic != magicTP2) continue;`
After: `if(!IsOurMagic(magic)) continue;`

### Không cần sửa

- **Gate 4 (`HasOpenPosition`)**: chỉ check magic TP1/TP2 range → DCA magic không match → OK
- **`ManageTrailing()`**: chỉ modify magic TP2 → DCA không bị ảnh hưởng → OK  
- **Close panel**: đã iterate ALL positions trên symbol → tự động bao gồm DCA → OK
- **Indicator code**: DCA hoàn toàn trong EA, indicator không biết → OK

### Step 7: MQ4 Mirror

Logic 100% giống MQ5. API delta:

| MQ5 | MQ4 |
|-----|-----|
| `CTrade.Buy/Sell()` | `OrderSend()` |
| `g_trade.PositionClose(ticket)` | `OrderClose(ticket, lots, price, slip)` |
| `PositionsTotal()` + `PositionGetTicket(i)` | `OrdersTotal()` + `OrderSelect(i, SELECT_BY_POS)` |
| `PositionGetDouble(POSITION_PROFIT)` | `OrderProfit()` |
| `SymbolInfoDouble(SYMBOL_BID)` | `Bid` |
| `CopyBuffer(g_hATR, ...)` | `iATR(Symbol(), 0, period, 0)` |
| `ulong magic/ticket` | `int magic/ticket` |

## Verification

1. **Compile** cả .mq5 và .mq4 không lỗi
2. **Backtest với DCA OFF** → kết quả phải giống hệt bản cũ (backward compat)
3. **Backtest với Positive DCA ON** → kiểm tra:
   - Lệnh DCA mở đúng grid levels
   - Dừng DCA khi vượt 50%
   - Half-close khi chạm TP1
   - SL move đúng vị trí 50%
4. **Backtest với Negative DCA ON** → kiểm tra:
   - Trigger đúng tại 50% Entry→SL
   - Lot giảm đúng ratio (75/50/25/25)
   - Basket close khi breakeven
   - Drawdown cap cut all khi vượt ngưỡng
5. **Backtest cả 2 ON** → không conflict
6. **Strategy Tester optimization** → OnTester() tính đúng PnL bao gồm DCA orders
