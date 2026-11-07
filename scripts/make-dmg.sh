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
# Crea el .dmg de instalación con fondo, ícono de volumen y acceso directo a Aplicaciones.
# Uso: scripts/make-dmg.sh <MacNTFS.app> <salida.dmg> <etiqueta de arquitectura>
set -euo pipefail

APP="$1"
DMG="$2"
ARCH_LABEL="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$ROOT/build/work/dmg-$ARCH_LABEL"

log() { printf "\033[1;36m▸ %s\033[0m\n" "$*"; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp "$ROOT/Resources/dmg/Leeme.txt" "$STAGE/Léeme primero.txt"

if command -v create-dmg >/dev/null; then
    log "Creando DMG con create-dmg ($ARCH_LABEL)"
    create-dmg \
        --volname "MacNTFS" \
        --volicon "$APP/Contents/Resources/AppIcon.icns" \
        --background "$ROOT/branding/dmg-background.png" \
        --window-pos 200 140 \
        --window-size 660 420 \
        --icon-size 120 \
        --icon "MacNTFS.app" 170 200 \
        --icon "Léeme primero.txt" 330 340 \
        --hide-extension "MacNTFS.app" \
        --app-drop-link 490 200 \
        --no-internet-enable \
        "$DMG" "$STAGE" || {
            # create-dmg devuelve 2 si solo falló el diseño de la ventana (p. ej. sin sesión gráfica)
            [ -f "$DMG" ] || exit 1
        }
else
    log "Creando DMG con hdiutil ($ARCH_LABEL) — instala create-dmg para una ventana con fondo"
    ln -s /Applications "$STAGE/Aplicaciones"
    hdiutil create -volname "MacNTFS" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
fi

log "DMG listo: $DMG ($(du -h "$DMG" | cut -f1))"
