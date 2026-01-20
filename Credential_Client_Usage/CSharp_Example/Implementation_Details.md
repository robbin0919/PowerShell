# C# 憑證用戶端執行流程與架構說明 (C# Credential Client Architecture)

本文件詳細說明 `PowerShell_Guide/Credential_Client_Usage/CSharp_Example` 程式的內部運作邏輯，協助開發人員理解如何跨平台解密 PowerShell 封裝的機敏資訊。

---

## 核心設計目標
1. **零依賴 (Zero Dependency)**：不需安裝 PowerShell 或 PowerShell SDK。
2. **跨平台 (Cross-Platform)**：支援 Windows、Linux 與 Docker 環境。
3. **數據可移植性**：管理端使用 PowerShell，執行端使用 .NET C#。

## 支援矩陣 (Support Matrix)

本程式支援兩種解密模式，其適用環境如下：

| 特性 | AES 模式 | DPAPI 模式 |
| :--- | :--- | :--- |
| **適用作業系統** | Windows, Linux, Docker (跨平台) | **僅限 Windows** |
| **依賴條件** | 需提供 `master.key` 檔案 | 需以「建立檔案的相同使用者」身分執行 |
| **核心技術** | AES-256 (CBC Mode) | Windows Data Protection API |
| **典型用途** | CI/CD, 容器化應用, Linux 服務 | 開發者本機測試, 傳統 Windows 服務 |

## DPAPI 實作細節 (DPAPI Implementation Details)
為了支援 Windows 原生加密，本程式實作了以下機制：

1.  **XML 解析擴充**：
    PowerShell 將 `SecureString` 序列化為 `<SS>` 標籤，而非標準字串的 `<S>`。程式中的 `CredentialStore` 已更新為可同時識別這兩種標籤，確保能讀取 DPAPI 封裝的密文。

2.  **平台檢測**：
    透過 `RuntimeInformation.IsOSPlatform(OSPlatform.Windows)` 進行執行期檢測。若在 Linux 上嘗試解密 DPAPI 憑證，程式會主動攔截並顯示錯誤，而非直接崩潰。

3.  **解密呼叫**：
    使用 .NET 標準庫 `System.Security.Cryptography.ProtectedData` 呼叫 Windows 底層 API。
    ```csharp
    ProtectedData.Unprotect(encryptedBytes, null, DataProtectionScope.CurrentUser);
    ```
    這確保了與 PowerShell `ConvertTo-SecureString` 的相容性，因為兩者底層皆使用相同機制。

---

## 執行流程圖解

```text
[啟動] -> [路徑解析] -> [讀取 Master Key] -> [解析 CLIXML] -> [AES 解密] -> [輸出明文]
```

### 1. 初始化與路徑解析 (Initialization)
*   **參數優先**：程式優先解析命令列傳入的 `--store` 與 `--key` 參數。
*   **自動偵測 (Smart Detection)**：若未指定，程式會啟動自動搜尋機制（`FindProjectRoot`），從當前執行目錄往上層尋找 `MySecrets.xml`。
*   **路徑連結**：若僅指定 Store，程式會自動搜尋同目錄下的 `master.key`，簡化部署配置。

### 2. 載入金鑰 (Loading Master Key)
*   **Base64 轉換**：從 `master.key` 讀取 Base64 字串，並轉換為 AES 演算法所需的 256-bit (32 bytes) 二進位金鑰陣列。

### 3. 解析 PowerShell CLIXML 結構 (XML Parsing)
由於 PowerShell `Export-Clixml` 採用特殊的序列化格式，程式透過 `System.Xml.Linq` 進行以下解析：
*   **定位雜湊表 (Hashtable)**：在 XML 中尋找 `<En>` (Entry) 標籤。
*   **Key 值比對**：找到名稱屬性 (N="Key") 匹配 `MyService` 的條目。
*   **屬性映射**：從該條目的 `<MS>` 區塊中提取出 `Identity` (身分/帳號) 與 `Value` (加密本文)。

### 4. 跨平台 AES 解密 (AES Decryption Logic)
這是程式最核心的部分，模擬了 PowerShell `ConvertTo-SecureString` 的解密行為：
1.  **拆解封包**：將 `Value` 進行 Base64 解碼後，還原為一段 Unicode 字串，其格式為 `標頭|加密本文(Base64)|IV(Base64)`。
2.  **分離 IV 與 CipherText**：以 `|` 為分隔符，提取出初始化向量 (IV) 與實際加密內容。
3.  **AES 運算設定**：
    *   **演算法**：AES (Advanced Encryption Standard)。
    *   **模式**：CBC (Cipher Block Chaining)。
    *   **填充**：PKCS7。
    *   **編碼**：UTF-16LE (Unicode)。
4.  **還原明文**：使用 Master Key 與 IV 進行解密運算，將二進位流轉回原始字串。

### 5. 輸出與應用
*   完成解密後，程式取得原始帳號與密碼，可用於資料庫連線、API 認證等後續操作。

---

## 安全性注意事項
- **金鑰隔離**：`master.key` 與 `MySecrets.xml` 應分開存放或給予不同的權限控管。
- **記憶體保護**：解密後的密碼在 C# 中為 `string` 類型，建議在傳遞給 API 後儘速釋放或使用 `SecureString` (若應用程式端支援)。
