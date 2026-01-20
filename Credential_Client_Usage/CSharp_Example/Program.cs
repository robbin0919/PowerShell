using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;

namespace CredentialClient
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args.Contains("-h") || args.Contains("--help"))
            {
                Console.WriteLine("Usage: dotnet run -- [options]");
                Console.WriteLine("Options:");
                Console.WriteLine("  --store <path>  Path to the credential XML file (default: auto-detect)");
                Console.WriteLine("  --key <path>    Path to the master key file (default: auto-detect or master.key next to XML)");
                return;
            }

            // 預設路徑邏輯 (自動搜尋)
            string baseDir = FindProjectRoot();
            string storePath = Path.Combine(baseDir, "MySecrets.xml");
            string masterKeyPath = Path.Combine(baseDir, "master.key");

            // 解析命令列參數
            for (int i = 0; i < args.Length; i++)
            {
                if ((args[i] == "--store" || args[i] == "-s") && i + 1 < args.Length)
                {
                    storePath = args[i + 1];
                    i++;
                }
                else if ((args[i] == "--key" || args[i] == "-k") && i + 1 < args.Length)
                {
                    masterKeyPath = args[i + 1];
                    i++;
                }
            }
            
            // 若使用者只指定 Store，未指定 Key，嘗試在 Store 同目錄下找 master.key
            if (args.Contains("--store") && !args.Contains("--key"))
            {
                string storeDir = Path.GetDirectoryName(storePath) ?? "";
                string potentialKey = Path.Combine(storeDir, "master.key");
                if (File.Exists(potentialKey))
                {
                    masterKeyPath = potentialKey;
                }
            }

            Console.WriteLine($"[C# Credential Client Example]");
            Console.WriteLine($"Store Path: {Path.GetFullPath(storePath)}");
            Console.WriteLine($"Key Path:   {Path.GetFullPath(masterKeyPath)}");

            if (!File.Exists(storePath))
            {
                Console.WriteLine($"Error: Credential store file not found at: {storePath}");
                Console.WriteLine("Please run the PowerShell example to generate it or specify the correct path using --store.");
                return;
            }

            try
            {
                // 1. 讀取 Master Key
                if (!File.Exists(masterKeyPath))
                {
                    Console.WriteLine($"Error: Master key file not found at: {masterKeyPath}");
                     return;
                }
                
                string keyBase64 = File.ReadAllText(masterKeyPath).Trim();
                byte[] masterKey = Convert.FromBase64String(keyBase64);

                // 2. 讀取並解析 XML 取得加密資料
                var credential = CredentialStore.GetCredential("MyService", storePath);

                if (credential == null)
                {
                    Console.WriteLine("Credential 'MyService' not found in store.");
                    return;
                }

                Console.WriteLine($"\nFound Credential for User: {credential.UserName}");

                // 3. 解密密碼
                string plainPassword = PowerShellDecryptor.Decrypt(credential.EncryptedPassword, masterKey);
                
                Console.WriteLine($"Decrypted Password: {plainPassword}");
                // 模擬使用
                Console.WriteLine($"Connecting to service as {credential.UserName}...");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error: {ex.Message}");
                if (ex.InnerException != null) Console.WriteLine($"Inner: {ex.InnerException.Message}");
            }
        }

        static string FindProjectRoot()
        {
            // 簡單的輔助方法，往上尋找包含 MySecrets.xml 的目錄
            string current = Directory.GetCurrentDirectory();
            for (int i = 0; i < 4; i++)
            {
                if (File.Exists(Path.Combine(current, "MySecrets.xml"))) return current;
                var parent = Directory.GetParent(current);
                if (parent == null) break;
                current = parent.FullName;
            }
            // Fallback to strict relative path from source location
            return Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "..", ".."));
        }
    }

    public class CredentialItem
    {
        public string UserName { get; set; } = "";
        public string EncryptedPassword { get; set; } = "";
        public string EncryptionType { get; set; } = "";
    }

    public static class CredentialStore
    {
        public static CredentialItem? GetCredential(string keyName, string xmlPath)
        {
            // 解析 PowerShell Export-Clixml 產生的 Hashtable
            // 結構: <Objs><Obj><DCT><En> ... Entries ... </En></DCT></Obj></Objs>
            // 每個 Entry: <S N="Key">TheKeyName</S> <Obj N="Value">TheContent</Obj>
            
            XDocument doc = XDocument.Load(xmlPath);
            
            // 找到 Hashtable 的 Entries
            var entries = doc.Descendants("En");

            foreach (var entry in entries)
            {
                // 檢查 Key
                var keyElement = entry.Elements("S").FirstOrDefault(e => e.Attribute("N")?.Value == "Key");
                if (keyElement != null && keyElement.Value == keyName)
                {
                    // 找到對應的 Value 物件
                    var valueObj = entry.Elements("Obj").FirstOrDefault(e => e.Attribute("N")?.Value == "Value");
                    if (valueObj != null)
                    {
                        // 解析 PSCustomObject 的屬性 (MS -> S)
                        var props = valueObj.Descendants("MS").FirstOrDefault();
                        if (props != null)
                        {
                            var item = new CredentialItem();
                            
                            // 讀取屬性: Identity, Value, EncryptionType
                            // 注意: 屬性可能在 <S> (String) 標籤中
                            foreach (var prop in props.Elements())
                            {
                                string name = prop.Attribute("N")?.Value ?? "";
                                string val = prop.Value;

                                if (name == "Identity") item.UserName = val;
                                else if (name == "UserName") item.UserName = val; // 相容性
                                else if (name == "Value") item.EncryptedPassword = val;
                                else if (name == "EncryptionType") item.EncryptionType = val;
                            }
                            return item;
                        }
                    }
                }
            }
            return null;
        }
    }

    public static class PowerShellDecryptor
    {
        /// <summary>
        /// 解密 PowerShell ConvertFrom-SecureString -Key 的輸出字串
        /// </summary>
        public static string Decrypt(string encryptedBase64, byte[] key)
        {
            if (string.IsNullOrEmpty(encryptedBase64)) throw new ArgumentException("Encrypted string is empty");

            // 1. Base64 Decode -> Bytes
            byte[] rawBytes = Convert.FromBase64String(encryptedBase64);

            // 2. Bytes -> Unicode String -> Split by '|'
            // Format: Header | EncryptedData(Base64) | IV(Base64)
            string combinedString = Encoding.Unicode.GetString(rawBytes);
            string[] parts = combinedString.Split('|');

            if (parts.Length != 3)
            {
                throw new FormatException("Invalid encrypted string format. Expected 3 parts separated by '|'.");
            }

            // part[0] is Header/Signature (skip)
            string cipherBase64 = parts[1];
            string ivBase64 = parts[2];

            byte[] cipherBytes = Convert.FromBase64String(cipherBase64);
            byte[] ivBytes = Convert.FromBase64String(ivBase64);

            using (Aes aes = Aes.Create())
            {
                aes.Key = key;
                aes.IV = ivBytes;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;

                using (var decryptor = aes.CreateDecryptor())
                using (var ms = new MemoryStream(cipherBytes))
                using (var cs = new CryptoStream(ms, decryptor, CryptoStreamMode.Read))
                using (var reader = new StreamReader(cs, Encoding.Unicode))
                {
                    return reader.ReadToEnd();
                }
            }
        }
    }
}
