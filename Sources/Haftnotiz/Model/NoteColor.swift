import AppKit
import SwiftUI

/// The paper colour of a note. Palette and inks taken over from Tic (MIT, Kasun Vithanage).
enum NoteColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow
    case pink
    case blue
    case green
    case purple
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yellow: "Gelb"
        case .pink: "Rosa"
        case .blue: "Blau"
        case .green: "Grün"
        case .purple: "Lila"
        case .graphite: "Grau"
        }
    }

    /// The paper fill.
    var fill: Color {
        switch self {
        case .yellow: Color(red: 1.00, green: 0.90, blue: 0.46)
        case .pink: Color(red: 1.00, green: 0.78, blue: 0.84)
        case .blue: Color(red: 0.70, green: 0.86, blue: 1.00)
        case .green: Color(red: 0.76, green: 0.93, blue: 0.74)
        case .purple: Color(red: 0.84, green: 0.79, blue: 0.97)
        case .graphite: Color(red: 0.86, green: 0.87, blue: 0.90)
        }
    }

    /// A deeper shade of the hue for soft accents (bullets, code background, links).
    var accent: Color {
        switch self {
        case .yellow: Color(red: 0.78, green: 0.62, blue: 0.10)
        case .pink: Color(red: 0.82, green: 0.36, blue: 0.50)
        case .blue: Color(red: 0.18, green: 0.48, blue: 0.78)
        case .green: Color(red: 0.26, green: 0.58, blue: 0.30)
        case .purple: Color(red: 0.46, green: 0.36, blue: 0.74)
        case .graphite: Color(red: 0.40, green: 0.42, blue: 0.46)
        }
    }

    /// Body text: a deep tone of the hue, crisper on its pastel than flat black.
    fileprivate var solidInk: Color {
        switch self {
        case .yellow: Color(red: 0.24, green: 0.19, blue: 0.04)
        case .pink: Color(red: 0.27, green: 0.12, blue: 0.17)
        case .blue: Color(red: 0.08, green: 0.18, blue: 0.32)
        case .green: Color(red: 0.10, green: 0.24, blue: 0.12)
        case .purple: Color(red: 0.22, green: 0.14, blue: 0.38)
        case .graphite: Color(red: 0.14, green: 0.15, blue: 0.18)
        }
    }

    /// Markdown markers, placeholders, finished items. Muting is baked in.
    fileprivate var solidSecondary: Color {
        switch self {
        case .yellow: Color(red: 0.46, green: 0.40, blue: 0.20)
        case .pink: Color(red: 0.55, green: 0.34, blue: 0.40)
        case .blue: Color(red: 0.34, green: 0.45, blue: 0.58)
        case .green: Color(red: 0.36, green: 0.48, blue: 0.36)
        case .purple: Color(red: 0.48, green: 0.42, blue: 0.62)
        case .graphite: Color(red: 0.48, green: 0.50, blue: 0.55)
        }
    }

    fileprivate var solidCheckbox: Color {
        switch self {
        case .yellow: Color(red: 0.78, green: 0.62, blue: 0.10)
        case .pink: Color(red: 0.78, green: 0.30, blue: 0.45)
        case .blue: Color(red: 0.13, green: 0.42, blue: 0.72)
        case .green: Color(red: 0.18, green: 0.50, blue: 0.24)
        case .purple: Color(red: 0.42, green: 0.30, blue: 0.72)
        case .graphite: Color(red: 0.30, green: 0.40, blue: 0.78)
        }
    }
}

/// The resolved palette of a note.
struct NoteTheme: Equatable {
    let color: NoteColor

    var accent: Color { color.accent }
    var ink: Color { color.solidInk }
    var secondary: Color { color.solidSecondary }
    var checkbox: Color { color.solidCheckbox }

    var nsInk: NSColor { NSColor(color.solidInk) }
    var nsSecondary: NSColor { NSColor(color.solidSecondary) }
    var nsAccent: NSColor { NSColor(color.accent) }
    var nsCheckbox: NSColor { NSColor(color.solidCheckbox) }
}
