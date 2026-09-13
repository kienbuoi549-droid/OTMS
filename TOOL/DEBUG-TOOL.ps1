# ================================================================
# DEBUG-TOOL.ps1 -- Cong cu doc lap de xem/sua/luu cac file .db (ma hoa
# AES+GZip) cua du an OTMSAnalyzer V10, hoac bat ky file JSON/XML thuong nao.
# Tu dong to mau theo CAP LONG NHAU (depth), thut le ro rang, cho phep
# COPY va SUA TAY truc tiep trong khung soan thao, roi LUU lai (tu dong
# ma hoa lai neu file goc dang ma hoa).
#
# CACH CHAY:
#   powershell.exe -ExecutionPolicy Bypass -File DEBUG-TOOL.ps1
#
# LUU Y: day la cong cu DEBUG, KHONG co xac nhan/validate truoc khi luu --
# ban tu chiu trach nhiem noi dung sua co dung dinh dang khong truoc khi
# ghi de len file that (dac biet la Active.db/MO.db dang duoc app chinh
# dung song song). Nen "Luu" ra 1 ban COPY de test truoc khi ghi de file goc.
# ================================================================
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ================================================================
# KHOA AES + IV -- Y HET Variable.psm1 cua OTMSAnalyzer, KHONG duoc doi
# ================================================================
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

# ================================================================
# HAM MA HOA / GIAI MA / NEN / GIAI NEN -- port nguyen tu Database.psm1
# ================================================================
function NEN_GZIP([byte[]]$data) {
    $ms = New-Object System.IO.MemoryStream
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
    $gz.Write($data, 0, $data.Length)
    $gz.Close()
    return $ms.ToArray()
}
function GIAI_NEN_GZIP([byte[]]$data) {
    $src = New-Object System.IO.MemoryStream(,$data)
    $gz  = New-Object System.IO.Compression.GZipStream($src, [System.IO.Compression.CompressionMode]::Decompress)
    $dst = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 4096
    do { $n = $gz.Read($buf, 0, $buf.Length); if ($n -gt 0) { $dst.Write($buf, 0, $n) } } while ($n -gt 0)
    $gz.Close()
    return $dst.ToArray()
}
function MA_HOA_AES([byte[]]$data) {
    $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
    $aes.KeySize = 256; $aes.BlockSize = 128
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $global:AES_KEY; $aes.IV = $global:AES_IV
    $enc = $aes.CreateEncryptor()
    $ms  = New-Object System.IO.MemoryStream
    $cs  = New-Object System.Security.Cryptography.CryptoStream($ms, $enc, [System.Security.Cryptography.CryptoStreamMode]::Write)
    $cs.Write($data, 0, $data.Length)
    $cs.FlushFinalBlock()
    $cs.Close(); $aes.Dispose()
    return $ms.ToArray()
}
function GIAI_MA_AES([byte[]]$data) {
    $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
    $aes.KeySize = 256; $aes.BlockSize = 128
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $global:AES_KEY; $aes.IV = $global:AES_IV
    $dec = $aes.CreateDecryptor()
    $ms  = New-Object System.IO.MemoryStream(,$data)
    $cs  = New-Object System.Security.Cryptography.CryptoStream($ms, $dec, [System.Security.Cryptography.CryptoStreamMode]::Read)
    $dst = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 4096
    do { $n = $cs.Read($buf, 0, $buf.Length); if ($n -gt 0) { $dst.Write($buf, 0, $n) } } while ($n -gt 0)
    $cs.Close(); $aes.Dispose()
    return $dst.ToArray()
}

# ================================================================
# NHAN DANG DINH DANG (JSON / XML / UNKNOWN)
# ================================================================
function PHAT_HIEN_DINH_DANG([string]$text) {
    $t = $text.TrimStart()
    if ($t.StartsWith('{') -or $t.StartsWith('[')) { return 'JSON' }
    if ($t.StartsWith('<')) { return 'XML' }
    return 'UNKNOWN'
}

# ================================================================
# DINH DANG LAI (PRETTY-PRINT) CO THUT LE NHAT QUAN
# ================================================================
function DINH_DANG_JSON_DEP([string]$text) {
    $obj = $text | ConvertFrom-Json
    return ($obj | ConvertTo-Json -Depth 40)
}
function DINH_DANG_XML_DEP([string]$text) {
    $xmlDoc = New-Object System.Xml.XmlDocument
    $xmlDoc.PreserveWhitespace = $false
    $xmlDoc.LoadXml($text)
    $sw = New-Object System.IO.StringWriter
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.OmitXmlDeclaration = $false
    $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
    $xmlDoc.Save($xw)
    $xw.Close()
    return $sw.ToString()
}

# ── Xac dinh DO SAU (depth) cua tung dong dua tren so dau cach dau dong,
# tu do phat hien don vi thut le (khong hardcode, tranh sai lech giua cac
# phien ban PowerShell/ConvertTo-Json khac nhau). ──
function LAY_DANH_SACH_DONG_CO_DO_SAU([string]$textDaThutLe) {
    $dongList = $textDaThutLe -split "`r`n|`n"
    $donVi = 0
    foreach ($d in $dongList) {
        $soDauCach = $d.Length - $d.TrimStart(' ').Length
        if ($soDauCach -gt 0) { $donVi = $soDauCach; break }
    }
    if ($donVi -le 0) { $donVi = 2 }

    $ketQua = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($d in $dongList) {
        $soDauCach = $d.Length - $d.TrimStart(' ').Length
        $doSau = [Math]::Floor($soDauCach / $donVi)
        $ketQua.Add(@{ depth = $doSau; text = $d })
    }
    return $ketQua
}

# ================================================================
# TO MAU VAO RichTextBox THEO DO SAU -- moi dong 1 mau theo cap long nhau,
# lap lai vong mau khi qua sau. TextBox thuong KHONG to mau tung phan duoc,
# nen bat buoc dung RichTextBox (van sua tay/copy binh thuong).
# ================================================================
$global:BangMauTheoDoSau = @('#4FC1FF','#6A9955','#DCB67A','#C586C0','#F48771','#4EC9B0','#CE9178','#9CDCFE')

function TO_MAU_VAO_RICHTEXTBOX($rtb, $dongList) {
    $flowDoc = New-Object Windows.Documents.FlowDocument
    $flowDoc.PagePadding = New-Object Windows.Thickness(0)
    foreach ($dong in $dongList) {
        $para = New-Object Windows.Documents.Paragraph
        $para.Margin = New-Object Windows.Thickness(0)
        $run = New-Object Windows.Documents.Run($dong.text)
        $mauHex = $global:BangMauTheoDoSau[[int]$dong.depth % $global:BangMauTheoDoSau.Count]
        $run.Foreground = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($mauHex))
        $para.Inlines.Add($run)
        $flowDoc.Blocks.Add($para)
    }
    $rtb.Document = $flowDoc
}
function HIEN_THI_THO($rtb, [string]$text) {
    $flowDoc = New-Object Windows.Documents.FlowDocument
    $flowDoc.PagePadding = New-Object Windows.Thickness(0)
    $dongList = $text -split "`r`n|`n"
    foreach ($d in $dongList) {
        $para = New-Object Windows.Documents.Paragraph
        $para.Margin = New-Object Windows.Thickness(0)
        $run = New-Object Windows.Documents.Run($d)
        $run.Foreground = New-Object Windows.Media.SolidColorBrush([Windows.Media.Colors]::Gainsboro)
        $para.Inlines.Add($run)
        $flowDoc.Blocks.Add($para)
    }
    $rtb.Document = $flowDoc
}

# ================================================================
# GIAO DIEN (XAML) -- luon toan man hinh (Maximized + khong cho resize ve
# dang nho hon), nen toi de tuong phan tot voi mau to theo cap long nhau
# ================================================================
[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DEBUG-TOOL -- OTMSAnalyzer"
        WindowState="Maximized"
        ResizeMode="CanMinimize"
        Background="#1E1E1E"
        FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="BtnToolbar" TargetType="Button">
      <Setter Property="Background" Value="#0E639C"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1177BB"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#3C3C3C"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <DockPanel>
    <!-- TOOLBAR -->
    <Border DockPanel.Dock="Top" Background="#2D2D30" Padding="14,10" BorderBrush="#3F3F46" BorderThickness="0,0,0,1">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="Button_Mo_File" Content="Mở file..." Style="{StaticResource BtnToolbar}"/>
        <Button x:Name="Button_Luu_File" Content="Lưu file..." Style="{StaticResource BtnToolbar}"/>
        <Border Width="1" Background="#3F3F46" Margin="4,0,14,0"/>
        <TextBlock x:Name="Label_Duong_Dan" Text="Chưa mở file nào" FontSize="12" Foreground="#CCCCCC" VerticalAlignment="Center"/>
      </StackPanel>
    </Border>

    <!-- STATUS BAR -->
    <Border DockPanel.Dock="Bottom" Background="#007ACC" Padding="14,5">
      <TextBlock x:Name="Label_Trang_Thai" Text="Sẵn sàng" FontSize="11" Foreground="White"/>
    </Border>

    <!-- KHUNG SOAN THAO CHINH -->
    <Border Background="#1E1E1E" Padding="4">
      <RichTextBox x:Name="Rtb_NoiDung"
                   Background="#1E1E1E" Foreground="#D4D4D4"
                   FontFamily="Consolas" FontSize="14"
                   BorderThickness="0"
                   VerticalScrollBarVisibility="Auto"
                   HorizontalScrollBarVisibility="Auto"
                   AcceptsReturn="True" AcceptsTab="True"
                   IsUndoEnabled="True">
        <RichTextBox.Resources>
          <Style TargetType="Paragraph">
            <Setter Property="Margin" Value="0"/>
          </Style>
        </RichTextBox.Resources>
      </RichTextBox>
    </Border>
  </DockPanel>
</Window>
'@

# ================================================================
# NAP GIAO DIEN + LAY THAM CHIEU CAC PHAN TU
# ================================================================
$reader = New-Object System.Xml.XmlNodeReader $Xaml
$global:W = [Windows.Markup.XamlReader]::Load($reader)

$global:e = @{
    Button_Mo_File   = $global:W.FindName('Button_Mo_File')
    Button_Luu_File  = $global:W.FindName('Button_Luu_File')
    Label_Duong_Dan  = $global:W.FindName('Label_Duong_Dan')
    Label_Trang_Thai = $global:W.FindName('Label_Trang_Thai')
    Rtb_NoiDung      = $global:W.FindName('Rtb_NoiDung')
}

$global:FileDangMo     = $null
$global:DaMaHoaLucMo   = $false
$global:DinhDangDangMo = 'UNKNOWN'

# [CHAN DOAN] Hien Apartment State cua luong hien tai ngay khi mo tool -- neu
# ghi "MTA" thay vi "STA", day chinh la nguyen nhan OpenFileDialog/SaveFileDialog
# bao loi khi chay tu ban .exe da nen (COM-based dialog bat buoc can STA).
$global:TrangThaiLuong = [System.Threading.Thread]::CurrentThread.GetApartmentState()
$global:e.Label_Trang_Thai.Text = "San sang | Apartment State cua luong hien tai: $global:TrangThaiLuong $(if($global:TrangThaiLuong -ne 'STA'){'-- CANH BAO: can STA de dung hop thoai file, xem lai co dung -STA khi nen exe khong'}else{'(dung, se mo file duoc)'})"

# ================================================================
# XU LY NUT "MO FILE"
# ================================================================
function XU_LY_MO_FILE {
    try {
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Database files (*.db)|*.db|JSON files (*.json)|*.json|XML files (*.xml)|*.xml|Tat ca file (*.*)|*.*'
        $dlg.Title  = 'Chon file de mo'
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot) -and (Test-Path $PSScriptRoot)) {
            $dlg.InitialDirectory = $PSScriptRoot
        }

        $ok = $dlg.ShowDialog()
        if ($ok -ne $true) { return }

        $duongDan = $dlg.FileName
        $rawBytes = [System.IO.File]::ReadAllBytes($duongDan)

        # Thu giai ma AES+GZip truoc (dinh dang .db chuan cua OTMSAnalyzer) --
        # neu that bai (vd file JSON/XML thuong, khong ma hoa) thi doc thang UTF8.
        $noiDung = $null
        $daMaHoa = $false
        try {
            $giaiMa  = GIAI_MA_AES $rawBytes
            $giaiNen = GIAI_NEN_GZIP $giaiMa
            $ungVien = [System.Text.Encoding]::UTF8.GetString($giaiNen)
            if ([string]::IsNullOrWhiteSpace($ungVien)) { throw 'Noi dung giai ma rong' }
            $noiDung = $ungVien
            $daMaHoa = $true
        } catch {
            $noiDung = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            $daMaHoa = $false
        }

        $global:FileDangMo   = $duongDan
        $global:DaMaHoaLucMo = $daMaHoa

        $dinhDang = PHAT_HIEN_DINH_DANG $noiDung
        $ghiChuLoi = ''
        try {
            switch ($dinhDang) {
                'JSON' {
                    $depText  = DINH_DANG_JSON_DEP $noiDung
                    $dongList = LAY_DANH_SACH_DONG_CO_DO_SAU $depText
                    TO_MAU_VAO_RICHTEXTBOX $global:e.Rtb_NoiDung $dongList
                }
                'XML' {
                    $depText  = DINH_DANG_XML_DEP $noiDung
                    $dongList = LAY_DANH_SACH_DONG_CO_DO_SAU $depText
                    TO_MAU_VAO_RICHTEXTBOX $global:e.Rtb_NoiDung $dongList
                }
                default {
                    HIEN_THI_THO $global:e.Rtb_NoiDung $noiDung
                }
            }
        } catch {
            # Parse/dinh dang lai that bai (vd JSON/XML trong file khong hop le)
            # -- van hien THO, khong chan nguoi dung xem noi dung.
            HIEN_THI_THO $global:e.Rtb_NoiDung $noiDung
            $ghiChuLoi = " (loi parse: $($_.Exception.Message) -- dang hien THO)"
        }

        $global:DinhDangDangMo = $dinhDang
        $global:e.Label_Duong_Dan.Text = $duongDan
        $global:e.Label_Trang_Thai.Text = "Da mo | Dinh dang: $dinhDang$ghiChuLoi | Ma hoa: $(if($daMaHoa){'CO'}else{'KHONG'}) | $((Get-Date).ToString('HH:mm:ss'))"
    } catch {
        [System.Windows.MessageBox]::Show("Loi mo file:`n$($_.Exception.Message)", 'Loi', 'OK', 'Error') | Out-Null
    }
}

# ================================================================
# XU LY NUT "LUU FILE"
# ================================================================
function XU_LY_LUU_FILE {
    try {
        if (-not $global:FileDangMo) {
            [System.Windows.MessageBox]::Show('Chua mo file nao de luu.', 'Thong bao', 'OK', 'Warning') | Out-Null
            return
        }

        $textRange  = New-Object Windows.Documents.TextRange($global:e.Rtb_NoiDung.Document.ContentStart, $global:e.Rtb_NoiDung.Document.ContentEnd)
        $noiDungMoi = $textRange.Text.TrimEnd("`r", "`n")

        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.FileName         = [System.IO.Path]::GetFileName($global:FileDangMo)
        $dlg.InitialDirectory = [System.IO.Path]::GetDirectoryName($global:FileDangMo)
        $dlg.Filter = 'Database files (*.db)|*.db|JSON files (*.json)|*.json|XML files (*.xml)|*.xml|Tat ca file (*.*)|*.*'
        $dlg.Title  = 'Luu file (mac dinh trung ten/vi tri file da mo -- doi neu muon luu ra ban khac)'

        $ok = $dlg.ShowDialog()
        if ($ok -ne $true) { return }

        $duongDanLuu = $dlg.FileName

        if ($global:DaMaHoaLucMo) {
            $rawBytes   = [System.Text.Encoding]::UTF8.GetBytes($noiDungMoi)
            $nenBytes   = NEN_GZIP $rawBytes
            $maHoaBytes = MA_HOA_AES $nenBytes
            [System.IO.File]::WriteAllBytes($duongDanLuu, $maHoaBytes)
        } else {
            [System.IO.File]::WriteAllText($duongDanLuu, $noiDungMoi, [System.Text.Encoding]::UTF8)
        }

        $global:e.Label_Trang_Thai.Text = "Da luu: $duongDanLuu | $((Get-Date).ToString('HH:mm:ss'))"
        [System.Windows.MessageBox]::Show("Da luu thanh cong:`n$duongDanLuu", 'Thanh cong', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show("Loi luu file:`n$($_.Exception.Message)", 'Loi', 'OK', 'Error') | Out-Null
    }
}

# ================================================================
# GAN SU KIEN + HIEN CUA SO
# ================================================================
$global:e.Button_Mo_File.Add_Click({
    try { XU_LY_MO_FILE }
    catch { [System.Windows.MessageBox]::Show("Loi ngoai du kien khi mo file:`n$($_.Exception.Message)", 'Loi', 'OK', 'Error') | Out-Null }
})
$global:e.Button_Luu_File.Add_Click({
    try { XU_LY_LUU_FILE }
    catch { [System.Windows.MessageBox]::Show("Loi ngoai du kien khi luu file:`n$($_.Exception.Message)", 'Loi', 'OK', 'Error') | Out-Null }
})

[void]$global:W.ShowDialog()
