# 🧪 GCP API Gateway: Cloud Run Identity Token Exchange 实验

## 1. 实验背景 (Background)
- **合规与环境限制**：在企业级 GCP 环境（如 `jason-hsbc` 项目）中，受严格的 Org Policy 限制，Cloud Run 服务绝对禁止暴露到公网（禁止赋予 `allUsers` 权限）。任何对 Cloud Run 的调用都必须经过 Google IAP（Identity-Aware Proxy）或在请求头中携带合法的 GCP Identity Token。
- **业务痛点**：在某些场景下，我们需要将 Cloud Run 中托管的前端 UI 或轻量级 API 暴露给特定的外部客户端。然而，现有的 IAP 策略可能被死板地绑定到了特定的企业域名（如 `maplequad.com`），导致正常用户无法登录；而强迫外部客户端自行实现 GCP Identity Token 换取逻辑，又会带来极大的接入成本和秘钥泄露风险。
- **解法构思**：引入 **Google Cloud API Gateway** 作为公网前端网关。客户端向网关发起免鉴权（或简单 API Key）的请求，网关利用自身绑定的专属 Service Account (SA) 在底层自动完成向 GCP 申请 Identity Token 的动作，并附着在对 Cloud Run 的代理请求上。

## 2. 实验目的 (Objective)
- **验证网关鉴权转换能力**：验证 API Gateway 能否在完全不编写任何自定义中间件代码（无需自己开发 BFF 代理服务）的前提下，纯靠 `openapi.yaml` 声明式配置，实现后端的 OIDC (OpenID Connect) Token 代理转换。
- **实现安全透传**：实现外部客户端发出的“无 Token 裸请求”，通过 API Gateway 拦截并“换装”后，能成功叩开处于高度锁定状态（`--no-allow-unauthenticated`）的 Cloud Run 大门。
- **合规区域部署实践**：验证全套架构在受限的 `europe-west2` (伦敦) 区域的自动化部署流程。

## 3. 交付标准 (Acceptance Criteria / DoD)
本实验成功必须满足以下所有条件：

- [ ] **资源就绪**：成功在 `europe-west2` 部署 1 个私有状态的 Cloud Run 靶标服务（返回测试页面或 JSON），以及配套的 API Gateway 实例。
- [ ] **权限隔离**：成功创建专用 Service Account 并仅赋予 `roles/run.invoker` 角色，准确绑定至 API Gateway Config。
- [ ] **反向验证 (Negative Test)**：直接使用浏览器或 Curl 访问 Cloud Run 的原生 URL 时，系统必须拦截并返回 `403 Forbidden`。
- [ ] **正向验证 (Positive Test)**：使用浏览器或 Curl 访问 API Gateway 暴露的 URL 时，在不提供任何 IAM 凭证的情况下，能成功展示 Cloud Run 后端的响应内容（HTTP 200）。
- [ ] **资产沉淀**：所有部署脚本（Bash）与网关配置规范（`openapi.yaml`）需做到可复用，并完整提交至本 GitHub 仓库。
