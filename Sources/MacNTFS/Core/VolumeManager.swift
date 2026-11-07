import Foundation
import AppKit
import SwiftUI

/// Orquesta todo: lista de volúmenes, montaje automático, políticas de seguridad y operaciones.
@MainActor
final class VolumeManager: ObservableObject {
    @Published private(set) var volumes: [Volume] = []
    @Published private(set) var busy: Set<String> = []
    @Published var issues: [String: MountIssue] = [:]
    @Published private(set) var fuse = FuseRuntime.detect()
    @Published private(set) var componentsVersion: String? = Privileged.installedVersion()
    @Published var toast: String?

    private let monitor = DiskMonitor()
    private var handled = Set<String>()          // volúmenes ya procesados por el montaje automático
    private var ourMounts: [String: String] = [:] // bsd → punto de montaje creado por MacNTFS
    private var timer: Timer?

    init() {
        monitor.onChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        UpdateChecker.checkInBackgroundIfDue()
    }

    // MARK: Estado general

    var componentsInstalled: Bool { componentsVersion != nil }
    var componentsOutdated: Bool { componentsVersion != nil && componentsVersion != AppInfo.version && AppInfo.version != "dev" }
    var isReady: Bool { fuse.isReady && componentsInstalled }
    var ntfsVolumes: [Volume] { volumes.filter(\.isNTFS) }
    var otherVolumes: [Volume] { volumes.filter { !$0.isNTFS } }
    var hasReadWriteMounts: Bool { volumes.contains { $0.isNTFS && $0.state == .readWrite } }

    func volume(_ id: String?) -> Volume? {
        guard let id else { return nil }
        return volumes.first { $0.id == id }
    }

    func refreshEnvironment() {
        fuse = FuseRuntime.detect()
        componentsVersion = Privileged.installedVersion()
    }

    func refreshAll() {
        refreshEnvironment()
        monitor.reloadAll()
        refresh()
    }

    // MARK: Construcción de la lista

    func refresh() {
        let mounts = MountTable.read()
        let rootDevice = mounts.first(where: { $0.mountPoint == "/" })?.from ?? ""
        var list: [Volume] = []

        for (bsd, raw) in monitor.descriptions {
            let desc = DiskDescription(raw: raw)
            guard let kind = desc.volumeKind, !kind.isEmpty, !desc.isWhole else { continue }
            let whole = bsd.replacingOccurrences(of: #"s\d+(s\d+)?$"#, with: "", options: .regularExpression)

            // ¿Dónde está montado?
            var entry: MountEntry?
            if let path = desc.volumePath {
                entry = mounts.first { $0.mountPoint == path }
            }
            if entry == nil, let ours = ourMounts[bsd] {
                entry = mounts.first { $0.mountPoint == ours }
                if entry == nil { ourMounts.removeValue(forKey: bsd) }
            }
            if entry == nil {
                entry = mounts.first { $0.from == "/dev/\(bsd)" || $0.from.hasSuffix("/\(bsd)") }
            }

            let isNTFS = kind.lowercased() == "ntfs"
            // Ocultar volúmenes internos que no son NTFS (sistema, datos, recuperación…)
            if !isNTFS && desc.isInternal { continue }

            var state: MountState = .unmounted
            if let e = entry {
                if isNTFS && (e.fsType == "ntfs" || e.fsType == "ufsd_NTFS") && e.readOnly {
                    state = .appleReadOnly
                } else {
                    state = e.readOnly ? .readOnly : .readWrite
                }
            }

            list.append(Volume(
                bsdName: bsd,
                wholeDisk: whole,
                name: desc.volumeName ?? "Sin nombre",
                uuid: desc.volumeUUID,
                kind: kind,
                size: desc.mediaSize,
                isInternal: desc.isInternal,
                isRemovable: desc.isRemovable,
                isEjectable: desc.isEjectable,
                isWritableMedia: desc.isWritable,
                deviceModel: desc.deviceModel,
                protocolName: desc.protocolName,
                mountPoint: entry?.mountPoint,
                mountFSType: entry?.fsType,
                totalBytes: entry?.totalBytes,
                freeBytes: entry?.freeBytes,
                isBoot: entry?.mountPoint == "/" || rootDevice.hasPrefix("/dev/\(bsd)"),
                state: state
            ))
        }

        list.sort {
            if $0.isNTFS != $1.isNTFS { return $0.isNTFS }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if list != volumes { volumes = list }

        let ids = Set(list.map(\.id))
        handled = handled.intersection(ids)
        issues = issues.filter { ids.contains($0.key) }
        autoMountIfNeeded()
    }

    // MARK: Montaje automático

    private func autoMountIfNeeded() {
        guard isReady, Prefs.driverEnabled, Prefs.autoMount else { return }
        for v in volumes where v.isNTFS && !v.isBoot && !handled.contains(v.id) && !busy.contains(v.id) {
            // Esperar a que macOS termine su propio montaje antes de tomar el control.
            if let seen = monitor.firstSeen[v.id], Date().timeIntervalSince(seen) < 2 { continue }
            handled.insert(v.id)
            let options = OptionsStore.load(v.optionsKey)
            if options.noAutomount { continue }
            if v.state == .appleReadOnly || v.state == .unmounted {
                Log.info("Montaje automático de \(v.name) (\(v.bsdName))")
                Task { await self.mount(v, interactive: false) }
            }
        }
    }

    // MARK: Operaciones

    @discardableResult
    func mount(_ v: Volume, interactive: Bool = true, forceReadOnly: Bool = false,
               removeHiberfile: Bool = false, skipDirtyCheck: Bool = false, depth: Int = 0) async -> Bool {
        guard depth < 3 else { return false }
        guard isReady else {
            issues[v.id] = fuse.isReady ? .notInstalled : .fuseError
            return false
        }
        handled.insert(v.id)
        busy.insert(v.id)
        defer { busy.remove(v.id) }

        let options = OptionsStore.load(v.optionsKey)
        let policy = Prefs.dirtyPolicy
        var flags: [String] = []
        if options.readOnly || forceReadOnly { flags.append("ro") }
        if !options.saveLastAccess { flags.append("noatime") }
        if options.ignoreOwnership { flags.append("ignore_owner") }
        if policy != .recover && !skipDirtyCheck && !flags.contains("ro") { flags.append("norecover") }
        if removeHiberfile { flags.append("remove_hiberfile") }

        let mountPoint = mountPointFor(v)
        let result = await Privileged.helper(["mount", v.bsdName, mountPoint, v.name,
                                              String(getuid()), String(getgid())] + flags)
        if result.ok {
            ourMounts[v.id] = mountPoint
            issues[v.id] = nil
            Log.info("Montado \(v.name) en \(mountPoint) [\(flags.joined(separator: ","))]")
            let mode = flags.contains("ro") ? "solo lectura" : "lectura y escritura"
            Notifier.post("\(v.name) está listo", "Montado en \(mode) con MacNTFS.")
            if options.spotlight { _ = await Privileged.helper(["spotlight", mountPoint, "on"]) }
            refresh()
            return true
        }

        let issue = MountIssue(code: result.status, output: result.combined)
        Log.error("Fallo al montar \(v.bsdName): \(result.status) \(result.combined)")

        switch issue {
        case .unclean:
            switch policy {
            case .repair:
                let fix = await Privileged.helper(["repair", v.bsdName])
                if fix.ok {
                    Log.info("Registro NTFS limpiado en \(v.bsdName)")
                    return await mount(v, interactive: interactive, skipDirtyCheck: true, depth: depth + 1)
                }
                return await mount(v, interactive: interactive, forceReadOnly: true, depth: depth + 1)
            case .readOnly:
                return await mount(v, interactive: interactive, forceReadOnly: true, depth: depth + 1)
            case .ask, .recover:
                switch Decision.askUnclean(v) {
                case .primary:
                    let fix = await Privileged.helper(["repair", v.bsdName])
                    return await mount(v, interactive: interactive, skipDirtyCheck: fix.ok, depth: depth + 1)
                case .secondary:
                    return await mount(v, interactive: interactive, forceReadOnly: true, depth: depth + 1)
                case .cancel:
                    issues[v.id] = issue
                    return false
                }
            }
        case .hibernated:
            if Prefs.hibernatedPolicy == .readOnly && !removeHiberfile {
                issues[v.id] = issue
                return await mount(v, interactive: interactive, forceReadOnly: true, depth: depth + 1)
            }
            switch Decision.askHibernated(v) {
            case .primary:
                issues[v.id] = issue
                return await mount(v, interactive: interactive, forceReadOnly: true, depth: depth + 1)
            case .secondary:
                return await mount(v, interactive: interactive, removeHiberfile: true, depth: depth + 1)
            case .cancel:
                issues[v.id] = issue
                return false
            }
        case .cancelled:
            return false
        default:
            issues[v.id] = issue
            Notifier.post("No se pudo montar \(v.name)", issue.title, isError: true)
            if interactive { Decision.showError(issue, volume: v) }
            refresh()
            return false
        }
    }

    @discardableResult
    func unmount(_ v: Volume, force: Bool = false) async -> Bool {
        guard let mp = v.mountPoint else { return true }
        busy.insert(v.id)
        defer { busy.remove(v.id) }
        handled.insert(v.id) // no volver a montarlo solo
        var args = ["unmount", mp]
        if force { args.append("force") }
        let result = await Privileged.helper(args)
        ourMounts.removeValue(forKey: v.id)
        refresh()
        if !result.ok {
            let issue = MountIssue(code: result.status, output: result.combined)
            issues[v.id] = issue
            Log.error("Fallo al desmontar \(v.bsdName): \(result.combined)")
            if !force, Decision.askForceUnmount(v) {
                return await unmount(v, force: true)
            }
            return false
        }
        issues[v.id] = nil
        Log.info("Desmontado \(v.name)")
        return true
    }

    func toggleMount(_ v: Volume) async {
        switch v.state {
        case .readWrite, .readOnly:
            await unmount(v)
        case .appleReadOnly, .unmounted:
            if v.isNTFS {
                await mount(v)
            } else {
                _ = await Shell.run("/usr/sbin/diskutil", ["mount", v.bsdName])
                refresh()
            }
        }
    }

    func remount(_ v: Volume) async {
        if v.state.isMounted {
            guard await unmount(v) else { return }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let fresh = volume(v.id) { await mount(fresh) }
    }

    func eject(_ v: Volume) async {
        for other in volumes where other.wholeDisk == v.wholeDisk && other.state.isMounted {
            guard await unmount(other) else { return }
        }
        let result = await Shell.run("/usr/sbin/diskutil", ["eject", v.wholeDisk])
        if result.ok {
            toast = "Puedes desconectar \(v.deviceModel.isEmpty ? v.name : v.deviceModel) con seguridad."
        } else {
            issues[v.id] = .other(code: result.status, message: result.combined)
        }
        refresh()
    }

    /// Verifica (solo lectura) o repara. El volumen se desmonta antes.
    func check(_ v: Volume, repair: Bool) async -> ShellResult {
        busy.insert(v.id)
        defer { busy.remove(v.id) }
        if let current = volume(v.id), current.state.isMounted {
            busy.remove(v.id)
            guard await unmount(current) else {
                return ShellResult(status: 66, stdout: "", stderr: "No se pudo desmontar el volumen. Cierra los archivos abiertos.")
            }
            busy.insert(v.id)
        }
        let result = await Privileged.helper([repair ? "repair" : "verify", v.bsdName])
        Log.info("\(repair ? "Reparación" : "Verificación") de \(v.bsdName): código \(result.status)")
        if repair && result.ok { issues[v.id] = nil }
        refresh()
        return result
    }

    func erase(_ v: Volume, format: EraseFormat, label: String, wholeDisk: Bool, scheme: PartitionScheme) async -> ShellResult {
        busy.insert(v.id)
        defer { busy.remove(v.id) }
        let args: [String]
        if wholeDisk {
            args = [Privileged.helperPath, "formatdisk", v.wholeDisk, scheme.rawValue, format.rawValue, label]
        } else {
            args = [Privileged.helperPath, "format", v.bsdName, format.rawValue, label]
        }
        let target = wholeDisk ? "el disco \(v.wholeDisk)" : "el volumen \(v.name)"
        let result = await Privileged.admin(args, prompt: "MacNTFS va a borrar \(target). Se perderán todos sus datos.")
        Log.info("Formateo \(args.dropFirst().joined(separator: " ")): código \(result.status)")
        handled.remove(v.id)
        ourMounts.removeValue(forKey: v.id)
        monitor.reloadAll()
        return result
    }

    func options(for v: Volume) -> VolumeOptions { OptionsStore.load(v.optionsKey) }

    func setOptions(_ new: VolumeOptions, for v: Volume) {
        let old = OptionsStore.load(v.optionsKey)
        guard new != old else { return }
        OptionsStore.save(new, for: v.optionsKey)
        objectWillChange.send()
        Task {
            if new.spotlight != old.spotlight, let mp = v.mountPoint {
                _ = await Privileged.helper(["spotlight", mp, new.spotlight ? "on" : "off"])
            }
            if v.isNTFS, v.state == .readWrite || v.state == .readOnly, new.requiresRemount(comparedTo: old) {
                await remount(v)
            }
        }
    }

    // MARK: Driver y componentes

    func installComponents() async -> ShellResult {
        let result = await Privileged.installComponents()
        refreshEnvironment()
        handled.removeAll()
        refresh()
        return result
    }

    func uninstallComponents() async -> ShellResult {
        for v in volumes where v.isNTFS && (v.state == .readWrite || v.state == .readOnly) {
            await unmount(v)
        }
        let result = await Privileged.uninstallComponents()
        refreshEnvironment()
        return result
    }

    /// Al desactivar el driver, los volúmenes vuelven al driver de Apple (solo lectura).
    func setDriverEnabled(_ enabled: Bool) async {
        if enabled {
            handled.removeAll()
            refresh()
        } else {
            for v in volumes where v.isNTFS && (v.state == .readWrite || v.state == .readOnly) {
                if await unmount(v) {
                    _ = await Shell.run("/usr/sbin/diskutil", ["mount", v.bsdName])
                }
            }
            refresh()
        }
    }

    // MARK: Utilidades

    private func mountPointFor(_ v: Volume) -> String {
        let clean = v.name
            .replacingOccurrences(of: "/", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "/Volumes/" + (clean.isEmpty || clean == "." || clean == ".." ? v.bsdName : clean)
        let used = Set(MountTable.read().map(\.mountPoint))
        if !used.contains(base) || v.mountPoint == base { return base }
        return "\(base) (\(v.bsdName))"
    }
}

// MARK: - Diálogos de decisión (funcionan aunque la ventana esté cerrada)

enum Decision {
    enum Choice { case primary, secondary, cancel }

    @MainActor
    private static func run(_ title: String, _ text: String, primary: String, secondary: String?, style: NSAlert.Style = .warning) -> Choice {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: primary)
        if let secondary { alert.addButton(withTitle: secondary) }
        alert.addButton(withTitle: "Cancelar")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .primary
        case .alertSecondButtonReturn: return secondary == nil ? .cancel : .secondary
        default: return .cancel
        }
    }

    @MainActor
    static func askUnclean(_ v: Volume) -> Choice {
        run("“\(v.name)” no se expulsó correctamente",
            MountIssue.unclean.detail,
            primary: "Reparar y montar", secondary: "Montar en solo lectura")
    }

    @MainActor
    static func askHibernated(_ v: Volume) -> Choice {
        run("Windows está hibernado en “\(v.name)”",
            MountIssue.hibernated.detail + "\n\nSi eliges escribir de todas formas se descartará la sesión hibernada de Windows.",
            primary: "Montar en solo lectura", secondary: "Descartar hibernación y montar")
    }

    @MainActor
    static func askForceUnmount(_ v: Volume) -> Bool {
        run("“\(v.name)” está en uso",
            "Alguna app tiene archivos abiertos en este volumen. Forzar el desmontaje puede causar pérdida de datos no guardados.",
            primary: "Forzar desmontaje", secondary: nil, style: .critical) == .primary
    }

    @MainActor
    static func showError(_ issue: MountIssue, volume v: Volume) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "No se pudo montar “\(v.name)”: \(issue.title)"
        alert.informativeText = issue.detail
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.runModal()
    }
}
