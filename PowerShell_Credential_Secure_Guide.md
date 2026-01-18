# PowerShell 自動化排程憑證加密處理指南

## 1. 核心觀念：為何無法解密？

當使用 PowerShell 的 `Export-Clixml` 匯出 `PSCredential` 物件時，預設使用 **Windows DPAPI (Data Protection API)** 進行加密。此機制具有以下嚴格限制：

*   **綁定機器 (Machine-Bound)**：加密檔案只能在「產生該檔案的電腦」上解密。
*   **綁定使用者 (User-Bound)**：加密檔案只能由「產生該檔案的使用者帳戶」解密。

因此，若排程執行的身分與產生憑證檔案的身分不同，解密將會失敗。

---

## 2. 解決方案一：使用相同帳戶執行 (推薦)

這是最安全且符合微軟標準的做法。確保「產生憑證的人」與「執行排程的人」是同一個帳號。

### 適用場景
*   您擁有該服務帳號 (Service Account) 的密碼。
*   排程在單一伺服器上運作。

### 設定步驟

1.  **以服務帳號登入**
    若該帳號無桌面登入權限，請使用管理者權限開啟 CMD，切換身分執行 PowerShell：
    ```cmd
    runas /user:網域\服務帳號名稱 powershell
    ```

2.  **產生憑證檔**
    在跳出的 PowerShell 視窗中執行：
    ```powershell
    # 輸入帳號密碼
    $Cred = Get-Credential
    # 匯出加密檔 (使用 DPAPI 保護)
    $Cred | Export-Clixml -Path "C:\Scripts\creds.xml"
    ```

3.  **設定工作排程器 (Task Scheduler)**
    *   建立工作時，在「一般 (General)」頁籤的「執行身分 (User account)」欄位，選擇**相同的服務帳號**。
    *   腳本中直接匯入使用：
        ```powershell
        $Cred = Import-Clixml -Path "C:\Scripts\creds.xml"
        ```

---

## 3. 解決方案二：使用 AES 金鑰 (可跨使用者/機器)

若需使用 `SYSTEM` 帳戶執行，或需將腳本派送至多台機器，需改用 AES 金鑰加密。

### 適用場景
*   使用 `SYSTEM`, `NETWORK SERVICE` 等特殊帳戶。
*   自動化腳本需部署到多台伺服器。

### 設定步驟

1.  **產生 AES 金鑰 (只需執行一次)**
    執行以下指令並**複製產生的數字陣列**：
    ```powershell
    $Key = (1..32) | ForEach-Object { Get-Random -Minimum 0 -Maximum 255 }
    # 顯示並複製這串數字
    $Key -join ","
    ```

2.  **加密並建立憑證檔**
    將上一步的金鑰填入 `$Key`：
    ```powershell
    $Key = (10, 25, 255, ...) # 填入您的金鑰
    $Cred = Get-Credential
    
    # 使用 AES 金鑰強制加密
    $Cred.Password | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString -Key $Key | Out-File "C:\Scripts\creds_aes.txt"
    ```

3.  **在排程腳本中解密**
    您的自動化腳本 (Script.ps1) 需包含金鑰才能解密：
    ```powershell
    # 必須與加密時使用相同的金鑰
    $Key = (10, 25, 255, ...) 
    
    # 讀取並還原密碼
    $EncryptedPass = Get-Content "C:\Scripts\creds_aes.txt" | ConvertTo-SecureString -Key $Key
    
    # 重組 Credential 物件 (使用者名稱需寫死或另外存)
    $Cred = New-Object System.Management.Automation.PSCredential ("BackupUser", $EncryptedPass)
    
    # 使用憑證
    # Do-Something -Credential $Cred
    ```

---

## 5. 進階技巧：儲存多組憑證

您無須為每組帳號建立單獨的檔案。透過 **雜湊表 (Hashtable)**，可以在單一檔案中管理多組憑證。

### 儲存方式 (一次性設定)
```powershell
# 建立雜湊表並輸入多組帳密
$CredStore = @{
    "Database"  = Get-Credential -Message "請輸入 DB 帳密"
    "WebServer" = Get-Credential -Message "請輸入 Web 帳密"
    "Backup"    = Get-Credential -Message "請輸入 備份 帳密"
}

# 匯出單一檔案
$CredStore | Export-Clixml -Path "C:\Scripts\All_Creds.xml"
```

### 讀取方式 (排程腳本中)
```powershell
# 匯入憑證庫
$CredStore = Import-Clixml -Path "C:\Scripts\All_Creds.xml"

# 依據 Key 取用特定憑證
Connect-Database -Credential $CredStore["Database"]
Start-Backup     -Credential $CredStore["Backup"]
```

---

## 6. 安全性注意事項 (Critical)

*   **檔案權限 (ACL)**：
    無論使用哪種方法，**務必**設定存放密碼檔 (或包含 AES Key 的腳本檔) 的 NTFS 權限。
    *   **允許：** 僅限 `System`、`Administrators` 及 `執行排程的帳號` 擁有「讀取」權限。
    *   **拒絕：** 其他所有使用者 (Users/Everyone)。
*   **AES Key 風險**：
    方法二將金鑰寫在腳本中等同於「將鑰匙放在門墊下」。任何能讀取該腳本的人都能解密密碼，因此權限控管至關重要。
