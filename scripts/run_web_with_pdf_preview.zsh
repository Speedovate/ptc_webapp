#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PREVIEW_OFFICE_BIN="${SOFFICE_BIN:-}"
if [[ -z "$PREVIEW_OFFICE_BIN" ]]; then
  if command -v soffice >/dev/null 2>&1; then
    PREVIEW_OFFICE_BIN="$(command -v soffice)"
  elif [[ -x /Applications/LibreOffice.app/Contents/MacOS/soffice ]]; then
    PREVIEW_OFFICE_BIN=/Applications/LibreOffice.app/Contents/MacOS/soffice
  else
    echo 'LibreOffice is required. Install LibreOffice or set SOFFICE_BIN to its soffice executable.' >&2
    exit 1
  fi
fi
SOFFICE_BIN="$PREVIEW_OFFICE_BIN" ALLOW_LOCALHOST=true PORT=8784 \
  node services/docx-preview/server.mjs &
PREVIEW_SERVER_PID=$!
trap 'kill "$PREVIEW_SERVER_PID" 2>/dev/null || true' EXIT INT TERM
sleep 1
if ! kill -0 "$PREVIEW_SERVER_PID" 2>/dev/null; then
  echo 'The PDF conversion service did not start.' >&2
  exit 1
fi
flutter run -d chrome --dart-define=DOCX_PREVIEW_ENDPOINT=http://127.0.0.1:8784/convert "$@"
