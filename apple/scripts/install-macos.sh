#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APPLE_DIR="${SCRIPT_DIR:h}"
DERIVED_DIR="$APPLE_DIR/.derived-data.noindex"
BUILD_APP="$DERIVED_DIR/Build/Products/Release/Lion Pass.app"
BACKUP_DIR="$DERIVED_DIR/install-backups"
INSTALLED_APP="/Applications/Lion Pass.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
MAC_BUNDLE_ID="com.lioncodetech.lionpassword.mac"
USER_LIBRARY="${HOME}/Library"
SANDBOX_VAULT_DIR="$USER_LIBRARY/Containers/$MAC_BUNDLE_ID/Data/Library/Application Support/LionPass"

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

migrate_legacy_vault() {
  local filename
  local source
  local destination
  local migrated=0

  mkdir -p "$SANDBOX_VAULT_DIR"
  chmod 0700 "$SANDBOX_VAULT_DIR"

  for filename in default.lionvault default.previous.lionvault; do
    destination="$SANDBOX_VAULT_DIR/$filename"
    [[ -e "$destination" || -L "$destination" ]] && continue

    for source in \
      "$USER_LIBRARY/Application Support/LionPass/$filename" \
      "$USER_LIBRARY/Application Support/LionPassword/$filename"; do
      [[ -f "$source" && ! -L "$source" ]] || continue
      install -m 0600 "$source" "$destination"
      cmp -s "$source" "$destination" || {
        print -u2 "Falha ao verificar a migração de $filename"
        return 1
      }
      migrated=1
      break
    done
  done

  (( migrated == 0 )) || print "Cofre existente migrado com segurança para o App Sandbox."
}

verify_secure_release() {
  local app="$1"
  local signature
  local entitlements
  local sandbox_enabled
  local user_files_enabled

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

  sandbox_enabled="$(print -r -- "$entitlements" | plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - - 2>/dev/null || true)"
  user_files_enabled="$(print -r -- "$entitlements" | plutil -extract 'com\.apple\.security\.files\.user-selected\.read-write' raw -o - - 2>/dev/null || true)"
  if [[ "$sandbox_enabled" != "true" ]]; then
    print -u2 "Falha de segurança: App Sandbox não está ativo em $app"
    return 1
  fi
  if [[ "$user_files_enabled" != "true" ]]; then
    print -u2 "Falha de segurança: arquivos escolhidos pelo usuário não estão autorizados em $app"
    return 1
  fi
}

trap remove_build_app EXIT INT TERM
remove_build_app
xattr -cr "$DERIVED_DIR"
migrate_legacy_vault

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

print "Lion Pass instalado com App Sandbox, Hardened Runtime e sem get-task-allow."
