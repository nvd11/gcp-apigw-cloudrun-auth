# 突破 GCP 企业合规限制：基于 API Gateway 的 Cloud Run 鉴权转换方案

**作者**：Jason Poon
**标签**：`GCP`, `Cloud Run`, `API Gateway`, `Serverless`, `IAM`, `架构设计`

---

## 1. 背景：企业级安全策略下的访问隔离

在 Google Cloud Platform (GCP) 中，Cloud Run 是 Serverless 容器托管的核心组件。在标准场景下，开发者通常通过赋予 `allUsers` 权限来对外暴露服务。

然而，在企业级生产环境（如跨国金融机构的 GCP 基础设施中），面临严格的合规审计与组织策略（Org Policy）约束，Cloud Run 服务通常被绝对禁止暴露于公网，必须强制配置 `--no-allow-unauthenticated` 参数。

由此产生架构痛点：**托管在内部 Cloud Run 上的服务（如前端 SPA 或外部调用的轻量级 API），应如何在受限环境下向合法外部客户端提供访问入口？**

前期，本团队曾通过 GCE + Envoy 结合 `gcp_authn` C++ 插件的方式，构建代理节点手动签发 Token 来解决此问题（详见：[《硬核破局！Envoy 编译 gcp_authn 插件：以网关身份动态换取 GCP Identity Token 代理访问受限 Cloud Run》](https://blog.csdn.net/nvd11/article/details/153066928)）。然而，自建 Envoy 代理带来了较高的计算资源与运维负担。本文将介绍一种更为云原生、免运维的 Serverless 替代方案，即利用 Google API Gateway 实现原生的鉴权转换。

## 2. 架构瓶颈：前后端分离场景下的鉴权困境

针对受限的 Cloud Run，GCP 官方提供两种标准访问模式：
1. **Google Identity-Aware Proxy (IAP)**：通过 IAP 实现应用级访问控制。
   * **局限性**：IAP 通常与企业 Google Workspace 域（如 `@company.com`）深度绑定。对于域外终端用户或 B2B API 调用，IAP 鉴权链路存在阻碍，缺乏灵活性。
2. **Identity Token 鉴权**：在 HTTP Header 中提供合法的 `Authorization: Bearer <GCP_Identity_Token>`。
   * **局限性**：在前后端分离架构下，前端 JS 运行于用户侧浏览器。客户端无法、也不应持有 GCP Service Account 密钥文件以自行签发 Token。

由此形成架构冲突：客户端无法持有凭证，而底层服务拒绝无凭证访问。

## 3. 解决方案：API Gateway Token Exchange 架构

为解决无状态客户端访问内部服务的问题，我们引入 **Google Cloud API Gateway** 作为前置反向代理层。

### 核心架构设计

![Architecture Diagram](https://ghproxy.net/https://raw.githubusercontent.com/nvd11/gcp-apigw-cloudrun-auth/main/images/architecture.png)

通过引入 API Gateway，将 Token 签发逻辑由客户端后置至网关层：
1. 将 API Gateway 暴露至公网，作为流量的统一入口。
2. 为网关实例绑定特定的 Service Account (SA)。
3. 客户端发起无状态的常规 HTTP 请求。
4. **鉴权转换 (Token Exchange)**：网关拦截请求，使用绑定的 SA 动态向 GCP IAM 换取临时 Identity Token，并将其注入 HTTP `Authorization` Header，随后转发至后端 Cloud Run。
5. Cloud Run 校验 Token 有效性，放行请求并返回业务响应。

---

## 4. 工程实践：端到端配置指南

以下为实现鉴权转换的 Terraform / gcloud 操作路径。

### 步骤一：部署受限的 Cloud Run 服务
部署应用时，显式拒绝所有未经认证的请求：
```bash
gcloud run deploy cr-webui \
  --image europe-west2-docker.pkg.dev/my-project/my-repo/webui:latest \
  --service-account=cr-webui-runtime-sa@my-project.iam.gserviceaccount.com \
  --no-allow-unauthenticated \
  --region europe-west2
```
此时通过公网直接访问原生 URL 将返回 HTTP 403 Forbidden。

### 步骤二：配置网关专属 Service Account
创建网关运行标识，并授予其调用目标 Cloud Run 的 IAM 权限：

```bash
# 创建网关 Service Account
gcloud iam service-accounts create gateway-invoker --project=my-project

# 授予 run.invoker 角色
gcloud run services add-iam-policy-binding cr-webui \
  --member="serviceAccount:gateway-invoker@my-project.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --region=europe-west2 \
  --project=my-project
```

### 步骤三：定义 OpenAPI 路由规范
API Gateway 的路由分发与后端鉴权逻辑由 OpenAPI 2.0 (Swagger) 规范驱动。

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
      
      # x-google-backend 为 GCP API Gateway 的私有扩展
      x-google-backend:
        address: "https://cr-webui-7hq3m4pdya-nw.a.run.app"
        path_translation: APPEND_PATH_TO_ADDRESS
        
      responses:
        '200':
          description: "OK"

  /**:
    # 通配符路由：处理静态资源与子路径请求
    get:
      operationId: "proxyGet"
      x-google-backend:
        address: "https://cr-webui-7hq3m4pdya-nw.a.run.app"
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        '200':
          description: "OK"
```
配置中的 `x-google-backend` 扩展是核心所在，它触发网关底层的 Token 获取机制并将请求重定向至目标 `address`。

![GCP API Gateway Config](https://ghproxy.net/https://raw.githubusercontent.com/nvd11/gcp-apigw-cloudrun-auth/main/images/gcp_gateway_config.png)
*图：GCP 控制台中解析后的 OpenAPI 规范*

### 步骤四：部署 API Gateway 实例
应用配置并拉起网关实例：

```bash
# 1. 创建 API
gcloud api-gateway apis create cr-webui-api --project=my-project

# 2. 创建 API Config，绑定 OpenAPI 规范与目标 SA
gcloud api-gateway api-configs create cr-webui-config-v1 \
    --api=cr-webui-api \
    --openapi-spec=openapi.yaml \
    --project=my-project \
    --backend-auth-service-account=gateway-invoker@my-project.iam.gserviceaccount.com

# 3. 部署 Gateway
gcloud api-gateway gateways create cr-webui-gw \
    --api=cr-webui-api \
    --api-config=cr-webui-config-v1 \
    --location=europe-west2 \
    --project=my-project
```

---

## 5. 验证与抓包分析

部署完成后，网关将获得一个 `.gateway.dev` 后缀的公网入口。

![GCP API Gateway List](https://ghproxy.net/https://raw.githubusercontent.com/nvd11/gcp-apigw-cloudrun-auth/main/images/gcp_gateway_list.png)
*图：API Gateway 分配的默认域名*

通过该网关 URL 访问服务，请求成功响应 HTTP 200。在后端的 HTTP Headers 审查中，可以看到网关自动注入的 JWT：
```text
Authorization: Bearer eyJhbGciOiJSUzI...
```
解析该 JWT，其 `email` 字段的值即为 `gateway-invoker@my-project.iam.gserviceaccount.com`。

这验证了无状态外网请求在途经 API Gateway 时，已成功完成身份转换，底层穿透了 Cloud Run 的 IAM 安全策略限制。

## 6. 架构探讨与最佳实践

### Q1: 如何为 API Gateway 配置自定义域名？
API Gateway 实例默认不支持直接绑定自定义 DNS 记录。如需配置自定义域名（如 `api.company.com`），需在网关前沿部署 **Google Cloud 外部应用负载均衡器 (External Application Load Balancer)**，通过创建 Serverless NEG (网络端点组) 将网关作为后端接入，并由负载均衡器完成 SSL 卸载与域名路由。

### Q2: 内部微服务 (Cloud Run to Cloud Run) 是否应通过 Gateway 调用？
**不建议。** 如果调用方同为 GCP 内部的 Cloud Run 服务，其已具备运行时 Service Account。最佳实践是让调用方在代码级直接请求 GCP Metadata 服务，获取目标 Audience 的 Identity Token 后发起点对点 (P2P) 请求。在此场景下引入 API Gateway 会导致不必要的网络跳数、延迟及额外成本。
进一步的隔离要求可通过 VPC Connector 配置 Direct VPC Egress 实现纯内网流量控制。

### 总结
在 GCP Serverless 生态中，API Gateway 配合 `x-google-backend` 扩展有效调和了企业安全合规与业务接入灵活性之间的矛盾。该方案大幅降低了前置鉴权与反向代理的运维复杂度，是企业级云原生架构中的标准实践。
