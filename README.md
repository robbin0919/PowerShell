# PowerShell 自動化與資安實務工具庫

本專案是一個關於 **PowerShell 自動化與資安實務** 的技術資源庫，主要聚焦於「憑證安全管理」以及「Windows 檔案安全機制 (MOTW)」的理論與實作。

## 📂 專案結構

### 1. 核心指南與疑難排解 (Root)
*   [**PowerShell 憑證加密處理指南**](./PowerShell_Credential_Secure_Guide.md): 深入解析 Windows DPAPI 機制，提供跨機器/帳號的 AES 加密方案，解決排程執行時的解密失敗問題。
*   [**自動化腳本資安最佳實務**](./Security_Best_Practices.md): 比較環境變數、Clixml 加密及 Secret Management 等方案，協助開發者選擇最合適的敏感資訊保護方式。
*   [**憑證疑難排解與 C# 整合指南**](./Credential_Troubleshooting_Guide.md): 說明如何識別不明來源的加密檔案，以及如何在 C#/.NET 專案中解密 PowerShell 產生的憑證檔案。

### 2. 集中式憑證管理工具 (Credential_Tools) - 🚀 進階實務
這是本專案的核心工具組，採用 **「集中管理 (Admin) / 分散使用 (Client)」** 架構：
*   **AES-256 加密**: 支援跨機器、跨平台（Windows/Linux/Docker）部署。
*   **集中化管理**: `Manage-Secrets.ps1` 互動式介面，統一管理專案所需的所有憑證。
*   **自動稽核**: 內建 Log 機制，記錄所有憑證的存取與變更歷程。
*   **模組化**: 提供 `CredentialManager.psm1` 供業務腳本直接引用，達成程式碼與敏感資訊分離。
*   [詳細工具說明](./Credential_Tools/README.md)

### 3. 憑證管理實驗室 (Credential_POC) - 🧪 基礎教學
提供一組概念驗證 (POC) 腳本，展示安全憑證庫的基礎生命週期管理，適合初學者理解原理：
*   `Generate_Credentials.ps1`: 建立並加密儲存憑證檔案。
*   `Manage_Credentials.ps1`: 管理憑證庫（查詢標籤、新增/更新密碼）。
*   `Verify_Credentials.ps1`: 驗證解密功能，模擬排程任務讀取憑證的行為。
*   [詳細操作手冊](./Credential_POC/README.md)

### 4. Windows 檔案安全機制 (MOTW)
研究並處理來自網路下載檔案的限制問題：
*   [**MOTW 機制說明**](./MOTW/README.md): 解釋 `Zone.Identifier` 與 NTFS 備用資料流 (ADS) 的原理。
*   **find_motw**: 包含 `find_motw.ps1` 腳本，用於遞迴搜尋並識別目錄下所有帶有網路標記的檔案。

## 🛠️ 主要解決的問題
1.  **跨環境憑證解密**: 透過 AES-256 打破 Windows DPAPI 的機器限制，讓憑證能在 CI/CD 或 Docker 中流通。
2.  **安全性稽核**: 解決「誰在何時使用了哪組密碼」的合規性問題。
3.  **腳本執行警告**: 處理因檔案帶有 MOTW 標籤而產生的安全性警告或封鎖。
4.  **敏感資訊外洩**: 避免在自動化腳本中以明碼寫死密碼，改用加密檔案或環境變數。

## ⚠️ 免責聲明
本專案內容僅供技術研究與開發參考。在生產環境中使用 AES 金鑰或其他加密方案時，請務必嚴格控管金鑰權限與 NTFS 存取清單 (ACL)。
