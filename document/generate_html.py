"""
RSI Advanced — User Guide HTML Generator
Outputs: RSI_Advanced_User_Guide.html  (open in any browser, print to PDF)
         RSI_Advanced_User_Guide.rsiadv (same content, custom ext — DRM bypass)
"""
import os, shutil

OUT_HTML  = r"f:\Jimmii\Projects\RSI_Advanced\document\RSI_Advanced_User_Guide.html"
OUT_COPY  = r"f:\Jimmii\Projects\RSI_Advanced\document\RSI_Advanced_User_Guide.rsiadv"

# ── CSS ──────────────────────────────────────────────────────────────────────
CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: #0D1117; color: #E6EDF3;
  font-family: 'Segoe UI', Arial, sans-serif;
  font-size: 13px; line-height: 1.6;
  max-width: 960px; margin: 0 auto; padding: 32px 24px;
}
/* HEADER */
.page-header {
  background: linear-gradient(135deg,#161B22 0%,#1F2937 100%);
  border: 1px solid #30363D; border-radius: 12px;
  padding: 40px 48px; margin-bottom: 36px; text-align:center;
}
.page-header h1 { font-size:36px; color:#D4A017; letter-spacing:2px; margin-bottom:10px; }
.page-header .sub { font-size:16px; color:#8B949E; margin-bottom:6px; }
.page-header .ver { font-size:13px; color:#58A6FF; font-weight:600; }
/* TOC */
.toc { background:#161B22; border:1px solid #30363D; border-radius:8px; padding:24px 32px; margin-bottom:36px; }
.toc h2 { color:#58A6FF; font-size:15px; margin-bottom:14px; border-bottom:1px solid #30363D; padding-bottom:8px; }
.toc-section { color:#D4A017; font-weight:700; font-size:12px; margin:10px 0 4px; text-transform:uppercase; }
.toc a { color:#8B949E; text-decoration:none; display:block; padding:2px 0 2px 14px; }
.toc a:hover { color:#58A6FF; }
/* SECTIONS */
h2.section-title {
  font-size:22px; color:#58A6FF; margin:40px 0 20px;
  padding-bottom:10px; border-bottom:2px solid #1F6FEB;
}
h3 { font-size:15px; color:#00D26A; margin:24px 0 10px; }
h4 { font-size:13px; color:#F0B429; margin:18px 0 8px; }
p, li { margin-bottom:6px; color:#C9D1D9; }
ul { padding-left:20px; }
/* TABLES */
table { width:100%; border-collapse:collapse; margin:12px 0 20px; border-radius:8px; overflow:hidden; }
th { background:#1E2A3A; color:#D4A017; font-size:11.5px; padding:10px 12px; text-align:left; border-bottom:2px solid #30363D; }
td { padding:9px 12px; font-size:12px; border-bottom:1px solid #1A1F28; vertical-align:top; }
tr:nth-child(odd)  td { background:#0D1117; }
tr:nth-child(even) td { background:#161B22; }
tr:hover td { background:#1C2333; }
/* CALLOUTS */
.warn { background:#1A0000; border-left:4px solid #FF4444; border-radius:0 6px 6px 0; padding:14px 16px; margin:14px 0; color:#FF9090; }
.tip  { background:#001A0D; border-left:4px solid #00D26A; border-radius:0 6px 6px 0; padding:14px 16px; margin:14px 0; color:#7EE2A8; }
.info { background:#0D1E3A; border-left:4px solid #58A6FF; border-radius:0 6px 6px 0; padding:14px 16px; margin:14px 0; color:#A5C8FF; }
/* COLOR CHIPS */
.g  { color:#00D26A; font-weight:600; }
.y  { color:#F0B429; font-weight:600; }
.r  { color:#FF4444; font-weight:600; }
.bl { color:#58A6FF; font-weight:600; }
.or { color:#FF8C00; font-weight:600; }
.gr { color:#8B949E; }
.go { color:#D4A017; font-weight:600; }
/* CASE CARDS */
.case-card { background:#161B22; border:1px solid #30363D; border-radius:8px; padding:18px 22px; margin:14px 0; }
.case-card .case-num { font-size:11px; font-weight:700; color:#58A6FF; text-transform:uppercase; letter-spacing:1px; }
.case-card .case-name { font-size:16px; color:#00D26A; font-weight:700; margin:4px 0 10px; }
.case-card dl { display:grid; grid-template-columns:110px 1fr; gap:4px 12px; }
.case-card dt { color:#8B949E; font-size:11.5px; align-self:start; padding-top:2px; }
.case-card dd { color:#C9D1D9; font-size:12px; }
/* STEPS */
.step { display:flex; gap:16px; margin:10px 0; }
.step-num { background:#1F6FEB; color:#fff; font-weight:700; font-size:13px;
            width:28px; height:28px; border-radius:50%; display:flex;
            align-items:center; justify-content:center; flex-shrink:0; margin-top:2px; }
.step-body strong { color:#E6EDF3; }
.step-body p { margin:2px 0; color:#8B949E; font-size:12px; }
/* FOOTER */
footer { margin-top:60px; padding-top:20px; border-top:1px solid #30363D;
         text-align:center; color:#484F58; font-size:11px; }
/* PRINT */
@media print {
  body { background:#fff !important; color:#111 !important; max-width:100%; }
  .page-header { background:#f0f4f8 !important; border-color:#ccc !important; }
  .page-header h1 { color:#333 !important; }
  th { background:#e0e7f0 !important; color:#333 !important; }
  td { border-color:#ddd !important; }
  tr:nth-child(odd)  td { background:#f9f9f9 !important; }
  tr:nth-child(even) td { background:#fff !important; }
  .warn { background:#fff5f5 !important; color:#800 !important; }
  .tip  { background:#f5fff9 !important; color:#060 !important; }
  .info { background:#f0f7ff !important; color:#036 !important; }
  .case-card { background:#f8f9fa !important; border-color:#ccc !important; }
  .g,.y,.r,.bl,.or,.go { color:#111 !important; }
  .gr { color:#555 !important; }
}
"""

# ── CONTENT BUILDER ──────────────────────────────────────────────────────────
def tr(*cells, header=False):
    tag = "th" if header else "td"
    return "<tr>" + "".join(f"<{tag}>{c}</{tag}>" for c in cells) + "</tr>"

def table(*rows):
    header = rows[0]
    body   = rows[1:]
    html   = "<table>"
    html  += "<thead>" + tr(*header, header=True) + "</thead>"
    html  += "<tbody>" + "".join(tr(*r) for r in body) + "</tbody>"
    html  += "</table>"
    return html

def step(n, title, detail):
    return f"""<div class="step">
  <div class="step-num">{n}</div>
  <div class="step-body"><strong>{title}</strong><p>{detail}</p></div>
</div>"""

def case_card(num, name, desc, meaning, best, notes):
    notes_html = notes.replace("\n","<br>")
    return f"""<div class="case-card">
  <div class="case-num">Case {num}</div>
  <div class="case-name">{name}</div>
  <dl>
    <dt>Mô tả</dt><dd>{desc}</dd>
    <dt>Ý nghĩa</dt><dd>{meaning}</dd>
    <dt>Tốt nhất khi</dt><dd>{best}</dd>
    <dt>Lưu ý</dt><dd>{notes_html}</dd>
  </dl>
</div>"""

# ── HTML BUILD ───────────────────────────────────────────────────────────────
def build():
    parts = []
    def w(s): parts.append(s)

    w(f"""<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>RSI Advanced — Hướng Dẫn Sử Dụng</title>
<style>{CSS}</style>
</head>
<body>
""")

    # COVER
    w("""<div class="page-header">
  <h1>RSI ADVANCED</h1>
  <p class="sub">Hướng Dẫn Sử Dụng Chỉ Báo</p>
  <p class="sub">MT4 / MT5 &nbsp;·&nbsp; Phiên bản 11.x</p>
  <p class="ver">Thực chiến: khi nào vào lệnh, khi nào thoát, khung thời gian phù hợp</p>
</div>""")

    # TOC
    w("""<div class="toc">
  <h2>Mục Lục</h2>
  <div class="toc-section">Phần 1 — Thực Chiến (đọc trước)</div>
  <a href="#entry">1. Khi Nào Vào Lệnh (Entry Conditions)</a>
  <a href="#exit">2. Khi Nào Thoát Lệnh (Exit Conditions)</a>
  <a href="#tf">3. Khung Thời Gian Tốt Nhất</a>
  <a href="#workflow">4. Workflow Một Lệnh Chuẩn (7 bước)</a>
  <div class="toc-section">Phần 2 — Đọc Bảng Điều Khiển</div>
  <a href="#rec">5. Recommendation Label</a>
  <a href="#prob">6. Xác Suất Tín Hiệu (Probability)</a>
  <a href="#mtf">7. Multi-Timeframe (MTF)</a>
  <a href="#wf">8. Walk-Forward &amp; IC</a>
  <a href="#other">9. Các Thông Số Khác</a>
  <div class="toc-section">Phần 3 — 8 Loại Tín Hiệu</div>
  <a href="#cases">10–17. Case 1–8: Ý Nghĩa &amp; Cách Dùng</a>
  <div class="toc-section">Phần 4 — Lưu Ý &amp; Cảnh Báo</div>
  <a href="#dont">18. Những Điều KHÔNG Được Làm</a>
  <a href="#spread">19. Spread, Volatility &amp; Session Timing</a>
  <a href="#cfg">20. Cài Đặt Khuyến Nghị</a>
</div>""")

    # ── PHẦN 1 ────────────────────────────────────────────────────────────────
    w('<h2 class="section-title">PHẦN 1 — THỰC CHIẾN</h2>')

    # 1. VÀO LỆNH
    w('<h3 id="entry">1. Khi Nào Vào Lệnh</h3>')
    w('<p>Kiểm tra <strong>từ trên xuống dưới</strong>. Chỉ vào lệnh khi <strong>TẤT CẢ 5 điều kiện bắt buộc</strong> thỏa mãn.</p>')

    w('<h4>■ Điều Kiện Bắt Buộc (phải có đủ cả 5)</h4>')
    w(table(
        ["#", "Điều Kiện", "Kiểm Tra Ở Đâu", "Giá Trị Cần"],
        ["1", "Mũi tên tín hiệu xuất hiện trên nến <em>đã đóng</em>",
              "Chart — mũi tên xanh (BUY) / đỏ (SELL)",
              "<span class='r'>KHÔNG</span> vào lệnh khi nến chưa close"],
        ["2", "Recommendation <strong>ENTRY</strong> trở lên",
              "Panel → dòng chữ to đầu tiên",
              "<span class='g'>STRONG ENTRY</span> hoặc <span class='g'>ENTRY</span> &nbsp;·&nbsp; <span class='y'>CAUTION ENTRY</span> = half-size"],
        ["3", "Win% > 50% và R:R > 1:1.5",
              "Panel → mục <em>Prob</em>",
              "Win: XX% &gt; 50% <strong>VÀ</strong> R:R &gt; 1:1.5"],
        ["4", "Edge-left ≥ 40% (signal còn tươi)",
              "Panel → dòng <em>Edge-left</em>",
              "Màu <span class='g'>xanh</span> (>70%) hoặc <span class='y'>vàng</span> (40-70%). <span class='r'>Đỏ</span> = bỏ qua"],
        ["5", "Spread không EXTREME",
              "Panel → dòng Spread",
              "Không hiện <span class='r'>EXTREME</span> hoặc <span class='r'>SPIKE</span>"],
    ))

    w('<h4>■ Điều Kiện Tăng Độ Tin Cậy (càng nhiều càng tốt)</h4>')
    w(table(
        ["Điều Kiện", "Tốt", "Rất Tốt"],
        ["MTF Agreement", "≥ 3/6 TF cùng chiều", "<span class='g'>STRONG BULL/BEAR</span> — ≥ 4/6 TF"],
        ["Vol Regime", "NORMAL", "<span class='g'>QUIET</span> — mean-revert mạnh hơn"],
        ["Session", "London 08-12h UTC", "London+NY Overlap 12-16h UTC"],
        ["Walk-Forward", "<span class='g'>ROBUST</span>", "IS ≈ OOS, IC > 0.05"],
        ["1-Bar Confirm", "Nến sau xác nhận hướng", "Close vượt High/Low nến tín hiệu"],
        ["Case Type", "Case 2, 3 (divergence)", "Case 2, 3 + MTF aligned + QUIET session"],
    ))

    w("""<div class="warn">
<strong>⛔ TUYỆT ĐỐI KHÔNG VÀO LỆNH khi:</strong><br>
• Recommendation = <strong>AVOID</strong> hoặc <strong>AVOID (Counter Trend)</strong><br>
• Vol Regime = <strong>EVENT</strong> (spike / tin tức FOMC, NFP)<br>
• Edge-left &lt; 20% — màu <strong>đỏ</strong> — signal đã hết hạn<br>
• Session = <strong>Dead Zone</strong> (22:00 – 00:00 UTC)<br>
• Nến tín hiệu <strong>chưa đóng</strong> (bar đang chạy)<br>
• Spread = <strong>EXTREME</strong> (> 3x average)
</div>""")

    # 2. THOÁT LỆNH
    w('<h3 id="exit">2. Khi Nào Thoát Lệnh</h3>')
    w('<h4>■ Thoát Tự Động (TP/SL đặt sẵn)</h4>')
    w(table(
        ["Mục Tiêu", "Chiến Lược", "Ghi Chú"],
        ["TP1 hit", "Đóng 50% vị thế → dời SL về breakeven",
                    "Panel hiển thị xác suất TP1 (thường 52–68%)"],
        ["TP2 hit", "Đóng thêm 30% → giữ 20% còn lại",
                    "TP2 ≈ 1.618× TP1 distance (Fibonacci)"],
        ["TP3 hit", "Đóng toàn bộ 100%",
                    "TP3 ≈ 2.618× TP1 distance"],
        ["SL hit",  "Đóng toàn bộ — <span class='r'>không</span> thêm vào",
                    "SL đã được tính từ swing structure + ATR buffer"],
    ))

    w('<h4>■ Thoát Chủ Động (theo dõi panel)</h4>')
    w(table(
        ["Tín Hiệu Thoát", "Mức Độ Khẩn", "Hành Động"],
        ["Edge-left đổi sang <span class='r'>ĐỎ</span> (&lt;20%)",
                "<span class='r'>🔴 Cao</span>",
                "Xem xét đóng — signal đã expired"],
        ["Recommendation đổi thành <span class='r'>AVOID</span>",
                "<span class='r'>🔴 Cao</span>",
                "Đóng nếu chưa đạt TP1"],
        ["Panel: <em>'PRICE BREACHED SL – Signal invalidated'</em>",
                "<span class='r'>🔴 Khẩn cấp</span>",
                "Đóng ngay nếu chưa bị SL tự động"],
        ["Vol Regime đột ngột = <span class='r'>EVENT</span>",
                "<span class='or'>🟠 Trung bình</span>",
                "Đóng 50%, giữ SL chặt"],
        ["MTF đảo chiều hoàn toàn (tất cả TF đối lập)",
                "<span class='or'>🟠 Trung bình</span>",
                "Đóng nếu lệnh đang lỗ"],
        ["<em>'Expires ~XXm'</em> — signal sắp hết hạn",
                "<span class='y'>🟡 Thấp</span>",
                "Cân nhắc thoát nếu lệnh chưa lời"],
        ["<em>'!! STALE SIGNAL !!'</em> hiện trên panel",
                "<span class='y'>🟡 Thấp</span>",
                "&gt;20 nến đã qua, P/L âm &gt;50% SL — xem xét đóng"],
    ))

    w("""<div class="tip">
<strong>💡 Chiến lược quản lý lệnh khuyến nghị:</strong><br>
✓ Đặt SL tại mức panel hiển thị — đã tính spread buffer + ATR buffer.<br>
✓ Khi TP1 đạt: dời SL về breakeven → lệnh trở thành 0-risk.<br>
✓ Không can thiệp thủ công khi Recommendation vẫn là ENTRY.<br>
✓ Chỉ thoát sớm khi Edge-left &lt; 20% HOẶC Vol = EVENT.<br>
✓ Không trung bình giá (DCA) khi lệnh đang lỗ.
</div>""")

    # 3. KHUNG TG
    w('<h3 id="tf">3. Khung Thời Gian Tốt Nhất</h3>')
    w(table(
        ["Khung TG", "Đánh Giá", "Tần Suất Tín Hiệu", "Phù Hợp Với"],
        ["M15", "<span class='g'>⭐⭐⭐⭐⭐ TỐT NHẤT</span>", "5–15/tuần",
                "Intraday trader, theo dõi 2–4h/ngày. Gold, Forex major."],
        ["H1",  "<span class='g'>⭐⭐⭐⭐⭐ TỐT NHẤT</span>", "3–8/tuần",
                "Swing trader nhẹ. Xác suất cao hơn M15, ít nhiễu hơn."],
        ["M30", "<span class='g'>⭐⭐⭐⭐ TỐT</span>",         "8–20/tuần",
                "Cân bằng giữa M15 và H1. Phù hợp hầu hết instruments."],
        ["H4",  "<span class='y'>⭐⭐⭐ ĐƯỢC</span>",          "2–5/tuần",
                "Swing dài hạn. Cần vốn lớn hơn cho SL rộng."],
        ["M5",  "<span class='or'>⭐⭐ HẠN CHẾ</span>",       "20–50/tuần",
                "Nhiều false signal. Cần kỷ luật chặt."],
        ["M1",  "<span class='r'>⭐ KHÔNG KHUYẾN NGHỊ</span>","50–200/tuần",
                "Noise cực cao. Spread ăn hết edge trên XAUUSD."],
        ["D1",  "<span class='or'>⭐⭐ ÍT HIỆU QUẢ</span>",   "1–3/tháng",
                "Quá ít data cho probability engine."],
    ))

    w('<h4>■ Theo Instrument</h4>')
    w(table(
        ["Instrument", "Khung TG Tốt Nhất", "Session Tốt Nhất", "Lưu Ý"],
        ["<span class='go'>XAUUSD (Gold)</span>", "M15, H1",
                "London (08–12h UTC)",
                "Spread cao vào news FOMC/NFP — tránh vào lệnh. Case 1 rất hiệu quả."],
        ["EURUSD / GBPUSD", "M15, M30, H1",
                "London+Overlap (08–17h UTC)",
                "Case 2, 3 (divergence) hiệu quả nhất. Spread thường thấp."],
        ["USDJPY", "M30, H1",
                "Tokyo+London (00–12h UTC)",
                "Vol QUIET rất phổ biến — lý tưởng cho RSI."],
        ["US30 / NAS100", "H1, H4",
                "NY session (13–21h UTC)",
                "Vol EVENT thường xuyên — kiểm tra Regime trước khi vào."],
        ["BTCUSD / Crypto", "H1, H4",
                "24/7 — tập trung NY+London",
                "Session quality = 0. Case 4, 6 tốt hơn Case 1."],
    ))

    # 4. WORKFLOW
    w('<h3 id="workflow">4. Workflow Một Lệnh Chuẩn</h3>')
    for i, (t, d) in enumerate([
        ("Mũi tên xuất hiện trên nến đóng",
         "Xem case number trên mũi tên. BUY = xanh lên. SELL = đỏ xuống."),
        ("Kiểm tra Recommendation",
         "Chỉ tiếp tục nếu STRONG ENTRY hoặc ENTRY. CAUTION ENTRY = half-size. Khác = bỏ qua."),
        ("Kiểm tra Probability",
         "Win% > 50%? R:R > 1:1.5? Edge-left ≥ 40%? 'Expires ~30m' đã hiện = quá trễ."),
        ("Kiểm tra MTF",
         "Ít nhất 3/6 TF cùng chiều. 'STRONG BULL/BEAR' = điểm cộng. MTF against = cân nhắc bỏ."),
        ("Kiểm tra môi trường",
         "Vol Regime ≠ EVENT. Spread ≠ EXTREME. Session ≠ Dead Zone (22–00h UTC)."),
        ("Đặt lệnh",
         "Entry tại giá trên panel. SL và TP1/TP2/TP3 đã tính sẵn — dùng đúng mức đó."),
        ("Quản lý lệnh",
         "TP1 hit → dời SL về breakeven. Theo dõi Edge-left. Đóng khi Edge-left < 20%."),
    ], 1):
        w(step(i, t, d))

    # ── PHẦN 2 ────────────────────────────────────────────────────────────────
    w('<h2 class="section-title">PHẦN 2 — ĐỌC BẢNG ĐIỀU KHIỂN</h2>')

    # 5. RECOMMENDATION
    w('<h3 id="rec">5. Recommendation Label</h3>')
    w(table(
        ["Label (Màu)", "Score", "EV", "Hành Động", "Risk %"],
        [f"<span class='g'>STRONG ENTRY</span> (xanh sáng)", "≥ 75/100", "> +0.15R",
                "Vào lệnh với full size", "1.5 – 2.0%"],
        [f"<span class='g'>ENTRY</span> (xanh)", "55–74", "> +0.05R",
                "Vào lệnh với standard size", "1.0 – 1.5%"],
        [f"<span class='y'>CAUTION ENTRY</span> (vàng)", "35–54", "> 0",
                "Vào lệnh với half size hoặc bỏ qua", "0.5 – 1.0%"],
        [f"<span class='or'>WAIT</span> (cam)", "< 35", "> -0.05R",
                "Không vào, chờ điều kiện tốt hơn", "0%"],
        [f"<span class='r'>AVOID</span> (đỏ)", "bất kỳ", "≤ -0.05R",
                "Bỏ qua hoàn toàn", "0%"],
        [f"<span class='r'>AVOID (Counter Trend)</span> (đỏ)", "bất kỳ", "âm",
                "Ngược xu hướng MTF — nguy hiểm", "0%"],
    ))
    w('<p class="gr">Score = EV (0–50) + Data confidence (0–25) + MTF (0–5) + Intermarket (0–10) ± Walk-Forward (±5–10) ± Spread (–7/–2)</p>')

    # 6. PROBABILITY
    w('<h3 id="prob">6. Xác Suất Tín Hiệu (Probability)</h3>')
    w(table(
        ["Thông Số Panel", "Ý Nghĩa", "Đọc Như Thế Nào"],
        ["Win: XX% → YY%", "Xác suất đạt TP1",
                "'68%→55%' = lúc tươi 68%, sau time-decay còn 55%. Cần > 50%."],
        ["TP1/TP2/TP3: XX% (m/n)", "Xác suất đạt từng TP",
                "m = số lần đạt TP, n = tổng samples. TP1 ≥ TP2 ≥ TP3."],
        ["Edge: XX.X%", "Lợi thế thực của signal",
                "Edge 54% = 54/100 lần đúng chiều. &lt;51% = không có edge."],
        ["TP1~Xbars  SL~Ybars", "Số nến trung bình đến TP1/SL",
                "'TP1~15bars SL~4bars' = TP sau ~15 nến, SL sau ~4 nến."],
        ["Edge-left: Y%", "% edge còn lại (Weibull survival)",
                "<span class='g'>Xanh</span> >70% · <span class='y'>Vàng</span> 40–70% · <span class='or'>Cam</span> 20–40% · <span class='r'>Đỏ</span> &lt;20%"],
        ["Expires ~XXm", "Thời gian trước khi edge = 15%",
                "Cảnh báo thời gian — không phải đóng lệnh tự động."],
    ))

    # 7. MTF
    w('<h3 id="mtf">7. Multi-Timeframe (MTF)</h3>')
    w(table(
        ["Hiển Thị", "Ý Nghĩa"],
        [f"<span class='g'>BUY</span> / <span class='r'>SELL</span> / <span class='gr'>WAIT</span>",
                "Xu hướng của timeframe đó. BUY = RSI ủng hộ long."],
        ["[XX.X] OB / &gt;&gt; / &lt;&lt; / OS",
                "Vùng RSI: OB=overbought(&gt;68) · &gt;&gt;=trên50 · &lt;&lt;=dưới50 · OS=oversold(&lt;32)"],
        ["<span class='g'>STRONG BULL</span> / <span class='g'>WEAK BULL</span>",
                "Đa số TF đồng ý BUY. STRONG &gt; 50% TF."],
        ["<span class='r'>STRONG BEAR</span> / <span class='r'>WEAK BEAR</span>",
                "Đa số TF đồng ý SELL."],
        ["<span class='gr'>MIXED</span>",
                "TF chia đều — rủi ro cao, cân nhắc bỏ qua signal."],
        ["ALIGNED / AGAINST",
                "<span class='g'>ALIGNED</span> = signal cùng chiều MTF (tốt). <span class='r'>AGAINST</span> = ngược chiều (cẩn thận)."],
    ))

    # 8. WALK-FORWARD + IC
    w('<h3 id="wf">8. Walk-Forward Validation &amp; Information Coefficient (IC)</h3>')
    w(table(
        ["Thông Số", "Ý Nghĩa", "Diễn Giải"],
        ["IS: XX% (n=Y)", "In-sample win rate",
                "Win rate trên 70–80% data đầu. Thường cao hơn OOS."],
        ["OOS: XX% (n=Y)", "Out-of-sample win rate",
                "Win rate trên data gần nhất — thực tế hơn IS."],
        [f"Ratio: X.XX <span class='g'>[ROBUST]</span>", "IS/OOS ratio",
                "&lt;1.15 = <span class='g'>ROBUST</span>. ≥1.15 = <span class='r'>OVERFIT WARNING</span> — giảm size 50%."],
        ["IC: X.XXX", "Information Coefficient",
                "<span class='g'>STRONG</span> (&gt;0.10): score predict được. "
                "<span class='y'>WEAK</span> (0.05–0.10): marginal. "
                "<span class='r'>NOISE</span> (&lt;0.05): score không có giá trị dự báo."],
    ))

    # 9. CÁC THÔNG SỐ KHÁC
    w('<h3 id="other">9. Các Thông Số Khác</h3>')
    w(table(
        ["Mục", "Hiển Thị", "Cần Chú Ý Khi Nào"],
        ["Vol Regime", "QUIET / NORMAL / TRENDING / EVENT",
                "<span class='r'>EVENT</span> = tránh vào. <span class='g'>QUIET</span> = RSI signals mạnh nhất."],
        ["ATR Ratio", "ATR:X.XXx",
                "&gt;1.8x = EVENT. &lt;0.6x = QUIET. 1.0x = bình thường."],
        ["Spread", "Normal / SPIKE / EXTREME",
                "<span class='r'>EXTREME</span> = không vào. SPIKE = đợi normalize (2–5 phút)."],
        ["Rolling Perf", "10sig:XX% 20sig:XX% All:XX%",
                "<span class='r'>!! DECLINING !!</span> = win rate đang giảm — giảm size."],
        ["Intermarket", "DXY direction | Corr score",
                "XAUUSD: DXY tăng = Gold yếu. Corr âm = USD không ủng hộ Gold BUY."],
        ["P/L hiện tại", "+/-XX pips (X.XXR)",
                "Theo dõi so sánh với Edge-left để quyết định thoát sớm."],
    ))

    # ── PHẦN 3 ────────────────────────────────────────────────────────────────
    w('<h2 class="section-title">PHẦN 3 — 8 LOẠI TÍN HIỆU</h2>')
    w('<p id="cases">Chỉ báo phát hiện 8 loại tín hiệu (cases). Mỗi case có điều kiện, hiệu quả theo session và cách sử dụng khác nhau.</p><br>')

    cases = [
        (1, "OB/OS Bounce",
         "RSI vào vùng Overbought (&gt;70) hoặc Oversold (&lt;30) rồi bật ngược lại.",
         "RSI quay đầu từ vùng cực — giá có khả năng hồi về trung bình.",
         "Asian session (00–08h UTC). Vol Regime = QUIET. Thị trường sideway.",
         "• Hiệu quả nhất khi Vol Regime = QUIET.\n• Tránh khi có tin tức lớn (EVENT).\n• Kết hợp với TF cao hơn cũng trong vùng extreme."),
        (2, "Regular Divergence",
         "Giá tạo đỉnh cao hơn nhưng RSI đỉnh thấp hơn (bearish). Hoặc đáy thấp hơn nhưng RSI đáy cao hơn (bullish).",
         "Momentum đang yếu đi — xu hướng hiện tại có thể đảo chiều. Case TIN CẬY NHẤT.",
         "London+Overlap (08–16h UTC). Trend reversal setup.",
         "• Mạnh nhất trong 8 cases về độ tin cậy.\n• Cần swing point rõ ràng — không count nếu quá gần.\n• Angle strength ít quan trọng, structure mới là chính."),
        (3, "Hidden Divergence",
         "Giá đáy cao hơn nhưng RSI đáy thấp hơn (bullish hidden). Ngược lại cho bearish.",
         "Điều chỉnh trong xu hướng — giá sẽ tiếp tục theo trend gốc.",
         "London+NY Overlap (12–16h UTC). Strong trending market.",
         "• Dùng để vào theo xu hướng sau pullback.\n• MTF alignment bắt buộc — phải có trend rõ trên TF cao.\n• Không dùng trong thị trường sideway."),
        (4, "Strong Trend",
         "RSI vượt qua ngưỡng 50 với momentum mạnh (angle strength Z-score cao).",
         "Xu hướng mạnh đang hình thành — momentum breakout.",
         "London Open (08–10h UTC). Vol Regime = TRENDING.",
         "• Cần Vol Regime = TRENDING để hiệu quả nhất.\n• Angle strength Z-score &gt; 1.5 = tín hiệu mạnh.\n• SL có thể rộng hơn bình thường."),
        (5, "Orange Near Level",
         "RSI đang tiếp cận ngưỡng OB/OS từ phía trong — chưa vào hẳn nhưng gần.",
         "Cảnh báo sớm — giá đang tiến đến vùng reversal tiềm năng.",
         "Asian+London (04–12h UTC).",
         "• Tín hiệu SỚM — xác suất thấp hơn Case 1.\n• Nên chờ thêm 1-bar confirmation.\n• Dùng half-size so với Case 1."),
        (6, "Trend Continuation",
         "RSI trong vùng 40–60, pullback nhẹ rồi tiếp tục xu hướng chính.",
         "Xu hướng chính vẫn mạnh, đây là điểm entry tốt sau pullback.",
         "NY session (13–21h UTC). Trending instruments.",
         "• MTF phải STRONG BULL/BEAR — không dùng khi MTF MIXED.\n• Stop lỗ chặt (ATR × 1.0).\n• Tốt cho Index (US30, NAS100) và trending Forex."),
        (7, "Sideway Breakout",
         "RSI thoát khỏi vùng sideway hẹp (45–55) với momentum tăng đột biến.",
         "Thị trường đang compress, chuẩn bị breakout ra khỏi range.",
         "London Open (08–10h UTC). Cuối Asian session (06–08h UTC).",
         "• Cần confirm bằng Vol Regime chuyển TRENDING.\n• False breakout phổ biến — chờ close vượt ngưỡng.\n• R:R rất tốt khi thắng dù tỷ lệ thắng không cao nhất."),
        (8, "Basic Crossover",
         "RSI cắt qua đường tín hiệu (signal line) — tín hiệu cơ bản nhất.",
         "Momentum đổi chiều đơn giản.",
         "Phù hợp mọi session nhưng hiệu quả nhất London.",
         "• Case yếu nhất — chỉ vào khi đủ điều kiện khác.\n• Cần MTF alignment mạnh.\n• Dùng half-size."),
    ]
    for c in cases:
        w(case_card(*c))

    # ── PHẦN 4 ────────────────────────────────────────────────────────────────
    w('<h2 class="section-title">PHẦN 4 — LƯU Ý VÀ CẢNH BÁO</h2>')

    # 18. KHÔNG LÀM
    w('<h3 id="dont">18. Những Điều KHÔNG Được Làm</h3>')
    w(table(
        ["❌ Đừng Làm", "Lý Do"],
        [f"<span class='r'>✗ Vào lệnh khi nến chưa đóng</span>",
                "Tín hiệu có thể biến mất. Chỉ báo tính trên closed bar."],
        [f"<span class='r'>✗ Trung bình giá (DCA) khi lệnh lỗ</span>",
                "SL đã tính khoa học. Thêm vào lệnh thua phá vỡ risk management."],
        [f"<span class='r'>✗ Kéo SL về phía lỗ</span>",
                "Nếu SL gần bị hit, market đã cho tín hiệu sai. Không widen stop."],
        [f"<span class='r'>✗ Vào lệnh khi Recommendation = AVOID</span>",
                "EV âm = kỳ vọng lỗ mỗi lệnh về mặt toán học."],
        [f"<span class='r'>✗ Bỏ qua Vol Regime = EVENT</span>",
                "Tin tức lớn làm spread tăng 3–10x, behavior thay đổi hoàn toàn."],
        [f"<span class='r'>✗ Chỉ xem TF thấp, bỏ qua MTF</span>",
                "Counter-trend signal thường thua. MTF là sanity check quan trọng."],
        [f"<span class='r'>✗ Scalping M1 với chỉ báo này</span>",
                "Probability engine cần đủ bar history. M1 quá nhiễu, spread ăn edge."],
        [f"<span class='r'>✗ Ignore Walk-Forward OVERFIT WARNING</span>",
                "Warning = system nhớ quá khứ tốt nhưng forward performance kém → giảm 50% size."],
    ))

    # 19. SPREAD + SESSION
    w('<h3 id="spread">19. Spread, Volatility &amp; Session Timing</h3>')
    w('<h4>Spread — Ảnh Hưởng Lên Xác Suất</h4>')
    w(table(
        ["Trạng Thái", "Spread/ATR", "Tác Động Prob", "Khuyến Nghị"],
        [f"<span class='g'>Normal</span>",    "&lt; 10%", "Ít",       "Vào bình thường"],
        [f"<span class='y'>SPIKE</span>",     "10–30%",  "~–5%",     "Cẩn thận, size nhỏ"],
        [f"<span class='r'>EXTREME</span>",   "&gt; 30%", "~–20%",   "Không vào — đợi normalize"],
    ))

    w('<h4>Session Timing (UTC)</h4>')
    w(table(
        ["Session", "Giờ UTC", "Chất Lượng", "Ghi Chú"],
        ["Asian",       "00–08h", "<span class='y'>Trung bình</span>",
                "Ít vol, tốt cho Case 1. Spread thấp."],
        ["London Open", "08–12h", "<span class='g'>Tốt nhất</span>",
                "Cao nhất cho Case 2, 3, 4, 7. Vol tăng đột biến."],
        ["NY Overlap",  "12–16h", "<span class='g'>Rất tốt</span>",
                "Tốt cho tất cả cases. Liquidity cao nhất."],
        ["Late NY",     "16–22h", "<span class='y'>Trung bình</span>",
                "Ổn cho Case 6 (trend continuation)."],
        ["Dead Zone",   "22–00h", "<span class='r'>Tránh</span>",
                "Spread tăng, liquidity thấp, nhiều false signal."],
    ))

    # 20. CÀI ĐẶT
    w('<h3 id="cfg">20. Cài Đặt Khuyến Nghị</h3>')
    w(table(
        ["Tham Số", "Mặc Định", "Khuyến Nghị", "Lưu Ý"],
        ["InpRSIPeriod",       "14",   "14",         "Không đổi — chuẩn Wilder RSI"],
        ["InpSLRatio",         "1.5",  "1.2 – 2.0",  "Forex: 1.2. Gold: 1.5–2.0"],
        ["InpTPRatio",         "2.0",  "1.5 – 2.5",  "R:R tối thiểu 1:1.5"],
        ["InpSLTPMethod",      "ATR",  "Hybrid",      "Hybrid: ATR + Fibonacci — tốt nhất"],
        ["InpShowMTF",         "true", "true",        "Bắt buộc — MTF là filter quan trọng"],
        ["InpUseWalkForward",  "true", "true",        "Bắt buộc — phát hiện overfitting"],
        ["InpOOSPercent",      "20",   "20 – 25",     "Không &lt;15%. 20% là chuẩn."],
        ["InpProbMaxBars",     "3000", "2000 – 3000", "M15: 2000. H1: 3000."],
        ["InpMaxBars",         "5000", "3000 – 5000", "Nhiều hơn = accurate hơn"],
        ["InpEntryZoneCount",  "4",    "3 – 5",       "M15: 3. H1+: 4–5"],
        ["InpUseSpreadRegime", "true", "true",        "Filter EXTREME spread"],
    ))

    w("""<div class="tip">
<strong>💡 Lời Khuyên Cuối:</strong><br>
1. Chạy indicator trên H1/XAUUSD 2 tuần đầu chỉ để <strong>quan sát</strong> — chưa vào lệnh.<br>
2. Walk-Forward cần tối thiểu 15–20 tín hiệu để có kết quả ý nghĩa.<br>
3. Khi IC = NOISE: angleStrength không predict outcomes — dựa nhiều hơn vào Case type + MTF.<br>
4. Luôn đặt SL theo panel — KHÔNG đặt SL cảm tính nhìn chart.<br>
5. Nhật ký giao dịch: ghi Case number, Recommendation, Edge-left% và kết quả. Sau 30 lệnh sẽ thấy pattern.
</div>""")

    # FOOTER
    w("""<footer>
RSI Advanced User Guide &nbsp;·&nbsp; Phiên bản 11.x &nbsp;·&nbsp; MT4 / MT5<br>
Mở bằng bất kỳ trình duyệt nào. In ra PDF: Ctrl+P → Save as PDF.
</footer>
</body></html>""")

    return "".join(parts)


html_content = build()

with open(OUT_HTML, "w", encoding="utf-8") as f:
    f.write(html_content)

shutil.copy2(OUT_HTML, OUT_COPY)

sz_html = os.path.getsize(OUT_HTML)
sz_copy = os.path.getsize(OUT_COPY)
print(f"HTML  : {OUT_HTML}  ({sz_html//1024} KB)")
print(f"RSIADV: {OUT_COPY}  ({sz_copy//1024} KB)")
print("Done. Mo bang trinh duyet → Ctrl+P → Save as PDF.")
