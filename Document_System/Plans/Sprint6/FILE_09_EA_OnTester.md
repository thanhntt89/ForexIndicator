# Sprint 6 — File 9: `Experts/QuantEdge_EA_Template.mq4` + `.mq5`

> **Action:** MODIFY (+36 lines MQ4, +48 lines MQ5)
> **Status:** DONE

---

## Business Purpose

Cho phép MT4/MT5 Strategy Tester optimizer target custom fitness function (`EV × √N`) thay vì raw profit. Tránh optimizer chọn parameter sets "lucky" nhưng ít trades.

User chọn "Custom max" trong Strategy Tester settings (manual step, không code).

---

## Data Flow

```
Strategy Tester chạy backtest
  └─ OnTester() (gọi 1 lần khi test pass kết thúc)
       ├─ Đọc lịch sử trades từ platform API
       ├─ Tính wins, losses, totalProfit, totalLoss
       ├─ Tính EV = WR × avgWin - (1-WR) × avgLoss
       └─ Return EV × sqrt(N) → platform dùng làm optimization criterion
```

**KHÔNG đọc `g_virtualPositions[]`** — đó là indicator-side state. EA là program riêng, dùng platform's own order/deal history.

---

## Input

### MQ4 (`OrdersHistoryTotal` pattern)
```mql4
for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
{
   if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
   if(OrderSymbol() != Symbol()) continue;
   int mag = OrderMagicNumber();
   if(mag != InpMagicNumber && mag != magicTP2) continue;
   if(OrderType() > OP_SELL) continue;   // skip pending/balance
   double pnl = OrderProfit() + OrderSwap() + OrderCommission();
   // classify win/loss
}
```

### MQ5 (`HistoryDealsTotal` pattern — reuse `UpdateDailyLossTracking()` loop shape)
```mql5
HistorySelect(0, TimeCurrent());
for(int i = 0; i < HistoryDealsTotal(); i++)
{
   ulong dealTicket = HistoryDealGetTicket(i);
   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT) continue;   // chỉ closing deals
   string dealSym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(dealSym != Symbol()) continue;
   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(dealMagic != (long)InpMagicNumber && dealMagic != (long)magicTP2) continue;
   double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
               + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
               + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   // classify win/loss
}
```

---

## Output

```mql4
double OnTester()
{
   // ... aggregate history ...
   int n = wins + losses;
   if(n == 0) return(-999);   // degenerate zero-trade → sort last

   double wr     = (double)wins / n;
   double avgWin = (wins > 0) ? totalProfit / wins : 0;
   double avgLos = (losses > 0) ? totalLoss / losses : 0;
   double ev     = wr * avgWin - (1.0 - wr) * avgLos;

   return(ev * MathSqrt((double)n));   // rewards edge AND sample size
}
```

- `EV × √N`: positive EV + nhiều trades = high score. Negative EV → negative score. Zero trades → -999.
- `magicTP2 = InpMagicNumber + MAGIC_TP2_OFFSET`: filter cả partial TP2 close orders.

---

## Design Decisions

1. **`EV × √N`** thay vì raw profit: optimizer sẽ không chọn "1 trade lucky win = $5000" over "100 trades avg +$20 = $2000" vì sqrt(100) × 20 >> sqrt(1) × 5000.
2. **`return -999` khi zero trades**: ensures degenerate parameter sets sort last trong optimization results.
3. **PnL includes swap + commission**: `OrderProfit() + OrderSwap() + OrderCommission()` (MQ4) / `DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION` (MQ5) — realistic.
4. **MQ5 filters `DEAL_ENTRY_OUT` only**: counting entries would double-count. Match existing `UpdateDailyLossTracking()` pattern.
5. **`int magicTP2` (MQ4) vs `ulong magicTP2` (MQ5)**: platform-specific types, MQ5 uses `ulong` for magic numbers.
