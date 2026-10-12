import Foundation

enum EditorMode: String {
    case home
    case rom
    case save
    case teamCoach
    case swordShield
}

struct PokemonBaseStats: Equatable {
    var hp: Int
    var attack: Int
    var defense: Int
    var speed: Int
    var specialAttack: Int
    var specialDefense: Int
}

struct PokemonSpecies: Identifiable, Equatable {
    let id: Int
    var name: String
    var baseStats: PokemonBaseStats
    var type1: Int
    var type2: Int
    var catchRate: Int
    var baseExperience: Int
    var genderRatio: Int
    var stepsToHatch: Int
    var baseFriendship: Int
    var growthRate: Int
    var ability1: Int
    var ability2: Int
    let statsOffset: Int
}

struct PokemonNamedValue: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct MoveData: Identifiable, Equatable {
    let id: Int
    var name: String
    var effectID: Int
    var power: Int
    var type: Int
    var accuracy: Int
    var pp: Int
    var effectChance: Int
    var target: Int
    var priority: Int
    var info: Int
    let statsOffset: Int
}

struct LevelUpMove: Equatable {
    let move: Int
    let level: Int
}

enum TrainerPartyFormat: Int, CaseIterable {
    case normal = 0
    case moves = 1
    case items = 2
    case itemsAndMoves = 3

    var title: String {
        localizedTitle(language: .english)
    }

    func localizedTitle(language: AppLanguage) -> String {
        switch self {
        case .normal: "Base"
        case .moves: language == .italian ? "Mosse personalizzate" : "Custom moves"
        case .items: language == .italian ? "Strumenti tenuti" : "Held items"
        case .itemsAndMoves: language == .italian ? "Strumenti tenuti + mosse personalizzate" : "Held items + custom moves"
        }
    }

    var includesMoves: Bool { rawValue & 1 != 0 }
    var includesItems: Bool { rawValue & 2 != 0 }
    var memberLength: Int { includesMoves ? 16 : 8 }
}

struct TrainerPartyMember: Identifiable, Equatable {
    let id: Int
    var ivSpread: Int
    var level: Int
    var species: Int
    var heldItem: Int
    var moves: [Int]
    let offset: Int
}

struct TrainerData: Identifiable, Equatable {
    let id: Int
    var name: String
    var trainerClass: Int
    var introMusicAndGender: Int
    var sprite: Int
    var items: [Int]
    var doubleBattle: Bool
    var aiFlags: UInt32
    var partyFormat: TrainerPartyFormat
    var partyCount: Int
    var party: [TrainerPartyMember]
    let entryOffset: Int
    var partyOffset: Int
}

struct PokemonStatSpread: Equatable {
    var hp: Int
    var attack: Int
    var defense: Int
    var specialAttack: Int
    var specialDefense: Int
    var speed: Int
}

struct PlayerPartyPokemon: Identifiable, Equatable {
    let id: Int
    let slot: Int
    let offset: Int
    let personality: UInt32
    let otID: UInt32
    var nickname: String
    let species: Int
    var heldItem: Int
    var experience: UInt32
    var ppBonuses: Int
    var friendship: Int
    var moves: [Int]
    var pp: [Int]
    var evs: PokemonStatSpread
    let pokerus: Int
    let metLocation: Int
    let metLevel: Int
    let pokeball: Int
    let abilityNum: Int
    var ivs: PokemonStatSpread
    let isEgg: Bool
    let level: Int
    let currentHP: Int
    let maxHP: Int
    let attack: Int
    let defense: Int
    let speed: Int
    let specialAttack: Int
    let specialDefense: Int
    let checksumValid: Bool

    var natureIndex: Int {
        Int(personality % 25)
    }

    var natureName: String {
        Self.natureNames.indices.contains(natureIndex) ? Self.natureNames[natureIndex] : "Nature #\(natureIndex)"
    }

    var isShiny: Bool {
        let trainer = UInt16(truncatingIfNeeded: otID) ^ UInt16(truncatingIfNeeded: otID >> 16)
        let pokemon = UInt16(truncatingIfNeeded: personality) ^ UInt16(truncatingIfNeeded: personality >> 16)
        return (trainer ^ pokemon) < 8
    }

    private static let natureNames = [
        "Hardy", "Lonely", "Brave", "Adamant", "Naughty",
        "Bold", "Docile", "Relaxed", "Impish", "Lax",
        "Timid", "Hasty", "Serious", "Jolly", "Naive",
        "Modest", "Mild", "Quiet", "Bashful", "Rash",
        "Calm", "Gentle", "Sassy", "Careful", "Quirky"
    ]
}

struct PlayerSaveData: Equatable {
    let fileURL: URL
    let activeSaveIndex: UInt32
    let saveBlockOffset: Int
    let saveBlock1SectionOffset: Int
    let allSectionChecksumsValid: Bool
    let gameTitle: String?
    let trainer: SaveTrainerInfo
    let playTime: SavePlayTime?
    let saveCount: UInt32?
    let money: UInt32?
    let coins: Int?
    let partyCountOffset: Int
    let party: [PlayerPartyPokemon]
    let boxes: [SavePCBox]
    let bagPockets: [SaveBagPocket]
    let pokedex: SavePokedexData?
    let progression: SaveProgressionData
    let sections: [SaveSectionInfo]
    let activeSlot: Int

    var fileName: String {
        fileURL.lastPathComponent
    }
}

struct SavePlayTime: Equatable {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int

    var displayValue: String {
        String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

struct SaveTrainerInfo: Equatable {
    let name: String?
    let gender: Int?
    let trainerID: UInt16?
    let secretID: UInt16?
    let securityKey: UInt32?
    let nationalDexUnlocked: Bool?
}

struct SaveBoxPokemon: Identifiable, Equatable {
    let id: Int
    let boxIndex: Int
    let slot: Int
    let personality: UInt32
    let otID: UInt32
    let nickname: String
    let species: Int
    let heldItem: Int
    let experience: UInt32
    let moves: [Int]
    let pp: [Int]
    let ivs: PokemonStatSpread
    let isEgg: Bool
    let checksumValid: Bool

    var natureIndex: Int {
        Int(personality % 25)
    }

    var natureName: String {
        Self.natureNames.indices.contains(natureIndex) ? Self.natureNames[natureIndex] : "Nature #\(natureIndex)"
    }

    var isShiny: Bool {
        let trainer = UInt16(truncatingIfNeeded: otID) ^ UInt16(truncatingIfNeeded: otID >> 16)
        let pokemon = UInt16(truncatingIfNeeded: personality) ^ UInt16(truncatingIfNeeded: personality >> 16)
        return (trainer ^ pokemon) < 8
    }

    private static let natureNames = [
        "Hardy", "Lonely", "Brave", "Adamant", "Naughty",
        "Bold", "Docile", "Relaxed", "Impish", "Lax",
        "Timid", "Hasty", "Serious", "Jolly", "Naive",
        "Modest", "Mild", "Quiet", "Bashful", "Rash",
        "Calm", "Gentle", "Sassy", "Careful", "Quirky"
    ]
}

struct SavePCBox: Identifiable, Equatable {
    let id: Int
    let name: String
    let pokemon: [SaveBoxPokemon]
}

enum SaveBagPocketKind: String, CaseIterable, Identifiable {
    case items
    case keyItems
    case balls
    case machines
    case berries

    var id: String { rawValue }
}

struct SaveBagItem: Identifiable, Equatable {
    let id: Int
    let slot: Int
    let itemID: Int
    let quantity: Int
}

struct SaveBagPocket: Identifiable, Equatable {
    let id: String
    let kind: SaveBagPocketKind
    let name: String
    let capacity: Int
    let items: [SaveBagItem]
}

struct SavePokedexEntry: Identifiable, Equatable {
    let id: Int
    let seen: Bool
    let caught: Bool
}

struct SavePokedexData: Equatable {
    let entries: [SavePokedexEntry]

    var seenCount: Int { entries.filter(\.seen).count }
    var caughtCount: Int { entries.filter(\.caught).count }
}

struct SaveProgressionData: Equatable {
    let badges: Int?
    let mapGroup: Int?
    let mapNumber: Int?
    let x: Int?
    let y: Int?
    let healLocation: String?
}

struct SaveSectionInfo: Identifiable, Equatable {
    let id: Int
    let slot: Int
    let sectionID: Int
    let offset: Int
    let storedChecksum: UInt16
    let calculatedChecksum: UInt16
    let saveIndex: UInt32

    var checksumValid: Bool {
        storedChecksum == calculatedChecksum
    }
}

struct SaveDocument: Equatable {
    var data: Data
    var fileURL: URL
    var parsed: PlayerSaveData
    var isDirty: Bool = false

    var isLoaded: Bool {
        !data.isEmpty
    }
}

struct ItemData: Identifiable, Equatable {
    let id: Int
    var name: String
    var price: Int
    var holdEffect: Int
    var parameter: Int
    var description: String
    var keyItemValue: Int
    var bagKeyItem: Int
    var pocket: Int
    var type: Int
    let descriptionOffset: Int?
    let fieldEffectPointer: UInt32
    let battleUsage: UInt32
    let battleEffectPointer: UInt32
    let battleExtra: UInt32
    let statsOffset: Int
}

enum WildEncounterKind: String, CaseIterable, Identifiable {
    case grass
    case surf
    case rockSmash
    case oldRod
    case goodRod
    case superRod

    var id: String { rawValue }

    var title: String {
        localizedTitle(language: .english)
    }

    func localizedTitle(language: AppLanguage) -> String {
        switch self {
        case .grass: L10n.text("grass", language: language)
        case .surf: L10n.text("surf", language: language)
        case .rockSmash: L10n.text("rock.smash", language: language)
        case .oldRod: L10n.text("old.rod", language: language)
        case .goodRod: L10n.text("good.rod", language: language)
        case .superRod: L10n.text("super.rod", language: language)
        }
    }
}

struct WildEncounterSlot: Identifiable, Equatable {
    let id: Int
    var species: Int
    var minLevel: Int
    var maxLevel: Int
    let chance: Int
    let offset: Int
}

struct WildEncounterGroup: Identifiable, Equatable {
    let id: String
    let kind: WildEncounterKind
    var encounterRate: Int
    var slots: [WildEncounterSlot]
    let rateOffset: Int
    let tableOffset: Int
}

struct WildEncounterArea: Identifiable, Equatable {
    let id: Int
    let mapGroup: Int
    let mapNumber: Int
    var groups: [WildEncounterGroup]
    let tableOffset: Int

    var displayName: String {
        "Map \(mapGroup).\(mapNumber)"
    }
}

enum MapEditorMode: String, CaseIterable, Identifiable {
    case map
    case collision
    case events

    var id: String { rawValue }

    var title: String {
        localizedTitle(language: .english)
    }

    func localizedTitle(language: AppLanguage) -> String {
        switch self {
        case .map: L10n.text("map", language: language)
        case .collision: L10n.text("collision", language: language)
        case .events: L10n.text("events", language: language)
        }
    }
}

struct MapBlockCell: Identifiable, Equatable {
    let x: Int
    let y: Int
    var metatileID: Int
    var collision: Int
    var elevation: Int
    let offset: Int

    var id: String { "\(x)-\(y)" }
    var rawValue: Int { ((elevation & 0x0F) << 12) | ((collision & 0x03) << 10) | (metatileID & 0x03FF) }
}

struct MapObjectEvent: Identifiable, Equatable {
    let id: Int
    var localID: Int
    var graphicsID: Int
    var x: Int
    var y: Int
    var elevation: Int
    var movementType: Int
    var movementRangeX: Int
    var movementRangeY: Int
    var trainerType: Int
    var trainerRangeOrBerryID: Int
    var scriptPointer: UInt32
    var flag: Int
    let offset: Int
}

struct MapObjectTrainerLink: Equatable {
    let trainerID: Int
    let scriptOffset: Int
    let commandOffset: Int
}

struct MapScriptAnalysis: Equatable {
    enum Classification: String {
        case none = "No script"
        case scripted = "Scripted event"
        case important = "Important scripted event"
        case possibleProgression = "Possible progression event"
    }

    let pointer: UInt32
    let scriptOffset: Int?
    let eventType: String
    let classification: Classification
    let flags: [Int]
    let variables: [Int]
    let commands: [String]
    let reason: String

    var isImportant: Bool {
        classification == .important || classification == .possibleProgression
    }
}

struct MapWarpEvent: Identifiable, Equatable {
    let id: Int
    var x: Int
    var y: Int
    var elevation: Int
    var warpID: Int
    var destinationMap: Int
    var destinationGroup: Int
    let offset: Int
}

struct MapCoordinateEvent: Identifiable, Equatable {
    let id: Int
    var x: Int
    var y: Int
    var elevation: Int
    var trigger: Int
    var index: Int
    var scriptPointer: UInt32
    let offset: Int
}

struct MapBackgroundEvent: Identifiable, Equatable {
    let id: Int
    var x: Int
    var y: Int
    var elevation: Int
    var kind: Int
    var argument: UInt32
    let offset: Int
}

struct MapConnectionData: Identifiable, Equatable {
    let id: Int
    var direction: Int
    var offsetValue: Int
    var targetGroup: Int
    var targetMap: Int
    let entryOffset: Int

    var directionName: String {
        switch direction {
        case 1: "South"
        case 2: "North"
        case 3: "West"
        case 4: "East"
        default: "Direction #\(direction)"
        }
    }
}

struct MapData: Identifiable, Equatable {
    var id: String { "\(group)-\(mapID)" }
    let group: Int
    let mapID: Int
    var name: String
    var width: Int
    var height: Int
    var blocks: [MapBlockCell]
    var objects: [MapObjectEvent]
    var warps: [MapWarpEvent]
    var coordinateEvents: [MapCoordinateEvent]
    var backgroundEvents: [MapBackgroundEvent]
    var connections: [MapConnectionData]
    let headerOffset: Int
    let layoutOffset: Int
    let blockmapOffset: Int
    let eventsOffset: Int?
    let connectionsOffset: Int?
    let primaryTilesetOffset: Int?
    let secondaryTilesetOffset: Int?
    var music: Int
    var layoutID: Int
    var regionSectionID: Int
    var cave: Int
    var weather: Int
    var mapType: Int
    var flags: Int
    var battleType: Int
}
