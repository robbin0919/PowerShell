# PowerShell Module
# -----------------------------------------------------------------------------
# 模組名稱: CredentialManager
# 功能描述: 支援 Windows DPAPI 與 AES 跨平台加密的憑證管理模組 (單一模式強制版)
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
    
    # 移除原本的 Write-Error/Write-Warning 輸出，避免與呼叫端重複顯示
}

<#
.SYNOPSIS
    (內部函式) 取得或初始化 AES Master Key
    注意：此函式現在是被動的，它只處理被指派的路徑，不負責決策路徑。
#>
function Get-MasterKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$KeyPath
    )

    # 1. 優先檢查環境變數 (高優先級覆寫)
    if (-not [string]::IsNullOrEmpty($env:PS_MASTER_KEY)) {
        try {
            $Bytes = [Convert]::FromBase64String($env:PS_MASTER_KEY)
            if ($Bytes.Count -eq 32) { return ,$Bytes }
        } catch {
            Write-CredentialLog -Message "環境變數 PS_MASTER_KEY 格式錯誤。" -Level "WARNING"
        }
    }

    # 2. 檔案讀取
    if (Test-Path $KeyPath) {
        try {
            $Content = Get-Content -Path $KeyPath -Raw -ErrorAction Stop
            $Content = $Content.Trim()
            $Bytes = [Convert]::FromBase64String($Content)
            if ($Bytes.Count -eq 32) { return ,$Bytes }
        } catch {
            Write-CredentialLog -Message "Master Key 檔案損毀或格式錯誤: $KeyPath" -Level "WARNING"
        }
        Move-Item $KeyPath "$KeyPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    }

    # 3. 產生新 Key
    Write-CredentialLog -Message "正在產生新的 AES Master Key (Base64) 於: $KeyPath" -Level "INFO"
    $NewKey = New-Object Byte[] 32
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($NewKey)
    $Base64String = [Convert]::ToBase64String($NewKey)
    
    $Dir = Split-Path $KeyPath -Parent
    if (-not (Test-Path $Dir)) { New-Item -Path $Dir -ItemType Directory | Out-Null }
    Set-Content -Path $KeyPath -Value $Base64String -Encoding Ascii -NoNewline
    
    Write-CredentialLog -Message "已產生新的 Master Key: $KeyPath" -Level "WARNING"
    
    return ,$NewKey
}

<#
.SYNOPSIS
    (內部函式) 解析 Key 的絕對路徑
    XML 內記錄的通常是相對路徑 (為了攜帶性)，此函式將其轉為絕對路徑。
#>
function Resolve-KeyPath {
    param(
        [string]$StorePath,
        [string]$KeyFilename
    )
    
    if ([System.IO.Path]::IsPathRooted($KeyFilename)) {
        return $KeyFilename
    } else {
        $StoreDir = Split-Path $StorePath -Parent
        return Join-Path $StoreDir $KeyFilename
    }
}

<#
.SYNOPSIS
    偵測目前 XML 檔案的加密模式
.OUTPUTS
    "AES", "DPAPI", "EMPTY" (空檔), "UNKNOWN" (無法判斷)
#>
function Get-CredentialStoreMode {
    param([string]$StorePath)

    if (-not (Test-Path $StorePath)) { return "EMPTY" }

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        if ($null -eq $Store -or $Store.Count -eq 0) { return "EMPTY" }

        # 檢查特殊設定檔或第一筆資料
        # 注意: 跳過 _StoreConfig 本身，檢查真正的資料
        $DataKeys = $Store.Keys | Where-Object { $_ -ne "_StoreConfig" }
        $FirstKey = $DataKeys | Select-Object -First 1
        
        if (-not $FirstKey) {
            # 只有 Config 沒有資料，視為該 Config 指定的模式 (通常是 AES)
            if ($Store.ContainsKey("_StoreConfig")) { return "AES" }
            return "EMPTY" 
        }

        $Item = $Store[$FirstKey]
        if ($Item.PSObject.Properties.Match("EncryptionType")) {
            if ($Item.EncryptionType -eq "AES") { return "AES" }
            if ($Item.EncryptionType -eq "DPAPI") { return "DPAPI" }
        }
        
        if ($Item -is [System.Management.Automation.PSCredential]) {
            return "DPAPI"
        } else {
            return "UNKNOWN"
        }
    } catch {
        return "UNKNOWN"
    }
}

<#
.SYNOPSIS
    儲存或更新憑證 (強制單一模式)
#>
function New-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Key,
        
        [Parameter(Mandatory=$false)]
        [string]$StorePath = $DefaultStorePath,
        
        [Parameter(Mandatory=$false)]
        [string]$Description = "",

        [Parameter(Mandatory=$false)]
        [ValidateSet("AES", "DPAPI")]
        [string]$Mode = "AES",

        [Parameter(Mandatory=$false)]
        [string]$MasterKeyFilename = "master.key"
    )

    Write-CredentialLog -Message "準備更新憑證: $Key" -Level "INFO" -TargetKey $Key

    # 1. 檢查現有檔案模式，防止混合
    $CurrentMode = Get-CredentialStoreMode -StorePath $StorePath
    
    if ($CurrentMode -ne "EMPTY" -and $CurrentMode -ne "UNKNOWN") {
        # 如果檔案已有資料，強制使用現有模式
        if ($Mode -ne $CurrentMode) {
            throw "模式衝突！此檔案已設定為 [$CurrentMode] 模式，無法寫入 [$Mode] 格式的資料。"
        }
    }

    # 2. 讀取現有檔案 (或建立新的 Hashtable)
    $Store = @{}
    if (Test-Path $StorePath) {
        try {
            $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        } catch {
            Write-CredentialLog -Message "無法讀取現有檔案，將建立新檔案。" -Level "WARNING"
        }
    }

    # 3. 取得使用者輸入 (中性化介面，支援單一 Secret 或 Token)
    Write-Host "`n[$Key] 資料內容輸入：" -ForegroundColor Cyan
    
    $InputUser = Read-Host "身份識別/帳號 (Identity, 若無對應帳號可按 Enter 跳過)"
    if ([string]::IsNullOrWhiteSpace($InputUser)) { 
        $InputUser = "N/A" # 預設標記為不適用
    }
    
    $InputPass = Read-Host "機敏資訊內容/密碼 (Secret Value)" -AsSecureString
    if ($null -eq $InputPass -or $InputPass.Length -eq 0) { 
        throw "內容不能為空。" 
    }

    # 建立物件 (內部仍使用 PSCredential 以相容現有機制)
    $Cred = New-Object System.Management.Automation.PSCredential ($InputUser, $InputPass)

    # 4. 根據模式處理資料
    if ($Mode -eq "AES") {
        # --- AES 模式 (跨平台) ---
        
        # [關鍵邏輯] 決定 Key Filename
        # 1. 優先使用 XML 內既有的設定
        # 2. 若無，使用傳入的參數 (預設 master.key) 並寫入設定
        
        $TargetKeyFilename = $MasterKeyFilename # Default from param
        
        if ($Store.ContainsKey("_StoreConfig") -and $Store["_StoreConfig"].KeyFilename) {
            $TargetKeyFilename = $Store["_StoreConfig"].KeyFilename
            # 若使用者嘗試傳入不同的 Key 名稱，可以在此 Log 警告，但我們優先遵從檔案內的設定以保持一致性
        } else {
            # 新檔案或舊版檔案，寫入設定
            $Store["_StoreConfig"] = @{ KeyFilename = $TargetKeyFilename }
        }

        # 解析完整路徑
        $FullPathToKey = Resolve-KeyPath -StorePath $StorePath -KeyFilename $TargetKeyFilename

        $AesKeyObject = Get-MasterKey -KeyPath $FullPathToKey
        
        # 除錯資訊：檢查 Key 的型別與長度
        if ($AesKeyObject -is [Array] -and $AesKeyObject[0] -isnot [byte]) {
             $AesKey = $AesKeyObject | Select-Object -Last 1
        } else {
             $AesKey = $AesKeyObject
        }
        
        if ($AesKey -isnot [byte[]] -and $AesKey -isnot [System.Collections.Generic.List[byte]]) {
             try { $AesKey = [byte[]]$AesKey } catch { throw "Master Key 型別錯誤" }
        }

        if ($AesKey.Count -ne 32) {
            throw "Master Key 長度錯誤 (預期 32, 實際 $($AesKey.Count))。"
        }

        # --- SecureString 驗證與修復 ---
        if ($null -eq $Cred.Password -or $Cred.Password.Length -eq 0) {
            throw "密碼長度為 0 或物件為空，無法加密。"
        }

        try {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Cred.Password)
            $Plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
            $SafeSecurePass = ConvertTo-SecureString $Plain -AsPlainText -Force
        } finally {
            if ($BSTR) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR) }
        }

        try {
            $EncryptedValue = $SafeSecurePass | ConvertFrom-SecureString -Key $AesKey
        } catch {
            Write-Error "加密失敗。"
            throw
        }
        
        # 儲存物件 (使用 Identity 與 Value 作為屬性名稱)
        $Store[$Key] = [PSCustomObject]@{
            Identity          = $Cred.UserName
            Value             = $EncryptedValue
            EncryptionType    = "AES"
            Description       = $Description
            UpdatedBy         = $env:USERNAME
            UpdatedAt         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    } else {
        # --- DPAPI 模式 (Windows 專用) ---
        # 重構：不再直接儲存 PSCredential，而是封裝成統一結構
        # Export-Clixml 會自動加密屬性中的 SecureString (Value)
        
        $Store[$Key] = [PSCustomObject]@{
            Identity          = $Cred.UserName
            Value             = $Cred.Password # 這是 SecureString
            EncryptionType    = "DPAPI"
            Description       = $Description
            UpdatedBy         = $env:USERNAME
            UpdatedAt         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    # 5. 寫回檔案
    try {
        $Store | Export-Clixml -Path $StorePath -Force
        Write-CredentialLog -Message "憑證更新成功 ($Mode)。" -Level "INFO" -TargetKey $Key
        Write-Host "✅ 憑證 [$Key] 已成功儲存至: $StorePath (模式: $Mode)" -ForegroundColor Green
        if ($Mode -eq "AES") {
            Write-Host "   (使用金鑰: $TargetKeyFilename)" -ForegroundColor DarkGray
        }
    } catch {
        throw "寫入憑證檔失敗: $_"
    }
}

<#
.SYNOPSIS
    讀取憑證 (自動識別模式)
#>
function Get-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Key,
        [Parameter(Mandatory=$false)]
        [string]$StorePath = $DefaultStorePath
    )

    if (-not (Test-Path $StorePath)) { throw "找不到憑證儲存檔: $StorePath" }

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        
        if ($Store.ContainsKey($Key)) {
            $Item = $Store[$Key]
            Write-CredentialLog -Message "憑證存取成功" -Level "INFO" -TargetKey $Key

            if ($Item.PSObject.Properties.Match("EncryptionType") -and $Item.EncryptionType -eq "AES") {
                # --- AES 解密 ---
                
                # 1. 讀取設定中的 Key Filename
                $TargetKeyFilename = "master.key" # Default Fallback
                if ($Store.ContainsKey("_StoreConfig") -and $Store["_StoreConfig"].KeyFilename) {
                    $TargetKeyFilename = $Store["_StoreConfig"].KeyFilename
                }

                # 2. 解析完整路徑
                $FullPathToKey = Resolve-KeyPath -StorePath $StorePath -KeyFilename $TargetKeyFilename

                $AesKey = Get-MasterKey -KeyPath $FullPathToKey
                
                # 欄位名稱相容性處理
                $EncryptedString = if ($Item.PSObject.Properties.Match("Value")) { $Item.Value } else { $Item.EncryptedPassword }
                $UserIdentity    = if ($Item.PSObject.Properties.Match("Identity")) { $Item.Identity } else { $Item.UserName }

                $SecurePass = $EncryptedString | ConvertTo-SecureString -Key $AesKey
                return New-Object System.Management.Automation.PSCredential ($UserIdentity, $SecurePass)
            } 
            elseif ($Item.PSObject.Properties.Match("EncryptionType") -and $Item.EncryptionType -eq "DPAPI") {
                # --- DPAPI 解密 (新版結構) ---
                # Import-Clixml 已經自動解密了 SecureString (Value 屬性)
                return New-Object System.Management.Automation.PSCredential ($Item.Identity, $Item.Value)
            }
            elseif ($Item -is [System.Management.Automation.PSCredential]) {
                # --- DPAPI 解密 (舊版相容) ---
                return $Item
            }
            else {
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

    $CurrentMode = Get-CredentialStoreMode -StorePath $StorePath
    Write-Host "目前的檔案模式: [$CurrentMode]" -ForegroundColor Cyan
    
    # 嘗試讀取 Key 設定以顯示
    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        if ($Store.ContainsKey("_StoreConfig")) {
             Write-Host "綁定金鑰檔案: [$($Store["_StoreConfig"].KeyFilename)]" -ForegroundColor DarkGray
        }

        $Store.Keys | Where-Object { $_ -ne "_StoreConfig" } | ForEach-Object {
            $Key = $_
            $Item = $Store[$Key]
            
            if ($Item.PSObject.Properties.Match("EncryptionType") -and $Item.EncryptionType -eq "AES") {
                $ShowUser = if ($Item.PSObject.Properties.Match("Identity")) { $Item.Identity } else { $Item.UserName }
                [PSCustomObject]@{
                    Key = $Key; Identity = $ShowUser; Updated = $Item.UpdatedAt; Desc = $Item.Description; Mode = "AES"
                }
            } else {
                # DPAPI 模式
                $Desc = if ($Item.PSObject.Properties.Match("Description")) { $Item.Description } else { "" }
                $Date = if ($Item.PSObject.Properties.Match("UpdatedAt")) { $Item.UpdatedAt } else { "" }
                [PSCustomObject]@{
                    Key = $Key; User = $Item.UserName; Updated = $Date; Desc = $Desc; Mode = "DPAPI"
                }
            }
        }
    } catch {
        Write-Error "無法讀取清單: $_"
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

    $CurrentMode = Get-CredentialStoreMode -StorePath $StorePath
    Write-Host "目前的檔案模式: [$CurrentMode]" -ForegroundColor Cyan

    try {
        $Store = Import-Clixml -Path $StorePath -ErrorAction Stop
        
        $Store.Keys | ForEach-Object {
            $Key = $_
            $Item = $Store[$Key]
            
            if ($Item.PSObject.Properties.Match("EncryptionType") -and $Item.EncryptionType -eq "AES") {
                $ShowUser = if ($Item.PSObject.Properties.Match("Identity")) { $Item.Identity } else { $Item.UserName }
                [PSCustomObject]@{
                    Key = $Key; Identity = $ShowUser; Updated = $Item.UpdatedAt; Desc = $Item.Description; Mode = "AES"
                }
            } elseif ($Item.PSObject.Properties.Match("EncryptionType") -and $Item.EncryptionType -eq "DPAPI") {
                # DPAPI 新版結構
                [PSCustomObject]@{
                    Key = $Key; Identity = $Item.Identity; Updated = $Item.UpdatedAt; Desc = $Item.Description; Mode = "DPAPI"
                }
            } else {
                # DPAPI 舊版相容
                $Desc = if ($Item.PSObject.Properties.Match("Description")) { $Item.Description } else { "" }
                $Date = if ($Item.PSObject.Properties.Match("UpdatedAt")) { $Item.UpdatedAt } else { "" }
                [PSCustomObject]@{
                    Key = $Key; Identity = $Item.UserName; Updated = $Date; Desc = $Desc; Mode = "DPAPI (Legacy)"
                }
            }
        }
    } catch {
        Write-Error "無法讀取清單: $_"
    }
}

Export-ModuleMember -Function New-StoredCredential, Get-StoredCredential, Get-StoredCredentialList, Get-CredentialStoreMode, Write-CredentialLog