// swift-tools-version:5.9
// MacNTFS — lectura y escritura de NTFS para macOS. Licencia GPL-2.0-or-later.
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
