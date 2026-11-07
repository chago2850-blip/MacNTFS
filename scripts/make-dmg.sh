#!/bin/bash
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
