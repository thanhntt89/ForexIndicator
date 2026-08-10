# Sprint 6 — File 8: `Include/QuantEdge/Display/PanelDrawing.mqh`

> **Action:** MODIFY (+150 lines)
> **Status:** DONE

---

## Business Purpose

Hiển thị virtual-trade performance (WR, PF, Sharpe, Sortino, MaxDD, EV, Market vs Pullback WR) trực tiếp trên panel. User không cần mở CSV/Python report để đánh giá strategy đang chạy thế nào.

---

## Data Flow

```
DrawInfoPanel() / DrawManualPanel()
  └─ DrawPerfReport(px, pad, fs, cy, compact)
       └─ CalculateVirtualPerf()
            └─ Loop g_virtualPositions[0..g_vpCount]
                 ├─ Filter: signalTime > 0, finalOutcome != 0, isActivated, slDist > 0
                 ├─ Classify: pnl > 0 → win, else → loss
                 ├─ Accumulate: grossProfit, grossLoss, R-returns, cumPips
                 └─ Return VirtualPerfMetrics
```

---

## Input

| Source | Type | Mô tả |
|--------|------|--------|
| `g_virtualPositions[]` | `VirtualPosition[200]` | Toàn bộ circular buffer |
| `g_vpCount` | int | Slots occupied |

Đọc trực tiếp, KHÔNG cache — panel redraws đã throttled 200ms.

---

## Output

### Full panel (5 lines, `compact = false`)
```
--- Virtual Perf ---
Trades: 47 (32W 15L) | WR: 68.1%
PF: 2.14 | Sharpe: 1.85 | Sortino: 2.31
MaxDD: -3.2% | Avg RR: 1.8 | EV: +0.42R
Market: 72% WR | Pullback: 61% WR
```

### Compact panel (2 lines, `compact = true`)
```
47 trades 68%WR PF:2.14 DD:-3.2%
Mkt:72% PB:61% EV:+0.42R
```

---

## Functions

### `CalculateVirtualPerf()` — L198-288
Returns `VirtualPerfMetrics` struct.

**Metrics:**

| Metric | Formula | Notes |
|--------|---------|-------|
| Win Rate | `wins / totalTrades × 100` | `isWin = (pnl > 0)`, KHÔNG dùng `maxTPReached` |
| Profit Factor | `grossProfit / grossLoss` | Guard: `grossLoss > 0` |
| Sharpe | `mean(R) / std(R)` | Per-trade R-returns, KHÔNG annualize (không phải daily returns) |
| Sortino | `mean(R) / downside_dev(R)` | `downside_dev = sqrt(sum(neg_R²) / N)` |
| Max Drawdown % | `maxDD / peakPips × 100` | Peak-to-trough trên cumulative PnL. All-losing → 100% |
| Avg R:R | `mean(TP1_dist / SL_dist)` cho winning trades | Planned RR, không realized |
| EV/trade | `meanR` (= mean of R-returns) | Positive = profitable edge |
| Market WR | WR cho `zoneIndex == 0` | — |
| Pullback WR | WR cho `zoneIndex > 0` | — |

### `DrawPerfReport(px, pad, fs, &cy, compact)` — L290-349
- Guard: `if(!InpShowVirtualPerf || IsBacktestMode()) return;`
- Guard: `if(g_vpCount == 0 || pm.totalTrades == 0) return;`
- Call `CalculateVirtualPerf()`, format & display qua `CreateTextLabel()`

---

## Wiring

| Call site | Panel type | compact |
|-----------|------------|---------|
| `DrawInfoPanel()` sau `DrawRiskSummary()` | Full | false |
| `DrawManualPanel()` sau `DrawRiskSummary()` | Manual | true |

---

## Design Decisions & Review Fixes

1. **`isWin = (pnl > 0)`** thay vì `maxTPReached > 0`: Reversal với partial TP (TP1 touched nhưng exit ở loss) không nên count là win hay add negative pnl vào grossProfit. Review bug (MEDIUM).
2. **`totalTrades++` SAU `slDist` guard**: trades với `slDist == 0` bị skip entirely, không count vào totalTrades. Review bug (CRITICAL).
3. **KHÔNG annualize Sharpe/Sortino**: `sqrt(252)` chỉ đúng cho daily returns. Đây là per-trade R-returns, trading frequency không cố định. Review bug (MEDIUM).
4. **MaxDD all-losing = 100%**: khi `peakPips == 0` và `maxDD > 0` (tất cả trades thua), show 100% thay vì 0%. Review fix (LOW).
5. **`IsBacktestMode()` guard**: Strategy Tester cần speed, panel perf stats vô nghĩa trong backtest. Match pattern của `DrawRiskSummary()`.
