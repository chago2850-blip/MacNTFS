import Foundation
import Darwin

struct MountEntry: Equatable {
    let from: String
    let mountPoint: String
    let fsType: String
    let readOnly: Bool
    let totalBytes: Int64
    let freeBytes: Int64
}

/// Lee los sistemas de archivos montados (incluye montajes FUSE, que DiskArbitration no ve).
enum MountTable {
    static func read() -> [MountEntry] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [] }
        var entries: [MountEntry] = []
        entries.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            var s = buffer[i]
            let from = cString(&s.f_mntfromname)
            let on = cString(&s.f_mntonname)
            let type = cString(&s.f_fstypename)
            let bsize = Int64(s.f_bsize)
            entries.append(MountEntry(
                from: from,
                mountPoint: on,
                fsType: type,
                readOnly: (s.f_flags & UInt32(MNT_RDONLY)) != 0,
                totalBytes: Int64(s.f_blocks) * bsize,
                freeBytes: Int64(s.f_bavail) * bsize
            ))
        }
        return entries
    }

    static var rootDevice: String? {
        read().first(where: { $0.mountPoint == "/" })?.from
    }

    private static func cString<T>(_ tuple: inout T) -> String {
        withUnsafePointer(to: &tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
