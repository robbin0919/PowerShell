# PowerShell Module
# -----------------------------------------------------------------------------
# 模組名稱: CredentialManager
# 功能描述: 支援 Windows DPAPI 與 AES 跨平台加密的憑證管理模組
# -----------------------------------------------------------------------------

# 定義路徑變數
$ParentDir = Split-Path $PSScriptRoot -Parent
$DefaultStorePath = Join-Path $ParentDir "Data" | Join-Path -ChildPath "Global_Credentials.xml"
$DefaultKeyPath   = Join-Path $ParentDir "Data" | Join-Path -ChildPath "master.key"
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
    
    $LogDir = Split-Path $DefaultLogPath -Parent
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory | Out-Null }

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] [$env:USERNAME] [$TargetKey] $Message"
    Add-Content -Path $DefaultLogPath -Value $LogEntry -Encoding UTF8
    
    if ($Level -eq "ERROR") { Write-Error $Message }
    elseif ($Level -eq "WARNING") { Write-Warning $Message }
    else { Write-Host "$Message" -ForegroundColor Gray }
}

<#
.SYNOPSIS
    (內部函式) 取得或初始化 AES Master Key
    用於跨平台 (Linux/Docker) 加密支援
#>
function Get-MasterKey {
    param([string]$KeyPath = $DefaultKeyPath)

    # 1. 如果檔案存在，直接讀取
    if (Test-Path $KeyPath) {
        $Bytes = Get-Content -Path $KeyPath -Encoding Byte -ReadCount 0
        if ($Bytes.Count -eq 32) {
            return $Bytes
        }
        Write-CredentialLog -Message "Master Key 損毀或長度錯誤，將備份並重新產生。" -Level "WARNING"
        Move-Item $KeyPath "$KeyPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    }

    # 2. 檔案不存在，產生新的 32-byte AES Key
    Write-CredentialLog -Message "正在產生新的 AES Master Key..." -Level "INFO"
    $NewKey = New-Object Byte[] 32
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($NewKey)
    
    # 確保目錄存在
    $Dir = Split-Path $KeyPath -Parent
    if (-not (Test-Path $Dir)) { New-Item -Path $Dir -ItemType Directory | Out-Null }

    # 寫入檔案
    Set-Content -Path $KeyPath -Value $NewKey -Encoding Byte
    
    # 警告：這是最重要的檔案
    Write-Warning "⚠️  已產生新的 Master Key: $KeyPath"
    Write-Warning "    請務必備份此檔案！若遺失此 Key，所有憑證將無法解密。"
    
    return $NewKey
}

<#
.SYNOPSIS
    儲存或更新憑證 (支援 AES)
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

    # 1. 取得 Master Key
    try {
        $AesKey = Get-MasterKey
    } catch {
        throw "無法取得 Master Key: $_"
    }

    # 2. 讀取現有檔案
    $Store = @{}
    if (Test-Path $StorePath) {
        try {
            $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        } catch {
            Write-CredentialLog -Message "無法讀取現有檔案，將建立新檔案。" -Level "WARNING" -TargetKey $Key
        }
    }

    # 3. 取得使用者輸入的憑證
    $Cred = Get-Credential -Message "設定 [$Key] 的帳號密碼"

    # 4. 加密密碼 (AES)
    # 將 SecureString 轉為加密後的標準字串
    $EncryptedPassword = $Cred.Password | ConvertFrom-SecureString -Key $AesKey

    # 5. 更新儲存物件 (存的是 AES 加密字串，而非原始 Credential)
    $Store[$Key] = [PSCustomObject]@{
        UserName          = $Cred.UserName
        EncryptedPassword = $EncryptedPassword
        EncryptionType    = "AES"
        Description       = $Description
        UpdatedBy         = $env:USERNAME
        UpdatedAt         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    # 6. 寫回檔案
    try {
        $Store | Export-Clixml -Path $StorePath -Force
        Write-CredentialLog -Message "憑證更新成功 (AES)。" -Level "INFO" -TargetKey $Key
        Write-Host "✅ 憑證 [$Key] 已成功儲存至: $StorePath" -ForegroundColor Green
    } catch {
        throw "寫入憑證檔失敗: $_"
    }
}

<#
.SYNOPSIS
    讀取憑證 (支援 AES)
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

    # 1. 取得 Master Key
    $AesKey = Get-MasterKey

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        
        if ($Store.ContainsKey($Key)) {
            $Item = $Store[$Key]
            Write-CredentialLog -Message "憑證存取成功" -Level "INFO" -TargetKey $Key

            # --- 舊版相容性檢查 ---
            if ($Item -is [System.Management.Automation.PSCredential]) {
                # 這是舊版 DPAPI 格式，如果是在不同機器會失敗
                return $Item
            } 
            elseif ($Item.EncryptionType -eq "AES") {
                # --- 新版 AES 解密邏輯 ---
                $SecurePass = $Item.EncryptedPassword | ConvertTo-SecureString -Key $AesKey
                return New-Object System.Management.Automation.PSCredential ($Item.UserName, $SecurePass)
            }
            else {
                # 既不是舊版也不是新版，可能格式損壞
                throw "未知的憑證格式。"
            }
        } else {
            throw "找不到指定的 Key: [$Key]"
        }
    } catch {
        Write-CredentialLog -Message "存取失敗或解密錯誤: $_" -Level "ERROR" -TargetKey $Key
        throw
    }
}

<#
.SYNOPSIS
    列出所有可用憑證 Key
#>
function Get-StoredCredentialList {
    [CmdletBinding()]
    param(
        [string]$StorePath = $DefaultStorePath
    )

    if (-not (Test-Path $StorePath)) { return }

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        Write-CredentialLog -Message "執行憑證清單查詢" -Level "INFO"

        $Store.Keys | ForEach-Object {
            $Key = $_
            $Item = $Store[$Key]
            
            # 統一輸出格式
            if ($Item.EncryptionType -eq "AES") {
                [PSCustomObject]@{
                    Key = $Key; User = $Item.UserName; Updated = $Item.UpdatedAt; Desc = $Item.Description; Type = "AES"
                }
            } else {
                # 舊版格式處理
                $User = if ($Item -is [System.Management.Automation.PSCredential]) { $Item.UserName } else { $Item.Credential.UserName }
                [PSCustomObject]@{
                    Key = $Key; User = $User; Updated = "Legacy"; Desc = "Old DPAPI"; Type = "DPAPI"
                }
            }
        }
    } catch {
        Write-Error "無法讀取清單: $_"
    }
}

Export-ModuleMember -Function New-StoredCredential, Get-StoredCredential, Get-StoredCredentialList, Write-CredentialLog