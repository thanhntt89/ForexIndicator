# QuantEdge — Signal Interface (Pluggable Signal Sources)

## 1. Vấn Đề Hiện Tại

RSI signal logic nằm rải rác trong 3 file:
- `RSICore.mqh` — Tính RSI buffers (Green, Red, Orange, BB)
- `SignalCases.mqh` — 9 case detection functions
- `QuantEdge_RSI.mq4` (dòng 350-580) — DetectSignals loop

**Hệ quả:** Không thể thay RSI bằng MACD hoặc Price Action mà không viết lại cả main file.

## 2. Thiết Kế: ISignalSource Interface

### Concept

```
┌─────────────────────────────────────────┐
│              QuantEdge Core              │
│  (ProbabilityEngine, WalkForward, etc.)  │
│                                          │
│  ← ISignalSource interface ←            │
│                                          │
└──────────────┬──────────────────────────┘
               │ DetectSignals()
       ┌───────┴────────┐
       │                │
  RSISignal.mqh    MACDSignal.mqh (future)
```

### Interface Definition (MQL4 style — no class inheritance)

MQL4 không hỗ trợ interface/abstract class đầy đủ, nên dùng pattern **function pointers via #include swap**:

```mql4
// File: Include/QuantEdge/Signals/ISignalSource.mqh
// Mỗi signal module PHẢI implement các hàm sau:

// 1. Init signal source buffers
void Signal_Init(int maxBars);

// 2. Calculate indicator values for bar i
void Signal_Calculate(int i, int totalBars,
                      const double &high[],
                      const double &low[],
                      const double &close[]);

// 3. Detect buy/sell signals at bar i
//    Returns: caseNumber (1-9 for RSI, 101-109 for MACD, etc.)
//    Returns 0 if no signal
int Signal_DetectBuy(int i, int totalBars, const double &high[],
                     const double &low[], const double &close[]);
int Signal_DetectSell(int i, int totalBars, const double &high[],
                      const double &low[], const double &close[]);

// 4. Get signal-specific data for logging
double Signal_GetAngleStrength(int i);
double Signal_GetIndicatorValue(int i);  // RSI value, MACD histogram, etc.
string Signal_GetCaseName(int caseNum);
string Signal_GetSourceName();           // "RSI", "MACD", "PA", etc.
```

### RSI Implementation

```mql4
// File: Include/QuantEdge/Signals/RSISignal.mqh
#include "../RSICore.mqh"
#include "../SignalCases.mqh"

string Signal_GetSourceName() { return "RSI"; }

void Signal_Init(int maxBars)
{
   // Existing RSI buffer setup
}

int Signal_DetectBuy(int i, int totalBars, ...)
{
   // Wrap existing CheckCase1Buy(), CheckCase2Buy(), etc.
   if(CheckCase1Buy(i, totalBars, ...)) return 1;
   if(CheckCase2Buy(i, totalBars, ...)) return 2;
   // ...
   return 0;
}
```

### Main File Change

```mql4
// QuantEdge_RSI.mq4 → chỉ cần 1 dòng include:
#include <QuantEdge/Signals/RSISignal.mqh>

// Future: QuantEdge_MACD.mq4
#include <QuantEdge/Signals/MACDSignal.mqh>
```

## 3. Case Number Convention

| Range | Signal Source |
|-------|-------------|
| 1-9 | RSI (hiện tại) |
| 11-19 | MACD (tương lai) |
| 21-29 | Price Action (tương lai) |
| 31-39 | Bollinger (tương lai) |
| 41-49 | Ichimoku (tương lai) |
| 100+ | Custom / AI-generated |

## 4. Thư Mục Cấu Trúc Mới

```
Include/QuantEdge/
├── Signals/                  ← [NEW] Signal source plugins
│   ├── ISignalSource.mqh     ← Interface definition
│   └── RSISignal.mqh         ← RSI implementation (refactor từ RSICore + SignalCases)
├── ProbabilityEngine.mqh     ← Không đổi (nhận SignalData từ bất kỳ source nào)
├── WalkForward.mqh           ← Không đổi
└── ...
```

## 5. Ưu Tiên Thực Hiện

| Bước | Mô tả | Risk |
|------|-------|------|
| 1 | Tạo `ISignalSource.mqh` interface | Thấp |
| 2 | Tạo `RSISignal.mqh` wrap existing code | Trung bình — cần test kỹ |
| 3 | Refactor main file dùng Signal_Detect*() | Cao — đụng main loop |
| 4 | Verify compile + behavior unchanged | Bắt buộc |
