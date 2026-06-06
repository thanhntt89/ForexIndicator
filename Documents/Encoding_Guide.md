# Hướng Dẫn Mã Hóa File (Encoding) & Quy Tắc Viết Comment MQL

Tài liệu này ghi lại nguyên nhân và giải pháp khắc phục lỗi vỡ font/sai mã hóa (encoding/mojibake) xảy ra khi AI Agent hoặc các công cụ lập trình chỉnh sửa file nguồn MQL4/MQL5 (`.mq4`, `.mq5`, `.mqh`).

---

## 1. Nguyên Nhân Gốc Rễ (Root Cause)

*   **Xung đột mã hóa giữa các Editor**: 
    *   Trình soạn thảo **MetaEditor** (của MetaQuotes) thường sử dụng mã hóa **ANSI (Windows-1252 / Windows-1258)** hoặc **UTF-8 với BOM (Byte Order Mark)** để đọc và hiển thị các file mã nguồn.
    *   Các công cụ chỉnh sửa tự động (như IDE bên thứ ba hoặc các AI Agent thông qua file write API) lại ghi nội dung dưới dạng **UTF-8 chuẩn (UTF-8 without BOM)**.
*   **Hiện tượng Double-Encoding (Mojibake)**:
    *   Khi file được ghi dưới dạng UTF-8 (không có dấu hiệu nhận biết BOM), MetaEditor mở lên và thông dịch các byte UTF-8 của ký tự tiếng Việt có dấu dưới dạng mã ANSI/Windows-1252.
    *   Sau đó, khi lưu lại, các ký tự đã bị thông dịch sai này lại được mã hóa ngược một lần nữa, tạo ra các chuỗi ký tự lỗi chồng chéo (ví dụ: chữ `Khởi` biến thành `KhÃƒÆ’Ã‚Â¡Ãƒâ€šÃ‚Â»Ãƒâ€¦Ã‚Â¸i`).

---

## 2. Giải Pháp Phòng Ngừa & Nguyên Tắc Lập Trình (Bắt Buộc Cho AI)

Để đảm bảo code luôn biên dịch chuẩn xác và không bị lỗi hiển thị font giữa các môi trường (Git, MetaEditor, VS Code, AI Tools), tất cả các AI Agent khi làm việc trên dự án này phải tuân thủ nghiêm ngặt các quy tắc sau:

### Quy Tắc 1: Chỉ Sử Dụng Ký Tự ASCII (Không Dấu) Trong File Mã Nguồn
*   **KHÔNG** viết tiếng Việt có dấu trong các dòng comment (`//` hoặc `/* ... */`).
*   Tất cả comment giải thích mã nguồn phải được viết bằng **tiếng Anh** hoặc **tiếng Việt không dấu**.
    *   *Sai*: `// Khởi tạo logger tại đây`
    *   *Đúng*: `// Initialize logger here` hoặc `// Khoi tao logger tai day`

### Quy Tắc 2: Xử Lý Chuỗi Ký Tự Hiển Thị Trên Chart / Panel
*   Nếu cần hiển thị tiếng Việt trên đồ thị (Label, Button, Panel) hoặc xuất ra file log:
    *   Sử dụng mã hóa tiếng Việt không dấu để hiển thị an toàn nhất (ví dụ: `LUAT TRANH CHAP` thay vì `LUẬT TRANH CHẤP`).
    *   Nếu bắt buộc phải dùng tiếng Việt có dấu trên giao diện, hãy sử dụng các chuỗi Unicode/Hex hoặc tách biệt tài nguyên ngôn ngữ, không viết trực tiếp ký tự có dấu vào file code logic chính.

### Quy Tắc 3: Kiểm Tra Lại File Sau Khi Ghi
*   Trước khi commit, hãy chạy kiểm tra biên dịch (`make.ps1`) để đảm bảo các thay đổi không phá vỡ cấu trúc file.
*   Nếu phát hiện bất kỳ ký tự lạ nào dạng `Ãƒ`, `Ã`, `Ã‚` trong file source code, hãy khôi phục lại (revert) hoặc sửa ngay lập tức thành ký tự không dấu.

---

## 3. Cách Khắc Phục Khi Gặp Sự Cố

Nếu file vô tình bị vỡ font do ghi đè nhầm định dạng mã hóa:
1.  **Chuyển đổi lại Encoding**: Mở file lỗi bằng các trình soạn thảo chuyên dụng (như VS Code hoặc Notepad++). Sử dụng tính năng **Reopen with Encoding** -> Chọn **UTF-8** hoặc **Windows-1252** để tìm lại trạng thái gốc của ký tự, sau đó chuyển đổi (Save with Encoding) về **UTF-8 with BOM** trước khi mở bằng MetaEditor.
2.  **Khôi phục thủ công**: Đối với các comment bị lỗi, cách nhanh nhất là thay thế toàn bộ dòng comment lỗi đó bằng câu chú thích ngắn gọn bằng tiếng Anh. (Hệ thống MQL chỉ quan tâm đến cú pháp mã nguồn, comment bị thay đổi không ảnh hưởng đến logic hoạt động của chỉ báo/EA).
