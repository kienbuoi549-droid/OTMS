#Requires -Version 5.1
<#
============================================================================
 TimKiemNangCao_V9.ps1
============================================================================
 THAY DOI RIENG CUA V9 - DOI CHIEU TUNG THUOC TINH CSS CUA BAN HTML VOI
 XAML (9A yeu cau clone 100% cho nut/dropdown/toggle/checkbox, khong chi
 mau sac ma ca cac TRANG THAI TUONG TAC dang bi thieu hoan toan):
   1. Nut dong (X): them trang thai :active (bam giu -> nen dam hon
      #1C000000) - truoc chi co hover, thieu han pressed.
   2. ComboBox (Type): sua BorderBrush ve dung #1A000000 (0.1 opacity,
      truoc dung nham #1F000000); them Height=26, MinWidth=138 (bo Width
      co dinh 130), FontSize 13 (truoc 12.5) dung theo CSS; them shadow
      day nhe; them han TRANG THAI :focus (vien xanh + glow) - truoc
      KHONG CO GI ca khi focus.
   3. Segmented (Ca): them Height=26 cho khung ngoai; them khoang cach 1px
      giua 3 nut; sua FontWeight nen tang tu Normal sang Medium (dung CSS
      goc co san font-weight:500 tren MOI nut, khong rieng active); BO
      FontWeight=SemiBold tung tu them rieng cho nut active (CSS KHONG lam
      dam nut active, chi doi mau/nen - day la chi tiet em tu suy dien
      them, khong co trong ban goc); them han TRANG THAI hover cho nut
      chua active (truoc khong doi gi khi ruot chuot qua); them shadow nhe
      cho nut active (mo phong 2 lop box-shadow cua CSS bang 1
      DropShadowEffect, WPF khong xep chong nhieu shadow tren 1 phan tu
      duoc).
   4. Checkbox: them trang thai :focus-visible (vien khi dieu huong bang
      phim Tab) - truoc thieu hoan toan.
 Luu y ky thuat: WPF khong the xep chong NHIEU box-shadow tren cung 1
 phan tu nhu CSS (bd co dinh dang double-shadow o nut active cua ban HTML)
 - da mo phong bang 1 DropShadowEffect duy nhat, gan giong nhung khong the
 100% tuyet doi ve mat ky thuat render; tat ca thuoc tinh do duoc (mau,
 kich thuoc, khoang cach, font-weight, cac trang thai tuong tac) da doi
 chieu va sua dung tung gia tri.

 THAY DOI RIENG CUA V8 - QUET NHIEU FILE THEO KHOANG NGAY (9A xac nhan
 cach tim file cua V1..V7 sai - dung 2 duong dan co dinh la SAI hoan toan
 so voi thuc te):
   - Thu muc du lieu THAT: D:\OTMS\Data\Database (co dinh, khong con dua
     theo $PSScriptRoot cua script nua).
   - File ngay dinh dang co dinh yyyymmdd.db, TEN file thi KHONG co dinh
     (ham moi TAO_DUONG_DAN_FILE_NGAY ghep dung ten tu 1 [DateTime]).
     Active.db la file RIENG, luon doc, khong theo ten ngay.
   - So luong file can doc PHU THUOC [Tu ngay]<->[Den ngay] chon tren UI:
     NAP_DU_LIEU_TIM_KIEM gio quet TUNG NGAY trong khoang (2 dau bao gom),
     ngay nao khong co file (nha may khong chay ngay do) thi bo qua im
     lang, khong bao loi. Active.db van luon doc + cong them nhu cycle moi
     (dung quy tac 9A da chot truoc do), KHONG phu thuoc khoang ngay dang
     chon.
   - Kien truc doi tu "nap 1 lan luc mo cua so, sau do chi loc" sang "nap
     LAI moi khi doi Tu ngay/Den ngay" (ham moi NAP_LAI_DU_LIEU, goi luc
     mo cua so VA moi lan SelectedDateChanged cua 2 DatePicker). Mac dinh
     luc mo cua so: ca Tu ngay/Den ngay = HOM NAY (khong con "do tu du
     lieu da nap" nhu truoc, vi gio thu tu la NGAY CHON TRUOC, du lieu nap
     SAU, khong lam nguoc lai duoc nua).
   - Dropdown Type gio giu lai lua chon cu khi doi ngay (neu type do van
     con trong du lieu moi nap), thay vi luon reset ve "Tat ca".
   - Co gioi han mem 366 ngay/lan quet (GIOI_HAN_SO_NGAY_QUET) de tranh
     truong hop chon nham khoang qua rong (vd nham nam) lam UI cham/dung.
   - Da kiem tra rieng co che quet (ghep ten file, loc theo khoang, bo qua
     file khong ton tai) bang Python tren thu muc mo phong - dung nhu ky
     vong.

 THAY DOI RIENG CUA V7 - 9A HOI VE HANH VI CO GIAN COT: cot checkbox
 (34px) + Finish (105px) trong table raw co dinh, con Col1/Col2 (Type/
 Oven-Batch) dat Width="*" - khi table details hien len, cot chua table
 raw trong gridResults co lai tu ~100% xuong con ~56% (ti le 1.3*:1*),
 khien 2 cot * do co theo, chu (nhat la Batch ID kieu "ATTIS-00104-01-03")
 co the bi bop chat kho doc.
 Sua: them MinWidth cho Col1/Col2 (ca table raw lan table details) - dung
 nguong hop ly theo dung noi dung THAT su chua (Col1 luon la Type, ngan;
 Col2 tro len la Oven/Batch ID hoac Magaziner ID, dai hon). Duoi nguong do
 DataGrid tu dong hien thanh cuon ngang (da bat ro rang ScrollViewer.
 HorizontalScrollBarVisibility="Auto", khong con phu thuoc gia dinh ve
 mac dinh cua WPF) thay vi bop chu kho doc.

 THAY DOI RIENG CUA V6 - VAN "TABLE DETAILS KHONG HIEN THI" SAU CA V5 (co
 loi ro rang tu try/catch nhung 9A van khong thay gi) => nghia la loi
 KHONG nam trong 5 ham CHI_TIET_* (khong roi vao catch), ma nam SOM HON:
 rat co the do TwoWay binding "IsChecked" tren CheckBox (nam trong
 DataGridTemplateColumn) KHONG ghi nguoc dang tin cay vao PSCustomObject -
 PSCustomObject khong phai 1 class C# thuan voi property chuan, ghi qua
 binding co the khong hoat dong dung nhu ky vong trong moi truong hop. Hau
 qua: CAP_NHAT_CHI_TIET luon doc thay MOI dong co IsChecked=false (du da
 tich tren giao dien), tu dong an het khung Chi tiet - dung boi try/catch
 vi khong co gi loi ca, chi la "0 dong duoc tich" (dung logic, sai du lieu
 dau vao).
 Sua tan goc - KHONG con phu thuoc TwoWay binding de biet dong nao duoc
 tich:
   - Them VirtualizingPanel.IsVirtualizing="False" cho dgRaw - bat buoc de
     MOI dong (ke ca dong da cuon ra ngoai man hinh) van giu container
     UI that, khong bi "ao hoa" mat container.
   - Ham moi LAY_HANG_DA_TICH: doc TRUC TIEP thuoc tinh IsChecked cua
     CheckBox THAT tren giao dien qua ItemContainerGenerator + duyet cay
     hien thi (VisualTreeHelper), thay vi doc $r.IsChecked tren du lieu.
     CAP_NHAT_CHI_TIET doi sang goi ham nay - khong con tin vao binding
     ghi nguoc nua, luon dung 100% voi nhung gi dang hien tren man hinh.
   - Them luoi an toan thu 2: bat them su kien Mouse.MouseUpEvent (khong
     phai MouseLeftButtonUpEvent - su kien rieng theo nut chuot trong WPF
     mac dinh KHONG bubble, chi Mouse.MouseUpEvent chung moi bubble) tren
     ca DataGrid, goi lai CAP_NHAT_CHI_TIET moi lan co thao tac chuot bat
     ky trong bang - vo hai du co goi thua (chi la tinh lai, khong doi
     ket qua) nhung dam bao khong bao gio "bo lot" 1 lan tich do nghi ngo
     rieng ve Checked/Unchecked cua ToggleButton co bubble hay khong.

 THAY DOI RIENG CUA V5 - SUA "TABLE DETAILS KHONG HIEN THI":
   1. NGHI NGO CHINH: file dang luu UTF-8 KHONG CO BOM. Windows PowerShell
      5.1 (khac PowerShell Core/pwsh) doc file .ps1 khong BOM co the tu
      doan nham sang bang ma ANSI he thong thay vi UTF-8, lam hong cac ky
      tu dac biet (gach dai em-dash, mui ten, dau X...) - co the gay loi
      am tham dung o buoc dung table details. Sua: luu lai file voi UTF-8
      CO BOM (chuan duoc Windows PowerShell 5.1 nhan dung tuyet doi).
   2. Bo het em-dash '—' dung lam o trong (Magaziner) trong du lieu hien
      thi, doi sang chuoi ASCII thuan '(trong)' - giam rui ro encoding o
      dung cho la DU LIEU (khong chi giao dien), phong truong hop con
      nguyen nhan encoding nao khac ngoai BOM.
   3. Boc try/catch quanh toan bo 5 ham CHI_TIET_* trong CAP_NHAT_CHI_TIET:
      truoc day neu ham nao loi (bat ky nguyen nhan gi) se lam khung Chi
      tiet trong khong ro ly do. Gio neu loi se HIEN THI THONG BAO LOI
      THAT ngay trong bang (noi dung $_.Exception.Message) thay vi im
      lang - lan sau neu con van de gi, 9A chup man hinh dong loi do gui
      lai la em sua duoc ngay, khong phai doan mu nua.

 THAY DOI RIENG CUA V4 - 9A CHI RA V3 VAN LA DOAN MO (chua xac nhan) VA DAN
 DEN 1 VONG HOI-DAP LAI TU DAU DE CHOT DUNG CACH HIEN THI CUA CA 5 DINH
 DANG TIM KIEM. KET QUA:
   1. BO HAN logic "do trung Active theo finish" cua V3 - 9A xac nhan day
      la suy dien SAI: Oven ID/Magaziner/Model/Config trung nhau giua
      Active va file ngay la CHUYEN BINH THUONG (vd cung 1 magaziner vat
      ly duoc nap lai me khac), KHONG phai dau hieu de coi la "cung 1
      batch". Active LUON duoc cong them nhu 1 cycle MOI, dung dung quy
      tac goc tu V1 (cycle = max da archive +1), KHONG tu suy dien them
      gi nua. (Luu y: voi dung bo du lieu mau dang co, dieu nay nghia la
      2 dong "gia' - Search Model 2103-023000-90 se lai ra 2 dong panel
      R4DJ79N9G8TE6P giong het nhau nhu V1/V2 - 9A xac nhan day KHONG
      phai loi can sua, chi la dac diem cua dung bo mau nay.)
   2. Table raw CHUAN HOA lai thu tu cot cho CA 5 dinh dang thanh dung
      [tich][STT][Type][Oven/Batch][Finish] - truoc day Oven ID va Panel/
      Mpanel dang de Oven/Batch ra truoc Type, gio dao lai dung thu tu.
   3. Table details cua Oven ID search VIET LAI HOAN TOAN: truoc day liet
      ke tung Mpanel/Panel rieng le (sai) - gio GOP THEO MAGAZINER (1
      magaziner = 1 nhom), trong 1 nhom tach dong con theo dung CAP
      (Model, Config) khac nhau (giong Model+Config -> gop SIP; khac 1
      trong 2 -> tach dong rieng). STT + Magaziner ID chi hien o dong DAU
      cua nhom, cac dong con tiep theo de trong (mo phong o gop xuyen
      dong vi DataGrid khong ho tro row-span that).
   4. Textblock cua Model ID va Config ID search THEM o "Số Oven" (dem so
      Oven ID khac nhau) - 9A xac nhan can co, truoc day chi co Tổng SIP
      (Model ID) hoac Số Magaziner+Tổng SIP (Config ID).
 CA 5 dinh dang da duoc 9A xac nhan tung diem MOT qua hoi-dap truc tiep
 (khong con doan) truoc khi sua code lan nay - xem bang tong hop day du
 ngay truoc luc bat dau sua. Da doi chieu lai bang Python tren du lieu
 that (giai ma 2 file .db): tong batch dung lai 25 (Active luon cong,
 khong dedup), CHI_TIET_OVEN nhom dung theo tung Magaziner voi vi du thuc
 te co nhieu Mpanel khac Model/Config trong cung 1 magaziner.

 THAY DOI RIENG CUA V3 - SUA LOI DEM TRUNG BATCH TU ACTIVE.DB: 9A yeu cau
 doi chieu that ky lai toan bo kich ban query tu dau conversation. Chay lai
 dung du lieu that (giai ma 2 file .db, dung lai toan bo pipeline) phat
 hien V2 dang dem TRUNG mot phan du lieu, khong phai 1 truong hop rieng le
 ma la CA 6/6 oven trong Active.db: moi oven trong Active.db (mau dang co)
 co finish TRUNG KHOP TUYET DOI voi batch cuoi cung (cycle lon nhat) da
 archive cua dung oven+shift+ngay do (khong rieng EQOVN00104-01 nhu ban V1/
 V2 tung ghi chu - 5 oven PDTEST con lai cung trung, chi khong de y vi
 Items rong nen khong "nhin thay" duoc su trung lap qua noi dung).
 Hau qua truoc khi sua: MOI oven deu bi tao them 1 "batch ao" TRUNG voi
 batch da archive - Oven ID search ra du 1 dong thua; search theo Model/
 Config co the dem 1 panel/mpanel 2 LAN (vd search "2103-023000-90" +
 Type=ATTIS, tich het: SIP tong bi cong du 15, tu 603 thanh 618).
 Nguyen nhan goc: V1 tung tu quyet dinh "khong do trung, luon cong Active
 nhu 1 cycle moi" (9A CHUA TUNG xac nhan diem nay, chi la gia dinh rieng
 luc do) - gio co bang chung cu the la gia dinh do sai voi du lieu that.
 Sua: khi doc Active.db, neu OvenId+ShiftId+ShiftDate DA co 1 batch archive
 voi finish GIONG HET (cung giay) - coi la CUNG 1 lan nuong vat ly, BO QUA
 khong tao dong ao, khong cong cycle moi. Neu finish KHAC (oven that su
 dang chay lo moi, chua kip archive) thi van cong binh thuong nhu truoc.
 Da doi chieu lai bang Python (giai ma that 2 file .db, dung lai toan bo
 logic gop+loc+tim): tong batch giam tu 25 xuong 19 (dung 6 dong ao bi loai
 dung 6 oven), oven EQOVN00104-01 tim theo Oven ID gio ra dung 2 dong (truoc
 la 3), search Model 2103-023000-90 + Type=ATTIS tich het ra dung Tong SIP
 = 603 (truoc la 618, sai du 15).

 THAY DOI RIENG CUA V2 - DOC FILE .DB THAT (AES-256/CBC + GZip), khong con
 doc plaintext .txt: 4A gui MultiRequest_V7-7.txt (script ghi du lieu that,
 tu V7-1 da doi Active.xml/yyyymmdd.xml sang Active.db/yyyymmdd.db qua GHI_
 FILE_DB, copy nguyen tu Database.psm1 cua OTMSAnalyzer). Doi chieu file do
 xac nhan dung 1 dieu quan trong nhat con bo ngo tu dau: noi dung XML BEN
 TRONG file .db KHONG doi gi so voi schema o:OTMS/o:Shift/o:Oven/o:Batch da
 dung xuyen suot tu truoc - MultiRequest chi ghi $XmlDoc.OuterXml (dung cay
 XML da xay bang CreateElement/o:Oven/o:Batch nhu cac ban truoc) qua GHI_
 FILE_DB, KHONG phai 1 schema DataSet XML nao khac. Nen KHONG can doi bat
 ky ham parse/loc/gop nao (DOC_LAY_ITEMS, NAP_DU_LIEU_TIM_KIEM, 5 ham XD_
 RAW_*, 5 ham CHI_TIET_*... giu nguyen 100%) - chi them lop giai ma o dung
 1 diem da co san tu V1 (DOC_XML_TU_FILE).
   - Copy nguyen 4 ham NEN_GZIP/GIAI_NEN_GZIP/MA_HOA_AES/GIAI_MA_AES tu
     MultiRequest_V7-7.txt (giu dung ten ham) + ham DOC_FILE_DB (giai ma AES
     -> giai nen GZip -> UTF8). Khoa AES_KEY/AES_IV CO DINH, dung gia tri da
     xac nhan tu dau conversation (khop chinh xac voi byte array trong file
     4A vua gui - da doi chieu tung byte).
   - DOC_XML_TU_FILE (V1) doi tu Get-Content/Xml.Load truc tiep sang goi
     DOC_FILE_DB roi LoadXml() chuoi da giai ma. Day la NOI DUY NHAT bi doi
     trong toan bo VUNG du lieu/tim kiem.
   - Duong dan mac dinh doi tu Active.txt/20260711.txt sang Active.db/
     20260711.db (dung ten MultiRequest_V7-7 dang dung).
   - DA KIEM CHUNG round-trip bang Python (cung thuat toan AES-256-CBC/
     PKCS7 + GZip chuan, cung khoa/IV) tren dung noi dung 20260711.txt/
     Active.txt hien co: ma hoa roi giai ma lai ra Y HET ban goc. 2 file
     .db tao tu buoc kiem chung nay duoc gui kem de 4A test thu ngay ma
     khong can cho file that tu he thong.

 Ban dau tien (V1) cua chuc nang TIM KIEM NANG CAO, clone tu ban demo HTML
 da duoc 4A xac nhan (ca ve logic du lieu lan UI). Muc dich file nay: PORT
 dung 1-1 sang PowerShell 5.1 + WPF, KHONG doi logic nghiep vu da chot.

 PHAM VI CON LAI CHUA LAM (khong lien quan V3 nay):
   1. CHUA quet nhieu file theo khoang ngay (multi-file). Bo loc ngay/ca/
      type van hoat dong dung tren du lieu da nap, nhung "nap file nao" con
      dang co dinh 2 duong dan cau hinh o dau file - quet dong theo khoang
      ngay (tu 4A tung xac nhan: doanh gioi ngay quyet dinh SO FILE can
      doc) se la buoc tiep theo tu nhien.
   2. Day la SCRIPT DOC LAP (co cua so rieng, WindowStyle=None gia lam
      popup 95% man hinh dung y spec) - KHONG chinh sua truc tiep vao
      OTMSAnalyzer_V9-6.ps1 vi khong co san ma nguon file do de doi chieu.
      Cac ham duoc dat ten/to chuc theo dung quy uoc VUNG + tieng Viet
      khong dau de sau nay ghep vao OTMSAnalyzer thuan tien (vd boc toan
      bo trong 1 ham Mo_TimKiemNangCao de goi tu nut co san).

 CAC QUY TAC NGHIEP VU DA CHOT (giu nguyen 100% tu ban demo HTML, dung
 doi lai khi doc file nay):
   - Active.db (giai ma ra) luon duoc cong them nhu 1 "batch ao": cycle =
     cycle lon nhat DA CO trong dung (OvenId, ShiftId, ShiftDate) cua file
     ngay +1. KHONG do trung noi dung - du co giong batch da archive (nhu
     truong hop mau EQOVN00104-01) van cu cong them, vi du lieu that se
     khong bao gio trung boi Active la ban dang chay, chua archive.
   - Panel dung rieng (khong thuoc Magaziner) trong table details: LUON
     la 1 dong RIENG, cot Magaziner de trong (khong gop vao Magaziner
     ngay truoc no).
   - Tim theo Oven ID: table details liet ke TUNG Mpanel/Panel rieng le
     (khong gop theo Magaziner), vi cot Config chi co nghia o muc tung
     item.
   - Doanh gioi ngay [Tu ngay]<->[Den ngay] loc theo NGAY CUA FILE (Shift
     date/ten file), KHONG loc theo "finish" cua tung batch.
   - Dropdown Type build dong tu du lieu dang nap (KHONG co san "Hades"
     tru khi file dang nap co oven type do).
   - 5 dinh dang nhan dien (Oven/Magaziner/Mpanel-Panel/Model/Config) va
     toan bo cong thuc table raw / table details / textblock: giu dung
     nhu bang doi chieu da thong nhat qua nhieu vong hoi-dap.

 GIOI HAN QUAN TRONG CAN 4A BIET TRUOC KHI CHAY:
   Moi truong xay dung file nay KHONG co PowerShell/WPF de chay-thu (chi
   co Linux sandbox, da kiem tra khong co pwsh). Phan logic doc/loc/gop
   du lieu la PORT TRUNG 1-1 tu ban JS da duoc test bang script that (ket
   qua so khop: EQOVN00104-01 ra dung cycle 3, model 2103-023000-90 ra
   dung 9 dong ke ca ban ao tu Active, sip ATTIS-MZ-D04-...012 = 87...).
   Lop ma hoa moi trong V2 nay dung dung class .NET AesCryptoServiceProvider/
   GZipStream (khong tu viet lai thuat toan) nen phan CRYPTO tin cay cao;
   da kiem chung round-trip ngoai PowerShell (Python, cung thuat toan) tren
   dung noi dung that. Phan XAML/wiring WPF (DataGrid, DataGridColumn.
   Visibility qua FindName, AllowsTransparency, DragMove...) dung dung cac
   API/pattern chuan cua WPF nhung CHUA duoc chay that tren Windows - 4A
   chay thu va bao loi cu the (thong bao + dong nao) neu co.
============================================================================
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# ============================================================================
# CAU HINH DUONG DAN (V8: thu muc du lieu that, quet nhieu file theo ngay)
# ============================================================================
$script:ThuMucDuLieu = "D:\OTMS\Data\Database"
$script:DuongDanActive = Join-Path $script:ThuMucDuLieu "Active.db"
$script:GIOI_HAN_SO_NGAY_QUET = 366   # chan pham vi qua rong (vd go nham nam) khong lam UI dung

function TAO_DUONG_DAN_FILE_NGAY {
    # File ngay dinh dang co dinh yyyymmdd.db (9A xac nhan), nam trong dung
    # $script:ThuMucDuLieu. Ten file KHONG co dinh (khac ngay khac ten) -
    # ham nay la noi DUY NHAT ghep dung dinh dang ten tu 1 ngay cu the.
    param([DateTime]$Ngay)
    $tenFile = $Ngay.ToString("yyyyMMdd") + ".db"
    return Join-Path $script:ThuMucDuLieu $tenFile
}

# ============================================================================
# VUNG: MA HOA/GIAI MA FILE .DB
# Copy NGUYEN 100% ten ham + logic tu MultiRequest_V7-7.txt (chinh no cung
# copy nguyen tu Database.psm1 cua OTMSAnalyzer) - KHONG doi thuat toan/thu
# tu buoc, de dam bao doc dung file .db that do he thong ghi ra. Khoa AES +
# IV CO DINH, giong het gia tri da xac nhan tu dau.
# Da kiem tra round-trip bang Python (cung thuat toan AES-256-CBC/PKCS7 +
# GZip chuan) tren dung noi dung 20260711.txt/Active.txt - giai ma ra dung
# y het ban goc truoc khi ma hoa.
# ============================================================================
$global:AES_KEY = [byte[]](
    0x4F, 0x56, 0x45, 0x4E, 0x44, 0x42, 0x4B, 0x45,
    0x59, 0x32, 0x30, 0x32, 0x35, 0x4F, 0x54, 0x4D,
    0x53, 0x41, 0x45, 0x53, 0x32, 0x35, 0x36, 0x42,
    0x49, 0x54, 0x4B, 0x45, 0x59, 0x46, 0x4F, 0x52
)
$global:AES_IV = [byte[]](
    0x4F, 0x54, 0x4D, 0x53, 0x49, 0x56, 0x31, 0x36,
    0x42, 0x59, 0x54, 0x45, 0x32, 0x30, 0x32, 0x35
)

function NEN_GZIP([byte[]]$data) {
    try {
        $ms = New-Object System.IO.MemoryStream
        $gz = New-Object System.IO.Compression.GZipStream(
            $ms, [System.IO.Compression.CompressionMode]::Compress)
        $gz.Write($data, 0, $data.Length)
        $gz.Close()
        return , $ms.ToArray()
    }
    catch { return $null }
}

function GIAI_NEN_GZIP([byte[]]$data) {
    try {
        $src = New-Object System.IO.MemoryStream(, $data)
        $gz = New-Object System.IO.Compression.GZipStream(
            $src, [System.IO.Compression.CompressionMode]::Decompress)
        $dst = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 4096
        do {
            $n = $gz.Read($buf, 0, $buf.Length)
            if ($n -gt 0) { $dst.Write($buf, 0, $n) }
        } while ($n -gt 0)
        $gz.Close()
        return , $dst.ToArray()
    }
    catch { return $null }
}

function MA_HOA_AES([byte[]]$data) {
    try {
        $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $global:AES_KEY
        $aes.IV = $global:AES_IV
        $enc = $aes.CreateEncryptor()
        $ms = New-Object System.IO.MemoryStream
        $cs = New-Object System.Security.Cryptography.CryptoStream(
            $ms, $enc, [System.Security.Cryptography.CryptoStreamMode]::Write)
        $cs.Write($data, 0, $data.Length)
        $cs.FlushFinalBlock()
        $cs.Close(); $aes.Dispose()
        return , $ms.ToArray()
    }
    catch { return $null }
}

function GIAI_MA_AES([byte[]]$data) {
    try {
        $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $global:AES_KEY
        $aes.IV = $global:AES_IV
        $dec = $aes.CreateDecryptor()
        $ms = New-Object System.IO.MemoryStream(, $data)
        $cs = New-Object System.Security.Cryptography.CryptoStream(
            $ms, $dec, [System.Security.Cryptography.CryptoStreamMode]::Read)
        $dst = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 4096
        do {
            $n = $cs.Read($buf, 0, $buf.Length)
            if ($n -gt 0) { $dst.Write($buf, 0, $n) }
        } while ($n -gt 0)
        $cs.Close(); $aes.Dispose()
        return , $dst.ToArray()
    }
    catch { return $null }
}

function DOC_FILE_DB([string]$path) {
    # Giai ma AES -> Giai nen GZip -> UTF8 (dung thu tu voi GHI_FILE_DB cua
    # MultiRequest_V7-7: UTF8 -> Nen GZip -> Ma hoa AES).
    try {
        $encrypted = [System.IO.File]::ReadAllBytes($path)
        $compressed = GIAI_MA_AES $encrypted
        if ($null -eq $compressed) { return $null }
        $raw = GIAI_NEN_GZIP $compressed
        if ($null -eq $raw) { return $null }
        return [System.Text.Encoding]::UTF8.GetString($raw)
    }
    catch { return $null }
}

# ============================================================================
# VUNG: MO HINH DU LIEU & NAP FILE
# ============================================================================

function DOC_XML_TU_FILE {
    # Doc file .db (nhi phan, AES+GZip) qua DOC_FILE_DB o tren, roi LoadXml()
    # chuoi XML da giai ma - KHONG con doc plaintext truc tiep nhu truoc.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = DOC_FILE_DB $Path
    if ([string]::IsNullOrEmpty($text)) { return $null }
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($text)
        return $doc
    }
    catch {
        return $null
    }
}

function DOC_LAY_ITEMS {
    # Doc <o:Items> (co the null/rong) -> tach Magaziner (chua Mpanel ben
    # trong) va Panel dung rieng. Dung XPath "*[local-name()='X']" (khong
    # can XmlNamespaceManager) - dung dung quy uoc da co san trong
    # MultiRequest_V6-2.ps1 (Add-ActiveOven / Invoke-ReconcileActive).
    param($ItemsEl)
    $magaziners = New-Object System.Collections.ArrayList
    $standalone = New-Object System.Collections.ArrayList
    if ($null -ne $ItemsEl) {
        foreach ($mag in $ItemsEl.SelectNodes("*[local-name()='Magaziner']")) {
            $mpanels = New-Object System.Collections.ArrayList
            foreach ($mp in $mag.SelectNodes("*[local-name()='Mpanel']")) {
                [void]$mpanels.Add([PSCustomObject]@{
                        Id     = $mp.GetAttribute("id")
                        Model  = $mp.GetAttribute("model")
                        Config = $mp.GetAttribute("config")
                        Sip    = [int]$mp.GetAttribute("sip")
                    })
            }
            [void]$magaziners.Add([PSCustomObject]@{
                    Id      = $mag.GetAttribute("id")
                    Model   = $mag.GetAttribute("model")
                    Mpanels = $mpanels
                })
        }
        foreach ($p in $ItemsEl.SelectNodes("*[local-name()='Panel']")) {
            [void]$standalone.Add([PSCustomObject]@{
                    Id     = $p.GetAttribute("id")
                    Model  = $p.GetAttribute("model")
                    Config = $p.GetAttribute("config")
                    Sip    = [int]$p.GetAttribute("sip")
                })
        }
    }
    # Boc ca 2 ArrayList vao 1 PSCustomObject truoc khi tra ve - dung quy
    # uoc da rut ra tu loi EndInvoke cua MultiRequest_V6-2.ps1 (V6-1): KHONG
    # bao gio tra thang 1 collection tu ham, de tranh PowerShell "bung" no.
    return [PSCustomObject]@{ Magaziners = $magaziners; StandalonePanels = $standalone }
}

function NAP_1_FILE_NGAY {
    # Doc 1 file archive (yyyymmdd.db) DA GIAI MA (XmlDocument) -> them tung
    # Batch vao $Batches va cap nhat $MaxCycle. ArrayList/Hashtable la kieu
    # tham chieu nen sua truc tiep tren tham so se phan anh ve noi goi, khong
    # can dung [ref].
    param($Doc, $Batches, $MaxCycle)
    if ($null -eq $Doc) { return }
    foreach ($shift in $Doc.DocumentElement.SelectNodes("*[local-name()='Shift']")) {
        $shiftId = $shift.GetAttribute("id")
        $shiftDate = $shift.GetAttribute("date")
        foreach ($oven in $shift.SelectNodes("*[local-name()='Oven']")) {
            $ovenId = $oven.GetAttribute("id")
            $ovenType = $oven.GetAttribute("type")
            foreach ($batch in $oven.SelectNodes("*[local-name()='Batch']")) {
                $cycle = 0
                [void][int]::TryParse($batch.GetAttribute("cycle"), [ref]$cycle)
                $itemsEl = $batch.SelectSingleNode("*[local-name()='Items']")
                $parsed = DOC_LAY_ITEMS -ItemsEl $itemsEl
                $finishRaw = $batch.GetAttribute("finish")
                $finishDt = [DateTime]::MinValue
                [void][DateTime]::TryParse($finishRaw, [ref]$finishDt)
                [void]$Batches.Add([PSCustomObject]@{
                        ShiftId          = $shiftId
                        ShiftDate        = $shiftDate
                        OvenId           = $ovenId
                        OvenType         = $ovenType
                        BatchId          = $batch.GetAttribute("id")
                        Cycle            = $cycle
                        Finish           = $finishDt
                        FinishRaw        = $finishRaw
                        Status           = $batch.GetAttribute("status")
                        Source           = "archive"
                        Magaziners       = $parsed.Magaziners
                        StandalonePanels = $parsed.StandalonePanels
                    })
                $key = "$ovenId|$shiftId|$shiftDate"
                if ((-not $MaxCycle.ContainsKey($key)) -or ($cycle -gt $MaxCycle[$key])) {
                    $MaxCycle[$key] = $cycle
                }
            }
        }
    }
}

function NAP_DU_LIEU_TIM_KIEM {
    # V8: quet MOI file yyyymmdd.db trong D:\OTMS\Data\Database co ngay nam
    # trong [TuNgay, DenNgay] (2 dau bao gom) - ngay nao khong co file (nha
    # may khong chay / chua toi ngay) thi BO QUA IM LANG (DOC_XML_TU_FILE
    # da tra $null cho file khong ton tai, NAP_1_FILE_NGAY tu bo qua $null).
    # Active.db LUON duoc doc + cong them nhu cycle moi, KHONG phu thuoc
    # khoang ngay dang chon (dung quy tac 9A da chot rieng, xem ghi chu o
    # duoi) - so file dang doc = so ngay hop le trong khoang + 1 (Active).
    param([DateTime]$TuNgay, [DateTime]$DenNgay)

    $batches = New-Object System.Collections.ArrayList
    $maxCycle = @{}

    $tu = $TuNgay.Date
    $den = $DenNgay.Date
    if ($tu -gt $den) { $t = $tu; $tu = $den; $den = $t }
    if ((($den - $tu).Days + 1) -gt $script:GIOI_HAN_SO_NGAY_QUET) {
        $den = $tu.AddDays($script:GIOI_HAN_SO_NGAY_QUET - 1)
    }
    $ngay = $tu
    while ($ngay -le $den) {
        $duongDanFile = TAO_DUONG_DAN_FILE_NGAY -Ngay $ngay
        $docNgay = DOC_XML_TU_FILE -Path $duongDanFile
        NAP_1_FILE_NGAY -Doc $docNgay -Batches $batches -MaxCycle $maxCycle
        $ngay = $ngay.AddDays(1)
    }

    # Active.db: 9A xac nhan Active va file ngay hoan toan co the trung
    # Oven ID/Magaziner/Model/Config voi nhau (vd cung 1 magaziner vat ly
    # duoc nap lai cho me khac) - do KHONG PHAI dau hieu de coi la "cung 1
    # batch". Active LUON duoc cong them nhu 1 cycle MOI (= max da archive
    # +1), KHONG tu suy dien do trung theo bat ky tieu chi nao, va KHONG
    # phu thuoc khoang ngay dang chon (Active la trang thai HIEN TAI, doc
    # doc lap voi bo loc ngay - bo loc ngay chi anh huong file archive).
    $docActive = DOC_XML_TU_FILE -Path $script:DuongDanActive
    if ($null -ne $docActive) {
        foreach ($shift in $docActive.DocumentElement.SelectNodes("*[local-name()='Shift']")) {
            $shiftId = $shift.GetAttribute("id")
            $shiftDate = $shift.GetAttribute("date")
            foreach ($oven in $shift.SelectNodes("*[local-name()='Oven']")) {
                $ovenId = $oven.GetAttribute("id")
                $ovenType = $oven.GetAttribute("type")
                $itemsEl = $oven.SelectSingleNode("*[local-name()='Items']")
                $parsed = DOC_LAY_ITEMS -ItemsEl $itemsEl
                $key = "$ovenId|$shiftId|$shiftDate"
                $finishRaw = $oven.GetAttribute("finish")
                $cycle = 1
                if ($maxCycle.ContainsKey($key)) { $cycle = $maxCycle[$key] + 1 }
                $maxCycle[$key] = $cycle
                $last8 = $ovenId
                if ($last8.Length -gt 8) { $last8 = $last8.Substring($last8.Length - 8) }
                $batchId = "{0}-{1}-{2:00}" -f $ovenType, $last8, $cycle
                $finishDt = [DateTime]::MinValue
                [void][DateTime]::TryParse($finishRaw, [ref]$finishDt)
                [void]$batches.Add([PSCustomObject]@{
                        ShiftId          = $shiftId
                        ShiftDate        = $shiftDate
                        OvenId           = $ovenId
                        OvenType         = $ovenType
                        BatchId          = $batchId
                        Cycle            = $cycle
                        Finish           = $finishDt
                        FinishRaw        = $finishRaw
                        Status           = $oven.GetAttribute("status")
                        Source           = "active"
                        Magaziners       = $parsed.Magaziners
                        StandalonePanels = $parsed.StandalonePanels
                    })
            }
        }
    }
    return [PSCustomObject]@{ Batches = $batches }
}

# ============================================================================
# VUNG: NHAN DIEN DINH DANG TIM KIEM
# ============================================================================
function NHAN_DIEN_LOAI_TIM_KIEM {
    param([string]$RawValue)
    $v = $RawValue.Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    if ($v -match '^EQOVN\d{5}-\d{2}$') { return 'oven' }
    if ($v -match '^\d{4}-\d{6}-\d{2}$') { return 'model' }
    if ($v -match '^\d{7}-[A-Za-z]{3}\d{3}[A-Za-z]$') { return 'config' }
    if ($v -match '^[A-Z0-9]{14}$') { return 'panel' }
    if ($v.Contains('-') -and $v.Length -gt 20) { return 'magaziner' }
    return 'unknown'
}

$script:NHAN_LOAI = @{
    oven      = 'Oven ID'
    magaziner = 'Magaziner ID'
    panel     = 'Mpanel / Panel ID'
    model     = 'Model ID'
    config    = 'Config ID'
}

# ============================================================================
# VUNG: LOC PHAM VI (ngay file / ca / type)
# ============================================================================
function LOC_PHAM_VI {
    # QUAN TRONG: DatePicker.SelectedDate la kieu Nullable<DateTime> ben .NET,
    # nhung khi CLR box gia tri nay de PowerShell doc qua reflection, no LUON
    # tro thanh $null (chua chon ngay) HOAC 1 [DateTime] THUAN (da chon ngay)
    # - KHONG BAO GIO la 1 doi tuong Nullable con giu duoc thuoc tinh .Value/
    # .HasValue (quy tac boxing chuan cua .NET cho struct Nullable<T>). Ban
    # dau dung "$TuNgay.Value.Date" la SAI - ".Value" khong ton tai tren 1
    # [DateTime] thuan, PowerShell (che do khong strict) am tham tra ve $null
    # thay vi bao loi, khien so sanh ngay luon sai va loc mat het ket qua.
    # Sua: kiem tra $null truc tiep, ep kieu [DateTime] khi dung (khong dung
    # toi .Value).
    param($Batches, $TuNgay, $DenNgay, [string]$Ca, [string]$Type)
    $coTuNgay = ($null -ne $TuNgay)
    $coDenNgay = ($null -ne $DenNgay)
    $ket = New-Object System.Collections.ArrayList
    foreach ($b in $Batches) {
        $ngayBatch = [DateTime]::MinValue
        [void][DateTime]::TryParseExact($b.ShiftDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ngayBatch)
        if ($coTuNgay -and ($ngayBatch.Date -lt ([DateTime]$TuNgay).Date)) { continue }
        if ($coDenNgay -and ($ngayBatch.Date -gt ([DateTime]$DenNgay).Date)) { continue }
        if ($Ca -ne 'ALL' -and $b.ShiftId -ne $Ca) { continue }
        if (-not [string]::IsNullOrEmpty($Type) -and $b.OvenType -ne $Type) { continue }
        [void]$ket.Add($b)
    }
    return [PSCustomObject]@{ Batches = $ket }
}

# ============================================================================
# VUNG: XAY DUNG TABLE RAW (theo tung loai tim kiem)
# ============================================================================
function SAP_XEP_THEO_FINISH {
    param($DsBatch)
    $out = New-Object System.Collections.ArrayList
    foreach ($x in ($DsBatch | Sort-Object FinishRaw)) { [void]$out.Add($x) }
    return $out
}

function XD_RAW_OVEN {
    param($Batches, [string]$GiaTri)
    $ket = New-Object System.Collections.ArrayList
    foreach ($b in $Batches) { if ($b.OvenId -eq $GiaTri) { [void]$ket.Add($b) } }
    $out = New-Object System.Collections.ArrayList
    foreach ($x in ($ket | Sort-Object Cycle)) { [void]$out.Add($x) }
    return [PSCustomObject]@{ Rows = $out }
}
function XD_RAW_MAGAZINER {
    param($Batches, [string]$GiaTri)
    $ket = New-Object System.Collections.ArrayList
    foreach ($b in $Batches) {
        $co = $false
        foreach ($m in $b.Magaziners) { if ($m.Id -eq $GiaTri) { $co = $true } }
        if ($co) { [void]$ket.Add($b) }
    }
    return [PSCustomObject]@{ Rows = (SAP_XEP_THEO_FINISH $ket) }
}
function XD_RAW_PANEL {
    param($Batches, [string]$GiaTri)
    $ket = New-Object System.Collections.ArrayList
    foreach ($b in $Batches) {
        $co = $false
        foreach ($p in $b.StandalonePanels) { if ($p.Id -eq $GiaTri) { $co = $true } }
        foreach ($m in $b.Magaziners) { foreach ($mp in $m.Mpanels) { if ($mp.Id -eq $GiaTri) { $co = $true } } }
        if ($co) { [void]$ket.Add($b) }
    }
    return [PSCustomObject]@{ Rows = (SAP_XEP_THEO_FINISH $ket) }
}
function XD_RAW_MODEL {
    param($Batches, [string]$GiaTri)
    $ket = New-Object System.Collections.ArrayList
    foreach ($b in $Batches) {
        $co = $false
        foreach ($p in $b.StandalonePanels) { if ($p.Model -eq $GiaTri) { $co = $true } }
        foreach ($m in $b.Magaziners) { foreach ($mp in $m.Mpanels) { if ($mp.Model -eq $GiaTri) { $co = $true } } }
        if ($co) { [void]$ket.Add($b) }
    }
    return [PSCustomObject]@{ Rows = (SAP_XEP_THEO_FINISH $ket) }
}
function XD_RAW_CONFIG {
    param($Batches, [string]$GiaTri)
    $ket = New-Object System.Collections.ArrayList
    foreach ($b in $Batches) {
        $co = $false
        foreach ($p in $b.StandalonePanels) { if ($p.Config -eq $GiaTri) { $co = $true } }
        foreach ($m in $b.Magaziners) { foreach ($mp in $m.Mpanels) { if ($mp.Config -eq $GiaTri) { $co = $true } } }
        if ($co) { [void]$ket.Add($b) }
    }
    return [PSCustomObject]@{ Rows = (SAP_XEP_THEO_FINISH $ket) }
}

function LAY_TRANG_THAI_PHA {
    param([string]$Status)
    if ($Status -match '\(([^)]+)\)') { return $Matches[1] }
    if ($Status -match '^Baking') { return 'BAKING' }
    if ([string]::IsNullOrWhiteSpace($Status)) { return 'NONE' }
    return ($Status -replace '[^A-Za-z0-9]', '')
}

function LAY_MAU_PHA {
    # Mau dung dung theo bang macOS system color da dung trong ban HTML
    # (rising/baking/cooling/pdtest) - tra ve SolidColorBrush de bind thang
    # vao Ellipse.Fill, khong can IValueConverter (tranh phai Add-Type C#).
    param([string]$Phase)
    $mau = switch ($Phase) {
        'RISING' { [System.Windows.Media.Color]::FromRgb(255, 149, 0) }
        'BAKING' { [System.Windows.Media.Color]::FromRgb(255, 59, 48) }
        'COOLING' { [System.Windows.Media.Color]::FromRgb(48, 176, 199) }
        'PDTEST' { [System.Windows.Media.Color]::FromRgb(142, 142, 147) }
        default { [System.Windows.Media.Color]::FromRgb(152, 152, 157) }
    }
    $brush = New-Object System.Windows.Media.SolidColorBrush $mau
    $brush.Freeze()
    return $brush
}

$script:TIEU_DE_RAW = @{
    oven      = @('Type', 'Batch ID')
    magaziner = @('Type', 'Oven ID')
    panel     = @('Type', 'Oven ID')
    model     = @('Type', 'Oven ID')
    config    = @('Type', 'Oven ID')
}

function TAO_HANG_RAW {
    param($Batch, [int]$RowId, [string]$Loai)
    $col1 = ''; $col2 = ''
    switch ($Loai) {
        'oven' { $col1 = $Batch.OvenType; $col2 = $Batch.BatchId }
        'magaziner' { $col1 = $Batch.OvenType; $col2 = $Batch.OvenId }
        'panel' { $col1 = $Batch.OvenType; $col2 = $Batch.OvenId }
        'model' { $col1 = $Batch.OvenType; $col2 = $Batch.OvenId }
        'config' { $col1 = $Batch.OvenType; $col2 = $Batch.OvenId }
    }
    $phase = LAY_TRANG_THAI_PHA -Status $Batch.Status
    return [PSCustomObject]@{
        RowId         = $RowId
        IsChecked     = $false
        Batch         = $Batch
        Stt           = $RowId + 1
        Phase         = $phase
        PhaseColor    = (LAY_MAU_PHA -Phase $phase)
        FinishDisplay = $Batch.Finish.ToString("HH:mm dd/MM")
        Col1          = $col1
        Col2          = $col2
    }
}

# ============================================================================
# VUNG: XAY DUNG TABLE DETAILS + TEXTBLOCK (theo tung loai tim kiem)
# ============================================================================
function TAO_CHIP_DATA { param([string]$Label, [string]$Value) return [PSCustomObject]@{ Label = $Label; Value = $Value } }

function CHI_TIET_OVEN {
    param($HangDaChon)
    $items = New-Object System.Collections.ArrayList
    foreach ($r in $HangDaChon) {
        $b = $r.Batch
        foreach ($m in $b.Magaziners) {
            foreach ($mp in $m.Mpanels) {
                [void]$items.Add([PSCustomObject]@{ MagId = $m.Id; Model = $mp.Model; Config = $mp.Config; Sip = $mp.Sip })
            }
        }
        foreach ($p in $b.StandalonePanels) {
            [void]$items.Add([PSCustomObject]@{ MagId = ''; Model = $p.Model; Config = $p.Config; Sip = $p.Sip })
        }
    }

    # Gom theo Magaziner (giu dung thu tu xuat hien dau tien). Panel dung
    # rieng (MagId rong) LUON la 1 nhom cua rieng no (khong gop nhieu panel
    # dung rieng lai voi nhau). Trong 1 nhom Magaziner, gop tiep theo dung
    # CAP (Model, Config) giong het nhau thanh 1 dong con, cong don SIP;
    # khac Model HOAC khac Config la 2 dong con rieng biet (9A xac nhan).
    $groups = New-Object System.Collections.ArrayList
    $chiSoNhom = @{}   # MagId (khac rong) -> vi tri trong $groups
    foreach ($it in $items) {
        if ([string]::IsNullOrEmpty($it.MagId)) {
            $subRows = New-Object System.Collections.ArrayList
            [void]$subRows.Add([PSCustomObject]@{ Model = $it.Model; Config = $it.Config; Sip = $it.Sip })
            [void]$groups.Add([PSCustomObject]@{ MagId = ''; SubRows = $subRows })
        }
        else {
            if (-not $chiSoNhom.ContainsKey($it.MagId)) {
                $chiSoNhom[$it.MagId] = $groups.Count
                [void]$groups.Add([PSCustomObject]@{ MagId = $it.MagId; SubRows = (New-Object System.Collections.ArrayList) })
            }
            $g = $groups[$chiSoNhom[$it.MagId]]
            $conTrung = $null
            foreach ($sr in $g.SubRows) {
                if ($sr.Model -eq $it.Model -and $sr.Config -eq $it.Config) { $conTrung = $sr }
            }
            if ($null -ne $conTrung) {
                $conTrung.Sip += $it.Sip
            }
            else {
                [void]$g.SubRows.Add([PSCustomObject]@{ Model = $it.Model; Config = $it.Config; Sip = $it.Sip })
            }
        }
    }

    # Trai phang thanh dong hien thi cho DataGrid (khong co co che gop-o
    # xuyen-dong that su): dong DAU cua 1 nhom moi co STT + Magaziner ID,
    # cac dong con tiep theo cung nhom de trong ca 2 cot do - nhin nhu 1 o
    # gop xuyen dong dung y 9A ve.
    $rows = New-Object System.Collections.ArrayList
    $stt = 0
    foreach ($g in $groups) {
        $stt++
        $dongDau = $true
        foreach ($sr in $g.SubRows) {
            $sttHienThi = ''
            $magHienThi = ''
            if ($dongDau) {
                $sttHienThi = [string]$stt
                if ([string]::IsNullOrEmpty($g.MagId)) { $magHienThi = '(trong)' } else { $magHienThi = $g.MagId }
            }
            [void]$rows.Add([PSCustomObject]@{ Stt = $sttHienThi; Col1 = $magHienThi; Col2 = $sr.Model; Col3 = $sr.Config; Col4 = [string]$sr.Sip })
            $dongDau = $false
        }
    }

    $models = @($items | Select-Object -ExpandProperty Model -Unique)
    $configs = @($items | Select-Object -ExpandProperty Config -Unique)
    $tongSip = 0
    foreach ($it in $items) { $tongSip += $it.Sip }
    $chips = New-Object System.Collections.ArrayList
    [void]$chips.Add((TAO_CHIP_DATA 'Model' ([string]$models.Count)))
    [void]$chips.Add((TAO_CHIP_DATA 'Config' ([string]$configs.Count)))
    [void]$chips.Add((TAO_CHIP_DATA 'Total SIP' ([string]$tongSip)))
    return [PSCustomObject]@{ Headers = @('Magaziner ID', 'Model ID', 'Config ID', 'SIP'); Rows = $rows; Chips = $chips }
}

function CHI_TIET_MAGAZINER {
    param($HangDaChon, [string]$GiaTri)
    $items = New-Object System.Collections.ArrayList
    foreach ($r in $HangDaChon) {
        foreach ($m in $r.Batch.Magaziners) {
            if ($m.Id -eq $GiaTri) {
                foreach ($mp in $m.Mpanels) {
                    [void]$items.Add([PSCustomObject]@{ Id = $mp.Id; Model = $mp.Model; Config = $mp.Config; Sip = $mp.Sip })
                }
            }
        }
    }
    $rows = New-Object System.Collections.ArrayList
    $i = 0; $tongSip = 0
    foreach ($it in $items) {
        $i++
        [void]$rows.Add([PSCustomObject]@{ Stt = $i; Col1 = $it.Id; Col2 = $it.Model; Col3 = $it.Config; Col4 = [string]$it.Sip })
        $tongSip += $it.Sip
    }
    $models = @($items | Select-Object -ExpandProperty Model -Unique)
    $byConfig = @{}
    foreach ($it in $items) {
        if (-not $byConfig.ContainsKey($it.Config)) { $byConfig[$it.Config] = [PSCustomObject]@{ Count = 0; Sip = 0 } }
        $byConfig[$it.Config].Count++
        $byConfig[$it.Config].Sip += $it.Sip
    }
    $chips = New-Object System.Collections.ArrayList
    [void]$chips.Add((TAO_CHIP_DATA 'Số model' ([string]$models.Count)))
    foreach ($cfg in $byConfig.Keys) {
        [void]$chips.Add((TAO_CHIP_DATA $cfg ("{0}x . sip {1}" -f $byConfig[$cfg].Count, $byConfig[$cfg].Sip)))
    }
    [void]$chips.Add((TAO_CHIP_DATA 'Tổng SIP magaziner' ([string]$tongSip)))
    return [PSCustomObject]@{ Headers = @('Mpanel/Panel ID', 'Model ID', 'Config ID', 'SIP'); Rows = $rows; Chips = $chips }
}

function CHI_TIET_PANEL {
    param($HangDaChon, [string]$GiaTri)
    $items = New-Object System.Collections.ArrayList
    foreach ($r in $HangDaChon) {
        $b = $r.Batch
        $tim = $null
        foreach ($p in $b.StandalonePanels) { if ($p.Id -eq $GiaTri) { $tim = [PSCustomObject]@{ MagId = ''; Model = $p.Model; Config = $p.Config; Sip = $p.Sip } } }
        if ($null -eq $tim) {
            foreach ($m in $b.Magaziners) {
                foreach ($mp in $m.Mpanels) {
                    if ($mp.Id -eq $GiaTri) { $tim = [PSCustomObject]@{ MagId = $m.Id; Model = $mp.Model; Config = $mp.Config; Sip = $mp.Sip } }
                }
            }
        }
        if ($null -ne $tim) { [void]$items.Add($tim) }
    }
    $rows = New-Object System.Collections.ArrayList
    $i = 0; $tongSip = 0
    foreach ($it in $items) {
        $i++
        $magDisp = '(trong)'
        if (-not [string]::IsNullOrEmpty($it.MagId)) { $magDisp = $it.MagId }
        [void]$rows.Add([PSCustomObject]@{ Stt = $i; Col1 = $magDisp; Col2 = $it.Model; Col3 = $it.Config; Col4 = '' })
        $tongSip += $it.Sip
    }
    $chips = New-Object System.Collections.ArrayList
    [void]$chips.Add((TAO_CHIP_DATA 'SIP' ([string]$tongSip)))
    return [PSCustomObject]@{ Headers = @('Magaziner ID', 'Model ID', 'Config ID'); Rows = $rows; Chips = $chips }
}

function CHI_TIET_MODEL {
    param($HangDaChon, [string]$GiaTri)
    $items = New-Object System.Collections.ArrayList
    foreach ($r in $HangDaChon) {
        $b = $r.Batch
        foreach ($m in $b.Magaziners) {
            $matching = New-Object System.Collections.ArrayList
            foreach ($mp in $m.Mpanels) { if ($mp.Model -eq $GiaTri) { [void]$matching.Add($mp) } }
            if ($matching.Count -gt 0) {
                $s = 0; foreach ($x in $matching) { $s += $x.Sip }
                [void]$items.Add([PSCustomObject]@{ OvenId = $b.OvenId; MagId = $m.Id; Count = $matching.Count; Sip = $s })
            }
        }
        foreach ($p in $b.StandalonePanels) {
            if ($p.Model -eq $GiaTri) { [void]$items.Add([PSCustomObject]@{ OvenId = $b.OvenId; MagId = ''; Count = 1; Sip = $p.Sip }) }
        }
    }
    $rows = New-Object System.Collections.ArrayList
    $i = 0; $tongSip = 0
    foreach ($it in $items) {
        $i++
        $magDisp = '(trong)'
        if (-not [string]::IsNullOrEmpty($it.MagId)) { $magDisp = $it.MagId }
        [void]$rows.Add([PSCustomObject]@{ Stt = $i; Col1 = $it.OvenId; Col2 = $magDisp; Col3 = [string]$it.Count; Col4 = [string]$it.Sip })
        $tongSip += $it.Sip
    }
    $chips = New-Object System.Collections.ArrayList
    $ovenSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($it in $items) { [void]$ovenSet.Add($it.OvenId) }
    [void]$chips.Add((TAO_CHIP_DATA 'Số Oven' ([string]$ovenSet.Count)))
    [void]$chips.Add((TAO_CHIP_DATA 'Tổng SIP' ([string]$tongSip)))
    return [PSCustomObject]@{ Headers = @('Oven ID', 'Magaziner ID', 'SL Model', 'SIP'); Rows = $rows; Chips = $chips }
}

function CHI_TIET_CONFIG {
    param($HangDaChon, [string]$GiaTri)
    $items = New-Object System.Collections.ArrayList
    foreach ($r in $HangDaChon) {
        $b = $r.Batch
        foreach ($m in $b.Magaziners) {
            $matching = New-Object System.Collections.ArrayList
            foreach ($mp in $m.Mpanels) { if ($mp.Config -eq $GiaTri) { [void]$matching.Add($mp) } }
            if ($matching.Count -gt 0) {
                $s = 0; foreach ($x in $matching) { $s += $x.Sip }
                [void]$items.Add([PSCustomObject]@{ OvenId = $b.OvenId; MagId = $m.Id; Count = $matching.Count; Sip = $s })
            }
        }
        foreach ($p in $b.StandalonePanels) {
            if ($p.Config -eq $GiaTri) { [void]$items.Add([PSCustomObject]@{ OvenId = $b.OvenId; MagId = ''; Count = 1; Sip = $p.Sip }) }
        }
    }
    $rows = New-Object System.Collections.ArrayList
    $i = 0; $tongSip = 0
    foreach ($it in $items) {
        $i++
        $magDisp = '(trong)'
        if (-not [string]::IsNullOrEmpty($it.MagId)) { $magDisp = $it.MagId }
        [void]$rows.Add([PSCustomObject]@{ Stt = $i; Col1 = $it.OvenId; Col2 = $magDisp; Col3 = [string]$it.Count; Col4 = [string]$it.Sip })
        $tongSip += $it.Sip
    }
    $ovenSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($it in $items) { [void]$ovenSet.Add($it.OvenId) }
    $magSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($it in $items) { if (-not [string]::IsNullOrEmpty($it.MagId)) { [void]$magSet.Add($it.MagId) } }
    $chips = New-Object System.Collections.ArrayList
    [void]$chips.Add((TAO_CHIP_DATA 'Số Oven' ([string]$ovenSet.Count)))
    [void]$chips.Add((TAO_CHIP_DATA 'Số Magaziner' ([string]$magSet.Count)))
    [void]$chips.Add((TAO_CHIP_DATA 'Tổng SIP' ([string]$tongSip)))
    return [PSCustomObject]@{ Headers = @('Oven ID', 'Magaziner ID', 'SL Config', 'SIP'); Rows = $rows; Chips = $chips }
}

# ============================================================================
# VUNG: GIAO DIEN WPF (macOS-light adapted sang Windows: Segoe UI thay SF Pro
# vi may Windows khong co san font SF Pro; giu dung tinh than mau sac/bo goc/
# segmented control cua ban macOS, KHONG dung nut dot tron macOS)
# ============================================================================
[xml]$xamlXml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="OTMS - Tim kiem nang cao (V9)"
    WindowStyle="None" AllowsTransparency="True" Background="Transparent"
    WindowStartupLocation="Manual">
  <Window.Resources>
    <Style x:Key="SegBtnStyle" TargetType="RadioButton">
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontWeight" Value="Medium"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#6E6E73"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="bd" CornerRadius="6" Padding="12,0" Background="Transparent" VerticalAlignment="Stretch">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="#1D1D1F"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="White"/>
                <Setter Property="Foreground" Value="#1D1D1F"/>
                <Setter TargetName="bd" Property="Effect">
                  <Setter.Value>
                    <DropShadowEffect Color="Black" Opacity="0.18" BlurRadius="3" ShadowDepth="1" Direction="270"/>
                  </Setter.Value>
                </Setter>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CloseBtnStyle" TargetType="Button">
      <Setter Property="Foreground" Value="#98989D"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="14" Width="28" Height="28" Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#12000000"/>
                <Setter Property="Foreground" Value="#1D1D1F"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1C000000"/>
                <Setter Property="Foreground" Value="#1D1D1F"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#F6F6F7"/>
      <Setter Property="Foreground" Value="#6E6E73"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="BorderBrush" Value="#E3E3E5"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Foreground" Value="#1D1D1F"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Background" Value="White"/>
      <Style.Triggers>
        <Trigger Property="AlternationIndex" Value="1">
          <Setter Property="Background" Value="#F8F8FA"/>
        </Trigger>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#E7F1FF"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="bd" Width="15" Height="15" CornerRadius="4"
                    Background="White" BorderBrush="#48000000" BorderThickness="1">
              <Path x:Name="mark" Stroke="White" StrokeThickness="1.8"
                    StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
                    Visibility="Collapsed">
                <Path.Data>
                  <PathGeometry Figures="M 3,7.2 L 6,10.2 L 11,4"/>
                </Path.Data>
              </Path>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#007AFF"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#007AFF"/>
                <Setter TargetName="mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="bd" Property="Effect">
                  <Setter.Value>
                    <DropShadowEffect Color="#007AFF" Opacity="0.9" BlurRadius="0" ShadowDepth="0"/>
                  </Setter.Value>
                </Setter>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ComboBox: template rieng (khong con la khung xam kieu Windows cu) -->
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#1A000000"/>
      <Setter Property="Foreground" Value="#1D1D1F"/>
      <Setter Property="Padding" Value="9,0"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="MinWidth" Value="138"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Effect">
        <Setter.Value>
          <DropShadowEffect Color="Black" Opacity="0.03" BlurRadius="1" ShadowDepth="1" Direction="270"/>
        </Setter.Value>
      </Setter>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="7"/>
              <Grid Margin="{TemplateBinding Padding}">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="16"/>
                </Grid.ColumnDefinitions>
                <ContentPresenter Grid.Column="0" x:Name="ContentSite" IsHitTestVisible="False"
                                   Content="{TemplateBinding SelectionBoxItem}"
                                   ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                   VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <Path Grid.Column="1" Data="M0,0 L4,4 L8,0" Stroke="#6E6E73" StrokeThickness="1.4"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
                      HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>
              <ToggleButton x:Name="ToggleBtn" Background="Transparent" BorderThickness="0"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                            Focusable="False" ClickMode="Press">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Rectangle Fill="Transparent"/>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}"
                     AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                <Border Background="White" BorderBrush="#1A000000" BorderThickness="1" CornerRadius="7" Margin="0,4,0,0"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                  <Border.Effect>
                    <DropShadowEffect Opacity="0.22" BlurRadius="14" ShadowDepth="3"/>
                  </Border.Effect>
                  <ScrollViewer MaxHeight="220" Margin="2">
                    <StackPanel IsItemsHost="True"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#38000000"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocusWithin" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#007AFF"/>
                <Setter TargetName="bd" Property="Effect">
                  <Setter.Value>
                    <DropShadowEffect Color="#007AFF" Opacity="0.35" BlurRadius="7" ShadowDepth="0"/>
                  </Setter.Value>
                </Setter>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Padding" Value="9,6"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Style.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
          <Setter Property="Background" Value="#E7F1FF"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <!-- DatePicker: chi chinh mau/vien qua Setter (KHONG thay ControlTemplate
         - ban lich xo popup cua DatePicker gan lien voi cac PART_ noi bo,
         thay toan bo template rui ro lam vo chuc nang chon ngay). Bo goc se
         khong tron hoan toan nhu HTML nhung mau/vien/font se dung. -->
    <Style TargetType="DatePicker">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#1F000000"/>
      <Setter Property="Foreground" Value="#1D1D1F"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Padding" Value="8,0"/>
    </Style>
    <Style TargetType="DatePickerTextBox">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
  </Window.Resources>

  <Border x:Name="borderWindow" CornerRadius="13" Background="#ECECEE" BorderBrush="#38000000" BorderThickness="1">
    <Border.Effect>
      <DropShadowEffect Color="#000000" Opacity="0.32" BlurRadius="44" ShadowDepth="9" Direction="270"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- ROW 1: title bar -->
      <Border x:Name="borderTitleBar" Grid.Row="0" Background="#EBFFFFFF" BorderBrush="#12000000" BorderThickness="0,0,0,1" Padding="20,12">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <StackPanel Orientation="Vertical" VerticalAlignment="Center">
              <TextBlock Text="OTMS · Oven Tracking" FontFamily="Segoe UI" FontSize="11" Foreground="#98989D"/>
              <TextBlock Text="Tìm kiếm nâng cao" FontFamily="Segoe UI" FontSize="15" FontWeight="SemiBold" Foreground="#1D1D1F"/>
            </StackPanel>
            <Border BorderBrush="#12000000" BorderThickness="1,0,0,0" Margin="22,0,0,0" Padding="0">
              <StackPanel Orientation="Horizontal" Margin="22,0,0,0">
                <StackPanel Orientation="Horizontal" Margin="0,0,13,0">
                  <Ellipse Width="6" Height="6" Fill="#FF9500" Margin="0,0,5,0" VerticalAlignment="Center"/>
                  <TextBlock Text="Rising" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,13,0">
                  <Ellipse Width="6" Height="6" Fill="#FF3B30" Margin="0,0,5,0" VerticalAlignment="Center"/>
                  <TextBlock Text="Baking" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,13,0">
                  <Ellipse Width="6" Height="6" Fill="#30B0C7" Margin="0,0,5,0" VerticalAlignment="Center"/>
                  <TextBlock Text="Cooling" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Ellipse Width="6" Height="6" Fill="#8E8E93" Margin="0,0,5,0" VerticalAlignment="Center"/>
                  <TextBlock Text="PDTEST" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73"/>
                </StackPanel>
              </StackPanel>
            </Border>
          </StackPanel>
          <Button x:Name="btnClose" Grid.Column="1" Style="{StaticResource CloseBtnStyle}" Content="✕" VerticalAlignment="Center"/>
        </Grid>
      </Border>

      <!-- ROW 2: filters -->
      <Border Grid.Row="1" Background="#E6FAFAFB" BorderBrush="#12000000" BorderThickness="0,0,0,1" Padding="20,11">
        <StackPanel Orientation="Horizontal">
          <StackPanel Orientation="Vertical" Margin="0,0,18,0">
            <TextBlock Text="Từ ngày (file)" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73" Margin="0,0,0,5"/>
            <DatePicker x:Name="dpTuNgay" Width="130" FontFamily="Segoe UI" FontSize="12.5"/>
          </StackPanel>
          <TextBlock Text="→" FontSize="13" Foreground="#98989D" VerticalAlignment="Bottom" Margin="0,0,18,7"/>
          <StackPanel Orientation="Vertical" Margin="0,0,18,0">
            <TextBlock Text="Đến ngày (file)" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73" Margin="0,0,0,5"/>
            <DatePicker x:Name="dpDenNgay" Width="130" FontFamily="Segoe UI" FontSize="12.5"/>
          </StackPanel>
          <StackPanel Orientation="Vertical" Margin="0,0,18,0">
            <TextBlock Text="Ca" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73" Margin="0,0,0,5"/>
            <Border Background="#0F000000" CornerRadius="8" Padding="2" Height="26">
              <StackPanel Orientation="Horizontal">
                <RadioButton x:Name="rdoShiftAll" GroupName="Shift" Style="{StaticResource SegBtnStyle}" Content="Tất cả" IsChecked="True" Margin="0,0,1,0"/>
                <RadioButton x:Name="rdoShiftDay" GroupName="Shift" Style="{StaticResource SegBtnStyle}" Content="Day" Margin="0,0,1,0"/>
                <RadioButton x:Name="rdoShiftNight" GroupName="Shift" Style="{StaticResource SegBtnStyle}" Content="Night"/>
              </StackPanel>
            </Border>
          </StackPanel>
          <StackPanel Orientation="Vertical">
            <TextBlock Text="Type" FontFamily="Segoe UI" FontSize="11" Foreground="#6E6E73" Margin="0,0,0,5"/>
            <ComboBox x:Name="cboType" FontFamily="Segoe UI"/>
          </StackPanel>
        </StackPanel>
      </Border>

      <!-- ROW 3: scan input -->
      <Border Grid.Row="2" Background="#ECECEE" BorderBrush="#12000000" BorderThickness="0,0,0,1" Padding="20,11">
        <Border x:Name="borderScan" Background="#0E000000" CornerRadius="9" BorderThickness="1" BorderBrush="Transparent" Padding="12,2">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Path x:Name="pathScanIcon" Grid.Column="0" Stroke="#98989D" StrokeThickness="1.6"
                  StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                  Width="15" Height="15" Margin="0,0,9,0" VerticalAlignment="Center">
              <Path.Data>
                <GeometryGroup>
                  <EllipseGeometry Center="6.2,6.2" RadiusX="5.2" RadiusY="5.2"/>
                  <LineGeometry StartPoint="10,10" EndPoint="14.3,14.3"/>
                </GeometryGroup>
              </Path.Data>
            </Path>
            <TextBox x:Name="txtScan" Grid.Column="1" BorderThickness="0" Background="Transparent"
                     FontFamily="Segoe UI" FontSize="14" Padding="0,9"
                     Tag="Quét mã BCR hoặc dán ID — Oven / Magaziner / Mpanel / Panel / Model / Config"/>
            <Border x:Name="borderBadge" Grid.Column="2" Background="#007AFF" CornerRadius="5" Padding="9,4" VerticalAlignment="Center" Visibility="Collapsed">
              <TextBlock x:Name="txtBadge" FontFamily="Segoe UI" FontSize="11" FontWeight="SemiBold" Foreground="White"/>
            </Border>
          </Grid>
        </Border>
      </Border>

      <!-- ROW 4: results -->
      <Grid x:Name="gridResults" Grid.Row="3">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="1.3*"/>
          <ColumnDefinition Width="1"/>
          <ColumnDefinition Width="0"/>
        </Grid.ColumnDefinitions>

        <Grid Grid.Column="0" Background="White">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#FAFAFB" BorderBrush="#12000000" BorderThickness="0,0,0,1" Padding="16,8">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="KẾT QUẢ" FontFamily="Segoe UI" FontSize="11.5" FontWeight="SemiBold" Foreground="#6E6E73"/>
              <Border Grid.Column="1" Background="#0E000000" CornerRadius="10" Padding="8,2">
                <TextBlock x:Name="txtRawCount" FontFamily="Segoe UI" FontSize="11" FontWeight="SemiBold" Foreground="#6E6E73"/>
              </Border>
            </Grid>
          </Border>
          <Grid Grid.Row="1">
            <DataGrid x:Name="dgRaw" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                      HeadersVisibility="Column" GridLinesVisibility="None" RowHeight="30" AlternationCount="2"
                      VirtualizingPanel.IsVirtualizing="False"
                      ScrollViewer.HorizontalScrollBarVisibility="Auto"
                      Visibility="Collapsed">
              <DataGrid.Columns>
                <DataGridTemplateColumn Header="" Width="34">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <CheckBox HorizontalAlignment="Center" VerticalAlignment="Center" IsChecked="{Binding IsChecked, Mode=TwoWay}"/>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTextColumn Header="STT" Binding="{Binding Stt}" Width="40"/>
                <DataGridTextColumn x:Name="colRaw1" Header="Col1" Binding="{Binding Col1}" Width="*" MinWidth="70"/>
                <DataGridTextColumn x:Name="colRaw2" Header="Col2" Binding="{Binding Col2}" Width="*" MinWidth="150"/>
                <DataGridTemplateColumn Header="Finish" Width="105">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <StackPanel Orientation="Horizontal">
                        <Ellipse Width="6" Height="6" Fill="{Binding PhaseColor}" Margin="0,0,7,0" VerticalAlignment="Center"/>
                        <TextBlock Text="{Binding FinishDisplay}" VerticalAlignment="Center"/>
                      </StackPanel>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
              </DataGrid.Columns>
            </DataGrid>
            <StackPanel x:Name="panelEmptyRaw" VerticalAlignment="Center" HorizontalAlignment="Center">
              <Path Stroke="#98989D" StrokeThickness="1.4" Width="40" Height="40" Margin="0,0,0,10"
                    StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Center" Opacity="0.6">
                <Path.Data>
                  <GeometryGroup>
                    <EllipseGeometry Center="17,17" RadiusX="14" RadiusY="14"/>
                    <LineGeometry StartPoint="27,27" EndPoint="38,38"/>
                  </GeometryGroup>
                </Path.Data>
              </Path>
              <TextBlock x:Name="txtEmptyRaw" Text="Nhập hoặc quét mã để tìm kiếm." FontFamily="Segoe UI" FontSize="13" Foreground="#98989D" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="420"/>
            </StackPanel>
          </Grid>
        </Grid>

        <Border Grid.Column="1" Background="#12000000"/>

        <Grid x:Name="panelDetails" Grid.Column="2" Background="White" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#FAFAFB" BorderBrush="#12000000" BorderThickness="0,0,0,1" Padding="16,8">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="CHI TIẾT" FontFamily="Segoe UI" FontSize="11.5" FontWeight="SemiBold" Foreground="#6E6E73"/>
              <Border Grid.Column="1" Background="#0E000000" CornerRadius="10" Padding="8,2">
                <TextBlock x:Name="txtDetailsCount" FontFamily="Segoe UI" FontSize="11" FontWeight="SemiBold" Foreground="#6E6E73"/>
              </Border>
            </Grid>
          </Border>
          <DataGrid x:Name="dgDetails" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                    HeadersVisibility="Column" GridLinesVisibility="None" RowHeight="28" AlternationCount="2"
                    ScrollViewer.HorizontalScrollBarVisibility="Auto">
            <DataGrid.Columns>
              <DataGridTextColumn Header="STT" Binding="{Binding Stt}" Width="40"/>
              <DataGridTextColumn x:Name="colDet1" Header="Col1" Binding="{Binding Col1}" Width="*" MinWidth="160"/>
              <DataGridTextColumn x:Name="colDet2" Header="Col2" Binding="{Binding Col2}" Width="*" MinWidth="130"/>
              <DataGridTextColumn x:Name="colDet3" Header="Col3" Binding="{Binding Col3}" Width="*" MinWidth="110"/>
              <DataGridTextColumn x:Name="colDet4" Header="Col4" Binding="{Binding Col4}" Width="70"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </Grid>

      <!-- ROW 5: summary chips -->
      <Border x:Name="panelSummaryWrap" Grid.Row="4" Background="#FAFAFB" BorderBrush="#12000000" BorderThickness="0,1,0,0" Padding="20,11" Visibility="Collapsed">
        <StackPanel x:Name="panelSummary" Orientation="Horizontal"/>
      </Border>

    </Grid>
  </Border>
</Window>
'@

$xamlReader = New-Object System.Xml.XmlNodeReader $xamlXml
$script:Window = [Windows.Markup.XamlReader]::Load($xamlReader)

$borderTitleBar = $script:Window.FindName("borderTitleBar")
$btnClose = $script:Window.FindName("btnClose")
$dpTuNgay = $script:Window.FindName("dpTuNgay")
$dpDenNgay = $script:Window.FindName("dpDenNgay")
$rdoShiftAll = $script:Window.FindName("rdoShiftAll")
$rdoShiftDay = $script:Window.FindName("rdoShiftDay")
$rdoShiftNight = $script:Window.FindName("rdoShiftNight")
$cboType = $script:Window.FindName("cboType")
$borderScan = $script:Window.FindName("borderScan")
$pathScanIcon = $script:Window.FindName("pathScanIcon")
$txtScan = $script:Window.FindName("txtScan")
$borderBadge = $script:Window.FindName("borderBadge")
$txtBadge = $script:Window.FindName("txtBadge")
$dgRaw = $script:Window.FindName("dgRaw")
$colRaw1 = $script:Window.FindName("colRaw1")
$colRaw2 = $script:Window.FindName("colRaw2")
$txtRawCount = $script:Window.FindName("txtRawCount")
$panelEmptyRaw = $script:Window.FindName("panelEmptyRaw")
$txtEmptyRaw = $script:Window.FindName("txtEmptyRaw")
$gridResults = $script:Window.FindName("gridResults")
$panelDetails = $script:Window.FindName("panelDetails")
$dgDetails = $script:Window.FindName("dgDetails")
$colDet1 = $script:Window.FindName("colDet1")
$colDet2 = $script:Window.FindName("colDet2")
$colDet3 = $script:Window.FindName("colDet3")
$colDet4 = $script:Window.FindName("colDet4")
$txtDetailsCount = $script:Window.FindName("txtDetailsCount")
$panelSummaryWrap = $script:Window.FindName("panelSummaryWrap")
$panelSummary = $script:Window.FindName("panelSummary")

$script:DetailCols = @($colDet1, $colDet2, $colDet3, $colDet4)

# Placeholder cho TextBox (WPF khong co thuoc tinh Placeholder san co) -
# dung mau xam + tu xoa/khoi phuc theo GotFocus/LostFocus.
$script:PlaceholderScan = $txtScan.Tag
function AP_DUNG_PLACEHOLDER {
    if ([string]::IsNullOrEmpty($txtScan.Text)) {
        $txtScan.Text = $script:PlaceholderScan
        $txtScan.Foreground = [System.Windows.Media.Brushes]::Gray
        $script:DangHienPlaceholder = $true
    }
}
AP_DUNG_PLACEHOLDER
$txtScan.Add_GotFocus({
        if ($script:DangHienPlaceholder) {
            $txtScan.Text = ''
            $txtScan.Foreground = [System.Windows.Media.Brushes]::Black
            $script:DangHienPlaceholder = $false
        }
    })
$txtScan.Add_LostFocus({ AP_DUNG_PLACEHOLDER })

# ============================================================================
# VUNG: TRANG THAI + DIEU PHOI CHINH
# ============================================================================
$script:TatCaBatch = New-Object System.Collections.ArrayList
$script:HangRawHienTai = New-Object System.Collections.ArrayList
$script:LoaiHienTai = $null
$script:GiaTriHienTai = ''

function TAO_CHIP_UI {
    param([string]$Label, [string]$Value)
    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.Brushes]::White
    $border.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 225, 225, 227))
    $border.BorderThickness = 1
    $border.CornerRadius = 7
    $border.Padding = "11,6"
    $border.Margin = "0,0,8,0"
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = $Label
    $t1.FontFamily = "Segoe UI"
    $t1.FontSize = 11
    $t1.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 152, 152, 157))
    $t1.VerticalAlignment = 'Center'
    $t1.Margin = "0,0,7,0"
    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.Text = $Value
    $t2.FontFamily = "Consolas"
    $t2.FontSize = 13
    $t2.FontWeight = 'SemiBold'
    $t2.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 0, 122, 255))
    $t2.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($t1)
    [void]$sp.Children.Add($t2)
    $border.Child = $sp
    return $border
}

function VE_LAI_RAW {
    $tieuDe = $null
    if ($script:LoaiHienTai) { $tieuDe = $script:TIEU_DE_RAW[$script:LoaiHienTai] }
    if ($tieuDe) {
        $colRaw1.Header = $tieuDe[0]
        $colRaw2.Header = $tieuDe[1]
    }
    $dgRaw.ItemsSource = $null
    $dgRaw.ItemsSource = $script:HangRawHienTai

    if (-not $script:LoaiHienTai) {
        if ($script:TatCaBatch.Count -eq 0) {
            $txtEmptyRaw.Text = "⚠ Chưa nạp được dữ liệu nào (0 batch) trong khoảng ngày đang chọn. Kiểm tra thư mục sau có đúng không, và có file $($dpTuNgay.SelectedDate.ToString('yyyyMMdd')).db ... $($dpDenNgay.SelectedDate.ToString('yyyyMMdd')).db / Active.db không:`n$($script:ThuMucDuLieu)"
        }
        else {
            $txtEmptyRaw.Text = "Nhập hoặc quét mã để tìm kiếm.`n(Đã nạp $($script:TatCaBatch.Count) batch từ 2 file.)"
        }
        $panelEmptyRaw.Visibility = 'Visible'; $dgRaw.Visibility = 'Collapsed'; $txtRawCount.Text = ''
    }
    elseif ($script:LoaiHienTai -eq 'unknown') {
        $txtEmptyRaw.Text = "Không nhận diện được định dạng cho `"$($script:GiaTriHienTai)`"."
        $panelEmptyRaw.Visibility = 'Visible'; $dgRaw.Visibility = 'Collapsed'; $txtRawCount.Text = ''
    }
    elseif ($script:HangRawHienTai.Count -eq 0) {
        $txtEmptyRaw.Text = "Không tìm thấy kết quả cho `"$($script:GiaTriHienTai)`" trong phạm vi đang lọc (ngày/ca/type). Thử nới bộ lọc nếu bạn chắc dữ liệu có tồn tại."
        $panelEmptyRaw.Visibility = 'Visible'; $dgRaw.Visibility = 'Collapsed'; $txtRawCount.Text = ''
    }
    else {
        $panelEmptyRaw.Visibility = 'Collapsed'; $dgRaw.Visibility = 'Visible'
        $txtRawCount.Text = "$($script:HangRawHienTai.Count) kết quả"
    }
}

function TIM_CON_THEO_KIEU {
    # Duyet cay hien thi (visual tree) tim con dau tien dung KIEU chi dinh.
    # Dung de tim CheckBox thuc te ben trong 1 DataGridRow da ve ra man
    # hinh - doc TRUC TIEP trang thai tren giao dien, khong phu thuoc vao
    # TwoWay binding co ghi nguoc dung vao PSCustomObject hay khong (day la
    # nghi ngo chinh gay "table details khong hien thi" - PSCustomObject
    # khong phai lop C# thuan, ghi nguoc qua binding co the khong dang tin
    # cay 100% trong moi truong hop).
    param($Goc, [type]$Kieu)
    if ($null -eq $Goc) { return $null }
    $soCon = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Goc)
    for ($i = 0; $i -lt $soCon; $i++) {
        $con = [System.Windows.Media.VisualTreeHelper]::GetChild($Goc, $i)
        if ($con -is $Kieu) { return $con }
        $timDuoc = TIM_CON_THEO_KIEU -Goc $con -Kieu $Kieu
        if ($null -ne $timDuoc) { return $timDuoc }
    }
    return $null
}

function LAY_HANG_DA_TICH {
    # Doc truc tiep tung CheckBox tren giao dien (qua ItemContainerGenerator
    # + visual tree) thay vi doc thuoc tinh IsChecked tren PSCustomObject -
    # dam bao dung du du binding TwoWay co hoat dong hay khong. Yeu cau
    # VirtualizingPanel.IsVirtualizing="False" tren dgRaw (da bat trong
    # XAML) de MOI dong deu co container that, khong bi "ao hoa" mat di
    # khi cuon ngoai man hinh.
    $ketQua = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $script:HangRawHienTai.Count; $i++) {
        $container = $dgRaw.ItemContainerGenerator.ContainerFromIndex($i)
        if ($null -eq $container) { continue }
        $chk = TIM_CON_THEO_KIEU -Goc $container -Kieu ([System.Windows.Controls.CheckBox])
        if ($null -ne $chk -and $chk.IsChecked -eq $true) {
            [void]$ketQua.Add($script:HangRawHienTai[$i])
        }
    }
    return $ketQua
}

function CAP_NHAT_CHI_TIET {
    $daChon = LAY_HANG_DA_TICH

    if ((-not $script:LoaiHienTai) -or ($script:LoaiHienTai -eq 'unknown') -or ($daChon.Count -eq 0)) {
        $panelDetails.Visibility = 'Collapsed'
        $panelSummaryWrap.Visibility = 'Collapsed'
        $gridResults.ColumnDefinitions[2].Width = New-Object System.Windows.GridLength(0)
        return
    }
    $gridResults.ColumnDefinitions[2].Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $panelDetails.Visibility = 'Visible'

    $ketQua = $null
    try {
        switch ($script:LoaiHienTai) {
            'oven' { $ketQua = CHI_TIET_OVEN -HangDaChon $daChon }
            'magaziner' { $ketQua = CHI_TIET_MAGAZINER -HangDaChon $daChon -GiaTri $script:GiaTriHienTai }
            'panel' { $ketQua = CHI_TIET_PANEL -HangDaChon $daChon -GiaTri $script:GiaTriHienTai }
            'model' { $ketQua = CHI_TIET_MODEL -HangDaChon $daChon -GiaTri $script:GiaTriHienTai }
            'config' { $ketQua = CHI_TIET_CONFIG -HangDaChon $daChon -GiaTri $script:GiaTriHienTai }
        }
    }
    catch {
        # Luoi an toan: neu CHI_TIET_* loi vi bat ky nguyen nhan gi (kieu du
        # lieu bat thuong, encoding...), hien THONG BAO LOI THAT ngay trong
        # khung Chi tiet thay vi de trong im lang - de 9A copy dung noi dung
        # loi gui lai, khong phai doan "khong hien thi" la vi sao.
        $panelSummary.Children.Clear()
        $panelSummaryWrap.Visibility = 'Collapsed'
        for ($i = 0; $i -lt 4; $i++) { $script:DetailCols[$i].Visibility = 'Collapsed' }
        $dgDetails.ItemsSource = $null
        $txtDetailsCount.Text = 'Loi'
        $loiRows = New-Object System.Collections.ArrayList
        [void]$loiRows.Add([PSCustomObject]@{ Stt = '!'; Col1 = "LOI: $($_.Exception.Message)"; Col2 = ''; Col3 = ''; Col4 = '' })
        $script:DetailCols[0].Visibility = 'Visible'
        $script:DetailCols[0].Header = 'Chi tiet loi (chup man hinh gui lai)'
        $dgDetails.ItemsSource = $loiRows
        return
    }

    for ($i = 0; $i -lt 4; $i++) {
        if ($i -lt $ketQua.Headers.Count) {
            $script:DetailCols[$i].Header = $ketQua.Headers[$i]
            $script:DetailCols[$i].Visibility = 'Visible'
        }
        else {
            $script:DetailCols[$i].Visibility = 'Collapsed'
        }
    }
    $dgDetails.ItemsSource = $null
    $dgDetails.ItemsSource = $ketQua.Rows
    $txtDetailsCount.Text = "$($ketQua.Rows.Count) dòng"

    $panelSummary.Children.Clear()
    $panelSummaryWrap.Visibility = 'Visible'
    foreach ($chip in $ketQua.Chips) {
        [void]$panelSummary.Children.Add((TAO_CHIP_UI -Label $chip.Label -Value $chip.Value))
    }
}

function CHAY_TIM_KIEM {
    if ($script:DangHienPlaceholder) {
        $loai = $null
        $giaTri = ''
    }
    else {
        $giaTri = $txtScan.Text.Trim()
        $loai = NHAN_DIEN_LOAI_TIM_KIEM -RawValue $giaTri
    }
    $script:LoaiHienTai = $loai
    $script:GiaTriHienTai = $giaTri

    if ($loai -and $loai -ne 'unknown') {
        $txtBadge.Text = "Đã nhận diện: " + $script:NHAN_LOAI[$loai]
        $borderBadge.Visibility = 'Visible'
        $borderScan.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 0, 122, 255))
        $pathScanIcon.Stroke = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 0, 122, 255))
    }
    elseif ($loai -eq 'unknown') {
        $txtBadge.Text = "Không nhận diện được định dạng"
        $borderBadge.Visibility = 'Visible'
        $borderScan.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 152, 152, 157))
        $pathScanIcon.Stroke = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 152, 152, 157))
    }
    else {
        $borderBadge.Visibility = 'Collapsed'
        $borderScan.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        $pathScanIcon.Stroke = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 152, 152, 157))
    }

    if (-not $loai -or $loai -eq 'unknown') {
        $script:HangRawHienTai = New-Object System.Collections.ArrayList
        VE_LAI_RAW
        CAP_NHAT_CHI_TIET
        return
    }

    $tuNgay = $dpTuNgay.SelectedDate
    $denNgay = $dpDenNgay.SelectedDate
    $ca = 'ALL'
    if ($rdoShiftDay.IsChecked -eq $true) { $ca = 'D' }
    if ($rdoShiftNight.IsChecked -eq $true) { $ca = 'N' }
    $type = ''
    if ($cboType.SelectedItem) { $type = [string]$cboType.SelectedItem }

    $phamVi = LOC_PHAM_VI -Batches $script:TatCaBatch -TuNgay $tuNgay -DenNgay $denNgay -Ca $ca -Type $type

    $ketQua = $null
    switch ($loai) {
        'oven' { $ketQua = XD_RAW_OVEN -Batches $phamVi.Batches -GiaTri $giaTri }
        'magaziner' { $ketQua = XD_RAW_MAGAZINER -Batches $phamVi.Batches -GiaTri $giaTri }
        'panel' { $ketQua = XD_RAW_PANEL -Batches $phamVi.Batches -GiaTri $giaTri }
        'model' { $ketQua = XD_RAW_MODEL -Batches $phamVi.Batches -GiaTri $giaTri }
        'config' { $ketQua = XD_RAW_CONFIG -Batches $phamVi.Batches -GiaTri $giaTri }
    }

    $hangs = New-Object System.Collections.ArrayList
    $idx = 0
    foreach ($b in $ketQua.Rows) {
        [void]$hangs.Add((TAO_HANG_RAW -Batch $b -RowId $idx -Loai $loai))
        $idx++
    }
    $script:HangRawHienTai = $hangs
    VE_LAI_RAW
    CAP_NHAT_CHI_TIET
}

function NAP_DROPDOWN_TYPE {
    $luaChonCu = $null
    if ($cboType.SelectedItem) { $luaChonCu = [string]$cboType.SelectedItem }
    $types = @($script:TatCaBatch | Select-Object -ExpandProperty OvenType -Unique | Sort-Object)
    $cboType.Items.Clear()
    [void]$cboType.Items.Add("")
    foreach ($t in $types) { [void]$cboType.Items.Add($t) }
    if ($luaChonCu -and $types -contains $luaChonCu) {
        $cboType.SelectedItem = $luaChonCu
    }
    else {
        $cboType.SelectedIndex = 0
    }
}

function NAP_LAI_DU_LIEU {
    # V8: goi lai moi khi Tu ngay/Den ngay doi (va 1 lan luc mo cua so) -
    # quet dung cac file yyyymmdd.db trong khoang dang chon + Active.db,
    # thay vi nap co dinh 1 lan nhu ban truoc.
    $tu = $dpTuNgay.SelectedDate
    $den = $dpDenNgay.SelectedDate
    if (-not $tu) { $tu = (Get-Date).Date }
    if (-not $den) { $den = (Get-Date).Date }
    $loaded = NAP_DU_LIEU_TIM_KIEM -TuNgay $tu -DenNgay $den
    $script:TatCaBatch = $loaded.Batches
    NAP_DROPDOWN_TYPE
}

# ============================================================================
# VUNG: SU KIEN
# ============================================================================
$script:DebounceTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:DebounceTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:DebounceTimer.Add_Tick({
        $script:DebounceTimer.Stop()
        CHAY_TIM_KIEM
    })
$txtScan.Add_TextChanged({
        if (-not $script:DangHienPlaceholder) {
            $script:DebounceTimer.Stop()
            $script:DebounceTimer.Start()
        }
    })
$txtScan.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $script:DebounceTimer.Stop()
            CHAY_TIM_KIEM
        }
    })

$hanlerTichChon = [System.Windows.RoutedEventHandler] {
    param($s, $e)
    # CheckBox trong DataGridTemplateColumn khong di qua co che "edit mode"
    # cua DataGrid (khac DataGridCheckBoxColumn) - nen KHONG bi anh huong
    # boi IsReadOnly cua luoi/cot. Bat 2 su kien Checked/Unchecked cua
    # ToggleButton (CheckBox ke thua) qua AddHandler vi chung BUBBLE len
    # tan DataGrid, khong can tim tung o rieng le.
    $script:Window.Dispatcher.BeginInvoke([action] { CAP_NHAT_CHI_TIET }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}
$dgRaw.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $hanlerTichChon)
$dgRaw.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $hanlerTichChon)
# Luoi an toan them: bat ca su kien nhap chuot tren toan DataGrid (chac
# chan LUON bubble trong WPF, khong phu thuoc dung suy doan ve Checked/
# Unchecked co bubble hay khong). CAP_NHAT_CHI_TIET doc lai TOAN BO trang
# thai checkbox tren giao dien (LAY_HANG_DA_TICH) nen goi thua vai lan
# (vd click chon dong khong trung checkbox) khong gay sai lech gi, chi la
# tinh toan lai - an toan tuyet doi de du phong.
$dgRaw.AddHandler([System.Windows.Input.Mouse]::MouseUpEvent, [System.Windows.Input.MouseButtonEventHandler] {
        param($s, $e)
        $script:Window.Dispatcher.BeginInvoke([action] { CAP_NHAT_CHI_TIET }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    })

foreach ($rdo in @($rdoShiftAll, $rdoShiftDay, $rdoShiftNight)) {
    $rdo.Add_Checked({ if ($script:LoaiHienTai -and $script:LoaiHienTai -ne 'unknown') { CHAY_TIM_KIEM } })
}
$dpTuNgay.Add_SelectedDateChanged({ NAP_LAI_DU_LIEU; VE_LAI_RAW; CAP_NHAT_CHI_TIET; if ($script:LoaiHienTai -and $script:LoaiHienTai -ne 'unknown') { CHAY_TIM_KIEM } })
$dpDenNgay.Add_SelectedDateChanged({ NAP_LAI_DU_LIEU; VE_LAI_RAW; CAP_NHAT_CHI_TIET; if ($script:LoaiHienTai -and $script:LoaiHienTai -ne 'unknown') { CHAY_TIM_KIEM } })
$cboType.Add_SelectionChanged({ if ($script:LoaiHienTai -and $script:LoaiHienTai -ne 'unknown') { CHAY_TIM_KIEM } })

$borderTitleBar.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($e.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) { $script:Window.DragMove() }
    })
$btnClose.Add_Click({ $script:Window.Close() })
$script:Window.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $script:Window.Close() }
    })

# ============================================================================
# KHOI CHAY
# ============================================================================
$homNay = (Get-Date).Date
$dpTuNgay.SelectedDate = $homNay
$dpDenNgay.SelectedDate = $homNay
NAP_LAI_DU_LIEU
VE_LAI_RAW
CAP_NHAT_CHI_TIET

$workArea = [System.Windows.SystemParameters]::WorkArea
$script:Window.Width = $workArea.Width * 0.95
$script:Window.Height = $workArea.Height * 0.95
$script:Window.Left = $workArea.Left + ($workArea.Width - $script:Window.Width) / 2
$script:Window.Top = $workArea.Top + ($workArea.Height - $script:Window.Height) / 2

[void]$script:Window.ShowDialog()
