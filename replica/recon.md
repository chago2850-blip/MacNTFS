# Mapa de recon: Paragon NTFS for Mac 17 (macOS, escritorio)

Alcance: lectura/escritura transparente de volúmenes NTFS en macOS + gestión de volúmenes (montar, desmontar, verificar, formatear) + opciones por volumen y preferencias. Todo lo que hace el producto excepto licencias, cuenta y telemetría comercial.
Para: **MacNTFS**, app de código abierto y gratuita, sin prueba, sin activación y sin límites, para cualquier usuario de macOS.
Fecha: 2026-11-06

> Método: clean-room. Todo sale de documentación pública (manual de usuario, notas de prensa, reseñas, Homebrew). **El instalador .dmg que se subió no se abrió ni se analizó**: viene de un sitio de redistribución no oficial (FileCR) y las reglas de este proceso prohíben descompilar o inspeccionar el binario. No se guardaron capturas en `screens/`; la UI se reconstruye a partir de la descripción del manual.

## Fuentes

| # | fuente | URL | notas |
| --- | --- | --- | --- |
| 1 | manual de usuario (Paragon NTFS for Mac) | https://manualmachine.com/paragon/ntfs/2842278-user-manual | La fuente más completa: ventana, operaciones, opciones, preferencias, CLI. Versión 15/16, la UI de la 17 es la misma familia. |
| 2 | nota de prensa NTFS for Mac 17 | https://embeddedcomputing.com/technology/software-and-os/os-filesystems-libraries/paragon-software-releases-the-new-edition-of-microsoft-ntfs-for-mac-17 | Lista de funciones v17: R/W, automontaje, formatear/verificar/reparar, Boot Camp, respaldo a disco NTFS. |
| 3 | Homebrew cask `paragon-ntfs` | https://formulae.brew.sh/cask/paragon-ntfs | v17.0.488; **sigue usando kernel extension (kext)**. |
| 4 | guía de fallos en Apple Silicon (iBoysoft, competidor) | https://iboysoft.com/ntfs-for-mac/paragon-ntfs-for-mac-not-working.html | Requiere "Seguridad reducida" en Recovery, aprobar kext, Acceso total al disco, ítems de inicio. Principal dolor del usuario. |
| 5 | evolución técnica de drivers NTFS (iBoysoft) | https://iboysoft.com/ntfs-for-mac/ntfs-driver-tech-evolution.html | Gen1 FUSE+ntfs-3g, Gen2 kext, Gen3 FSKit (sin kext, sin Recovery). |
| 6 | Apple FSKit `FSUnaryFileSystem` | https://developer.apple.com/documentation/fskit/fsunaryfilesystem.md | macOS 15.4+. Un recurso de bloque → un volumen. Base de la arquitectura propuesta. |
| 7 | LightNTFS (hilo de desarrollador) | https://forums.macrumors.com/threads/developer-lightntfs-beta-ntfs-read-write-and-formatting-using-apple-fskit.2490564/ | Prueba de que ntfs-3g + FSKit + app de barra de menú es viable. |
| 8 | Mounty | https://mounty.app/ | Alternativa gratuita existente (remonta con el driver de Apple / ntfs-3g). |
| 9 | reseña Macworld (v15) | https://www.macworld.com/article/3212946/paragon-ntfs-for-mac-15-review-slick-native-performance-for-accessing-ntfs-windows-drives.html | Rendimiento casi nativo como argumento de venta. |

## Bucle principal

Conectas un disco formateado en Windows y **funciona en Finder como cualquier disco de Mac: copiar, borrar, renombrar, sin hacer nada**. El resto de la app es para cuando algo sale mal (disco sucio, Windows hibernado) o para administrar el volumen.

## Cómo funciona el original (resumen técnico)

- Driver propietario **UFSD** ("File System Link") cargado como **kext** en el kernel. Monta NTFS con su propio tipo de sistema de archivos (`ufsd_NTFS`).
- Herramientas instaladas: `/usr/local/sbin/fsck_ufsd_NTFS` (`-n` verificar, `-y` reparar) y `/usr/local/sbin/newfs_ufsd_NTFS` (formatear). Se integran con `diskutil` y Utilidad de Discos.
- App de escritorio + ícono opcional en barra de menú + daemon que vigila la conexión de discos y decide cómo montarlos.
- En Apple Silicon el kext obliga a: Recovery → Seguridad reducida → permitir extensiones de desarrolladores identificados → aprobar en Privacidad y seguridad → reiniciar. Es la fricción número 1.
- Licencia: prueba de 10 días, activación online/offline con serial y archivo `LicenseSet.xml`.

**Decisión de diseño para MacNTFS:** no imitar el kext. Usar **FSKit** (macOS 15.4+, espacio de usuario, sin Recovery ni seguridad reducida) con un motor NTFS basado en **libntfs-3g** (GPL-2.0). Respaldo para macOS < 15.4: macFUSE / FUSE-T + ntfs-3g. Lo detalla `/replica-architect`.

## Pantallas

| ID | pantalla | cómo se llega | propósito | componentes clave | estados vistos |
| --- | --- | --- | --- | --- | --- |
| S01 | Ventana principal: lista de volúmenes | Aplicaciones → la app | Ver todos los discos/volúmenes físicos y virtuales (incluye DMG montados) | Sidebar de volúmenes con ícono, nombre, FS; barra de operaciones | vacío (sin discos externos), lleno, volumen sin montar (gris), solo lectura, sucio, hibernado, error |
| S02 | Panel de detalle de volumen | seleccionar volumen en S01 | Info y opciones del volumen | Nombre, FS, capacidad/usado (barra), punto de montaje, dispositivo (`disk4s1`), estado; botones Montar/Desmontar, Verificar, Borrar; casillas de opciones | montado R/W, montado R/O, desmontado, disco de arranque (operaciones deshabilitadas), medio de solo lectura |
| S03 | Hoja Verificar / Reparar | S02 → Verificar | Comprobar integridad y corregir errores | Log de progreso, barra, resultado, botón Reparar | en curso, sin errores, errores encontrados, reparado, fallo, "hay que desmontar primero" |
| S04 | Hoja Borrar (formatear) | S02 → Borrar | Reformatear volumen | Selector de FS (NTFS, FAT32, Mac OS Plus 4 variantes, ext2/3/4 opcional), campo etiqueta, aviso de pérdida de datos, confirmar | normal, deshabilitado (arranque / R/O / DMG comprimido), en curso, éxito, error; aviso FAT32 >4 GB |
| S05 | Disco de arranque | menú barra / S01 | Elegir volumen de arranque (Boot Camp) y reiniciar ahora o después | Lista de volúmenes arrancables, botones Reiniciar / Más tarde | solo Intel con Boot Camp |
| S06 | Preferencias → General | menú app → Preferencias | Activar/desactivar driver, desinstalar, tema, política de volúmenes sucios, de Windows hibernado, logs detallados | Toggle, botón Desinstalar, pickers | driver activo / inactivo (cae al driver R/O de Apple) |
| S07 | Preferencias → Actualizaciones | pestaña | Buscar actualizaciones diarias / manual | Toggle, botón "Buscar ahora", última comprobación | al día, hay actualización, error de red |
| S08 | Preferencias → Alertas y notificaciones | pestaña | Activar/desactivar cada aviso (montaje, prueba) | Lista de toggles | — |
| S09 | Preferencias → Menú y temas | pestaña | Ícono en barra de menú, tema de ventana y de menú | Toggle, pickers de tema | — |
| S10 | Menú de barra (menu bar extra) | ícono en barra | Info rápida de volúmenes, montar/desmontar, disco de arranque, abrir Preferencias | Lista de volúmenes con submenús | sin volúmenes, con volúmenes |
| S11 | Alerta: volumen sucio | al conectar disco con dirty flag | Avisar y comprobar/reparar antes de montar | Diálogo: Reparar y montar / Montar solo lectura / Cancelar | — |
| S12 | Alerta: Windows hibernado / Inicio rápido | al conectar disco hibernado | Preguntar si montar; recomendar solo lectura | Diálogo con explicación | — |
| S13 | Notificación de montaje | tras montar | Informe de montaje (OK / R/O / error) | Notificación del sistema | éxito, solo lectura, fallo |
| S14 | Instalador / primer arranque | abrir DMG → Instalar | Licencia, contraseña admin, aprobar driver, reiniciar | Asistente por pasos | en Apple Silicon: guía a Recovery (el dolor principal) |
| S15 | Prueba / activación | primer arranque | Trial 10 días, login MyParagon, serial, licencia offline | Formularios | **skip** en el clon |
| S16 | Cuenta y soporte | ícono auriculares | Enviar ticket con logs adjuntos | Formulario | en el clon: "Reportar problema" → issue de GitHub con logs |

## Flujos

```
F01 Usar un disco NTFS en Finder (bucle principal)
    conectar disco -> (daemon) -> montaje R/W automático -> Finder
    clics del camino feliz: 0
    edge: disco sucio (F06), hibernado (F07), BitLocker, disco MBR vs GPT, varios volúmenes en un disco,
          nombres con caracteres no latinos, archivos > 4 GB, desconexión sin expulsar

F02 Expulsar / desmontar
    S01/S10 -> Desmontar (o expulsar en Finder)
    clics: 1-2
    edge: archivo abierto ("volumen en uso"), forzar desmontaje

F03 Montar en solo lectura
    S01 -> S02 -> marcar "Montar en solo lectura" -> remonta
    clics: 2
    edge: disco de arranque (deshabilitado)

F04 Verificar y reparar
    S01 -> S02 -> Verificar -> (desmonta) -> S03 -> Reparar -> monta
    clics: 3-4
    edge: volumen en uso, disco de arranque (ir a Recovery), daño que solo chkdsk de Windows arregla

F05 Formatear volumen
    S01 -> S02 -> Borrar -> S04 (FS + etiqueta) -> Confirmar -> S13
    clics: 4
    edge: disco de arranque / R/O / DMG comprimido (deshabilitado), FAT32 con disco >32 GB

F06 Disco sucio al conectar
    conectar -> S11 -> Reparar y montar -> S03 (automático) -> montado
    clics: 1
    edge: reparación falla -> ofrecer solo lectura

F07 Windows hibernado / Inicio rápido
    conectar -> S12 -> Montar solo lectura (recomendado) | R/W bajo riesgo | Cancelar
    clics: 1

F08 Instalación y primer arranque
    DMG -> S14 -> contraseña -> aprobar extensión -> (Recovery en Apple Silicon) -> reiniciar -> S15 activar
    clics del original: ~12 + reinicio a Recovery
    clon: arrastrar a Aplicaciones -> abrir -> activar extensión FSKit en Ajustes del Sistema -> listo (objetivo: ≤ 4 clics, sin reiniciar)

F09 Opciones por volumen
    S01 -> S02 -> casillas: ignorar propietarios, guardar último acceso, indexar Spotlight, no automontar
    clics: 2

F10 Desactivar driver / desinstalar
    S06 -> toggle o "Desinstalar"
    edge: al desactivar, macOS vuelve a su driver NTFS de solo lectura

F11 Elegir disco de arranque (Boot Camp, solo Intel)
    S10 -> S05 -> elegir -> Reiniciar ahora | Más tarde

F12 Actualizar
    S07 -> Buscar ahora -> descargar -> instalar

F13 Reportar problema
    S16 -> formulario -> enviar con logs

F14 Terminal
    fsck_* -n / -y, newfs_* , diskutil verifyVolume / eraseVolume
```

## Componentes

| componente | variantes | estados | usado en |
| --- | --- | --- | --- |
| Fila de volumen (sidebar) | físico, virtual/DMG, arranque, partición sin montar | normal, seleccionada, desmontado (atenuado), advertencia (sucio/hibernado), error | S01, S10 |
| Barra de capacidad | — | normal, casi lleno | S02 |
| Botón de operación | Montar/Desmontar (toggle), Verificar, Borrar (destructivo) | normal, hover, deshabilitado, en curso | S02 |
| Casilla de opción | — | on, off, deshabilitada (no aplica a este FS) | S02, S06 |
| Hoja modal (sheet) | progreso, confirmación destructiva, resultado | en curso, éxito, error | S03, S04 |
| Diálogo de alerta | informativa, decisión con 3 botones | — | S11, S12 |
| Picker de FS | — | — | S04 |
| Panel de preferencias con pestañas | General, Actualizaciones, Alertas, Menú y temas | — | S06–S09 |
| Menú de barra | lista + submenú por volumen | — | S10 |
| Notificación de sistema | éxito, aviso, error | — | S13 |
| Visor de log | — | vacío, con contenido, copiar | S03, S16 |

## Modelo de datos inferido

No hay base de datos: el "modelo" es el estado de los discos (lo da DiskArbitration/IOKit) más preferencias locales.

```
Disk        bsd_name (disk4), media_name, size_bytes, is_removable, is_internal,
            partition_scheme (GPT|MBR), protocol (USB|Thunderbolt|SATA|virtual)
            evidence: S01 lista física + virtual         confidence: high

Volume      bsd_name (disk4s1), uuid, label, fs_type (ntfs|fat32|exfat|hfs+|apfs|ext*),
            size, used, mount_point?, mount_mode (rw|ro|unmounted),
            is_boot_volume, is_dirty, is_hibernated, is_bitlocker, is_readonly_media, is_compressed_dmg
            evidence: S02, reglas de "deshabilitado" del manual   confidence: high (is_bitlocker: guess)

VolumeOptions  volume_uuid (clave), ignore_ownership=false, save_last_access=true,
               spotlight_index=false?, mount_read_only=false, no_automount=false
            evidence: manual "Options area"; valores por defecto del manual   confidence: high (default spotlight: guess)

AppPreferences driver_enabled=true, theme, dirty_policy (check_and_repair|ask|skip),
               hibernated_policy (ask|ro|rw), verbose_logs=false,
               auto_update_check=daily, alerts{mount_report: bool, ...},
               menu_bar_icon=bool, menu_theme
            evidence: S06–S09   confidence: high

CheckRun    volume_uuid, started_at, mode (verify|repair), result (clean|errors|repaired|failed), log
            evidence: S03, fsck -n/-y   confidence: medium

MountEvent  volume_uuid, at, action (mount|unmount|remount), mode, outcome, message
            evidence: S13 "mount reports", logs de soporte   confidence: medium

FormatJob   volume bsd_name, target_fs, label, started_at, outcome
            evidence: S04   confidence: high
```

Relaciones: Disk 1-n Volume; Volume 1-1 VolumeOptions (por UUID, sobrevive a reconexiones); Volume 1-n CheckRun; Volume 1-n MountEvent.

## Matriz de funciones

Ver `features.csv`. Must: 17, should: 14, could: 8, skip: 6.

## Fuera de alcance (no se puede o no se debe clonar)

- **Driver UFSD de Paragon** (propietario). Se sustituye por libntfs-3g (GPL-2.0) sobre FSKit.
- **Prueba, activación, seriales, MyParagon, extensión por Facebook**: el clon no tiene restricciones por diseño.
- **Integración con la GUI de Utilidad de Discos** del original: depende de hooks privados del kext; en el clon se ofrecen las herramientas `fsck_ntfs`/`newfs_ntfs` en CLI (posible integración vía FSKit en macOS 26: por confirmar).
- **Boot Camp en Apple Silicon**: no existe en hardware Apple Silicon.
- **Reparación completa tipo chkdsk**: ni ntfs-3g ni ningún proyecto abierto replica el chkdsk de Windows; `ntfsfix` solo arregla lo básico y limpia el journal. Se dice claramente en la UI.
- **Firma y notarización** con la cuenta de desarrollador de Apple de Paragon: el proyecto necesita su propio Developer ID (99 USD/año) o el usuario verá Gatekeeper al abrir builds sin firmar.

## Tamaño

Pantallas 16 (14 a construir), flujos 14, entidades 7.

Partes difíciles:
1. **Motor NTFS en espacio de usuario sobre FSKit**: portar libntfs-3g al protocolo `FSUnaryFileSystem` + `FSVolume` (lookup, read/write, xattrs, renombrado, permisos) y conseguir rendimiento aceptable (caché, tamaños de E/S).
2. **Seguridad de datos**: detectar volumen sucio, hibernación/Inicio rápido de Windows, BitLocker; montar en solo lectura cuando haya riesgo. Un fallo aquí corrompe discos de usuarios.
3. **Distribución y compatibilidad**: FSKit solo desde macOS 15.4; ruta de respaldo FUSE (macFUSE/FUSE-T) para macOS 12–15.3; firma, notarización y la licencia GPL de ntfs-3g (el proyecto entero debe ser GPL-compatible).

Tamaño: **L (un trimestre)** para paridad con must + should. Un MVP de montaje R/W automático en macOS 15.4+ es **M (unas semanas)**.
