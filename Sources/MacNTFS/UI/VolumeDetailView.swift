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

struct VolumeDetailView: View {
    @EnvironmentObject private var manager: VolumeManager
    let volumeID: String
    @State private var showVerify = false
    @State private var showErase = false

    var body: some View {
        if let v = manager.volume(volumeID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(v)
                    if let issue = manager.issues[v.id], issue != .cancelled {
                        IssueBanner(issue: issue, volume: v)
                    }
                    actions(v)
                    info(v)
                    if v.isNTFS { OptionsCard(volume: v) }
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $showVerify) { VerifySheet(volume: v) }
            .sheet(isPresented: $showErase) { EraseSheet(volume: v) }
        } else {
            EmptyStateView()
        }
    }

    private func header(_ v: Volume) -> some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Brand.deepGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: .brandViolet.opacity(0.35), radius: 10, y: 5)
                Image(systemName: v.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Brand.gradient)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(v.name).font(.largeTitle.weight(.bold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(v.kindTitle) · \(formatBytes(v.size)) · \(v.bsdName)")
                    if !v.protocolName.isEmpty { Text("· \(v.protocolName)") }
                }
                .foregroundStyle(.secondary)
                StatusPill(state: v.state, issue: manager.issues[v.id])
            }
            Spacer()
        }
    }

    private func actions(_ v: Volume) -> some View {
        let busy = manager.busy.contains(v.id)
        return HStack(spacing: 10) {
            if v.state == .readWrite || v.state == .readOnly {
                Button {
                    Task { await manager.unmount(v) }
                } label: { Label("Desmontar", systemImage: "eject") }
                    .controlSize(.large)
            } else {
                Button {
                    Task { await manager.toggleMount(v) }
                } label: {
                    Label(v.isNTFS ? "Montar en lectura y escritura" : "Montar", systemImage: "externaldrive.badge.plus")
                }
                .buttonStyle(BrandButtonStyle())
                .disabled(v.isNTFS && !manager.isReady)
            }

            if let mp = v.mountPoint {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mp))
                } label: { Label("Abrir en Finder", systemImage: "folder") }
                    .controlSize(.large)
            }

            Spacer()

            Menu {
                if v.canVerify {
                    Button("Verificar y reparar…") { showVerify = true }
                }
                Button("Borrar / formatear…") { showErase = true }
                    .disabled(!v.canErase)
                if v.isEjectable || v.isRemovable || !v.isInternal {
                    Divider()
                    Button("Expulsar disco") { Task { await manager.eject(v) } }
                }
            } label: {
                Label("Más", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.large)
        }
        .disabled(busy || !v.canMountOperations)
        .overlay(alignment: .trailing) {
            if busy { ProgressView().controlSize(.small).offset(x: 28) }
        }
    }

    private func info(_ v: Volume) -> some View {
        Card {
            if let fraction = v.usedFraction, let total = v.totalBytes, let free = v.freeBytes {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Usado \(formatBytes(total - free))").font(.headline)
                        Spacer()
                        Text("Disponible \(formatBytes(free))").foregroundStyle(.secondary)
                    }
                    CapacityBar(fraction: fraction)
                }
                Divider()
            }
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Estado", value: v.state.title)
                InfoRow(label: "Controlador", value: v.driverTitle)
                InfoRow(label: "Punto de montaje", value: v.mountPoint ?? "—")
                InfoRow(label: "Dispositivo", value: "/dev/\(v.bsdName)")
                InfoRow(label: "Disco", value: v.deviceModel.isEmpty ? v.wholeDisk : "\(v.deviceModel) (\(v.wholeDisk))")
                InfoRow(label: "Ubicación", value: v.isInternal ? "Interna" : "Externa")
                if let uuid = v.uuid { InfoRow(label: "UUID", value: uuid) }
                if v.isBoot { InfoRow(label: "Nota", value: "Es el disco de arranque: las operaciones están desactivadas.") }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct IssueBanner: View {
    @EnvironmentObject private var manager: VolumeManager
    let issue: MountIssue
    let volume: Volume

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title).font(.headline)
                if !issue.detail.isEmpty {
                    Text(issue.detail).font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    if issue == .unclean || issue == .corrupt {
                        Button("Reparar y montar") {
                            Task {
                                let r = await manager.check(volume, repair: true)
                                if r.ok, let v = manager.volume(volume.id) { await manager.mount(v, skipDirtyCheck: true) }
                            }
                        }
                    }
                    if issue == .hibernated || issue == .unclean || issue == .corrupt {
                        Button("Montar en solo lectura") {
                            Task { await manager.mount(volume, forceReadOnly: true) }
                        }
                    }
                    if issue == .fullDiskAccess {
                        Button("Abrir Acceso total al disco") { FullDiskAccess.openSettings() }
                    }
                    Button("Ignorar") { manager.issues[volume.id] = nil }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }
}

struct OptionsCard: View {
    @EnvironmentObject private var manager: VolumeManager
    let volume: Volume

    private func binding(_ keyPath: WritableKeyPath<VolumeOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.options(for: volume)[keyPath: keyPath] },
            set: { newValue in
                var options = manager.options(for: volume)
                options[keyPath: keyPath] = newValue
                manager.setOptions(options, for: volume)
            }
        )
    }

    var body: some View {
        Card {
            Text("Opciones de este volumen").font(.headline)
            Toggle("Montar en solo lectura", isOn: binding(\.readOnly))
                .help("Protege el contenido; útil para discos con Windows hibernado.")
            Toggle("No montar automáticamente", isOn: binding(\.noAutomount))
            Toggle("Ignorar propietarios (todos los usuarios pueden escribir)", isOn: binding(\.ignoreOwnership))
            Toggle("Guardar la fecha de último acceso", isOn: binding(\.saveLastAccess))
                .help("Desactívalo para reducir escrituras en el disco.")
            Toggle("Indexar con Spotlight", isOn: binding(\.spotlight))
                .help("Puede no estar disponible con FUSE-T.")
            Text("Los cambios se aplican volviendo a montar el volumen automáticamente.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(volume.isBoot)
    }
}
