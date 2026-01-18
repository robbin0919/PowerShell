# PowerShell 加密憑證檔案疑難排解指南

本文件說明當遭遇「孤兒憑證檔」（來源不明或無法解密的 `.xml` 檔案）時，如何透過數位鑑識手段識別其所屬的環境與使用者，以及說明與 C#/.NET 專案整合的可行性。

## 1. 遺失歸屬資訊時的識別策略

當您手邊有一份加密憑證檔，但不確定它屬於哪台機器或哪個帳號時，可依序使用以下方法進行鑑識。

### 策略 A：檢視檔案明文內容 (識別帳號)
雖然密碼受 DPAPI 保護，但 **使用者名稱 (UserName)** 與 **標籤 (Key)** 通常是以明文儲存。
*   **工具**：使用 `Manage_Credentials.ps1 -Action List`。
*   **判斷**：
    *   若帳號顯示 `DOMAIN\SQL_Backup_User`，則該檔案極高機率僅能由該網域帳號解密。
    *   這能協助您鎖定「執行身分 (Who)」。

### 策略 B：檢查 NTFS 擁有者 (識別建立者)
若檔案未經特殊複製（保留了原始 ACL），檔案擁有者通常即為建立者（也就是唯一能解密的人）。
*   **指令**：
    ```powershell
    Get-Acl ".\Unknown_Creds.xml" | Select-Object Owner
    ```
*   **判斷**：若 Owner 為 `CORP\WebAdmin`，則您必須以該帳號登入才能解密。

### 策略 C：暴力探針測試 (識別機器)
若懷疑檔案屬於某幾台特定伺服器，可將檔案複製過去並執行以下簡單指令進行「試誤 (Trial and Error)」。
```powershell
# 探針測試指令 (一列式)
try { $c=Import-Clixml "./File.xml"; $c.Values[0].GetNetworkCredential().Password; "✅ 成功匹配" } catch { "❌ 失敗" }
```
*   **原理**：DPAPI 解密失敗會立即拋出異常，若無錯誤則代表找到了正確的「機器 + 使用者」組合。

### ⚠️ 最終手段
若上述方法皆無效（例如檔案被複製導致 Owner 遺失，且帳號為通用名稱），由於 DPAPI 的強加密特性，該檔案將**無法復原**。此時「重新建立檔案」是唯一解法。

---

## 2. 進階整合：在 C# (.NET) 應用程式中讀取

PowerShell 產生的 Clixml 檔案可被 C# 應用程式讀取，但無法使用標準的 `XmlSerializer`。

### 必要條件
1.  **環境限制**：C# 程式執行的 **機器** 與 **使用者身分** 必須與建立該 `.xml` 的環境完全一致 (DPAPI 限制)。
2.  **SDK 引用**：專案需安裝 NuGet 套件 `Microsoft.PowerShell.SDK` 或引用 `System.Management.Automation.dll`。

### 程式碼範例 (C#)
```csharp
using System.Management.Automation; // 需引用此命名空間

public void LoadCredentials(string xmlPath)
{
    // 使用 PowerShell 專用的還原序列化器
    // 注意：此行會觸發 DPAPI 解密，若身分不符將會拋出例外
    var deserializedObj = PSSerializer.Deserialize(xmlPath);

    if (deserializedObj is System.Collections.Hashtable credStore)
    {
        foreach (System.Collections.DictionaryEntry entry in credStore)
        {
            var key = entry.Key.ToString();
            var cred = entry.Value as PSCredential;
            
            // 取得明文密碼
            string password = cred.GetNetworkCredential().Password;
            
            Console.WriteLine($"標籤: {key}, 帳號: {cred.UserName}");
        }
    }
}
```

### 最佳實務
若您的專案混合了 PowerShell 腳本與 C# 程式：
*   建議統一由 PowerShell 負責產製憑證檔 (`Export-Clixml`)。
*   C# 端透過 `PSSerializer` 讀取，以確保安全性與格式一致。
