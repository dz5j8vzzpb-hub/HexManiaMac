import Foundation

enum ROMPatchStatus: String, CaseIterable {
    case vanilla
    case applied
    case incompatible

    var title: String {
        switch self {
        case .vanilla:
            "Vanilla"
        case .applied:
            "Applicata"
        case .incompatible:
            "Non compatibile"
        }
    }
}

enum EmeraldQoLPatchID: String, CaseIterable, Identifiable {
    case instantText = "instant_dialogue"
    case preventNPCRetrigger
    case reduceRedundantConfirmations
    case repeatMedicineUse
    case forgetHMMoves
    case coloredMoveBoxes

    var id: String { rawValue }
}

struct EmeraldQoLBytePatch: Equatable {
    let offset: Int
    let originalBytes: [UInt8]
    let patchedBytes: [UInt8]
    let legacyPatchedBytes: [[UInt8]]

    init(offset: Int, originalBytes: [UInt8], patchedBytes: [UInt8], legacyPatchedBytes: [[UInt8]] = []) {
        self.offset = offset
        self.originalBytes = originalBytes
        self.patchedBytes = patchedBytes
        self.legacyPatchedBytes = legacyPatchedBytes
    }

    var isValid: Bool {
        !originalBytes.isEmpty
            && originalBytes.count == patchedBytes.count
            && legacyPatchedBytes.allSatisfy { $0.count == originalBytes.count }
    }

    func currentPatchedBytes(in data: Data) -> [UInt8]? {
        if data.matches(patchedBytes, at: offset) {
            return patchedBytes
        }
        return legacyPatchedBytes.first { data.matches($0, at: offset) }
    }
}

struct EmeraldQoLPatchDefinition: Identifiable, Equatable {
    let id: EmeraldQoLPatchID
    let name: String
    let description: String
    let supportedGameCodes: Set<String>
    let bytePatches: [String: [EmeraldQoLBytePatch]]

    var supportedROMsDescription: String {
        supportedGameCodes.sorted().joined(separator: ", ")
    }

    func status(in data: Data, gameCode: String) -> ROMPatchStatus {
        guard supportedGameCodes.contains(gameCode),
              let patches = bytePatches[gameCode],
              !patches.isEmpty,
              patches.allSatisfy(\.isValid) else {
            return .incompatible
        }

        let originalMatches = patches.allSatisfy { data.matches($0.originalBytes, at: $0.offset) }
        let patchedMatches = patches.allSatisfy { $0.currentPatchedBytes(in: data) != nil }

        if patchedMatches { return .applied }
        if originalMatches { return .vanilla }
        return .incompatible
    }

    func replacementPatches(for gameCode: String, enabled: Bool, in data: Data) -> [EmeraldQoLBytePatch]? {
        guard supportedGameCodes.contains(gameCode),
              let patches = bytePatches[gameCode],
              !patches.isEmpty,
              patches.allSatisfy(\.isValid) else {
            return nil
        }
        return patches.map { patch in
            let currentBytes: [UInt8]
            let replacementBytes: [UInt8]

            if enabled {
                currentBytes = patch.currentPatchedBytes(in: data) ?? patch.originalBytes
                replacementBytes = patch.patchedBytes
            } else {
                currentBytes = patch.currentPatchedBytes(in: data) ?? patch.patchedBytes
                replacementBytes = patch.originalBytes
            }

            return EmeraldQoLBytePatch(
                offset: patch.offset,
                originalBytes: currentBytes,
                patchedBytes: replacementBytes
            )
        }
    }
}

struct EmeraldQoLPatchSummary: Identifiable, Equatable {
    let definition: EmeraldQoLPatchDefinition
    let status: ROMPatchStatus

    var id: EmeraldQoLPatchID { definition.id }
}

enum EmeraldQoLPatchCatalog {
    static let supportedEmeraldGameCodes: Set<String> = ["BPEE", "BPEI"]

    static let definitions: [EmeraldQoLPatchDefinition] = [
        EmeraldQoLPatchDefinition(
            id: .instantText,
            name: "Dialoghi istantanei",
            description: "Mostra immediatamente l'intera pagina di testo senza attendere l'animazione carattere per carattere.",
            supportedGameCodes: supportedEmeraldGameCodes,
            bytePatches: [
                "BPEE": [
                    EmeraldQoLBytePatch(
                        offset: 0x1972E0,
                        originalBytes: [0x00, 0xF0, 0x56, 0xFB],
                        patchedBytes: [0xFF, 0x20, 0x00, 0xBF],
                        legacyPatchedBytes: [[0x00, 0x20, 0x00, 0xBF]]
                    )
                ],
                "BPEI": [
                    EmeraldQoLBytePatch(
                        offset: 0x196DDC,
                        originalBytes: [0x00, 0xF0, 0x56, 0xFB],
                        patchedBytes: [0xFF, 0x20, 0x00, 0xBF],
                        legacyPatchedBytes: [[0x00, 0x20, 0x00, 0xBF]]
                    )
                ]
            ]
        ),
        EmeraldQoLPatchDefinition(
            id: .preventNPCRetrigger,
            name: "Evita doppia interazione NPC",
            description: "Evita di riaprire accidentalmente lo stesso dialogo premendo A ripetutamente.",
            supportedGameCodes: supportedEmeraldGameCodes,
            bytePatches: [:]
        ),
        EmeraldQoLPatchDefinition(
            id: .reduceRedundantConfirmations,
            name: "Riduci conferme inutili",
            description: "Riduce i passaggi di conferma ridondanti nelle azioni comuni.",
            supportedGameCodes: supportedEmeraldGameCodes,
            bytePatches: [:]
        ),
        EmeraldQoLPatchDefinition(
            id: .repeatMedicineUse,
            name: "Uso ripetuto medicine",
            description: "Dopo aver usato una medicina fuori dalla lotta, resta nel flusso di utilizzo per poter curare rapidamente altri Pokemon.",
            supportedGameCodes: supportedEmeraldGameCodes,
            bytePatches: [:]
        ),
        EmeraldQoLPatchDefinition(
            id: .forgetHMMoves,
            name: "MN cancellabili normalmente",
            description: "Permette di dimenticare le mosse MN senza dover usare il Cancella Mosse.",
            supportedGameCodes: supportedEmeraldGameCodes,
            bytePatches: [:]
        ),
        EmeraldQoLPatchDefinition(
            id: .coloredMoveBoxes,
            name: "Colora mosse per tipo",
            description: "Colora i riquadri delle mosse in battaglia in base al loro tipo, come nei giochi Pokemon moderni.",
            supportedGameCodes: supportedEmeraldGameCodes,
            bytePatches: [:]
        )
    ]

    static func definition(id: EmeraldQoLPatchID) -> EmeraldQoLPatchDefinition? {
        definitions.first { $0.id == id }
    }
}

private extension Data {
    func matches(_ bytes: [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + bytes.count <= count else { return false }
        return Array(self[offset..<(offset + bytes.count)]) == bytes
    }
}
