<#
.SYNOPSIS
    建立並加密憑證檔案 (POC 產生器)
.DESCRIPTION
    此腳本用於產生 PowerShell 排程所需的加密憑證檔 (.xml)。
    支援兩種模式：
    1. Interactive (預設): 彈出視窗讓管理者輸入真實帳密。
    2. Simulated: 使用寫死的假資料快速產生 (僅供測試)。
.EXAMPLE
    .\Generate_Credentials.ps1 -Path "C:\Temp\Creds.xml" -Mode Interactive
.EXAMPLE
    .\Generate_Credentials.ps1 -Path "C:\Temp\Creds.xml" -Mode Simulated
#>

param(
    [string]$Path = "$HOME/My_Secured_Creds.xml",
    
    [ValidateSet("Interactive", "Simulated")]
    [string]$Mode = "Interactive"
)

$Store = @{}

Write-Host "=== 啟動憑證建立程序 ===" -ForegroundColor Cyan
Write-Host "模式: $Mode"
Write-Host "輸出: $Path"
Write-Host "---------------------------"

if ($Mode -eq "Simulated") {
    # --- 模擬模式 (POC) ---
    Write-Host "正在建立模擬資料..." -ForegroundColor Yellow
    
    $Store["AppServer"] = New-Object System.Management.Automation.PSCredential (
        "AppAdmin_Mock", 
        ("MockPass_123" | ConvertTo-SecureString -AsPlainText -Force)
    )
    $Store["DbServer"]  = New-Object System.Management.Automation.PSCredential (
        "DbAdmin_Mock", 
        ("MockPass_456" | ConvertTo-SecureString -AsPlainText -Force)
    )
    
} else {
    # --- 互動模式 (管理者輸入) ---
    Write-Host "請依序輸入憑證資料 (將彈出視窗)..." -ForegroundColor Yellow
    
    # 這裡定義您需要哪些憑證
    $RequiredKeys = @("AppServer", "DbServer")
    
    foreach ($Key in $RequiredKeys) {
        Write-Host "正在請求 [$Key] 的憑證..." -NoNewline
        $Store[$Key] = Get-Credential -Message "請輸入 [$Key] 的帳號密碼"
        Write-Host " [OK]" -ForegroundColor Green
    }
}

# --- 執行加密匯出 ---
try {
    $Store | Export-Clixml -Path $Path -ErrorAction Stop
    Write-Host "`n✅ 憑證庫已成功加密並匯出！" -ForegroundColor Green
    Write-Host "檔案路徑: $Path"
    Write-Host "安全性提示: 此檔案僅能由當前使用者 ($env:USERNAME) 在此電腦 ($env:COMPUTERNAME) 上解密。" -ForegroundColor Gray
} catch {
    Write-Error "❌ 匯出失敗: $_"
}
