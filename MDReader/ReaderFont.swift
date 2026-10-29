import SwiftUI

enum ReaderFont: String, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"
    case rounded = "Rounded"
    case monospaced = "Monospaced"
    case georgia = "Georgia"

    var id: Self { self }

    func font(size: Double) -> Font {
        switch self {
        case .system: .system(size: size)
        case .serif: .system(size: size, design: .serif)
        case .rounded: .system(size: size, design: .rounded)
        case .monospaced: .system(size: size, design: .monospaced)
        case .georgia: .custom("Georgia", size: size)
        }
    }
}
