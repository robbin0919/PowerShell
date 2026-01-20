# C# Credential Client Example

這是一個 .NET C# 範例程式，展示如何讀取並解密由 PowerShell `CredentialManager` 模組產生的 `MySecrets.xml` 檔案。
這證明了在異質環境中 (例如 DevOps 流程)，可以使用 PowerShell 進行憑證封裝，並由 C# 應用程式讀取使用。

## 專案結構

- `Program.cs`: 主要程式碼，包含 XML 解析與 AES 解密邏輯。
- `CredentialClient.csproj`: .NET 專案檔。

## 前置需求

1.  **安裝 .NET SDK**: 需要 .NET 8.0 或相容版本。
2.  **準備憑證資料**:
    - 此程式預設讀取上層目錄 (`../`) 的 `MySecrets.xml` 與 `master.key`。
    - 請先使用 **憑證管理工具** (`../../Credential_Tools/Manage-Secrets.ps1`) 產生這些檔案，並將其放置於 `Credential_Client_Usage/` 目錄下。

## 如何編譯與執行

在終端機中，進入此目錄並執行：

```bash
# 還原相依套件並執行 (自動搜尋上層目錄的 MySecrets.xml)
dotnet run
```

### 命令列參數 (Arguments)

您也可以手動指定檔案路徑：

```bash
# 指定特定的 XML 檔案與 Key 檔案
dotnet run -- --store "C:\Data\MySecrets.xml" --key "C:\Data\master.key"

# 僅指定 Store (自動在同目錄尋找 master.key)
dotnet run -- --store "../OtherSecrets.xml"
```

若執行成功，您將看到類似以下的輸出：

```text
[C# Credential Client Example]
Store Path: ...\MySecrets.xml
Key Path:   ...\master.key

Found Credential for User: demo_user
Decrypted Password: MySuperSecretPassword
Connecting to service as demo_user...
```

## 核心邏輯說明

1.  **XML 解析**:
    PowerShell 的 `Export-Clixml` 會將物件序列化為複雜的 XML 結構。此範例使用 `System.Xml.Linq` (XDocument) 針對 Hashtable 結構進行解析，提取 `Identity` 與 `Value` 欄位。

2.  **AES 解密**:
    PowerShell 的 `ConvertFrom-SecureString -Key ...` 會輸出一段 Base64 字串。
    解密步驟如下 (在 `PowerShellDecryptor` 類別中實作)：
    1. Base64 Decode -> 取得原始 Byte Array。
    2. Convert to Unicode String -> 取得格式為 `Header|Cipher(Base64)|IV(Base64)` 的字串。
    3. Split 字串取得 IV 與 CipherText。
    4. 使用標準 `System.Security.Cryptography.Aes` (CBC Mode, PKCS7 Padding) 進行解密。
    5. 解密後的 Bytes 轉回 Unicode String 即為明文密碼。
