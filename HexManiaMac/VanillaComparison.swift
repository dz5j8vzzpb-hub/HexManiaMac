import Foundation

enum VanillaComparisonState: Equatable {
    case unavailable
    case comparing
    case available(VanillaChangeSet)
    case incompatible
    case failed(String)
}

struct VanillaChangeSet: Equatable {
    var pokemonIDs: Set<Int> = []
    var moveIDs: Set<Int> = []
    var trainerIDs: Set<Int> = []
    var itemIDs: Set<Int> = []
    var encounterAreaIDs: Set<Int> = []
    var encounterGroupIDs: Set<VanillaEncounterGroupID> = []
    var mapIDs: Set<MapData.ID> = []
    var unverifiableCategories: Set<VanillaCategory> = []

    var hasReliableResults: Bool {
        unverifiableCategories.count < VanillaCategory.allCases.count
    }
}

struct VanillaEncounterGroupID: Hashable {
    let areaID: Int
    let kind: WildEncounterKind
}

enum VanillaCategory: String, CaseIterable, Codable {
    case pokemon
    case moves
    case trainers
    case items
    case encounters
    case maps
}

struct ROMVersionIdentity: Codable, Hashable {
    let gameCode: String
    let makerCode: String
    let revision: UInt8

    init(data: Data) {
        let identity = ROMIdentity.read(from: data)
        gameCode = identity.gameCode
        makerCode = identity.makerCode
        revision = data.indices.contains(0xBC) ? data[0xBC] : 0
    }

    var storageKey: String {
        "\(gameCode)-\(makerCode)-r\(revision)"
    }
}

struct VanillaReferenceMetadata: Codable {
    let identity: ROMVersionIdentity
    let fileName: String
    let importedAt: Date
}

enum VanillaReferenceError: LocalizedError {
    case unsupported
    case invalidHeader
    case incompatible
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unsupported: "La ROM selezionata non è supportata."
        case .invalidHeader: "La ROM selezionata non supera la verifica dell'intestazione GBA."
        case .incompatible: "La ROM Vanilla non corrisponde a gioco, regione o revisione della ROM aperta."
        case .unavailable: "Impossibile creare la cartella dei riferimenti Vanilla."
        }
    }
}

struct VanillaReferenceStore {
    private let fileManager = FileManager.default
    private let customDirectoryURL: URL?

    init(directoryURL: URL? = nil) {
        customDirectoryURL = directoryURL
    }

    private var directoryURL: URL? {
        if let customDirectoryURL { return customDirectoryURL }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HexManiaMac", isDirectory: true)
            .appendingPathComponent("VanillaReferences", isDirectory: true)
    }

    func referenceData(for identity: ROMVersionIdentity) throws -> Data? {
        guard let directoryURL else { throw VanillaReferenceError.unavailable }
        let deterministicURL = directoryURL.appendingPathComponent("\(identity.storageKey).gba")
        if fileManager.fileExists(atPath: deterministicURL.path) {
            let data = try Data(contentsOf: deterministicURL, options: .mappedIfSafe)
            guard ROMVersionIdentity(data: data) == identity else { return nil }
            return data
        }
        let metadataURL = directoryURL.appendingPathComponent("\(identity.storageKey).json")
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
        let metadata = try JSONDecoder().decode(
            VanillaReferenceMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.identity == identity else { return nil }
        return try Data(contentsOf: directoryURL.appendingPathComponent(metadata.fileName), options: .mappedIfSafe)
    }

    func referenceURL(for identity: ROMVersionIdentity) -> URL? {
        guard let directoryURL else { return nil }
        let url = directoryURL.appendingPathComponent("\(identity.storageKey).gba")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func importReference(from sourceURL: URL, matching currentIdentity: ROMVersionIdentity?) throws -> ROMVersionIdentity {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        let identity = ROMVersionIdentity(data: data)
        guard EmeraldROM.supportedGameCodes.contains(identity.gameCode) else {
            throw VanillaReferenceError.unsupported
        }
        guard Self.hasValidGBAHeader(data) else {
            throw VanillaReferenceError.invalidHeader
        }
        if let currentIdentity, currentIdentity != identity {
            throw VanillaReferenceError.incompatible
        }
        guard let directoryURL else { throw VanillaReferenceError.unavailable }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let romFileName = "\(identity.storageKey).gba"
        let destinationURL = directoryURL.appendingPathComponent(romFileName)
        try data.write(to: destinationURL, options: .atomic)

        let metadata = VanillaReferenceMetadata(
            identity: identity,
            fileName: romFileName,
            importedAt: Date()
        )
        let encoded = try JSONEncoder().encode(metadata)
        try encoded.write(
            to: directoryURL.appendingPathComponent("\(identity.storageKey).json"),
            options: .atomic
        )
        return identity
    }

    static func hasValidGBAHeader(_ data: Data) -> Bool {
        guard data.count > 0xBD else { return false }
        var checksum: UInt8 = 0
        for byte in data[0xA0...0xBC] {
            checksum &-= byte
        }
        checksum &-= 0x19
        return checksum == data[0xBD]
    }
}

struct VanillaSemanticSnapshot {
    let pokemon: [Int: PokemonSignature]?
    let moves: [Int: MoveSignature]?
    let trainers: [Int: TrainerSignature]?
    let items: [Int: ItemSignature]?
    let encounters: [Int: EncounterSignature]?
    let maps: [MapData.ID: MapSignature]?

    init(data: Data) {
        let rom = EmeraldROM(data: data)
        pokemon = try? Dictionary(uniqueKeysWithValues: rom.pokemonSpecies().map { ($0.id, PokemonSignature($0)) })
        moves = try? Dictionary(uniqueKeysWithValues: rom.moves().map { ($0.id, MoveSignature($0)) })
        trainers = try? Dictionary(uniqueKeysWithValues: rom.trainers().map { ($0.id, TrainerSignature($0)) })
        items = try? Dictionary(uniqueKeysWithValues: rom.itemData().map { ($0.id, ItemSignature($0)) })
        encounters = try? Dictionary(uniqueKeysWithValues: rom.wildEncounterAreas().map { ($0.id, EncounterSignature($0)) })
        maps = try? Dictionary(uniqueKeysWithValues: rom.maps().map { ($0.id, MapSignature($0)) })
    }

    init(
        pokemon: [PokemonSpecies],
        moves: [MoveData],
        trainers: [TrainerData],
        items: [ItemData],
        encounters: [WildEncounterArea],
        maps: [MapData]
    ) {
        self.pokemon = Dictionary(uniqueKeysWithValues: pokemon.map { ($0.id, PokemonSignature($0)) })
        self.moves = Dictionary(uniqueKeysWithValues: moves.map { ($0.id, MoveSignature($0)) })
        self.trainers = Dictionary(uniqueKeysWithValues: trainers.map { ($0.id, TrainerSignature($0)) })
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, ItemSignature($0)) })
        self.encounters = Dictionary(uniqueKeysWithValues: encounters.map { ($0.id, EncounterSignature($0)) })
        self.maps = Dictionary(uniqueKeysWithValues: maps.map { ($0.id, MapSignature($0)) })
    }
}

enum VanillaComparisonEngine {
    static func compare(currentData: Data, vanillaData: Data) -> VanillaChangeSet {
        compare(
            current: VanillaSemanticSnapshot(data: currentData),
            vanilla: VanillaSemanticSnapshot(data: vanillaData)
        )
    }

    static func compare(current: VanillaSemanticSnapshot, vanilla: VanillaSemanticSnapshot) -> VanillaChangeSet {
        var result = VanillaChangeSet()
        compare(current.pokemon, vanilla.pokemon, category: .pokemon, changed: &result.pokemonIDs, unknown: &result.unverifiableCategories)
        compare(current.moves, vanilla.moves, category: .moves, changed: &result.moveIDs, unknown: &result.unverifiableCategories)
        compare(current.trainers, vanilla.trainers, category: .trainers, changed: &result.trainerIDs, unknown: &result.unverifiableCategories)
        compare(current.items, vanilla.items, category: .items, changed: &result.itemIDs, unknown: &result.unverifiableCategories)
        compare(current.encounters, vanilla.encounters, category: .encounters, changed: &result.encounterAreaIDs, unknown: &result.unverifiableCategories)
        compareEncounterGroups(current.encounters, vanilla.encounters, result: &result)
        compare(current.maps, vanilla.maps, category: .maps, changed: &result.mapIDs, unknown: &result.unverifiableCategories)

        if let areas = current.encounters {
            for areaID in result.encounterAreaIDs {
                guard let area = areas[areaID] else { continue }
                result.mapIDs.insert("\(area.mapGroup)-\(area.mapNumber)")
            }
        }
        return result
    }

    private static func compareEncounterGroups(
        _ current: [Int: EncounterSignature]?,
        _ vanilla: [Int: EncounterSignature]?,
        result: inout VanillaChangeSet
    ) {
        guard let current, let vanilla else { return }
        for areaID in Set(current.keys).union(vanilla.keys) {
            let currentGroups = Dictionary(uniqueKeysWithValues: (current[areaID]?.groups ?? []).map { ($0.kind, $0) })
            let vanillaGroups = Dictionary(uniqueKeysWithValues: (vanilla[areaID]?.groups ?? []).map { ($0.kind, $0) })
            for kind in Set(currentGroups.keys).union(vanillaGroups.keys) where currentGroups[kind] != vanillaGroups[kind] {
                result.encounterGroupIDs.insert(VanillaEncounterGroupID(areaID: areaID, kind: kind))
                result.encounterAreaIDs.insert(areaID)
            }
        }
    }

    private static func compare<Key: Hashable, Value: Equatable>(
        _ current: [Key: Value]?,
        _ vanilla: [Key: Value]?,
        category: VanillaCategory,
        changed: inout Set<Key>,
        unknown: inout Set<VanillaCategory>
    ) {
        guard let current, let vanilla else {
            unknown.insert(category)
            return
        }
        for key in Set(current.keys).union(vanilla.keys) where current[key] != vanilla[key] {
            changed.insert(key)
        }
    }
}

struct PokemonSignature: Equatable {
    let name: String
    let stats: PokemonBaseStats
    let type1: Int
    let type2: Int
    let catchRate: Int
    let baseExperience: Int
    let genderRatio: Int
    let stepsToHatch: Int
    let baseFriendship: Int
    let growthRate: Int
    let ability1: Int
    let ability2: Int

    init(_ value: PokemonSpecies) {
        name = value.name
        stats = value.baseStats
        type1 = value.type1
        type2 = value.type2
        catchRate = value.catchRate
        baseExperience = value.baseExperience
        genderRatio = value.genderRatio
        stepsToHatch = value.stepsToHatch
        baseFriendship = value.baseFriendship
        growthRate = value.growthRate
        ability1 = value.ability1
        ability2 = value.ability2
    }
}

struct MoveSignature: Equatable {
    let name: String
    let values: [Int]

    init(_ value: MoveData) {
        name = value.name
        values = [value.effectID, value.power, value.type, value.accuracy, value.pp, value.effectChance, value.target, value.priority, value.info]
    }
}

struct TrainerMemberSignature: Equatable {
    let ivSpread: Int
    let level: Int
    let species: Int
    let heldItem: Int
    let moves: [Int]
}

struct TrainerSignature: Equatable {
    let name: String
    let values: [Int]
    let aiFlags: UInt32
    let party: [TrainerMemberSignature]

    init(_ value: TrainerData) {
        name = value.name
        values = [value.trainerClass, value.introMusicAndGender, value.sprite] + value.items
            + [value.doubleBattle ? 1 : 0, value.partyFormat.rawValue, value.partyCount]
        aiFlags = value.aiFlags
        party = value.party.map {
            TrainerMemberSignature(ivSpread: $0.ivSpread, level: $0.level, species: $0.species, heldItem: $0.heldItem, moves: $0.moves)
        }
    }
}

struct ItemSignature: Equatable {
    let name: String
    let description: String
    let values: [UInt32]

    init(_ value: ItemData) {
        name = value.name
        description = value.description
        values = [
            UInt32(value.price), UInt32(value.holdEffect), UInt32(value.parameter),
            UInt32(value.keyItemValue), UInt32(value.bagKeyItem), UInt32(value.pocket),
            UInt32(value.type), value.battleUsage, value.battleExtra
        ]
    }
}

struct EncounterSlotSignature: Equatable {
    let species: Int
    let minLevel: Int
    let maxLevel: Int
    let chance: Int
}

struct EncounterGroupSignature: Equatable {
    let kind: WildEncounterKind
    let encounterRate: Int
    let slots: [EncounterSlotSignature]
}

struct EncounterSignature: Equatable {
    let mapGroup: Int
    let mapNumber: Int
    let groups: [EncounterGroupSignature]

    init(_ value: WildEncounterArea) {
        mapGroup = value.mapGroup
        mapNumber = value.mapNumber
        groups = value.groups.map {
            EncounterGroupSignature(
                kind: $0.kind,
                encounterRate: $0.encounterRate,
                slots: $0.slots.map {
                    EncounterSlotSignature(species: $0.species, minLevel: $0.minLevel, maxLevel: $0.maxLevel, chance: $0.chance)
                }
            )
        }
    }
}

struct MapSignature: Equatable {
    let name: String
    let dimensionsAndProperties: [Int]
    let blocks: [[Int]]
    let objects: [[UInt32]]
    let warps: [[Int]]
    let coordinateEvents: [[UInt32]]
    let backgroundEvents: [[UInt32]]
    let connections: [[Int]]

    init(_ value: MapData) {
        name = value.name
        dimensionsAndProperties = [
            value.width, value.height, value.music, value.layoutID, value.regionSectionID,
            value.cave, value.weather, value.mapType, value.flags, value.battleType
        ]
        blocks = value.blocks.map { [$0.x, $0.y, $0.metatileID, $0.collision, $0.elevation] }
        objects = value.objects.map {
            [UInt32($0.localID), UInt32($0.graphicsID), UInt32($0.x), UInt32($0.y), UInt32($0.elevation),
             UInt32($0.movementType), UInt32($0.movementRangeX), UInt32($0.movementRangeY),
             UInt32($0.trainerType), UInt32($0.trainerRangeOrBerryID), UInt32($0.flag)]
        }
        warps = value.warps.map { [$0.x, $0.y, $0.elevation, $0.warpID, $0.destinationMap, $0.destinationGroup] }
        coordinateEvents = value.coordinateEvents.map {
            [UInt32($0.x), UInt32($0.y), UInt32($0.elevation), UInt32($0.trigger), UInt32($0.index)]
        }
        backgroundEvents = value.backgroundEvents.map {
            [UInt32($0.x), UInt32($0.y), UInt32($0.elevation), UInt32($0.kind), $0.argument]
        }
        connections = value.connections.map { [$0.direction, $0.offsetValue, $0.targetGroup, $0.targetMap] }
    }
}
