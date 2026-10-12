import Foundation

enum TeamCoachAssessmentCategory: String, CaseIterable, Identifiable {
    case excellent
    case good
    case developing
    case redundant

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .excellent:
            language == .italian ? "ECCELLENTE" : "EXCELLENT"
        case .good:
            language == .italian ? "BUONO" : "GOOD"
        case .developing:
            language == .italian ? "ACERBO" : "DEVELOPING"
        case .redundant:
            language == .italian ? "RIDONDANTE" : "REDUNDANT"
        }
    }
}

struct TeamCoachSlot: Identifiable, Equatable {
    let id: Int
    var speciesID: Int?
    var level: Int?
    var moveIDs: [Int?]

    var isEmpty: Bool {
        speciesID == nil
    }

    static func emptySlots(count: Int = 6) -> [TeamCoachSlot] {
        (0..<count).map { index in
            TeamCoachSlot(id: index, speciesID: nil, level: nil, moveIDs: Array(repeating: nil, count: 4))
        }
    }
}

struct TeamCoachProgressionCheckpoint: Identifiable, Hashable {
    let id: String
    let title: String
    let source: Source

    enum Source: Hashable {
        case manual
        case map(group: Int, mapID: Int)
        case saveProgression
    }

    static let notSet = TeamCoachProgressionCheckpoint(
        id: "manual.not-set",
        title: "Non impostata",
        source: .manual
    )
}

struct TeamCoachSettings: Equatable {
    var reachedAreaID: TeamCoachProgressionCheckpoint.ID = TeamCoachProgressionCheckpoint.notSet.id
    var recommendDiscoveredOnly = false
}

struct TeamCoachContext {
    let team: [TeamCoachSlot]
    let species: [PokemonSpecies]
    let moves: [MoveData]
    let types: [PokemonNamedValue]
    let encounterAreas: [WildEncounterArea]
    let maps: [MapData]
    let progression: TeamCoachProgressionCheckpoint?
    let recommendDiscoveredOnly: Bool
    let pokedex: SavePokedexData?
}

struct TeamCoachSlotAnalysis: Identifiable, Equatable {
    let id: TeamCoachSlot.ID
    let category: TeamCoachAssessmentCategory
    let explanation: String
    let suggestion: String
}

struct TeamCoachRecommendation: Identifiable, Equatable {
    let id: Int
    let speciesID: Int
    let reason: String
    let areaName: String?
    let minLevel: Int?
    let maxLevel: Int?
    let replacementSlotID: TeamCoachSlot.ID?
}
