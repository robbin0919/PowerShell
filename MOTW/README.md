# Mark of the Web (MOTW) 安全機制說明

## 什麼是 MOTW？

**MOTW** 是 **Mark of the Web** 的縮寫，這是 Windows 作業系統內建的一種安全機制。

當您從網際網路（例如，透過瀏覽器）下載檔案時，系統會自動為該檔案附加此標記，以識別其來源。

## MOTW 如何運作？

技術上，MOTW 是透過在檔案的 NTFS 檔案系統中附加一個名為 `Zone.Identifier` 的**「備用資料流」 (Alternate Data Stream, ADS)** 來實現的。這個資料流就是 MOTW 的具體實作，裡面記錄了該檔案來自於「網際網路區域」(Internet Zone)。

## MOTW 的影響？

作業系統和許多應用程式（如 Microsoft Office、Outlook 等）會檢查這個標記。如果偵測到 MOTW，它們會採取保護措施，例如：

*   **Microsoft Office**：會以「受保護的檢視」模式開啟檔案，限制編輯和宏的執行。
*   **執行檔或腳本**：在執行前，系統會向您顯示額外的安全警告，需要您手動確認才能繼續。
*   在某些情況下，檔案的執行會被完全阻止。

## 如何移除 MOTW？

有兩種主要的方法可以移除 MOTW，讓系統將檔案視為安全的本機檔案：

#### 1. 手動方式

*   在檔案上按右鍵 -> 選擇「**內容**」。
*   在「**一般**」分頁的下方，您會看到一個安全性的提示。
*   勾選「**解除封鎖**」，然後點擊「套用」或「確定」。

![手動解除封鎖](https://i.imgur.com/example.png)  <!-- 這是一個示意圖，實際路徑可能不同 -->

#### 2. PowerShell 指令 (批次處理)

使用 `Unblock-File` 這個 PowerShell 指令，可以有效率地對單一或多個檔案進行批次解除封鎖。

##### PowerShell 批次移除 MOTW 範例

以下指令可以解除指定資料夾及其所有子資料夾中，全部檔案的 MOTW 標記：

```powershell
Get-ChildItem D:\MOTW_LAB\Schedule_Job\*.* -Recurse | Unblock-File
```

##### 指令分解

*   **`Get-ChildItem D:\MOTW_LAB\Schedule_Job\*.* -Recurse`**
    *   `Get-ChildItem`: 尋找檔案和資料夾。
    *   `D:\MOTW_LAB\Schedule_Job\*.*`: 指定要尋找的路徑和檔案類型（`*.*` 代表所有檔案）。
    *   `-Recurse`: 包含所有子資料夾。
    *   **作用**：找出指定路徑下的所有檔案。

*   **`|` (管線符號)**
    *   **作用**：將左邊指令的結果（找到的檔案列表）逐一傳遞給右邊的指令。

*   **`Unblock-File`**
    *   **作用**：接收從管線傳來的檔案，並移除其 `Zone.Identifier` 備用資料流，也就是解除 MOTW 標記。

---

## 如何查詢帶有 MOTW 標記的檔案

您可以透過 PowerShell 或傳統命令提示字元 (CMD) 來檢查檔案是否被標記。

### 方法一：使用 PowerShell (建議)

請開啟 PowerShell 終端機，並執行以下指令：

```powershell
Get-ChildItem -Path D:\MOTW_LAB\ -Recurse | ForEach-Object {
    if (Get-Item -Path $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
        Write-Host "發現被標記的檔案 (MOTW): $($_.FullName)"
    }
}
```

#### 指令說明
*   `Get-ChildItem -Recurse`: 遞迴地取得指定路徑下的所有檔案。
*   `ForEach-Object`: 針對每一個找到的檔案執行後續的檢查。
*   `Get-Item -Stream Zone.Identifier`: 嘗試讀取名為 `Zone.Identifier` 的備用資料流 (ADS)。
*   `-ErrorAction SilentlyContinue`: 忽略讀取不到 ADS 時的錯誤，保持輸出乾淨。
*   `if (...)`: 如果成功讀取到 ADS (表示 MOTW 存在)，則條件成立。
*   `Write-Host`: 印出被標記檔案的完整路徑。

#### 結果解讀
*   **有輸出**: 會列出所有被 MOTW 標記的檔案路徑。
*   **無輸出**: 代表該目錄中沒有任何檔案被標記。

---

### 方法二：使用命令提示字元 (CMD)

請開啟命令提示字元 (CMD)，並執行以下指令：

```cmd
dir /r /s "D:\MOTW_LAB" | findstr /i ":Zone.Identifier"
```

#### 指令說明
*   `dir /r /s`: `/r` 顯示檔案的備用資料流 (ADS)，`/s` 進行遞迴搜尋。
*   `| findstr /i ":Zone.Identifier"`: 將 `dir` 的輸出結果傳遞給 `findstr`，並篩選出包含 `:Zone.Identifier` 的那幾行。

#### 結果解讀
*   **有輸出**: 會顯示類似 `128 file.exe:Zone.Identifier:$DATA` 的資訊，表示 `file.exe` 被標記了。
*   **無輸出**: 代表沒有檔案被標記。

##### 輸出細節解析
在 `128 file.exe:Zone.Identifier:$DATA` 中：
*   **`128`**: 代表 `Zone.Identifier` 這個備用資料流的大小，單位是位元組 (bytes)。
*   **`$DATA`**: 是資料流的「類型名稱」，表示這是一個標準的資料儲存串流。關鍵是前面的 `:Zone.Identifier` 名稱。