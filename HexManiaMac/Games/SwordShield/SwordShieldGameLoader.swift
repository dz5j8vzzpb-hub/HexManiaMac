import Foundation

enum SwordShieldGame: String, CaseIterable, Identifiable, Equatable {
    case sword
    case shield

    var id: String { rawValue }

    var supportedGame: SupportedGame {
        switch self {
        case .sword: .sword
        case .shield: .shield
        }
    }

    var displayName: String {
        switch self {
        case .sword: "Pokémon Spada"
        case .shield: "Pokémon Scudo"
        }
    }

    var englishName: String {
        switch self {
        case .sword: "Pokemon Sword"
        case .shield: "Pokemon Shield"
        }
    }

    var titleId: String {
        switch self {
        case .sword: "0100ABF008968000"
        case .shield: "01008DB008C2C000"
        }
    }

    var titleIdBytesLittleEndian: [UInt8] {
        let value = UInt64(titleId, radix: 16) ?? 0
        return (0..<8).map { UInt8((value >> UInt64($0 * 8)) & 0xFF) }
    }

    static func recognized(titleId: String) -> SwordShieldGame? {
        let normalized = titleId.uppercased()
        return allCases.first { $0.titleId == normalized }
    }
}

enum SwordShieldValidationState: Equatable {
    case valid
    case invalid(String)
}

struct SwordShieldGameSession: Equatable {
    let game: SwordShieldGame
    let version: String
    let rootURL: URL
    let romfsURL: URL
    let exefsURL: URL?
    let titleId: String?
    let validationState: SwordShieldValidationState
}

enum SwordShieldLoaderError: LocalizedError, Equatable {
    case extractedFolderRequired
    case romFSNotFound
    case exeFSNotFound
    case invalidDump
    case selectedGameMismatch(expected: SupportedGame, actual: SwordShieldGame)

    var errorDescription: String? {
        switch self {
        case .extractedFolderRequired:
            return "Per ora Hex Mania richiede RomFS/ExeFS estratti."
        case .romFSNotFound:
            return "RomFS non trovato."
        case .exeFSNotFound:
            return "ExeFS non trovato."
        case .invalidDump:
            return "Questa cartella non sembra contenere un dump valido di Pokémon Spada/Scudo."
        case .selectedGameMismatch(let expected, let actual):
            if expected == .shield, actual == .sword {
                return "Il dump selezionato sembra appartenere a Pokémon Spada."
            }
            if expected == .sword, actual == .shield {
                return "Il dump selezionato sembra appartenere a Pokémon Scudo."
            }
            return "Il dump selezionato non appartiene al gioco scelto."
        }
    }
}

enum SwordShieldGameLoader {
    private static let fileManager = FileManager.default
    private static let metadataFileNames: Set<String> = ["control.nacp", "main.npdm", "programinfo.xml", "metadata.json", "cnmt.xml"]
    private static let romFSMarkers: [[String]] = [
        ["bin"],
        ["bin_archive"],
        ["message"],
        ["sound"],
        ["streamingassets"],
        ["field"],
        ["pokemon"],
        ["nx"]
    ]

    static func load(rootURL: URL, expectedGame: SupportedGame) throws -> SwordShieldGameSession {
        guard expectedGame == .sword || expectedGame == .shield else {
            throw SwordShieldLoaderError.invalidDump
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SwordShieldLoaderError.extractedFolderRequired
        }

        let containers = containerCandidates(rootURL: rootURL)

        let buckets = containers.compactMap { container -> (container: URL, romfs: URL, exefs: URL?)? in
            guard let romfsURL = findChildDirectory(named: "romfs", in: container) else { return nil }
            return (container, romfsURL, findChildDirectory(named: "exefs", in: container))
        }

        guard !buckets.isEmpty else {
            let hasSwitchDumpHints = containers.contains { container in
                findChildDirectory(named: "exefs", in: container) != nil
                    || directChildren(of: container).contains { isMetadataFileName($0.lastPathComponent.lowercased()) }
            }
            if hasSwitchDumpHints {
                throw SwordShieldLoaderError.romFSNotFound
            }
            throw SwordShieldLoaderError.invalidDump
        }

        guard buckets.contains(where: { $0.exefs != nil }) else {
            if buckets.contains(where: { hasSwordShieldROMFSMarkers($0.romfs) }) {
                throw SwordShieldLoaderError.exeFSNotFound
            }
            throw SwordShieldLoaderError.invalidDump
        }

        for bucket in buckets where bucket.exefs != nil {
            guard let exefsURL = bucket.exefs else { continue }
            guard hasSwordShieldROMFSMarkers(bucket.romfs) else { continue }

            let metadata = detectMetadata(rootURL: bucket.container, romfsURL: bucket.romfs, exefsURL: exefsURL)
            guard let detectedGame = metadata.game else { continue }
            guard detectedGame.supportedGame == expectedGame else {
                throw SwordShieldLoaderError.selectedGameMismatch(expected: expectedGame, actual: detectedGame)
            }

            return SwordShieldGameSession(
                game: detectedGame,
                version: metadata.version ?? "Sconosciuta",
                rootURL: bucket.container,
                romfsURL: bucket.romfs,
                exefsURL: exefsURL,
                titleId: metadata.titleId,
                validationState: .valid
            )
        }

        throw SwordShieldLoaderError.invalidDump
    }

    private static func containerCandidates(rootURL: URL) -> [URL] {
        [rootURL] + directChildren(of: rootURL).filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else { return false }
            let name = url.lastPathComponent.lowercased()
            return name != "romfs" && name != "exefs"
        }
    }

    private static func directChildren(of url: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func isMetadataFileName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return metadataFileNames.contains { normalized == $0.lowercased() }
    }

    private static func findChildDirectory(named expectedName: String, in rootURL: URL) -> URL? {
        return directChildren(of: rootURL).first { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            return url.lastPathComponent.lowercased() == expectedName.lowercased()
        }
    }

    private static func hasSwordShieldROMFSMarkers(_ romfsURL: URL) -> Bool {
        let markerHits = romFSMarkers.filter { pathComponents in
            var url = romfsURL
            for component in pathComponents {
                url.appendPathComponent(component)
            }
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        return markerHits.count >= 2
    }

    private static func detectMetadata(rootURL: URL, romfsURL: URL, exefsURL: URL?) -> (game: SwordShieldGame?, version: String?, titleId: String?) {
        let metadataFiles = candidateMetadataFiles(rootURL: rootURL, romfsURL: romfsURL, exefsURL: exefsURL)

        for url in metadataFiles {
            if let nacp = readNACP(url), let game = nacp.game {
                return (game, nacp.version, nacp.titleId)
            }
        }

        for game in SwordShieldGame.allCases {
            if pathContainsTitleId(game.titleId, rootURL: rootURL) {
                return (game, nil, game.titleId)
            }
        }

        for url in metadataFiles {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            if let game = gameFromMetadataData(data) {
                return (game, nil, game.titleId)
            }
        }

        return (nil, nil, nil)
    }

    private static func candidateMetadataFiles(rootURL: URL, romfsURL: URL, exefsURL: URL?) -> [URL] {
        var candidates: [URL] = []
        let roots = [rootURL, rootURL.appendingPathComponent("control"), exefsURL, romfsURL].compactMap { $0 }

        for root in roots {
            for name in metadataFileNames {
                let direct = root.appendingPathComponent(name)
                if fileManager.fileExists(atPath: direct.path) {
                    candidates.append(direct)
                }
            }
        }

        if let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                guard metadataFileNames.contains(url.lastPathComponent.lowercased()) else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      (values.fileSize ?? 0) <= 8 * 1024 * 1024 else { continue }
                candidates.append(url)
            }
        }

        return Array(Set(candidates))
    }

    private static func readNACP(_ url: URL) -> (game: SwordShieldGame?, version: String?, titleId: String?)? {
        guard url.lastPathComponent.lowercased() == "control.nacp",
              let data = try? Data(contentsOf: url),
              data.count >= 0x3070 else { return nil }

        let titleRegion = data.prefix(min(data.count, 0x3000))
        let titleText = decodedMetadataText(titleRegion)
        let game = gameFromText(titleText)
        let version = decodedMetadataText(data[0x3060..<min(data.count, 0x3070)]).nilIfEmpty
        let titleId = titleIdFromData(data)
        return (game ?? titleId.flatMap(SwordShieldGame.recognized(titleId:)), version, titleId)
    }

    private static func gameFromMetadataData(_ data: Data) -> SwordShieldGame? {
        if let game = titleIdFromData(data).flatMap(SwordShieldGame.recognized(titleId:)) {
            return game
        }
        return gameFromText(decodedMetadataText(data.prefix(min(data.count, 2 * 1024 * 1024))))
    }

    private static func gameFromText(_ text: String) -> SwordShieldGame? {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if normalized.localizedCaseInsensitiveContains("pokemon sword") || normalized.localizedCaseInsensitiveContains("pokémon sword") {
            return .sword
        }
        if normalized.localizedCaseInsensitiveContains("pokemon shield") || normalized.localizedCaseInsensitiveContains("pokémon shield") {
            return .shield
        }
        for game in SwordShieldGame.allCases where normalized.localizedCaseInsensitiveContains(game.titleId) {
            return game
        }
        return nil
    }

    private static func titleIdFromData(_ data: Data) -> String? {
        for game in SwordShieldGame.allCases {
            if data.range(of: Data(game.titleId.utf8)) != nil || data.range(of: Data(game.titleId.lowercased().utf8)) != nil {
                return game.titleId
            }
            if data.range(of: Data(game.titleIdBytesLittleEndian)) != nil {
                return game.titleId
            }
        }
        return nil
    }

    private static func pathContainsTitleId(_ titleId: String, rootURL: URL) -> Bool {
        rootURL.pathComponents.contains { component in
            component.uppercased() == titleId
        }
    }

    private static func decodedMetadataText<D: DataProtocol>(_ data: D) -> String {
        let bytes = Array(data).filter { byte in
            byte == 0x09 || byte == 0x0A || byte == 0x0D || (byte >= 0x20 && byte < 0x7F) || byte >= 0xC0
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
