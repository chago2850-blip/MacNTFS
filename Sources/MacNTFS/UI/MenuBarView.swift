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

struct MenuBarView: View {
    @EnvironmentObject private var manager: VolumeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppLogo(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacNTFS").font(.headline)
                    Text(manager.isReady ? "Driver activo" : "Configuración pendiente")
                        .font(.caption).foregroundStyle(manager.isReady ? Color.secondary : Color.orange)
                }
                Spacer()
            }

            Divider()

            if manager.ntfsVolumes.isEmpty {
                Text("No hay discos NTFS conectados")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(manager.ntfsVolumes) { v in
                    HStack(spacing: 10) {
                        DriveIcon(volume: v, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.name).lineLimit(1)
                            Text(manager.issues[v.id]?.title ?? v.state.title)
                                .font(.caption)
                                .foregroundStyle(manager.issues[v.id] == nil ? Color.secondary : Color.orange)
                        }
                        Spacer()
                        if manager.busy.contains(v.id) {
                            ProgressView().controlSize(.small)
                        } else if v.state == .readWrite || v.state == .readOnly {
                            Button {
                                Task { await manager.unmount(v) }
                            } label: { Image(systemName: "eject.fill") }
                                .buttonStyle(.borderless)
                                .help("Desmontar")
                        } else {
                            Button("Montar") { Task { await manager.mount(v) } }
                                .controlSize(.small)
                                .disabled(!manager.isReady || v.isBoot)
                        }
                    }
                    .contextMenu {
                        if let mp = v.mountPoint {
                            Button("Abrir en Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: mp)) }
                        }
                        Button("Montar en solo lectura") { Task { await manager.mount(v, forceReadOnly: true) } }
                        Button("Expulsar disco") { Task { await manager.eject(v) } }
                    }
                }
            }

            Divider()

            HStack {
                Button("Abrir MacNTFS") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                settingsButton
                Button {
                    NSApp.terminate(nil)
                } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless)
                    .help("Salir de MacNTFS")
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Preferencias")
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Preferencias")
        }
    }
}
