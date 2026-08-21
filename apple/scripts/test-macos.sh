#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APPLE_DIR="${SCRIPT_DIR:h}"
DERIVED_DIR="$APPLE_DIR/.derived-data.noindex"
APP_BUNDLE="$DERIVED_DIR/Build/Products/Debug/Lion Pass.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

case "$APP_BUNDLE" in
  "$APPLE_DIR/.derived-data.noindex/Build/Products/"*) ;;
  *)
    print -u2 "Caminho de limpeza inseguro: $APP_BUNDLE"
    exit 1
    ;;
esac

mkdir -p "$DERIVED_DIR"
touch "$DERIVED_DIR/.metadata_never_index"
xattr -cr "$DERIVED_DIR"

remove_test_app() {
  if [[ -d "$APP_BUNDLE" ]]; then
    "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
    rm -rf "$APP_BUNDLE"
  fi
}

trap remove_test_app EXIT INT TERM

xcodebuild test \
  -project "$APPLE_DIR/LionPass.xcodeproj" \
  -scheme LionPassMac \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DIR" \
  "$@"
