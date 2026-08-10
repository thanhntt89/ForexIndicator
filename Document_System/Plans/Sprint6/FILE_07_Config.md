# Sprint 6 — File 7: `Include/QuantEdge/Core/Config.mqh`

> **Action:** MODIFY (+12 lines)
> **Status:** DONE

---

## Business Purpose

User-facing on/off switches và cosmetic settings cho virtual trade history. Không chứa logic — chỉ là inputs.

---

## Position in Config

Sau group **Entry Zones** (kết thúc ở `InpZone5Color`), trước group **Info Panel** (bắt đầu ở `inp_grp_panel`).

---

## Inputs Added (7)

```mql4
input string inp_grp_vhist         = "========== Virtual Trade History =========="; // ---
input bool   InpEnableVirtualTrades = true;            // Enable virtual trade tracking
input bool   InpShowHistoryLines    = true;            // Draw history lines on chart
input color  InpColorVirtualTP      = clrLime;         // TP line color
input color  InpColorVirtualSL      = clrRed;          // SL line color
input int    InpHistoryLineWidth    = 1;               // History line width
input int    InpHistoryLineStyle    = 0;               // History line style (0=solid)
input bool   InpShowVirtualPerf     = true;            // Show virtual performance on panel
```

Lines: 170-177

---

## Usage Map

| Input | Used by | Effect when OFF |
|-------|---------|-----------------|
| `InpEnableVirtualTrades` | File 4, File 6 (main gate) | Zero overhead — entire virtual trade engine skipped |
| `InpShowHistoryLines` | File 5 (`CreateHistoryLine`/`UpdateHistoryLineEnd`) | Lines not drawn, but positions still tracked + CSV still written |
| `InpColorVirtualTP` | File 4 (`VP_GetOutcomeColor`) → File 5 | — |
| `InpColorVirtualSL` | File 4 (`VP_GetOutcomeColor`) → File 5 | — |
| `InpHistoryLineWidth` | File 4 (`UpdateVirtualPositions_OnBar`) → File 5 | — |
| `InpHistoryLineStyle` | File 4 (`UpdateVirtualPositions_OnBar`) → File 5 | — |
| `InpShowVirtualPerf` | File 8 (`DrawPerfReport` guard) | Panel section hidden |

---

## Design Decisions

1. **`InpEnableVirtualTrades` = master switch**: khi false, KHÔNG call `UpdateVirtualPositions_Tick()` → zero tick overhead. CSV cũng không mở.
2. **`InpShowHistoryLines` tách riêng**: có thể muốn track + log CSV mà không vẽ lines (giảm chart clutter).
3. **`InpShowVirtualPerf` tách riêng**: panel section có thể heavy khi nhiều trades → cho phép tắt independent.
4. **Default tất cả = true**: Sprint 6 là opt-in qua indicator settings, mặc định bật cho user trải nghiệm ngay.
