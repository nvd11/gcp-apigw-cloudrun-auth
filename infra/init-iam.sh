#!/bin/bash
set -e

PROJECT_ID="jason-hsbc"

# 我们现在有三个 SA
# 1. GitHub Actions 用的 SA (用于流水线部署，采用 JSON Key 鉴权)
GITHUB_SA="github-actions-sa"
# 2. Cloud Run Web UI 运行时用的 SA
CLOUDRUN_RUNTIME_SA="cr-webui-runtime-sa"
# 3. API Gateway 用的 SA (用于去拿 Token，这个后面配 Gateway 时用，先列出来)
GATEWAY_INVOKER_SA="gateway-invoker"

echo "========================================"
echo "🚀 Starting IAM Initialization (JSON Key Route)..."
echo "========================================"

# 0. Enable APIs
echo "[Exec] Enabling required GCP APIs..."
gcloud services enable run.googleapis.com artifactregistry.googleapis.com apigateway.googleapis.com servicemanagement.googleapis.com servicecontrol.googleapis.com iamcredentials.googleapis.com

# 1. Create Service Accounts (Idempotent)
for sa_name in "$GITHUB_SA" "$CLOUDRUN_RUNTIME_SA" "$GATEWAY_INVOKER_SA"; do
    if gcloud iam service-accounts describe "${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        echo "[Skip] Service Account '${sa_name}' already exists."
    else
        echo "[Exec] Creating Service Account '${sa_name}'..."
        gcloud iam service-accounts create $sa_name --project="${PROJECT_ID}"
    fi
done

# 2. Grant roles to GitHub Actions SA (Project Level)
echo "[Exec] Ensuring Project-level IAM roles for '${GITHUB_SA}'..."
for role in "roles/run.admin" "roles/artifactregistry.writer" "roles/apigateway.admin"; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:${GITHUB_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
      --role="$role" --condition=None >/dev/null
done

# 3. Grant SA-level role: Allow GitHub SA to act as Cloud Run Runtime SA
echo "[Exec] Granting SA-level impersonation (Service Account User) to '${GITHUB_SA}'..."
gcloud iam service-accounts add-iam-policy-binding \
    "${CLOUDRUN_RUNTIME_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="${PROJECT_ID}" \
    --member="serviceAccount:${GITHUB_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser" >/dev/null

echo "========================================"
echo "✅ IAM Initialization Complete!"
echo ""
echo "⚠️  Next Step: Please generate a JSON key for the GitHub Actions SA:"
echo "gcloud iam service-accounts keys create credentials.json \\"
echo "    --iam-account=${GITHUB_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
echo ""
echo "Then copy the contents of credentials.json into a GitHub Secret named GCP_CREDENTIALS."
echo "========================================"
