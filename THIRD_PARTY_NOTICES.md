# Componentes de terceros

MacNTFS se distribuye bajo la **GPL-3.0-or-later**. Este archivo enumera el software de terceros que se incluye en el DMG o que la aplicación utiliza, junto con su licencia.

## Incluido en el DMG

| Componente | Licencia | Código fuente |
|---|---|---|
| [ntfs-3g](https://github.com/tuxera/ntfs-3g): `ntfs-3g`, `ntfs-3g.probe`, `mkntfs`, `ntfsfix`, `ntfslabel`, `ntfsinfo` | GPL-2.0-or-later (© Tuxera Inc. y colaboradores) | El archivo `ntfs-3g-<versión>-codigo-fuente.tar.gz` de cada versión en [Releases](https://github.com/chago2850-blip/MacNTFS/releases), compilado sin modificaciones |

Por su cláusula "or later", ntfs-3g puede distribuirse junto a MacNTFS bajo los términos de la GPL-3.0.

## Necesarios pero no incluidos

El usuario instala por su cuenta una de estas capas FUSE. Cada una tiene su propia licencia y MacNTFS no las redistribuye.

| Componente | Licencia |
|---|---|
| [FUSE-T](https://www.fuse-t.org) | Licencia propia de FUSE-T (gratuita) |
| [macFUSE](https://macfuse.github.io) | Licencia propia de macFUSE |

MacNTFS también usa herramientas incluidas en macOS (`diskutil`, `mdutil`, `osascript`, `sudo`), propiedad de Apple.

## Marcas

"Paragon" y "NTFS for Mac" son marcas de Paragon Software Group. "NTFS" y "Windows" son marcas de Microsoft. MacNTFS es un proyecto independiente y no está afiliado a ninguna de esas compañías. La carpeta `replica/` contiene un análisis funcional hecho únicamente con documentación pública.
