# PowerShell 憑證讀取範例 (Standalone PowerShell Example)

此目錄包含一個完整的 PowerShell 範例，展示如何使用 `CredentialManager` 模組讀取加密的憑證並套用到應用程式中。

## 目錄結構

- `Modules/`: 包含核心模組 `CredentialManager.psm1`。
- `Invoke_App_With_Credential.ps1`: 示範腳本，展示如何載入模組、讀取憑證並取出帳號密碼。

## 前置作業

1. **準備憑證檔案**：
   此範例預設讀取上層目錄的 `MySecrets.xml` 與 `master.key`。
   若您尚未產生這些檔案，請參考 `PowerShell_Guide/Credential_POC` 中的說明來建立。

2. **目錄隔離**：
   此目錄與 C# 版本完全隔離，適合直接部署到僅支援 PowerShell 的環境。

## 如何執行

開啟 PowerShell 並執行：

```powershell
./Invoke_App_With_Credential.ps1
```

## 核心邏輯

1. **模組載入**：使用 `Import-Module` 載入私有的 `Modules\CredentialManager.psm1`。
2. **憑證獲取**：使用 `Get-StoredCredential` 取得 `PSCredential` 物件。
3. **安全處理**：展示如何使用 `SecureString` 以及在必要時如何安全地轉換為明文以供舊式 API 使用。
