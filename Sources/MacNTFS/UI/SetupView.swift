import SwiftUI
import AppKit

/// Configuración inicial: 1) FUSE-T, 2) componentes de MacNTFS. Sin reinicios ni modo Recuperación.
struct SetupView: View {
    @EnvironmentObject private var manager: VolumeManager
    @State private var installing = false
    @State private var message: String?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AppLogo(size: 112)
                    .shadow(color: .brandViolet.opacity(0.35), radius: 18, y: 8)
                VStack(spacing: 6) {
                    Text("Bienvenido a MacNTFS").font(.largeTitle.weight(.bold))
                    Text("Tres pasos y tus discos de Windows funcionarán en Finder con lectura y escritura.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                step(number: 1,
                     title: "Instala FUSE-T",
                     done: manager.fuse.isInstalled,
                     detail: manager.fuse.isInstalled
                        ? "Detectado: \(manager.fuse.name)."
                        : "FUSE-T es gratuito y no usa extensiones de núcleo: no hace falta reducir la seguridad del Mac.") {
                    if !manager.fuse.isInstalled {
                        HStack {
                            Button("Descargar FUSE-T") { NSWorkspace.shared.open(FuseRuntime.fuseTReleases) }
                                .buttonStyle(BrandButtonStyle())
                            Button(copied ? "¡Copiado!" : "Copiar comando de Homebrew") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(FuseRuntime.brewCommand, forType: .string)
                                copied = true
                            }
                        }
                        Text(FuseRuntime.brewCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if manager.fuse.macFUSE && !manager.fuse.fuseT {
                        Text("Con macFUSE en Mac con chip Apple tendrás que aprobar su extensión del sistema. FUSE-T evita ese paso.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                step(number: 2,
                     title: manager.componentsOutdated ? "Actualiza los componentes de MacNTFS" : "Instala los componentes de MacNTFS",
                     done: manager.componentsInstalled && !manager.componentsOutdated && manager.fuse.libfuse2,
                     detail: "Copia el motor ntfs-3g y el ayudante de montaje. Se pide tu contraseña de administrador una sola vez.") {
                    HStack {
                        Button(manager.componentsInstalled ? "Reparar componentes" : "Instalar componentes") {
                            Task {
                                installing = true
                                let r = await manager.installComponents()
                                installing = false
                                message = r.ok ? nil : (r.status == -128 ? "Instalación cancelada." : r.combined)
                            }
                        }
                        .buttonStyle(BrandButtonStyle())
                        .disabled(!manager.fuse.isInstalled || installing)
                        if installing { ProgressView().controlSize(.small) }
                    }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }

                step(number: 3,
                     title: "Permite el Acceso total al disco",
                     done: manager.hasFullDiskAccess,
                     detail: "macOS solo deja escribir directamente en un disco externo a las apps con este permiso. Sin él no se puede montar en escritura, reparar ni formatear.") {
                    if !manager.hasFullDiskAccess {
                        Button("Abrir Acceso total al disco") { FullDiskAccess.openSettings() }
                            .buttonStyle(BrandButtonStyle())
                        Text("Activa MacNTFS en la lista (si no aparece, agrégalo con +). Después cierra MacNTFS y vuelve a abrirlo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button {
                    manager.refreshAll()
                } label: {
                    Label("Comprobar de nuevo", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.link)

                if manager.isReady && !manager.componentsOutdated {
                    Label("¡Todo listo! Conecta un disco NTFS.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                }
            }
            .padding(32)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func step<Extra: View>(number: Int, title: String, done: Bool, detail: String,
                                   @ViewBuilder extra: () -> Extra) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(done ? AnyShapeStyle(Color.green) : AnyShapeStyle(Brand.gradient))
                        .frame(width: 34, height: 34)
                    if done {
                        Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(.headline.weight(.bold)).foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                    extra()
                }
            }
        }
    }
}
