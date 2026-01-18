<#
.SYNOPSIS
    業務腳本範本 (Client Script Template)
.DESCRIPTION
    這是標準的業務腳本範本，展示如何「唯讀」地使用憑證。
    此腳本不包含任何建立憑證的代碼。
#>

# --- 1. 初始化設定 ---
# 指向共用的憑證庫與模組 (建議寫在設定檔或固定路徑)
$ToolsDir = "C:\Path\To\Credential_Tools"  # 請依實際部署路徑修改
$SecretPath = Join-Path $ToolsDir "Global_Credentials.xml"
$ModulePath = Join-Path $ToolsDir "CredentialManager.psm1"

# --- 2. 載入憑證模組 ---
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
} else {
    Throw "找不到憑證模組，無法繼續執行。"
}

# --- 3. 取得所需憑證 ---
try {
    # 只需一行指令，乾淨俐落
    $DbCred = Get-StoredCredential -Key "DB_Production" -StorePath $SecretPath
    
    Write-Host "成功取得資料庫憑證: $($DbCred.UserName)"
} catch {
    Write-Error "無法取得憑證 [DB_Production]。請聯絡管理員使用 Manage-Secrets.ps1 進行設定。"
    exit 1
}

# --- 4. 開始業務邏輯 ---
Write-Host "正在連線至資料庫..."
# Connect-SqlInstance -Credential $DbCred ...
