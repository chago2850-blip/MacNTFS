import Foundation
import AppKit
import UserNotifications

// MARK: - FUSE

/// Detecta la capa FUSE instalada. MacNTFS prefiere FUSE-T (sin extensión de núcleo).
struct FuseRuntime: Equatable {
    var fuseT: Bool
    var macFUSE: Bool
    var libfuse2: Bool

    var isInstalled: Bool { fuseT || macFUSE }
    var isReady: Bool { isInstalled && libfuse2 }

    var name: String {
        if fuseT { return "FUSE-T" }
        if macFUSE { return "macFUSE" }
        return "Ninguno"
    }

    static func detect() -> FuseRuntime {
        let fm = FileManager.default
        return FuseRuntime(
            fuseT: fm.fileExists(atPath: "/usr/local/lib/libfuse-t.dylib") || fm.fileExists(atPath: "/Library/Application Support/fuse-t"),
            macFUSE: fm.fileExists(atPath: "/Library/Filesystems/macfuse.fs"),
            libfuse2: fm.fileExists(atPath: "/usr/local/lib/libfuse.2.dylib")
        )
    }

    static let fuseTDownload = URL(string: "https://www.fuse-t.org")!
    static let fuseTReleases = URL(string: "https://github.com/macos-fuse-t/fuse-t/releases")!
    static let brewCommand = "brew install macos-fuse-t/homebrew-cask/fuse-t"
}

// MARK: - Registro

enum Log {
    private static let queue = DispatchQueue(label: "macntfs.log")
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacNTFS", isDirectory: true)
    }
    static var file: URL { directory.appendingPathComponent("macntfs.log") }

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }
    static func debug(_ message: String) { if Prefs.verboseLogs { write("DEBUG", message) } }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? NSNumber, size.intValue > 2_000_000 {
                try? fm.removeItem(at: directory.appendingPathComponent("macntfs.old.log"))
                try? fm.moveItem(at: file, to: directory.appendingPathComponent("macntfs.old.log"))
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
    }

    static func tail(maxBytes: Int = 8_000) -> String {
        guard let data = try? Data(contentsOf: file) else { return "" }
        return String(decoding: data.suffix(maxBytes), as: UTF8.self)
    }

    static func revealInFinder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}

// MARK: - Notificaciones

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { Log.debug("Notificaciones no disponibles: \(error.localizedDescription)") }
        }
    }

    static func post(_ title: String, _ body: String, isError: Bool = false) {
        let enabled = isError ? Prefs.notifyErrors : Prefs.notifyMount
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if isError { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.debug("No se pudo mostrar la notificación: \(error.localizedDescription)") }
        }
    }
}

// MARK: - Actualizaciones

struct ReleaseInfo: Decodable {
    let tag_name: String
    let html_url: String
    let name: String?
}

enum UpdateChecker {
    enum Outcome { case upToDate, available(version: String, url: URL), failed(String) }

    static func check() async -> Outcome {
        let url = URL(string: "https://api.github.com/repos/\(AppInfo.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacNTFS/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed("No hay versiones publicadas todavía.") }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Prefs.Key.lastUpdateCheck)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if isNewer(latest, than: AppInfo.version), let page = URL(string: release.html_url) {
                return .available(version: latest, url: page)
            }
            return .upToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func checkInBackgroundIfDue() {
        guard Prefs.autoUpdateCheck else { return }
        let last = UserDefaults.standard.double(forKey: Prefs.Key.lastUpdateCheck)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        Task {
            if case .available(let version, _) = await check() {
                Notifier.post("Hay una nueva versión de MacNTFS", "La versión \(version) está disponible. Ábrela desde Preferencias → Actualizaciones.")
            }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - Soporte

enum SupportReporter {
    static func openIssue() {
        let fuse = FuseRuntime.detect()
        let body = """
        **Describe el problema:**


        **Pasos para reproducirlo:**
        1.

        ---
        MacNTFS \(AppInfo.version) · \(AppInfo.architecture)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        FUSE: \(fuse.name) (libfuse2: \(fuse.libfuse2 ? "sí" : "no"))
        Componentes: \(Privileged.installedVersion() ?? "no instalados")

        <details><summary>Registro</summary>

        ```
        \(Log.tail(maxBytes: 4_000))
        ```
        </details>
        """
        var components = URLComponents(string: "https://github.com/\(AppInfo.repository)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: "[Problema] "),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
