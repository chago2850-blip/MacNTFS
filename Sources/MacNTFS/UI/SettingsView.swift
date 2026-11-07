import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            UpdatesSettings().tabItem { Label("Actualizaciones", systemImage: "arrow.down.circle") }
            NotificationSettings().tabItem { Label("Alertas", systemImage: "bell.badge") }
            AppearanceSettings().tabItem { Label("Menú y apariencia", systemImage: "paintpalette") }
        }
        .frame(width: 560)
        .padding(.vertical, 8)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject private var manager: VolumeManager
    @AppStorage(Prefs.Key.driverEnabled) private var driverEnabled = true
    @AppStorage(Prefs.Key.autoMount) private var autoMount = true
    @AppStorage(Prefs.Key.dirtyPolicy) private var dirtyPolicy: DirtyPolicy = .repair
    @AppStorage(Prefs.Key.hibernatedPolicy) private var hibernatedPolicy: HibernatedPolicy = .ask
    @AppStorage(Prefs.Key.verboseLogs) private var verboseLogs = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var working = false
    @State private var confirmUninstall = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Activar MacNTFS (lectura y escritura)", isOn: $driverEnabled)
                    .onChange(of: driverEnabled) { enabled in Task { await manager.setDriverEnabled(enabled) } }
                Text(driverEnabled ? "Los discos NTFS se montan con ntfs-3g en lectura y escritura."
                                   : "macOS usará su driver NTFS de solo lectura.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Montar discos NTFS automáticamente al conectarlos", isOn: $autoMount)
                    .disabled(!driverEnabled)
                Toggle("Abrir MacNTFS al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            message = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
                        }
                    }
            }
            Section("Seguridad de los datos") {
                Picker("Volumen no expulsado correctamente", selection: $dirtyPolicy) {
                    ForEach(DirtyPolicy.allCases) { Text($0.title).tag($0) }
                }
                Picker("Windows hibernado / Inicio rápido", selection: $hibernatedPolicy) {
                    ForEach(HibernatedPolicy.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Componentes") {
                LabeledContent("Capa FUSE", value: manager.fuse.name)
                LabeledContent("Componentes instalados", value: manager.componentsVersion ?? "No")
                Toggle("Registro detallado (para soporte)", isOn: $verboseLogs)
                HStack {
                    Button("Reparar componentes") {
                        Task {
                            working = true
                            let r = await manager.installComponents()
                            working = false
                            message = r.ok ? "Componentes instalados correctamente." : r.combined
                        }
                    }
                    Button("Abrir registros") { Log.revealInFinder() }
                    Spacer()
                    Button("Desinstalar…", role: .destructive) { confirmUninstall = true }
                }
                .disabled(working)
                if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .confirmationDialog("¿Desinstalar los componentes de MacNTFS?", isPresented: $confirmUninstall) {
            Button("Desinstalar", role: .destructive) {
                Task {
                    let r = await manager.uninstallComponents()
                    if r.ok {
                        message = "Componentes eliminados. Ya puedes mover MacNTFS a la Papelera."
                    } else {
                        message = r.combined
                    }
                }
            }
        } message: {
            Text("Se desmontarán los discos NTFS y macOS volverá a su driver de solo lectura. FUSE-T no se desinstala.")
        }
    }
}

struct UpdatesSettings: View {
    @AppStorage(Prefs.Key.autoUpdateCheck) private var autoCheck = true
    @AppStorage(Prefs.Key.lastUpdateCheck) private var lastCheck: Double = 0
    @State private var status: String?
    @State private var releaseURL: URL?
    @State private var checking = false

    var body: some View {
        Form {
            LabeledContent("Versión instalada", value: AppInfo.version)
            LabeledContent("Arquitectura", value: AppInfo.architecture)
            Toggle("Buscar actualizaciones automáticamente cada día", isOn: $autoCheck)
            LabeledContent("Última comprobación",
                           value: lastCheck > 0 ? Date(timeIntervalSince1970: lastCheck).formatted(date: .abbreviated, time: .shortened) : "Nunca")
            HStack {
                Button("Buscar ahora") {
                    Task {
                        checking = true
                        switch await UpdateChecker.check() {
                        case .upToDate: status = "Tienes la versión más reciente."; releaseURL = nil
                        case .available(let v, let url): status = "Disponible la versión \(v)."; releaseURL = url
                        case .failed(let e): status = "No se pudo comprobar: \(e)"
                        }
                        checking = false
                    }
                }
                .disabled(checking)
                if checking { ProgressView().controlSize(.small) }
                if let releaseURL {
                    Button("Descargar") { NSWorkspace.shared.open(releaseURL) }
                        .buttonStyle(BrandButtonStyle())
                }
            }
            if let status { Text(status).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

struct NotificationSettings: View {
    @AppStorage(Prefs.Key.notifyMount) private var notifyMount = true
    @AppStorage(Prefs.Key.notifyErrors) private var notifyErrors = true

    var body: some View {
        Form {
            Toggle("Avisar cuando un volumen se monte", isOn: $notifyMount)
            Toggle("Avisar cuando un volumen no se pueda montar", isOn: $notifyErrors)
            Text("Los avisos de disco sucio y de Windows hibernado siempre se muestran, porque requieren una decisión.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 220)
    }
}

struct AppearanceSettings: View {
    @AppStorage(Prefs.Key.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.Key.theme) private var theme: AppTheme = .system

    var body: some View {
        Form {
            Toggle("Mostrar MacNTFS en la barra de menús", isOn: $showMenuBar)
            Picker("Tema", selection: $theme) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: theme) { _ in AppTheme.apply() }
        }
        .formStyle(.grouped)
        .frame(height: 200)
    }
}
