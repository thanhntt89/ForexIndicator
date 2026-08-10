# Sprint 6 — File 2: `Include/QuantEdge/Core/Globals.mqh`

> **Action:** MODIFY (+7 lines)
> **Status:** DONE

---

## Business Purpose

Fixed-size storage cho tất cả virtual positions (live + historical). Dùng circular buffer thay vì growable array để tick-rate updates không bao giờ phải trả chi phí `ArrayResize()`.

---

## Data Flow

```
VP_AddPosition() [File 4]
  ├─ Ghi VirtualPosition vào g_virtualPositions[slot]
  ├─ Tăng g_vpCount hoặc advance g_vpWriteHead
  │
UpdateVirtualPositions_Tick() [File 4]
  ├─ Loop i = 0..g_vpCount, xử lý mỗi position
  │
CalculateVirtualPerf() [File 8]
  └─ Loop i = 0..g_vpCount, tính metrics
```

---

## Globals Added

```mql4
#define MAX_VIRTUAL_POS 200
VirtualPosition g_virtualPositions[MAX_VIRTUAL_POS];
int             g_vpCount     = 0;   // positions currently occupying slots
int             g_vpWriteHead = 0;   // circular overwrite pointer
```

---

## Design Decisions

1. **200 slots**: ~5 zones/signal × 40 signals = 40 signals of virtual history retained. Đủ cho phân tích trên 1 symbol/TF.
2. **Circular buffer**: khi `g_vpCount == MAX_VIRTUAL_POS`, `VP_AddPosition()` ưu tiên recycle resolved slot trước; nếu không có, overwrite tại `g_vpWriteHead` và advance pointer.
3. **Fixed array, KHÔNG `ArrayResize`**: tick-rate loop (XAUUSD M1 ~300 ticks/min × 200 positions) cần O(1) allocation. `ArrayResize` sẽ gây micro-lag.
4. **`g_vpWriteHead` tách riêng khỏi `g_vpCount`**: `g_vpCount` chỉ tăng lên MAX rồi dừng; `g_vpWriteHead` wrap around khi cần overwrite.
