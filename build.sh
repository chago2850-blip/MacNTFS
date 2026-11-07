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
# MacNTFS — compila la app y genera los instaladores .dmg para Apple Silicon (ARM) e Intel.
#
#   ./build.sh            ambas arquitecturas
#   ./build.sh arm64      solo Apple Silicon
#   ./build.sh x86_64     solo Intel
#
# Variables opcionales: MACNTFS_VERSION (1.0.0), MACNTFS_REPO (usuario/MacNTFS en GitHub),
#                       MACNTFS_SIGN_ID ("Developer ID Application: …" para firmar y notarizar).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
VERSION="${MACNTFS_VERSION:-1.0.0}"
export MACNTFS_VERSION="$VERSION"
DIST="$ROOT/dist"

ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m! %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

echo
echo "  MacNTFS $VERSION — compilación"
echo "  ───────────────────────────────"

# --- Requisitos ---------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || fail "Este script debe ejecutarse en macOS."
xcode-select -p >/dev/null 2>&1 || fail "Faltan las herramientas de Xcode. Ejecuta: xcode-select --install"
command -v swift >/dev/null || fail "No se encontró swift. Instala Xcode o las Command Line Tools."
SWIFT_VER="$(swift --version 2>&1 | head -1)"
ok "Swift: $SWIFT_VER"

command -v brew >/dev/null || fail "Necesitas Homebrew (https://brew.sh) para instalar autoconf, automake, libtool y pkg-config."
MISSING=()
for tool in autoconf automake glibtoolize pkg-config; do
    command -v "$tool" >/dev/null || MISSING+=("$tool")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    warn "Instalando herramientas de compilación: autoconf automake libtool pkg-config"
    brew install autoconf automake libtool pkg-config
fi
ok "Herramientas de autotools"

if ! pkg-config --exists fuse 2>/dev/null && [ ! -f /usr/local/include/fuse/fuse.h ] \
   && [ ! -d /Library/Frameworks/fuse_t.framework ] && [ ! -e /usr/local/lib/libfuse-t.dylib ]; then
    fail "Falta FUSE para compilar ntfs-3g. Instala FUSE-T:  brew install macos-fuse-t/homebrew-cask/fuse-t
   (o macFUSE:  brew install --cask macfuse)"
fi
ok "FUSE disponible"

command -v create-dmg >/dev/null || warn "Opcional: 'brew install create-dmg' para un DMG con fondo e ícono personalizados."

# --- Compilación --------------------------------------------------------------
if [ $# -eq 0 ]; then ARCHES=(arm64 x86_64); else ARCHES=("$@"); fi
mkdir -p "$DIST"

for ARCH in "${ARCHES[@]}"; do
    case "$ARCH" in
        arm64)  LABEL="AppleSilicon" ;;
        x86_64) LABEL="Intel" ;;
        *) fail "Arquitectura desconocida: $ARCH (usa arm64 o x86_64)" ;;
    esac
    echo
    echo "  ▶ $LABEL ($ARCH)"
    scripts/build-ntfs3g.sh "$ARCH" "$ROOT/build/ntfs-$ARCH"
    scripts/build-app.sh "$ARCH" "$ROOT/build/ntfs-$ARCH" "$ROOT/build/$ARCH/MacNTFS.app"
    scripts/make-dmg.sh "$ROOT/build/$ARCH/MacNTFS.app" "$DIST/MacNTFS-$VERSION-$LABEL.dmg" "$LABEL"
    ok "dist/MacNTFS-$VERSION-$LABEL.dmg"
done

echo
ok "Listo. Instaladores en: $DIST"
ls -lh "$DIST"/*.dmg
