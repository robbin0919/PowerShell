# 憑證解密流程技術手冊 (Decryption Workflow)

本模組為了同時兼顧「安全性」與「跨平台移植性」，實作了雙軌解密邏輯。本文件說明 `Get-StoredCredential` 函式在讀取 `Global_Credentials.xml` 時的內部運作流程。

## 1. 總覽圖解

```text
[讀取檔案] --> [身分檢查]
    |
    |-- 是舊版格式 (DPAPI)? ----> [呼叫 Windows DPAPI] ----> 成功? --> [回傳 Credential]
    |                                   |                    |
    |                                   |                    +--> 失敗 (噴錯：人/機器不符)
    |
    +-- 是新版格式 (AES)? ------> [讀取 master.key] ----> [AES-256 解密] ----> [回傳 Credential]
                                        |                    |
                                        |                    +--> 失敗 (噴錯：Key 不正確)
                                        |
                                        +--> 找不到 master.key? (噴錯：請提供金鑰)
```

---

## 2. 詳細流程說明

### 第一階段：讀取與初步判定
1.  從檔案系統載入 `Global_Credentials.xml` 到記憶體。
2.  判定該筆憑證 (Key) 的物件類型：
    *   若物件類型為 `PSCredential`，進入 **DPAPI 模式**。
    *   若物件屬性標註 `EncryptionType = "AES"`，進入 **AES 模式**。

### 第二階段：分支處理

#### A. DPAPI 模式 (Windows 原生模式)
*   **機制**：使用 Windows `CryptUnprotectData` API。
*   **特性**：解密過程不需要額外金鑰檔案，因為金鑰隱含在 Windows 作業系統的使用者 Profile 與機器硬體識別中。
*   **限制**：僅能在同一台電腦由同一個使用者帳戶解密。

#### B. AES 模式 (跨平台模式)
*   **機制**：使用 .NET 的 `System.Security.Cryptography` 類別進行 AES-256 解密。
*   **金鑰來源**：讀取外部檔案 `master.key` (32-byte 原始位元組)。
*   **解密步驟**：
    1.  讀取儲存在 XML 中的 `EncryptedPassword` Base64 字串。
    2.  讀取 `master.key`。
    3.  使用 `ConvertTo-SecureString -Key $AesKey` 進行解密。
    4.  重新封裝為 `PSCredential` 物件。

---

## 3. 異常處理與稽核

在解密過程中，模組會自動觸發以下動作：
1.  **日誌記錄**：
    *   解密成功時：記錄 `[INFO] [使用者] [Key] 憑證存取成功`。
    *   解密失敗時：記錄 `[ERROR] [使用者] [Key] 存取失敗或解密錯誤: <詳細原因>`。
2.  **安全性阻斷**：
    *   若解密失敗，函式會立即透過 `throw` 終止執行，防止後續業務腳本在無密碼狀態下進行無效嘗試（避免觸發帳號鎖定）。

## 4. 常見錯誤代碼

*   **"Key not valid for use in specified state"**：
    通常發生在 DPAPI 模式。表示您正在嘗試從「非建立者」的電腦或帳號解密檔案。
*   **"The provided key is not a valid size"**：
    表示 `master.key` 檔案損壞，長度不足 32 bytes。
*   **"Cannot decrypt... key is incorrect"**：
    表示 `master.key` 存在，但不是當初加密時用的那把鑰匙。
