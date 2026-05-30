#!/bin/bash
set -e

PROJECT_ID="jason-hsbc"
REPO="nvd11/gcp-apigw-cloudrun-auth"
SERVICE_ACCOUNT="github-actions-sa"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"

echo "========================================"
echo "🚀 Starting WIF & IAM Initialization..."
echo "========================================"

# 0. Enable APIs
echo "[Exec] Enabling required GCP APIs..."
gcloud services enable iamcredentials.googleapis.com sts.googleapis.com run.googleapis.com artifactregistry.googleapis.com apigateway.googleapis.com servicemanagement.googleapis.com servicecontrol.googleapis.com

# 1. Create Service Account (Idempotent)
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "[Skip] Service Account '${SERVICE_ACCOUNT}' already exists."
else
    echo "[Exec] Creating Service Account '${SERVICE_ACCOUNT}'..."
    gcloud iam service-accounts create $SERVICE_ACCOUNT \
        --project="${PROJECT_ID}" \
        --display-name="GitHub Actions Deployment SA"
fi

# 2. Grant roles
echo "[Exec] Ensuring IAM roles for '${SERVICE_ACCOUNT}'..."
for role in "roles/run.admin" "roles/artifactregistry.writer" "roles/iam.serviceAccountUser" "roles/apigateway.admin"; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
      --role="$role" >/dev/null
done

# 3. Create WIF Pool
if gcloud iam workload-identity-pools describe $POOL_NAME --project="${PROJECT_ID}" --location="global" >/dev/null 2>&1; then
    echo "[Skip] WIF Pool '${POOL_NAME}' already exists."
else
    echo "[Exec] Creating WIF Pool '${POOL_NAME}'..."
    gcloud iam workload-identity-pools create $POOL_NAME \
        --project="${PROJECT_ID}" --location="global" \
        --display-name="GitHub Actions Pool"
fi

# 4. Create WIF Provider
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

# 5. Bind GitHub Repo
echo "[Exec] Ensuring Repo impersonation binding..."
WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe $POOL_NAME \
  --project="${PROJECT_ID}" --location="global" --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${REPO}" >/dev/null

echo "========================================"
echo "✅ Initialization Complete!"
echo "WIF Provider ID for GitHub Actions:"
echo "projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"
echo "========================================"
