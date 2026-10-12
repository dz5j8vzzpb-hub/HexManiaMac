import AppKit
import Foundation
import UniformTypeIdentifiers

struct ByteChange {
    let offset: Int
    let oldValue: UInt8
    let newValue: UInt8
}

enum MapEditProfiler {
    static func now() -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }

    static func log(_ label: String, since start: CFAbsoluteTime) {
        #if DEBUG
        let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard milliseconds >= 1 else { return }
        print(String(format: "[MapPerf] %@ %.2f ms", label, milliseconds))
        #endif
    }
}

struct ROMIdentity {
    let title: String
    let gameCode: String
    let makerCode: String
    let description: String
    let supported: Bool

    static func read(from data: Data) -> ROMIdentity {
        guard data.count >= 0xB2 else {
            return ROMIdentity(title: "Invalid ROM", gameCode: "—", makerCode: "—", description: "The file is too small to contain a GBA header.", supported: false)
        }

        func ascii(_ range: Range<Int>) -> String {
            String(bytes: data[range], encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters.union(.whitespaces)) ?? ""
        }

        let title = ascii(0xA0..<0xAC)
        let gameCode = ascii(0xAC..<0xB0)
        let maker = ascii(0xB0..<0xB2)
        let games: [String: String] = [
            "BPEE": "Pokémon Emerald (USA)",
            "BPEI": "Pokémon Emerald (ITA)",
            "AXVE": "Pokémon Ruby (USA)",
            "AXPE": "Pokémon Sapphire (USA)",
            "BPRE": "Pokémon FireRed (USA)",
            "BPGE": "Pokémon LeafGreen (USA)"
        ]
        return ROMIdentity(
            title: title.isEmpty ? "Untitled GBA ROM" : title,
            gameCode: gameCode.isEmpty ? "—" : gameCode,
            makerCode: maker.isEmpty ? "—" : maker,
            description: games[gameCode] ?? "Generic Game Boy Advance ROM",
            supported: games[gameCode] != nil
        )
    }
}

@MainActor
final class ROMDocument: ObservableObject {
    static let bytesPerRow = 16
    static let pageSize = 4096

    @Published private(set) var data = Data()
    @Published private(set) var fileURL: URL?
    @Published private(set) var identity = ROMIdentity(title: "No ROM open", gameCode: "—", makerCode: "—", description: "Open a legally obtained ROM copy to begin.", supported: false)
    @Published private(set) var isDirty = false
    @Published var editorMode: EditorMode = .home
    @Published var selectedOffset: Int?
    @Published var page = 0
    @Published var statusMessage = "Ready"
    @Published var isImporterPresented = false
    @Published var isSaveImporterPresented = false
    @Published var searchText = ""
    @Published var gotoText = ""
    @Published private(set) var pokemonSpecies: [PokemonSpecies] = []
    @Published private(set) var pokemonTypes: [PokemonNamedValue] = []
    @Published private(set) var pokemonAbilities: [PokemonNamedValue] = []
    @Published private(set) var moves: [MoveData] = []
    @Published private(set) var trainerClasses: [PokemonNamedValue] = []
    @Published private(set) var items: [PokemonNamedValue] = []
    @Published private(set) var itemData: [ItemData] = []
    @Published private(set) var trainers: [TrainerData] = []
    @Published private(set) var levelUpLearnsets: [Int: [LevelUpMove]] = [:]
    @Published private(set) var wildEncounterAreas: [WildEncounterArea] = []
    @Published private(set) var maps: [MapData] = []
    @Published private(set) var mapParsingDiagnostic = ""
    @Published private(set) var saveDocument: SaveDocument?
    @Published private(set) var linkedSaveROMURL: URL?
    @Published private(set) var swordShieldSession: SwordShieldGameSession?
    @Published private(set) var vanillaComparisonState: VanillaComparisonState = .unavailable

    private var undoStack: [ByteChange] = []
    private var redoStack: [ByteChange] = []
    private var savedData = Data()
    private var originalData = Data()
    private var pokemonSpriteCache: [Int: NSImage] = [:]
    private var trainerSpriteCache: [Int: NSImage] = [:]
    private var objectEventSpriteCache: [Int: NSImage] = [:]
    private var scriptAnalysisCache: [String: MapScriptAnalysis] = [:]
    private var mapImageCache: [MapData.ID: NSImage] = [:]
    private var mapMetatileImageCache: [String: NSImage] = [:]
    private var linkedSaveROMData = Data()
    private var linkedSaveROMSpriteCache: [Int: NSImage] = [:]
    private let linkedSaveROMBookmarkKey = "HexManiaMac.LinkedSaveReferenceROMBookmark"
    private let vanillaReferenceStore = VanillaReferenceStore()
    private var vanillaData = Data()
    private var vanillaSnapshot: VanillaSemanticSnapshot?

    init() {
        restoreLinkedSaveReferenceROM()
    }
    var isLoaded: Bool { !data.isEmpty }
    var playerSave: PlayerSaveData? { saveDocument?.parsed }
    var canSaveActiveDocument: Bool {
        switch editorMode {
        case .home, .teamCoach, .swordShield:
            false
        case .rom:
            isLoaded && isDirty
        case .save:
            saveDocument?.isDirty == true
        }
    }
    var canSaveAsActiveDocument: Bool {
        editorMode == .rom && isLoaded
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var pageCount: Int { max(1, (data.count + Self.pageSize - 1) / Self.pageSize) }
    var pageStart: Int { min(page * Self.pageSize, max(0, data.count - 1)) }
    var pageEnd: Int { min(pageStart + Self.pageSize, data.count) }

    func open(_ url: URL) {
        print("[ROM] Security scoped access requested")
        let accessing = url.startAccessingSecurityScopedResource()
        print("[ROM] Security scoped access: \(accessing)")
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            print("[ROM] Reading file")
            let loaded = try Data(contentsOf: url, options: .mappedIfSafe)
            print("[ROM] File size: \(loaded.count)")
            guard loaded.count >= 0xC0 else { throw ROMError.invalidFile }
            data = loaded
            savedData = loaded
            originalData = loaded
            isDirty = false
            fileURL = url
            identity = ROMIdentity.read(from: loaded)
            selectedOffset = 0
            page = 0
            undoStack.removeAll()
            redoStack.removeAll()
            pokemonSpriteCache.removeAll()
            trainerSpriteCache.removeAll()
            objectEventSpriteCache.removeAll()
            scriptAnalysisCache.removeAll()
            mapImageCache.removeAll()
            mapMetatileImageCache.removeAll()
            moves = []
            trainerClasses = []
            items = []
            itemData = []
            trainers = []
            levelUpLearnsets = [:]
            wildEncounterAreas = []
            maps = []
            mapParsingDiagnostic = ""
            print("[ROM] Parser started")
            loadSemanticTables()
            loadVanillaComparisonIfAvailable()
            print("[ROM] Parser completed")
            print("[ROM] Switching editor mode to ROM")
            editorMode = .rom
            statusMessage = "Opened \(url.lastPathComponent) — \(Self.formatSize(loaded.count))"
        } catch {
            present(error: error)
        }
    }

    func openSave(_ url: URL) {
        print("[SAVE] Security scoped access requested")
        let accessing = url.startAccessingSecurityScopedResource()
        print("[SAVE] Security scoped access: \(accessing)")
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            print("[SAVE] Reading file")
            let loaded = try Data(contentsOf: url, options: .mappedIfSafe)
            print("[SAVE] File size: \(loaded.count)")
            print("[SAVE] Parser started")
            let parsedSave = try EmeraldSaveParser(data: loaded, fileURL: url).parse()
            print("[SAVE] Parser completed")
            saveDocument = SaveDocument(data: loaded, fileURL: url, parsed: parsedSave)
            print("[SAVE] Switching editor mode to SAVE")
            editorMode = .save
            statusMessage = "Opened save \(parsedSave.fileName) — party \(parsedSave.party.count)/6"
        } catch {
            present(error: error)
        }
    }

    func openTeamCoach() {
        editorMode = .teamCoach
        statusMessage = "Team Coach"
    }

    func openSwordShieldDump(_ url: URL, expectedGame: SupportedGame) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let session = try SwordShieldGameLoader.load(rootURL: url, expectedGame: expectedGame)
            swordShieldSession = session
            editorMode = .swordShield
            statusMessage = "Aperto \(session.game.displayName) — Versione \(session.version)"
        } catch let error as SwordShieldLoaderError {
            swordShieldSession = nil
            statusMessage = error.localizedDescription
        } catch {
            swordShieldSession = nil
            statusMessage = error.localizedDescription
        }
    }

    func linkSaveReferenceROM() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "gba") ?? .data]
        panel.message = "Choose a Pokémon Emerald ROM to use as read-only graphics reference."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.loadLinkedSaveReferenceROM(from: url, persistBookmark: true)
            }
        }
    }

    private func restoreLinkedSaveReferenceROM() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: linkedSaveROMBookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            loadLinkedSaveReferenceROM(from: url, persistBookmark: isStale)
        } catch {
            UserDefaults.standard.removeObject(forKey: linkedSaveROMBookmarkKey)
            statusMessage = "Linked ROM bookmark could not be restored."
        }
    }

    private func loadLinkedSaveReferenceROM(from url: URL, persistBookmark: Bool) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let loaded = try Data(contentsOf: url, options: .mappedIfSafe)
            let identity = ROMIdentity.read(from: loaded)
            guard identity.supported, identity.gameCode.hasPrefix("BPE") else {
                statusMessage = "Choose a compatible Pokémon Emerald ROM."
                return
            }

            linkedSaveROMData = loaded
            linkedSaveROMURL = url
            linkedSaveROMSpriteCache.removeAll()

            if persistBookmark {
                let bookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmark, forKey: linkedSaveROMBookmarkKey)
            }

            statusMessage = "Linked ROM \(url.lastPathComponent) for Save Editor sprites."
        } catch {
            present(error: error)
        }
    }

    func closeActiveDocument() {
        switch editorMode {
        case .home:
            return
        case .rom:
            closeROM()
        case .save:
            closeSave()
        case .teamCoach:
            editorMode = .home
            statusMessage = "Ready"
        case .swordShield:
            closeSwordShield()
        }
    }

    func closeROM() {
        data = Data()
        savedData = Data()
        originalData = Data()
        fileURL = nil
        identity = ROMIdentity(title: "No ROM open", gameCode: "—", makerCode: "—", description: "Open a legally obtained ROM copy to begin.", supported: false)
        isDirty = false
        selectedOffset = nil
        page = 0
        undoStack.removeAll()
        redoStack.removeAll()
        pokemonSpriteCache.removeAll()
        trainerSpriteCache.removeAll()
        objectEventSpriteCache.removeAll()
        scriptAnalysisCache.removeAll()
        mapImageCache.removeAll()
        mapMetatileImageCache.removeAll()
        pokemonSpecies = []
        pokemonTypes = []
        pokemonAbilities = []
        moves = []
        trainerClasses = []
items = []
            itemData = []
            trainers = []
            levelUpLearnsets = [:]
            wildEncounterAreas = []
        maps = []
        mapParsingDiagnostic = ""
        vanillaData = Data()
        vanillaSnapshot = nil
        vanillaComparisonState = .unavailable
        if editorMode == .rom {
            editorMode = .home
        }
        statusMessage = "Ready"
    }

    func closeSave() {
        saveDocument = nil
        if editorMode == .save {
            editorMode = .home
        }
        statusMessage = "Ready"
    }

    func closeSwordShield() {
        swordShieldSession = nil
        if editorMode == .swordShield {
            editorMode = .home
        }
        statusMessage = "Ready"
    }

    func byte(at offset: Int) -> UInt8? {
        guard data.indices.contains(offset) else { return nil }
        return data[offset]
    }

    func editSelectedByte(hex: String) {
        guard let offset = selectedOffset,
              data.indices.contains(offset),
              let value = UInt8(hex.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) else {
            statusMessage = "Enter one byte from 00 to FF"
            return
        }
        apply(ByteChange(offset: offset, oldValue: data[offset], newValue: value), recording: true)
    }

    private func apply(_ change: ByteChange, recording: Bool) {
        guard data.indices.contains(change.offset), data[change.offset] != change.newValue else { return }
        data[change.offset] = change.newValue
        isDirty = true
        if recording {
            undoStack.append(change)
            redoStack.removeAll()
        }
        objectWillChange.send()
        statusMessage = String(format: "Changed 0x%08X: %02X → %02X", change.offset, change.oldValue, change.newValue)
    }

    func undo() {
        guard let change = undoStack.popLast() else { return }
        redoStack.append(change)
        apply(ByteChange(offset: change.offset, oldValue: change.newValue, newValue: change.oldValue), recording: false)
        isDirty = data != savedData
    }

    func redo() {
        guard let change = redoStack.popLast() else { return }
        undoStack.append(change)
        apply(change, recording: false)
        isDirty = data != savedData
    }

    var emeraldQoLPatchSummaries: [EmeraldQoLPatchSummary] {
        EmeraldQoLPatchCatalog.definitions.map { definition in
            EmeraldQoLPatchSummary(
                definition: definition,
                status: definition.status(in: data, gameCode: identity.gameCode)
            )
        }
    }

    func setEmeraldQoLPatch(_ id: EmeraldQoLPatchID, enabled: Bool) {
        guard let definition = EmeraldQoLPatchCatalog.definition(id: id) else { return }
        let currentStatus = definition.status(in: data, gameCode: identity.gameCode)

        if enabled, currentStatus == .applied { return }
        if !enabled, currentStatus == .vanilla { return }
        guard currentStatus != .incompatible,
              let patches = definition.replacementPatches(for: identity.gameCode, enabled: enabled, in: data) else {
            statusMessage = "Patch non compatibile con questa ROM/versione."
            return
        }

        guard patches.allSatisfy({ dataMatches($0.originalBytes, at: $0.offset) }) else {
            statusMessage = "Patch non compatibile con questa ROM/versione."
            return
        }

        var changes: [ByteChange] = []
        for patch in patches {
            for index in patch.patchedBytes.indices {
                let offset = patch.offset + index
                let oldValue = data[offset]
                let newValue = patch.patchedBytes[index]
                if oldValue != newValue {
                    changes.append(ByteChange(offset: offset, oldValue: oldValue, newValue: newValue))
                }
            }
        }
        guard !changes.isEmpty else { return }

        objectWillChange.send()
        for change in changes {
            data[change.offset] = change.newValue
        }
        undoStack.append(contentsOf: changes)
        redoStack.removeAll()
        isDirty = data != savedData
        statusMessage = enabled ? "Patch applicata: \(definition.name)" : "Patch ripristinata: \(definition.name)"
    }

    private func dataMatches(_ bytes: [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + bytes.count <= data.count else { return false }
        return Array(data[offset..<(offset + bytes.count)]) == bytes
    }

    func goToOffset() {
        var input = gotoText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if input.hasPrefix("0x") { input.removeFirst(2) }
        let parsed = Int(input, radix: 16) ?? Int(input)
        guard let offset = parsed, data.indices.contains(offset) else {
            statusMessage = "Offset outside ROM"
            return
        }
        select(offset)
    }

    func select(_ offset: Int) {
        guard data.indices.contains(offset) else { return }
        selectedOffset = offset
        page = offset / Self.pageSize
        gotoText = String(format: "%X", offset)
    }

    func searchNext() {
        guard let needle = searchBytes(from: searchText), !needle.isEmpty else {
            statusMessage = "Search with text or bytes such as DE AD BE EF"
            return
        }
        let start = min((selectedOffset ?? -1) + 1, data.count)
        if let range = data.range(of: needle, options: [], in: start..<data.count) ?? data.range(of: needle, options: [], in: 0..<start) {
            select(range.lowerBound)
            statusMessage = String(format: "Found at 0x%08X", range.lowerBound)
        } else {
            statusMessage = "No match"
        }
    }

    private func searchBytes(from input: String) -> Data? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "," })
        if tokens.count > 1, tokens.allSatisfy({ $0.count <= 2 && UInt8($0, radix: 16) != nil }) {
            return Data(tokens.compactMap { UInt8($0, radix: 16) })
        }
        if trimmed.count == 2, let byte = UInt8(trimmed, radix: 16) { return Data([byte]) }
        return trimmed.data(using: .utf8)
    }

    func updatePokemonSpecies(_ species: PokemonSpecies) {
        guard let index = pokemonSpecies.firstIndex(where: { $0.id == species.id }) else { return }
        do {
            var editedData = data
            try PokemonTableParser.write(species, into: &editedData)
            data = editedData
            pokemonSpecies[index] = species
            refreshPokemonVanillaStatus(species)
            isDirty = true
            statusMessage = "Updated \(species.name)"
            // logChangedByteSummary(context: "Pokémon edit")
        } catch {
            present(error: error)
        }
    }

    func showPokemonInHex(_ species: PokemonSpecies) {
        select(species.statsOffset)
    }

    func updateMove(_ move: MoveData) {
        guard let index = moves.firstIndex(where: { $0.id == move.id }) else { return }
        do {
            var editedData = data
            try MoveTableParser.write(move, into: &editedData)
            data = editedData
            moves[index] = move
            refreshMoveVanillaStatus(move)
            isDirty = data != savedData
            statusMessage = "Updated \(move.name)"
            logChangedByteSummary(context: "Move edit")
        } catch {
            present(error: error)
        }
    }

    func showMoveInHex(_ move: MoveData) {
        select(move.statsOffset)
    }

    func updateTrainer(_ trainer: TrainerData) {
        guard let index = trainers.firstIndex(where: { $0.id == trainer.id }) else { return }
        do {
            var editedData = data
            try TrainerTableParser.write(trainer, into: &editedData)
            let reloadedTrainer = (try? TrainerTableParser(data: editedData).parseTrainers().first { $0.id == trainer.id }) ?? trainer
            data = editedData
            trainers[index] = reloadedTrainer
            refreshTrainerVanillaStatus(reloadedTrainer)
            isDirty = data != savedData
            statusMessage = "Updated \(reloadedTrainer.name)"
        } catch {
            present(error: error)
        }
    }

    func showTrainerInHex(_ trainer: TrainerData) {
        select(trainer.entryOffset)
    }

    func showTrainerPartyInHex(_ trainer: TrainerData) {
        select(trainer.partyOffset)
    }

    func updateItem(_ item: ItemData) {
        guard let index = itemData.firstIndex(where: { $0.id == item.id }) else { return }
        do {
            var editedData = data
            try ItemTableParser.write(item, into: &editedData)
            data = editedData
            itemData[index] = item
            refreshItemVanillaStatus(item)
            items = itemData.map { PokemonNamedValue(id: $0.id, name: $0.name.isEmpty ? "Item #\($0.id)" : $0.name) }
            isDirty = data != savedData
            statusMessage = "Updated \(item.name)"
        } catch {
            present(error: error)
        }
    }

    func showItemInHex(_ item: ItemData) {
        select(item.statsOffset)
    }

    func updateWildEncounterArea(_ area: WildEncounterArea) {
        guard let index = wildEncounterAreas.firstIndex(where: { $0.id == area.id }) else { return }
        do {
            var editedData = data
            try WildEncounterTableParser.write(area, into: &editedData)
            data = editedData
            wildEncounterAreas[index] = area
            refreshEncounterVanillaStatus(area)
            isDirty = data != savedData
            statusMessage = "Updated \(area.displayName)"
        } catch {
            present(error: error)
        }
    }

    func showWildEncounterAreaInHex(_ area: WildEncounterArea) {
        select(area.tableOffset)
    }

    func updateMapBlock(_ block: MapBlockCell, in map: MapData) {
        updateMapBlocks([block], in: map)
    }

    func updateMapBlocks(_ blocks: [MapBlockCell], in map: MapData) {
        let totalStart = MapEditProfiler.now()
        guard let mapIndex = maps.firstIndex(where: { $0.id == map.id }),
              !blocks.isEmpty else { return }
        do {
            let writerStart = MapEditProfiler.now()
            var editedData = data
            for block in blocks {
                try MapTableParser.writeBlock(block, into: &editedData)
            }
            refreshMapVanillaStatus(maps[mapIndex])
            data = editedData
            MapEditProfiler.log("map writer update", since: writerStart)

            let modelStart = MapEditProfiler.now()
            var blockIndexes: [MapBlockCell.ID: Int] = [:]
            blockIndexes.reserveCapacity(maps[mapIndex].blocks.count)
            for index in maps[mapIndex].blocks.indices {
                blockIndexes[maps[mapIndex].blocks[index].id] = index
            }
            for block in blocks {
                guard let blockIndex = blockIndexes[block.id] else { continue }
                maps[mapIndex].blocks[blockIndex] = block
                patchCachedMapImage(for: block, in: maps[mapIndex])
            }
            isDirty = data != savedData
            statusMessage = blocks.count == 1
                ? "Updated \(MapNameResolver.shared.mapName(group: map.group, map: map.mapID)) block \(blocks[0].x),\(blocks[0].y)"
                : "Updated \(MapNameResolver.shared.mapName(group: map.group, map: map.mapID)) blocks: \(blocks.count)"
            MapEditProfiler.log("map model/cache update", since: modelStart)
            MapEditProfiler.log("paint operation", since: totalStart)
        } catch {
            present(error: error)
        }
    }

    func restoreOriginalMap(_ map: MapData) {
        guard let mapIndex = maps.firstIndex(where: { $0.id == map.id }) else {
            present(error: ROMError.unsafeMapRestore("The selected map no longer exists."))
            return
        }

        do {
            let originalMaps = try EmeraldROM(data: originalData).maps()
            guard let originalMap = originalMaps.first(where: { $0.id == map.id }) else {
                throw ROMError.unsafeMapRestore("The selected map was not found in the original ROM snapshot.")
            }
            try validateRestoreCompatibility(current: maps[mapIndex], original: originalMap)

            var editedData = data
            for block in originalMap.blocks {
                try MapTableParser.writeBlock(block, into: &editedData)
            }
            for object in originalMap.objects {
                try MapTableParser.writeObject(object, into: &editedData)
            }
            for warp in originalMap.warps {
                try MapTableParser.writeWarp(warp, into: &editedData)
            }

            data = editedData
            var restoredMap = maps[mapIndex]
            restoredMap.blocks = originalMap.blocks
            restoredMap.objects = originalMap.objects
            restoredMap.warps = originalMap.warps
            maps[mapIndex] = restoredMap
            refreshMapVanillaStatus(restoredMap)
            mapImageCache.removeValue(forKey: mapImageCacheKey(for: restoredMap))
            objectEventSpriteCache.removeAll()
            scriptAnalysisCache.removeAll()
            isDirty = data != savedData
            statusMessage = "Restored original map: \(MapNameResolver.shared.mapName(group: restoredMap.group, map: restoredMap.mapID))"
        } catch {
            present(error: error)
        }
    }

    private func validateRestoreCompatibility(current: MapData, original: MapData) throws {
        guard current.width == original.width,
              current.height == original.height,
              current.blockmapOffset == original.blockmapOffset,
              current.blocks.count == original.blocks.count else {
            throw ROMError.unsafeMapRestore("The selected map layout no longer matches the original ROM snapshot.")
        }
        guard zip(current.blocks, original.blocks).allSatisfy({ currentBlock, originalBlock in
            currentBlock.id == originalBlock.id && currentBlock.offset == originalBlock.offset
        }) else {
            throw ROMError.unsafeMapRestore("The selected map block structure is not compatible with the original ROM snapshot.")
        }
        guard current.objects.count == original.objects.count,
              zip(current.objects, original.objects).allSatisfy({ $0.id == $1.id && $0.offset == $1.offset }) else {
            throw ROMError.unsafeMapRestore("The selected map object events are not compatible with the original ROM snapshot.")
        }
        guard current.warps.count == original.warps.count,
              zip(current.warps, original.warps).allSatisfy({ $0.id == $1.id && $0.offset == $1.offset }) else {
            throw ROMError.unsafeMapRestore("The selected map warp events are not compatible with the original ROM snapshot.")
        }
    }

    func updateMapObject(_ object: MapObjectEvent, in map: MapData) {
        guard let mapIndex = maps.firstIndex(where: { $0.id == map.id }),
              let objectIndex = maps[mapIndex].objects.firstIndex(where: { $0.id == object.id }) else { return }
        do {
            var editedData = data
            try MapTableParser.writeObject(object, into: &editedData)
            data = editedData
            if maps[mapIndex].objects[objectIndex].graphicsID != object.graphicsID {
                objectEventSpriteCache.removeValue(forKey: maps[mapIndex].objects[objectIndex].graphicsID)
                objectEventSpriteCache.removeValue(forKey: object.graphicsID)
            }
            maps[mapIndex].objects[objectIndex] = object
            refreshMapVanillaStatus(maps[mapIndex])
            isDirty = data != savedData
            statusMessage = "Updated \(MapNameResolver.shared.mapName(group: map.group, map: map.mapID)) object #\(object.id + 1)"
        } catch {
            present(error: error)
        }
    }

    func updateMapWarp(_ warp: MapWarpEvent, in map: MapData) {
        guard let mapIndex = maps.firstIndex(where: { $0.id == map.id }),
              let warpIndex = maps[mapIndex].warps.firstIndex(where: { $0.id == warp.id }) else { return }
        do {
            var editedData = data
            try MapTableParser.writeWarp(warp, into: &editedData)
            data = editedData
            maps[mapIndex].warps[warpIndex] = warp
            refreshMapVanillaStatus(maps[mapIndex])
            isDirty = data != savedData
            statusMessage = "Updated \(MapNameResolver.shared.mapName(group: map.group, map: map.mapID)) warp #\(warp.id + 1)"
            logChangedByteSummary(context: "Map warp edit")
        } catch {
            present(error: error)
        }
    }

    func showMapHeaderInHex(_ map: MapData) {
        select(map.headerOffset)
    }

    func showMapLayoutInHex(_ map: MapData) {
        select(map.layoutOffset)
    }

    func showMapEventsInHex(_ map: MapData) {
        guard let eventsOffset = map.eventsOffset else { return }
        select(eventsOffset)
    }

    func showMapTilesetInHex(_ map: MapData) {
        if let primaryTilesetOffset = map.primaryTilesetOffset {
            select(primaryTilesetOffset)
        }
    }

    func mapImage(for map: MapData) -> NSImage? {
        let start = MapEditProfiler.now()
        defer { MapEditProfiler.log("map image lookup/render", since: start) }
        let key = mapImageCacheKey(for: map)
        if let cached = mapImageCache[key] { return cached }
        let image = EmeraldROM(data: data).mapImage(for: map)
        if let image {
            mapImageCache[key] = image
        }
        return image
    }

    func mapMetatileImage(for metatileID: Int, in map: MapData) -> NSImage? {
        let start = MapEditProfiler.now()
        defer { MapEditProfiler.log("metatile image lookup/render", since: start) }
        let key = "\(mapTilesetCacheKey(for: map))-\(metatileID)"
        if let cached = mapMetatileImageCache[key] { return cached }
        let image = EmeraldROM(data: data).mapMetatileImage(for: metatileID, in: map)
        if let image {
            mapMetatileImageCache[key] = image
        }
        return image
    }

    private func mapImageCacheKey(for map: MapData) -> String {
        "\(map.id)-layout:\(map.layoutOffset)-blockmap:\(map.blockmapOffset)-\(mapTilesetCacheKey(for: map))"
    }

    private func mapTilesetCacheKey(for map: MapData) -> String {
        "\(map.primaryTilesetOffset ?? -1)-\(map.secondaryTilesetOffset ?? -1)"
    }

    private func patchCachedMapImage(for block: MapBlockCell, in map: MapData) {
        let start = MapEditProfiler.now()
        defer { MapEditProfiler.log("incremental map image patch", since: start) }
        let key = mapImageCacheKey(for: map)
        guard let cachedImage = mapImageCache[key],
              let mapBitmap = cachedImage.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let mapPixels = mapBitmap.bitmapData,
              let tileImage = mapMetatileImage(for: block.metatileID, in: map),
              let tileBitmap = tileImage.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let tilePixels = tileBitmap.bitmapData,
              mapBitmap.pixelsWide >= (block.x + 1) * 16,
              mapBitmap.pixelsHigh >= (block.y + 1) * 16,
              tileBitmap.pixelsWide >= 16,
              tileBitmap.pixelsHigh >= 16 else { return }

        let bytesPerPixel = 4
        let tileSide = 16
        guard let patchedBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: mapBitmap.pixelsWide,
            pixelsHigh: mapBitmap.pixelsHigh,
            bitsPerSample: mapBitmap.bitsPerSample,
            samplesPerPixel: mapBitmap.samplesPerPixel,
            hasAlpha: mapBitmap.hasAlpha,
            isPlanar: false,
            colorSpaceName: mapBitmap.colorSpaceName,
            bytesPerRow: mapBitmap.bytesPerRow,
            bitsPerPixel: mapBitmap.bitsPerPixel
        ), let patchedPixels = patchedBitmap.bitmapData else { return }

        for row in 0..<mapBitmap.pixelsHigh {
            let source = row * mapBitmap.bytesPerRow
            let destination = row * patchedBitmap.bytesPerRow
            for byte in 0..<mapBitmap.bytesPerRow {
                patchedPixels[destination + byte] = mapPixels[source + byte]
            }
        }

        for row in 0..<tileSide {
            let destination = (block.y * tileSide + row) * patchedBitmap.bytesPerRow + block.x * tileSide * bytesPerPixel
            let source = row * tileBitmap.bytesPerRow
            for byte in 0..<(tileSide * bytesPerPixel) {
                patchedPixels[destination + byte] = tilePixels[source + byte]
            }
        }

        let patchedImage = NSImage(size: cachedImage.size)
        patchedImage.addRepresentation(patchedBitmap)
        mapImageCache[key] = patchedImage
    }

    func runMapParserDiagnostic() {
        guard isLoaded else {
            mapParsingDiagnostic = "Map parser diagnostic\nROM loaded: false"
            return
        }
        mapParsingDiagnostic = EmeraldROM(data: data).mapParserDiagnosticReport()
        print("[HexManiaMac Maps Diagnostic]\n\(mapParsingDiagnostic)")
    }

    func debugByteDiffReport(limit: Int = 32) -> String {
        let report = ROMDiffReport.compare(original: originalData, modified: data)
        let deltas = report.changedBytes
            .prefix(limit)
            .map { change in
                String(format: "0x%08X: %02X -> %02X", change.offset, change.oldValue, change.newValue)
            }
            .joined(separator: "\n")
        return [report.summary(), deltas].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func runIntegrityQA() {
        guard isLoaded else {
            print("[HexManiaMac QA] No ROM loaded")
            return
        }
        print("[HexManiaMac QA]\n\(ROMIntegrityTestSuite.report(on: data))")
    }

    func pokemonSprite(for species: PokemonSpecies) -> NSImage? {
        if let cached = pokemonSpriteCache[species.id] { return cached }
        guard let sprite = EmeraldROM(data: data).pokemonSprite(for: species.id) else { return nil }
        pokemonSpriteCache[species.id] = sprite
        return sprite
    }

    func pokemonSprite(forSpeciesID speciesID: Int) -> NSImage? {
        if let cached = pokemonSpriteCache[speciesID] { return cached }
        guard isLoaded,
              let sprite = EmeraldROM(data: data).pokemonSprite(for: speciesID) else { return nil }
        pokemonSpriteCache[speciesID] = sprite
        return sprite
    }

    func linkedSavePokemonSprite(forSpeciesID speciesID: Int) -> NSImage? {
        if let cached = linkedSaveROMSpriteCache[speciesID] { return cached }
        guard !linkedSaveROMData.isEmpty,
              let sprite = EmeraldROM(data: linkedSaveROMData).pokemonSprite(for: speciesID) else { return nil }
        linkedSaveROMSpriteCache[speciesID] = sprite
        return sprite
    }

    func referenceSpeciesName(id: Int) -> String {
        pokemonSpecies.first { $0.id == id }?.name
            ?? Self.fallbackSpeciesNames[id]
            ?? "Species #\(id)"
    }

    func referenceMoveName(id: Int) -> String {
        guard id != 0 else { return "Nessuna" }
        return moves.first { $0.id == id }?.name
            ?? Self.fallbackMoveNames[id]
            ?? "Move #\(id)"
    }

    func referenceItemName(id: Int) -> String {
        guard id != 0 else { return "Nessuno" }
        return items.first { $0.id == id }?.name
            ?? Self.fallbackItemNames[id]
            ?? "Item #\(id)"
    }

    func referencePokeballName(id: Int) -> String {
        Self.fallbackPokeballNames[id] ?? "Poké Ball #\(id)"
    }

    func referenceLocationName(id: Int) -> String {
        Self.fallbackLocationNames[id] ?? "#\(id)"
    }

    func referenceMoveOptions(including selectedID: Int) -> [PokemonNamedValue] {
        referenceOptions(
            primary: moves.map { PokemonNamedValue(id: $0.id, name: $0.name) },
            fallback: Self.fallbackMoveNames,
            including: selectedID,
            zeroName: "Nessuna",
            fallbackPrefix: "Move"
        )
    }

    func referenceItemOptions(including selectedID: Int) -> [PokemonNamedValue] {
        referenceOptions(
            primary: items,
            fallback: Self.fallbackItemNames,
            including: selectedID,
            zeroName: "Nessuno",
            fallbackPrefix: "Item"
        )
    }

    private func referenceOptions(primary: [PokemonNamedValue], fallback: [Int: String], including selectedID: Int, zeroName: String, fallbackPrefix: String) -> [PokemonNamedValue] {
        var keyed = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0.name) })
        keyed[0] = zeroName
        for (id, name) in fallback where keyed[id] == nil {
            keyed[id] = name
        }
        if keyed[selectedID] == nil {
            keyed[selectedID] = selectedID == 0 ? zeroName : "\(fallbackPrefix) #\(selectedID)"
        }
        return keyed
            .map { PokemonNamedValue(id: $0.key, name: $0.value) }
            .sorted { $0.id < $1.id }
    }

    func trainerSprite(for trainer: TrainerData) -> NSImage? {
        if let cached = trainerSpriteCache[trainer.sprite] { return cached }
        guard let sprite = EmeraldROM(data: data).trainerSprite(for: trainer.sprite) else { return nil }
        trainerSpriteCache[trainer.sprite] = sprite
        return sprite
    }

    func objectEventSprite(for object: MapObjectEvent) -> NSImage? {
        if let cached = objectEventSpriteCache[object.graphicsID] { return cached }
        guard let sprite = EmeraldROM(data: data).objectEventSprite(for: object.graphicsID) else { return nil }
        objectEventSpriteCache[object.graphicsID] = sprite
        return sprite
    }

    func trainerLink(for object: MapObjectEvent) -> MapObjectTrainerLink? {
        EmeraldROM(data: data).trainerLink(for: object)
    }

    func trainerLinks(for object: MapObjectEvent) -> [MapObjectTrainerLink] {
        guard object.trainerType != 0 else { return [] }
        return TrainerScriptReferenceScanner(data: data).trainerReferences(in: object.scriptPointer).map {
            MapObjectTrainerLink(trainerID: $0.trainerID, scriptOffset: $0.scriptOffset, commandOffset: $0.commandOffset)
        }
    }

    func scriptAnalysis(pointer: UInt32, eventType: String) -> MapScriptAnalysis {
        let key = "\(eventType)-\(pointer)"
        if let cached = scriptAnalysisCache[key] { return cached }
        let analysis = EmeraldROM(data: data).scriptAnalysis(pointer: pointer, eventType: eventType)
        scriptAnalysisCache[key] = analysis
        return analysis
    }

    func save() {
        guard let fileURL else { saveAs(); return }
        write(to: fileURL, backingUp: true)
    }

    func saveActiveDocument() {
        switch editorMode {
        case .home, .teamCoach, .swordShield:
            return
        case .rom:
            save()
        case .save:
            saveSaveDocument()
        }
    }

    func updatePlayerPartyPokemon(_ pokemon: PlayerPartyPokemon) {
        guard var saveDocument,
              saveDocument.parsed.party.contains(where: { $0.id == pokemon.id }) else { return }
        do {
            var editedData = saveDocument.data
            try EmeraldSaveParser.writePartyPokemon(
                pokemon,
                into: &editedData,
                saveBlock1SectionOffset: saveDocument.parsed.saveBlock1SectionOffset
            )
            let reparsed = try EmeraldSaveParser(data: editedData, fileURL: saveDocument.fileURL).parse()
            saveDocument.data = editedData
            saveDocument.parsed = reparsed
            saveDocument.isDirty = true
            self.saveDocument = saveDocument
            statusMessage = "Updated \(pokemon.nickname)"
        } catch {
            present(error: error)
        }
    }

    func updateSaveBagItem(pocket: SaveBagPocketKind, slot: Int, itemID: Int, quantity: Int) {
        guard var saveDocument,
              let parsedPocket = saveDocument.parsed.bagPockets.first(where: { $0.kind == pocket }),
              (0..<parsedPocket.capacity).contains(slot) else { return }
        do {
            var editedData = saveDocument.data
            try EmeraldSaveParser.writeBagItem(
                pocket: pocket,
                slot: slot,
                itemID: itemID,
                quantity: quantity,
                into: &editedData,
                saveBlock1SectionOffset: saveDocument.parsed.saveBlock1SectionOffset,
                securityKey: saveDocument.parsed.trainer.securityKey ?? 0
            )
            let reparsed = try EmeraldSaveParser(data: editedData, fileURL: saveDocument.fileURL).parse()
            saveDocument.data = editedData
            saveDocument.parsed = reparsed
            saveDocument.isDirty = true
            self.saveDocument = saveDocument
            statusMessage = "Updated bag"
        } catch {
            present(error: error)
        }
    }

    func updatePokedexEntry(speciesID: Int, seen: Bool, caught: Bool) {
        guard var saveDocument,
              saveDocument.parsed.pokedex?.entries.contains(where: { $0.id == speciesID }) == true,
              let trainerSectionOffset = saveDocument.parsed.sections.first(where: { $0.sectionID == 0 })?.offset else { return }
        do {
            var editedData = saveDocument.data
            try EmeraldSaveParser.writePokedexEntry(
                speciesID: speciesID,
                seen: seen,
                caught: caught,
                into: &editedData,
                trainerSectionOffset: trainerSectionOffset
            )
            let reparsed = try EmeraldSaveParser(data: editedData, fileURL: saveDocument.fileURL).parse()
            saveDocument.data = editedData
            saveDocument.parsed = reparsed
            saveDocument.isDirty = true
            self.saveDocument = saveDocument
            statusMessage = "Updated Pokédex"
        } catch {
            present(error: error)
        }
    }

    func updatePokedexEntries(_ entries: [SavePokedexEntry]) {
        guard var saveDocument,
              let currentEntries = saveDocument.parsed.pokedex?.entries,
              !entries.isEmpty,
              entries.allSatisfy({ entry in currentEntries.contains(where: { $0.id == entry.id }) }),
              let trainerSectionOffset = saveDocument.parsed.sections.first(where: { $0.sectionID == 0 })?.offset else { return }
        do {
            var editedData = saveDocument.data
            try EmeraldSaveParser.writePokedexEntries(
                entries,
                into: &editedData,
                trainerSectionOffset: trainerSectionOffset
            )
            let reparsed = try EmeraldSaveParser(data: editedData, fileURL: saveDocument.fileURL).parse()
            saveDocument.data = editedData
            saveDocument.parsed = reparsed
            saveDocument.isDirty = true
            self.saveDocument = saveDocument
            statusMessage = "Updated Pokédex"
        } catch {
            present(error: error)
        }
    }

    private func saveSaveDocument() {
        guard var saveDocument else { return }
        do {
            try createSaveBackupIfNeeded(of: saveDocument.fileURL)
            let temporaryURL = saveDocument.fileURL
                .deletingLastPathComponent()
                .appendingPathComponent(".\(saveDocument.fileURL.lastPathComponent).tmp")
            try saveDocument.data.write(to: temporaryURL, options: .atomic)
            _ = try EmeraldSaveParser(data: Data(contentsOf: temporaryURL), fileURL: saveDocument.fileURL).parse()
            let fm = FileManager.default
            if fm.fileExists(atPath: saveDocument.fileURL.path) {
                _ = try fm.replaceItemAt(saveDocument.fileURL, withItemAt: temporaryURL)
            } else {
                try fm.moveItem(at: temporaryURL, to: saveDocument.fileURL)
            }
            saveDocument.isDirty = false
            saveDocument.parsed = try EmeraldSaveParser(data: saveDocument.data, fileURL: saveDocument.fileURL).parse()
            self.saveDocument = saveDocument
            statusMessage = "Saved \(saveDocument.fileURL.lastPathComponent)"
        } catch {
            present(error: error)
        }
    }

    func saveAs() {
        guard isLoaded else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gba") ?? .data]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "edited.gba"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { write(to: url, backingUp: url == fileURL) }
    }

    private func loadSemanticTables() {
        let emerald = EmeraldROM(data: data)
        guard emerald.isSupported else {
            pokemonSpecies = []
            pokemonTypes = []
            pokemonAbilities = []
            moves = []
            trainerClasses = []
            items = []
            itemData = []
            trainers = []
            levelUpLearnsets = [:]
            wildEncounterAreas = []
            maps = []
            mapParsingDiagnostic = ""
            return
        }

        do {
            pokemonSpecies = try emerald.pokemonSpecies()
            pokemonTypes = try emerald.pokemonTypes()
            pokemonAbilities = try emerald.pokemonAbilities()
            moves = try emerald.moves()
            trainerClasses = try emerald.trainerClasses()
            do {
                items = try emerald.items()
            } catch {
                items = []
            }
            do {
                itemData = try emerald.itemData()
            } catch {
                itemData = []
            }
            do {
                trainers = try emerald.trainers()
            } catch {
                trainers = []
            }
            do {
                levelUpLearnsets = try emerald.levelUpLearnsets()
            } catch {
                levelUpLearnsets = [:]
            }
            do {
                wildEncounterAreas = try emerald.wildEncounterAreas()
            } catch {
                wildEncounterAreas = []
            }
            do {
                maps = try emerald.maps()
                mapParsingDiagnostic = emerald.mapParserDiagnosticReport()
            } catch {
                maps = []
                if let mapError = error as? MapParsingError {
                    mapParsingDiagnostic = mapError.report
                } else {
                    mapParsingDiagnostic = emerald.mapParserDiagnosticReport()
                }
                statusMessage = "Impossibile leggere la tabella mappe. Vedi console per i dettagli tecnici."
            }
        } catch {
            pokemonSpecies = []
            pokemonTypes = []
            pokemonAbilities = []
            moves = []
            trainerClasses = []
            items = []
            itemData = []
            trainers = []
            levelUpLearnsets = [:]
            wildEncounterAreas = []
            maps = []
            mapParsingDiagnostic = ""
            statusMessage = error.localizedDescription
        }
    }

    func configureVanillaReference() {
        guard isLoaded else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "gba") ?? .data]
        panel.message = "Seleziona la ROM originale corrispondente. Verrà copiata come riferimento di sola lettura."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    let currentIdentity = ROMVersionIdentity(data: self.data)
                    _ = try self.vanillaReferenceStore.importReference(from: url, matching: currentIdentity)
                    self.loadVanillaComparisonIfAvailable()
                    self.statusMessage = "Riferimento Vanilla configurato per \(currentIdentity.storageKey)."
                } catch {
                    self.present(error: error)
                }
            }
        }
    }

    var vanillaChangeSet: VanillaChangeSet? {
        guard case .available(let changeSet) = vanillaComparisonState else { return nil }
        return changeSet
    }

    var hasVanillaReference: Bool {
        if case .available = vanillaComparisonState { return true }
        return false
    }

    var vanillaReferenceURL: URL? {
        guard isLoaded else { return nil }
        return vanillaReferenceStore.referenceURL(for: ROMVersionIdentity(data: data))
    }

    func revealVanillaReference() {
        guard let vanillaReferenceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([vanillaReferenceURL])
    }

    func isPokemonModified(_ id: Int) -> Bool { vanillaChangeSet?.pokemonIDs.contains(id) == true }
    func isMoveModified(_ id: Int) -> Bool { vanillaChangeSet?.moveIDs.contains(id) == true }
    func isTrainerModified(_ id: Int) -> Bool { vanillaChangeSet?.trainerIDs.contains(id) == true }
    func isItemModified(_ id: Int) -> Bool { vanillaChangeSet?.itemIDs.contains(id) == true }
    func isEncounterAreaModified(_ id: Int) -> Bool { vanillaChangeSet?.encounterAreaIDs.contains(id) == true }
    func isEncounterGroupModified(areaID: Int, kind: WildEncounterKind) -> Bool {
        vanillaChangeSet?.encounterGroupIDs.contains(VanillaEncounterGroupID(areaID: areaID, kind: kind)) == true
    }
    func isMapModified(_ id: MapData.ID) -> Bool { vanillaChangeSet?.mapIDs.contains(id) == true }

    func supportsVanillaComparison(_ category: VanillaCategory) -> Bool {
        guard let changeSet = vanillaChangeSet else { return false }
        return !changeSet.unverifiableCategories.contains(category)
    }

    private func loadVanillaComparisonIfAvailable() {
        guard EmeraldROM(data: data).isSupported else {
            vanillaComparisonState = .incompatible
            return
        }
        do {
            let version = ROMVersionIdentity(data: data)
            guard let reference = try vanillaReferenceStore.referenceData(for: version) else {
                vanillaData = Data()
                vanillaSnapshot = nil
                vanillaComparisonState = .unavailable
                return
            }
            guard ROMVersionIdentity(data: reference) == version else {
                vanillaComparisonState = .incompatible
                return
            }
            vanillaComparisonState = .comparing
            vanillaData = reference
            let referenceSnapshot = VanillaSemanticSnapshot(data: reference)
            vanillaSnapshot = referenceSnapshot
            refreshAllVanillaStatuses()
        } catch {
            vanillaComparisonState = .failed(error.localizedDescription)
        }
    }

    private func refreshAllVanillaStatuses() {
        guard let vanillaSnapshot else { return }
        let current = VanillaSemanticSnapshot(data: data)
        vanillaComparisonState = .available(VanillaComparisonEngine.compare(current: current, vanilla: vanillaSnapshot))
    }

    private func updateVanillaChangeSet(_ update: (inout VanillaChangeSet) -> Void) {
        guard case .available(var changeSet) = vanillaComparisonState else { return }
        update(&changeSet)
        vanillaComparisonState = .available(changeSet)
    }

    private func refreshPokemonVanillaStatus(_ value: PokemonSpecies) {
        guard let vanilla = vanillaSnapshot?.pokemon?[value.id] else { return }
        updateVanillaChangeSet { setMembership(&$0.pokemonIDs, id: value.id, changed: PokemonSignature(value) != vanilla) }
    }

    private func refreshMoveVanillaStatus(_ value: MoveData) {
        guard let vanilla = vanillaSnapshot?.moves?[value.id] else { return }
        updateVanillaChangeSet { setMembership(&$0.moveIDs, id: value.id, changed: MoveSignature(value) != vanilla) }
    }

    private func refreshTrainerVanillaStatus(_ value: TrainerData) {
        guard let vanilla = vanillaSnapshot?.trainers?[value.id] else { return }
        updateVanillaChangeSet { setMembership(&$0.trainerIDs, id: value.id, changed: TrainerSignature(value) != vanilla) }
    }

    private func refreshItemVanillaStatus(_ value: ItemData) {
        guard let vanilla = vanillaSnapshot?.items?[value.id] else { return }
        updateVanillaChangeSet { setMembership(&$0.itemIDs, id: value.id, changed: ItemSignature(value) != vanilla) }
    }

    private func refreshEncounterVanillaStatus(_ value: WildEncounterArea) {
        guard let vanilla = vanillaSnapshot?.encounters?[value.id] else { return }
        let changed = EncounterSignature(value) != vanilla
        updateVanillaChangeSet {
            setMembership(&$0.encounterAreaIDs, id: value.id, changed: changed)
            let currentGroups = Dictionary(uniqueKeysWithValues: EncounterSignature(value).groups.map { ($0.kind, $0) })
            let vanillaGroups = Dictionary(uniqueKeysWithValues: vanilla.groups.map { ($0.kind, $0) })
            for kind in Set(currentGroups.keys).union(vanillaGroups.keys) {
                let groupID = VanillaEncounterGroupID(areaID: value.id, kind: kind)
                setMembership(&$0.encounterGroupIDs, id: groupID, changed: currentGroups[kind] != vanillaGroups[kind])
            }
            let mapID = "\(value.mapGroup)-\(value.mapNumber)"
            let mapChanged = vanillaSnapshot?.maps?[mapID] != maps.first(where: { $0.id == mapID }).map(MapSignature.init)
            setMembership(&$0.mapIDs, id: mapID, changed: changed || mapChanged)
        }
    }

    private func refreshMapVanillaStatus(_ value: MapData) {
        guard let vanilla = vanillaSnapshot?.maps?[value.id] else { return }
        let encounterChanged = wildEncounterAreas.first(where: { $0.mapGroup == value.group && $0.mapNumber == value.mapID })
            .map { isEncounterAreaModified($0.id) } ?? false
        updateVanillaChangeSet {
            setMembership(&$0.mapIDs, id: value.id, changed: MapSignature(value) != vanilla || encounterChanged)
        }
    }

    private func setMembership<ID: Hashable>(_ set: inout Set<ID>, id: ID, changed: Bool) {
        if changed { set.insert(id) } else { set.remove(id) }
    }

    private func write(to url: URL, backingUp: Bool) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            if backingUp, FileManager.default.fileExists(atPath: url.path) { try createBackup(of: url) }
            try data.write(to: url, options: .atomic)
            let reloadedData = try Data(contentsOf: url)
            guard reloadedData == data else { throw ROMError.saveVerificationFailed }
            fileURL = url
            savedData = data
            isDirty = false
            logChangedByteSummary(context: "Save")
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            present(error: error)
        }
    }

    private func logChangedByteSummary(context: String) {
        let summary = changedByteSummary()
        let rangeText = summary.ranges
            .prefix(12)
            .map { range -> String in
                range.lowerBound == range.upperBound
                    ? String(format: "0x%08X", range.lowerBound)
                    : String(format: "0x%08X-0x%08X", range.lowerBound, range.upperBound)
            }
            .joined(separator: ", ")
        let suffix = summary.ranges.count > 12 ? ", …" : ""
        print("[HexManiaMac] \(context): \(summary.changedByteCount) byte(s) changed from opened ROM")
        if !rangeText.isEmpty {
            print("[HexManiaMac] Changed ranges: \(rangeText)\(suffix)")
        }
        let deltas = ROMDiffReport.compare(original: originalData, modified: data).changedBytes.prefix(8)
        for change in deltas {
            print(String(format: "[HexManiaMac] Changed byte 0x%08X: %02X -> %02X", change.offset, change.oldValue, change.newValue))
        }
    }

    private func logTrainerEdit(_ trainer: TrainerData) {
        print("[HexManiaMac] Trainer edit index: \(trainer.id)")
        print(String(format: "[HexManiaMac] Trainer entry offset: 0x%08X", trainer.entryOffset))
        print(String(format: "[HexManiaMac] Trainer party pointer: 0x%08X", trainer.partyOffset))
        print("[HexManiaMac] Trainer party format: \(trainer.partyFormat.title)")
    }

    private func logWildEncounterEdit(_ area: WildEncounterArea) {
        print("[HexManiaMac] Wild encounter edit area: \(area.displayName)")
        print(String(format: "[HexManiaMac] Wild table entry offset: 0x%08X", area.tableOffset))
        for group in area.groups {
            print(String(format: "[HexManiaMac] %@ rate offset: 0x%08X data offset: 0x%08X", group.kind.title, group.rateOffset, group.tableOffset))
        }
    }

    private func changedByteSummary() -> (changedByteCount: Int, ranges: [ClosedRange<Int>]) {
        guard !originalData.isEmpty else { return (0, []) }
        let comparedLength = min(originalData.count, data.count)
        var changedCount = abs(data.count - originalData.count)
        var ranges: [ClosedRange<Int>] = []
        var activeStart: Int?

        for offset in 0..<comparedLength {
            if originalData[offset] != data[offset] {
                changedCount += 1
                if activeStart == nil { activeStart = offset }
            } else if let start = activeStart {
                ranges.append(start...(offset - 1))
                activeStart = nil
            }
        }

        if let start = activeStart {
            ranges.append(start...(comparedLength - 1))
        }
        if data.count != originalData.count {
            let start = comparedLength
            let end = max(data.count, originalData.count) - 1
            if start <= end { ranges.append(start...end) }
        }
        return (changedCount, ranges)
    }

    private func createBackup(of original: URL) throws {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let appID = Bundle.main.bundleIdentifier ?? "org.example.hexmaniamac"
        let directory = support.appendingPathComponent(appID, isDirectory: true).appendingPathComponent("Backups", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let base = original.deletingPathExtension().lastPathComponent
        let destination = directory.appendingPathComponent("\(base)_\(formatter.string(from: Date())).gba")
        try fm.copyItem(at: original, to: destination)
    }

    private func createSaveBackupIfNeeded(of original: URL) throws {
        let fm = FileManager.default
        let directory = original.deletingLastPathComponent()
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension.isEmpty ? "sav" : original.pathExtension
        let firstBackup = directory.appendingPathComponent("\(base).backup.\(ext)")
        if !fm.fileExists(atPath: firstBackup.path) {
            try fm.copyItem(at: original, to: firstBackup)
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamped = directory.appendingPathComponent("\(base).backup.\(formatter.string(from: Date())).\(ext)")
        try fm.copyItem(at: original, to: timestamped)
    }

    private static let fallbackSpeciesNames: [Int: String] = [
        277: "Treecko",
        278: "Grovyle",
        279: "Sceptile",
        280: "Torchic",
        281: "Combusken",
        282: "Blaziken",
        283: "Mudkip"
    ]

    private static let fallbackMoveNames: [Int: String] = [
        1: "Pound",
        2: "Karate Chop",
        3: "Double Slap",
        4: "Comet Punch",
        5: "Mega Punch",
        15: "Cut",
        33: "Tackle",
        43: "Leer",
        45: "Growl",
        55: "Water Gun",
        71: "Absorb",
        98: "Quick Attack",
        189: "Mud-Slap"
    ]

    private static let fallbackItemNames: [Int: String] = [
        1: "Master Ball",
        2: "Ultra Ball",
        3: "Great Ball",
        4: "Poké Ball",
        13: "Potion",
        44: "Rare Candy",
        79: "Oran Berry",
        200: "Leftovers"
    ]

    private static let fallbackPokeballNames: [Int: String] = [
        1: "Master Ball",
        2: "Ultra Ball",
        3: "Great Ball",
        4: "Poké Ball",
        5: "Safari Ball",
        6: "Net Ball",
        7: "Dive Ball",
        8: "Nest Ball",
        9: "Repeat Ball",
        10: "Timer Ball",
        11: "Luxury Ball",
        12: "Premier Ball"
    ]

    private static let fallbackLocationNames: [Int: String] = [:]

    private func present(error: Error) {
        statusMessage = error.localizedDescription
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    static func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum ROMError: LocalizedError {
    case invalidFile
    case unsupportedSemanticTables
    case missingTable(String)
    case valueOutOfRange(String)
    case signedValueOutOfRange(String)
    case uint16ValueOutOfRange(String)
    case indexOutOfRange(String)
    case textNotEncodable(String)
    case textTooLong(String)
    case partyResizeUnsupported
    case invalidSaveFile
    case invalidPokemonSubstructures(Int)
    case invalidPokemonChecksum(Int)
    case invalidSaveEditValue
    case saveVerificationFailed
    case unsafeMapRestore(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            "This file is not large enough to be a valid GBA ROM."
        case .unsupportedSemanticTables:
            "This ROM does not contain the expected Pokémon Emerald USA tables."
        case .missingTable(let tableName):
            "Could not find \(tableName) in this Pokémon Emerald USA ROM."
        case .valueOutOfRange(let label):
            "\(label) must be between 0 and 255."
        case .signedValueOutOfRange(let label):
            "\(label) must be between -128 and 127."
        case .uint16ValueOutOfRange(let label):
            "\(label) must be between 0 and 65535."
        case .indexOutOfRange(let label):
            "\(label) references an entry outside the ROM table."
        case .textNotEncodable(let label):
            "\(label) contains characters that cannot be encoded with the Pokémon GBA text table."
        case .textTooLong(let label):
            "\(label) is too long for the fixed-size ROM field."
        case .partyResizeUnsupported:
            "Changing trainer party size is not supported yet."
        case .invalidSaveFile:
            "This file is not a valid Pokémon Emerald / Gen III save."
        case .invalidPokemonSubstructures(let slot):
            "Saved Pokémon slot \(slot) does not contain four valid 12-byte Gen III substructures."
        case .invalidPokemonChecksum(let slot):
            "Saved Pokémon slot \(slot) failed its Gen III Pokémon checksum."
        case .invalidSaveEditValue:
            "The save edit contains a value outside the supported range."
        case .saveVerificationFailed:
            "The ROM was written, but the saved file did not match the edited data."
        case .unsafeMapRestore(let reason):
            "Cannot restore the original map safely. \(reason)"
        }
    }
}
