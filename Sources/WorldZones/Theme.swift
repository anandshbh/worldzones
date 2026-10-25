import AppKit
import SwiftUI

enum Theme {
    static let cardRadius: CGFloat = 14
    static let accent = LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.36, blue: 0.98)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)

    static func title(_ size: CGFloat = 13, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Tint over the panel's blur (which lives in AppKit, see StatusPanel.swift): a faint color wash
/// and top sheen so it reads glossy rather than flat black or white.
struct PanelBackground: View {
    let style: GlassStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // Frosted adds a little opacity back for readability over busy wallpapers.
            Color(nsColor: .windowBackgroundColor).opacity(tintOpacity)
            LinearGradient(colors: [Color(red: 0.36, green: 0.5, blue: 1.0).opacity(0.10), .clear,
                                    Color(red: 0.6, green: 0.35, blue: 0.95).opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.07 : 0.25), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var tintOpacity: Double {
        switch style {
        case .clear: return 0
        case .regular: return scheme == .dark ? 0.15 : 0.2
        case .frosted: return scheme == .dark ? 0.45 : 0.5
        }
    }
}

/// The panel outline: a rounded body with an arrow on top pointing at the menu bar item.
/// Used both to clip the SwiftUI content and as the AppKit blur's mask, so they line up exactly.
struct PopoverShape: Shape {
    var arrowX: CGFloat
    static let arrowHeight: CGFloat = 9
    static let arrowHalfWidth: CGFloat = 11
    static let radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let r = Self.radius, ah = Self.arrowHeight, aw = Self.arrowHalfWidth
        let top = rect.minY + ah
        let x = min(max(arrowX, rect.minX + r + aw), rect.maxX - r - aw)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: top))
        // Concave sides with a softened tip, like a system popover.
        p.addLine(to: CGPoint(x: x - aw, y: top))
        p.addCurve(to: CGPoint(x: x, y: rect.minY), control1: CGPoint(x: x - aw * 0.45, y: top), control2: CGPoint(x: x - 2.5, y: rect.minY))
        p.addCurve(to: CGPoint(x: x + aw, y: top), control1: CGPoint(x: x + 2.5, y: rect.minY), control2: CGPoint(x: x + aw * 0.45, y: top))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: top), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.maxX, y: top), radius: r)
        p.closeSubpath()
        return p
    }
}

/// Rounded translucent card with a hairline sheen on its top edge.
struct GlassCard: ViewModifier {
    var highlighted = false
    var radius: CGFloat = Theme.cardRadius
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.18 : 0.7), .white.opacity(scheme == .dark ? 0.03 : 0.2)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.6))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 3, y: 1)
    }

    private var fill: Color {
        if scheme == .dark { return .white.opacity(highlighted ? 0.11 : 0.055) }
        return .white.opacity(highlighted ? 0.6 : 0.38)
    }
}

extension View {
    func glassCard(highlighted: Bool = false, radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(GlassCard(highlighted: highlighted, radius: radius))
    }
}

/// Small round toolbar button.
struct CircleIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 26
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(hover.on ? 0.14 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover.on = $0 }
    }
}

/// `@State` needs a macro plugin the Command Line Tools don't ship.
final class HoverState: ObservableObject {
    @Published var on = false
}
