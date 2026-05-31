#!/bin/bash
set -e

PROJECT_ID="jason-hsbc"
REGION="europe-west2"
API_NAME="cr-webui-api"
CONFIG_ID="cr-webui-config-v1"
GATEWAY_NAME="cr-webui-gw"
INVOKER_SA="gateway-invoker@${PROJECT_ID}.iam.gserviceaccount.com"

echo "========================================"
echo "🚀 Deploying API Gateway..."
echo "========================================"

# 1. Create API
if ! gcloud api-gateway apis describe $API_NAME --project=$PROJECT_ID >/dev/null 2>&1; then
    echo "[Exec] Creating API '${API_NAME}'..."
    gcloud api-gateway apis create $API_NAME --project=$PROJECT_ID
else
    echo "[Skip] API '${API_NAME}' already exists."
fi

# 2. Create API Config (Bind the OpenAPI spec and the Invoker SA)
echo "[Exec] Creating API Config '${CONFIG_ID}' (This may take 1-2 minutes)..."
gcloud api-gateway api-configs create $CONFIG_ID \
    --api=$API_NAME \
    --openapi-spec=gateway/openapi.yaml \
    --project=$PROJECT_ID \
    --backend-auth-service-account=$INVOKER_SA

# 3. Create Gateway
echo "[Exec] Deploying Gateway '${GATEWAY_NAME}' (This takes a few minutes)..."
gcloud api-gateway gateways create $GATEWAY_NAME \
    --api=$API_NAME \
    --api-config=$CONFIG_ID \
    --location=$REGION \
    --project=$PROJECT_ID

echo "========================================"
echo "✅ API Gateway Deployment Complete!"
echo "========================================"

GATEWAY_URL=$(gcloud api-gateway gateways describe $GATEWAY_NAME \
  --location=$REGION \
  --project=$PROJECT_ID \
  --format="value(defaultHostname)")

echo "🎉 Your Web UI is now accessible via API Gateway at:"
echo "https://${GATEWAY_URL}"
