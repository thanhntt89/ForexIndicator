# Design: Data Quality Metrics for Probability Engine

**Version**: V11.30
**Date**: 2026-06-25
**Status**: APPROVED

---

## 1. Problem Statement

Panel hien tai hien thi `Prob [n=205]` va `(39/205)` nhung trader khong biet:
- 205 mau gom bao nhieu **signal that** (Tier 1+2) vs **ATR scan** (Tier 3)?
- Thoi gian bao phu bao lau? Signal cu nhat bao nhieu ngay?
- Weighting co qua tap trung vao vai mau khong?
- nEff / raw count ratio → weight "nghien" bao nhieu?

Tier 3 (ATR-based scan) khong co signal conditions — chi filter theo RSI range + angle tier.
Win rate Tier 3 thuong thap hon signal that. Khi Tier 3 chiem da so, xac suat bi keo xuong
hoac thoi phong len khong phan anh chat luong tin hieu that.

## 2. Data Quality Metrics (7 metrics)

| # | Metric | Variable | Type | Description |
|---|--------|----------|------|-------------|
| 1 | Tier 1 raw count | rawCountT1 | int | So signal that cung case, cung direction |
| 2 | Tier 2 raw count | rawCountT2 | int | So signal that khac case, cung direction |
| 3 | Tier 3 count | countT3 | int | So bar tuong tu RSI tu ATR scan |
| 4 | Tier 1 effective N | nEffT1 | double | = tw1^2 / sumW2_1 (sau S5-S9 weighting) |
| 5 | Tier 2 effective N | nEffT2 | double | = tw2^2 / sumW2_2 |
| 6 | Real signal % | realPct | double | = (nEffT1 + nEffT2) / totalSamples * 100 |
| 7 | Oldest signal age | oldestDays | double | So ngay tu signal cu nhat den hien tai |
| 8 | Timeout count | timeoutCount | int | Signals khong hit TP hoac SL trong maxFwd |
| 9 | Win rate Tier 1 | wrT1 | double | TP1 hit rate cua Tier 1 (%) |
| 10 | Win rate Tier 2 | wrT2 | double | TP1 hit rate cua Tier 2 (%) |
| 11 | Win rate Tier 3 | wrT3 | double | TP1 hit rate cua Tier 3 (%) |

### Quality Color Coding:
- **Green** (clrLime): realPct >= 50% — da so du lieu tu signal that
- **Yellow**: realPct >= 20% — co signal that nhung Tier 3 van chiem nhieu
- **Orange**: realPct < 20% — gan nhu toan Tier 3, xac suat khong dang tin

## 3. Architecture

### 3.1 Struct Addition

File: `Include/RSI_Advanced/Structs.mqh` — ProbabilityData struct (line 93)

```
struct ProbabilityData
{
   // ... existing fields ...

   // Data quality metrics (V11.30)
   int    rawCountT1;
   int    rawCountT2;
   int    countT3;
   double nEffT1;
   double nEffT2;
   int    timeoutCount;
   double oldestDays;
   double realPct;
   double wrT1;
   double wrT2;
   double wrT3;
};
```

### 3.2 Computation

File: `Include/RSI_Advanced/ProbabilityEngine.mqh` — CalculateProbability()

**Source variables** (already computed, just not stored):
- `t1_rawN`, `t2_rawN` — raw counts (from ScanStoredSignalsBoth)
- `t3_t` — Tier 3 total (from ScanHistoricalATRBased)
- `t1_tw`, `t1_sumW2` — weighted sum and sum-of-squares (for nEff)
- `t2_tw`, `t2_sumW2` — same for Tier 2
- `t1_to`, `t2_to`, `t3_to` — timeout counts
- `t1_w1/t1_tw`, `t2_w1/t2_tw`, `t3_1/t3_t` — win rates

**Computation** (after debug block ~line 1237):
```
t1NE = (t1_sumW2 > 0) ? t1_tw*t1_tw/t1_sumW2 : 0
t2NE = (t2_sumW2 > 0) ? t2_tw*t2_tw/t2_sumW2 : 0
realPct = (totalUsed > 0) ? (t1NE + t2NE) / totalUsed * 100 : 0
```

**oldestDays**: loop g_signals[] cung direction, track max daysDiff.

### 3.3 Panel Display

File: `Include/RSI_Advanced/PanelDrawing.mqh`

1 dong compact sau dong "TP1~Xbars SL~Ybars Edge:X%":

```
 T1:8(12) T2:3(8) T3:194 Real:5% Span:45d
```

Giai thich cho trader:
- T1:nEff(raw) — signal that cung case
- T2:nEff(raw) — signal that khac case
- T3:count — ATR scan (khong phai signal that)
- Real:% — ty le du lieu that
- Span:days — do rong thoi gian du lieu

### 3.4 CSV Logging Extension

File: `Include/RSI_Advanced/SignalLogger.mqh`

Them 4 columns vao scoring CSV:
- RAW_T1: rawCountT1
- RAW_T2: rawCountT2
- COUNT_T3: countT3
- REAL_PCT: realPct

## 4. Files Modified

| File | Change |
|------|--------|
| Structs.mqh | +11 fields in ProbabilityData |
| ProbabilityEngine.mqh | Populate metrics, move nEff calc out of debug block |
| PanelDrawing.mqh | +1 DQ line + panel height calc update |
| SignalLogger.mqh | +4 CSV columns + signature update |
| RSI_Advanced.mq4 | Update LogScoringSnapshot caller |
| RSI_Advanced.mq5 | Update LogScoringSnapshot caller |

## 5. Verification Checklist

- [ ] Compile mq4 + mq5 thanh cong
- [ ] Panel hien thi dong DQ moi voi mau sac dung
- [ ] T1+T2 raw counts khop voi debug Print (InpDebugMode=true)
- [ ] realPct = (nEffT1+nEffT2)/totalSamples * 100
- [ ] Mau: green >=50%, yellow >=20%, orange <20%
- [ ] Span days hop ly (M30: <=180d, H4: <=365d)
- [ ] CSV scoring log co them 4 columns moi
- [ ] Gia tri CSV khop voi panel display
