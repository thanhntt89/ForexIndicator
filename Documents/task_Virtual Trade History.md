# Task: Virtual Trade History (V11)

Spec đầy đủ: [VirtualTradeHistory_Spec.md](file:///d:/Thanh/Forex/RSI_Advanced/Documents/VirtualTradeHistory_Spec.md)

---

## Checklist Implement

- [x] **1. Structs.mqh**: Thêm struct `VirtualPosition` với các trường theo đặc tả
- [x] **2. Globals.mqh**: Khai báo mảng tĩnh `g_virtualPositions[200]`, `g_vpCount`, `g_vpWriteHead` và các biến CSV handle `g_csvHandle`, `g_csvBuffer`, `g_csvPendingRows`
- [x] **3. SignalLogger.mqh**: Thêm các hàm ghi file CSV
  - [x] Thêm `GetTFString()` (nếu chưa có)
  - [x] Thêm `PriceToPips(priceUnits)`
  - [x] Thêm `InitVirtualCSV()`
  - [x] Thêm `AppendVirtualTradeLog()`
  - [x] Thêm `FlushPendingCSVLogs()`
  - [x] Thêm `CloseVirtualCSV()`
- [x] **4. Config.mqh**: Thêm Input group `========== Virtual History Lines ==========`
- [x] **5. LineDrawing.mqh**: Thêm hàm vẽ đường TrendLine
  - [x] Thêm `CreateHistoryLine()`
  - [x] Thêm `UpdateHistoryLineEnd()`
- [x] **6. VirtualTradeTracker.mqh [NEW FILE]**: Tạo module xử lý Virtual Trade
  - [x] Khai báo CMutex `g_vpMutex` (bọc `__MQL5__`)
  - [x] Hàm `VP_AddPosition()`
  - [x] Hàm `OnNewSignal()`
  - [x] Hàm `VP_CheckActivation()`
  - [x] Hàm `VP_CheckSLTP()`
  - [x] Hàm `VP_HitTP()`
  - [x] Hàm `VP_UpdateMFE_MAE()`
  - [x] Hàm `VP_RedrawHistoryLine()`
  - [x] Hàm `VP_CloseAllBySignal()`
  - [x] Hàm `UpdateVirtualPositions_Tick()` (Tier 1)
  - [x] Hàm `UpdateVirtualPositions_OnBar()` (Tier 2)
- [ ] **7. RSI_Advanced.mq4**: Tích hợp các module vào Main Loop
  - [ ] `#include <RSI_Advanced\VirtualTradeTracker.mqh>`
  - [ ] `OnInit()`: Gọi `InitVirtualCSV()`
  - [ ] `OnDeinit()`: Gọi `CloseVirtualCSV()`
  - [ ] `OnTick()`: Gọi `UpdateVirtualPositions_Tick(Bid, Ask)`
  - [ ] Nến mới: Gọi `UpdateVirtualPositions_OnBar()`
  - [ ] Tín hiệu mới: Gọi `OnNewSignal()` sau `StoreSignal()`
  - [ ] Đảo chiều: Gọi `VP_CloseAllBySignal()` trước khi tạo tín hiệu mới
- [ ] **8. RSI_Advanced.mq5**: Tích hợp tương tự mq4
- [ ] **9. Compile & Fix**: MQL4 và MQL5 phải pass 0 error, 0 warning.
