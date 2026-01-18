# PowerShell Module
<#
.SYNOPSIS
    PowerShell 安全憑證管理模組
.DESCRIPTION
    此模組提供標準化的函式，用於建立、儲存與讀取加密的 PSCredential 物件。
    使用 Windows DPAPI 進行保護，確保憑證僅能在授權的機器與使用者下解密。
#>

# 定義路徑變數
$ParentDir = Split-Path $PSScriptRoot -Parent
# 預設憑證檔路徑
$DefaultStorePath = Join-Path $ParentDir "Data" | Join-Path -ChildPath "Global_Credentials.xml"
# 預設日誌檔路徑
$DefaultLogPath   = Join-Path $ParentDir "Logs" | Join-Path -ChildPath "Credential_Audit.log"

<#
.SYNOPSIS
    (內部函式) 寫入稽核日誌
#>
function Write-CredentialLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$TargetKey = "N/A"
    )
    
    # 確保日誌目錄存在
    $LogDir = Split-Path $DefaultLogPath -Parent
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory | Out-Null }

    # 格式: [時間] [層級] [使用者] [Key] 訊息
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] [$env:USERNAME] [$TargetKey] $Message"
    
    # 寫入檔案 (Append)
    Add-Content -Path $DefaultLogPath -Value $LogEntry -Encoding UTF8
    
    # 同步輸出到 Console (選擇性)
    if ($Level -eq "ERROR") { 
        Write-Error $Message 
    } elseif ($Level -eq "WARNING") { 
        Write-Warning $Message 
    } else {
        # 一般訊息僅記錄不一定印出，或印出灰色
        Write-Host "$Message" -ForegroundColor Gray
    }
}

<#
.SYNOPSIS
    儲存或更新憑證 (Admin Use)
.EXAMPLE
    New-StoredCredential -Key "DatabaseProd" -StorePath "C:\Secured\Creds.xml"
#>
function New-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Key,

        [Parameter(Mandatory=$false)]
        [string]$StorePath = $DefaultStorePath,

        [Parameter(Mandatory=$false)]
        [string]$Description = ""
    )

    Write-CredentialLog -Message "準備更新憑證: $Key" -Level "INFO" -TargetKey $Key

    # 1. 讀取現有檔案 (如果存在)
    $Store = @{}
    if (Test-Path $StorePath) {
        try {
            $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        } catch {
            Write-CredentialLog -Message "無法讀取現有檔案 ($StorePath): $_" -Level "WARNING" -TargetKey $Key
        }
    }

    # 2. 取得新憑證
    $Cred = Get-Credential -Message "設定 [$Key] 的帳號密碼"

    # 3. 更新記憶體中的儲存區
    $Store[$Key] = [PSCustomObject]@{
        Credential  = $Cred
        Description = $Description
        UpdatedBy   = $env:USERNAME
        UpdatedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    # 4. 寫回檔案 (加密)
    try {
        # 確保目錄存在
        $Dir = Split-Path $StorePath -Parent
        if (-not (Test-Path $Dir)) { New-Item -Path $Dir -ItemType Directory | Out-Null }

        $Store | Export-Clixml -Path $StorePath -Force
        
        Write-CredentialLog -Message "憑證更新成功。" -Level "INFO" -TargetKey $Key
        Write-Host "✅ 憑證 [$Key] 已成功儲存至: $StorePath" -ForegroundColor Green
    } catch {
        $ErrMsg = "寫入憑證檔失敗: $_"
        Write-CredentialLog -Message $ErrMsg -Level "ERROR" -TargetKey $Key
        throw $ErrMsg
    }
}

<#
.SYNOPSIS
    讀取憑證 (Script Use)
.EXAMPLE
    $Cred = Get-StoredCredential -Key "DatabaseProd"
    Connect-Db -Credential $Cred
#>
function Get-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Key,

        [Parameter(Mandatory=$false)]
        [string]$StorePath = $DefaultStorePath
    )

    if (-not (Test-Path $StorePath)) {
        $Msg = "找不到憑證儲存檔: $StorePath"
        Write-CredentialLog -Message $Msg -Level "ERROR" -TargetKey $Key
        throw $Msg
    }

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        
        if ($Store.ContainsKey($Key)) {
            $Item = $Store[$Key]
            
            # 寫入稽核日誌 (記錄誰在什麼時候讀取了哪個Key)
            Write-CredentialLog -Message "憑證存取成功" -Level "INFO" -TargetKey $Key

            # 相容性處理
            if ($Item -is [System.Management.Automation.PSCredential]) {
                return $Item
            } elseif ($Item.PSObject.Properties['Credential']) {
                return $Item.Credential
            } else {
                throw "儲存格式不符，無法讀取 [$Key]"
            }
        } else {
            $Msg = "找不到指定的 Key: [$Key]"
            Write-CredentialLog -Message $Msg -Level "WARNING" -TargetKey $Key
            throw $Msg
        }
    } catch {
        Write-CredentialLog -Message "存取失敗或解密錯誤: $_" -Level "ERROR" -TargetKey $Key
        throw
    }
}

<#
.SYNOPSIS
    列出所有可用憑證 Key (Info Use)
#>
function Get-StoredCredentialList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$StorePath = $DefaultStorePath
    )

    if (-not (Test-Path $StorePath)) {
        Write-Warning "檔案不存在: $StorePath"
        return
    }

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        
        # 列表操作通常不需每筆都 Log，只 Log 動作本身
        Write-CredentialLog -Message "執行憑證清單查詢" -Level "INFO"

        $Store.Keys | ForEach-Object {
            $Key = $_
            $Item = $Store[$Key]
            
            if ($Item -is [System.Management.Automation.PSCredential]) {
                [PSCustomObject]@{
                    Key = $Key
                    User = $Item.UserName
                    Updated = "N/A"
                    Desc = "Legacy Format"
                }
            } else {
                [PSCustomObject]@{
                    Key = $Key
                    User = $Item.Credential.UserName
                    Updated = $Item.UpdatedAt
                    Desc = $Item.Description
                }
            }
        }
    } catch {
        Write-Error "無法讀取清單: $_"
    }
}

# 匯出模組成員 (Write-CredentialLog 可視需求匯出或隱藏，此處匯出方便其他腳本也能寫入相關日誌)
Export-ModuleMember -Function New-StoredCredential, Get-StoredCredential, Get-StoredCredentialList, Write-CredentialLog