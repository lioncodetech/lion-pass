#!/usr/bin/env bash
set -euo pipefail
export AVALONIA_TELEMETRY_OPTOUT="${AVALONIA_TELEMETRY_OPTOUT:-1}"
export DOTNET_CLI_TELEMETRY_OPTOUT="${DOTNET_CLI_TELEMETRY_OPTOUT:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$LINUX_DIR/.." && pwd)"
RID="${1:-linux-x64}"
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="$LINUX_DIR/artifacts/$RID"
PUBLISH_DIR="$OUTPUT_DIR/publish"
PROJECT="$LINUX_DIR/src/LionPass.App/LionPass.App.csproj"
DOTNET_BIN="${DOTNET_BIN:-dotnet}"

case "$RID" in
  linux-x64) DEB_ARCH="amd64" ;;
  linux-arm64) DEB_ARCH="arm64" ;;
  *) echo "RID não suportado: $RID" >&2; exit 2 ;;
esac

rm -rf "$OUTPUT_DIR"
mkdir -p "$PUBLISH_DIR"
"$DOTNET_BIN" publish "$PROJECT" -c Release -r "$RID" --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -o "$PUBLISH_DIR"
find "$PUBLISH_DIR" -name '*.pdb' -delete

cp "$ROOT_DIR/shared/assets/app-icon/LionPass-1024.png" "$OUTPUT_DIR/lion-pass.png"
tar -C "$OUTPUT_DIR" -czf "$OUTPUT_DIR/LionPass-Linux-$RID-$VERSION.tar.gz" publish

if command -v dpkg-deb >/dev/null 2>&1; then
  DEB_ROOT="$OUTPUT_DIR/deb-root"
  mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/opt/lion-pass" \
    "$DEB_ROOT/usr/share/applications" "$DEB_ROOT/usr/share/icons/hicolor/512x512/apps"
  cp -a "$PUBLISH_DIR/." "$DEB_ROOT/opt/lion-pass/"
  cp "$LINUX_DIR/packaging/linux-pass.desktop" "$DEB_ROOT/usr/share/applications/lion-pass.desktop"
  cp "$OUTPUT_DIR/lion-pass.png" "$DEB_ROOT/usr/share/icons/hicolor/512x512/apps/lion-pass.png"
  sed -e "s/@VERSION@/$VERSION/g" -e "s/@ARCH@/$DEB_ARCH/g" \
    "$LINUX_DIR/packaging/deb/control.template" > "$DEB_ROOT/DEBIAN/control"
  dpkg-deb --build --root-owner-group "$DEB_ROOT" "$OUTPUT_DIR/lion-pass_${VERSION}_${DEB_ARCH}.deb"
fi

APPIMAGE_TOOL="${APPIMAGETOOL:-$(command -v appimagetool || true)}"
if [[ -n "$APPIMAGE_TOOL" && "$RID" == "linux-x64" ]]; then
  APPDIR="$OUTPUT_DIR/LionPass.AppDir"
  mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/512x512/apps"
  cp -a "$PUBLISH_DIR/." "$APPDIR/usr/bin/"
  cp "$LINUX_DIR/packaging/appimage/AppRun" "$APPDIR/AppRun"
  chmod +x "$APPDIR/AppRun" "$APPDIR/usr/bin/LionPass.App"
  cp "$LINUX_DIR/packaging/appimage/lion-pass.desktop" "$APPDIR/lion-pass.desktop"
  cp "$OUTPUT_DIR/lion-pass.png" "$APPDIR/lion-pass.png"
  cp "$OUTPUT_DIR/lion-pass.png" "$APPDIR/usr/share/icons/hicolor/512x512/apps/lion-pass.png"
  ARCH=x86_64 "$APPIMAGE_TOOL" "$APPDIR" "$OUTPUT_DIR/LionPass-$VERSION-x86_64.AppImage"
fi

echo "Pacotes gerados em $OUTPUT_DIR"
