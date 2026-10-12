import Foundation

struct WildEncounterClipboardRow: Equatable, Identifiable {
    let id: Int
    let chance: Int
    let speciesID: Int
    let speciesName: String
    let minLevel: Int
    let maxLevel: Int
}

struct WildEncounterClipboardPreview: Equatable {
    struct Row: Equatable, Identifiable {
        let id: Int
        let chance: Int
        let currentSpeciesName: String
        let currentMinLevel: Int
        let currentMaxLevel: Int
        let newSpeciesID: Int
        let newSpeciesName: String
        let newMinLevel: Int
        let newMaxLevel: Int
    }

    let mapID: String
    let tableID: String
    let rows: [Row]
}

enum WildEncounterClipboardError: LocalizedError, Equatable {
    case missingTable
    case mapMismatch
    case tableMismatch(expected: String, actual: String)
    case invalidRow(line: Int)
    case slotCountMismatch(expected: Int, actual: Int)
    case unknownPokemon(String)
    case invalidLevel(line: Int)
    case chanceMismatch(line: Int, expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .missingTable:
            return "TABLE mancante."
        case .mapMismatch:
            return "Questi dati appartengono a un'altra mappa."
        case let .tableMismatch(expected, actual):
            return "Questi dati sono per \(expected), ma stai modificando \(actual)."
        case let .invalidRow(line):
            return "Riga \(line) non valida. Usa percentuale,Pokemon,minLevel,maxLevel."
        case let .slotCountMismatch(expected, actual):
            return "Numero slot non valido: trovati \(actual), attesi \(expected)."
        case let .unknownPokemon(name):
            return "Pokémon non trovato: \(name)."
        case let .invalidLevel(line):
            return "Livelli non validi alla riga \(line)."
        case let .chanceMismatch(line, expected, actual):
            return "Percentuale non valida alla riga \(line): trovata \(actual), attesa \(expected)."
        }
    }
}

struct WildEncounterClipboardFormatter {
    let species: [PokemonNamedValue]
    let language: AppLanguage

    func exportText(area: WildEncounterArea, group: WildEncounterGroup) -> String {
        var lines = [
            "MAP=\(Self.mapID(for: area))",
            "TABLE=\(Self.tableID(for: group.kind))",
            ""
        ]

        lines.append(contentsOf: group.slots.map { slot in
            let name = speciesName(for: slot.species)
            return "\(slot.chance),\(name),\(slot.minLevel),\(slot.maxLevel)"
        })
        return lines.joined(separator: "\n")
    }

    func preview(text: String, area: WildEncounterArea, group: WildEncounterGroup) throws -> WildEncounterClipboardPreview {
        let parsed = try parse(text: text)
        let expectedMapID = Self.mapID(for: area)
        let actualTableID = Self.tableID(for: group.kind)

        if let parsedMapID = parsed.mapID {
            guard parsedMapID == expectedMapID else { throw WildEncounterClipboardError.mapMismatch }
        }
        guard parsed.tableID == actualTableID else {
            throw WildEncounterClipboardError.tableMismatch(
                expected: tableTitle(for: parsed.tableID),
                actual: group.kind.localizedTitle(language: language)
            )
        }
        guard parsed.rows.count == group.slots.count else {
            throw WildEncounterClipboardError.slotCountMismatch(expected: group.slots.count, actual: parsed.rows.count)
        }

        let rows = try zip(group.slots, parsed.rows).map { currentSlot, parsedRow in
            guard currentSlot.chance == parsedRow.chance else {
                throw WildEncounterClipboardError.chanceMismatch(line: parsedRow.lineNumber, expected: currentSlot.chance, actual: parsedRow.chance)
            }
            guard (1...100).contains(parsedRow.minLevel), (1...100).contains(parsedRow.maxLevel), parsedRow.minLevel <= parsedRow.maxLevel else {
                throw WildEncounterClipboardError.invalidLevel(line: parsedRow.lineNumber)
            }
            let speciesID = try speciesID(for: parsedRow.speciesName)
            return WildEncounterClipboardPreview.Row(
                id: currentSlot.id,
                chance: currentSlot.chance,
                currentSpeciesName: speciesName(for: currentSlot.species),
                currentMinLevel: currentSlot.minLevel,
                currentMaxLevel: currentSlot.maxLevel,
                newSpeciesID: speciesID,
                newSpeciesName: speciesName(for: speciesID),
                newMinLevel: parsedRow.minLevel,
                newMaxLevel: parsedRow.maxLevel
            )
        }

        return WildEncounterClipboardPreview(mapID: parsed.mapID ?? expectedMapID, tableID: parsed.tableID, rows: rows)
    }

    func applying(_ preview: WildEncounterClipboardPreview, to group: WildEncounterGroup) -> WildEncounterGroup {
        var updated = group
        for row in preview.rows {
            guard let index = updated.slots.firstIndex(where: { $0.id == row.id }) else { continue }
            updated.slots[index].species = row.newSpeciesID
            updated.slots[index].minLevel = row.newMinLevel
            updated.slots[index].maxLevel = row.newMaxLevel
        }
        return updated
    }

    static func mapID(for area: WildEncounterArea) -> String {
        "\(area.mapGroup).\(area.mapNumber)"
    }

    static func tableID(for kind: WildEncounterKind) -> String {
        switch kind {
        case .grass: "GRASS"
        case .surf: "SURF"
        case .rockSmash: "ROCK_SMASH"
        case .oldRod: "OLD_ROD"
        case .goodRod: "GOOD_ROD"
        case .superRod: "SUPER_ROD"
        }
    }

    private struct ParsedRow {
        let lineNumber: Int
        let chance: Int
        let speciesName: String
        let minLevel: Int
        let maxLevel: Int
    }

    private struct ParsedTable {
        let mapID: String?
        let tableID: String
        let rows: [ParsedRow]
    }

    private func parse(text: String) throws -> ParsedTable {
        let lines = text.components(separatedBy: .newlines)
        var mapID: String?
        var tableID: String?
        var rows: [ParsedRow] = []

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("MAP=") {
                mapID = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if line.uppercased().hasPrefix("TABLE=") {
                tableID = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                continue
            }

            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 4,
                  let chance = Int(parts[0]),
                  let minLevel = Int(parts[2]),
                  let maxLevel = Int(parts[3]) else {
                throw WildEncounterClipboardError.invalidRow(line: lineNumber)
            }
            rows.append(ParsedRow(lineNumber: lineNumber, chance: chance, speciesName: parts[1], minLevel: minLevel, maxLevel: maxLevel))
        }

        let parsedMapID = mapID?.isEmpty == false ? mapID : nil
        guard let tableID, !tableID.isEmpty else { throw WildEncounterClipboardError.missingTable }
        return ParsedTable(mapID: parsedMapID, tableID: tableID, rows: rows)
    }

    private func speciesID(for name: String) throws -> Int {
        if let numericID = Int(name), species.contains(where: { $0.id == numericID }) {
            return numericID
        }
        if let match = species.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match.id
        }
        throw WildEncounterClipboardError.unknownPokemon(name)
    }

    private func speciesName(for id: Int) -> String {
        species.first { $0.id == id }?.name ?? "Species #\(id)"
    }

    private func tableTitle(for tableID: String) -> String {
        WildEncounterKind.allCases.first { Self.tableID(for: $0) == tableID }?.localizedTitle(language: language) ?? tableID
    }
}
