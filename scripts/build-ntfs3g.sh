#!/bin/bash
# Compila ntfs-3g (motor NTFS de código abierto, GPL) para una arquitectura de macOS.
# Uso: scripts/build-ntfs3g.sh <arm64|x86_64> <carpeta-salida>
set -euo pipefail

ARCH="$1"
OUT="$2"
NTFS3G_VERSION="${NTFS3G_VERSION:-2022.10.3}"
MIN_MACOS="${MIN_MACOS:-12.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/work"
SRC_CACHE="$WORK/ntfs-3g-src-$NTFS3G_VERSION"
BUILD_DIR="$WORK/ntfs-3g-$ARCH"

log() { printf "\033[1;36m▸ %s\033[0m\n" "$*"; }

mkdir -p "$WORK"

# --- Fuente -----------------------------------------------------------------
if [ ! -d "$SRC_CACHE" ]; then
    log "Descargando ntfs-3g $NTFS3G_VERSION"
    git clone --depth 1 --branch "$NTFS3G_VERSION" https://github.com/tuxera/ntfs-3g.git "$SRC_CACHE"
    (cd "$SRC_CACHE" && LIBTOOLIZE=glibtoolize autoreconf -fi)
fi
rm -rf "$BUILD_DIR"
cp -R "$SRC_CACHE" "$BUILD_DIR"

# --- FUSE (cabeceras y biblioteca libfuse 2) -------------------------------
PKG_DIR="$WORK/pkgconfig"
mkdir -p "$PKG_DIR"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

if pkg-config --exists fuse 2>/dev/null; then
    log "Usando FUSE de pkg-config: $(pkg-config --modversion fuse) ($(pkg-config --cflags fuse))"
else
    # Solo FUSE-T instalado: crear un fuse.pc temporal que apunte a sus cabeceras.
    HDR=""
    for d in /usr/local/include/fuse /Library/Frameworks/fuse_t.framework/Headers /Library/Frameworks/fuse_t.framework/Versions/A/Headers; do
        [ -f "$d/fuse.h" ] && { HDR="$d"; break; }
    done
    LIBNAME=""
    [ -e /usr/local/lib/libfuse.2.dylib ] && LIBNAME="fuse"
    [ -z "$LIBNAME" ] && [ -e /usr/local/lib/libfuse-t.dylib ] && LIBNAME="fuse-t"
    if [ -z "$HDR" ] || [ -z "$LIBNAME" ]; then
        echo "No se encontraron las cabeceras de FUSE." >&2
        echo "Instala macFUSE (solo hace falta para compilar):  brew install --cask macfuse" >&2
        echo "o FUSE-T:                                           brew install macos-fuse-t/homebrew-cask/fuse-t" >&2
        exit 1
    fi
    log "Generando fuse.pc para FUSE-T ($HDR, -l$LIBNAME)"
    cat > "$PKG_DIR/fuse.pc" <<EOF
prefix=/usr/local
Name: fuse
Description: FUSE (FUSE-T)
Version: 2.9.9
Libs: -L/usr/local/lib -l$LIBNAME
Cflags: -I$HDR -D_FILE_OFFSET_BITS=64 -D_DARWIN_USE_64_BIT_INODE
EOF
    export PKG_CONFIG_PATH="$PKG_DIR:$PKG_CONFIG_PATH"
fi

# --- Compilación ------------------------------------------------------------
HOST_ARCH="$(uname -m)"
case "$ARCH" in
    arm64)  HOST_TRIPLE="aarch64-apple-darwin" ;;
    x86_64) HOST_TRIPLE="x86_64-apple-darwin" ;;
    *) echo "Arquitectura no válida: $ARCH" >&2; exit 64 ;;
esac
case "$HOST_ARCH" in
    arm64)  BUILD_TRIPLE="aarch64-apple-darwin" ;;
    *)      BUILD_TRIPLE="x86_64-apple-darwin" ;;
esac

export CC="clang -arch $ARCH"
export CFLAGS="-O2 -arch $ARCH -mmacosx-version-min=$MIN_MACOS -Wno-implicit-function-declaration"
export LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -Wl,-rpath,/usr/local/lib -Wl,-rpath,/Library/Frameworks"

log "Configurando ntfs-3g para $ARCH"
cd "$BUILD_DIR"
./configure \
    --build="$BUILD_TRIPLE" \
    --host="$HOST_TRIPLE" \
    --prefix=/usr/local \
    --exec-prefix=/usr/local \
    --with-fuse=external \
    --disable-shared \
    --enable-static \
    --disable-ldconfig \
    --disable-mtab \
    --disable-plugins \
    --disable-dependency-tracking \
    > "$WORK/configure-$ARCH.log" 2>&1 || { tail -40 "$WORK/configure-$ARCH.log"; exit 1; }

log "Compilando ntfs-3g para $ARCH"
make -j"$(sysctl -n hw.ncpu)" > "$WORK/make-$ARCH.log" 2>&1 || { tail -60 "$WORK/make-$ARCH.log"; exit 1; }

# --- Copiar binarios ----------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT/bin"
pick() {
    local path="$1"
    local dir; dir="$(dirname "$path")"; local name; name="$(basename "$path")"
    if [ -f "$dir/.libs/$name" ] && file "$dir/.libs/$name" | grep -q Mach-O; then
        echo "$dir/.libs/$name"
    else
        echo "$path"
    fi
}
for p in src/ntfs-3g src/ntfs-3g.probe ntfsprogs/mkntfs ntfsprogs/ntfsfix ntfsprogs/ntfslabel ntfsprogs/ntfsinfo; do
    real="$(pick "$p")"
    if ! file "$real" | grep -q Mach-O; then
        echo "No se generó $p (ver $WORK/make-$ARCH.log)" >&2
        exit 1
    fi
    cp "$real" "$OUT/bin/$(basename "$p")"
    strip -x "$OUT/bin/$(basename "$p")" 2>/dev/null || true
done

log "ntfs-3g listo en $OUT/bin"
lipo -info "$OUT/bin/ntfs-3g"
otool -L "$OUT/bin/ntfs-3g" | sed 's/^/    /'
