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

import Foundation
import AppKit

enum DirtyPolicy: String, CaseIterable, Identifiable {
    case repair      // limpiar con ntfsfix y montar (recomendado)
    case recover     // dejar que ntfs-3g reinicie el registro al montar
    case readOnly    // montar en solo lectura
    case ask         // preguntar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .repair: return "Comprobar, reparar y montar (recomendado)"
        case .recover: return "Montar directamente (ntfs-3g limpia el registro)"
        case .readOnly: return "Montar en solo lectura"
        case .ask: return "Preguntar cada vez"
        }
    }
}

enum HibernatedPolicy: String, CaseIterable, Identifiable {
    case ask, readOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: return "Preguntar cada vez"
        case .readOnly: return "Montar en solo lectura (recomendado)"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Igual que el sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    static func apply() {
        let raw = UserDefaults.standard.string(forKey: Prefs.Key.theme) ?? AppTheme.system.rawValue
        switch AppTheme(rawValue: raw) ?? .system {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Prefs {
    enum Key {
        static let driverEnabled = "driverEnabled"
        static let autoMount = "autoMount"
        static let dirtyPolicy = "dirtyPolicy"
        static let hibernatedPolicy = "hibernatedPolicy"
        static let verboseLogs = "verboseLogs"
        static let autoUpdateCheck = "autoUpdateCheck"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let notifyMount = "notifyMount"
        static let notifyErrors = "notifyErrors"
        static let showMenuBar = "showMenuBar"
        static let theme = "theme"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.driverEnabled: true,
            Key.autoMount: true,
            Key.dirtyPolicy: DirtyPolicy.repair.rawValue,
            Key.hibernatedPolicy: HibernatedPolicy.ask.rawValue,
            Key.verboseLogs: false,
            Key.autoUpdateCheck: true,
            Key.notifyMount: true,
            Key.notifyErrors: true,
            Key.showMenuBar: true,
            Key.theme: AppTheme.system.rawValue
        ])
    }

    private static var d: UserDefaults { .standard }
    static var driverEnabled: Bool { d.bool(forKey: Key.driverEnabled) }
    static var autoMount: Bool { d.bool(forKey: Key.autoMount) }
    static var verboseLogs: Bool { d.bool(forKey: Key.verboseLogs) }
    static var notifyMount: Bool { d.bool(forKey: Key.notifyMount) }
    static var notifyErrors: Bool { d.bool(forKey: Key.notifyErrors) }
    static var autoUpdateCheck: Bool { d.bool(forKey: Key.autoUpdateCheck) }
    static var dirtyPolicy: DirtyPolicy { DirtyPolicy(rawValue: d.string(forKey: Key.dirtyPolicy) ?? "") ?? .repair }
    static var hibernatedPolicy: HibernatedPolicy { HibernatedPolicy(rawValue: d.string(forKey: Key.hibernatedPolicy) ?? "") ?? .ask }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var repository: String {
        Bundle.main.infoDictionary?["MacNTFSRepository"] as? String ?? "chago2850-blip/MacNTFS"
    }

    static var repositoryURL: URL { URL(string: "https://github.com/\(repository)")! }

    static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }

    static var resourcesPath: String { Bundle.main.resourcePath ?? "" }
}
