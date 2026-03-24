#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$APP_DIR/ios"

if command -v flutter >/dev/null 2>&1; then
  echo "Using existing flutter: $(command -v flutter)"
else
  FLUTTER_ROOT="$HOME/flutter"
  echo "Installing Flutter into: $FLUTTER_ROOT"
  rm -rf "$FLUTTER_ROOT"
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
  export PATH="$FLUTTER_ROOT/bin:$PATH"
fi

flutter --version

cd "$APP_DIR"
flutter pub get

cd "$IOS_DIR"
pod install --repo-update
