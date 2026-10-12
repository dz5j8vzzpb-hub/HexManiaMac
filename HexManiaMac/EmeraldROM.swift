import AppKit
import Foundation

struct EmeraldROM {
    static let supportedGameCodes = ["BPEE", "BPEI"]

    let data: Data

    var isSupported: Bool {
        guard data.count >= 0xB2 else { return false }
        return Self.supportedGameCodes.contains(ascii(0xAC..<0xB0))
    }

    func pokemonSpecies() throws -> [PokemonSpecies] {
        try PokemonTableParser(data: data).parseSpecies()
    }

    func pokemonTypes() throws -> [PokemonNamedValue] {
        try PokemonTableParser(data: data).parseTypes()
    }

    func pokemonAbilities() throws -> [PokemonNamedValue] {
        try PokemonTableParser(data: data).parseAbilities()
    }

    func moves() throws -> [MoveData] {
        try MoveTableParser(data: data).parseMoves()
    }

    func trainerClasses() throws -> [PokemonNamedValue] {
        try TrainerTableParser(data: data).parseTrainerClasses()
    }

    func items() throws -> [PokemonNamedValue] {
        try TrainerTableParser(data: data).parseItems()
    }

    func itemData() throws -> [ItemData] {
        try ItemTableParser(data: data).parseItems()
    }

    func trainers() throws -> [TrainerData] {
        try TrainerTableParser(data: data).parseTrainers()
    }

    func levelUpLearnsets() throws -> [Int: [LevelUpMove]] {
        try LevelUpLearnsetParser(data: data).parseLearnsets()
    }

    func wildEncounterAreas() throws -> [WildEncounterArea] {
        try WildEncounterTableParser(data: data).parseAreas()
    }

    func maps() throws -> [MapData] {
        try MapTableParser(data: data).parseMaps()
    }

    func mapParserDiagnosticReport() -> String {
        MapTableParser(data: data).diagnosticReport()
    }

    func pokemonSprite(for speciesID: Int) -> NSImage? {
        PokemonSpriteRenderer(data: data).frontSprite(for: speciesID)
    }

    func trainerSprite(for spriteID: Int) -> NSImage? {
        TrainerSpriteRenderer(data: data).frontSprite(for: spriteID)
    }

    func objectEventSprite(for graphicsID: Int) -> NSImage? {
        ObjectEventSpriteRenderer(data: data).sprite(for: graphicsID)
    }

    func trainerLink(for object: MapObjectEvent) -> MapObjectTrainerLink? {
        EventScriptTrainerResolver(data: data).trainerLink(for: object)
    }

    func scriptAnalysis(pointer: UInt32, eventType: String) -> MapScriptAnalysis {
        EventScriptAnalyzer(data: data).analyze(pointer: pointer, eventType: eventType)
    }

    func mapImage(for map: MapData) -> NSImage? {
        MapRenderer(data: data).render(map: map)
    }

    func mapMetatileImage(for metatileID: Int, in map: MapData) -> NSImage? {
        MapRenderer(data: data).metatileImage(for: metatileID, in: map)
    }

    static func validateSupported(_ data: Data) throws {
        guard EmeraldROM(data: data).isSupported else { throw ROMError.unsupportedSemanticTables }
    }

    private func ascii(_ range: Range<Int>) -> String {
        String(bytes: data[range], encoding: .ascii) ?? ""
    }
}

struct MapRenderDiagnostic {
    let mapID: String
    let mapName: String
    let width: Int
    let height: Int
    let primaryTilesetOffset: Int?
    let secondaryTilesetOffset: Int?
    let primaryTilesOffset: Int?
    let secondaryTilesOffset: Int?
    let primaryPalettesOffset: Int?
    let secondaryPalettesOffset: Int?
    let primaryMetatilesOffset: Int?
    let secondaryMetatilesOffset: Int?
    let primaryAttributesOffset: Int?
    let secondaryAttributesOffset: Int?
    let primaryCompressed: Bool?
    let secondaryCompressed: Bool?
    let renderedCellCount: Int
    let failedCellCount: Int
    let eventSummary: String
    let failureSamples: [String]

    var passed: Bool {
        let total = renderedCellCount + failedCellCount
        guard total > 0 else { return false }
        return Double(renderedCellCount) / Double(total) >= 0.99
    }

    var reportLines: [String] {
        [
            "\(mapName) (\(mapID)) \(width)x\(height)",
            "primaryTileset=\(hex(primaryTilesetOffset)) secondaryTileset=\(hex(secondaryTilesetOffset))",
            "tiles=\(hex(primaryTilesOffset))/\(hex(secondaryTilesOffset)) palettes=\(hex(primaryPalettesOffset))/\(hex(secondaryPalettesOffset))",
            "metatiles=\(hex(primaryMetatilesOffset))/\(hex(secondaryMetatilesOffset)) attributes=\(hex(primaryAttributesOffset))/\(hex(secondaryAttributesOffset))",
            "compressed=\(primaryCompressed.map(String.init) ?? "nil")/\(secondaryCompressed.map(String.init) ?? "nil")",
            "rendered=\(renderedCellCount) failed=\(failedCellCount)",
            eventSummary
        ] + failureSamples.map { "failure: \($0)" }
    }

    private func hex(_ value: Int?) -> String {
        value.map { String(format: "0x%08X", $0) } ?? "nil"
    }
}

struct MapRenderer {
    private struct TilesetData {
        let offset: Int
        let isCompressed: Bool
        let isSecondary: Bool
        let tilesOffset: Int
        let palettesOffset: Int
        let tiles: Data
        let palettes: [NSColor]
        let metatilesOffset: Int
        let attributesOffset: Int
    }

    private struct RenderTilesets {
        let primary: TilesetData
        let secondary: TilesetData
        let combinedTiles: Data
        let combinedPalettes: [NSColor]
    }

    private struct MetatileAttributes {
        let raw: Int
        let behavior: Int
        let layerType: Int
    }

    private enum Layout {
        static let tilesetLength = 24
        static let metatileByteLength = 16
        static let metatileAttributesByteLength = 2
        static let metatilesPerTileset = 512
        static let metatileSide = 16
        static let tileSide = 8
        static let tileByteLength = 32
        static let primaryTileCount = 0x200
        static let secondaryTileCount = 0x200
        static let primaryPaletteCount = 6
        static let totalPaletteCount = 16
        static let colorsPerPalette = 16
        static let paletteByteLength = totalPaletteCount * colorsPerPalette * 2
    }

    let data: Data

    func render(map: MapData) -> NSImage? {
        let start = MapEditProfiler.now()
        defer { MapEditProfiler.log("full map render", since: start) }
        guard let tilesets = parseRenderTilesets(for: map),
              map.width > 0,
              map.height > 0 else { return nil }
        logTilesets(tilesets, map: map)

        let pixelWidth = map.width * Layout.metatileSide
        let pixelHeight = map.height * Layout.metatileSide
        let bytesPerRow = pixelWidth * 4
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        ), let pixels = bitmap.bitmapData else { return nil }

        var metatileCache: [Int: [UInt8]] = [:]
        for block in map.blocks {
            let metatilePixels = metatileCache[block.metatileID] ?? renderMetatile(block.metatileID, tilesets: tilesets, map: map)
            metatileCache[block.metatileID] = metatilePixels
            copyMetatile(metatilePixels, to: pixels, mapWidth: pixelWidth, x: block.x, y: block.y)
        }

        let image = NSImage(size: NSSize(width: pixelWidth, height: pixelHeight))
        image.addRepresentation(bitmap)
        return image
    }

    func metatileImage(for metatileID: Int, in map: MapData) -> NSImage? {
        let start = MapEditProfiler.now()
        defer { MapEditProfiler.log("metatile render", since: start) }
        guard let tilesets = parseRenderTilesets(for: map) else { return nil }
        let pixels = renderMetatile(metatileID, tilesets: tilesets, map: map)
        let side = Layout.metatileSide
        let bytesPerRow = side * 4
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        ), let destination = bitmap.bitmapData else { return nil }
        for index in 0..<pixels.count {
            destination[index] = pixels[index]
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    func diagnostics(for map: MapData) -> MapRenderDiagnostic {
        guard let tilesets = parseRenderTilesets(for: map) else {
            return MapRenderDiagnostic(
                mapID: map.id,
                mapName: map.name,
                width: map.width,
                height: map.height,
                primaryTilesetOffset: map.primaryTilesetOffset,
                secondaryTilesetOffset: map.secondaryTilesetOffset,
                primaryTilesOffset: nil,
                secondaryTilesOffset: nil,
                primaryPalettesOffset: nil,
                secondaryPalettesOffset: nil,
                primaryMetatilesOffset: nil,
                secondaryMetatilesOffset: nil,
                primaryAttributesOffset: nil,
                secondaryAttributesOffset: nil,
                primaryCompressed: nil,
                secondaryCompressed: nil,
                renderedCellCount: 0,
                failedCellCount: map.blocks.count,
                eventSummary: "objects=\(map.objects.count) warps=\(map.warps.count) coords=\(map.coordinateEvents.count) backgrounds=\(map.backgroundEvents.count)",
                failureSamples: ["tileset parse failed"]
            )
        }

        var rendered = 0
        var failed = 0
        var samples: [String] = []
        for block in map.blocks {
            if let failure = metatileFailureReason(block.metatileID, tilesets: tilesets) {
                failed += 1
                if samples.count < 6 {
                    samples.append("metatile #\(block.metatileID) at \(block.x),\(block.y): \(failure)")
                }
            } else {
                rendered += 1
            }
        }

        return MapRenderDiagnostic(
            mapID: map.id,
            mapName: map.name,
            width: map.width,
            height: map.height,
            primaryTilesetOffset: tilesets.primary.offset,
            secondaryTilesetOffset: tilesets.secondary.offset,
            primaryTilesOffset: tilesets.primary.tilesOffset,
            secondaryTilesOffset: tilesets.secondary.tilesOffset,
            primaryPalettesOffset: tilesets.primary.palettesOffset,
            secondaryPalettesOffset: tilesets.secondary.palettesOffset,
            primaryMetatilesOffset: tilesets.primary.metatilesOffset,
            secondaryMetatilesOffset: tilesets.secondary.metatilesOffset,
            primaryAttributesOffset: tilesets.primary.attributesOffset,
            secondaryAttributesOffset: tilesets.secondary.attributesOffset,
            primaryCompressed: tilesets.primary.isCompressed,
            secondaryCompressed: tilesets.secondary.isCompressed,
            renderedCellCount: rendered,
            failedCellCount: failed,
            eventSummary: "objects=\(map.objects.count) warps=\(map.warps.count) coords=\(map.coordinateEvents.count) backgrounds=\(map.backgroundEvents.count)",
            failureSamples: samples
        )
    }

    private func parseRenderTilesets(for map: MapData) -> RenderTilesets? {
        guard let primaryOffset = map.primaryTilesetOffset,
              let secondaryOffset = map.secondaryTilesetOffset,
              let primary = parseTileset(at: primaryOffset),
              let secondary = parseTileset(at: secondaryOffset) else { return nil }
        let primaryTiles = normalizedTiles(primary.tiles, byteLength: Layout.primaryTileCount * Layout.tileByteLength)
        let secondaryTiles = normalizedTiles(secondary.tiles, byteLength: Layout.secondaryTileCount * Layout.tileByteLength)
        let primaryPaletteColorCount = Layout.primaryPaletteCount * Layout.colorsPerPalette
        let totalPaletteColorCount = Layout.totalPaletteCount * Layout.colorsPerPalette
        var combinedPalettes = Array(primary.palettes.prefix(totalPaletteColorCount))
        if combinedPalettes.count < totalPaletteColorCount {
            combinedPalettes.append(contentsOf: Array(repeating: .black, count: totalPaletteColorCount - combinedPalettes.count))
        }

        let secondaryColors = secondary.palettes.dropFirst(primaryPaletteColorCount).prefix(totalPaletteColorCount - primaryPaletteColorCount)
        combinedPalettes.replaceSubrange(primaryPaletteColorCount..<(primaryPaletteColorCount + secondaryColors.count), with: secondaryColors)

        return RenderTilesets(
            primary: primary,
            secondary: secondary,
            combinedTiles: primaryTiles + secondaryTiles,
            combinedPalettes: combinedPalettes
        )
    }

    private func parseTileset(at offset: Int) -> TilesetData? {
        guard hasRange(offset, length: Layout.tilesetLength) else { return nil }
        let isCompressed = data[offset] != 0
        let isSecondary = data[offset + 1] != 0
        guard let tilesOffset = readPointer(at: offset + 4),
              let palettesOffset = readPointer(at: offset + 8),
              let metatilesOffset = readPointer(at: offset + 12),
              let attributesOffset = readPointer(at: offset + 16),
              hasRange(palettesOffset, length: Layout.paletteByteLength) else { return nil }

        let tiles: Data
        let expectedTileByteLength = (isSecondary ? Layout.secondaryTileCount : Layout.primaryTileCount) * Layout.tileByteLength
        if isCompressed {
            guard let decompressed = lz77Decompress(from: tilesOffset) else { return nil }
            tiles = decompressed
        } else {
            guard hasRange(tilesOffset, length: expectedTileByteLength) else { return nil }
            tiles = Data(data[tilesOffset..<(tilesOffset + expectedTileByteLength)])
        }

        return TilesetData(
            offset: offset,
            isCompressed: isCompressed,
            isSecondary: isSecondary,
            tilesOffset: tilesOffset,
            palettesOffset: palettesOffset,
            tiles: tiles,
            palettes: decodePalettes(at: palettesOffset),
            metatilesOffset: metatilesOffset,
            attributesOffset: attributesOffset
        )
    }

    private func renderMetatile(_ metatileID: Int, tilesets: RenderTilesets, map: MapData) -> [UInt8] {
        let tileset = metatileID < Layout.metatilesPerTileset ? tilesets.primary : tilesets.secondary
        let localID = metatileID < Layout.metatilesPerTileset ? metatileID : metatileID - Layout.metatilesPerTileset
        let entryOffset = tileset.metatilesOffset + localID * Layout.metatileByteLength
        guard localID >= 0,
              hasRange(entryOffset, length: Layout.metatileByteLength),
              metatileAttributes(forLocalID: localID, in: tileset) != nil else {
            print("[MapRender][FAIL] map \(map.group).\(map.mapID) tileset=0x\(String(format: "%08X", tileset.offset)) metatile=\(metatileID) reason=metatile outside table")
            return placeholderMetatile(metatileID)
        }

        var output = [UInt8](repeating: 0, count: Layout.metatileSide * Layout.metatileSide * 4)
        for entryIndex in 0..<8 {
            let tileEntryOffset = entryOffset + entryIndex * 2
            let entry = Int(data[tileEntryOffset]) | (Int(data[tileEntryOffset + 1]) << 8)
            let tileIndex = entry & 0x03FF
            let horizontalFlip = entry & 0x0400 != 0
            let verticalFlip = entry & 0x0800 != 0
            let paletteIndex = (entry >> 12) & 0x0F
            let tileX = entryIndex % 2
            let tileY = (entryIndex / 2) % 2
            drawTile(
                tileIndex,
                paletteIndex: paletteIndex,
                horizontalFlip: horizontalFlip,
                verticalFlip: verticalFlip,
                combinedTiles: tilesets.combinedTiles,
                combinedPalettes: tilesets.combinedPalettes,
                treatsColorZeroAsTransparent: entryIndex >= 4,
                destinationX: tileX * Layout.tileSide,
                destinationY: tileY * Layout.tileSide,
                into: &output
            )
        }
        return output
    }

    private func drawTile(
        _ tileIndex: Int,
        paletteIndex: Int,
        horizontalFlip: Bool,
        verticalFlip: Bool,
        combinedTiles: Data,
        combinedPalettes: [NSColor],
        treatsColorZeroAsTransparent: Bool,
        destinationX: Int,
        destinationY: Int,
        into output: inout [UInt8]
    ) {
        let tileOffset = tileIndex * Layout.tileByteLength
        guard tileOffset + Layout.tileByteLength <= combinedTiles.count else { return }
        for row in 0..<Layout.tileSide {
            for pair in 0..<4 {
                let packed = combinedTiles[tileOffset + row * 4 + pair]
                let colorIndexes = [Int(packed & 0x0F), Int(packed >> 4)]
                for subpixel in 0..<2 {
                    let colorIndex = colorIndexes[subpixel]
                    if colorIndex == 0, treatsColorZeroAsTransparent { continue }
                    let sourceX = pair * 2 + subpixel
                    let sourceY = row
                    let x = destinationX + (horizontalFlip ? (Layout.tileSide - 1 - sourceX) : sourceX)
                    let y = destinationY + (verticalFlip ? (Layout.tileSide - 1 - sourceY) : sourceY)
                    let paletteOffset =
                        paletteIndex * Layout.colorsPerPalette + colorIndex

                    guard paletteOffset < combinedPalettes.count,
                          let rgb = combinedPalettes[paletteOffset]
                            .usingColorSpace(.deviceRGB)
                    else {
                        continue
                    }
                    let destination = (y * Layout.metatileSide + x) * 4
                    output[destination + 0] = UInt8((rgb.redComponent * 255).rounded())
                    output[destination + 1] = UInt8((rgb.greenComponent * 255).rounded())
                    output[destination + 2] = UInt8((rgb.blueComponent * 255).rounded())
                    output[destination + 3] = 255
                }
            }
        }
    }

    private func normalizedTiles(_ tiles: Data, byteLength: Int) -> Data {
        if tiles.count == byteLength { return tiles }
        if tiles.count > byteLength { return Data(tiles.prefix(byteLength)) }
        var padded = tiles
        padded.append(Data(repeating: 0, count: byteLength - tiles.count))
        return padded
    }

    private func metatileFailureReason(_ metatileID: Int, tilesets: RenderTilesets) -> String? {
        let tileset = metatileID < Layout.metatilesPerTileset ? tilesets.primary : tilesets.secondary
        let localID = metatileID < Layout.metatilesPerTileset ? metatileID : metatileID - Layout.metatilesPerTileset
        let entryOffset = tileset.metatilesOffset + localID * Layout.metatileByteLength
        guard localID >= 0, hasRange(entryOffset, length: Layout.metatileByteLength) else {
            return "metatile entry outside ROM"
        }

        for entryIndex in 0..<8 {
            let tileEntryOffset = entryOffset + entryIndex * 2
            let entry = Int(data[tileEntryOffset]) | (Int(data[tileEntryOffset + 1]) << 8)
            let tileIndex = entry & 0x03FF
            let paletteIndex = (entry >> 12) & 0x0F
            guard tileIndex * Layout.tileByteLength + Layout.tileByteLength <= tilesets.combinedTiles.count else {
                return "tile #\(tileIndex) outside combined primary/secondary graphics"
            }
            guard paletteIndex * Layout.colorsPerPalette + (Layout.colorsPerPalette - 1) < tilesets.combinedPalettes.count else {
                return "palette #\(paletteIndex) outside combined primary/secondary palettes"
            }
        }
        guard metatileAttributes(forLocalID: localID, in: tileset) != nil else {
            return "metatile attributes outside ROM"
        }
        let pixels = renderMetatile(metatileID, tilesets: tilesets, map: MapData(
            group: -1,
            mapID: -1,
            name: "diagnostic",
            width: 1,
            height: 1,
            blocks: [],
            objects: [],
            warps: [],
            coordinateEvents: [],
            backgroundEvents: [],
            connections: [],
            headerOffset: 0,
            layoutOffset: 0,
            blockmapOffset: 0,
            eventsOffset: nil,
            connectionsOffset: nil,
            primaryTilesetOffset: nil,
            secondaryTilesetOffset: nil,
            music: 0,
            layoutID: 0,
            regionSectionID: 0,
            cave: 0,
            weather: 0,
            mapType: 0,
            flags: 0,
            battleType: 0
        ))
        if !stride(from: 3, to: pixels.count, by: 4).contains(where: { pixels[$0] != 0 }) {
            return "metatile rendered no visible pixels"
        }
        return nil
    }

    private func metatileAttributes(forLocalID localID: Int, in tileset: TilesetData) -> MetatileAttributes? {
        let offset = tileset.attributesOffset + localID * Layout.metatileAttributesByteLength
        guard localID >= 0, hasRange(offset, length: Layout.metatileAttributesByteLength) else { return nil }
        let raw = Int(data[offset]) | (Int(data[offset + 1]) << 8)
        return MetatileAttributes(
            raw: raw,
            behavior: raw & 0x00FF,
            layerType: (raw >> 12) & 0x000F
        )
    }

    private func copyMetatile(_ metatilePixels: [UInt8], to pixels: UnsafeMutablePointer<UInt8>, mapWidth: Int, x: Int, y: Int) {
        for row in 0..<Layout.metatileSide {
            let source = row * Layout.metatileSide * 4
            let destination = ((y * Layout.metatileSide + row) * mapWidth + x * Layout.metatileSide) * 4
            for byte in 0..<(Layout.metatileSide * 4) {
                pixels[destination + byte] = metatilePixels[source + byte]
            }
        }
    }

    private func placeholderMetatile(_ metatileID: Int) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: Layout.metatileSide * Layout.metatileSide * 4)
        let red = UInt8((metatileID * 53) % 255)
        let green = UInt8((metatileID * 97) % 255)
        let blue = UInt8((metatileID * 193) % 255)
        for index in stride(from: 0, to: output.count, by: 4) {
            output[index + 0] = red
            output[index + 1] = green
            output[index + 2] = blue
            output[index + 3] = 255
        }
        return output
    }

    private func decodePalettes(at offset: Int) -> [NSColor] {
        stride(from: 0, to: Layout.paletteByteLength, by: 2).map { relativeOffset in
            let value = UInt16(data[offset + relativeOffset]) | (UInt16(data[offset + relativeOffset + 1]) << 8)
            let red = CGFloat(value & 0x1F) / 31.0
            let green = CGFloat((value >> 5) & 0x1F) / 31.0
            let blue = CGFloat((value >> 10) & 0x1F) / 31.0
            return NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
        }
    }

    private func lz77Decompress(from offset: Int) -> Data? {
        guard hasRange(offset, length: 4), data[offset] == 0x10 else { return nil }
        let decompressedLength = Int(data[offset + 1]) | (Int(data[offset + 2]) << 8) | (Int(data[offset + 3]) << 16)
        guard decompressedLength > 0 else { return nil }

        var source = offset + 4
        var output = Data()
        output.reserveCapacity(decompressedLength)

        while output.count < decompressedLength, hasRange(source, length: 1) {
            let flags = data[source]
            source += 1
            for bit in 0..<8 where output.count < decompressedLength {
                if flags & (0x80 >> UInt8(bit)) == 0 {
                    guard hasRange(source, length: 1) else { return nil }
                    output.append(data[source])
                    source += 1
                } else {
                    guard hasRange(source, length: 2) else { return nil }
                    let first = Int(data[source])
                    let second = Int(data[source + 1])
                    source += 2
                    let length = (first >> 4) + 3
                    let displacement = ((first & 0x0F) << 8) | second
                    let copyStart = output.count - displacement - 1
                    guard copyStart >= 0 else { return nil }
                    for index in 0..<length where output.count < decompressedLength {
                        output.append(output[copyStart + index])
                    }
                }
            }
        }

        return output.count == decompressedLength ? output : nil
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let pointer = Int(raw - 0x0800_0000)
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private func logTilesets(_ tilesets: RenderTilesets, map: MapData) {
        print(String(format: "[MapRender] map %@ primary=0x%08X secondary=0x%08X pTiles=0x%08X sTiles=0x%08X pPal=0x%08X sPal=0x%08X pMeta=0x%08X sMeta=0x%08X pAttr=0x%08X sAttr=0x%08X compressed=%@/%@ size=%dx%d",
                     map.id,
                     tilesets.primary.offset,
                     tilesets.secondary.offset,
                     tilesets.primary.tilesOffset,
                     tilesets.secondary.tilesOffset,
                     tilesets.primary.palettesOffset,
                     tilesets.secondary.palettesOffset,
                     tilesets.primary.metatilesOffset,
                     tilesets.secondary.metatilesOffset,
                     tilesets.primary.attributesOffset,
                     tilesets.secondary.attributesOffset,
                     tilesets.primary.isCompressed ? "true" : "false",
                     tilesets.secondary.isCompressed ? "true" : "false",
                     map.width,
                     map.height))
    }
}

struct ROMByteDelta: Equatable {
    let offset: Int
    let oldValue: UInt8
    let newValue: UInt8
}

struct ROMDiffReport {
    let changedBytes: [ROMByteDelta]
    let ranges: [ClosedRange<Int>]

    var changedByteCount: Int { changedBytes.count }

    static func compare(original: Data, modified: Data) -> ROMDiffReport {
        let comparedLength = min(original.count, modified.count)
        var changes: [ROMByteDelta] = []
        var ranges: [ClosedRange<Int>] = []
        var activeStart: Int?

        for offset in 0..<comparedLength {
            guard original[offset] != modified[offset] else {
                if let start = activeStart {
                    ranges.append(start...(offset - 1))
                    activeStart = nil
                }
                continue
            }
            changes.append(ROMByteDelta(offset: offset, oldValue: original[offset], newValue: modified[offset]))
            if activeStart == nil { activeStart = offset }
        }

        if let start = activeStart {
            ranges.append(start...(comparedLength - 1))
        }

        if original.count != modified.count {
            let start = comparedLength
            let end = max(original.count, modified.count) - 1
            if start <= end { ranges.append(start...end) }
        }

        return ROMDiffReport(changedBytes: changes, ranges: ranges)
    }

    func summary(limit: Int = 8) -> String {
        let rangeText = ranges
            .prefix(limit)
            .map { range in
                range.lowerBound == range.upperBound
                    ? String(format: "0x%08X", range.lowerBound)
                    : String(format: "0x%08X-0x%08X", range.lowerBound, range.upperBound)
            }
            .joined(separator: ", ")
        return "Changed bytes: \(changedByteCount)" + (rangeText.isEmpty ? "" : "\nRange: \(rangeText)")
    }
}

struct ROMIntegrityTestResult {
    let name: String
    let passed: Bool
    let details: [String]

    var reportText: String {
        ([name, passed ? "PASS" : "FAIL"] + details).joined(separator: "\n")
    }
}

struct ROMIntegrityTestSuite {
    static func run(on data: Data) -> [ROMIntegrityTestResult] {
        [
            runPokemonWriterTest(on: data),
            runMoveWriterTest(on: data),
            runTrainerWriterTest(on: data),
            runEncounterWriterTest(on: data),
            runItemWriterTest(on: data),
            runMapBanksResolverTest(on: data),
            runMapParserTest(on: data),
            runMapRendererTest(on: data),
            runMapWriterTest(on: data),
            runMapWarpWriterTest(on: data),
            runMapObjectWriterTest(on: data),
            runSaveReloadTest(on: data),
            runHeaderGuardTest(on: data)
        ]
    }

    static func report(on data: Data) -> String {
        run(on: data).map(\.reportText).joined(separator: "\n\n")
    }

    private static func runPokemonWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let species = try PokemonTableParser(data: data).parseSpecies()
            guard var rayquaza = species.first(where: { $0.name.uppercased() == "RAYQUAZA" }) else {
                return fail("PokemonWriter", "RAYQUAZA not found")
            }
            let originalHP = rayquaza.baseStats.hp
            guard originalHP < 255 else { return fail("PokemonWriter", "RAYQUAZA HP cannot be incremented safely") }
            rayquaza.baseStats.hp = originalHP + 1

            var modified = data
            try PokemonTableParser.write(rayquaza, into: &modified)
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffset = rayquaza.statsOffset
            guard diff.changedBytes.map(\.offset) == [expectedOffset] else {
                return fail("PokemonWriter", diff.summary(), "Expected only HP offset \(hex(expectedOffset))")
            }
            let reparsed = try PokemonTableParser(data: modified).parseSpecies()
            guard reparsed.first(where: { $0.id == rayquaza.id })?.baseStats.hp == originalHP + 1 else {
                return fail("PokemonWriter", "Parser did not reload HP \(originalHP + 1)")
            }

            return pass("PokemonWriter",
                        "RAYQUAZA HP \(originalHP) -> \(originalHP + 1)",
                        "Stats: Atk \(rayquaza.baseStats.attack), Def \(rayquaza.baseStats.defense), Speed \(rayquaza.baseStats.speed), SpAtk \(rayquaza.baseStats.specialAttack), SpDef \(rayquaza.baseStats.specialDefense)",
                        "Types: \(rayquaza.type1)/\(rayquaza.type2), Abilities: \(rayquaza.ability1)/\(rayquaza.ability2)",
                        diff.summary())
        } catch {
            return fail("PokemonWriter", error.localizedDescription)
        }
    }

    private static func runMoveWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let moves = try MoveTableParser(data: data).parseMoves()
            guard var move = moves.first(where: { $0.id > 0 && $0.power < 255 }) else {
                return fail("MoveWriter", "No editable move found")
            }
            let originalPower = move.power
            move.power += 1

            var modified = data
            try MoveTableParser.write(move, into: &modified)
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffset = move.statsOffset + 1
            guard diff.changedBytes.map(\.offset) == [expectedOffset] else {
                return fail("MoveWriter", diff.summary(), "Expected only Power offset \(hex(expectedOffset))")
            }
            let reparsed = try MoveTableParser(data: modified).parseMoves()
            guard reparsed.first(where: { $0.id == move.id })?.power == originalPower + 1 else {
                return fail("MoveWriter", "Parser did not reload Power \(originalPower + 1)")
            }

            return pass("MoveWriter", "\(move.name) Power \(originalPower) -> \(originalPower + 1)", diff.summary())
        } catch {
            return fail("MoveWriter", error.localizedDescription)
        }
    }

    private static func runTrainerWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let trainers = try TrainerTableParser(data: data).parseTrainers()
            guard var trainer = trainers.first(where: { $0.party.first?.level ?? 100 < 100 }) else {
                return fail("TrainerWriter", "No trainer with incrementable party level found")
            }
            let originalPartyPointer = trainer.partyOffset
            let originalEntry = data[trainer.entryOffset..<(trainer.entryOffset + 40)]
            var member = trainer.party[0]
            let originalLevel = member.level
            member.level += 1
            trainer.party[0] = member

            var modified = data
            try TrainerTableParser.write(trainer, into: &modified)
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffset = member.offset + 2
            guard diff.changedBytes.map(\.offset) == [expectedOffset] else {
                return fail("TrainerWriter", diff.summary(), "Expected only Level offset \(hex(expectedOffset))")
            }
            guard modified[trainer.entryOffset..<(trainer.entryOffset + 40)] == originalEntry else {
                return fail("TrainerWriter", "Trainer entry changed even though only party level was edited")
            }
            let reparsed = try TrainerTableParser(data: modified).parseTrainers()
            guard let reloaded = reparsed.first(where: { $0.id == trainer.id }),
                  reloaded.partyOffset == originalPartyPointer,
                  reloaded.party.first?.level == originalLevel + 1 else {
                return fail("TrainerWriter", "Parser did not reload trainer level or pointer changed")
            }

            return pass("TrainerWriter",
                        "\(trainer.name) \(trainer.partyFormat.title)",
                        "Party pointer unchanged: \(hex(originalPartyPointer))",
                        "Level \(originalLevel) -> \(originalLevel + 1)",
                        diff.summary())
        } catch {
            return fail("TrainerWriter", error.localizedDescription)
        }
    }

    private static func runEncounterWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let areas = try WildEncounterTableParser(data: data).parseAreas()
            guard var area = areas.first(where: { area in
                area.groups.contains { group in group.slots.contains { $0.minLevel < $0.maxLevel && $0.minLevel < 100 } }
            }) else {
                return fail("EncounterWriter", "No encounter slot with incrementable min level found")
            }
            guard let groupIndex = area.groups.firstIndex(where: { $0.slots.contains { $0.minLevel < $0.maxLevel && $0.minLevel < 100 } }),
                  let slotIndex = area.groups[groupIndex].slots.firstIndex(where: { $0.minLevel < $0.maxLevel && $0.minLevel < 100 }) else {
                return fail("EncounterWriter", "No editable encounter slot found")
            }

            let originalGroup = area.groups[groupIndex]
            var slot = originalGroup.slots[slotIndex]
            let originalMinLevel = slot.minLevel
            slot.minLevel += 1
            area.groups[groupIndex].slots[slotIndex] = slot

            var modified = data
            try WildEncounterTableParser.write(area, into: &modified)
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffset = slot.offset
            guard diff.changedBytes.map(\.offset) == [expectedOffset] else {
                return fail("EncounterWriter", diff.summary(), "Expected only min level offset \(hex(expectedOffset))")
            }
            let reparsed = try WildEncounterTableParser(data: modified).parseAreas()
            guard let reloadedArea = reparsed.first(where: { $0.id == area.id }),
                  let reloadedGroup = reloadedArea.groups.first(where: { $0.id == originalGroup.id }),
                  let reloadedSlot = reloadedGroup.slots.first(where: { $0.id == slot.id }),
                  reloadedSlot.minLevel == originalMinLevel + 1,
                  reloadedSlot.species == slot.species,
                  reloadedSlot.maxLevel == slot.maxLevel,
                  reloadedGroup.encounterRate == originalGroup.encounterRate else {
                return fail("EncounterWriter", "Parser did not reload min level or adjacent fields changed")
            }

            return pass("EncounterWriter",
                        "\(area.displayName) \(originalGroup.kind.title) slot \(slot.id + 1)",
                        "Min level \(originalMinLevel) -> \(originalMinLevel + 1)",
                        diff.summary())
        } catch {
            return fail("EncounterWriter", error.localizedDescription)
        }
    }

    private static func runItemWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let items = try ItemTableParser(data: data).parseItems()
            guard var item = items.first(where: { $0.name.uppercased() == "POTION" && $0.price < 65535 }) ?? items.first(where: { $0.price < 65535 }) else {
                return fail("ItemWriter", "No editable item found")
            }
            let originalPrice = item.price
            let originalPointers = [item.descriptionOffset.map(UInt32.init) ?? 0, item.fieldEffectPointer, item.battleUsage, item.battleEffectPointer, item.battleExtra]
            item.price += 1

            var modified = data
            try ItemTableParser.write(item, into: &modified)
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffsets = Set([item.statsOffset + 16, item.statsOffset + 17])
            guard Set(diff.changedBytes.map(\.offset)).isSubset(of: expectedOffsets), !diff.changedBytes.isEmpty else {
                return fail("ItemWriter", diff.summary(), "Expected only Price bytes at \(hex(item.statsOffset + 16))-\(hex(item.statsOffset + 17))")
            }
            let reparsed = try ItemTableParser(data: modified).parseItems()
            guard let reloaded = reparsed.first(where: { $0.id == item.id }),
                  reloaded.price == originalPrice + 1,
                  [reloaded.descriptionOffset.map(UInt32.init) ?? 0, reloaded.fieldEffectPointer, reloaded.battleUsage, reloaded.battleEffectPointer, reloaded.battleExtra] == originalPointers else {
                return fail("ItemWriter", "Parser did not reload price or pointer fields changed")
            }

            return pass("ItemWriter", "\(item.name) Price \(originalPrice) -> \(originalPrice + 1)", diff.summary())
        } catch {
            return fail("ItemWriter", error.localizedDescription)
        }
    }

    private static func runMapBanksResolverTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let maps = try MapTableParser(data: data).parseMaps()
            guard !maps.isEmpty else {
                return fail("MapBanksResolver", "BPEE recognized, but no valid map headers were found")
            }
            let groups = Set(maps.map(\.group)).count
            guard let first = maps.first else { return fail("MapBanksResolver", "No first map") }
            return pass(
                "MapBanksResolver",
                "BPEE recognized",
                "data.maps.banks fallback offset: 0x00084AA4",
                "Map groups found: \(groups)",
                "First valid header: \(hex(first.headerOffset))",
                "First layout: \(hex(first.layoutOffset))"
            )
        } catch {
            return fail("MapBanksResolver", error.localizedDescription)
        }
    }

    private static func runMapParserTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let maps = try MapTableParser(data: data).parseMaps()
            guard let map = maps.first(where: { !$0.blocks.isEmpty }) else {
                return fail("MapParser", "No valid map parsed")
            }
            guard map.blocks.count == map.width * map.height else {
                return fail("MapParser", "Block count \(map.blocks.count) != \(map.width)x\(map.height)")
            }
            return pass("MapParser", "\(map.name) \(map.width)x\(map.height)", "Layout count = width * height")
        } catch {
            return fail("MapParser", error.localizedDescription)
        }
    }

    private static func runMapRendererTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let rom = EmeraldROM(data: data)
            let maps = try rom.maps()
            let selectedMaps = multiTilesetSample(from: maps, minimumCount: 10)
            guard selectedMaps.count >= 10 else {
                return fail("MapRenderer", "Only \(selectedMaps.count) renderable maps found for multi-map QA")
            }

            var details: [String] = []
            var failed: [String] = []
            for map in selectedMaps {
                let diagnostic = MapRenderer(data: data).diagnostics(for: map)
                guard let image = rom.mapImage(for: map) else {
                    failed.append("\(map.id) \(map.name): renderer returned nil")
                    continue
                }
                let expectedSize = NSSize(width: CGFloat(map.width * 16), height: CGFloat(map.height * 16))
                if image.size != expectedSize {
                    failed.append("\(map.id) \(map.name): image size \(image.size) != \(expectedSize)")
                }
                if !diagnostic.passed {
                    failed.append(contentsOf: diagnostic.reportLines)
                }
                details.append(contentsOf: diagnostic.reportLines.prefix(6))
            }
            guard failed.isEmpty else { return fail("MapRenderer", failed.joined(separator: "\n")) }
            return pass("MapRenderer", (["Multi-map render PASS: \(selectedMaps.count) maps"] + details).joined(separator: "\n"))
        } catch {
            return fail("MapRenderer", error.localizedDescription)
        }
    }

    private static func runMapWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let maps = try MapTableParser(data: data).parseMaps()
            guard let map = maps.first(where: { $0.blocks.contains { $0.metatileID < 0x03FF } }),
                  var block = map.blocks.first(where: { $0.metatileID < 0x03FF }) else {
                return fail("MapWriter", "No editable map block found")
            }
            let original = block
            let originalCollision = block.collision
            let originalElevation = block.elevation
            block.metatileID += 1
            var modified = data
            try MapTableParser.writeBlock(block, into: &modified)
            guard modified.count == data.count else { return fail("MapWriter", "ROM size changed") }
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffsets = Set([block.offset, block.offset + 1])
            guard Set(diff.changedBytes.map(\.offset)).isSubset(of: expectedOffsets), !diff.changedBytes.isEmpty else {
                return fail("MapWriter", diff.summary(), "Expected only block bytes \(hex(block.offset))-\(hex(block.offset + 1))")
            }
            let reparsed = try MapTableParser(data: modified).parseMaps()
            guard let reloaded = reparsed.first(where: { $0.id == map.id })?.blocks.first(where: { $0.id == block.id }),
                  reloaded.metatileID == original.metatileID + 1,
                  reloaded.collision == originalCollision,
                  reloaded.elevation == originalElevation else {
                return fail("MapWriter", "Parser did not reload metatile or collision/elevation were not preserved")
            }
            var restored = modified
            try MapTableParser.writeBlock(original, into: &restored)
            guard restored == data else { return fail("MapWriter", "Undo restore did not match original data") }
            return pass("MapWriter", "\(map.name) block \(block.x),\(block.y)", diff.summary(), "Collision/elevation preserved: \(originalCollision)/\(originalElevation)", "Undo restore PASS")
        } catch {
            return fail("MapWriter", error.localizedDescription)
        }
    }

    private static func runMapWarpWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let maps = try MapTableParser(data: data).parseMaps()
            guard let map = maps.first(where: { $0.warps.contains { $0.x < 32767 } }),
                  var warp = map.warps.first(where: { $0.x < 32767 }) else {
                return fail("WarpWriter", "No editable warp found")
            }
            let originalDestination = (warp.destinationGroup, warp.destinationMap, warp.warpID)
            warp.x += 1
            var modified = data
            try MapTableParser.writeWarp(warp, into: &modified)
            guard modified.count == data.count else { return fail("WarpWriter", "ROM size changed") }
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffsets = Set([warp.offset, warp.offset + 1])
            guard Set(diff.changedBytes.map(\.offset)).isSubset(of: expectedOffsets), !diff.changedBytes.isEmpty else {
                return fail("WarpWriter", diff.summary(), "Expected only Warp X bytes")
            }
            let reparsed = try MapTableParser(data: modified).parseMaps()
            guard let reloaded = reparsed.first(where: { $0.id == map.id })?.warps.first(where: { $0.id == warp.id }),
                  reloaded.x == warp.x,
                  (reloaded.destinationGroup, reloaded.destinationMap, reloaded.warpID) == originalDestination else {
                return fail("WarpWriter", "Parser did not reload warp X or destination changed")
            }
            return pass("WarpWriter", "\(map.name) warp #\(warp.id + 1)", diff.summary())
        } catch {
            return fail("WarpWriter", error.localizedDescription)
        }
    }

    private static func runMapObjectWriterTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            try EmeraldROM.validateSupported(data)
            let maps = try MapTableParser(data: data).parseMaps()
            guard let map = maps.first(where: { $0.objects.contains { $0.x < 32767 } }),
                  var object = map.objects.first(where: { $0.x < 32767 }) else {
                return fail("ObjectEventWriter", "No editable object event found")
            }
            let originalScript = object.scriptPointer
            object.x += 1
            var modified = data
            try MapTableParser.writeObject(object, into: &modified)
            guard modified.count == data.count else { return fail("ObjectEventWriter", "ROM size changed") }
            let diff = ROMDiffReport.compare(original: data, modified: modified)
            let expectedOffsets = Set([object.offset + 4, object.offset + 5])
            guard Set(diff.changedBytes.map(\.offset)).isSubset(of: expectedOffsets), !diff.changedBytes.isEmpty else {
                return fail("ObjectEventWriter", diff.summary(), "Expected only Object X bytes")
            }
            let reparsed = try MapTableParser(data: modified).parseMaps()
            guard let reloaded = reparsed.first(where: { $0.id == map.id })?.objects.first(where: { $0.id == object.id }),
                  reloaded.x == object.x,
                  reloaded.scriptPointer == originalScript else {
                return fail("ObjectEventWriter", "Parser did not reload object X or script pointer changed")
            }
            return pass("ObjectEventWriter", "\(map.name) object #\(object.id + 1)", diff.summary())
        } catch {
            return fail("ObjectEventWriter", error.localizedDescription)
        }
    }

    private static func runSaveReloadTest(on data: Data) -> ROMIntegrityTestResult {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("HexManiaMac_QA_\(UUID().uuidString).gba")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try EmeraldROM.validateSupported(data)
            var species = try PokemonTableParser(data: data).parseSpecies()
            guard let index = species.firstIndex(where: { $0.name.uppercased() == "RAYQUAZA" }),
                  species[index].baseStats.hp < 255 else {
                return fail("SaveReload", "RAYQUAZA not available for save/reload")
            }
            let originalHP = species[index].baseStats.hp
            species[index].baseStats.hp += 1
            var modified = data
            try PokemonTableParser.write(species[index], into: &modified)
            guard modified.count == data.count else { return fail("SaveReload", "ROM size changed before save") }
            try modified.write(to: tempURL, options: .atomic)
            let reloadedData = try Data(contentsOf: tempURL)
            guard reloadedData == modified else { return fail("SaveReload", "Saved file bytes do not match modified data") }
            let reloadedSpecies = try PokemonTableParser(data: reloadedData).parseSpecies()
            guard reloadedSpecies.first(where: { $0.id == species[index].id })?.baseStats.hp == originalHP + 1 else {
                return fail("SaveReload", "Reloaded parser did not preserve HP")
            }
            return pass("SaveReload", "Temp file saved and removed", "ROM size unchanged: \(modified.count) bytes")
        } catch {
            return fail("SaveReload", error.localizedDescription)
        }
    }

    private static func runHeaderGuardTest(on data: Data) -> ROMIntegrityTestResult {
        do {
            var invalid = data
            guard invalid.count >= 0xB0 else { return fail("HeaderGuard", "Data too small for header guard test") }
            invalid[0xAC] = 0x41
            invalid[0xAD] = 0x41
            invalid[0xAE] = 0x41
            invalid[0xAF] = 0x41
            guard var species = try? PokemonTableParser(data: data).parseSpecies().first else {
                return fail("HeaderGuard", "No species available for writer guard")
            }
            species.baseStats.hp = min(species.baseStats.hp + 1, 255)
            do {
                try PokemonTableParser.write(species, into: &invalid)
                return fail("HeaderGuard", "Writer accepted non-BPEE header")
            } catch {
                return pass("HeaderGuard", "Writers reject non-BPEE ROM data")
            }
        }
    }

    private static func pass(_ name: String, _ details: String...) -> ROMIntegrityTestResult {
        ROMIntegrityTestResult(name: name, passed: true, details: details)
    }

    private static func fail(_ name: String, _ details: String...) -> ROMIntegrityTestResult {
        ROMIntegrityTestResult(name: name, passed: false, details: details)
    }

    private static func hex(_ value: Int) -> String {
        String(format: "0x%08X", value)
    }

    private static func multiTilesetSample(from maps: [MapData], minimumCount: Int) -> [MapData] {
        var selected: [MapData] = []
        var seenTilesets = Set<String>()
        for map in maps where !map.blocks.isEmpty {
            let key = "\(map.primaryTilesetOffset ?? -1)-\(map.secondaryTilesetOffset ?? -1)"
            guard !seenTilesets.contains(key) else { continue }
            seenTilesets.insert(key)
            selected.append(map)
            if selected.count >= minimumCount { return selected }
        }
        for map in maps where !map.blocks.isEmpty && !selected.contains(where: { $0.id == map.id }) {
            selected.append(map)
            if selected.count >= minimumCount { break }
        }
        return selected
    }
}

struct MapParsingError: LocalizedError {
    let report: String

    var errorDescription: String? {
        "Impossibile leggere la tabella mappe."
    }
}

struct PokemonTableParser {
    private enum Layout {
        // HexManiacAdvance src/HexManiac.Core/Models/Code/tableReference.txt, BPEE0 column.
        // Entries such as 0x144 and 0x1BC are pointer sources in the ROM header/anchor area.
        static let namesPointerSource = 0x000144
        static let statsPointerSource = 0x0001BC
        static let abilitiesPointerSource = 0x0001C0
        static let typeNamesPointerSource = 0x0166F4
        static let speciesCount = 412
        static let nameLength = 11
        static let typeCount = 18
        static let typeNameLength = 7
        static let abilityCount = 78
        static let abilityNameLength = 13
        static let statsLength = 28
    }

    let data: Data

    func parseSpecies() throws -> [PokemonSpecies] {
        let namesAddress = try resolveTableAddress(Layout.namesPointerSource, tableName: "data.pokemon.names")
        let statsAddress = try resolveTableAddress(Layout.statsPointerSource, tableName: "data.pokemon.stats")
        guard hasRange(namesAddress, length: Layout.speciesCount * Layout.nameLength),
              hasRange(statsAddress, length: Layout.speciesCount * Layout.statsLength) else {
            throw ROMError.unsupportedSemanticTables
        }

        return (0..<Layout.speciesCount).compactMap { index in
            let nameOffset = namesAddress + index * Layout.nameLength
            let statsOffset = statsAddress + index * Layout.statsLength
            let name = PCSStringCodec.decode(data, start: nameOffset, length: Layout.nameLength)
            guard index != 0, !name.isEmpty, !name.contains("\\!") else { return nil }
            return PokemonSpecies(
                id: index,
                name: name,
                baseStats: PokemonBaseStats(
                    hp: byte(statsOffset + 0),
                    attack: byte(statsOffset + 1),
                    defense: byte(statsOffset + 2),
                    speed: byte(statsOffset + 3),
                    specialAttack: byte(statsOffset + 4),
                    specialDefense: byte(statsOffset + 5)
                ),
                type1: byte(statsOffset + 6),
                type2: byte(statsOffset + 7),
                catchRate: byte(statsOffset + 8),
                baseExperience: byte(statsOffset + 9),
                genderRatio: byte(statsOffset + 16),
                stepsToHatch: byte(statsOffset + 17),
                baseFriendship: byte(statsOffset + 18),
                growthRate: byte(statsOffset + 19),
                ability1: byte(statsOffset + 22),
                ability2: byte(statsOffset + 23),
                statsOffset: statsOffset
            )
        }
    }

    func parseTypes() throws -> [PokemonNamedValue] {
        let address = try resolveTableAddress(Layout.typeNamesPointerSource, tableName: "data.pokemon.type.names")
        return try parseNamedValues(address: address, count: Layout.typeCount, length: Layout.typeNameLength, tableName: "data.pokemon.type.names")
    }

    func parseAbilities() throws -> [PokemonNamedValue] {
        let address = try resolveTableAddress(Layout.abilitiesPointerSource, tableName: "data.abilities.names")
        return try parseNamedValues(address: address, count: Layout.abilityCount, length: Layout.abilityNameLength, tableName: "data.abilities.names")
    }

    static func write(_ species: PokemonSpecies, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = PokemonTableParser(data: data)
        let statsAddress = try parser.resolveTableAddress(Layout.statsPointerSource, tableName: "data.pokemon.stats")
        let offset = species.statsOffset
        guard offset >= statsAddress,
              offset + Layout.statsLength <= data.count,
              (offset - statsAddress).isMultiple(of: Layout.statsLength) else {
            throw ROMError.unsupportedSemanticTables
        }

        try validateByte(species.baseStats.hp, "HP")
        try validateByte(species.baseStats.attack, "Attack")
        try validateByte(species.baseStats.defense, "Defense")
        try validateByte(species.baseStats.speed, "Speed")
        try validateByte(species.baseStats.specialAttack, "Special Attack")
        try validateByte(species.baseStats.specialDefense, "Special Defense")
        try validateByte(species.type1, "Type 1")
        try validateByte(species.type2, "Type 2")
        try validateByte(species.catchRate, "Catch rate")
        try validateByte(species.baseExperience, "Base EXP")
        try validateByte(species.genderRatio, "Gender ratio")
        try validateByte(species.stepsToHatch, "Steps to hatch")
        try validateByte(species.baseFriendship, "Friendship")
        try validateByte(species.growthRate, "Growth rate")
        try validateByte(species.ability1, "Ability 1")
        try validateByte(species.ability2, "Ability 2")

        data[offset + 0] = UInt8(species.baseStats.hp)
        data[offset + 1] = UInt8(species.baseStats.attack)
        data[offset + 2] = UInt8(species.baseStats.defense)
        data[offset + 3] = UInt8(species.baseStats.speed)
        data[offset + 4] = UInt8(species.baseStats.specialAttack)
        data[offset + 5] = UInt8(species.baseStats.specialDefense)
        data[offset + 6] = UInt8(species.type1)
        data[offset + 7] = UInt8(species.type2)
        data[offset + 8] = UInt8(species.catchRate)
        data[offset + 9] = UInt8(species.baseExperience)
        data[offset + 16] = UInt8(species.genderRatio)
        data[offset + 17] = UInt8(species.stepsToHatch)
        data[offset + 18] = UInt8(species.baseFriendship)
        data[offset + 19] = UInt8(species.growthRate)
        data[offset + 22] = UInt8(species.ability1)
        data[offset + 23] = UInt8(species.ability2)
    }

    private func parseNamedValues(address: Int, count: Int, length: Int, tableName: String) throws -> [PokemonNamedValue] {
        guard hasRange(address, length: count * length) else { throw ROMError.missingTable(tableName) }
        return (0..<count).map { index in
            let name = PCSStringCodec.decode(data, start: address + index * length, length: length)
            return PokemonNamedValue(id: index, name: name.isEmpty ? "#\(index)" : name)
        }
    }

    private func resolveTableAddress(_ source: Int, tableName: String) throws -> Int {
        if let pointer = readPointer(at: source), hasRange(pointer, length: 1) {
            return pointer
        }
        guard hasRange(source, length: 1) else { throw ROMError.missingTable(tableName) }
        return source
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        return Int(raw - 0x0800_0000)
    }

    private func byte(_ offset: Int) -> Int {
        Int(data[offset])
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private static func validateByte(_ value: Int, _ label: String) throws {
        guard (0...255).contains(value) else { throw ROMError.valueOutOfRange(label) }
    }
}

struct MoveTableParser {
    private enum Layout {
        // HexManiacAdvance src/HexManiac.Core/Models/Code/tableReference.txt, BPEE0 column.
        static let namesPointerSource = 0x000148
        static let statsPointerSource = 0x0001CC
        static let moveCount = 355
        static let nameLength = 13
        static let statsLength = 12
    }

    let data: Data

    func parseMoves() throws -> [MoveData] {
        let namesAddress = try resolveTableAddress(Layout.namesPointerSource, tableName: "data.pokemon.moves.names")
        let statsAddress = try resolveTableAddress(Layout.statsPointerSource, tableName: "data.pokemon.moves.stats.battle")
        guard hasRange(namesAddress, length: Layout.moveCount * Layout.nameLength),
              hasRange(statsAddress, length: Layout.moveCount * Layout.statsLength) else {
            throw ROMError.unsupportedSemanticTables
        }

        return (0..<Layout.moveCount).compactMap { index in
            let nameOffset = namesAddress + index * Layout.nameLength
            let statsOffset = statsAddress + index * Layout.statsLength
            let name = PCSStringCodec.decode(data, start: nameOffset, length: Layout.nameLength)
            guard !name.isEmpty, !name.contains("\\!") else { return nil }
            return MoveData(
                id: index,
                name: name,
                effectID: byte(statsOffset + 0),
                power: byte(statsOffset + 1),
                type: byte(statsOffset + 2),
                accuracy: byte(statsOffset + 3),
                pp: byte(statsOffset + 4),
                effectChance: byte(statsOffset + 5),
                target: byte(statsOffset + 6),
                priority: signedByte(statsOffset + 7),
                info: byte(statsOffset + 8),
                statsOffset: statsOffset
            )
        }
    }

    static func write(_ move: MoveData, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = MoveTableParser(data: data)
        let statsAddress = try parser.resolveTableAddress(Layout.statsPointerSource, tableName: "data.pokemon.moves.stats.battle")
        let offset = move.statsOffset
        guard offset >= statsAddress,
              offset + Layout.statsLength <= data.count,
              (offset - statsAddress).isMultiple(of: Layout.statsLength) else {
            throw ROMError.unsupportedSemanticTables
        }

        try validateByte(move.effectID, "Move effect")
        try validateByte(move.power, "Move power")
        try validateByte(move.type, "Move type")
        try validateByte(move.accuracy, "Move accuracy")
        try validateByte(move.pp, "Move PP")
        try validateByte(move.effectChance, "Move effect chance")
        try validateByte(move.target, "Move target")
        try validateSignedByte(move.priority, "Move priority")
        try validateByte(move.info, "Move info")

        data[offset + 0] = UInt8(move.effectID)
        data[offset + 1] = UInt8(move.power)
        data[offset + 2] = UInt8(move.type)
        data[offset + 3] = UInt8(move.accuracy)
        data[offset + 4] = UInt8(move.pp)
        data[offset + 5] = UInt8(move.effectChance)
        data[offset + 6] = UInt8(move.target)
        data[offset + 7] = UInt8(bitPattern: Int8(move.priority))
        data[offset + 8] = UInt8(move.info)
    }

    private func resolveTableAddress(_ source: Int, tableName: String) throws -> Int {
        if let pointer = readPointer(at: source), hasRange(pointer, length: 1) {
            return pointer
        }
        guard hasRange(source, length: 1) else { throw ROMError.missingTable(tableName) }
        return source
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        return Int(raw - 0x0800_0000)
    }

    private func byte(_ offset: Int) -> Int {
        Int(data[offset])
    }

    private func signedByte(_ offset: Int) -> Int {
        Int(Int8(bitPattern: data[offset]))
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private static func validateByte(_ value: Int, _ label: String) throws {
        guard (0...255).contains(value) else { throw ROMError.valueOutOfRange(label) }
    }

    private static func validateSignedByte(_ value: Int, _ label: String) throws {
        guard (-128...127).contains(value) else { throw ROMError.signedValueOutOfRange(label) }
    }
}

struct LevelUpLearnsetParser {
    private enum Layout {
        // HexManiacAdvance src/HexManiac.Core/Models/Code/tableReference.txt (BPEE0)
        // and default.bpei0.toml. Both sources hold a child pointer to the gLevelUpLearnsets
        // pointer table. Empirically verified on the BPEI ROM: 0x69310 -> 0x08328D7C.
        static let bpeePointerSource = 0x06930C
        static let bpeiPointerSource = 0x069310
        static let speciesCount = 412
        static let pointerLength = 4
        static let maxMovesPerSpecies = 40
    }

    let data: Data

    private var pointerSource: Int {
        gameCode == "BPEI" ? Layout.bpeiPointerSource : Layout.bpeePointerSource
    }

    // Learnset records are bit-packed u16 LE: move = bits 0-8 (9 bits, supports IDs > 255),
    // level = bits 9-15 (7 bits), terminated by 0xFFFF. Confirmed against Tokop's Bulbasaur,
    // Charmander, Pikachu and Castform learnsets in the BPEE/BPEI ROMs.
    func parseLearnsets() throws -> [Int: [LevelUpMove]] {
        let tableAddress = try resolveTableAddress(pointerSource, tableName: "data.pokemon.moves.levelup")
        guard hasRange(tableAddress, length: Layout.speciesCount * Layout.pointerLength) else {
            throw ROMError.missingTable("data.pokemon.moves.levelup")
        }

        var result: [Int: [LevelUpMove]] = [:]
        for species in 1..<Layout.speciesCount {
            guard let learnsetOffset = readPointer(at: tableAddress + species * Layout.pointerLength),
                  let learnset = learnset(at: learnsetOffset) else { continue }
            result[species] = learnset
        }
        return result
    }

    private func learnset(at offset: Int) -> [LevelUpMove]? {
        guard hasRange(offset, length: 2) else { return nil }
        var moves: [LevelUpMove] = []
        var cursor = offset
        for _ in 0..<Layout.maxMovesPerSpecies {
            guard hasRange(cursor, length: 2) else { break }
            let value = readUInt16(at: cursor)
            if value == 0xFFFF { break }
            moves.append(LevelUpMove(move: value & 0x1FF, level: value >> 9))
            cursor += 2
        }
        return moves.isEmpty ? nil : moves
    }

    private func resolveTableAddress(_ source: Int, tableName: String) throws -> Int {
        if let pointer = readPointer(at: source), hasRange(pointer, length: 1) {
            return pointer
        }
        guard hasRange(source, length: 1) else { throw ROMError.missingTable(tableName) }
        return source
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        return Int(raw - 0x0800_0000)
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private var gameCode: String {
        guard data.count >= 0xB0 else { return "" }
        return String(bytes: data[0xAC..<0xB0], encoding: .ascii) ?? ""
    }
}

struct EmeraldSaveParser {
    private enum Layout {
        static let sectorSize = 0x1000
        static let sectorDataLength = 0xFF4
        static let sectorCount = 14
        static let saveBlockLength = sectorSize * sectorCount
        static let sectionIDOffset = 0xFF4
        static let checksumOffset = 0xFF6
        static let signatureOffset = 0xFF8
        static let saveIndexOffset = 0xFFC
        static let signature = UInt32(0x0801_2025)
        static let saveBlock1SectionID = 1
        static let trainerSectionID = 0
        static let partyCountOffset = 0x234
        static let partyOffset = 0x238
        static let pokemonLength = 100
        static let boxPokemonLength = 80
        static let encryptedDataOffset = 32
        static let encryptedDataLength = 48
        static let trainerNameOffset = 0x000
        static let trainerNameLength = 7
        static let trainerGenderOffset = 0x008
        static let trainerIDOffset = 0x00A
        static let secretIDOffset = 0x00C
        static let playTimeOffset = 0x00E
        static let securityKeyOffset = 0x0AC
        static let pokedexOwnedOffset = 0x028
        static let pokedexSeenOffset = 0x05C
        static let pokedexBitsLength = 52
        static let saveBlock1MoneyOffset = 0x490
        static let saveBlock1CoinsOffset = 0x494
        static let currentMapOffset = 0x004
        static let playerXOffset = 0x000
        static let playerYOffset = 0x002
        static let pcSectionStartID = 5
        static let pcSectionEndID = 13
        static let pcStorageLength = 33_880
        static let pcBoxCount = 14
        static let pcBoxCapacity = 30
        static let pcBoxDataOffset = 0x004
        static let pcBoxNamesOffset = 0x8344
        static let pcBoxNameLength = 9
    }

    let data: Data
    let fileURL: URL

    func parse() throws -> PlayerSaveData {
        guard data.count >= Layout.saveBlockLength * 2 else { throw ROMError.invalidSaveFile }
        let blocks = [0, Layout.saveBlockLength].compactMap(parseSaveBlock(at:))
        guard let activeBlock = blocks.max(by: { $0.saveIndex < $1.saveIndex }),
              let saveBlock1Offset = activeBlock.sections[Layout.saveBlock1SectionID]?.offset else {
            throw ROMError.invalidSaveFile
        }
        let trainerSectionOffset = activeBlock.sections[Layout.trainerSectionID]?.offset

        let partyCountOffset = saveBlock1Offset + Layout.partyCountOffset
        guard hasRange(partyCountOffset, length: 1) else { throw ROMError.invalidSaveFile }
        let partyCount = min(Int(data[partyCountOffset]), 6)
        let partyBaseOffset = saveBlock1Offset + Layout.partyOffset
        guard hasRange(partyBaseOffset, length: partyCount * Layout.pokemonLength) else { throw ROMError.invalidSaveFile }

        var party: [PlayerPartyPokemon] = []
        for slot in 0..<partyCount {
            if let pokemon = try parsePokemon(at: partyBaseOffset + slot * Layout.pokemonLength, slot: slot) {
                party.append(pokemon)
            }
        }
        let trainer = trainerSectionOffset.map(parseTrainerInfo(at:)) ?? SaveTrainerInfo(name: nil, gender: nil, trainerID: nil, secretID: nil, securityKey: nil, nationalDexUnlocked: nil)
        let securityKey = trainer.securityKey ?? 0
        let pcStorage = pcStorageData(from: activeBlock)
        let sections = sectionInfos(for: activeBlock)

        return PlayerSaveData(
            fileURL: fileURL,
            activeSaveIndex: activeBlock.saveIndex,
            saveBlockOffset: activeBlock.offset,
            saveBlock1SectionOffset: saveBlock1Offset,
            allSectionChecksumsValid: activeBlock.allChecksumsValid,
            gameTitle: "Pokémon Emerald",
            trainer: trainer,
            playTime: trainerSectionOffset.flatMap { parsePlayTime(at: $0 + Layout.playTimeOffset) },
            saveCount: activeBlock.saveIndex,
            money: parseEncryptedMoney(saveBlock1Offset: saveBlock1Offset, securityKey: securityKey),
            coins: parseEncryptedCoins(saveBlock1Offset: saveBlock1Offset, securityKey: securityKey),
            partyCountOffset: partyCountOffset,
            party: party,
            boxes: parseBoxes(from: pcStorage),
            bagPockets: parseBag(saveBlock1Offset: saveBlock1Offset, securityKey: securityKey),
            pokedex: trainerSectionOffset.flatMap(parsePokedex(at:)),
            progression: parseProgression(saveBlock1Offset: saveBlock1Offset),
            sections: sections,
            activeSlot: activeBlock.offset == 0 ? 0 : 1
        )
    }

    private struct SaveSection {
        let offset: Int
        let slot: Int
        let sectionID: Int
        let storedChecksum: UInt16
        let calculatedChecksum: UInt16
        let saveIndex: UInt32

        var checksumValid: Bool {
            storedChecksum == calculatedChecksum
        }
    }

    private struct SaveBlock {
        let offset: Int
        let saveIndex: UInt32
        let sections: [Int: SaveSection]

        var allChecksumsValid: Bool {
            sections.count == Layout.sectorCount && sections.values.allSatisfy(\.checksumValid)
        }
    }

    private func parseSaveBlock(at blockOffset: Int) -> SaveBlock? {
        guard hasRange(blockOffset, length: Layout.saveBlockLength) else { return nil }
        var sections: [Int: SaveSection] = [:]
        var saveIndex: UInt32 = 0

        for sector in 0..<Layout.sectorCount {
            let offset = blockOffset + sector * Layout.sectorSize
            guard readUInt32(at: offset + Layout.signatureOffset) == Layout.signature else { continue }
            let sectionID = Int(readUInt16(at: offset + Layout.sectionIDOffset))
            guard (0..<Layout.sectorCount).contains(sectionID) else { continue }
            let storedChecksum = readUInt16(at: offset + Layout.checksumOffset)
            let calculatedChecksum = checksum(at: offset, length: Layout.sectorDataLength)
            let sectionSaveIndex = readUInt32(at: offset + Layout.saveIndexOffset)
            saveIndex = max(saveIndex, sectionSaveIndex)
            sections[sectionID] = SaveSection(
                offset: offset,
                slot: blockOffset == 0 ? 0 : 1,
                sectionID: sectionID,
                storedChecksum: storedChecksum,
                calculatedChecksum: calculatedChecksum,
                saveIndex: sectionSaveIndex
            )
        }

        guard sections[Layout.saveBlock1SectionID] != nil else { return nil }
        return SaveBlock(offset: blockOffset, saveIndex: saveIndex, sections: sections)
    }

    private func sectionInfos(for block: SaveBlock) -> [SaveSectionInfo] {
        block.sections.values
            .sorted { $0.sectionID < $1.sectionID }
            .map {
                SaveSectionInfo(
                    id: $0.sectionID,
                    slot: $0.slot,
                    sectionID: $0.sectionID,
                    offset: $0.offset,
                    storedChecksum: $0.storedChecksum,
                    calculatedChecksum: $0.calculatedChecksum,
                    saveIndex: $0.saveIndex
                )
            }
    }

    private func parseTrainerInfo(at sectionOffset: Int) -> SaveTrainerInfo {
        let name = hasRange(sectionOffset + Layout.trainerNameOffset, length: Layout.trainerNameLength)
            ? PCSStringCodec.decode(data, start: sectionOffset + Layout.trainerNameOffset, length: Layout.trainerNameLength)
            : ""
        let gender = hasRange(sectionOffset + Layout.trainerGenderOffset, length: 1) ? Int(data[sectionOffset + Layout.trainerGenderOffset]) : nil
        let trainerID = hasRange(sectionOffset + Layout.trainerIDOffset, length: 2) ? readUInt16(at: sectionOffset + Layout.trainerIDOffset) : nil
        let secretID = hasRange(sectionOffset + Layout.secretIDOffset, length: 2) ? readUInt16(at: sectionOffset + Layout.secretIDOffset) : nil
        let securityKey = hasRange(sectionOffset + Layout.securityKeyOffset, length: 4) ? readUInt32(at: sectionOffset + Layout.securityKeyOffset) : nil
        return SaveTrainerInfo(
            name: name.isEmpty ? nil : name,
            gender: gender,
            trainerID: trainerID,
            secretID: secretID,
            securityKey: securityKey,
            nationalDexUnlocked: nil
        )
    }

    private func parsePlayTime(at offset: Int) -> SavePlayTime? {
        guard hasRange(offset, length: 5) else { return nil }
        return SavePlayTime(
            hours: Int(readUInt16(at: offset)),
            minutes: Int(data[offset + 2]),
            seconds: Int(data[offset + 3]),
            frames: Int(data[offset + 4])
        )
    }

    private func parseEncryptedMoney(saveBlock1Offset: Int, securityKey: UInt32) -> UInt32? {
        let offset = saveBlock1Offset + Layout.saveBlock1MoneyOffset
        guard hasRange(offset, length: 4) else { return nil }
        return readUInt32(at: offset) ^ securityKey
    }

    private func parseEncryptedCoins(saveBlock1Offset: Int, securityKey: UInt32) -> Int? {
        let offset = saveBlock1Offset + Layout.saveBlock1CoinsOffset
        guard hasRange(offset, length: 2) else { return nil }
        return Int(readUInt16(at: offset) ^ UInt16(truncatingIfNeeded: securityKey))
    }

    private func parseBag(saveBlock1Offset: Int, securityKey: UInt32) -> [SaveBagPocket] {
        let pockets: [(SaveBagPocketKind, String, Int, Int)] = [
            (.items, "Oggetti", 0x560, 30),
            (.keyItems, "Strumenti chiave", 0x5D8, 30),
            (.balls, "Poké Ball", 0x650, 16),
            (.machines, "MT/MN", 0x690, 64),
            (.berries, "Bacche", 0x790, 46)
        ]
        return pockets.map { kind, name, relativeOffset, count in
            let baseOffset = saveBlock1Offset + relativeOffset
            let items = (0..<count).compactMap { slot -> SaveBagItem? in
                let offset = baseOffset + slot * 4
                guard hasRange(offset, length: 4) else { return nil }
                let itemID = Int(readUInt16(at: offset))
                guard itemID != 0 else { return nil }
                let quantity = Int(readUInt16(at: offset + 2) ^ UInt16(truncatingIfNeeded: securityKey))
                return SaveBagItem(id: slot, slot: slot, itemID: itemID, quantity: quantity)
            }
            return SaveBagPocket(id: kind.rawValue, kind: kind, name: name, capacity: count, items: items)
        }
    }

    private func parsePokedex(at sectionOffset: Int) -> SavePokedexData? {
        let caughtOffset = sectionOffset + Layout.pokedexOwnedOffset
        let seenOffset = sectionOffset + Layout.pokedexSeenOffset
        guard hasRange(caughtOffset, length: Layout.pokedexBitsLength),
              hasRange(seenOffset, length: Layout.pokedexBitsLength) else { return nil }
        let entries = (1...386).map { speciesID in
            SavePokedexEntry(
                id: speciesID,
                seen: bitIsSet(offset: seenOffset, bitIndex: speciesID - 1),
                caught: bitIsSet(offset: caughtOffset, bitIndex: speciesID - 1)
            )
        }
        return SavePokedexData(entries: entries)
    }

    private func parseProgression(saveBlock1Offset: Int) -> SaveProgressionData {
        let mapGroupOffset = saveBlock1Offset + Layout.currentMapOffset
        let xOffset = saveBlock1Offset + Layout.playerXOffset
        let yOffset = saveBlock1Offset + Layout.playerYOffset
        return SaveProgressionData(
            badges: nil,
            mapGroup: hasRange(mapGroupOffset, length: 2) ? Int(data[mapGroupOffset]) : nil,
            mapNumber: hasRange(mapGroupOffset, length: 2) ? Int(data[mapGroupOffset + 1]) : nil,
            x: hasRange(xOffset, length: 2) ? Int(readUInt16(at: xOffset)) : nil,
            y: hasRange(yOffset, length: 2) ? Int(readUInt16(at: yOffset)) : nil,
            healLocation: nil
        )
    }

    private func pcStorageData(from block: SaveBlock) -> [UInt8]? {
        var bytes: [UInt8] = []
        for sectionID in Layout.pcSectionStartID...Layout.pcSectionEndID {
            guard let section = block.sections[sectionID], hasRange(section.offset, length: Layout.sectorDataLength) else {
                return nil
            }
            bytes.append(contentsOf: data[section.offset..<(section.offset + Layout.sectorDataLength)])
        }
        return Array(bytes.prefix(Layout.pcStorageLength))
    }

    private func parseBoxes(from storage: [UInt8]?) -> [SavePCBox] {
        guard let storage, storage.count >= Layout.pcBoxNamesOffset else {
            return (0..<Layout.pcBoxCount).map { SavePCBox(id: $0, name: "Box \($0 + 1)", pokemon: []) }
        }
        return (0..<Layout.pcBoxCount).map { boxIndex in
            let pokemon = (0..<Layout.pcBoxCapacity).compactMap { slot -> SaveBoxPokemon? in
                let offset = Layout.pcBoxDataOffset + (boxIndex * Layout.pcBoxCapacity + slot) * Layout.boxPokemonLength
                return parseBoxPokemon(storage, at: offset, boxIndex: boxIndex, slot: slot)
            }
            let nameOffset = Layout.pcBoxNamesOffset + boxIndex * Layout.pcBoxNameLength
            let name: String
            if nameOffset + Layout.pcBoxNameLength <= storage.count {
                name = PCSStringCodec.decode(Data(storage), start: nameOffset, length: Layout.pcBoxNameLength)
            } else {
                name = ""
            }
            return SavePCBox(id: boxIndex, name: name.isEmpty ? "Box \(boxIndex + 1)" : name, pokemon: pokemon)
        }
    }

    private func parseBoxPokemon(_ storage: [UInt8], at offset: Int, boxIndex: Int, slot: Int) -> SaveBoxPokemon? {
        guard offset >= 0, offset + Layout.boxPokemonLength <= storage.count else { return nil }
        let personality = Self.readUInt32(storage, at: offset)
        let otID = Self.readUInt32(storage, at: offset + 4)
        guard personality != 0 || otID != 0 else { return nil }
        let nickname = PCSStringCodec.decode(Data(storage), start: offset + 8, length: 10)
        let storedChecksum = Self.readUInt16(storage, at: offset + 28)
        let decrypted = Self.decryptSecureData(from: Data(storage), pokemonOffset: offset, key: personality ^ otID)
        guard decrypted.count == Layout.encryptedDataLength else { return nil }
        let calculatedChecksum = Self.checksum(decrypted)
        let order = Self.substructOrders[Int(personality % 24)]
        let growth = substruct(0, order: order, data: decrypted)
        let attacks = substruct(1, order: order, data: decrypted)
        let misc = substruct(3, order: order, data: decrypted)
        guard growth.count == 12, attacks.count == 12, misc.count == 12 else { return nil }
        let ivData = Self.readUInt32(misc, at: 4)
        return SaveBoxPokemon(
            id: boxIndex * Layout.pcBoxCapacity + slot,
            boxIndex: boxIndex,
            slot: slot,
            personality: personality,
            otID: otID,
            nickname: nickname.isEmpty ? "Slot \(slot + 1)" : nickname,
            species: Int(Self.readUInt16(growth, at: 0)),
            heldItem: Int(Self.readUInt16(growth, at: 2)),
            experience: Self.readUInt32(growth, at: 4),
            moves: (0..<4).map { Int(Self.readUInt16(attacks, at: $0 * 2)) },
            pp: (0..<4).map { Int(attacks[8 + $0]) },
            ivs: PokemonStatSpread(
                hp: Int(ivData & 0x1F),
                attack: Int((ivData >> 5) & 0x1F),
                defense: Int((ivData >> 10) & 0x1F),
                specialAttack: Int((ivData >> 20) & 0x1F),
                specialDefense: Int((ivData >> 25) & 0x1F),
                speed: Int((ivData >> 15) & 0x1F)
            ),
            isEgg: ((ivData >> 30) & 0x01) != 0,
            checksumValid: storedChecksum == calculatedChecksum
        )
    }

    private func parsePokemon(at offset: Int, slot: Int) throws -> PlayerPartyPokemon? {
        guard hasRange(offset, length: Layout.pokemonLength) else { return nil }
        let personality = readUInt32(at: offset)
        let otID = readUInt32(at: offset + 4)
        guard personality != 0 || otID != 0 else { return nil }

        let nickname = PCSStringCodec.decode(data, start: offset + 8, length: 10)
        let storedChecksum = readUInt16(at: offset + 28)
        let decrypted = decryptedSecureData(at: offset, key: personality ^ otID)
        let calculatedChecksum = checksum(decrypted)
        guard storedChecksum == calculatedChecksum else {
            print("[SAVE] Pokémon checksum failed slot \(slot + 1): stored \(storedChecksum), calculated \(calculatedChecksum)")
            throw ROMError.invalidPokemonChecksum(slot + 1)
        }

        let order = Self.substructOrders[Int(personality % 24)]
        let growth = substruct(0, order: order, data: decrypted)
        let attacks = substruct(1, order: order, data: decrypted)
        let evs = substruct(2, order: order, data: decrypted)
        let misc = substruct(3, order: order, data: decrypted)
        print("[SAVE] Pokémon slot \(slot + 1)")
        print("[SAVE] personality: \(String(format: "0x%08X", personality))")
        print("[SAVE] OT ID: \(String(format: "0x%08X", otID))")
        print("[SAVE] personality % 24: \(personality % 24)")
        print("[SAVE] secure data offset: \(offset + Layout.encryptedDataOffset)")
        print("[SAVE] secure data length: \(decrypted.count)")
        print("[SAVE] permutation: \(order)")
        print("[SAVE] growth count: \(growth.count)")
        print("[SAVE] attacks count: \(attacks.count)")
        print("[SAVE] evs count: \(evs.count)")
        print("[SAVE] misc count: \(misc.count)")
        guard decrypted.count == Layout.encryptedDataLength,
              growth.count == 12,
              attacks.count == 12,
              evs.count == 12,
              misc.count == 12 else {
            throw ROMError.invalidPokemonSubstructures(slot + 1)
        }
        print("[SAVE] species: \(readUInt16(growth, at: 0))")
        print("[SAVE] experience: \(readUInt32(growth, at: 4))")

        let ivData = readUInt32(misc, at: 4)
        let metInfo = readUInt16(misc, at: 2)
        return PlayerPartyPokemon(
            id: slot,
            slot: slot,
            offset: offset,
            personality: personality,
            otID: otID,
            nickname: nickname.isEmpty ? "Slot \(slot + 1)" : nickname,
            species: Int(readUInt16(growth, at: 0)),
            heldItem: Int(readUInt16(growth, at: 2)),
            experience: readUInt32(growth, at: 4),
            ppBonuses: Int(growth[8]),
            friendship: Int(growth[9]),
            moves: (0..<4).map { Int(readUInt16(attacks, at: $0 * 2)) },
            pp: (0..<4).map { Int(attacks[8 + $0]) },
            evs: PokemonStatSpread(
                hp: Int(evs[0]),
                attack: Int(evs[1]),
                defense: Int(evs[2]),
                specialAttack: Int(evs[4]),
                specialDefense: Int(evs[5]),
                speed: Int(evs[3])
            ),
            pokerus: Int(misc[0]),
            metLocation: Int(misc[1]),
            metLevel: Int(metInfo & 0x7F),
            pokeball: Int((metInfo >> 11) & 0x0F),
            abilityNum: Int((ivData >> 31) & 0x01),
            ivs: PokemonStatSpread(
                hp: Int(ivData & 0x1F),
                attack: Int((ivData >> 5) & 0x1F),
                defense: Int((ivData >> 10) & 0x1F),
                specialAttack: Int((ivData >> 20) & 0x1F),
                specialDefense: Int((ivData >> 25) & 0x1F),
                speed: Int((ivData >> 15) & 0x1F)
            ),
            isEgg: ((ivData >> 30) & 0x01) != 0,
            level: Int(data[offset + Layout.boxPokemonLength + 4]),
            currentHP: Int(readUInt16(at: offset + Layout.boxPokemonLength + 6)),
            maxHP: Int(readUInt16(at: offset + Layout.boxPokemonLength + 8)),
            attack: Int(readUInt16(at: offset + Layout.boxPokemonLength + 10)),
            defense: Int(readUInt16(at: offset + Layout.boxPokemonLength + 12)),
            speed: Int(readUInt16(at: offset + Layout.boxPokemonLength + 14)),
            specialAttack: Int(readUInt16(at: offset + Layout.boxPokemonLength + 16)),
            specialDefense: Int(readUInt16(at: offset + Layout.boxPokemonLength + 18)),
            checksumValid: storedChecksum == calculatedChecksum
        )
    }

    private func decryptedSecureData(at pokemonOffset: Int, key: UInt32) -> [UInt8] {
        var result = Array(data[(pokemonOffset + Layout.encryptedDataOffset)..<(pokemonOffset + Layout.encryptedDataOffset + Layout.encryptedDataLength)])
        for offset in stride(from: 0, to: result.count, by: 4) {
            let value = readUInt32(result, at: offset) ^ key
            result[offset] = UInt8(value & 0xFF)
            result[offset + 1] = UInt8((value >> 8) & 0xFF)
            result[offset + 2] = UInt8((value >> 16) & 0xFF)
            result[offset + 3] = UInt8((value >> 24) & 0xFF)
        }
        return result
    }

    private func substruct(_ logicalIndex: Int, order: [Int], data: [UInt8]) -> [UInt8] {
        let physicalIndex = order[logicalIndex]
        let start = physicalIndex * 12
        return Array(data[start..<(start + 12)])
    }

    private func checksum(at offset: Int, length: Int) -> UInt16 {
        var sum = UInt32(0)
        for index in stride(from: offset, to: offset + length, by: 4) {
            sum &+= readUInt32(at: index)
        }
        return UInt16(truncatingIfNeeded: (sum & 0xFFFF) + (sum >> 16))
    }

    private func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum = UInt32(0)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            sum &+= UInt32(readUInt16(bytes, at: index))
        }
        return UInt16(truncatingIfNeeded: sum)
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private func bitIsSet(offset: Int, bitIndex: Int) -> Bool {
        let byteOffset = offset + bitIndex / 8
        guard hasRange(byteOffset, length: 1) else { return false }
        return (data[byteOffset] & UInt8(1 << (bitIndex % 8))) != 0
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    static func writePartyPokemon(_ pokemon: PlayerPartyPokemon, into data: inout Data, saveBlock1SectionOffset: Int) throws {
        guard pokemon.offset >= 0,
              pokemon.offset + Layout.pokemonLength <= data.count,
              saveBlock1SectionOffset >= 0,
              saveBlock1SectionOffset + Layout.sectorSize <= data.count else {
            throw ROMError.invalidSaveFile
        }
        guard (0...255).contains(pokemon.friendship),
              (0...255).contains(pokemon.ppBonuses),
              validByteSpread(pokemon.evs),
              validIVSpread(pokemon.ivs),
              pokemon.moves.count == 4,
              pokemon.pp.count == 4,
              pokemon.moves.allSatisfy({ (0...65535).contains($0) }),
              pokemon.pp.allSatisfy({ (0...255).contains($0) }),
              (0...65535).contains(pokemon.heldItem) else {
            throw ROMError.invalidSaveEditValue
        }

        try PCSStringCodec.write(pokemon.nickname, into: &data, start: pokemon.offset + 8, length: 10, label: "Pokémon nickname")

        let key = pokemon.personality ^ pokemon.otID
        let order = substructOrders[Int(pokemon.personality % 24)]
        let decrypted = decryptSecureData(from: data, pokemonOffset: pokemon.offset, key: key)
        guard decrypted.count == Layout.encryptedDataLength else { throw ROMError.invalidPokemonSubstructures(pokemon.slot + 1) }

        var logical = (0..<4).map { logicalIndex -> [UInt8] in
            let physicalIndex = order[logicalIndex]
            let start = physicalIndex * 12
            return Array(decrypted[start..<(start + 12)])
        }
        guard logical.allSatisfy({ $0.count == 12 }) else { throw ROMError.invalidPokemonSubstructures(pokemon.slot + 1) }

        writeUInt16(pokemon.heldItem, at: 2, into: &logical[0])
        writeUInt32(Int(pokemon.experience), at: 4, into: &logical[0])
        logical[0][8] = UInt8(pokemon.ppBonuses)
        logical[0][9] = UInt8(pokemon.friendship)

        for index in 0..<4 {
            writeUInt16(pokemon.moves[index], at: index * 2, into: &logical[1])
            logical[1][8 + index] = UInt8(pokemon.pp[index])
        }

        logical[2][0] = UInt8(pokemon.evs.hp)
        logical[2][1] = UInt8(pokemon.evs.attack)
        logical[2][2] = UInt8(pokemon.evs.defense)
        logical[2][3] = UInt8(pokemon.evs.speed)
        logical[2][4] = UInt8(pokemon.evs.specialAttack)
        logical[2][5] = UInt8(pokemon.evs.specialDefense)

        var ivData = readUInt32(logical[3], at: 4)
        ivData = (ivData & 0xC000_0000)
            | UInt32(pokemon.ivs.hp & 0x1F)
            | (UInt32(pokemon.ivs.attack & 0x1F) << 5)
            | (UInt32(pokemon.ivs.defense & 0x1F) << 10)
            | (UInt32(pokemon.ivs.speed & 0x1F) << 15)
            | (UInt32(pokemon.ivs.specialAttack & 0x1F) << 20)
            | (UInt32(pokemon.ivs.specialDefense & 0x1F) << 25)
        writeUInt32(Int(ivData), at: 4, into: &logical[3])

        var physical = Array(repeating: UInt8(0), count: Layout.encryptedDataLength)
        for logicalIndex in 0..<4 {
            let physicalIndex = order[logicalIndex]
            let destination = physicalIndex * 12
            for byteIndex in 0..<12 {
                physical[destination + byteIndex] = logical[logicalIndex][byteIndex]
            }
        }

        let pokemonChecksum = checksum(physical)
        writeUInt16(Int(pokemonChecksum), at: pokemon.offset + 28, into: &data)
        let encrypted = encryptSecureData(physical, key: key)
        for index in 0..<Layout.encryptedDataLength {
            data[pokemon.offset + Layout.encryptedDataOffset + index] = encrypted[index]
        }

        let sectionChecksum = checksum(at: saveBlock1SectionOffset, length: Layout.sectorDataLength, data: data)
        writeUInt16(Int(sectionChecksum), at: saveBlock1SectionOffset + Layout.checksumOffset, into: &data)
    }

    static func writeBagItem(pocket: SaveBagPocketKind, slot: Int, itemID: Int, quantity: Int, into data: inout Data, saveBlock1SectionOffset: Int, securityKey: UInt32) throws {
        let layout = bagLayout(for: pocket)
        guard (0..<layout.capacity).contains(slot),
              (0...65535).contains(itemID),
              (0...999).contains(quantity),
              saveBlock1SectionOffset >= 0,
              saveBlock1SectionOffset + Layout.sectorSize <= data.count else {
            throw ROMError.invalidSaveEditValue
        }

        let itemOffset = saveBlock1SectionOffset + layout.relativeOffset + slot * 4
        guard itemOffset >= 0, itemOffset + 4 <= data.count else {
            throw ROMError.invalidSaveEditValue
        }

        let normalizedItemID = quantity == 0 ? 0 : itemID
        let normalizedQuantity = normalizedItemID == 0 ? 0 : quantity
        writeUInt16(normalizedItemID, at: itemOffset, into: &data)
        writeUInt16(normalizedQuantity ^ Int(UInt16(truncatingIfNeeded: securityKey)), at: itemOffset + 2, into: &data)

        let sectionChecksum = checksum(at: saveBlock1SectionOffset, length: Layout.sectorDataLength, data: data)
        writeUInt16(Int(sectionChecksum), at: saveBlock1SectionOffset + Layout.checksumOffset, into: &data)
    }

    static func writePokedexEntry(speciesID: Int, seen: Bool, caught: Bool, into data: inout Data, trainerSectionOffset: Int) throws {
        guard (1...386).contains(speciesID),
              trainerSectionOffset >= 0,
              trainerSectionOffset + Layout.sectorSize <= data.count else {
            throw ROMError.invalidSaveEditValue
        }
        let normalizedSeen = seen || caught
        let caughtOffset = trainerSectionOffset + Layout.pokedexOwnedOffset
        let seenOffset = trainerSectionOffset + Layout.pokedexSeenOffset
        guard caughtOffset + Layout.pokedexBitsLength <= data.count,
              seenOffset + Layout.pokedexBitsLength <= data.count else {
            throw ROMError.invalidSaveEditValue
        }
        setBit(offset: seenOffset, bitIndex: speciesID - 1, value: normalizedSeen, data: &data)
        setBit(offset: caughtOffset, bitIndex: speciesID - 1, value: caught, data: &data)
        let sectionChecksum = checksum(at: trainerSectionOffset, length: Layout.sectorDataLength, data: data)
        writeUInt16(Int(sectionChecksum), at: trainerSectionOffset + Layout.checksumOffset, into: &data)
    }

    static func writePokedexEntries(_ entries: [SavePokedexEntry], into data: inout Data, trainerSectionOffset: Int) throws {
        guard entries.allSatisfy({ (1...386).contains($0.id) }),
              trainerSectionOffset >= 0,
              trainerSectionOffset + Layout.sectorSize <= data.count else {
            throw ROMError.invalidSaveEditValue
        }
        let caughtOffset = trainerSectionOffset + Layout.pokedexOwnedOffset
        let seenOffset = trainerSectionOffset + Layout.pokedexSeenOffset
        guard caughtOffset + Layout.pokedexBitsLength <= data.count,
              seenOffset + Layout.pokedexBitsLength <= data.count else {
            throw ROMError.invalidSaveEditValue
        }
        for entry in entries {
            setBit(offset: seenOffset, bitIndex: entry.id - 1, value: entry.seen || entry.caught, data: &data)
            setBit(offset: caughtOffset, bitIndex: entry.id - 1, value: entry.caught, data: &data)
        }
        let sectionChecksum = checksum(at: trainerSectionOffset, length: Layout.sectorDataLength, data: data)
        writeUInt16(Int(sectionChecksum), at: trainerSectionOffset + Layout.checksumOffset, into: &data)
    }

    private static func bagLayout(for pocket: SaveBagPocketKind) -> (relativeOffset: Int, capacity: Int) {
        switch pocket {
        case .items: (0x560, 30)
        case .keyItems: (0x5D8, 30)
        case .balls: (0x650, 16)
        case .machines: (0x690, 64)
        case .berries: (0x790, 46)
        }
    }

    private static func validByteSpread(_ spread: PokemonStatSpread) -> Bool {
        [spread.hp, spread.attack, spread.defense, spread.specialAttack, spread.specialDefense, spread.speed].allSatisfy { (0...255).contains($0) }
    }

    private static func validIVSpread(_ spread: PokemonStatSpread) -> Bool {
        [spread.hp, spread.attack, spread.defense, spread.specialAttack, spread.specialDefense, spread.speed].allSatisfy { (0...31).contains($0) }
    }

    private static func decryptSecureData(from data: Data, pokemonOffset: Int, key: UInt32) -> [UInt8] {
        var result = Array(data[(pokemonOffset + Layout.encryptedDataOffset)..<(pokemonOffset + Layout.encryptedDataOffset + Layout.encryptedDataLength)])
        for offset in stride(from: 0, to: result.count, by: 4) {
            let value = readUInt32(result, at: offset) ^ key
            writeUInt32(Int(value), at: offset, into: &result)
        }
        return result
    }

    private static func encryptSecureData(_ bytes: [UInt8], key: UInt32) -> [UInt8] {
        var result = bytes
        for offset in stride(from: 0, to: result.count, by: 4) {
            let value = readUInt32(result, at: offset) ^ key
            writeUInt32(Int(value), at: offset, into: &result)
        }
        return result
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum = UInt32(0)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            sum &+= UInt32(readUInt16(bytes, at: index))
        }
        return UInt16(truncatingIfNeeded: sum)
    }

    private static func checksum(at offset: Int, length: Int, data: Data) -> UInt16 {
        var sum = UInt32(0)
        for index in stride(from: offset, to: offset + length, by: 4) {
            sum &+= UInt32(data[index])
                | (UInt32(data[index + 1]) << 8)
                | (UInt32(data[index + 2]) << 16)
                | (UInt32(data[index + 3]) << 24)
        }
        return UInt16(truncatingIfNeeded: (sum & 0xFFFF) + (sum >> 16))
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func writeUInt16(_ value: Int, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeUInt16(_ value: Int, at offset: Int, into bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeUInt32(_ value: Int, at offset: Int, into bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func setBit(offset: Int, bitIndex: Int, value: Bool, data: inout Data) {
        let byteOffset = offset + bitIndex / 8
        let mask = UInt8(1 << (bitIndex % 8))
        if value {
            data[byteOffset] |= mask
        } else {
            data[byteOffset] &= ~mask
        }
    }

    private static let substructOrders = [
        [0, 1, 2, 3], [0, 1, 3, 2], [0, 2, 1, 3], [0, 3, 1, 2],
        [0, 2, 3, 1], [0, 3, 2, 1], [1, 0, 2, 3], [1, 0, 3, 2],
        [2, 0, 1, 3], [3, 0, 1, 2], [2, 0, 3, 1], [3, 0, 2, 1],
        [1, 2, 0, 3], [1, 3, 0, 2], [2, 1, 0, 3], [3, 1, 0, 2],
        [2, 3, 0, 1], [3, 2, 0, 1], [1, 2, 3, 0], [1, 3, 2, 0],
        [2, 1, 3, 0], [3, 1, 2, 0], [2, 3, 1, 0], [3, 2, 1, 0]
    ]
}

struct TrainerTableParser {
    private enum Layout {
        // HexManiacAdvance src/HexManiac.Core/Models/Code/tableReference.txt, BPEE0 column.
        static let trainersPointerSource = 0x03587C
        static let trainersPointerSourceBPEI = 0x035880
        static let trainerClassesPointerSource = 0x0183B4
        static let itemsPointerSource = 0x0001C8
        static let itemCount = 377
        static let trainerCount = 855
        static let trainerLength = 40
        static let trainerNameLength = 12
        static let trainerClassCount = 66
        static let trainerClassNameLength = 13
        static let itemNameLength = 13
        static let itemLength = 44
        static let pokemonCount = 412
        static let moveCount = 355
    }

    let data: Data
    private var trainersPointerSource: Int {
        let gameCode = String(
            bytes: data[0xAC..<0xB0],
            encoding: .ascii
        ) ?? ""

        if gameCode == "BPEI" {
            return Layout.trainersPointerSourceBPEI
        }

        return Layout.trainersPointerSource
    }
    func parseTrainerClasses() throws -> [PokemonNamedValue] {
        let address = try resolveTableAddress(Layout.trainerClassesPointerSource, tableName: "data.trainers.classes.names")
        guard hasRange(address, length: Layout.trainerClassCount * Layout.trainerClassNameLength) else {
            throw ROMError.missingTable("data.trainers.classes.names")
        }
        return (0..<Layout.trainerClassCount).map { index in
            let name = PCSStringCodec.decode(data, start: address + index * Layout.trainerClassNameLength, length: Layout.trainerClassNameLength)
            return PokemonNamedValue(id: index, name: name.isEmpty ? "Class #\(index)" : name)
        }
    }

    func parseItems() throws -> [PokemonNamedValue] {
        let address = try resolveTableAddress(Layout.itemsPointerSource, tableName: "data.items.stats")
        let count = try itemCount()
        guard hasRange(address, length: count * Layout.itemLength) else {
            throw ROMError.missingTable("data.items.stats")
        }
        return (0..<count).map { index in
            let name = PCSStringCodec.decode(data, start: address + index * Layout.itemLength, length: Layout.itemNameLength)
            return PokemonNamedValue(id: index, name: name.isEmpty ? "Item #\(index)" : name)
        }
    }

    func parseTrainers() throws -> [TrainerData] {
        let trainersAddress = try resolveTableAddress(trainersPointerSource, tableName: "data.trainers.stats")
        guard hasRange(trainersAddress, length: Layout.trainerCount * Layout.trainerLength) else {
            throw ROMError.missingTable("data.trainers.stats")
        }

        return (0..<Layout.trainerCount).compactMap { index in
            let entryOffset = trainersAddress + index * Layout.trainerLength
            let name = PCSStringCodec.decode(data, start: entryOffset + 4, length: Layout.trainerNameLength)
            guard !name.isEmpty, !name.contains("\\!") else { return nil }
            guard let format = TrainerPartyFormat(rawValue: byte(entryOffset + 0)) else { return nil }
            let partyCount = readUInt32(at: entryOffset + 32)
            guard partyCount <= 6 else { return nil }
            guard let partyOffset = readPointer(at: entryOffset + 36), partyCount == 0 || hasRange(partyOffset, length: Int(partyCount) * format.memberLength) else {
                return nil
            }

            let party = parseParty(offset: partyOffset, count: Int(partyCount), format: format)
            return TrainerData(
                id: index,
                name: name,
                trainerClass: byte(entryOffset + 1),
                introMusicAndGender: byte(entryOffset + 2),
                sprite: byte(entryOffset + 3),
                items: [
                    readUInt16(at: entryOffset + 16),
                    readUInt16(at: entryOffset + 18),
                    readUInt16(at: entryOffset + 20),
                    readUInt16(at: entryOffset + 22)
                ],
                doubleBattle: readUInt32(at: entryOffset + 24) != 0,
                aiFlags: UInt32(readUInt32(at: entryOffset + 28)),
                partyFormat: format,
                partyCount: Int(partyCount),
                party: party,
                entryOffset: entryOffset,
                partyOffset: partyOffset
            )
        }
    }

    static func write(_ trainer: TrainerData, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = TrainerTableParser(data: data)
        let trainersAddress = try
            parser.resolveTableAddress(
                parser.trainersPointerSource,
                tableName: "data.trainers.stats"
            )
        let entryOffset = trainer.entryOffset
        guard entryOffset >= trainersAddress,
              entryOffset + Layout.trainerLength <= data.count,
              (entryOffset - trainersAddress).isMultiple(of: Layout.trainerLength) else {
            throw ROMError.unsupportedSemanticTables
        }

        let partyCount = trainer.party.count
        guard (1...6).contains(partyCount), trainer.partyCount == partyCount else { throw ROMError.partyResizeUnsupported }
        try validateByte(trainer.trainerClass, "Trainer class")
        try validateByte(trainer.introMusicAndGender, "Intro music/gender")
        try validateByte(trainer.sprite, "Trainer sprite")
        try validateByte(trainer.partyFormat.rawValue, "Party format")
        let itemCount = try parser.itemCount()
        for item in trainer.items { try validateIndex(item, "Trainer item", count: itemCount) }

        let currentFormat = TrainerPartyFormat(rawValue: Int(data[entryOffset])) ?? trainer.partyFormat
        let currentPartyCount = parser.readUInt32(at: entryOffset + 32)
        guard currentPartyCount <= 6,
              let currentPartyPointer = parser.readPointer(at: entryOffset + 36) else {
            throw ROMError.unsupportedSemanticTables
        }
        let currentPayloadLength = Int(currentPartyCount) * currentFormat.memberLength
        let desiredPayloadLength = partyCount * trainer.partyFormat.memberLength
        guard parser.hasRange(currentPartyPointer, length: max(0, currentPayloadLength)) else {
            throw ROMError.unsupportedSemanticTables
        }
        guard Int(currentPartyCount) == partyCount else {
            throw ROMError.partyResizeUnsupported
        }

        let targetPartyOffset: Int
        if trainer.partyFormat == currentFormat {
            targetPartyOffset = currentPartyPointer
        } else {
            let trainersTable = trainersAddress..<(trainersAddress + Layout.trainerCount * Layout.trainerLength)
            guard let freeSpace = Self.findFreeSpace(
                in: data,
                length: desiredPayloadLength,
                alignment: 4,
                avoiding: [trainersTable, currentPartyPointer..<(currentPartyPointer + currentPayloadLength)]
            ), freeSpace + desiredPayloadLength <= data.count else {
                throw ROMError.partyResizeUnsupported
            }
            targetPartyOffset = freeSpace
        }

        data[entryOffset + 0] = UInt8(trainer.partyFormat.rawValue)
        data[entryOffset + 1] = UInt8(trainer.trainerClass)
        data[entryOffset + 2] = UInt8(trainer.introMusicAndGender)
        data[entryOffset + 3] = UInt8(trainer.sprite)
        try PCSStringCodec.write(trainer.name, into: &data, start: entryOffset + 4, length: Layout.trainerNameLength, label: "Trainer name")
        writeUInt16(trainer.items[safe: 0] ?? 0, at: entryOffset + 16, into: &data)
        writeUInt16(trainer.items[safe: 1] ?? 0, at: entryOffset + 18, into: &data)
        writeUInt16(trainer.items[safe: 2] ?? 0, at: entryOffset + 20, into: &data)
        writeUInt16(trainer.items[safe: 3] ?? 0, at: entryOffset + 22, into: &data)
        writeUInt32(trainer.doubleBattle ? 1 : 0, at: entryOffset + 24, into: &data)
        writeUInt32(Int(trainer.aiFlags), at: entryOffset + 28, into: &data)
        writeUInt32(partyCount, at: entryOffset + 32, into: &data)
        writeUInt32(0x0800_0000 + targetPartyOffset, at: entryOffset + 36, into: &data)

        guard targetPartyOffset + desiredPayloadLength <= data.count else {
            throw ROMError.unsupportedSemanticTables
        }

        for (index, member) in trainer.party.enumerated() {
            let memberOffset = targetPartyOffset + index * trainer.partyFormat.memberLength
            try write(member, format: trainer.partyFormat, itemCount: itemCount, at: memberOffset, into: &data)
        }
    }

    private func parseParty(offset: Int, count: Int, format: TrainerPartyFormat) -> [TrainerPartyMember] {
        (0..<count).map { index in
            let memberOffset = offset + index * format.memberLength
            let heldItem = format.includesItems ? readUInt16(at: memberOffset + 6) : 0
            let movesOffset = memberOffset + (format.includesItems ? 8 : 6)
            let moves = format.includesMoves
                ? (0..<4).map { readUInt16(at: movesOffset + $0 * 2) }
                : [0, 0, 0, 0]
            return TrainerPartyMember(
                id: index,
                ivSpread: readUInt16(at: memberOffset + 0),
                level: readUInt16(at: memberOffset + 2),
                species: readUInt16(at: memberOffset + 4),
                heldItem: heldItem,
                moves: moves,
                offset: memberOffset
            )
        }
    }

    private static func write(_ member: TrainerPartyMember, format: TrainerPartyFormat, itemCount: Int, at memberOffset: Int, into data: inout Data) throws {
        try validateUInt16(member.ivSpread, "IV spread")
        guard (1...100).contains(member.level) else { throw ROMError.valueOutOfRange("Level") }
        try validateIndex(member.species, "Species", count: Layout.pokemonCount)
        guard memberOffset >= 0, memberOffset + format.memberLength <= data.count else { throw ROMError.unsupportedSemanticTables }
        writeUInt16(member.ivSpread, at: memberOffset + 0, into: &data)
        writeUInt16(member.level, at: memberOffset + 2, into: &data)
        writeUInt16(member.species, at: memberOffset + 4, into: &data)

        if format.includesItems {
            try validateIndex(member.heldItem, "Held item", count: itemCount)
            writeUInt16(member.heldItem, at: memberOffset + 6, into: &data)
        }
        if format.includesMoves {
            let movesOffset = memberOffset + (format.includesItems ? 8 : 6)
            guard member.moves.count == 4 else { throw ROMError.unsupportedSemanticTables }
            for index in 0..<4 {
                try validateIndex(member.moves[index], "Move", count: Layout.moveCount)
                writeUInt16(member.moves[index], at: movesOffset + index * 2, into: &data)
            }
        }
    }

    private static func findFreeSpace(in data: Data, length: Int, alignment: Int, avoiding ranges: [Range<Int>]) -> Int? {
        guard length > 0, length <= data.count else { return nil }
        var runEnd = data.count
        var offset = data.count - 1
        while offset >= 0 {
            let value = data[offset]
            if value == 0xFF || value == 0x00 {
                let runStart = offset
                let runLength = runEnd - runStart
                if runLength >= length {
                    var candidate = runEnd - length
                    if alignment > 1 {
                        candidate -= candidate % alignment
                    }
                    if candidate >= runStart,
                       candidate + length <= runEnd,
                       !ranges.contains(where: { candidate < $0.upperBound && candidate + length > $0.lowerBound }) {
                        return candidate
                    }
                }
            } else {
                runEnd = offset
            }
            offset -= 1
        }
        return nil
    }

    private func itemCount() throws -> Int {
        Layout.itemCount
    }

    private func resolveTableAddress(_ source: Int, tableName: String) throws -> Int {
        if let pointer = readPointer(at: source), hasRange(pointer, length: 1) {
            return pointer
        }
        guard hasRange(source, length: 1) else { throw ROMError.missingTable(tableName) }
        return source
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        return Int(raw - 0x0800_0000)
    }

    private func byte(_ offset: Int) -> Int {
        Int(data[offset])
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func readUInt32(at offset: Int) -> Int {
        Int(data[offset])
            | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16)
            | (Int(data[offset + 3]) << 24)
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private static func writeUInt16(_ value: Int, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeUInt32(_ value: Int, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func validateByte(_ value: Int, _ label: String) throws {
        guard (0...255).contains(value) else { throw ROMError.valueOutOfRange(label) }
    }

    private static func validateUInt16(_ value: Int, _ label: String) throws {
        guard (0...65535).contains(value) else { throw ROMError.uint16ValueOutOfRange(label) }
    }

    private static func validateIndex(_ value: Int, _ label: String, count: Int) throws {
        guard (0..<count).contains(value) else { throw ROMError.indexOutOfRange(label) }
    }
}

struct ItemTableParser {
    private enum Layout {
        // HexManiacAdvance tableReference.txt BPEE0: data.items.stats.
        static let itemsPointerSource = 0x0001C8
        static let itemCount = 377
        static let itemLength = 44
        static let itemNameLength = 13
    }

    let data: Data

    func parseItems() throws -> [ItemData] {
        let address = try resolveTableAddress(Layout.itemsPointerSource, tableName: "data.items.stats")
        let count = try itemCount()
        guard hasRange(address, length: count * Layout.itemLength) else {
            throw ROMError.missingTable("data.items.stats")
        }

        return (0..<count).map { index in
            let offset = address + index * Layout.itemLength
            let descriptionOffset = readPointer(at: offset + 20)
            let description = descriptionOffset.map {
                PCSStringCodec.decode(data, start: $0, length: 384)
            } ?? ""
            return ItemData(
                id: index,
                name: PCSStringCodec.decode(data, start: offset, length: Layout.itemNameLength),
                price: readUInt16(at: offset + 16),
                holdEffect: byte(offset + 18),
                parameter: byte(offset + 19),
                description: description,
                keyItemValue: byte(offset + 24),
                bagKeyItem: byte(offset + 25),
                pocket: byte(offset + 26),
                type: byte(offset + 27),
                descriptionOffset: descriptionOffset,
                fieldEffectPointer: readRawUInt32(at: offset + 28),
                battleUsage: readRawUInt32(at: offset + 32),
                battleEffectPointer: readRawUInt32(at: offset + 36),
                battleExtra: readRawUInt32(at: offset + 40),
                statsOffset: offset
            )
        }
    }

    static func write(_ item: ItemData, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = ItemTableParser(data: data)
        let address = try parser.resolveTableAddress(Layout.itemsPointerSource, tableName: "data.items.stats")
        let count = try parser.itemCount()
        let offset = item.statsOffset
        guard offset >= address,
              offset + Layout.itemLength <= data.count,
              (offset - address).isMultiple(of: Layout.itemLength),
              (0..<count).contains(item.id) else {
            throw ROMError.unsupportedSemanticTables
        }

        try validateUInt16(item.price, "Item price")
        try validateByte(item.holdEffect, "Hold effect")
        try validateByte(item.parameter, "Hold effect parameter")
        try validateByte(item.keyItemValue, "Key item value")
        try validateByte(item.bagKeyItem, "Bag key item")
        try validateByte(item.pocket, "Pocket")
        try validateByte(item.type, "Item type")

        writeUInt16(item.price, at: offset + 16, into: &data)
        data[offset + 18] = UInt8(item.holdEffect)
        data[offset + 19] = UInt8(item.parameter)
        data[offset + 24] = UInt8(item.keyItemValue)
        data[offset + 25] = UInt8(item.bagKeyItem)
        data[offset + 26] = UInt8(item.pocket)
        data[offset + 27] = UInt8(item.type)
    }

    private func itemCount() throws -> Int {
        Layout.itemCount
    }

    private func resolveTableAddress(_ source: Int, tableName: String) throws -> Int {
        if let pointer = readPointer(at: source), hasRange(pointer, length: 1) {
            return pointer
        }
        guard hasRange(source, length: 1) else { throw ROMError.missingTable(tableName) }
        return source
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = readRawUInt32(at: offset)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let pointer = Int(raw - 0x0800_0000)
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func byte(_ offset: Int) -> Int {
        Int(data[offset])
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

    private static func writeUInt16(_ value: Int, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func validateByte(_ value: Int, _ label: String) throws {
        guard (0...255).contains(value) else { throw ROMError.valueOutOfRange(label) }
    }

    private static func validateUInt16(_ value: Int, _ label: String) throws {
        guard (0...65535).contains(value) else { throw ROMError.uint16ValueOutOfRange(label) }
    }
}

struct WildEncounterTableParser {
    private enum Layout {
        static let bpeeWildTableAddress = 0x552D48
        static let bpeiWildTableAddress = 0x54FA8C
        static let headerLength = 20
        static let grassSlots = 12
        static let waterSlots = 5
        static let fishingSlots = 10
        static let slotLength = 4
        static let pokemonCount = 412
    }

    private struct SlotSpec {
        let kind: WildEncounterKind
        let start: Int
        let count: Int
        let odds: [Int]
    }

    let data: Data

    private var wildTableAddress: Int {
        gameCode == "BPEI" ? Layout.bpeiWildTableAddress : Layout.bpeeWildTableAddress
    }

    func parseAreas() throws -> [WildEncounterArea] {
        guard hasRange(wildTableAddress, length: Layout.headerLength) else {
            throw ROMError.missingTable("data.pokemon.wild")
        }

        var areas: [WildEncounterArea] = []
        var offset = wildTableAddress
        var index = 0
        while hasRange(offset, length: Layout.headerLength) {
            let mapGroup = byte(offset + 0)
            let mapNumber = byte(offset + 1)
            if mapGroup == 0xFF && mapNumber == 0xFF { break }

            var groups: [WildEncounterGroup] = []
            groups += parseEncounterInfo(kind: .grass, pointerOffset: offset + 4, slotCount: Layout.grassSlots, odds: Self.grassOdds)
            groups += parseEncounterInfo(kind: .surf, pointerOffset: offset + 8, slotCount: Layout.waterSlots, odds: Self.waterOdds)
            groups += parseEncounterInfo(kind: .rockSmash, pointerOffset: offset + 12, slotCount: Layout.waterSlots, odds: Self.waterOdds)
            groups += parseFishingInfo(pointerOffset: offset + 16)

            if !groups.isEmpty {
                areas.append(WildEncounterArea(id: index, mapGroup: mapGroup, mapNumber: mapNumber, groups: groups, tableOffset: offset))
            }
            offset += Layout.headerLength
            index += 1
        }

        return areas
    }

    static func write(_ area: WildEncounterArea, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = WildEncounterTableParser(data: data)
        guard parser.hasRange(area.tableOffset, length: Layout.headerLength) else {
            throw ROMError.unsupportedSemanticTables
        }

        var touchedRateOffsets = Set<Int>()
        for group in area.groups {
            guard parser.hasRange(group.rateOffset, length: 1) else { throw ROMError.unsupportedSemanticTables }
            try validateByte(group.encounterRate, "Encounter rate")
            if !touchedRateOffsets.contains(group.rateOffset) {
                data[group.rateOffset] = UInt8(group.encounterRate)
                touchedRateOffsets.insert(group.rateOffset)
            }

            for slot in group.slots {
                guard parser.hasRange(slot.offset, length: Layout.slotLength) else { throw ROMError.unsupportedSemanticTables }
                try validateIndex(slot.species, "Wild species", count: Layout.pokemonCount)
                guard (1...100).contains(slot.minLevel), (1...100).contains(slot.maxLevel), slot.minLevel <= slot.maxLevel else {
                    throw ROMError.valueOutOfRange("Wild level")
                }
                data[slot.offset + 0] = UInt8(slot.minLevel)
                data[slot.offset + 1] = UInt8(slot.maxLevel)
                writeUInt16(slot.species, at: slot.offset + 2, into: &data)
            }
        }
    }

    private func parseEncounterInfo(kind: WildEncounterKind, pointerOffset: Int, slotCount: Int, odds: [Int]) -> [WildEncounterGroup] {
        guard let infoOffset = readPointer(at: pointerOffset),
              hasRange(infoOffset, length: 8),
              let tableOffset = readPointer(at: infoOffset + 4),
              hasRange(tableOffset, length: slotCount * Layout.slotLength) else { return [] }
        return [
            WildEncounterGroup(
                id: "\(kind.rawValue)-\(infoOffset)",
                kind: kind,
                encounterRate: byte(infoOffset),
                slots: parseSlots(tableOffset: tableOffset, slotCount: slotCount, odds: odds, idBase: 0),
                rateOffset: infoOffset,
                tableOffset: tableOffset
            )
        ]
    }

    private func parseFishingInfo(pointerOffset: Int) -> [WildEncounterGroup] {
        guard let infoOffset = readPointer(at: pointerOffset),
              hasRange(infoOffset, length: 8),
              let tableOffset = readPointer(at: infoOffset + 4),
              hasRange(tableOffset, length: Layout.fishingSlots * Layout.slotLength) else { return [] }
        let specs = [
            SlotSpec(kind: .oldRod, start: 0, count: 2, odds: [70, 30]),
            SlotSpec(kind: .goodRod, start: 2, count: 3, odds: [60, 20, 20]),
            SlotSpec(kind: .superRod, start: 5, count: 5, odds: [40, 40, 15, 4, 1])
        ]
        return specs.map { spec in
            let startOffset = tableOffset + spec.start * Layout.slotLength
            return WildEncounterGroup(
                id: "\(spec.kind.rawValue)-\(infoOffset)",
                kind: spec.kind,
                encounterRate: byte(infoOffset),
                slots: parseSlots(tableOffset: startOffset, slotCount: spec.count, odds: spec.odds, idBase: spec.start),
                rateOffset: infoOffset,
                tableOffset: startOffset
            )
        }
    }

    private func parseSlots(tableOffset: Int, slotCount: Int, odds: [Int], idBase: Int) -> [WildEncounterSlot] {
        (0..<slotCount).map { index in
            let offset = tableOffset + index * Layout.slotLength
            return WildEncounterSlot(
                id: idBase + index,
                species: readUInt16(at: offset + 2),
                minLevel: byte(offset + 0),
                maxLevel: byte(offset + 1),
                chance: odds[safe: index] ?? 0,
                offset: offset
            )
        }
    }

    private static let grassOdds = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]
    private static let waterOdds = [60, 30, 5, 4, 1]

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let pointer = Int(raw - 0x0800_0000)
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func byte(_ offset: Int) -> Int {
        Int(data[offset])
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private var gameCode: String {
        guard data.count >= 0xB0 else { return "" }
        return String(bytes: data[0xAC..<0xB0], encoding: .ascii) ?? ""
    }

    private static func writeUInt16(_ value: Int, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func validateByte(_ value: Int, _ label: String) throws {
        guard (0...255).contains(value) else { throw ROMError.valueOutOfRange(label) }
    }

    private static func validateIndex(_ value: Int, _ label: String, count: Int) throws {
        guard (0..<count).contains(value) else { throw ROMError.indexOutOfRange(label) }
    }
}

#if DEBUG
enum DevelopmentROMFixture {
    static func testROMURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["HEXMANIA_TEST_ROM"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for _ in 0..<8 {
            let candidate = directory
                .appendingPathComponent("LocalTestROMs")
                .appendingPathComponent("Emerald_USA_BPEE.gba")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return nil
    }

    static func loadTestROM() throws -> (url: URL, data: Data) {
        guard let url = testROMURL() else {
            throw ROMError.invalidFile
        }
        return (url, try Data(contentsOf: url, options: .mappedIfSafe))
    }
}

enum MapDevelopmentQASuite {
    static func report() -> String {
        do {
            let fixture = try DevelopmentROMFixture.loadTestROM()
            let beforeAttributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
            let results = ROMIntegrityTestSuite.run(on: fixture.data).filter { result in
                result.name.hasPrefix("Map")
                    || result.name == "WarpWriter"
                    || result.name == "ObjectEventWriter"
                    || result.name == "SaveReload"
            }
            let copyResult = try runMapPaintReloadCopyTest(on: fixture.data)
            let afterData = try Data(contentsOf: fixture.url, options: .mappedIfSafe)
            let afterAttributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
            let fixtureUnchanged = afterData == fixture.data
                && (beforeAttributes[.size] as? NSNumber) == (afterAttributes[.size] as? NSNumber)
            return ([
                "MapDevelopmentQA",
                "Fixture: \(fixture.url.path)",
                "Fixture unchanged: \(fixtureUnchanged ? "PASS" : "FAIL")"
            ] + results.map(\.reportText) + [copyResult.reportText]).joined(separator: "\n\n")
        } catch {
            return "MapDevelopmentQA\nFAIL\n\(error.localizedDescription)"
        }
    }

    private static func runMapPaintReloadCopyTest(on data: Data) throws -> ROMIntegrityTestResult {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("HexManiaMac_MapPaint_\(UUID().uuidString).gba")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let maps = try MapTableParser(data: data).parseMaps()
        guard let map = maps.first(where: { $0.blocks.contains { $0.metatileID < 0x03FF } }),
              var block = map.blocks.first(where: { $0.metatileID < 0x03FF }) else {
            return ROMIntegrityTestResult(name: "MapPaintReloadCopy", passed: false, details: ["No editable map block found"])
        }
        let original = block
        block.metatileID += 1

        var modified = data
        try MapTableParser.writeBlock(block, into: &modified)
        try modified.write(to: tempURL, options: .atomic)
        let reloadedData = try Data(contentsOf: tempURL)
        let reloadedMaps = try MapTableParser(data: reloadedData).parseMaps()
        guard let reloaded = reloadedMaps.first(where: { $0.id == map.id })?.blocks.first(where: { $0.id == block.id }) else {
            return ROMIntegrityTestResult(name: "MapPaintReloadCopy", passed: false, details: ["Reloaded block not found"])
        }
        let passed = reloaded.metatileID == block.metatileID
            && reloaded.collision == original.collision
            && reloaded.elevation == original.elevation
            && reloadedData.count == data.count
        let diff = ROMDiffReport.compare(original: data, modified: reloadedData)
        return ROMIntegrityTestResult(
            name: "MapPaintReloadCopy",
            passed: passed,
            details: [
                "\(map.name) \(map.id) block \(block.x),\(block.y)",
                "Metatile \(original.metatileID) -> \(block.metatileID)",
                "Collision/elevation preserved: \(original.collision)/\(original.elevation)",
                diff.summary(),
                "Temp file removed"
            ]
        )
    }
}
#endif

struct MapTableParser {
    private enum Layout {
        // HexManiacAdvance tableReference.txt BPEE0 column: data.maps.banks.
        static let bpeeMapBanksAddress = 0x084AA4
        static let bpeiMapBanksAddress = 0x084AB8
        static let bpeeMapLayoutsAddress = 0x0849CC
        static let bpeeMapNamesAddress = 0x5A0B10
        static let bpeiMapNamesAddress = 0x59D4D4
        static let mapBankCount = 34
        static let mapNameCount = 256
        static let mapHeaderLength = 28
        static let mapLayoutLength = 24
        static let mapObjectLength = 24
        static let mapWarpLength = 8
        static let mapCoordinateLength = 16
        static let mapBackgroundLength = 12
        static let mapConnectionHeaderLength = 8
        static let mapConnectionLength = 12
        static let mapLayoutCount = 441
        static let maxMapCountPerBank = 127
    }

    private struct ParsedLayout {
        let offset: Int
        let source: String
        let width: Int
        let height: Int
        let rawBorderPointer: UInt32
        let rawBlockmapPointer: UInt32
        let rawPrimaryTilesetPointer: UInt32
        let rawSecondaryTilesetPointer: UInt32
        let borderOffset: Int
        let blockmapOffset: Int
        let primaryTilesetOffset: Int
        let secondaryTilesetOffset: Int
    }

    let data: Data
    private var mapNamesAddress: Int {
        gameCode == "BPEI" ? Layout.bpeiMapNamesAddress : Layout.bpeeMapNamesAddress
    }

    func parseMaps() throws -> [MapData] {
        try EmeraldROM.validateSupported(data)
        let banksAddress = try resolveMapBanksAddress()
        guard hasRange(banksAddress, length: Layout.mapBankCount * 4) else {
            logFailure(stage: "mapBanksAnchor", offset: banksAddress, rawValue: nil, reason: "anchor outside ROM")
            throw ROMError.missingTable("data.maps.banks")
        }
        let firstRawPointer = readRawUInt32(at: banksAddress)
        let firstConvertedPointer = gbaPointerToROMOffset(firstRawPointer)
        logHeader(banksAddress: banksAddress, firstRawPointer: firstRawPointer, firstConvertedPointer: firstConvertedPointer)

        let bankPointers = (0..<Layout.mapBankCount).map { group -> Int? in
            let pointerOffset = banksAddress + group * 4
            let raw = readRawUInt32(at: pointerOffset)
            guard let pointer = gbaPointerToROMOffset(raw), hasRange(pointer, length: 4) else {
                logFailure(stage: "mapGroupPointer", offset: pointerOffset, rawValue: raw, reason: "pointer outside ROM or not a GBA ROM pointer")
                return nil
            }
            return pointer
        }
        let mapSectionNames = parseMapSectionNames()
        var maps: [MapData] = []
        var invalidMapCount = 0
        for group in 0..<Layout.mapBankCount {
            guard let bankOffset = bankPointers[group] else { continue }
            let count = mapCount(group: group, bankPointers: bankPointers, banksAddress: banksAddress)
            for mapID in 0..<count {
                let pointerOffset = bankOffset + mapID * 4
                let rawHeaderPointer = readRawUInt32(at: pointerOffset)
                guard let headerOffset = gbaPointerToROMOffset(rawHeaderPointer), hasRange(headerOffset, length: Layout.mapHeaderLength) else {
                    invalidMapCount += 1
                    logFailure(stage: "mapHeaderPointer", offset: pointerOffset, rawValue: rawHeaderPointer, reason: "header pointer outside ROM")
                    continue
                }
                if let map = parseMap(group: group, mapID: mapID, headerOffset: headerOffset, mapSectionNames: mapSectionNames) {
                    maps.append(map)
                } else {
                    invalidMapCount += 1
                }
            }
        }
        if maps.isEmpty {
            throw MapParsingError(report: diagnosticReport(extraFailure: "No valid maps were parsed."))
        }
        return maps
    }

    static func writeBlock(_ block: MapBlockCell, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = MapTableParser(data: data)
        guard parser.hasRange(block.offset, length: 2) else { throw ROMError.unsupportedSemanticTables }
        try validateMetatile(block.metatileID)
        guard (0...3).contains(block.collision) else { throw ROMError.valueOutOfRange("Collision") }
        guard (0...15).contains(block.elevation) else { throw ROMError.valueOutOfRange("Elevation") }
        writeUInt16(block.rawValue, at: block.offset, into: &data)
    }

    static func writeObject(_ object: MapObjectEvent, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = MapTableParser(data: data)
        guard parser.hasRange(object.offset, length: Layout.mapObjectLength) else { throw ROMError.unsupportedSemanticTables }
        try validateSigned16(object.x, "Object X")
        try validateSigned16(object.y, "Object Y")
        try validateByte(object.elevation, "Object elevation")
        try validateByte(object.graphicsID, "Object graphics")
        try validateByte(object.movementType, "Object movement")
        guard (0...15).contains(object.movementRangeX), (0...15).contains(object.movementRangeY) else {
            throw ROMError.valueOutOfRange("Object movement range")
        }
        data[object.offset + 1] = UInt8(object.graphicsID)
        data[object.offset + 4] = UInt8(object.x & 0xFF)
        data[object.offset + 5] = UInt8((object.x >> 8) & 0xFF)
        data[object.offset + 6] = UInt8(object.y & 0xFF)
        data[object.offset + 7] = UInt8((object.y >> 8) & 0xFF)
        data[object.offset + 8] = UInt8(object.elevation)
        data[object.offset + 9] = UInt8(object.movementType)
        data[object.offset + 10] = UInt8((object.movementRangeY << 4) | object.movementRangeX)
    }

    static func writeWarp(_ warp: MapWarpEvent, into data: inout Data) throws {
        try EmeraldROM.validateSupported(data)
        let parser = MapTableParser(data: data)
        guard parser.hasRange(warp.offset, length: Layout.mapWarpLength) else { throw ROMError.unsupportedSemanticTables }
        try validateSigned16(warp.x, "Warp X")
        try validateSigned16(warp.y, "Warp Y")
        try validateByte(warp.elevation, "Warp elevation")
        try validateByte(warp.warpID, "Destination warp")
        try validateByte(warp.destinationMap, "Destination map")
        try validateByte(warp.destinationGroup, "Destination group")
        data[warp.offset + 0] = UInt8(warp.x & 0xFF)
        data[warp.offset + 1] = UInt8((warp.x >> 8) & 0xFF)
        data[warp.offset + 2] = UInt8(warp.y & 0xFF)
        data[warp.offset + 3] = UInt8((warp.y >> 8) & 0xFF)
        data[warp.offset + 4] = UInt8(warp.elevation)
        data[warp.offset + 5] = UInt8(warp.warpID)
        data[warp.offset + 6] = UInt8(warp.destinationMap)
        data[warp.offset + 7] = UInt8(warp.destinationGroup)
    }

    func diagnosticReport(extraFailure: String? = nil) -> String {
        var lines: [String] = []
        func add(_ text: String) { lines.append(text) }
        func addHex(_ label: String, _ value: Int?) {
            add("\(label): \(value.map { String(format: "0x%08X", $0) } ?? "nil")")
        }
        func addRaw(_ label: String, _ value: UInt32?) {
            add("\(label): \(value.map { String(format: "0x%08X", $0) } ?? "nil")")
        }
        func fail(stage: String, offset: Int?, raw: UInt32?, reason: String) -> String {
            add("")
            add("[MapDebug][FAIL]")
            add("stage: \(stage)")
            addHex("offset", offset)
            addRaw("raw value", raw)
            add("reason: \(reason)")
            return lines.joined(separator: "\n")
        }

        add("Map parser diagnostic")
        add("ROM code: \(gameCode)")
        add("ROM size: \(data.count)")

        guard EmeraldROM.supportedGameCodes.contains(gameCode) else {
            return fail(stage: "ROMCode", offset: nil, raw: nil, reason: "expected BPEE or BPEI"
            )
        }

        let source = mapBanksPointerSource
        addHex("map banks source", source)
        add("source reference: \(gameCode == "BPEI" ? "verified BPEI map banks source" : "HexManiacAdvance tableReference.txt BPEE0")")
        guard hasRange(source, length: 32) else {
            return fail(stage: "MapBanksSource", offset: source, raw: nil, reason: "source outside ROM")
        }

        let resolvedSource = readPointer(at: source)
        addHex("map banks resolved offset", resolvedSource)
        add("first 32 bytes at source: \(hexBytes(start: source, count: 32))")
        if let resolvedSource {
            add("first 32 bytes at resolved table: \(hexBytes(start: resolvedSource, count: 32))")
        }

        let groupIndex = 0
        let groupPointerOffset = (resolvedSource ?? source) + groupIndex * 4
        let groupPointerRaw = readRawUInt32(at: groupPointerOffset)
        let groupPointerConverted = gbaPointerToROMOffset(groupPointerRaw)
        add("group index corrente: \(groupIndex)")
        addHex("group pointer offset", groupPointerOffset)
        addRaw("group pointer raw", groupPointerRaw)
        addHex("group pointer converted", groupPointerConverted)
        guard let groupOffset = groupPointerConverted, hasRange(groupOffset, length: 4) else {
            return fail(stage: "MapGroup[0]", offset: groupPointerOffset, raw: groupPointerRaw, reason: "group pointer is not a valid GBA ROM pointer")
        }

        let mapIndex = 0
        let mapHeaderPointerOffset = groupOffset + mapIndex * 4
        let mapHeaderPointerRaw = readRawUInt32(at: mapHeaderPointerOffset)
        let mapHeaderOffset = gbaPointerToROMOffset(mapHeaderPointerRaw)
        add("map index corrente: \(mapIndex)")
        addHex("map header pointer offset", mapHeaderPointerOffset)
        addRaw("map header pointer raw", mapHeaderPointerRaw)
        addHex("map header offset", mapHeaderOffset)
        guard let headerOffset = mapHeaderOffset, hasRange(headerOffset, length: Layout.mapHeaderLength) else {
            return fail(stage: "MapHeader[0.0]", offset: mapHeaderPointerOffset, raw: mapHeaderPointerRaw, reason: "map header pointer is not a valid GBA ROM pointer")
        }

        let layoutPointerRaw = readRawUInt32(at: headerOffset + 0)
        let eventsPointerRaw = readRawUInt32(at: headerOffset + 4)
        let scriptsPointerRaw = readRawUInt32(at: headerOffset + 8)
        let connectionsPointerRaw = readRawUInt32(at: headerOffset + 12)
        let layoutOffset = gbaPointerToROMOffset(layoutPointerRaw)
        let eventsOffset = gbaPointerToROMOffset(eventsPointerRaw)
        let scriptsOffset = gbaPointerToROMOffset(scriptsPointerRaw)
        let connectionsOffset = gbaPointerToROMOffset(connectionsPointerRaw)
        let mapLayoutID = readUInt16(at: headerOffset + 18)
        addRaw("layout pointer raw", layoutPointerRaw)
        addHex("layout offset", layoutOffset)
        addRaw("events pointer raw", eventsPointerRaw)
        addHex("events pointer", eventsOffset)
        addRaw("scripts pointer raw", scriptsPointerRaw)
        addHex("scripts pointer", scriptsOffset)
        addRaw("connections pointer raw", connectionsPointerRaw)
        addHex("connections pointer", connectionsOffset)
        add("mapLayoutId: \(mapLayoutID)")
        guard let layoutOffset, hasRange(layoutOffset, length: Layout.mapLayoutLength) else {
            return fail(stage: "LayoutPointer[0.0]", offset: headerOffset, raw: layoutPointerRaw, reason: "layout pointer is not a valid GBA ROM pointer")
        }

        add("raw 24 bytes at header layout target: \(hexBytes(start: layoutOffset, count: Layout.mapLayoutLength))")
        add(layoutDump(offset: layoutOffset))

        guard let layout = resolveMapLayout(rawLayoutPointer: layoutPointerRaw, mapLayoutID: mapLayoutID, group: 0, mapID: 0) else {
            return fail(stage: "LayoutResolve[0.0]", offset: layoutOffset, raw: layoutPointerRaw, reason: "no valid Emerald MapLayout via direct, indirect, or mapLayoutId lookup")
        }

        add("resolved layout source: \(layout.source)")
        addHex("resolved layout offset", layout.offset)
        add("width: \(layout.width)")
        add("height: \(layout.height)")
        addRaw("border pointer raw", layout.rawBorderPointer)
        addHex("border pointer", layout.borderOffset)
        addRaw("blockdata pointer raw", layout.rawBlockmapPointer)
        addHex("blockdata pointer", layout.blockmapOffset)
        addRaw("primary tileset pointer raw", layout.rawPrimaryTilesetPointer)
        addHex("primary tileset pointer", layout.primaryTilesetOffset)
        addRaw("secondary tileset pointer raw", layout.rawSecondaryTilesetPointer)
        addHex("secondary tileset pointer", layout.secondaryTilesetOffset)

        if !hasRange(layout.blockmapOffset, length: layout.width * layout.height * 2) {
            return fail(stage: "BlockmapBounds[0.0]", offset: layout.blockmapOffset, raw: layout.rawBlockmapPointer, reason: "blockmap does not contain width*height cells")
        }

        add("")
        if let extraFailure {
            add("[MapDebug][FAIL]")
            add("stage: ParseMaps")
            add("reason: \(extraFailure)")
        } else {
            add("[MapDebug] Group 0 valid")
            add("[MapDebug] Map 0 valid")
            add("[MapDebug] Header valid")
            add("[MapDebug] Layout valid")
            add("[MapDebug] Width/height valid")
        }
        return lines.joined(separator: "\n")
    }

    private func parseMap(group: Int, mapID: Int, headerOffset: Int, mapSectionNames: [Int: String]) -> MapData? {
        guard hasRange(headerOffset, length: Layout.mapHeaderLength) else {
            logFailure(stage: "mapHeader", offset: headerOffset, rawValue: nil, reason: "header outside ROM")
            return nil
        }

        let rawLayoutPointer = readRawUInt32(at: headerOffset + 0)
        let rawEventsPointer = readRawUInt32(at: headerOffset + 4)
        let rawConnectionsPointer = readRawUInt32(at: headerOffset + 12)
        let mapLayoutID = readUInt16(at: headerOffset + 18)
        guard let layout = resolveMapLayout(rawLayoutPointer: rawLayoutPointer, mapLayoutID: mapLayoutID, group: group, mapID: mapID) else {
            logFailure(stage: "layoutResolve", offset: headerOffset, rawValue: rawLayoutPointer, reason: "no valid Emerald MapLayout via direct, indirect, or mapLayoutId lookup")
            return nil
        }

        let eventsOffset = gbaPointerToROMOffset(rawEventsPointer)
        let connectionsOffset = gbaPointerToROMOffset(rawConnectionsPointer)
        let blocks: [MapBlockCell]
        if hasRange(layout.blockmapOffset, length: layout.width * layout.height * 2) {
            blocks = parseBlocks(width: layout.width, height: layout.height, blockmapOffset: layout.blockmapOffset)
        } else {
            logFailure(stage: "blockmapBounds", offset: layout.blockmapOffset, rawValue: layout.rawBlockmapPointer, reason: "blockmap does not contain width*height cells")
            blocks = []
        }
        let events = eventsOffset.flatMap(parseEvents) ?? ([], [], [], [])
        let connections = connectionsOffset.map(parseConnections) ?? []

        let regionSectionID = byte(headerOffset + 20)
        let locationName = mapSectionNames[regionSectionID]
        return MapData(
            group: group,
            mapID: mapID,
            name: locationName?.isEmpty == false ? locationName! : "Map \(group).\(mapID)",
            width: layout.width,
            height: layout.height,
            blocks: blocks,
            objects: events.objects,
            warps: events.warps,
            coordinateEvents: events.coords,
            backgroundEvents: events.backgrounds,
            connections: connections,
            headerOffset: headerOffset,
            layoutOffset: layout.offset,
            blockmapOffset: layout.blockmapOffset,
            eventsOffset: eventsOffset,
            connectionsOffset: connectionsOffset,
            primaryTilesetOffset: layout.primaryTilesetOffset,
            secondaryTilesetOffset: layout.secondaryTilesetOffset,
            music: readUInt16(at: headerOffset + 16),
            layoutID: mapLayoutID,
            regionSectionID: regionSectionID,
            cave: byte(headerOffset + 21),
            weather: byte(headerOffset + 22),
            mapType: byte(headerOffset + 23),
            flags: byte(headerOffset + 26),
            battleType: byte(headerOffset + 27)
        )
    }

    private func parseBlocks(width: Int, height: Int, blockmapOffset: Int) -> [MapBlockCell] {
        var blocks: [MapBlockCell] = []
        blocks.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = blockmapOffset + (y * width + x) * 2
                let raw = readUInt16(at: offset)
                blocks.append(MapBlockCell(
                    x: x,
                    y: y,
                    metatileID: raw & 0x03FF,
                    collision: (raw >> 10) & 0x03,
                    elevation: (raw >> 12) & 0x0F,
                    offset: offset
                ))
            }
        }
        return blocks
    }

    private func parseMapSectionNames() -> [Int: String] {
        let namesAddress = mapNamesAddress
        guard hasRange(namesAddress, length: 1) else { return [:] }
        var result: [Int: String] = [:]
        var offset = namesAddress
        for index in 0..<Layout.mapNameCount {
            guard hasRange(offset, length: 1) else { break }
            let name = PCSStringCodec.decode(data, start: offset, length: 64)
            result[index] = name
            guard let terminator = (offset..<min(offset + 64, data.count)).first(where: { data[$0] == 0xFF }) else {
                break
            }
            offset = terminator + 1
        }
        return result
    }

    private func parseEvents(_ offset: Int) -> (objects: [MapObjectEvent], warps: [MapWarpEvent], coords: [MapCoordinateEvent], backgrounds: [MapBackgroundEvent])? {
        guard hasRange(offset, length: 20) else { return nil }
        let objectCount = byte(offset + 0)
        let warpCount = byte(offset + 1)
        let scriptCount = byte(offset + 2)
        let signpostCount = byte(offset + 3)
        let objectOffset = readPointer(at: offset + 4)
        let warpOffset = readPointer(at: offset + 8)
        let scriptOffset = readPointer(at: offset + 12)
        let signpostOffset = readPointer(at: offset + 16)
        let objects = parseObjects(offset: objectOffset, count: objectCount)
        let warps = parseWarps(offset: warpOffset, count: warpCount)
        let coords = parseCoordinateEvents(offset: scriptOffset, count: scriptCount)
        let backgrounds = parseBackgroundEvents(offset: signpostOffset, count: signpostCount)
        return (objects, warps, coords, backgrounds)
    }

    private func parseObjects(offset: Int?, count: Int) -> [MapObjectEvent] {
        guard let offset, count <= 100, hasRange(offset, length: count * Layout.mapObjectLength) else { return [] }
        return (0..<count).map { index in
            let entry = offset + index * Layout.mapObjectLength
            let range = byte(entry + 10)
            return MapObjectEvent(
                id: index,
                localID: byte(entry + 0),
                graphicsID: byte(entry + 1),
                x: readInt16(at: entry + 4),
                y: readInt16(at: entry + 6),
                elevation: byte(entry + 8),
                movementType: byte(entry + 9),
                movementRangeX: range & 0x0F,
                movementRangeY: range >> 4,
                trainerType: readUInt16(at: entry + 12),
                trainerRangeOrBerryID: readUInt16(at: entry + 14),
                scriptPointer: readRawUInt32(at: entry + 16),
                flag: readUInt16(at: entry + 20),
                offset: entry
            )
        }
    }

    private func parseWarps(offset: Int?, count: Int) -> [MapWarpEvent] {
        guard let offset, count <= 100, hasRange(offset, length: count * Layout.mapWarpLength) else { return [] }
        return (0..<count).map { index in
            let entry = offset + index * Layout.mapWarpLength
            return MapWarpEvent(
                id: index,
                x: readInt16(at: entry + 0),
                y: readInt16(at: entry + 2),
                elevation: byte(entry + 4),
                warpID: byte(entry + 5),
                destinationMap: byte(entry + 6),
                destinationGroup: byte(entry + 7),
                offset: entry
            )
        }
    }

    private func parseCoordinateEvents(offset: Int?, count: Int) -> [MapCoordinateEvent] {
        guard let offset, count <= 100, hasRange(offset, length: count * Layout.mapCoordinateLength) else { return [] }
        return (0..<count).map { index in
            let entry = offset + index * Layout.mapCoordinateLength
            return MapCoordinateEvent(
                id: index,
                x: readInt16(at: entry + 0),
                y: readInt16(at: entry + 2),
                elevation: byte(entry + 4),
                trigger: readUInt16(at: entry + 6),
                index: readUInt16(at: entry + 8),
                scriptPointer: readRawUInt32(at: entry + 12),
                offset: entry
            )
        }
    }

    private func parseBackgroundEvents(offset: Int?, count: Int) -> [MapBackgroundEvent] {
        guard let offset, count <= 100, hasRange(offset, length: count * Layout.mapBackgroundLength) else { return [] }
        return (0..<count).map { index in
            let entry = offset + index * Layout.mapBackgroundLength
            return MapBackgroundEvent(
                id: index,
                x: readInt16(at: entry + 0),
                y: readInt16(at: entry + 2),
                elevation: byte(entry + 4),
                kind: byte(entry + 5),
                argument: readRawUInt32(at: entry + 8),
                offset: entry
            )
        }
    }

    private func parseConnections(_ offset: Int) -> [MapConnectionData] {
        guard hasRange(offset, length: Layout.mapConnectionHeaderLength) else { return [] }
        let count = readUInt32(at: offset + 0)
        guard (0...32).contains(count),
              let entriesOffset = readPointer(at: offset + 4),
              hasRange(entriesOffset, length: count * Layout.mapConnectionLength) else { return [] }
        return (0..<count).map { index in
            let entry = entriesOffset + index * Layout.mapConnectionLength
            return MapConnectionData(
                id: index,
                direction: readUInt32(at: entry + 0),
                offsetValue: readInt32(at: entry + 4),
                targetGroup: byte(entry + 8),
                targetMap: byte(entry + 9),
                entryOffset: entry
            )
        }
    }

    private func resolveMapLayout(rawLayoutPointer: UInt32, mapLayoutID: Int, group: Int, mapID: Int) -> ParsedLayout? {
        if let directOffset = gbaPointerToROMOffset(rawLayoutPointer) {
            if let direct = parseLayout(at: directOffset, source: "MapHeader.mapLayout") {
                return direct
            }

            if hasRange(directOffset, length: 4) {
                let indirectRaw = readRawUInt32(at: directOffset)
                if let indirectOffset = gbaPointerToROMOffset(indirectRaw),
                   let indirect = parseLayout(at: indirectOffset, source: "MapHeader.mapLayout indirect") {
                    return indirect
                }
            }
        }

        guard mapLayoutID > 0, mapLayoutID <= Layout.mapLayoutCount else { return nil }
        let tableOffset = Layout.bpeeMapLayoutsAddress + (mapLayoutID - 1) * 4
        guard hasRange(tableOffset, length: 4) else { return nil }
        let rawLayoutFromTable = readRawUInt32(at: tableOffset)
        guard let layoutOffset = gbaPointerToROMOffset(rawLayoutFromTable) else { return nil }
        return parseLayout(at: layoutOffset, source: "data.maps.layouts[\(mapLayoutID - 1)]")
    }

    private func parseLayout(at offset: Int, source: String) -> ParsedLayout? {
        guard hasRange(offset, length: Layout.mapLayoutLength) else { return nil }

        let width = readUInt32(at: offset + 0)
        let height = readUInt32(at: offset + 4)
        guard (1...512).contains(width), (1...512).contains(height), width * height <= 65536 else {
            return nil
        }

        let rawBorderPointer = readRawUInt32(at: offset + 8)
        let rawBlockmapPointer = readRawUInt32(at: offset + 12)
        let rawPrimaryTilesetPointer = readRawUInt32(at: offset + 16)
        let rawSecondaryTilesetPointer = readRawUInt32(at: offset + 20)
        guard let borderOffset = gbaPointerToROMOffset(rawBorderPointer),
              let blockmapOffset = gbaPointerToROMOffset(rawBlockmapPointer),
              let primaryTilesetOffset = gbaPointerToROMOffset(rawPrimaryTilesetPointer),
              let secondaryTilesetOffset = gbaPointerToROMOffset(rawSecondaryTilesetPointer) else {
            return nil
        }

        return ParsedLayout(
            offset: offset,
            source: source,
            width: width,
            height: height,
            rawBorderPointer: rawBorderPointer,
            rawBlockmapPointer: rawBlockmapPointer,
            rawPrimaryTilesetPointer: rawPrimaryTilesetPointer,
            rawSecondaryTilesetPointer: rawSecondaryTilesetPointer,
            borderOffset: borderOffset,
            blockmapOffset: blockmapOffset,
            primaryTilesetOffset: primaryTilesetOffset,
            secondaryTilesetOffset: secondaryTilesetOffset
        )
    }

    private func resolveMapBanksAddress() throws -> Int {
        // The Swift port does not have HexManiacAdvance's symbolic anchor registry yet.
        // For BPEE only, use the verified HMA pointer source as an explicit fallback.
        guard EmeraldROM.supportedGameCodes.contains(gameCode) else {
            throw ROMError.unsupportedSemanticTables
        }
        let source = mapBanksPointerSource
        guard hasRange(source, length: 4) else {
            logFailure(stage: "mapBanksFallback", offset: source, rawValue: nil, reason: "BPEE fallback outside ROM")
            throw ROMError.missingTable("data.maps.banks")
        }
        let raw = readRawUInt32(at: source)
        guard let table = gbaPointerToROMOffset(raw), hasRange(table, length: Layout.mapBankCount * 4) else {
            logFailure(stage: "mapBanksPointerSource", offset: source, rawValue: raw, reason: "BPEE source did not resolve to gMapGroups")
            throw ROMError.missingTable("data.maps.banks")
        }
        return table
    }

    private var mapBanksPointerSource: Int {
        gameCode == "BPEI" ? Layout.bpeiMapBanksAddress : Layout.bpeeMapBanksAddress
    }

    private func mapCount(group: Int, bankPointers: [Int?], banksAddress: Int) -> Int {
        guard let bankOffset = bankPointers[safe: group] ?? nil else { return 0 }
        let sentinels = bankPointers
            .compactMap { $0 }
            .filter { $0 > bankOffset }
            + [banksAddress]
        guard let nextOffset = sentinels.filter({ $0 > bankOffset }).min() else { return 0 }
        let boundedCount = min((nextOffset - bankOffset) / 4, Layout.maxMapCountPerBank)
        var count = 0
        while count < boundedCount,
              let header = readPointer(at: bankOffset + count * 4),
              isValidMapHeader(at: header) {
            count += 1
        }
        return count
    }

    private func isValidMapHeader(at offset: Int) -> Bool {
        guard hasRange(offset, length: Layout.mapHeaderLength) else { return false }
        let rawLayoutPointer = readRawUInt32(at: offset + 0)
        let mapLayoutID = readUInt16(at: offset + 18)
        return resolveMapLayout(rawLayoutPointer: rawLayoutPointer, mapLayoutID: mapLayoutID, group: -1, mapID: -1) != nil
    }

    private var gameCode: String {
        guard data.count >= 0xB0 else { return "" }
        return String(bytes: data[0xAC..<0xB0], encoding: .ascii) ?? ""
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = readRawUInt32(at: offset)
        guard let pointer = gbaPointerToROMOffset(raw) else { return nil }
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func gbaPointerToROMOffset(_ raw: UInt32) -> Int? {
        guard raw >= 0x0800_0000 else { return nil }
        let pointer = Int(raw - 0x0800_0000)
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func logHeader(banksAddress: Int, firstRawPointer: UInt32, firstConvertedPointer: Int?) {
    }

    private func logFailure(stage: String, offset: Int, rawValue: UInt32?, reason: String) {
    }

    private func hexBytes(start: Int, count: Int) -> String {
        guard hasRange(start, length: 1) else { return "" }
        let end = min(start + count, data.count)
        return (start..<end).map { String(format: "%02X", data[$0]) }.joined(separator: " ")
    }

    private func layoutDump(offset: Int) -> String {
        guard hasRange(offset, length: Layout.mapLayoutLength) else {
            return String(format: "layout dump unavailable: 0x%08X outside ROM", offset)
        }
        return stride(from: 0, to: Layout.mapLayoutLength, by: 4).map { relativeOffset in
            let fieldOffset = offset + relativeOffset
            let bytes = hexBytes(start: fieldOffset, count: 4)
            let raw = readRawUInt32(at: fieldOffset)
            return String(format: "+0x%02X bytes: %@ -> u32 LE 0x%08X", relativeOffset, bytes, raw)
        }.joined(separator: "\n")
    }

    private func byte(_ offset: Int) -> Int {
        Int(data[offset])
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func readUInt32(at offset: Int) -> Int {
        Int(data[offset])
            | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16)
            | (Int(data[offset + 3]) << 24)
    }

    private func readRawUInt32(at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func readInt16(at offset: Int) -> Int {
        Int(Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)))
    }

    private func readInt32(at offset: Int) -> Int {
        Int(Int32(bitPattern: readRawUInt32(at: offset)))
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }

    private static func writeUInt16(_ value: Int, at offset: Int, into data: inout Data) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func validateByte(_ value: Int, _ label: String) throws {
        guard (0...255).contains(value) else { throw ROMError.valueOutOfRange(label) }
    }

    private static func validateMetatile(_ value: Int) throws {
        guard (0...0x03FF).contains(value) else { throw ROMError.indexOutOfRange("Metatile") }
    }

    private static func validateSigned16(_ value: Int, _ label: String) throws {
        guard (-32768...32767).contains(value) else { throw ROMError.signedValueOutOfRange(label) }
    }
}

struct PokemonSpriteRenderer {
    private enum Layout {
        // HexManiacAdvance tableReference.txt BPEE0: pointer sources for front sprite and normal palette tables.
        static let frontSpriteTablePointerSource = 0x000128
        static let normalPaletteTablePointerSource = 0x000130
        static let entryLength = 8
        static let side = 64
    }

    let data: Data

    func frontSprite(for speciesID: Int) -> NSImage? {
        guard speciesID > 0,
              let spriteTable = resolvePointerSource(Layout.frontSpriteTablePointerSource),
              let paletteTable = resolvePointerSource(Layout.normalPaletteTablePointerSource) else { return nil }

        let spriteEntry = spriteTable + speciesID * Layout.entryLength
        let paletteEntry = paletteTable + speciesID * Layout.entryLength
        guard let spriteAddress = readPointer(at: spriteEntry),
              let paletteAddress = readPointer(at: paletteEntry),
              let spriteData = lz77Decompress(from: spriteAddress),
              let paletteData = lz77Decompress(from: paletteAddress) else { return nil }

        let palette = decodePalette(paletteData)
        guard palette.count >= 16 else { return nil }
        return render4bppTileImage(spriteData, palette: palette)
    }

    private func render4bppTileImage(_ spriteData: Data, palette: [NSColor]) -> NSImage? {
        let side = Layout.side
        let bytesPerRow = side * 4
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        ), let pixels = bitmap.bitmapData else { return nil }

        for tileY in 0..<8 {
            for tileX in 0..<8 {
                let tileIndex = tileY * 8 + tileX
                let tileOffset = tileIndex * 32
                guard tileOffset + 32 <= spriteData.count else { continue }
                for row in 0..<8 {
                    for pair in 0..<4 {
                        let packed = spriteData[tileOffset + row * 4 + pair]
                        let colors = [Int(packed & 0x0F), Int(packed >> 4)]
                        for subpixel in 0..<2 {
                            let x = tileX * 8 + pair * 2 + subpixel
                            let y = tileY * 8 + row
                            let destination = y * bytesPerRow + x * 4
                            let colorIndex = colors[subpixel]
                            if colorIndex == 0 {
                                pixels[destination + 3] = 0
                            } else {
                                let color = palette[colorIndex]
                                guard let rgb = color.usingColorSpace(.deviceRGB) else { continue }
                                pixels[destination + 0] = UInt8((rgb.redComponent * 255).rounded())
                                pixels[destination + 1] = UInt8((rgb.greenComponent * 255).rounded())
                                pixels[destination + 2] = UInt8((rgb.blueComponent * 255).rounded())
                                pixels[destination + 3] = 255
                            }
                        }
                    }
                }
            }
        }

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    private func decodePalette(_ paletteData: Data) -> [NSColor] {
        stride(from: 0, to: min(32, paletteData.count), by: 2).map { offset in
            let value = UInt16(paletteData[offset]) | (UInt16(paletteData[offset + 1]) << 8)
            let red = CGFloat(value & 0x1F) / 31.0
            let green = CGFloat((value >> 5) & 0x1F) / 31.0
            let blue = CGFloat((value >> 10) & 0x1F) / 31.0
            return NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
        }
    }

    private func lz77Decompress(from offset: Int) -> Data? {
        guard hasRange(offset, length: 4), data[offset] == 0x10 else { return nil }
        let decompressedLength = Int(data[offset + 1]) | (Int(data[offset + 2]) << 8) | (Int(data[offset + 3]) << 16)
        guard decompressedLength > 0 else { return nil }

        var source = offset + 4
        var output = Data()
        output.reserveCapacity(decompressedLength)

        while output.count < decompressedLength, hasRange(source, length: 1) {
            let flags = data[source]
            source += 1
            for bit in 0..<8 where output.count < decompressedLength {
                if flags & (0x80 >> UInt8(bit)) == 0 {
                    guard hasRange(source, length: 1) else { return nil }
                    output.append(data[source])
                    source += 1
                } else {
                    guard hasRange(source, length: 2) else { return nil }
                    let first = Int(data[source])
                    let second = Int(data[source + 1])
                    source += 2
                    let length = (first >> 4) + 3
                    let displacement = ((first & 0x0F) << 8) | second
                    let copyStart = output.count - displacement - 1
                    guard copyStart >= 0 else { return nil }
                    for index in 0..<length where output.count < decompressedLength {
                        output.append(output[copyStart + index])
                    }
                }
            }
        }

        return output.count == decompressedLength ? output : nil
    }

    private func resolvePointerSource(_ source: Int) -> Int? {
        readPointer(at: source)
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let pointer = Int(raw - 0x0800_0000)
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }
}

struct TrainerSpriteRenderer {
    private enum Layout {
        // Offsets of graphics.trainers.sprites.front / graphics.trainers.palettes.front in Emerald.
        //   Game Code  frontSpriteTableAddress  frontPaletteTableAddress
        //   BPEE (USA) 0x305654                 0x30593C
        //   BPEI (ITA) 0x300DDC                 0x3010C4
        static let trainerSpriteCount = 93
        static let entryLength = 8
        static let side = 64

        static func frontSpriteTableAddress(for data: Data) -> Int {
            isItalian(data) ? 0x300DDC : 0x305654
        }

        static func frontPaletteTableAddress(for data: Data) -> Int {
            isItalian(data) ? 0x3010C4 : 0x30593C
        }

        private static func isItalian(_ data: Data) -> Bool {
            guard data.count >= 0xB0 else { return false }
            return String(bytes: data[0xAC..<0xB0], encoding: .ascii) == "BPEI"
        }
    }

    let data: Data

    func frontSprite(for spriteID: Int) -> NSImage? {
        guard spriteID >= 0, spriteID < Layout.trainerSpriteCount else {
            print("[HexManiaMac] Trainer sprite unavailable: sprite id \(spriteID) outside table")
            return nil
        }

        let spriteEntry = Layout.frontSpriteTableAddress(for: data) + spriteID * Layout.entryLength
        let paletteEntry = Layout.frontPaletteTableAddress(for: data) + spriteID * Layout.entryLength
        guard let spriteAddress = readPointer(at: spriteEntry),
              let paletteAddress = readPointer(at: paletteEntry) else {
            print(String(format: "[HexManiaMac] Trainer sprite unavailable: id %d spriteEntry 0x%08X paletteEntry 0x%08X", spriteID, spriteEntry, paletteEntry))
            return nil
        }

        guard let spriteData = lz77Decompress(from: spriteAddress),
              let paletteData = paletteData(from: paletteAddress) else {
            print(String(format: "[HexManiaMac] Trainer sprite unavailable: id %d spriteOffset 0x%08X paletteOffset 0x%08X", spriteID, spriteAddress, paletteAddress))
            return nil
        }

        let palette = decodePalette(paletteData)
        guard palette.count >= 16 else {
            print("[HexManiaMac] Trainer sprite unavailable: palette too small for id \(spriteID)")
            return nil
        }
        return render4bppTileImage(spriteData, palette: palette)
    }

    private func render4bppTileImage(_ spriteData: Data, palette: [NSColor]) -> NSImage? {
        let side = Layout.side
        let bytesPerRow = side * 4
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        ), let pixels = bitmap.bitmapData else { return nil }

        for tileY in 0..<8 {
            for tileX in 0..<8 {
                let tileIndex = tileY * 8 + tileX
                let tileOffset = tileIndex * 32
                guard tileOffset + 32 <= spriteData.count else { continue }
                for row in 0..<8 {
                    for pair in 0..<4 {
                        let packed = spriteData[tileOffset + row * 4 + pair]
                        let colors = [Int(packed & 0x0F), Int(packed >> 4)]
                        for subpixel in 0..<2 {
                            let x = tileX * 8 + pair * 2 + subpixel
                            let y = tileY * 8 + row
                            let destination = y * bytesPerRow + x * 4
                            let colorIndex = colors[subpixel]
                            if colorIndex == 0 {
                                pixels[destination + 3] = 0
                            } else {
                                let color = palette[colorIndex]
                                guard let rgb = color.usingColorSpace(.deviceRGB) else { continue }
                                pixels[destination + 0] = UInt8((rgb.redComponent * 255).rounded())
                                pixels[destination + 1] = UInt8((rgb.greenComponent * 255).rounded())
                                pixels[destination + 2] = UInt8((rgb.blueComponent * 255).rounded())
                                pixels[destination + 3] = 255
                            }
                        }
                    }
                }
            }
        }

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    private func decodePalette(_ paletteData: Data) -> [NSColor] {
        stride(from: 0, to: min(32, paletteData.count), by: 2).map { offset in
            let value = UInt16(paletteData[offset]) | (UInt16(paletteData[offset + 1]) << 8)
            let red = CGFloat(value & 0x1F) / 31.0
            let green = CGFloat((value >> 5) & 0x1F) / 31.0
            let blue = CGFloat((value >> 10) & 0x1F) / 31.0
            return NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
        }
    }

    private func paletteData(from offset: Int) -> Data? {
        if let decompressed = lz77Decompress(from: offset) {
            return decompressed
        }
        guard hasRange(offset, length: 32) else { return nil }
        return data.subdata(in: offset..<(offset + 32))
    }

    private func lz77Decompress(from offset: Int) -> Data? {
        guard hasRange(offset, length: 4), data[offset] == 0x10 else { return nil }
        let decompressedLength = Int(data[offset + 1]) | (Int(data[offset + 2]) << 8) | (Int(data[offset + 3]) << 16)
        guard decompressedLength > 0 else { return nil }

        var source = offset + 4
        var output = Data()
        output.reserveCapacity(decompressedLength)

        while output.count < decompressedLength, hasRange(source, length: 1) {
            let flags = data[source]
            source += 1
            for bit in 0..<8 where output.count < decompressedLength {
                if flags & (0x80 >> UInt8(bit)) == 0 {
                    guard hasRange(source, length: 1) else { return nil }
                    output.append(data[source])
                    source += 1
                } else {
                    guard hasRange(source, length: 2) else { return nil }
                    let first = Int(data[source])
                    let second = Int(data[source + 1])
                    source += 2
                    let length = (first >> 4) + 3
                    let displacement = ((first & 0x0F) << 8) | second
                    let copyStart = output.count - displacement - 1
                    guard copyStart >= 0 else { return nil }
                    for index in 0..<length where output.count < decompressedLength {
                        output.append(output[copyStart + index])
                    }
                }
            }
        }

        return output.count == decompressedLength ? output : nil
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let pointer = Int(raw - 0x0800_0000)
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }
}

struct ObjectEventSpriteRenderer {
    private enum Layout {
        static let pointerCount = 247
        static let pointerValidationCount = 24
        static let pointerLength = 4
        static let graphicsInfoLength = 36
        static let maxSpriteSide = 64
    }

    private struct GraphicsInfo {
        let paletteTag: Int
        let size: Int
        let width: Int
        let height: Int
        let imagesOffset: Int
    }

    let data: Data
    private static var pointerTableCache: [String: Int] = [:]
    private static var paletteCache: [String: [Int: [NSColor]]] = [:]
    private static var paletteTableCache: [String: [Int: Int]] = [:]
    private static var paletteCandidatesCache: [String: [Int: Int]] = [:]

    func sprite(for graphicsID: Int) -> NSImage? {
        guard graphicsID >= 0,
              let pointerTable = locateGraphicsInfoPointerTable(),
              hasRange(pointerTable + graphicsID * Layout.pointerLength, length: Layout.pointerLength),
              let infoOffset = readPointer(at: pointerTable + graphicsID * Layout.pointerLength),
              let info = parseGraphicsInfo(at: infoOffset),
              let frame = readSpriteFrame(from: info),
              let palette = palette(tag: info.paletteTag) else {
            return nil
        }
        return render(frame.data, width: info.width, height: info.height, palette: palette)
    }

    private func locateGraphicsInfoPointerTable() -> Int? {
        if let cached = Self.pointerTableCache[cacheKey] { return cached }
        var best: (offset: Int, score: Int)?
        var offset = 0
        while offset + Layout.pointerValidationCount * Layout.pointerLength < data.count {
            var score = 0
            for index in 0..<Layout.pointerValidationCount {
                let pointerOffset = offset + index * Layout.pointerLength
                guard let infoOffset = readPointer(at: pointerOffset),
                      parseGraphicsInfo(at: infoOffset) != nil else {
                    continue
                }
                score += 1
            }
            if score > (best?.score ?? 0) {
                best = (offset, score)
                if score == Layout.pointerValidationCount {
                    Self.pointerTableCache[cacheKey] = offset
                    return offset
                }
            }
            offset += 4
        }
        guard let best, best.score >= 18 else { return nil }
        Self.pointerTableCache[cacheKey] = best.offset
        return best.offset
    }

    private func parseGraphicsInfo(at offset: Int) -> GraphicsInfo? {
        guard hasRange(offset, length: Layout.graphicsInfoLength) else { return nil }
        let size = readUInt16(at: offset + 6)
        let width = readInt16(at: offset + 8)
        let height = readInt16(at: offset + 10)
        guard [128, 256, 512, 1024, 2048].contains(size),
              [16, 32, 64].contains(width),
              [16, 32, 64].contains(height),
              size >= width * height / 2,
              let imagesOffset = readPointer(at: offset + 28),
              hasRange(imagesOffset, length: 8) else { return nil }
        return GraphicsInfo(
            paletteTag: readUInt16(at: offset + 2),
            size: size,
            width: width,
            height: height,
            imagesOffset: imagesOffset
        )
    }

    private func readSpriteFrame(from info: GraphicsInfo) -> (data: Data, size: Int)? {
        guard let pixelsOffset = readPointer(at: info.imagesOffset) else { return nil }
        let frameSize = readUInt16(at: info.imagesOffset + 4)
        let byteCount = min(max(frameSize, info.width * info.height / 2), info.size)
        guard byteCount > 0, hasRange(pixelsOffset, length: byteCount) else { return nil }
        return (data.subdata(in: pixelsOffset..<(pixelsOffset + byteCount)), byteCount)
    }

    private func palette(tag: Int) -> [NSColor]? {
        if let cached = Self.paletteCache[cacheKey]?[tag] { return cached }
        guard let colors = decodeTaggedPalette(tag: tag) else { return nil }
        var palettes = Self.paletteCache[cacheKey] ?? [:]
        palettes[tag] = colors
        Self.paletteCache[cacheKey] = palettes
        return colors
    }

    private func decodeTaggedPalette(tag: Int) -> [NSColor]? {
        if let table = locateObjectEventPaletteTable(),
           let dataOffset = table[tag],
           hasRange(dataOffset, length: 32) {
            let colors = decodePalette(at: dataOffset)
            if isValidObjectPalette(colors) { return colors }
        }
        if let candidates = flattenedPaletteCandidates(), let dataOffset = candidates[tag],
           hasRange(dataOffset, length: 32) {
            let colors = decodePalette(at: dataOffset)
            if isValidObjectPalette(colors) { return colors }
        }
        var offset = 0
        while offset + 8 <= data.count {
            guard let dataOffset = readPointer(at: offset) else {
                offset += 4
                continue
            }
            if readUInt16(at: offset + 4) == tag,
               hasRange(dataOffset, length: 32) {
                let colors = decodePalette(at: dataOffset)
                if isValidObjectPalette(colors) { return colors }
            }
            offset += 4
        }
        return nil
    }

    private func locateObjectEventPaletteTable() -> [Int: Int]? {
        if let cached = Self.paletteTableCache[cacheKey] { return cached }
        let empty: [Int: Int] = [:]
        var bestRun: [(dataOffset: Int, tag: Int)] = []
        for base in 0..<8 {
            var currentRun: [(dataOffset: Int, tag: Int)] = []
            var offset = base
            while offset + 8 <= data.count {
                if let dataOffset = readPointer(at: offset),
                   hasRange(dataOffset, length: 32) {
                    currentRun.append((dataOffset, readUInt16(at: offset + 4)))
                } else {
                    if currentRun.count > bestRun.count { bestRun = currentRun }
                    currentRun = []
                }
                offset += 8
            }
            if currentRun.count > bestRun.count { bestRun = currentRun }
        }
        guard bestRun.count >= 6 else {
            Self.paletteTableCache[cacheKey] = empty
            return nil
        }
        var table: [Int: Int] = [:]
        for entry in bestRun {
            if table[entry.tag] == nil, hasRange(entry.dataOffset, length: 32),
               isValidObjectPalette(decodePalette(at: entry.dataOffset)) {
                table[entry.tag] = entry.dataOffset
            }
        }
        guard !table.isEmpty else {
            Self.paletteTableCache[cacheKey] = empty
            return nil
        }
        Self.paletteTableCache[cacheKey] = table
        return table
    }

    private func flattenedPaletteCandidates() -> [Int: Int]? {
        if let cached = Self.paletteCandidatesCache[cacheKey] { return cached }
        let empty: [Int: Int] = [:]
        var candidates: [Int: Int] = [:]
        var offset = 0
        while offset + 8 <= data.count {
            if let dataOffset = readPointer(at: offset),
               hasRange(dataOffset, length: 32) {
                let tag = readUInt16(at: offset + 4)
                if candidates[tag] == nil { candidates[tag] = dataOffset }
            }
            offset += 4
        }
        guard !candidates.isEmpty else {
            Self.paletteCandidatesCache[cacheKey] = empty
            return nil
        }
        Self.paletteCandidatesCache[cacheKey] = candidates
        return candidates
    }

    private func isValidObjectPalette(_ colors: [NSColor]) -> Bool {
        guard colors.count >= 2 else { return false }
        var seen: Set<Int> = []
        for color in colors {
            guard let rgb = color.usingColorSpace(.deviceRGB) else { continue }
            let r = min(31, Int((rgb.redComponent * 31).rounded()))
            let g = min(31, Int((rgb.greenComponent * 31).rounded()))
            let b = min(31, Int((rgb.blueComponent * 31).rounded()))
            seen.insert((r << 10) | (g << 5) | b)
            if seen.count >= 2 { return true }
        }
        return false
    }

    private var cacheKey: String {
        let code = data.count >= 0xB0 ? (String(bytes: data[0xAC..<0xB0], encoding: .ascii) ?? "") : ""
        return "\(code)-\(data.count)"
    }

    private func render(_ spriteData: Data, width: Int, height: Int, palette: [NSColor]) -> NSImage? {
        guard width > 0, height > 0,
              width <= Layout.maxSpriteSide,
              height <= Layout.maxSpriteSide else { return nil }
        let bytesPerRow = width * 4
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 32
        ), let pixels = bitmap.bitmapData else { return nil }

        let tilesWide = width / 8
        let tilesHigh = height / 8
        for tileY in 0..<tilesHigh {
            for tileX in 0..<tilesWide {
                let tileIndex = tileY * tilesWide + tileX
                let tileOffset = tileIndex * 32
                guard tileOffset + 32 <= spriteData.count else { continue }
                for row in 0..<8 {
                    for pair in 0..<4 {
                        let packed = spriteData[tileOffset + row * 4 + pair]
                        let colors = [Int(packed & 0x0F), Int(packed >> 4)]
                        for subpixel in 0..<2 {
                            let colorIndex = colors[subpixel]
                            let x = tileX * 8 + pair * 2 + subpixel
                            let y = tileY * 8 + row
                            let destination = y * bytesPerRow + x * 4
                            guard colorIndex != 0, colorIndex < palette.count,
                                  let rgb = palette[colorIndex].usingColorSpace(.deviceRGB) else {
                                pixels[destination + 3] = 0
                                continue
                            }
                            pixels[destination + 0] = UInt8((rgb.redComponent * 255).rounded())
                            pixels[destination + 1] = UInt8((rgb.greenComponent * 255).rounded())
                            pixels[destination + 2] = UInt8((rgb.blueComponent * 255).rounded())
                            pixels[destination + 3] = 255
                        }
                    }
                }
            }
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }

    private func decodePalette(at offset: Int) -> [NSColor] {
        stride(from: 0, to: 32, by: 2).map { relativeOffset in
            let value = UInt16(data[offset + relativeOffset]) | (UInt16(data[offset + relativeOffset + 1]) << 8)
            let red = CGFloat(value & 0x1F) / 31.0
            let green = CGFloat((value >> 5) & 0x1F) / 31.0
            let blue = CGFloat((value >> 10) & 0x1F) / 31.0
            return NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
        }
    }

    private func readPointer(at offset: Int) -> Int? {
        guard hasRange(offset, length: 4) else { return nil }
        let raw = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let pointer = Int(raw - 0x0800_0000)
        return hasRange(pointer, length: 1) ? pointer : nil
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func readInt16(at offset: Int) -> Int {
        Int(Int16(bitPattern: UInt16(readUInt16(at: offset))))
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }
}

struct EventScriptTrainerResolver {
    private enum Layout {
        static let trainerBattleCommand = 0x5C
        static let scanLength = 192
    }

    let data: Data

    func trainerLink(for object: MapObjectEvent) -> MapObjectTrainerLink? {
        guard object.trainerType != 0,
              let scriptOffset = gbaPointerToROMOffset(object.scriptPointer),
              hasRange(scriptOffset, length: 4) else {
            return nil
        }
        let end = min(scriptOffset + Layout.scanLength, data.count - 4)
        var offset = scriptOffset
        while offset < end {
            if data[offset] == UInt8(Layout.trainerBattleCommand), hasRange(offset, length: 4) {
                let trainerID = readUInt16(at: offset + 2)
                return MapObjectTrainerLink(trainerID: trainerID, scriptOffset: scriptOffset, commandOffset: offset)
            }
            offset += 1
        }
        return nil
    }

    private func gbaPointerToROMOffset(_ raw: UInt32) -> Int? {
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let offset = Int(raw - 0x0800_0000)
        return hasRange(offset, length: 1) ? offset : nil
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }
}

struct EventScriptAnalyzer {
    private enum Layout {
        static let scanLength = 192
        static let trainerBattleCommand = 0x5C
        static let setFlagCommand = 0x29
        static let clearFlagCommand = 0x2A
        static let checkFlagCommand = 0x2B
        static let setVarCommand = 0x16
        static let copyVarCommand = 0x19
        static let compareVarCommand = 0x21
        static let compareVarToVarCommand = 0x22
        static let callCommand = 0x04
        static let gotoCommand = 0x05
        static let callIfCommand = 0x06
        static let gotoIfCommand = 0x07
        static let specialCommand = 0x25
        static let giveItemCommand = 0x44
        static let applyMovementCommand = 0x4F
        static let endCommands: Set<UInt8> = [0x02, 0x03]
    }

    let data: Data

    func analyze(pointer: UInt32, eventType: String) -> MapScriptAnalysis {
        guard let scriptOffset = gbaPointerToROMOffset(pointer),
              hasRange(scriptOffset, length: 1) else {
            return MapScriptAnalysis(
                pointer: pointer,
                scriptOffset: nil,
                eventType: eventType,
                classification: .none,
                flags: [],
                variables: [],
                commands: [],
                reason: "Pointer assente o fuori ROM"
            )
        }

        var flags: [Int] = []
        var variables: [Int] = []
        var commands: [String] = []
        let end = min(scriptOffset + Layout.scanLength, data.count)
        var offset = scriptOffset
        while offset < end {
            let command = data[offset]
            if Layout.endCommands.contains(command) {
                commands.append("end")
                break
            }
            switch Int(command) {
            case Layout.trainerBattleCommand:
                if hasRange(offset + 2, length: 2) {
                    commands.append("trainerbattle #\(readUInt16(at: offset + 2))")
                    offset += 6
                    continue
                }
            case Layout.setFlagCommand:
                if hasRange(offset + 1, length: 2) {
                    let value = readUInt16(at: offset + 1)
                    flags.append(value)
                    commands.append("setflag #\(value)")
                    offset += 3
                    continue
                }
            case Layout.clearFlagCommand:
                if hasRange(offset + 1, length: 2) {
                    let value = readUInt16(at: offset + 1)
                    flags.append(value)
                    commands.append("clearflag #\(value)")
                    offset += 3
                    continue
                }
            case Layout.checkFlagCommand:
                if hasRange(offset + 1, length: 2) {
                    let value = readUInt16(at: offset + 1)
                    flags.append(value)
                    commands.append("checkflag #\(value)")
                    offset += 3
                    continue
                }
            case Layout.setVarCommand, Layout.copyVarCommand, Layout.compareVarCommand, Layout.compareVarToVarCommand:
                if hasRange(offset + 1, length: 2) {
                    let value = readUInt16(at: offset + 1)
                    variables.append(value)
                    commands.append("var command 0x\(String(format: "%02X", command)) #\(value)")
                    offset += 5
                    continue
                }
            case Layout.callCommand, Layout.gotoCommand:
                commands.append(command == Layout.callCommand ? "call" : "goto")
                offset += 5
                continue
            case Layout.callIfCommand, Layout.gotoIfCommand:
                commands.append(command == Layout.callIfCommand ? "callif" : "gotoif")
                offset += 6
                continue
            case Layout.specialCommand:
                commands.append("special")
                offset += 3
                continue
            case Layout.giveItemCommand:
                commands.append("giveitem")
                offset += 5
                continue
            case Layout.applyMovementCommand:
                commands.append("applymovement")
                offset += 6
                continue
            default:
                break
            }
            offset += 1
        }

        let uniqueFlags = Array(Set(flags)).sorted()
        let uniqueVariables = Array(Set(variables)).sorted()
        let uniqueCommands = Array(commands.prefix(10))
        let classification: MapScriptAnalysis.Classification
        let reason: String
        if uniqueCommands.contains(where: { $0.hasPrefix("trainerbattle") }) {
            classification = .important
            reason = "Contiene trainerbattle"
        } else if !uniqueFlags.isEmpty || !uniqueVariables.isEmpty || uniqueCommands.contains(where: { ["giveitem", "applymovement", "special"].contains($0) }) {
            classification = .possibleProgression
            reason = "Tocca flag/var o comandi di stato"
        } else if !uniqueCommands.isEmpty {
            classification = .scripted
            reason = "Script leggibile senza mutazioni note"
        } else {
            classification = .scripted
            reason = "Pointer valido, nessun comando noto nella finestra di analisi"
        }

        return MapScriptAnalysis(
            pointer: pointer,
            scriptOffset: scriptOffset,
            eventType: eventType,
            classification: classification,
            flags: uniqueFlags,
            variables: uniqueVariables,
            commands: uniqueCommands,
            reason: reason
        )
    }

    private func gbaPointerToROMOffset(_ raw: UInt32) -> Int? {
        guard raw >= 0x0800_0000 && raw < 0x0A00_0000 else { return nil }
        let offset = Int(raw - 0x0800_0000)
        return hasRange(offset, length: 1) ? offset : nil
    }

    private func readUInt16(at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private func hasRange(_ start: Int, length: Int) -> Bool {
        start >= 0 && length >= 0 && start + length <= data.count
    }
}

enum PCSStringCodec {
    private static let table: [String?] = {
        var values = Array<String?>(repeating: nil, count: 256)
        values[0x00] = " "
        fill(&values, "ÀÁÂÇÈÉÊËÌ", 0x01)
        fill(&values, "ÎÏÒÓÔ", 0x0B)
        fill(&values, "ŒÙÚÛÑßàá", 0x10)
        fill(&values, "çèéêëì", 0x19)
        fill(&values, "îïòóôœùúûñºª", 0x20)
        values[0x2C] = "é"
        fill(&values, "& +", 0x2D)
        fill(&values, "Lv=;", 0x34)
        values[0x48] = "\r"
        fill(&values, "¿¡", 0x51)
        values[0x53] = "PK"
        values[0x54] = "MN"
        fill(&values, "%()", 0x5B)
        values[0x68] = "â"
        values[0x6F] = "í"
        fill(&values, "0123456789", 0xA1)
        fill(&values, "!?.-", 0xAB)
        values[0xB0] = "…"
        values[0xB1] = "“"
        values[0xB2] = "”"
        values[0xB3] = "‘"
        values[0xB4] = "'"
        values[0xB5] = "♂"
        values[0xB6] = "♀"
        values[0xB7] = "$"
        values[0xB8] = ","
        values[0xB9] = "*"
        values[0xBA] = "/"
        fill(&values, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 0xBB)
        fill(&values, "abcdefghijklmnopqrstuvwxyz", 0xD5)
        values[0xF0] = ":"
        values[0xF1] = "Ä"
        values[0xF2] = "Ö"
        values[0xF3] = "Ü"
        values[0xF4] = "ä"
        values[0xF5] = "ö"
        values[0xF6] = "ü"
        return values
    }()

    private static let reverseTable: [String: UInt8] = {
        var values: [String: UInt8] = [:]
        for (index, text) in table.enumerated() {
            guard let text, values[text] == nil else { continue }
            values[text] = UInt8(index)
        }
        return values
    }()

    static func decode(_ data: Data, start: Int, length: Int) -> String {
        var result = ""
        for offset in start..<min(start + length, data.count) {
            let value = data[offset]
            if value == 0xFF { break }
            result += table[Int(value)] ?? String(format: "\\!%02X", value)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ text: String, into data: inout Data, start: Int, length: Int, label: String) throws {
        guard start >= 0, length > 0, start + length <= data.count else { throw ROMError.unsupportedSemanticTables }
        var bytes: [UInt8] = []
        for character in text {
            guard let encoded = reverseTable[String(character)] else {
                throw ROMError.textNotEncodable(label)
            }
            bytes.append(encoded)
        }
        guard bytes.count < length else { throw ROMError.textTooLong(label) }
        for index in 0..<length {
            data[start + index] = index < bytes.count ? bytes[index] : 0xFF
        }
    }

    private static func fill(_ values: inout [String?], _ text: String, _ start: Int) {
        for (index, character) in text.enumerated() where start + index < values.count {
            values[start + index] = String(character)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
