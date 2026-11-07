#!/bin/bash
# MacNTFS — lectura y escritura de discos NTFS en macOS
# Copyright (C) 2026 Santiago Miguel <chago2850@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Este programa es software libre: puede redistribuirlo y/o modificarlo bajo los
# términos de la Licencia Pública General GNU publicada por la Free Software
# Foundation, ya sea la versión 3 de la Licencia o (a su elección) cualquier
# versión posterior.
#
# Este programa se distribuye con la esperanza de que sea útil, pero SIN NINGUNA
# GARANTÍA; ni siquiera la garantía implícita de COMERCIABILIDAD o IDONEIDAD PARA
# UN PROPÓSITO PARTICULAR. Consulte la Licencia Pública General GNU para más detalles.
#
# Debería haber recibido una copia de la Licencia Pública General GNU junto con
# este programa (archivo LICENSE). Si no, consulte <https://www.gnu.org/licenses/>.
#
# Compila MacNTFS.app para una arquitectura y empaqueta ntfs-3g dentro.
# Uso: scripts/build-app.sh <arm64|x86_64> <carpeta ntfs-3g> <ruta .app de salida>
set -euo pipefail

ARCH="$1"
NTFS_DIR="$2"
APP="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${MACNTFS_VERSION:-1.0.0}"
BUILD_NUMBER="${MACNTFS_BUILD:-1}"
REPO="${MACNTFS_REPO:-chago2850-blip/MacNTFS}"
BUNDLE_ID="${MACNTFS_BUNDLE_ID:-io.github.macntfs.MacNTFS}"

log() { printf "\033[1;36m▸ %s\033[0m\n" "$*"; }

cd "$ROOT"
log "Compilando MacNTFS $VERSION ($ARCH)"
swift build -c release --arch "$ARCH" --product MacNTFS
BIN_PATH="$(swift build -c release --arch "$ARCH" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/helper" "$APP/Contents/Resources/ntfs/bin"
cp "$BIN_PATH/MacNTFS" "$APP/Contents/MacOS/MacNTFS"

# Recursos empaquetados por SwiftPM (si los hubiera)
for b in "$BIN_PATH"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# Ícono: generar .icns de alta calidad desde el PNG de 1024 px
ICONSET="$ROOT/build/work/AppIcon.iconset"
if command -v iconutil >/dev/null && [ -f "$ROOT/branding/logo-1024.png" ]; then
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ROOT/branding/logo-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s*2))
        sips -z $d $d "$ROOT/branding/logo-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    cp "$ROOT/branding/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ayudante y herramientas
cp Resources/helper/macntfs-helper Resources/helper/install.sh Resources/helper/uninstall.sh Resources/helper/macntfs "$APP/Contents/Resources/helper/"
chmod 755 "$APP"/Contents/Resources/helper/*
cp "$NTFS_DIR"/bin/* "$APP/Contents/Resources/ntfs/bin/"
chmod 755 "$APP"/Contents/Resources/ntfs/bin/*
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>CFBundleDisplayName</key><string>MacNTFS</string>
    <key>CFBundleExecutable</key><string>MacNTFS</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>MacNTFS</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Santiago Miguel · GPL-3.0-or-later</string>
    <key>MacNTFSRepository</key><string>$REPO</string>
</dict>
</plist>
EOF

# Firma ad-hoc (sin cuenta de desarrollador). Con una cuenta, exporta MACNTFS_SIGN_ID="Developer ID Application: …"
SIGN_ID="${MACNTFS_SIGN_ID:--}"
log "Firmando ($SIGN_ID)"
for f in "$APP"/Contents/Resources/ntfs/bin/*; do
    codesign --force --sign "$SIGN_ID" --timestamp=none "$f"
done
if [ "$SIGN_ID" = "-" ]; then
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi
codesign --verify --verbose=1 "$APP"
log "App lista: $APP"
