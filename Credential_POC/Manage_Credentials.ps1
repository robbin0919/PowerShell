<#
.SYNOPSIS
    管理憑證庫 (查詢與更新)
.DESCRIPTION
    此腳本用於維護已存在的加密憑證檔。
    功能：
    1. List: 列出目前檔案中儲存了哪些標籤 (Key) 與對應的帳號 (UserName)。
    2. Upsert: 更新現有憑證或新增一組新憑證。
.EXAMPLE
    .\Manage_Credentials.ps1 -Path "./My_Creds.xml" -Action List
.EXAMPLE
    .\Manage_Credentials.ps1 -Path "./My_Creds.xml" -Action Upsert -TargetKey "DbServer"
#>

param(
    [string]$Path = (Join-Path $HOME "My_Secured_Creds.xml"),
    
    [ValidateSet("List", "Upsert")]
    [string]$Action = "List",

    [string]$TargetKey = "" # 僅在 Upsert 模式下需要
)

if (-not (Test-Path $Path)) {
    Write-Warning "檔案不存在: $Path"
    if ($Action -eq "List") { exit }
    # 如果是 Upsert 且檔案不存在，則建立新的空雜湊表
    $Store = @{}
} else {
    try {
        $Store = Import-Clixml -Path $Path -ErrorAction Stop
    } catch {
        Write-Error "無法讀取檔案 (可能是權限不足或身分不符): $_"
        exit
    }
}

# --- 功能 1: 列出內容 (List) ---
if ($Action -eq "List") {
    Write-Host "=== 目前憑證庫清單 ===" -ForegroundColor Cyan
    Write-Host "檔案: $Path"
    Write-Host "---------------------------"
    
    if ($Store.Count -eq 0) {
        Write-Host "(空白)" -ForegroundColor Gray
    } else {
        $Store.Keys | ForEach-Object {
            $Cred = $Store[$_]
            Write-Host "標籤 (Key) : " -NoNewline
            Write-Host "$_" -ForegroundColor Yellow -NoNewline
            Write-Host " | 帳號: $($Cred.UserName)"
        }
    }
    Write-Host "---------------------------"
}

# --- 功能 2: 更新/新增 (Upsert) ---
if ($Action -eq "Upsert") {
    if ([string]::IsNullOrWhiteSpace($TargetKey)) {
        Write-Host "目前可用標籤: $($Store.Keys -join ', ')"
        $TargetKey = Read-Host "請輸入要新增或修改的標籤名稱 (Key)"
    }

    if ([string]::IsNullOrWhiteSpace($TargetKey)) {
        Write-Error "標籤名稱不能為空。"
        exit
    }

    Write-Host "正在設定 [$TargetKey] ..." -ForegroundColor Cyan
    
    # 彈出視窗取得新憑證
    $NewCred = Get-Credential -Message "請輸入 [$TargetKey] 的新帳號密碼"
    
    # 更新雜湊表
    $Store[$TargetKey] = $NewCred
    
    # 寫回檔案
    try {
        $Store | Export-Clixml -Path $Path -ErrorAction Stop
        Write-Host "✅ 更新成功！檔案已儲存至: $Path" -ForegroundColor Green
    } catch {
        Write-Error "❌ 寫入失敗: $_"
    }
}
