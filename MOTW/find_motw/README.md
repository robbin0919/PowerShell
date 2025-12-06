# 如何在 CMD 中執行 PowerShell 腳本 (`find_motw.ps1`)

此文件說明如何在 CMD (命令提示字元) 中執行 `find_motw.ps1` 這個 PowerShell 腳本。

## 關於 `find_motw.ps1`

這個腳本的用途是遞迴地搜尋指定資料夾中的所有檔案，並列出哪些檔案帶有「Mark of the Web (MOTW)」標記。

**腳本內容 (`find_motw.ps1`):**
```powershell
Get-ChildItem -Path D:\MOTW_LAB\ -Recurse | ForEach-Object {
    if (Get-Item -Path $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
        Write-Host "發現被標記的檔案 (MOTW): $($_.FullName)"
    }
}
```

**重要提示：**
腳本中的 `D:\MOTW_LAB\` 是一個 **範例路徑**。在執行之前，請務必根據您的實際需求，修改 `find_motw.ps1` 檔案中的路徑。

---

## 在 CMD 中執行 PowerShell 檔案的步驟

1.  **開啟 CMD**：
    按下 `Win + R` 鍵，輸入 `cmd`，然後按 `Enter`。

2.  **導航到此腳本所在的目錄**：
    使用 `cd` 命令導航到 `find_motw.ps1` 檔案所在的目錄 (`MOTW/find_motw`)。例如：
    ```cmd
    cd /d "D:\LAB\Notebook\MOTW\find_motw"
    ```

3.  **執行 PowerShell 檔案**：
    執行以下指令來運行 `find_motw.ps1` 檔案。我們使用 `-ExecutionPolicy Bypass` 來確保腳本可以被執行。

    ```cmd
powershell.exe -ExecutionPolicy Bypass -File ".\find_motw.ps1"
    ```
    *   `-ExecutionPolicy Bypass`: 暫時繞過當前的執行策略，允許腳本運行。這只影響當前會話，不會永久更改您的系統設定。
    *   `-File ".\find_motw.ps1"`: 指定要執行的 PowerShell 腳本檔案。`."` 代表當前目錄。
