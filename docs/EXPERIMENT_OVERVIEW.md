# 🧪 GCP API Gateway: Cloud Run Identity Token Exchange 实验

## 1. 实验背景 (Background)
- **合规与环境限制**：在企业级 GCP 环境（如 `jason-hsbc` 项目）中，受严格的 Org Policy 限制，Cloud Run 服务绝对禁止暴露到公网（禁止赋予 `allUsers` 权限）。任何对 Cloud Run 的调用都必须经过 Google IAP（Identity-Aware Proxy）或在请求头中携带合法的 GCP Identity Token。
- **业务痛点**：在某些场景下，我们需要将 Cloud Run 中托管的前端 UI 或轻量级 API 暴露给特定的外部客户端。然而，现有的 IAP 策略可能被死板地绑定到了特定的企业域名（如 `maplequad.com`），导致正常用户无法登录；而强迫外部客户端自行实现 GCP Identity Token 换取逻辑，又会带来极大的接入成本和秘钥泄露风险。
- **全链路交付演练**：为验证端到端的完整交付能力，本实验不仅包含底层的网关配置，还将从零构建一个 Web UI 测试项目，并通过自动化 CI/CD 流水线完成前置部署，最终再进行 API Gateway 的代理与鉴权转换。

## 2. 实验目的 (Objective)
本实验被划分为三个渐进的核心阶段：
1. **构建 Web UI 靶标 (UI Development)**：编写一个可视化的 Web UI 项目，打包为容器镜像，用于直观地验证浏览器端的渲染效果和请求链路。
2. **自动化 CI/CD (Pipeline)**：建立持续集成/部署流水线，将 Web UI 项目自动部署到 GCP Cloud Run，并强制开启 IAM 鉴权（`--no-allow-unauthenticated`）。
3. **网关鉴权转换 (Gateway Exchange)**：配置 Google Cloud API Gateway，利用专属 Service Account 自动完成向 GCP 申请 Identity Token 的动作，代理外部“裸请求”安全访问内部 Cloud Run。

## 3. 交付标准 (Acceptance Criteria / DoD)
本实验成功必须满足以下所有条件：

### 阶段一：Web UI 开发
- [ ] **代码就绪**：成功在仓库中建立 Web UI 项目目录，包含完整的 UI 代码及用于容器化的 `Dockerfile`。

### 阶段二：CI/CD 自动化流水线
- [ ] **流水线配置**：成功编写自动化流水线脚本（如 GitHub Actions 或 Cloud Build）。
- [ ] **自动部署**：流水线能够自动将镜像构建并部署至 `europe-west2` 的 Cloud Run，且环境处于高度锁定状态（禁止 `allUsers`）。

### 阶段三：API Gateway 整合与验证
- [ ] **权限隔离**：成功创建专属 Service Account 并赋予 `roles/run.invoker` 角色，绑定至 API Gateway Config。
- [ ] **网关部署**：在 `europe-west2` 成功部署 API Gateway 实例，并与后端 Cloud Run 完成路由映射。
- [ ] **反向验证 (Negative Test)**：直接使用浏览器访问 Cloud Run 的原生 URL 时，系统必须拦截并返回 `403 Forbidden`。
- [ ] **正向验证 (Positive Test)**：使用浏览器访问 API Gateway 暴露的 URL 时，在不提供任何 IAM 凭证的情况下，能成功渲染出 Web UI 界面（HTTP 200）。
- [ ] **资产沉淀**：所有架构代码、部署脚本与网关规范（`openapi.yaml`）完整提交至本仓库。
