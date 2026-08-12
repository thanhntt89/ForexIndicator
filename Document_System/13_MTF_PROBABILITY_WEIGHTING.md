# 13 — MTF Probability Weighting: Strength-Aware Edge Adjustment

| Field        | Value                                    |
|-------------|------------------------------------------|
| Status      | DESIGN                                   |
| Author      | QuantEdge Team                           |
| Created     | 2026-08-12                               |
| Affects     | `ProbabilityEngine.mqh` Step 3, `MTFEngine.mqh`, `Config.mqh` |
| EA contract | New input `InpMTFEdgeMode` pass-through  |

---

## 1. Problem Statement

### Current: Binary Vote (Line 1265-1272, ProbabilityEngine.mqh)

```c
int agreeCount = 0;
for(int t = 0; t < g_mtfCount; t++)
{
   if(curSig.isBuySignal && g_mtfData[t].trend == 1) agreeCount++;
   if(!curSig.isBuySignal && g_mtfData[t].trend == -1) agreeCount++;
}
double alignRatio = ((double)agreeCount / (double)g_mtfCount) * 2.0 - 1.0;
_exMtfAdj = alignRatio * 0.03;
```

### Defects

| #  | Issue                          | Example                                                        |
|----|--------------------------------|----------------------------------------------------------------|
| D1 | **Binary vote** — trend is `{-1, 0, +1}`, no intensity | H4 RSI=52 (barely bullish) = H4 RSI=85 (very strong) — same 1 vote |
| D2 | **No quality weight** — TF with 200 historical signals = TF with 5 signals | M15 data-rich vs D1 data-sparse → same 1 vote |
| D3 | **Unused probability info** — system already computed `greenValue`, `strength` per TF but edge adjustment uses only `trend ∈ {-1, 0, +1}` | H1 prob 72% bullish vs M30 prob 51% bullish → same 1 vote |
| D4 | **Hard cap ±3%** — identical whether 2/6 TF weak-agree or 5/6 TF strong-agree | Distinction between "weak majority" vs "unanimous strong conviction" is lost |

### Internal inconsistency

`GetMTFContextScore()` (MTFEngine.mqh:295) already uses `strength = |green - 50| / 50` and TF hierarchy weights for the **Signal Score display** (12% weight in `SignalEngine`). But the place that **actually impacts probability** (edge adjustment in Step 3) uses the crude binary vote.

**Display is smarter than computation.**

---

## 2. Design: Two MTF Edge Modes

### 2.1 Enum

```c
// Config.mqh — after ENUM_PROB_MODE
enum ENUM_MTF_EDGE_MODE
{
   MTF_EDGE_STRENGTH  = 0,  // Strength-weighted (recommended)
   MTF_EDGE_BINARY    = 1   // Binary vote (legacy)
};
```

**Default = `MTF_EDGE_STRENGTH`** (Option 1). Legacy binary = Option 2 for backward compatibility.

### 2.2 Input

```c
// Config.mqh — inside "Multi-Timeframe" input group, after InpMinMTFAgreement
input ENUM_MTF_EDGE_MODE InpMTFEdgeMode = MTF_EDGE_STRENGTH; // MTF edge mode
```

### 2.3 EA pass-through

Both EA templates (MQ4/MQ5) must include a matching `Ind_MTFEdgeMode` input and pass it in the `iCustom()` parameter list at the correct ordinal position.

---

## 3. Option 1: Strength-Weighted (`MTF_EDGE_STRENGTH`)

### Formula

For each enabled higher-TF slot `i`:

```
direction_i  = isBuy ? trend_i : -trend_i           // +1 agree, -1 disagree, 0 neutral
strength_i   = |greenValue_i - 50| / 50             // [0.0, 1.0] — RSI distance from midline
tfWeight_i   = GetTFHierarchyWeight(timeframe_i)    // H4+=3.0, H1=2.0, M30=1.5, M15/M5=1.0

contribution_i = direction_i * strength_i * tfWeight_i
```

Aggregate:

```
weightedAlign = Σ contribution_i / Σ (strength_i * tfWeight_i)   // [-1.0, +1.0]
                                                                  // denominator uses absolute strength
                                                                  // so neutral TFs (strength≈0) don't dilute

_exMtfAdj = weightedAlign * 0.04                                  // cap ±4% (slightly wider than binary ±3%)
```

### Why ±4% cap (vs current ±3%)

The strength-weighted formula is **self-dampening**: when TFs are split or weak, `weightedAlign` naturally stays near 0. The old binary formula needed a tight ±3% cap because it couldn't distinguish conviction levels. With continuous weighting, a wider cap allows strong unanimous alignment to have proportionally more impact without risk of weak signals getting the same boost.

### Division-by-zero guard

If all TFs are neutral (`strength_i ≈ 0` for all `i`), the denominator approaches 0. Guard:

```c
double denominator = 0;
for(i) denominator += strength_i * tfWeight_i;
if(denominator < 0.01) { _exMtfAdj = 0; }   // all TFs are around RSI 50 — no conviction
```

### Properties

| Property | Binary (old) | Strength-weighted (new) |
|----------|-------------|------------------------|
| H4 RSI=85 bullish, signal=Buy | +1 vote | +1.0 × 0.70 × 3.0 = +2.10 |
| H4 RSI=52 bullish, signal=Buy | +1 vote | +1.0 × 0.04 × 3.0 = +0.12 |
| M15 RSI=30 bearish, signal=Buy | +1 vote against | -1.0 × 0.40 × 1.0 = -0.40 |
| D1 RSI=50 neutral (trend=0) | 0 vote | 0.0 × 0.00 × 3.0 = 0.00 |

**Key insight**: H4 at RSI 85 now has **17.5× more influence** than H4 at RSI 52, instead of identical influence.

---

## 4. Option 2: Binary Vote (`MTF_EDGE_BINARY`)

Exact current logic, unchanged. Preserved for:
- Backward compatibility / comparison testing
- Users who prefer simplicity
- Regression testing (verify new mode doesn't degrade existing results)

---

## 5. Implementation Plan

### 5.1 Files to modify

| File | Change |
|------|--------|
| `Include/QuantEdge/Core/Config.mqh` | Add `ENUM_MTF_EDGE_MODE`, `InpMTFEdgeMode` input |
| `Include/QuantEdge/Engine/MTFEngine.mqh` | Add `GetMTFEdgeAdjustment(bool isBuy)` function |
| `Include/QuantEdge/Engine/ProbabilityEngine.mqh` | Replace inline MTF block (L1263-1274) with call to `GetMTFEdgeAdjustment()` |
| `Experts/QuantEdge_EA_Template.mq4` | Add `Ind_MTFEdgeMode` input, pass in `iCustom()` |
| `Experts/QuantEdge_EA_Template.mq5` | Same as MQ4 |
| `sales/01_source_code/QuantEdge_RSI.mq4` | Sync (same Config.mqh include) |
| `sales/01_source_code/QuantEdge_RSI.mq5` | Sync (same Config.mqh include) |

### 5.2 New function: `GetMTFEdgeAdjustment()` (MTFEngine.mqh)

```c
double GetMTFEdgeAdjustment(bool isBuy)
{
   if(!InpShowMTF || g_mtfCount == 0) return(0.0);

   if(InpMTFEdgeMode == MTF_EDGE_BINARY)
   {
      // --- Legacy binary vote ---
      int agreeCount = 0;
      for(int t = 0; t < g_mtfCount; t++)
      {
         if(isBuy  && g_mtfData[t].trend ==  1) agreeCount++;
         if(!isBuy && g_mtfData[t].trend == -1) agreeCount++;
      }
      double alignRatio = ((double)agreeCount / (double)g_mtfCount) * 2.0 - 1.0;
      return(alignRatio * 0.03);
   }

   // --- Strength-weighted (default) ---
   double numerator   = 0.0;
   double denominator = 0.0;

   for(int t = 0; t < g_mtfCount; t++)
   {
      double direction = isBuy ? (double)g_mtfData[t].trend
                               : -(double)g_mtfData[t].trend;
      double strength  = MathAbs(g_mtfData[t].greenValue - 50.0) / 50.0;

      double w = 1.0;
      if(g_mtfData[t].timeframe >= TF_H4)       w = 3.0;
      else if(g_mtfData[t].timeframe >= TF_H1)  w = 2.0;
      else if(g_mtfData[t].timeframe >= TF_M30) w = 1.5;

      numerator   += direction * strength * w;
      denominator += strength * w;
   }

   if(denominator < 0.01) return(0.0);

   double weightedAlign = numerator / denominator;   // [-1.0, +1.0]
   return(weightedAlign * 0.04);                     // cap ±4%
}
```

### 5.3 ProbabilityEngine.mqh change (Step 3)

Replace lines 1263-1274:

```c
// Before (inline binary vote):
if(InpShowMTF && g_mtfCount > 0)
{
   int agreeCount = 0;
   ...
   _exMtfAdj = alignRatio * 0.03;
   edgeAdjustment += _exMtfAdj;
}

// After (delegate to MTFEngine):
_exMtfAdj = GetMTFEdgeAdjustment(curSig.isBuySignal);
edgeAdjustment += _exMtfAdj;
```

### 5.4 Config.mqh additions

After line 213 (`InpMinMTFAgreement`):

```c
input ENUM_MTF_EDGE_MODE InpMTFEdgeMode = MTF_EDGE_STRENGTH; // MTF edge adjustment mode
```

Enum definition before input groups (after `ENUM_PROB_MODE`):

```c
enum ENUM_MTF_EDGE_MODE
{
   MTF_EDGE_STRENGTH = 0,  // Strength-weighted (default)
   MTF_EDGE_BINARY   = 1   // Binary vote (legacy)
};
```

### 5.5 EA template changes

Both MQ4 and MQ5 EA templates:

1. Add input:
```c
input int Ind_MTFEdgeMode = 0;  // MTF Edge Mode (0=Strength, 1=Binary)
```

2. Pass in `iCustom()` parameter list at the correct ordinal position (after `InpMinMTFAgreement`).

> **Note**: MQ4 `iCustom()` uses positional params — the new input must be at the exact ordinal matching the indicator's input declaration order. MQ5 uses handle-based `iCustom()` with the same positional contract.

---

## 6. Explain Panel Impact

No structural change to `ExplainData` or `PanelDrawing.mqh`. The explain panel already shows:
- `edgeMTF` — the raw edge adjustment value
- `probAfterMTF` — probability after MTF adjustment

These values will naturally reflect the new formula when `MTF_EDGE_STRENGTH` is active. The label `"+ MTF"` remains accurate.

The panel will show **larger deltas** when TFs strongly agree (vs current flat ±3%) and **smaller deltas** when TFs are split or weak — which is the correct behavior.

---

## 7. Verification

### 7.1 Compile check
- Build MQ4 + MQ5 indicator and both EA templates without errors

### 7.2 Visual comparison
1. Load indicator with `MTF_EDGE_BINARY` — verify explain panel shows identical values to current build
2. Switch to `MTF_EDGE_STRENGTH` — verify:
   - When all HTFs strongly agree (e.g. all RSI > 60 for buy): MTF edge > old binary edge
   - When HTFs are split or weak: MTF edge ≈ 0 (smaller than old binary)
   - When all HTFs neutral (RSI ≈ 50): MTF edge = 0

### 7.3 Edge cases
- Only 1 HTF available (e.g. chart = H4, only D1 above): formula should still produce valid result
- All TFs neutral (trend = 0): result must be 0.0, not NaN
- greenValue = 0 or 100 (extreme RSI): strength = 1.0, valid

### 7.4 EA integration
- Verify `iCustom()` parameter ordinal matches after adding new input
- Test buffer reads still return correct values with new param in the list
