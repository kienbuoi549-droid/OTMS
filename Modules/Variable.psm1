# ================================================================
# Variable.psm1 -- QUẢN LÝ BIẾN (Đường dẫn, khoá AES, trạng thái ứng dụng, hashtable phần tử giao diện)
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

function KHOI_TAO_BIEN([string]$RootDir) {
    try {
        # ── ĐƯỜNG DẪN GỐC + LOG (RootDir truyền vào từ main.ps1) -- PATH_LOG luôn cạnh
        # ứng dụng, KHÔNG đổi theo folder_data, để vẫn ghi được log ngay cả khi cấu hình
        # folder_data trỏ sai đường dẫn ──
        $global:ROOT_DIR = $RootDir
        $global:PATH_LOG = Join-Path $global:ROOT_DIR 'Loi.log'

        # ── KHOÁ VÀ VECTƠ KHỞI TẠO AES (cố định theo thông số kỹ thuật, đặt SỚM -- cần
        # dùng để dò đọc SETTINGS.db ở bước ngay bên dưới) ──
        # Khóa AES và Vectơ khởi tạo (IV) — cố định theo thông số kỹ thuật
        $global:AES_KEY = [byte[]](
        0x4F,0x56,0x45,0x4E,0x44,0x42,0x4B,0x45,
        0x59,0x32,0x30,0x32,0x35,0x4F,0x54,0x4D,
        0x53,0x41,0x45,0x53,0x32,0x35,0x36,0x42,
        0x49,0x54,0x4B,0x45,0x59,0x46,0x4F,0x52
        )
        $global:AES_IV = [byte[]](
        0x4F,0x54,0x4D,0x53,0x49,0x56,0x31,0x36,
        0x42,0x59,0x54,0x45,0x32,0x30,0x32,0x35
        )

        # ── BƯỚC 1: XÁC ĐỊNH ĐƯỜNG DẪN SETTINGS.db "CHUẨN" -- qua D:\OTMS\Info.xml nếu file
        # này đã tồn tại (người dùng có thể đã đổi qua thẻ riêng trong "Cài đặt chung"),
        # hoặc mặc định D:\OTMS\Data\SETTINGS.db nếu Info.xml CHƯA từng được tạo.
        #
        # QUAN TRỌNG: đường dẫn SETTINGS.db giờ ĐỘC LẬP với DATA_DIR (khác MO.db/USER.db/
        # Active.db vẫn đi theo folder_data/folder_database như trước, xem BƯỚC 2) -- cho
        # phép SETTINGS.db được dời tới bất kỳ đâu qua Info.xml MÀ KHÔNG cần bản thân
        # SETTINGS.db đã đọc được mới biết đường dẫn của chính nó (né vòng lặp "phải đọc
        # được SETTINGS.db mới biết SETTINGS.db ở đâu" mà folder_data/folder_database --
        # nằm BÊN TRONG SETTINGS.db -- luôn gặp phải).
        #
        # AN TOÀN: mọi lỗi đọc Info.xml (chưa có file, XML hỏng...) đều ÂM THẦM rơi về
        # đường dẫn MẶC ĐỊNH, không làm ứng dụng treo lúc khởi động.
        $global:THU_MUC_OTMS_GOC     = 'D:\OTMS'
        $global:PATH_INFO_XML        = Join-Path $global:THU_MUC_OTMS_GOC 'Info.xml'
        $duongDanSettingsMacDinh     = Join-Path (Join-Path $global:THU_MUC_OTMS_GOC 'Data') 'SETTINGS.db'
        $global:PATH_SETTINGS        = $duongDanSettingsMacDinh
        try {
            if (Test-Path $global:PATH_INFO_XML) {
                # Đọc qua DOC_BYTE_FILE_KHONG_CHAN_GHI (Database.psm1) thay vì Get-Content
                # -- đồng bộ nguyên tắc đọc file DÙNG CHUNG cho MỌI file .db/.xml trong dự
                # án: chia sẻ rộng nhất (không chặn tiến trình khác ghi/đổi tên đè lên
                # Info.xml), đọc xong đóng file NGAY, không giữ treo handle. Info.xml
                # không mã hoá/nén nên chỉ cần giải mã UTF-8 (bỏ qua bước AES/GZip của
                # DOC_FILE_DB) -- .TrimStart([char]0xFEFF) loại bỏ BOM UTF-8 nếu có, vì
                # Encoding.UTF8.GetString() KHÔNG tự động bỏ BOM như Get-Content -Encoding
                # UTF8 vẫn làm (GHI_INFO_XML ghi bằng Encoding.UTF8 nên CÓ kèm BOM).
                $bytesInfoXml   = DOC_BYTE_FILE_KHONG_CHAN_GHI $global:PATH_INFO_XML
                $noiDungInfoXml = [System.Text.Encoding]::UTF8.GetString($bytesInfoXml).TrimStart([char]0xFEFF)
                [xml]$infoDoc   = $noiDungInfoXml
                $duongDanTuXml = $infoDoc.OTMSInfo.SettingsPath
                if (-not [string]::IsNullOrWhiteSpace($duongDanTuXml)) {
                    $global:PATH_SETTINGS = $duongDanTuXml
                }
            }
        } catch {
            # KHÔNG để catch RỖNG ở đây -- Info.xml lỗi (XML hỏng, ký tự chưa thoát...)
            # trước đây bị NUỐT ÂM THẦM, app luôn rơi về đường dẫn mặc định mà KHÔNG một
            # dòng log nào giải thích vì sao, rất khó debug. Vẫn GIỮ NGUYÊN hành vi rơi về
            # mặc định (không throw ra ngoài) -- lỗi Info.xml không được phép làm app treo
            # lúc khởi động, chỉ cần biết được LÝ DO qua log. GHI_LOG an toàn gọi ở đây vì
            # $global:PATH_LOG đã được gán ngay đầu hàm này, và module Support.psm1 (định
            # nghĩa GHI_LOG) đã Import-Module xong trước khi KHOI_TAO_BIEN được gọi (xem
            # main.ps1).
            GHI_LOG "KHOI_TAO_BIEN: Info.xml tồn tại nhưng đọc/phân tích thất bại -- dùng đường dẫn SETTINGS.db mặc định. Lỗi: $($_.Exception.Message)" 'ERROR'
        }

        # ── BƯỚC 2: DÒ folder_data/folder_database TỪ SETTINGS.db (đọc thử tại đường dẫn
        # vừa xác định ở BƯỚC 1) để xác định DATA_DIR/DATABASE_DIR cho MO.db/USER.db/
        # Active.db -- 3 file này VẪN đi theo folder_data/folder_database như trước,
        # KHÔNG bị ảnh hưởng bởi việc SETTINGS.db được dời đi đâu qua Info.xml.
        # BẮT BUỘC dò lại MỖI LẦN hàm này chạy (không cache ra ngoài) -- KHOI_TAO_BIEN
        # được gọi ĐỘC LẬP trên CẢ UI thread lẫn Runspace nền (mỗi chu kỳ refresh trong
        # BAT_DAU_LAM_MOI_NEN), 2 bên KHÔNG chia sẻ $global:, nên nếu không tự dò lại ở
        # đây, Runspace nền sẽ đọc nhầm MO.db/USER.db ở thư mục MẶC ĐỊNH trong khi UI
        # thread đã đổi sang thư mục khác.
        $dataDirMacDinh = Join-Path $global:THU_MUC_OTMS_GOC 'Data'
        $dataDirThucTe  = $dataDirMacDinh
        $dbDirThucTe    = $null
        $daDoiDuongDan  = $false
        try {
            $jsonDo = DOC_FILE_DB_HOA_NULL $global:PATH_SETTINGS
            if ($jsonDo) {
                $cfgDo = $jsonDo | ConvertFrom-Json
                if ($cfgDo.config) {
                    $fdDo = [string]$cfgDo.config.folder_data
                    $fbDo = [string]$cfgDo.config.folder_database
                    if (-not [string]::IsNullOrWhiteSpace($fdDo)) { $dataDirThucTe = $fdDo; $daDoiDuongDan = $true }
                    if (-not [string]::IsNullOrWhiteSpace($fbDo)) { $dbDirThucTe   = $fbDo; $daDoiDuongDan = $true }
                }
            }
        } catch { }
        if (-not $dbDirThucTe) { $dbDirThucTe = Join-Path $dataDirThucTe 'DATABASE' }
        if ($daDoiDuongDan) {
            GHI_LOG "KHOI_TAO_BIEN: dùng đường dẫn tuỳ chỉnh -- DATA_DIR=$dataDirThucTe | DATABASE_DIR=$dbDirThucTe" 'INFO'
        }

        # ── ĐƯỜNG DẪN FILE VÀ THƯ MỤC CHÍNH THỨC ──
        $global:DATA_DIR      = $dataDirThucTe
        $global:DATABASE_DIR  = $dbDirThucTe
        $global:PATH_MO       = Join-Path $global:DATA_DIR  'MO.db'
        $global:PATH_USER     = Join-Path $global:DATA_DIR  'USER.db'
        # $global:PATH_SETTINGS ĐÃ được xác định ở BƯỚC 1 (qua Info.xml hoặc mặc định) --
        # KHÔNG ghi đè lại theo DATA_DIR ở đây nữa như các phiên bản trước.
        $global:PATH_ACTIVE   = Join-Path $global:DATABASE_DIR 'Active.db'

        # ── TRẠNG THÁI ỨNG DỤNG (giữ trong bộ nhớ khi chạy) ──
        $global:AS = @{
        models        = [System.Collections.Generic.List[PSObject]]::new()
        settingsModels= [System.Collections.Generic.List[PSObject]]::new()
        ovenDets      = @{}
        curUser       = 'VN004043'
        curName       = 'Administrator'
        editModelId   = $null
        moEmpty       = $false        # true khi MO.db không tồn tại/rỗng
        loginAttempts = 0
        loginLock     = [datetime]::MinValue
        cfgAttempts   = 0
        cfgLock       = [datetime]::MinValue
        ADMIN_HASH    = ''
        }

        # ── CÁC BIẾN DỮ LIỆU CHÍNH (rỗng ban đầu, Database.psm1 nạp sau) ──
        $global:MO_DB     = [ordered]@{}
        $global:USER_DB   = @{}
        $global:CFG       = @{ items=@{}; config=@{}; url_params=@{}; urls=@{} }
        $global:OVEN_DATA = @()

        # ── CỜ BẬT/TẮT GHI LOG HỆ THỐNG -- mặc định BẬT, sẽ được NAP_SETTINGS_DB
        # đồng bộ lại theo config.enable_log đã lưu (nếu có) ngay sau khi nạp SETTINGS.db.
        # Chỉnh được trong Popup "Cài đặt chung". ──
        $global:LOG_ENABLE = $true

        # ── HASHTABLE CHỨA CÁC PHẦN TỬ GIAO DIỆN (FindName điền vào trong main.ps1) ──
        $global:e = @{
        # Vùng header
        Label_Ca_Lam_Viec=$null; Khung_Ca_Lam_Viec=$null; Label_Dong_Ho=$null; Label_Cap_Nhat_Luc=$null
        Button_Lam_Moi_Nhanh=$null
        Label_Ma_Nhan_Vien=$null; Label_Chuc_Vu=$null; Khung_Nguoi_Dung=$null; Label_Tong_San_Luong=$null
        # Section 2 — bảng theo dõi sản lượng
        Bang_San_Luong=$null; Hieu_Ung_Mo=$null
        # Section 3 — khu vực lò nướng
        The_Lo_Nuong_1=$null; The_Lo_Nuong_2=$null; Label_Ten_Lo_1=$null; Label_Ten_Lo_2=$null
        Label_So_Luong_Lo_1=$null; Label_So_Luong_Lo_2=$null; Label_Tong_Sip_Lo_1=$null; Label_Tong_Sip_Lo_2=$null
        Danh_Sach_Lo_1=$null; Danh_Sach_Lo_2=$null; Danh_Sach_Xep_Hang_1=$null; Danh_Sach_Xep_Hang_2=$null
        # Popup thông tin hàng (row popup)
        Popup_Tien_Do=$null; Label_Popup_Ten_Model=$null
        Label_Popup_Ca_Con_Lai=$null; Label_Popup_Ca_Box=$null; Label_Popup_Ca_Gio=$null
        Label_Popup_Tong_Con_Lai=$null; Label_Popup_Tong_Box=$null; Label_Popup_Tong_Gio=$null
        # Popup chi tiết lò nướng
        Popup_Chi_Tiet_Lo=$null; Label_Popup_Ma_Lo=$null; Label_Popup_Mag=$null; Label_Popup_Sip=$null
        Khung_Popup_Noi_Dung=$null; Button_Dong_Popup_Lo=$null
        # Lớp phủ thông báo (WIP)
        Lop_Phu_Thong_Bao=$null; Label_Thong_Bao_Tieu_De=$null; Label_Thong_Bao_Noi_Dung=$null
        Button_Dong_Thong_Bao=$null; Xoay_Banh_Rang=$null; Ty_Le_Thong_Bao=$null
        # Lớp phủ đăng nhập
        Lop_Phu_Dang_Nhap=$null; Ty_Le_Khung_Dang_Nhap=$null; O_Nhap_Ma_Nhan_Vien=$null
        Khung_Khoa_Dang_Nhap=$null; Label_Khoa_Dang_Nhap=$null; Khung_Loi_Dang_Nhap=$null
        Label_Loi_Dang_Nhap=$null; Button_Xac_Nhan_Dang_Nhap=$null
        # Lớp phủ cài đặt sản lượng
        Lop_Phu_Cai_Dat_San_Luong=$null; Ty_Le_Cai_Dat_San_Luong=$null; Khung_Danh_Sach_Model=$null
        Khung_Loi_Cai_Dat=$null; Label_Loi_Cai_Dat=$null
        Button_Dong_Cai_Dat_San_Luong=$null; Button_Them_Model=$null; Button_Luu_Cai_Dat_San_Luong=$null; Button_Huy_Cai_Dat_San_Luong=$null
        # Lớp phủ xác thực cài đặt chung
        Lop_Phu_Xac_Thuc_Quyen=$null; Ty_Le_Xac_Thuc_Quyen=$null; O_Nhap_Ma_NV_Admin=$null; O_Nhap_Mat_Khau=$null
        Khung_Loi_Xac_Thuc=$null; Label_Loi_Xac_Thuc=$null; Button_Huy_Xac_Thuc=$null; Button_Xac_Nhan_Quyen=$null
        # Lớp phủ cài đặt chung
        Lop_Phu_Cai_Dat_Chung=$null; Ty_Le_Cai_Dat_Chung=$null; Khung_Form_Cai_Dat_Chung=$null
        CheckBox_Bat_Ghi_Log=$null; O_Nhap_Duong_Dan_Settings=$null
        Button_Luu_Cai_Dat_Chung=$null; Button_Huy_Cai_Dat_Chung=$null; Button_Dong_Cai_Dat_Chung=$null; Label_Da_Luu_Thanh_Cong=$null
        # Lớp phủ sửa plan
        Lop_Phu_Sua_Plan=$null; Ty_Le_Sua_Plan=$null; Label_Model_Dang_Sua=$null
        O_Nhap_So_Luong_Plan=$null; Button_Huy_Sua_Plan=$null; Button_Luu_Sua_Plan=$null
        # Thanh điều hướng (Thanh_Dieu_Huong)
        Nav_Trang_Chu=$null; Nav_Tim_Kiem=$null; Nav_Cai_Dat_San_Luong=$null; Nav_Cai_Dat_Chung=$null; Nav_Quan_Tri_He_Thong=$null; Button_Dang_Xuat=$null
        # Nút điều khiển cửa sổ (chấm tròn macOS)
        Cham_Do=$null; Cham_Vang=$null; Cham_Xanh=$null; Khung_Cham_Tieu_De=$null
        # Khác
        Thanh_Dieu_Huong=$null; Khung_Thong_Tin_Phien_Ban=$null
        }

    } catch {
        GHI_LOG "Lỗi hàm KHOI_TAO_BIEN: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function KHOI_TAO_BIEN
