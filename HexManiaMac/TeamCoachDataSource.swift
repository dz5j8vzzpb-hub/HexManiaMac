import AppKit
import Foundation

struct TeamCoachLoadedROM {
    let fileURL: URL
    let identity: ROMIdentity

    var fileName: String {
        fileURL.lastPathComponent
    }
}

struct TeamCoachLoadedSave {
    let fileURL: URL
    let parsed: PlayerSaveData

    var fileName: String {
        fileURL.lastPathComponent
    }
}

@MainActor
final class TeamCoachSession: ObservableObject {
    @Published private(set) var loadedROM: TeamCoachLoadedROM?
    @Published private(set) var loadedSave: TeamCoachLoadedSave?
    @Published private(set) var species: [PokemonSpecies] = []
    @Published private(set) var types: [PokemonNamedValue] = []
    @Published private(set) var moves: [MoveData] = []
    @Published private(set) var encounterAreas: [WildEncounterArea] = []
    @Published private(set) var maps: [MapData] = []
    @Published private(set) var importedParty: [TeamCoachSlot] = TeamCoachSlot.emptySlots()
    @Published private(set) var pokedex: SavePokedexData?
    @Published private(set) var saveProgression: SaveProgressionData?
    @Published var statusMessage = "Carica una ROM Pokémon Smeraldo per iniziare."

    private var romData = Data()
    private var spriteCache: [Int: NSImage] = [:]

    var hasLoadedROM: Bool {
        loadedROM != nil
    }

    var hasLoadedSave: Bool {
        loadedSave != nil
    }

    func loadROM(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let identity = ROMIdentity.read(from: data)
            let rom = EmeraldROM(data: data)
            guard identity.supported, rom.isSupported else {
                throw TeamCoachDataSourceError.unsupportedROM
            }

            romData = data
            loadedROM = TeamCoachLoadedROM(fileURL: url, identity: identity)
            species = try rom.pokemonSpecies()
            types = try rom.pokemonTypes()
            moves = try rom.moves()
            encounterAreas = (try? rom.wildEncounterAreas()) ?? []
            maps = (try? rom.maps()) ?? []
            spriteCache.removeAll()
            statusMessage = "ROM caricata: \(url.lastPathComponent)"
        } catch {
            clearROMData()
            statusMessage = error.localizedDescription
        }
    }

    func loadSave(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let parsed = try EmeraldSaveParser(data: data, fileURL: url).parse()
            loadedSave = TeamCoachLoadedSave(fileURL: url, parsed: parsed)
            importedParty = Self.partySlots(from: parsed.party)
            pokedex = parsed.pokedex
            saveProgression = parsed.progression
            statusMessage = "Salvataggio caricato: \(url.lastPathComponent)"
        } catch {
            loadedSave = nil
            importedParty = TeamCoachSlot.emptySlots()
            pokedex = nil
            saveProgression = nil
            statusMessage = error.localizedDescription
        }
    }

    func pokemonSprite(forSpeciesID speciesID: Int) -> NSImage? {
        if let cached = spriteCache[speciesID] { return cached }
        guard !romData.isEmpty,
              let sprite = EmeraldROM(data: romData).pokemonSprite(for: speciesID) else { return nil }
        spriteCache[speciesID] = sprite
        return sprite
    }

    func speciesName(id: Int) -> String {
        species.first { $0.id == id }?.name ?? "Species #\(id)"
    }

    private func clearROMData() {
        loadedROM = nil
        romData = Data()
        species = []
        types = []
        moves = []
        encounterAreas = []
        maps = []
        spriteCache.removeAll()
    }

    private static func partySlots(from party: [PlayerPartyPokemon]) -> [TeamCoachSlot] {
        var slots = TeamCoachSlot.emptySlots()
        for pokemon in party.prefix(6) {
            let index = min(max(pokemon.slot, 0), 5)
            slots[index] = TeamCoachSlot(
                id: index,
                speciesID: pokemon.species,
                level: pokemon.level,
                moveIDs: normalizedMoves(pokemon.moves)
            )
        }
        return slots
    }

    private static func normalizedMoves(_ moves: [Int]) -> [Int?] {
        Array(moves.prefix(4).map { $0 == 0 ? nil : Optional($0) } + Array(repeating: nil, count: max(0, 4 - moves.count)))
    }
}

enum TeamCoachDataSourceError: LocalizedError {
    case unsupportedROM

    var errorDescription: String? {
        switch self {
        case .unsupportedROM:
            "Carica una ROM Pokémon Smeraldo supportata."
        }
    }
}
