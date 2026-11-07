import Foundation

/// Estado de montaje de un volumen.
enum MountState: Equatable {
    case unmounted
    case appleReadOnly      // montado por el driver de Apple (solo lectura)
    case readOnly           // montado por MacNTFS en solo lectura
    case readWrite          // montado por MacNTFS en lectura/escritura

    var title: String {
        switch self {
        case .unmounted: return "Sin montar"
        case .appleReadOnly: return "Solo lectura (macOS)"
        case .readOnly: return "Solo lectura"
        case .readWrite: return "Lectura y escritura"
        }
    }

    var isMounted: Bool { self != .unmounted }
}

/// Un volumen (partición) visto por DiskArbitration más la tabla de montajes.
struct Volume: Identifiable, Equatable, Hashable {
    var id: String { bsdName }
    let bsdName: String            // disk4s1
    let wholeDisk: String          // disk4
    var name: String
    var uuid: String?
    var kind: String               // ntfs, msdos, exfat, hfs, apfs…
    var size: Int64
    var isInternal: Bool
    var isRemovable: Bool
    var isEjectable: Bool
    var isWritableMedia: Bool
    var deviceModel: String
    var protocolName: String
    var mountPoint: String?
    var mountFSType: String?
    var totalBytes: Int64?
    var freeBytes: Int64?
    var isBoot: Bool
    var state: MountState

    var isNTFS: Bool { kind.lowercased() == "ntfs" }
    var optionsKey: String { uuid ?? bsdName }

    var kindTitle: String {
        switch kind.lowercased() {
        case "ntfs": return "NTFS"
        case "msdos": return "FAT32"
        case "exfat": return "exFAT"
        case "hfs": return "Mac OS Plus"
        case "apfs": return "APFS"
        case "ufsd_ntfs": return "NTFS"
        default: return kind.uppercased()
        }
    }

    var driverTitle: String {
        switch state {
        case .unmounted: return "—"
        case .appleReadOnly: return "Driver de Apple (solo lectura)"
        case .readOnly, .readWrite: return isNTFS ? "MacNTFS · ntfs-3g" : "macOS"
        }
    }

    var usedFraction: Double? {
        guard let total = totalBytes, let free = freeBytes, total > 0 else { return nil }
        return Double(total - free) / Double(total)
    }

    var canMountOperations: Bool { !isBoot }
    var canErase: Bool { !isBoot && isWritableMedia }
    var canVerify: Bool { isNTFS && !isBoot }
}

/// Opciones por volumen (se guardan por UUID para que sobrevivan a reconexiones).
struct VolumeOptions: Codable, Equatable {
    var readOnly = false
    var noAutomount = false
    var ignoreOwnership = false
    var saveLastAccess = true
    var spotlight = false

    /// Opciones que requieren volver a montar el volumen para aplicarse.
    func requiresRemount(comparedTo other: VolumeOptions) -> Bool {
        readOnly != other.readOnly || ignoreOwnership != other.ignoreOwnership || saveLastAccess != other.saveLastAccess
    }
}

enum OptionsStore {
    private static let key = "volumeOptions"

    static func load(_ volumeKey: String) -> VolumeOptions {
        all()[volumeKey] ?? VolumeOptions()
    }

    static func save(_ options: VolumeOptions, for volumeKey: String) {
        var dict = all()
        dict[volumeKey] = options
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func all() -> [String: VolumeOptions] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: VolumeOptions].self, from: data) else { return [:] }
        return dict
    }
}

/// Motivos por los que ntfs-3g se niega a montar (códigos de salida de ntfs-3g, volume.h).
enum MountIssue: Equatable {
    case syntax
    case notNTFS
    case corrupt
    case hibernated
    case unclean
    case locked
    case raid
    case noPrivilege
    case fuseError
    case busy
    case notInstalled
    case cancelled
    case fullDiskAccess
    case other(code: Int32, message: String)

    init(code: Int32, output: String) {
        let lower = output.lowercased()
        if FullDiskAccess.isPermissionError(output) {
            self = .fullDiskAccess
            return
        }
        switch code {
        case 11: self = .syntax
        case 12: self = .notNTFS
        case 13: self = .corrupt
        case 14: self = .hibernated
        case 15: self = .unclean
        case 16: self = .locked
        case 17: self = .raid
        case 19: self = .noPrivilege
        case 21: self = .fuseError
        case 66: self = .busy
        case 65: self = .notInstalled
        case -128: self = .cancelled
        default:
            if lower.contains("hibernat") || lower.contains("fast restart") || lower.contains("inicio rápido") {
                self = .hibernated
            } else if lower.contains("unclean") || lower.contains("not unmounted properly") {
                self = .unclean
            } else if lower.contains("bitlocker") || lower.contains("-fve-fs-") {
                self = .locked
            } else if lower.contains("fuse") && (lower.contains("not found") || lower.contains("library not loaded")) {
                self = .fuseError
            } else {
                self = .other(code: code, message: output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    var title: String {
        switch self {
        case .syntax: return "Opciones de montaje no válidas"
        case .notNTFS: return "El volumen no es NTFS"
        case .corrupt: return "El volumen NTFS está dañado"
        case .hibernated: return "Windows está hibernado o con Inicio rápido"
        case .unclean: return "El volumen no se expulsó correctamente"
        case .locked: return "El volumen está cifrado (BitLocker)"
        case .raid: return "Volumen RAID / dinámico no compatible"
        case .noPrivilege: return "Faltan permisos para acceder al disco"
        case .fuseError: return "FUSE no está disponible"
        case .busy: return "El volumen está en uso"
        case .notInstalled: return "Faltan componentes de MacNTFS"
        case .cancelled: return "Operación cancelada"
        case .fullDiskAccess: return "MacNTFS necesita Acceso total al disco"
        case .other: return "No se pudo completar la operación"
        }
    }

    var detail: String {
        switch self {
        case .hibernated:
            return "Windows dejó el disco en uso. Escribir en él podría perder datos. Apaga Windows por completo (Shift + Apagar) o desactiva el Inicio rápido; mientras tanto puedes montarlo en solo lectura."
        case .unclean:
            return "El disco se desconectó sin expulsarlo. MacNTFS puede limpiar el registro de NTFS y montarlo, o montarlo en solo lectura."
        case .corrupt:
            return "Prueba con Verificar / Reparar. Si el daño es grave, ejecuta chkdsk /f en Windows."
        case .locked:
            return "Desbloquea el volumen con BitLocker en Windows o desactiva el cifrado para usarlo en el Mac."
        case .fuseError:
            return "Instala FUSE-T (recomendado) o macFUSE y luego pulsa Reparar componentes en Preferencias."
        case .busy:
            return "Cierra los archivos y apps que usen el volumen y vuelve a intentarlo."
        case .notInstalled:
            return "Abre la ventana principal de MacNTFS y completa la configuración inicial."
        case .noPrivilege:
            return "Reinstala los componentes de MacNTFS desde Preferencias → General."
        case .fullDiskAccess:
            return "macOS bloqueó el acceso directo al disco. Activa MacNTFS en Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco, cierra MacNTFS y vuelve a abrirlo."
        case .other(let code, let message):
            return message.isEmpty ? "Código de error \(code)." : "\(message) (código \(code))"
        default:
            return ""
        }
    }
}

enum EraseFormat: String, CaseIterable, Identifiable {
    case ntfs, exfat, fat32, hfs, apfs
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ntfs: return "Windows NT (NTFS)"
        case .exfat: return "exFAT"
        case .fat32: return "MS-DOS (FAT32)"
        case .hfs: return "Mac OS Plus (con registro)"
        case .apfs: return "APFS"
        }
    }

    var maxLabelLength: Int {
        switch self {
        case .fat32: return 11
        case .ntfs: return 32
        default: return 63
        }
    }

    var note: String? {
        switch self {
        case .fat32: return "FAT32 no admite archivos de más de 4 GB."
        case .ntfs: return "Compatible con Windows; MacNTFS lo lee y escribe en el Mac."
        case .exfat: return "Compatible con Windows y macOS sin drivers, sin permisos ni registro."
        default: return nil
        }
    }
}

enum PartitionScheme: String, CaseIterable, Identifiable {
    case mbr, gpt
    var id: String { rawValue }
    var title: String { self == .mbr ? "Registro de arranque maestro (MBR)" : "Tabla de particiones GUID (GPT)" }
}
