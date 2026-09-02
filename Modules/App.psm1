# ================================================================
# App.psm1 -- CÁC HÀM HIỆU ỨNG GIAO DIỆN (Mở/đóng lớp phủ, màu sắc, thông báo, điều hướng, đồng hồ)
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

function TIM_PHAN_TU([string]$n){
    try {     $global:W.FindName($n) 
    } catch {
        GHI_LOG "Lỗi hàm TIM_PHAN_TU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Lấy phần tử CHA an toàn cho cả 2 loại cây WPF -- VisualTreeHelper::GetParent CHỈ
# chấp nhận đối tượng Visual/Visual3D, trong khi InputHitTest/OriginalSource đôi khi trả
# về phần tử thuộc LOGICAL TREE nhưng KHÔNG thuộc VISUAL TREE (điển hình: đối tượng
# System.Windows.Documents.Run mà WPF TỰ TẠO NGẦM bên trong TextBlock ngay cả khi chỉ
# gán Text="..." chứ không khai <Run> tường minh). Gọi thẳng VisualTreeHelper::GetParent
# trên 1 Run sẽ NÉM InvalidOperationException ("... is not a Visual or Visual3D"), và vì
# lỗi này xảy ra bên trong 1 event handler WPF (ngoài try/catch của PowerShell nếu handler
# không tự bọc), nó CRASH LUÔN CẢ TIẾN TRÌNH thay vì được bắt lại như lỗi thường -- đây
# chính là nguyên nhân lỗi "click ngẫu nhiên vào bảng bị crash out tool". Hàm này kiểm tra
# kiểu TRƯỚC khi gọi: đối tượng thuộc Visual/Visual3D thì đi VisualTreeHelper (đúng như
# cũ), còn lại (như Run) thì đi LogicalTreeHelper thay thế -- vẫn tìm được phần tử cha,
# chỉ khác cây duyệt.
function LAY_CHA_AN_TOAN($el) {
    try {
        if ($null -eq $el) { return $null }
        if ($el -is [System.Windows.Media.Visual] -or $el -is [System.Windows.Media.Media3D.Visual3D]) {
            return [System.Windows.Media.VisualTreeHelper]::GetParent($el)
        }
        return [System.Windows.LogicalTreeHelper]::GetParent($el)
    } catch {
        GHI_LOG "Lỗi hàm LAY_CHA_AN_TOAN: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
        return $null
    }
}

function TAO_MAU([string]$hex){
    try {
        $b = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($hex))
        $b.Freeze()   # Đóng băng để dùng an toàn trên nhiều luồng (thread-safe)
        return $b

    } catch {
        GHI_LOG "Lỗi hàm TAO_MAU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function MO_LOP_PHU($ov, $scl){
    try {
        $global:e.Hieu_Ung_Mo.Radius = 6
        $ov.Visibility = 'Visible'
        if($scl){
            $scl.ScaleX=0.93; $scl.ScaleY=0.93
            $sb=[System.Windows.Media.Animation.Storyboard]::new()
            foreach($prop in @('ScaleX','ScaleY')){
                $a=[System.Windows.Media.Animation.DoubleAnimation]::new()
                $a.From=0.93; $a.To=1.0
                $a.Duration=[System.Windows.Duration]::new([TimeSpan]::FromSeconds(0.2))
                $ease=[System.Windows.Media.Animation.BackEase]::new()
                $ease.Amplitude=0.4; $ease.EasingMode='EaseOut'; $a.EasingFunction=$ease
                [System.Windows.Media.Animation.Storyboard]::SetTarget($a,$scl)
                [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($a,[System.Windows.PropertyPath]::new($prop))
                $sb.Children.Add($a)
            }
            $opA=[System.Windows.Media.Animation.DoubleAnimation]::new()
            $opA.From=0; $opA.To=1
            $opA.Duration=[System.Windows.Duration]::new([TimeSpan]::FromSeconds(0.18))
            [System.Windows.Media.Animation.Storyboard]::SetTarget($opA,$ov)
            [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($opA,[System.Windows.PropertyPath]::new('Opacity'))
            $sb.Children.Add($opA)
            $sb.Begin($global:W,$false)
        }

    } catch {
        GHI_LOG "Lỗi hàm MO_LOP_PHU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function DONG_LOP_PHU($ov){
    try {
        $ov.Visibility='Collapsed'
        $global:e.Hieu_Ung_Mo.Radius=0

    } catch {
        GHI_LOG "Lỗi hàm DONG_LOP_PHU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function DAT_NAV_HOAT_DONG([string]$active){
    try {
        $map=@{Nav_Trang_Chu='Nav_Trang_Chu';Nav_Tim_Kiem='Nav_Tim_Kiem';Nav_Cai_Dat_San_Luong='Nav_Cai_Dat_San_Luong';Nav_Cai_Dat_Chung='Nav_Cai_Dat_Chung';Nav_Quan_Tri_He_Thong='Nav_Quan_Tri_He_Thong'}
        foreach($k in $map.Keys){
            $el=$global:e[$k]
            if($el){ $el.Background=if($k-eq $active){TAO_MAU '#EFF6FF'}else{[Windows.Media.Brushes]::Transparent} }
        }

    } catch {
        GHI_LOG "Lỗi hàm DAT_NAV_HOAT_DONG: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function VE_TRANG_CHU{
    try {     DAT_NAV_HOAT_DONG 'Nav_Trang_Chu' 
    } catch {
        GHI_LOG "Lỗi hàm VE_TRANG_CHU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function DAT_MAU_THEO_TRANG_THAI([Windows.Controls.TextBlock]$tb,[string]$cls){
    try {
        $tb.Foreground=switch($cls){'pos'{TAO_MAU '#22C55E'}'neg'{TAO_MAU '#EF4444'}default{TAO_MAU '#475569'}}

    } catch {
        GHI_LOG "Lỗi hàm DAT_MAU_THEO_TRANG_THAI: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function HIEN_THONG_BAO([string]$title,[string]$msg){
    try {
        $global:e.Label_Thong_Bao_Tieu_De.Text=$title; $global:e.Label_Thong_Bao_Noi_Dung.Text=$msg
        MO_LOP_PHU $global:e.Lop_Phu_Thong_Bao $global:e.Ty_Le_Thong_Bao
        $ga=[System.Windows.Media.Animation.DoubleAnimation]::new(0,360,
            [System.Windows.Duration]::new([TimeSpan]::FromSeconds(2)))
        $ga.RepeatBehavior=[System.Windows.Media.Animation.RepeatBehavior]::Forever
        $global:e.Xoay_Banh_Rang.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$ga)

    } catch {
        GHI_LOG "Lỗi hàm HIEN_THONG_BAO: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function TINH_NANG_DANG_PHAT_TRIEN([string]$name){
    try {     HIEN_THONG_BAO 'Tính năng đang phát triển' $name 
    } catch {
        GHI_LOG "Lỗi hàm TINH_NANG_DANG_PHAT_TRIEN: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function KHOI_TAO_DONG_HO {
    try {
        # Tạo sẵn màu ca ngày/ca đêm — tái sử dụng mỗi giây, tránh tạo đối tượng mới
        $global:BR_SHIFT_DAY_BG  = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#E0E7FF')); $global:BR_SHIFT_DAY_BG.Freeze()
        $global:BR_SHIFT_NGT_BG  = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#1E293B')); $global:BR_SHIFT_NGT_BG.Freeze()
        $global:BR_SHIFT_DAY_FG  = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#4338CA')); $global:BR_SHIFT_DAY_FG.Freeze()
        $global:BR_SHIFT_NGT_FG  = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')); $global:BR_SHIFT_NGT_FG.Freeze()
    
        # Đồng hồ realtime — cập nhật mỗi giây
        $global:clockTimer=New-Object System.Windows.Threading.DispatcherTimer
        $global:clockTimer.Interval=[TimeSpan]::FromSeconds(1)
        $global:clockTimer.Add_Tick({
            $now=Get-Date
            $global:e.Label_Dong_Ho.Text=$now.ToString('HH:mm:ss')+' | '+$now.ToString('dd/MM/yyyy')
            $shift=LAY_CA_HIEN_TAI
            $global:e.Label_Ca_Lam_Viec.Text=if($shift-eq 'D'){'CA NGÀY'}else{'CA ĐÊM'}
            $global:e.Khung_Ca_Lam_Viec.Background=if($shift-eq 'D'){$global:BR_SHIFT_DAY_BG}else{$global:BR_SHIFT_NGT_BG}
            $global:e.Label_Ca_Lam_Viec.Foreground=if($shift-eq 'D'){$global:BR_SHIFT_DAY_FG}else{$global:BR_SHIFT_NGT_FG}
        })

    } catch {
        GHI_LOG "Lỗi hàm KHOI_TAO_DONG_HO: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function TIM_PHAN_TU, TAO_MAU, MO_LOP_PHU, DONG_LOP_PHU, DAT_NAV_HOAT_DONG, VE_TRANG_CHU, DAT_MAU_THEO_TRANG_THAI, HIEN_THONG_BAO, TINH_NANG_DANG_PHAT_TRIEN, KHOI_TAO_DONG_HO, LAY_CHA_AN_TOAN
