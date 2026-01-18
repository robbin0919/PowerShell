# 自動化腳本資安最佳實務 (Security Best Practices)

在自動化腳本中處理敏感資訊（如帳號、密碼、API Token）時，直接透過指令列參數傳遞存在極大的安全風險。本文件列出幾種替代方案，並分析其優缺點，協助您選擇最適合的實作方式。

## 風險說明

若直接在指令列中使用 `-Password "123456"`，可能導致以下資安漏洞：
1.  **Shell 歷史紀錄 (History)**：Linux 的 `.bash_history` 或 PowerShell 的 `Get-History` 會永久保留明碼密碼。
2.  **Process 列表外洩**：在腳本執行期間，同主機的其他使用者可透過 `ps -ef` (Linux) 或 `Get-Process` (Windows) 查看完整的指令參數。
3.  **CI/CD Log 洩漏**：Jenkins 或 GitLab CI 若未正確設定 Masking，可能會將完整的執行指令印在 Console Log 中。

---

## 替代方案比較

### 方案一：使用環境變數 (Environment Variables)
**✅ 推薦用於 CI/CD (Jenkins, GitLab CI, GitHub Actions)**

將敏感資訊儲存於作業系統的環境變數中，腳本執行時直接讀取。

*   **做法**：
    1.  **設定變數**：
        *   PowerShell: `$env:CX_PASSWORD = "my_secret"`
        *   Bash: `export CX_PASSWORD="my_secret"`
    2.  **腳本讀取**：
        ```powershell
        # 腳本中直接讀取，或設為參數預設值
        [string]$Password = $env:CX_PASSWORD
        ```
*   **優點**：
    *   密碼不落地（不存於檔案）。
    *   密碼不出現在指令列參數中。
    *   與各大 CI/CD 工具整合性極佳（CI 工具通常透過環境變數注入 Secret）。
*   **缺點**：
    *   本機開發時需手動設定變數（關閉視窗即失效，除非設為永久變數）。

### 方案二：PowerShell 加密憑證檔 (Clixml)
**✅ 推薦用於 Windows 本機排程任務**

利用 Windows 的 DPAPI (Data Protection API) 將憑證物件加密存檔。

*   **做法**：
    1.  **加密存檔** (僅需執行一次)：
        ```powershell
        Get-Credential | Export-Clixml -Path "CxCreds.xml"
        ```
    2.  **腳本讀取**：
        ```powershell
        $Creds = Import-Clixml -Path "CxCreds.xml"
        $Username = $Creds.UserName
        $Password = $Creds.GetNetworkCredential().Password
        ```
*   **優點**：
    *   檔案是加密的，直接打開只會看到亂碼。
    *   **安全性極高**：只有「建立該檔案的使用者」在「建立該檔案的電腦」上才能解密。即使檔案被偷走，駭客也無法在其他電腦解開。
*   **缺點**：
    *   **無法共用**：無法將檔案複製給其他同事或部署到另一台伺服器使用。

### 方案三：AES-256 加密憑證檔 (集中式管理)
**✅ 推薦用於 跨伺服器、Docker 容器或 Linux 環境**

本專案提供的 [**Credential_Tools**](./Credential_Tools/README.md) 即採用此方案。透過一組 Master Key (AES 金鑰) 來加密憑證庫。

*   **優點**：
    *   **跨平台支援**：金鑰與加密檔可隨腳本部署至 Linux 或 Docker 執行，不受 Windows 機器限制。
    *   **管理便利**：單一憑證庫即可管理多組帳密，方便定期更新。
    *   **稽核能力**：可記錄存取日誌，滿足合規要求。
*   **缺點**：
    *   **金鑰管理責任**：必須嚴格保護 `master.key` 檔案。若金鑰外洩，等同於所有密碼外洩。

### 方案四：整合企業級 Secret Management
**✅ 推薦用於大型企業環境**

使用 Azure Key Vault, HashiCorp Vault 或 AWS Secrets Manager。

*   **做法**：
    *   腳本執行時，先透過機器身分 (Managed Identity) 取得 Vault 的存取權。
    *   呼叫 API 從 Vault 取得當下的 Checkmarx 密碼。
*   **優點**：
    *   密碼集中管理，可定期自動輪替 (Rotate)。
    *   具備完整的存取稽核紀錄 (Audit Log)。
*   **缺點**：
    *   實作複雜度高，需額外撰寫 API 呼叫邏輯。

---

## 建議實作策略

為了兼顧 **CI/CD 自動化** 與 **本機開發便利性**，建議修改腳本以支援「混合模式」：

1.  **優先級 1**：若使用者透過參數 (`-Password`) 傳入，則使用參數值（適合臨時測試）。
2.  **優先級 2**：若參數為空，則嘗試讀取環境變數 (`CX_PASSWORD`)。
3.  **錯誤處理**：若兩者皆空，則拋出錯誤並中止執行。

這種設計能讓腳本同時適應本機手動執行與流水線自動化執行。
