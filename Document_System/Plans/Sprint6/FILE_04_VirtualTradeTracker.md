# Sprint 6 — File 4: `Include/QuantEdge/Engine/VirtualTradeTracker.mqh`

> **Action:** NEW FILE (+305 lines)
> **Status:** DONE

---

## Business Purpose

Core simulation engine. Biến `SignalData` + `EntryZone[]` thành tracked virtual positions, cập nhật state khi giá di chuyển. **KHÔNG BAO GIỜ** chạm pipeline probability/signal-detection.

---

## Architecture: 2-Tier Split (bắt buộc)

Lý do: XAUUSD M1 tạo ~300 ticks/min × 200 positions = 60,000 iterations/min.

| Tier | Trigger | Cho phép | Cấm |
|------|---------|----------|------|
| **Tier 1** | Mỗi tick | Arithmetic comparisons, `O(1)` per position | Bất kỳ `Object*()` chart call |
| **Tier 2** | Bar close | Chart redraw (`CreateHistoryLine`/`UpdateHistoryLineEnd`), CSV flush | — |

Cầu nối giữa 2 tier: flags `needsRedraw` và `needsLog` — Tier 1 set true, Tier 2 xử lý rồi clear.

---

## Data Flow

```
OnNewSignal(sig) ─────────── Tạo 1-5 VirtualPositions từ signal + zones
      │
      ▼
VP_AddPosition(vp) ─────── Insert vào circular buffer
      │
      ▼ (every tick)
UpdateVirtualPositions_Tick(bid, ask)
  ├── VP_CheckActivation()  ── Pullback: activate khi price chạm zone
  ├── VP_CheckSLTP()         ── Check TP3→TP2→TP1→SL (high first)
  └── VP_UpdateMFE_MAE()     ── Track max excursion
      │
      ▼ (bar close only)
UpdateVirtualPositions_OnBar()
  ├── needsRedraw → CreateHistoryLine / UpdateHistoryLineEnd [File 5]
  ├── needsLog    → AppendVirtualTradeLog [File 3]
  └── FlushPendingCSVLogs() [File 3]
      │
VP_CloseAllBySignal(oldTime, bid, ask)
  └── Mark all old signal's positions → finalOutcome = -2 (Reversal)
```

---

## Functions (10 total)

### 1. `VP_AddPosition(VirtualPosition &pos)` — L16-36
- **Input:** filled `VirtualPosition` struct
- **Output:** slot index (int)
- **Logic:** (1) scan for resolved slot (`finalOutcome != 0`), (2) append if `g_vpCount < MAX`, (3) else overwrite `g_vpWriteHead` and advance

### 2. `OnNewSignal(const SignalData &sig)` — L42-92
- **Input:** `SignalData` (mới detect) + `g_entryZones[]` + `g_validZoneCount` (đã populated bởi pipeline)
- **Output:** 1 Market + up to 4 Pullback `VirtualPosition`s vào buffer
- **Logic:** Loop `z = 0..g_validZoneCount`, skip invalid zones. Market (z==0) pre-activated. Pullback (z>0) start inactive. SL/TP tính từ zone distances + `g_cfgTP2Mult`/`g_cfgTP3Mult`.

### 3. `VP_CheckActivation(idx, bid, ask)` — L97-117
- **Input:** position index + current bid/ask
- **Logic:** BUY pullback: activate khi `ask ≤ entryPrice`; SELL pullback: activate khi `bid ≥ entryPrice`

### 4. `VP_HitTP(idx, tpLevel, t, price)` — L122-138
- **Input:** position index, TP level (1-3), time, price
- **Logic:** High-water mark — chỉ update nếu `tpLevel > maxTPReached`. Record `tpTime[level]`. Khi `tpLevel == 3`: close position (`finalOutcome=1`, `closePrice`, `needsLog=true`).
- **Key rule:** TP1/TP2 = high-water mark only, KHÔNG close position. Chỉ TP3 close.

### 5. `VP_UpdateMFE_MAE(idx, bid, ask)` — L143-158
- **Input:** position index + bid/ask
- **Logic:** BUY: `excursion = bid - entry`; SELL: `excursion = entry - ask`. Track max positive (mfe) and max negative (mae).

### 6. `VP_CheckSLTP(idx, bid, ask)` — L163-200
- **Input:** position index + bid/ask
- **Logic:** Check TP3 → TP2 → TP1 → SL (high levels first, tránh skip khi price gap through). SL hit: `finalOutcome = -1`, `closePrice = checkPrice` (actual price, simulates slippage).
- **checkPrice:** BUY dùng `bid`, SELL dùng `ask`

### 7. `UpdateVirtualPositions_Tick(bid, ask)` — L205-216
- **Tier 1 entry point.** Loop tất cả pending positions, gọi CheckActivation → CheckSLTP → UpdateMFE_MAE.

### 8. `VP_GetOutcomeColor(const VirtualPosition &vp)` — L221-223
- **Output:** `InpColorVirtualTP` (green) nếu `maxTPReached > 0`, else `InpColorVirtualSL` (red)

### 9. `UpdateVirtualPositions_OnBar()` — L229-278
- **Tier 2 entry point.** Loop tất cả positions:
  - `needsRedraw` → vẽ/update history line (lookup ATR từ `g_signals[]`)
  - `needsLog` → ghi CSV row
  - Cuối: `FlushPendingCSVLogs()`

### 10. `VP_CloseAllBySignal(oldSignalTime, bid, ask)` — L284-302
- **Input:** old signal's datetime + current bid/ask
- **Logic:** Tất cả positions matching `oldSignalTime` và `finalOutcome == 0` → set `finalOutcome = -2` (Reversal), `closePrice = isBuy ? bid : ask`. Chỉ set `needsRedraw/needsLog` cho activated positions.

---

## Design Decisions

1. **Direct array access** (`g_virtualPositions[idx].field`): MQL4 `GetPointer()` chỉ works trên class objects, KHÔNG works trên struct arrays. Ban đầu code dùng `GetPointer()` → phải full rewrite.
2. **TP3 closes position**: ban đầu `VP_HitTP` chỉ update high-water mark mà KHÔNG close → positions pending vĩnh viễn. Review bug #1 (CRITICAL).
3. **bid/ask per direction** trong `VP_CloseAllBySignal`: BUY close tại bid, SELL close tại ask. Ban đầu dùng bid cho tất cả → review bug #2 (CRITICAL).
4. **SL closePrice = actual checkPrice**: spec ghi `pos.stopLoss` (idealized), nhưng actual price realistic hơn (simulates slippage). Accepted deviation.
5. **ATR lookup tại Tier 2** (không store trong VirtualPosition): tránh duplicate data. Reverse-scan `g_signals[]` matching `signalTime + caseNumber`.
6. **`(long)sig.signalTime`** trong objectName: tránh truncation từ `(int)` cast sau 2038.
