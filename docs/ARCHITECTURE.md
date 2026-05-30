# Architecture: API Gateway to Internal Cloud Run

## Objective
Route external traffic through GCP API Gateway to a securely locked Cloud Run service (`--no-allow-unauthenticated`) without requiring the client to provide a GCP Identity Token.

## Mechanism
API Gateway uses a dedicated Service Account (with `run.invoker` role) to automatically perform an Identity Token exchange and append it to the backend request.

## Resources
- **API Gateway**: `secure-api` (europe-west2)
- **Cloud Run**: `secure-backend` (europe-west2)
- **Service Account**: `gateway-invoker`
