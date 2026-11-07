import Foundation

struct ShellResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
    var combined: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum Shell {
    /// Ejecuta un programa sin pasar por un shell (los argumentos nunca se interpretan).
    static func run(_ path: String, _ arguments: [String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(path, arguments))
            }
        }
    }

    static func runSync(_ path: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ShellResult(status: 127, stdout: "", stderr: error.localizedDescription)
        }

        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        let result = ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if Prefs.verboseLogs {
            Log.debug("$ \(path) \(arguments.joined(separator: " ")) → \(result.status)\n\(result.combined)")
        }
        return result
    }

    /// Comillas simples seguras para /bin/sh.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
