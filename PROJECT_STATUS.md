# RSI Advanced V11.00 - Project Status & Context Summary

Tài liệu này đóng vai trò là **Source of Truth (Nguồn thông tin gốc)** của dự án. AI ở các phiên tiếp theo **BẮT BUỘC** đọc file này để biết trạng thái hiện tại của code, các phát hiện định lượng mới nhất, và các công việc cần tiếp tục triển khai.

---

## 1. Trạng Thái Code & Kiến Trúc Hiện Tại
Dự án đã được cấu trúc lại hoàn chỉnh để hỗ trợ song song cả MT4 và MT5 với tính năng ghi log định lượng:

- **Build Pipeline**: 
  - File `make.ps1` thực hiện build song song `RSI_Advanced.mq4` (MT4) và `RSI_Advanced.mq5` (MT5), sau đó tự động deploy đến toàn bộ các MT4/MT5 Terminals cấu hình sẵn.
- **MT5 Compatibility**: 
  - `RSI_Advanced.mq5` là entry-point cho MT5, sử dụng thư viện dịch dịch ngược `Include/RSI_Advanced/MQLCompat.mqh` để chạy chung mã nguồn logic với MT4 mà không cần sửa đổi file gốc.
- **Logging System (Tối ưu hóa Non-Blocking)**:
  - File `Include/RSI_Advanced/SignalLogger.mqh` ghi log định lượng chi tiết cho 2 file CSV pipe-delimited (`|`): `signals_*.csv` và `outcomes_*.csv` nằm trong thư mục `Files/RSI_Advanced_Logs/`.
  - **Cơ chế RAM Queue + Bulk Flush**: Để tránh tắc nghẽn I/O làm đơ chart, logger lưu dữ liệu tạm thời vào mảng RAM và chỉ flush xuống đĩa tại 3 điểm:
    1. Khi kết thúc vòng lặp nến lịch sử (`fullRecalc`) lúc khởi chạy.
    2. Khi nến mới đóng (`isNewBar`) trong phiên live.
    3. Khi gỡ indicator khỏi chart (`OnDeinit`).
  - **Trạng thái hiện tại**: Logging đã được **TẮT mặc định** trong cấu hình để đảm bảo hiệu năng tối đa khi user sử dụng (`InpEnableSignalLog = false` trong `Config.mqh`). User có thể bật lại tùy ý trong mục Inputs của indicator.

---

## 2. Kết Quả Phân Tích Định Lượng (XAUUSD - M1 vs M5)
Phân tích dựa trên 138 tín hiệu M1 và 130 tín hiệu M5 đã ghi nhận:

### A. So sánh Khung thời gian:
- **Khung M1 hiệu quả hơn M5 về kỳ vọng toán học (Expectancy)**:
  - **M1**: Win Rate (TP1) = **40.6%**, SL Rate = 40.6%. MFE trung bình (1.59 ATR) > MAE trung bình (1.51 ATR) -> Kỳ vọng dương.
  - **M5**: Win Rate (TP1) = **36.7%**, SL Rate = 46.1%. MFE trung bình (1.37 ATR) < MAE trung bình (1.47 ATR) -> Kỳ vọng âm (nếu dùng SL/TP mặc định).

### B. So sánh thế mạnh từng Case:
- **Case 6 (TrendCont - Tiếp diễn xu hướng)**: **Hoạt động tốt trên M1** (WR 42.3% vs M5 35.2%). Động lượng M1 đẩy giá nhanh và chạm TP1 dứt khoát.
- **Case 7 (SidewayBreak - Phá vỡ đi ngang)**: **Hoạt động cực tốt trên M5** (WR **80.0%**, drawdown cực thấp 0.84 ATR) nhưng **rất tệ trên M1** (WR 33.3%). Lý do: M1 tích lũy quá ngắn dẫn đến breakout giả liên tục.

### C. So sánh theo Phiên giao dịch:
- **Phiên tốt nhất**: **London** đối với M5 (WR 54.5%) và **Overlap Âu-Mỹ** đối với M1 (WR 50.0% trên 68 lệnh).
- **Phiên tệ nhất**: **Asian** (M5 WR 26.1%) và **LateNY** (Cả hai khung WR 0.0%). Tránh tuyệt đối giao dịch TrendCont trong 2 phiên này.

---

## 3. Định Hướng Công Việc Cho AI Phiên Tiếp Theo (Next Steps)

Khi tiếp tục phiên làm việc mới, AI cần thảo luận với anh Thanh và triển khai các phần sau:

### Nhiệm vụ 1: Triển khai Bộ lọc Phiên & Hướng Giao Dịch thông minh (Smart Session & Directional Filter)
- Code thêm logic trong `SessionStatistics.mqh` hoặc `SessionFilter.mqh` để:
  - Tự động chặn tín hiệu **Case 6 (TrendCont)** trong phiên **Asian** và **LateNY** (khoảng thời gian từ 16:00 đến 08:00 UTC).
  - Đối với khung **M1**: Cấu hình bộ lọc chỉ cho phép giao dịch trong phiên **Overlap** (12:00 - 16:00 UTC).
  - Ưu tiên lệnh **SELL** trên M1 (WR 48.9%), siết chặt điều kiện hoặc tăng điểm số tối thiểu để lọc bớt lệnh BUY (WR chỉ 24.4%).

### Nhiệm vụ 2: Triển khai Cấu hình R:R Động cho từng Case (Dynamic Case-specific SL/TP)
- Thay đổi hàm `CalculateSLTP()` trong `SLTP.mqh` để:
  - **Case 7 (SidewayBreak) trên M5**: Rút SL xuống **1.2 ATR** (tăng R:R lên 1:1.5 hoặc 1:1.6).
  - **Case 6 (TrendCont) trên M1**: Rút TP1 xuống **1.3 ATR** để tăng win rate chốt lời nhanh.
  - **Case 6 (TrendCont) trên M5**: Rút TP1 xuống **1.2 ATR** và nới SL lên **2.2 ATR** (hoặc tích hợp Trail Stop chặt chẽ từ 0.8 ATR).

### Nhiệm vụ 3: Tích lũy thêm mẫu bằng Strategy Tester
- Bật lại `InpEnableSignalLog = true`.
- Chạy Backtest trên Strategy Tester của MT4 trong khoảng thời gian từ đầu năm 2026 đến nay để tự động ghi nhận **hàng ngàn mẫu** log.
- Chạy lại script Python `compare_logs.py` để cập nhật xác suất với sai số biên cực nhỏ (< ±3%).

---

*Báo cáo phân tích chi tiết được lưu trữ tại:*
* [quant_analysis_report_m1.md](file:///C:/Users/Administrator/.gemini/antigravity-ide/brain/9fd7d0ea-fddb-49b1-a8e2-fb69ae4b027d/quant_analysis_report_m1.md)
* [quant_analysis_report.md](file:///C:/Users/Administrator/.gemini/antigravity-ide/brain/9fd7d0ea-fddb-49b1-a8e2-fb69ae4b027d/quant_analysis_report.md)
* [quant_timeframe_comparison.md](file:///C:/Users/Administrator/.gemini/antigravity-ide/brain/9fd7d0ea-fddb-49b1-a8e2-fb69ae4b027d/quant_timeframe_comparison.md)