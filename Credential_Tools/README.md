# PowerShell 集中式憑證管理工具

本工具組採用 **「集中管理 (Admin) / 分散使用 (Client)」** 的架構。旨在將憑證的維護與業務邏輯分離。

## 📂 檔案結構

*   **`CredentialManager.psm1`**: (核心) 底層模組，提供加密存取功能。
*   **`Manage-Secrets.ps1`**: (管理端) **唯一** 用來新增、修改憑證的互動式工具。
*   **`Template_Script.ps1`**: (使用端) 業務腳本範本，展示如何唯讀取用憑證。

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