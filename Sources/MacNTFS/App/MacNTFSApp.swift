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
                Button("Sitio del proyecto y código fuente") { NSWorkspace.shared.open(AppInfo.repositoryURL) }
                Button("Licencia (GPL-3.0)") { LegalDocs.open("LICENSE.txt") }
                Button("Componentes de terceros") { LegalDocs.open("THIRD_PARTY_NOTICES.md") }
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

/// Abre los documentos legales incluidos en Resources con la app predeterminada.
enum LegalDocs {
    static func open(_ name: String) {
        let url = URL(fileURLWithPath: AppInfo.resourcesPath).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
        }
    }
}

enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(
            string: "Lectura y escritura de discos NTFS para macOS.\nCopyright © 2026 Santiago Miguel · chago2850@gmail.com\n\nSoftware libre bajo la Licencia Pública General GNU v3 o posterior (GPL-3.0-or-later). Se distribuye SIN NINGUNA GARANTÍA. Ayuda → Licencia para leerla completa.\n\nMotor NTFS: ntfs-3g (Tuxera / comunidad).\nCapa FUSE: FUSE-T o macFUSE.",
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
