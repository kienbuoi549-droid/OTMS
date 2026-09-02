# ================================================================
# Output_setting.psm1 -- HÀM LIÊN QUAN ĐẾN CHỨC NĂNG CÀI ĐẶT SẢN LƯỢNG (Thêm/Sửa/Xoá model)
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

function NAP_DANH_SACH_MODEL_CAI_DAT {
    try {
        # Nạp TOÀN BỘ model từ MO_DB (CẢ active=true LẪN active=false) vào danh sách RIÊNG
        # cho màn Cài đặt sản lượng -- khác với $global:AS.models (chỉ active=true VÀ
        # plan>0, dùng cho bảng theo dõi Sản lượng ở Trang chủ). Nhờ tách riêng danh sách
        # này, người dùng mới THẤY và BẬT LẠI được những model đang active=false.
        # Hàm này CHỈ được gọi khi MỞ MỚI màn hình Cài đặt sản lượng (xem main.ps1) --
        # KHÔNG được gọi lại sau khi xoá/thêm dòng, vì sẽ đọc lại MO_DB và làm "sống lại"
        # model vừa bị người dùng bấm "X" xoá (MO_DB chỉ thực sự thay đổi sau khi bấm Lưu).
        $global:AS.settingsModels.Clear()
        foreach($mid in $global:MO_DB.Keys){
            $v=$global:MO_DB[$mid]
            $global:AS.settingsModels.Add([PSCustomObject]@{
                ModelId=$mid; TypeTag=[string]$v.type_name; Plan=[double]$v.plan
                Actual=[double]$v.actual; ActualSip=[double]$v.actual_sip; Active=[bool]$v.active
            })
        }
        XAY_DUNG_DANH_SACH_MODEL

    } catch {
        GHI_LOG "Lỗi hàm NAP_DANH_SACH_MODEL_CAI_DAT: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function XAY_DUNG_DANH_SACH_MODEL {
    try {
        # Chỉ VẼ LẠI giao diện từ $global:AS.settingsModels ĐÃ CÓ trong bộ nhớ -- KHÔNG
        # đọc lại MO_DB ở đây (xem giải thích ở NAP_DANH_SACH_MODEL_CAI_DAT bên trên).
        $global:e.Khung_Danh_Sach_Model.Children.Clear()
        for($i=0;$i-lt $global:AS.settingsModels.Count;$i++){ THEM_DONG_MODEL $i $global:AS.settingsModels[$i] $false }

    } catch {
        GHI_LOG "Lỗi hàm XAY_DUNG_DANH_SACH_MODEL: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function THEM_DONG_MODEL($idx,$m,$isNew){
    try {
        $rG=New-Object Windows.Controls.Grid; $rG.Margin=[Windows.Thickness]::new(0,0,0,8); $rG.Tag=$idx
        if($isNew){$rG.Background=TAO_MAU '#F0FDF4'}
        foreach($cw in @(24,0,72,120,82,60,36)){
            $cd=New-Object Windows.Controls.ColumnDefinition
            $cd.Width=if($cw-eq 0){[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)}else{[Windows.GridLength]::new($cw)}
            $rG.ColumnDefinitions.Add($cd)
        }
        $nLbl=New-Object Windows.Controls.TextBlock
        $nLbl.Text=if($isNew){'+'} else{($idx+1).ToString()}
        $nLbl.FontSize=10; $nLbl.FontWeight='Bold'; $nLbl.Foreground=TAO_MAU '#CBD5E1'
        $nLbl.VerticalAlignment='Center'; $nLbl.HorizontalAlignment='Center'
        [Windows.Controls.Grid]::SetColumn($nLbl,0); $rG.Children.Add($nLbl)|Out-Null
        function New-SI($val,$ridx,$field,$ro){
            $tb=New-Object Windows.Controls.TextBox; $tb.Text=$val
            $tb.FontFamily=New-Object Windows.Media.FontFamily 'Courier New'; $tb.FontSize=12
            $tb.Padding=[Windows.Thickness]::new(8,7,8,7); $tb.Margin=[Windows.Thickness]::new(4,0,0,0)
            $tb.BorderBrush=TAO_MAU '#E2E8F0'; $tb.BorderThickness=[Windows.Thickness]::new(1.5)
            $tb.Background=TAO_MAU '#F8FAFC'; $tb.Foreground=TAO_MAU '#0F172A'; $tb.Tag="${field}|${ridx}"
            if($ro){$tb.IsReadOnly=$true; $tb.Background=TAO_MAU '#F1F5F9'; $tb.Foreground=TAO_MAU '#64748B'}
            return $tb
        }
        $iM=New-SI $m.ModelId $idx 'modelId' (-not $isNew); [Windows.Controls.Grid]::SetColumn($iM,1); $rG.Children.Add($iM)|Out-Null
        $iT=New-SI $m.TypeTag $idx 'typeTag' $false; [Windows.Controls.Grid]::SetColumn($iT,2); $rG.Children.Add($iT)|Out-Null
        # FIX HIỂN THỊ PLAN BỊ CẮT PHẦN THẬP PHÂN: trước đây ép [string][int]$m.Plan --
        # lưu Plan 5000.5 rồi mở lại form chỉ còn "5000". Dùng InvariantCulture để giữ
        # nguyên số đã lưu (5000.5 -> "5000.5", 5000 -> "5000").
        $iP=New-SI ([double]$m.Plan).ToString([System.Globalization.CultureInfo]::InvariantCulture) $idx 'plan' $false; [Windows.Controls.Grid]::SetColumn($iP,3); $rG.Children.Add($iP)|Out-Null
        $iS=New-SI ([string]$m.ActualSip) $idx 'actualSip' $false; [Windows.Controls.Grid]::SetColumn($iS,4); $rG.Children.Add($iS)|Out-Null
        # ── Ô tick ACTIVE (mới) -- bật/tắt theo dõi model mà KHÔNG xoá dữ liệu actual ──
        $cActive=New-Object Windows.Controls.CheckBox
        $cActive.IsChecked=[bool]$m.Active
        $cActive.Tag="active|${idx}"
        $cActive.HorizontalAlignment='Center'; $cActive.VerticalAlignment='Center'
        $cActive.ToolTip='Bỏ tick = tạm ngưng theo dõi model này ở Trang chủ (KHÔNG xoá dữ liệu actual đã sản xuất). Muốn xoá hẳn, dùng nút X.'
        [Windows.Controls.Grid]::SetColumn($cActive,5); $rG.Children.Add($cActive)|Out-Null
        $dBtn=New-Object Windows.Controls.Button; $dBtn.Content='X'; $dBtn.Style=$global:W.FindResource('BtnS')
        $dBtn.Padding=[Windows.Thickness]::new(4); $dBtn.FontSize=10; $dBtn.Margin=[Windows.Thickness]::new(4,0,0,0); $dBtn.Tag=$idx
        $dBtn.ToolTip='Xoá hẳn model này khỏi MO.db (áp dụng ngay khi bấm Lưu & Áp dụng)'
        $dBtn.Add_Click({
            param($s,$ev)
            try {
                # FIX MẤT DỮ LIỆU CHƯA LƯU -- trước đây bấm X chỉ RemoveAt khỏi bộ nhớ rồi
                # dựng lại giao diện TỪ BỘ NHỚ: mọi nội dung người dùng đã gõ vào ô ở các
                # dòng KHÁC nhưng CHƯA bấm Lưu đều BỊ MẤT im lặng (giá trị ô nhập chỉ được
                # đọc vào bộ nhớ duy nhất 1 lần ở LUU_CAI_DAT_SAN_LUONG). Đồng bộ UI -->
                # bộ nhớ TRƯỚC khi xoá để bảo toàn chỉnh sửa chưa lưu.
                DONG_BO_UI_VAO_BO_NHO | Out-Null
                $ridx=[int]$s.Tag
                if($ridx-ge 0 -and $ridx-lt $global:AS.settingsModels.Count){$global:AS.settingsModels.RemoveAt($ridx);XAY_DUNG_DANH_SACH_MODEL}
            } catch {
                GHI_LOG "Lỗi xoá dòng model (nút X): $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
            }
        })
        [Windows.Controls.Grid]::SetColumn($dBtn,6); $rG.Children.Add($dBtn)|Out-Null
        $global:e.Khung_Danh_Sach_Model.Children.Add($rG)|Out-Null

    } catch {
        GHI_LOG "Lỗi hàm THEM_DONG_MODEL: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function THEM_MODEL_MOI {
    try {
        $global:e.Khung_Loi_Cai_Dat.Visibility='Collapsed'
        $newM=[PSCustomObject]@{ModelId='';TypeTag='';Plan=0;Actual=0;ActualSip=1;Active=$true}
        $idx=$global:AS.settingsModels.Count; $global:AS.settingsModels.Add($newM); THEM_DONG_MODEL $idx $newM $true

    } catch {
        GHI_LOG "Lỗi hàm THEM_MODEL_MOI: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
# ── Đọc TOÀN BỘ giá trị đang hiển thị trên các ô nhập của màn Cài đặt sản lượng vào
# $global:AS.settingsModels -- HÀM DÙNG CHUNG cho 2 đường gọi:
#   1) LUU_CAI_DAT_SAN_LUONG (bấm Lưu & Áp dụng)
#   2) nút X xoá dòng model (trước khi RemoveAt + dựng lại danh sách -- xem fix ở đó)
# Giá trị số (Plan/ActualSip) được parse qua PHAN_TICH_SO (InvariantCulture ưu tiên --
# khác [double]::TryParse thuần vốn theo văn hoá máy: trên máy tiếng Việt, gõ "5000.5"
# thất bại âm thầm và giá trị cũ/0 được giữ lại mà người dùng không hề biết). Trả về
# mảng lỗi (rỗng = OK): ô số có nội dung nhưng KHÔNG parse được sẽ được BÁO LỖI RÕ RÀNG
# thay vì nuốt im lặng giữ giá trị cũ như trước đây.
function DONG_BO_UI_VAO_BO_NHO {
    $loiSo = @()
    foreach($rG in $global:e.Khung_Danh_Sach_Model.Children){
        $idx=[int]$rG.Tag
        if($idx-lt 0 -or $idx-ge $global:AS.settingsModels.Count){continue}
        foreach($ctrl in $rG.Children){
            if(-not $ctrl.Tag){continue}
            if($ctrl -is [Windows.Controls.TextBox]){
                $parts=($ctrl.Tag-as [string]).Split('|'); if($parts.Count-ne 2){continue}
                $field=$parts[0]; $ridx=[int]$parts[1]
                if($ridx-lt 0 -or $ridx-ge $global:AS.settingsModels.Count){continue}
                switch($field){
                    'modelId'  {$global:AS.settingsModels[$ridx].ModelId=$ctrl.Text.Trim()}
                    'typeTag'  {$global:AS.settingsModels[$ridx].TypeTag=$ctrl.Text.Trim()}
                    'plan'     {
                        $dv=0.0; $txt=$ctrl.Text.Trim()
                        if($txt -eq ''){ }
                        elseif(PHAN_TICH_SO $txt ([ref]$dv)){ $global:AS.settingsModels[$ridx].Plan=$dv }
                        else{ $loiSo+="Dòng $($ridx+1): Plan '$txt' không phải số hợp lệ (giữ giá trị cũ)." }
                    }
                    'actualSip'{
                        $dv=0.0; $txt=$ctrl.Text.Trim()
                        if($txt -eq ''){ }
                        elseif(PHAN_TICH_SO $txt ([ref]$dv)){ $global:AS.settingsModels[$ridx].ActualSip=$dv }
                        else{ $loiSo+="Dòng $($ridx+1): SIP '$txt' không phải số hợp lệ (giữ giá trị cũ)." }
                    }
                }
            }
            elseif($ctrl -is [Windows.Controls.CheckBox]){
                # Đọc trạng thái ô tick ACTIVE -- cùng dùng quy ước Tag "field|ridx"
                $parts=($ctrl.Tag-as [string]).Split('|'); if($parts.Count-ne 2){continue}
                $field=$parts[0]; $ridx=[int]$parts[1]
                if($ridx-lt 0 -or $ridx-ge $global:AS.settingsModels.Count){continue}
                if($field-eq 'active'){ $global:AS.settingsModels[$ridx].Active=[bool]$ctrl.IsChecked }
            }
        }
    }
    return ,$loiSo
}
function LUU_CAI_DAT_SAN_LUONG {
    try {
        $global:e.Khung_Loi_Cai_Dat.Visibility='Collapsed'; $errors=@()
        # Đọc toàn bộ giá trị đang hiển thị trên giao diện vào bộ nhớ -- HÀM DÙNG CHUNG
        # với nút X xoá dòng (xem DONG_BO_UI_VAO_BO_NHO). Thu thêm lỗi nhập số sai để
        # báo rõ cho người dùng thay vì nuốt im lặng giữ giá trị cũ như trước đây.
        $loiSo = DONG_BO_UI_VAO_BO_NHO
        if($loiSo.Count-gt 0){ $errors+=$loiSo }
        $doDaiChuan = 14
        if ($global:CFG -and $global:CFG.config.ContainsKey('length_panel')) {
            $lpTmp = 0
            if ([int]::TryParse([string]$global:CFG.config['length_panel'], [ref]$lpTmp) -and $lpTmp -gt 0) { $doDaiChuan = $lpTmp }
        }
        foreach($m in $global:AS.settingsModels){
            if($m.ModelId.Length-ne $doDaiChuan){$errors+="Model '$($m.ModelId)' cần $doDaiChuan ký tự."}
        }
        # FIX KIỂM TRA MODEL ID TRÙNG -- trước đây thiếu: 2 dòng cùng Model ID đều được
        # ghi, bản sau GHI ĐÈ bản trước trong MO_DB (hashtable không cho khoá trùng),
        # mất dữ liệu im lặng mà người dùng không hề hay biết.
        $idsTrung = @($global:AS.settingsModels | Group-Object -Property ModelId | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        foreach($idT in $idsTrung){ $errors+="Model ID bị trùng: '$idT' -- mỗi model chỉ được xuất hiện 1 lần." }
        if($errors.Count-gt 0){
            $global:e.Label_Loi_Cai_Dat.Text=$errors-join "`n"
            $global:e.Khung_Loi_Cai_Dat.Visibility='Visible'; return
        }
        # Đồng bộ model từ giao diện vào cơ sở dữ liệu, sau đó ghi file MO.db
        # (active giờ lấy TỪ Ô TICK người dùng chỉnh, không còn hard-code $true nữa,
        #  và nhánh cập nhật model ĐÃ CÓ cũng ghi đè active -- trước đây bị thiếu dòng này)
        foreach($m in $global:AS.settingsModels){
            if($global:MO_DB.Contains($m.ModelId)){
                $global:MO_DB[$m.ModelId].type_name  = $m.TypeTag
                $global:MO_DB[$m.ModelId].plan        = $m.Plan
                $global:MO_DB[$m.ModelId].actual_sip  = $m.ActualSip
                $global:MO_DB[$m.ModelId].actual      = $m.Actual
                $global:MO_DB[$m.ModelId].active      = $m.Active
            } else {
                $global:MO_DB[$m.ModelId] = @{
                    type_name=$m.TypeTag; plan=$m.Plan
                    actual_sip=$m.ActualSip; actual=$m.Actual; active=$m.Active
                }
            }
        }
        # XOÁ CỨNG (theo yêu cầu): Model ID nào đang có trong MO_DB nhưng KHÔNG còn nằm
        # trong danh sách trên giao diện (tức người dùng đã bấm nút "X") thì xoá HẲN khỏi
        # MO_DB. Dùng @() để chụp nhanh (snapshot) danh sách Keys TRƯỚC khi xoá -- nếu
        # duyệt trực tiếp $global:MO_DB.Keys trong lúc vừa Remove() sẽ báo lỗi "Collection
        # was modified" vì .NET không cho sửa dictionary khi đang enumerate nó.
        $idsGiuLai=[System.Collections.Generic.HashSet[string]]::new()
        foreach($m in $global:AS.settingsModels){ [void]$idsGiuLai.Add($m.ModelId) }
        foreach($midCu in @($global:MO_DB.Keys)){
            if(-not $idsGiuLai.Contains($midCu)){ $global:MO_DB.Remove($midCu) }
        }
        try{
            LUU_MO_DB
            [System.Windows.MessageBox]::Show(
                "Đã lưu MO.db thành công!`n$global:PATH_MO",
                'Thành công','OK','Information')|Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Lỗi lưu MO.db: $_",'Lỗi','OK','Error')|Out-Null
            return
        }
        DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_San_Luong; VE_TRANG_CHU
        # Nạp lại danh sách lọc (active=true & plan>0) cho bảng Sản lượng ở Trang chủ,
        # vì MO_DB vừa đổi (có thể vừa xoá/đổi active một vài model)
        NAP_DANH_SACH_MODEL; CAP_NHAT_BANG_DU_LIEU

    } catch {
        GHI_LOG "Lỗi hàm LUU_CAI_DAT_SAN_LUONG: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function NAP_DANH_SACH_MODEL_CAI_DAT, XAY_DUNG_DANH_SACH_MODEL, THEM_DONG_MODEL, THEM_MODEL_MOI, DONG_BO_UI_VAO_BO_NHO, LUU_CAI_DAT_SAN_LUONG
