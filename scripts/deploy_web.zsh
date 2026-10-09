#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

COMMIT_MESSAGE="${1:-Update web release}"

echo "Building Flutter web release..."
flutter build web --release

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
