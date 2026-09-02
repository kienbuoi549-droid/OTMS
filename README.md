# OTMS
================================================================================
BÁO CÁO KIỂM TRA & SỬA LỖI -- OTMSAnalyzer V10
Bản nguồn: OTMS-I1v2,0(190826)  -->  Bản đã sửa: OTMS-I1v2,6(190826)
Ngày kiểm tra: 31/08/2026
================================================================================
Lịch sử phiên bản sửa:
  - v2,1: sửa 10 lỗi logic/nghiệp vụ (LỖI 1 -> 10)
  - v2,2: sửa thêm LỖI 11 -- nhãn Target/Actual đè lên nhau trong cột tiến độ
  - v2,3: TÍNH NĂNG MỚI -- luồng điều hướng đa giao diện UI <-> OvenRanking <-> MiniMap
  - v2,4: TÍNH NĂNG MỚI -- NỐI DỮ LIỆU THẬT cho OvenRanking + MiniMap
  - v2,5: ĐỐI CHIẾU DỮ LIỆU THẬT MÁY CHẠY (2 file user cung cấp: Active.db thật
          + file lịch sử ca 20260830.db thật) -- 3 điều chỉnh theo đúng cấu trúc
          dữ liệu thực tế -- xem phần ĐỐI CHIẾU v2,5 cuối báo cáo này.
  - v2,6: TÍNH NĂNG MỚI -- MiniMap "OVEN HOÀN THÀNH GẦN NHẤT" lấy ĐÚNG batch
          có finish gần nhất trong yyyymmdd.db (không cộng dồn nguyên lò)
          + kiểm chứng đọc file lịch sử MÃ HOÁ AES+GZip -- xem phần
            TÍNH NĂNG MỚI v2,6 cuối báo cáo này.

Phạm vi v2,1 -> v2,3: rà soát TOÀN BỘ 15 file (5.171 dòng) -- main.ps1, UI.xaml,
9 module .psm1, 3 file dữ liệu mẫu. Kết quả: phát hiện & sửa 11 lỗi (3 nghiêm trọng,
5 mức vừa, 3 mức nhẹ).

--------------------------------------------------------------------------------
LỖI 1 [NGHIÊM TRỌNG] Mất dữ liệu chưa lưu khi bấm X xoá dòng model
File: Output_setting.psm1 -- nút X trong THEM_DONG_MODEL
--------------------------------------------------------------------------------
Nguyên nhân: nút X chỉ RemoveAt khỏi $global:AS.settingsModels rồi dựng lại giao
diện TỪ BỘ NHỚ. Giá trị các ô nhập chỉ được đọc vào bộ nhớ duy nhất 1 lần ở
LUU_CAI_DAT_SAN_LUONG, nên MỌI nội dung đã gõ nhưng CHƯA bấm Lưu đều biến mất.
Đã sửa: thêm hàm DONG_BO_UI_VAO_BO_NHO (đồng bộ UI -> bộ nhớ), gọi TRƯỚC khi xoá.

--------------------------------------------------------------------------------
LỖI 2 [NGHIÊM TRỌNG] Gõ ký tự không phải số -> âm thầm đăng nhập Administrator
File: Login.psm1 -- XAC_NHAN_DANG_NHAP
--------------------------------------------------------------------------------
Nguyên nhân: mã nhập bị lọc chỉ giữ chữ số. Gõ chữ -> chuỗi rỗng -> rơi vào nhánh
"nhập trống = dùng tài khoản mặc định VN004043".
Đã sửa: ô nhập CÓ nội dung nhưng KHÔNG có chữ số -> hiện lỗi rõ ràng, không tự
đăng nhập hộ. Nhập trống vẫn giữ hành vi cũ.

--------------------------------------------------------------------------------
LỖI 3 [NGHIÊM TRỌNG] MO.db hỏng 1 mục -> ứng dụng thoát ngay lúc khởi động
File: Database.psm1 -- NAP_MO_DB
--------------------------------------------------------------------------------
Nguyên nhân: ép kiểu trực tiếp [double]/[bool]. 1 model plan sai -> exception ->
TOÀN BỘ MO.db bị coi là hỏng -> KHOI_TAO_DB throw -> app THOÁT. Ngoài ra bẫy
[bool]"false" = $true.
Đã sửa: DOI_SO_DB_AN_TOAN / DOI_BOOL_DB_AN_TOAN (parse InvariantCulture, giá trị
sai -> về mặc định thay vì làm hỏng cả file).

--------------------------------------------------------------------------------
LỖI 4 [VỪA] Parse số phụ thuộc văn hoá máy -> số liệu QA-HOUR sai trên máy Việt
File: Production.psm1, Output_setting.psm1, Support.psm1
--------------------------------------------------------------------------------
Đã sửa: PHAN_TICH_SO (ưu tiên InvariantCulture; dữ liệu server gọi -ChiInvarian).

--------------------------------------------------------------------------------
LỖI 5 [VỪA] Huỷ đăng nhập -> header hiển thị sai phiên người dùng
File: main.ps1
--------------------------------------------------------------------------------
Đã sửa: hiển thị theo $global:AS.curUser / $global:AS.curName thay vì gán cứng.

--------------------------------------------------------------------------------
LỖI 6 [VỪA] Không kiểm tra Model ID trùng khi Lưu -> mất dữ liệu im lặng
File: Output_setting.psm1 -- LUU_CAI_DAT_SAN_LUONG
--------------------------------------------------------------------------------
Đã sửa: Group-Object kiểm tra trùng Model ID -> chặn Lưu tới khi sửa xong.

--------------------------------------------------------------------------------
LỖI 7 [VỪA] Rò rỉ DispatcherTimer khi tài khoản bị khoá
File: Login.psm1 -- CAP_NHAT_KHOA_DANG_NHAP + CAP_NHAT_KHOA_CAU_HINH
--------------------------------------------------------------------------------
Đã sửa: cờ guard -- chỉ timer đầu tiên được tạo, tự dừng khi hết thời gian khoá.

--------------------------------------------------------------------------------
LỖI 8 [NHẸ] Thuộc tính 'sip' thiếu/rỗng trong Active.db -> cả card lò bỏ trống
File: OvenBaking.psm1 -- XAY_DUNG_CHI_TIET_LO
--------------------------------------------------------------------------------
Đã sửa: DOI_INT_AN_TOAN (parse an toàn, sai -> mặc định 0).

--------------------------------------------------------------------------------
LỖI 9 [NHẸ] Plan bị cắt mất phần thập phân trong form sửa/cài đặt
File: Production.psm1 (MO_SUA_PLAN) + Output_setting.psm1
--------------------------------------------------------------------------------
Đã sửa: hiển thị bằng .ToString(InvariantCulture) giữ nguyên phần lẻ.

--------------------------------------------------------------------------------
LỖI 10 [NHẸ] Viền đỏ của ô nhập Plan "kẹt" mãi sau khi nhập sai 1 lần
File: Production.psm1 -- LUU_SUA_PLAN
--------------------------------------------------------------------------------
Đã sửa: trả về màu thường #E2E8F0 TRƯỚC khi kiểm tra.

--------------------------------------------------------------------------------
LỖI 11 [VỪA - GIAO DIỆN] Nhãn Target/Actual trong cột "TIEN DO SAN XUAT" đè lên
nhau khi hai tiến độ trùng/gần trùng nhau
File: Production.psm1 (TINH_BANG_DU_LIEU) + UI.xaml (MinWidth cột 120 -> 150)
--------------------------------------------------------------------------------
Đã sửa (quy tắc: Target giữ nguyên vị trí vốn có, Actual TỰ NHƯỜNG CHỖ):
khối "FIX CHONG DE NHAN" -- nếu |ActualPct - TargetPct| < MIN_GAP (32%) thì
Actual hiển thị tại TargetPct ± 32% theo phía vốn nằm; kẹt mép (EDGE 15%) thì
đảo phía. Vì 2*MIN_GAP (64) <= 100 - 2*EDGE (70) nên LUÔN có phía đủ chỗ.
Hai progress bar vẫn thể hiện % THẬT -- chỉ nhãn CHỮ tự né, số liệu không sai.
Đã kiểm chứng mô phỏng 1.002.001 tổ hợp: 4 bất biến đứng vững toàn không gian.

================================================================================
TÍNH NĂNG MỚI (v2,3) -- LUỒNG ĐIỀU HƯỚNG ĐA GIAO DIỆN (3 chấm macOS)
================================================================================
  Step1: mở app -> UI.xaml (mặc định, như cũ)
  Step2: UI.xaml         bấm CHAM XANH -> OvenRanking.xaml
  Step3: OvenRanking.xaml: CHAM XANH -> MiniMap.xaml | CHAM VÀNG -> UI.xaml
  Step4: MiniMap.xaml:     CHAM VÀNG -> ẩn taskbar | CHAM XANH -> OvenRanking
  CHAM ĐỎ  = thoát hẳn ứng dụng ở CẢ 3 giao diện. Alt+F4 = thoát (an toàn mặc định).
Kiến trúc: vòng lặp main.ps1 nạp cửa sổ theo $global:MAN_HINH_KE rồi ShowDialog();
chấm điều hướng chỉ đặt flag + Close(). $global + Runspace nền GIỮ NGUYÊN.
NAP_CUA_SO nạp XAML bất kỳ + tự quét mọi x:Name -> FindName -> dựng $global:e.

================================================================================
TÍNH NĂNG MỚI (v2,4) -- NỐI DỮ LIỆU THẬT CHO OVENRANKING + MINIMAP
================================================================================
KHÔNG còn dữ liệu mẫu cứng (mockup) -- 2 giao diện mới đọc dữ liệu thật:

NGUỒN DỮ LIỆU:
  1) Active.db (đã có sẵn): $global:OVEN_DATA do Runspace_LO cập nhật mỗi khi
     FileSystemWatcher phát hiện Active.db đổi (debounce 5 giây) + khi vào UI.
  2) yyyymmdd.db (MỚI -- mốc thời gian của ca làm việc hôm nay): file lịch sử
     nằm cùng thư mục DATABASE_DIR với Active.db, tên = <yyyyMMdd>.db với
     yyyyMMdd là NGÀY MỐC của ca đang chạy:
       - Giờ 08:00-23:59 -> mốc HÔM NAY (ca ngày bắt đầu 08:00 / ca đêm 20:00)
       - Giờ 00:00-07:59 -> mốc HÔM QUA (ca đêm bắt đầu 20:00 tối qua vẫn chạy)
     (hàm mới LAY_NGAY_CA_HIEN_TAI -- Support.psm1)

FILE SỬA:
  - Support.txt     : +LAY_NGAY_CA_HIEN_TAI (mốc ngày ca -> tên file lịch sử)
  - Database.txt    : +NAP_DB_LICH_SU_NGAY (đọc yyyymmdd.db: né vùng ghi, thăm dò
                      khoá, XML namespace urn:otms; thiếu/hỏng -> $null KHÔNG BAO
                      GIỜ ném exception làm chết luồng chính). v2,5: đọc LINH
                      HOẠT 2 định dạng XML thuần / AES+GZip (xem phần v2,5).
  - OvenBaking.txt  : +LAY_DANH_SACH_LOAI_LO (2 loại lò từ SETTINGS.items -- dùng
                      chung cho CẢ 2 nguồn để khóa dữ liệu đồng bộ; v2,5 bỏ bản
                      định nghĩa TRÙNG)
                      +XAY_DUNG_CHI_TIET_LO mở rộng: magCount (số kệ Magaziner VẬT
                      LÝ trong lò -- đếm node, không chia /8; không có node kệ thì
                      ước lượng ceil(panel/8)) và sipRaw (tổng SIP thô từng model)
                      +XAY_DUNG_CHI_TIET_LO_LICH_SU (bản quét descendant .// -- file
                      lịch sử có thêm tầng Batch/cycle giữa Oven và Items; v2,5:
                      chỉ cộng dồn Batch ĐÃ HOÀN THÀNH khi có truyền mốc)
                      +LAY_THOI_GIAN_HOAN_THANH_LO (mốc finish: Oven@finish ->
                      Oven@finishTime -> muộn nhất trên các Batch con; v2,5: bỏ
                      qua mốc VƯỢT TƯƠNG LAI khi có truyền $MocToiDa)
                      +LAY_DU_LIEU_LICH_SU_LO (đọc yyyymmdd.db, chọn oven hoàn thành
                      GẦN NHẤT theo từng loại lò; v2,5: lọc finish <= hiện tại)
                      +CHON_LO_HIEN_TAI_CHO_MINIMAP (oven có finish SỚM NHẤT = lò
                      sắp ra kế tiếp; lò không có finish hợp lệ bị loại)
  - OvenRanking.txt : viết lại -- bỏ 7 hàng lò + 7 popup CỨNG; giữ khung card +
                      container Card{1,2}_Rows / Card{1,2}_Rank / Card{1,2}_KhuVucDuoi
  - MiniMap.txt     : bỏ 2 danh sách model CỨNG -> 1 container SP_Models; giá trị
                      placeholder về "--"; tên 2 line lấy từ SETTINGS.items
  - main.txt        : +CAP_NHAT_GIAO_DIEN_RANKING (vẽ TOÀN BỘ 2 card động: header
                      "N lò"/tổng SIP, bảng lò sắp theo Finish gần->xa, Top Ranking
                      huy chương vàng/bạc/đồng tối đa 3 model, popup chi tiết từng
                      lò bấm hàng để mở/đóng -- giữ popup đang mở qua lần vẽ lại)
                      +CAP_NHAT_DU_LIEU_MINIMAP (dựng $global:MM_DATA từ 2 nguồn:
                      oven đang theo dõi từ Active.db + oven hoàn thành gần nhất từ
                      yyyymmdd.db; Rem tính lại từ mốc finish thật mỗi lần dữ liệu đổi)
                      Runspace_LO trả thêm LichSuLo; BG_POLL_TIMER_LO vẽ vào ĐÚNG màn
                      hình đang sống qua $global:MAN_HINH_HIEN_TAI
                      (UI: card lò | RANKING: 2 card | MINIMAP: dựng + vẽ line)

CHI TIẾT HIỂN THỊ:
  - OvenRanking: 2 card theo SETTINGS.items (vd C10.5/Hades). Header card: tên line
    + "N lò" + tổng SIP cộng dồn. Bảng: OVEN ID | Status (phần "(...)" tô màu
    BAKING xanh / RISING vàng / COOLING xanh lá) | HOÀN THÀNH. Top Ranking: huy
    chương + model + số MGZ. Bấm hàng lò -> popup chi tiết (tổng MAG/SIP, từng
    model + từng config + tổng SIP model) -- bấm × hoặc bấm ngoài để đóng.
  - MiniMap: thông tin oven đang theo dõi của line (OVEN ID/FINISH/MAG=số kệ/
    TOTAL SIP), đếm ngược tới mốc finish (4 trạng thái màu: thường / cảnh báo
    <=15 phút / khẩn cấp <=5 phút + badge nhấp nháy / hoàn thành), danh sách model
    | SIP của oven, section "OVEN HOÀN THÀNH GẦN NHẤT" từ yyyymmdd.db (ID, giờ
    hoàn thành, "X phút/giờ trước", tổng SIP). Line trống -> "--" + "Không có lò".
  - Đếm ngược: nguồn sự thật = mốc finish thật; dữ liệu Active.db đổi -> tính lại;
    giữa 2 lần cập nhật timer 1 giây tự giảm cục bộ (giữ nguyên cảm giác mockup).

================================================================================
ĐỐI CHIẾU v2,5 -- DỮ LIỆU THẬT MÁY CHẠY (Active.txt + 20260830.txt user cung cấp)
================================================================================
Phân tích 2 file THẬT user gửi cho thấy 3 điểm cần điều chỉnh so với v2,4:

ĐIỀU CHỈNH 1 [NGHIÊM TRỌNG] -- yyyymmdd.db thật là XML THUẦN, KHÔNG mã hoá
  File: Database.psm1 -- NAP_DB_LICH_SU_NGAY
  --------------------------------------------------------------------------------
  Phát hiện: Active.db thật là nhị phân AES-256-CBC + GZip (đúng chuẩn app tự ghi),
  NHƯNG file lịch sử ca 20260830.db thật do hệ thống nguồn ghi ra dạng XML thuần --
  mở bằng notepad thấy ngay '<?xml ... urn:otms'. v2,4 đọc lịch sử chỉ qua đường
  AES+GZip -> trên máy thật giải mã SAI -> phần "OVEN HOÀN THÀNH GẦN NHẤT" của
  MiniMap sẽ TRỐNG HOÀN TOÀN, còn spam log ERROR mỗi chu kỳ đọc (1-3 dòng/phút).
  Đã sửa: hàm DÒ 8 BYTE ĐẦU của file (nhảy qua UTF-8 BOM nếu có):
    - byte '<' (0x3C)  -> XML thuần: đọc thẳng thành văn bản (StreamReader UTF8,
      tự nhận BOM) -- KHÔNG đi qua AES/GZip
    - khác             -> nhị phân AES+GZip: đi qua DOC_FILE_DB như Active.db
  Mỗi đường thất bại vẫn còn đường kia làm dự phòng 1 lần trước khi báo hỏng
  (phòng hệ thống nguồn đổi cách ghi giữa chừng). Cả 2 đường hỏng -> trả $null
  KHÔNG ném exception như cũ.

ĐIỀU CHỈNH 2 [NHẸ] -- Định nghĩa TRÙNG hàm LAY_DANH_SACH_LOAI_LO
  File: OvenBaking.psm1
  --------------------------------------------------------------------------------
  v2,4 vô tình chứa 2 bản định nghĩa giống hệt nhau (bản sau đè bản trước nên
  chạy vẫn đúng, nhưng rối mã và dễ lệch về sau). Đã xoá bản thừa, giữ đúng 1.

ĐIỀU CHỈNH 3 [VỪA - NGHIỆP VỤ] -- Batch trong lịch sử có finish DỰ KIẾN TƯƠNG LAI
  File: OvenBaking.psm1 -- LAY_DU_LIEU_LICH_SU_LO, LAY_THOI_GIAN_HOAN_THANH_LO,
                            XAY_DUNG_CHI_TIET_LO_LICH_SU
  --------------------------------------------------------------------------------
  Phát hiện: trong 20260830.db thật, MỖI oven có 3-4 Batch (cycle 1..N) và Batch
  được ghi khi vào trạng thái Baking(COOLING) với finish là MỐC DỰ KIẾN -- có thể
  ở TƯƠNG LAI (vd lô cuối ca đêm finish 07:49 sáng hôm sau). v2,4 chọn "oven hoàn
  thành gần nhất" theo mốc finish muộn nhất KHÔNG xét hiện tại -> lúc 07:00 sáng
  section Done sẽ chỉ vào lò VẪN ĐANG nướng (finish dự kiến 07:49) với DoneAgo
  âm -- sai ngữ nghĩa.
  Đã sửa:
    - LAY_THOI_GIAN_HOAN_THANH_LO: tham số mới $MocToiDa -- mốc VƯỢT TƯƠNG LAI bị
      bỏ qua (chỉ chọn lô ĐÃ xong muộn nhất <= mốc).
    - XAY_DUNG_CHI_TIET_LO_LICH_SU: tham số mới $MocHoanThanh -- chỉ cộng dồn các
      Batch ĐÃ HOÀN THÀNH (finish <= mốc); batch thiếu finish -> coi như đã xong.
      DoneTotal = sản lượng ĐÃ RA của lò, không phình to bởi hàng còn trong lò.
    - LAY_DU_LIEU_LICH_SU_LO: chốt MỘC Get-Date ĐÚNG 1 LẦN đầu hàm, dùng chung cho
      chọn oven + gom chi tiết (nhất quán, không lệch ranh đổi giây).

CẤU TRÚC DỮ LIỆU THẬT ĐÃ XÁC NHẬN (đối chiếu code khớp 100%):
  Active.db (AES+GZip -> XML urn:otms):
    OTMS > Shift(id,date) > Oven(id,type,finish,status) > Items > Magaziner > Mpanel
           (id,model,config,sip)
           + Panel lẻ nằm THẲNG trong Items (lò không kệ -- vd ATTIS; có oven C10.5
             TRỘN cả Magaziner lẫn Panel trong 1 lò)
           + status thực tế: Baking(BAKING) / Baking(RISING) / Baking(COOLING)
  yyyymmdd.db (XML thuần urn:otms):
    OTMS > Shift(id=D|N, date) x2 CA TRONG 1 FILE > Oven(id,type) -- Oven KHÔNG có
           finish/status > Batch(id,cycle,finish,status) x3-4/lò > Items >
           Magaziner > Mpanel (+ Panel lẻ)
           + finish của Batch có thể ở SÁNG HÔM SAU (ca đêm chạy quá nửa đêm)
  SETTINGS.items thật: item1=C10.5, item7=Hades -- khớp 2 brand trong dữ liệu.

ĐÃ KIỂM TRA (v2,5):
  - scripts/test_du_lieu_that_v25.py chạy trên 2 FILE THẬT user gửi: 41/41 PASS
      + NAP_DB_LICH_SU_NGAY: XML thuần / XML+BOM / AES+GZip / file rác (4 case)
      + Active thật: 9 lò C10.5 + 2 lò Hades đúng số; tổng SIP card 2.608 đối
        chiếu độc lập khớp; lò trộn 2 kệ + 11 Mpanel + 4 Panel -> MAG/SIP đúng;
        lò không kệ -> ước lượng ceil/8 đúng
      + Lịch sử thật: 5 mốc thời gian x 2 brand -- oven Done + DoneTotal chỉ tính
        batch đã xong, khớp brute-force 100% (kể cả case 07:49 tương lai bị loại,
        case cùng 1 oven id xuất hiện ở CẢ 2 Shift D+N -- chỉ gộp node ca mới nhất)
      + Rem đếm ngược từ Active thật (lò finish sớm nhất = lò sắp ra) + 4 ngưỡng màu
      + Mốc tên file theo ca: 13:00 / 21:30 / 02:00 / 07:59 / 08:00 -- đúng hết
  - Hồi quy: test_luong_dieu_huong.py PASS (Step1-4 + 73 element khớp 100%);
    test_ne_nhan.py PASS (1.002.001 tổ hợp); cân bằng ngoặc toàn bộ file OK.

================================================================================
TÍNH NĂNG MỚI (v2,6) -- MINIMAP: "OVEN HOÀN THÀNH GẦN NHẤT" LẤY ĐÚNG BATCH CÓ
FINISH GẦN NHẤT + KIỂM CHỨNG ĐỌC FILE LỊCH SỬ MÃ HOÁ (AES+GZip)
================================================================================
Bối cảnh (yêu cầu user): (a) file yyyymmdd.db THẬT sẽ được MÃ HOÁ -- bản gửi
trước chỉ là show cấu trúc; (b) ở MiniMap, khi lò đã xong phải tìm trong
yyyymmdd.db và lấy thông tin BATCH có finish GẦN NHẤT.

1) Đổi logic chọn "oven hoàn thành" (OvenBaking.psm1 -- LAY_DU_LIEU_LICH_SU_LO):
   - Cũ (v2,4/v2,5): chọn OVEN hoàn thành gần nhất rồi cộng dồn TOÀN BỘ batch
     đã xong trong lò đó -> tổng SIP/MAG phình to bởi các batch ĐÃ RA TỪ TRƯỚC
     trong cùng lò (dữ liệu thật: 1 lò nướng 3-7 lô/cycle).
   - Mới (v2,6): quét MỌI Batch của TẤT CẢ oven cùng loại (trọn cả 2 Shift D+N
     cùng file), giữ batch có finish MUỘN NHẤT nhưng KHÔNG VƯỢT HIỆN TẠI; giờ
     hoàn thành + tổng SIP/MAG hiển thị thuộc về ĐÚNG batch đó (mốc trên
     Batch@finish, dự phòng finishTime/endTime).
   - Dữ liệu trả về thêm 2 trường: batchId (vd C10.5-00469-01-01) và cycle
     (số lô trong lò).
   - DỰ PHÒNG: loại lò KHÔNG có Batch nào mang mốc finish hợp lệ (cấu trúc khác
     -- Items thẳng trong Oven / finish trên Oven) -> tự quay về logic V2,5
     (oven-level) để section không trống vô nghĩa.
2) Hiển thị MiniMap (main.ps1 -- CAP_NHAT_DU_LIEU_MINIMAP):
   - MM_DoneId = "<mã lò> • Lô <cycle>" (vd "EQOVN00471-02 • Lô 5") -- phân
     biệt được lô nào vừa ra trong lò; thiếu mã lò -> hiển thị batchId; không
     có cycle -> chỉ hiển thị tên lò (như cũ).
   - MM_DoneTime / MM_DoneAgo / MM_DoneTotal lấy TRỰC TIẾP từ batch được chọn
     -- DoneTotal = tổng SIP của RIÊNG batch, KHÔNG cộng các lô đã ra trước đó.
3) File lịch sử MÃ HOÁ: NAP_DB_LICH_SU_NGAY (từ v2,5) tự nhận diện 2 định dạng
   XML thuần / AES-256-CBC + GZip, không cần cấu hình. v2,6 kiểm chứng trên
   file mã hoá sinh ra từ dữ liệu ca 20260830 bằng đúng key/IV hệ thống:
   đọc đúng nội dung; kể cả ca biên ciphertext tình cờ khởi đầu bằng byte '<'
   (xác suất 1/256 -- đường chính đo nhầm là XML thuần) thì đường dự phòng vẫn
   đọc được; file rác -> bỏ qua an toàn, KHÔNG làm rơi app, không spam log.

ĐÃ KIỂM TRA (v2,6):
  - scripts/test_du_lieu_that_v26.py: 59/59 PASS trên dữ liệu thật
      + Phần A (5 case): XML thuần / AES+GZip / XML+BOM / ciphertext bắt đầu
        '<' (fallback cứu được) / file rác -> đọc hoặc bỏ qua AN TOÀN
      + Phần B (43 case): 6 mốc "bây giờ" x 2 brand -- chọn đúng batch có
        finish muộn nhất <= hiện tại (đối chiếu brute-force độc lập khớp
        100%); SIP/panel scoped ĐÚNG batch (vd @31/08 02:00: batch Lô 5 =
        1.000 SIP trong khi cả lò 3.613 SIP -- chứng minh không cộng dồn);
        MAG = kệ Magaziner vật lý trong batch, lò không kệ -> ceil(panel/8);
        batch dự kiến TƯƠNG LAI (07:49 sáng hôm sau) KHÔNG bị chọn sớm; cấu
        trúc phẳng không Batch -> fallback oven-level đúng
      + Phần C (10 case): DoneId "<lò> • Lô N" đủ biến thể; DoneAgo "Vừa xong"
        / "N phút trước" / "N giờ M phút trước"
  - Hồi quy: test_luong_dieu_huong.py PASS (luồng Step1-4 + 73 tham chiếu
    $global:e khớp x:Name 100%); test_ne_nhan.py PASS (1.002.001 tổ hợp);
    cân bằng ngoặc toàn bộ file OK (UI.txt là false positive đã biết do dấu
    ')' trong comment XAML).

GHI CHÚ TRIỂN KHAI (cập nhật v2,6): NAP_DB_LICH_SU_NGAY tự nhận diện 2 định dạng
(XML thuần HOẶC AES+GZip) nên KHÔNG phụ thuộc việc hệ thống nguồn có mã hoá file
lịch sử hay không (user xác nhận file thật sẽ được mã hoá). Nếu ngày ca hiện tại
chưa có file <yyyyMMdd>.db, phần "OVEN HOÀN THÀNH GẦN NHẤT" hiển thị "--" +
"Chưa có dữ liệu ca này" -- app KHÔNG lỗi, mọi nguồn còn lại hoạt động bình
thường. Từ v2,6: section này thể hiện thông tin BATCH có finish gần nhất trong
lò (DoneId = "mã lò • Lô cycle", DoneTotal = SIP riêng batch đó) thay vì cộng
dồn cả lò. Cột MAG = số KỆ Magaziner vật lý (đếm node); lò không dùng kệ (panel
thẳng) -> ước lượng ceil(số panel / 8).

GHI CHÚ KỸ THUẬT: toàn bộ file giữ nguyên encoding UTF-8 (BOM) + line-ending CRLF
như bản gốc. Có thể áp dụng trực tiếp bằng cách đổi đuôi .txt về .ps1/.psm1/.xaml
theo đúng cấu trúc dự án (main.txt -> main.ps1; UI/OvenRanking/MiniMap.txt -> .xaml;
các module *.txt -> Modules/*.psm1; USER/SETTINGS/MO.txt là dữ liệu mẫu tham khảo).
================================================================================
