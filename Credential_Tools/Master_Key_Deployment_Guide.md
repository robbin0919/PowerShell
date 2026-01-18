# Master Key 部署指南 (Linux / Docker / K8s)

本文件說明如何將 Windows 端產生的 `master.key` 安全地部署至 Linux 或容器環境，以解鎖 `Global_Credentials.xml` 中的憑證。

---

## 1. 檔案掛載模式 (Volume Mount)
適用於：**Linux VM**、**單機 Docker**、**排程伺服器**。

這是最直接的方式，將 Windows 上產生的檔案複製到目標環境的指定目錄。

### 步驟
1.  **準備檔案**：確認 Windows 端的 `PowerShell_Guide/Credential_Tools/Data/master.key` 存在。
2.  **傳輸檔案**：
    *   **Linux VM**: 使用 SCP 或 SFTP 上傳。
        ```bash
        scp ./Data/master.key user@linux-server:/opt/scripts/Data/
        ```
    *   **Docker**: 使用 `-v` 參數掛載。
        ```bash
        docker run -d \
          -v $(pwd)/Data:/app/Data \
          my-automation-image
        ```
3.  **權限設定 (重要)**：
    在 Linux 上，必須限制該檔案僅能由執行腳本的使用者讀取。
    ```bash
    chmod 600 /opt/scripts/Data/master.key
    chown script-user:script-group /opt/scripts/Data/master.key
    ```

---

## 2. 環境變數模式 (Environment Variable)
適用於：**CI/CD Pipeline** (GitLab CI, GitHub Actions)、**Serverless**。

*注意：目前的 `CredentialManager.psm1` 預設讀取檔案。若需支援此模式，需修改 `Get-MasterKey` 邏輯以讀取 `$env:CREDENTIAL_MASTER_KEY`。*

### 步驟
1.  **轉換 Key 為 Base64**:
    在 Windows PowerShell 執行：
    ```powershell
    $Bytes = Get-Content "./Data/master.key" -Encoding Byte
    [Convert]::ToBase64String($Bytes)
    # 輸出範例: u8x/9sL... (複製這串字)
    ```
2.  **設定變數**:
    在 CI/CD 設定中加入變數 `CREDENTIAL_MASTER_KEY`，值為剛才複製的 Base64 字串。

---

## 3. Kubernetes Secret 模式
適用於：**Kubernetes (K8s)**、**OpenShift**。

這是容器編排平台的標準作法，將 Key 視為機敏物件管理。

### 步驟
1.  **建立 Secret**:
    ```bash
    kubectl create secret generic ps-master-key \
      --from-file=master.key=./Data/master.key
    ```
2.  **掛載至 Pod**:
    在 Deployment YAML 中設定掛載點：
    ```yaml
    volumeMounts:
      - name: secret-volume
        mountPath: "/app/Data/master.key"
        subPath: "master.key"
        readOnly: true
    volumes:
      - name: secret-volume
        secret:
          secretName: ps-master-key
    ```
---

## ⚠️ 安全檢查清單
*   [ ] **切勿** 將 `master.key` 提交至 Git 儲存庫 (應加入 `.gitignore`)。
*   [ ] **切勿** 將 `master.key` 內建於 Docker Image (Dockerfile COPY) 中。
*   [ ] 在生產環境中，應定期輪替 (Rotate) 金鑰：
    1.  產生新 Key。
    2.  解密所有憑證。
    3.  用新 Key 重新加密。
    4.  重新部署新 Key。
