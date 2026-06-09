"""
RSI Advanced — User Guide PDF Generator
Uses reportlab with Arial Unicode fonts for full Vietnamese text support.
"""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                  TableStyle, HRFlowable, PageBreak, KeepTogether)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# ── Fonts ────────────────────────────────────────────────────────────────────
FONT_DIR = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("Arial",   os.path.join(FONT_DIR, "arial.ttf")))
pdfmetrics.registerFont(TTFont("ArialB",  os.path.join(FONT_DIR, "arialbd.ttf")))
pdfmetrics.registerFont(TTFont("ArialI",  os.path.join(FONT_DIR, "ariali.ttf")))
pdfmetrics.registerFont(TTFont("ArialBI", os.path.join(FONT_DIR, "arialbi.ttf")))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="ArialB",
                               italic="ArialI", boldItalic="ArialBI")

# ── Colors ───────────────────────────────────────────────────────────────────
C_DARK    = colors.HexColor("#0D1117")
C_PANEL   = colors.HexColor("#161B22")
C_BORDER  = colors.HexColor("#30363D")
C_GREEN   = colors.HexColor("#00D26A")
C_LIME    = colors.HexColor("#39D353")
C_YELLOW  = colors.HexColor("#F0B429")
C_ORANGE  = colors.HexColor("#FF8C00")
C_RED     = colors.HexColor("#FF4444")
C_BLUE    = colors.HexColor("#58A6FF")
C_GRAY    = colors.HexColor("#8B949E")
C_WHITE   = colors.HexColor("#E6EDF3")
C_HEADING = colors.HexColor("#1F6FEB")
C_GOLD    = colors.HexColor("#D4A017")

W, H = A4

# ── Styles ───────────────────────────────────────────────────────────────────
def make_styles():
    s = {}
    def ps(name, **kw):
        kw.pop("parent", None)
        defaults = dict(fontName="Arial", fontSize=10, leading=14,
                        textColor=C_WHITE, backColor=None, spaceAfter=4)
        defaults.update(kw)
        p = ParagraphStyle(name, **defaults)
        s[name] = p
        return p

    ps("normal")
    ps("small",    fontSize=8.5, leading=12, textColor=C_GRAY)
    ps("body",     fontSize=10, leading=15, spaceAfter=6)

    ps("h1", fontName="ArialB", fontSize=22, leading=28,
        textColor=C_BLUE, spaceAfter=6, spaceBefore=8)
    ps("h2", fontName="ArialB", fontSize=15, leading=20,
        textColor=C_BLUE, spaceAfter=4, spaceBefore=14,
        borderPad=4)
    ps("h3", fontName="ArialB", fontSize=12, leading=16,
        textColor=C_GREEN, spaceAfter=3, spaceBefore=10)
    ps("h4", fontName="ArialB", fontSize=10.5, leading=14,
        textColor=C_YELLOW, spaceAfter=2, spaceBefore=7)

    ps("bullet", fontSize=10, leading=14, leftIndent=14,
        spaceAfter=3, firstLineIndent=-10)
    ps("bullet2", fontSize=9.5, leading=13, leftIndent=26,
        spaceAfter=2, firstLineIndent=-10, textColor=C_GRAY)

    ps("tag_green",  fontName="ArialB", fontSize=9, textColor=C_GREEN,
        borderColor=C_GREEN, borderWidth=1, borderPad=3, backColor=colors.HexColor("#0D2818"))
    ps("tag_yellow", fontName="ArialB", fontSize=9, textColor=C_YELLOW,
        borderColor=C_YELLOW, borderWidth=1, borderPad=3, backColor=colors.HexColor("#2A2000"))
    ps("tag_red",    fontName="ArialB", fontSize=9, textColor=C_RED,
        borderColor=C_RED, borderWidth=1, borderPad=3, backColor=colors.HexColor("#2A0000"))
    ps("tag_orange", fontName="ArialB", fontSize=9, textColor=C_ORANGE,
        borderColor=C_ORANGE, borderWidth=1, borderPad=3, backColor=colors.HexColor("#2A1500"))
    ps("tag_blue",   fontName="ArialB", fontSize=9, textColor=C_BLUE,
        borderColor=C_BLUE, borderWidth=1, borderPad=3, backColor=colors.HexColor("#0D1E3A"))

    ps("code", fontName="Arial", fontSize=8.5, leading=12,
        textColor=C_LIME, backColor=colors.HexColor("#161B22"),
        leftIndent=10, rightIndent=10, borderPad=6,
        borderColor=C_BORDER, borderWidth=0.5)

    ps("cover_title", fontName="ArialB", fontSize=32, leading=40,
        textColor=C_GOLD, alignment=1, spaceAfter=10)
    ps("cover_sub",   fontName="Arial",  fontSize=14, leading=20,
        textColor=C_GRAY, alignment=1, spaceAfter=6)
    ps("cover_ver",   fontName="ArialB", fontSize=11, leading=16,
        textColor=C_BLUE, alignment=1)

    ps("toc_h",  fontName="ArialB", fontSize=11, textColor=C_BLUE,   spaceAfter=2, spaceBefore=6)
    ps("toc_p",  fontName="Arial",  fontSize=10, textColor=C_GRAY,   spaceAfter=1, leftIndent=14)

    ps("warn", fontName="ArialB", fontSize=10, textColor=C_RED,
        backColor=colors.HexColor("#1A0000"), borderColor=C_RED,
        borderWidth=1, borderPad=8, spaceAfter=8, leftIndent=4)
    ps("tip",  fontName="Arial",  fontSize=10, textColor=C_GREEN,
        backColor=colors.HexColor("#001A0D"), borderColor=C_GREEN,
        borderWidth=1, borderPad=8, spaceAfter=8, leftIndent=4)

    return s

ST = make_styles()

# ── Helpers ──────────────────────────────────────────────────────────────────
def P(text, style="body"): return Paragraph(text, ST[style])
def SP(h=6):               return Spacer(1, h)
def HR():                  return HRFlowable(width="100%", thickness=0.5,
                                              color=C_BORDER, spaceAfter=8, spaceBefore=8)
def B(text):               return f"<b>{text}</b>"
def G(text):               return f'<font color="#00D26A">{text}</font>'
def Y(text):               return f'<font color="#F0B429">{text}</font>'
def R(text):               return f'<font color="#FF4444">{text}</font>'
def BL(text):              return f'<font color="#58A6FF">{text}</font>'
def GR(text):              return f'<font color="#8B949E">{text}</font>'
def OR(text):              return f'<font color="#FF8C00">{text}</font>'

def section_table(rows, col_widths=None, header_row=True):
    """Dark-themed table."""
    if col_widths is None:
        col_widths = [W - 4*cm]
    style = [
        ("BACKGROUND",  (0,0), (-1, 0 if header_row else -1), C_PANEL),
        ("TEXTCOLOR",   (0,0), (-1,-1), C_WHITE),
        ("FONTNAME",    (0,0), (-1,-1), "Arial"),
        ("FONTSIZE",    (0,0), (-1,-1), 9),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [C_DARK, C_PANEL]),
        ("GRID",        (0,0), (-1,-1), 0.4, C_BORDER),
        ("PADDING",     (0,0), (-1,-1), 5),
        ("VALIGN",      (0,0), (-1,-1), "MIDDLE"),
    ]
    if header_row:
        style += [
            ("FONTNAME",  (0,0), (-1,0), "ArialB"),
            ("FONTSIZE",  (0,0), (-1,0), 9.5),
            ("TEXTCOLOR", (0,0), (-1,0), C_GOLD),
            ("BACKGROUND",(0,0), (-1,0), colors.HexColor("#1E2A3A")),
        ]
    t = Table(rows, colWidths=col_widths)
    t.setStyle(TableStyle(style))
    return t


# ══════════════════════════════════════════════════════════════════════════════
# CONTENT
# ══════════════════════════════════════════════════════════════════════════════
def build_story():
    story = []
    add = story.append
    ext = story.extend

    # ── COVER ─────────────────────────────────────────────────────────────────
    ext([SP(120),
         P("RSI ADVANCED", "cover_title"),
         P("Hướng Dẫn Sử Dụng Chỉ Báo", "cover_sub"),
         P("Phiên bản 11.x  ·  MT4 / MT5", "cover_ver"),
         SP(20),
         P(GR("Hướng dẫn thực chiến: khi nào vào lệnh, khi nào thoát,"), "cover_sub"),
         P(GR("khung thời gian phù hợp và cách đọc bảng điều khiển."), "cover_sub"),
         PageBreak()])

    # ── MỤC LỤC ───────────────────────────────────────────────────────────────
    add(P("Mục Lục", "h1"))
    add(HR())
    toc = [
        ("PHẦN 1 — THỰC CHIẾN", [
            "1. Khi Nào Vào Lệnh (Entry Conditions)",
            "2. Khi Nào Thoát Lệnh (Exit Conditions)",
            "3. Khung Thời Gian Tốt Nhất",
            "4. Workflow Một Lệnh Chuẩn",
        ]),
        ("PHẦN 2 — ĐỌC BẢNG ĐIỀU KHIỂN (PANEL)", [
            "5. Recommendation Label",
            "6. Xác Suất Tín Hiệu (Probability)",
            "7. Multi-Timeframe (MTF)",
            "8. Walk-Forward & IC",
            "9. Các Thông Số Khác",
        ]),
        ("PHẦN 3 — 8 LOẠI TÍN HIỆU", [
            "10. Case 1: OB/OS Bounce",
            "11. Case 2: Regular Divergence",
            "12. Case 3: Hidden Divergence",
            "13. Case 4: Strong Trend",
            "14. Case 5: Orange Near Level",
            "15. Case 6: Trend Continuation",
            "16. Case 7: Sideway Breakout",
            "17. Case 8: Basic Crossover",
        ]),
        ("PHẦN 4 — LƯU Ý & CẢNH BÁO", [
            "18. Những Điều KHÔNG Làm",
            "19. Spread và Volatility",
            "20. Cài Đặt Khuyến Nghị",
        ]),
    ]
    for sec, items in toc:
        add(P(B(sec), "toc_h"))
        for item in items:
            add(P(f"• {item}", "toc_p"))
        add(SP(4))
    add(PageBreak())

    # ══════════════════════════════════════════════════════════════════════════
    # PHẦN 1 — THỰC CHIẾN
    # ══════════════════════════════════════════════════════════════════════════
    add(P("PHẦN 1 — THỰC CHIẾN", "h1"))
    add(HR())

    # ── 1. VÀO LỆNH ───────────────────────────────────────────────────────────
    add(P("1. Khi Nào Vào Lệnh", "h2"))
    add(P("Đây là thứ tự kiểm tra <b>từ trên xuống dưới</b>. Chỉ vào lệnh khi <b>TẤT CẢ</b> điều kiện bắt buộc thỏa mãn.", "body"))
    add(SP(4))

    add(P("■ ĐIỀU KIỆN BẮT BUỘC (phải có đủ cả 5)", "h3"))
    rows = [
        ["#", "Điều Kiện", "Kiểm Tra Ở Đâu", "Giá Trị Cần"],
        ["1", "Tín hiệu mới xuất hiện (mũi tên trên chart)",
                "Mũi tên xanh (BUY) / đỏ (SELL)", "Mũi tên phải ở nến đóng hoàn chỉnh, KHÔNG phải nến đang chạy"],
        ["2", "Recommendation là ENTRY trở lên",
                "Panel → dòng đầu to nhất", f"STRONG ENTRY  hoặc  ENTRY\n(CAUTION ENTRY = tùy chọn, risk thấp)"],
        ["3", "Xác suất Win > 50%",
                "Panel → mục Prob",  "Win% > 50%  VÀ  R:R > 1:1.5"],
        ["4", "Signal còn 'tươi' — Edge chưa hết",
                "Panel → dòng Edge-left", "Edge-left ≥ 40%  (màu vàng trở lên)"],
        ["5", "Spread không EXTREME",
                "Panel → dòng Spread",  "Không hiện chữ EXTREME hoặc SPIKE"],
    ]
    add(section_table(rows, col_widths=[0.6*cm, 4.5*cm, 4.2*cm, 6.5*cm]))
    add(SP(10))

    add(P("■ ĐIỀU KIỆN TĂNG ĐỘ TIN CẬY (càng nhiều càng tốt)", "h3"))
    rows2 = [
        ["Điều Kiện", "Tốt", "Rất Tốt"],
        ["MTF Agreement",  "≥ 3/6 TF cùng chiều",   "≥ 4/6 TF cùng chiều (STRONG BULL/BEAR)"],
        ["Vol Regime",     "NORMAL",                   "QUIET (mean-revert mạnh hơn)"],
        ["Session",        "London 08-12h UTC",        "London+NY Overlap 12-16h UTC"],
        ["Walk-Forward",   "ROBUST",                   "IS ≈ OOS, IC > 0.05"],
        ["1-Bar Confirm",  "Nến sau xác nhận hướng",   "Close vượt High/Low nến tín hiệu"],
        ["Case Type",      "Case 2,3 (divergence)",    "Case 2,3 + MTF aligned"],
    ]
    add(section_table(rows2, col_widths=[4.2*cm, 5.2*cm, 6.4*cm]))
    add(SP(8))

    add(P(f'⚠ {R("TUYỆT ĐỐI KHÔNG VÀO LỆNH khi")}:', "h4"))
    no_entry = [
        ("Recommendation = AVOID hoặc AVOID (Counter Trend)", "red"),
        ("Vol Regime = EVENT (spike/tin tức mạnh)", "red"),
        ("Edge-left < 20% (màu đỏ) — signal đã hết hạn", "red"),
        ("Session = Dead Zone (22:00 – 00:00 UTC)", "red"),
        ("Nến tín hiệu đang chạy chưa đóng (bar chưa close)", "red"),
        ("Spread EXTREME hoặc > 3x average", "red"),
    ]
    for txt, _ in no_entry:
        add(P(f'  {R("✗")}  {txt}', "bullet"))
    add(SP(10))

    # ── 2. THOÁT LỆNH ─────────────────────────────────────────────────────────
    add(P("2. Khi Nào Thoát Lệnh", "h2"))
    add(SP(4))

    add(P("■ THOÁT TỰ ĐỘNG (TP/SL đặt sẵn)", "h3"))
    rows3 = [
        ["Mục Tiêu", "Chiến Lược", "Ghi Chú"],
        ["TP1 hit",  "Đóng 50% vị thế, dời SL về breakeven",
                     "Xác suất TP1 hiển thị trong panel (thường 52-68%)"],
        ["TP2 hit",  "Đóng thêm 30%, giữ 20% còn lại",
                     "TP2 thường = 1.618x TP1 distance"],
        ["TP3 hit",  "Đóng toàn bộ 100%",
                     "TP3 thường = 2.618x TP1 distance (Fibonacci extension)"],
        ["SL hit",   "Đóng toàn bộ, không thêm vào lệnh thua",
                     "SL được đặt dưới swing low (BUY) hoặc trên swing high (SELL)"],
    ]
    add(section_table(rows3, col_widths=[2.4*cm, 5.5*cm, 7.9*cm]))
    add(SP(10))

    add(P("■ THOÁT CHỦ ĐỘNG (theo dõi panel để quyết định)", "h3"))
    rows4 = [
        ["Tín Hiệu Thoát", "Mức Độ Khẩn", "Hành Động"],
        ["Edge-left đổi sang ĐỎ (<20%)",
                "🔴 Cao",    "Xem xét đóng vị thế, signal đã expired"],
        ["Recommendation đổi thành AVOID",
                "🔴 Cao",    "Đóng nếu chưa đạt TP1"],
        ["Panel hiện '!! PRICE BREACHED SL – Signal invalidated !!'",
                "🔴 Khẩn cấp", "Đóng ngay nếu chưa bị SL tự động"],
        ["Vol Regime đột ngột = EVENT trong lúc đang giữ lệnh",
                "🟠 Trung bình", "Xem xét đóng 50%, giữ SL chặt"],
        ["MTF đảo chiều hoàn toàn (tất cả TF đối lập)",
                "🟠 Trung bình", "Đóng nếu lệnh đang lỗ"],
        ["Elapsed > avg bars to TP và chưa đạt TP1",
                "🟡 Thấp",   "Panel hiện 'Expires ~XXm' — nên thoát nếu lỗ nhỏ"],
        ["!! STALE SIGNAL – Consider closing !!",
                "🟡 Thấp",   "Lệnh mở > 20 nến, P/L âm > 50% SL — xem xét đóng"],
    ]
    add(section_table(rows4, col_widths=[5.5*cm, 2.5*cm, 7.8*cm]))
    add(SP(10))

    add(P(f'💡 {G("Chiến lược quản lý lệnh khuyến nghị")}', "h4"))
    tips = [
        "Đặt SL ngay tại mức panel hiển thị (đã tính spread buffer + ATR buffer).",
        "Khi TP1 đạt: dời SL lên breakeven → lệnh trở thành 0-risk.",
        "Không can thiệp thủ công khi Recommendation vẫn là ENTRY — để hệ thống chạy.",
        "Chỉ thoát sớm khi Edge-left < 20% HOẶC Vol Regime = EVENT.",
        "Không trung bình giá (average down) khi lệnh đang lỗ.",
    ]
    for t in tips:
        add(P(f'  {G("✓")}  {t}', "bullet"))
    add(SP(10))

    # ── 3. KHUNG THỜI GIAN ────────────────────────────────────────────────────
    add(P("3. Khung Thời Gian Tốt Nhất", "h2"))
    add(SP(4))

    rows5 = [
        ["Khung TG", "Đánh Giá", "Tần Suất Tín Hiệu", "Phù Hợp Với"],
        ["M15",  "⭐⭐⭐⭐⭐ TỐT NHẤT",  "5-15 tín hiệu/tuần",
                 "Intraday trader, theo dõi 2-4h/ngày. Gold, Forex major."],
        ["H1",   "⭐⭐⭐⭐⭐ TỐT NHẤT",  "3-8 tín hiệu/tuần",
                 "Swing trader nhẹ. Xác suất cao hơn M15, ít nhiễu hơn."],
        ["M30",  "⭐⭐⭐⭐ TỐT",         "8-20 tín hiệu/tuần",
                 "Cân bằng giữa M15 và H1. Phù hợp hầu hết instruments."],
        ["H4",   "⭐⭐⭐ ĐƯỢC",          "2-5 tín hiệu/tuần",
                 "Swing trading dài hạn hơn. Cần nhiều vốn hơn cho SL rộng."],
        ["M5",   "⭐⭐ HẠN CHẾ",        "20-50 tín hiệu/tuần",
                 "Nhiều false signal. Chỉ dùng nếu có kỷ luật chặt chẽ."],
        ["M1",   "⭐ KHÔNG KHUYẾN NGHỊ","50-200 tín hiệu/tuần",
                 "Noise cực cao, spread ăn hết edge. Tránh với XAUUSD."],
        ["D1",   "⭐⭐ ÍT HIỆU QUẢ",    "1-3 tín hiệu/tháng",
                 "Quá ít data cho probability engine. Chờ đợi dài."],
    ]
    add(section_table(rows5, col_widths=[1.8*cm, 3.5*cm, 3.5*cm, 7.0*cm]))
    add(SP(8))

    add(P("■ Theo Instrument", "h3"))
    rows6 = [
        ["Instrument", "Khung TG Tốt Nhất", "Session Tốt Nhất", "Lưu Ý"],
        ["XAUUSD (Gold)", "M15, H1",
                "London (08-12h UTC)", "Spread cao vào news FOMC/NFP — tránh vào lệnh"],
        ["EURUSD/GBPUSD", "M15, M30, H1",
                "London+Overlap (08-17h UTC)", "Case 2,3 (divergence) hiệu quả nhất"],
        ["USDJPY", "M30, H1",
                "Tokyo+London (00-12h UTC)", "Vol regime QUIET rất phổ biến — tốt cho RSI"],
        ["US30/NAS100", "H1, H4",
                "NY session (13-21h UTC)", "Vol EVENT thường xuyên — cẩn thận"],
        ["BTCUSD/Crypto", "H1, H4",
                "24/7 — tập trung NY+London", "Session quality = 0 (không áp dụng). Case 4,6 tốt hơn"],
    ]
    add(section_table(rows6, col_widths=[2.8*cm, 2.8*cm, 3.6*cm, 6.6*cm]))
    add(SP(10))

    # ── 4. WORKFLOW ───────────────────────────────────────────────────────────
    add(P("4. Workflow Một Lệnh Chuẩn", "h2"))
    add(SP(4))
    steps = [
        ("Bước 1", "Mũi tên xuất hiện trên nến đóng",
            "Xem case number trên mũi tên. BUY = mũi tên xanh lên. SELL = mũi tên đỏ xuống."),
        ("Bước 2", "Kiểm tra Recommendation",
            "Chỉ tiếp tục nếu STRONG ENTRY hoặc ENTRY. CAUTION ENTRY = half-size. Các trường hợp khác = bỏ qua."),
        ("Bước 3", "Kiểm tra Probability",
            "Win% > 50%? R:R > 1:1.5? Edge-left ≥ 40%? Nếu 'Expires ~30m' đã hiện = quá trễ."),
        ("Bước 4", "Kiểm tra MTF",
            "Ít nhất 3/6 TF cùng chiều. Nếu 'STRONG BULL/BEAR' = điểm cộng. MTF against = cân nhắc bỏ."),
        ("Bước 5", "Kiểm tra môi trường",
            "Vol Regime ≠ EVENT. Spread ≠ EXTREME. Session ≠ Dead Zone (22-00h UTC)."),
        ("Bước 6", "Đặt lệnh",
            "Entry tại giá hiển thị trong panel. SL và TP1/TP2/TP3 đã được tính sẵn — dùng đúng mức đó."),
        ("Bước 7", "Quản lý lệnh",
            "Khi TP1 hit → dời SL về breakeven. Theo dõi Edge-left. Đóng khi Edge-left < 20%."),
    ]
    step_rows = [["Bước", "Hành Động", "Chi Tiết"]] + \
                [[s[0], B(s[1]), s[2]] for s in steps]
    add(section_table(step_rows, col_widths=[1.5*cm, 3.5*cm, 10.8*cm]))
    add(PageBreak())

    # ══════════════════════════════════════════════════════════════════════════
    # PHẦN 2 — PANEL
    # ══════════════════════════════════════════════════════════════════════════
    add(P("PHẦN 2 — ĐỌC BẢNG ĐIỀU KHIỂN", "h1"))
    add(HR())

    # ── 5. RECOMMENDATION ────────────────────────────────────────────────────
    add(P("5. Recommendation Label", "h2"))
    add(SP(4))
    rows7 = [
        ["Label (Màu)", "Score", "EV", "Hành Động", "Risk %"],
        [G("STRONG ENTRY") + " (xanh lá)",
                "≥ 75/100", "> +0.15R", "Vào lệnh với full size",            "1.5 – 2.0%"],
        [G("ENTRY") + " (xanh)",
                "55–74",   "> +0.05R", "Vào lệnh với standard size",         "1.0 – 1.5%"],
        [Y("CAUTION ENTRY") + " (vàng)",
                "35–54",   "> 0",      "Vào lệnh với half size hoặc bỏ qua", "0.5 – 1.0%"],
        [OR("WAIT") + " (cam)",
                "< 35",    "> -0.05R", "Không vào, chờ điều kiện tốt hơn",  "0%"],
        [R("AVOID") + " (đỏ)",
                "bất kỳ",  "≤ -0.05R", "Bỏ qua hoàn toàn",                  "0%"],
        [R("AVOID (Counter Trend)") + " (đỏ)",
                "bất kỳ",  "âm",       "Tín hiệu ngược xu hướng MTF — nguy hiểm", "0%"],
    ]
    add(section_table(rows7, col_widths=[4.2*cm, 1.8*cm, 1.8*cm, 5.5*cm, 2.5*cm]))
    add(SP(6))
    add(P(f'{BL("Score")} được tính từ 4 yếu tố: EV (0-50đ) + Data confidence (0-25đ) + '
          f'MTF alignment (0-5đ) + Intermarket (0-10đ) ± Walk-Forward (±5-10đ) ± Spread penalty (-7đ).', "small"))
    add(SP(10))

    # ── 6. PROBABILITY ───────────────────────────────────────────────────────
    add(P("6. Xác Suất Tín Hiệu (Probability)", "h2"))
    add(SP(4))
    rows8 = [
        ["Thông Số Panel", "Ý Nghĩa", "Đọc Như Thế Nào"],
        ["Win: XX% → YY%",
                "Xác suất đạt TP1",
                "'68%→55%' = lúc tươi 68%, hiện tại sau time-decay còn 55%. Cần > 50% để vào lệnh."],
        ["TP1/TP2/TP3: XX% (m/n)",
                "Xác suất đạt từng mức TP",
                "m = số lần đạt TP trong lịch sử, n = tổng samples. TP1 luôn ≥ TP2 ≥ TP3."],
        ["Edge: XX.X%",
                "Lợi thế thực tế của signal so với random",
                "Edge 54% = cứ 100 lần tương tự, 54 lần đúng chiều. < 51% = không có edge."],
        ["TP1~Xbars  SL~Ybars",
                "Số nến trung bình để đạt TP1/SL",
                "VD: 'TP1~15bars SL~4bars' = thường đạt TP sau 15 nến, SL sau 4 nến."],
        ["Elapsed: X bars | Edge-left: Y%",
                "Bao lâu từ lúc signal, edge còn lại bao nhiêu",
                "Edge-left dựa trên Weibull survival model. Màu: xanh>70%, vàng>40%, cam>20%, đỏ≤20%."],
        ["Expires ~XXm",
                "Ước tính thời gian còn lại trước khi edge = 15%",
                "Đây là cảnh báo thời gian — không phải lệnh đóng tự động."],
        ["Acc:~72-78%",
                "Độ chính xác tổng thể ước tính của hệ thống",
                "Con số tham khảo. Độ chính xác thực tế phụ thuộc vào cách dùng và kỷ luật."],
    ]
    add(section_table(rows8, col_widths=[3.8*cm, 3.8*cm, 8.2*cm]))
    add(SP(10))

    # ── 7. MTF ────────────────────────────────────────────────────────────────
    add(P("7. Multi-Timeframe (MTF)", "h2"))
    add(SP(4))
    rows9 = [
        ["Hiển Thị", "Ý Nghĩa"],
        [G("BUY") + " / " + R("SELL") + " / " + GR("WAIT"),
                "Xu hướng của timeframe đó theo RSI. BUY = RSI đang tăng và ủng hộ long."],
        ["[XX.X] OB / >> / << / OS",
                "Giá trị RSI và vùng: OB=overbought(>68), >>= trên 50, <<=dưới 50, OS=oversold(<32)."],
        ["Cx (Case x)",
                "Loại tín hiệu gần nhất trên timeframe đó (1-8)."],
        [G("STRONG BULL") + " / " + G("WEAK BULL"),
                "Đa số TF đồng ý hướng BUY. STRONG = >50% TF."],
        [R("STRONG BEAR") + " / " + R("WEAK BEAR"),
                "Đa số TF đồng ý hướng SELL."],
        [GR("MIXED"),
                "TF chia đều — không có xu hướng rõ ràng. Rủi ro cao hơn."],
        ["ALIGNED / AGAINST",
                "Signal của bạn ALIGNED = cùng chiều MTF (tốt). AGAINST = ngược chiều (cẩn thận)."],
    ]
    add(section_table(rows9, col_widths=[4.8*cm, 11.0*cm]))
    add(SP(10))

    # ── 8. WALK-FORWARD + IC ─────────────────────────────────────────────────
    add(P("8. Walk-Forward Validation & IC", "h2"))
    add(SP(4))
    rows10 = [
        ["Thông Số", "Ý Nghĩa", "Diễn Giải"],
        ["IS: XX% (n=Y)",
                "In-sample win rate",
                "Win rate trên 70-80% data đầu tiên (training). Thường cao hơn OOS."],
        ["OOS: XX% (n=Y)",
                "Out-of-sample win rate",
                "Win rate trên 20-30% data gần nhất (validation). Đây là thực tế hơn."],
        ["Ratio: X.XX " + G("[ROBUST]"),
                "IS/OOS ratio",
                "< 1.15 = ROBUST (IS không tốt hơn OOS nhiều). ≥ 1.15 = OVERFIT WARNING."],
        [Y("[OVERFIT WARNING]"),
                "Cảnh báo overfitting",
                "Hệ thống đang 'nhớ quá khứ' tốt nhưng kém trong tương lai. Giảm risk."],
        ["IC: X.XXX [STRONG/WEAK/NOISE]",
                "Information Coefficient",
                "Đo xem angleStrength có predict outcomes không.\n"
                "STRONG(>0.10): score đang hoạt động. NOISE(<0.05): score không predict được."],
    ]
    add(section_table(rows10, col_widths=[3.5*cm, 3.5*cm, 8.8*cm]))
    add(SP(10))

    # ── 9. CÁC THÔNG SỐ KHÁC ────────────────────────────────────────────────
    add(P("9. Các Thông Số Khác Trên Panel", "h2"))
    add(SP(4))
    rows11 = [
        ["Mục", "Hiển Thị", "Cần Chú Ý Khi Nào"],
        ["Vol Regime",
                "QUIET / NORMAL / TRENDING / EVENT",
                "EVENT = tránh vào lệnh. QUIET = RSI signals mạnh nhất. TRENDING = ưu tiên Case 4,6."],
        ["ATR Ratio",
                "ATR:X.XXx",
                "> 1.8x = EVENT. < 0.6x = QUIET. 1.0x = bình thường."],
        ["Spread",
                "Normal / SPIKE / EXTREME",
                "EXTREME = tuyệt đối không vào. SPIKE = đợi spread normalize (thường 2-5 phút)."],
        ["Rolling Perf",
                "10sig:XX% 20sig:XX% All:XX%",
                "'!! DECLINING !!' = win rate 10 lệnh gần nhất < 70% của win rate 50 lệnh — cẩn thận."],
        ["Intermarket",
                "DXY: [hướng] | Corr: [score]",
                "Với XAUUSD: DXY tăng = Gold yếu. Corr âm = USD không ủng hộ Gold BUY."],
        ["P/L hiện tại",
                "+/-XX pips (X.XXR)",
                "> -1R và nên thoát trước SL nếu signal đã expired."],
    ]
    add(section_table(rows11, col_widths=[2.5*cm, 4.0*cm, 9.3*cm]))
    add(PageBreak())

    # ══════════════════════════════════════════════════════════════════════════
    # PHẦN 3 — 8 LOẠI TÍN HIỆU
    # ══════════════════════════════════════════════════════════════════════════
    add(P("PHẦN 3 — 8 LOẠI TÍN HIỆU", "h1"))
    add(HR())
    add(P("Chỉ báo phát hiện 8 loại tín hiệu (cases). Mỗi case có điều kiện, "
          "hiệu quả theo session và cách sử dụng khác nhau.", "body"))
    add(SP(6))

    cases = [
        ("Case 1", "OB/OS Bounce",
         "RSI vào vùng Overbought (>70) hoặc Oversold (<30) rồi bật ngược lại.",
         "RSI quay đầu từ vùng cực — giá có khả năng hồi về trung bình.",
         "Asian session (00-08h UTC). Thị trường sideway/mean-revert.",
         "• Hiệu quả nhất khi Vol Regime = QUIET.\n• Tránh khi có tin tức lớn (EVENT).\n• Kết hợp với MTF: TF cao hơn cũng trong vùng extreme.",
         C_GREEN),
        ("Case 2", "Regular Divergence",
         "Giá tạo đỉnh cao hơn nhưng RSI tạo đỉnh thấp hơn (bearish). Hoặc giá đáy thấp hơn nhưng RSI đáy cao hơn (bullish).",
         "Momentum đang yếu đi — xu hướng hiện tại có thể đảo chiều.",
         "London+Overlap (08-16h UTC). Trend reversal.",
         "• Mạnh nhất trong 8 cases về độ tin cậy.\n• Cần swing point rõ ràng — không count khi quá gần.\n• Angle strength ít quan trọng, structure mới quan trọng.",
         C_BLUE),
        ("Case 3", "Hidden Divergence",
         "Giá đáy cao hơn nhưng RSI đáy thấp hơn (bullish hidden). Ngược lại cho bearish.",
         "Điều chỉnh trong xu hướng — giá sẽ tiếp tục theo trend gốc.",
         "London+NY Overlap (12-16h UTC). Strong trending market.",
         "• Dùng để vào theo xu hướng sau pullback.\n• MTF alignment quan trọng — phải có trend rõ trên TF cao hơn.\n• Không dùng trong thị trường sideway.",
         C_BLUE),
        ("Case 4", "Strong Trend",
         "RSI vượt qua ngưỡng 50 với momentum mạnh (angle strength cao).",
         "Xu hướng mạnh đang hình thành — momentum breakout.",
         "London Open (08-10h UTC). Breakout sessions.",
         "• Cần Vol Regime = TRENDING để hiệu quả nhất.\n• Angle strength Z-score > 1.5 = tín hiệu mạnh.\n• SL có thể rộng hơn (dùng swing SL).",
         C_YELLOW),
        ("Case 5", "Orange Near Level",
         "RSI đang tiếp cận ngưỡng OB/OS từ phía trong — chưa vào hẳn nhưng gần.",
         "Vùng cảnh báo sớm — giá đang tiến đến vùng reversal tiềm năng.",
         "Asian+London (04-12h UTC).",
         "• Tín hiệu SỚM — xác suất thấp hơn Case 1.\n• Nên chờ thêm xác nhận (1-bar confirmation).\n• Dùng half-size so với Case 1.",
         C_ORANGE),
        ("Case 6", "Trend Continuation",
         "RSI trong vùng 40-60, pullback nhẹ rồi tiếp tục xu hướng chính.",
         "Xu hướng chính vẫn mạnh, đây là điểm entry sau pullback.",
         "NY session (13-21h UTC). Trending instruments.",
         "• MTF phải STRONG BULL/BEAR — không dùng khi MTF MIXED.\n• Stop lỗ tương đối chặt (ATR × 1.0).\n• Tốt cho Index (US30, NAS100) và trending Forex pairs.",
         C_GREEN),
        ("Case 7", "Sideway Breakout",
         "RSI thoát khỏi vùng sideway hẹp (45-55) với volume tăng.",
         "Thị trường đang compress, chuẩn bị breakout ra khỏi range.",
         "London Open (08-10h UTC). Cuối Asian session (06-08h UTC).",
         "• Cần confirm bằng ATR tăng (Vol Regime chuyển sang TRENDING).\n• False breakout phổ biến — chờ close vượt ngưỡng.\n• Tỷ lệ thắng thấp hơn nhưng R:R rất tốt khi thắng.",
         C_YELLOW),
        ("Case 8", "Basic Crossover",
         "RSI cắt qua đường tín hiệu (signal line) đơn giản.",
         "Tín hiệu cơ bản nhất — momentum đổi chiều.",
         "Phù hợp mọi session nhưng hiệu quả nhất London.",
         "• Case yếu nhất trong 8 — chỉ vào khi có đầy đủ điều kiện khác.\n• Cần MTF alignment mạnh mới đáng tin cậy.\n• Dùng half-size.",
         C_GRAY),
    ]

    for case_num, name, desc, meaning, best_time, notes, clr in cases:
        add(KeepTogether([
            P(f"{case_num}: {name}", "h3"),
            section_table([
                ["Mô Tả", desc],
                ["Ý Nghĩa", meaning],
                ["Tốt Nhất Khi", best_time],
                ["Lưu Ý", notes],
            ], col_widths=[2.4*cm, 13.4*cm], header_row=False),
            SP(8),
        ]))

    add(PageBreak())

    # ══════════════════════════════════════════════════════════════════════════
    # PHẦN 4 — LƯU Ý & CẢNH BÁO
    # ══════════════════════════════════════════════════════════════════════════
    add(P("PHẦN 4 — LƯU Ý VÀ CẢNH BÁO", "h1"))
    add(HR())

    # ── 18. KHÔNG LÀM ─────────────────────────────────────────────────────────
    add(P("18. Những Điều KHÔNG Được Làm", "h2"))
    add(SP(4))
    dont = [
        ("Vào lệnh khi nến tín hiệu chưa đóng",
         "Tín hiệu có thể biến mất trước khi nến đóng. Chỉ báo tính toán trên closed bar."),
        ("Trung bình giá (DCA) khi lệnh đang lỗ",
         "SL đã được tính khoa học từ swing structure + ATR. Thêm vào lệnh thua phá vỡ risk management."),
        ("Move SL về phía lỗ (widen stop)",
         "Nếu SL bị hit, market đã cho biết signal sai. Không kéo SL thêm."),
        ("Vào lệnh khi Recommendation = AVOID",
         "Hệ thống xác định EV âm — kỳ vọng lỗ trung bình mỗi lệnh."),
        ("Bỏ qua Vol Regime = EVENT",
         "Tin tức lớn (FOMC, NFP) làm spread tăng 3-10x và behavior thay đổi hoàn toàn."),
        ("Chỉ xem TF thấp mà bỏ qua MTF",
         "MTF section là 'sanity check' quan trọng. Counter-trend signal thường thua."),
        ("Dùng chỉ báo này cho scalping M1",
         "Probability engine cần đủ bar history để hoạt động. M1 quá nhiễu, spread ăn hết edge."),
        ("Ignore 'OVERFIT WARNING' trên Walk-Forward",
         "Warning này nghĩa là system đang nhớ quá khứ tốt nhưng forward performance kém. Giảm 50% size."),
    ]
    rows12 = [["❌ Đừng Làm", "Lý Do"]] + \
             [[R(f"✗ {d[0]}"), d[1]] for d in dont]
    add(section_table(rows12, col_widths=[6.0*cm, 9.8*cm]))
    add(SP(10))

    # ── 19. SPREAD & VOL ──────────────────────────────────────────────────────
    add(P("19. Spread, Volatility và Timing", "h2"))
    add(SP(4))

    add(P(f'{Y("Spread")} — Ảnh Hưởng Lớn Đến Xác Suất', "h3"))
    sp_rows = [
        ["Trạng Thái Spread", "Spread/ATR", "Tác Động Xác Suất", "Khuyến Nghị"],
        [G("Normal"),      "< 10%",  "Ít ảnh hưởng",   "Vào lệnh bình thường"],
        [Y("SPIKE"),       "10-30%", "Giảm probTP ~5%", "Vào lệnh cẩn thận, size nhỏ hơn"],
        [R("EXTREME"),     "> 30%",  "Giảm probTP ~20%","Không vào lệnh — đợi spread normalize"],
    ]
    add(section_table(sp_rows, col_widths=[2.8*cm, 2.5*cm, 3.8*cm, 6.7*cm]))
    add(SP(8))

    add(P(f'{Y("Session Timing")} — Giờ UTC Tốt Nhất', "h3"))
    sess_rows = [
        ["Session UTC", "Giờ UTC", "Chất Lượng", "Ghi Chú"],
        ["Asian",          "00 – 08h", Y("Trung bình"), "Ít vol, tốt cho Case 1 (OB/OS). Spread thấp."],
        ["London Open",    "08 – 12h", G("Tốt nhất"),   "Cao nhất cho Case 2,3,4,7. Vol tăng đột biến."],
        ["NY Overlap",     "12 – 16h", G("Rất tốt"),    "Tốt cho tất cả cases. Liquidity cao nhất."],
        ["Late NY",        "16 – 22h", Y("Trung bình"), "Ổn cho Case 6 (trend continuation)."],
        ["Dead Zone",      "22 – 00h", R("Tránh"),      "Spread tăng, liquidity thấp, nhiều false signal."],
    ]
    add(section_table(sess_rows, col_widths=[2.8*cm, 2.2*cm, 2.5*cm, 8.3*cm]))
    add(SP(10))

    # ── 20. CÀI ĐẶT KHUYẾN NGHỊ ──────────────────────────────────────────────
    add(P("20. Cài Đặt Khuyến Nghị", "h2"))
    add(SP(4))
    cfg_rows = [
        ["Tham Số", "Giá Trị Mặc Định", "Khuyến Nghị", "Lưu Ý"],
        ["InpRSIPeriod",        "14",  "14",       "Không đổi — chuẩn Wilder RSI"],
        ["InpSLRatio",          "1.5", "1.2 – 2.0","Forex: 1.2. Gold: 1.5-2.0 (volatile)"],
        ["InpTPRatio",          "2.0", "1.5 – 2.5","R:R tối thiểu 1:1.5. Đừng < 1.0"],
        ["InpSLTPMethod",       "ATR", "Hybrid",   "Hybrid tốt nhất: kết hợp ATR + Fibonacci"],
        ["InpShowMTF",          "true","true",      "Bắt buộc bật — MTF là filter quan trọng"],
        ["InpUseWalkForward",   "true","true",      "Bắt buộc bật — phát hiện overfitting"],
        ["InpOOSPercent",       "20",  "20 – 25",  "20% OOS là chuẩn. Không < 15%"],
        ["InpProbMaxBars",      "3000","2000 – 3000","Tăng = chậm hơn. M15 dùng 2000, H1 dùng 3000"],
        ["InpMaxBars",          "5000","3000 – 5000","Số nến lịch sử. Nhiều hơn = accurate hơn"],
        ["InpEntryZoneCount",   "4",   "3 – 5",    "3 zones cho M15, 4-5 cho H1+"],
        ["InpUseSpreadRegime",  "true","true",      "Bật — filter EXTREME spread"],
    ]
    add(section_table(cfg_rows, col_widths=[3.8*cm, 2.5*cm, 2.5*cm, 7.0*cm]))
    add(SP(10))

    add(P(f'💡 {G("Tip cuối")}', "h3"))
    final_tips = [
        "Chạy indicator trên H1 với Gold trong 2 tuần đầu chỉ để quan sát — chưa vào lệnh. Hiểu cách panel phản ứng.",
        "Walk-Forward cần tối thiểu 15-20 tín hiệu để cho kết quả ý nghĩa. Đừng đánh giá sau 3-5 lệnh.",
        "Khi IC = NOISE, tức là angleStrength không predict outcomes — hãy dựa nhiều hơn vào Case type và MTF.",
        "Luôn đặt SL theo panel — KHÔNG nhìn vào chart và đặt SL cảm tính.",
        "Nhật ký giao dịch: ghi lại Case number, Recommendation level, Edge-left% và kết quả. Sau 30 lệnh sẽ thấy pattern.",
    ]
    for i, t in enumerate(final_tips, 1):
        add(P(f'  {G(str(i) + ".")}  {t}', "bullet"))

    add(SP(20))
    add(HR())
    add(P(GR("RSI Advanced User Guide  ·  Phiên bản 11.x  ·  MT4 / MT5  ·  "
             "Tài liệu nội bộ — không phân phối"), "small"))

    return story


# ══════════════════════════════════════════════════════════════════════════════
# BUILD PDF
# ══════════════════════════════════════════════════════════════════════════════
OUT = r"f:\Jimmii\Projects\RSI_Advanced\document\RSI_Advanced_User_Guide.pdf"

doc = SimpleDocTemplate(
    OUT,
    pagesize=A4,
    leftMargin=1.8*cm, rightMargin=1.8*cm,
    topMargin=2.0*cm,  bottomMargin=1.8*cm,
    title="RSI Advanced — Hướng Dẫn Sử Dụng",
    author="RSI Advanced System",
    subject="User Guide v11",
)

def on_page(canvas, doc):
    """Dark header + footer on every page."""
    canvas.saveState()
    w, h = A4
    # Header bar
    canvas.setFillColor(C_PANEL)
    canvas.rect(0, h - 1.5*cm, w, 1.5*cm, fill=1, stroke=0)
    canvas.setFont("ArialB", 8)
    canvas.setFillColor(C_GOLD)
    canvas.drawString(1.8*cm, h - 1.0*cm, "RSI ADVANCED — HƯỚNG DẪN SỬ DỤNG")
    canvas.setFillColor(C_GRAY)
    canvas.setFont("Arial", 8)
    canvas.drawRightString(w - 1.8*cm, h - 1.0*cm, "v11.x  ·  MT4/MT5")
    # Footer
    canvas.setFillColor(C_PANEL)
    canvas.rect(0, 0, w, 1.2*cm, fill=1, stroke=0)
    canvas.setFont("Arial", 8)
    canvas.setFillColor(C_GRAY)
    canvas.drawCentredString(w/2, 0.5*cm, f"Trang {doc.page}")
    canvas.restoreState()

doc.build(build_story(), onFirstPage=on_page, onLaterPages=on_page)
print(f"PDF generated: {OUT}")
