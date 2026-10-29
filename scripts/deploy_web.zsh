#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

COMMIT_MESSAGE="${1:-Update web release}"

echo "Building Flutter web release..."
WEB_BUILD_ARGS=(--release)
if [[ -n "${DOCX_PREVIEW_ENDPOINT:-}" ]]; then
  WEB_BUILD_ARGS+=("--dart-define=DOCX_PREVIEW_ENDPOINT=$DOCX_PREVIEW_ENDPOINT")
fi
flutter build web "${WEB_BUILD_ARGS[@]}"

# Flutter does not copy standalone install-page files as part of its web build.
bash ./scripts/prepare_web_release.sh

git add .

if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

git commit -m "$COMMIT_MESSAGE"
git push

echo "Web release pushed successfully."
