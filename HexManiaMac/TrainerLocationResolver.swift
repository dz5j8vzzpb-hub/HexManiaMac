import Foundation

enum TrainerLocationSource: Int, Comparable {
    case event = 0
    case script = 1
    case rematch = 2
    case fallback = 3

    static func < (lhs: TrainerLocationSource, rhs: TrainerLocationSource) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum TrainerTerrainContext: String, Equatable {
    case land
    case water
    case coast
    case unknown
}

struct TrainerLocationReference: Equatable, Identifiable {
    var id: String { "\(trainerID)-\(mapGroup)-\(mapID)-\(source.rawValue)-\(objectLocalID ?? -1)-\(scriptOffset ?? -1)-\(commandOffset ?? -1)" }

    let trainerID: Int
    let mapGroup: Int
    let mapID: Int
    let locationName: String
    let source: TrainerLocationSource
    let objectLocalID: Int?
    let x: Int?
    let y: Int?
    let terrain: TrainerTerrainContext
    let requiresSurf: Bool
    let scriptOffset: Int?
    let commandOffset: Int?
}

struct TrainerLocationIndex: Equatable {
    static let empty = TrainerLocationIndex(referencesByTrainerID: [:])

    let referencesByTrainerID: [Int: [TrainerLocationReference]]

    var displayLocationsByTrainerID: [Int: [String]] {
        referencesByTrainerID.mapValues { references in
            var seen = Set<String>()
            var locations: [String] = []
            for reference in references.sorted(by: Self.sortReferences) where !seen.contains(reference.locationName) {
                seen.insert(reference.locationName)
                locations.append(reference.locationName)
            }
            return locations
        }
    }

    func primaryReference(for trainerID: Int) -> TrainerLocationReference? {
        referencesByTrainerID[trainerID]?.min { lhs, rhs in
            let lhsProgress = EmeraldStoryProgression.index(for: MapPoint(group: lhs.mapGroup, map: lhs.mapID)) ?? Int.max
            let rhsProgress = EmeraldStoryProgression.index(for: MapPoint(group: rhs.mapGroup, map: rhs.mapID)) ?? Int.max
            if lhsProgress != rhsProgress { return lhsProgress < rhsProgress }
            return Self.sortReferences(lhs, rhs)
        }
    }

    static func sortReferences(_ lhs: TrainerLocationReference, _ rhs: TrainerLocationReference) -> Bool {
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        if lhs.locationName != rhs.locationName { return lhs.locationName < rhs.locationName }
        if lhs.mapGroup != rhs.mapGroup { return lhs.mapGroup < rhs.mapGroup }
        return lhs.mapID < rhs.mapID
    }
}

struct TrainerLocationResolver {
    private let data: Data
    private let maps: [MapData]
    private let language: AppLanguage
    private let mapNameResolver: MapNameResolver

    init(data: Data, maps: [MapData], language: AppLanguage, mapNameResolver: MapNameResolver = .shared) {
        self.data = data
        self.maps = maps
        self.language = language
        self.mapNameResolver = mapNameResolver
    }

    func buildIndex() -> TrainerLocationIndex {
        guard !data.isEmpty, !maps.isEmpty else { return .empty }

        let scriptScanner = TrainerScriptReferenceScanner(data: data)
        var referencesByTrainerID: [Int: [TrainerLocationReference]] = [:]

        for map in maps {
            let terrainClassifier = TrainerMapTerrainClassifier(data: data, map: map)
            let point = MapPoint(group: map.group, map: map.mapID)
            let resolvedName = EmeraldGymLocationLayout.locationName(for: point, language: language)
                ?? mapNameResolver.mapName(group: map.group, map: map.mapID, language: language)
            guard let locationName = sanitizedLocation(resolvedName) else { continue }

            for object in map.objects {
                if let link = scriptScanner.trainerLink(for: object) {
                    append(
                        TrainerLocationReference(
                            trainerID: link.trainerID,
                            mapGroup: map.group,
                            mapID: map.mapID,
                            locationName: locationName,
                            source: .event,
                            objectLocalID: object.localID,
                            x: object.x,
                            y: object.y,
                            terrain: terrainClassifier.context(x: object.x, y: object.y),
                            requiresSurf: terrainClassifier.context(x: object.x, y: object.y) == .water,
                            scriptOffset: link.scriptOffset,
                            commandOffset: link.commandOffset
                        ),
                        to: &referencesByTrainerID
                    )
                }

                for scriptReference in scriptScanner.trainerReferences(in: object.scriptPointer) {
                    let terrain = terrainClassifier.context(x: object.x, y: object.y)
                    append(
                        reference(
                            from: scriptReference,
                            map: map,
                            locationName: locationName,
                            source: .script,
                            object: object,
                            terrain: terrain
                        ),
                        to: &referencesByTrainerID
                    )
                }
            }

            for event in map.coordinateEvents {
                for scriptReference in scriptScanner.trainerReferences(in: event.scriptPointer) {
                    append(reference(from: scriptReference, map: map, locationName: locationName, source: .script), to: &referencesByTrainerID)
                }
            }

            for event in map.backgroundEvents {
                for scriptReference in scriptScanner.trainerReferences(in: event.argument) {
                    append(reference(from: scriptReference, map: map, locationName: locationName, source: .script), to: &referencesByTrainerID)
                }
            }
        }

        let sorted = referencesByTrainerID.mapValues { $0.sorted(by: TrainerLocationIndex.sortReferences) }
        return TrainerLocationIndex(referencesByTrainerID: sorted)
    }

    private func reference(
        from scriptReference: TrainerScriptReference,
        map: MapData,
        locationName: String,
        source: TrainerLocationSource,
        object: MapObjectEvent? = nil,
        terrain: TrainerTerrainContext = .unknown
    ) -> TrainerLocationReference {
        TrainerLocationReference(
            trainerID: scriptReference.trainerID,
            mapGroup: map.group,
            mapID: map.mapID,
            locationName: locationName,
            source: source,
            objectLocalID: object?.localID,
            x: object?.x,
            y: object?.y,
            terrain: terrain,
            requiresSurf: terrain == .water,
            scriptOffset: scriptReference.scriptOffset,
            commandOffset: scriptReference.commandOffset
        )
    }

    private func append(_ reference: TrainerLocationReference, to referencesByTrainerID: inout [Int: [TrainerLocationReference]]) {
        var references = referencesByTrainerID[reference.trainerID, default: []]
        guard !references.contains(reference) else { return }
        references.append(reference)
        referencesByTrainerID[reference.trainerID] = references
    }

    private func sanitizedLocation(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("\\!") { return nil }
        if trimmed.count > 60 { return nil }
        if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return nil }
        return trimmed
    }
}

private struct TrainerMapTerrainClassifier {
    private static let virtualAddressBase: UInt32 = 0x0800_0000
    private static let secondaryMetatileStart = 512
    private static let waterBehaviors: Set<Int> = [
        0x10, // Pond water
        0x11, // Semi-deep water
        0x12, // Deep water
        0x13, // Waterfall
        0x14, // Ocean water
        0x15, // Puddle / shallow water
        0x16  // Shallow flowing water
    ]

    let data: Data
    let map: MapData
    let metatileByCoordinate: [Int: Int]

    init(data: Data, map: MapData) {
        self.data = data
        self.map = map
        metatileByCoordinate = Dictionary(
            uniqueKeysWithValues: map.blocks.map { ($0.y * map.width + $0.x, $0.metatileID) }
        )
    }

    func context(x: Int, y: Int) -> TrainerTerrainContext {
        guard let currentBehavior = behavior(x: x, y: y) else { return .unknown }
        if Self.waterBehaviors.contains(currentBehavior) { return .water }

        let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
        if neighbors.contains(where: { coordinates in
            guard let adjacent = behavior(x: coordinates.0, y: coordinates.1) else { return false }
            return Self.waterBehaviors.contains(adjacent)
        }) {
            return .coast
        }
        return .land
    }

    private func behavior(x: Int, y: Int) -> Int? {
        guard x >= 0, y >= 0, x < map.width, y < map.height,
              let metatileID = metatileByCoordinate[y * map.width + x] else {
            return nil
        }
        let usesSecondaryTileset = metatileID >= Self.secondaryMetatileStart
        let tilesetOffset = usesSecondaryTileset ? map.secondaryTilesetOffset : map.primaryTilesetOffset
        guard let tilesetOffset,
              let attributesOffset = pointerOffset(at: tilesetOffset + 16) else {
            return nil
        }
        let metatileIndex = usesSecondaryTileset
            ? metatileID - Self.secondaryMetatileStart
            : metatileID
        let attributeOffset = attributesOffset + metatileIndex * 4
        guard hasRange(attributeOffset, length: 4) else { return nil }
        return Int(readUInt32(at: attributeOffset) & 0x1FF)
    }

    private func pointerOffset(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let pointer = readUInt32(at: offset)
        guard pointer >= Self.virtualAddressBase && pointer < 0x0A00_0000 else { return nil }
        let result = Int(pointer - Self.virtualAddressBase)
        return hasRange(result, length: 4) ? result : nil
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func hasRange(_ offset: Int, length: Int) -> Bool {
        offset >= 0 && length >= 0 && offset + length <= data.count
    }
}

struct TrainerScriptReference: Equatable {
    let trainerID: Int
    let scriptOffset: Int
    let commandOffset: Int
}

struct TrainerScriptReferenceScanner {
    private enum Layout {
        static let trainerBattleCommand: UInt8 = 0x5C
        static let callCommand: UInt8 = 0x04
        static let gotoCommand: UInt8 = 0x05
        static let callIfCommand: UInt8 = 0x06
        static let gotoIfCommand: UInt8 = 0x07
        static let virtualAddressBase = 0x0800_0000
        static let scanLength = 384
        static let maxVisitedScripts = 24
        static let endCommands: Set<UInt8> = [0x02, 0x03]
    }

    let data: Data

    func trainerLink(for object: MapObjectEvent) -> MapObjectTrainerLink? {
        guard object.trainerType != 0 else { return nil }
        guard let first = trainerReferences(in: object.scriptPointer).first else { return nil }
        return MapObjectTrainerLink(trainerID: first.trainerID, scriptOffset: first.scriptOffset, commandOffset: first.commandOffset)
    }

    func trainerReferences(in pointer: UInt32) -> [TrainerScriptReference] {
        guard let scriptOffset = gbaPointerToROMOffset(pointer), hasRange(scriptOffset, length: 1) else { return [] }

        var visited = Set<Int>()
        var pending = [scriptOffset]
        var references: [TrainerScriptReference] = []

        while let currentScriptOffset = pending.popLast() {
            guard visited.count < Layout.maxVisitedScripts, !visited.contains(currentScriptOffset) else { continue }
            visited.insert(currentScriptOffset)

            let end = min(currentScriptOffset + Layout.scanLength, data.count)
            var offset = currentScriptOffset
            while offset < end {
                let command = data[offset]
                if Layout.endCommands.contains(command) { break }

                if command == Layout.trainerBattleCommand, hasRange(offset + 2, length: 2) {
                    let trainerID = readUInt16(at: offset + 2)
                    let reference = TrainerScriptReference(trainerID: trainerID, scriptOffset: currentScriptOffset, commandOffset: offset)
                    if !references.contains(reference) {
                        references.append(reference)
                    }
                    offset += 6
                    continue
                }

                if command == Layout.callCommand || command == Layout.gotoCommand, hasRange(offset + 1, length: 4) {
                    if let target = gbaPointerToROMOffset(readRawUInt32(at: offset + 1)) {
                        pending.append(target)
                    }
                    offset += 5
                    continue
                }

                if command == Layout.callIfCommand || command == Layout.gotoIfCommand, hasRange(offset + 2, length: 4) {
                    if let target = gbaPointerToROMOffset(readRawUInt32(at: offset + 2)) {
                        pending.append(target)
                    }
                    offset += 6
                    continue
                }

                offset += 1
            }
        }

        return references
    }

    private func gbaPointerToROMOffset(_ raw: UInt32) -> Int? {
        guard raw >= Layout.virtualAddressBase && raw < 0x0A00_0000 else { return nil }
        let offset = Int(raw - UInt32(Layout.virtualAddressBase))
        return hasRange(offset, length: 1) ? offset : nil
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func readRawUInt32(at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }
}
