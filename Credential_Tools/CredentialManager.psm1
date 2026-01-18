<#
.SYNOPSIS
    PowerShell 安全憑證管理模組
.DESCRIPTION
    此模組提供標準化的函式，用於建立、儲存與讀取加密的 PSCredential 物件。
    使用 Windows DPAPI 進行保護，確保憑證僅能在授權的機器與使用者下解密。
#>

# 定義預設的憑證儲存路徑 (可由外部參數覆蓋)
$DefaultStorePath = Join-Path $PSScriptRoot "Global_Credentials.xml"

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

    Write-Host "正在設定憑證 [$Key]..." -ForegroundColor Cyan

    # 1. 讀取現有檔案 (如果存在)
    $Store = @{}
    if (Test-Path $StorePath) {
        try {
            $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        } catch {
            Write-Warning "無法讀取現有檔案，將建立新檔案。原因: $_"
        }
    }

    # 2. 取得新憑證
    $Cred = Get-Credential -Message "設定 [$Key] 的帳號密碼"

    # 3. 更新記憶體中的儲存區
    # 我們可以儲存一個自訂物件，包含憑證與描述，增加可讀性
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
        Write-Host "✅ 憑證 [$Key] 已成功儲存至: $StorePath" -ForegroundColor Green
    } catch {
        throw "寫入憑證檔失敗: $_"
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
        throw "找不到憑證儲存檔: $StorePath"
    }

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        
        if ($Store.ContainsKey($Key)) {
            $Item = $Store[$Key]
            
            # 相容性處理：舊版可能直接存 PSCredential，新版存 PSCustomObject
            if ($Item -is [System.Management.Automation.PSCredential]) {
                return $Item
            } elseif ($Item.PSObject.Properties['Credential']) {
                return $Item.Credential
            } else {
                throw "儲存格式不符，無法讀取 [$Key]"
            }
        } else {
            throw "找不到指定的 Key: [$Key]"
        }
    } catch {
        # 重新拋出錯誤，讓呼叫端知道發生了什麼事 (例如解密失敗)
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

# 匯出模組成員
Export-ModuleMember -Function New-StoredCredential, Get-StoredCredential, Get-StoredCredentialList
