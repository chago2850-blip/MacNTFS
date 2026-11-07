import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: VolumeManager
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            Group {
                if !manager.isReady || manager.componentsOutdated {
                    SetupView()
                } else if let volume = manager.volume(selection) {
                    VolumeDetailView(volumeID: volume.id)
                        .id(volume.id)
                } else {
                    EmptyStateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manager.refreshAll()
                } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                .help("Actualizar la lista de volúmenes")
            }
        }
        .navigationTitle("MacNTFS")
        .onAppear {
            manager.refreshAll()
            if selection == nil { selection = manager.ntfsVolumes.first?.id }
        }
        .onChange(of: manager.volumes) { volumes in
            if selection == nil || !volumes.contains(where: { $0.id == selection }) {
                selection = manager.ntfsVolumes.first?.id ?? volumes.first?.id
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = manager.toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        withAnimation { manager.toast = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: manager.toast)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var manager: VolumeManager
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            Section("Windows (NTFS)") {
                if manager.ntfsVolumes.isEmpty {
                    Text("Conecta un disco NTFS")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(manager.ntfsVolumes) { volume in
                    VolumeRow(volume: volume).tag(volume.id)
                }
            }
            if !manager.otherVolumes.isEmpty {
                Section("Otros volúmenes externos") {
                    ForEach(manager.otherVolumes) { volume in
                        VolumeRow(volume: volume).tag(volume.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(manager.isReady ? "Driver activo · \(manager.fuse.name)" : "Configuración pendiente")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        }
    }
}

struct VolumeRow: View {
    @EnvironmentObject private var manager: VolumeManager
    let volume: Volume

    var body: some View {
        HStack(spacing: 10) {
            DriveIcon(volume: volume, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name).lineLimit(1)
                HStack(spacing: 4) {
                    Text(volume.kindTitle)
                    Text("·")
                    Text(formatBytes(volume.size))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if manager.busy.contains(volume.id) {
                ProgressView().controlSize(.small)
            } else if manager.issues[volume.id] != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if volume.state == .readWrite {
                Image(systemName: "pencil.circle.fill").foregroundStyle(.green).help("Lectura y escritura")
            } else if volume.state == .readOnly || volume.state == .appleReadOnly {
                Image(systemName: "lock.circle.fill").foregroundStyle(.blue).help("Solo lectura")
            }
        }
        .padding(.vertical, 3)
        .opacity(volume.state == .unmounted ? 0.65 : 1)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            AppLogo(size: 120)
            Text("Conecta un disco de Windows")
                .font(.title2.weight(.semibold))
            Text("MacNTFS lo montará automáticamente en lectura y escritura.\nLuego úsalo en Finder como cualquier otro disco.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
