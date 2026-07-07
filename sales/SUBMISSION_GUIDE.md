# MQL5 Market — Submission Checklist for RSI Advanced

## Thứ tự thực hiện (Step-by-step)

### BƯỚC 1 — Đăng ký Seller Account
URL: https://www.mql5.com/en/market
1. Đăng nhập / tạo tài khoản mql5.com
2. Vào Profile → "Become a Seller"
3. Điền thông tin thanh toán (PayPal hoặc chuyển khoản)
4. Chờ xét duyệt: 1-2 ngày làm việc

---

### BƯỚC 2 — Chuẩn bị files (ĐÃ XONG)

Thư mục: sales/

01_source_code/
  RSI_Advanced.mq4          ← Upload cho MT4 listing
  RSI_Advanced.mq5          ← Upload cho MT5 listing
  RSI_Advanced_vXX.ex4      ← Compiled MT4 (tham khảo, MQL5 Market tự compile)
  RSI_Advanced_vXX.ex5      ← Compiled MT5 (tham khảo)

02_screenshots/             ← Chọn 6-8 ảnh đẹp nhất để upload
  (15 ảnh hiện có)

03_description/
  product_description_EN.md ← Copy nội dung vào ô Description trên web

04_user_guide/
  RSI_Advanced_UserGuide.html  ← Upload làm Documentation
  RSI_Advanced_UserGuide_VI.pdf

05_changelog/
  CHANGELOG.md              ← Dán vào ô "What's new" mỗi lần update

---

### BƯỚC 3 — Submit sản phẩm
URL: https://www.mql5.com/en/market/new

Điền các trường:
  [ ] Title: "RSI Advanced - Probabilistic Multi-Case Signal Indicator"
  [ ] Category: Indicators
  [ ] Platform: MetaTrader 4 + MetaTrader 5 (tạo 2 listing riêng, hoặc 1 listing MQL5 Market cho phép)
  [ ] Price: $39 (gợi ý) — có thể thêm rental: $15/tháng
  [ ] Description: Paste nội dung từ 03_description/product_description_EN.md
  [ ] Screenshots: Upload 6-8 ảnh từ 02_screenshots/
  [ ] Source file MQ5: Upload 01_source_code/RSI_Advanced.mq5
  [ ] Source file MQ4: Upload 01_source_code/RSI_Advanced.mq4 (MT4 version)
  [ ] Documentation: Upload 04_user_guide/RSI_Advanced_UserGuide.html

---

### BƯỚC 4 — Xét duyệt
- MetaQuotes review: 3-7 ngày làm việc
- Họ kiểm tra: code compile được, không có malware, mô tả khớp chức năng
- Nếu bị từ chối: đọc lý do, sửa và resubmit

---

### BƯỚC 5 — Sau khi được duyệt
- Chia sẻ link sản phẩm lên:
  * Telegram group trader Việt Nam
  * YouTube (video demo)
  * MQL5.com forum / blog
- Theo dõi reviews và phản hồi user

---

## Gợi ý giá

| Loại | Giá gợi ý |
|------|-----------|
| Mua vĩnh viễn | $39 |
| Thuê 1 tháng | $15 |
| Thuê 3 tháng | $35 |

---

## Lưu ý quan trọng

⚠️  MQL5 Market KHÔNG chấp nhận file .ex4/.ex5 từ bên ngoài.
    Phải submit SOURCE CODE (.mq4 / .mq5) — họ tự compile server-side.

⚠️  Description PHẢI viết bằng tiếng Anh.

⚠️  Screenshot tối thiểu 1 ảnh, khuyến khích 6-8 ảnh (tối đa 8).

⚠️  Mỗi lần update code phải resubmit để xét duyệt lại.
