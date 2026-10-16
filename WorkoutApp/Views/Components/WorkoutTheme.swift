import SwiftUI

/// Shared look for the redesigned tabs: near-black background, dark cards,
/// pale-yellow poster headers, lime primary CTAs, pink secondary accents.
enum WorkoutTheme {
    static let background = Color(red: 0.045, green: 0.045, blue: 0.065)
    static let card = Color(red: 0.115, green: 0.115, blue: 0.135)
    static let tile = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.62)
    /// Secondary accent: selection rings, highlights.
    static let pink = Color(red: 0.96, green: 0.47, blue: 0.71)
    static let dotEmpty = Color(white: 0.17)
    /// Primary accent: workout days, CTAs.
    static let lime = Color(red: 0.70, green: 0.90, blue: 0.20)
    /// Warm-up sets.
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.20)
    static let grayText = Color(white: 0.55)
    static let softText = Color(white: 0.78)
}

/// The primary call-to-action: lime pill, black text.
/// The one primary action per screen uses this.
struct LimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(WorkoutTheme.lime)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension ButtonStyle where Self == LimeButtonStyle {
    static var lime: LimeButtonStyle { LimeButtonStyle() }
}

extension Font {
    /// Heavy poster type for headers, always paired with `.textCase(.uppercase)`.
    static func poster(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }
}

extension View {
    /// The dark, non-native shell used by the redesigned tabs.
    func workoutTabStyle() -> some View {
        self
            .preferredColorScheme(.dark)
            .background(WorkoutTheme.background)
    }
}
