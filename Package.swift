// swift-tools-version:5.9
// MacNTFS — lectura y escritura de discos NTFS en macOS
// Copyright (C) 2026 Santiago Miguel <chago2850@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Este programa es software libre: puede redistribuirlo y/o modificarlo bajo los
// términos de la Licencia Pública General GNU publicada por la Free Software
// Foundation, ya sea la versión 3 de la Licencia o (a su elección) cualquier
// versión posterior.
//
// Este programa se distribuye con la esperanza de que sea útil, pero SIN NINGUNA
// GARANTÍA; ni siquiera la garantía implícita de COMERCIABILIDAD o IDONEIDAD PARA
// UN PROPÓSITO PARTICULAR. Consulte la Licencia Pública General GNU para más detalles.
//
// Debería haber recibido una copia de la Licencia Pública General GNU junto con
// este programa (archivo LICENSE). Si no, consulte <https://www.gnu.org/licenses/>.
import PackageDescription

let package = Package(
    name: "MacNTFS",
    defaultLocalization: "es",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacNTFS", targets: ["MacNTFS"])
    ],
    targets: [
        .executableTarget(
            name: "MacNTFS",
            path: "Sources/MacNTFS",
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
