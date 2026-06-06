# Báo Cáo So Sánh Định Lượng: M1 vs M5 — RSI Advanced

Báo cáo này so sánh hiệu suất định lượng giữa khung thời gian **M1 (138 tín hiệu)** và **M5 (130 tín hiệu)** trên sản phẩm **XAUUSD/XAUUSDc** từ dữ liệu logs thực tế, nhằm giúp anh xác định khung thời gian nào hiệu quả hơn và những tín hiệu nào tốt nhất trên từng khung.

---

## 1. So Sánh Hiệu Suất Tổng Quan (M1 vs M5)

| Chỉ số | Khung M1 | Khung M5 | So Sánh & Nhận Xét |
| :--- | :---: | :---: | :--- |
| **Tổng số tín hiệu** | 138 | 130 | Tần suất xuất hiện tín hiệu tương đương nhau. |
| **Tỷ lệ thắng (TP1 Hit)** | **40.6%** | **36.7%** | **M1 cao hơn M5 (+3.9%)** |
| **Tỷ lệ cắt lỗ (SL Hit)** | **40.6%** | **46.1%** | **M1 tốt hơn M5 (ít bị quét SL hơn -5.5%)** |
| **Tỷ lệ đóng sớm (Reversal)** | 18.8% | 17.2% | Tương đương nhau (xấp xỉ 17-19%). |
| **MFE/ATR Trung bình** | **1.589** | **1.375** | **M1 vượt trội (+0.21 ATR)** - Lợi nhuận tiềm năng theo ATR của M1 cao hơn. |
| **MAE/ATR Trung bình** | **1.511** | **1.472** | M5 có mức sụt giảm drawdown trung bình thấp hơn một chút. |

> [!NOTE]
> **Kết luận tổng quan**: **Khung M1 hiệu quả hơn M5 về mặt kỳ vọng toán học (Expectancy)**. 
> - Trên **M1**: MFE trung bình (1.589) > MAE trung bình (1.511) -> Kỳ vọng dương.
> - Trên **M5**: MFE trung bình (1.375) < MAE trung bình (1.472) -> Kỳ vọng âm nếu dùng tỷ lệ SL/TP mặc định.

---

## 2. So Sánh Chi Tiết Theo Case (M1 vs M5)

Bảng so sánh Win Rate (TP1) và R:R (MFE/MAE tỷ lệ theo ATR) của từng Case:

| Case | Tên Tín Hiệu | Số lệnh M1 | Win Rate M1 | MFE/MAE (M1) | Số lệnh M5 | Win Rate M5 | MFE/MAE (M5) | Khung vượt trội |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **6** | **TrendCont** | 111 | **42.3%** | 1.65 / 1.56 | 108 | **35.2%** | 1.40 / 1.56 | **M1 vượt trội** |
| **7** | **SidewayBreak** | 9 | **33.3%** | 1.60 / 1.98 | 5 | **80.0%** | 1.93 / 0.84 | **M5 vượt trội hoàn toàn** |
| **4** | **StrongTrend** | 1 | 100% | 2.36 / 0.45 | 4 | 50.0% | 1.83 / 1.85 | Tương đương (Mẫu ít) |
| **3** | **HiddenDiv** | 3 | 33.3% | 0.99 / 0.05 | 4 | 25.0% | 0.53 / 0.23 | Tương đương |
| **5** | **OrangeLevel** | 2 | 0.0% | 0.18 / 1.44 | 4 | 50.0% | 1.19 / 1.02 | M5 tốt hơn |

### Nhận xét quan trọng:
1. **Case 6 (TrendCont - Tiếp diễn xu hướng)** hoạt động **tốt hơn nhiều trên M1**: Win rate cao hơn 7.1%, và MFE/ATR đạt 1.65 (so với 1.40 trên M5). Ở khung M1, động lượng xu hướng tiếp diễn xảy ra rất nhanh và dứt khoát, dễ chạm TP1 trước khi đảo chiều.
2. **Case 7 (SidewayBreak - Phá vỡ đi ngang)** hoạt động **tốt hơn hoàn toàn trên M5**: M5 đạt tỷ lệ thắng **80.0%** (MAE cực nhỏ 0.84 ATR) trong khi M1 chỉ đạt **33.3%** (MAE rất lớn 1.98 ATR). Ở khung M1, các vùng tích lũy đi ngang quá ngắn nên phá vỡ giả (fakeout) xảy ra liên tục. M5 có tích lũy đủ lâu nên khi phá vỡ sẽ đi rất xa.

---

## 3. So Sánh Theo Phiên Giao Dịch (M1 vs M5)

| Phiên (SESSION) | Tín hiệu M1 | Win Rate M1 | MFE/MAE (M1) | Tín hiệu M5 | Win Rate M5 | MFE/MAE (M5) | Đánh Giá Khung Thời Gian |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **London (Âu)** | 63 | **31.7%** | 1.48 / 1.96 | 44 | **54.5%** | 1.82 / 1.47 | **M5 thắng thế** (M1 quá nhiễu trong phiên Âu) |
| **Overlap (Mỹ-Âu)** | 68 | **50.0%** | 1.72 / 1.11 | 22 | **50.0%** | 1.51 / 1.09 | **M1 thắng thế** (Tần suất cao + R:R MFE vượt trội) |
| **Asian (Á)** | 0 | 0.0% | 0.00 / 0.00 | 46 | **26.1%** | 1.11 / 1.55 | M1 không có lệnh (M5 rất tệ trừ Case 7) |
| **LateNY (Cuối Mỹ)** | 2 | 0.0% | 0.38 / 1.24 | 16 | **0.0%** | 0.72 / 1.78 | Cả 2 khung đều thua lỗ 100% |

---

## 4. TOP TÍN HIỆU TỐT NHẤT TRÊN CẢ 2 KHUNG (Mẫu >= 2)

Dưới đây là xếp hạng các "Điểm sáng" (Sweet Spots) tối ưu nhất của chỉ báo dựa trên sự kết hợp giữa **Case + Phiên + Khung thời gian**:

1. **Case 7 (SidewayBreak) — Khung M1 — Phiên Overlap**:
   - **Win Rate: 100%** (3 tín hiệu, 3 thắng).
   - **MFE trung bình: 3.16 ATR** (Cực lớn), MAE trung bình: 1.33 ATR.
   - *Đặc điểm*: Phá vỡ đi ngang vào phiên Mỹ của M1 cho động lượng cực mạnh, giá bay thẳng tắp.
2. **Case 7 (SidewayBreak) — Khung M5 — Phiên Asian**:
   - **Win Rate: 75.0%** (4 tín hiệu, 3 thắng).
   - **MFE trung bình: 1.91 ATR**, MAE trung bình: **0.64 ATR** (Drawdown cực thấp).
   - *Đặc điểm*: Phá vỡ vùng range tích lũy phiên Á trên M5 rất chuẩn xác.
3. **Case 6 (TrendCont) — Khung M5 — Phiên London**:
   - **Win Rate: 56.4%** (39 tín hiệu, 22 thắng).
   - **MFE trung bình: 1.88 ATR**, MAE trung bình: 1.40 ATR.
   - *Đặc điểm*: Đánh tiếp diễn xu hướng vào phiên Âu trên M5 là chuẩn bài nhất.
4. **Case 6 (TrendCont) — Khung M1 — Phiên Overlap**:
   - **Win Rate: 51.8%** (56 tín hiệu, 29 thắng).
   - **MFE trung bình: 1.82 ATR**, MAE trung bình: **1.16 ATR** (Drawdown rất thấp).
   - *Đặc điểm*: Đây là **"cỗ máy in tiền"** thực tế của chỉ báo do tần suất xuất hiện cực lớn (56 tín hiệu) mà vẫn giữ được winrate > 50% cùng R:R dương.

---

## 5. Khuyến Nghị Giao Dịch Cho Anh

Để đạt hiệu quả tối đa khi sử dụng chỉ báo RSI Advanced, anh nên phân chia chiến lược rõ ràng cho 2 khung như sau:

### Chiến lược cho M1:
- **Chỉ giao dịch phiên Overlap (Mỹ-Âu)** (từ 12:00 - 16:00 UTC). Tận dụng **Case 6 (TrendCont)** và **Case 7 (SidewayBreak)**.
- **Tránh xa phiên London** trên M1 vì nhiễu nến làm win rate giảm xuống chỉ còn 31.7% với drawdown rất lớn (MAE 1.96 ATR).

### Chiến lược cho M5:
- **Tập trung đánh phiên London**: Rất hiệu quả cho **Case 6 (TrendCont)** (Win rate 56.4%).
- **Giao dịch phiên Á**: Chỉ chấp nhận tín hiệu **Case 7 (SidewayBreak)** (Win rate 75%, SL siêu ngắn). Chặn hoàn toàn Case 6 trong phiên Á.
