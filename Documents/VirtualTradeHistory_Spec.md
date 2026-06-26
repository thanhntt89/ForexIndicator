# Virtual Trade History — Design Specification
**Version:** 2.0  
**Date:** 2026-06-07  
**Status:** APPROVED — Ready for implementation  
**Author:** AI Agent + User Thanh (discussion-based design)  
**Changelog v2.0:** Architecture review integrated — 4 critical bugs fixed, 5 design gaps resolved. All decisions finalized. No open questions remain.

---

## 1. Tổng Quan (Overview)

Hệ thống Virtual Trade History biến RSI Advanced từ một chỉ báo tín hiệu đơn thuần thành một **Hệ thống Mô phỏng Giao dịch Ảo (Virtual Trading Simulator)** trực quan trên biểu đồ. Mỗi tín hiệu phát sinh sẽ tạo ra nhiều vị thế ảo (Market Entry + Pullback Entries) và theo dõi hành trình giá từ lúc vào lệnh đến khi kết thúc (TP hoặc SL), sau đó vẽ đường nối lịch sử lên chart.

**Mục tiêu chính:**
- Trực quan hóa kết quả lệnh ảo trên chart (xanh = TP, đỏ = SL)
- Theo dõi đa vị thế (Market + tất cả Pullback zones) song song cho cùng 1 tín hiệu
- Ghi log đầy đủ cho phân tích Quant về sau (Market vs Pullback performance)

---

## 2. Kiến Trúc Xử Lý (Processing Architecture)

> ⚠️ **[v2.0 — Critical Fix #1]** Spec v1.0 xử lý toàn bộ logic trong mỗi tick (OnTick), gây lag nghiêm trọng trên XAUUSD M1 (50–300 tick/phút × 200 vị thế). Kiến trúc v2.0 tách thành 2 tier bắt buộc.

### 2.1 Tier 1 — Tick Processing (OnTick)

Chỉ thực hiện các phép toán số học thuần túy, **tuyệt đối không gọi chart object functions**:

```mql4
void UpdateVirtualPositions_Tick(double bid, double ask)
{
   for(int i = 0; i < g_vpCount; i++)
   {
      if(g_virtualPositions[i].finalOutcome != 0) continue;
      VP_CheckActivation(i, bid, ask);   // So sánh giá — O(1)
      VP_CheckSLTP(i, bid, ask);         // So sánh giá — O(1)
      VP_UpdateMFE_MAE(i, bid, ask);     // Cập nhật double — O(1)
      // Nếu có thay đổi: set flag, KHÔNG gọi ObjectCreate/ObjectMove ở đây
   }
}
```

### 2.2 Tier 2 — Bar Close Processing (OnBarClose)

Chỉ chạy khi nến M1 đóng. Thực hiện tất cả chart operations và CSV flush:

```mql4
void UpdateVirtualPositions_OnBar()
{
   for(int i = 0; i < g_vpCount; i++)
   {
      if(g_virtualPositions[i].needsRedraw)
      {
         VP_RedrawHistoryLine(i);        // ObjectCreate / ObjectMove
         g_virtualPositions[i].needsRedraw = false;
      }
   }
   FlushPendingCSVLogs();               // Ghi CSV batch — chỉ 1 lần/bar
}
```

### 2.3 Gọi từ Main EA

```mql4
// RSI_Advanced.mq4 — OnTick()
void OnTick()
{
   double bid = MarketInfo(Symbol(), MODE_BID);
   double ask = MarketInfo(Symbol(), MODE_ASK);
   UpdateVirtualPositions_Tick(bid, ask);  // Tier 1: mọi tick

   bool isNewBar = IsNewBar();             // Kiểm tra nến mới
   if(isNewBar)
   {
      // ... logic signal detection ...
      UpdateVirtualPositions_OnBar();      // Tier 2: mỗi bar close
   }
}
```

---

## 3. Quy Tắc Hiển Thị Trên Chart (Visual Rules)

### 3.1 Lệnh đang chạy (Active/Pending State)

Sử dụng hệ thống vẽ đường ngang đã có sẵn trong `LineDrawing.mqh` (DrawSLTPLines, DrawZoneLines). Không thay đổi gì ở phần này — giữ nguyên kiến trúc hiện tại.

### 3.2 Lệnh kết thúc (Resolved State) — Vẽ đường lịch sử

Khi một vị thế ảo kết thúc, vẽ **1 đường OBJ_TREND** trên main chart window:

| Kết quả | Điểm bắt đầu | Điểm kết thúc | Màu |
|---|---|---|---|
| Chạm TP1 | (activationTime, entryPrice) | (tpTime[1], takeProfit1) | clrLime |
| Chạm TP2 | (activationTime, entryPrice) | (tpTime[2], takeProfit2) | clrLime |
| Chạm TP3 | (activationTime, entryPrice) | (tpTime[3], takeProfit3) | clrLime |
| Chạm SL (chưa đạt TP nào) | (activationTime, entryPrice) | (outcomeTime, stopLoss) | clrRed |
| Reversal (chưa đạt TP nào) | (activationTime, entryPrice) | (outcomeTime, closePrice) | clrRed |
| TP1 rồi quay đầu SL/Reversal | (activationTime, entryPrice) | (tpTime[1], takeProfit1) | clrLime |

**Cơ chế High-Water Mark (quan trọng):**
- `maxTPReached` chỉ tăng, không bao giờ giảm.
- Khi `maxTPReached` tăng: set flag `needsRedraw = true`, Tier 2 sẽ gọi `ObjectMove()` để dịch điểm cuối lên TP mới.
- Khi giá quay đầu sau khi đã đạt TP: đường xanh **không dịch xuống**. Giữ nguyên tại mốc TP cao nhất đạt được.
- Khi SL hit mà `maxTPReached > 0`: `finalOutcome = SL`, visual vẫn là **đường xanh** tại mốc TP cao nhất. CSV ghi đủ cả hai.

### 3.3 Hàm vẽ đường trong LineDrawing.mqh

Thêm hàm mới sau hàm hiện có:

```mql4
void CreateHistoryLine(string objName, datetime t1, double p1,
                       datetime t2, double p2, color clr,
                       int width, int style)
{
   if(ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);
   ObjectCreate(0, objName, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, objName, OBJPROP_COLOR,    clr);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH,    width);
   ObjectSetInteger(0, objName, OBJPROP_STYLE,    style);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN,   true);
}

void UpdateHistoryLineEnd(string objName, datetime t2, double p2)
{
   if(ObjectFind(0, objName) < 0) return;
   ObjectSetInteger(0, objName, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, objName, OBJPROP_PRICE, 1, p2);
}
```

### 3.4 Input Parameters (Config.mqh)

```mql4
input string   inp_grp_vhist        = "===== Virtual History Lines =====";
input bool     InpShowHistoryLines  = true;
input color    InpColorVirtualTP    = clrLime;
input color    InpColorVirtualSL    = clrRed;
input int      InpHistoryLineWidth  = 1;
input int      InpHistoryLineStyle  = STYLE_SOLID;
```

---

## 4. Đa Vị Thế Ảo (Multiple Virtual Positions)

### 4.1 Danh sách vị thế theo EntryZones

| Vị thế | Entry Price | Điều kiện kích hoạt | SL/TP |
|---|---|---|---|
| Market (Z1) | sig.entryPrice | Luôn kích hoạt ngay khi nến tín hiệu đóng | Chung từ signal gốc |
| Pullback Z2 | g_entryZones[1].price | Giá chạm zone price | Chung từ signal gốc |
| Pullback Z3 | g_entryZones[2].price | Giá chạm zone price | Chung từ signal gốc |
| Pullback Z4 | g_entryZones[3].price | Giá chạm zone price | Chung từ signal gốc |
| Pullback Z5 | g_entryZones[4].price | Giá chạm zone price | Chung từ signal gốc |

Chỉ tạo vị thế cho zone có `isValid = true`. Zone `isValid = false` bỏ qua hoàn toàn.

### 4.2 SL/TP — Quyết định dứt khoát

> ⚠️ **[v2.0 — Gap #1 Resolved]** Spec v1.0 mâu thuẫn giữa "SL/TP tính từ giá Pullback" vs "cùng mốc với signal gốc".  
> **Quyết định v2.0: SL/TP là giá tuyệt đối chung cho tất cả vị thế trong cùng 1 signal.**

Lý do: Đây là cách DCA hoạt động thực tế — tất cả lệnh cùng thoát tại 1 mốc giá. R:R sẽ khác nhau tự nhiên do entry price khác nhau, và CSV ghi `RR_RATIO` riêng cho từng vị thế để phân tích.

```mql4
// Khi tạo VirtualPosition từ zone z:
pos.stopLoss    = sig.stopLoss;     // Giá tuyệt đối — KHÔNG tính lại
pos.takeProfit1 = sig.takeProfit1;  // Giá tuyệt đối — KHÔNG tính lại
pos.takeProfit2 = sig.takeProfit2;
pos.takeProfit3 = sig.takeProfit3;
// R:R thực tế tính khi đóng lệnh:
// rrRatio = (entryPrice - stopLoss) / (takeProfit1 - entryPrice) cho BUY
```

### 4.3 Điều kiện kích hoạt Pullback

Kiểm tra trong **Tier 1 (mỗi tick)**, không phải bar close:

```mql4
void VP_CheckActivation(int idx, double bid, double ask)
{
   VirtualPosition &pos = g_virtualPositions[idx];
   if(pos.isActivated) return;
   if(pos.zoneIndex == 0) { pos.isActivated = true; return; } // Market: luôn active

   if(pos.isBuy)
   {
      // BUY pullback: giá Bid chạm hoặc xuống dưới zone price
      if(bid <= pos.entryPrice)
      {
         pos.isActivated    = true;
         pos.activationTime = TimeCurrent();
         pos.activationBar  = Bars - 1;
      }
   }
   else
   {
      // SELL pullback: giá Ask chạm hoặc lên trên zone price
      if(ask >= pos.entryPrice)
      {
         pos.isActivated    = true;
         pos.activationTime = TimeCurrent();
         pos.activationBar  = Bars - 1;
      }
   }
}
```

---

## 5. Cấu Trúc Dữ Liệu (Data Structures)

### 5.1 Struct VirtualPosition (Structs.mqh)

> ⚠️ **[v2.0 — Multiple Fixes Applied]**
> - `signalIndex` đã bị xóa, thay bằng composite key `signalTime + signalCaseNum` (Fix Critical #3)
> - `maxTPTime` đổi thành array `tpTime[4]` để lưu từng mốc (Fix Gap #2)
> - Thêm `needsRedraw`, `needsLog`, `closePrice` cho Tier 1/2 split (Fix Critical #1)

```mql4
struct VirtualPosition
{
   //--- Identity (Composite key — không dùng index)
   datetime signalTime;        // Signal time — key bất biến
   int      signalCaseNum;     // Case number của signal gốc — key bất biến
   int      zoneIndex;         // 0=Market, 1=Z2, 2=Z3, 3=Z4, 4=Z5
   string   entryType;         // "MARKET","PULLBACK_Z2","PULLBACK_Z3","PULLBACK_Z4","PULLBACK_Z5"

   //--- Entry
   double   entryPrice;        // Giá vào lệnh thực tế của vị thế này
   bool     isActivated;       // Market=true ngay, Pullback=true khi giá chạm zone
   datetime activationTime;    // Thời điểm được kích hoạt
   int      activationBar;     // Bars-1 tại thời điểm kích hoạt (để tính BARS_HELD)

   //--- Shared SL/TP từ signal gốc (giá tuyệt đối, chung cho tất cả zone)
   double   stopLoss;
   double   takeProfit1;
   double   takeProfit2;
   double   takeProfit3;
   bool     isBuy;
   string   sessionName;       // "Asian"/"London"/"Overlap"/"LateNY"

   //--- Tracking state
   int      maxTPReached;      // 0=none, 1=TP1, 2=TP2, 3=TP3. Chỉ tăng, không giảm.
   datetime tpTime[4];         // tpTime[1]=khi chạm TP1, [2]=TP2, [3]=TP3. [0] không dùng.
   int      finalOutcome;      // 0=pending, 1=TP_HIT, -1=SL_HIT, -2=REVERSAL
   datetime outcomeTime;       // Thời điểm đóng vị thế
   double   closePrice;        // Giá đóng thực tế (SL price, TP price, hoặc giá lúc reversal)

   //--- MFE/MAE (đơn vị: price units, không phải pips — convert khi ghi CSV)
   double   mfe;               // Max Favorable Excursion tính từ entryPrice
   double   mae;               // Max Adverse Excursion tính từ entryPrice

   //--- Tier 1/2 communication flags (set bởi Tier 1, cleared bởi Tier 2)
   bool     needsRedraw;       // Tier 2 cần vẽ lại đường lịch sử
   bool     needsLog;          // Tier 2 cần ghi CSV

   //--- Drawing state
   bool     historyDrawn;      // Đã vẽ đường lịch sử chưa
   string   objectName;        // Tên chart object để cleanup
};
```

### 5.2 Global Variables (Globals.mqh)

> ⚠️ **[v2.0 — Fix Critical #1 + Gap #4]** Dùng static array kích thước cố định + circular write pointer. Không dùng `ArrayResize` trong runtime.

```mql4
#define MAX_VIRTUAL_POS 200

VirtualPosition g_virtualPositions[MAX_VIRTUAL_POS];
int             g_vpCount   = 0;    // Số vị thế hiện có (tối đa MAX_VIRTUAL_POS)
int             g_vpWriteHead = 0;  // Circular write pointer

//--- CSV — Fix Critical #2: persistent handle, không mở/đóng mỗi lần ghi
int             g_csvHandle      = INVALID_HANDLE;
string          g_csvBuffer      = "";   // Accumulate rows trước khi flush
int             g_csvPendingRows = 0;
```

### 5.3 Circular Buffer — Thêm vị thế mới

```mql4
// VirtualTradeTracker.mqh
int VP_AddPosition(VirtualPosition &pos)
{
   // Tìm slot: ưu tiên slot đã resolved (finalOutcome != 0)
   int slot = -1;
   for(int i = 0; i < MAX_VIRTUAL_POS; i++)
   {
      int idx = (g_vpWriteHead + i) % MAX_VIRTUAL_POS;
      if(g_virtualPositions[idx].finalOutcome != 0 ||
         g_virtualPositions[idx].signalTime == 0)
      { slot = idx; break; }
   }
   // Nếu không tìm được slot resolved: overwrite slot cũ nhất (circular)
   if(slot < 0)
   {
      slot = g_vpWriteHead;
      g_vpWriteHead = (g_vpWriteHead + 1) % MAX_VIRTUAL_POS;
   }

   g_virtualPositions[slot] = pos;
   if(g_vpCount < MAX_VIRTUAL_POS) g_vpCount++;
   return slot;
}
```

---

## 6. CSV Log Cho Phân Tích Quant

### 6.1 File

`virtual_trades_SYMBOL_TF_YYYY.csv`  
Ví dụ: `virtual_trades_XAUUSD_M1_2026.csv`

### 6.2 Columns

```
SIGNAL_ID,SYMBOL,TF,SIGNAL_TIME,CASE_NUM,CASE_NAME,DIR,SESSION,
ENTRY_TYPE,ENTRY_PRICE,ACTIVATION_TIME,
SL,TP1,TP2,TP3,ATR,
MAX_TP_REACHED,FINAL_OUTCOME,OUTCOME_TIME,
EXIT_PRICE,BARS_HELD,MFE_PIPS,MAE_PIPS,RR_RATIO
```

| Cột | Kiểu | Mô tả |
|---|---|---|
| SIGNAL_ID | string | `signalTime_caseNum` — VD: `20260607143000_2` |
| ENTRY_TYPE | string | `MARKET` / `PULLBACK_Z2` / `PULLBACK_Z3` / `PULLBACK_Z4` / `PULLBACK_Z5` |
| ENTRY_PRICE | double | Giá vào lệnh của vị thế này |
| ACTIVATION_TIME | datetime | Thời điểm vị thế được kích hoạt |
| MAX_TP_REACHED | int | 0/1/2/3 — Mốc TP cao nhất từng đạt được |
| FINAL_OUTCOME | string | `TP1` / `TP2` / `TP3` / `SL` / `REVERSAL` / `NOT_ACTIVATED` |
| EXIT_PRICE | double | Giá đóng thực tế |
| BARS_HELD | int | Số nến từ `activationBar` đến bar đóng |
| MFE_PIPS | double | `mfe / pipSize` — convert từ price units |
| MAE_PIPS | double | `mae / pipSize` — convert từ price units |
| RR_RATIO | double | R:R thực tế tính từ `entryPrice` của vị thế này |

### 6.3 Quy đổi đơn vị MFE/MAE sang Pips

> ⚠️ **[v2.0 — Gap #5 Resolved]** XAUUSD không có pip chuẩn forex. Dùng công thức:

```mql4
// Trong hàm LogVirtualTrade()
string GetPipSizeStr()
{
   // XAUUSD Digits=2: _Point=0.01, pipSize=0.10 (1 pip = $0.10)
   // EURUSD Digits=5: _Point=0.00001, pipSize=0.0001
   // Dùng _Point * 10 nếu Digits lẻ, _Point nếu Digits chẵn
   double pipSize = (Digits % 2 != 0) ? _Point * 10.0 : _Point;
   return DoubleToString(pipSize, Digits);
}

double PriceToPips(double priceUnits)
{
   double pipSize = (Digits % 2 != 0) ? _Point * 10.0 : _Point;
   return priceUnits / pipSize;
}
// Gọi: PriceToPips(pos.mfe), PriceToPips(pos.mae)
```

### 6.4 File Handle Management

> ⚠️ **[v2.0 — Fix Critical #2]** Không mở/đóng file mỗi lần ghi. Persistent handle + batch flush.

```mql4
// SignalLogger.mqh

// Gọi trong OnInit()
bool InitVirtualCSV()
{
   string fname = "virtual_trades_" + Symbol() + "_" +
                  GetTFString() + "_" +
                  IntegerToString(Year()) + ".csv";
   g_csvHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
   if(g_csvHandle == INVALID_HANDLE) return false;
   // Ghi header nếu file mới
   FileWrite(g_csvHandle,
      "SIGNAL_ID,SYMBOL,TF,SIGNAL_TIME,CASE_NUM,CASE_NAME,DIR,SESSION,"
      "ENTRY_TYPE,ENTRY_PRICE,ACTIVATION_TIME,"
      "SL,TP1,TP2,TP3,ATR,"
      "MAX_TP_REACHED,FINAL_OUTCOME,OUTCOME_TIME,"
      "EXIT_PRICE,BARS_HELD,MFE_PIPS,MAE_PIPS,RR_RATIO");
   return true;
}

// Gọi trong OnDeinit()
void CloseVirtualCSV()
{
   FlushPendingCSVLogs();  // Flush còn lại
   if(g_csvHandle != INVALID_HANDLE)
   { FileClose(g_csvHandle); g_csvHandle = INVALID_HANDLE; }
}

// Gọi mỗi khi vị thế đóng (Tier 1 set flag, Tier 2 gọi hàm này)
void AppendVirtualTradeLog(const VirtualPosition &pos)
{
   if(g_csvHandle == INVALID_HANDLE) return;

   string signalId = TimeToString(pos.signalTime, TIME_DATE|TIME_MINUTES) +
                     "_" + IntegerToString(pos.signalCaseNum);
   double slDist   = MathAbs(pos.entryPrice - pos.stopLoss);
   double tp1Dist  = MathAbs(pos.takeProfit1 - pos.entryPrice);
   double rrRatio  = (slDist > 0) ? tp1Dist / slDist : 0;
   int    barsHeld = (pos.activationBar > 0) ? pos.activationBar - (Bars - 1) : 0;

   string outcome  = "NOT_ACTIVATED";
   if(!pos.isActivated) outcome = "NOT_ACTIVATED";
   else if(pos.finalOutcome ==  1)
   {
      if(pos.maxTPReached == 1) outcome = "TP1";
      else if(pos.maxTPReached == 2) outcome = "TP2";
      else if(pos.maxTPReached == 3) outcome = "TP3";
   }
   else if(pos.finalOutcome == -1) outcome = "SL";
   else if(pos.finalOutcome == -2) outcome = "REVERSAL";

   FileWrite(g_csvHandle,
      signalId,
      Symbol(),
      GetTFString(),
      TimeToString(pos.signalTime, TIME_DATE|TIME_MINUTES),
      IntegerToString(pos.signalCaseNum),
      "",                                              // CASE_NAME: caller fills in
      pos.isBuy ? "BUY" : "SELL",
      pos.sessionName,
      pos.entryType,
      DoubleToString(pos.entryPrice, Digits),
      TimeToString(pos.activationTime, TIME_DATE|TIME_MINUTES),
      DoubleToString(pos.stopLoss,    Digits),
      DoubleToString(pos.takeProfit1, Digits),
      DoubleToString(pos.takeProfit2, Digits),
      DoubleToString(pos.takeProfit3, Digits),
      "",                                              // ATR: caller fills in
      IntegerToString(pos.maxTPReached),
      outcome,
      TimeToString(pos.outcomeTime, TIME_DATE|TIME_MINUTES),
      DoubleToString(pos.closePrice, Digits),
      IntegerToString(MathAbs(barsHeld)),
      DoubleToString(PriceToPips(pos.mfe), 1),
      DoubleToString(PriceToPips(pos.mae), 1),
      DoubleToString(rrRatio, 2)
   );

   g_csvPendingRows++;
   if(g_csvPendingRows >= 10) FlushPendingCSVLogs();
}

void FlushPendingCSVLogs()
{
   if(g_csvHandle == INVALID_HANDLE) return;
   FileFlush(g_csvHandle);
   g_csvPendingRows = 0;
}
```

---

## 7. Luồng Xử Lý Chi Tiết (Processing Flow)

### 7.1 Khi tín hiệu mới xuất hiện (Signal Creation)

```mql4
// VirtualTradeTracker.mqh
void OnNewSignal(const SignalData &sig)
{
   // Tạo VirtualPosition cho Market Entry
   VirtualPosition pos;
   ArrayInitialize(pos.tpTime, 0);    // Init array tpTime[4]

   pos.signalTime    = sig.signalTime;
   pos.signalCaseNum = sig.caseNumber;
   pos.isBuy         = sig.isBuySignal;
   pos.sessionName   = GetSessionName(sig.signalTime);
   pos.stopLoss      = sig.stopLoss;
   pos.takeProfit1   = sig.takeProfit1;
   pos.takeProfit2   = sig.takeProfit2;
   pos.takeProfit3   = sig.takeProfit3;

   // Zone 0: Market
   pos.zoneIndex       = 0;
   pos.entryType       = "MARKET";
   pos.entryPrice      = sig.entryPrice;
   pos.isActivated     = true;
   pos.activationTime  = sig.signalTime;
   pos.activationBar   = Bars - 1;
   pos.maxTPReached    = 0;
   pos.finalOutcome    = 0;
   pos.mfe             = 0;
   pos.mae             = 0;
   pos.needsRedraw     = false;
   pos.needsLog        = false;
   pos.historyDrawn    = false;
   pos.objectName      = "VH_" + IntegerToString(sig.signalTime) + "_Z0";
   VP_AddPosition(pos);

   // Zones 1–4: Pullback
   string zoneNames[] = {"", "PULLBACK_Z2", "PULLBACK_Z3", "PULLBACK_Z4", "PULLBACK_Z5"};
   for(int z = 1; z < 5; z++)
   {
      if(z >= ArraySize(g_entryZones) || !g_entryZones[z].isValid) continue;
      pos.zoneIndex      = z;
      pos.entryType      = zoneNames[z];
      pos.entryPrice     = g_entryZones[z].price;
      pos.isActivated    = false;
      pos.activationTime = 0;
      pos.activationBar  = 0;
      pos.maxTPReached   = 0;
      pos.finalOutcome   = 0;
      pos.mfe            = 0;
      pos.mae            = 0;
      pos.needsRedraw    = false;
      pos.needsLog       = false;
      pos.historyDrawn   = false;
      pos.objectName     = "VH_" + IntegerToString(sig.signalTime) +
                           "_Z" + IntegerToString(z);
      ArrayInitialize(pos.tpTime, 0);
      VP_AddPosition(pos);
   }
}
```

### 7.2 Mỗi Tick — Tier 1

```mql4
void VP_CheckSLTP(int idx, double bid, double ask)
{
   VirtualPosition &pos = g_virtualPositions[idx];
   if(!pos.isActivated || pos.finalOutcome != 0) return;

   double curPrice = pos.isBuy ? bid : ask;

   // Check TP3 → TP2 → TP1 (từ cao xuống thấp để cập nhật đúng)
   if(pos.maxTPReached < 3 && pos.isBuy  && bid >= pos.takeProfit3) VP_HitTP(idx, 3, TimeCurrent(), pos.takeProfit3);
   if(pos.maxTPReached < 3 && !pos.isBuy && ask <= pos.takeProfit3) VP_HitTP(idx, 3, TimeCurrent(), pos.takeProfit3);
   if(pos.maxTPReached < 2 && pos.isBuy  && bid >= pos.takeProfit2) VP_HitTP(idx, 2, TimeCurrent(), pos.takeProfit2);
   if(pos.maxTPReached < 2 && !pos.isBuy && ask <= pos.takeProfit2) VP_HitTP(idx, 2, TimeCurrent(), pos.takeProfit2);
   if(pos.maxTPReached < 1 && pos.isBuy  && bid >= pos.takeProfit1) VP_HitTP(idx, 1, TimeCurrent(), pos.takeProfit1);
   if(pos.maxTPReached < 1 && !pos.isBuy && ask <= pos.takeProfit1) VP_HitTP(idx, 1, TimeCurrent(), pos.takeProfit1);

   // Check SL
   bool slHit = (pos.isBuy && bid <= pos.stopLoss) ||
                (!pos.isBuy && ask >= pos.stopLoss);
   if(slHit)
   {
      pos.finalOutcome = -1;
      pos.outcomeTime  = TimeCurrent();
      pos.closePrice   = pos.stopLoss;
      pos.needsRedraw  = true;
      pos.needsLog     = true;
   }
}

void VP_HitTP(int idx, int tpLevel, datetime t, double price)
{
   VirtualPosition &pos = g_virtualPositions[idx];
   pos.maxTPReached     = tpLevel;
   pos.tpTime[tpLevel]  = t;
   pos.finalOutcome     = 1;
   pos.outcomeTime      = t;
   pos.closePrice       = price;
   pos.needsRedraw      = true;  // Tier 2 sẽ vẽ lại
   // needsLog = false ở đây — chỉ log khi lệnh ĐÓNG hoàn toàn
   // Log xảy ra khi SL hit HOẶC Reversal sau khi đạt TP
}

void VP_UpdateMFE_MAE(int idx, double bid, double ask)
{
   VirtualPosition &pos = g_virtualPositions[idx];
   if(!pos.isActivated || pos.finalOutcome != 0) return;

   double fav = pos.isBuy ? (bid - pos.entryPrice) : (pos.entryPrice - ask);
   double adv = pos.isBuy ? (pos.entryPrice - ask) : (bid - pos.entryPrice);
   if(fav > pos.mfe) pos.mfe = fav;
   if(adv > pos.mae) pos.mae = adv;
}
```

### 7.3 Mỗi Bar Close — Tier 2

```mql4
void VP_RedrawHistoryLine(int idx)
{
   VirtualPosition &pos = g_virtualPositions[idx];
   if(!InpShowHistoryLines) return;

   datetime t1 = pos.activationTime;
   double   p1 = pos.entryPrice;
   datetime t2;
   double   p2;
   color    clr;

   if(pos.maxTPReached > 0)
   {
      // Đường xanh tại mốc TP cao nhất đạt được
      t2  = pos.tpTime[pos.maxTPReached];
      p2  = (pos.maxTPReached == 1) ? pos.takeProfit1 :
            (pos.maxTPReached == 2) ? pos.takeProfit2 : pos.takeProfit3;
      clr = InpColorVirtualTP;
   }
   else
   {
      // Chưa đạt TP nào → đường đỏ đến điểm đóng
      t2  = pos.outcomeTime;
      p2  = pos.closePrice;
      clr = InpColorVirtualSL;
   }

   if(t2 <= 0 || t2 <= t1) return;  // Guard: thời gian hợp lệ

   if(!pos.historyDrawn)
   {
      CreateHistoryLine(pos.objectName, t1, p1, t2, p2, clr,
                        InpHistoryLineWidth, InpHistoryLineStyle);
      pos.historyDrawn = true;
   }
   else
   {
      UpdateHistoryLineEnd(pos.objectName, t2, p2);
   }
}
```

### 7.4 Khi tín hiệu đảo chiều (Reversal)

> ⚠️ **[v2.0 — Gap #3 Resolved]** Reversal chỉ được xử lý tại **bar close** (gọi từ `UpdateVirtualPositions_OnBar`), không xử lý intra-bar để tránh false reversal do nến chưa đóng.

```mql4
// Gọi từ Tier 2, sau khi xác nhận tín hiệu đảo chiều tại bar close
void VP_CloseAllBySignal(datetime oldSignalTime, double currentPrice)
{
   for(int i = 0; i < MAX_VIRTUAL_POS; i++)
   {
      VirtualPosition &pos = g_virtualPositions[i];
      if(pos.signalTime != oldSignalTime) continue;
      if(pos.finalOutcome != 0) continue;  // Đã đóng rồi

      if(!pos.isActivated)
      {
         // Chưa kích hoạt → NOT_ACTIVATED
         pos.finalOutcome = -2;
         pos.outcomeTime  = TimeCurrent();
         pos.closePrice   = currentPrice;
         pos.needsLog     = true;
         // needsRedraw = false — không vẽ đường cho zone chưa activate
      }
      else
      {
         pos.finalOutcome = -2;  // REVERSAL
         pos.outcomeTime  = TimeCurrent();
         pos.closePrice   = currentPrice;
         pos.needsRedraw  = true;
         pos.needsLog     = true;
      }
   }
}
```

---

## 8. Quy Tắc Tín Hiệu Cùng Chiều vs Đảo Chiều

### 8.1 Tín hiệu cùng chiều (Same Direction)

Khi có tín hiệu BUY mới trong khi BUY cũ đang chạy:
- KHÔNG thay đổi Active Signal Display (giữ đường ngang Entry/SL/TP của lệnh cũ).
- Gọi `OnNewSignal()` để tạo bộ VirtualPosition mới cho tín hiệu BUY mới.
- Mỗi bộ VirtualPosition theo dõi TP/SL độc lập với `signalTime` khác nhau.

### 8.2 Tín hiệu đảo chiều (Opposite Direction)

Khi có tín hiệu SELL xuất hiện trong khi BUY đang chạy — xử lý **tại bar close**:
1. Gọi `VP_CloseAllBySignal(oldSignalTime, Close[1])` với giá đóng của nến vừa đóng.
2. Tier 2 vẽ đường lịch sử + ghi CSV cho tất cả vị thế BUY cũ.
3. Chuyển Active Signal Display sang tín hiệu SELL mới.
4. Gọi `OnNewSignal()` để tạo bộ VirtualPosition mới cho SELL.

---

## 9. Thread Safety (MT5)

> ⚠️ **[v2.0 — Fix Critical #4]** MT5 chạy `OnTick()` và `OnTimer()` trên thread khác nhau. Bắt buộc dùng mutex khi access `g_virtualPositions[]` trên MT5.

```mql5
// VirtualTradeTracker.mqh — đầu file
#ifdef __MQL5__
   #include <Mutex.mqh>
   CMutex g_vpMutex;
   #define LOCK_VP   g_vpMutex.Lock()
   #define UNLOCK_VP g_vpMutex.Unlock()
#else
   #define LOCK_VP
   #define UNLOCK_VP
#endif

// Bao mọi hàm access g_virtualPositions[]:
void UpdateVirtualPositions_Tick(double bid, double ask)
{
   LOCK_VP;
   for(int i = 0; i < g_vpCount; i++) { /* ... */ }
   UNLOCK_VP;
}
```

---

## 10. Cleanup — OnDeinit

> ⚠️ **[v2.0 — Clarification]** OBJ_TREND tạo bằng `ObjectCreate` **không** tự xóa khi indicator deinit. Phải xóa tường minh hoặc để lại (theo ý người dùng). Spec này chọn **giữ lại đường lịch sử** khi remove indicator — chúng là dữ liệu phân tích.

```mql4
// RSI_Advanced.mq4 — OnDeinit()
void OnDeinit(int reason)
{
   CloseVirtualCSV();    // Flush + đóng file handle
   // Đường lịch sử OBJ_TREND được giữ lại trên chart — KHÔNG xóa
   // Người dùng có thể xóa thủ công hoặc dùng nút "Clear History" nếu implement
}
```

Nếu muốn xóa khi deinit, thêm:
```mql4
void VP_DeleteAllHistoryLines()
{
   for(int i = 0; i < MAX_VIRTUAL_POS; i++)
      if(g_virtualPositions[i].historyDrawn)
         ObjectDelete(0, g_virtualPositions[i].objectName);
}
```

---

## 11. File Source Code — Phân Công Thay Đổi

| File | Vai trò | Thay đổi v2.0 |
|---|---|---|
| `Structs.mqh` | Định nghĩa struct | **[NEW]** Thêm `VirtualPosition` (đã có đầy đủ ở Section 5.1) |
| `Globals.mqh` | Biến global | **[MODIFY]** Thêm `g_virtualPositions[200]`, `g_vpCount`, `g_vpWriteHead`, `g_csvHandle`, `g_csvBuffer`, `g_csvPendingRows` |
| `VirtualTradeTracker.mqh` | Logic theo dõi | **[NEW]** `OnNewSignal()`, `VP_CheckActivation()`, `VP_CheckSLTP()`, `VP_HitTP()`, `VP_UpdateMFE_MAE()`, `VP_RedrawHistoryLine()`, `VP_CloseAllBySignal()`, `VP_AddPosition()`, `UpdateVirtualPositions_Tick()`, `UpdateVirtualPositions_OnBar()` |
| `SignalLogger.mqh` | Ghi CSV | **[MODIFY]** Thêm `InitVirtualCSV()`, `CloseVirtualCSV()`, `AppendVirtualTradeLog()`, `FlushPendingCSVLogs()`, `PriceToPips()` |
| `Config.mqh` | Tham số | **[MODIFY]** Thêm input group Virtual History Lines (Section 3.4) |
| `LineDrawing.mqh` | Vẽ đường | **[MODIFY]** Thêm `CreateHistoryLine()`, `UpdateHistoryLineEnd()` (Section 3.3) |
| `RSI_Advanced.mq4` | Main MT4 | **[MODIFY]** Gọi `UpdateVirtualPositions_Tick()` mỗi tick, `UpdateVirtualPositions_OnBar()` mỗi bar close, `InitVirtualCSV()` trong OnInit, `CloseVirtualCSV()` trong OnDeinit |
| `RSI_Advanced.mq5` | Main MT5 | **[MODIFY]** Tương tự mq4, thêm mutex wrap (Section 9) |

---

## 12. Tóm Tắt Quyết Định Thiết Kế v2.0

| # | Câu hỏi | Quyết định v2.0 | Lý do |
|---|---|---|---|
| 1 | Vẽ mấy đường khi TP1→SL? | 1 đường xanh Entry→TP1. CSV ghi đủ cả 2. | Thể hiện lệnh đã từng đạt TP |
| 2 | Màu reversal? | Đỏ (giống SL) | Đơn giản, reversal = ép đóng sớm |
| 3 | Số vị thế pullback? | Tất cả zone `isValid=true` | Phân tích đầy đủ từng zone |
| 4 | Log quant ghi gì? | `MAX_TP_REACHED` + `FINAL_OUTCOME` + `tpTime[4]` | Phân tích Partial Win, timing từng TP |
| 5 | Tín hiệu cùng chiều? | Giữ display cũ, tạo VirtualPosition mới | Không nhảy Entry, cho phép nhồi lệnh ảo |
| 6 | Tín hiệu đảo chiều? | Đóng tất cả VPosition cũ tại bar close | Tránh false reversal intra-bar |
| 7 | SL/TP mỗi zone tính thế nào? | **Giá tuyệt đối chung** từ signal gốc | DCA thực tế — tất cả cùng mốc thoát |
| 8 | Tick loop performance? | **Tier 1/2 split** — không vẽ chart trong tick | XAUUSD M1 có 300 tick/phút |
| 9 | CSV file handle? | **Persistent handle** + batch flush mỗi 10 rows | Tránh lag từ mở/đóng file liên tục |
| 10 | Signal lookup key? | `signalTime + signalCaseNum` (composite) | Index-based fragile khi array bị compact |
| 11 | maxTPTime? | **Array `tpTime[4]`** — lưu timestamp từng TP | Không mất data khi TP1→TP2→TP3 |
| 12 | Memory management? | **Static array + circular write pointer** | Không ArrayResize trong runtime |
| 13 | MT5 thread safety? | **CMutex** wrap tất cả array access | MT5 multi-threaded |
| 14 | MFE/MAE đơn vị? | Lưu price units, convert khi ghi CSV | XAUUSD không có pip chuẩn |
| 15 | Cleanup khi deinit? | Giữ đường lịch sử, đóng file handle | Đường lịch sử là dữ liệu phân tích |

---

## 13. Checklist Trước Khi Implement

Trước khi viết code `VirtualTradeTracker.mqh`, xác nhận:

- [ ] `GetSessionName(datetime t)` đã có trong codebase trả về `string` ("Asian"/"London"/"Overlap"/"LateNY")
- [ ] `GetTFString()` đã có trả về `string` ("M1"/"M5"/"H1"...)
- [ ] `IsNewBar()` đã có và hoạt động đúng trên cả mq4/mq5
- [ ] `g_entryZones[]` đã được populate trước khi `OnNewSignal()` được gọi
- [ ] `SignalData` struct đã có field `caseNumber`, `takeProfit1/2/3`, `stopLoss`, `entryPrice`
- [ ] MT5 build: `Mutex.mqh` available trong `MQL5/Include/`