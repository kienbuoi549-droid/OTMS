# ================================================================
# main.ps1 -- Điều phối toàn bộ module cho OTMSAnalyzer V10
# Ứng dụng màn hình toàn phần (WPF / PowerShell 5.1)
# Mã hoá dữ liệu: AES-256-CBC + Nén GZip
# Cách chạy: powershell.exe -ExecutionPolicy Bypass -File main.ps1
# ================================================================
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$global:DONG_HO_KHOI_DONG = [System.Diagnostics.Stopwatch]::StartNew()
function _GHI_MOC_THOI_GIAN([string]$tenBuoc) {
    $ms = $global:DONG_HO_KHOI_DONG.ElapsedMilliseconds
    Write-Host "[$ms ms] $tenBuoc"
    try { GHI_LOG "[KHOI_DONG +$($ms)ms] $tenBuoc" } catch { }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ================================================================
# CHẶN MỞ TRÙNG LẶP ỨNG DỤNG (Mutex hệ thống -- không phụ thuộc file, không có rủi ro
# "file khoá còn sót lại" nếu app crash bất thường như cách dùng file .lock)
# ================================================================
$global:MUTEX_UNG_DUNG = $null
try {
    $daTaoMoiMutex = $false
    $global:MUTEX_UNG_DUNG = New-Object System.Threading.Mutex($true, 'Global\OTMSAnalyzer_SingleInstance', [ref]$daTaoMoiMutex)
    if (-not $daTaoMoiMutex) {
        [System.Windows.MessageBox]::Show(
            "OTMSAnalyzer đang chạy rồi. Không thể mở thêm bản thứ hai cùng lúc.",
            'Ứng dụng đang chạy', 'OK', 'Warning') | Out-Null
        exit
    }
} catch {
    # Lỗi tạo Mutex (rất hiếm gặp) -- KHÔNG chặn người dùng mở app vì lý do không chắc
    # chắn, chỉ bỏ qua bước kiểm tra và cho chạy tiếp bình thường.
}

# ================================================================
# TRẠNG THÁI DÙNG CHUNG GIỮA UI THREAD VÀ RUNSPACE NỀN (hashtable ĐỒNG BỘ HOÁ -- an
# toàn đọc/ghi đồng thời từ NHIỀU LUỒNG/RUNSPACE khác nhau trong CÙNG 1 tiến trình).
# KHỞI TẠO ĐÚNG 1 LẦN Ở ĐÂY, TRƯỚC KHI TẠO Runspace nền -- không được tạo lại bên trong
# KHOI_TAO_BIEN hay bất kỳ đâu chạy lặp lại mỗi chu kỳ, nếu không mỗi lần tạo lại sẽ RA
# 1 ĐỐI TƯỢNG KHÁC, làm mất tác dụng "dùng chung" giữa UI thread và Runspace nền.
#   - ActiveDbDaThayDoi: FileSystemWatcher đặt $true khi phát hiện Active.db đổi; đọc +
#     reset về $false bởi refreshTimer (hoặc nút Làm Mới Nhanh) ở lần chạy KẾ TIẾP.
#   - GhiLogBat: cờ bật/tắt ghi log DÙNG CHUNG cho GHI_LOG (Support.psm1) -- đổi công tắc
#     "Ghi log hệ thống" trong Cài đặt chung áp dụng NGAY LẬP TỨC cho CẢ UI thread LẪN
#     Runspace nền, không cần đợi Runspace nền tự đọc lại SETTINGS.db ở chu kỳ sau.
$global:TRANG_THAI_DUNG_CHUNG = [hashtable]::Synchronized(@{
    # Bắt đầu $true (khác mặc định $false trước đây) -- ÉP lượt BAT_DAU_LAM_MOI_NEN ĐẦU
    # TIÊN (gọi từ Window.Add_Loaded) phải đọc Active.db ngay. FileSystemWatcher CHỈ được
    # bật (EnableRaisingEvents=$true) SAU KHI BAT_DAU_LAM_MOI_NEN đã được gọi lần đầu (xem
    # cuối Window.Add_Loaded bên dưới), nên không thể tự báo "đã đổi" kịp cho lượt đầu đó.
    # Nếu để $false như cũ, card lò nướng sẽ trống ("0 OVEN") cho tới khi Active.db đổi LẦN
    # ĐẦU sau khi mở app và watcher kịp bắt -- có thể mất nhiều phút, hoặc không bao giờ
    # nếu dữ liệu chưa đổi. Cờ tự reset về $false ngay sau khi được "tiêu thụ" ở chu kỳ đầu
    # (xem BAT_DAU_LAM_MOI_NEN), không ảnh hưởng logic "chỉ đọc lại khi có đổi" ở các chu kỳ
    # kế tiếp.
    ActiveDbDaThayDoi = $true
    GhiLogBat         = $true
})

# ================================================================
# XÁC ĐỊNH THƯ MỤC GỐC ỨNG DỤNG
# (Phải tính ở đây, KHÔNG được tính trong module .psm1 -- vì $PSScriptRoot
#  bên trong 1 .psm1 sẽ trỏ về thư mục Modules/, không phải thư mục gốc)
# ================================================================
$APP_ROOT = if ($PSScriptRoot -and $PSScriptRoot -ne '') {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
_GHI_MOC_THOI_GIAN "Xác định APP_ROOT xong"

# ================================================================
# NẠP TẤT CẢ MODULE TỪ THƯ MỤC Modules/
# ================================================================
$moduleDir = Join-Path $APP_ROOT 'Modules'
foreach ($modName in @('Variable','Database','Support','App','Login',
                       'Production','OvenBaking','Output_setting','General_Install','QaHour')) {
    $modPath = Join-Path $moduleDir "$modName.psm1"
    if (Test-Path $modPath) {
        Import-Module $modPath -Force -Global
    } else {
        Write-Warning "[main] Không tìm thấy module: $modPath"
    }
}
_GHI_MOC_THOI_GIAN "Import-Module 9 module xong"

# ================================================================
# KHỞI TẠO BIẾN TOÀN CỤC (đường dẫn, AES key/iv, trạng thái app, $e rỗng)
# ================================================================
KHOI_TAO_BIEN -RootDir $APP_ROOT
DAT_HASH_ADMIN
_GHI_MOC_THOI_GIAN "KHOI_TAO_BIEN + DAT_HASH_ADMIN xong"

# ================================================================
# KHỞI TẠO ĐỒNG HỒ (màu ca ngày/đêm + DispatcherTimer) — tạo ĐÚNG 1 LẦN;
# Start()/Stop() theo vòng đời cửa sổ UI.xaml trong vòng lặp điều hướng bên dưới
# ================================================================
KHOI_TAO_DONG_HO
_GHI_MOC_THOI_GIAN "KHOI_TAO_DONG_HO xong"

# ================================================================
# HỆ THỐNG NẠP ĐA GIAO DIỆN (UI.xaml <-> OvenRanking.xaml <-> MiniMap.xaml)
# ================================================================
# Luồng điều hướng (3 chấm macOS trên từng cửa sổ):
#   UI.xaml         : CHAM XANH -> OvenRanking | VÀNG -> thu nhỏ (như cũ) | ĐỎ -> thoát app
#   OvenRanking.xaml: CHAM XANH -> MiniMap     | VÀNG -> về UI.xaml    | ĐỎ -> thoát app
#   MiniMap.xaml    : CHAM XANH -> OvenRanking | VÀNG -> ẩn xuống taskbar | ĐỎ -> thoát app
# Cơ chế: vòng lặp dưới cuối main.ps1 nạp cửa sổ theo $global:MAN_HINH_KE rồi ShowDialog();
# bấm chấm chỉ đặt lại $global:MAN_HINH_KE rồi Close() -- ShowDialog trả về, vòng lặp nạp
# cửa sổ KẾ TIẾP. Toàn bộ dữ liệu $global và Runspace nền 60s/Runspace_LO GIỮ NGUYÊN,
# KHÔNG thoát tiến trình (chỉ thoát hẳn khi MAN_HINH_KE = 'EXIT').
#   - Dispatcher là per-THREAD: mọi cửa sổ tạo trên main thread dùng chung 1 Dispatcher,
#     nên marshal $global:W.Dispatcher của FileSystemWatcher vẫn hợp lệ sau khi đổi cửa sổ.
#   - $global:UI_HOAT_DONG: cờ "cửa sổ UI.xaml đang sống" -- phần cập nhật element giao diện
#     của timer nền chỉ chạy khi cờ $true (dữ liệu/thuần tính toán vẫn chạy tiếp mỗi chu kỳ).
$global:UI_HOAT_DONG = $false
$global:MAN_HINH_KE  = 'UI'
# Màn hình ĐANG sống ('UI' | 'RANKING' | 'MINIMAP') -- timer nền (BG_POLL_TIMER_LO)
# dùng biến này để biết phải vẽ dữ liệu lò mới vào giao diện nào
$global:MAN_HINH_HIEN_TAI = 'UI'
# V2.4 -- Lịch sử oven hoàn thành gần nhất theo loại lò, nguồn yyyymmdd.db (mốc thời
# gian ca làm việc hiện tại), do Runspace_LO đọc và trả về cùng $global:OVEN_DATA
$global:LO_LICH_SU = @{}

# ── Nạp 1 file XAML trong APP_ROOT thành Window + dựng lại $global:e tự động ──
# Quét TOÀN BỘ x:Name trong tài liệu XML rồi FindName từng cái -- không phải khai báo tay
# danh sách element cho từng giao diện mới (giống cách $global:e cũ nhưng tự động hoá).
# Nạp LỖI -> $global:W = $null: vòng lặp điều hướng sẽ thoát sạch sẽ qua khối dọn dẹp
# thay vì để exception giết tiến trình (rò rỉ Mutex/Runspace).
function NAP_CUA_SO([string]$tenFileXaml){
    try {
        $xamlPath = Join-Path $APP_ROOT $tenFileXaml
        [xml]$XamlDoc = Get-Content -Path $xamlPath -Raw -Encoding UTF8
        $reader = New-Object System.Xml.XmlNodeReader $XamlDoc
        $global:W = [Windows.Markup.XamlReader]::Load($reader)
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($XamlDoc.NameTable)
        $nsMgr.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
        $reg = @{}
        foreach ($node in $XamlDoc.SelectNodes('//*[@x:Name]', $nsMgr)) {
            $ten = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
            if ($ten) { $reg[$ten] = $global:W.FindName($ten) }
        }
        $global:e = $reg
    } catch {
        $global:W = $null
        try {
            [System.Windows.MessageBox]::Show(
                "Lỗi nạp giao diện ${tenFileXaml}:`n$($_.Exception.Message)",
                'Lỗi giao diện', 'OK', 'Error') | Out-Null
        } catch { }
        GHI_LOG "Lỗi NAP_CUA_SO ${tenFileXaml}: $($_.Exception.Message)" 'ERROR'
    }
}

# ── Đóng cửa sổ hiện tại và đi tới màn hình kế tiếp ('UI' | 'RANKING' | 'MINIMAP' | 'EXIT') ──
function DONG_VE([string]$manHinhKe){
    $global:MAN_HINH_KE = $manHinhKe
    $global:W.Close()
}

# ── Gán 3 chấm macOS cho cửa sổ hiện tại (cùng vị trí, khác hành vi từng màn hình) ──
# (đặt tên param $doHanh -- tránh trùng từ khóa 'do' của PowerShell)
function GAN_CHAM_MAC([scriptblock]$xanh, [scriptblock]$vang, [scriptblock]$doHanh){
    try {
        if ($global:e.Cham_Xanh) { $global:e.Cham_Xanh.Add_MouseLeftButtonDown($xanh) }
        else { GHI_LOG "GAN_CHAM_MAC: Cham_Xanh null -- handler xanh không gán được" 'ERROR' }

        if ($global:e.Cham_Vang) { $global:e.Cham_Vang.Add_MouseLeftButtonDown($vang) }
        else { GHI_LOG "GAN_CHAM_MAC: Cham_Vang null -- handler vàng không gán được" 'ERROR' }

        if ($global:e.Cham_Do) { $global:e.Cham_Do.Add_MouseLeftButtonDown($doHanh) }
        else { GHI_LOG "GAN_CHAM_MAC: Cham_Do null -- handler đỏ không gán được" 'ERROR' }
    } catch {
        GHI_LOG "Lỗi GAN_CHAM_MAC: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ════════════════════════════════════════════════════════════════
# MÀN HÌNH OvenRanking.xaml — xếp hạng lò nướng (DỮ LIỆU THẬT v2,4)
# Nguồn: $global:OVEN_DATA -- Runspace_LO đọc Active.db theo 2 loại lò trong
# SETTINGS.items. Bảng lò / Top Ranking / popup chi tiết dựng ĐỘNG từng hàng
# (XAML chỉ giữ khung card + container Card{1,2}_Rows/Rank/KhuVucDuoi).
# ════════════════════════════════════════════════════════════════
# Bản đồ phần tử động đang sống trên cửa sổ Ranking (dựng lại mỗi lần vẽ):
#   RANKING_POP_MAP : ovenId -> Border popup   |  RANKING_ROW_MAP : ovenId -> Border hàng
#   RANKING_POP_MO / RANKING_ROW_MO / RANKING_ROW_MO_ID : popup đang mở (giữ qua lần vẽ lại)
$global:RANKING_POP_MAP   = @{}
$global:RANKING_ROW_MAP   = @{}
$global:RANKING_POP_MO    = $null
$global:RANKING_ROW_MO    = $null
$global:RANKING_ROW_MO_ID = $null

# Màu chữ phần "(...)" của trạng thái lò (khớp mockup: Baking xanh / Rising vàng / Cooling xanh lá)
function LAY_MAU_TRANG_THAI_LO([string]$key) {
    switch ($key) {
        'BAKING' { return '#3B82F6' }
        'RISING' { return '#F59E0B' }
        'COOLING'{ return '#22C55E' }
        default  { return '#64748B' }
    }
}

function DONG_POPUP_RANKING {
    try {
        if ($global:RANKING_POP_MO) { $global:RANKING_POP_MO.Visibility = 'Collapsed' }
        # ClearValue trả Border về màu của Style -- trigger hover hoạt động lại bình thường
        if ($global:RANKING_ROW_MO) { $global:RANKING_ROW_MO.ClearValue([System.Windows.Controls.Border]::BackgroundProperty) }
    } catch {
        GHI_LOG "Lỗi DONG_POPUP_RANKING: $($_.Exception.Message)" 'ERROR'
    } finally {
        $global:RANKING_POP_MO = $null; $global:RANKING_ROW_MO = $null; $global:RANKING_ROW_MO_ID = $null
    }
}

# Bấm 1 hàng lò: đang mở popup này thì đóng, chưa thì đóng popup cũ và mở popup này
function HUONG_RANKING_MO_POPUP($popEl, $rowEl, [string]$ovenId) {
    try {
        $dangMo = ($null -ne $global:RANKING_POP_MO -and [object]::ReferenceEquals($global:RANKING_POP_MO, $popEl))
        DONG_POPUP_RANKING
        if (-not $dangMo) {
            $popEl.Visibility = 'Visible'
            $rowEl.Background = TAO_MAU '#EFF6FF'   # highlight hàng đang mở (đè trigger hover, như mockup .active)
            $global:RANKING_POP_MO = $popEl; $global:RANKING_ROW_MO = $rowEl; $global:RANKING_ROW_MO_ID = $ovenId
        }
    } catch {
        GHI_LOG "Lỗi HUONG_RANKING_MO_POPUP: $($_.Exception.Message)" 'ERROR'
    }
}

# ── Tạo 1 hàng lò (Border) cho bảng lò -- khớp mockup: OVEN ID | Status | HOÀN THÀNH ──
function TAO_HANG_LO_RANKING($ov, [bool]$laHangCuoi) {
    $row = New-Object Windows.Controls.Border
    $styleLo = $global:W.TryFindResource('RowLo')
    if ($styleLo) { $row.Style = $styleLo }
    $row.Padding = [Windows.Thickness]::new(10,8,10,8)
    if ($laHangCuoi) { $row.BorderThickness = [Windows.Thickness]::new(0) }   # hàng cuối bỏ viền dưới (như mockup)

    $g = New-Object Windows.Controls.Grid
    $cw1 = New-Object Windows.Controls.ColumnDefinition; $cw1.Width = [Windows.GridLength]::new(3.2,[Windows.GridUnitType]::Star)
    $cw2 = New-Object Windows.Controls.ColumnDefinition; $cw2.Width = [Windows.GridLength]::new(4,[Windows.GridUnitType]::Star)
    $cw3 = New-Object Windows.Controls.ColumnDefinition; $cw3.Width = [Windows.GridLength]::new(2.4,[Windows.GridUnitType]::Star)
    $g.ColumnDefinitions.Add($cw1); $g.ColumnDefinitions.Add($cw2); $g.ColumnDefinitions.Add($cw3)

    $tbId = New-Object Windows.Controls.TextBlock
    $tbId.Text = [string]$ov.id; $tbId.FontSize = 11; $tbId.FontWeight = 'Bold'
    $tbId.Foreground = TAO_MAU '#1E293B'; $tbId.VerticalAlignment = 'Center'; $tbId.TextTrimming = 'CharacterEllipsis'
    [Windows.Controls.Grid]::SetColumn($tbId, 0)
    $g.Children.Add($tbId) | Out-Null

    # Trạng thái: "Status:" xám + phần chính + phần "(...)" tô màu theo loại
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
    $t1 = New-Object Windows.Controls.TextBlock
    $t1.Text = 'Status:'; $t1.FontSize = 11; $t1.FontWeight = 'SemiBold'
    $t1.Foreground = TAO_MAU '#94A3B8'; $t1.Margin = [Windows.Thickness]::new(0,0,2,0)
    $t2 = New-Object Windows.Controls.TextBlock
    $t2.Text = [string]$ov.statusPrefix; $t2.FontSize = 11; $t2.Foreground = TAO_MAU '#1E293B'
    $t3 = New-Object Windows.Controls.TextBlock
    $t3.Text = [string]$ov.statusParenTxt; $t3.FontSize = 11; $t3.FontWeight = 'Bold'
    $t3.Foreground = TAO_MAU (LAY_MAU_TRANG_THAI_LO ([string]$ov.statusParenKey)); $t3.Margin = [Windows.Thickness]::new(1,0,0,0)
    $sp.Children.Add($t1) | Out-Null; $sp.Children.Add($t2) | Out-Null; $sp.Children.Add($t3) | Out-Null
    [Windows.Controls.Grid]::SetColumn($sp, 1)
    $g.Children.Add($sp) | Out-Null

    $tbF = New-Object Windows.Controls.TextBlock
    $tbF.Text = [string]$ov.f; $tbF.FontSize = 11
    $tbF.Foreground = TAO_MAU '#1E293B'; $tbF.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($tbF, 2)
    $g.Children.Add($tbF) | Out-Null

    $row.Child = $g
    return $row
}

# ── Tạo 1 hàng Top Ranking (huy chương + model + số MAG) -- khớp mockup ──
function TAO_HANG_XEP_HANG_RANKING($rk, [int]$thuTu) {
    # Cặp màu huy chương (ribbon tối + đĩa sáng): vàng / bạc / đồng
    $mauRibbon = @('#B45309','#475569','#8C5A2B')[[Math]::Min($thuTu,2)]
    $mauDia    = @('#F59E0B','#94A3B8','#CD7F32')[[Math]::Min($thuTu,2)]

    $row = New-Object Windows.Controls.Border
    $styleHang = $global:W.TryFindResource('RowHang')
    if ($styleHang) { $row.Style = $styleHang }

    $g = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = [Windows.GridLength]::Auto
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $c3 = New-Object Windows.Controls.ColumnDefinition; $c3.Width = [Windows.GridLength]::Auto
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

    # Huy chương vẽ bằng Canvas (2 dải ribbon + đĩa tròn + số thứ tự) như mockup
    $cv = New-Object Windows.Controls.Canvas
    $cv.Width = 20; $cv.Height = 26; $cv.VerticalAlignment = 'Center'
    $p1 = New-Object Windows.Shapes.Polygon
    $p1.Points = [Windows.Media.PointCollection]::new([Windows.Point[]]@([Windows.Point]::new(5,0),[Windows.Point]::new(10,0),[Windows.Point]::new(8,12),[Windows.Point]::new(3,9)))
    $p1.Fill = TAO_MAU $mauRibbon
    $cv.Children.Add($p1) | Out-Null
    $p2 = New-Object Windows.Shapes.Polygon
    $p2.Points = [Windows.Media.PointCollection]::new([Windows.Point[]]@([Windows.Point]::new(10,0),[Windows.Point]::new(15,0),[Windows.Point]::new(17,9),[Windows.Point]::new(12,12)))
    $p2.Fill = TAO_MAU $mauDia
    $cv.Children.Add($p2) | Out-Null
    $e1 = New-Object Windows.Shapes.Ellipse
    $e1.Width = 14; $e1.Height = 14; $e1.Fill = TAO_MAU $mauRibbon
    [Windows.Controls.Canvas]::SetLeft($e1,3); [Windows.Controls.Canvas]::SetTop($e1,12)
    $cv.Children.Add($e1) | Out-Null
    $e2 = New-Object Windows.Shapes.Ellipse
    $e2.Width = 14; $e2.Height = 14; $e2.Fill = TAO_MAU $mauDia
    [Windows.Controls.Canvas]::SetLeft($e2,3); [Windows.Controls.Canvas]::SetTop($e2,11)
    $cv.Children.Add($e2) | Out-Null
    $tbN = New-Object Windows.Controls.TextBlock
    $tbN.Width = 14; $tbN.Text = [string]($thuTu + 1); $tbN.FontSize = 9
    $tbN.FontWeight = 'Black'; $tbN.Foreground = [Windows.Media.Brushes]::White
    $tbN.TextAlignment = 'Center'
    [Windows.Controls.Canvas]::SetLeft($tbN,3); [Windows.Controls.Canvas]::SetTop($tbN,14.5)
    $cv.Children.Add($tbN) | Out-Null
    [Windows.Controls.Grid]::SetColumn($cv, 0)
    $g.Children.Add($cv) | Out-Null

    $tbM = New-Object Windows.Controls.TextBlock
    $tbM.Text = [string]$rk.m; $tbM.FontFamily = New-Object Windows.Media.FontFamily 'Courier New'
    $tbM.FontSize = 10; $tbM.FontWeight = 'Bold'; $tbM.Foreground = TAO_MAU '#1E293B'
    $tbM.Margin = [Windows.Thickness]::new(8,0,0,0); $tbM.VerticalAlignment = 'Center'
    $tbM.TextTrimming = 'CharacterEllipsis'
    [Windows.Controls.Grid]::SetColumn($tbM, 1)
    $g.Children.Add($tbM) | Out-Null

    # Số MAG: card.rank.v là chuỗi DINH_DANG_MAG ("3,2 MAG") -- bỏ đuôi " MAG", thêm nhãn MGZ
    $spV = New-Object Windows.Controls.StackPanel
    $spV.Orientation = 'Horizontal'
    $tbV = New-Object Windows.Controls.TextBlock
    $tbV.Text = ([string]$rk.v -replace '\s*MAG\s*$',''); $tbV.FontSize = 12; $tbV.FontWeight = 'ExtraBold'
    $tbV.Foreground = TAO_MAU '#005696'; $tbV.VerticalAlignment = 'Center'
    $tbU = New-Object Windows.Controls.TextBlock
    $tbU.Text = ' MGZ'; $tbU.FontSize = 8; $tbU.Foreground = TAO_MAU '#94A3B8'
    $tbU.VerticalAlignment = 'Bottom'; $tbU.Margin = [Windows.Thickness]::new(0,0,0,1)
    $spV.Children.Add($tbV) | Out-Null; $spV.Children.Add($tbU) | Out-Null
    [Windows.Controls.Grid]::SetColumn($spV, 2)
    $g.Children.Add($spV) | Out-Null

    $row.Child = $g
    return $row
}

# ── Tạo popup chi tiết 1 lò (Border phủ đè vùng Top Ranking, ZIndex 20) -- khớp mockup ──
# $det: dữ liệu chi tiết của oven (card.det[ovenId] -- tổng MAG/SIP + danh sách model/config)
function TAO_POPUP_LO_RANKING([string]$ovenId, $det) {
    $pop = New-Object Windows.Controls.Border
    $pop.Background  = [Windows.Media.Brushes]::White
    $pop.BorderBrush = TAO_MAU '#E2E8F0'
    $pop.BorderThickness = [Windows.Thickness]::new(1)
    $pop.CornerRadius = [Windows.CornerRadius]::new(12)
    $pop.Visibility = 'Collapsed'
    [Windows.Controls.Panel]::SetZIndex($pop, 20)
    $sh = New-Object Windows.Media.Effects.DropShadowEffect
    $sh.Color = [Windows.Media.ColorConverter]::ConvertFromString('#0F172A')
    $sh.BlurRadius = 28; $sh.ShadowDepth = 0; $sh.Opacity = 0.16
    $pop.Effect = $sh

    $g = New-Object Windows.Controls.Grid
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = [Windows.GridLength]::Auto
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $g.RowDefinitions.Add($r1); $g.RowDefinitions.Add($r2)

    # ── Header: "Oven: ID" + pill MAG + pill SIP + nút × ──
    $hd = New-Object Windows.Controls.StackPanel
    $hd.Orientation = 'Horizontal'; $hd.Margin = [Windows.Thickness]::new(10,7,10,7)
    $tbT = New-Object Windows.Controls.TextBlock
    $tbT.Text = "Oven: $ovenId"; $tbT.FontSize = 11; $tbT.FontWeight = 'Bold'
    $tbT.Foreground = TAO_MAU '#0F172A'; $tbT.VerticalAlignment = 'Center'; $tbT.TextTrimming = 'CharacterEllipsis'
    $hd.Children.Add($tbT) | Out-Null
    $pillMag = New-Object Windows.Controls.Border
    $pillMag.Background = TAO_MAU '#F1F5F9'; $pillMag.CornerRadius = [Windows.CornerRadius]::new(5)
    $pillMag.Padding = [Windows.Thickness]::new(7,2,7,2); $pillMag.Margin = [Windows.Thickness]::new(6,0,0,0)
    $pillMag.VerticalAlignment = 'Center'
    $tbMag = New-Object Windows.Controls.TextBlock
    $tbMag.Text = if ($det) { [string]$det.totalMag } else { '0,0 MAG' }
    $tbMag.FontSize = 10; $tbMag.FontWeight = 'Bold'; $tbMag.Foreground = TAO_MAU '#64748B'
    $pillMag.Child = $tbMag
    $hd.Children.Add($pillMag) | Out-Null
    $pillSip = New-Object Windows.Controls.Border
    $pillSip.Background = TAO_MAU '#EFF6FF'; $pillSip.BorderBrush = TAO_MAU '#BFDBFE'
    $pillSip.BorderThickness = [Windows.Thickness]::new(1); $pillSip.CornerRadius = [Windows.CornerRadius]::new(5)
    $pillSip.Padding = [Windows.Thickness]::new(7,2,7,2); $pillSip.Margin = [Windows.Thickness]::new(4,0,0,0)
    $pillSip.VerticalAlignment = 'Center'
    $tbSip = New-Object Windows.Controls.TextBlock
    $tbSip.Text = if ($det) { [string]$det.totalSip } else { '0 SIP' }
    $tbSip.FontSize = 10; $tbSip.FontWeight = 'ExtraBold'; $tbSip.Foreground = TAO_MAU '#005696'
    $pillSip.Child = $tbSip
    $hd.Children.Add($pillSip) | Out-Null
    $nutClose = New-Object Windows.Controls.Border
    $nutClose.Background = TAO_MAU '#F1F5F9'; $nutClose.CornerRadius = [Windows.CornerRadius]::new(9)
    $nutClose.Width = 18; $nutClose.Height = 18; $nutClose.Margin = [Windows.Thickness]::new(6,0,0,0)
    $nutClose.VerticalAlignment = 'Center'; $nutClose.Cursor = 'Hand'
    $tbX = New-Object Windows.Controls.TextBlock
    $tbX.Text = '×'; $tbX.FontSize = 13; $tbX.Foreground = TAO_MAU '#64748B'
    $tbX.TextAlignment = 'Center'; $tbX.Margin = [Windows.Thickness]::new(0,-3,0,0)
    $nutClose.Child = $tbX
    $nutClose.Add_MouseLeftButtonDown({ DONG_POPUP_RANKING })
    $hd.Children.Add($nutClose) | Out-Null
    [Windows.Controls.Grid]::SetRow($hd, 0)
    $g.Children.Add($hd) | Out-Null

    # ── Nội dung: mỗi model 1 khối (● model + badge MAG, các dòng config, tổng SIP model) ──
    $sc = New-Object Windows.Controls.ScrollViewer
    $sc.VerticalScrollBarVisibility = 'Auto'; $sc.Margin = [Windows.Thickness]::new(8,0,8,8)
    $nd = New-Object Windows.Controls.StackPanel
    if ($det -and $det.models.Count -gt 0) {
        foreach ($mEntry in $det.models) {
            $gM = New-Object Windows.Controls.Grid
            $gM.Margin = [Windows.Thickness]::new(0,7,0,0)
            foreach ($w in @('Auto','1*','Auto','Auto','Auto')) {
                $cc = New-Object Windows.Controls.ColumnDefinition
                if ($w -eq 'Auto') { $cc.Width = [Windows.GridLength]::Auto }
                else { $cc.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star) }
                $gM.ColumnDefinitions.Add($cc)
            }
            $tbMo = New-Object Windows.Controls.TextBlock
            $tbMo.Text = "●  $($mEntry.id)"; $tbMo.FontSize = 11; $tbMo.FontWeight = 'Bold'
            $tbMo.Foreground = TAO_MAU '#0F172A'
            [Windows.Controls.Grid]::SetColumn($tbMo, 0)
            [Windows.Controls.Grid]::SetColumnSpan($tbMo, 3)
            $gM.Children.Add($tbMo) | Out-Null
            $bMagM = New-Object Windows.Controls.Border
            $bMagM.Background = TAO_MAU '#F8FAFC'; $bMagM.CornerRadius = [Windows.CornerRadius]::new(5)
            $bMagM.Padding = [Windows.Thickness]::new(7,2,7,2)
            $tbMagM = New-Object Windows.Controls.TextBlock
            $tbMagM.Text = [string]$mEntry.mag; $tbMagM.FontSize = 10; $tbMagM.FontWeight = 'Bold'
            $tbMagM.Foreground = TAO_MAU '#475569'
            $bMagM.Child = $tbMagM
            [Windows.Controls.Grid]::SetColumn($bMagM, 3)
            $gM.Children.Add($bMagM) | Out-Null
            $nd.Children.Add($gM) | Out-Null

            foreach ($cfg in $mEntry.configs) {
                $gC = New-Object Windows.Controls.Grid
                $gC.Margin = [Windows.Thickness]::new(6,3,0,0)
                foreach ($w in @('14','1*','Auto','Auto','Auto')) {
                    $cc = New-Object Windows.Controls.ColumnDefinition
                    if ($w -eq 'Auto') { $cc.Width = [Windows.GridLength]::Auto }
                    elseif ($w -eq '14') { $cc.Width = [Windows.GridLength]::new(14) }
                    else { $cc.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star) }
                    $gC.ColumnDefinitions.Add($cc)
                }
                $tbCode = New-Object Windows.Controls.TextBlock
                $tbCode.Text = [string]$cfg.code
                $tbCode.FontFamily = New-Object Windows.Media.FontFamily 'Courier New'
                $tbCode.FontSize = 10; $tbCode.Foreground = TAO_MAU '#334155'
                $tbCode.VerticalAlignment = 'Center'; $tbCode.TextTrimming = 'CharacterEllipsis'
                [Windows.Controls.Grid]::SetColumn($tbCode, 1)
                $gC.Children.Add($tbCode) | Out-Null
                $tbMagC = New-Object Windows.Controls.TextBlock
                $tbMagC.Text = [string]$cfg.mag; $tbMagC.FontSize = 10
                $tbMagC.Foreground = TAO_MAU '#64748B'; $tbMagC.Margin = [Windows.Thickness]::new(0,0,10,0)
                $tbMagC.VerticalAlignment = 'Center'
                [Windows.Controls.Grid]::SetColumn($tbMagC, 2)
                $gC.Children.Add($tbMagC) | Out-Null
                $tbSipC = New-Object Windows.Controls.TextBlock
                $tbSipC.Text = [string]$cfg.sip; $tbSipC.FontSize = 10; $tbSipC.FontWeight = 'SemiBold'
                $tbSipC.Foreground = TAO_MAU '#0071E3'; $tbSipC.Margin = [Windows.Thickness]::new(0,0,10,0)
                $tbSipC.VerticalAlignment = 'Center'
                [Windows.Controls.Grid]::SetColumn($tbSipC, 3)
                $gC.Children.Add($tbSipC) | Out-Null
                $nd.Children.Add($gC) | Out-Null
            }

            # Tổng SIP của model -- box xanh nổi bật, canh phải (giống mockup + popup UI.xaml)
            $gS = New-Object Windows.Controls.Grid
            $gS.Margin = [Windows.Thickness]::new(0,4,0,0)
            $bSipM = New-Object Windows.Controls.Border
            $bSipM.Background = TAO_MAU '#EFF6FF'; $bSipM.CornerRadius = [Windows.CornerRadius]::new(5)
            $bSipM.Padding = [Windows.Thickness]::new(8,2,8,2)
            $bSipM.HorizontalAlignment = 'Right'
            $tbSipM = New-Object Windows.Controls.TextBlock
            $tbSipM.Text = [string]$mEntry.sip; $tbSipM.FontSize = 11; $tbSipM.FontWeight = 'ExtraBold'
            $tbSipM.Foreground = TAO_MAU '#005696'
            $bSipM.Child = $tbSipM
            $gS.Children.Add($bSipM) | Out-Null
            $nd.Children.Add($gS) | Out-Null
        }
    } else {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = 'Không có dữ liệu trong lò này'; $empty.FontSize = 11
        $empty.Foreground = TAO_MAU '#CBD5E1'
        $empty.Margin = [Windows.Thickness]::new(12,10,12,10)
        $nd.Children.Add($empty) | Out-Null
    }
    $sc.Content = $nd
    [Windows.Controls.Grid]::SetRow($sc, 1)
    $g.Children.Add($sc) | Out-Null

    $pop.Child = $g
    return $pop
}

# ── Vẽ TOÀN BỘ nội dung 2 card từ $global:OVEN_DATA (bảng lò + top ranking + popup) ──
# Gọi từ: MO_MAN_HINH_RANKING (vào màn hình) và BG_POLL_TIMER_LO tick (dữ liệu mới về
# khi đang ở Ranking -- Active.db vừa được ghi). Popup đang mở được GIỮ lại theo ovenId.
function CAP_NHAT_GIAO_DIEN_RANKING {
    try {
        if (-not $global:e -or -not $global:e['Card1_Ten']) { return }   # cửa sổ Ranking chưa sống

        # Ghi nhớ popup đang mở theo ovenId để khôi phục sau khi vẽ lại bằng dữ liệu tươi
        $idDangMo = $global:RANKING_ROW_MO_ID
        $global:RANKING_POP_MAP = @{}
        $global:RANKING_ROW_MAP = @{}

        for ($i = 0; $i -lt 2; $i++) {
            $tienTo = "Card$($i + 1)"
            $card = if ($i -lt $global:OVEN_DATA.Count) { $global:OVEN_DATA[$i] } else { $null }

            $tbTen = $global:e["${tienTo}_Ten"]
            $tbSl  = $global:e["${tienTo}_SoLuong"]
            $tbSip = $global:e["${tienTo}_TongSip"]
            $rows  = $global:e["${tienTo}_Rows"]
            $rank  = $global:e["${tienTo}_Rank"]
            $vungPopup = $global:e["${tienTo}_KhuVucDuoi"]
            if (-not $tbTen -or -not $rows -or -not $rank -or -not $vungPopup) { continue }

            # Header card: tên loại lò + "N lò" + tổng SIP (đã cộng dồn trong Runspace_LO)
            $tbTen.Text = if ($card) { [string]$card.brand } else { '---' }
            $tbSl.Text  = "$(if($card){$card.soLuongOven}else{0}) lò"
            $tbSip.Text = "$(DINH_DANG_SO $(if($card){$card.tongSip}else{0})) SIP"

            # Dọn popup của lần vẽ TRƯỚC (child 0 là khung TOP RANKING tĩnh -- giữ lại)
            for ($ci = $vungPopup.Children.Count - 1; $ci -ge 1; $ci--) { $vungPopup.Children.RemoveAt($ci) }

            # ── Bảng lò: sắp xếp theo Finish gần nhất → xa nhất (giống UI.xaml) ──
            $rows.Children.Clear()
            $soHang = 0
            if ($card -and $card.ovens -and $card.ovens.Count -gt 0) {
                $ovensSapXep = @($card.ovens | Sort-Object {
                    if ($_.fRaw -ne [datetime]::MinValue) { $_.fRaw } else { [datetime]::MaxValue }
                })
                $tong = $ovensSapXep.Count
                foreach ($ov in $ovensSapXep) {
                    $soHang++
                    $rowEl = TAO_HANG_LO_RANKING $ov ($soHang -ge $tong)
                    $ovenId = [string]$ov.id
                    $det = if ($card.det -and $card.det.ContainsKey($ovenId)) { $card.det[$ovenId] } else { $null }
                    $popEl = TAO_POPUP_LO_RANKING $ovenId $det
                    $vungPopup.Children.Add($popEl) | Out-Null
                    $global:RANKING_ROW_MAP[$ovenId] = $rowEl
                    $global:RANKING_POP_MAP[$ovenId] = $popEl
                    # GetNewClosure(): chụp $popEl/$rowEl/$ovenId TẠI THỜI ĐIỂM tạo handler
                    $rowEl.Add_MouseLeftButtonDown({
                        param($s,$ev)
                        HUONG_RANKING_MO_POPUP $popEl $rowEl $ovenId
                    }.GetNewClosure())
                    $rows.Children.Add($rowEl) | Out-Null
                }
            }
            if ($soHang -eq 0) {
                $empty = New-Object Windows.Controls.TextBlock
                $empty.Text = 'Không có dữ liệu lò'; $empty.FontSize = 11
                $empty.Foreground = TAO_MAU '#94A3B8'
                $empty.Margin = [Windows.Thickness]::new(12,10,12,10)
                $rows.Children.Add($empty) | Out-Null
            }

            # ── Top Ranking: tối đa 3 model (card.rank đã sắp xếp trong Runspace_LO) ──
            $rank.Children.Clear()
            $thuTu = 0
            if ($card -and $card.rank) {
                foreach ($rk in $card.rank) {
                    if ($thuTu -ge 3) { break }
                    $rank.Children.Add((TAO_HANG_XEP_HANG_RANKING $rk $thuTu)) | Out-Null
                    $thuTu++
                }
            }
            if ($thuTu -eq 0) {
                $emptyR = New-Object Windows.Controls.TextBlock
                $emptyR.Text = 'Chưa có dữ liệu'; $emptyR.FontSize = 10
                $emptyR.Foreground = TAO_MAU '#94A3B8'
                $emptyR.Margin = [Windows.Thickness]::new(8,4,0,4)
                $rank.Children.Add($emptyR) | Out-Null
            }
        }

        # Khôi phục popup đang mở (nếu oven đó vẫn còn trong dữ liệu mới)
        if ($idDangMo -and $global:RANKING_POP_MAP.ContainsKey($idDangMo)) {
            $popEl2 = $global:RANKING_POP_MAP[$idDangMo]
            $rowEl2 = $global:RANKING_ROW_MAP[$idDangMo]
            if ($popEl2 -and $rowEl2) {
                $popEl2.Visibility = 'Visible'
                $rowEl2.Background = TAO_MAU '#EFF6FF'
                $global:RANKING_POP_MO = $popEl2; $global:RANKING_ROW_MO = $rowEl2; $global:RANKING_ROW_MO_ID = $idDangMo
                return
            }
        }
        $global:RANKING_POP_MO = $null; $global:RANKING_ROW_MO = $null; $global:RANKING_ROW_MO_ID = $null

    } catch {
        GHI_LOG "Lỗi CAP_NHAT_GIAO_DIEN_RANKING: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
}
function MO_MAN_HINH_RANKING {
    NAP_CUA_SO 'OvenRanking.xaml'
    $global:UI_HOAT_DONG = $false
    _GHI_MOC_THOI_GIAN "Nạp OvenRanking.xaml xong"

    # Kéo cửa sổ (khi không phóng to) -- giữ cùng nguyên tắc với UI.xaml
    $global:W.Add_MouseLeftButtonDown({
        param($s,$ev)
        if($global:W.WindowState -ne 'Maximized' -and $ev.Source -is [System.Windows.Window]){
            try{ $global:W.DragMove() }catch{}
        }
    })

    # 3 chấm: XANH -> MiniMap | VÀNG -> về UI.xaml | ĐỎ -> thoát ứng dụng
    GAN_CHAM_MAC { DONG_VE 'MINIMAP' } { DONG_VE 'UI' } { DONG_VE 'EXIT' }

    # Vẽ toàn bộ nội dung 2 card từ dữ liệu thật $global:OVEN_DATA (bảng lò + top
    # ranking + popup chi tiết -- handler bấm từng hàng đã gắn ngay khi dựng)
    CAP_NHAT_GIAO_DIEN_RANKING

    # Bấm NGOÀI popup đang mở -> đóng (Preview tunnel: chạy TRƯỚC handler mở popup của
    # hàng, tránh trường hợp vừa mở popup bằng click này lại bị đóng ngay sau đó)
    $global:W.Add_PreviewMouseDown({
        param($s,$ev)
        try {
            $pop = $global:RANKING_POP_MO
            if ($pop -and $pop.Visibility -eq 'Visible') {
                $pt = $ev.GetPosition($pop)
                $rc = [System.Windows.Rect]::new(0,0,$pop.ActualWidth,$pop.ActualHeight)
                if (-not $rc.Contains($pt)) { DONG_POPUP_RANKING }
            }
        } catch {
            GHI_LOG "Lỗi đóng popup Ranking khi bấm ngoài: $($_.Exception.Message)" 'ERROR'
        }
    })

    # Đẩy dữ liệu tươi ngay khi vào Ranking (kết quả áp vào giao diện qua BG_POLL_TIMER_LO)
    BAT_DAU_LAM_MOI_LO_NEN
}

# ════════════════════════════════════════════════════════════════
# MÀN HÌNH MiniMap.xaml — popup 500x370 neo góc phải-dưới, luôn nổi trên
# (DỮ LIỆU THẬT v2,4 -- đọc 2 nguồn)
# ════════════════════════════════════════════════════════════════
# Nguồn 1: $global:OVEN_DATA  -- Runspace_LO đọc Active.db   -> oven ĐANG theo dõi
#          của từng line (OVEN ID/FINISH/MAG/TOTAL + đếm ngược + danh sách model)
# Nguồn 2: $global:LO_LICH_SU -- Runspace_LO đọc yyyymmdd.db (mốc thời gian của ca
#          làm việc hiện tại) -> BATCH có finish GẦN NHẤT (≤ hiện tại) của từng line
#          (MM_Done* -- V2.6: cấp BATCH, không cộng dồn nguyên lò)
# Rem = tổng giây đếm ngược -- tính lại từ mốc finish thật MỖI KHI dữ liệu Active.db
# thay đổi (CAP_NHAT_DU_LIEU_MINIMAP), giữa 2 lần cập nhật timer 1 giây tự giảm cục bộ.
$global:MM_DATA      = @{}   # brand -> @{ OvenId; Finish; Mag; TotalSip; Rem; Models; KhongCoLo; DoneId; DoneTime; DoneAgo; DoneTotal }
$global:MM_LINES     = @()   # 2 line theo SETTINGS.items (thứ tự card 1, card 2)
$global:MINIMAP_LINE = $null # line đang hiển thị

# ── Dựng $global:MM_DATA từ dữ liệu thật (gọi khi vào MiniMap + mỗi lần Runspace_LO
# trả dữ liệu mới khi đang ở MiniMap). KHÔNG đụng element WPF -- chỉ chuẩn bị dữ liệu.
function CAP_NHAT_DU_LIEU_MINIMAP {
    try {
        $now = Get-Date

        # 2 line theo thứ tự card (SETTINGS.items); card trống -> bỏ qua line đó
        $global:MM_LINES = @()
        for ($i = 0; $i -lt 2; $i++) {
            $b = ''
            if ($i -lt $global:OVEN_DATA.Count -and $global:OVEN_DATA[$i].brand) { $b = [string]$global:OVEN_DATA[$i].brand }
            $global:MM_LINES += $b
        }

        for ($i = 0; $i -lt 2; $i++) {
            $brand = $global:MM_LINES[$i]
            if (-not $brand) { continue }
            $card = if ($i -lt $global:OVEN_DATA.Count) { $global:OVEN_DATA[$i] } else { $null }
            $mm = if ($global:MM_DATA.ContainsKey($brand)) { $global:MM_DATA[$brand] } else { @{} }

            # ── Nguồn 1 (Active.db): oven đang theo dõi = lò có finish SỚM NHẤT
            #    (lò sắp ra kế tiếp -- đếm ngược tới mốc đó)
            $loHT = CHON_LO_HIEN_TAI_CHO_MINIMAP $card
            if ($loHT) {
                $mm.OvenId = [string]$loHT.id
                $mm.Finish = [string]$loHT.f
                $remMoi = 0
                if ($loHT.fRaw -ne [datetime]::MinValue) {
                    $remMoi = [int][Math]::Floor(($loHT.fRaw - $now).TotalSeconds)
                    if ($remMoi -lt 0) { $remMoi = 0 }
                }
                $mm.Rem = $remMoi
                $det = if ($card.det -and $card.det.ContainsKey([string]$loHT.id)) { $card.det[[string]$loHT.id] } else { $null }
                $mm.Mag      = if ($det) { [string]$det.magCount } else { '0' }
                $mm.TotalSip = if ($det) { "$(DINH_DANG_SO $det.totalSipRaw) SIP" } else { '0 SIP' }
                # Danh sách model của oven (id + tổng SIP thô) cho cột MODEL ID | SIP
                $dsModel = @()
                if ($det) {
                    foreach ($mo in $det.models) { $dsModel += @{ id = [string]$mo.id; sipRaw = $mo.sipRaw } }
                }
                $mm.Models = $dsModel
                $mm.KhongCoLo = $false
            } else {
                $mm.OvenId = '--'; $mm.Finish = '--'; $mm.Mag = '0'; $mm.TotalSip = '0 SIP'
                $mm.Rem = 0; $mm.Models = @(); $mm.KhongCoLo = $true
            }

            # ── Nguồn 2 (yyyymmdd.db): V2.6 -- BATCH có finish GẦN NHẤT (≤ hiện tại)
            #    của line này. DoneTime/DoneAgo/DoneTotal lấy TRỰC TIẾP từ batch đó
            #    (không cộng dồn các batch cũ hơn trong cùng lò); DoneId hiển thị lò
            #    chứa batch + số lô (cycle) để phân biệt các lô trong cùng 1 lò.
            $ls = $null
            if ($global:LO_LICH_SU -is [hashtable] -and $global:LO_LICH_SU.ContainsKey($brand)) { $ls = $global:LO_LICH_SU[$brand] }
            if ($ls) {
                $tenHienThi = [string]$ls.id
                if ([string]::IsNullOrWhiteSpace($tenHienThi)) { $tenHienThi = [string]$ls.batchId }
                $chuKy = [string]$ls.cycle
                if ([string]::IsNullOrWhiteSpace($chuKy)) {
                    $mm.DoneId = $tenHienThi
                } else {
                    $mm.DoneId = "$tenHienThi • Lô $chuKy"
                }
                $mm.DoneTime  = [string]$ls.finish
                $mm.DoneTotal = "$(DINH_DANG_SO $ls.totalSipRaw) SIP"
                $phut = 0
                if ($ls.fRaw -ne [datetime]::MinValue) { $phut = [int][Math]::Round(($now - $ls.fRaw).TotalMinutes) }
                if ($phut -le 0) {
                    $mm.DoneAgo = 'Vừa xong'
                } elseif ($phut -lt 60) {
                    $mm.DoneAgo = "$phut phút trước"
                } else {
                    $mm.DoneAgo = "$([int][Math]::Floor($phut/60)) giờ $($phut % 60) phút trước"
                }
            } else {
                $mm.DoneId = '--'; $mm.DoneTime = '--'; $mm.DoneAgo = 'Chưa có dữ liệu ca này'; $mm.DoneTotal = '0 SIP'
            }

            $global:MM_DATA[$brand] = $mm
        }

        # Line mặc định: giữ line đang chọn nếu còn hợp lệ, không thì line đầu tiên
        if (-not $global:MINIMAP_LINE -or $global:MM_LINES -notcontains $global:MINIMAP_LINE) {
            $global:MINIMAP_LINE = ($global:MM_LINES | Where-Object { $_ } | Select-Object -First 1)
        }

    } catch {
        GHI_LOG "Lỗi CAP_NHAT_DU_LIEU_MINIMAP: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
}

# ── Tạo 1 hàng model (MODEL ID | SIP) cho danh sách bên phải MiniMap ──
function TAO_HANG_MODEL_MINIMAP($m) {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = [Windows.Thickness]::new(16,10,16,10)
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = [Windows.GridLength]::Auto
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $tb1 = New-Object Windows.Controls.TextBlock
    $tb1.Text = [string]$m.id; $tb1.FontSize = 12; $tb1.FontWeight = 'SemiBold'
    $tb1.Foreground = TAO_MAU '#1F2937'; $tb1.VerticalAlignment = 'Center'; $tb1.TextTrimming = 'CharacterEllipsis'
    [Windows.Controls.Grid]::SetColumn($tb1, 0)
    $g.Children.Add($tb1) | Out-Null
    $tb2 = New-Object Windows.Controls.TextBlock
    $tb2.Text = DINH_DANG_SO $m.sipRaw; $tb2.FontSize = 12; $tb2.FontWeight = 'Bold'
    $tb2.Foreground = TAO_MAU '#2563EB'; $tb2.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($tb2, 1)
    $g.Children.Add($tb2) | Out-Null
    return $g
}

function DOI_MAUSAC_DEM_NGUOC([string]$maTime,[string]$maHour,[string]$maBox1,[string]$maBox2){
    $global:e.MM_RemTime.Foreground = TAO_MAU $maTime
    $global:e.MM_RemHour.Foreground = TAO_MAU $maHour
    $global:e.GS_Rem_1.Color = [Windows.Media.ColorConverter]::ConvertFromString($maBox1)
    $global:e.GS_Rem_2.Color = [Windows.Media.ColorConverter]::ConvertFromString($maBox2)
}
function CAP_NHAT_DEM_NGUOC_MINIMAP([string]$line){
    try {
        if (-not $global:MM_DATA.ContainsKey($line)) { return }
        if (-not $global:e.MM_RemTime) { return }   # cửa sổ MiniMap chưa/chỉ vừa chết -- bỏ qua tick
        $d = $global:MM_DATA[$line]
        # Không có lò nào đang nướng trên line này -> hiển thị trống an toàn
        if ($d.KhongCoLo) {
            $global:e.MM_RemTime.Text = '--'
            $global:e.MM_RemHour.Text = 'Không có lò'
            DOI_MAUSAC_DEM_NGUOC '#2563EB' '#6B7280' '#FCFDFF' '#F5F9FF'
            $global:e.MM_Badge.Visibility = 'Collapsed'
            $global:e.MM_Badge_Text.ClearValue([System.Windows.Controls.TextBlock]::OpacityProperty)
            return
        }
        $t = [int]$d.Rem
        $h = [int][Math]::Floor($t/3600); $m = [int][Math]::Floor(($t%3600)/60); $sec = $t%60
        $global:e.MM_RemTime.Text = ('{0:d2}' -f $m) + "'" + ('{0:d2}' -f $sec) + 's'
        if ($t -le 0) {
            $global:e.MM_RemHour.Text = 'Hoàn thành'
            DOI_MAUSAC_DEM_NGUOC '#16A34A' '#16A34A' '#F7FEFA' '#EEFAF2'
            $global:e.MM_Badge.Visibility = 'Visible'
            $global:e.MM_Badge.Background = TAO_MAU '#16A34A'
            $global:e.MM_Badge_Text.Text  = 'ĐÃ HOÀN THÀNH'
            $global:e.MM_Badge_Text.ClearValue([System.Windows.Controls.TextBlock]::OpacityProperty)
        } elseif ($t -le 300) {
            $global:e.MM_RemHour.Text = 'Sắp hoàn thành'
            DOI_MAUSAC_DEM_NGUOC '#DC2626' '#DC2626' '#FFF9F8' '#FFF0EF'
            $global:e.MM_Badge.Visibility = 'Visible'
            $global:e.MM_Badge.Background = TAO_MAU '#DC2626'
            $global:e.MM_Badge_Text.Text  = 'SẮP XONG'
            # Nhấp nháy badge như mockup @keyframes badgeBlink 1.1s (1<->0.55, lặp vô hạn)
            $nhayAnim = New-Object System.Windows.Media.Animation.DoubleAnimation
            $nhayAnim.From = 1.0; $nhayAnim.To = 0.55
            $nhayAnim.Duration = [System.Windows.Duration]::FromTimeSpan([TimeSpan]::FromMilliseconds(550))
            $nhayAnim.AutoReverse = $true
            $nhayAnim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $global:e.MM_Badge_Text.BeginAnimation([System.Windows.Controls.TextBlock]::OpacityProperty, $nhayAnim)
        } else {
            if ($h -gt 0) { $global:e.MM_RemHour.Text = "$h Giờ" } else { $global:e.MM_RemHour.Text = 'Sắp hoàn thành' }
            if ($t -le 900) {
                DOI_MAUSAC_DEM_NGUOC '#D97706' '#B45309' '#FFFDF8' '#FFF8EC'
            } else {
                DOI_MAUSAC_DEM_NGUOC '#2563EB' '#6B7280' '#FCFDFF' '#F5F9FF'
            }
            $global:e.MM_Badge.Visibility = 'Collapsed'
            $global:e.MM_Badge_Text.ClearValue([System.Windows.Controls.TextBlock]::OpacityProperty)
        }
    } catch {
        GHI_LOG "Lỗi CAP_NHAT_DEM_NGUOC_MINIMAP: $($_.Exception.Message)" 'ERROR'
    }
}
function VE_LINE_MINIMAP([string]$line){
    try {
        if (-not $global:MM_DATA.ContainsKey($line)) { return }
        if (-not $global:e.MM_OvenId) { return }    # cửa sổ MiniMap chưa/chỉ vừa chết -- bỏ qua
        $d = $global:MM_DATA[$line]
        # ── Nguồn Active.db: oven đang theo dõi ──
        $global:e.MM_OvenId.Text = [string]$d.OvenId
        $global:e.MM_Finish.Text = [string]$d.Finish
        $global:e.MM_Mag.Text    = [string]$d.Mag
        $global:e.MM_Total.Text  = [string]$d.TotalSip
        # ── Nguồn yyyymmdd.db: oven hoàn thành gần nhất của line ──
        $global:e.MM_DoneId.Text    = [string]$d.DoneId
        $global:e.MM_DoneTime.Text  = [string]$d.DoneTime
        $global:e.MM_DoneAgo.Text   = [string]$d.DoneAgo
        $global:e.MM_DoneTotal.Text = [string]$d.DoneTotal

        # Danh sách model của line -- dựng động vào SP_Models (nguồn Active.db)
        $sp = $global:e.SP_Models
        $sp.Children.Clear()
        if ($d.Models -and $d.Models.Count -gt 0) {
            foreach ($m in $d.Models) { $sp.Children.Add((TAO_HANG_MODEL_MINIMAP $m)) | Out-Null }
        } else {
            $empty = New-Object Windows.Controls.TextBlock
            $empty.Text = 'Không có model trong lò'; $empty.FontSize = 12
            $empty.Foreground = TAO_MAU '#9CA3AF'
            $empty.Margin = [Windows.Thickness]::new(16,10,16,10)
            $sp.Children.Add($empty) | Out-Null
        }

        # Tên 2 line lấy theo SETTINGS.items + tô sáng line đang chọn (như mockup)
        $l0 = if ($global:MM_LINES.Count -gt 0) { [string]$global:MM_LINES[0] } else { '' }
        $l1 = if ($global:MM_LINES.Count -gt 1) { [string]$global:MM_LINES[1] } else { '' }
        $global:e.Line_Btn_C105.Text  = if ($l0) { $l0 } else { '---' }
        $global:e.Line_Btn_Hades.Text = if ($l1) { $l1 } else { '---' }
        if ($line -eq $l0) {
            $global:e.Line_Btn_C105.Foreground = TAO_MAU '#FFFFFF'; $global:e.Line_Btn_Hades.Foreground = TAO_MAU '#6B7280'
        } else {
            $global:e.Line_Btn_C105.Foreground = TAO_MAU '#6B7280'; $global:e.Line_Btn_Hades.Foreground = TAO_MAU '#FFFFFF'
        }
        CAP_NHAT_DEM_NGUOC_MINIMAP $line
    } catch {
        GHI_LOG "Lỗi VE_LINE_MINIMAP: $($_.Exception.Message)" 'ERROR'
    }
}
function DOI_LINE_MINIMAP {
    try {
        if ($global:MM_LINES.Count -lt 2) { return }
        $lineMoi = if ($global:MINIMAP_LINE -eq $global:MM_LINES[0]) { $global:MM_LINES[1] } else { $global:MM_LINES[0] }
        $global:MINIMAP_LINE = $lineMoi
        # Thumb trượt sang nửa phải khi chuyển sang line 2 (translate 0 -> 76px, 0.22s)
        $xMoi = if ($lineMoi -eq $global:MM_LINES[1]) { 76.0 } else { 0.0 }
        $tr = New-Object System.Windows.Media.Animation.DoubleAnimation
        $tr.To = $xMoi
        $tr.Duration = [System.Windows.Duration]::FromTimeSpan([TimeSpan]::FromMilliseconds(220))
        $global:e.Line_Thumb_X.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $tr)
        VE_LINE_MINIMAP $global:MINIMAP_LINE
    } catch {
        GHI_LOG "Lỗi DOI_LINE_MINIMAP: $($_.Exception.Message)" 'ERROR'
    }
}
function MO_MAN_HINH_MINIMAP {
    NAP_CUA_SO 'MiniMap.xaml'
    $global:UI_HOAT_DONG = $false
    _GHI_MOC_THOI_GIAN "Nạp MiniMap.xaml xong"

    # Neo góc phải-dưới vùng làm việc (popup 500x370 + viền shadow 12 mỗi bên; lề 20 như mockup)
    $wa = [System.Windows.SystemParameters]::WorkArea
    $global:W.WindowStartupLocation = 'Manual'
    $global:W.Left = $wa.Right  - $global:W.Width  - 8
    $global:W.Top  = $wa.Bottom - $global:W.Height - 8

    # 3 chấm: XANH -> OvenRanking | VÀNG -> ẩn xuống taskbar (minimize) | ĐỎ -> thoát ứng dụng
    GAN_CHAM_MAC { DONG_VE 'RANKING' } { $global:W.WindowState = 'Minimized' } { DONG_VE 'EXIT' }

    # Line toggle: 1 vùng bấm duy nhất -- bấm bất kỳ đâu trong pill đều chuyển line (như mockup)
    $global:e.Line_Toggle.Add_MouseLeftButtonDown({ DOI_LINE_MINIMAP })

    # Đồng hồ đếm ngược 1 giây (DispatcherTimer) -- tạo ĐÚNG 1 LẦN; Start/Stop theo vòng đời MiniMap.
    # Giảm countdown CẢ 2 line chạy ngầm (line trống bỏ qua), chỉ vẽ lại line đang hiển thị.
    if (-not $global:MINIMAP_TIMER) {
        $global:MINIMAP_TIMER = New-Object System.Windows.Threading.DispatcherTimer
        $global:MINIMAP_TIMER.Interval = [TimeSpan]::FromSeconds(1)
        $global:MINIMAP_TIMER.Add_Tick({
            try {
                foreach ($k in @($global:MM_LINES)) {
                    if ($k -and $global:MM_DATA.ContainsKey($k) -and -not $global:MM_DATA[$k].KhongCoLo) {
                        if ($global:MM_DATA[$k].Rem -gt 0) { $global:MM_DATA[$k].Rem -= 1 }
                    }
                }
                if ($global:MINIMAP_LINE) { CAP_NHAT_DEM_NGUOC_MINIMAP $global:MINIMAP_LINE }
            } catch {
                GHI_LOG "Lỗi tick đếm ngược MiniMap: $($_.Exception.Message)" 'ERROR'
            }
        })
    }

    $global:W.Add_Loaded({
        try {
            # Dựng dữ liệu thật (Active.db + yyyymmdd.db của ca) rồi vẽ line đang chọn
            CAP_NHAT_DU_LIEU_MINIMAP
            if ($global:MINIMAP_LINE) { VE_LINE_MINIMAP $global:MINIMAP_LINE }
            $global:MINIMAP_TIMER.Start()
        } catch {
            GHI_LOG "Lỗi Loaded MiniMap: $($_.Exception.Message)" 'ERROR'
        }
    })

    # Đẩy dữ liệu tươi ngay khi vào MiniMap (Runspace_LO đọc lại Active.db + yyyymmdd.db,
    # kết quả áp vào giao diện qua BG_POLL_TIMER_LO -- switch ở MAN_HINH_HIEN_TAI 'MINIMAP')
    BAT_DAU_LAM_MOI_LO_NEN
}

# ================================================================
# HẠ TẦNG CHẠY NỀN (Runspace) -- Tính toán dữ liệu trên luồng riêng,
# KHÔNG chặn UI thread. Đây là cơ chế đa luồng GỐC của PowerShell,
# không cần C#.
#
# NGUYÊN TẮC AN TOÀN LUỒNG (BẮT BUỘC tuân thủ khi sửa đổi):
#   - Runspace nền KHÔNG BAO GIỜ được đụng vào bất kỳ control WPF nào
#     (không $global:e, không $global:W). Chỉ trả về dữ liệu thuần
#     (string, số, PSCustomObject, List) qua EndInvoke().
#   - Mọi thao tác gán ItemsSource/Text... chỉ được thực hiện sau khi
#     đã EndInvoke() xong, lúc đó đang chạy lại trên UI thread (vì
#     hàm này được gọi từ trong DispatcherTimer.Tick).
# ================================================================
$global:BG_RUNSPACE = [runspacefactory]::CreateRunspace()
$global:BG_RUNSPACE.Open()
$global:BG_PS        = $null
$global:BG_HANDLE     = $null
$global:BG_DANG_CHAY  = $false

function BAT_DAU_LAM_MOI_NEN {
    if ($global:BG_DANG_CHAY) {
        # Đang có 1 lượt làm mới chạy rồi -- bỏ qua để tránh chồng lấn
        GHI_LOG "BAT_DAU_LAM_MOI_NEN: bỏ qua vì đang có tiến trình nền chạy" 'INFO'
        return
    }
    $global:BG_DANG_CHAY = $true

    $global:BG_PS = [powershell]::Create()
    $global:BG_PS.Runspace = $global:BG_RUNSPACE

    [void]$global:BG_PS.AddScript({
        param($ModuleDir, $RootDir, $LogPath, $TrangThaiDungChung)

        # Ghi log trực tiếp (không qua GHI_LOG) -- vì bước nạp module có thể
        # thất bại TRƯỚC KHI hàm GHI_LOG (trong Support.psm1) sẵn sàng dùng
        function Ghi_Log_Du_Phong([string]$noiDung) {
            try {
                $dong = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))] [ERROR-IMPORT] $noiDung"
                Add-Content -Path $LogPath -Value $dong -Encoding UTF8 -ErrorAction SilentlyContinue
            } catch { }
        }

        # Gán vào $global: CỦA CHÍNH RUNSPACE NÀY -- $TrangThaiDungChung là tham số cục bộ
        # (param), nhưng giá trị nó trỏ tới là CÙNG 1 hashtable Synchronized với UI thread
        # (truyền qua AddArgument bên dưới). Gán vào $global: ở đây để GHI_LOG (gọi từ bất
        # kỳ hàm nào bên trong Runspace này) cũng đọc được đúng cờ GhiLogBat dùng chung.
        $global:TRANG_THAI_DUNG_CHUNG = $TrangThaiDungChung

        # Runspace này CHỈ còn lo Sản lượng + QA-HOUR -- Oven đã tách riêng sang
        # Runspace_LO (BAT_DAU_LAM_MOI_LO_NEN bên dưới, kích hoạt qua FileSystemWatcher +
        # hẹn giờ debounce 5 giây, không còn phụ thuộc chu kỳ 60 giây này nữa), nên KHÔNG
        # còn cần nạp OvenBaking ở đây.
        $Danh_Sach_Module = @('Variable','Database','Support','Production','QaHour')
        foreach ($Ten_Module in $Danh_Sach_Module) {
            try {
                Import-Module (Join-Path $ModuleDir "$Ten_Module.psm1") -Force -Global -ErrorAction Stop
            } catch {
                Ghi_Log_Du_Phong "Nạp module '$Ten_Module.psm1' THẤT BẠI: $($_.Exception.Message)"
                return [PSCustomObject]@{ Models=@(); MoEmpty=$true; BangKq=$null; QaHourRows=@() }
            }
        }

        KHOI_TAO_BIEN -RootDir $RootDir
        KHOI_TAO_DB          # Nạp MO_DB + USER_DB + CFG (riêng cho runspace này)
        NAP_DANH_SACH_MODEL

        # Bảng sản lượng LUÔN tính lại mỗi chu kỳ (không phụ thuộc Active.db có đổi hay
        # không) -- vì có phần phụ thuộc thời gian (giờ đã trôi kể từ đầu ca) cần cập nhật
        # dù dữ liệu sản lượng gốc không đổi.
        $bangKq = TINH_BANG_DU_LIEU

        # Lấy dữ liệu QA-HOUR trên CÙNG runspace nền này (không chặn UI thread).
        # LAY_DU_LIEU_QA_HOUR là hàm THUẦN (không đụng WPF) nên an toàn gọi ở đây --
        # việc ÁP DỤNG thật vào $global:MO_DB (trên UI thread thật sự) được thực hiện
        # sau, trong BG_POLL_TIMER.Add_Tick bên dưới, sau khi EndInvoke() xong.
        $qaHourRows = @()
        try { $qaHourRows = LAY_DU_LIEU_QA_HOUR } catch { Ghi_Log_Du_Phong "LAY_DU_LIEU_QA_HOUR lỗi: $($_.Exception.Message)" }

        # Chỉ trả về DỮ LIỆU THUẦN -- không đụng bất kỳ WPF object nào
        return [PSCustomObject]@{
            Models        = @($global:AS.models)
            MoEmpty       = $global:AS.moEmpty
            BangKq        = $bangKq
            QaHourRows    = @($qaHourRows)
        }
    }).AddArgument($moduleDir).AddArgument($APP_ROOT).AddArgument($global:PATH_LOG).AddArgument($global:TRANG_THAI_DUNG_CHUNG)

    $global:BG_HANDLE = $global:BG_PS.BeginInvoke()

    if (-not $global:BG_POLL_TIMER) {
        $global:BG_POLL_TIMER = New-Object System.Windows.Threading.DispatcherTimer
        $global:BG_POLL_TIMER.Interval = [TimeSpan]::FromMilliseconds(150)
        $global:BG_POLL_TIMER.Add_Tick({
            if (-not $global:BG_HANDLE.IsCompleted) { return }
            $global:BG_POLL_TIMER.Stop()
            try {
                $Ket_Qua_Nen = $global:BG_PS.EndInvoke($global:BG_HANDLE)
                if ($Ket_Qua_Nen) {
                    # ── Từ đây trở đi đang chạy trên UI thread -- an toàn gán vào control ──
                    try {
                        $global:AS.models.Clear()
                        foreach ($Model_Item in $Ket_Qua_Nen.Models) { $global:AS.models.Add($Model_Item) }
                        $global:AS.moEmpty = $Ket_Qua_Nen.MoEmpty
                    } catch {
                        GHI_LOG "Lỗi áp dụng danh sách Model: $($_.Exception.Message)" 'ERROR'
                    }

                    try {
                        # LUỒNG ĐA GIAO DIỆN: element bảng sản lượng chỉ tồn tại trên UI.xaml --
                        # chỉ gán khi UI đang sống; dữ liệu thuần (AS.models, MO_DB) vẫn cập nhật.
                        if ($global:UI_HOAT_DONG) {
                            if ($Ket_Qua_Nen.MoEmpty -or -not $Ket_Qua_Nen.BangKq -or $Ket_Qua_Nen.BangKq.Rows.Count -eq 0) {
                                $global:e.Bang_San_Luong.ItemsSource = $null
                                $global:e.Label_Tong_San_Luong.Text   = 'Chưa có dữ liệu'
                            } else {
                                $global:e.Bang_San_Luong.ItemsSource = $Ket_Qua_Nen.BangKq.Rows
                                $global:e.Label_Tong_San_Luong.Text   = $Ket_Qua_Nen.BangKq.TotalText
                            }
                        }
                    } catch {
                        GHI_LOG "Lỗi gán dữ liệu bảng sản lượng: $($_.Exception.Message)" 'ERROR'
                    }

                    # Áp dụng kết quả QA-HOUR (đã lấy sẵn trên Runspace nền ở trên) vào
                    # MO_DB -- CAP_NHAT_ACTUAL_TU_QA_HOUR tự nó sẽ lo phần đối chiếu model
                    # khớp/không khớp, lưu MO.db, nạp lại danh sách và cập nhật lại bảng
                    # sản lượng NẾU có ít nhất 1 model được cập nhật (xem Production.psm1).
                    try {
                        if ($Ket_Qua_Nen.QaHourRows -and $Ket_Qua_Nen.QaHourRows.Count -gt 0) {
                            CAP_NHAT_ACTUAL_TU_QA_HOUR $Ket_Qua_Nen.QaHourRows
                        }
                    } catch {
                        GHI_LOG "Lỗi áp dụng dữ liệu QA-HOUR vào MO_DB: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
                    }
                } else {
                    GHI_LOG "EndInvoke trả về NULL -- tiến trình nền không trả dữ liệu gì" 'ERROR'
                }
            } catch {
                GHI_LOG "Lỗi tiến trình nền (Runspace) -- EndInvoke thất bại: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
            } finally {
                $global:BG_PS.Dispose()
                $global:BG_PS = $null
                $global:BG_HANDLE = $null
                $global:BG_DANG_CHAY = $false
            }
        })
    }
    $global:BG_POLL_TIMER.Start()
}

# ================================================================
# HẠ TẦNG CHẠY NỀN RIÊNG CHO OVEN (Runspace_LO) -- TÁCH KHỎI Runspace nền 60 giây ở trên
# ================================================================
# LÝ DO PHẢI TÁCH RIÊNG (không dùng chung $global:BG_RUNSPACE ở trên): 1 Runspace CHỈ
# chạy được 1 lệnh tại 1 thời điểm -- nếu Oven kích hoạt đúng lúc chu kỳ Sản lượng/
# QA-HOUR 60 giây đang chạy dở (vd QA-HOUR đang chờ phản hồi HTTP vài giây), gọi chung
# Runspace sẽ bị lỗi "Runspace đã đang được sử dụng" hoặc phải xếp hàng chờ, làm mất hết
# ý nghĩa "phản ứng trong 5 giây" mà Oven cần. Oven vì vậy có RIÊNG: Runspace, tiến trình
# PowerShell, handle, cờ bận/đang chạy, và poll timer -- độc lập hoàn toàn với bộ máy 60
# giây, chỉ khác nhau về TẦN SỐ KÍCH HOẠT (Oven: theo sự kiện FileSystemWatcher + hẹn giờ
# debounce 5 giây; Sản lượng/QA-HOUR: theo đồng hồ cố định 60 giây).
$global:BG_RUNSPACE_LO = [runspacefactory]::CreateRunspace()
$global:BG_RUNSPACE_LO.Open()
$global:BG_PS_LO        = $null
$global:BG_HANDLE_LO    = $null
$global:BG_DANG_CHAY_LO = $false

# Kích hoạt từ: (1) Window.Add_Loaded -- đọc Oven LẦN ĐẦU ngay khi mở app, và (2) Tick của
# $global:HEN_GIO_LAM_MOI_LO (đồng hồ debounce 5 giây, xem Window.Add_Loaded bên dưới) --
# mỗi khi FileSystemWatcher phát hiện Active.db đổi VÀ đã 5 giây liên tục không có đổi
# THÊM (giảm rung/debounce thật sự). KHÔNG chặn UI thread trong bất kỳ trường hợp nào.
function BAT_DAU_LAM_MOI_LO_NEN {
    if ($global:BG_DANG_CHAY_LO) {
        # Đang có 1 lượt đọc Oven chạy rồi (vd lần trước chưa kịp xong đã có sự kiện mới)
        # -- bỏ qua lần này, KHÔNG xếp hàng chờ -- sự kiện Active.db tiếp theo (nếu có) sẽ
        # tự kích hoạt lại hẹn giờ debounce và thử lại bình thường.
        GHI_LOG "BAT_DAU_LAM_MOI_LO_NEN: bỏ qua vì đang có tiến trình đọc Oven chạy rồi" 'INFO'
        return
    }
    $global:BG_DANG_CHAY_LO = $true

    $global:BG_PS_LO = [powershell]::Create()
    $global:BG_PS_LO.Runspace = $global:BG_RUNSPACE_LO

    [void]$global:BG_PS_LO.AddScript({
        param($ModuleDir, $RootDir, $LogPath, $TrangThaiDungChung)

        function Ghi_Log_Du_Phong([string]$noiDung) {
            try {
                $dong = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))] [ERROR-IMPORT] $noiDung"
                Add-Content -Path $LogPath -Value $dong -Encoding UTF8 -ErrorAction SilentlyContinue
            } catch { }
        }

        # Gán $global:TRANG_THAI_DUNG_CHUNG CỦA CHÍNH RUNSPACE_LO NÀY -- cùng 1 hashtable
        # Synchronized với UI thread và Runspace nền 60 giây kia (truyền qua AddArgument
        # bên dưới), để cờ bật/tắt ghi log (GhiLogBat) áp dụng NHẤT QUÁN trên CẢ 3 nơi,
        # không riêng UI thread và Runspace 60 giây như trước.
        $global:TRANG_THAI_DUNG_CHUNG = $TrangThaiDungChung

        $Danh_Sach_Module = @('Variable','Database','Support','OvenBaking')
        foreach ($Ten_Module in $Danh_Sach_Module) {
            try {
                Import-Module (Join-Path $ModuleDir "$Ten_Module.psm1") -Force -Global -ErrorAction Stop
            } catch {
                Ghi_Log_Du_Phong "Nạp module '$Ten_Module.psm1' THẤT BẠI (Runspace_LO): $($_.Exception.Message)"
                return [PSCustomObject]@{ ThanhCong = $false; OvenData = @(); LichSuLo = @{} }
            }
        }

        KHOI_TAO_BIEN -RootDir $RootDir
        # Chỉ cần NAP_SETTINGS_DB (lấy CFG.items -- loại card cho LAM_MOI_DU_LIEU_LO) --
        # KHÔNG cần KHOI_TAO_DB đầy đủ (MO.db/USER.db không dùng tới ở Runspace này).
        NAP_SETTINGS_DB | Out-Null

        # LAM_MOI_DU_LIEU_LO giờ TRẢ VỀ $true/$false phản ánh ĐÚNG việc đọc Active.db có
        # thành công hay không (xem OvenBaking.psm1) -- dùng giá trị này, KHÔNG suy luận
        # "có sự kiện đổi file = đọc chắc chắn thành công", vì file vẫn có thể đang bị
        # khoá đúng lúc đọc dù đã có báo đổi.
        $docThanhCong = LAM_MOI_DU_LIEU_LO

        # V2.4: đọc thêm lịch sử yyyymmdd.db (mốc thời gian của ca làm việc hiện tại -- xem
        # NAP_DB_LICH_SU_NGAY/LAY_NGAY_CA_HIEN_TAI) -- batch có finish gần nhất (≤ hiện
        # tại, V2.6) theo từng loại lò, phục vụ section "OVEN HOÀN THÀNH GẦN NHẤT" của
        # MiniMap. Hàm TỰ an toàn
        # (file thiếu/khoá/hỏng -> hashtable rỗng, không ném exception).
        $lichSuLo = @{}
        try { $lichSuLo = LAY_DU_LIEU_LICH_SU_LO } catch { Ghi_Log_Du_Phong "LAY_DU_LIEU_LICH_SU_LO lỗi: $($_.Exception.Message)" }

        # Chỉ trả về DỮ LIỆU THUẦN -- không đụng bất kỳ WPF object nào
        return [PSCustomObject]@{
            ThanhCong = [bool]$docThanhCong
            OvenData  = $global:OVEN_DATA
            LichSuLo  = $lichSuLo
        }
    }).AddArgument($moduleDir).AddArgument($APP_ROOT).AddArgument($global:PATH_LOG).AddArgument($global:TRANG_THAI_DUNG_CHUNG)

    $global:BG_HANDLE_LO = $global:BG_PS_LO.BeginInvoke()

    if (-not $global:BG_POLL_TIMER_LO) {
        $global:BG_POLL_TIMER_LO = New-Object System.Windows.Threading.DispatcherTimer
        $global:BG_POLL_TIMER_LO.Interval = [TimeSpan]::FromMilliseconds(150)
        $global:BG_POLL_TIMER_LO.Add_Tick({
            if (-not $global:BG_HANDLE_LO.IsCompleted) { return }
            $global:BG_POLL_TIMER_LO.Stop()
            try {
                $Ket_Qua_Lo = $global:BG_PS_LO.EndInvoke($global:BG_HANDLE_LO)
                if ($Ket_Qua_Lo -and $Ket_Qua_Lo.ThanhCong) {
                    # ── Từ đây trở đi đang chạy trên UI thread -- an toàn gán vào control ──
                    try {
                        $global:OVEN_DATA = $Ket_Qua_Lo.OvenData
                        # V2.4: lịch sử oven hoàn thành gần nhất theo line (yyyymmdd.db)
                        if ($Ket_Qua_Lo.LichSuLo -is [hashtable]) { $global:LO_LICH_SU = $Ket_Qua_Lo.LichSuLo }
                        # LUỒNG ĐA GIAO DIỆN v2,4: vẽ dữ liệu lò vào ĐÚNG màn hình đang sống --
                        #   UI      : card lò góc dưới (như cũ)
                        #   RANKING : toàn bộ 2 card (bảng lò + top ranking + popup)
                        #   MINIMAP : dựng lại $global:MM_DATA từ dữ liệu mới rồi vẽ line
                        # Dữ liệu $global:OVEN_DATA/$global:LO_LICH_SU luôn cập nhật đầy đủ dù
                        # đang ở màn hình nào.
                        switch ($global:MAN_HINH_HIEN_TAI) {
                            'UI'      { CAP_NHAT_GIAO_DIEN_LO }
                            'RANKING' { CAP_NHAT_GIAO_DIEN_RANKING }
                            'MINIMAP' {
                                CAP_NHAT_DU_LIEU_MINIMAP
                                if ($global:MINIMAP_LINE) { VE_LINE_MINIMAP $global:MINIMAP_LINE }
                            }
                        }
                    } catch {
                        GHI_LOG "Lỗi cập nhật giao diện lò nướng (Runspace_LO): $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
                    }
                } else {
                    # Đọc Active.db KHÔNG thành công lần này (khoá quá lâu, XML hỏng...) --
                    # GIỮ NGUYÊN card lò nướng đang hiển thị, KHÔNG xoá về "0 OVEN". Sự
                    # kiện FileSystemWatcher kế tiếp (nếu Active.db còn tiếp tục được ghi)
                    # sẽ tự kích hoạt lại hẹn giờ debounce và thử đọc lại bình thường.
                    GHI_LOG "BAT_DAU_LAM_MOI_LO_NEN: đọc Active.db không thành công lần này -- giữ nguyên dữ liệu lò cũ, chờ sự kiện FileSystemWatcher kế tiếp" 'WARN'
                }
            } catch {
                GHI_LOG "Lỗi tiến trình nền (Runspace_LO) -- EndInvoke thất bại: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
            } finally {
                $global:BG_PS_LO.Dispose()
                $global:BG_PS_LO = $null
                $global:BG_HANDLE_LO = $null
                $global:BG_DANG_CHAY_LO = $false
            }
        })
    }
    $global:BG_POLL_TIMER_LO.Start()
}

# ================================================================
# MÀN HÌNH UI.xaml — màn hình chính (giao diện/hiệu ứng giữ nguyên bản gốc,
# chỉ thay hành vi CHAM XANH thành "mở OvenRanking" theo luồng điều hướng mới)
# ================================================================
function MO_MAN_HINH_UI {
    NAP_CUA_SO 'UI.xaml'
    # BlurEffect là đối tượng đặc biệt — phải lấy qua thuộc tính Effect của mainContent
    $global:e.Hieu_Ung_Mo = (TIM_PHAN_TU 'mainContent').Effect
    $global:UI_HOAT_DONG = $true
    _GHI_MOC_THOI_GIAN "Nạp UI.xaml + FindName tất cả phần tử xong"

$global:W.Add_MouseLeftButtonDown({
    param($s,$ev)
    # Chỉ kéo cửa sổ khi không phóng to và click đúng vào Window
    if($global:W.WindowState -ne 'Maximized' -and $ev.Source -is [System.Windows.Window]){
        try{ $global:W.DragMove() }catch{}
    }
})

# Nút điều khiển cửa sổ kiểu macOS (đỏ/vàng/xanh)
# LUỒNG MỚI: XANH = mở OvenRanking (ghi đè toggle phóng to theo yêu cầu) | VÀNG = thu nhỏ | ĐỎ = thoát
GAN_CHAM_MAC { DONG_VE 'RANKING' } {
    if($global:W.WindowState-eq 'Minimized'){$global:W.WindowState='Maximized'}else{$global:W.WindowState='Minimized'}
} { DONG_VE 'EXIT' }

# Nút "Làm Mới Nhanh" (title bar) -- ép làm mới NGAY, không đợi lịch 60 giây.
# CHỈ áp dụng cho San lượng + QA-HOUR -- Oven KHÔNG còn do nút này điều khiển nữa (đã
# tách thành cơ chế tự động riêng: FileSystemWatcher + hẹn giờ debounce 5 giây +
# Runspace_LO, xem BAT_DAU_LAM_MOI_LO_NEN phía trên). Bấm nút này KHÔNG rút ngắn thời
# gian chờ của Oven. Chạy ĐỒNG BỘ trên UI thread (không qua Runspace nền) vì đây là hành
# động do người dùng chủ động bấm -- chấp nhận chờ 1 chút (đã giới hạn timeout
# ngắn, xem bên dưới), đổi lại đơn giản hơn nhiều so với dựng thêm 1 bộ
# Runspace/Timer riêng chỉ cho nút này.
$global:e.Button_Lam_Moi_Nhanh.Add_Click({
    $btn = $global:e.Button_Lam_Moi_Nhanh
    $btn.IsEnabled = $false
    try {
        # Cắt ngang chu kỳ tự động đang chạy dở (dù còn bao nhiêu giây), ép về 0 -- chạy
        # ngay lần này, rồi lên lịch lại ĐÚNG 1 chu kỳ MỚI (refreshMs) tính từ THỜI ĐIỂM
        # BẤM NÚT, không phải nối tiếp lịch cũ của timer trước đó.
        if ($global:refreshTimer) { $global:refreshTimer.Stop() }

        $qaRows = @()
        # Chỉ thử 1 lần, timeout 6s -- khác với chu kỳ nền (mặc định 3 lần x 15s,
        # có thể tới ~45s) vì đây là gọi ĐỒNG BỘ trên UI thread, không thể để
        # người dùng chờ quá lâu chỉ vì bấm 1 nút làm mới thủ công.
        try { $qaRows = LAY_DU_LIEU_QA_HOUR -MaxRetries 1 -TimeoutMs 6000 } catch { GHI_LOG "Làm Mới Nhanh - lỗi LAY_DU_LIEU_QA_HOUR: $($_.Exception.Message)" 'ERROR' }
        if ($qaRows -and $qaRows.Count -gt 0) { CAP_NHAT_ACTUAL_TU_QA_HOUR $qaRows }
        # Luôn nạp lại danh sách + vẽ lại bảng sản lượng ở đây (dù QA-HOUR có
        # dòng nào khớp hay không) để đảm bảo UI production LUÔN được làm mới
        # như yêu cầu, không phụ thuộc kết quả QA-HOUR.
        NAP_DANH_SACH_MODEL
        CAP_NHAT_BANG_DU_LIEU
        $global:e.Label_Cap_Nhat_Luc.Text = '  Cập nhật: ' + ((Get-Date).ToString('HH:mm:ss'))
        GHI_LOG "Đã Làm Mới Nhanh theo yêu cầu người dùng" 'INFO'
    } catch {
        GHI_LOG "Lỗi khi Làm Mới Nhanh: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    } finally {
        if ($global:refreshTimer) { $global:refreshTimer.Start() }
        $btn.IsEnabled = $true
    }
})

# Nút thông tin người dùng — click để đăng nhập user khác
$global:e.Khung_Nguoi_Dung.Add_MouseLeftButtonDown({
    $global:e.O_Nhap_Ma_Nhan_Vien.Text=''; $global:e.Khung_Loi_Dang_Nhap.Visibility='Collapsed'; $global:e.Khung_Khoa_Dang_Nhap.Visibility='Collapsed'
    MO_LOP_PHU $global:e.Lop_Phu_Dang_Nhap $global:e.Ty_Le_Khung_Dang_Nhap
    $global:W.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Input,
        [Action]{$global:e.O_Nhap_Ma_Nhan_Vien.Focus()|Out-Null;CAP_NHAT_KHOA_DANG_NHAP})
})

# Xử lý đăng nhập
$global:e.Button_Xac_Nhan_Dang_Nhap.Add_Click({XAC_NHAN_DANG_NHAP})
$global:e.O_Nhap_Ma_Nhan_Vien.Add_KeyDown({param($s,$ev);if($ev.Key-eq 'Return'){XAC_NHAN_DANG_NHAP}})
$global:e.Lop_Phu_Dang_Nhap.Add_MouseLeftButtonDown({
    param($s,$ev)
    if($ev.Source -is [System.Windows.Controls.Grid]){
        # FIX HIỂN THỊ SAI PHIÊN: bấm ra ngoài với ô nhập RỖNG = huỷ đăng nhập -- khôi
        # phục khung người dùng theo PHIÊN ĐĂNG NHẬP HIỆN TẠI (AS.curUser/curName).
        # TRƯỚC ĐÂY ghi cứng 'VN004043'/'Administrator': nếu phiên đang là nhân viên
        # khác, header sẽ hiển thị SAI so với phiên thật (AS.curUser không đổi).
        if($global:e.O_Nhap_Ma_Nhan_Vien.Text.Trim()-eq ''){
            $global:e.Label_Ma_Nhan_Vien.Text=$global:AS.curUser
            $global:e.Label_Chuc_Vu.Text=$global:AS.curName
        }
        DONG_LOP_PHU $global:e.Lop_Phu_Dang_Nhap
    }
})

# Đóng thông báo WIP
$global:e.Button_Dong_Thong_Bao.Add_Click({
    $global:e.Xoay_Banh_Rang.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$null)
    DONG_LOP_PHU $global:e.Lop_Phu_Thong_Bao
})
$global:e.Lop_Phu_Thong_Bao.Add_MouseLeftButtonDown({
    param($s,$ev)
    if($ev.Source -is [System.Windows.Controls.Grid]){
        $global:e.Xoay_Banh_Rang.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$null)
        DONG_LOP_PHU $global:e.Lop_Phu_Thong_Bao
    }
})

# Đăng xuất — thoát ứng dụng
$global:e.Button_Dang_Xuat.Add_MouseLeftButtonDown({ $global:W.Close() })
# Sự kiện click lò nướng — lấy DataContext.OvenId từ ContentPresenter
$xLyClickLo = {
    param($s, $ev)
    try {
        $el = $ev.OriginalSource
        while ($el -and $el -isnot [System.Windows.Controls.ContentPresenter]) {
            $el = LAY_CHA_AN_TOAN $el
        }
        if ($el -and $el.DataContext -and $el.DataContext.OvenId) {
            HIEN_POPUP_LO $el.DataContext.OvenId
        }
    } catch {
        GHI_LOG "Lỗi xLyClickLo: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
}
$global:e.Danh_Sach_Lo_1.Add_MouseLeftButtonDown($xLyClickLo)
$global:e.Danh_Sach_Lo_2.Add_MouseLeftButtonDown($xLyClickLo)

# Điều hướng Thanh_Dieu_Huong
$global:e.Nav_Trang_Chu.Add_MouseLeftButtonDown({
    DAT_NAV_HOAT_DONG 'Nav_Trang_Chu'; DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung
    DONG_LOP_PHU $global:e.Lop_Phu_Thong_Bao; $global:e.Popup_Tien_Do.Visibility='Collapsed'; AN_POPUP_LO
})
$global:e.Nav_Tim_Kiem.Add_MouseLeftButtonDown({DAT_NAV_HOAT_DONG 'Nav_Tim_Kiem'; TINH_NANG_DANG_PHAT_TRIEN 'Tìm kiếm nâng cao'})
$global:e.Nav_Quan_Tri_He_Thong.Add_MouseLeftButtonDown({DAT_NAV_HOAT_DONG 'Nav_Quan_Tri_He_Thong'; TINH_NANG_DANG_PHAT_TRIEN 'Quản trị hệ thống'})
$global:e.Nav_Cai_Dat_San_Luong.Add_MouseLeftButtonDown({
    DAT_NAV_HOAT_DONG 'Nav_Cai_Dat_San_Luong'; $global:e.Khung_Loi_Cai_Dat.Visibility='Collapsed'
    NAP_DANH_SACH_MODEL_CAI_DAT; MO_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong $global:e.Ty_Le_Cai_Dat_San_Luong
})
$global:e.Nav_Cai_Dat_Chung.Add_MouseLeftButtonDown({
    DAT_NAV_HOAT_DONG 'Nav_Cai_Dat_Chung'; $global:e.Khung_Loi_Xac_Thuc.Visibility='Collapsed'
    $global:e.O_Nhap_Mat_Khau.Password=''; $global:e.Button_Xac_Nhan_Quyen.IsEnabled=$true
    MO_LOP_PHU $global:e.Lop_Phu_Xac_Thuc_Quyen $global:e.Ty_Le_Xac_Thuc_Quyen
    $global:W.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Input,
        [Action]{if((Get-Date)-ge $global:AS.cfgLock){$global:e.O_Nhap_Mat_Khau.Focus()|Out-Null}})
})


# Cài đặt sản lượng
$global:e.Button_Dong_Cai_Dat_San_Luong.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU})
$global:e.Button_Huy_Cai_Dat_San_Luong.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU})
$global:e.Button_Luu_Cai_Dat_San_Luong.Add_Click({LUU_CAI_DAT_SAN_LUONG})
$global:e.Button_Them_Model.Add_Click({THEM_MODEL_MOI})
$global:e.Lop_Phu_Cai_Dat_San_Luong.Add_MouseLeftButtonDown({
    param($s,$ev); if($ev.Source -is [System.Windows.Controls.Grid]){DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU}
})

# Xác thực quyền cài đặt chung
$global:e.Button_Xac_Nhan_Quyen.Add_Click({XAC_NHAN_QUYEN_TRUY_CAP})
$global:e.Button_Huy_Xac_Thuc.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Xac_Thuc_Quyen; VE_TRANG_CHU})
$global:e.O_Nhap_Mat_Khau.Add_KeyDown({param($s,$ev);if($ev.Key-eq 'Return'){XAC_NHAN_QUYEN_TRUY_CAP}})
$global:e.O_Nhap_Ma_NV_Admin.Add_KeyDown({param($s,$ev);if($ev.Key-eq 'Return'){$global:e.O_Nhap_Mat_Khau.Focus()|Out-Null}})

# Cài đặt chung
$global:e.Button_Luu_Cai_Dat_Chung.Add_Click({LUU_CAU_HINH_CHUNG})
$global:e.Button_Huy_Cai_Dat_Chung.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung; VE_TRANG_CHU})
$global:e.Button_Dong_Cai_Dat_Chung.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung; VE_TRANG_CHU})

# Sửa kế hoạch sản lượng (Plan)
$global:e.Button_Luu_Sua_Plan.Add_Click({LUU_SUA_PLAN})
$global:e.Button_Huy_Sua_Plan.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Sua_Plan})
$global:e.O_Nhap_So_Luong_Plan.Add_KeyDown({
    param($s,$ev)
    if($ev.Key-eq 'Return'){LUU_SUA_PLAN}
    if($ev.Key-eq 'Escape'){DONG_LOP_PHU $global:e.Lop_Phu_Sua_Plan}
})
$global:e.Lop_Phu_Sua_Plan.Add_MouseLeftButtonDown({
    param($s,$ev); if($ev.Source -is [System.Windows.Controls.Grid]){DONG_LOP_PHU $global:e.Lop_Phu_Sua_Plan}
})

# Đóng cửa sổ chi tiết lò nướng
$global:e.Button_Dong_Popup_Lo.Add_Click({AN_POPUP_LO})
$global:W.Add_MouseDown({
    param($s,$ev)
    if($global:e.Popup_Chi_Tiet_Lo.Visibility-eq 'Visible'){
        $pt=$ev.GetPosition($global:e.Popup_Chi_Tiet_Lo)
        $rc=[System.Windows.Rect]::new(0,0,$global:e.Popup_Chi_Tiet_Lo.ActualWidth,$global:e.Popup_Chi_Tiet_Lo.ActualHeight)
        if(-not $rc.Contains($pt)){AN_POPUP_LO}
    }
})

# Sự kiện bảng dữ liệu sản lượng — HOVER (di chuột) hiện popup, không cần click
$global:MAIN_CONTENT_REF = TIM_PHAN_TU 'mainContent'
$global:e.Bang_San_Luong.Add_PreviewMouseMove({
    param($s,$ev)
    try {
        $pos = $ev.GetPosition($global:e.Bang_San_Luong)
        $hit = $global:e.Bang_San_Luong.InputHitTest($pos)
        $el = $hit
        while ($el -and $el -isnot [System.Windows.Controls.DataGridRow]) {
            $el = LAY_CHA_AN_TOAN $el
        }
        if ($el -and $el.Item) {
            if ($global:AS.hoverRowItem -ne $el.Item) {
                $global:AS.hoverRowItem = $el.Item
                $viTriY = 100
                try {
                    $diem = $el.TransformToAncestor($global:MAIN_CONTENT_REF).Transform([System.Windows.Point]::new(0,0))
                    $viTriY = $diem.Y
                } catch { }
                HIEN_POPUP_HANG $el.Item $viTriY
            }
        } else {
            if ($global:AS.hoverRowItem) {
                $global:AS.hoverRowItem = $null
                AN_POPUP_HANG
            }
        }
    } catch {
        GHI_LOG "Lỗi Bang_San_Luong PreviewMouseMove: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
})
$global:e.Bang_San_Luong.Add_MouseLeftButtonUp({
    param($s,$ev)
    try {
        $cell=$ev.OriginalSource
        while($cell -and $cell -isnot [Windows.Controls.DataGridCell]){
            $cell = LAY_CHA_AN_TOAN $cell
        }
        if(-not $cell){return}
        if($cell.Column -and $cell.Column.Header-eq 'PLAN'){
            $item=$global:e.Bang_San_Luong.SelectedItem; if($item){MO_SUA_PLAN $item}
        }
    } catch {
        GHI_LOG "Lỗi Bang_San_Luong MouseLeftButtonUp: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
})
$global:e.Bang_San_Luong.Add_MouseLeave({ $global:AS.hoverRowItem=$null; AN_POPUP_HANG })

# Phím Esc đóng lớp phủ theo thứ tự ưu tiên
$global:W.Add_KeyDown({
    param($s,$ev)
    if($ev.Key-eq 'Escape'){
        if    ($global:e.Lop_Phu_Sua_Plan.Visibility    -eq 'Visible'){DONG_LOP_PHU $global:e.Lop_Phu_Sua_Plan; $ev.Handled=$true}
        elseif($global:e.Lop_Phu_Cai_Dat_Chung.Visibility -eq 'Visible'){DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung; VE_TRANG_CHU; $ev.Handled=$true}
        elseif($global:e.Lop_Phu_Xac_Thuc_Quyen.Visibility     -eq 'Visible'){DONG_LOP_PHU $global:e.Lop_Phu_Xac_Thuc_Quyen; VE_TRANG_CHU; $ev.Handled=$true}
        elseif($global:e.Lop_Phu_Cai_Dat_San_Luong.Visibility    -eq 'Visible'){DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU; $ev.Handled=$true}
        elseif($global:e.Lop_Phu_Thong_Bao.Visibility      -eq 'Visible'){$global:e.Xoay_Banh_Rang.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$null); DONG_LOP_PHU $global:e.Lop_Phu_Thong_Bao; $ev.Handled=$true}
        elseif($global:e.Lop_Phu_Dang_Nhap.Visibility       -eq 'Visible'){DONG_LOP_PHU $global:e.Lop_Phu_Dang_Nhap; $ev.Handled=$true}
        elseif($global:e.Popup_Chi_Tiet_Lo.Visibility          -eq 'Visible'){AN_POPUP_LO; $ev.Handled=$true}
    }
})

    $global:W.Add_Loaded({
        $global:e.Label_Ma_Nhan_Vien.Text   = $global:AS.curUser
        $global:e.Label_Chuc_Vu.Text = $global:AS.curName
        $global:e.Label_Cap_Nhat_Luc.Text  = '  Cập nhật: '+((Get-Date).ToString('HH:mm:ss'))
        _GHI_MOC_THOI_GIAN "Window.Loaded fired -- khung tĩnh đã hiển thị"

        # Chạy tính toán trên Runspace nền — KHÔNG chặn UI, cửa sổ hiện ngay.
        # Gọi lại mỗi lần quay về UI.xaml (từ OvenRanking/MiniMap) để số liệu tươi ngay.
        BAT_DAU_LAM_MOI_NEN
        BAT_DAU_LAM_MOI_LO_NEN

        $global:clockTimer.Start()

        # Chu kỳ làm mới tự động (Sản lượng + QA-HOUR) -- tạo ĐÚNG 1 LẦN (guard), các lần
        # quay lại UI.xaml chỉ Start() lại. KHÔNG liên quan Oven (đã tách Runspace_LO riêng).
        if (-not $global:refreshTimer) {
            $refreshMs = 60000
            if ($global:CFG -and $global:CFG.config.ContainsKey('refresh')) {
                $rfTmp = 0
                if ([int]::TryParse([string]$global:CFG.config['refresh'], [ref]$rfTmp) -and $rfTmp -ge 5000) { $refreshMs = $rfTmp }
            }
            $global:refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:refreshTimer.Interval = [TimeSpan]::FromMilliseconds($refreshMs)
            $global:refreshTimer.Add_Tick({
                try { $global:e.Label_Cap_Nhat_Luc.Text = '  Cập nhật: ' + ((Get-Date).ToString('HH:mm:ss')) } catch { }
                BAT_DAU_LAM_MOI_NEN
            })
        }
        $global:refreshTimer.Start()

        # Hẹn giờ debounce 5 giây cho Oven -- tạo ĐÚNG 1 LẦN cho vòng đời app (guard)
        if (-not $global:HEN_GIO_LAM_MOI_LO) {
            $global:HEN_GIO_LAM_MOI_LO = New-Object System.Windows.Threading.DispatcherTimer
            $global:HEN_GIO_LAM_MOI_LO.Interval = [TimeSpan]::FromSeconds(5)
            $global:HEN_GIO_LAM_MOI_LO.Add_Tick({
                $global:HEN_GIO_LAM_MOI_LO.Stop()
                BAT_DAU_LAM_MOI_LO_NEN
            })
        }

        # FileSystemWatcher Active.db -- tạo/đăng ký ĐÚNG 1 LẦN cho vòng đời app.
        # Dispatcher là per-thread nên marshal $global:W.Dispatcher vẫn hợp lệ sau khi
        # đổi cửa sổ (mọi cửa sổ cùng main thread dùng chung 1 Dispatcher).
        if (-not $global:FSW_ACTIVE) {
            try {
                $global:FSW_ACTIVE = New-Object System.IO.FileSystemWatcher
                $global:FSW_ACTIVE.Path = $global:DATABASE_DIR
                $global:FSW_ACTIVE.IncludeSubdirectories = $false
                # KHÔNG lọc theo tên file cụ thể ('Active.db') -- nếu MultiRequest ghi qua file
                # tạm rồi ĐỔI TÊN đè lên (như chính OTMSAnalyzer đang làm với SETTINGS.db.tmp),
                # sự kiện Renamed có thể mang tên file NGUỒN khác 'Active.db', dễ bị Filter lọc
                # mất. Vì $global:DATABASE_DIR chỉ chứa đúng Active.db, theo dõi CẢ thư mục và cứ
                # khởi động lại hẹn giờ debounce mỗi khi có bất kỳ thay đổi nào là an toàn, không
                # cần phân biệt.
                $Xu_Ly_Su_Kien_FSW_ActiveDb = {
                    $global:TRANG_THAI_DUNG_CHUNG['ActiveDbDaThayDoi'] = $true
                    $global:W.Dispatcher.BeginInvoke([Action]{
                        $global:HEN_GIO_LAM_MOI_LO.Stop()
                        $global:HEN_GIO_LAM_MOI_LO.Start()
                    }) | Out-Null
                }

                Register-ObjectEvent -InputObject $global:FSW_ACTIVE -EventName Changed -Action $Xu_Ly_Su_Kien_FSW_ActiveDb -SourceIdentifier 'FSW_ActiveDb_Changed' | Out-Null
                Register-ObjectEvent -InputObject $global:FSW_ACTIVE -EventName Created -Action $Xu_Ly_Su_Kien_FSW_ActiveDb -SourceIdentifier 'FSW_ActiveDb_Created' | Out-Null
                Register-ObjectEvent -InputObject $global:FSW_ACTIVE -EventName Renamed -Action $Xu_Ly_Su_Kien_FSW_ActiveDb -SourceIdentifier 'FSW_ActiveDb_Renamed' | Out-Null

                $global:FSW_ACTIVE.EnableRaisingEvents = $true
            } catch {
                GHI_LOG "Lỗi khởi tạo FileSystemWatcher cho Active.db: $($_.Exception.Message)" 'ERROR'
            }
        }
    })
}

# ================================================================
# KHỞI TẠO ỨNG DỤNG VÀ HIỂN THỊ MÀN HÌNH
# ================================================================
# Chỉ nạp MO/USER/SETTINGS.db (nhỏ, nhanh) đồng bộ ở đây — vì USER_DB
# cần sẵn sàng ngay để đăng nhập hoạt động được trước khi Runspace nền
# kịp chạy xong. Phần TÍNH TOÁN NẶNG (bảng sản lượng + Active.db) đã
# chuyển sang BAT_DAU_LAM_MOI_NEN (chạy nền, xem phía trên).
try {
    KHOI_TAO_DB
    # Nạp lại nhân viên đã đăng nhập lần gần nhất (employee_id lưu trong SETTINGS.db) --
    # PHẢI gọi SAU KHOI_TAO_DB (cần CFG.url_params + USER_DB đã nạp xong), TRƯỚC
    # Window.Add_Loaded (hiển thị Label_Ma_Nhan_Vien/Label_Chuc_Vu bên dưới).
    NAP_NGUOI_DUNG_DA_LUU
} catch {
    # KHOI_TAO_DB chỉ ném lỗi ra tới đây khi CÓ file .db TỒN TẠI nhưng đọc/giải mã/phân
    # tích THẤT BẠI (file thiếu ở lần đầu cài đặt KHÔNG bị coi là lỗi, xem NAP_MO_DB/
    # NAP_USER_DB/NAP_SETTINGS_DB) -- đây là lỗi NGHIÊM TRỌNG, dữ liệu có thể đã hỏng,
    # KHÔNG an toàn để chạy tiếp với dữ liệu rỗng/sai. Thông báo rõ + THOÁT ứng dụng.
    GHI_LOG "Lỗi khởi tạo DB (đồng bộ lúc mở app) -- thoát ứng dụng: $($_.Exception.Message)" 'ERROR'
    [System.Windows.MessageBox]::Show(
        "Không thể đọc dữ liệu cần thiết để khởi động ứng dụng:`n$($_.Exception.Message)`n`nỨng dụng sẽ đóng lại.",
        'Lỗi khởi động', 'OK', 'Error') | Out-Null
    exit
}
_GHI_MOC_THOI_GIAN "KHOI_TAO_DB (đồng bộ, nhẹ) xong"

while ($true) {
    $manHinhDangMo = $global:MAN_HINH_KE
    if ($manHinhDangMo -notin @('UI','RANKING','MINIMAP')) { break }
    $global:MAN_HINH_KE = 'EXIT'
    # V2.4: timer nền (BG_POLL_TIMER_LO) đọc biến này để vẽ dữ liệu lò mới vào
    # đúng màn hình đang sống (UI: card lò / RANKING: 2 card / MINIMAP: line data)
    $global:MAN_HINH_HIEN_TAI = $manHinhDangMo

    switch ($manHinhDangMo) {
        'UI'      { MO_MAN_HINH_UI }
        'RANKING' { MO_MAN_HINH_RANKING }
        'MINIMAP' { MO_MAN_HINH_MINIMAP }
    }
    if (-not $global:W) { break }

    [void]$global:W.ShowDialog()

    # Dọn timer gắn với cửa sổ vừa đóng (DispatcherTimer gắn chung Dispatcher -- window
    # đóng rồi mà không Stop() sẽ tiếp tục tick vào element đã chết)
    if ($global:clockTimer)    { $global:clockTimer.Stop() }
    if ($global:refreshTimer)  { $global:refreshTimer.Stop() }
    if ($global:MINIMAP_TIMER) { $global:MINIMAP_TIMER.Stop() }
}
_GHI_MOC_THOI_GIAN "Thoát vòng lặp điều hướng -- dọn dẹp tài nguyên"
$global:clockTimer.Stop()
if($global:refreshTimer){ $global:refreshTimer.Stop() }
if($global:HEN_GIO_LAM_MOI_LO){ $global:HEN_GIO_LAM_MOI_LO.Stop() }
if($global:MINIMAP_TIMER){ $global:MINIMAP_TIMER.Stop() }
if($global:BG_POLL_TIMER){ $global:BG_POLL_TIMER.Stop() }
if($global:BG_POLL_TIMER_LO){ $global:BG_POLL_TIMER_LO.Stop() }
if($global:BG_PS){ try{ $global:BG_PS.Dispose() }catch{} }
if($global:BG_PS_LO){ try{ $global:BG_PS_LO.Dispose() }catch{} }
if($global:BG_RUNSPACE){ try{ $global:BG_RUNSPACE.Close() }catch{} }
if($global:BG_RUNSPACE_LO){ try{ $global:BG_RUNSPACE_LO.Close() }catch{} }
foreach ($Ma_Dang_Ky_FSW in @('FSW_ActiveDb_Changed','FSW_ActiveDb_Created','FSW_ActiveDb_Renamed')) {
    try { Unregister-Event -SourceIdentifier $Ma_Dang_Ky_FSW -ErrorAction SilentlyContinue } catch { }
}
if($global:FSW_ACTIVE){
    try { $global:FSW_ACTIVE.EnableRaisingEvents = $false; $global:FSW_ACTIVE.Dispose() } catch { }
}
if($global:MUTEX_UNG_DUNG){
    try { $global:MUTEX_UNG_DUNG.ReleaseMutex(); $global:MUTEX_UNG_DUNG.Dispose() } catch { }
}
