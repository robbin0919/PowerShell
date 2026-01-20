# -----------------------------------------------------------------------------
# 腳本名稱: Invoke_App_With_Credential.ps1
# 功能描述: 示範如何使用 CredentialManager 模組讀取加密的憑證
# -----------------------------------------------------------------------------

# --- 1. 初始化設定 (Configuration) ---
# 設定模組路徑 (指向 Modules 子目錄)
$ModulePath = Join-Path $PSScriptRoot "Modules\CredentialManager.psm1"

# 設定憑證庫路徑 (指向上層目錄的檔案)
$StorePath  = Join-Path (Split-Path $PSScriptRoot -Parent) "MySecrets.xml" 

# 設定 AES 金鑰路徑 (指向上層目錄的檔案)
$MasterKeyPath = Join-Path (Split-Path $PSScriptRoot -Parent) "master.key"

# --- 2. 載入憑證模組 (Import Module) ---
if (Test-Path $ModulePath) {
    Write-Host "正在載入模組: $ModulePath" -ForegroundColor Gray
    Import-Module $ModulePath -Force
} else {
    Write-Error "錯誤: 找不到模組檔案 [$ModulePath]。`n請確保 'Modules\CredentialManager.psm1' 存在。"
    exit 1
}

# --- 3. 取得憑證物件 (Get Credential) ---
# 設定您要讀取的 Key (識別名稱)
$TargetKey = "MyService" 

try {
    Write-Host "正在嘗試讀取憑證 Key: [$TargetKey] ..." -NoNewline
    
    # [核心指令] 讀取憑證
    # 透過 -MasterKeyPath 指定金鑰位置 (若 XML 與 Key 在不同目錄時很有用)
    $Cred = Get-StoredCredential -Key $TargetKey -StorePath $StorePath -MasterKeyPath $MasterKeyPath

    Write-Host " [成功]" -ForegroundColor Green

    # --- 4. 使用憑證範例 (Usage Examples) ---

    # 範例 A: 使用 PowerShell 原生指令 (支援 PSCredential 物件)
    # Invoke-RestMethod -Uri "https://api.example.com" -Credential $Cred
    # Connect-SqlInstance -Credential $Cred
    
    Write-Host "`n[範例 A] 取得的使用者帳號: $($Cred.UserName)"

    # 範例 B: 取出明文密碼 (僅在必要時使用，例如傳給不支援 PSCredential 的外部程式)
    $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Cred.Password)
    )
    
    Write-Host "[範例 B] 密碼解密成功 (長度: $($PlainPassword.Length) 字元)"
    Write-Host "        明文預覽: $($PlainPassword.Substring(0, [math]::Min(3, $PlainPassword.Length)))..." -ForegroundColor DarkGray

} catch {
    Write-Host " [失敗]" -ForegroundColor Red
    Write-Error "無法讀取憑證: $($_.Exception.Message)"
    
    Write-Host "`n[提示] 您可以使用以下指令檢查檔案中有哪些 Key:" -ForegroundColor Yellow
    Write-Host "Get-StoredCredentialList -StorePath `"$StorePath`"" -ForegroundColor Yellow
}
