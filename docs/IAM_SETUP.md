# 🔐 为 GitHub Actions 配置 IAM 权限 (JSON Key 模式)

## 为什么回退到 JSON Key？
在最初的架构设计中，我们计划使用 **Workload Identity Federation (WIF)** 来实现无秘钥部署。但由于 `jason-hsbc` 项目所在的 GCP Organization 实施了严格的 Org Policy (`constraints/iam.workloadIdentityPoolProviders`)，封禁了所有未授权的外部 OIDC 发行方（包括 GitHub）。
因此，本实验采取降级方案，使用传统的 Service Account JSON Key 进行 CI/CD 认证。

---

## 🛠️ 配置步骤

进入项目的 `infra/` 目录，执行初始化脚本：

```bash
cd infra
./init-iam.sh
```

该脚本将自动完成以下操作：
1. 开启 Cloud Run, Artifact Registry, API Gateway 相关的基础 API。
2. 创建 3 个各司其职的 Service Account (`github-actions-sa`, `cr-webui-runtime-sa`, `gateway-invoker`)。
3. 为 `github-actions-sa` 赋予项目级的部署权限 (`run.admin`, `artifactregistry.writer`, `apigateway.admin`)。
4. **最小权限安全绑定**：仅允许 `github-actions-sa` 冒充 (Impersonate) 专门用于 Web UI 的 `cr-webui-runtime-sa`，隔离其他高权限 SA。

---

## 🔑 生成凭证并上传至 GitHub
脚本执行完毕后，您需要手动为 `github-actions-sa` 生成一把 JSON 钥匙：

```bash
gcloud iam service-accounts keys create credentials.json \
    --iam-account=github-actions-sa@jason-hsbc.iam.gserviceaccount.com
```

拿到 `credentials.json` 文件后：
1. 打开本 GitHub 仓库的 **Settings** -> **Secrets and variables** -> **Actions**。
2. 点击 **New repository secret**。
3. Name 填入：`GCP_CREDENTIALS`
4. Value 填入：`credentials.json` 文件中的全部内容。
