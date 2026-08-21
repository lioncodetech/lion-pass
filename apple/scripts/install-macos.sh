#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APPLE_DIR="${SCRIPT_DIR:h}"
DERIVED_DIR="$APPLE_DIR/.derived-data.noindex"
BUILD_APP="$DERIVED_DIR/Build/Products/Release/Lion Pass.app"
BACKUP_DIR="$DERIVED_DIR/install-backups"
INSTALLED_APP="/Applications/Lion Pass.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

case "$BUILD_APP" in
  "$APPLE_DIR/.derived-data.noindex/Build/Products/"*) ;;
  *)
    print -u2 "Caminho de build inseguro: $BUILD_APP"
    exit 1
    ;;
esac

mkdir -p "$DERIVED_DIR" "$BACKUP_DIR"
touch "$DERIVED_DIR/.metadata_never_index"

remove_build_app() {
  if [[ -d "$BUILD_APP" ]]; then
    "$LSREGISTER" -u "$BUILD_APP" >/dev/null 2>&1 || true
    rm -rf "$BUILD_APP"
  fi
}

verify_secure_release() {
  local app="$1"
  local signature
  local entitlements

  codesign --verify --deep --strict "$app"
  signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
  entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null || true)"

  if [[ "$signature" != *"flags="*"runtime"* ]]; then
    print -u2 "Falha de segurança: Hardened Runtime não está ativo em $app"
    return 1
  fi

  if [[ "$entitlements" == *"com.apple.security.get-task-allow"* ]]; then
    print -u2 "Falha de segurança: get-task-allow está presente em $app"
    return 1
  fi
}

trap remove_build_app EXIT INT TERM
remove_build_app
xattr -cr "$DERIVED_DIR"

xcodebuild build \
  -project "$APPLE_DIR/LionPass.xcodeproj" \
  -scheme LionPassMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  "$@"

verify_secure_release "$BUILD_APP"

if [[ -d "$INSTALLED_APP" ]]; then
  backup_file="$BACKUP_DIR/Lion-Pass-before-hardening-$(date +%Y%m%d-%H%M%S).zip"
  ditto -c -k --keepParent "$INSTALLED_APP" "$backup_file"
  print "Backup recuperável criado em: $backup_file"
  "$LSREGISTER" -u "$INSTALLED_APP" >/dev/null 2>&1 || true
  rm -rf "$INSTALLED_APP"
fi

ditto "$BUILD_APP" "$INSTALLED_APP"
verify_secure_release "$INSTALLED_APP"
"$LSREGISTER" -f "$INSTALLED_APP" >/dev/null

print "Lion Pass instalado com Hardened Runtime e sem get-task-allow."
