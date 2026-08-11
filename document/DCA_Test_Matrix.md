# DCA Strategy — Test Scenarios Matrix

## Test Environment

- **Backtest mode**: Every tick based on real ticks (most accurate)
- **Symbol**: XAUUSD (primary), EURUSD (secondary)
- **Timeframe**: M15 (primary), H1 (secondary)
- **Period**: Chọn period có cả trending và ranging market

## Abbreviations

- **POS**: Positive DCA
- **NEG**: Negative DCA
- **BE**: Breakeven
- **DD**: Drawdown
- **HC**: Half-close

---

## Group A: Backward Compatibility (DCA OFF)

| ID | Scenario | Config | Expected Behavior | Verify |
|----|----------|--------|--------------------|--------|
| A1 | Normal trading, both DCA OFF | `UsePosDCA=false, UseNegDCA=false` | Kết quả backtest PHẢI giống hệt bản cũ: cùng trades, cùng P&L, cùng custom criterion | So sánh report với build cũ |
| A2 | Only Positive DCA ON, no signal fires | `UsePosDCA=true` trên symbol không có signal | Zero DCA orders. ManageDCA() returns immediately. Không ảnh hưởng performance | Check Experts log: không có "DCA" entries |
| A3 | EA restart with DCA OFF | Chạy EA với DCA ON → tắt EA → bật lại với DCA OFF | GlobalVariables vẫn tồn tại nhưng ManageDCA() skip. Không error | Không crash, không stale orders |

---

## Group B: Positive DCA — Happy Path

| ID | Scenario | Config | Setup | Expected Behavior | Verify |
|----|----------|--------|-------|--------------------|----|
| B1 | Full grid fill + TP1 hit | `UsePosDCA=true, MaxOrders=4, HalfClosePct=50` | BUY signal, entry=2000, TP1=2100, SL=1950 | Grid: 2020, 2040 mở. 2060, 2080 blocked (>50%). Khi TP1 hit: close 1, keep 1, SL→2050 | Journal: 2 DCA orders placed, 1 closed at TP1, 1 SL modified |
| B2 | Price runs straight to TP1 | Same | Giá chạy thẳng 2000→2100 trong 1-2 bars | Có thể 0-4 DCA tùy speed. Half-close fires. Remaining gets locked SL | Check DCA count, half-close log |
| B3 | Price hits 50% then reverses to SL | Same | Giá lên 2050 (2 DCA placed) rồi quay xuống 1950 | DCA+1 (2020), DCA+2 (2040) mở. SL = 1950 (original). Khi SL hit: tất cả close | Journal: 2 DCA placed, all SL hit |
| B4 | MaxOrders=1 | `MaxOrders=1` | Entry=2000, TP1=2100 | Chỉ 1 grid level (2050). 1 DCA max. HC: close 1, keep 0 | 1 DCA order only |
| B5 | MaxOrders=10 (extreme) | `MaxOrders=10` | Entry=2000, TP1=2100 | Grid step = 100/11 ≈ 9pts. Max 5 placed (50% cutoff). HC: close 3, keep 2 | 5 DCA orders, proper HC |
| B6 | HalfClosePct=100 | `HalfClosePct=100` | Giá chạy từ entry đến gần TP1 | Tất cả grid levels available. DCA mở ở mọi level | No cutoff applied |
| B7 | HalfClosePct=0 | `HalfClosePct=0` | Any | Cutoff = entry → KHÔNG có DCA nào mở | Zero DCA orders |

---

## Group C: Positive DCA — Edge Cases

| ID | Scenario | Setup | Expected Behavior | Verify |
|----|----------|-------|--------------------|----|
| C1 | Weekend gap through grid | Friday close=2010, Monday open=2060 | DCA+1 (2020) và DCA+2 (2040) triggered cùng tick | 2 orders placed in same OnTick |
| C2 | TP1 hit before any DCA | Giá gap từ 2005 → 2105 (qua TP1) | TP1 leg auto-closed by broker. DCA orders may or may not exist. HC fires on whatever DCA exists (0 → noop) | No crash if count=0 |
| C3 | Margin insufficient | Account balance thấp, lot > free margin | DCA order fails (OrderSend error). Retry mỗi tick | Log "FAILED", retry attempts visible |
| C4 | Manual close 1 DCA | User đóng 1 DCA order thủ công | Remaining DCA orders continue. HC adjusts count. Magic-based tracking unaffected | Correct count in HC |
| C5 | SL modified externally | User kéo SL trên chart | DCA orders giữ SL cũ (g_dcaOriginalSL). Inconsistent nhưng acceptable | Log warning nếu có |
| C6 | SELL signal (reverse direction) | SELL entry=2100, TP1=2000, SL=2150 | Grid levels GIẢM: 2080, 2060. Cutoff ở 2050. TP1 hit khi giá ≤ 2000 | Mirror logic works |
| C7 | Spread spike during HC | Spread = 50 points tại thời điểm half-close | PositionClose may fail (requote). Log error. g_dcaTP1HalfClosed vẫn = true → không retry | Log error, no infinite loop |
| C8 | Very small TP1 distance | Entry=2000, TP1=2002 (2 points) | gridStep < _Point → degenerate guard triggers → return | No DCA placed |

---

## Group D: Negative DCA — Happy Path

| ID | Scenario | Config | Setup | Expected Behavior | Verify |
|----|----------|--------|-------|--------------------|----|
| D1 | Full neg DCA + breakeven | `UseNegDCA=true, MaxOrders=5, TriggerPct=50, ATRMult=0.5, MaxDDPct=5` | BUY 2000, SL=1950. Price drops to 1974 | Trigger at 1975. DCA-1 @ 1974 (75%), DCA-2..5 at ATR intervals. When avg entry reached → close basket | Journal: trigger, 5 DCA, breakeven close |
| D2 | Price drops then recovers quickly | Same | Price drops to 1970, triggers DCA-1, immediately bounces to 1990 | Only DCA-1 placed (75%). Avg entry ≈ 1994. BE reached quickly | 1 DCA, fast breakeven |
| D3 | Price drops slowly | Same, ATRMult=0.5, ATR=20 | Price drops 1pt/tick | DCA-1 @ 1975, DCA-2 @ 1965, DCA-3 @ 1955, DCA-4 @ 1945, DCA-5 @ 1935. All placed | 5 DCA at correct levels |
| D4 | Breakeven calculation accuracy | Same | 5 DCA placed. Check avg entry math | Original: 0.10@2000 + TP2: 0.04@2000 + DCA-1: 0.075@1974 + DCA-2: 0.05@1964 + DCA-3: 0.025@1954 + DCA-4: 0.025@1944 + DCA-5: 0.025@1934. Avg = Σ(lot×price)/Σ(lot) | Manual calculation matches |

---

## Group E: Negative DCA — Drawdown Cap

| ID | Scenario | Config | Setup | Expected Behavior | Verify |
|----|----------|--------|-------|--------------------|----|
| E1 | Drawdown cap triggers | `MaxDDPct=5`, balance=$10,000 | Basket floating loss reaches $500+ | "DRAWDOWN CAP HIT" log. CloseEntireBasket(). ClearDCAState() | ALL positions closed, state reset |
| E2 | Drawdown cap = 0 (disabled) | `MaxDDPct=0` | Basket loss grows indefinitely | No cap check. Only breakeven or manual close | Verify cap not checked |
| E3 | Drawdown near cap, then recovers | Basket loss = $490 (cap $500), price bounces | Cap NOT triggered ($490 < $500). Next tick: loss may be $480 → still OK | No false trigger |
| E4 | Cap hit with positive DCA also open | Both DCA on | Neg DCA causes drawdown cap | CloseEntireBasket() closes ALL including positive DCA | All gone, state cleared |

---

## Group F: Negative DCA — Edge Cases

| ID | Scenario | Setup | Expected Behavior | Verify |
|----|----------|-------|--------------------|----|
| F1 | Original SL hit before trigger | Price drops from 2000 to 1950 (SL) without passing 1975 slowly enough | If SL hit first (broker close), next tick: HasAnyOriginalPosition()=false → ClearDCAState(). Neg DCA never triggers | Clean state reset |
| F2 | Original TP1 hit while neg DCA active | Neg triggered, 2 DCA placed. Price bounces and hits TP1 (2100) | TP1 leg auto-closed by broker. TP2 still open. Neg DCA basket still tracked. Breakeven recalculated with fewer lots | Avg entry shifts, breakeven recalculated |
| F3 | ATR = 0 | Start of chart, insufficient bars | ManageNegativeDCA() returns at atrSpacing check. No DCA placed | Log nothing (silent skip) |
| F4 | ATR very large | ATR=200, mult=0.5 → spacing=100 | DCA-2 at triggerPrice-100, DCA-3 at triggerPrice-200 → likely below SL. Orders placed if price reaches those levels | Orders at extreme levels, may never fill |
| F5 | SELL direction | SELL 2000, SL=2050. TriggerPrice=2025 | Trigger when price ≥ 2025. DCA levels: 2025, 2035, 2045... | Mirror logic correct |
| F6 | All neg DCA placed, no breakeven | Max 5 DCA, price continues against. No drawdown cap | 5 orders open, all losing. No more DCA. Only breakeven check runs | 5 orders, wait for recovery or manual close |
| F7 | CloseNegDCABasket with pos DCA open | Pos DCA+1 exists, neg DCA breakeven hit | CloseNegDCABasket closes original + neg DCA ONLY. Pos DCA+1 survives | Pos DCA order still open |

---

## Group G: Combined Positive + Negative DCA

| ID | Scenario | Config | Setup | Expected Behavior | Verify |
|----|----------|--------|-------|--------------------|----|
| G1 | Price up then down (V-shape) | Both ON | BUY 2000. Price→2040 (2 pos DCA). Then→1970 (neg trigger). Then→2000 | Pos DCA: 2 orders placed. Neg DCA: triggers at 1975, places orders. Breakeven at avg. Pos DCA orders: SL at 1950 (original SL), still open | Both systems work independently |
| G2 | Neg DCA breakeven, then price to TP1 | Both ON | Neg basket closes at breakeven. Then price runs to TP1 | After neg close: original gone. g_dcaActive may still be true if pos DCA orders exist. Pos DCA HC fires at TP1 | Pos DCA lifecycle completes |
| G3 | Drawdown cap with both systems active | Both ON | Pos DCA 2 orders + neg DCA 3 orders. Total loss > 5% | CloseEntireBasket() closes ALL (original + pos + neg). ClearDCAState() | Total cleanup |
| G4 | Price oscillates around entry | Both ON | 2000→2030→1970→2020→1960→2000... | Pos DCA: places orders as levels hit. Neg DCA: may trigger if hits 1975. Complex interaction but each system checks independently | No double-counting, no conflict |

---

## Group H: State Persistence

| ID | Scenario | Setup | Expected Behavior | Verify |
|----|----------|-------|--------------------|----|
| H1 | EA restart mid-DCA | DCA active, 2 orders open. Remove EA, re-add | LoadDCAState() restores. ManageDCA() continues. New DCA orders placed if levels reached | State restored from GlobalVariables |
| H2 | Chart change and back | Switch to different TF then back | OnDeinit() saves. OnInit() loads. State matches | Continuous operation |
| H3 | Terminal restart | Close terminal, reopen | GlobalVariables persist. OnInit() loads. DCA resumes | State survives terminal restart |
| H4 | Manual GlobalVariable delete | Delete QE_DCA_* from GlobalVariables window | LoadDCAState() finds no vars → g_dcaActive remains false. ManageDCA() detects positions exist but state is idle → positions orphaned | User must close manually. Acceptable |
| H5 | Corrupted state (partial save) | Kill terminal during SaveDCAState() | Some vars saved, some not. Partial state loaded | ManageDCA() may detect inconsistency (active=true but entry=0) → positions exist → continues. Worst case: DCA logic uses stale values. Low risk |

---

## Group I: Strategy Tester Specific

| ID | Scenario | Config | Expected Behavior | Verify |
|----|----------|--------|--------------------|----|
| I1 | Open prices mode | Backtest with "Open prices" | DCA orders placed at bar-open. Grid levels may be skipped if price gaps intra-bar. HC fires at first bar where TP1 crossed | Fewer DCA orders than "Every tick" |
| I2 | Optimization | Optimize InpPosDCAMaxOrders [1-8] | OnTester() includes DCA orders in PnL calculation via IsOurMagic() | Custom criterion reflects DCA impact |
| I3 | Visual mode | Visual backtest | DCA orders visible on chart. Comment shows "QE DCA+1", "QE DCA-2" etc | Visual confirmation of grid levels |
| I4 | Multi-symbol optimization | Optimize on XAUUSD + EURUSD | Different ATR → different grid spacings. GlobalVariable keys include Symbol → no conflict | Independent per symbol |

---

## Group J: Lot Sizing

| ID | Scenario | Config | Expected Behavior | Verify |
|----|----------|--------|-------|-------|
| J1 | Pos DCA lot = original | Original lot=0.10 | All pos DCA = 0.10 | Journal lot sizes |
| J2 | Neg DCA lot decreasing | Original lot=0.10 | DCA-1=0.075, DCA-2=0.05, DCA-3=0.025, DCA-4=0.025, DCA-5=0.025 | Journal lot sizes |
| J3 | Lot clamped to minLot | Original lot=0.01 (minimum) | Neg DCA-3: 0.01*0.25=0.0025 → clamped to minLot=0.01 | All DCA ≥ minLot |
| J4 | Lot clamped to maxLot | Original lot=0.90, MaxLotSize=1.0 | Pos DCA lot=0.90 → OK. If original was 1.5 → clamped to 1.0 | Never exceeds maxLot |
| J5 | Lot step rounding | Broker lotStep=0.01 | All lots rounded down to 0.01 step | No fractional lots |

---

## Execution Checklist

Mỗi test group cần verify:
- [ ] **Journal log**: Đúng messages tại đúng thời điểm
- [ ] **Position count**: Đúng số lệnh mở/đóng
- [ ] **Magic numbers**: Đúng range cho mỗi type
- [ ] **SL/TP values**: Đúng theo spec
- [ ] **Lot sizes**: Đúng ratio, clamped correctly
- [ ] **State variables**: g_dca* values correct
- [ ] **GlobalVariables**: Persist/load/clear đúng
- [ ] **No crash**: Không access violation, division by zero
- [ ] **Performance**: OnTick() không lag (< 1ms per tick)
