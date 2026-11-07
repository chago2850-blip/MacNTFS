import Foundation
import DiskArbitration

/// Observa la conexión y desconexión de discos con DiskArbitration (sin privilegios).
final class DiskMonitor {
    private var session: DASession?
    private(set) var descriptions: [String: [String: Any]] = [:]
    private(set) var firstSeen: [String: Date] = [:]
    var onChange: (() -> Void)?

    func start() {
        guard session == nil, let s = DASessionCreate(kCFAllocatorDefault) else { return }
        session = s
        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(s, nil, { disk, ctx in
            guard let monitor = DiskMonitor.from(ctx) else { return }
            monitor.update(disk)
        }, context)

        DARegisterDiskDisappearedCallback(s, nil, { disk, ctx in
            guard let monitor = DiskMonitor.from(ctx) else { return }
            monitor.remove(disk)
        }, context)

        DARegisterDiskDescriptionChangedCallback(s, nil, nil, { disk, _, ctx in
            guard let monitor = DiskMonitor.from(ctx) else { return }
            monitor.update(disk)
        }, context)

        DASessionScheduleWithRunLoop(s, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Vuelve a leer la descripción de todos los discos conocidos.
    func reloadAll() {
        guard let s = session else { return }
        for name in Array(descriptions.keys) {
            guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, s, name) else { continue }
            if let desc = DADiskCopyDescription(disk) as? [String: Any] {
                descriptions[name] = desc
            }
        }
        onChange?()
    }

    private static func from(_ ctx: UnsafeMutableRawPointer?) -> DiskMonitor? {
        guard let ctx else { return nil }
        return Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue()
    }

    private static func bsdName(_ disk: DADisk) -> String? {
        guard let c = DADiskGetBSDName(disk) else { return nil }
        return String(cString: c)
    }

    fileprivate func update(_ disk: DADisk) {
        guard let name = DiskMonitor.bsdName(disk),
              let desc = DADiskCopyDescription(disk) as? [String: Any] else { return }
        descriptions[name] = desc
        if firstSeen[name] == nil { firstSeen[name] = Date() }
        onChange?()
    }

    fileprivate func remove(_ disk: DADisk) {
        guard let name = DiskMonitor.bsdName(disk) else { return }
        descriptions.removeValue(forKey: name)
        firstSeen.removeValue(forKey: name)
        onChange?()
    }
}

/// Acceso tipado a las claves de la descripción de DiskArbitration.
struct DiskDescription {
    let raw: [String: Any]

    func string(_ key: CFString) -> String? { raw[key as String] as? String }
    func bool(_ key: CFString) -> Bool { (raw[key as String] as? Bool) ?? ((raw[key as String] as? NSNumber)?.boolValue ?? false) }
    func int64(_ key: CFString) -> Int64 { (raw[key as String] as? NSNumber)?.int64Value ?? 0 }

    var volumeKind: String? { string(kDADiskDescriptionVolumeKindKey) }
    var volumeName: String? { string(kDADiskDescriptionVolumeNameKey) }
    var mediaSize: Int64 { int64(kDADiskDescriptionMediaSizeKey) }
    var isWhole: Bool { bool(kDADiskDescriptionMediaWholeKey) }
    var isInternal: Bool { bool(kDADiskDescriptionDeviceInternalKey) }
    var isRemovable: Bool { bool(kDADiskDescriptionMediaRemovableKey) }
    var isEjectable: Bool { bool(kDADiskDescriptionMediaEjectableKey) }
    var isWritable: Bool { bool(kDADiskDescriptionMediaWritableKey) }
    var deviceModel: String { (string(kDADiskDescriptionDeviceModelKey) ?? string(kDADiskDescriptionMediaNameKey) ?? "").trimmingCharacters(in: .whitespaces) }
    var protocolName: String { string(kDADiskDescriptionDeviceProtocolKey) ?? "" }

    var volumePath: String? {
        guard let value = raw[kDADiskDescriptionVolumePathKey as String] else { return nil }
        if let url = value as? URL { return url.path }
        if let url = value as? NSURL { return url.path }
        return nil
    }

    var volumeUUID: String? {
        guard let value = raw[kDADiskDescriptionVolumeUUIDKey as String] else { return nil }
        let cf = value as CFTypeRef
        guard CFGetTypeID(cf) == CFUUIDGetTypeID() else { return nil }
        let uuid = unsafeBitCast(cf, to: CFUUID.self)
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }
}
