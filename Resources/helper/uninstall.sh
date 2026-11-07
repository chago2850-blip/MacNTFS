#!/bin/bash
# Desinstala los componentes de MacNTFS (no toca FUSE-T ni macFUSE).
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
BASE=/usr/local/libexec/macntfs

[ "$(id -u)" = "0" ] || { echo "Se requiere administrador" >&2; exit 77; }

if [ -e "$BASE/.created-libfuse-symlink" ] && [ -L /usr/local/lib/libfuse.2.dylib ]; then
    rm -f /usr/local/lib/libfuse.2.dylib
fi
rm -f /etc/sudoers.d/macntfs
rm -f /usr/local/bin/macntfs
rm -rf "$BASE"
echo "Componentes de MacNTFS eliminados."
