#!/usr/bin/env bash
set -euo pipefail

# Flutter copies standard web assets but not extra standalone HTML pages.
mkdir -p build/web/script
cp web/download.html build/web/download.html
cp web/script/installpwa.js build/web/script/installpwa.js
