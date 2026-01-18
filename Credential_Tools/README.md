# PowerShell 集中式憑證管理工具

本工具組採用 **「集中管理 (Admin) / 分散使用 (Client)」** 的架構。旨在將憑證的維護與業務邏輯分離。

## 📂 檔案結構

*   **`Modules/`**: 存放核心模組。
*   **`Data/`**: 存放加密後的憑證資料檔 (.xml)。
*   **`Logs/`**: 存放操作與存取紀錄檔 (.log)。
*   **`Manage-Secrets.ps1`**: (管理端) **唯一** 用來新增、修改憑證的互動式工具。

---

## 📝 稽核日誌 (Audit Logs)

本工具具備自動稽核功能，所有的憑證操作都會被記錄。
*   **日誌位置**: `Logs/Credential_Audit.log`
*   **記錄內容**: 時間戳記、操作層級、執行使用者、存取的 Key、詳細訊息。

這對於資安合規 (Compliance) 至關重要，您可以追蹤「誰」在「什麼時候」使用了「哪組密碼」。

---

## 🔐 跨平台支援與 AES 加密 (New)

本工具已升級支援 **AES-256 加密**，打破了傳統 DPAPI 只能在同一台電腦運作的限制。

### 核心元件
1.  **`Data/Global_Credentials.xml`**: 加密後的憑證庫（保險箱）。
2.  **`Data/master.key`**: AES 金鑰檔案（鑰匙）。

### 如何在 Linux / Docker 使用？
只要將上述 **兩個檔案** 一同部署到目標環境（Linux/Container），腳本即可正常解密並讀取憑證。

### ⚠️ 安全性與備份警告 (Critical)
*   **不可遺失**: `master.key` 是解密的唯一依據。若遺失此檔案，`Global_Credentials.xml` 內的所有資料將無法復原。
*   **權限控管**: 擁有這兩個檔案的人即擁有所有密碼。請務必設定嚴格的檔案權限（例如 Linux `chmod 600`），僅允許應用程式帳號讀取。

---

## 🚀 使用流程

### 角色 1: 系統管理員 (Admin)
當需要新增一組帳密（例如資料庫密碼）時：
1.  執行 `.\Manage-Secrets.ps1`。
2.  選擇 **2. 新增/更新憑證**。
3.  輸入識別 Key (例如 `HR_DB`) 與描述。
4.  在彈出的視窗中輸入帳號密碼。
    *   *結果：憑證被加密存入 `Global_Credentials.xml`。*

### 角色 2: 自動化腳本 (Client Scripts)
當編寫備份或排程腳本時，**不需要** 再寫任何 `Get-Credential` 的代碼。
直接引用模組並讀取：

```powershell
# 載入模組
Import-Module "./CredentialManager.psm1"

# 取用憑證
$Cred = Get-StoredCredential -Key "HR_DB" -StorePath "./Global_Credentials.xml"

# 使用憑證
Connect-Database -Credential $Cred
```

## 🔒 安全性設計
*   **權限分離**：業務腳本只負責讀取，無法修改憑證檔（若搭配適當的 NTFS 權限設定）。
*   **單一來源**：所有腳本共用 `Global_Credentials.xml`，更換密碼時只需在管理端改一次，所有腳本自動生效。