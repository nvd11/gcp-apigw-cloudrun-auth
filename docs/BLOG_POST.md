# 破局 GCP 企业合规限制：巧用 API Gateway 实现 Cloud Run 鉴权转换 (Token Exchange)

**作者**：Jason Poon & Moon  
**标签**：`GCP`, `Cloud Run`, `API Gateway`, `Serverless`, `IAM`, `架构设计`

---

## 1. 序言：当云原生遇到企业级“紧箍咒”

在 Google Cloud Platform (GCP) 上，Cloud Run 无疑是部署 Serverless 容器的最优解。它支持自动扩缩容、按需计费，且开发者只需关注代码逻辑。在个人项目中，我们通常直接将 Cloud Run 的权限设置为 `allUsers`（允许未经过滤的公网访问），轻松愉快地对外提供服务。

然而，在真实的企业级环境中（如大型跨国银行的 GCP 项目），情况则截然不同。受限于严格的合规审计和 GCP Org Policy（组织策略），**Cloud Run 服务绝对禁止暴露在公网**。所有的底层服务强制加上了 `--no-allow-unauthenticated` 枷锁。

这就引出了一个非常现实的技术痛点：**如果我托管在 Cloud Run 上的服务（比如一个前端单页应用 SPA，或者轻量级 API），确实需要给特定的外部用户访问，该怎么办？**

## 2. 痛点剖析：前后端分离架构下的死局

面对锁死的 Cloud Run，GCP 官方提供了两种正统的敲门砖：
1. **Google Identity-Aware Proxy (IAP)**：在服务前面套一层 IAP，用户访问时重定向到 Google 登录页。
   * **痛点**：IAP 通常与企业的 Google Workspace 域（如 `@maplequad.com` 或企业内网环境）深度绑定。对于不在企业域内的正常外部用户，IAP 就像一堵无法逾越的高墙，极度不灵活。
2. **Identity Token 鉴权**：在 HTTP 请求头中携带合法的 `Authorization: Bearer <GCP_Identity_Token>`。
   * **痛点**：对于后端服务互调，这很容易做到。但如果客户端是**用户的浏览器**（比如 React/Vue 渲染的页面），JS 代码下载到用户本地执行，它绝对不可能、也不应该持有一份 GCP 的 Service Account JSON 密钥去自己签名换取 Token！这会导致极大的秘钥泄露风险。

**这就形成了一个死局**：前端 JS 拿不到 Token，没有 Token 就调不通 Cloud Run，服务彻底陷入瘫痪。

## 3. 破局之道：API Gateway 与 Token Exchange 架构

为了在不破坏底层“禁止公网直连”安全红线的前提下，让无状态的浏览器安全访问内部服务，我们需要引入一位“代理人” —— **Google Cloud API Gateway**。

### 核心架构思路
与其让客户端自己去挠头搞 Token，不如让网关挡在前面代劳。
1. 我们将 API Gateway 暴露在公网，作为唯一的入口。
2. 给网关绑定一个专用的 Service Account（服务账号）。
3. 客户端发起“裸请求”（不带任何凭证）到网关。
4. **【核心魔术】**：网关在将请求转发给后端的 Cloud Run 之前，自动向 GCP 鉴权中心发起请求，用自己的 SA 换取一把临时的 **Identity Token**，并神不知鬼不觉地塞进 HTTP 的 `Authorization` 请求头里。
5. Cloud Run 收到带有合法 Token 的请求，放行并返回数据。

这个过程被称为 **鉴权转换 (Authentication Exchange)**。

---

## 4. 实战演练：从 0 到 1 跑通全链路

下面我们将一步步拆解，如何通过代码和配置实现这一套华丽的鉴权转换。

### 步骤一：铸造铜墙铁壁 —— 部署锁死的 Cloud Run
假设我们已经写好了一个 FastAPI 的 Web 服务。在将其部署到 Cloud Run 时，我们必须坚定地加上安全锁：
```bash
gcloud run deploy cr-webui \
  --image europe-west2-docker.pkg.dev/my-project/my-repo/webui:latest \
  --service-account=cr-webui-runtime-sa@my-project.iam.gserviceaccount.com \
  --no-allow-unauthenticated \  # 核心：禁止公网无鉴权访问
  --region europe-west2
```
此时，如果你用浏览器直接访问 Cloud Run 的原生 URL，迎接你的将是一个冷冰冰的 `403 Forbidden`。

### 步骤二：颁发“特许通行证” —— 配置 IAM Service Account
为了让网关有资格去换取敲开 Cloud Run 大门的 Token，我们需要创建一个网关专属的 SA，并赋予它 `roles/run.invoker`（Cloud Run 调用者）权限。

```bash
# 1. 创建网关专属 SA
gcloud iam service-accounts create gateway-invoker --project=my-project

# 2. 赋予该 SA 调用目标 Cloud Run 服务的权限
gcloud run services add-iam-policy-binding cr-webui \
  --member="serviceAccount:gateway-invoker@my-project.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --region=europe-west2 \
  --project=my-project
```

### 步骤三：注入灵魂 —— 编写 OpenAPI (Swagger) 规范
API Gateway 并没有花里胡哨的图形配置界面，它的路由规则和鉴权逻辑完全由一份 `openapi.yaml` 文件驱动。注意，**GCP 目前只支持 Swagger 2.0 标准**。

这是最关键的一步，也是全案的灵魂所在：

```yaml
swagger: '2.0'
info:
  title: CR-WebUI API Gateway
  description: Gateway to proxy requests with Identity Token exchange
  version: 1.0.0
schemes:
  - https

paths:
  /:
    get:
      summary: "Root Web UI"
      operationId: "getRoot"
      
      # [核心扩展] x-google-backend 是 GCP 的私有插件
      x-google-backend:
        # address: 指向底层 Cloud Run 的原生 URL
        address: "https://cr-webui-7hq3m4pdya-nw.a.run.app"
        # APPEND_PATH_TO_ADDRESS: 自动将客户端路径拼接到后端地址上
        path_translation: APPEND_PATH_TO_ADDRESS
        
      responses:
        '200':
          description: "OK"

  /**:
    # 兜底路由：处理静态资源 (JS/CSS) 或后续的 API 请求
    get:
      operationId: "proxyGet"
      x-google-backend:
        address: "https://cr-webui-7hq3m4pdya-nw.a.run.app"
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        '200':
          description: "OK"
```
当网关解析到 `x-google-backend` 时，它的内置引擎就会知道：“哦，我需要去代劳换取 Token 了”。

### 步骤四：唤醒网关 —— 自动化部署
拿着写好的 YAML 文件和刚才建好的 SA，我们就可以正式唤醒网关了：

```bash
# 1. 创建 API 壳子
gcloud api-gateway apis create cr-webui-api --project=my-project

# 2. 创建 API Config，将 YAML 和 SA 绑定在一起
gcloud api-gateway api-configs create cr-webui-config-v1 \
    --api=cr-webui-api \
    --openapi-spec=openapi.yaml \
    --project=my-project \
    --backend-auth-service-account=gateway-invoker@my-project.iam.gserviceaccount.com

# 3. 部署 Gateway 实例
gcloud api-gateway gateways create cr-webui-gw \
    --api=cr-webui-api \
    --api-config=cr-webui-config-v1 \
    --location=europe-west2 \
    --project=my-project
```

---

## 5. 效果验证：见证奇迹的时刻

部署完成后，GCP 会分配一个 `*.gateway.dev` 的公网域名。
当我们在浏览器中打开这个网关 URL 时，奇迹发生了：
页面不再是 403，而是完美地渲染出了我们的 Web UI！

如果我们在后端代码中打印接收到的 HTTP Headers，会赫然看到一个巨大的 JWT：
```text
Authorization: Bearer eyJhbGciOiJSUzI... (省略数百字符)
```
将这段 JWT 丢进 jwt.io 解析，你会发现它的 `email` 字段正是我们的 `gateway-invoker@my-project.iam.gserviceaccount.com`！

这证明：**外部的无状态请求，在经过 API Gateway 的瞬间，被完美地披上了一层合法身份的外衣，成功越过了企业级的安全高墙。**

## 6. 进阶探讨与总结

### Q1: API Gateway 的自定义域名怎么做？
API Gateway 本身不支持直接绑定自定义域名（如 `api.mycompany.com`）。如果你有强烈的品牌需求，必须在 Gateway 前面再套一层 **Google Cloud 外部应用负载均衡器 (External Load Balancer)**，通过 Serverless NEG 挂载网关，并在 LB 上配置自签名的 SSL 证书和域名路由。

### Q2: 如果调用方是另一个内部 Cloud Run 呢？
**千万不要用 Gateway！**
如果 Cloud Run A 要调 Cloud Run B，因为 A 自身就在 GCP 环境内且自带 Service Account，它可以直接在代码中向 GCP 换取目标为 B 的 Identity Token，然后进行点对点 (P2P) 通信。这种场景下引入网关不仅多余，还会增加网络延迟和费用。
如果是更高级的安全要求，还可以利用 VPC Connector 实现 **Direct VPC Egress**，让微服务之间的流量彻底与公网物理隔离。

### 结语
企业安全合规与开发便利性往往是一对宿敌。但在 GCP 的 Serverless 生态中，通过 API Gateway 与 `x-google-backend` 扩展的精妙配合，我们不仅守住了基础设施的安全底线，还赋予了前端应用极大的自由度。这是一次优雅的“架构破局”，也是每一个云原生架构师必修的内功心法。
