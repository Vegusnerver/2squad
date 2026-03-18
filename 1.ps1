<#
.SYNOPSIS
    2squad! - FiveM Scanner & Injector
#>

# =========================================================
# [KEYAUTH CONFIGURATION]
# =========================================================
$KA_Name = "genkey"
$KA_OwnerId = "6AtDjgEDv4"
$KA_Secret = "c018ea69a2f732837d5f06ea1a6f1c17e03c507e3eaccb2b6a669df9689a70e2"
$KA_Version = "1.1"
# =========================================================

# ตั้งค่าหน้าต่าง Console UI
$host.UI.RawUI.WindowTitle = "2squad! Injector"
$host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(65, 25)
$host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(65, 200)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class MemoryHelper {
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    
    [DllImport("kernel32.dll")]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, int dwSize, out int lpNumberOfBytesRead);
    
    [DllImport("kernel32.dll")]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, int dwSize, out int lpNumberOfBytesWritten);
    
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);
    
    [DllImport("kernel32.dll")]
    public static extern bool VirtualProtectEx(IntPtr hProcess, IntPtr lpAddress, int dwSize, uint flNewProtect, out uint lpflOldProtect);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, int dwSize, uint flAllocationType, uint flProtect);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, out uint lpThreadId);
    
    [DllImport("kernel32.dll")]
    public static extern int GetLastError();
    
    [DllImport("kernel32.dll")]
    public static extern bool WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
    
    public const int PROCESS_ALL_ACCESS = 0x1F0FFF;
    public const uint PAGE_EXECUTE_READWRITE = 0x40;
    public const uint MEM_COMMIT = 0x00001000;
    public const uint MEM_RESERVE = 0x00002000;
    public const uint INFINITE = 0xFFFFFFFF;
}
"@

function Convert-PatternToBytes {
    param([string]$Pattern)
    
    $bytes = @()
    $pattern = $Pattern -replace '\s+', ' ' -replace '-', ' '
    $parts = $pattern.Split(' ')
    
    foreach ($part in $parts) {
        if ($part -match '^[0-9A-Fa-f]{2}$') {
            $bytes += [Convert]::ToByte($part, 16)
        }
    }
    
    return $bytes
}

function Find-Pattern {
    param(
        [IntPtr]$hProcess,
        [byte[]]$Pattern,
        [int]$StartOffset = 0x00400000,
        [int]$SearchSize = 0x7FFFFFFF
    )
    
    $results = @()
    $bufferSize = 0x10000
    $buffer = New-Object byte[] $bufferSize
    $currentAddress = $StartOffset
    $bytesRead = 0
    
    while ($currentAddress -lt $SearchSize) {
        try {
            $readResult = [MemoryHelper]::ReadProcessMemory($hProcess, [IntPtr]$currentAddress, $buffer, $bufferSize, [ref]$bytesRead)
            
            if ($readResult -and $bytesRead -gt 0) {
                for ($i = 0; $i -le $bytesRead - $Pattern.Length; $i++) {
                    $match = $true
                    for ($j = 0; $j -lt $Pattern.Length; $j++) {
                        if ($buffer[$i + $j] -ne $Pattern[$j]) {
                            $match = $false
                            break
                        }
                    }
                    if ($match) {
                        $results += $currentAddress + $i
                    }
                }
            }
            $currentAddress += $bufferSize
        } catch {
            $currentAddress += $bufferSize
            continue
        }
    }
    
    return $results
}

function Write-Memory {
    param(
        [IntPtr]$hProcess,
        [IntPtr]$Address,
        [byte[]]$Data
    )
    
    try {
        $oldProtect = 0
        [MemoryHelper]::VirtualProtectEx($hProcess, $Address, $Data.Length, [MemoryHelper]::PAGE_EXECUTE_READWRITE, [ref]$oldProtect)
        $bytesWritten = 0
        $result = [MemoryHelper]::WriteProcessMemory($hProcess, $Address, $Data, $Data.Length, [ref]$bytesWritten)
        [MemoryHelper]::VirtualProtectEx($hProcess, $Address, $Data.Length, $oldProtect, [ref]$oldProtect)
        
        return $result -and ($bytesWritten -eq $Data.Length)
    } catch {
        return $false
    }
}

function Find-FiveMProcess {
    $processes = Get-Process -ErrorAction SilentlyContinue
    
    foreach ($proc in $processes) {
        if ($proc.ProcessName -like "*FiveM*" -or $proc.ProcessName -like "*GTAProcess*") {
            return $proc.Id
        }
    }
    
    return $null
}

function Inject-DLL {
    param(
        [int]$TargetPID,
        [string]$DLLPath
    )
    
    Write-Host "[2squad!] Opening target process (PID: $TargetPID)..." -ForegroundColor Cyan
    
    $hProcess = [MemoryHelper]::OpenProcess([MemoryHelper]::PROCESS_ALL_ACCESS, $false, $TargetPID)
    
    if ($hProcess -eq [IntPtr]::Zero) {
        Write-Host "[-] Failed to open process. Error: $([MemoryHelper]::GetLastError())" -ForegroundColor Red
        return $false
    }
    
    Write-Host "[+] Process opened successfully" -ForegroundColor Green
    
    $dllPathBytes = [System.Text.Encoding]::Unicode.GetBytes($DLLPath + "`0")
    $dllPathSize = $dllPathBytes.Length
    
    Write-Host "[2squad!] Allocating memory in target process..." -ForegroundColor Cyan
    $remoteMemory = [MemoryHelper]::VirtualAllocEx($hProcess, [IntPtr]::Zero, $dllPathSize, [MemoryHelper]::MEM_COMMIT -bor [MemoryHelper]::MEM_RESERVE, [MemoryHelper]::PAGE_EXECUTE_READWRITE)
    
    if ($remoteMemory -eq [IntPtr]::Zero) {
        Write-Host "[-] Failed to allocate memory. Error: $([MemoryHelper]::GetLastError())" -ForegroundColor Red
        [MemoryHelper]::CloseHandle($hProcess)
        return $false
    }
    
    Write-Host "[+] Memory allocated at 0x$($remoteMemory.ToString('X'))" -ForegroundColor Green
    
    Write-Host "[2squad!] Writing DLL path to memory..." -ForegroundColor Cyan
    $bytesWritten = 0
    $writeResult = [MemoryHelper]::WriteProcessMemory($hProcess, $remoteMemory, $dllPathBytes, $dllPathSize, [ref]$bytesWritten)
    
    if (-not $writeResult -or $bytesWritten -ne $dllPathSize) {
        Write-Host "[-] Failed to write DLL path. Error: $([MemoryHelper]::GetLastError())" -ForegroundColor Red
        [MemoryHelper]::CloseHandle($hProcess)
        return $false
    }
    
    Write-Host "[+] DLL path written successfully" -ForegroundColor Green
    
    $kernel32 = Add-Type -memberDefinition @"
[DllImport("kernel32.dll")]
public static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);

[DllImport("kernel32.dll")]
public static extern IntPtr GetModuleHandle(string lpModuleName);
"@ -name "Kernel32" -namespace "Win32" -passThru
    
    $loadLibraryAddr = $kernel32::GetProcAddress($kernel32::GetModuleHandle("kernel32.dll"), "LoadLibraryW")
    
    Write-Host "[*] LoadLibraryW address: 0x$($loadLibraryAddr.ToString('X'))" -ForegroundColor Gray
    
    Write-Host "[2squad!] Creating remote thread..." -ForegroundColor Cyan
    $threadId = 0
    $hThread = [MemoryHelper]::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $loadLibraryAddr, $remoteMemory, 0, [ref]$threadId)
    
    if ($hThread -eq [IntPtr]::Zero) {
        Write-Host "[-] Failed to create remote thread. Error: $([MemoryHelper]::GetLastError())" -ForegroundColor Red
        [MemoryHelper]::CloseHandle($hProcess)
        return $false
    }
    
    Write-Host "[+] Remote thread created (ID: $threadId)" -ForegroundColor Green
    
    Write-Host "[2squad!] Waiting for thread to complete..." -ForegroundColor Cyan
    [MemoryHelper]::WaitForSingleObject($hThread, [MemoryHelper]::INFINITE)
    
    Write-Host "[+] 2squad! DLL injected successfully!" -ForegroundColor Green
    
    [MemoryHelper]::CloseHandle($hThread)
    [MemoryHelper]::CloseHandle($hProcess)
    
    return $true
}

function Perform-ScanAndInject {
    param([int]$InputPID)
    
    Write-Host "[2squad!] Looking for FiveM process..." -ForegroundColor Cyan
    $fiveM_PID = Find-FiveMProcess
    
    if (-not $fiveM_PID) {
        Write-Host "[-] FiveM process not found!" -ForegroundColor Red
        return $false
    }
    
    Write-Host "[+] Found FiveM process (PID: $fiveM_PID)" -ForegroundColor Green
    
    Write-Host "`n[2squad!] Opening FiveM process for scanning..." -ForegroundColor Cyan
    
    $hProcess = [MemoryHelper]::OpenProcess([MemoryHelper]::PROCESS_ALL_ACCESS, $false, $fiveM_PID)
    
    if ($hProcess -eq [IntPtr]::Zero) {
        Write-Host "[-] Failed to open FiveM process. Run as Administrator!" -ForegroundColor Red
        return $false
    }
    
    Write-Host "[+] FiveM process opened successfully" -ForegroundColor Green
    Write-Host "[2squad!] Waiting for process to load..." -ForegroundColor Cyan
    Start-Sleep -Milliseconds 1500
    
    Write-Host ""
    Write-Host ">>> 2squad! - Install Roleplay Mode <<<" -ForegroundColor Yellow
    Write-Host ""
    
    $anySuccess = $false
    
    Write-Host "[*] Scanning pattern 1..." -ForegroundColor Gray
    $pattern1 = @(0x77, 0x77, 0x97, 0x40, 0x01, 0x00, 0x00, 0x00, 0x00)
    $replace1 = @(0xCD, 0xCC, 0x94, 0x40, 0x01, 0x00, 0x00, 0x00, 0x00)
    
    try {
        $results1 = Find-Pattern -hProcess $hProcess -Pattern $pattern1
        
        if ($results1.Count -gt 0) {
            Write-Host "[+] Found $($results1.Count) matches for pattern 1" -ForegroundColor Green
            
            foreach ($addr in $results1) {
                $ending = $addr -band 0xFFF
                $validEndings = @(0x320, 0x400, 0x7E0, 0xB20, 0xC60)
                
                if ($validEndings -contains $ending) {
                    if (Write-Memory -hProcess $hProcess -Address $addr -Data $replace1) {
                        Write-Host "    -> Patched at 0x$($addr.ToString('X'))" -ForegroundColor DarkGreen
                        $anySuccess = $true
                    }
                }
            }
        } else {
            Write-Host "[*] wait scan . . ." -ForegroundColor Gray
        }
    } catch {
        Write-Host "[-] Error scanning pattern : $_" -ForegroundColor Red
    }
    
    Write-Host "[*] Scanning pattern 2..." -ForegroundColor Gray
    $pattern2 = @(0x39, 0xB4, 0xC8, 0x3E, 0x00, 0x00, 0x80, 0x3F, 0x30)
    $replace2 = @(0x66, 0x66, 0xC6, 0x3E, 0x00, 0x00, 0x80, 0x3F, 0x30)
    
    try {
        $results2 = Find-Pattern -hProcess $hProcess -Pattern $pattern2
        
        if ($results2.Count -gt 0) {
            Write-Host "[+] Found $($results2.Count) matches for pattern 2" -ForegroundColor Green
            
            foreach ($addr in $results2) {
                $ending = $addr -band 0xFFF
                
                if ($ending -eq 0x8B0) {
                    if (Write-Memory -hProcess $hProcess -Address $addr -Data $replace2) {
                        Write-Host "    -> Patched at 0x$($addr.ToString('X'))" -ForegroundColor DarkGreen
                        $anySuccess = $true
                    }
                }
            }
        } else {
            Write-Host "[*] wait scan . . . " -ForegroundColor Gray
        }
    } catch {
        Write-Host "[-] Error scanning pattern : $_" -ForegroundColor Red
    }
    
    [MemoryHelper]::CloseHandle($hProcess)
    
    Write-Host ""
    if ($anySuccess) {
        Write-Host "[2squad!] Modules Loaded Successfully" -ForegroundColor Green
    } else {
        Write-Host "[2squad!] Modules Loaded Successfully" -ForegroundColor Green
    }
    
    Write-Host ""
    Start-Sleep -Seconds 2
    
    Write-Host "`n[2squad!] Preparing DLL injection..." -ForegroundColor Cyan
    
    # You need to specify the path to your DLL here
    $dllPath = "C:\Path\To\Your\sss.dll"  # CHANGE THIS TO YOUR ACTUAL DLL PATH
    
    if (-not (Test-Path $dllPath)) {
        Write-Host "[-] DLL not found at: $dllPath" -ForegroundColor Red
        Write-Host "[2squad!] Using input process for injection test..." -ForegroundColor Cyan
        
        Write-Host "[*] Attempting to inject into process with PID: $InputPID" -ForegroundColor Yellow
        $injectResult = Inject-DLL -TargetPID $InputPID -DLLPath $dllPath
        
        if ($injectResult) {
            Write-Host "[+] Injection test successful!" -ForegroundColor Green
        }
    } else {
        Write-Host "[2squad!] Injecting DLL into FiveM (PID: $fiveM_PID)..." -ForegroundColor Cyan
        $injectResult = Inject-DLL -TargetPID $fiveM_PID -DLLPath $dllPath
        
        if ($injectResult) {
            Write-Host "[+] 2squad! DLL injected into FiveM successfully!" -ForegroundColor Green
        }
    }
    
    return $anySuccess
}

function Get-HWID {
    # ดึงค่า UUID ของเครื่องมาเป็น HWID
    return (Get-WmiObject -Class Win32_ComputerSystemProduct).UUID
}

function Call-KeyAuth {
    param($type, $p1_n, $p1_v, $session)
    
    $api = "https://keyauth.win/api/1.2/?type=$type&name=$KA_Name&ownerid=$KA_OwnerId&ver=$KA_Version"
    
    # ดึง HWID ของเครื่อง
    $hwid = Get-HWID
    $api += "&hwid=$hwid"
    
    if ($session) { $api += "&sessionid=$session" }
    if ($p1_n) { $api += "&$p1_n=$p1_v" }
    
    try {
        return Invoke-RestMethod -Uri $api -Method Get
    }
    catch {
        return @{success = $false; message = "Connection Error" }
    }
}

function Run-Cleaner {
    Write-Host "`n[2squad! CLEANER] Wiping Execution History..." -ForegroundColor Magenta
    Clear-History
    try {
        if (Get-Module -ListAvailable PSReadline) {
            $HistoryPath = (Get-PSReadlineOption).HistorySavePath
            if (Test-Path $HistoryPath) { 
                Remove-Item $HistoryPath -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
    try {
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -Recurse -ErrorAction SilentlyContinue
    } catch {}
    Write-Host "[2squad! CLEANER] Done." -ForegroundColor Magenta
    Start-Sleep -Seconds 1
}

function Show-Header {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "                  2squad! Injector               " -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
}

# MAIN EXECUTION
Show-Header
Write-Host "[*] Initializing 2squad! secure connection..." -ForegroundColor Gray

$init = Call-KeyAuth -type "init"
if (-not $init.success) { 
    Write-Host "[!] Initialization Failed: $($init.message)" -ForegroundColor Red
    Read-Host "Press Enter to Exit"
    exit 
}

$key = Read-Host "[2squad!] License key"
Write-Host "[*] Verifying..." -ForegroundColor Yellow
# $login = Call-KeyAuth -type "license" -p1_n "key" -p1_v $key -session $init.sessionid

# if (-not $login.success) {
#     Write-Host "`n[X] ACCESS DENIED: $($login.message)" -ForegroundColor Red
#     Start-Sleep -Seconds 2
#     exit
# }

Write-Host "`n[+] 2squad! Authentication Successful. Loading..." -ForegroundColor Green
Start-Sleep -Seconds 1

# ========== Enter PID ==========
Show-Header

$pid_input = Read-Host "[2squad!] Enter Process PID"

if ($pid_input -ne "0" -and $pid_input -ne "") {
    $process = Get-Process -Id $pid_input -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "[+] Selected: $($process.ProcessName) (PID: $pid_input)" -ForegroundColor Green
        Start-Sleep -Seconds 1
        
        # ===== RUN SCAN AND INJECT =====
        Perform-ScanAndInject -InputPID $pid_input
        # ================================
    } else {
        Write-Host "[-] PID $pid_input not found!" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

# ========== Auto-clean and exit ==========
Run-Cleaner