<#
.SYNOPSIS
    驗證憑證檔案解密 (POC 驗證器)
.DESCRIPTION
    此腳本模擬自動化排程的行為：
    1. 讀取加密的 .xml 檔案。
    2. 嘗試解密憑證。
    3. 顯示解密結果 (是否成功)。
.EXAMPLE
    .\Verify_Credentials.ps1 -Path "C:\Temp\Creds.xml"
#>

param(
    [string]$Path = (Join-Path $HOME "My_Secured_Creds.xml")
)

Write-Host "=== 啟動排程模擬 (憑證驗證) ===" -ForegroundColor Cyan
Write-Host "讀取檔案: $Path"

if (-not (Test-Path $Path)) {
    Write-Error "❌ 找不到檔案: $Path"
    exit
}

try {
    # 1. 匯入憑證庫
    $LoadedStore = Import-Clixml -Path $Path -ErrorAction Stop
    Write-Host "檔案讀取成功，包含 $($LoadedStore.Count) 組憑證。`n"

    # 2. 逐一驗證解密
    foreach ($Key in $LoadedStore.Keys) {
        $Cred = $LoadedStore[$Key]
        Write-Host "正在驗證 [$Key] ..." -NoNewline

        try {
            # 嘗試存取 Password 屬性 (如果解密失敗，這裡會拋出異常)
            # 使用 GetNetworkCredential().Password 會將 SecureString 轉為明文以供測試
            $PlainPass = $Cred.GetNetworkCredential().Password
            
            if (-not [string]::IsNullOrEmpty($PlainPass)) {
                Write-Host " [成功]" -ForegroundColor Green
                Write-Host "    帳號: $($Cred.UserName)"
                # 為了安全，實務上不要印出密碼，這裡僅顯示長度證明解密成功
                Write-Host "    密碼: (已解密，長度 $($PlainPass.Length) 字元)" 
            } else {
                Write-Host " [異常]" -ForegroundColor Red
                Write-Host "    原因: 密碼為空"
            }
        } catch {
            Write-Host " [失敗]" -ForegroundColor Red
            Write-Host "    原因: 無法解密 (Key not valid for use in specified state)"
            Write-Host "    說明: 當前使用者/電腦與建立檔案者不同。"
        }
        Write-Host "" # 空行
    }
    
    Write-Host "✅ 驗證程序結束。" -ForegroundColor Cyan

} catch {
    Write-Error "❌ 發生嚴重錯誤: $_"
}
