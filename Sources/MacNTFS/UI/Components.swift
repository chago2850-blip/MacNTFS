import SwiftUI
import AppKit

extension Color {
    static let brandTeal = Color(red: 0.37, green: 0.92, blue: 0.83)
    static let brandSky = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let brandViolet = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let brandNavy = Color(red: 0.06, green: 0.10, blue: 0.28)
}

enum Brand {
    static let gradient = LinearGradient(colors: [.brandTeal, .brandSky, .brandViolet],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let deepGradient = LinearGradient(colors: [Color(red: 0.11, green: 0.16, blue: 0.42), .brandNavy],
                                             startPoint: .top, endPoint: .bottom)
}

struct AppLogo: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Ícono de unidad con el degradado de la marca.
struct DriveIcon: View {
    let volume: Volume
    var size: CGFloat = 28

    var symbol: String {
        if volume.isInternal { return "internaldrive.fill" }
        if volume.protocolName.lowercased().contains("virtual") || volume.protocolName.lowercased().contains("disk image") { return "opticaldiscdrive.fill" }
        return "externaldrive.fill"
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.62, weight: .semibold))
            .foregroundStyle(volume.isNTFS ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary))
            .frame(width: size, height: size)
    }
}

struct StatusPill: View {
    let state: MountState
    var issue: MountIssue?

    var color: Color {
        if issue != nil { return .orange }
        switch state {
        case .readWrite: return .green
        case .readOnly, .appleReadOnly: return .blue
        case .unmounted: return .secondary
        }
    }

    var text: String {
        if let issue, issue != .cancelled { return issue == .hibernated ? "Windows hibernado" : (issue == .unclean ? "Requiere revisión" : "Atención") }
        return state.title
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color == .secondary ? Color.secondary : color)
    }
}

struct CapacityBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(fraction > 0.9 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Brand.gradient))
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 10)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: Color.brandSky.opacity(0.3), radius: 6, y: 3)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

func formatBytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
