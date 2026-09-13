# ================================================================
# General_Install.psm1 -- CÁC HÀM CHỨC NĂNG CÀI ĐẶT CHUNG (URL kết nối, tham số hệ thống)
# Dự án: OTMSAnalyzer V10 -- WPF / PowerShell 5.1
# ================================================================

function XAY_DUNG_FORM_CAU_HINH {
    try {
        $global:e.Khung_Form_Cai_Dat_Chung.Children.Clear()
        # Gán trạng thái công tắc "Ghi log hệ thống" theo giá trị hiện tại mỗi lần mở form
        if ($global:e.CheckBox_Bat_Ghi_Log) { $global:e.CheckBox_Bat_Ghi_Log.IsChecked = $global:LOG_ENABLE }
        # Gán ô "Đường dẫn SETTINGS.db chuẩn" theo giá trị ĐANG DÙNG THẬT SỰ của phiên hiện
        # tại ($global:PATH_SETTINGS, đã được KHOI_TAO_BIEN xác định qua Info.xml hoặc mặc
        # định -- xem Variable.psm1), KHÔNG đọc lại Info.xml ở đây.
        if ($global:e.O_Nhap_Duong_Dan_Settings) { $global:e.O_Nhap_Duong_Dan_Settings.Text = $global:PATH_SETTINGS }
        function Add-CfgSection([string]$title){
            $sLbl=New-Object Windows.Controls.TextBlock; $sLbl.Text=$title
            $sLbl.FontSize=9; $sLbl.FontWeight='Black'; $sLbl.Foreground=TAO_MAU '#005696'
            $sB=New-Object Windows.Controls.Border; $sB.Background=TAO_MAU '#EFF6FF'
            $sB.CornerRadius=[Windows.CornerRadius]::new(6); $sB.Padding=[Windows.Thickness]::new(10,5,10,5)
            $sB.Margin=[Windows.Thickness]::new(0,14,0,8); $sB.Child=$sLbl
            $global:e.Khung_Form_Cai_Dat_Chung.Children.Add($sB)|Out-Null
        }
        function Add-CfgRow([string]$section,[string]$key,[string]$val){
            $rG=New-Object Windows.Controls.Grid; $rG.Margin=[Windows.Thickness]::new(0,0,0,8)
            $rG.Tag="$section|$key"  # nhãn "section|key" (key GỐC lúc dựng form -- dùng để dò dòng, không dùng để đọc giá trị Key hiện tại nữa vì Key giờ có thể bị người dùng sửa)
            $cd1=New-Object Windows.Controls.ColumnDefinition; $cd1.Width=[Windows.GridLength]::new(130)
            $cd2=New-Object Windows.Controls.ColumnDefinition; $cd2.Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
            $rG.ColumnDefinitions.Add($cd1); $rG.ColumnDefinitions.Add($cd2)

            if($section-eq 'items'){
                # Riêng khu vực 'items': cho sửa CẢ tên Key (item1/item7) qua TextBox --
                # khác 3 khu vực còn lại, nơi Key cố định do code đọc thẳng bằng tên
                # (vd $global:CFG.urls['mag']), nên chỉ hiện Label tĩnh, không cho sửa Key.
                $kTB=New-Object Windows.Controls.TextBox; $kTB.Text=$key; $kTB.Tag='key'
                $kTB.FontFamily=New-Object Windows.Media.FontFamily 'Courier New'; $kTB.FontSize=11; $kTB.FontWeight='Bold'
                $kTB.Padding=[Windows.Thickness]::new(8,7,8,7)
                $kTB.BorderBrush=TAO_MAU '#E2E8F0'; $kTB.BorderThickness=[Windows.Thickness]::new(1.5)
                $kTB.Background=TAO_MAU '#F8FAFC'; $kTB.Foreground=TAO_MAU '#475569'
                [Windows.Controls.Grid]::SetColumn($kTB,0); $rG.Children.Add($kTB)|Out-Null
            } else {
                $kLbl=New-Object Windows.Controls.TextBlock; $kLbl.Text=$key; $kLbl.FontSize=11; $kLbl.FontWeight='Bold'
                $kLbl.Foreground=TAO_MAU '#475569'; $kLbl.VerticalAlignment='Center'
                [Windows.Controls.Grid]::SetColumn($kLbl,0); $rG.Children.Add($kLbl)|Out-Null
            }

            $vTB=New-Object Windows.Controls.TextBox; $vTB.Text=$val; $vTB.Tag='value'
            $vTB.FontFamily=New-Object Windows.Media.FontFamily 'Courier New'; $vTB.FontSize=11
            $vTB.Padding=[Windows.Thickness]::new(8,7,8,7); $vTB.Margin=[Windows.Thickness]::new(8,0,0,0)
            $vTB.BorderBrush=TAO_MAU '#E2E8F0'; $vTB.BorderThickness=[Windows.Thickness]::new(1.5)
            $vTB.Background=TAO_MAU '#F8FAFC'
            [Windows.Controls.Grid]::SetColumn($vTB,1); $rG.Children.Add($vTB)|Out-Null
            $global:e.Khung_Form_Cai_Dat_Chung.Children.Add($rG)|Out-Null
        }
        # Brand/Item -- 2 dòng CỐ ĐỊNH (item1/item7), chỉ đổi ô tên Key từ Label sang TextBox
        Add-CfgSection 'Loại sản phẩm / Cấu hình item'
        foreach($k in $global:CFG.items.Keys){ Add-CfgRow 'items' $k ([string]$global:CFG.items[$k]) }
        # System config
        Add-CfgSection 'Tham số hệ thống'
        foreach($k in $global:CFG.config.Keys){
            if($k -eq 'enable_log'){ continue }   # Đã có công tắc riêng (CheckBox_Bat_Ghi_Log), không hiện lại ở đây
            Add-CfgRow 'config' $k ([string]$global:CFG.config[$k])
        }
        # URL params
        Add-CfgSection 'Tham số URL'
        foreach($k in $global:CFG.url_params.Keys){ Add-CfgRow 'url_params' $k ([string]$global:CFG.url_params[$k]) }
        # URLs
        Add-CfgSection 'Cấu hình URL kết nối'
        foreach($k in $global:CFG.urls.Keys){ Add-CfgRow 'urls' $k ([string]$global:CFG.urls[$k]) }

    } catch {
        GHI_LOG "Lỗi hàm XAY_DUNG_FORM_CAU_HINH: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}
function LUU_CAU_HINH_CHUNG {
    try {
        # 'items' xử lý riêng: đọc CẢ Key hiện tại (có thể vừa bị sửa) lẫn Value từ 2
        # TextBox của mỗi dòng, gom vào 1 hashtable tạm rồi GHI ĐÈ TOÀN BỘ CFG.items --
        # cách này xử lý đúng cả trường hợp đổi tên Key (nếu đọc theo Tag "section|key"
        # cũ như trước đây sẽ vẫn dùng tên Key GỐC lúc mở form, không thấy tên mới).
        $itemsMoi=[ordered]@{}
        foreach($rG in $global:e.Khung_Form_Cai_Dat_Chung.Children){
            if($rG -isnot [Windows.Controls.Grid] -or -not $rG.Tag){continue}
            $tagParts=($rG.Tag-as [string]).Split('|')
            if($tagParts.Count-ne 2){continue}
            $section=$tagParts[0]
            if($section-eq 'items'){
                $keyMoi=$null; $valMoi=$null
                foreach($ctrl in $rG.Children){
                    if($ctrl -isnot [Windows.Controls.TextBox]){continue}
                    if($ctrl.Tag-eq 'key'){$keyMoi=$ctrl.Text.Trim()}
                    elseif($ctrl.Tag-eq 'value'){$valMoi=$ctrl.Text.Trim()}
                }
                if(-not [string]::IsNullOrWhiteSpace($keyMoi)){ $itemsMoi[$keyMoi]=$valMoi }
                continue
            }
            $key=$tagParts[1]
            foreach($ctrl in $rG.Children){
                if($ctrl -isnot [Windows.Controls.TextBox] -or $ctrl.Tag-ne 'value'){continue}
                $val=$ctrl.Text.Trim()
                switch($section){
                    'config'    {
                        # QUAN TRỌNG: mục 'config' chứa CẢ giá trị số (max_retry, retry_delay,
                        # gap_time_min, length_panel, refresh) LẪN giá trị chuỗi (folder_data,
                        # folder_database...). Trước đây luôn ép TryParse([double]) rồi gán $dv
                        # bất kể parse có thành công hay không -- nếu $val không phải số hợp lệ
                        # (vd đường dẫn "D:Data"), TryParse thất bại và $dv giữ nguyên 0.0 lúc
                        # khởi tạo, khiến chuỗi bị ÂM THẦM GHI ĐÈ THÀNH 0 mỗi lần bấm Lưu.
                        # Sửa: chỉ lưu dạng số khi parse thành công, còn lại giữ NGUYÊN VĂN
                        # chuỗi người dùng đã nhập trong ô (giống cách 'url_params'/'urls' đang làm).
                        # RIÊNG folder_data/folder_database: LUÔN lưu dạng chuỗi, KHÔNG cho qua
                        # TryParse([double]) dù giá trị người dùng gõ có VÔ TÌNH toàn là số (vd
                        # gõ nhầm "0") -- 2 khoá này giờ quyết định đường dẫn ổ đĩa thật (dùng
                        # bởi KHOI_TAO_BIEN để dò DATA_DIR/DATABASE_DIR), nên không được phép
                        # biến thành kiểu double dưới bất kỳ tình huống nào.
                        if ($key -eq 'folder_data' -or $key -eq 'folder_database') {
                            $global:CFG.config[$key] = $val
                        } else {
                            $dv=0.0
                            if([double]::TryParse($val,[ref]$dv)){ $global:CFG.config[$key]=$dv }
                            else{ $global:CFG.config[$key]=$val }
                        }
                    }
                    'url_params'{ $global:CFG.url_params[$key]=$val }
                    'urls'      { $global:CFG.urls[$key]=$val }
                }
            }
        }
        $global:CFG.items.Clear()
        foreach($k in $itemsMoi.Keys){ $global:CFG.items[$k]=$itemsMoi[$k] }

        # Công tắc "Ghi log hệ thống" -- đọc riêng (không nằm trong vòng lặp danh sách
        # config động ở trên). Ghi vào $global:TRANG_THAI_DUNG_CHUNG (hashtable đồng bộ
        # hoá, xem GHI_LOG trong Support.psm1) để áp dụng NGAY LẬP TỨC cho CẢ UI thread
        # LẪN Runspace nền -- không cần đợi Runspace nền tự đọc lại SETTINGS.db ở chu kỳ
        # sau. $global:LOG_ENABLE vẫn được cập nhật song song để tương thích các chỗ khác
        # còn đọc biến này, và lưu xuống config.enable_log để lần MỞ APP SAU nhớ đúng.
        if ($global:e.CheckBox_Bat_Ghi_Log) {
            $ghiLogMoi = [bool]$global:e.CheckBox_Bat_Ghi_Log.IsChecked
            $global:LOG_ENABLE = $ghiLogMoi
            $global:CFG.config['enable_log'] = $ghiLogMoi
            if ($global:TRANG_THAI_DUNG_CHUNG -is [hashtable]) {
                $global:TRANG_THAI_DUNG_CHUNG['GhiLogBat'] = $ghiLogMoi
            }
        }

        # Ô "Đường dẫn SETTINGS.db chuẩn" -- đọc riêng, KHÔNG nằm trong SETTINGS.db (ghi
        # vào D:\OTMS\Info.xml, đọc TRƯỚC CẢ KHI SETTINGS.db đọc được -- xem
        # Variable.psm1). CHỈ ghi Info.xml khi giá trị THỰC SỰ thay đổi so với đường dẫn
        # đang dùng, tránh ghi đè vô ích mỗi lần bấm Lưu. Áp dụng từ lần MỞ APP KẾ TIẾP
        # (không đổi $global:PATH_SETTINGS của phiên đang chạy).
        if ($global:e.O_Nhap_Duong_Dan_Settings) {
            $duongDanMoi = $global:e.O_Nhap_Duong_Dan_Settings.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($duongDanMoi) -and $duongDanMoi -ne $global:PATH_SETTINGS) {
                try { GHI_INFO_XML $duongDanMoi } catch { GHI_LOG "Lỗi lưu đường dẫn SETTINGS.db (Info.xml): $($_.Exception.Message)" 'ERROR' }
            }
        }

        try{
            LUU_SETTINGS_DB
            $global:e.Label_Da_Luu_Thanh_Cong.Visibility='Visible'
            $t=New-Object System.Windows.Threading.DispatcherTimer
            $t.Interval=[TimeSpan]::FromSeconds(2)
            $t.Add_Tick({$global:e.Label_Da_Luu_Thanh_Cong.Visibility='Collapsed';$t.Stop()}.GetNewClosure())
            $t.Start()
        } catch {
            [System.Windows.MessageBox]::Show("Lỗi lưu SETTINGS.db: $_",'Error','OK','Error')|Out-Null
        }
        DONG_LOP_PHU $global:e.Lop_Phu_Cai_Dat_Chung; VE_TRANG_CHU

    } catch {
        GHI_LOG "Lỗi hàm LUU_CAU_HINH_CHUNG: $($_.Exception.Message) | Dòng: $($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    }
}

# ================================================================
# XUẤT HÀM RA NGOÀI MODULE
# ================================================================
Export-ModuleMember -Function XAY_DUNG_FORM_CAU_HINH, LUU_CAU_HINH_CHUNG
