# ================================================================
# Support.psm1 -- CÁC HÀM HỖ TRỢ KHÁC (Tính giờ, định dạng số liệu, phân tích chuỗi)
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

# ── Ghi log ra file -- KHÔNG phụ thuộc terminal còn hiện hay không ──
# Dùng để chẩn đoán lỗi/đo thời gian mà không lo mất dữ liệu khi cửa sổ đóng/cuộn mất
function GHI_LOG([string]$noiDung, [string]$loai = 'INFO') {
    try {
        # Ưu tiên đọc cờ bật/tắt từ $global:TRANG_THAI_DUNG_CHUNG (hashtable ĐỒNG BỘ HOÁ
        # dùng CHUNG giữa UI thread và Runspace nền, tạo ở main.ps1) -- đảm bảo bật/tắt
        # log trong "Cài đặt chung" có hiệu lực NGAY LẬP TỨC cho CẢ 2 luồng, không cần đợi
        # Runspace nền tự đọc lại SETTINGS.db ở chu kỳ kế tiếp. $global:LOG_ENABLE (biến
        # đơn, KHÔNG đồng bộ hoá) chỉ dùng làm phương án dự phòng cho các bối cảnh RẤT SỚM
        # lúc khởi động, trước khi TRANG_THAI_DUNG_CHUNG kịp được tạo.
        $batGhiLog = $true
        if ($global:TRANG_THAI_DUNG_CHUNG -is [hashtable] -and $global:TRANG_THAI_DUNG_CHUNG.ContainsKey('GhiLogBat')) {
            $batGhiLog = $global:TRANG_THAI_DUNG_CHUNG['GhiLogBat']
        } elseif ($global:LOG_ENABLE -eq $false) {
            $batGhiLog = $false
        }
        if ($batGhiLog -eq $false) { return }
        $dong = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))] [$loai] $noiDung"
        Add-Content -Path $global:PATH_LOG -Value $dong -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function LAY_GIO_DA_TROI {
    try {
        $n=Get-Date; return (($n.Hour-8+24)%24)+$n.Minute/60.0

    } catch {
        GHI_LOG "Lỗi hàm LAY_GIO_DA_TROI: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function LAY_CA_HIEN_TAI {
    try {
        $h=(Get-Date).Hour; if($h-ge 8 -and $h-lt 20){'D'}else{'N'}

    } catch {
        GHI_LOG "Lỗi hàm LAY_CA_HIEN_TAI: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Ngày MỐC của ca làm việc ĐANG CHẠY -- dùng làm phần "yyyymmdd" của tên file lịch
# sử yyyymmdd.db (mốc thời gian của ca làm việc hôm nay). Quy ước khớp LAY_CA_HIEN_TAI
# (ca ngày 08:00-19:59, ca đêm 20:00-07:59):
#   - Giờ 08:00 -> 23:59 : ca bắt đầu trong ngày HÔM NAY  (ca ngày bắt đầu 08:00, hoặc
#                          ca đêm bắt đầu 20:00 tối nay)      -> mốc = hôm nay
#   - Giờ 00:00 -> 07:59 : ca đêm bắt đầu 20:00 HÔM QUA vẫn đang chạy -> mốc = HÔM QUA
# Trả về DateTime (phần .Date) để nơi gọi tự format 'yyyyMMdd' theo nhu cầu.
function LAY_NGAY_CA_HIEN_TAI {
    try {
        $n = Get-Date
        if ($n.Hour -ge 8) { return $n.Date }
        return $n.Date.AddDays(-1)

    } catch {
        GHI_LOG "Lỗi hàm LAY_NGAY_CA_HIEN_TAI: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return (Get-Date).Date
    }
}
function DINH_DANG_SO([double]$n) {
    try {
        $neg=$n-lt 0; $s=[string][Math]::Round([Math]::Abs($n))
        $out=''; $len=$s.Length
        for($i=0;$i-lt $len;$i++){ if($i-gt 0 -and ($len-$i)%3-eq 0){$out+=','};$out+=$s[$i] }
        $dau = if($neg){'-'}else{''}
        return $dau + $out

    } catch {
        GHI_LOG "Lỗi hàm DINH_DANG_SO: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function DINH_DANG_SO_CO_DAU([double]$n) {
    try {
        if($n-eq 0){'0'}else{ $dauSo = if($n-gt 0){'+'}else{''}; $dauSo+(DINH_DANG_SO $n) }

    } catch {
        GHI_LOG "Lỗi hàm DINH_DANG_SO_CO_DAU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function DINH_DANG_GIO([double]$rem,[double]$qph) {
    try {
        if($qph-eq 0){ return '0h 00' }
        $h=[Math]::Abs($rem/$qph); $hrs=[int][Math]::Floor($h); $m=[int][Math]::Round(($h-$hrs)*60)
        if($m-ge 60){$hrs++;$m=0}; "${hrs}h $($m.ToString('D2'))"

    } catch {
        GHI_LOG "Lỗi hàm DINH_DANG_GIO: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function DINH_DANG_GIO_PHUT([double]$rem,[double]$plan) {
    try {
        $rate=if($plan-ne 0){$plan/24.0}else{1}
        $tot=$rem/$rate; $neg=$tot-lt 0; $abs=[Math]::Abs($tot)
        $h=[int][Math]::Floor($abs); $m=[int][Math]::Round(($abs-$h)*60)
        if($m-ge 60){$h++;$m=0}
        $dauPhut = if($neg){'-'}else{''}
        $dauPhut+"${h}h:$($m.ToString('D2'))"

    } catch {
        GHI_LOG "Lỗi hàm DINH_DANG_GIO_PHUT: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function PHAN_TICH_CHUOI_SIP([string]$s) {
    try {
        $c=[System.Text.RegularExpressions.Regex]::Replace($s,'[^0-9]','')
        if($c){[int]$c}else{0}

    } catch {
        GHI_LOG "Lỗi hàm PHAN_TICH_CHUOI_SIP: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function PHAN_TICH_CHUOI_CFG([string]$s) {
    try {
        if(-not $s){return @()}
        $r=[System.Collections.Generic.List[PSObject]]::new()
        foreach($part in $s.Split('|')){
            $kv=$part.Split(':')
            $magRaw = if($kv.Count-gt 1){$kv[1]}else{'0'}
            $r.Add([PSCustomObject]@{
                name=$kv[0]
                mag=[int]([System.Text.RegularExpressions.Regex]::Replace($magRaw,'[^0-9]',''))
            })
        }; return $r

    } catch {
        GHI_LOG "Lỗi hàm PHAN_TICH_CHUOI_CFG: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Parse chuỗi sang số THỰC theo đúng văn hoá (FIX lỗi số liệu sai theo vùng máy) ──
# TRƯỚC ĐÂY dự án dùng [double]::TryParse($text,[ref]$dv) thuần (theo VĂN HOÁ MÁY), gây
# 2 hệ lụy thực tế:
#   1) Dữ liệu từ server SFIS/QA-HOUR định dạng en-US (vd "5,000" = 5000) -- trên máy đặt
#      tiếng Việt (dấu ',' là THẬP PHÂN), "5,000" bị hiểu thành 5.0: số liệu sản lượng
#      SAI IM LẶNG mà không có bất kỳ báo lỗi nào.
#   2) Người dùng Việt gõ "5000,5" (dấu ',' thập phân) trên ô Plan -- trên máy đặt en-US
#      sẽ thất bại và giá trị bị nuốt im lặng.
# CÁCH SỬA: ưu tiên parse theo InvariantCulture (',' là phân cách NGHÌN, '.' là thập phân
# -- khớp định dạng server); CHỈ khi thất bại mới thử văn hoá máy (cho dữ liệu người dùng
# gõ kiểu Việt). Với dữ liệu TỪ SERVER bắt buộc truyền -ChiInvarian để KHÔNG fallback văn
# hoá máy (tránh nhầm "5,000" thành 5.0 trên máy tiếng Việt).
function PHAN_TICH_SO([string]$chuoi, [ref]$ketQua, [switch]$ChiInvarian) {
    try {
        if ($null -eq $chuoi) { return $false }
        $chuoi = $chuoi.Trim()
        if ($chuoi -eq '') { return $false }
        $dv = 0.0
        if ([double]::TryParse($chuoi, [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dv)) {
            if ($ketQua) { $ketQua.Value = $dv }
            return $true
        }
        if ($ChiInvarian) { return $false }
        # Phương án dự phòng cho dữ liệu NGƯỜI DÙNG gõ theo thói quen Việt (vd "5000,5").
        # Chỉ chạy khi Invariant ĐÃ thất bại nên không thể nhầm lẫn 2 định dạng với nhau.
        if ([double]::TryParse($chuoi, [System.Globalization.NumberStyles]::Number, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$dv)) {
            if ($ketQua) { $ketQua.Value = $dv }
            return $true
        }
        return $false

    } catch {
        GHI_LOG "Lỗi hàm PHAN_TICH_SO: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $false
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function LAY_GIO_DA_TROI, LAY_CA_HIEN_TAI, LAY_NGAY_CA_HIEN_TAI, DINH_DANG_SO, DINH_DANG_SO_CO_DAU, DINH_DANG_GIO, DINH_DANG_GIO_PHUT, PHAN_TICH_CHUOI_SIP, PHAN_TICH_CHUOI_CFG, PHAN_TICH_SO, GHI_LOG
