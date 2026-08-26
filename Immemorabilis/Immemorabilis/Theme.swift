import SwiftUI

enum AccentChoice: String, CaseIterable, Identifiable {
    case red
    case blue

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red: .immemorabilisRed
        case .blue: .immemorabilisInkBlue
        }
    }
}

extension Color {
    static let immemorabilisRed = adaptive(
        light: UIColor(red: 0.79, green: 0.04, blue: 0.03, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.34, blue: 0.32, alpha: 1)
    )
    static let immemorabilisInkBlue = adaptive(
        light: UIColor(red: 0.03, green: 0.43, blue: 0.70, alpha: 1),
        dark: UIColor(red: 0.29, green: 0.53, blue: 0.83, alpha: 1)
    )
    static let immemorabilisBlue = adaptive(
        light: UIColor(red: 0.82, green: 0.94, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.09, blue: 0.15, alpha: 1)
    )
    static let immemorabilisCanvas = adaptive(
        light: UIColor(red: 0.95, green: 0.98, blue: 0.99, alpha: 1),
        dark: .black
    )
    static let immemorabilisSurface = adaptive(
        light: .systemBackground,
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )
    static let immemorabilisModalCanvas = adaptive(
        light: UIColor(red: 0.95, green: 0.98, blue: 0.99, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1)
    )

    static var immemorabilisAccent: Color {
        AccentChoice(rawValue: UserDefaults.standard.string(forKey: "accentColorChoice") ?? "red")?.color ?? .immemorabilisRed
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct BrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            stops: colorScheme == .dark ? darkStops : lightStops,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var lightStops: [Gradient.Stop] {
        [
            .init(color: .immemorabilisBlue, location: 0),
            .init(color: .immemorabilisCanvas, location: 0.30),
            .init(color: .immemorabilisCanvas, location: 1)
        ]
    }

    private var darkStops: [Gradient.Stop] {
        [
            .init(color: .immemorabilisBlue, location: 0),
            .init(color: .immemorabilisBlue, location: 0.16),
            .init(color: .immemorabilisCanvas, location: 0.23),
            .init(color: .immemorabilisCanvas, location: 1)
        ]
    }
}

struct ModalBackground: View {
    var body: some View {
        Color.immemorabilisModalCanvas
            .ignoresSafeArea()
    }
}

struct ImmemorabilisCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color.immemorabilisSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(minHeight: 54)
            .background(Color.immemorabilisAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct RoundActionButtonStyle: ButtonStyle {
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.medium))
            .foregroundStyle(emphasized ? Color.white : Color.primary)
            .frame(width: 54, height: 54)
            .background {
                if emphasized {
                    Circle().fill(Color.immemorabilisAccent)
                } else {
                    Circle().fill(.thinMaterial)
                }
            }
            .overlay(Circle().stroke(emphasized ? Color.white.opacity(0.16) : Color.primary.opacity(0.12)))
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct ScreenTitleBar: View {
    let title: String
    var showsCancel = true
    var confirmEnabled = true
    var cancel: () -> Void = {}
    var confirm: (() -> Void)?

    var body: some View {
        HStack {
            if showsCancel {
                Button(action: cancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RoundActionButtonStyle())
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("screen-cancel")
            } else {
                Color.clear.frame(width: 54, height: 54)
            }

            Spacer()
            Text(title)
                .font(.title3.bold())
            Spacer()

            if let confirm {
                Button(action: confirm) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(RoundActionButtonStyle(emphasized: true))
                .disabled(!confirmEnabled)
                .opacity(confirmEnabled ? 1 : 0.42)
                .accessibilityLabel("Save")
                .accessibilityIdentifier("screen-save")
            } else {
                Button(action: cancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RoundActionButtonStyle(emphasized: true))
                .accessibilityLabel("Close")
                .accessibilityIdentifier("screen-close")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
