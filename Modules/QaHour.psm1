# ================================================================
# QaHour.psm1 -- LẤY DỮ LIỆU ACTUAL TỪ HỆ THỐNG QA-HOUR (SFIS), DÙNG ĐỂ CẬP NHẬT MO.db
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================
# Logic request/parse được CHUYỂN THỂ từ MultiRequest_V6-2.ps1 (Invoke-Flow2Worker
# + Parse-QaHourRows + Invoke-GetWithRetry) -- giữ NGUYÊN các fix đã được kiểm
# chứng qua nhiều phiên bản thực tế (V5-4 công thức fromDate/toDate, V5-5 + V5-8
# cách parse bám mốc "PREMOLD-DFU", V6-1 cách bọc kết quả tránh bị PowerShell
# "bung" mảng khi đi qua EndInvoke). KHÔNG tự ý đổi lại logic parse/URL đã được
# kiểm chứng này nếu chưa xác nhận lại với hệ thống QA-HOUR thật.
#
# Hàm LAY_DU_LIEU_QA_HOUR là HÀM THUẦN (KHÔNG đụng vào $global:e / $global:W) --
# an toàn gọi từ CẢ HAI nơi:
#   1) Runspace nền -- chu kỳ 60 giây, ghép chung vào BAT_DAU_LAM_MOI_NEN (main.ps1)
#   2) UI thread -- nút "Làm Mới Nhanh" (gọi trực tiếp, đồng bộ, nên truyền
#      -MaxRetries 1 -TimeoutMs ngắn hơn để tránh treo UI quá lâu)
#
# Kết quả trả về: mảng [PSCustomObject]@{ModelId=...; Actual=...}, ĐÚNG định dạng
# mà CAP_NHAT_ACTUAL_TU_QA_HOUR (Production.psm1) đang chờ sẵn.
# ================================================================

# ── Assembly System.Web cần cho HttpUtility.UrlEncode -- PowerShell 5.1 KHÔNG
# tự nạp sẵn assembly này (khác PresentationFramework/WindowsBase đã nạp trong
# main.ps1), nên phải Add-Type riêng ở đây. An toàn gọi lại nhiều lần (vd mỗi
# lần Runspace nền Import-Module -Force) vì nạp lại assembly đã nạp là vô hại. ──
Add-Type -AssemblyName System.Web

# ── Thiết lập ServicePointManager 1 LẦN cho cả process -- giảm độ trễ request
# (bỏ qua vòng "100 Continue", tắt gom gói Nagle, bỏ qua dò proxy hệ thống vì
# là mạng nội bộ IP tĩnh). Chuyển thể từ Initialize-HttpDefaults trong
# MultiRequest_V6-2.ps1, bỏ lại phần DefaultConnectionLimit vì OTMSAnalyzer
# chỉ gọi 1 request QA-HOUR/chu kỳ (không cần nhiều kết nối song song như
# MultiRequest với hàng chục oven-detail worker cùng lúc). ──
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [Net.ServicePointManager]::Expect100Continue = $false
    [Net.ServicePointManager]::UseNagleAlgorithm = $false
    [System.Net.WebRequest]::DefaultWebProxy = $null
} catch { }

# ── Gọi HTTP GET, thử lại tối đa $MaxRetries lần nếu lỗi/timeout/response rỗng.
# Dùng [System.Net.HttpWebRequest] THUẦN (không Invoke-WebRequest, không cookie)
# -- đúng y hệ MultiRequest_V6-2.ps1 đang chạy ổn định với CHÍNH server này. ──
function LAY_HTML_CO_THU_LAI {
    param([string]$Url, [int]$MaxRetries = 3, [int]$TimeoutMs = 15000, [int]$RetryDelayMs = 300)
    $loiCuoi = $null
    for ($lan = 1; $lan -le $MaxRetries; $lan++) {
        $resp = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method             = 'GET'
            $req.Timeout            = $TimeoutMs
            $req.UserAgent          = 'Mozilla/5.0'
            $req.AllowAutoRedirect  = $true
            $req.CookieContainer    = $null

            $resp   = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $text   = $reader.ReadToEnd()
            $reader.Close()

            if ([string]::IsNullOrEmpty($text)) {
                throw (New-Object System.Exception("Response rỗng từ $Url"))
            }
            return $text
        } catch {
            $loiCuoi = $_
            if ($lan -lt $MaxRetries) { Start-Sleep -Milliseconds $RetryDelayMs }
        } finally {
            if ($resp) { $resp.Close() }
        }
    }
    throw $loiCuoi
}

# ── Parse response QA-HOUR: DÙ TÊN FILE LÀ "getQueryJSON.jsp" NHƯNG RESPONSE THỰC TẾ
# LÀ HTML (không phải JSON) -- dùng chuỗi "PREMOLD-DFU" làm MỐC (chính là giá trị tham
# số lọc groupName=PREMOLD-DFU trong URL, nên luôn có thật trong response).
#
# CÁCH LÀM: tìm thẻ <td> có chứa "PREMOLD-DFU", rồi lấy ĐÚNG 2 thẻ <td> LIÊN KỀ NGAY SAU
# nó -- không có nội dung/thẻ nào khác chen giữa (chỉ cho phép khoảng trắng/xuống dòng
# định dạng giữa các thẻ, KHÔNG cho phép thẻ khác hay text lạ). 3 thẻ này LIỀN NHAU: thẻ
# 1 chứa "PREMOLD-DFU", thẻ 2 = Model ID, thẻ 3 = Actual. Dùng 1 regex bắt cả 3 thẻ cùng
# lúc, khớp từng dòng độc lập với nhau -- KHÔNG còn phụ thuộc "tìm <td> kế tiếp ở bất kỳ
# đâu phía sau trong toàn bộ phần còn lại của trang" như cách làm CŨ (walk substring
# thủ công): cách cũ dễ nhảy nhầm sang <td> KHÔNG liên quan nằm xa hơn trong trang khi
# response CHỈ CÓ 1 dòng dữ liệu (không còn dòng nào khác theo sau để tự nhiên "chặn"
# phạm vi tìm kiếm dừng lại trong phạm vi 1 hàng) -- đây chính là nguyên nhân mất dữ liệu
# khi chỉ có 1 model đang chạy.
function PHAN_TICH_DONG_QA_HOUR {
    param([string]$RawText)
    # SỬA LỖI GỐC (xác nhận qua test thật với dữ liệu QA-HOUR thực tế): response là JSON
    # nên dùng \n để mã hoá xuống dòng (đúng chuẩn JSON) -- trước đây CHỈ giải mã \/ và \"
    # mà THIẾU \n, nên giữa các thẻ <td> vẫn còn nguyên 2 ký tự CHỮ "\" + "n" (không phải
    # ký tự xuống dòng THẬT). Quy tắc regex bên dưới dùng \s* để cho phép khoảng trắng/
    # xuống dòng THẬT giữa các thẻ -- nhưng \s KHÔNG khớp được với 2 ký tự chữ "\n", nên
    # match luôn thất bại HOÀN TOÀN, BẤT KỂ có bao nhiêu dòng dữ liệu (đã kiểm chứng: cả
    # trường hợp 1 model LẪN nhiều model đều 0 dòng khớp trước khi sửa). Thêm cả \r, \t
    # cho đầy đủ (JSON có thể mã hoá cả 2 ký tự này), dù hiện tại chưa thấy xuất hiện
    # thực tế trong response QA-HOUR.
    $daGiaiMa = $RawText.Replace('\/', '/').Replace('\"', '"').Replace('\n', "`n").Replace('\r', "`r").Replace('\t', "`t")
    $ketQua   = New-Object System.Collections.ArrayList

    $mauRegex = '<td[^>]*>[^<]*PREMOLD-DFU[^<]*</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>'
    $dsKhop   = [System.Text.RegularExpressions.Regex]::Matches($daGiaiMa, $mauRegex)

    foreach ($kh in $dsKhop) {
        $modelVal  = $kh.Groups[1].Value.Trim()
        $actualVal = $kh.Groups[2].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($modelVal)) {
            # [void] BẮT BUỘC -- ArrayList.Add() trả về chỉ số vừa thêm, nếu
            # không bọc [void] thì số nguyên đó sẽ "rò rỉ" ra pipeline của hàm,
            # làm kết quả trả về cuối cùng bị trộn lẫn thêm số thừa.
            [void]$ketQua.Add([PSCustomObject]@{
                ModelId = $modelVal
                Actual  = $actualVal
            })
        }
    }

    # ── CHẨN ĐOÁN TỰ ĐỘNG (bổ sung sau khi ghi nhận trường hợp CHỈ 1 MODEL đang chạy
    # không parse được, dù quy tắc trên đã được thiết kế riêng cho đúng tình huống này) --
    # nếu response CÓ chứa "PREMOLD-DFU" (nghĩa là CÓ dữ liệu, không phải do không model
    # nào đang chạy) nhưng quy tắc trên KHÔNG khớp được dòng nào cả, rất có thể cấu trúc
    # HTML thật sự KHÁC với giả định (vd hệ thống QA-HOUR trả về định dạng khác khi chỉ có
    # đúng 1 kết quả, thay vì <td>...</td> liên tiếp như khi có nhiều kết quả). Ghi lại
    # NGUYÊN VĂN 1 đoạn ngắn (khoảng 300 ký tự quanh vị trí tìm thấy "PREMOLD-DFU") vào
    # Loi.log để đối chiếu sau này -- KHÔNG ghi nguyên cả trang (có thể rất dài + chứa dữ
    # liệu sản xuất), và CHỈ ghi khi thật sự nghi ngờ bất thường (có mốc nhưng không khớp
    # được gì), tránh làm đầy log ở tình huống bình thường "không model nào đang chạy".
    if ($ketQua.Count -eq 0) {
        $viTriMoc = $daGiaiMa.IndexOf('PREMOLD-DFU')
        if ($viTriMoc -ge 0) {
            $batDau    = [Math]::Max(0, $viTriMoc - 100)
            $doDai     = [Math]::Min(300, $daGiaiMa.Length - $batDau)
            $doanQuanh = $daGiaiMa.Substring($batDau, $doDai)
            GHI_LOG "PHAN_TICH_DONG_QA_HOUR: tìm thấy 'PREMOLD-DFU' trong response nhưng KHÔNG khớp được dòng nào -- có thể cấu trúc HTML thật khác giả định hiện tại. Đoạn quanh vị trí tìm thấy: $doanQuanh" 'WARN'
        }
    }

    return ,$ketQua
}

# ── Hàm CHÍNH -- gọi từ cả Runspace nền (chu kỳ 60s) lẫn UI thread (nút Làm
# Mới Nhanh). Tự dùng URL trong SETTINGS.db (key 'qahour') làm gốc, tự ghép
# thêm chuỗi tham số + khung giờ 24h đang diễn ra (tính theo mốc 8h GẦN NHẤT,
# giống hệt quy ước 8h = đầu ca làm việc đã dùng trong LAY_CA_HIEN_TAI). ──
function LAY_DU_LIEU_QA_HOUR {
    param(
        [int]$MaxRetries   = -1,
        [int]$TimeoutMs    = 15000,
        [int]$RetryDelayMs = -1
    )
    try {
        # Khi KHÔNG truyền -MaxRetries/-RetryDelayMs rõ ràng (chu kỳ nền 60s, xem
        # BAT_DAU_LAM_MOI_NEN trong main.ps1), lấy theo config.max_retry/config.retry_delay
        # đã lưu trong SETTINGS.db. Nút "Làm Mới Nhanh" vẫn CHỦ ĐỘNG truyền riêng
        # -MaxRetries 1 -TimeoutMs 6000 (xem main.ps1) nên KHÔNG bị cấu hình này ghi đè.
        if ($MaxRetries -lt 0) {
            $MaxRetries = 3
            if ($global:CFG -and $global:CFG.config.ContainsKey('max_retry')) {
                $mrTmp = 0
                if ([int]::TryParse([string]$global:CFG.config['max_retry'], [ref]$mrTmp) -and $mrTmp -gt 0) { $MaxRetries = $mrTmp }
            }
        }
        if ($RetryDelayMs -lt 0) {
            $RetryDelayMs = 300
            if ($global:CFG -and $global:CFG.config.ContainsKey('retry_delay')) {
                $rdTmp = 0
                if ([int]::TryParse([string]$global:CFG.config['retry_delay'], [ref]$rdTmp) -and $rdTmp -ge 0) { $RetryDelayMs = $rdTmp }
            }
        }
        $urlGoc = $global:CFG.urls['qahour']
        if ([string]::IsNullOrWhiteSpace($urlGoc)) {
            GHI_LOG "QA-HOUR: không tìm thấy URL 'qahour' trong SETTINGS.db -- bỏ qua chu kỳ này" 'WARN'
            return @()
        }

        $now     = Get-Date
        $tam8Gio = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 8 -Minute 0 -Second 0
        if ($now.Hour -ge 8) {
            $tuNgay  = $tam8Gio
            $denNgay = $tam8Gio.AddDays(1)
        } else {
            $tuNgay  = $tam8Gio.AddDays(-1)
            $denNgay = $tam8Gio
        }
        $tuStr  = [System.Web.HttpUtility]::UrlEncode($tuNgay.ToString('yyyy/MM/dd HH:mm:ss'))
        $denStr = [System.Web.HttpUtility]::UrlEncode($denNgay.ToString('yyyy/MM/dd HH:mm:ss'))

        $url = $urlGoc + '?profitCenter=0000000025&Include_Rework_WO=Y&PROD_TYPE=ALL' +
               "&fromDate=$tuStr&toDate=$denStr" +
               '&BU=&Customer=&MO=&cbxExclude_PANEL_WO=Yes&modelName=&majorProject=&projectName=&productName=' +
               '&lineName=&sectionName=&cbxModelName=Yes&profit=&profits=&groupName=PREMOLD-DFU&modelSerial=ALL'

        $html = LAY_HTML_CO_THU_LAI -Url $url -MaxRetries $MaxRetries -TimeoutMs $TimeoutMs -RetryDelayMs $RetryDelayMs

        $rows = PHAN_TICH_DONG_QA_HOUR -RawText $html
        GHI_LOG "QA-HOUR: nhận $($rows.Count) dòng từ $url" 'INFO'
        return ,$rows

    } catch {
        GHI_LOG "Lỗi hàm LAY_DU_LIEU_QA_HOUR: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return @()
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE (chỉ hàm chính -- 2 hàm còn lại là chi tiết cài đặt
# nội bộ, không cần gọi trực tiếp từ ngoài module này)
# ================================================================
Export-ModuleMember -Function LAY_DU_LIEU_QA_HOUR
