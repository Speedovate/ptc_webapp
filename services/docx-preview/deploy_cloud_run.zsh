#!/bin/zsh
set -euo pipefail
SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)"
PREVIEW_PROJECT="${PREVIEW_PROJECT:-ptc-mvp}"
PREVIEW_REGION="${PREVIEW_REGION:-asia-southeast1}"
# This command creates/updates a billed Cloud Run service. Run only when ready
# to deploy. It does not deploy or publish the Flutter frontend.
gcloud run deploy paltranco-docx-preview \
  --source "$SERVICE_DIR" \
  --project "$PREVIEW_PROJECT" --region "$PREVIEW_REGION" \
  --memory 1Gi --cpu 1 --concurrency 1 --max-instances 2 --timeout 60 \
  --allow-unauthenticated \
  --set-env-vars 'CORS_ORIGINS=https://paltranco.vercel.app,ALLOW_LOCALHOST=true'
PREVIEW_SERVICE_URL="$(gcloud run services describe paltranco-docx-preview \
  --project "$PREVIEW_PROJECT" --region "$PREVIEW_REGION" --format='value(status.url)')"
echo "Set DOCX_PREVIEW_ENDPOINT=$PREVIEW_SERVICE_URL/convert when building Flutter."
