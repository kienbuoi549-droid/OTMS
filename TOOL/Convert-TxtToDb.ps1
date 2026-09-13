# ================================================================
# Convert-TxtToDb.ps1  (v2 -- xu ly loi manh + tu nhan dien encoding)
# Chuyen doi file .txt (JSON/XML thuan) sang file .db ma hoa
# Dung CHINH XAC pipeline ma hoa giong OTMSAnalyzer:
#   Van ban -> UTF-8 -> Nen GZip -> Ma hoa AES-256-CBC -> File .db
#
# Cach dung:
#   1 file:     .\Convert-TxtToDb.ps1 -InputPath "MO.txt" -OutputPath "Data\MO.db"
#   Ca thu muc: .\Convert-TxtToDb.ps1 -InputFolder ".\SampleTxt" -OutputFolder ".\Data"
#
# LUU Y: Neu duong dan co dau cach, PHAI dat trong dau ngoac kep "..."
# ================================================================
param(
    [string]$InputPath,
    [string]$OutputPath,
    [string]$InputFolder,
    [string]$OutputFolder
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$global:CO_LOI = $false

# ── Khoa AES va Vecto khoi tao (IV) -- PHAI khop voi Variable.psm1 cua app ──
$AES_KEY = [byte[]](
    0x4F,0x56,0x45,0x4E,0x44,0x42,0x4B,0x45,
    0x59,0x32,0x30,0x32,0x35,0x4F,0x54,0x4D,
    0x53,0x41,0x45,0x53,0x32,0x35,0x36,0x42,
    0x49,0x54,0x4B,0x45,0x59,0x46,0x4F,0x52
)
$AES_IV = [byte[]](
    0x4F,0x54,0x4D,0x53,0x49,0x56,0x31,0x36,
    0x42,0x59,0x54,0x45,0x32,0x30,0x32,0x35
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ── Doc file .txt bang moi encoding co the -- tu nhan dien qua BOM ──
# (Fix quan trong: KHONG ep cung -Encoding UTF8, vi file that co the la
#  UTF-16 (Notepad "Unicode"), UTF-8-BOM, hoac ANSI tuy nguon tao file)
function DOC_TXT_TU_DONG_NHAN_DIEN([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        # UTF-8 co BOM
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        # UTF-16 LE (Notepad "Unicode")
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        # UTF-16 BE
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    # Khong co BOM -- thu UTF-8 truoc (phu hop JSON/XML chuan)
    $asUtf8 = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($asUtf8 -notmatch [char]0xFFFD) {
        return $asUtf8
    }
    # UTF-8 that bai (co ky tu loi) -- fallback ve ANSI he thong (vi du Windows-1258 cho tieng Viet)
    Write-Warning "  (!) File khong phai UTF-8 chuan, dang thu doc bang ANSI he thong: $path"
    return [System.Text.Encoding]::Default.GetString($bytes)
}

# ── Nen GZip ──
function NEN_GZIP([byte[]]$data) {
    $ms = New-Object System.IO.MemoryStream
    $gz = New-Object System.IO.Compression.GZipStream(
              $ms, [System.IO.Compression.CompressionMode]::Compress)
    $gz.Write($data, 0, $data.Length)
    $gz.Close()
    return $ms.ToArray()
}

# ── Ma hoa AES-256-CBC ──
function MA_HOA_AES([byte[]]$data) {
    $aes = New-Object System.Security.Cryptography.AesCryptoServiceProvider
    $aes.KeySize   = 256
    $aes.BlockSize = 128
    $aes.Mode      = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding   = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key       = $AES_KEY
    $aes.IV        = $AES_IV
    $enc = $aes.CreateEncryptor()
    $ms  = New-Object System.IO.MemoryStream
    $cs  = New-Object System.Security.Cryptography.CryptoStream(
               $ms, $enc, [System.Security.Cryptography.CryptoStreamMode]::Write)
    $cs.Write($data, 0, $data.Length)
    $cs.FlushFinalBlock()
    $cs.Close(); $aes.Dispose()
    return $ms.ToArray()
}

# ── Chuyen 1 file .txt -> .db (co try/catch rieng, khong lam chet ca script) ──
function Convert-OneFile([string]$srcPath, [string]$dstPath) {
    try {
        if (-not (Test-Path -LiteralPath $srcPath)) {
            Write-Host "[LOI] Khong tim thay file nguon: $srcPath" -ForegroundColor Red
            $global:CO_LOI = $true
            return
        }

        $plaintext = DOC_TXT_TU_DONG_NHAN_DIEN $srcPath
        if ([string]::IsNullOrWhiteSpace($plaintext)) {
            Write-Host "[LOI] File rong hoac doc khong ra noi dung: $srcPath" -ForegroundColor Red
            $global:CO_LOI = $true
            return
        }

        $rawBytes   = [System.Text.Encoding]::UTF8.GetBytes($plaintext)
        $compressed = NEN_GZIP $rawBytes
        $encrypted  = MA_HOA_AES $compressed

        $dstDir = Split-Path -Parent $dstPath
        if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllBytes($dstPath, $encrypted)
        Write-Host "[OK] $srcPath -> $dstPath  ($($encrypted.Length) bytes)" -ForegroundColor Green
    }
    catch {
        Write-Host "[LOI] Khong the chuyen doi '$srcPath'" -ForegroundColor Red
        Write-Host "      Chi tiet: $($_.Exception.Message)" -ForegroundColor Red
        $global:CO_LOI = $true
    }
}

# ================================================================
# THAN CHINH -- boc trong try/catch tong de KHONG BAO GIO chet cham
# ================================================================
try {
    if ($InputPath) {
        # ── CHE DO 1: Chuyen 1 file don le ──
        if (-not $OutputPath) {
            Write-Host "[LOI] Phai chi dinh -OutputPath khi dung -InputPath" -ForegroundColor Red
            $global:CO_LOI = $true
        } else {
            Convert-OneFile -srcPath $InputPath -dstPath $OutputPath
        }
    }
    elseif ($InputFolder) {
        # ── CHE DO 2: Chuyen ca thu muc -- tu map ten file .txt -> .db ──
        if (-not $OutputFolder) { $OutputFolder = '.\Data' }

        if (-not (Test-Path -LiteralPath $InputFolder)) {
            Write-Host "[LOI] Khong tim thay thu muc: $InputFolder" -ForegroundColor Red
            $global:CO_LOI = $true
        } else {
            $MAP = @{
                'mo.txt'       = 'MO.db'
                'user.txt'     = 'USER.db'
                'settings.txt' = 'SETTINGS.db'
                'active.txt'   = 'DATABASE\Active.db'
            }
            $files = Get-ChildItem -LiteralPath $InputFolder -Filter '*.txt'
            if ($files.Count -eq 0) {
                Write-Host "[CANH BAO] Khong tim thay file .txt nao trong: $InputFolder" -ForegroundColor Yellow
            }
            foreach ($f in $files) {
                $keyName = $f.Name.ToLower()
                if ($MAP.ContainsKey($keyName)) {
                    $dst = Join-Path $OutputFolder $MAP[$keyName]
                }
                elseif ($f.BaseName -match '^\d{8}') {
                    $dateStr = ($f.BaseName -replace '[^\d]', '').Substring(0,8)
                    $dst = Join-Path $OutputFolder "DATABASE\$dateStr.db"
                }
                else {
                    Write-Host "[BO QUA] Khong nhan dien duoc ten file: $($f.Name)" -ForegroundColor Yellow
                    continue
                }
                Convert-OneFile -srcPath $f.FullName -dstPath $dst
            }
        }
    }
    else {
        Write-Host "Dung:" -ForegroundColor Cyan
        Write-Host '  1 file:     .\Convert-TxtToDb.ps1 -InputPath "MO.txt" -OutputPath "Data\MO.db"'
        Write-Host '  Ca thu muc: .\Convert-TxtToDb.ps1 -InputFolder ".\SampleTxt" -OutputFolder ".\Data"'
    }
}
catch {
    Write-Host ""
    Write-Host "[LOI NGHIEM TRONG] Script gap loi khong luong truoc:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    $global:CO_LOI = $true
}
finally {
    Write-Host ""
    if ($global:CO_LOI) {
        Write-Host "===== HOAN TAT -- CO LOI XAY RA, xem chi tiet ben tren =====" -ForegroundColor Red
    } else {
        Write-Host "===== HOAN TAT -- KHONG CO LOI =====" -ForegroundColor Green
    }
    # Luon dung lai -- neu double-click chay file nay, cua so se KHONG tu dong tat
    Write-Host ""
    Write-Host "Nhan phim bat ky de dong cua so nay..." -ForegroundColor Gray
    try {
        [void][System.Console]::ReadKey($true)
    } catch {
        # Mot so moi truong (ISE, terminal tich hop) khong ho tro ReadKey truc tiep
        Read-Host "Nhan Enter de dong"
    }
}
