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

當憑證庫升級為 AES 模式時，C# 應用程式必須配合以下邏輯：

#### 1. 讀取 Base64 格式的 Master Key
由於 `master.key` 現在是 Base64 純文字，讀取方式如下：
```csharp
string base64Key = File.ReadAllText("master.key").Trim();
byte[] aesKey = Convert.FromBase64String(base64Key);
```

#### 2. 解密 AES 憑證 (推薦做法)
強烈建議使用 **PowerShell SDK** 進行解密，以避免自行實作 AES 演算法時與 PowerShell `ConvertTo-SecureString` 的內部格式不相容。

```csharp
using System.Management.Automation;

public PSCredential DecryptWithPowerShell(string userName, string encryptedPass, byte[] aesKey)
{
    using (PowerShell ps = PowerShell.Create())
    {
        // 傳遞 Key 並呼叫 PowerShell 指令進行還原
        ps.AddCommand("ConvertTo-SecureString")
          .AddParameter("String", encryptedPass)
          .AddParameter("Key", aesKey);
        
        var securePass = ps.Invoke<System.Security.SecureString>()[0];
        return new PSCredential(userName, securePass);
    }
}
```

#### 方式三：使用純 .NET SDK 解密 (進階/輕量化)

**為什麼需要手動解析？**
PowerShell 的 `ConvertTo-SecureString` 產出的加密字串並非單純的密文，而是一個包含 **IV (初始化向量)** 與 **Cipher Text (密文)** 的混合結構 (通常以 Hex 字串呈現)。若不使用 SDK，您必須自行「拆包」才能解密。

| 特性 | PowerShell SDK (方式二) | 純 .NET SDK (方式三) |
| :--- | :--- | :--- |
| **依賴性** | 需引用 `Microsoft.PowerShell.SDK` (較重) | **零依賴** (內建於 System) |
| **程式碼** | 極簡 (約 3 行) | 較繁瑣 (需自行處理 Hex/IV/Stream) |
| **穩定性** | **高** (官方維護相容性) | **中** (若 PowerShell 內部格式變更需手動維護) |
| **適用場景**| 快速開發、企業級應用 | 微服務、Lambda/Functions、極致輕量化 |

**實作範例：**
```csharp
using System.Security.Cryptography;
using System.Text;

public string DecryptPureDotNet(string hexString, byte[] masterKey)
{
    // 1. 將 Hex 轉為 Byte[]
    byte[] fullData = Enumerable.Range(0, hexString.Length / 2)
                        .Select(x => Convert.ToByte(hexString.Substring(x * 2, 2), 16))
                        .ToArray();

    // 2. 拆分 IV (前 16 bytes) 與 密文
    byte[] iv = fullData.Take(16).ToArray();
    byte[] cipherText = fullData.Skip(16).ToArray();

    // 3. 標準 AES 解密
    using (Aes aes = Aes.Create())
    {
        aes.Key = masterKey;
        aes.IV = iv;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;

        using (var decryptor = aes.CreateDecryptor())
        using (var ms = new MemoryStream(cipherText))
        using (var cs = new CryptoStream(ms, decryptor, CryptoStreamMode.Read))
        using (var sr = new StreamReader(cs, Encoding.Unicode)) // UTF-16LE
        {
            return sr.ReadToEnd();
        }
    }
}
```

### 最佳實務
若您的專案混合了 PowerShell 腳本與 C# 程式：
*   建議統一由 PowerShell 負責產製憑證檔 (`Export-Clixml`)。
*   C# 端讀取 `master.key` 時請注意去除空白。
*   解密邏輯應優先調用 PowerShell SDK，以確保 100% 的相容性與安全性。
