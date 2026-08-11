# DCA Strategy — Detailed Function Specifications

## Conventions

- **MQ5-first**: Specs viết cho MQ5. MQ4 delta ở cuối mỗi function.
- **Magic ranges**: TP1=`M`, TP2=`M+100000`, PosDCA=`M+200000+i`, NegDCA=`M+300000+i`
- **"Our positions"**: bất kỳ position nào có magic trong 4 ranges trên VÀ symbol match.

---

## 1. `IsOurMagic(long magic) → bool`

**Purpose**: Kiểm tra magic number có thuộc EA này không (bao gồm tất cả leg types).

**Parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `magic` | `long` | Magic number cần check |

**Returns**: `true` nếu magic thuộc bất kỳ range nào của EA.

**Logic**:
```
IF magic == InpMagicNumber                                    → true  (TP1 original)
IF magic == InpMagicNumber + MAGIC_TP2_OFFSET                 → true  (TP2 original)
IF magic >= InpMagicNumber + MAGIC_POS_DCA_OFFSET
   AND magic < InpMagicNumber + MAGIC_POS_DCA_OFFSET + 100    → true  (Positive DCA)
IF magic >= InpMagicNumber + MAGIC_NEG_DCA_OFFSET
   AND magic < InpMagicNumber + MAGIC_NEG_DCA_OFFSET + 100    → true  (Negative DCA)
ELSE → false
```

**Preconditions**: None.
**Postconditions**: Pure function, no side effects.
**Edge cases**:
- Magic = 0 → false
- Magic negative → false
- Magic trong khoảng 100001-199999 (giữa TP2 và PosDCA) → false

**MQ4 delta**: Parameter type `int` thay vì `long`. Casts thành `(int)`.

---

## 2. `CountDCAPositions(int dcaType) → int`

**Purpose**: Đếm số positions đang mở thuộc 1 DCA type cụ thể.

**Parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `dcaType` | `int` | `MAGIC_POS_DCA_OFFSET` hoặc `MAGIC_NEG_DCA_OFFSET` |

**Returns**: Số lượng positions match (0 nếu không có).

**Logic**:
```
count = 0
FOR each position in PositionsTotal():
    IF symbol != Symbol() → skip
    IF magic >= InpMagicNumber + dcaType
       AND magic < InpMagicNumber + dcaType + 100
       → count++
RETURN count
```

**Preconditions**: None.
**Postconditions**: Pure function, no side effects.
**Edge cases**:
- `dcaType` không phải POS/NEG offset → returns 0 (no match)
- Positions từ EA khác trên cùng symbol → filtered out by magic range

**MQ4 delta**: `OrdersTotal()`, `OrderSelect(i, SELECT_BY_POS, MODE_TRADES)`, `OrderSymbol()`, `OrderMagicNumber()`.

---

## 3. `HasAnyOriginalPosition() → bool`

**Purpose**: Check xem còn lệnh gốc nào không (TP1 hoặc TP2 leg).

**Parameters**: None.

**Returns**: `true` nếu tồn tại ít nhất 1 position với magic = `InpMagicNumber` hoặc `InpMagicNumber + MAGIC_TP2_OFFSET` trên Symbol() hiện tại.

**Logic**: Scan `PositionsTotal()`, check symbol + magic.

**MQ4 delta**: `OrdersTotal()` scan.

---

## 4. `HasAnyDCAPosition() → bool`

**Purpose**: Check xem còn bất kỳ DCA order nào không (positive hoặc negative).

**Parameters**: None.

**Returns**: `true` nếu tồn tại position với magic trong range `[M+200000, M+300099]`.

**Logic**: Scan tất cả positions, check magic range bao phủ cả pos và neg DCA.

**MQ4 delta**: `OrdersTotal()` scan.

---

## 5. `CalculateBasketPnL() → double`

**Purpose**: Tính tổng floating P&L (profit + swap) của tất cả positions thuộc EA.

**Parameters**: None.

**Returns**: Tổng P&L (dương = lời, âm = lỗ). 0.0 nếu không có positions.

**Logic**:
```
total = 0
FOR each position:
    IF symbol != Symbol() → skip
    IF !IsOurMagic(magic) → skip
    total += POSITION_PROFIT + POSITION_SWAP
RETURN total
```

**Preconditions**: None.
**Postconditions**: Pure function.
**Edge cases**:
- Commission không được tính trong floating P&L (MetaTrader chỉ tính commission khi close). Đây là limitation nhỏ — drawdown cap có thể trigger sớm hơn 1-2$ so với actual P&L.

**MQ4 delta**: `OrderProfit() + OrderSwap() + OrderCommission()` — MQ4 CÓ commission trong floating.

---

## 6. `CalculateNegDCAAvgEntry() → double`

**Purpose**: Tính weighted average entry price cho basket gồm original positions + negative DCA positions.

**Parameters**: None.

**Returns**: Volume-weighted average entry price. 0.0 nếu không có positions.

**Logic**:
```
totalLots = 0
weightedPrice = 0
FOR each position:
    IF symbol != Symbol() → skip
    IF magic is original (TP1 or TP2) OR magic is neg DCA → include
    ELSE → skip
    totalLots += volume
    weightedPrice += volume * openPrice
IF totalLots <= 0 → RETURN 0
RETURN weightedPrice / totalLots
```

**Preconditions**: Ít nhất 1 position phải tồn tại.
**Postconditions**: Pure function.
**Edge cases**:
- Positive DCA positions KHÔNG được tính vào average — chúng thuộc hệ thống riêng.
- Nếu original TP1 đã bị broker close (hit TP1) nhưng TP2 vẫn mở → TP2 vẫn được tính.
- Volume = 0 (impossible trong MT nhưng defensive) → return 0.

**MQ4 delta**: `OrderLots()`, `OrderOpenPrice()`.

---

## 7. `NegDCALotRatio(int index) → double`

**Purpose**: Trả về lot ratio cho negative DCA order thứ `index`.

**Parameters**:
| Param | Type | Description |
|-------|------|-------------|
| `index` | `int` | 1-based index (1 = first neg DCA order) |

**Returns**: Ratio (0.0 - 1.0).

**Logic**:
```
index 1 → 0.75  (75% of original lot)
index 2 → 0.50  (50%)
index 3+ → 0.25 (25%)
```

**Preconditions**: `index >= 1`.
**Postconditions**: Pure function.
**Edge cases**: `index <= 0` → treats as index 3+ → returns 0.25 (defensive).

**MQ4 delta**: Identical.

---

## 8. `SaveDCAState() → void`

**Purpose**: Persist toàn bộ DCA state vào terminal GlobalVariables.

**Parameters**: None.

**Logic**: Ghi 9 GlobalVariables với prefix `QE_DCA_{Symbol}_{Magic}_`:
- `Active` (0.0/1.0)
- `Direction` (1.0/-1.0)
- `Entry`, `SL`, `TP1`, `Lot` (double)
- `TP1HalfClosed` (0.0/1.0)
- `NegTriggered` (0.0/1.0)
- `NegTrigPrice` (double)

**Preconditions**: State variables đã được set.
**Postconditions**: GlobalVariables updated. Survive EA restart, chart change, terminal restart.
**Edge cases**: GlobalVariableSet() cannot fail (returns previous value or 0).

**MQ4 delta**: Identical — GlobalVariable API giống nhau.

---

## 9. `LoadDCAState() → void`

**Purpose**: Restore DCA state từ GlobalVariables khi EA khởi động lại.

**Parameters**: None.

**Logic**:
```
IF GlobalVariableCheck(prefix + "Active") is false → RETURN (no saved state)
Read all 9 GlobalVariables into g_dca* globals
```

**Preconditions**: None (safe to call anytime).
**Postconditions**: `g_dca*` variables populated if state existed, unchanged if not.
**Edge cases**:
- State tồn tại nhưng positions đã bị close bên ngoài (manual, panel, khác EA) → `ManageDCA()` sẽ detect và call `ClearDCAState()` ở tick tiếp theo.
- State corrupted (partial save, terminal crash) → worst case: some vars = 0. `ManageDCA()` sẽ detect no positions và reset.

**MQ4 delta**: Identical.

---

## 10. `ClearDCAState() → void`

**Purpose**: Reset toàn bộ DCA state về defaults VÀ xóa GlobalVariables.

**Parameters**: None.

**Logic**: Set tất cả `g_dca*` = default values. Xóa 9 GlobalVariables.

**Preconditions**: None.
**Postconditions**: DCA state = idle. GlobalVariables cleaned up.

**MQ4 delta**: Identical.

---

## 11. `ManagePositiveDCA() → void`

**Purpose**: Quản lý positive DCA grid — mở lệnh mới khi giá đạt grid levels, half-close khi TP1 hit, lock SL.

**Parameters**: None (reads from `g_dca*` globals).

**Preconditions**:
- `InpUsePositiveDCA == true`
- `g_dcaActive == true`
- `g_dcaOriginalEntry`, `g_dcaOriginalTP1`, `g_dcaOriginalSL`, `g_dcaOriginalLot` đã set

**Postconditions**:
- Có thể mở 0-N DCA orders (market orders, filled immediately)
- Có thể đóng nửa DCA orders (half-close)
- Có thể modify SL của remaining orders (trailing lock)
- `g_dcaTP1HalfClosed` có thể chuyển thành `true`
- `SaveDCAState()` được gọi khi state thay đổi

**Logic** (chi tiết):

```
1. Calculate entryToTP1 = g_dcaOriginalTP1 - g_dcaOriginalEntry
   IF |entryToTP1| < _Point → return (degenerate)

2. Get current price (BUY → ask, SELL → bid)

3. IF NOT g_dcaTP1HalfClosed:
   Check TP1 reached:
     BUY: bid >= g_dcaOriginalTP1
     SELL: ask <= g_dcaOriginalTP1
   IF reached → ExecutePosDCAHalfClose(), set flag, save, return

4. Check 50% cutoff:
   halfwayPrice = entry + entryToTP1 * (InpPosDCAHalfClosePct / 100)
   BUY: price > halfwayPrice → return (stop adding)
   SELL: price < halfwayPrice → return

5. Grid calculation:
   gridStep = entryToTP1 / (InpPosDCAMaxOrders + 1)
   // +1 vì entry là level 0, TP1 là level N+1
   // DCA orders tại: entry + 1*step, entry + 2*step, ..., entry + N*step

6. FOR idx = 1 TO InpPosDCAMaxOrders:
   a. dcaMagic = InpMagicNumber + MAGIC_POS_DCA_OFFSET + idx
   b. Scan positions: if magic == dcaMagic exists → skip (already placed)
   c. level = g_dcaOriginalEntry + idx * gridStep
   d. Check triggered:
      BUY: price >= level
      SELL: price <= level
      IF not triggered → skip
   e. Calculate lot:
      dcaLot = g_dcaOriginalLot
      Clamp to [minLot, maxLot], round to lotStep
   f. Place market order:
      SL = g_dcaOriginalSL, TP = 0
      Comment = "QE DCA+{idx}"
   g. Log result
```

**Edge cases**:
- **Giá gap qua nhiều levels cùng lúc** (weekend gap, news spike): Tất cả triggered levels sẽ được mở trong cùng 1 tick. Loop chạy tuần tự idx=1→N, mỗi lệnh placed independently. OK.
- **Margin không đủ**: `CTrade.Buy()` returns false, log error. Lệnh đó sẽ retry mỗi tick (magic check sẽ fail → attempt again). Không có retry counter — intentional: nếu margin freed up later, order sẽ được placed.
- **InpPosDCAMaxOrders = 0**: Loop không chạy. Chỉ có TP1 hit half-close logic hoạt động (nhưng không có DCA orders nào để close → noop).
- **InpPosDCAHalfClosePct = 100**: Cutoff = TP1 → positive DCA mở ở mọi grid level. Half-close vẫn hoạt động bình thường.
- **InpPosDCAHalfClosePct = 0**: Cutoff = entry → KHÔNG có DCA nào được mở (luôn beyond cutoff).

**MQ4 delta**: `Ask`/`Bid` globals, `OrderSend()`, `OrdersTotal()` scan.

---

## 12. `ExecutePosDCAHalfClose() → void`

**Purpose**: Đóng nửa số positive DCA orders (ít lời nhất trước), move SL remaining.

**Parameters**: None.

**Preconditions**:
- Ít nhất 1 positive DCA position tồn tại
- Giá đã chạm TP1

**Postconditions**:
- ceil(count/2) positions đóng (least profitable first)
- Remaining positions: SL modified to 50% of entry↔TP1
- Log mỗi action

**Logic**:
```
1. Collect: scan positions, filter magic range [M+200000, M+200099]
   Store arrays: dcaTickets[], dcaEntries[], count

2. IF count == 0 → return

3. Sort by entry price:
   BUY → descending (highest entry = least profitable first)
   SELL → ascending (lowest entry = least profitable first)
   Algorithm: selection sort (array max 10 elements)

4. closeCount = ceil(count / 2)

5. Close first closeCount:
   FOR i = 0 TO closeCount-1:
     g_trade.PositionClose(dcaTickets[i])
     Log success/failure

6. Move SL of remaining:
   newSL = g_dcaOriginalEntry + (g_dcaOriginalTP1 - g_dcaOriginalEntry) * 0.5
   Normalize to _Digits
   FOR i = closeCount TO count-1:
     Re-select position by ticket
     g_trade.PositionModify(dcaTickets[i], newSL, currentTP)
     Log
```

**Edge cases**:
- **count = 1**: closeCount = ceil(0.5) = 1 → close the only order. No remaining → no SL modify.
- **count = 2**: closeCount = 1 → close 1, keep 1.
- **count = 3**: closeCount = 2 → close 2, keep 1.
- **Close fails** (broker reject): Log error. Position remains open. Next TP1 check won't re-trigger (g_dcaTP1HalfClosed already set to true). User must close manually or via panel.
- **PositionModify fails** (SL inside spread): Log error. Position keeps old SL. Acceptable — user can modify manually.

**MQ4 delta**: `OrderSelect(ticket, SELECT_BY_TICKET)`, `OrderClose(ticket, OrderLots(), Bid/Ask, slip)`, `OrderModify()`. Arrays = `int[]` thay `ulong[]`.

---

## 13. `ManageNegativeDCA() → void`

**Purpose**: Quản lý negative DCA — drawdown cap, basket breakeven, trigger, order placement.

**Parameters**: None.

**Preconditions**:
- `InpUseNegativeDCA == true`
- `g_dcaActive == true`

**Postconditions**:
- Có thể close toàn bộ basket (drawdown cap hoặc breakeven)
- Có thể mở 0-N negative DCA orders
- Có thể update `g_dcaNegTriggered`, `g_dcaNegTriggerPrice`

**Logic** (chi tiết):

```
1. DRAWDOWN CAP (priority 1 — safety valve):
   basketPnL = CalculateBasketPnL()
   balance = AccountBalance
   IF InpNegDCAMaxDDPct > 0 AND balance > 0:
     maxLoss = balance * InpNegDCAMaxDDPct / 100
     IF basketPnL < 0 AND |basketPnL| >= maxLoss:
       Log "DRAWDOWN CAP HIT"
       CloseEntireBasket()
       ClearDCAState()
       RETURN

2. BREAKEVEN CHECK (priority 2):
   IF g_dcaNegTriggered AND CountDCAPositions(NEG) > 0:
     avgEntry = CalculateNegDCAAvgEntry()
     IF avgEntry > 0:
       BUY: bid >= avgEntry → breakeven reached
       SELL: ask <= avgEntry → breakeven reached
       IF reached:
         Log "BREAKEVEN"
         CloseNegDCABasket()  // close original + neg DCA only
         // Note: positive DCA positions NOT closed
         RETURN

3. TRIGGER CHECK (priority 3):
   entryToSL = g_dcaOriginalSL - g_dcaOriginalEntry  // negative for BUY
   triggerPrice = g_dcaOriginalEntry + entryToSL * (InpNegDCATriggerPct / 100)
   IF NOT g_dcaNegTriggered:
     BUY: ask <= triggerPrice → triggered
     SELL: bid >= triggerPrice → triggered
     IF triggered:
       Set g_dcaNegTriggered = true
       Set g_dcaNegTriggerPrice = triggerPrice
       SaveDCAState()
       Log "TRIGGERED"

4. PLACE ORDERS (priority 4):
   IF NOT g_dcaNegTriggered → return
   Read ATR via CopyBuffer(g_hATR)
   atrSpacing = ATR * InpNegDCAATRMult
   IF atrSpacing <= 0 → return

   price = BUY ? ask : bid
   FOR idx = 1 TO InpNegDCAMaxOrders:
     a. dcaMagic = InpMagicNumber + MAGIC_NEG_DCA_OFFSET + idx
     b. Check exists (magic scan) → skip if yes
     c. level = triggerPrice + (idx-1) * atrSpacing * adverseDirection
        BUY: level = triggerPrice - (idx-1) * atrSpacing  (further down)
        SELL: level = triggerPrice + (idx-1) * atrSpacing  (further up)
        NOTE: idx=1 → level = triggerPrice (first DCA at trigger point)
     d. Check triggered:
        BUY: price <= level
        SELL: price >= level
     e. Calculate lot:
        ratio = NegDCALotRatio(idx)
        dcaLot = g_dcaOriginalLot * ratio
        Clamp, round
     f. Place: SL=0, TP=0 (managed by basket logic)
        Comment = "QE DCA-{idx}"
     g. Log
```

**Edge cases**:
- **ATR = 0** (insufficient data, flat market): atrSpacing = 0 → return. No DCA placed. Will retry next tick when ATR becomes non-zero.
- **InpNegDCAATRMult very small** (e.g., 0.01): spacing rất nhỏ → nhiều orders cluster gần nhau. Max 5 orders nên acceptable, nhưng risk concentration cao.
- **Original position hit SL before neg DCA trigger**: `HasAnyOriginalPosition()` = false → `ManageDCA()` wrapper calls `ClearDCAState()`. Neg DCA never triggers. Correct.
- **Basket breakeven while drawdown cap also true**: Drawdown cap checked FIRST (priority 1). Breakeven checked second. In practice, if drawdown cap hasn't hit, breakeven is the preferred exit.
- **Price at exactly triggerPrice**: Trigger fires. First DCA order placed at triggerPrice. Subsequent at triggerPrice ± ATR*mult.
- **CloseNegDCABasket vs ClearDCAState**: `CloseNegDCABasket()` only closes original + neg DCA. Positive DCA orders survive. But `g_dcaActive` remains true (positive DCA may still have open positions). State reset happens via `ManageDCA()` wrapper when ALL positions gone.

**MQ4 delta**: `iATR()` thay `CopyBuffer()`. `Ask`/`Bid` globals. `OrderSend()`. `int` types.

---

## 14. `CloseNegDCABasket() → void`

**Purpose**: Đóng tất cả original positions (TP1 + TP2 leg) VÀ tất cả negative DCA positions. Positive DCA positions KHÔNG bị ảnh hưởng.

**Parameters**: None.

**Logic**:
```
FOR each position (reverse iterate):
    IF symbol != Symbol() → skip
    IF magic is original OR magic is neg DCA → close
    ELSE → skip (positive DCA preserved)
```

**Preconditions**: Ít nhất 1 position cần đóng.
**Postconditions**: Original + neg DCA positions closed. Positive DCA positions untouched.
**Edge cases**:
- Close fails → log error, continue to next. User sees partial close in log.
- Positive DCA positions vẫn mở → `ManageDCA()` wrapper vẫn chạy, sẽ manage half-close / SL lock nếu applicable. Tuy nhiên `g_dcaOriginalEntry/TP1` vẫn valid.

**MQ4 delta**: `OrderClose()`.

---

## 15. `CloseEntireBasket() → void`

**Purpose**: Emergency close — đóng TẤT CẢ positions thuộc EA (bao gồm cả positive DCA).

**Parameters**: None.

**Logic**:
```
FOR each position (reverse iterate):
    IF symbol != Symbol() → skip
    IF IsOurMagic(magic) → close
```

**Preconditions**: Drawdown cap triggered.
**Postconditions**: ALL EA positions closed. `ClearDCAState()` phải được gọi sau đó (by caller).

**MQ4 delta**: `OrderClose()`.

---

## 16. `ManageDCA() → void`

**Purpose**: Top-level wrapper — auto-reset detection + dispatch.

**Parameters**: None.

**Logic**:
```
IF neither positive nor negative DCA enabled → return
IF g_dcaActive:
    IF !HasAnyOriginalPosition() AND !HasAnyDCAPosition():
        Log "All positions closed — resetting"
        ClearDCAState()
        return
IF !g_dcaActive → return
ManagePositiveDCA()
ManageNegativeDCA()
```

**Preconditions**: None.
**Postconditions**: DCA state managed for this tick.

**Edge cases**:
- Both features disabled → immediate return (zero overhead).
- State active but ALL positions closed externally (panel, manual, different EA) → auto-reset. Clean.

**MQ4 delta**: Identical.

---

## 17. `DCA_GVPrefix() → string`

**Purpose**: Generate GlobalVariable key prefix unique to this EA instance + symbol.

**Returns**: `"QE_DCA_{Symbol}_{Magic}_"` e.g., `"QE_DCA_XAUUSD_20260805_"`

**MQ4 delta**: Identical.
