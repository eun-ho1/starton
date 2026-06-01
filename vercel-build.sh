#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="${SCRIPT_DIR}/frontend"
ROOT_BUILD_DIR="${SCRIPT_DIR}/build/web"

bash "${FRONTEND_DIR}/vercel-build.sh"

rm -rf "${ROOT_BUILD_DIR}"
mkdir -p "${ROOT_BUILD_DIR}"
cp -R "${FRONTEND_DIR}/build/web/." "${ROOT_BUILD_DIR}/"
