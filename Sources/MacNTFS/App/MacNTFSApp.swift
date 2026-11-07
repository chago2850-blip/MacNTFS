import SwiftUI
import AppKit

@main
struct MacNTFSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = VolumeManager()
    @AppStorage(Prefs.Key.showMenuBar) private var showMenuBar = true

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        Window("MacNTFS", id: "main") {
            ContentView()
                .environmentObject(manager)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear { AppTheme.apply() }
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de MacNTFS") { AboutPanel.show() }
            }
            CommandGroup(after: .newItem) {
                Button("Actualizar lista de volúmenes") { manager.refreshAll() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
            CommandGroup(replacing: .help) {
                Button("Reportar un problema…") { SupportReporter.openIssue() }
                Button("Abrir carpeta de registros") { Log.revealInFinder() }
                Divider()
                Button("Sitio del proyecto") { NSWorkspace.shared.open(AppInfo.repositoryURL) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(manager)
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environmentObject(manager)
        } label: {
            Image(systemName: manager.hasReadWriteMounts ? "externaldrive.fill.badge.checkmark" : "externaldrive.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Sigue funcionando en la barra de menús para montar discos automáticamente.
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("MacNTFS \(AppInfo.version) iniciado en macOS \(ProcessInfo.processInfo.operatingSystemVersionString) (\(AppInfo.architecture))")
        Notifier.requestAuthorization()
        AppTheme.apply()
    }
}

enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(
            string: "Lectura y escritura de discos NTFS para macOS.\nLibre, gratuito y de código abierto (GPL-2.0-or-later).\n\nDesarrollado por Santiago Miguel\nchago2850@gmail.com\n\nMotor NTFS: ntfs-3g (Tuxera / comunidad).\nCapa FUSE: FUSE-T o macFUSE.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MacNTFS",
            .applicationVersion: AppInfo.version,
            .credits: credits
        ])
    }
}
