import Foundation

enum SupportedGame: String, CaseIterable, Identifiable {
    case emerald
    case sword
    case shield

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emerald:
            "Pokémon Smeraldo"
        case .sword:
            "Pokémon Spada"
        case .shield:
            "Pokémon Scudo"
        }
    }

    var isEmerald: Bool {
        self == .emerald
    }
}
