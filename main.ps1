# ================================================================
# main.ps1 -- Điều phối toàn bộ module cho OTMSAnalyzer V10
# Ứng dụng màn hình toàn phần (WPF / PowerShell 5.1)
# Mã hoá dữ liệu: AES-256-CBC + Nén GZip
# Cách chạy: powershell.exe -ExecutionPolicy Bypass -File main.ps1
#
# v2.7.1: Bỏ toàn bộ MessageBox, thay bằng GHI_LOG (Support.psm1).
#         Fix catch block bị hỏng cú pháp trong NAP_CUA_SO (khiến
#         lỗi nạp XAML bị nuốt im lặng). Thêm guard $null cho
#         $global:W sau mỗi NAP_CUA_SO.
# ================================================================
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# ================================================================
# SECTION 1 — KHỞI TẠO MÔI TRƯỜNG
# ================================================================
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

# ── Chặn mở trùng lặp ứng dụng (Mutex hệ thống) ──
# LƯU Ý: đoạn này chạy TRƯỚC khi import module Support -> chưa có GHI_LOG,
# nên dùng Write-Host thay MessageBox để không chặn UI.
$global:MUTEX_UNG_DUNG = $null
try {
    $daTaoMoiMutex = $false
    $global:MUTEX_UNG_DUNG = New-Object System.Threading.Mutex($true, 'Global\OTMSAnalyzer_SingleInstance', [ref]$daTaoMoiMutex)
    if (-not $daTaoMoiMutex) {
        Write-Host "OTMSAnalyzer đang chạy rồi. Không thể mở thêm bản thứ hai cùng lúc." -ForegroundColor Yellow
        exit
    }
} catch { }

# ── Trạng thái dùng chung giữa UI thread và Runspace nền (hashtable đồng bộ hoá) ──
$global:TRANG_THAI_DUNG_CHUNG = [hashtable]::Synchronized(@{
    ActiveDbDaThayDoi = $true
    GhiLogBat         = $true
})

# ── Xác định thư mục gốc ứng dụng ──
$APP_ROOT = if ($PSScriptRoot -and $PSScriptRoot -ne '') {
    $PSScriptRoot
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
_GHI_MOC_THOI_GIAN "Xác định APP_ROOT xong"

# ── Nạp tất cả module từ thư mục Modules/ ──
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
_GHI_MOC_THOI_GIAN "Import-Module 10 module xong"

KHOI_TAO_BIEN -RootDir $APP_ROOT
DAT_HASH_ADMIN
_GHI_MOC_THOI_GIAN "KHOI_TAO_BIEN + DAT_HASH_ADMIN xong"

KHOI_TAO_DONG_HO
_GHI_MOC_THOI_GIAN "KHOI_TAO_DONG_HO xong"

# ================================================================
# SECTION 2 — KHAI BÁO BIẾN TOÀN CỤC
# ================================================================
$global:UI_HOAT_DONG       = $false
$global:MAN_HINH_KE        = 'UI'
$global:MAN_HINH_HIEN_TAI  = 'UI'
$global:LO_LICH_SU         = @{}

# Ranking popup state (2 popup ĐỘC LẬP cho 2 card)
$global:RANKING_POP_MAP = @{ 1=@{}; 2=@{} }
$global:RANKING_ROW_MAP = @{ 1=@{}; 2=@{} }
$global:RANKING_STATE = @{
    1 = @{ Pop=$null; Row=$null; OvenId=$null }
    2 = @{ Pop=$null; Row=$null; OvenId=$null }
}

# MiniMap data
$global:MM_DATA      = @{}
$global:MM_LINES     = @()
$global:MINIMAP_LINE = $null
$global:MINIMAP_TIMER = $null

# Runspace nền (Sản lượng + QA-HOUR, chu kỳ 60s)
$global:BG_RUNSPACE   = $null
$global:BG_PS         = $null
$global:BG_HANDLE     = $null
$global:BG_DANG_CHAY  = $false
$global:BG_POLL_TIMER = $null

# Runspace nền riêng cho Oven (FileSystemWatcher + debounce 5s)
$global:BG_RUNSPACE_LO   = $null
$global:BG_PS_LO         = $null
$global:BG_HANDLE_LO     = $null
$global:BG_DANG_CHAY_LO  = $false
$global:BG_POLL_TIMER_LO = $null
$global:HEN_GIO_LAM_MOI_LO = $null

# Timer khác
$global:refreshTimer = $null
$global:FSW_ACTIVE   = $null
# $global:clockTimer đã được tạo trong KHOI_TAO_DONG_HO

# ================================================================
# SECTION 3 — ĐỊNH NGHĨA HÀM
# ================================================================

# ── Nạp 1 file XAML trong APP_ROOT thành Window + dựng lại $global:e tự động ──
# Mỗi lần gọi tạo Window MỚI -> handler gắn vào Window/$e.XXX không chồng qua điều hướng.
function NAP_CUA_SO([string]$tenFileXaml){
    $xamlPath = Join-Path $APP_ROOT $tenFileXaml
    try {
        if (-not (Test-Path $xamlPath)) {
            throw "Không tìm thấy file XAML: $xamlPath"
        }
        [xml]$XamlDoc = Get-Content -Path $xamlPath -Raw -Encoding UTF8
        $reader = New-Object System.Xml.XmlNodeReader $XamlDoc
        $global:W = [Windows.Markup.XamlReader]::Load($reader)
        if ($null -eq $global:W) {
            throw "XamlReader.Load trả về NULL (không rõ lý do)"
        }

        # Tạo XmlNamespaceManager qua ::new() để chắc chắn đúng type
        $nsMgr = [System.Xml.XmlNamespaceManager]::new([System.Xml.XmlNameTable]$XamlDoc.NameTable)
        $nsMgr.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')

        $reg = @{}
        foreach ($node in $XamlDoc.SelectNodes('//*[@x:Name]', $nsMgr)) {
            $ten = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
            if ($ten) { $reg[$ten] = $global:W.FindName($ten) }
        }
        $global:e = $reg
        Write-Host "  ✓ Nạp $tenFileXaml -- $($reg.Count) element" -ForegroundColor Green
    } catch {
        $global:W = $null
        $global:e = $null
        # BỎ MessageBox -- chỉ ghi log (GHI_LOG tự bỏ qua nếu bị tắt, tự tạo
        # file Loi.log nếu chưa có). Ghi 2 dòng: 1 cho người dùng đọc, 1 có
        # stack trace đầy đủ cho dev debug.
        try { GHI_LOG "[NAP_CUA_SO $tenFileXaml] Không nạp được XAML -- $($_.Exception.Message) | Dòng $($_.InvocationInfo.ScriptLineNumber) | Path: $xamlPath" 'ERROR' } catch { }
        try { GHI_LOG "[NAP_CUA_SO $tenFileXaml] STACK: $($_.Exception.ToString())" 'ERROR' } catch { }
    }
}

# ── Đóng cửa sổ hiện tại và đi tới màn hình kế tiếp ──
function DONG_VE([string]$manHinhKe){
    $global:UI_HOAT_DONG = $false
    $global:MAN_HINH_KE = $manHinhKe
    $global:W.Close()
}

# ── Gán 3 chấm macOS cho cửa sổ hiện tại ──
function GAN_CHAM_MAC([scriptblock]$xanh, [scriptblock]$vang, [scriptblock]$doHanh){
    $global:e.Cham_Xanh.Add_MouseLeftButtonDown($xanh)
    $global:e.Cham_Vang.Add_MouseLeftButtonDown($vang)
    $global:e.Cham_Do.Add_MouseLeftButtonDown($doHanh)
}

# ════════════════════════════════════════════════════════════════
# SECTION 3A — HÀM MÀN HÌNH OVENRANKING
# ════════════════════════════════════════════════════════════════

function LAY_MAU_TRANG_THAI_LO([string]$key) {
    switch ($key) {
        'BAKING' { return '#3B82F6' }
        'RISING' { return '#F59E0B' }
        'COOLING'{ return '#22C55E' }
        default  { return '#64748B' }
    }
}

# Đóng popup Ranking. $cardIdx: 1|2 = chỉ đóng card đó; 0 (mặc định) = đóng cả 2.
function global:DONG_POPUP_RANKING([int]$cardIdx = 0) {
    try {
        $danhSachCard = if ($cardIdx -in @(1,2)) { @($cardIdx) } else { @(1,2) }
        foreach ($i in $danhSachCard) {
            $st = $global:RANKING_STATE[$i]
            if ($st -and $st.Pop) { $st.Pop.Visibility = 'Collapsed' }
            if ($st -and $st.Row) { $st.Row.ClearValue([System.Windows.Controls.Border]::BackgroundProperty) }
            $global:RANKING_STATE[$i] = @{ Pop=$null; Row=$null; OvenId=$null }
        }
    } catch {
        GHI_LOG "Lỗi DONG_POPUP_RANKING: $($_.Exception.Message)" 'ERROR'
    }
}

# Bấm 1 hàng lò: đang mở popup này thì đóng, chưa thì đóng popup cũ (CHỈ trong card đó)
function global:HUONG_RANKING_MO_POPUP($popEl, $rowEl, [string]$ovenId, [int]$cardIdx) {
    try {
        $st = $global:RANKING_STATE[$cardIdx]
        $dangMo = ($null -ne $st.Pop -and [object]::ReferenceEquals($st.Pop, $popEl))
        DONG_POPUP_RANKING $cardIdx
        if (-not $dangMo) {
            $popEl.Visibility = 'Visible'
            $rowEl.Background = TAO_MAU '#EFF6FF'
            $global:RANKING_STATE[$cardIdx] = @{ Pop=$popEl; Row=$rowEl; OvenId=$ovenId }
        }
    } catch {
        GHI_LOG "Lỗi HUONG_RANKING_MO_POPUP: $($_.Exception.Message)" 'ERROR'
    }
}

function TAO_HANG_LO_RANKING($ov, [bool]$laHangCuoi) {
    $row = New-Object Windows.Controls.Border
    $styleLo = $global:W.TryFindResource('RowLo')
    if ($styleLo) { $row.Style = $styleLo }
    $row.Padding = [Windows.Thickness]::new(10,8,10,8)
    if ($laHangCuoi) { $row.BorderThickness = [Windows.Thickness]::new(0) }

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

function TAO_HANG_XEP_HANG_RANKING($rk, [int]$thuTu) {
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

function global:CAP_NHAT_GIAO_DIEN_RANKING {
    try {
        if ($global:MAN_HINH_HIEN_TAI -ne 'RANKING') { return }
        if (-not $global:e -or -not $global:e['Card1_Ten']) { return }

        for ($i = 0; $i -lt 2; $i++) {
            $cardIdx = $i + 1
            $tienTo = "Card$cardIdx"
            $card = if ($i -lt $global:OVEN_DATA.Count) { $global:OVEN_DATA[$i] } else { $null }

            $tbTen = $global:e["${tienTo}_Ten"]
            $tbSl  = $global:e["${tienTo}_SoLuong"]
            $tbSip = $global:e["${tienTo}_TongSip"]
            $rows  = $global:e["${tienTo}_Rows"]
            $rank  = $global:e["${tienTo}_Rank"]
            $vungPopup = $global:e["${tienTo}_KhuVucDuoi"]
            if (-not $tbTen -or -not $rows -or -not $rank -or -not $vungPopup) { continue }

            $idDangMo = $global:RANKING_STATE[$cardIdx].OvenId
            $global:RANKING_POP_MAP[$cardIdx] = @{}
            $global:RANKING_ROW_MAP[$cardIdx] = @{}

            $tbTen.Text = if ($card) { [string]$card.brand } else { '---' }
            $tbSl.Text  = "$(if($card){$card.soLuongOven}else{0}) lò"
            $tbSip.Text = "$(DINH_DANG_SO $(if($card){$card.tongSip}else{0})) SIP"

            for ($ci = $vungPopup.Children.Count - 1; $ci -ge 1; $ci--) { $vungPopup.Children.RemoveAt($ci) }

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
                    $global:RANKING_ROW_MAP[$cardIdx][$ovenId] = $rowEl
                    $global:RANKING_POP_MAP[$cardIdx][$ovenId] = $popEl
                    $rowEl.Add_MouseLeftButtonDown({
                        param($s,$ev)
                        HUONG_RANKING_MO_POPUP $popEl $rowEl $ovenId $cardIdx
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

            if ($idDangMo -and $global:RANKING_POP_MAP[$cardIdx].ContainsKey($idDangMo)) {
                $popEl2 = $global:RANKING_POP_MAP[$cardIdx][$idDangMo]
                $rowEl2 = $global:RANKING_ROW_MAP[$cardIdx][$idDangMo]
                if ($popEl2 -and $rowEl2) {
                    $popEl2.Visibility = 'Visible'
                    $rowEl2.Background = TAO_MAU '#EFF6FF'
                    $global:RANKING_STATE[$cardIdx] = @{ Pop=$popEl2; Row=$rowEl2; OvenId=$idDangMo }
                } else {
                    $global:RANKING_STATE[$cardIdx] = @{ Pop=$null; Row=$null; OvenId=$null }
                }
            } else {
                $global:RANKING_STATE[$cardIdx] = @{ Pop=$null; Row=$null; OvenId=$null }
            }
        }

    } catch {
        GHI_LOG "Lỗi CAP_NHAT_GIAO_DIEN_RANKING: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
}

function MO_MAN_HINH_RANKING {
    NAP_CUA_SO 'OvenRanking.xaml'
    if ($null -eq $global:W) {
        try { GHI_LOG "[MO_MAN_HINH_RANKING] NAP_CUA_SO thất bại -- W=null, bỏ qua màn Ranking" 'ERROR' } catch { }
        return
    }
    $global:UI_HOAT_DONG = $false
    _GHI_MOC_THOI_GIAN "Nạp OvenRanking.xaml xong"

    # Reset trạng thái popup mỗi lần vào màn (2 card riêng, độc lập)
    $global:RANKING_STATE = @{
        1 = @{ Pop=$null; Row=$null; OvenId=$null }
        2 = @{ Pop=$null; Row=$null; OvenId=$null }
    }

    # Neo cửa sổ vào chính giữa WorkArea (popup 900x600 theo XAML)
    $wa = [System.Windows.SystemParameters]::WorkArea
    $global:W.WindowStartupLocation = 'Manual'
    $global:W.Left = $wa.Left + ($wa.Width  - 900) / 2
    $global:W.Top  = $wa.Top  + ($wa.Height - 600) / 2

    $global:e.Khung_Cham_Tieu_De.Add_MouseLeftButtonDown({
        param($s,$ev)
        try { $global:W.DragMove() } catch { }
    })

    GAN_CHAM_MAC { DONG_VE 'MINIMAP' } { DONG_VE 'UI' } { DONG_VE 'EXIT' }

    CAP_NHAT_GIAO_DIEN_RANKING

    $global:W.Add_PreviewMouseDown({
        param($s,$ev)
        try {
            $clickTrongRow = $false
            foreach ($i in @(1,2)) {
                foreach ($rowEl in $global:RANKING_ROW_MAP[$i].Values) {
                    if ($rowEl -and $rowEl.IsVisible) {
                        $pt = $ev.GetPosition($rowEl)
                        $rc = [System.Windows.Rect]::new(0,0,$rowEl.ActualWidth,$rowEl.ActualHeight)
                        if ($rc.Contains($pt)) { $clickTrongRow = $true; break }
                    }
                }
                if ($clickTrongRow) { break }
            }
            if ($clickTrongRow) { return }

            foreach ($i in @(1,2)) {
                $st = $global:RANKING_STATE[$i]
                if ($st -and $st.Pop -and $st.Pop.Visibility -eq 'Visible') {
                    $pt = $ev.GetPosition($st.Pop)
                    $rc = [System.Windows.Rect]::new(0,0,$st.Pop.ActualWidth,$st.Pop.ActualHeight)
                    if (-not $rc.Contains($pt)) { DONG_POPUP_RANKING $i }
                }
            }
        } catch {
            try { GHI_LOG "[RANKING.Add_PreviewMouseDown] $($_.Exception.Message) | Dòng $($_.InvocationInfo.ScriptLineNumber)" 'ERROR' } catch { }
        }
    })

    BAT_DAU_LAM_MOI_LO_NEN
}

# ════════════════════════════════════════════════════════════════
# SECTION 3B — HÀM MÀN HÌNH MINIMAP
# ════════════════════════════════════════════════════════════════

function CAP_NHAT_DU_LIEU_MINIMAP {
    try {
        $now = Get-Date

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

        if (-not $global:MINIMAP_LINE -or $global:MM_LINES -notcontains $global:MINIMAP_LINE) {
            $global:MINIMAP_LINE = ($global:MM_LINES | Where-Object { $_ } | Select-Object -First 1)
        }

    } catch {
        GHI_LOG "Lỗi CAP_NHAT_DU_LIEU_MINIMAP: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
}

function TAO_HANG_MODEL_MINIMAP($m) {
    $g = New-Object Windows.Controls.Grid
    # v2.7.1: giảm margin dọc 10→4 (mỗi hàng), khoảng cách giữa 2 hàng chỉ
    # còn 8px thay vì 20px -- hiển thị được nhiều hàng hơn trong cùng không
    # gian, mà vẫn đủ thoáng đọc. Giữ margin ngang 16 cho khớp lề header.
    $g.Margin = [Windows.Thickness]::new(16,4,16,2)
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
        if (-not $global:e.MM_RemTime) { return }
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
        $m = [int][Math]::Floor(($t%3600)/60)
        $sec = $t % 60

        # Dòng giây: MM'SSs
        $global:e.MM_RemTime.Text = ('{0:d2}' -f $m) + "'" + ('{0:d2}' -f $sec) + 's'

        # Phân nhánh theo thời gian còn lại:
        #   ≤ 0          : "Hoàn thành"      + badge xanh lá
        #   ≤ 5 phút     : "Rất gần"         + badge đỏ nhấp nháy
        #   5 .. 15 phút : "Sắp hoàn thành"  (vàng)
        #   > 15 phút    : "Đang nướng"      (xanh dương, trung tính)
        if ($t -le 0) {
            $global:e.MM_RemHour.Text = 'Hoàn thành'
            DOI_MAUSAC_DEM_NGUOC '#16A34A' '#16A34A' '#F7FEFA' '#EEFAF2'
            $global:e.MM_Badge.Visibility = 'Visible'
            $global:e.MM_Badge.Background = TAO_MAU '#16A34A'
            $global:e.MM_Badge_Text.Text  = 'ĐÃ HOÀN THÀNH'
            $global:e.MM_Badge_Text.ClearValue([System.Windows.Controls.TextBlock]::OpacityProperty)
        }
        elseif ($t -le 300) {
            $global:e.MM_RemHour.Text = 'Rất gần'
            DOI_MAUSAC_DEM_NGUOC '#DC2626' '#DC2626' '#FFF9F8' '#FFF0EF'
            $global:e.MM_Badge.Visibility = 'Visible'
            $global:e.MM_Badge.Background = TAO_MAU '#DC2626'
            $global:e.MM_Badge_Text.Text  = 'SẮP XONG'
            $nhayAnim = New-Object System.Windows.Media.Animation.DoubleAnimation
            $nhayAnim.From = 1.0
            $nhayAnim.To = 0.55
            $nhayAnim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(550))
            $nhayAnim.AutoReverse = $true
            $nhayAnim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $global:e.MM_Badge_Text.BeginAnimation([System.Windows.Controls.TextBlock]::OpacityProperty, $nhayAnim)
        }
        elseif ($t -le 900) {
            $global:e.MM_RemHour.Text = 'Sắp hoàn thành'
            DOI_MAUSAC_DEM_NGUOC '#D97706' '#B45309' '#FFFDF8' '#FFF8EC'
            $global:e.MM_Badge.Visibility = 'Collapsed'
            $global:e.MM_Badge_Text.ClearValue([System.Windows.Controls.TextBlock]::OpacityProperty)
        }
        else {
            # > 15 phút -- label trung tính
            $global:e.MM_RemHour.Text = 'Đang nướng'
            DOI_MAUSAC_DEM_NGUOC '#2563EB' '#6B7280' '#FCFDFF' '#F5F9FF'
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
        if (-not $global:e.MM_OvenId) { return }
        $d = $global:MM_DATA[$line]
        $global:e.MM_OvenId.Text = [string]$d.OvenId
        $global:e.MM_Finish.Text = [string]$d.Finish
        $global:e.MM_Mag.Text    = [string]$d.Mag
        $global:e.MM_Total.Text  = [string]$d.TotalSip
        $global:e.MM_DoneId.Text    = [string]$d.DoneId
        $global:e.MM_DoneTime.Text  = [string]$d.DoneTime
        $global:e.MM_DoneAgo.Text   = [string]$d.DoneAgo
        $global:e.MM_DoneTotal.Text = [string]$d.DoneTotal

        $sp = $global:e.SP_Models
        $sp.Children.Clear()
        if ($d.Models -and $d.Models.Count -gt 0) {
            foreach ($m in $d.Models) { $sp.Children.Add((TAO_HANG_MODEL_MINIMAP $m)) | Out-Null }
        } else {
            $empty = New-Object Windows.Controls.TextBlock
            $empty.Text = 'Không có model trong lò'; $empty.FontSize = 10
            $empty.Foreground = TAO_MAU '#9CA3AF'
            $empty.Margin = [Windows.Thickness]::new(10,5,15,5)
            $empty.TextAlignment = "Center"
            $sp.Children.Add($empty) | Out-Null
        }

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
        $xMoi = if ($lineMoi -eq $global:MM_LINES[1]) { 80.5 } else { 1.5 }
        $tr = New-Object System.Windows.Media.Animation.DoubleAnimation
        $tr.To = $xMoi
        $tr.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(220))
        $global:e.Line_Thumb_X.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $tr)
        VE_LINE_MINIMAP $global:MINIMAP_LINE
    } catch {
        GHI_LOG "Lỗi DOI_LINE_MINIMAP: $($_.Exception.Message)" 'ERROR'
    }
}

function MO_MAN_HINH_MINIMAP {
    NAP_CUA_SO 'MiniMap.xaml'
    if ($null -eq $global:W) {
        try { GHI_LOG "[MO_MAN_HINH_MINIMAP] NAP_CUA_SO thất bại -- W=null, bỏ qua màn MiniMap" 'ERROR' } catch { }
        return
    }
    $global:UI_HOAT_DONG = $false
    _GHI_MOC_THOI_GIAN "Nạp MiniMap.xaml xong"

    $wa = [System.Windows.SystemParameters]::WorkArea
    $global:W.WindowStartupLocation = 'Manual'
    $global:W.Left = $wa.Right  - $global:W.Width  - 8
    $global:W.Top  = $wa.Bottom - $global:W.Height - 8

    GAN_CHAM_MAC { DONG_VE 'RANKING' } { $global:W.WindowState = 'Minimized' } { DONG_VE 'EXIT' }

    $global:e.Line_Toggle.Add_MouseLeftButtonDown({ DOI_LINE_MINIMAP })

    if (-not $global:MINIMAP_TIMER) {
        $global:MINIMAP_TIMER = New-Object System.Windows.Threading.DispatcherTimer
        $global:MINIMAP_TIMER.Interval = [TimeSpan]::FromSeconds(1)
        $global:MINIMAP_TIMER.Add_Tick({
            try {
                if ($global:MAN_HINH_HIEN_TAI -ne 'MINIMAP') { return }
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
            CAP_NHAT_DU_LIEU_MINIMAP
            if ($global:MINIMAP_LINE) { VE_LINE_MINIMAP $global:MINIMAP_LINE }
            $global:MINIMAP_TIMER.Start()
        } catch {
            GHI_LOG "Lỗi Loaded MiniMap: $($_.Exception.Message)" 'ERROR'
        }
    })

    BAT_DAU_LAM_MOI_LO_NEN
}

# ════════════════════════════════════════════════════════════════
# SECTION 3C — HÀM CHẠY NỀN (RUNSPACE)
# ════════════════════════════════════════════════════════════════

function BAT_DAU_LAM_MOI_NEN {
    if ($global:BG_DANG_CHAY) {
        GHI_LOG "BAT_DAU_LAM_MOI_NEN: bỏ qua vì đang có tiến trình nền chạy" 'INFO'
        return
    }
    $global:BG_DANG_CHAY = $true

    $global:BG_PS = [powershell]::Create()
    $global:BG_PS.Runspace = $global:BG_RUNSPACE

    [void]$global:BG_PS.AddScript({
        param($ModuleDir, $RootDir, $LogPath, $TrangThaiDungChung)

        function Ghi_Log_Du_Phong([string]$noiDung) {
            try {
                $dong = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))] [ERROR-IMPORT] $noiDung"
                Add-Content -Path $LogPath -Value $dong -Encoding UTF8 -ErrorAction SilentlyContinue
            } catch { }
        }

        $global:TRANG_THAI_DUNG_CHUNG = $TrangThaiDungChung

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
        KHOI_TAO_DB
        NAP_DANH_SACH_MODEL

        $bangKq = TINH_BANG_DU_LIEU

        $qaHourRows = @()
        try { $qaHourRows = LAY_DU_LIEU_QA_HOUR } catch { Ghi_Log_Du_Phong "LAY_DU_LIEU_QA_HOUR lỗi: $($_.Exception.Message)" }

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
                    try {
                        $global:AS.models.Clear()
                        foreach ($Model_Item in $Ket_Qua_Nen.Models) { $global:AS.models.Add($Model_Item) }
                        $global:AS.moEmpty = $Ket_Qua_Nen.MoEmpty
                    } catch {
                        GHI_LOG "Lỗi áp dụng danh sách Model: $($_.Exception.Message)" 'ERROR'
                    }

                    try {
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

function BAT_DAU_LAM_MOI_LO_NEN {
    if ($global:BG_DANG_CHAY_LO) {
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
        NAP_SETTINGS_DB | Out-Null

        $docThanhCong = LAM_MOI_DU_LIEU_LO

        $lichSuLo = @{}
        try { $lichSuLo = LAY_DU_LIEU_LICH_SU_LO } catch { Ghi_Log_Du_Phong "LAY_DU_LIEU_LICH_SU_LO lỗi: $($_.Exception.Message)" }

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
                    try {
                        $global:OVEN_DATA = $Ket_Qua_Lo.OvenData
                        if ($Ket_Qua_Lo.LichSuLo -is [hashtable]) { $global:LO_LICH_SU = $Ket_Qua_Lo.LichSuLo }
                        switch ($global:MAN_HINH_HIEN_TAI) {
                            'UI'      { if ($global:UI_HOAT_DONG) { CAP_NHAT_GIAO_DIEN_LO } }
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

# ════════════════════════════════════════════════════════════════
# SECTION 3D — HÀM MÀN HÌNH UI (màn hình chính)
# ════════════════════════════════════════════════════════════════
function MO_MAN_HINH_UI {
    NAP_CUA_SO 'UI.xaml'
    if ($null -eq $global:W) {
        try { GHI_LOG "[MO_MAN_HINH_UI] NAP_CUA_SO thất bại -- W=null, bỏ qua màn UI" 'ERROR' } catch { }
        return
    }
    $global:e.Hieu_Ung_Mo = (TIM_PHAN_TU 'mainContent').Effect
    $global:UI_HOAT_DONG = $true
    _GHI_MOC_THOI_GIAN "Nạp UI.xaml + FindName tất cả phần tử xong"

    $global:W.Add_MouseLeftButtonDown({
        param($s,$ev)
        if($global:W.WindowState -ne 'Maximized' -and $ev.Source -is [System.Windows.Window]){
            try{ $global:W.DragMove() }catch{}
        }
    })

    GAN_CHAM_MAC { DONG_VE 'RANKING' } {
        if($global:W.WindowState-eq 'Minimized'){$global:W.WindowState='Maximized'}else{$global:W.WindowState='Minimized'}
    } { DONG_VE 'EXIT' }

    $global:e.Button_Lam_Moi_Nhanh.Add_Click({
        $btn = $global:e.Button_Lam_Moi_Nhanh
        $btn.IsEnabled = $false
        try {
            if ($global:refreshTimer) { $global:refreshTimer.Stop() }

            $qaRows = @()
            try { $qaRows = LAY_DU_LIEU_QA_HOUR -MaxRetries 1 -TimeoutMs 6000 } catch { GHI_LOG "Làm Mới Nhanh - lỗi LAY_DU_LIEU_QA_HOUR: $($_.Exception.Message)" 'ERROR' }
            if ($qaRows -and $qaRows.Count -gt 0) { CAP_NHAT_ACTUAL_TU_QA_HOUR $qaRows }
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

    $global:e.Khung_Nguoi_Dung.Add_MouseLeftButtonDown({
        $global:e.O_Nhap_Ma_Nhan_Vien.Text=''; $global:e.Khung_Loi_Dang_Nhap.Visibility='Collapsed'; $global:e.Khung_Khoa_Dang_Nhap.Visibility='Collapsed'
        MO_LOP_PHU $global:e.Lop_Phu_Dang_Nhap $global:e.Ty_Le_Khung_Dang_Nhap
        $global:W.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Input,
            [Action]{$global:e.O_Nhap_Ma_Nhan_Vien.Focus()|Out-Null;CAP_NHAT_KHOA_DANG_NHAP})
    })

    $global:e.Button_Xac_Nhan_Dang_Nhap.Add_Click({XAC_NHAN_DANG_NHAP})
    $global:e.O_Nhap_Ma_Nhan_Vien.Add_KeyDown({param($s,$ev);if($ev.Key-eq 'Return'){XAC_NHAN_DANG_NHAP}})
    $global:e.Lop_Phu_Dang_Nhap.Add_MouseLeftButtonDown({
        param($s,$ev)
        if($ev.Source -is [System.Windows.Controls.Grid]){
            if($global:e.O_Nhap_Ma_Nhan_Vien.Text.Trim()-eq ''){
                $global:e.Label_Ma_Nhan_Vien.Text=$global:AS.curUser
                $global:e.Label_Chuc_Vu.Text=$global:AS.curName
            }
            DONG_LOP_PHU $global:e.Lop_Phu_Dang_Nhap
        }
    })

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

    $global:e.Button_Dang_Xuat.Add_MouseLeftButtonDown({ $global:W.Close() })

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

    $global:e.Button_Dong_Cai_Dat_San_Luong.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU})
    $global:e.Button_Huy_Cai_Dat_San_Luong.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU})
    $global:e.Button_Luu_Cai_Dat_San_Luong.Add_Click({LUU_CAI_DAT_SAN_LUONG})
    $global:e.Button_Them_Model.Add_Click({THEM_MODEL_MOI})
    $global:e.Lop_Phu_Cai_Dat_San_Luong.Add_MouseLeftButtonDown({
        param($s,$ev); if($ev.Source -is [System.Windows.Controls.Grid]){DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU}
    })

    $global:e.Button_Xac_Nhan_Quyen.Add_Click({XAC_NHAN_QUYEN_TRUY_CAP})
    $global:e.Button_Huy_Xac_Thuc.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Xac_Thuc_Quyen; VE_TRANG_CHU})
    $global:e.O_Nhap_Mat_Khau.Add_KeyDown({param($s,$ev);if($ev.Key-eq 'Return'){XAC_NHAN_QUYEN_TRUY_CAP}})
    $global:e.O_Nhap_Ma_NV_Admin.Add_KeyDown({param($s,$ev);if($ev.Key-eq 'Return'){$global:e.O_Nhap_Mat_Khau.Focus()|Out-Null}})

    $global:e.Button_Luu_Cai_Dat_Chung.Add_Click({LUU_CAU_HINH_CHUNG})
    $global:e.Button_Huy_Cai_Dat_Chung.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung; VE_TRANG_CHU})
    $global:e.Button_Dong_Cai_Dat_Chung.Add_Click({DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung; VE_TRANG_CHU})

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

    $global:e.Button_Dong_Popup_Lo.Add_Click({AN_POPUP_LO})
    $global:W.Add_MouseDown({
        param($s,$ev)
        if($global:e.Popup_Chi_Tiet_Lo.Visibility-eq 'Visible'){
            $pt=$ev.GetPosition($global:e.Popup_Chi_Tiet_Lo)
            $rc=[System.Windows.Rect]::new(0,0,$global:e.Popup_Chi_Tiet_Lo.ActualWidth,$global:e.Popup_Chi_Tiet_Lo.ActualHeight)
            if(-not $rc.Contains($pt)){AN_POPUP_LO}
        }
    })

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

        BAT_DAU_LAM_MOI_NEN
        BAT_DAU_LAM_MOI_LO_NEN

        $global:clockTimer.Start()

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

        if (-not $global:HEN_GIO_LAM_MOI_LO) {
            $global:HEN_GIO_LAM_MOI_LO = New-Object System.Windows.Threading.DispatcherTimer
            $global:HEN_GIO_LAM_MOI_LO.Interval = [TimeSpan]::FromSeconds(5)
            $global:HEN_GIO_LAM_MOI_LO.Add_Tick({
                $global:HEN_GIO_LAM_MOI_LO.Stop()
                BAT_DAU_LAM_MOI_LO_NEN
            })
        }

        if (-not $global:FSW_ACTIVE) {
            try {
                $global:FSW_ACTIVE = New-Object System.IO.FileSystemWatcher
                $global:FSW_ACTIVE.Path = $global:DATABASE_DIR
                $global:FSW_ACTIVE.IncludeSubdirectories = $false
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
# SECTION 4 — KHỞI TẠO RUNSPACE THẬT SỰ
# ================================================================
$global:BG_RUNSPACE = [runspacefactory]::CreateRunspace()
$global:BG_RUNSPACE.Open()

$global:BG_RUNSPACE_LO = [runspacefactory]::CreateRunspace()
$global:BG_RUNSPACE_LO.Open()

# ================================================================
# SECTION 5 — KHỞI TẠO DB ĐỒNG BỘ + VÒNG LẶP ĐIỀU HƯỚNG
# ================================================================
try {
    KHOI_TAO_DB
    NAP_NGUOI_DUNG_DA_LUU
} catch {
    # BỎ MessageBox -- chỉ ghi log + Write-Host để user vẫn thấy trên console
    GHI_LOG "Lỗi khởi tạo DB (đồng bộ lúc mở app) -- thoát ứng dụng: $($_.Exception.Message) | Dòng $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    Write-Host "Lỗi khởi tạo DB -- xem Loi.log tại $global:PATH_LOG" -ForegroundColor Red
    Write-Host "Chi tiết: $($_.Exception.Message)" -ForegroundColor Red
    exit
}
_GHI_MOC_THOI_GIAN "KHOI_TAO_DB (đồng bộ, nhẹ) xong"

while ($true) {
    $manHinhDangMo = $global:MAN_HINH_KE
    if ($manHinhDangMo -notin @('UI','RANKING','MINIMAP')) { break }
    $global:MAN_HINH_KE = 'EXIT'
    $global:MAN_HINH_HIEN_TAI = $manHinhDangMo

    switch ($manHinhDangMo) {
        'UI'      { MO_MAN_HINH_UI }
        'RANKING' { MO_MAN_HINH_RANKING }
        'MINIMAP' { MO_MAN_HINH_MINIMAP }
    }
    if (-not $global:W) {
        # Không có Window -> không thể ShowDialog -> thoát vòng lặp để tránh
        # PowerShell lặp vô hạn trên cùng 1 màn hình lỗi
        GHI_LOG "[Vòng lặp điều hướng] Màn hình $manHinhDangMo nạp thất bại (W=null) -- thoát vòng lặp" 'ERROR'
        break
    }

    [void]$global:W.ShowDialog()

    if ($global:clockTimer)    { $global:clockTimer.Stop() }
    if ($global:refreshTimer)  { $global:refreshTimer.Stop() }
    if ($global:MINIMAP_TIMER) { $global:MINIMAP_TIMER.Stop() }
}

_GHI_MOC_THOI_GIAN "Thoát vòng lặp điều hướng -- dọn dẹp tài nguyên"
if($global:clockTimer){ $global:clockTimer.Stop() }
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
