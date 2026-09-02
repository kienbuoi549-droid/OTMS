# ================================================================
# Login.psm1 -- HÀM CHỨC NĂNG CHO TÍNH NĂNG ĐĂNG NHẬP USER + XÁC THỰC QUYỀN ADMIN
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

function MA_HOA_DJB2([string]$s) {
    try {
        $h = [uint32]5381
        foreach ($c in $s.ToCharArray()) {
            # QUAN TRỌNG -- KHÔNG được ép thẳng [uint32](...) trên kết quả đã vượt giới hạn:
            # [uint32](...) là 1 phép ÉP KIỂU TƯỜNG MINH, mà .NET/PowerShell sẽ KIỂM TRA
            # phạm vi và NÉM LỖI OverflowException ("Cannot convert value ... to type
            # System.UInt32 ... too large or too small") ngay khi giá trị > 4,294,967,295 --
            # Nó KHÔNG tự động "tràn số" (wraparound) như bạn nghĩ. Với chuỗi dài >= 4 ký tự,
            # DJB2 (h = h*33 + c, tương đương (h<<5)+h+c) vượt mốc này ngay từ ký tự thứ 4,
            # nên hàm sẽ lỗi với HẦU HẾT chuỗi đầu vào thực tế.
            #
            # CÁCH SỬA: dùng PHÉP NHÂN (*) và PHÉP CHIA LẤY DƯ (%) thay vì -shl/-band, và
            # ép [uint64] TƯỜNG MINH trên TỪNG số hạng riêng lẻ -- kể cả hằng số 33 và
            # 4294967296 -- để không phụ thuộc vào việc PowerShell tự suy kiểu cho 1 hằng số
            # đứng một mình (ví dụ số hex 0xFFFFFFFF có thể được suy là kiểu nào còn tuỳ phiên
            # bản/ngữ cảnh, không nên dựa vào điều đó). Khi CẢ HAI toán hạng của %  đều đã là
            # [uint64] tường minh, phép chia lấy dư chắc chắn cho kết quả trong [0, 4294967295]
            # -- đúng khoảng giá trị hợp lệ của UInt32 -- nên bước ép [uint32] cuối cùng LUÔN
            # THÀNH CÔNG, không còn phụ thuộc suy diễn về cách PowerShell xử lý hằng số tràn.
            $h = [uint32]( ( ([uint64]$h * [uint64]33) + [uint64][char]$c ) % [uint64]4294967296 )
        }
        return $h.ToString('x8')

    } catch {
        GHI_LOG "Lỗi hàm MA_HOA_DJB2: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function DAT_HASH_ADMIN {
    try {
        $global:AS.ADMIN_HASH = MA_HOA_DJB2 'VN004043'

    } catch {
        GHI_LOG "Lỗi hàm DAT_HASH_ADMIN: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function XAC_NHAN_DANG_NHAP {
    try {
        $now=Get-Date; if($now-lt $global:AS.loginLock){CAP_NHAT_KHOA_DANG_NHAP;return}
        $rawNhap=$global:e.O_Nhap_Ma_Nhan_Vien.Text.Trim()
        $code=[System.Text.RegularExpressions.Regex]::Replace($rawNhap,'[^0-9]','')
        # FIX LỖ HỔNG LOGIC: người dùng CÓ nhập nhưng KHÔNG có chữ số nào (vd gõ chữ
        # "abc") -- TRƯỚC ĐÂY chuỗi lọc rỗng rơi thẳng vào nhánh "nhập trống" bên dưới và
        # ÂM THẦM ĐĂNG NHẬP tài khoản mặc định Administrator: ai gõ linh tinh cũng vào
        # được như admin hiển thị. Sửa: báo lỗi rõ ràng, KHÔNG tự đăng nhập hộ.
        if($rawNhap -ne '' -and $code -eq ''){
            $global:e.Khung_Loi_Dang_Nhap.Visibility='Visible'
            $global:e.Label_Loi_Dang_Nhap.Text='Mã nhân viên chỉ gồm 6 chữ số (VD: 004043).'
            return
        }
        # Nhập trống → dùng tài khoản mặc định VN004043
        if($code-eq ''){
            $defName = if($global:USER_DB.ContainsKey('VN004043')){$global:USER_DB['VN004043']}else{'Administrator'}
            $global:AS.curUser='VN004043'; $global:AS.curName=$defName
            $global:e.Label_Ma_Nhan_Vien.Text='VN004043'; $global:e.Label_Chuc_Vu.Text=$defName
            # Lưu employee_id xuống SETTINGS.db NGAY (đọc thời gian đổi hiển thị UI liền,
            # không chờ tới lượt mở app sau) -- để lần mở app SAU nhớ đúng tài khoản vừa
            # chọn, không tự động "quên" về giá trị đã lưu trước đó.
            if($global:CFG.url_params['employee_id']-ne 'VN004043'){
                $global:CFG.url_params['employee_id']='VN004043'
                try { LUU_SETTINGS_DB } catch { GHI_LOG "Lỗi lưu employee_id (mặc định) sau đăng nhập: $($_.Exception.Message)" 'ERROR' }
            }
            $global:e.Khung_Loi_Dang_Nhap.Visibility='Collapsed'; $global:e.Khung_Khoa_Dang_Nhap.Visibility='Collapsed'
            DONG_LOP_PHU $global:e.Lop_Phu_Dang_Nhap; return
        }
        if($code.Length-lt 6){
            $global:e.Khung_Loi_Dang_Nhap.Visibility='Visible'
            $global:e.Label_Loi_Dang_Nhap.Text='Vui lòng nhập đủ 6 chữ số'; return
        }
        $vnId='VN'+$code
        # Tra trực tiếp theo VN ID — không dùng mã băm (hash)
        if($global:USER_DB.ContainsKey($vnId)){
            $global:AS.loginAttempts=0
            $global:AS.curUser=$vnId
            $global:AS.curName=$global:USER_DB[$vnId]
            $global:e.Label_Ma_Nhan_Vien.Text=$vnId
            $global:e.Label_Chuc_Vu.Text=$global:USER_DB[$vnId]
            # Cập nhật mã nhân viên trong CFG để tạo đường dẫn URL, VÀ lưu xuống
            # SETTINGS.db NGAY -- để lần mở app SAU nhớ đúng nhân viên vừa đăng nhập.
            $global:CFG.url_params['employee_id']=$vnId
            try { LUU_SETTINGS_DB } catch { GHI_LOG "Lỗi lưu employee_id sau đăng nhập: $($_.Exception.Message)" 'ERROR' }
            $global:e.Khung_Loi_Dang_Nhap.Visibility='Collapsed'; $global:e.Khung_Khoa_Dang_Nhap.Visibility='Collapsed'
            DONG_LOP_PHU $global:e.Lop_Phu_Dang_Nhap
        } else {
            $global:AS.loginAttempts++
            if($global:AS.loginAttempts-ge 5){
                $global:AS.loginLock=(Get-Date).AddSeconds(60); $global:AS.loginAttempts=0
                $global:e.Khung_Loi_Dang_Nhap.Visibility='Collapsed'; CAP_NHAT_KHOA_DANG_NHAP
            } else {
                $left=5-$global:AS.loginAttempts
                $global:e.Khung_Loi_Dang_Nhap.Visibility='Visible'
                $global:e.Label_Loi_Dang_Nhap.Text="Mã $vnId không tồn tại trong hệ thống. Còn $left lần thử."
            }
        }

    } catch {
        GHI_LOG "Lỗi hàm XAC_NHAN_DANG_NHAP: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function CAP_NHAT_KHOA_DANG_NHAP {
    try {
        # FIX RÒ RỈ TIMER -- hàm này chạy lại MỖI LẦN người dùng bấm Enter khi đang bị
        # khoá (XAC_NHAN_DANG_NHAP gọi ngay ở dòng đầu tiên). Trước đây mỗi lần gọi tạo
        # MỘT DispatcherTimer 1 giây MỚI: spam Enter 30 lần khi bị khoá = 30 timer chạy
        # song song cập nhật cùng 1 label cho tới hết thời gian khoá. Có cờ guard thì
        # chỉ timer ĐẦU TIÊN được tạo, các lần gọi sau bỏ qua (timer đang chạy tự lo
        # cập nhật đếm ngược và tự dừng đúng lúc).
        if ($global:AS.Contains('loginLockTimerDangChay') -and $global:AS.loginLockTimerDangChay) { return }
        $now=Get-Date; $diff=($global:AS.loginLock-$now).TotalSeconds
        if($diff-gt 0){
            $global:e.Khung_Khoa_Dang_Nhap.Visibility='Visible'
            $global:e.Label_Khoa_Dang_Nhap.Text="Tài khoản tạm khoá. Thử lại sau $([int][Math]::Ceiling($diff)) giây."
            $global:e.Button_Xac_Nhan_Dang_Nhap.IsEnabled=$false
            $global:AS.loginLockTimerDangChay=$true
            $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromSeconds(1)
            $t.Add_Tick({
                $n2=Get-Date
                if($n2-ge $global:AS.loginLock){$global:AS.loginLockTimerDangChay=$false;$global:e.Khung_Khoa_Dang_Nhap.Visibility='Collapsed';$global:e.Button_Xac_Nhan_Dang_Nhap.IsEnabled=$true;$t.Stop()}
                else{$global:e.Label_Khoa_Dang_Nhap.Text="Tài khoản tạm khoá. Thử lại sau $([int][Math]::Ceiling(($global:AS.loginLock-$n2).TotalSeconds)) giây."}
            }.GetNewClosure()); $t.Start()
        } else {$global:e.Khung_Khoa_Dang_Nhap.Visibility='Collapsed';$global:e.Button_Xac_Nhan_Dang_Nhap.IsEnabled=$true}

    } catch {
        GHI_LOG "Lỗi hàm CAP_NHAT_KHOA_DANG_NHAP: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ================================================================
# VÙNG 17 — XÁC THỰC QUYỀN TRUY CẬP CÀI ĐẶT CHUNG (Chỉ quản trị viên)
# ================================================================
function XAC_NHAN_QUYEN_TRUY_CAP {
    try {
        $now=Get-Date; if($now-lt $global:AS.cfgLock){CAP_NHAT_KHOA_CAU_HINH;return}
        $user=$global:e.O_Nhap_Ma_NV_Admin.Text.Trim(); $pass=$global:e.O_Nhap_Mat_Khau.Password.Trim()
        $userOk=(MA_HOA_DJB2 $user)-eq $global:AS.ADMIN_HASH
        # Mật khẩu đúng theo phút: chuỗi "HHmm4043" của thời điểm hiện tại, băm qua CÙNG 1
        # hàm MA_HOA_DJB2 duy nhất (không còn hàm riêng LAY_HASH_MAT_KHAU nữa) để đảm bảo
        # 2 vế luôn dùng chung 1 thuật toán hash, không thể lệch nhau.
        $n=Get-Date; $chuoiMatKhauDungGio = $n.ToString('HH')+$n.ToString('mm')+'4043'
        $passOk=(MA_HOA_DJB2 $pass)-eq (MA_HOA_DJB2 $chuoiMatKhauDungGio)
        if(-not $userOk -or -not $passOk){
            $global:AS.cfgAttempts++
            if($global:AS.cfgAttempts-ge 3){
                $global:AS.cfgLock=(Get-Date).AddSeconds(120); $global:AS.cfgAttempts=0
                $global:e.O_Nhap_Mat_Khau.Password=''; CAP_NHAT_KHOA_CAU_HINH
            } else {
                $left=3-$global:AS.cfgAttempts
                $msg=if(-not $userOk){'Tài khoản không có quyền.'}else{'Mật khẩu không đúng.'}
                $global:e.Khung_Loi_Xac_Thuc.Visibility='Visible'; $global:e.Label_Loi_Xac_Thuc.Text="$msg Còn $left lần thử."
                $global:e.O_Nhap_Mat_Khau.Password=''; $global:e.O_Nhap_Mat_Khau.Focus()|Out-Null
            }
            return
        }
        $global:AS.cfgAttempts=0; DONG_LOP_PHU $global:e.Lop_Phu_Xac_Thuc_Quyen
        XAY_DUNG_FORM_CAU_HINH; MO_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung $global:e.Ty_Le_Cai_Dat_Chung

    } catch {
        GHI_LOG "Lỗi hàm XAC_NHAN_QUYEN_TRUY_CAP: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function CAP_NHAT_KHOA_CAU_HINH {
    try {
        # FIX RÒ RỈ TIMER -- y hệt CAP_NHAT_KHOA_DANG_NHAP: mỗi lần bấm Xác nhận khi đang
        # bị khoá trước đây tạo thêm 1 DispatcherTimer mới. Cờ guard chỉ cho tạo 1 timer.
        if ($global:AS.Contains('cfgLockTimerDangChay') -and $global:AS.cfgLockTimerDangChay) { return }
        $now=Get-Date; $diff=($global:AS.cfgLock-$now).TotalSeconds
        if($diff-gt 0){
            $global:e.Khung_Loi_Xac_Thuc.Visibility='Visible'
            $global:e.Label_Loi_Xac_Thuc.Text="Bị khoá. Thử lại sau $([int][Math]::Ceiling($diff)) giây."
            $global:e.Button_Xac_Nhan_Quyen.IsEnabled=$false
            $global:AS.cfgLockTimerDangChay=$true
            $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromSeconds(1)
            $t.Add_Tick({
                $n2=Get-Date
                if($n2-ge $global:AS.cfgLock){$global:AS.cfgLockTimerDangChay=$false;$global:e.Khung_Loi_Xac_Thuc.Visibility='Collapsed';$global:e.Button_Xac_Nhan_Quyen.IsEnabled=$true;$t.Stop()}
                else{$global:e.Label_Loi_Xac_Thuc.Text="Bị khoá. Thử lại sau $([int][Math]::Ceiling(($global:AS.cfgLock-$n2).TotalSeconds)) giây."}
            }.GetNewClosure()); $t.Start()
        } else {$global:e.Khung_Loi_Xac_Thuc.Visibility='Collapsed';$global:e.Button_Xac_Nhan_Quyen.IsEnabled=$true}

    } catch {
        GHI_LOG "Lỗi hàm CAP_NHAT_KHOA_CAU_HINH: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Nạp lại nhân viên đã đăng nhập LẦN GẦN NHẤT (employee_id đã lưu trong SETTINGS.db)
# NGAY LÚC MỞ APP -- GỌI SAU khi KHOI_TAO_DB (NAP_SETTINGS_DB + NAP_USER_DB) đã chạy
# xong, TRƯỚC khi Window.Loaded hiển thị Label_Ma_Nhan_Vien/Label_Chuc_Vu (xem main.ps1).
# Nếu KHÔNG gọi hàm này, $global:AS.curUser/curName sẽ LUÔN đứng yên ở giá trị mặc định
# VN004043/Administrator đặt sẵn trong KHOI_TAO_BIEN (Variable.psm1) mỗi lần mở app, dù
# lần trước đã đăng nhập bằng nhân viên khác và employee_id đó ĐÃ được lưu xuống
# SETTINGS.db (xem XAC_NHAN_DANG_NHAP) -- vì KHOI_TAO_BIEN chạy TRƯỚC KHOI_TAO_DB nên
# không thể tự đọc được employee_id ngay trong lúc khởi tạo biến.
function NAP_NGUOI_DUNG_DA_LUU {
    try {
        $idDaLuu = $global:CFG.url_params['employee_id']
        if (-not [string]::IsNullOrWhiteSpace($idDaLuu) -and $global:USER_DB.ContainsKey($idDaLuu)) {
            $global:AS.curUser = $idDaLuu
            $global:AS.curName = $global:USER_DB[$idDaLuu]
        }
        # employee_id đã lưu KHÔNG tồn tại trong USER_DB (vd nhân viên đó đã bị xoá khỏi
        # USER.db sau khi lưu) -- GIỮ NGUYÊN mặc định VN004043/Administrator, không cần
        # làm gì thêm ở đây.

    } catch {
        GHI_LOG "Lỗi hàm NAP_NGUOI_DUNG_DA_LUU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function MA_HOA_DJB2, DAT_HASH_ADMIN, XAC_NHAN_DANG_NHAP, CAP_NHAT_KHOA_DANG_NHAP, XAC_NHAN_QUYEN_TRUY_CAP, CAP_NHAT_KHOA_CAU_HINH, NAP_NGUOI_DUNG_DA_LUU
