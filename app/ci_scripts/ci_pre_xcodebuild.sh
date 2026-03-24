#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$APP_DIR"
flutter --version
