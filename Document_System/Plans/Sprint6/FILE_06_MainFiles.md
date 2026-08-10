# Sprint 6 — File 6: `QuantEdge_RSI.mq4` + `QuantEdge_RSI.mq5`

> **Action:** MODIFY (+19 lines mỗi file)
> **Status:** DONE

---

## Business Purpose

Wire virtual trade tracker vào indicator lifecycle (OnInit / OnCalculate / OnDeinit). Không disturb signal-detection/probability pipeline. Toàn bộ Sprint 6 logic được gate bởi `InpEnableVirtualTrades` — tắt = zero overhead.

---

## Data Flow

```
OnInit()
  └─ InitVirtualCSV()             [File 3] — mở persistent CSV handle

OnCalculate() ── mỗi tick
  │
  ├─ [existing pipeline: RSI → ProbabilityEngine → SignalDetector → SLTP]
  │
  ├─ Tier 1 (after CheckAndLogNewlyResolved):
  │   └─ UpdateVirtualPositions_Tick(bid, ask)   [File 4]
  │
  ├─ if(isNewBar):
  │   └─ Tier 2:
  │       └─ UpdateVirtualPositions_OnBar()      [File 4]
  │
  └─ After CalculateEntryZones() + DrawZoneLines():
      └─ OnNewSignal guard:
          ├─ static datetime s_lastVirtualSignalTime = 0
          ├─ if(activeSig.signalTime != s_lastVirtualSignalTime):
          │   ├─ VP_CloseAllBySignal(old, bid, ask)  [File 4]
          │   ├─ OnNewSignal(activeSig)              [File 4]
          │   └─ s_lastVirtualSignalTime = activeSig.signalTime
          └─ (static guard = fire ONCE per genuinely new signal)

OnDeinit()
  └─ CloseVirtualCSV()            [File 3] — flush + đóng handle
```

---

## 5 Integration Points (identical MQ4/MQ5)

### 1. Include (top of file)
```mql4
#include <QuantEdge/Engine/VirtualTradeTracker.mqh>
```
Sau `#include <QuantEdge/Data/SignalLogger.mqh>`

### 2. OnInit — sau `LoggerInit(false)`
```mql4
InitVirtualCSV();
```
MQ4: L221 | MQ5: L271

### 3. OnDeinit — sau `FlushLogQueues()`
```mql4
CloseVirtualCSV();
```
MQ4: L266 | MQ5: L318

### 4. Tier 1 tick — sau `CheckAndLogNewlyResolved()`
```mql4
if(InpEnableVirtualTrades)
   UpdateVirtualPositions_Tick(MarketInfo(Symbol(), MODE_BID), MarketInfo(Symbol(), MODE_ASK));
```
MQ4: L733 | MQ5: L826

### 5. Tier 2 bar — trong `if(isNewBar)` block
```mql4
if(InpEnableVirtualTrades)
   UpdateVirtualPositions_OnBar();
```
MQ4: L742 | MQ5: L835

### 6. OnNewSignal hook — sau `DrawZoneLines()` + `s_zonesDrawn = true`
```mql4
if(InpEnableVirtualTrades)
{
   static datetime s_lastVirtualSignalTime = 0;
   if(activeSig.signalTime != s_lastVirtualSignalTime)
   {
      if(s_lastVirtualSignalTime > 0)
         VP_CloseAllBySignal(s_lastVirtualSignalTime,
            MarketInfo(Symbol(), MODE_BID), MarketInfo(Symbol(), MODE_ASK));
      OnNewSignal(activeSig);
      s_lastVirtualSignalTime = activeSig.signalTime;
   }
}
```
MQ4: L897-910 | MQ5: L1000-1013

---

## Design Decisions

1. **Signal-finalization ordering**: `OnNewSignal()` PHẢI gọi SAU `CalculateEntryZones()` (step 3 trong pipeline). Nếu gọi trước → `g_entryZones[]` chưa populated → virtual positions có SL/TP = 0.
2. **Static guard `s_lastVirtualSignalTime`**: `CalculateEntryZones()` fires theo `needZoneRedraw` staleness check (không strictly 1 lần per signal), nên cần guard để `OnNewSignal()` fire đúng 1 lần per genuinely new signal.
3. **Always close old positions**: ban đầu chỉ close khi direction reversal → same-direction signals orphan old positions. Review bug #3 (MEDIUM).
4. **`MarketInfo(Symbol(), MODE_BID/ASK)`**: works cả MQ4 và MQ5 trong codebase này (đã có precedent).
5. **`OnNewSignalAccepted()` ở L549/647 KHÔNG phải hook cho virtual trades**: nó chỉ tăng `g_portfolioRisk.dailyTradeCount++`, fire quá sớm (trước zones computed).
