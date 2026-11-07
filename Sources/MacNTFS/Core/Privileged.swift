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

/// Componentes privilegiados instalados una sola vez con contraseña de administrador:
///   /usr/local/libexec/macntfs/macntfs-helper   (raíz, valida todos los argumentos)
///   /usr/local/libexec/macntfs/bin/ntfs-3g, mkntfs, ntfsfix, ntfslabel, ntfsinfo
///   /etc/sudoers.d/macntfs                      (montar, desmontar, verificar y reparar sin contraseña)
/// Formatear siempre vuelve a pedir la contraseña.
enum Privileged {
    static let base = "/usr/local/libexec/macntfs"
    static let helperPath = base + "/macntfs-helper"

    static func installedVersion() -> String? {
        guard let text = try? String(contentsOfFile: base + "/VERSION", encoding: .utf8) else { return nil }
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static var helperExists: Bool { FileManager.default.isExecutableFile(atPath: helperPath) }

    /// Ejecuta el ayudante con sudo sin contraseña; si no está permitido, pide la contraseña.
    static func helper(_ args: [String], prompt: String = "MacNTFS necesita permiso para acceder al disco.") async -> ShellResult {
        guard helperExists else {
            return ShellResult(status: 65, stdout: "", stderr: "El ayudante de MacNTFS no está instalado.")
        }
        let result = await Shell.run("/usr/bin/sudo", ["-n", helperPath] + args)
        if result.status == 1, result.stderr.lowercased().contains("password") || result.stderr.lowercased().contains("contraseña") {
            Log.info("sudo sin contraseña no disponible; se solicitará autorización")
            return await admin([helperPath] + args, prompt: prompt)
        }
        return result
    }

    /// Ejecuta un comando como administrador mostrando el diálogo de contraseña de macOS.
    static func admin(_ argv: [String], prompt: String) async -> ShellResult {
        let command = argv.map(Shell.quote).joined(separator: " ")
        let script = "do shell script \"\(appleScriptEscape(command))\" with prompt \"\(appleScriptEscape(prompt))\" with administrator privileges"
        var result = await Shell.run("/usr/bin/osascript", ["-e", script])
        result.stdout = result.stdout.replacingOccurrences(of: "\r", with: "\n")
        if !result.ok {
            // osascript: "execution error: <mensaje> (<código>)"
            let message = result.stderr
            if let range = message.range(of: #"\((-?\d+)\)\s*$"#, options: .regularExpression) {
                let digits = message[range].trimmingCharacters(in: CharacterSet(charactersIn: "() \n"))
                result.status = Int32(digits) ?? result.status
            }
            result.stderr = message
                .replacingOccurrences(of: #"^.*execution error: "#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\r", with: "\n")
        }
        return result
    }

    static func installComponents() async -> ShellResult {
        let res = AppInfo.resourcesPath
        let script = res + "/helper/install.sh"
        return await admin(["/bin/bash", script, res, NSUserName(), AppInfo.version],
                           prompt: "MacNTFS va a instalar sus componentes para leer y escribir discos NTFS.")
    }

    static func uninstallComponents() async -> ShellResult {
        let script = AppInfo.resourcesPath + "/helper/uninstall.sh"
        return await admin(["/bin/bash", script], prompt: "MacNTFS va a desinstalar sus componentes.")
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
