#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "vercel-build.sh failed at line ${LINENO}" >&2' ERR

log() {
  echo "==> $*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

FLUTTER_ROOT="${HOME}/flutter"
FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
API_BASE_URL="${START_ON_API_BASE_URL:-}"

if [ -z "${API_BASE_URL}" ]; then
  echo "START_ON_API_BASE_URL must be set in the Vercel project environment variables." >&2
  exit 1
fi

log "Preparing Flutter SDK (${FLUTTER_VERSION})"

if [ ! -d "${FLUTTER_ROOT}/.git" ]; then
  log "Cloning Flutter into ${FLUTTER_ROOT}"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
else
  log "Refreshing cached Flutter SDK in ${FLUTTER_ROOT}"
  git -C "${FLUTTER_ROOT}" fetch --depth 1 origin "${FLUTTER_VERSION}"
  git -C "${FLUTTER_ROOT}" checkout --force FETCH_HEAD
fi

export PATH="${FLUTTER_ROOT}/bin:${PATH}"

log "Flutter version"
flutter --version

log "Enabling Flutter web support"
flutter config --enable-web

log "Pre-caching web artifacts"
flutter precache --web

log "Installing Dart and Flutter dependencies"
flutter pub get

log "Building Flutter web app"
if ! flutter build web --release --dart-define=START_ON_API_BASE_URL="${API_BASE_URL}"; then
  log "Retrying Flutter web build with verbose output"
  flutter build web --verbose --dart-define=START_ON_API_BASE_URL="${API_BASE_URL}"
fi
