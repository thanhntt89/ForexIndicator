# Mastering the RSI (RSI Advanced) - Tổng Hợp Điều Kiện Vào Lệnh

Tài liệu này tóm tắt bộ quy tắc và các trường hợp vào lệnh (Entry Conditions) dựa trên cuốn "Mastering the RSI" của tác giả Tung Nguyen.

## I. Thông Số Cài Đặt (Indicator Setup)

Hệ thống RSI Advanced là sự kết hợp của nhiều chỉ báo lồng vào nhau trên cùng một cửa sổ:
1. **RSI (Đường chính - bị ẩn hoặc không dùng trực tiếp):** Period 10, Apply to Close.
   - Các mức Levels: `20, 32, 50, 68, 80`.
2. **MA Xanh Lá (Fast Signal):** Period 2, Simple, Apply to Previous Indicator's Data (Đường trung bình nhanh của RSI).
3. **MA Đỏ (Slow Signal):** Period 7, Simple, Apply to Previous Indicator's Data (Đường trung bình chậm của RSI).
4. **Bollinger Bands Xanh Da Trời (Volatility Bands):** Period 34, Deviation 1.618, Apply to First Indicator's Data.
5. **MA Cam (Baseline / Trung tâm):** Period 34, Simple, Apply to First Indicator's Data (Chính là trục giữa của Bollinger Bands).

---

## II. Nguyên Tắc Góc Cắt (Angle of Intersection)
- **Góc 12h - 2h (Hướng Lên):** Đại diện cho động lượng Tăng mạnh. Tín hiệu BUY chỉ hợp lệ khi đường Xanh Lá cắt lên đường Đỏ với góc này.
- **Góc 4h - 6h (Hướng Xuống):** Đại diện cho động lượng Giảm mạnh. Tín hiệu SELL chỉ hợp lệ khi đường Xanh Lá cắt xuống đường Đỏ với góc này.
- **Góc 2h - 4h (Sideway):** Động lượng yếu, thị trường đi ngang, không rõ xu hướng.

---

## III. 7 Trường Hợp Vào Lệnh (The 7 Signal Cases)

### Trường hợp 1: Quá Mua / Quá Bán (Reversal)
- **Lệnh BUY:** Đường Xanh Lá rớt ra khỏi dải dưới của Bollinger Bands và nằm dưới mức 32. Sau đó, Xanh Lá cắt ngược lên trên mức 32 VÀ chui lại vào trong Bollinger Bands.
  - *SL:* Đặt dưới đáy gần nhất + Spread.
- **Lệnh SELL:** Đường Xanh Lá vượt ra ngoài dải trên Bollinger Bands và nằm trên mức 68. Sau đó, Xanh Lá cắt ngược xuống dưới mức 68 VÀ chui lại vào trong Bollinger Bands.
  - *SL:* Đặt trên đỉnh gần nhất + Spread.

### Trường hợp 2: Phân Kỳ Hội Tụ (Regular Divergence)
*Xác suất thắng rất cao (lên tới 90% theo tác giả).*
- **Lệnh BUY:** Giá tạo Đáy 2 thấp hơn Đáy 1 (Lower Low), nhưng Xanh Lá và Đỏ tạo Đáy 2 cao hơn Đáy 1 (Higher Low). Lực bán đã cạn.
  - *Entry:* Chờ nến vượt qua đỉnh gần nhất (hoặc dùng Buy Stop).
- **Lệnh SELL:** Giá tạo Đỉnh 2 cao hơn Đỉnh 1 (Higher High), nhưng Xanh Lá và Đỏ tạo Đỉnh 2 thấp hơn Đỉnh 1 (Lower High). Lực mua đã cạn.
  - *Entry:* Chờ nến phá vỡ đáy gần nhất (hoặc dùng Sell Stop).

### Trường hợp 3: Phân Kỳ Hội Tụ Ẩn (Hidden Divergence)
- **Lệnh BUY:** Giá tạo Đáy 2 cao hơn Đáy 1 (Higher Low), nhưng Xanh Lá và Đỏ tạo Đáy 2 thấp hơn Đáy 1 (Lower Low).
  - *Entry:* BUY khi Xanh Lá cắt lên Đỏ với góc 12h-2h.
- **Lệnh SELL:** Giá tạo Đỉnh 2 thấp hơn Đỉnh 1 (Lower High), nhưng Xanh Lá và Đỏ tạo Đỉnh 2 cao hơn Đỉnh 1 (Higher High).
  - *Entry:* SELL khi Xanh Lá cắt xuống Đỏ với góc 4h-6h.

### Trường hợp 4: Tín Hiệu Mạnh Mẽ (Xác Nhận Xu Hướng Lớn)
*Dùng để xác định xu hướng sắp tới trên khung D1, H4.*
- **Xác nhận Tăng:** Đường Xanh Lá cắt LÊN mức 50 ĐỒNG THỜI vượt ra khỏi dải trên của Bollinger Bands.
- **Xác nhận Giảm:** Đường Xanh Lá cắt XUỐNG mức 50 ĐỒNG THỜI rớt ra khỏi dải dưới của Bollinger Bands.
- *Tip:* Khi có xác nhận này trên khung lớn, hãy về khung nhỏ chỉ canh me đánh thuận theo xu hướng đó.

### Trường hợp 5: Điểm Vào Lệnh Tiềm Năng Thường Gặp
- **Lệnh BUY:** Đường Cam đang nằm sát mức 32. Xanh Lá cắt lên Đỏ với góc 12h-2h.
- **Lệnh SELL:** Đường Cam đang nằm sát mức 68. Xanh Lá cắt xuống Đỏ với góc 4h-6h.

### Trường hợp 6: Tiếp Diễn Xu Hướng (Trend Continuation)
- **Lệnh BUY (Kéo ngược - Pullback):** Xanh Lá và Đỏ trước đó đã cắt lên trên đường Cam. Sau đó chúng hồi giá (pullback) quay lại chạm đường Cam nhưng không thể cắt xuyên xuống dưới (hoặc cắt xuống nhẹ rồi bật lên ngay). VÀO LỆNH BUY khi chúng bật lên tiếp diễn.
- **Lệnh SELL (Kéo ngược):** Xanh Lá và Đỏ trước đó đã cắt xuống dưới đường Cam. Sau đó chúng hồi giá chạm đường Cam nhưng không thể cắt xuyên lên trên. VÀO LỆNH SELL khi chúng cắm đầu xuống tiếp.

### Trường hợp 7: Không Xu Hướng (Sideway Squeeze)
- **Dấu hiệu:** Đường Xanh Lá và Đỏ liên tục cắt nhau loạn xạ, xoắn vào nhau và nằm gọn trong dải Bollinger Bands.
- **Hành động:** KHÔNG GIAO DỊCH. Đứng ngoài chờ đợi cho đến khi đường Xanh Lá cắt bứt phá ra khỏi dải Bollinger Bands (Cắt lên thì canh Buy, cắt xuống thì canh Sell).

---

## IV. Quy Trình Giao Dịch Đề Xuất
1. **Bước 1:** Xác định xu hướng trên khung thời gian lớn nhất của phong cách (VD: Scalping thì xem H1/M30; Day Trading thì xem H4/D1).
2. **Bước 2:** Mở khung nhỏ nhất (VD: M1/M5 cho Scalping) để tìm 1 trong 7 tín hiệu trên. Ưu tiên tín hiệu THUẬN với xu hướng ở Bước 1.
3. **Bước 3:** Đặt SL tại đỉnh/đáy gần nhất + Spread. Đặt TP cố định (Scalping: 10-50 pips, Day Trading: 50-150 pips) hoặc TP theo cấu trúc giá.
