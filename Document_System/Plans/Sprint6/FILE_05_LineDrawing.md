# Sprint 6 — File 5: `Include/QuantEdge/Display/LineDrawing.mqh`

> **Action:** MODIFY (+25 lines)
> **Status:** DONE

---

## Business Purpose

Render mỗi resolved virtual trade thành 1 trend line trên chart (entry → exit), để user visual audit historical performance trực tiếp trên chart.

---

## Data Flow

```
Tier 2: UpdateVirtualPositions_OnBar() [File 4]
  ├── needsRedraw == true
  │   ├── !historyDrawn → CreateHistoryLine()    ← lần đầu
  │   └──  historyDrawn → UpdateHistoryLineEnd()  ← update endpoint (TP level tăng)
  └── Clear needsRedraw = false
```

Chỉ gọi từ Tier 2 (bar close), KHÔNG BAO GIỜ từ Tier 1 (tick).

---

## Input

| Parameter | Type | Source |
|-----------|------|--------|
| `name` | string | `"VH_{signalTime}_Z{zoneIndex}"` từ `vp.objectName` |
| `t1, p1` | datetime, double | `activationTime`, `entryPrice` (entry point) |
| `t2, p2` | datetime, double | `outcomeTime` (or `TimeCurrent()`), `closePrice` (or current bid) |
| `clr` | color | `VP_GetOutcomeColor()`: green nếu any TP touched, red nếu pure SL/Reversal |
| `width, style` | int, int | Từ `InpHistoryLineWidth`, `InpHistoryLineStyle` |

---

## Output

1 `OBJ_TREND` per resolved position:
- `RAY = false` (không extend vô cực)
- `SELECTABLE = false` (không bị drag nhầm)
- `HIDDEN = true` (không clutter object list)
- `BACK = true` (vẽ phía sau price bars)

---

## Functions

### `CreateHistoryLine(name, t1, p1, t2, p2, clr, width, style)` — L303-316
- Guard: `if(InpEAMode || !InpShowHistoryLines) return;`
- Delete stale object cùng tên (defensive)
- Tạo `OBJ_TREND` với properties trên

### `UpdateHistoryLineEnd(name, t2, p2, clr)` — L318-324
- Guard: same
- Chỉ di chuyển endpoint (point 1) → line "grow" khi maxTPReached tăng
- Update color (có thể chuyển từ red → green nếu TP1 vừa hit)

---

## Design Decisions

1. **High-water-mark rule**: line endpoint = highest TP ever reached. Nếu position hit TP2 rồi SL → line VẪN ở TP2, color green. CSV ghi cả `MAX_TP_REACHED=2` và `FINAL_OUTCOME=SL`.
2. **Prefix "VH_"**: cho phép bulk cleanup via `DeleteObjectsByPrefix("VH_")`, nhưng history lines KHÔNG bị auto-delete trên `OnDeinit()` hoặc fullRecalc/TF switch — chúng là analysis data.
3. **Guard `InpEAMode`**: EA mode không có chart → skip tất cả object operations.
4. **`BACK = true`**: lines vẽ behind candles, không che price action.
