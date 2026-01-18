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

# 設定資料目錄
$DataDir = Join-Path $PSScriptRoot "Data"
if (-not (Test-Path $DataDir)) { New-Item -Path $DataDir -ItemType Directory | Out-Null }

# 載入模組
if (-not (Test-Path $ModulePath)) {
    Write-Error "找不到核心模組: $ModulePath"
    exit
}
Import-Module $ModulePath -Force

# --- 檔案選擇器函式 ---
function Select-CredentialFile {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    📂 選擇憑證儲存庫 (XML)" -ForegroundColor Cyan
    Write-Host "=========================================="
    
    $Files = Get-ChildItem -Path $DataDir -Filter "*.xml"
    $Index = 1
    $Selection = @{}

    if ($Files.Count -eq 0) {
        Write-Host " (目前無任何檔案)" -ForegroundColor Gray
    } else {
        foreach ($File in $Files) {
            Write-Host " [$Index] $($File.Name)"
            $Selection[$Index] = $File.FullName
            $Index++
        }
    }
    Write-Host " [N] 建立新檔案 (New)"
    Write-Host "------------------------------------------"
    
    $Choice = Read-Host "請選擇 [1-$($Index-1)] 或 [N]"
    
    if ($Choice -match "^[nN]") {
        $NewName = Read-Host "請輸入新檔名 (不含路徑, 例如 MySecrets)"
        if (-not $NewName.EndsWith(".xml")) { $NewName += ".xml" }
        return Join-Path $DataDir $NewName
    }
    elseif ($Selection.ContainsKey([int]$Choice)) {
        return $Selection[[int]$Choice]
    }
    else {
        return $null
    }
}

# --- 啟動流程 ---
$TargetXmlPath = Select-CredentialFile
if (-not $TargetXmlPath) {
    Write-Warning "未選擇檔案，程式結束。"
    exit
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    🔐 集中式憑證管理控制台 (Admin)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "目標檔案: $(Split-Path $TargetXmlPath -Leaf)"
    
    # 顯示目前檔案的模式狀態
    $CurrentMode = Get-CredentialStoreMode -StorePath $TargetXmlPath
    if ($CurrentMode -eq "EMPTY") {
        Write-Host "檔案狀態: [新檔案] (尚未初始化)" -ForegroundColor Gray
    } else {
        Write-Host "檔案狀態: [$CurrentMode 模式]" -ForegroundColor Green
    }
    
    # 顯示配對的 Key 狀態 (僅 AES 模式)
    if ($CurrentMode -eq "AES" -or $CurrentMode -eq "EMPTY") {
        $KeyPath = [System.IO.Path]::ChangeExtension($TargetXmlPath, ".key")
        if (Test-Path $KeyPath) {
            Write-Host "金鑰狀態: [已存在] $(Split-Path $KeyPath -Leaf)" -ForegroundColor Green
        } else {
            Write-Host "金鑰狀態: [未建立] (將於首次寫入時自動產生)" -ForegroundColor Yellow
        }
    }

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
            Get-StoredCredentialList -StorePath $TargetXmlPath | Format-Table -AutoSize
            Pause
        }
        "2" {
            Write-Host "`n--- 新增/更新憑證 ---" -ForegroundColor Yellow
            $KeyName = Read-Host "請輸入識別名稱 (Key, 例如 DB_Prod)"
            
            if (-not [string]::IsNullOrWhiteSpace($KeyName)) {
                $Desc = Read-Host "請輸入描述 (Description, 選填)"
                
                # 判斷模式
                $ModeToUse = "AES" # 預設值
                $FileMode = Get-CredentialStoreMode -StorePath $TargetXmlPath
                
                if ($FileMode -eq "EMPTY") {
                    # 如果是新檔案，詢問使用者
                    Write-Host "`n此為新檔案，請選擇加密模式："
                    Write-Host " [A] AES (跨平台通用，需搭配 .key 檔)"
                    Write-Host " [D] DPAPI (Windows 專用，綁定本機使用者)"
                    $ModeInput = Read-Host "請選擇 [A/D]"
                    if ($ModeInput -match "^[dD]") { $ModeToUse = "DPAPI" }
                    else { $ModeToUse = "AES" }
                } elseif ($FileMode -ne "UNKNOWN") {
                    # 如果是既有檔案，強制沿用
                    $ModeToUse = $FileMode
                    Write-Host "偵測到現有檔案使用 [$ModeToUse] 模式，將自動沿用。" -ForegroundColor Gray
                }

                # 若為 AES 且需要初始化 (或首次設定)，確認 Key 檔名
                $KeyFilename = "master.key" # Default
                if ($ModeToUse -eq "AES" -and $FileMode -eq "EMPTY") {
                     Write-Host "`n請指定 Key 檔案名稱 (預設: master.key)"
                     Write-Host "您可以輸入自訂名稱 (如 common.key) 讓多個 XML 共用同一把鑰匙。" -ForegroundColor Gray
                     $InputKeyName = Read-Host "Key 檔名"
                     if (-not [string]::IsNullOrWhiteSpace($InputKeyName)) {
                         $KeyFilename = $InputKeyName
                     }
                     if (-not $KeyFilename.EndsWith(".key")) { $KeyFilename += ".key" }
                }

                try {
                    New-StoredCredential -Key $KeyName -StorePath $TargetXmlPath -Description $Desc -Mode $ModeToUse -MasterKeyFilename $KeyFilename
                    Write-Host "✅ 設定完成！" -ForegroundColor Green
                } catch {
                    $ErrMsg = $_.Exception.Message
                    if (-not $ErrMsg) { $ErrMsg = $_.ToString() }
                    Write-Host "❌ 設定失敗: $ErrMsg" -ForegroundColor Red
                    Write-CredentialLog -Message $ErrMsg -Level "ERROR" -TargetKey $KeyName
                }
            }
            Pause
        }
        "3" {
            Write-Host "`n--- 測試讀取 ---" -ForegroundColor Yellow
            $KeyName = Read-Host "請輸入要測試的 Key"
            try {
                $Cred = Get-StoredCredential -Key $KeyName -StorePath $TargetXmlPath
                Write-Host "讀取成功！" -ForegroundColor Green
                Write-Host "帳號/身分: $($Cred.UserName)"
                Write-Host "密碼/內容: (已隱藏)"
            } catch {
                $ErrMsg = $_.Exception.Message
                if (-not $ErrMsg) { $ErrMsg = $_.ToString() }
                Write-Host "❌ 讀取失敗: $ErrMsg" -ForegroundColor Red
                Write-CredentialLog -Message $ErrMsg -Level "ERROR" -TargetKey $KeyName
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