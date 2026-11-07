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
