#!/bin/bash
# Instala los componentes de MacNTFS. Lo ejecuta la app como administrador.
# Uso: install.sh <ruta Resources de MacNTFS.app> <usuario> <versión>
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

RES="$1"; USER_NAME="${2:-}"; VERSION="${3:-dev}"
BASE=/usr/local/libexec/macntfs
HELPER="$BASE/macntfs-helper"
SUDOERS=/etc/sudoers.d/macntfs

[ "$(id -u)" = "0" ] || { echo "Se requiere administrador" >&2; exit 77; }
[ -x "$RES/ntfs/bin/ntfs-3g" ] || { echo "El paquete no contiene ntfs-3g ($RES/ntfs/bin)" >&2; exit 65; }

# 1. Motor ntfs-3g y herramientas (copias propiedad de root: la app no puede modificarlas)
install -d -o root -g wheel -m 755 /usr/local/libexec "$BASE" "$BASE/bin"
for f in "$RES"/ntfs/bin/*; do
    install -o root -g wheel -m 755 "$f" "$BASE/bin/$(basename "$f")"
done
install -o root -g wheel -m 755 "$RES/helper/macntfs-helper" "$HELPER"
echo "$VERSION" > "$BASE/VERSION"
chown root:wheel "$BASE/VERSION"; chmod 644 "$BASE/VERSION"
xattr -dr com.apple.quarantine "$BASE" 2>/dev/null || true

# 2. Permitir montar/desmontar/verificar/reparar sin contraseña (formatear siempre la pide)
TMP=$(mktemp /tmp/macntfs-sudoers.XXXXXX)
cat > "$TMP" <<EOF
# MacNTFS — operaciones de disco NTFS sin contraseña. Elimina este archivo para desactivarlo.
Cmnd_Alias MACNTFS_CMDS = $HELPER mount *, $HELPER unmount *, $HELPER verify *, $HELPER repair *, $HELPER spotlight *, $HELPER version
%staff ALL=(root) NOPASSWD: MACNTFS_CMDS
EOF
if visudo -cf "$TMP" >/dev/null; then
    install -o root -g wheel -m 440 "$TMP" "$SUDOERS"
else
    echo "Advertencia: no se pudo validar la regla de sudo; MacNTFS pedirá contraseña al montar." >&2
fi
rm -f "$TMP"

# 3. FUSE-T expone la API de libfuse 2 en libfuse-t.dylib; ntfs-3g busca libfuse.2.dylib
mkdir -p /usr/local/lib
if [ ! -e /usr/local/lib/libfuse.2.dylib ] && [ -e /usr/local/lib/libfuse-t.dylib ]; then
    ln -s /usr/local/lib/libfuse-t.dylib /usr/local/lib/libfuse.2.dylib
    touch "$BASE/.created-libfuse-symlink"
fi
if [ ! -e /etc/fuse.conf ] || ! grep -q '^user_allow_other' /etc/fuse.conf; then
    echo "user_allow_other" >> /etc/fuse.conf
fi

# 4. Herramienta de Terminal
mkdir -p /usr/local/bin
install -o root -g wheel -m 755 "$RES/helper/macntfs" /usr/local/bin/macntfs

# 5. Comprobación rápida del motor
if ! "$BASE/bin/ntfs-3g" --version >/dev/null 2>&1 && ! "$BASE/bin/ntfs-3g" -h 2>&1 | grep -qi "ntfs-3g"; then
    if [ ! -e /usr/local/lib/libfuse.2.dylib ]; then
        echo "Componentes instalados, pero falta FUSE (libfuse.2.dylib). Instala FUSE-T y pulsa Reparar componentes." >&2
        exit 21
    fi
fi

echo "MacNTFS $VERSION instalado para ${USER_NAME:-todos los usuarios}."
