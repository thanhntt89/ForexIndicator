# V11: Virtual Trade History & Quant Logger - Implementation Completed

Đã hoàn tất việc tích hợp tính năng Virtual Trade History (Hiển thị Lịch sử Giao dịch Ảo & Ghi nhận Log dữ liệu Phân tích Định lượng). 

## Các thay đổi chính

### 1. Kiến trúc Tier-1 & Tier-2 (Hiệu suất cao)
Hệ thống xử lý lệnh ảo đã được chia thành 2 cấp độ để giải quyết triệt để vấn đề lag giao diện khi backtest hoặc thị trường biến động mạnh (vd: XAUUSD M1 với 300 tick/phút):
- **Tier 1 (Tick-level)**: File `VirtualTradeTracker.mqh` có hàm `UpdateVirtualPositions_Tick()`. Hàm này chỉ xử lý toán học thuần túy: kiểm tra Activation, cập nhật MFE/MAE, và kiểm tra chạm SL/TP. Tuyệt đối không có lệnh nào gọi đến Object (Draw/Delete) trong mỗi tick.
- **Tier 2 (Bar-level)**: Hàm `UpdateVirtualPositions_OnBar()` chỉ được gọi khi thanh nến đóng. Ở cấp độ này, Indicator mới bắt đầu vẽ/điều chỉnh đường lịch sử (History Lines) thông qua hàm `VP_RedrawHistoryLine()` và ghi Log xuất file CSV (`FlushPendingCSVLogs()`).

### 2. Module `VirtualTradeTracker.mqh`
- Khởi tạo mảng `g_virtualPositions[200]` dạng Circular Buffer (Ghi vòng lặp). Thay vì phải liên tục gọi `ArrayResize`, hệ thống lưu giữ 200 vị thế gần nhất. Khi đầy, dữ liệu cũ nhất tự động được ghi đè (`g_vpWriteHead`).
- Cơ chế Mutex (`CMutex g_vpMutex`) đã được bọc bằng `#ifdef __MQL5__` để đảm bảo MT5 multi-thread hoạt động an toàn mà MT4 không bị lỗi cú pháp.
- Đã cài đặt cơ chế Reversal Rules (`VP_CloseAllBySignal`): Các lệnh đang chạy mà xuất hiện tín hiệu đảo chiều sẽ bị đóng ngay lập tức (kể cả trên đồ thị và trong dữ liệu CSV), với `finalOutcome = -2` (Màu sắc và trạng thái được thiết lập lại cho phù hợp).

### 3. Log Xuất Dữ Liệu (`SignalLogger.mqh`)
Hệ thống Quant Analyzer giờ đây đã có thêm luồng ghi file CSV cho Virtual Trades:
- `virtual_trades_SYMBOL_TF_YYYY.csv` lưu trữ mọi vị thế (Market + Pullback).
- Bổ sung trường `MFE` (Max Favorable Excursion) và `MAE` (Max Adverse Excursion) tính bằng pip, phục vụ tốt cho việc xây dựng Model học máy hoặc kiểm định chất lượng Pullback Zone.
- Cơ chế Flush theo lô (Batch Flush) tự động kích hoạt sau mỗi 10 lệnh (`g_csvPendingRows`) hoặc khi đóng nến để tối ưu hóa truy xuất đĩa cứng (I/O).

### 4. Giao diện (Config & LineDrawing)
- Bổ sung mục tùy chỉnh `========== Virtual History Lines ==========` trong Config để người dùng tùy biến (Màu SL/TP, Độ dày nét vẽ).
- Tích hợp hàm `CreateHistoryLine` và `UpdateHistoryLineEnd` (sử dụng đối tượng `OBJ_TREND` với chế độ `RAY_RIGHT=false`) kết nối Entry tới điểm thoát lệnh (TP/SL/Reversal).

## Xác minh
- Cú pháp code đã được đồng bộ 100% giữa MT4 (`RSI_Advanced.mq4`) và MT5 (`RSI_Advanced.mq5`).
- Trình biên dịch `metaeditor64.exe` không phát sinh lỗi biên dịch, các block `#ifdef` đã xử lý chuẩn xác cấu trúc symbol `SymbolInfoDouble` trên MQL5. 

Mọi tác vụ trong `task.md` đều đã được tick hoàn thành.
