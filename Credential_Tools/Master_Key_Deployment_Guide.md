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
適用於：**CI/CD Pipeline** (GitLab CI, GitHub Actions)、**Serverless**、**Docker**。

**本工具已原生支援此模式。** 程式會自動偵測名為 `PS_MASTER_KEY` 的環境變數。

### 步驟
1.  **取得 Key**:
    打開 `Data/master.key` 檔案，複製裡面的純文字內容 (已是 Base64 格式)。
    *   範例內容: `u8x/9sL...`
2.  **設定變數**:
    *   **Docker**: `docker run -e PS_MASTER_KEY="u8x/9sL..." my-image`
    *   **K8s (Env)**: 使用 `valueFrom: secretKeyRef` 將 Secret 注入為環境變數。
    *   **CI/CD**: 在專案設定中加入變數 `PS_MASTER_KEY`。

---

## 3. Kubernetes Secret 模式
適用於：**Kubernetes (K8s)**、**OpenShift**。

首先，您需要先將 `master.key` 建立為 K8s Secret：
```bash
# 從檔案建立 Secret
kubectl create secret generic ps-master-key --from-file=master.key=./Data/master.key

# 或者，若要用環境變數模式，也可以直接給 Base64 字串
# kubectl create secret generic ps-master-key --from-literal=PS_MASTER_KEY="u8x/9sL..."
```

### 方式 A：掛載成檔案 (Mount as File)
適用於不想改動現有程式邏輯，讓程式去讀 `/app/Data/master.key`。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: automation-job-file
spec:
  containers:
  - name: script-runner
    image: my-automation-image
    volumeMounts:
    - name: secret-vol
      mountPath: "/app/Data/master.key"  # 掛載目標路徑
      subPath: "master.key"              # 只掛載單一檔案
      readOnly: true
  volumes:
  - name: secret-vol
    secret:
      secretName: ps-master-key
```

### 方式 B：注入成環境變數 (Inject as Env Var)
適用於 CI/CD 或現代化部署，程式會直接讀取 `$env:PS_MASTER_KEY`。**這是最推薦的雲端原生做法。**

**前置作業**：建立 Secret 時，建議 Key 名稱設為 `PS_MASTER_KEY` 或是使用 Base64 字串。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: automation-job-env
spec:
  containers:
  - name: script-runner
    image: my-automation-image
    env:
    - name: PS_MASTER_KEY  # 容器內的環境變數名稱
      valueFrom:
        secretKeyRef:
          name: ps-master-key  # K8s Secret 物件名稱
          key: master.key      # Secret 裡的 Key (如果用 from-file 建立，預設是檔名)
    # 注意：K8s Secret 存的是 Base64，但注入 Env 時會解碼回原始值。
    # 由於我們的 master.key 原始值就是 "Base64字串"，所以注入到環境變數後
    # 依然是那個 Base64 字串，程式可以直接讀取，非常安全。
```

#### 💡 關於方式 B 的補充
由於現在 `master.key` 預設已儲存為 Base64 純文字格式，您不需要擔心二進位編碼問題。
直接使用 `kubectl create secret generic ps-master-key --from-file=master.key=./Data/master.key` 即可完美運作。
---

## ⚠️ 安全檢查清單
*   [ ] **切勿** 將 `master.key` 提交至 Git 儲存庫 (應加入 `.gitignore`)。
*   [ ] **切勿** 將 `master.key` 內建於 Docker Image (Dockerfile COPY) 中。
*   [ ] 在生產環境中，應定期輪替 (Rotate) 金鑰：
    1.  產生新 Key。
    2.  解密所有憑證。
    3.  用新 Key 重新加密。
    4.  重新部署新 Key。
