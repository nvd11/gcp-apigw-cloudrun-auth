# 🔐 为 GitHub Actions 配置 Workload Identity Federation (WIF)

## 为什么使用 WIF？（无秘钥安全架构）
传统上，使用 GitHub Actions 部署代码到 GCP 需要生成一个长期有效的 Service Account JSON 秘钥文件，并将其存储在 GitHub Secrets 中。如果这个秘钥不慎泄露，将带来灾难性的安全风险。

**Workload Identity Federation (WIF)** 通过 OIDC (OpenID Connect) 彻底解决了这个问题。GCP 不再向 GitHub 发放永久秘钥，而是与 GitHub 建立一种“信任关系”。当 GitHub Action 运行时，它会向 GCP 出示一个短期的 OIDC 令牌 (Token)。GCP 验证该令牌的合法性，检查对应的 GitHub 仓库是否在白名单内，然后允许 GitHub Action 临时“模拟 (Impersonate)” 一个 GCP Service Account 去执行部署任务。

**全程无需 JSON 秘钥，安全性拉满！**

---

## 🛠️ 详细配置步骤指北

请在您的终端中运行以下脚本（确保您已登录 `gcloud` 并且在 `jason-hsbc` 项目中拥有 Owner 或 Org Admin 权限）。

### 第 1 步：定义环境变量
如果您的 GitHub 仓库名称变了，请记得修改 `REPO` 变量。
```bash
export PROJECT_ID="jason-hsbc"
export REPO="nvd11/gcp-apigw-cloudrun-auth"
export SERVICE_ACCOUNT="github-actions-sa"
export POOL_NAME="github-pool"
export PROVIDER_NAME="github-provider"
```

### 第 2 步：创建用于部署的 Service Account
这就是后续 GitHub Actions 去执行 `gcloud run deploy` 时所套用的“马甲”身份。
```bash
gcloud iam service-accounts create $SERVICE_ACCOUNT \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions Deployment SA"
```

### 第 3 步：赋予该 SA 必要的部署权限
GitHub Actions 需要向 Artifact Registry 推送镜像、更新 Cloud Run，以及可能要操作 API Gateway，所以我们要给足对应的角色权限。
```bash
for role in "roles/run.admin" "roles/artifactregistry.writer" "roles/iam.serviceAccountUser" "roles/apigateway.admin"; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
      --role="$role"
done
```

### 第 4 步：创建 WIF 身份池 (Identity Pool)
身份池就相当于 GCP 里接待外部访客的大厅。
```bash
gcloud iam workload-identity-pools create $POOL_NAME \
    --project="${PROJECT_ID}" --location="global" \
    --display-name="GitHub Actions Pool"
```

### 第 5 步：将 GitHub 添加为 OIDC 提供商 (Provider)
这一步是与 GitHub 建立信任。我们需要将 GitHub 发过来的凭证字段（如 repository 名字）映射到 GCP 的属性上。
```bash
gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
    --project="${PROJECT_ID}" --location="global" --workload-identity-pool=$POOL_NAME \
    --display-name="GitHub Actions Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
    --issuer-uri="https://token.actions.githubusercontent.com"
```

### 第 6 步：绑定 GitHub 仓库与 Service Account
**极度重要的安全步骤：** 这个操作规定了，**只有您指定的这个 GitHub 仓库** (`nvd11/gcp-apigw-cloudrun-auth`) 才有资格去冒充刚才创建的部署 SA。其他的仓库即便知道 ID，也会被 GCP 拒绝。
```bash
export WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe $POOL_NAME \
  --project="${PROJECT_ID}" --location="global" --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${REPO}"
```

---

## 🎯 最终输出 (用于 GitHub Actions 配置)
配置完成后，我们需要获取这个 WIF Provider 的唯一资源名称，这串字符串将会被写在 `.github/workflows/deploy.yml` 文件里。请执行：

```bash
echo "projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"
```

**请将终端输出的字符串保存下来！** 它看起来应该类似这样：
`projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider`
