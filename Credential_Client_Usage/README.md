# Credential Client Usage Guide

此目錄提供了如何從不同環境讀取加密憑證的範例。我們將 PowerShell 與 .NET (C#) 的實作完全隔離，以避免對依賴項產生誤解。

## 📂 範例目錄

### 1. [PowerShell 範例](./PowerShell_Example/)
- **適用場景**：PowerShell 自動化腳本、維運工作。
- **依賴項**：需引用目錄下的 `Modules/CredentialManager.psm1`。
- **特點**：使用原生 PowerShell 指令，開發最快速。

### 2. [C# (.NET) 範例](./CSharp_Example/)
- **適用場景**：編譯式應用程式、純 .NET 環境、容器化服務。
- **依賴項**：**不依賴** PowerShell 模組。解密邏輯已內建於 C# 程式碼中。
- **特點**：跨平台效能佳，適合整合進大型專案。

---

## 🔑 共用資源 (機敏檔案)

無論使用哪種語言，都需要以下由管理員產生的檔案：
- `MySecrets.xml`: 加密後的憑證資料庫。
- `master.key`: AES 解密金鑰 (跨機模式必備)。

> **注意**：這些檔案通常不應進入版本控制，請確保它們放置於此目錄或在腳本中正確設定路徑。
