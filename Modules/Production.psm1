# ================================================================
# Production.psm1 -- CÁC HÀM LIÊN QUAN ĐẾN BẢNG THEO DÕI SẢN LƯỢNG (Section 2)
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

# ── Nạp danh sách model (chỉ những model có active=true) vào bộ nhớ ──
function NAP_DANH_SACH_MODEL {
    try {
        $global:AS.models.Clear()
        $global:AS.moEmpty = ($global:MO_DB.Count -eq 0)
        if ($global:AS.moEmpty) { return }
        foreach ($key in $global:MO_DB.Keys) {
            $v = $global:MO_DB[$key]
            if (-not $v.active)        { continue }
            if ([double]$v.plan -le 0) { continue }
            $global:AS.models.Add([PSCustomObject]@{
                ModelId   = $key
                TypeTag   = [string]$v.type_name
                Plan      = [double]$v.plan
                Actual    = [double]$v.actual
                ActualSip = [double]$v.actual_sip
            })
        }

    } catch {
        GHI_LOG "Lỗi hàm NAP_DANH_SACH_MODEL: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function CAP_NHAT_BANG_DU_LIEU {
    try {
        # LUỒNG ĐA GIAO DIỆN: hàm này đụng element giao diện UI.xaml (Bang_San_Luong,
        # Label_Tong_San_Luong). Khi đang ở OvenRanking/MiniMap ($global:UI_HOAT_DONG =
        # $false) thì RETURN -- phần cập nhật dữ liệu MO.db trong CAP_NHAT_ACTUAL_TU_QA_HOUR
        # vẫn chạy bình thường (gọi TRƯỚC hàm này), chỉ bỏ qua phần vẽ bảng.
        if ($global:UI_HOAT_DONG -ne $true) { return }
        # Empty state khi MO.db không có
        if ($global:AS.moEmpty -or $global:AS.models.Count -eq 0) {
            $global:e.Bang_San_Luong.ItemsSource = $null
            $global:e.Label_Tong_San_Luong.Text   = 'Chưa có dữ liệu'
            return
        }
        try {
            $ketQua = TINH_BANG_DU_LIEU
            $global:e.Bang_San_Luong.ItemsSource = $ketQua.Rows
            $global:e.Label_Tong_San_Luong.Text   = $ketQua.TotalText
        } catch {
            GHI_LOG "CAP_NHAT_BANG_DU_LIEU lỗi: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" 'ERROR'
        }

    } catch {
        GHI_LOG "Lỗi hàm CAP_NHAT_BANG_DU_LIEU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ── Tính toán thuần tuý (KHÔNG đụng bất kỳ phần tử giao diện nào) ──
# Tách riêng để có thể chạy trên Runspace nền (đa luồng) mà không vi phạm
# nguyên tắc "chỉ UI thread mới được động vào control WPF"
function TINH_BANG_DU_LIEU {
    try {
        $rows=[System.Collections.Generic.List[PSObject]]::new()
        $totA=0.0; $totP=0.0; $gH=LAY_GIO_DA_TROI; $now=Get-Date
        foreach($m in $global:AS.models){
            if($m.Plan -le 0){ continue }
            $pl=[Math]::Max($m.Plan,1); $act=$m.Actual; $sip=[Math]::Max($m.ActualSip,1)
            $qph=$pl/24.0; $box1=$qph/$sip; $rem=$act-($qph*$gH); $box2=$rem/$sip
            $tgt=[Math]::Round($qph*$gH)
            $aDH=8+$(if($qph-gt 0){$act/$qph}else{0})
            $aH=[int][Math]::Floor($aDH%24); $aM=[int][Math]::Round(($aDH-[Math]::Floor($aDH))*60)
            if($aM-ge 60){$aH=($aH+1)%24;$aM=0}
            $tPct=[Math]::Min([Math]::Max($(if($pl-gt 0){($qph*$gH)*100.0/$pl}else{0}),0),100)
            $aPct=[Math]::Min([Math]::Max($(if($pl-gt 0){$act*100.0/$pl}else{0}),0),100)
            $rc=if($rem-gt 0){'pos'}elseif($rem-lt 0){'neg'}else{''}
            $totA+=$act; $totP+=$pl

            # ── FIX CHONG DE NHAN Target/Actual ──────────────────────────────
            # Khi Actual chạy sát/khớp Target (|aPct - tPct| nhỏ) thì 2 nhãn giờ
            # (TgtTimeStr/ActTimeStr) và 2 nhãn SIP (TgtSipVal/ActSipVal) cùng rơi
            # trùng vị trí % trên progress bar và ĐÈ LÊN NHAU, không đọc được.
            # Quy tắc xử lý:
            #   - Target được ưu tiên GIỮ NGUYÊN vị trí % vốn có (tPct)
            #   - Actual TỰ NHƯỜNG CHỖ: dịch ra xa Target đúng MIN_GAP % về phía nó
            #     vốn nằm (Actual >= Target thì nhích sang phải, ngược lại sang trái)
            #   - Nếu phía đó chạm mép thanh (còn dưới EDGE %) thì chuyển sang phía kia
            #   - Vì 2*MIN_GAP (64) <= 100 - 2*EDGE (70) nên luôn luôn có ít nhất
            #     một phía đủ chỗ, thuật toán không bao giờ bí
            # Kết quả: tâm nhãn Actual luôn cách tâm nhãn Target tối thiểu MIN_GAP %
            # bề ngang cột (>= 48px khi cột rộng >= 150px) -> không bao giờ đè nhau.
            $EDGE=15.0; $MIN_GAP=32.0; $aHienThi=$aPct
            if([Math]::Abs($aPct-$tPct) -lt $MIN_GAP){
                $huong=1; if($aPct-lt $tPct){$huong=-1}
                $aHienThi=$tPct+$huong*$MIN_GAP
                if($aHienThi -gt 100-$EDGE){$aHienThi=$tPct-$MIN_GAP}
                elseif($aHienThi -lt $EDGE){$aHienThi=$tPct+$MIN_GAP}
                $aHienThi=[Math]::Min([Math]::Max($aHienThi,0),100)
            }

            $rows.Add([PSCustomObject]@{
                ModelId=$m.ModelId; TypeTag=$m.TypeTag; Plan=$m.Plan; Actual=$act; ActualSip=$sip
                PlanFmt=DINH_DANG_SO $m.Plan; QtyHourFmt=DINH_DANG_SO([Math]::Round($qph))
                Box1Fmt=$box1.ToString('F1'); TargetPct=$tPct; ActualPct=$aPct
                TgtTimeStr=$now.ToString('HH:mm'); TgtSipVal=(DINH_DANG_SO $tgt)+' SIP'
                ActTimeStr="$($aH.ToString('D2')):$($aM.ToString('D2'))"
                ActSipVal=(DINH_DANG_SO $act)+' SIP'
                RemainFmt=DINH_DANG_SO_CO_DAU([Math]::Round($rem)); RemainCls=$rc; Remain=$rem
                HourStr=DINH_DANG_GIO $rem $qph
                Box2Fmt="$(if($box2-ge 0){'+'}else{''})" + $box2.ToString('F1')
                _actual=$act; _plan=$m.Plan; _sip=$sip
                # Chuỗi tỉ lệ dạng "45.2*" -- dùng làm Width cho ColumnDefinition trong XAML,
                # để nhãn Target/Actual TỰ ĐỘNG đứng đúng vị trí % trên progress bar,
                # cập nhật lại mỗi khi TargetPct/ActualPct đổi (không cần Converter)
                TgtGridW=[Math]::Round($tPct,2).ToString([System.Globalization.CultureInfo]::InvariantCulture)+'*'
                TgtGridWRem=[Math]::Round(100-$tPct,2).ToString([System.Globalization.CultureInfo]::InvariantCulture)+'*'
                # ActGridW dùng $aHienThi (đã tự né Target) thay vì $aPct -- xem FIX CHONG DE NHAN
                ActGridW=[Math]::Round($aHienThi,2).ToString([System.Globalization.CultureInfo]::InvariantCulture)+'*'
                ActGridWRem=[Math]::Round(100-$aHienThi,2).ToString([System.Globalization.CultureInfo]::InvariantCulture)+'*'
            })
        }
        return [PSCustomObject]@{
            Rows      = $rows
            TotalText = "$(DINH_DANG_SO $totA) / $(DINH_DANG_SO $totP) : $(DINH_DANG_SO_CO_DAU([Math]::Round($totA-$totP)))"
        }

    } catch {
        GHI_LOG "Lỗi hàm TINH_BANG_DU_LIEU: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ════════════════════════════════════════════════════════════════
# VÙNG 10b — POPUP THÔNG TIN TIẾN ĐỘ TỪNG DÒNG (Hiện khi hover/chọn dòng)
# ════════════════════════════════════════════════════════════════
function HIEN_POPUP_HANG([PSObject]$item, [double]$viTriY = 100){
    try {
        $act=$item._actual; $plan=$item._plan; $sip=[Math]::Max($item._sip,1)
        $isDayShift=(LAY_CA_HIEN_TAI)-eq 'D'
        $sRem=if($isDayShift){$act-$plan/2}else{$act-$plan}
        $tRem=$act-$plan; $sBox=$sRem/$sip; $tBox=$tRem/$sip
        $global:e.Label_Popup_Ten_Model.Text=$item.ModelId
        $global:e.Label_Popup_Ca_Con_Lai.Text=DINH_DANG_SO_CO_DAU([Math]::Round($sRem))
        $global:e.Label_Popup_Ca_Box.Text="$(if($sBox-ge 0){'+'}else{''})" + $sBox.ToString('F1')
        $global:e.Label_Popup_Ca_Gio.Text=DINH_DANG_GIO_PHUT $sRem $plan
        $global:e.Label_Popup_Tong_Con_Lai.Text=DINH_DANG_SO_CO_DAU([Math]::Round($tRem))
        $global:e.Label_Popup_Tong_Box.Text="$(if($tBox-ge 0){'+'}else{''})" + $tBox.ToString('F1')
        $global:e.Label_Popup_Tong_Gio.Text=DINH_DANG_GIO_PHUT $tRem $plan
        foreach($pair in @(
            @{el=$global:e.Label_Popup_Ca_Con_Lai;n=$sRem},@{el=$global:e.Label_Popup_Ca_Box;n=$sBox},@{el=$global:e.Label_Popup_Ca_Gio;n=$sRem},
            @{el=$global:e.Label_Popup_Tong_Con_Lai;n=$tRem},@{el=$global:e.Label_Popup_Tong_Box;n=$tBox},@{el=$global:e.Label_Popup_Tong_Gio;n=$tRem}
        )){
            $trangThai = if($pair.n-gt 0){'pos'}elseif($pair.n-lt 0){'neg'}else{''}
            DAT_MAU_THEO_TRANG_THAI $pair.el $trangThai
        }

        # Định vị popup ngang hàng với row đang hover — giữ neo phải/dưới cũ (20,0)
        # chỉ tính lại khoảng cách trên cùng (Top) theo toạ độ Y truyền vào
        $tOld = $global:e.Popup_Tien_Do.Margin
        $global:e.Popup_Tien_Do.Margin = [Windows.Thickness]::new($tOld.Left, $viTriY, 20, 0)
        $global:e.Popup_Tien_Do.Visibility='Visible'

    } catch {
        GHI_LOG "Lỗi hàm HIEN_POPUP_HANG: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function AN_POPUP_HANG{
    try {     $global:e.Popup_Tien_Do.Visibility='Collapsed' 
    } catch {
        GHI_LOG "Lỗi hàm AN_POPUP_HANG: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

function MO_SUA_PLAN([PSObject]$item){
    try {
        $global:AS.editModelId=$item.ModelId; $global:e.Label_Model_Dang_Sua.Text=$item.ModelId
        # FIX HIỂN THỊ: giữ phần thập phân của Plan (InvariantCulture) -- trước đây ép
        # [string][int] làm mất phần lẻ khi mở form sửa.
        $global:e.O_Nhap_So_Luong_Plan.Text=([double]$item.Plan).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        MO_LOP_PHU $global:e.Lop_Phu_Sua_Plan $global:e.Ty_Le_Sua_Plan
        $global:W.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Input,
            [Action]{$global:e.O_Nhap_So_Luong_Plan.SelectAll();$global:e.O_Nhap_So_Luong_Plan.Focus()|Out-Null})

    } catch {
        GHI_LOG "Lỗi hàm MO_SUA_PLAN: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function LUU_SUA_PLAN {
    try {
        $mid=$global:AS.editModelId; if(-not $mid){DONG_LOP_PHU $global:e.Lop_Phu_Sua_Plan;return}
        $dv=0.0
        # FIX VIỀN ĐỎ KẸT: trả ô nhập về màu thường TRƯỚC khi kiểm tra -- trước đây sau
        # 1 lần nhập sai, viền đỏ bị KẸP MÃI (local value đè style setter, không bao giờ
        # được reset) kể cả khi các lần nhập sau đã hợp lệ.
        $global:e.O_Nhap_So_Luong_Plan.BorderBrush=TAO_MAU '#E2E8F0'
        # FIX PARSE SỐ: dùng PHAN_TICH_SO (Invariant ưu tiên, thử văn hoá máy sau) thay
        # cho [double]::TryParse thuần theo văn hoá máy -- trước đây trên máy đặt tiếng
        # Việt gõ "5000.5" luôn báo lỗi dù số hợp lệ (và ngược lại trên máy en-US với
        # "5000,5").
        if(-not (PHAN_TICH_SO $global:e.O_Nhap_So_Luong_Plan.Text ([ref]$dv)) -or $dv-lt 0){
            $global:e.O_Nhap_So_Luong_Plan.BorderBrush=TAO_MAU '#EF4444'
            [System.Windows.MessageBox]::Show("Số lượng Plan không hợp lệ (phải là số >= 0).`nGiá trị vừa nhập: '$($global:e.O_Nhap_So_Luong_Plan.Text)'",'Giá trị không hợp lệ','OK','Warning')|Out-Null
            return
        }
        # Cập nhật giá trị Plan trong danh sách model đang chạy
        foreach($m in $global:AS.models){if($m.ModelId-eq $mid){$m.Plan=$dv;break}}
        # Đồng bộ giá trị mới vào cơ sở dữ liệu tạm trong bộ nhớ
        if($global:MO_DB.Contains($mid)){ $global:MO_DB[$mid].plan=$dv }
        # Lưu xuống file .db -- HIỂN THỊ LỖI RÕ RÀNG nếu thất bại (đồng bộ với cách
        # LUU_CAU_HINH_CHUNG / LUU_CAI_DAT_SAN_LUONG đang làm), thay vì chỉ Write-Warning
        # âm thầm ra console ẩn (console thường ẩn/không có trong bản build .exe)
        try {
            LUU_MO_DB
        } catch {
            [System.Windows.MessageBox]::Show("Lỗi lưu MO.db sau khi sửa Plan: $_",'Error','OK','Error')|Out-Null
            GHI_LOG "Lỗi hàm LUU_SUA_PLAN (khi gọi LUU_MO_DB): $($_.Exception.Message)" 'ERROR'
            return
        }
        $global:AS.editModelId=$null
        DONG_LOP_PHU $global:e.Lop_Phu_Sua_Plan
        CAP_NHAT_BANG_DU_LIEU

    } catch {
        [System.Windows.MessageBox]::Show("Lỗi không xác định khi lưu Plan: $($_.Exception.Message)",'Error','OK','Error')|Out-Null
        GHI_LOG "Lỗi hàm LUU_SUA_PLAN: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ════════════════════════════════════════════════════════════════
# VÙNG — ÁP KẾT QUẢ FLOW 2 (QA-HOUR, cào từ module Scraper) VÀO MO_DB
# Hàm này PHẢI được gọi từ UI THREAD (vd trong tick của DispatcherTimer sau
# khi RunspacePool cào xong, tương tự cách $global:BG_POLL_TIMER hiện có xử
# lý kết quả từ Runspace nền) -- KHÔNG được gọi từ bên trong RunspacePool
# worker, vì hàm này đụng thẳng vào $global:MO_DB và gọi CAP_NHAT_BANG_DU_LIEU
# (có động vào control WPF Bang_San_Luong), vi phạm nguyên tắc "chỉ UI thread
# mới được động vào control WPF" nếu gọi sai luồng.
# ════════════════════════════════════════════════════════════════
function CAP_NHAT_ACTUAL_TU_QA_HOUR([System.Collections.IEnumerable]$Rows) {
    try {
        if (-not $Rows) { return }
        $soCapNhat = 0; $soBoQua = 0
        foreach ($r in $Rows) {
            $mid = [string]$r.ModelId
            # Không tìm thấy Model ID tương ứng trong MO_DB -> BỎ QUA, sang cấp tiếp theo
            # (đúng ý muốn: không tự tạo mới model từ QA-HOUR, chỉ cập nhật model ĐÃ CÓ sẵn)
            if (-not $global:MO_DB.Contains($mid)) { $soBoQua++; continue }
            $dv = 0.0
            # FIX SỐ LIỆU SAI THEO VÙNG MÁY: Actual đến từ server SFIS định dạng en-US
            # (vd "5,000" = 5000). [double]::TryParse thuần theo văn hoá máy: trên máy
            # đặt tiếng Việt (',' là thập phân), "5,000" bị hiểu thành 5.0 -- sản lượng
            # SAI IM LẶNG. PHAN_TICH_SO -ChiInvarian parse BẮT BUỘC theo InvariantCulture,
            # không fallback văn hoá máy cho dữ liệu từ server.
            if (PHAN_TICH_SO ([string]$r.Actual) ([ref]$dv) -ChiInvarian) {
                $global:MO_DB[$mid].actual = $dv
                $soCapNhat++
            } else {
                $soBoQua++
            }
        }
        # Model nào đang có trong MO_DB nhưng KHÔNG xuất hiện trong $Rows lần cào này
        # thì KHÔNG đụng tới -- giữ nguyên actual cũ (đúng yêu cầu, không làm gì thêm
        # ở đây vì đơn giản là không duyệt tới các Model ID đó trong vòng lặp trên).
        if ($soCapNhat -gt 0) {
            try { LUU_MO_DB } catch { GHI_LOG "Lỗi lưu MO_DB sau khi áp dụng QA-HOUR: $($_.Exception.Message)" 'ERROR' }
            NAP_DANH_SACH_MODEL
            CAP_NHAT_BANG_DU_LIEU
        }
        GHI_LOG "CAP_NHAT_ACTUAL_TU_QA_HOUR: cập nhật $soCapNhat model, bỏ qua $soBoQua (không khớp ID hoặc không parse được số)" 'INFO'

    } catch {
        GHI_LOG "Lỗi hàm CAP_NHAT_ACTUAL_TU_QA_HOUR: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function NAP_DANH_SACH_MODEL, CAP_NHAT_BANG_DU_LIEU, TINH_BANG_DU_LIEU, HIEN_POPUP_HANG, AN_POPUP_HANG, MO_SUA_PLAN, LUU_SUA_PLAN, CAP_NHAT_ACTUAL_TU_QA_HOUR
