#!/usr/bin/env bash
set -euo pipefail

FLUTTER_ROOT="${HOME}/flutter"
FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
API_BASE_URL="${START_ON_API_BASE_URL:?START_ON_API_BASE_URL must be set}"

if [ ! -d "${FLUTTER_ROOT}" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
fi

export PATH="${FLUTTER_ROOT}/bin:${PATH}"

flutter config --enable-web
flutter pub get
flutter build web --release --dart-define=START_ON_API_BASE_URL="${API_BASE_URL}"
