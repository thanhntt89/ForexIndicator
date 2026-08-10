# Sprint 6 — File 1: `Include/QuantEdge/Core/Structs.mqh`

> **Action:** MODIFY (+50 lines)
> **Status:** DONE

---

## Business Purpose

Định nghĩa data shape cho virtual trade — mỗi instance `VirtualPosition` = 1 vị thế mô phỏng (Market entry hoặc 1 Pullback zone) gắn với 1 signal thực. Tách riêng với `SignalData` vì 1 signal fan-out thành tối đa 5 virtual positions (1 Market + 4 Pullback zones).

`VirtualPerfMetrics` là output struct cho panel — chứa các metric tổng hợp (WR, PF, Sharpe, Sortino, MaxDD, EV) được tính từ toàn bộ `g_virtualPositions[]`.

---

## Data Flow

```
OnNewSignal() [File 4]
  ├─ Đọc SignalData + g_entryZones[]
  ├─ Tạo VirtualPosition, ghi vào g_virtualPositions[slot]
  │
VP_Check* functions [File 4]
  ├─ Mutate VirtualPosition mỗi tick (activation, MFE/MAE, SL/TP)
  │
AppendVirtualTradeLog() [File 3]
  ├─ Đọc const VirtualPosition& → ghi CSV
  │
CalculateVirtualPerf() [File 8]
  ├─ Loop g_virtualPositions[] → tính VirtualPerfMetrics
  └─ DrawPerfReport() hiển thị lên panel
```

---

## Struct: VirtualPosition (25 fields)

### Identity (set once at creation — composite key, KHÔNG dùng array index)

| Field | Type | Mô tả |
|-------|------|--------|
| `signalTime` | datetime | Thời điểm signal được detect |
| `signalCaseNum` | int | Case number (1-14) |
| `zoneIndex` | int | 0=Market, 1-4=Pullback Z2-Z5 |
| `entryType` | string | "Market", "PB-Zone2", ... (copy từ `EntryZone.zoneName`) |
| `entryPrice` | double | Giá entry (copy từ `EntryZone.price`) |
| `stopLoss` | double | SL tuyệt đối (tính từ `entryPrice ± slDistance`) |
| `takeProfit1/2/3` | double | TP1/2/3 tuyệt đối (TP2 = TP1 × g_cfgTP2Mult, TP3 = TP1 × g_cfgTP3Mult) |
| `isBuy` | bool | Hướng (copy từ `sig.isBuySignal`) |
| `sessionName` | string | "Asian"/"London"/"NewYork"/"Off-session" |

### Lifetime state (mutated tick-by-tick)

| Field | Type | Mô tả |
|-------|------|--------|
| `isActivated` | bool | Market: true ngay lập tức; Pullback: true khi price chạm zone |
| `activationTime` | datetime | Thời điểm kích hoạt |
| `activationBar` | int | (unused, kept for struct compat — `ZeroMemory` = 0) |
| `maxTPReached` | int | 0-3, monotonic high-water mark (KHÔNG BAO GIỜ giảm) |
| `tpTime[4]` | datetime[] | Index 0 unused, [1..3] = thời điểm TP level đầu tiên được chạm |
| `finalOutcome` | int | 0=pending, 1=TP3 hit, -1=SL hit, -2=Reversal |
| `outcomeTime` | datetime | Thời điểm kết thúc |
| `closePrice` | double | Giá exit thực tế (SL dùng actual price, TP3 dùng checkPrice) |
| `mfe` | double | Max Favorable Excursion (price units từ entryPrice) |
| `mae` | double | Max Adverse Excursion (price units từ entryPrice) |

### Tier 1 → Tier 2 handoff flags

| Field | Type | Mô tả |
|-------|------|--------|
| `needsRedraw` | bool | Tier 1 set true → Tier 2 vẽ/cập nhật history line |
| `needsLog` | bool | Tier 1 set true → Tier 2 ghi CSV row |
| `historyDrawn` | bool | true = đã `CreateHistoryLine()`, dùng `UpdateHistoryLineEnd()` cho lần sau |
| `objectName` | string | "VH_{signalTime}_Z{zoneIndex}" — unique OBJ_TREND name |

---

## Struct: VirtualPerfMetrics (12 fields)

| Field | Type | Mô tả |
|-------|------|--------|
| `totalTrades` | int | Tổng positions đã resolved + activated + slDist > 0 |
| `wins` | int | Positions có pnl > 0 |
| `losses` | int | Positions có pnl ≤ 0 |
| `winRate` | double | wins / totalTrades × 100 |
| `profitFactor` | double | grossProfit / grossLoss |
| `sharpe` | double | mean(R-returns) / std(R-returns), per-trade (KHÔNG annualize) |
| `sortino` | double | mean(R-returns) / downside_deviation, per-trade |
| `maxDrawdownPct` | double | Peak-to-trough drawdown trên cumulative PnL curve (%) |
| `avgRR` | double | Mean TP1-distance/SL-distance cho winning trades |
| `evPerTradeR` | double | Mean R-return (= expected value per trade in R units) |
| `marketWinRate` | double | WR chỉ cho zoneIndex == 0 |
| `pullbackWinRate` | double | WR chỉ cho zoneIndex > 0 |

---

## Design Decisions

1. **Composite key** (`signalTime + signalCaseNum + zoneIndex`) thay vì array index — vì circular buffer tái sử dụng slot, index không ổn định.
2. **`tpTime[4]` với index 0 unused** — truy cập trực tiếp `tpTime[1]` cho TP1, tránh off-by-one.
3. **`activationBar` giữ lại nhưng unused** — đã bỏ assignment ở `VirtualTradeTracker.mqh`, `ZeroMemory` set = 0. Giữ field trong struct để tránh breaking change nếu có code ngoài reference.
4. **Tách `VirtualPerfMetrics` thành struct riêng** — `CalculateVirtualPerf()` return by value, panel code không cần biết internal loop logic.
