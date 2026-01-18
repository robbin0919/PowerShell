# PowerShell 憑證加密管理 POC 使用指南

此目錄包含一組 POC (概念驗證) 腳本，展示如何安全地儲存與讀取 PowerShell 自動化腳本所需的憑證。

## 📂 檔案結構

*   `Generate_Credentials.ps1`: 負責建立與加密憑證檔案。
*   `Verify_Credentials.ps1`: 負責讀取並驗證解密功能 (模擬排程行為)。

---

## 🚀 使用步驟

### 1. 產生加密憑證檔

您可以選擇「互動模式」手動輸入，或「模擬模式」快速產生測試資料。

**模式 A：互動模式 (管理者手動輸入)**
```powershell
.\Generate_Credentials.ps1 -Mode Interactive -Path "./My_Creds.xml"
```
*腳本將彈出視窗詢問 `AppServer` 與 `DbServer` 的帳密。*

**模式 B：模擬模式 (快速測試)**
```powershell
.\Generate_Credentials.ps1 -Mode Simulated -Path "./My_Creds.xml"
```
*使用內建的測試帳密自動產生檔案。*

---

### 2. 驗證憑證解密

執行此腳本來確認剛產生的檔案是否可以被正確讀取並解密。

```powershell
.\Verify_Credentials.ps1 -Path "./My_Creds.xml"
```

---

## 3. 維護憑證庫 (查詢與修改)

若您忘記檔案中存了哪些帳號，或需要重設特定帳號的密碼，請使用 `Manage_Credentials.ps1`。

### 查詢內容 (List)
列出檔案中所有的標籤 (Key) 與帳號 (Username)。
```powershell
.\Manage_Credentials.ps1 -Path "./My_Creds.xml" -Action List
```
*輸出範例：*
> 標籤 (Key) : **AppServer** | 帳號: AppAdmin
> 標籤 (Key) : **DbServer**  | 帳號: DbAdmin

### 重設密碼 / 新增憑證 (Upsert)
針對特定的標籤更新密碼，若標籤不存在則會自動新增。
```powershell
.\Manage_Credentials.ps1 -Path "./My_Creds.xml" -Action Upsert
```
*腳本將提示您輸入要修改的標籤名稱 (例如 `DbServer`)，並彈出視窗讓您設定新的帳密。*

---

## 💡 關鍵驗證實驗 (安全性測試)

為了驗證 DPAPI 的保護機制，您可以嘗試以下操作：

1.  **跨使用者測試**：
    以「使用者 A」身分執行 `Generate_Credentials.ps1`，然後切換到「使用者 B」執行 `Verify_Credentials.ps1` 指向同一個 XML。您將看到「解密失敗」的訊息。

2.  **跨電腦測試**：
    將產生的 `.xml` 檔案透過隨身碟或網路複製到另一台電腦，再執行 `Verify_Credentials.ps1`。同樣會因為機器金鑰不同而無法解密。

## ⚠️ 注意事項

*   此 POC 使用之解密方式僅供驗證。在生產環境的腳本中，**絕不應將解密後的密碼明文印出**。
*   實際應用時，應直接將匯入的 `$Cred` 物件傳遞給 cmdlet (如 `Connect-DbaInstance -Credential $Cred`)。
