import SwiftUI

struct VerifySheet: View {
    @EnvironmentObject private var manager: VolumeManager
    @Environment(\.dismiss) private var dismiss
    let volume: Volume

    enum Phase: Equatable { case idle, running(String), done(ok: Bool, repaired: Bool) }
    @State private var phase: Phase = .idle
    @State private var log = ""
    @State private var wasMounted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "stethoscope")
                    .font(.title)
                    .foregroundStyle(Brand.gradient)
                VStack(alignment: .leading) {
                    Text("Verificar y reparar “\(volume.name)”").font(.title3.weight(.semibold))
                    Text("El volumen se desmontará durante la comprobación.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            ScrollView {
                Text(log.isEmpty ? "Pulsa Verificar para comprobar la integridad del sistema de archivos NTFS." : log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(height: 220)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            statusLine

            Text("La reparación de MacNTFS (ntfsfix) corrige errores básicos y limpia el registro de NTFS. Para daños graves usa chkdsk /f en Windows.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Cerrar") {
                    if wasMounted, let v = manager.volume(volume.id), !v.state.isMounted {
                        Task { await manager.mount(v) }
                    }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Verificar") { Task { await run(repair: false) } }
                    .disabled(isRunning)
                Button("Reparar") { Task { await run(repair: true) } }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(isRunning)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear { wasMounted = volume.state.isMounted }
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    @ViewBuilder private var statusLine: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .running(let what):
            HStack { ProgressView().controlSize(.small); Text(what) }
        case .done(let ok, let repaired):
            Label(ok ? (repaired ? "Reparación completada." : "No se encontraron errores.") : "Se encontraron problemas. Prueba Reparar.",
                  systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }

    private func run(repair: Bool) async {
        phase = .running(repair ? "Reparando…" : "Verificando…")
        log += (log.isEmpty ? "" : "\n") + "== \(repair ? "Reparación" : "Verificación") \(Date().formatted(date: .omitted, time: .standard)) ==\n"
        let result = await manager.check(volume, repair: repair)
        log += result.combined.isEmpty ? "(sin salida)\n" : result.combined + "\n"
        phase = .done(ok: result.ok, repaired: repair)
    }
}

struct EraseSheet: View {
    @EnvironmentObject private var manager: VolumeManager
    @Environment(\.dismiss) private var dismiss
    let volume: Volume

    @State private var format: EraseFormat = .ntfs
    @State private var label = ""
    @State private var wholeDisk = false
    @State private var scheme: PartitionScheme = .mbr
    @State private var confirm = false
    @State private var running = false
    @State private var resultText: String?
    @State private var success = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "eraser.fill").font(.title).foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text("Borrar “\(volume.name)”").font(.title3.weight(.semibold))
                    Text("Se eliminarán todos los datos. Esta acción no se puede deshacer.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Form {
                Picker("Formato", selection: $format) {
                    ForEach(EraseFormat.allCases) { Text($0.title).tag($0) }
                }
                TextField("Nombre", text: $label, prompt: Text("Sin título"))
                if let note = format.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if !volume.isInternal {
                    Toggle("Borrar el disco completo (\(volume.wholeDisk))", isOn: $wholeDisk)
                    if wholeDisk {
                        Picker("Esquema", selection: $scheme) {
                            ForEach(PartitionScheme.allCases) { Text($0.title).tag($0) }
                        }
                        Text("Se borrarán todas las particiones de \(volume.deviceModel.isEmpty ? volume.wholeDisk : volume.deviceModel).")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: wholeDisk ? 250 : 170)

            if let resultText {
                Label(resultText, systemImage: success ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(success ? .green : .red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            HStack {
                Button(success ? "Listo" : "Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if running { ProgressView().controlSize(.small) }
                Button("Borrar") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(running || success || trimmedLabel.count > format.maxLabelLength)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { label = volume.name }
        .confirmationDialog("¿Borrar \(wholeDisk ? "todo el disco" : "el volumen") y crear \(format.title)?",
                            isPresented: $confirm, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { Task { await erase() } }
        } message: {
            Text("Todos los datos de “\(volume.name)” se perderán.")
        }
    }

    private var trimmedLabel: String {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Sin titulo" : t
    }

    private func erase() async {
        running = true
        let finalLabel = format == .fat32 ? trimmedLabel.uppercased() : trimmedLabel
        let result = await manager.erase(volume, format: format, label: finalLabel, wholeDisk: wholeDisk, scheme: scheme)
        running = false
        success = result.ok
        if result.ok {
            resultText = "Formateado como \(format.title)."
        } else if result.status == -128 {
            resultText = "Cancelado."
        } else {
            resultText = result.combined.isEmpty ? "Error \(result.status)" : result.combined
        }
    }
}
