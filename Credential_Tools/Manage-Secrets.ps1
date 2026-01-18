<#
.SYNOPSIS
    集中式憑證管理工具 (CLI)
.DESCRIPTION
    這是唯一的管理介面。請使用此工具來新增、更新或查詢所有的加密憑證。
    其他業務腳本不應包含建立憑證的邏輯。
.EXAMPLE
    .\Manage-Secrets.ps1
#>

# 設定模組路徑 (移動至子目錄)
$ModulePath = Join-Path $PSScriptRoot "Modules" | Join-Path -ChildPath "CredentialManager.psm1"

# 設定全域憑證庫路徑 (存放於 Data 子目錄)
$GlobalSecretPath = Join-Path $PSScriptRoot "Data" | Join-Path -ChildPath "Global_Credentials.xml"

# 載入模組
if (-not (Test-Path $ModulePath)) {
    Write-Error "找不到核心模組: $ModulePath"
    exit
}
Import-Module $ModulePath -Force

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    🔐 集中式憑證管理控制台 (Admin)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "儲存庫: $GlobalSecretPath"
    Write-Host "------------------------------------------"
    Write-Host "1. 列出所有憑證 (List)"
    Write-Host "2. 新增/更新憑證 (Upsert)"
    Write-Host "3. 測試讀取憑證 (Test)"
    Write-Host "Q. 離開 (Quit)"
    Write-Host "------------------------------------------"
}

# --- 主迴圈 ---
do {
    Show-Menu
    $Choice = Read-Host "請選擇功能 [1-3, Q]"

    switch ($Choice) {
        "1" { 
            Write-Host "`n--- 憑證清單 ---" -ForegroundColor Yellow
            Get-StoredCredentialList -StorePath $GlobalSecretPath | Format-Table -AutoSize
            Pause
        }
        "2" {
            Write-Host "`n--- 新增/更新憑證 ---" -ForegroundColor Yellow
            $KeyName = Read-Host "請輸入識別名稱 (Key, 例如 DB_Prod)"
            if (-not [string]::IsNullOrWhiteSpace($KeyName)) {
                $Desc = Read-Host "請輸入描述 (Description, 選填)"
                try {
                    New-StoredCredential -Key $KeyName -StorePath $GlobalSecretPath -Description $Desc
                    Write-Host "✅ 設定完成！" -ForegroundColor Green
                } catch {
                    Write-Error "設定失敗: $_"
                }
            }
            Pause
        }
        "3" {
            Write-Host "`n--- 測試讀取 ---" -ForegroundColor Yellow
            $KeyName = Read-Host "請輸入要測試的 Key"
            try {
                $Cred = Get-StoredCredential -Key $KeyName -StorePath $GlobalSecretPath
                Write-Host "讀取成功！" -ForegroundColor Green
                Write-Host "帳號: $($Cred.UserName)"
                Write-Host "密碼: (已隱藏)"
            } catch {
                Write-Error "讀取失敗: $_"
            }
            Pause
        }
        "Q" { 
            Write-Host "Bye!"
            break 
        }
        default { 
            Write-Warning "無效的選擇"
            Start-Sleep -Seconds 1 
        }
    }
} until ($Choice -eq "Q")
