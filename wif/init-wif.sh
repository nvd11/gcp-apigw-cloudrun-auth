#!/bin/bash
set -e

PROJECT_ID="jason-hsbc"
REPO="nvd11/gcp-apigw-cloudrun-auth"

# 我们现在有三个 SA
# 1. GitHub Actions 用的 SA (用于流水线部署)
GITHUB_SA="github-actions-sa"
# 2. Cloud Run Web UI 运行时用的 SA
CLOUDRUN_RUNTIME_SA="cr-webui-runtime-sa"
# 3. API Gateway 用的 SA (用于去拿 Token，这个后面配 Gateway 时用，先列出来)
GATEWAY_INVOKER_SA="gateway-invoker"

POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"

echo "========================================"
echo "🚀 Starting WIF & IAM Initialization..."
echo "========================================"

# 0. Enable APIs
echo "[Exec] Enabling required GCP APIs..."
gcloud services enable iamcredentials.googleapis.com sts.googleapis.com run.googleapis.com artifactregistry.googleapis.com apigateway.googleapis.com servicemanagement.googleapis.com servicecontrol.googleapis.com

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
# 注意：我们去掉了 Project 级别的 roles/iam.serviceAccountUser
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

# 4. Create WIF Pool
if gcloud iam workload-identity-pools describe $POOL_NAME --project="${PROJECT_ID}" --location="global" >/dev/null 2>&1; then
    echo "[Skip] WIF Pool '${POOL_NAME}' already exists."
else
    echo "[Exec] Creating WIF Pool '${POOL_NAME}'..."
    gcloud iam workload-identity-pools create $POOL_NAME \
        --project="${PROJECT_ID}" --location="global" \
        --display-name="GitHub Actions Pool"
fi

# 5. Create WIF Provider
if gcloud iam workload-identity-pools providers describe $PROVIDER_NAME --project="${PROJECT_ID}" --location="global" --workload-identity-pool=$POOL_NAME >/dev/null 2>&1; then
    echo "[Skip] WIF Provider '${PROVIDER_NAME}' already exists."
else
    echo "[Exec] Creating WIF Provider '${PROVIDER_NAME}'..."
    gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
        --project="${PROJECT_ID}" --location="global" --workload-identity-pool=$POOL_NAME \
        --display-name="GitHub Actions Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com"
fi

# 6. Bind GitHub Repo
echo "[Exec] Ensuring Repo impersonation binding..."
WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe $POOL_NAME \
  --project="${PROJECT_ID}" --location="global" --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "${GITHUB_SA}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${REPO}" >/dev/null

echo "========================================"
echo "✅ Initialization Complete!"
echo "WIF Provider ID for GitHub Actions:"
echo "projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"
echo "========================================"
