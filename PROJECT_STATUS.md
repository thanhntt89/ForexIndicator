# RSI Advanced V11.00 - Project Status & Context Summary

Tài liệu này đóng vai trò là **Source of Truth (Nguồn thông tin gốc)** của dự án. AI ở các phiên tiếp theo **BẮT BUỘC** đọc file này để biết trạng thái hiện tại của code, các phát hiện định lượng mới nhất, và các công việc cần tiếp tục triển khai.

---

## 1. Trạng Thái Code & Kiến Trúc Hiện Tại
Dự án đã được cấu trúc lại hoàn chỉnh để hỗ trợ song song cả MT4 và MT5 với tính năng ghi log định lượng:

- **Build Pipeline**: File `make.ps1` thực hiện build song song `RSI_Advanced.mq4` (MT4) và `RSI_Advanced.mq5` (MT5).
- **MT5 Compatibility**: Sử dụng `Include/RSI_Advanced/MQLCompat.mqh` để chạy chung mã nguồn logic với MT4.
- **Logging System**: Ghi log định lượng chi tiết với cơ chế RAM Queue + Bulk Flush để chống đơ chart. Đang được tắt mặc định ở `Config.mqh`.

---

## 2. Kết Quả Phân Tích Định Lượng (XAUUSD - M1 vs M5)
- **M1 vs M5**: Khung M1 hiệu quả hơn M5 về kỳ vọng toán học (MFE trung bình lớn hơn MAE trung bình).
- **Phân loại Case**: 
  - *Case 6 (TrendCont)*: Hoạt động rất tốt trên M1, đánh nhanh thắng nhanh. Tránh đánh vào phiên Asian và LateNY.
  - *Case 7 (SidewayBreak)*: Hoạt động cực tốt trên M5, nhưng rất tệ trên M1 do sideway ảo.
- **Phiên Giao Dịch**: Phiên Overlap Âu-Mỹ là phiên ngon nhất cho M1. Phiên London là phiên ngon nhất cho M5.

---

## 3. Các Cập Nhật & Bản Vá Định Lượng Bắt Buộc Ghi Nhớ (Vừa hoàn thành)
AI phiên trước và User Thanh đã phối hợp rà soát toàn diện hệ thống `SLTP.mqh` và `IntermarketAnalysis.mqh` dưới góc độ Quant:

1. **Fix Lỗi Asymmetric Bias trong SL/TP**: 
   Đã gỡ bỏ giới hạn `MathMin/MathMax` trong `CalculateSLTP()`. Thuật toán đo MFE (Lợi nhuận tối đa quá khứ) thông qua `MeasureOptimalTPRatios` giờ đây được phép nới rộng TP (Let Profits Run) nếu lịch sử cho thấy lệnh có thể chạy xa hơn, không còn bị chặn một chiều như trước.
   
2. **Khắc phục Lookahead Bias (Rò rỉ dữ liệu Tương lai)**: 
   Hàm `FindNearestSwingLow` và `FindNearestSwingHigh` đã được ép sử dụng nến đã đóng (`bs = 1` trở lên). Tuyệt đối **không dùng `bs = 0`** để gán biến Depth ATR cho Swing, tránh hiện tượng Repainting SL/TP liên tục khi nến đang chạy.

3. **Luật Bất Thành Văn cho Intermarket Analysis**:
   Khác với SL/TP, hàm `CalculateIntermarketTrend` đóng vai trò là Macro-Momentum Filter. **BẮT BUỘC dùng nến Live (`shift 0`)** cho tính toán ATR và SMA của DXY/EURUSD để EA có thể block lệnh ngay tắp lự khi USD bùng nổ. Không được sửa thành nến `1` nếu không EA sẽ bị mù thông tin vĩ mô chậm 1 nến!

4. **Fix Timeout Data**: 
   Hàm `MeasureOptimalTPRatios` và `MeasureZoneReachProb` đã được sửa để dùng `timeBasedMax`, không bị rớt mất dữ liệu thống kê.

---

## 4. Định Hướng Công Việc Cho AI Phiên Tiếp Theo (Next Steps)

Khi tiếp tục phiên làm việc mới, AI cần thảo luận với anh Thanh và triển khai các phần sau:

### Nhiệm vụ 1: Triển khai Bộ lọc Phiên & Hướng Giao Dịch (Smart Session & Directional Filter)
- Code thêm logic trong `SessionStatistics.mqh` hoặc `SessionFilter.mqh` để:
  - Tự động chặn tín hiệu **Case 6 (TrendCont)** trong phiên **Asian** và **LateNY**.
  - Đối với khung **M1**: Cấu hình bộ lọc chỉ cho phép giao dịch trong phiên **Overlap**.
  - Ưu tiên lệnh **SELL** trên M1 (WR 48.9%), siết chặt điều kiện đối với lệnh BUY (WR chỉ 24.4%).

### Nhiệm vụ 2: Triển khai Cấu hình R:R Động cho từng Case (Dynamic Case-specific SL/TP)
- Thay đổi hàm `CalculateSLTP()` trong `SLTP.mqh` để:
  - **Case 7 (SidewayBreak) trên M5**: Rút SL xuống **1.2 ATR**.
  - **Case 6 (TrendCont) trên M1**: Rút TP1 xuống **1.3 ATR**.
  - **Case 6 (TrendCont) trên M5**: Rút TP1 xuống **1.2 ATR** và nới SL lên **2.2 ATR**.

### Nhiệm vụ 3: Đánh giá Probability Engine với Dữ Liệu Mới
- Do chúng ta vừa nới lỏng giới hạn R:R và fix các lỗi Quant, AI cần hướng dẫn user chạy lại Data Logger thông qua Strategy Tester để thu thập lượng mẫu mới.
- Sau đó chạy script Python để phân tích lại hiệu quả của bộ máy Xác Suất hiện tại.