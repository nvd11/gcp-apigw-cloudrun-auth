# 🔐 Setup Workload Identity Federation (WIF) for GitHub Actions

## Why WIF? (The "Keyless" Architecture)
Traditionally, deploying to GCP from GitHub Actions required generating a long-lived Service Account JSON key and storing it in GitHub Secrets. This poses a significant security risk if the key is leaked.

**Workload Identity Federation (WIF)** solves this by using OIDC (OpenID Connect). Instead of giving GitHub a permanent key, GCP establishes a trust relationship with GitHub. When a GitHub Action runs, it presents a short-lived OIDC token. GCP verifies the token, checks if the repository is authorized, and then temporarily lets GitHub "impersonate" a GCP Service Account. 

**Zero JSON keys required. Maximum security.**

---

## 🛠️ Step-by-Step Configuration Guide

Run the following script in your terminal (ensure you are authenticated to GCP and have Org/Project Admin rights for `jason-hsbc`).

### Step 1: Define Environment Variables
Modify the `REPO` variable if your GitHub repository name changes.
```bash
export PROJECT_ID="jason-hsbc"
export REPO="nvd11/gcp-apigw-cloudrun-auth"
export SERVICE_ACCOUNT="github-actions-sa"
export POOL_NAME="github-pool"
export PROVIDER_NAME="github-provider"
```

### Step 2: Create the Deployment Service Account
This is the identity that GitHub Actions will assume when deploying the Cloud Run service.
```bash
gcloud iam service-accounts create $SERVICE_ACCOUNT \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions Deployment SA"
```

### Step 3: Grant Deployment Permissions to the SA
GitHub Actions needs permissions to push images to Artifact Registry, deploy to Cloud Run, and manage API Gateways.
```bash
for role in "roles/run.admin" "roles/artifactregistry.writer" "roles/iam.serviceAccountUser" "roles/apigateway.admin"; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
      --role="$role"
done
```

### Step 4: Create the WIF Identity Pool
A pool is a container for your external identity providers.
```bash
gcloud iam workload-identity-pools create $POOL_NAME \
    --project="${PROJECT_ID}" --location="global" \
    --display-name="GitHub Actions Pool"
```

### Step 5: Add GitHub as an OIDC Provider
This establishes trust with GitHub's OIDC issuer. We map the GitHub claims (like `repository`) to Google attributes.
```bash
gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
    --project="${PROJECT_ID}" --location="global" --workload-identity-pool=$POOL_NAME \
    --display-name="GitHub Actions Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
    --issuer-uri="https://token.actions.githubusercontent.com"
```

### Step 6: Bind the GitHub Repo to the Service Account
**CRITICAL SECURITY STEP:** This ensures that *only* your specific GitHub repository (`nvd11/gcp-apigw-cloudrun-auth`) can impersonate this Service Account.
```bash
export WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe $POOL_NAME \
  --project="${PROJECT_ID}" --location="global" --format="value(name)")

gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${REPO}"
```

---

## 🎯 Final Output (Required for GitHub Actions)
To configure the GitHub Actions `.yml` file, you need the exact resource name of the WIF Provider you just created. Run this command to retrieve it:

```bash
echo "projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"
```

**Save the output string.** It will look something like this:
`projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider`
