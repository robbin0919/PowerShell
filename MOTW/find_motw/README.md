# 如何在 CMD 中執行 PowerShell 指令碼 (`find_motw.ps1`)

此文件說明如何在 CMD (命令提示字元) 中執行 `find_motw.ps1` 這個 PowerShell 指令碼。

## 關於 `find_motw.ps1`

這個指令碼的用途是遞迴地搜尋指定資料夾中的所有檔案，並列出哪些檔案帶有「Mark of the Web (MOTW)」標記。

**最新指令碼 (`find_motw.ps1`):**
```powershell
param(
    [string]$Path = "."
)

Get-ChildItem -Path $Path -Recurse | ForEach-Object {
    if ($_.PSIsContainer -eq $false) {
        try {
            $stream = Get-Item -Path $_.FullName -Stream Zone.Identifier -ErrorAction Stop
            if ($stream) {
                Write-Host "發現檔案帶有網路標記 (MOTW): $($_.FullName)"
            }
        }
        catch {
            # This will suppress errors for files that don't have the Zone.Identifier stream
        }
    }
}
```

---

## 在 CMD 中執行 PowerShell 指令碼的步驟

1.  **開啟 CMD**：
    按下 `Win + R` 鍵，輸入 `cmd`，然後按 `Enter`。

2.  **導航到此指令碼所在的目錄**：
    使用 `cd` 命令導航到 `find_motw.ps1` 檔案所在的目錄 (`MOTW/find_motw`)。例如：
    ```cmd
    cd /d "D:\LAB\Notebook\MOTW\find_motw"
    ```

3.  **執行 PowerShell 指令碼**：
    執行以下指令來運行 `find_motw.ps1` 檔案。我們使用 `-ExecutionPolicy Bypass` 來確保指令碼可以被執行。

    ### 掃描特定目錄
    使用 `-Path` 參數來指定您想掃描的資料夾。
    ```cmd
    powershell.exe -ExecutionPolicy Bypass -File ".\find_motw.ps1" -Path "您想掃描的資料夾路徑"
    ```
    **範例：**
    ```cmd
    powershell.exe -ExecutionPolicy Bypass -File ".\find_motw.ps1" -Path "D:\Downloads"
    ```

    ### 掃描目前目錄
    如果省略 `-Path` 參數，指令碼將預設掃描其所在的目前目錄。
    ```cmd
    powershell.exe -ExecutionPolicy Bypass -File ".\find_motw.ps1"
    ```
    *   `-ExecutionPolicy Bypass`: 暫時繞過當前的執行策略，允許指令碼運行。這只影響當前會話，不會永久更改您的系統設定。
    *   `-File ".\find_motw.ps1"`: 指定要執行的 PowerShell 指令碼檔案。`."` 代表當前目錄。
