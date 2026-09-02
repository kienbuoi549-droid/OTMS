
# Database.psm1 -- HÀM HỖ TRỢ LÀM VIỆC VỚI CẤU TRÚC DỮ LIỆU (JSON, XML) TRONG FILE.DB (Mã hoá AES+GZip, đọc/ghi MO/USER/SETTINGS/Active.db)
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

# ── Nén dữ liệu bằng GZip (đầu vào: mảng byte, đầu ra: mảng byte đã nén) ──
function NEN_GZIP([byte[]]$data) {
    try {
        $ms  = New-Object System.IO.MemoryStream
        $gz  = New-Object System.IO.Compression.GZipStream(
                   $ms, [System.IO.Compression.CompressionMode]::Compress)
        $gz.Write($data, 0, $data.Length)
        $gz.Close()
        return $ms.ToArray()

    } catch {
        GHI_LOG "Lỗi hàm NEN_GZIP: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Giải nén GZip (đầu vào: mảng byte đã nén, đầu ra: mảng byte gốc) ──
function GIAI_NEN_GZIP([byte[]]$data) {
    try {
        $src = New-Object System.IO.MemoryStream(,$data)
        $gz  = New-Object System.IO.Compression.GZipStream(
                   $src, [System.IO.Compression.CompressionMode]::Decompress)
        $dst = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 4096
        do {
            $n = $gz.Read($buf, 0, $buf.Length)
            if ($n -gt 0) { $dst.Write($buf, 0, $n) }
        } while ($n -gt 0)
        $gz.Close()
        return $dst.ToArray()

    } catch {
        GHI_LOG "Lỗi hàm GIAI_NEN_GZIP: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Mã hoá AES-256 chế độ CBC (đầu vào: byte thô, đầu ra: byte đã mã hoá) ──
function MA_HOA_AES([byte[]]$data) {
    try {
        $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
        $aes.KeySize   = 256
        $aes.BlockSize = 128
        $aes.Mode      = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding   = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key       = $global:AES_KEY
        $aes.IV        = $global:AES_IV
        $enc = $aes.CreateEncryptor()
        $ms  = New-Object System.IO.MemoryStream
        $cs  = New-Object System.Security.Cryptography.CryptoStream(
                   $ms, $enc,
                   [System.Security.Cryptography.CryptoStreamMode]::Write)
        $cs.Write($data, 0, $data.Length)
        $cs.FlushFinalBlock()
        $cs.Close(); $aes.Dispose()
        return $ms.ToArray()

    } catch {
        GHI_LOG "Lỗi hàm MA_HOA_AES: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Giải mã AES-256 chế độ CBC (đầu vào: byte đã mã hoá, đầu ra: byte thô) ──
function GIAI_MA_AES([byte[]]$data) {
    try {
        $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
        $aes.KeySize   = 256
        $aes.BlockSize = 128
        $aes.Mode      = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding   = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key       = $global:AES_KEY
        $aes.IV        = $global:AES_IV
        $dec = $aes.CreateDecryptor()
        $ms  = New-Object System.IO.MemoryStream(,$data)
        $cs  = New-Object System.Security.Cryptography.CryptoStream(
                   $ms, $dec,
                   [System.Security.Cryptography.CryptoStreamMode]::Read)
        $dst = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 4096
        do {
            $n = $cs.Read($buf, 0, $buf.Length)
            if ($n -gt 0) { $dst.Write($buf, 0, $n) }
        } while ($n -gt 0)
        $cs.Close(); $aes.Dispose()
        return $dst.ToArray()

    } catch {
        GHI_LOG "Lỗi hàm GIAI_MA_AES: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Đọc file .db và trả về nội dung văn bản, hoặc $null nếu không có / lỗi ──
function DOC_FILE_DB_HOA_NULL([string]$duongDan) {
    try {
        if (-not (Test-Path $duongDan)) { return $null }
        try   { return DOC_FILE_DB $duongDan }
        catch { Write-Warning "[DL] Lỗi đọc file: $duongDan — $_"; return $null }

    } catch {
        GHI_LOG "Lỗi hàm DOC_FILE_DB_HOA_NULL: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Đổi tên file tạm đè lên file đích -- 3 TẦNG bảo vệ theo thứ tự ưu tiên, dùng CHUNG
# cho MỌI nơi cần đổi tên đè trong dự án (GHI_FILE_DB và GHI_INFO_XML bên dưới):
#
#   TẦNG 1 -- File.Replace/Move (nguyên tử nhất, ưu tiên hàng đầu): thử lại tối đa
#   MaxRetries lần, NHƯNG CHỈ khi lỗi THẬT SỰ là IOException (khoá file tạm thời, vd tiến
#   trình khác đang đọc/ghi đúng lúc đó).
#
#   LƯU Ý QUAN TRỌNG (bug đã xác nhận qua log thực tế -- SỬA Ở ĐÂY): khi gọi method .NET
#   qua cú pháp [Type]::Method(), PowerShell LUÔN bọc lỗi gốc bên trong
#   MethodInvocationException -- "catch [System.IO.IOException]" KHÔNG BAO GIỜ khớp trực
#   tiếp dù lỗi gốc THẬT SỰ là IOException, vì kiểu PowerShell nhìn thấy bên ngoài luôn là
#   MethodInvocationException (không kế thừa từ IOException). Nghĩa là bản TRƯỚC ĐÂY,
#   nhánh "thử lại khi khoá file" KHÔNG BAO GIỜ thực sự chạy -- mọi lỗi (kể cả khoá file
#   thật) đều rơi thẳng vào nhánh ném lỗi ngay, không hề có 750ms retry như tưởng. Phải
#   lấy lỗi THẬT qua .Exception.InnerException rồi mới so kiểu.
#
#   TẦNG 2 -- PHƯƠNG ÁN DỰ PHÒNG (xoá file đích + Move file tạm vào đúng tên): dùng khi
#   TẦNG 1 thất bại vì lý do KHÁC khoá file thông thường -- vd môi trường có Controlled
#   Folder Access (chống ransomware của Windows) hoặc phần mềm EDR/backup công ty chặn
#   thao tác "đổi tên đè lên file đã tồn tại" dù file KHÔNG hề bị khoá (đã xác nhận thực
#   tế: thử đổi tên tay qua Explorer trong cùng thư mục cũng bị chặn y hệt, thành
#   "tên(1).db" thay vì ghi đè -- không phải lỗi riêng của app).
#
#   ĐÁNH ĐỔI của TẦNG 2: mất tính NGUYÊN TỬ TUYỆT ĐỐI trong khoảng RẤT NGẮN giữa lúc xoá
#   file cũ và lúc đổi tên file mới vào (nếu mất điện/crash ĐÚNG khoảnh khắc đó, file đích
#   sẽ tạm thời KHÔNG TỒN TẠI cho tới lần lưu kế tiếp) -- nhưng KHÔNG BAO GIỜ làm nội dung
#   file rơi vào trạng thái GHI DỞ/HỎNG (khác hẳn nếu ghi trực tiếp đè lên file đích), vì
#   nội dung mới đã ghi xong HOÀN CHỈNH vào file tạm từ trước rồi. NAP_MO_DB/NAP_USER_DB/
#   NAP_SETTINGS_DB đều đã coi "file không tồn tại" là trạng thái HỢP LỆ (như lần đầu cài
#   đặt), không phải lỗi, nên app vẫn khởi động bình thường nếu rơi đúng trường hợp hiếm
#   gặp này.
#
#   TẦNG 3 -- hết cả 2 phương án: ném lỗi kèm đầy đủ ngữ cảnh để nơi gọi (GHI_FILE_DB/
#   GHI_INFO_XML) biết chắc chắn đã thất bại thật sự.
function DOI_TEN_FILE_AN_TOAN([string]$DuongDanTam, [string]$DuongDanDich, [int]$MaxRetries = 5, [int]$RetryDelayMs = 150) {
    $daXong = $false
    for ($lan = 1; $lan -le $MaxRetries; $lan++) {
        try {
            if (Test-Path $DuongDanDich) {
                [System.IO.File]::Replace($DuongDanTam, $DuongDanDich, $null)
            } else {
                [System.IO.File]::Move($DuongDanTam, $DuongDanDich)
            }
            $daXong = $true
            break
        } catch {
            # Lấy lỗi THẬT bên trong (InnerException) -- xem giải thích ở comment đầu hàm.
            $loiThat = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
            if ($loiThat -is [System.IO.IOException] -and $lan -lt $MaxRetries) {
                Start-Sleep -Milliseconds $RetryDelayMs
                continue
            }
            # Không phải lỗi khoá file (hoặc đã hết lượt thử cho lỗi khoá file) -- dừng
            # TẦNG 1 ngay, chuyển sang TẦNG 2 (phương án dự phòng) bên dưới thay vì ném
            # lỗi luôn như bản trước đây.
            break
        }
    }

    if (-not $daXong) {
        try {
            if (Test-Path $DuongDanDich) {
                Remove-Item -LiteralPath $DuongDanDich -Force -ErrorAction Stop
            }
            [System.IO.File]::Move($DuongDanTam, $DuongDanDich)
            $daXong = $true
            GHI_LOG "DOI_TEN_FILE_AN_TOAN: File.Replace/Move-đè-lên bị môi trường chặn (không phải khoá file) -- đã dùng phương án dự phòng (xoá + tạo mới) cho '$DuongDanDich'. Nếu lặp lại thường xuyên, kiểm tra Controlled Folder Access / phần mềm EDR-backup đang bảo vệ thư mục này." 'WARN'
        } catch {
            throw "Đổi tên file '$DuongDanTam' đè lên '$DuongDanDich' thất bại (đã thử cả phương án dự phòng xoá+tạo mới) -- $($_.Exception.Message)"
        }
    }
}

# ── Ghi chuỗi văn bản vào file .db: UTF-8 → Nén GZip → Mã hoá AES → GHI NGUYÊN TỬ.
# Áp dụng cho MỌI file .db (MO.db, USER.db, SETTINGS.db, và bất kỳ file nào gọi hàm này
# sau này) -- ghi vào file tạm ".tmp" trước, xác nhận ghi thành công (không rỗng), rồi
# mới đổi tên đè lên bản chính (qua DOI_TEN_FILE_AN_TOAN ở trên). File .db tại đường dẫn
# CHÍNH THỨC không bao giờ ở trạng thái "ghi dở" dù có sự cố giữa chừng (mất điện, crash
# tiến trình, disk đầy...).
function GHI_FILE_DB([string]$path, [string]$plaintext) {
    $duongDanTam = $path + '.tmp'
    try {
        $raw        = [System.Text.Encoding]::UTF8.GetBytes($plaintext)
        $compressed = NEN_GZIP $raw
        $encrypted  = MA_HOA_AES $compressed

        # Xoá file tạm CŨ (nếu còn sót từ lần ghi trước bị lỗi giữa chừng) TRƯỚC khi ghi
        # mới -- tránh tình huống lần ghi NÀY thất bại giữa chừng (vd hết dung lượng đĩa)
        # mà bước kiểm tra "tồn tại + không rỗng" bên dưới lại đọc nhầm nội dung CŨ còn
        # sót lại là "vừa ghi thành công".
        Remove-Item -LiteralPath $duongDanTam -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllBytes($duongDanTam, $encrypted)

        if (-not (Test-Path $duongDanTam) -or (Get-Item $duongDanTam).Length -eq 0) {
            throw "Ghi file tạm '$duongDanTam' thất bại hoặc file rỗng -- huỷ bước đổi tên để tránh mất dữ liệu"
        }

        DOI_TEN_FILE_AN_TOAN $duongDanTam $path

    } catch {
        GHI_LOG "Lỗi hàm GHI_FILE_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        throw   # Ném lại để LUU_MO_DB/LUU_USER_DB/LUU_SETTINGS_DB (và nơi gọi chúng) biết
                # CHẮC CHẮN việc ghi đã thất bại, thay vì âm thầm coi như đã lưu xong.
    } finally {
        # DỌN SẠCH file tạm nếu VẪN CÒN sót lại sau tất cả (dù thành công hay thất bại) --
        # đảm bảo KHÔNG BAO GIỜ để lại ".tmp" mồ côi gây nhầm lẫn khi debug sau này. Nếu
        # đổi tên đã thành công, file tạm đã "biến mất" thành file chính rồi nên Test-Path
        # ở đây tự nhiên là false, dòng Remove-Item không làm gì thêm.
        Remove-Item -LiteralPath $duongDanTam -Force -ErrorAction SilentlyContinue
    }
}

# ── Đọc TOÀN BỘ byte thô của 1 file bằng chế độ CHIA SẺ RỘNG NHẤT có thể
# (FileShare.ReadWrite + Delete) -- để tiến trình NGOÀI (vd công cụ ghi Active.db) vẫn
# GHI ĐƯỢC hoặc ĐỔI TÊN ĐÈ (kiểu ghi qua file tạm ".tmp" rồi rename -- CHÍNH kiểu
# GHI_FILE_DB ở trên đang dùng cho MO/USER/SETTINGS.db) lên file này TRONG LÚC ta đang
# đọc, KHÔNG bị chặn bởi handle đọc của ta. [System.IO.File]::ReadAllBytes (cách dùng
# TRƯỚC ĐÂY) mặc định chỉ xin FileShare.Read -- ĐỦ để tiến trình khác ĐỌC song song,
# nhưng KHÔNG đủ để họ GHI hoặc ĐỔI TÊN ĐÈ lên file trong lúc ta giữ handle, dễ gây lỗi
# khoá phía họ (đúng nguyên nhân khiến Active.db thỉnh thoảng báo "đang bị khoá bởi tiến
# trình khác" -- xem DOI_FILE_KHONG_KHOA/NAP_ACTIVE_DB bên dưới).
#
# Handle đọc được ĐÓNG NGAY trong khối finally, TRƯỚC KHI hàm gọi (DOC_FILE_DB) bắt đầu
# giải mã AES/giải nén GZip -- các bước đó chỉ xử lý trên mảng byte ĐÃ CÓ SẴN trong bộ
# nhớ, hoàn toàn không cần file mở, nên không có lý do giữ handle thêm dù chỉ 1 khoảnh
# khắc.
function DOC_BYTE_FILE_KHONG_CHAN_GHI([string]$path) {
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream(
            $path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        )
        $len = $fs.Length
        $buf = New-Object byte[] $len
        $daDoc = 0
        # FileStream.Read KHÔNG đảm bảo đọc đủ trong 1 lần gọi -- lặp tới khi đủ $len
        # byte hoặc gặp cuối luồng sớm bất thường (file bị cắt ngắn giữa chừng bởi tiến
        # trình khác, dù hiếm gặp với file .db nhỏ và đã có GHI_FILE_DB ghi nguyên tử).
        while ($daDoc -lt $len) {
            $n = $fs.Read($buf, $daDoc, $len - $daDoc)
            if ($n -le 0) { break }
            $daDoc += $n
        }
        if ($daDoc -ne $len) {
            throw "Đọc file '$path' thiếu byte -- mong đợi $len, đọc được $daDoc"
        }
        return $buf
    } catch {
        GHI_LOG "Lỗi hàm DOC_BYTE_FILE_KHONG_CHAN_GHI: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        throw
    } finally {
        if ($fs) { $fs.Close() }
    }
}

# ── Đọc file .db thành văn bản: Giải mã AES → Giải nén GZip → UTF-8 ──
function DOC_FILE_DB([string]$path) {
    try {
        $encrypted  = DOC_BYTE_FILE_KHONG_CHAN_GHI $path
        $compressed = GIAI_MA_AES   $encrypted
        $raw        = GIAI_NEN_GZIP $compressed
        return [System.Text.Encoding]::UTF8.GetString($raw)

    } catch {
        GHI_LOG "Lỗi hàm DOC_FILE_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function TAO_THU_MUC_DATA {
    try {
        foreach ($dir in @($global:DATA_DIR, $global:DATABASE_DIR)) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Host "[DL] Đã tạo thư mục: $dir"
            }
        }

    } catch {
        GHI_LOG "Lỗi hàm TAO_THU_MUC_DATA: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Ghi (đè) D:\OTMS\Info.xml với đường dẫn SETTINGS.db được chỉ định -- HÀM DÙNG CHUNG,
# gọi từ CẢ TAO_INFO_XML_NEU_CHUA_CO (tạo lần đầu, dùng đường dẫn mặc định) LẪN
# LUU_CAU_HINH_CHUNG (General_Install.psm1, khi người dùng tự đổi ô "Đường dẫn
# SETTINGS.db chuẩn"). File KHÔNG mã hoá (chỉ XML thuần), ghi NGUYÊN TỬ qua .tmp + đổi
# tên như mọi file khác trong app.
function GHI_INFO_XML([string]$duongDanSettingsMoi) {
    try {
        if (-not (Test-Path $global:THU_MUC_OTMS_GOC)) {
            New-Item -ItemType Directory -Path $global:THU_MUC_OTMS_GOC -Force | Out-Null
        }
        # Thoát các ký tự đặc biệt XML (&, <, >...) trước khi ghép vào here-string --
        # đường dẫn UNC/tuỳ chỉnh có thể chứa "&" (vd "\\SERVER\Data & Backup\..."),
        # ghép thẳng chuỗi thô sẽ tạo ra Info.xml KHÔNG HỢP LỆ, khiến lần đọc kế tiếp
        # (KHOI_TAO_BIEN, Variable.psm1) phân tích XML thất bại.
        $duongDanDaThoat = [System.Security.SecurityElement]::Escape($duongDanSettingsMoi)
        $noiDungXml = @"
<?xml version="1.0" encoding="utf-8"?>
<OTMSInfo>
  <SettingsPath>$duongDanDaThoat</SettingsPath>
</OTMSInfo>
"@
        $duongDanTam = $global:PATH_INFO_XML + '.tmp'
        Remove-Item -LiteralPath $duongDanTam -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($duongDanTam, $noiDungXml, [System.Text.Encoding]::UTF8)
        DOI_TEN_FILE_AN_TOAN $duongDanTam $global:PATH_INFO_XML
        GHI_LOG "Đã ghi Info.xml -- đường dẫn SETTINGS.db: $duongDanSettingsMoi" 'INFO'

    } catch {
        GHI_LOG "Lỗi hàm GHI_INFO_XML: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    } finally {
        Remove-Item -LiteralPath ($global:PATH_INFO_XML + '.tmp') -Force -ErrorAction SilentlyContinue
    }
}

# ── Tạo D:\OTMS\Info.xml NẾU CHƯA CÓ -- gọi khi SETTINGS.db chính không đọc được (thiếu
# hoặc hỏng) -- xem NAP_SETTINGS_DB. CHỈ tạo khi Info.xml CHƯA TỒN TẠI -- nếu đã có (kể cả
# trỏ tới đường dẫn TUỲ CHỈNH người dùng từng đổi qua "Cài đặt chung"), GIỮ NGUYÊN không
# đụng vào, vì việc SETTINGS.db tại đường dẫn đó không đọc được là vấn đề CẦN NGƯỜI DÙNG
# xử lý (khôi phục file/backup vào đúng chỗ), không phải lý do để âm thầm reset lại đường
# dẫn họ đã tự chọn.
function TAO_INFO_XML_NEU_CHUA_CO {
    try {
        if (Test-Path $global:PATH_INFO_XML) { return }
        $duongDanMacDinh = Join-Path (Join-Path $global:THU_MUC_OTMS_GOC 'Data') 'SETTINGS.db'
        GHI_INFO_XML $duongDanMacDinh

    } catch {
        GHI_LOG "Lỗi hàm TAO_INFO_XML_NEU_CHUA_CO: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Sửa các dấu \ KHÔNG PHẢI escape hợp lệ trong JSON (vd đường dẫn Windows gõ tay
# "C:\User\Data" thay vì "C:\\User\\Data" đúng chuẩn JSON) -- quét TOÀN BỘ chuỗi, chỉ
# đụng vào dấu \ nào KHÔNG theo sau bởi 1 trong các ký tự escape hợp lệ (" \ / b f n r t
# hoặc uXXXX 4 số hex). Dấu \\ ĐÃ hợp lệ sẵn (vd \\ mở đầu đường dẫn UNC \\SERVER\Share)
# được BỎ QUA, không đụng tới -- tránh phá hỏng dữ liệu JSON vốn đã đúng chuẩn.
#
# Đây là hàm PHỤ nội bộ, KHÔNG export ra ngoài module -- chỉ PHAN_TICH_JSON_AN_TOAN bên
# dưới gọi tới khi ConvertFrom-Json lần đầu thất bại, không cần gọi trực tiếp từ nơi khác.
function SUA_ESCAPE_JSON_KHONG_HOP_LE([string]$vanBanJson) {
    try {
        return [System.Text.RegularExpressions.Regex]::Replace(
            $vanBanJson,
            '\\(?!["\\/bfnrt]|u[0-9A-Fa-f]{4})',
            '\\'
        )
    } catch {
        GHI_LOG "Lỗi hàm SUA_ESCAPE_JSON_KHONG_HOP_LE: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $vanBanJson
    }
}

# ── Chuyển đổi chuỗi JSON sang đối tượng PowerShell, CÓ TỰ SỬA nếu gặp dấu \ không hợp lệ
# (vd đường dẫn Windows gõ tay/sửa tay thiếu escape). Dùng thay cho việc gọi thẳng
# "ConvertFrom-Json" ở NAP_MO_DB/NAP_USER_DB/NAP_SETTINGS_DB bên dưới.
#
# CÁCH LÀM: luôn thử ConvertFrom-Json BÌNH THƯỜNG trước -- CHỈ khi thất bại mới chạy
# SUA_ESCAPE_JSON_KHONG_HOP_LE rồi thử phân tích LẦN 2. Thứ tự này CHỦ ĐÍCH -- không bao
# giờ đụng vào dữ liệu vốn đã đúng chuẩn (nhánh sửa chỉ chạy khi chắc chắn lần đầu đã
# thất bại), tránh rủi ro làm sai lệch những chuỗi \\ hợp lệ sẵn có (vd đường dẫn UNC).
# Nếu sửa xong parse lại VẪN thất bại, ném lại đúng LỖI GỐC (lần thử đầu, trước khi sửa)
# để nơi gọi (NAP_MO_DB/NAP_USER_DB/NAP_SETTINGS_DB) biết chắc dữ liệu hỏng thật -- không
# phải chỉ do escape -- và xử lý y hệt như một lỗi ConvertFrom-Json bình thường.
function PHAN_TICH_JSON_AN_TOAN([string]$vanBanJson) {
    try {
        return $vanBanJson | ConvertFrom-Json
    } catch {
        $loiGoc = $_
        GHI_LOG "PHAN_TICH_JSON_AN_TOAN: ConvertFrom-Json lần đầu thất bại ($($_.Exception.Message)) -- thử sửa escape không hợp lệ và phân tích lại" 'WARN'
        try {
            $vanBanDaSua = SUA_ESCAPE_JSON_KHONG_HOP_LE $vanBanJson
            $ketQua = $vanBanDaSua | ConvertFrom-Json
            GHI_LOG "PHAN_TICH_JSON_AN_TOAN: đã sửa escape không hợp lệ và phân tích lại THÀNH CÔNG -- nên mở lại file nguồn (vd Cài đặt chung > Lưu) để ghi lại đúng chuẩn JSON" 'WARN'
            return $ketQua
        } catch {
            GHI_LOG "PHAN_TICH_JSON_AN_TOAN: vẫn thất bại sau khi sửa escape -- dữ liệu JSON hỏng thực sự, không phải chỉ do escape: $($_.Exception.Message)" 'ERROR'
            throw $loiGoc
        }
    }
}

# ── Đọc số THUẦN TÚY an toàn từ dữ liệu JSON của file .db (có thể là số, chuỗi, null,
# hoặc thuộc tính KHÔNG TỒN TẠI nếu MO.db được sửa tay) ──
# TRƯỚC ĐÂY dùng ép kiểu [double]$v.plan trực tiếp: chỉ cần 1 model có plan null/chuỗi
# sai là exception ném ra khỏi vòng lặp --> TOÀN BỘ MO.db bị coi là hỏng (NAP_MO_DB trả
# về $false) --> KHOI_TAO_DB throw --> ỨNG DỤNG THOÁT ngay lúc khởi động dù chỉ 1 mục
# hỏng trong file. Parse theo InvariantCulture để không phụ thuộc cài đặt vùng của máy.
function DOI_SO_DB_AN_TOAN($giaTri, [double]$macDinh = 0.0) {
    try {
        if ($null -eq $giaTri -or $giaTri -is [bool]) { return $macDinh }
        $dv = 0.0
        if ([double]::TryParse([string]$giaTri, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dv)) { return $dv }
        return $macDinh
    } catch { return $macDinh }
}

# ── Đọc boolean an toàn từ dữ liệu JSON của file .db ──
# TRƯỚC ĐÂY dùng [bool]$v.active trực tiếp -- bẫy PowerShell kinh điển: ÉP [bool] trên
# CHUỖI thì MỌI chuỗi KHÔNG RỖNG đều ra $true, kể cả "false" (bẫy này đã được ghi nhận
# và xử lý trong NAP_SETTINGS_DB ở dưới nhưng NAP_MO_DB thì chưa). Hệ quả: MO.db được
# sửa tay với "active": "false" sẽ bị hiểu NGƯỢC thành "đang theo dõi" và model vẫn
# hiện ở bảng sản lượng Trang chủ.
function DOI_BOOL_DB_AN_TOAN($giaTri, [bool]$macDinh = $false) {
    try {
        if ($null -eq $giaTri) { return $macDinh }
        if ($giaTri -is [bool]) { return $giaTri }
        return (([string]$giaTri).Trim().ToLower() -eq 'true')
    } catch { return $macDinh }
}

function NAP_MO_DB {
    try {
        $global:MO_DB = [ordered]@{}
        if (-not (Test-Path $global:PATH_MO)) {
            Write-Host "[DL] Không tìm thấy MO.db — Bảng sản lượng sẽ hiển thị trống"
            return $true   # Chưa tồn tại = trạng thái HỢP LỆ (lần đầu cài đặt), KHÔNG phải lỗi
        }
        $json = DOC_FILE_DB_HOA_NULL $global:PATH_MO
        if ($null -eq $json) {
            Write-Warning "[DL] MO.db tồn tại nhưng không đọc/giải mã được"
            return $false   # File TỒN TẠI nhưng đọc/giải mã thất bại = lỗi thật
        }
        try {
            $raw = PHAN_TICH_JSON_AN_TOAN $json
            $raw.PSObject.Properties | ForEach-Object {
                $mid = $_.Name; $v = $_.Value
                # FIX: dùng bộ chuyển đổi an toàn thay vì ép kiểu trực tiếp -- trước đây
                # [double]$v.plan ném exception khi plan null/chuỗi sai (file sửa tay) và
                # khiến TOÀN BỘ MO.db bị coi là hỏng, app THOÁT lúc khởi động; còn
                # [bool]$v.active với chuỗi "false" trả về $true (bẫy PowerShell).
                $global:MO_DB[$mid] = @{
                    type_name  = [string]$v.type_name
                    plan       = DOI_SO_DB_AN_TOAN $v.plan
                    actual_sip = DOI_SO_DB_AN_TOAN $v.actual_sip
                    actual     = DOI_SO_DB_AN_TOAN $v.actual
                    active     = DOI_BOOL_DB_AN_TOAN $v.active
                }
            }
            Write-Host "[DL] Đã nạp MO.db: $($global:MO_DB.Count) model"
            return $true
        } catch {
            Write-Warning "[DL] Lỗi phân tích MO.db: $_"
            $global:MO_DB = [ordered]@{}
            return $false
        }

    } catch {
        GHI_LOG "Lỗi hàm NAP_MO_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $false
    }
}

# ── Lưu dữ liệu model hiện tại xuống file MO.db (GHI_FILE_DB tự ghi NGUYÊN TỬ qua .tmp)
function LUU_MO_DB {
    try {
        $obj = [ordered]@{}
        foreach ($mid in $global:MO_DB.Keys) {
            $v = $global:MO_DB[$mid]
            $obj[$mid] = [ordered]@{
                type_name  = $v.type_name
                plan       = $v.plan
                actual_sip = $v.actual_sip
                actual     = $v.actual
                active     = $v.active
            }
        }
        $json = $obj | ConvertTo-Json -Depth 3 -Compress:$false
        GHI_FILE_DB $global:PATH_MO $json
        Write-Host "[DL] Đã lưu MO.db"

    } catch {
        GHI_LOG "Lỗi hàm LUU_MO_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        throw   # Ném lại để nơi gọi (LUU_SUA_PLAN, LUU_CAI_DAT_SAN_LUONG...) biết ghi thất bại
    }
}

# ── Nạp file USER.db vào biến toàn cục (để trống nếu file không tồn tại) ──
function NAP_USER_DB {
    try {
        $global:USER_DB = @{}
        if (-not (Test-Path $global:PATH_USER)) {
            Write-Host "[DL] Không tìm thấy USER.db — đăng nhập sẽ luôn thất bại"
            return $true   # Chưa tồn tại = trạng thái HỢP LỆ (lần đầu cài đặt), KHÔNG phải lỗi
        }
        $json = DOC_FILE_DB_HOA_NULL $global:PATH_USER
        if ($null -eq $json) {
            Write-Warning "[DL] USER.db tồn tại nhưng không đọc/giải mã được"
            return $false   # File TỒN TẠI nhưng đọc/giải mã thất bại = lỗi thật
        }
        try {
            $raw = PHAN_TICH_JSON_AN_TOAN $json
            # Cấu trúc thực tế: { "users": { "VN_ID": { "name": "Tên" }, ... } }
            if ($raw.PSObject.Properties.Name -contains 'users') {
                $raw.users.PSObject.Properties | ForEach-Object {
                    $global:USER_DB[$_.Name] = [string]$_.Value.name
                }
            }
            Write-Host "[DL] Đã nạp USER.db: $($global:USER_DB.Count) người dùng"
            return $true
        } catch {
            Write-Warning "[DL] Lỗi phân tích USER.db: $_"
            $global:USER_DB = @{}
            return $false
        }

    } catch {
        GHI_LOG "Lỗi hàm NAP_USER_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $false
    }
}

# ── Lưu dữ liệu nhân viên hiện tại xuống file USER.db (GHI_FILE_DB tự ghi NGUYÊN TỬ qua .tmp) ──
function LUU_USER_DB {
    try {
        $usersObj = [ordered]@{}
        foreach ($k in ($global:USER_DB.Keys | Sort-Object)) {
            $usersObj[$k] = @{ name = $global:USER_DB[$k] }
        }
        $obj  = [ordered]@{ users = $usersObj }
        $json = $obj | ConvertTo-Json -Depth 3
        GHI_FILE_DB $global:PATH_USER $json
        Write-Host "[DL] Đã lưu USER.db"

    } catch {
        GHI_LOG "Lỗi hàm LUU_USER_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        throw
    }
}

# ── Nạp file SETTINGS.db vào biến cấu hình toàn cục ──
function NAP_SETTINGS_DB {
    try {
        $global:CFG = @{ items=@{}; config=@{}; url_params=@{}; urls=@{} }
        if (-not (Test-Path $global:PATH_SETTINGS)) {
            Write-Host "[DL] Không tìm thấy SETTINGS.db — dùng cấu hình rỗng"
            TAO_INFO_XML_NEU_CHUA_CO
            return $true   # Chưa tồn tại = trạng thái HỢP LỆ (lần đầu cài đặt), KHÔNG phải lỗi
        }
        $json = DOC_FILE_DB_HOA_NULL $global:PATH_SETTINGS
        if ($null -eq $json) {
            Write-Warning "[DL] SETTINGS.db tồn tại nhưng không đọc/giải mã được"
            TAO_INFO_XML_NEU_CHUA_CO
            return $false   # File TỒN TẠI nhưng đọc/giải mã thất bại = lỗi thật (dù không
                             # còn khiến app thoát nữa -- xem KHOI_TAO_DB)
        }
        try {
            $raw = PHAN_TICH_JSON_AN_TOAN $json
            if ($raw.items)      { $raw.items.PSObject.Properties      | ForEach-Object { $global:CFG.items[$_.Name]      = [string]$_.Value } }
            if ($raw.config)     { $raw.config.PSObject.Properties     | ForEach-Object { $global:CFG.config[$_.Name]     = $_.Value } }
            # Đồng bộ cờ bật/tắt ghi log từ config.enable_log NẾU đã từng lưu qua Cài đặt
            # chung -- nếu key này chưa tồn tại (SETTINGS.db cũ / lần đầu chạy), GIỮ
            # NGUYÊN giá trị mặc định $true đã đặt sẵn ở KHOI_TAO_BIEN, không ghi đè.
            # Chấp nhận CẢ boolean JSON thật (true/false không ngoặc kép, do chính app này
            # lưu qua CheckBox_Bat_Ghi_Log) LẪN chuỗi văn bản ("true"/"false", không phân
            # biệt hoa thường, trường hợp SETTINGS.db được sửa tay) -- KHÔNG ép kiểu [bool]
            # trực tiếp trên chuỗi, vì PowerShell coi MỌI chuỗi KHÔNG RỖNG là $true (kể cả
            # chuỗi "false"!) -- ép [bool]"false" vẫn ra $true, đây là bẫy phổ biến.
            if ($global:CFG.config.ContainsKey('enable_log')) {
                $giaTriGhiLogTho = $global:CFG.config['enable_log']
                $giaTriGhiLogBool = if ($giaTriGhiLogTho -is [bool]) { $giaTriGhiLogTho } else { ([string]$giaTriGhiLogTho).Trim().ToLower() -eq 'true' }
                $global:LOG_ENABLE = $giaTriGhiLogBool
                if ($global:TRANG_THAI_DUNG_CHUNG -is [hashtable]) {
                    $global:TRANG_THAI_DUNG_CHUNG['GhiLogBat'] = $giaTriGhiLogBool
                }
            }
            if ($raw.url_params) { $raw.url_params.PSObject.Properties | ForEach-Object { $global:CFG.url_params[$_.Name] = [string]$_.Value } }
            if ($raw.urls)       { $raw.urls.PSObject.Properties       | ForEach-Object { $global:CFG.urls[$_.Name]       = [string]$_.Value } }
            Write-Host "[DL] Đã nạp SETTINGS.db"
            return $true
        } catch {
            Write-Warning "[DL] Lỗi phân tích SETTINGS.db: $_"
            $global:CFG = @{ items=@{}; config=@{}; url_params=@{}; urls=@{} }
            TAO_INFO_XML_NEU_CHUA_CO
            return $false
        }

    } catch {
        GHI_LOG "Lỗi hàm NAP_SETTINGS_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $false
    }
}

# ── Lưu cấu hình hiện tại xuống file SETTINGS.db -- GHI_FILE_DB (Database.psm1) đã tự
# NGUYÊN TỬ (ghi qua .tmp + đổi tên đè) cho MỌI file .db, nên ở đây chỉ cần gọi thẳng với
# đường dẫn THẬT, KHÔNG tự tính/quản lý đường dẫn .tmp thủ công nữa.
function LUU_SETTINGS_DB {
    try {
        $obj = [ordered]@{
            items      = $global:CFG.items
            config     = $global:CFG.config
            url_params = $global:CFG.url_params
            urls       = $global:CFG.urls
        }
        $json = $obj | ConvertTo-Json -Depth 4
        GHI_FILE_DB $global:PATH_SETTINGS $json

        Write-Host "[DL] Đã lưu SETTINGS.db (qua file tạm)"

    } catch {
        GHI_LOG "Lỗi hàm LUU_SETTINGS_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        # Ném lại BẮT BUỘC -- LUU_CAU_HINH_CHUNG (General_Install.psm1) có try/catch riêng
        # bọc quanh lệnh gọi LUU_SETTINGS_DB, CHỈ hiện "Đã lưu thành công" khi KHÔNG có
        # exception nào ném ra. Trước đây hàm này chỉ log rồi return bình thường, nên dù
        # ghi file thất bại hoàn toàn (như lỗi GHI_FILE_DB vừa gặp), người dùng vẫn thấy
        # thông báo thành công -- SAI sự thật.
        throw
    }
}

# ── Tạo đường dẫn URL — thay thế các thẻ {TEN_THAM_SO} bằng giá trị thực ──────────────────────────
function LAY_DUONG_DAN_URL([string]$key, [hashtable]$vars = @{}) {
    try {
        if (-not $global:CFG.urls.ContainsKey($key)) { return '' }
        $url = $global:CFG.urls[$key]
        # Lấy mã nhân viên từ tham số url_params
        $empId = $global:CFG.url_params['employee_id']
        $url   = $url -replace '\{EMPLOYEE_ID\}', $empId
        # Thay thế các tham số tuỳ chỉnh
        foreach ($k in $vars.Keys) {
            $url = $url -replace "\{$k\}", $vars[$k]
        }
        return $url

    } catch {
        GHI_LOG "Lỗi hàm LAY_DUONG_DAN_URL: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function KHOI_TAO_DB {
    try {
        TAO_THU_MUC_DATA
        $okMo       = NAP_MO_DB
        $okUser     = NAP_USER_DB
        $okSettings = NAP_SETTINGS_DB

        # SETTINGS.db KHÔNG còn nằm trong danh sách gây thoát app nữa -- đây là file cấu
        # hình CHÍNH, chứa đường dẫn tới các file khác; nếu nó không đọc được, ứng dụng
        # KHÔNG thể hoạt động đúng, nhưng VẪN phải MỞ ĐƯỢC để người dùng còn thấy tình
        # trạng lỗi và có cơ hội vào "Cài đặt chung" chỉnh lại đường dẫn (qua Info.xml) --
        # xem NAP_SETTINGS_DB tự lo phần tạo Info.xml khi cần, KHÔNG throw ra đây nữa.
        if (-not $okSettings) {
            GHI_LOG "KHOI_TAO_DB: SETTINGS.db không đọc được -- tiếp tục chạy với cấu hình rỗng, đã tạo Info.xml (nếu chưa có) để hỗ trợ khôi phục" 'WARN'
        }

        # MO.db/USER.db: chỉ file TỒN TẠI nhưng đọc/giải mã/phân tích THẤT BẠI mới bị coi
        # là lỗi thật (trả về $false) -- file CHƯA TỒN TẠI (lần đầu cài đặt) là trạng thái
        # HỢP LỆ, đã tự trả về $true, KHÔNG bị liệt vào đây.
        $cacFileLoi = @()
        if (-not $okMo)   { $cacFileLoi += 'MO.db' }
        if (-not $okUser) { $cacFileLoi += 'USER.db' }

        if ($cacFileLoi.Count -gt 0) {
            $danhSach = $cacFileLoi -join ', '
            throw "Không thể đọc file: $danhSach -- file có thể bị hỏng hoặc sai định dạng"
        }

    } catch {
        GHI_LOG "Lỗi hàm KHOI_TAO_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        throw   # để main.ps1 hiển thị thông báo rõ ràng + thoát ứng dụng
    }
}

# ── Chờ qua "vùng nguy hiểm" quanh thời điểm MultiRequest có thể vừa ghi xong Active.db
# -- dùng LastWriteTime CỦA CHÍNH FILE làm mốc (KHÔNG dùng thời điểm nhận sự kiện
# FileSystemWatcher), theo đúng quy ước đã chốt: AN TOÀN để đọc khi đã ĐỦ 5 giây kể từ
# lúc MultiRequest ghi xong Active.db lần gần nhất.
#
# ĐÂY LÀ LỚP PHÒNG VỆ CHỦ ĐỘNG (dự đoán qua mốc thời gian), BỔ SUNG cho
# DOI_FILE_KHONG_KHOA (lớp phòng vệ BỊ ĐỘNG, dựa trên trạng thái khoá file THỰC TẾ tại
# thời điểm mở file) -- gọi hàm này TRƯỚC, DOI_FILE_KHONG_KHOA vẫn giữ nguyên vai trò
# lưới an toàn cuối cùng ngay sau đó (xem NAP_ACTIVE_DB bên dưới). Cần CẢ HAI vì cơ chế
# FileSystemWatcher + hẹn giờ debounce 5 giây (main.ps1) chỉ tính thời gian chờ kể từ LÚC
# NHẬN được sự kiện đổi -- không phải lúc nào cũng trùng khớp tuyệt đối với LastWriteTime
# thật của file. Hàm này bổ khuyết đúng 2 tình huống mà cơ chế debounce KHÔNG che được:
#   1) Lần đọc ĐẦU TIÊN lúc mở app -- gọi BAT_DAU_LAM_MOI_LO_NEN thẳng từ Window.Add_Loaded,
#      KHÔNG đi qua hẹn giờ debounce (xem main.ps1), nên nếu app khởi động đúng lúc
#      MultiRequest vừa/đang ghi, không có bước chờ nào bảo vệ trước khi hàm này ra đời.
#   2) Hàng đợi sự kiện hệ điều hành bị trễ (event queue backlog) khiến thời điểm NHẬN
#      sự kiện Changed lệch so với thời điểm GHI thật -- kiểm tra LastWriteTime trực tiếp
#      luôn là mốc ĐÚNG SỰ THẬT nhất, không phụ thuộc độ trễ khâu trung gian.
#
# $MaxChoGiay: giới hạn TỐI ĐA hàm này được phép Start-Sleep -- TRÁNH block luồng gọi vô
# thời hạn nếu Active.db liên tục bị ghi đè dồn dập. Mặc định bằng đúng $NguongAnToanGiay
# (5 giây) vì hàm này HIỆN TẠI CHỈ được gọi từ Runspace_LO (luồng NỀN -- xem
# BAT_DAU_LAM_MOI_LO_NEN, main.ps1), không có đường gọi trực tiếp trên UI thread nào tại
# thời điểm viết hàm này nên chờ vài giây không ảnh hưởng UI. NẾU SAU NÀY có đường gọi
# thẳng từ UI thread (vd CAP_NHAT_KHU_VUC_LO được kích hoạt lại), PHẢI truyền riêng
# -MaxChoGiay nhỏ hơn hẳn (vd 0.5-1 giây) khi gọi từ nhánh đó để tránh treo giao diện --
# KHÔNG đổi giá trị mặc định dùng chung ở đây, tránh ảnh hưởng ngược lại đường gọi nền.
#
# Nếu chờ hết $MaxChoGiay mà vẫn CHƯA đủ $NguongAnToanGiay, hàm KHÔNG chặn thêm nữa --
# cứ để luồng gọi tiếp tục sang bước DOI_FILE_KHONG_KHOA như bình thường (best-effort,
# không phải bảo đảm tuyệt đối -- lưới an toàn cuối cùng vẫn là kiểm tra khoá file thật).
function DOI_THOI_DIEM_AN_TOAN_DOC_ACTIVE {
    param(
        [string]$Path             = $global:PATH_ACTIVE,
        [double]$NguongAnToanGiay = 5,
        [double]$MaxChoGiay       = 5
    )
    try {
        if (-not (Test-Path $Path)) { return }

        $gioGhiCuoi  = (Get-Item -LiteralPath $Path).LastWriteTime
        $daTroiGiay  = ((Get-Date) - $gioGhiCuoi).TotalSeconds

        if ($daTroiGiay -ge $NguongAnToanGiay) {
            # Đã đủ xa lần ghi gần nhất -- an toàn đọc ngay, không cần chờ thêm
            return
        }

        $canChoGiay = [Math]::Min($NguongAnToanGiay - $daTroiGiay, $MaxChoGiay)
        if ($canChoGiay -gt 0) {
            GHI_LOG "DOI_THOI_DIEM_AN_TOAN_DOC_ACTIVE: Active.db vừa ghi cách đây $([Math]::Round($daTroiGiay,2))s (< ngưỡng ${NguongAnToanGiay}s) -- chờ thêm $([Math]::Round($canChoGiay,2))s trước khi đọc" 'INFO'
            Start-Sleep -Milliseconds ([int]([Math]::Round($canChoGiay * 1000)))
        }

    } catch {
        GHI_LOG "Lỗi hàm DOI_THOI_DIEM_AN_TOAN_DOC_ACTIVE: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function NAP_ACTIVE_DB {
    try {
        if (-not (Test-Path $global:PATH_ACTIVE)) {
            Write-Host "[DL] Không tìm thấy file Active.db — khu vực lò nướng sẽ hiển thị rỗng"
            return $null
        }

        # Né vùng nguy hiểm quanh chu kỳ ghi của MultiRequest TRƯỚC KHI thăm dò khoá file
        # thật -- xem giải thích đầy đủ ở comment của DOI_THOI_DIEM_AN_TOAN_DOC_ACTIVE.
        DOI_THOI_DIEM_AN_TOAN_DOC_ACTIVE -Path $global:PATH_ACTIVE

        # Kiểm tra file có đang bị KHOÁ bởi tiến trình khác không (vd tiến trình ghi
        # Active.db vẫn đang giữ handle ghi dở, hoặc phần mềm diệt virus/backup quét trúng
        # lúc đó). Nếu khoá, chờ ngắn rồi thử lại vài lần (xem DOI_FILE_KHONG_KHOA) trước
        # khi bỏ cuộc -- tránh mỗi lần gặp khoá là nhảy thẳng vào nhánh lỗi bên dưới ngay
        # từ lần thử đầu tiên.
        if (-not (DOI_FILE_KHONG_KHOA $global:PATH_ACTIVE)) {
            Write-Warning "[DL] Active.db đang bị khoá bởi tiến trình khác (có thể đang được ghi) -- bỏ qua chu kỳ này"
            GHI_LOG "NAP_ACTIVE_DB: Active.db vẫn bị khoá sau khi thử lại -- bỏ qua chu kỳ này" 'WARN'
            return $null
        }

        try {
            $xmlStr = DOC_FILE_DB $global:PATH_ACTIVE
            $doc    = [System.Xml.XmlDocument]::new()
            $doc.LoadXml($xmlStr)
            return $doc
        } catch {
            Write-Warning "[DL] Lỗi đọc/phân tích file Active.db: $_"
            return $null
        }

    } catch {
        GHI_LOG "Lỗi hàm NAP_ACTIVE_DB: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Kiểm tra nhanh 1 file .db CÓ đang bị KHOÁ bởi tiến trình khác không -- mở thử ở chế
# độ ĐỌC + CHIA SẺ RỘNG NHẤT (FileShare.ReadWrite + Delete -- ĐỒNG BỘ với
# DOC_BYTE_FILE_KHONG_CHAN_GHI ở trên, cùng lý do: dù chỉ mở-đóng ngay tức thì, KHÔNG
# được để bước thăm dò này chặn tiến trình khác đang GHI hoặc ĐỔI TÊN ĐÈ lên file, dù chỉ
# trong 1 khoảnh khắc), đóng lại NGAY, KHÔNG đọc nội dung. Nếu mở thất bại do khoá
# ([System.IO.IOException] hoặc [System.UnauthorizedAccessException], 2 loại lỗi .NET
# thường gặp khi 1 tiến trình khác đang giữ độc quyền ghi file), chờ RetryDelayMs rồi thử
# lại, tối đa MaxRetries lần. Trả về $true nếu cuối cùng mở được (an toàn để đọc thật),
# $false nếu hết lượt thử mà vẫn khoá.
#
# LƯU Ý: hàm này CHỈ retry đúng 2 loại lỗi liên quan KHOÁ FILE -- các lỗi KHÁC (file bị
# xoá giữa chừng, quyền truy cập thư mục sai...) sẽ tự nhiên KHÔNG khớp catch nào ở đây và
# thoát vòng lặp qua khối catch NGOÀI CÙNG (log lỗi, trả về $false), không retry vô ích.
function DOI_FILE_KHONG_KHOA([string]$path, [int]$MaxRetries = 5, [int]$RetryDelayMs = 150) {
    try {
        for ($lan = 1; $lan -le $MaxRetries; $lan++) {
            try {
                $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                $fs.Close()
                return $true
            } catch {
                # Lấy lỗi THẬT bên trong (InnerException) -- CÙNG BUG với GHI_FILE_DB/
                # DOI_TEN_FILE_AN_TOAN (xem comment chi tiết ở đó): gọi method .NET qua
                # [Type]::Method() luôn bọc lỗi gốc trong MethodInvocationException, nên
                # "catch [System.IO.IOException]"/"catch [System.UnauthorizedAccessException]"
                # kiểu CŨ (2 catch riêng theo kiểu) KHÔNG BAO GIỜ khớp trực tiếp được --
                # nhánh retry trước đây thực chất chưa từng chạy.
                $loiThat = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
                if (($loiThat -is [System.IO.IOException] -or $loiThat -is [System.UnauthorizedAccessException]) -and $lan -lt $MaxRetries) {
                    Start-Sleep -Milliseconds $RetryDelayMs
                }
            }
        }
        return $false

    } catch {
        GHI_LOG "Lỗi hàm DOI_FILE_KHONG_KHOA: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $false
    }
}

# ── Đọc file LỊCH SỬ THEO NGÀY (yyyymmdd.db) của ca làm việc đang chạy trong
# DATABASE_DIR -- dữ liệu nguồn thứ 2 cho MiniMap (bên cạnh Active.db). Tên file =
# "yyyymmdd.db" với yyyymmdd là NGÀY MỐC CA HIỆN TẠI (LAY_NGAY_CA_HIEN_TAI, Support.psm1:
# ca ngày mốc hôm nay, ca đêm chạy quá nửa đêm mốc HÔM QUA -- ca bắt đầu 20:00 tối qua).
# V2.5 -- ĐÃ XÁC NHẬN QUA DỮ LIỆU THẬT MÁY CHẠY: Active.db là nhị phân AES+GZip, NHƯNG
# file lịch sử yyyymmdd.db do hệ thống nguồn ghi ra dạng XML THUẦN (không mã hoá -- ví
# dụ 20260830.db mở bằng notepad thấy ngay <?xml ... urn:otms). Vì vậy hàm DÒ 8 BYTE ĐẦU
# của file (nhảy qua UTF-8 BOM nếu có): byte '<' (0x3C) = XML thuần -> đọc thẳng thành
# văn bản; ngược lại coi là nhị phân AES+GZip -> đi qua DOC_FILE_DB như Active.db. Mỗi
# đường thất bại vẫn còn đường kia làm dự phòng 1 lần trước khi báo hỏng. Trả về
# XmlDocument, hoặc $null khi
# file chưa tồn tại/đang bị khoá/XML hỏng -- KHÔNG BAO GIỜ ném exception ra ngoài, vì
# dữ liệu lịch sử thiếu không được phép làm gián đoạn luồng dữ liệu chính (Active.db).
function NAP_DB_LICH_SU_NGAY {
    param([string]$NgayYyyyMmDd = '')
    try {
        if ([string]::IsNullOrWhiteSpace($NgayYyyyMmDd)) {
            $NgayYyyyMmDd = (LAY_NGAY_CA_HIEN_TAI).ToString('yyyyMMdd')
        }
        $path = Join-Path $global:DATABASE_DIR ($NgayYyyyMmDd + '.db')
        if (-not (Test-Path $path)) {
            Write-Host "[DL] Không tìm thấy file lịch sử ${NgayYyyyMmDd}.db — phần 'OVEN HOÀN THÀNH GẦN NHẤT' sẽ hiển thị trống"
            return $null
        }

        # Né vùng nguy hiểm quanh chu kỳ ghi của hệ thống nguồn TRƯỚC khi thăm dò khoá --
        # cùng nguyên tắc NAP_ACTIVE_DB (ngưỡng ngắn hơn: 3 giây, tối đa chờ 2 giây, vì
        # file lịch sử ít khi được ghi dồn dập như Active.db).
        DOI_THOI_DIEM_AN_TOAN_DOC_ACTIVE -Path $path -NguongAnToanGiay 3 -MaxChoGiay 2

        if (-not (DOI_FILE_KHONG_KHOA $path)) {
            Write-Warning "[DL] File lịch sử ${NgayYyyyMmDd}.db đang bị khoá bởi tiến trình khác -- bỏ qua chu kỳ này"
            GHI_LOG "NAP_DB_LICH_SU_NGAY: $path vẫn bị khoá sau khi thử lại -- bỏ qua chu kỳ này" 'WARN'
            return $null
        }

        # V2.5: đọc LINH HOẠT 2 định dạng (XML thuần / AES+GZip) -- xem giải thích đầu hàm.
        # Dò byte đầu trong 1 lần mở file duy nhất (cùng FileShare với
        # DOC_BYTE_FILE_KHONG_CHAN_GHI để không chặn tiến trình ghi khác).
        $doc = $null
        try {
            $laXmlThuan = $false
            $xmlStr     = $null
            $fs         = $null
            try {
                $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                $head = New-Object byte[] 8
                $n = 0
                while ($n -lt 8) {
                    $m = $fs.Read($head, $n, 8 - $n)
                    if ($m -le 0) { break }
                    $n += $m
                }
                $batDau = 0
                # Nhảy qua UTF-8 BOM (EF BB BF) nếu có
                if ($n -ge 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) { $batDau = 3 }
                if ($n -gt $batDau -and $head[$batDau] -eq 0x3C) { $laXmlThuan = $true }
                if ($laXmlThuan) {
                    # XML thuần: đọc thẳng thành văn bản -- TUYỆT ĐỐI không đi qua DOC_FILE_DB
                    # (giải mã AES sai trên plaintext chỉ làm Loi.log spam ERROR mỗi chu kỳ)
                    $fs.Position = 0
                    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
                    $xmlStr = $sr.ReadToEnd()
                    $sr.Close(); $fs = $null
                }
            } finally {
                if ($fs) { $fs.Close() }
            }

            if (-not $laXmlThuan) { $xmlStr = DOC_FILE_DB $path }

            if (-not [string]::IsNullOrWhiteSpace($xmlStr)) {
                $doc = [System.Xml.XmlDocument]::new()
                $doc.LoadXml($xmlStr)
                return $doc
            }
            return $null

        } catch {
            # V2.5: đường chính thất bại -> thử đường CÒN LẠI đúng 1 lần (phòng lúc dò sai
            # định dạng hoặc hệ thống nguồn đổi cách ghi giữa chừng). Cả 2 đường đều hỏng
            # mới báo lỗi và trả $null -- lịch sử thiếu không được làm rơi luồng chính.
            try {
                $xmlStr2 = DOC_FILE_DB $path
                if ([string]::IsNullOrWhiteSpace($xmlStr2)) {
                    $fs2 = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                    try {
                        $sr2 = New-Object System.IO.StreamReader($fs2, [System.Text.Encoding]::UTF8, $true)
                        $xmlStr2 = $sr2.ReadToEnd()
                        $sr2.Close()
                    } finally { $fs2.Close() }
                }
                if (-not [string]::IsNullOrWhiteSpace($xmlStr2)) {
                    $doc = [System.Xml.XmlDocument]::new()
                    $doc.LoadXml($xmlStr2)
                    GHI_LOG "NAP_DB_LICH_SU_NGAY: đường đọc chính thất bại, đã đọc được file lịch sử qua đường dự phòng ($path)" 'WARN'
                    return $doc
                }
            } catch {
                GHI_LOG "NAP_DB_LICH_SU_NGAY: cả 2 đường đọc (XML thuần / AES+GZip) đều thất bại ($path): $($_.Exception.Message)" 'ERROR'
            }
            Write-Warning "[DL] Lỗi đọc/phân tích file lịch sử $path: $_"
            GHI_LOG "NAP_DB_LICH_SU_NGAY: phân tích XML thất bại ($path): $($_.Exception.Message)" 'ERROR'
            return $null
        }

    } catch {
        GHI_LOG "Lỗi hàm NAP_DB_LICH_SU_NGAY: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $null
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function NEN_GZIP, GIAI_NEN_GZIP, MA_HOA_AES, GIAI_MA_AES, DOC_BYTE_FILE_KHONG_CHAN_GHI, DOC_FILE_DB_HOA_NULL, DOI_TEN_FILE_AN_TOAN, GHI_FILE_DB, DOC_FILE_DB, TAO_THU_MUC_DATA, GHI_INFO_XML, TAO_INFO_XML_NEU_CHUA_CO, PHAN_TICH_JSON_AN_TOAN, NAP_MO_DB, LUU_MO_DB, NAP_USER_DB, LUU_USER_DB, NAP_SETTINGS_DB, LUU_SETTINGS_DB, LAY_DUONG_DAN_URL, KHOI_TAO_DB, NAP_ACTIVE_DB, NAP_DB_LICH_SU_NGAY, DOI_FILE_KHONG_KHOA, DOI_THOI_DIEM_AN_TOAN_DOC_ACTIVE
