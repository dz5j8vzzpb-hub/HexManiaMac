import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case pokemon
    case moves
    case trainers
    case maps
    case wildEncounters
    case items
    case teamCoach
    case advanced
    case texts
    case hex

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .pokemon: L10n.text("pokemon", language: language)
        case .moves: L10n.text("moves", language: language)
        case .trainers: L10n.text("trainers", language: language)
        case .maps: L10n.text("maps", language: language)
        case .wildEncounters: L10n.text("wild.encounters", language: language)
        case .items: L10n.text("items", language: language)
        case .teamCoach: "Team Coach"
        case .advanced: language == .italian ? "Avanzate" : "Advanced"
        case .texts: L10n.text("texts", language: language)
        case .hex: L10n.text("hex", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .pokemon: "pawprint.fill"
        case .moves: "sparkles"
        case .trainers: "person.2.fill"
        case .maps: "map.fill"
        case .wildEncounters: "leaf.fill"
        case .items: "shippingbox.fill"
        case .teamCoach: "person.3.sequence.fill"
        case .advanced: "slider.horizontal.3"
        case .texts: "text.quote"
        case .hex: "number"
        }
    }

    var isImplemented: Bool {
        self == .pokemon || self == .moves || self == .trainers || self == .maps || self == .wildEncounters || self == .items || self == .teamCoach || self == .advanced || self == .hex
    }
}

enum SaveWorkspaceSection: String, CaseIterable, Identifiable {
    case info
    case party
    case boxes
    case bag
    case trainer
    case pokedex
    case progression
    case advanced

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .info: L10n.text("save.info", language: language)
        case .party: L10n.text("party", language: language)
        case .boxes: L10n.text("boxes", language: language)
        case .bag: L10n.text("bag", language: language)
        case .trainer: L10n.text("trainer", language: language)
        case .pokedex: L10n.text("pokedex", language: language)
        case .progression: L10n.text("progress", language: language)
        case .advanced: L10n.text("advanced", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .party: "person.3.fill"
        case .boxes: "square.grid.3x3.fill"
        case .bag: "bag.fill"
        case .trainer: "person.crop.circle.fill"
        case .pokedex: "book.closed.fill"
        case .progression: "flag.checkered"
        case .advanced: "slider.horizontal.3"
        }
    }
}

enum SwordShieldWorkspaceSection: String, CaseIterable, Identifiable {
    case pokemon
    case moves
    case trainers
    case wildEncounters
    case items

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pokemon:
            "Pokémon"
        case .moves:
            "Mosse"
        case .trainers:
            "Allenatori"
        case .wildEncounters:
            "Incontri selvatici"
        case .items:
            "Oggetti"
        }
    }

    var systemImage: String {
        switch self {
        case .pokemon:
            "pawprint.fill"
        case .moves:
            "sparkles"
        case .trainers:
            "person.2.fill"
        case .wildEncounters:
            "leaf.fill"
        case .items:
            "shippingbox.fill"
        }
    }
}

struct MapTrainerNavigationContext: Equatable {
    let mapID: MapData.ID
    let objectID: MapObjectEvent.ID
}

struct ContentView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @State private var selectedSection: WorkspaceSection = .pokemon
    @State private var selectedSaveSection: SaveWorkspaceSection = .info
    @State private var selectedSwordShieldSection: SwordShieldWorkspaceSection = .pokemon
    @State private var isSettingsPresented = false
    @State private var selectedGame: SupportedGame = .emerald
    @State private var swordShieldStatusMessage: String?
    @State private var requestedTrainerID: TrainerData.ID?
    @State private var mapTrainerContext: MapTrainerNavigationContext?

    var body: some View {
        Group {
            switch document.editorMode {
            case .home:
                WelcomeView(
                    selectedGame: $selectedGame,
                    swordShieldStatusMessage: swordShieldStatusMessage,
                    openROM: {
                        if selectedGame.isEmerald {
                            print("[ROM] Open ROM button pressed")
                            presentOpenPanel(kind: .rom)
                        } else {
                            presentOpenPanel(kind: .gameDirectory)
                        }
                    },
                    openSave: {
                        guard selectedGame.isEmerald else { return }
                        print("[SAVE] Open Save button pressed")
                        presentOpenPanel(kind: .save)
                    },
                    openTeamCoach: {
                        document.openTeamCoach()
                    },
                    openSettings: {
                        isSettingsPresented = true
                    }
                )
            case .rom:
                romWorkspace
            case .save:
                saveWorkspace
            case .teamCoach:
                TeamCoachView(returnHome: document.closeActiveDocument)
            case .swordShield:
                swordShieldWorkspace
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
                .environment(\.appLanguage, language)
        }
        .onChange(of: document.isImporterPresented) { isPresented in
            guard isPresented else { return }
            document.isImporterPresented = false
            if selectedGame.isEmerald {
                print("[ROM] Open ROM menu command pressed")
                presentOpenPanel(kind: .rom)
            } else {
                presentOpenPanel(kind: .gameDirectory)
            }
        }
        .onChange(of: document.isSaveImporterPresented) { isPresented in
            guard isPresented else { return }
            document.isSaveImporterPresented = false
            guard selectedGame.isEmerald else { return }
            print("[SAVE] Open Save menu command pressed")
            presentOpenPanel(kind: .save)
        }
    }

    private enum OpenPanelKind {
        case rom
        case save
        case gameDirectory
    }

    private func presentOpenPanel(kind: OpenPanelKind) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        switch kind {
        case .rom:
            print("[ROM] Presenting ROM picker")
            panel.allowedContentTypes = [UTType(filenameExtension: "gba") ?? .data]
            panel.begin { response in
                print("[ROM] Picker returned")
                guard response == .OK, let url = panel.url else { return }
                print("[ROM] Selected URL: \(url.path)")
                print("[ROM] Loading ROM")
                document.open(url)
                print("[ROM] ROM loaded")
            }
        case .save:
            print("[SAVE] Presenting Save picker")
            panel.allowedContentTypes = [UTType(filenameExtension: "sav") ?? .data]
            panel.begin { response in
                print("[SAVE] Picker returned")
                guard response == .OK, let url = panel.url else { return }
                print("[SAVE] Selected URL: \(url.path)")
                document.openSave(url)
            }
        case .gameDirectory:
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.message = "Seleziona la cartella contenente RomFS/ExeFS estratti."
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                document.openSwordShieldDump(url, expectedGame: selectedGame)
                swordShieldStatusMessage = document.editorMode == .swordShield ? nil : document.statusMessage
            }
        }
    }

    private var romWorkspace: some View {
        NavigationSplitView {
            ROMSidebarView(selectedSection: $selectedSection)
                .navigationSplitViewColumnWidth(min: EditorLayout.sidebarMinWidth, ideal: EditorLayout.sidebarIdealWidth, max: EditorLayout.sidebarMaxWidth)
        } detail: {
            detailView
        }
    }

    private var saveWorkspace: some View {
        NavigationSplitView {
            SaveSidebarView(selectedSection: $selectedSaveSection)
                .navigationSplitViewColumnWidth(min: EditorLayout.sidebarMinWidth, ideal: EditorLayout.sidebarIdealWidth, max: EditorLayout.sidebarMaxWidth)
        } detail: {
            saveDetailView
        }
    }

    private var swordShieldWorkspace: some View {
        NavigationSplitView {
            SwordShieldSidebarView(selectedSection: $selectedSwordShieldSection)
                .navigationSplitViewColumnWidth(min: EditorLayout.sidebarMinWidth, ideal: EditorLayout.sidebarIdealWidth, max: EditorLayout.sidebarMaxWidth)
        } detail: {
            SwordShieldPlaceholderDetailView(selectedSection: selectedSwordShieldSection)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .pokemon:
            if document.pokemonSpecies.isEmpty {
                PlaceholderView(title: L10n.text("no.pokemon.table", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.species", language: language))
            } else {
                PokemonEditorView(showingHex: Binding(
                    get: { selectedSection == .hex },
                    set: { if $0 { selectedSection = .hex } }
                ))
            }
        case .moves:
            if document.moves.isEmpty {
                PlaceholderView(title: L10n.text("no.moves.table", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.moves", language: language))
            } else {
                MoveEditorView(showingHex: Binding(
                    get: { selectedSection == .hex },
                    set: { if $0 { selectedSection = .hex } }
                ))
            }
        case .trainers:
            if document.trainers.isEmpty {
                PlaceholderView(title: L10n.text("no.trainers", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.trainers", language: language))
            } else {
                TrainerEditorView(showingHex: Binding(
                    get: { selectedSection == .hex },
                    set: { if $0 { selectedSection = .hex } }
                ), requestedTrainerID: $requestedTrainerID, returnToMap: mapTrainerContext == nil ? nil : {
                    selectedSection = .maps
                })
            }
        case .maps:
            if document.maps.isEmpty {
                MapParserDiagnosticView()
            } else {
                MapEditorView(showingHex: Binding(
                    get: { selectedSection == .hex },
                    set: { if $0 { selectedSection = .hex } }
                ), navigationContext: $mapTrainerContext, openTrainer: { trainerID, context in
                    requestedTrainerID = trainerID
                    mapTrainerContext = context
                    selectedSection = .trainers
                })
            }
        case .wildEncounters:
            if document.maps.isEmpty {
                PlaceholderView(title: L10n.text("no.wild.encounters", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.encounters", language: language))
            } else {
                WildEncounterEditorView(showingHex: Binding(
                    get: { selectedSection == .hex },
                    set: { if $0 { selectedSection = .hex } }
                ))
            }
        case .items:
            if document.itemData.isEmpty {
                PlaceholderView(title: L10n.text("no.items", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.items", language: language))
            } else {
                ItemEditorView(showingHex: Binding(
                    get: { selectedSection == .hex },
                    set: { if $0 { selectedSection = .hex } }
                ))
            }
        case .teamCoach:
            if document.pokemonSpecies.isEmpty || document.moves.isEmpty {
                PlaceholderView(title: "Team Coach", systemImage: selectedSection.systemImage, message: L10n.text("open.emerald.species", language: language))
            } else {
                TeamCoachView()
            }
        case .advanced:
            AdvancedROMView()
        case .hex:
            HexWorkspaceView()
        case .texts:
            PlaceholderView(title: L10n.text("coming.soon", language: language), systemImage: selectedSection.systemImage, message: L10n.text("future.section.message", language: language))
        }
    }

    @ViewBuilder
    private var saveDetailView: some View {
        switch selectedSaveSection {
        case .info:
            SaveInfoView()
        case .party:
            PlayerPartyEditorView()
        case .boxes:
            SaveBoxesView()
        case .bag:
            SaveBagView()
        case .trainer:
            SaveTrainerView()
        case .pokedex:
            SavePokedexView()
        case .progression:
            SaveProgressionView()
        case .advanced:
            SaveAdvancedView()
        }
    }
}

private struct ROMSidebarView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var selectedSection: WorkspaceSection

    var body: some View {
        List(selection: $selectedSection) {
            Section("ROM") {
                Label(document.identity.description, systemImage: "gamecontroller.fill")
                LabeledContent(L10n.text("header", language: language), value: document.identity.title)
                LabeledContent(L10n.text("game.code", language: language), value: document.identity.gameCode)
                LabeledContent(L10n.text("maker", language: language), value: document.identity.makerCode)
                if document.isLoaded {
                    LabeledContent(L10n.text("size", language: language), value: ROMDocument.formatSize(document.data.count))
                    LabeledContent(L10n.text("state", language: language), value: document.isDirty ? L10n.text("unsaved.changes", language: language) : L10n.text("saved", language: language))
                    if document.hasVanillaReference {
                        Menu {
                            Button("Mostra nel Finder") { document.revealVanillaReference() }
                            Button("Sostituisci riferimento…") { document.configureVanillaReference() }
                        } label: {
                            Label("Riferimento Vanilla", systemImage: "checkmark.circle")
                        }
                    } else {
                        Button {
                            document.configureVanillaReference()
                        } label: {
                            Label("Configura ROM Vanilla", systemImage: "circle.dashed")
                        }
                    }
                }
            }
            if document.isLoaded {
                Section(L10n.text("editor", language: language)) {
                    ForEach(WorkspaceSection.allCases.filter { $0 != .teamCoach }) { section in
                        Label {
                            HStack {
                                Text(section.title(language: language))
                                if !section.isImplemented {
                                    Spacer()
                                    Text(L10n.text("coming.soon", language: language))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                        .foregroundStyle(section.isImplemented ? .primary : .secondary)
                        .tag(section)
                        .disabled(!section.isImplemented)
                    }
                }
            }
            Section {
                Button {
                    document.closeROM()
                } label: {
                    Label(L10n.text("close.rom", language: language), systemImage: "xmark.circle")
                }
            }
        }
        .navigationTitle("Hex Mania Mac")
        .safeAreaInset(edge: .bottom) {
            Text(document.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.bar)
        }
    }
}

private struct SwordShieldSidebarView: View {
    @EnvironmentObject private var document: ROMDocument
    @Binding var selectedSection: SwordShieldWorkspaceSection

    var body: some View {
        List(selection: $selectedSection) {
            if let session = document.swordShieldSession {
                Section("Gioco") {
                    Label(session.game.displayName, systemImage: "gamecontroller.fill")
                    LabeledContent("Versione", value: session.version)
                    if let titleId = session.titleId {
                        LabeledContent("Title ID", value: titleId)
                    }
                }
            }

            Section("Editor") {
                ForEach(SwordShieldWorkspaceSection.allCases) { section in
                    Label {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text("Non disponibile")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: section.systemImage)
                    }
                    .foregroundStyle(.secondary)
                    .tag(section)
                    .disabled(true)
                }
            }

            Section {
                Button {
                    document.closeSwordShield()
                } label: {
                    Label("Chiudi gioco", systemImage: "xmark.circle")
                }
            }
        }
        .navigationTitle("Hex Mania")
        .safeAreaInset(edge: .bottom) {
            Text(document.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.bar)
        }
    }
}

private struct SwordShieldPlaceholderDetailView: View {
    @EnvironmentObject private var document: ROMDocument
    let selectedSection: SwordShieldWorkspaceSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let session = document.swordShieldSession {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.game.displayName)
                            .font(.largeTitle.weight(.semibold))
                        Text("Versione: \(session.version)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Panel(title: "Dump") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Percorso", value: session.rootURL.path)
                            LabeledContent("RomFS", value: session.romfsURL.path)
                            if let exefsURL = session.exefsURL {
                                LabeledContent("ExeFS", value: exefsURL.path)
                            }
                            if let titleId = session.titleId {
                                LabeledContent("Title ID", value: titleId)
                            }
                        }
                    }

                    Panel(title: selectedSection.title) {
                        Label("Modulo non ancora implementato", systemImage: "wrench.and.screwdriver")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    PlaceholderView(
                        title: "Nessun gioco aperto",
                        systemImage: "exclamationmark.triangle",
                        message: "Apri dati estratti di Pokémon Spada/Scudo dalla Home."
                    )
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(selectedSection.title)
    }
}

private struct AdvancedROMView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(language == .italian ? "AVANZATE" : "ADVANCED")
                    .font(.largeTitle.weight(.semibold))

                Panel(title: "QoL") {
                    VStack(spacing: 12) {
                        ForEach(document.emeraldQoLPatchSummaries) { summary in
                            AdvancedPatchRow(summary: summary)
                        }
                    }
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(language == .italian ? "Avanzate" : "Advanced")
    }
}

private struct AdvancedPatchRow: View {
    @EnvironmentObject private var document: ROMDocument
    let summary: EmeraldQoLPatchSummary

    private var currentStatus: ROMPatchStatus {
        document.emeraldQoLPatchSummaries.first { $0.id == summary.id }?.status ?? summary.status
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.definition.name)
                    .font(.headline)
                Text(summary.definition.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(currentStatus.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())

            Toggle("", isOn: Binding(
                get: { currentStatus == .applied },
                set: { document.setEmeraldQoLPatch(summary.id, enabled: $0) }
            ))
            .labelsHidden()
            .disabled(currentStatus == .incompatible)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch currentStatus {
        case .vanilla:
            .secondary
        case .applied:
            .green
        case .incompatible:
            .orange
        }
    }
}

private struct SaveSidebarView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var selectedSection: SaveWorkspaceSection

    var body: some View {
        List(selection: $selectedSection) {
            if let saveDocument = document.saveDocument {
                Section(L10n.text("save.file", language: language)) {
                    Label(saveDocument.parsed.fileName, systemImage: "externaldrive.fill")
                    LabeledContent(L10n.text("size", language: language), value: ROMDocument.formatSize(saveDocument.data.count))
                    LabeledContent(L10n.text("state", language: language), value: saveStateText(saveDocument))
                    LabeledContent("Checksum", value: saveDocument.parsed.allSectionChecksumsValid ? "OK" : L10n.text("warning", language: language))
                }
            }
            Section(L10n.text("editor", language: language)) {
                ForEach(SaveWorkspaceSection.allCases) { section in
                    Label(section.title(language: language), systemImage: section.systemImage)
                        .tag(section)
                }
            }
            Section {
                Button {
                    document.closeSave()
                } label: {
                    Label(L10n.text("close.save", language: language), systemImage: "xmark.circle")
                }
            }
        }
        .navigationTitle("Hex Mania Save")
        .safeAreaInset(edge: .bottom) {
            Text(document.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.bar)
        }
    }

    private func saveStateText(_ saveDocument: SaveDocument) -> String {
        if saveDocument.isDirty {
            return language == .italian ? "Modificato" : "Modified"
        }
        return language == .italian ? "Salvato" : "Saved"
    }
}

struct MoveEditorView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var showingHex: Bool
    @State private var searchText = ""
    @State private var selectedMoveID: MoveData.ID?
    @State private var onlyModified = false

    private var displayedMoves: [MoveData] {
        document.moves.sorted { lhs, rhs in
            let lhsPlaceholder = isPlaceholderName(lhs.name)
            let rhsPlaceholder = isPlaceholderName(rhs.name)
            if lhsPlaceholder != rhsPlaceholder { return lhsPlaceholder }
            return alphabeticallyAscending(lhs.name, rhs.name, language: language)
        }
    }

    private var filteredMoves: [MoveData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = onlyModified ? displayedMoves.filter { document.isMoveModified($0.id) } : displayedMoves
        guard !query.isEmpty else { return candidates }
        return candidates.filter { move in
            move.name.lowercased().contains(query) || String(move.id).contains(query)
        }
    }

    private var selectedMove: MoveData? {
        guard let selectedMoveID else { return document.moves.first }
        return document.moves.first { $0.id == selectedMoveID }
    }

    var body: some View {
        HStack(spacing: 0) {
            moveList
                .frame(minWidth: EditorLayout.listMinWidth, idealWidth: EditorLayout.listIdealWidth, maxWidth: EditorLayout.listMaxWidth, maxHeight: .infinity)
            Divider()
            detail
                .frame(minWidth: EditorLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear(perform: selectInitialMove)
        .onChange(of: document.moves) { _ in selectInitialMove() }
        .onChange(of: language) { _ in selectInitialMove() }
    }

    @ViewBuilder
    private var detail: some View {
        if let move = selectedMove {
            MoveDetailEditor(
                move: binding(for: move),
                types: document.pokemonTypes,
                showInHex: {
                    document.showMoveInHex(move)
                    showingHex = true
                }
            )
            .id(move.id)
        } else {
            PlaceholderView(title: L10n.text("no.moves.table", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.moves", language: language))
        }
    }

    private var moveList: some View {
        VStack(spacing: 0) {
            TextField(L10n.text("search.moves", language: language), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, EditorLayout.listPadding)
                .padding(.top, EditorLayout.listPadding)
                .padding(.bottom, 8)
            if document.supportsVanillaComparison(.moves) {
                VanillaModifiedFilterToggle(isOn: $onlyModified)
                    .padding(.horizontal, EditorLayout.listPadding)
                    .padding(.bottom, 8)
            }

            List(filteredMoves, selection: $selectedMoveID) { move in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(move.name).font(.body).lineLimit(1)
                        if document.isMoveModified(move.id) { VanillaModifiedIndicator() }
                    }
                    Text("Index #\(move.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .tag(move.id)
            }
        }
        .navigationTitle(L10n.text("moves", language: language))
    }

    private func binding(for move: MoveData) -> Binding<MoveData> {
        Binding {
            document.moves.first { $0.id == move.id } ?? move
        } set: { updatedMove in
            guard document.moves.first(where: { $0.id == updatedMove.id }) != updatedMove else { return }
            document.updateMove(updatedMove)
        }
    }

    private func selectInitialMove() {
        guard !document.moves.isEmpty else {
            selectedMoveID = nil
            return
        }
        if selectedMoveID == nil || !document.moves.contains(where: { $0.id == selectedMoveID }) {
            selectedMoveID = document.moves.first?.id
        }
    }

    private func isPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "--" || trimmed == "Nessuno" || trimmed == "None"
    }
}

private struct MoveDetailEditor: View {
    @Environment(\.appLanguage) private var language
    @Binding var move: MoveData
    let types: [PokemonNamedValue]
    let showInHex: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                EditorCardGrid {
                    Panel(title: L10n.text("battle.data", language: language)) {
                        PickerRow(title: L10n.text("type", language: language), selection: intBinding(\.type), options: typeOptions)
                        NumericRow(L10n.text("power", language: language), value: intBinding(\.power), range: 0...255)
                        NumericRow(L10n.text("accuracy", language: language), value: intBinding(\.accuracy), range: 0...255)
                        NumericRow("PP", value: intBinding(\.pp), range: 0...255)
                        NumericRow(L10n.text("priority", language: language), value: intBinding(\.priority), range: -128...127)
                        NumericRow(L10n.text("effect.chance", language: language), value: intBinding(\.effectChance), range: 0...255)
                    }

                    Panel(title: L10n.text("references", language: language)) {
                        ReadOnlyRow(title: L10n.text("effect.id", language: language), value: "#\(move.effectID)")
                        ReadOnlyRow(title: L10n.text("target", language: language), value: "#\(move.target)")
                        ReadOnlyRow(title: L10n.text("info", language: language), value: "#\(move.info)")
                    }
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(move.name)
    }

    private var header: some View {
        EditorHeaderCard {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text(move.name)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Chip("Index #\(move.id)")
                    Chip(typeName(move.type))
                    Chip("PP \(move.pp)")
                }
                Button(action: showInHex) {
                    Label(L10n.text("show.in.hex", language: language), systemImage: "number")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var typeOptions: [PokemonNamedValue] {
        var result = types
        if !result.contains(where: { $0.id == move.type }) {
            result.append(PokemonNamedValue(id: move.type, name: "Type #\(move.type)"))
        }
        return result.sorted { $0.id < $1.id }
    }

    private func typeName(_ id: Int) -> String {
        typeOptions.first { $0.id == id }?.name ?? "Type #\(id)"
    }

    private func intBinding(_ keyPath: WritableKeyPath<MoveData, Int>) -> Binding<Int> {
        Binding {
            move[keyPath: keyPath]
        } set: { newValue in
            move[keyPath: keyPath] = newValue
        }
    }
}

private struct MapParserDiagnosticView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("maps.unavailable", language: language))
                        .font(.title2.weight(.semibold))
                    Text(document.isLoaded ? L10n.text("cannot.read.maps", language: language) : L10n.text("open.emerald.usa", language: language))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("diagnose.map.parser", language: language)) {
                    document.runMapParserDiagnostic()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!document.isLoaded)
            }

            ScrollView {
                Text(document.mapParsingDiagnostic.isEmpty ? L10n.text("no.diagnostics", language: language) : document.mapParsingDiagnostic)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
        }
        .padding(EditorLayout.detailPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum TrainerNavigationMode: String, CaseIterable { case byArea, byName }
private enum TrainerZoneOrder: String, CaseIterable { case story, alphabetical }
private enum TrainerQuickFilter: String, CaseIterable { case all, land, water, coast, boss, doubles, optional }

private struct TrainerZoneGroup: Identifiable {
    let name: String
    let trainers: [TrainerData]
    let progressionIndex: Int
    var id: String { name }
}

struct TrainerEditorView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var showingHex: Bool
    @Binding var requestedTrainerID: TrainerData.ID?
    let returnToMap: (() -> Void)?
    @State private var searchText = ""
    @State private var selectedTrainerID: TrainerData.ID?
    @State private var trainerLocationIndex = TrainerLocationIndex.empty
    @State private var navigationMode = TrainerNavigationMode.byArea
    @State private var zoneOrder = TrainerZoneOrder.story
    @State private var quickFilter = TrainerQuickFilter.all
    @State private var expandedZones = Set<String>()
    @State private var onlyModified = false

    private var trainerLocationsByID: [Int: [String]] {
        trainerLocationIndex.displayLocationsByTrainerID
    }

    private func unresolvedLocationText() -> String {
        language == .italian ? "Posizione non risolta" : "Unresolved location"
    }

    private var trainerIDs: [TrainerData.ID] {
        document.trainers.map(\.id)
    }

    private func filteredTrainers(locationsByID: [Int: [String]]) -> [TrainerData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<Int>()
        return document.trainers.filter { trainer in
            guard seen.insert(trainer.id).inserted, matchesQuickFilter(trainer) else { return false }
            guard !onlyModified || document.isTrainerModified(trainer.id) else { return false }
            guard !query.isEmpty else { return true }
            return trainer.name.lowercased().contains(query)
                || className(trainer.trainerClass).lowercased().contains(query)
                || String(trainer.id).contains(query)
                || trainer.party.contains { speciesName($0.species).lowercased().contains(query) }
                || (locationsByID[trainer.id] ?? []).contains { $0.lowercased().contains(query) }
        }
        .sorted { alphabeticallyAscending($0.name, $1.name, language: language) }
    }

    private func matchesQuickFilter(_ trainer: TrainerData) -> Bool {
        let reference = trainerLocationIndex.primaryReference(for: trainer.id)
        switch quickFilter {
        case .all: return true
        case .land: return reference?.terrain == .land
        case .water: return reference?.terrain == .water
        case .coast: return reference?.terrain == .coast
        case .boss: return isBoss(trainer)
        case .doubles: return trainer.doubleBattle
        case .optional: return false
        }
    }

    private func isBoss(_ trainer: TrainerData) -> Bool {
        let value = className(trainer.trainerClass).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).uppercased()
        return ["LEADER", "CAPOPALESTRA", "ELITE FOUR", "SUPERQUATTRO", "CHAMPION", "CAMPIONE"].contains { value.contains($0) }
    }

    private func contextLabels(for trainer: TrainerData) -> [String] {
        var labels: [String] = []
        if let reference = trainerLocationIndex.primaryReference(for: trainer.id) {
            switch reference.terrain {
            case .land: labels.append(language == .italian ? "Terra" : "Land")
            case .water: labels.append(language == .italian ? "Acqua" : "Water")
            case .coast: labels.append(language == .italian ? "Costa" : "Coast")
            case .unknown: break
            }
            if reference.requiresSurf { labels.append(language == .italian ? "Richiede Surf" : "Requires Surf") }
        }
        if isBoss(trainer) { labels.append("Boss") }
        if trainer.doubleBattle { labels.append(language == .italian ? "Doppia" : "Double") }
        return labels
    }

    private func zoneGroups(locationsByID: [Int: [String]]) -> [TrainerZoneGroup] {
        Dictionary(grouping: filteredTrainers(locationsByID: locationsByID)) { trainer in
            trainerLocationIndex.primaryReference(for: trainer.id)?.locationName ?? unresolvedLocationText()
        }.map { name, trainers in
            let progression = trainers.compactMap { trainer -> Int? in
                guard let reference = trainerLocationIndex.primaryReference(for: trainer.id) else { return nil }
                return EmeraldStoryProgression.index(for: MapPoint(group: reference.mapGroup, map: reference.mapID))
            }.min() ?? Int.max
            return TrainerZoneGroup(name: name, trainers: trainers, progressionIndex: progression)
        }.sorted { lhs, rhs in
            if zoneOrder == .story, lhs.progressionIndex != rhs.progressionIndex { return lhs.progressionIndex < rhs.progressionIndex }
            return alphabeticallyAscending(lhs.name, rhs.name, language: language)
        }
    }

    private var selectedTrainer: TrainerData? {
        guard let selectedTrainerID else { return document.trainers.first }
        return document.trainers.first { $0.id == selectedTrainerID }
    }

    var body: some View {
        let locationsByID = trainerLocationsByID
        HStack(spacing: 0) {
            trainerList(locationsByID: locationsByID)
                .frame(minWidth: EditorLayout.listMinWidth, idealWidth: EditorLayout.listIdealWidth, maxWidth: EditorLayout.listMaxWidth, maxHeight: .infinity)
            Divider()
            detail(locationsByID: locationsByID)
                .frame(minWidth: EditorLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            applyRequestedTrainerIfNeeded()
            selectInitialTrainer()
            rebuildTrainerLocationIndex()
        }
        .onChange(of: requestedTrainerID) { _ in applyRequestedTrainerIfNeeded() }
        .onChange(of: trainerIDs) { _ in selectInitialTrainer() }
        .onChange(of: document.maps) { _ in rebuildTrainerLocationIndex() }
        .onChange(of: language) { _ in rebuildTrainerLocationIndex() }
    }

    @ViewBuilder
    private func detail(locationsByID: [Int: [String]]) -> some View {
        if let trainer = selectedTrainer {
            TrainerDetailEditor(
                trainer: binding(for: trainer),
                trainerClasses: document.trainerClasses,
                species: document.pokemonSpecies.map { PokemonNamedValue(id: $0.id, name: $0.name) },
                items: document.items,
                moves: document.moves.map { PokemonNamedValue(id: $0.id, name: $0.name) },
                levelUpLearnsets: document.levelUpLearnsets,
                locations: locationsByID[trainer.id] ?? [],
                locationReferences: trainerLocationIndex.referencesByTrainerID[trainer.id] ?? [],
                contextLabels: contextLabels(for: trainer),
                pokemonSpriteProvider: { speciesID in
                    guard let species = document.pokemonSpecies.first(where: { $0.id == speciesID }) else { return nil }
                    return document.pokemonSprite(for: species)
                },
                showTrainerInHex: {
                    document.showTrainerInHex(trainer)
                    showingHex = true
                },
                showPartyInHex: {
                    document.showTrainerPartyInHex(trainer)
                    showingHex = true
                }
            )
        } else {
            PlaceholderView(title: L10n.text("no.trainers", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.trainers", language: language))
        }
    }

    private func trainerList(locationsByID: [Int: [String]]) -> some View {
        VStack(spacing: 0) {
            if let returnToMap {
                Button(action: returnToMap) {
                    Label(language == .italian ? "Torna alla mappa" : "Return to Map", systemImage: "arrow.left")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, EditorLayout.listPadding)
                .padding(.top, EditorLayout.listPadding)
            }
            Picker("", selection: $navigationMode) {
                Text(language == .italian ? "Per zona" : "By Area").tag(TrainerNavigationMode.byArea)
                Text(language == .italian ? "Per nome" : "By Name").tag(TrainerNavigationMode.byName)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, EditorLayout.listPadding)
            .padding(.top, EditorLayout.listPadding)

            TextField(L10n.text("search.trainers", language: language), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, EditorLayout.listPadding)
                .padding(.vertical, 8)

            HStack(spacing: 8) {
                Picker(language == .italian ? "Filtro" : "Filter", selection: $quickFilter) {
                    ForEach(TrainerQuickFilter.allCases, id: \.self) { filter in
                        Text(quickFilterTitle(filter)).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                if navigationMode == .byArea {
                    Picker(language == .italian ? "Ordine" : "Order", selection: $zoneOrder) {
                        Text(language == .italian ? "Storia" : "Story").tag(TrainerZoneOrder.story)
                        Text(language == .italian ? "Alfabetico" : "Alphabetical").tag(TrainerZoneOrder.alphabetical)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                Spacer()
            }
            .padding(.horizontal, EditorLayout.listPadding)
            .padding(.bottom, 8)
            if document.supportsVanillaComparison(.trainers) {
                VanillaModifiedFilterToggle(isOn: $onlyModified)
                    .padding(.horizontal, EditorLayout.listPadding)
                    .padding(.bottom, 8)
            }

            List(selection: $selectedTrainerID) {
                if navigationMode == .byName {
                    ForEach(filteredTrainers(locationsByID: locationsByID)) { trainer in
                        trainerRow(trainer).tag(trainer.id)
                    }
                } else {
                    ForEach(zoneGroups(locationsByID: locationsByID)) { group in
                        DisclosureGroup(isExpanded: zoneExpansionBinding(group.name)) {
                            ForEach(group.trainers) { trainer in
                                trainerRow(trainer).tag(trainer.id)
                            }
                        } label: {
                            HStack {
                                Text(group.name.uppercased()).font(.caption.weight(.semibold))
                                Spacer()
                                Text("\(group.trainers.count)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("trainers", language: language))
    }

    private func quickFilterTitle(_ filter: TrainerQuickFilter) -> String {
        switch filter {
        case .all: language == .italian ? "Tutti" : "All"
        case .land: language == .italian ? "Terra" : "Land"
        case .water: language == .italian ? "Acqua" : "Water"
        case .coast: language == .italian ? "Costa" : "Coast"
        case .boss: "Boss"
        case .doubles: language == .italian ? "Doppie" : "Doubles"
        case .optional: language == .italian ? "Opzionali" : "Optional"
        }
    }

    private func zoneExpansionBinding(_ name: String) -> Binding<Bool> {
        Binding(get: { expandedZones.contains(name) || !searchText.isEmpty }, set: { expanded in
            if expanded { expandedZones.insert(name) } else { expandedZones.remove(name) }
        })
    }

    private func trainerRow(_ trainer: TrainerData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(trainer.name).font(.body).lineLimit(1)
                if document.isTrainerModified(trainer.id) { VanillaModifiedIndicator() }
            }
            Text("\(className(trainer.trainerClass)) • #\(trainer.id)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let summary = partySummary(for: trainer) { Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            let labels = contextLabels(for: trainer)
            if !labels.isEmpty { Text(labels.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.vertical, 2)
    }

    private func binding(for trainer: TrainerData) -> Binding<TrainerData> {
        Binding {
            document.trainers.first { $0.id == trainer.id } ?? trainer
        } set: { updatedTrainer in
            document.updateTrainer(updatedTrainer)
        }
    }

    private func selectInitialTrainer() {
        guard !document.trainers.isEmpty else {
            selectedTrainerID = nil
            return
        }
        if selectedTrainerID == nil || !document.trainers.contains(where: { $0.id == selectedTrainerID }) {
            selectedTrainerID = document.trainers.first?.id
        }
    }

    private func applyRequestedTrainerIfNeeded() {
        guard let requestedTrainerID,
              document.trainers.contains(where: { $0.id == requestedTrainerID }) else { return }
        selectedTrainerID = requestedTrainerID
        self.requestedTrainerID = nil
    }

    private func rebuildTrainerLocationIndex() {
        let newIndex = TrainerLocationResolver(data: document.data, maps: document.maps, language: language).buildIndex()
        trainerLocationIndex = newIndex
        expandedZones.formUnion(newIndex.displayLocationsByTrainerID.values.flatMap { $0 })
    }

    private func className(_ id: Int) -> String {
        document.trainerClasses.first { $0.id == id }?.name ?? "Class #\(id)"
    }

    private func speciesName(_ id: Int) -> String {
        document.pokemonSpecies.first { $0.id == id }?.name ?? "Species #\(id)"
    }

    private func partySummary(for trainer: TrainerData) -> String? {
        guard !trainer.party.isEmpty else { return nil }
        return trainer.party
            .map { "\(L10n.text("lv", language: language)).\($0.level) \(speciesName($0.species))" }
            .joined(separator: " / ")
    }
}

private struct TrainerDetailEditor: View {
    @Environment(\.appLanguage) private var language
    @Binding var trainer: TrainerData
    let trainerClasses: [PokemonNamedValue]
    let species: [PokemonNamedValue]
    let items: [PokemonNamedValue]
    let moves: [PokemonNamedValue]
    let levelUpLearnsets: [Int: [LevelUpMove]]
    let locations: [String]
    let locationReferences: [TrainerLocationReference]
    let contextLabels: [String]
    let pokemonSpriteProvider: (Int) -> NSImage?
    let showTrainerInHex: () -> Void
    let showPartyInHex: () -> Void
    @State private var pendingFormat: TrainerPartyFormat?
    @State private var isFormatConfirmationPresented = false
    @State private var isAIExpanded = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Color.clear
                        .frame(height: 0)
                        .id("trainer-detail-top")
                    header
                    partyPanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    locationPanel
                    aiPanel
                    identityPanel
                }
                .padding(EditorLayout.detailPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: trainer.id) { _ in
                proxy.scrollTo("trainer-detail-top", anchor: .top)
            }
        }
        .navigationTitle(trainer.name)
        .alert(L10n.text("trainer.format.confirm.title", language: language), isPresented: $isFormatConfirmationPresented) {
            Button(L10n.text("cancel", language: language), role: .cancel) { pendingFormat = nil }
            Button(L10n.text("confirm", language: language)) {
                if let pendingFormat {
                    applyFormat(pendingFormat)
                }
                pendingFormat = nil
            }
        } message: {
            Text(L10n.text("trainer.format.confirm.message", language: language))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trainer.name)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 10) {
                Chip("Trainer #\(trainer.id)")
                Chip(className(trainer.trainerClass))
                Chip(trainer.partyFormat.localizedTitle(language: language))
                ForEach(contextLabels, id: \.self) { Chip($0) }
            }
            Text(locationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button(action: showTrainerInHex) {
                    Label(L10n.text("show.trainer.hex", language: language), systemImage: "number")
                }
                Button(action: showPartyInHex) {
                    Label(L10n.text("show.party.hex", language: language), systemImage: "list.bullet.rectangle")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var locationSummary: String {
        let prefix = language == .italian ? "Usato in" : "Used in"
        guard !locations.isEmpty else {
            return "\(prefix): \(language == .italian ? "Posizione non risolta" : "Unresolved location")"
        }
        let text = locations.count <= 2
            ? locations.joined(separator: ", ")
            : "\(locations.prefix(2).joined(separator: ", ")), …"
        return "\(prefix): \(text)"
    }

    private var identityPanel: some View {
        Panel(title: language == .italian ? "Dati tecnici" : "Technical Data") {
            EditorRow(title: L10n.text("trainer.name", language: language)) {
                TextField(L10n.text("trainer.name", language: language), text: Binding(
                    get: { trainer.name },
                    set: { trainer.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            PickerRow(title: L10n.text("trainer.class", language: language), selection: intBinding(\.trainerClass), options: classOptions)
            EditorRow(title: L10n.text("double.battle", language: language)) {
                Toggle("", isOn: Binding(
                    get: { trainer.doubleBattle },
                    set: { trainer.doubleBattle = $0 }
                ))
                .labelsHidden()
            }
            ReadOnlyRow(title: L10n.text("intro.music", language: language), value: "#\(trainer.introMusicAndGender)")
            ReadOnlyRow(title: L10n.text("sprite", language: language), value: "#\(trainer.sprite)")
            ReadOnlyRow(title: L10n.text("party.size", language: language), value: "\(trainer.party.count)")
        }
    }

    private var aiPanel: some View {
        Panel(title: "AI") {
            HStack {
                Text(language == .italian ? "\(activeAIFlagCount) flag attivi" : "\(activeAIFlagCount) active flags")
                    .font(.subheadline)
                Spacer()
                Text("Raw: \(String(format: "0x%08X", trainer.aiFlags))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button(isAIExpanded ? (language == .italian ? "Nascondi dettagli" : "Hide Details") : (language == .italian ? "Mostra dettagli" : "Show Details")) {
                    isAIExpanded.toggle()
                }
                .buttonStyle(.bordered)
            }
            if isAIExpanded {
                Divider()
                ForEach(AIFlagGroup.allCases, id: \.self) { group in
                    Text(group.title(language: language)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Self.aiFlags.filter { $0.group == group }) { flag in aiFlagRow(flag) }
                }
            }
        }
    }

    private var activeAIFlagCount: Int { Self.aiFlags.filter { trainer.aiFlags & (UInt32(1) << UInt32($0.bit)) != 0 }.count }

    private var locationPanel: some View {
        Panel(title: language == .italian ? "Posizione e contesto" : "Location & Context") {
            if let reference = locationReferences.first {
                ReadOnlyRow(title: language == .italian ? "Zona logica" : "Logical area", value: reference.locationName)
                ReadOnlyRow(title: language == .italian ? "Mappa fisica" : "Physical map", value: MapNameResolver.shared.mapName(group: reference.mapGroup, map: reference.mapID, language: language))
                if let x = reference.x, let y = reference.y { ReadOnlyRow(title: language == .italian ? "Coordinate evento" : "Event coordinates", value: "x: \(x), y: \(y)") }
                if !contextLabels.isEmpty { ReadOnlyRow(title: language == .italian ? "Contesto" : "Context", value: contextLabels.joined(separator: " · ")) }
            } else {
                Text(language == .italian ? "Posizione non risolta" : "Unresolved location").foregroundStyle(.secondary)
            }
            if locations.count > 1 { ReadOnlyRow(title: language == .italian ? "Altre associazioni" : "Other associations", value: locations.dropFirst().joined(separator: ", ")) }
        }
    }

    private func aiFlagRow(_ flag: AIFlagInfo) -> some View {
        let mask = UInt32(1) << UInt32(flag.bit)
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                HStack(spacing: 5) {
                    Text(flag.name(language: language))
                        .lineLimit(2)
                    if let help = flag.help(language: language) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(help)
                    }
                }
                .frame(width: 190, alignment: .leading)

                Toggle("", isOn: Binding(
                    get: { trainer.aiFlags & mask != 0 },
                    set: { enabled in
                        if enabled {
                            trainer.aiFlags |= mask
                        } else {
                            trainer.aiFlags &= ~mask
                        }
                    }
                ))
                .labelsHidden()
                .frame(minWidth: EditorLayout.controlMinWidth, maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 28)
    }

    private var partyPanel: some View {
        Panel(title: L10n.text("party", language: language)) {
            formatRow
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10, alignment: .topLeading)], alignment: .leading, spacing: 10) {
                ForEach($trainer.party) { $member in
                    TrainerPartyMemberEditor(
                        member: $member,
                        index: member.id,
                        format: trainer.partyFormat,
                        species: speciesOptions(for: member.species),
                        items: itemOptions(for: member.heldItem),
                        moves: moveOptions(for: member.moves),
                        learnset: learnset(for: member.species),
                        sprite: pokemonSpriteProvider(member.species)
                    )
                }
            }
        }
    }

    private var formatRow: some View {
        @ViewBuilder
        var row: some View {
            if trainer.partyFormat.includesItems {
                ReadOnlyRow(title: L10n.text("format", language: language), value: trainer.partyFormat.localizedTitle(language: language))
            } else {
                EditorRow(title: L10n.text("format", language: language)) {
                    Picker(L10n.text("format", language: language), selection: formatBinding) {
                        Text(TrainerPartyFormat.normal.localizedTitle(language: language)).tag(TrainerPartyFormat.normal)
                        Text(TrainerPartyFormat.moves.localizedTitle(language: language)).tag(TrainerPartyFormat.moves)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        return row
    }

    private var formatBinding: Binding<TrainerPartyFormat> {
        Binding {
            trainer.partyFormat
        } set: { newFormat in
            setFormat(newFormat)
        }
    }

    private func setFormat(_ newFormat: TrainerPartyFormat) {
        guard newFormat != trainer.partyFormat else { return }
        if trainer.partyFormat.includesMoves {
            pendingFormat = newFormat
            isFormatConfirmationPresented = true
        } else {
            applyFormat(newFormat)
        }
    }

    private func applyFormat(_ newFormat: TrainerPartyFormat) {
        guard newFormat != trainer.partyFormat else { return }
        var updated = trainer
        if !newFormat.includesMoves {
            for index in updated.party.indices {
                updated.party[index].moves = [0, 0, 0, 0]
            }
        }
        updated.partyFormat = newFormat
        trainer = updated
    }

    private var classOptions: [PokemonNamedValue] {
        options(trainerClasses, including: [trainer.trainerClass], fallback: "Class")
    }

    private func speciesOptions(for selectedID: Int) -> [PokemonNamedValue] {
        options(species, including: [selectedID], fallback: "Species")
    }

    private func itemOptions(for selectedID: Int) -> [PokemonNamedValue] {
        options(items, including: [selectedID], fallback: "Item", zeroName: L10n.text("none", language: language))
    }

    private func moveOptions(for selectedIDs: [Int]) -> [PokemonNamedValue] {
        var result = moves.filter { $0.id != 0 }
        for id in selectedIDs where id != 0 && !result.contains(where: { $0.id == id }) {
            result.append(PokemonNamedValue(id: id, name: "Move #\(id)"))
        }
        result.sort { alphabeticallyAscending($0.name, $1.name, language: language) }
        return [PokemonNamedValue(id: 0, name: L10n.text("none", language: language))] + result
    }

    private func learnset(for speciesID: Int) -> [LevelUpMove] {
        levelUpLearnsets[speciesID] ?? []
    }

    private func options(_ values: [PokemonNamedValue], including selectedIDs: [Int], fallback: String, zeroName: String? = nil) -> [PokemonNamedValue] {
        var result = values.map { value in
            if value.id == 0, let zeroName {
                PokemonNamedValue(id: value.id, name: zeroName)
            } else {
                value
            }
        }
        if let zeroName, !result.contains(where: { $0.id == 0 }) {
            result.append(PokemonNamedValue(id: 0, name: zeroName))
        }
        for id in selectedIDs where !result.contains(where: { $0.id == id }) {
            result.append(PokemonNamedValue(id: id, name: "\(fallback) #\(id)"))
        }
        return result.sorted { $0.id < $1.id }
    }

    private func className(_ id: Int) -> String {
        classOptions.first { $0.id == id }?.name ?? "Class #\(id)"
    }

    private func intBinding(_ keyPath: WritableKeyPath<TrainerData, Int>) -> Binding<Int> {
        Binding {
            trainer[keyPath: keyPath]
        } set: { newValue in
            trainer[keyPath: keyPath] = newValue
        }
    }

    private static let aiFlags: [AIFlagInfo] = [
        AIFlagInfo(bit: 0, group: .base, englishName: "Check bad move", italianName: "Evita mosse sbagliate", italianHelp: "Evita mosse che fallirebbero o sarebbero chiaramente inefficaci.", englishHelp: "Avoids moves that would fail or be clearly ineffective."),
        AIFlagInfo(bit: 1, group: .base, englishName: "Try to KO", italianName: "Cerca il KO", italianHelp: "Privilegia mosse che possono mandare KO l’avversario.", englishHelp: "Prioritizes moves that can KO the opponent."),
        AIFlagInfo(bit: 2, group: .base, englishName: "Check viability", italianName: "Valuta la mossa migliore", italianHelp: "Confronta l’utilità delle mosse disponibili nel contesto attuale.", englishHelp: "Compares the utility of available moves in the current context."),
        AIFlagInfo(bit: 3, group: .strategy, englishName: "Setup first turn", italianName: "Setup al primo turno", italianHelp: "Favorisce mosse di setup nel primo turno.", englishHelp: "Favors setup moves on the first turn."),
        AIFlagInfo(bit: 4, group: .strategy, englishName: "Risky", italianName: "Strategia rischiosa", italianHelp: "Preferisce opzioni più aggressive o rischiose.", englishHelp: "Prefers more aggressive or risky options."),
        AIFlagInfo(bit: 5, group: .strategy, englishName: "Prefer strongest move", italianName: "Preferisci mosse più forti", italianHelp: "Favorisce mosse che possono chiudere lo scontro rapidamente.", englishHelp: "Favors moves that can end the battle quickly."),
        AIFlagInfo(bit: 6, group: .strategy, englishName: "Prefer Baton Pass", italianName: "Preferisci Baton Pass", italianHelp: "Favorisce strategie basate su Baton Pass e setup.", englishHelp: "Favors strategies based on Baton Pass and setup."),
        AIFlagInfo(bit: 7, group: .context, englishName: "Double battle", italianName: "Logica lotta doppia", italianHelp: "Abilita valutazioni specifiche per le lotte doppie.", englishHelp: "Enables evaluations specific to double battles."),
        AIFlagInfo(bit: 8, group: .context, englishName: "HP aware", italianName: "Considera gli HP", italianHelp: "Modifica le scelte in base agli HP propri e avversari.", englishHelp: "Adjusts choices based on both sides’ HP."),
        AIFlagInfo(bit: 9, group: .context, englishName: "Try Sunny Day", italianName: "Prova Giornodisole", italianHelp: "Favorisce Giornodisole quando previsto dalla strategia.", englishHelp: "Favors Sunny Day when the strategy calls for it."),
        AIFlagInfo(bit: 29, group: .special, englishName: "Roaming", italianName: "Roaming", italianHelp: "Flag speciale usato per incontri roaming.", englishHelp: "Special flag used for roaming encounters."),
        AIFlagInfo(bit: 30, group: .special, englishName: "Safari", italianName: "Safari", italianHelp: "Flag speciale usato nella Zona Safari.", englishHelp: "Special flag used in the Safari Zone."),
        AIFlagInfo(bit: 31, group: .special, englishName: "First battle", italianName: "Prima battaglia", italianHelp: "Flag speciale usato nella prima battaglia prevista dal gioco.", englishHelp: "Special flag used for the game's first battle.")
    ]

    private enum AIFlagGroup: CaseIterable { case base, strategy, context, special
        func title(language: AppLanguage) -> String {
            switch (self, language) {
            case (.base, _): return "BASE"
            case (.strategy, .italian): return "STRATEGIA"
            case (.strategy, .english): return "STRATEGY"
            case (.context, .italian): return "CONTESTO"
            case (.context, .english): return "CONTEXT"
            case (.special, .italian): return "SPECIALI"
            case (.special, .english): return "SPECIAL"
            }
        }
    }

    private struct AIFlagInfo: Identifiable {
        let bit: Int
        let group: AIFlagGroup
        let englishName: String
        let italianName: String
        let italianHelp: String?
        let englishHelp: String?
        var id: Int { bit }

        func name(language: AppLanguage) -> String { language == .italian ? italianName : englishName }

        func help(language: AppLanguage) -> String? {
            switch language {
            case .italian: italianHelp
            case .english: englishHelp
            }
        }
    }

}

private struct TrainerPartyMemberEditor: View {
    @Environment(\.appLanguage) private var language
    @Binding var member: TrainerPartyMember
    let index: Int
    let format: TrainerPartyFormat
    let species: [PokemonNamedValue]
    let items: [PokemonNamedValue]
    let moves: [PokemonNamedValue]
    let learnset: [LevelUpMove]
    let sprite: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let sprite {
                    Image(nsImage: sprite)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(speciesName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("#\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(L10n.text("lv", language: language)) \(member.level)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }

            LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
                CompactPickerRow(title: L10n.text("species", language: language), selection: intBinding(\.species), options: species)
                CompactNumericRow(title: L10n.text("level", language: language), value: intBinding(\.level), range: 1...100)
                CompactNumericRow(title: L10n.text("common.iv", language: language), value: intBinding(\.ivSpread), range: 0...65535)
                if format.includesItems {
                    CompactPickerRow(title: L10n.text("held.item", language: language), selection: intBinding(\.heldItem), options: items)
                }
            }
            if format.includesMoves {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("moves", language: language))
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
                        ForEach(0..<4, id: \.self) { moveIndex in
                            CompactPickerRow(
                                title: "\(L10n.text("move.number", language: language)) \(moveIndex + 1)",
                                selection: moveBinding(moveIndex),
                                options: moves,
                                warningMessage: isMoveAvailableInLearnset(moveIndex) ? nil : L10n.text("move.not.available.at.level", language: language)
                            )
                        }
                    }
                }
            } else {
                Text(L10n.text("automatic.learnset.moves", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
    }

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .topLeading)]
    }

    private var speciesName: String {
        species.first { $0.id == member.species }?.name ?? "Species #\(member.species)"
    }

    private func intBinding(_ keyPath: WritableKeyPath<TrainerPartyMember, Int>) -> Binding<Int> {
        Binding {
            member[keyPath: keyPath]
        } set: { newValue in
            member[keyPath: keyPath] = newValue
        }
    }

    private func moveBinding(_ index: Int) -> Binding<Int> {
        Binding {
            member.moves.indices.contains(index) ? member.moves[index] : 0
        } set: { newValue in
            while member.moves.count <= index {
                member.moves.append(0)
            }
            member.moves[index] = newValue
        }
    }

    private func isMoveAvailableInLearnset(_ moveIndex: Int) -> Bool {
        let moveID = member.moves.indices.contains(moveIndex) ? member.moves[moveIndex] : 0
        guard moveID != 0 else { return true }
        guard !learnset.isEmpty else { return true }
        return learnset.contains { $0.move == moveID && $0.level <= member.level }
    }
}

private struct CompactPickerRow: View {
    let title: String
    @Binding var selection: Int
    let options: [PokemonNamedValue]
    var warningMessage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            if let warningMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(warningMessage)
                    .accessibilityLabel(warningMessage)
            }
        }
        .frame(minHeight: 26)
    }
}

private struct CompactNumericRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            TextField(title, value: clampedValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Stepper(title, value: clampedValue, in: range)
                .labelsHidden()
                .frame(width: EditorLayout.stepperWidth)
        }
        .frame(minHeight: 26)
    }

    private var clampedValue: Binding<Int> {
        Binding {
            value
        } set: { newValue in
            value = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }
}

private enum MapTool: String, CaseIterable, Identifiable {
    case select
    case pencil
    case rectangle
    case fill
    case eyedropper
    case move

    var id: String { rawValue }
    func title(language: AppLanguage) -> String {
        switch self {
        case .select: L10n.text("select", language: language)
        case .pencil: L10n.text("pencil", language: language)
        case .rectangle: L10n.text("rectangle", language: language)
        case .fill: L10n.text("fill", language: language)
        case .eyedropper: L10n.text("eyedropper", language: language)
        case .move: L10n.text("move", language: language)
        }
    }
}

private enum MapUndoAction {
    case blocks(mapID: MapData.ID, before: [MapBlockCell], after: [MapBlockCell])
    case object(mapID: MapData.ID, before: MapObjectEvent, after: MapObjectEvent)
    case warp(mapID: MapData.ID, before: MapWarpEvent, after: MapWarpEvent)
}

private enum MapEventKind {
    case object
    case warp
    case coordinate
    case background
}

private enum CollisionEditProperty: String, CaseIterable, Identifiable {
    case collision
    case elevation

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .collision: L10n.text("collision", language: language)
        case .elevation: L10n.text("elevation", language: language)
        }
    }
}

private enum MapEventDisplayFilter: String, CaseIterable, Identifiable {
    case all
    case trainers
    case items
    case warps
    case others

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all: language == .italian ? "Tutti" : "All"
        case .trainers: language == .italian ? "Allenatori" : "Trainers"
        case .items: language == .italian ? "Oggetti" : "Items"
        case .warps: "Warp"
        case .others: language == .italian ? "NPC / Altri" : "NPC / Others"
        }
    }
}

struct MapEditorView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var showingHex: Bool
    @Binding var navigationContext: MapTrainerNavigationContext?
    let openTrainer: (TrainerData.ID, MapTrainerNavigationContext) -> Void
    @State private var searchText = ""
    @State private var groupFilter = ""
    @State private var selectedMapID: MapData.ID?
    @State private var selectedBlockID: MapBlockCell.ID?
    @State private var selectedObjectID: MapObjectEvent.ID?
    @State private var selectedWarpID: MapWarpEvent.ID?
    @State private var selectedCoordinateID: MapCoordinateEvent.ID?
    @State private var selectedBackgroundID: MapBackgroundEvent.ID?
    @State private var selectedTool: MapTool = .select
    @State private var mode: MapEditorMode = .map
    @State private var selectedMetatile = 1
    @State private var selectedCollision = 0
    @State private var selectedElevation = 3
    @State private var zoom = 1.0
    @State private var showGrid = true
    @State private var showObjects = true
    @State private var showWarps = true
    @State private var showCoordinateEvents = true
    @State private var showBackgroundEvents = true
    @State private var undoStack: [MapUndoAction] = []
    @State private var redoStack: [MapUndoAction] = []
    @State private var rectangleStart: MapBlockCell?
    @State private var strokeMapID: MapData.ID?
    @State private var strokeBefore: [MapBlockCell.ID: MapBlockCell] = [:]
    @State private var strokeAfter: [MapBlockCell.ID: MapBlockCell] = [:]
    @State private var eventRenderCache: MapEventRenderCache?
    @State private var isAdvancedHexExpanded = false
    @State private var isRestoreMapConfirmationPresented = false
    @State private var collisionEditProperty: CollisionEditProperty = .collision
    @State private var showCollisionValues = true
    @State private var showElevationValues = false
    @State private var showBehaviorValues = false
    @State private var onlyModified = false
    @State private var mapOrder = WildEncounterMapOrder.rom
    @State private var eventFilter = MapEventDisplayFilter.all

    private var filteredMaps: [MapData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let group = Int(groupFilter.trimmingCharacters(in: .whitespacesAndNewlines))
        let matches = document.maps.filter { map in
            let matchesGroup = group.map { map.group == $0 } ?? true
            guard matchesGroup else { return false }
            guard !onlyModified || document.isMapModified(map.id) else { return false }
            guard !query.isEmpty else { return true }
            return MapNameResolver.shared.mapName(group: map.group, map: map.mapID, language: language).lowercased().contains(query)
                || "\(map.group).\(map.mapID)".contains(query)
                || "\(map.width)x\(map.height)".contains(query)
        }
        return sortedMaps(matches)
    }

    private var selectedMap: MapData? {
        guard let selectedMapID else { return document.maps.first }
        return document.maps.first { $0.id == selectedMapID }
    }

    private var availableTools: [MapTool] {
        switch mode {
        case .map: [.select, .pencil, .rectangle, .fill, .eyedropper]
        case .collision: [.select, .pencil]
        case .events: [.select, .move]
        }
    }

    private var coordinatesTitle: String {
        language == .italian ? "Coordinate" : "Coordinates"
    }

    var body: some View {
        HSplitView {
            mapList
                .frame(minWidth: 240, idealWidth: EditorLayout.mapListIdealWidth, maxWidth: EditorLayout.mapListMaxWidth, maxHeight: .infinity)
            editor
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            inspector
                .frame(minWidth: 300, idealWidth: EditorLayout.mapInspectorIdealWidth, maxWidth: EditorLayout.mapInspectorMaxWidth, maxHeight: .infinity)
        }
        .onAppear(perform: selectInitialMap)
        .onChange(of: document.maps) { _ in selectInitialMap() }
        .onChange(of: mode) { _ in normalizeToolForMode() }
        .onChange(of: navigationContext) { context in restoreNavigationContext(context) }
        .alert(L10n.text("restore.map.confirm.title", language: language), isPresented: $isRestoreMapConfirmationPresented) {
            Button(L10n.text("cancel", language: language), role: .cancel) {}
            Button(L10n.text("restore", language: language), role: .destructive) {
                restoreSelectedMapToOriginal()
            }
        } message: {
            Text(L10n.text("restore.map.confirm.message", language: language))
        }
    }

    private var mapList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField(L10n.text("search.maps", language: language), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                TextField(L10n.text("map.group", language: language), text: $groupFilter)
                    .textFieldStyle(.roundedBorder)
                if document.supportsVanillaComparison(.maps) || document.supportsVanillaComparison(.encounters) {
                    VanillaModifiedFilterToggle(isOn: $onlyModified)
                }
                HStack(spacing: 8) {
                    Text(language == .italian ? "Ordine" : "Order")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(language == .italian ? "Ordine" : "Order", selection: $mapOrder) {
                        ForEach(WildEncounterMapOrder.allCases) { order in
                            Text(order.title(language: language)).tag(order)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal, EditorLayout.listPadding)
            .padding(.top, EditorLayout.listPadding)
            .padding(.bottom, 8)

            List(filteredMaps, selection: $selectedMapID) { map in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(MapNameResolver.shared.mapName(group: map.group, map: map.mapID, language: language))
                            .font(.body)
                            .lineLimit(2)
                        if document.isMapModified(map.id) { VanillaModifiedIndicator() }
                    }
                    Text("\(map.group).\(map.mapID) • \(map.width)×\(map.height)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .tag(map.id)
            }
        }
        .navigationTitle(L10n.text("maps", language: language))
    }

    @ViewBuilder
    private var editor: some View {
        if let map = selectedMap {
            VStack(spacing: 0) {
                toolbar
                MapCanvasView(
                    map: map,
                    baseImage: document.mapImage(for: map),
                    selectedBlockID: $selectedBlockID,
                    selectedObjectID: selectedObjectID,
                    selectedWarpID: selectedWarpID,
                    selectedCoordinateID: selectedCoordinateID,
                    selectedBackgroundID: selectedBackgroundID,
                    mode: mode,
                    tool: selectedTool,
                    selectedMetatile: selectedMetatile,
                    selectedCollision: selectedCollision,
                    selectedElevation: selectedElevation,
                    zoom: zoom,
                    showGrid: showGrid,
                    showCollisionValues: showCollisionValues,
                    showElevationValues: showElevationValues,
                    showBehaviorValues: showBehaviorValues,
                    showObjects: showObjects,
                    showWarps: showWarps,
                    showCoordinateEvents: showCoordinateEvents,
                    showBackgroundEvents: showBackgroundEvents,
                    onPick: pickBlock,
                    onPaint: paintBlock,
                    onEndPaintStroke: endPaintStroke,
                    onRectangle: rectangleBlock,
                    onFill: fillBlock,
                    onSelectObject: { selectEvent(.object, id: $0) },
                    onSelectWarp: { selectEvent(.warp, id: $0) },
                    onSelectCoordinate: { selectEvent(.coordinate, id: $0) },
                    onSelectBackground: { selectEvent(.background, id: $0) },
                    onMoveObject: moveObject,
                    onMoveWarp: moveWarp,
                    objectSprites: eventRenderCache?.objectSprites ?? [:],
                    importantScriptKeys: eventRenderCache?.importantScriptKeys ?? [],
                    trainerIDsByObjectID: eventRenderCache?.trainerIDsByObjectID ?? [:],
                    modifiedTrainerIDs: document.vanillaChangeSet?.trainerIDs ?? [],
                    trainerComparisonAvailable: document.supportsVanillaComparison(.trainers),
                    eventFilter: eventFilter,
                    onOpenTrainer: openTrainerFromObject
                )
                .onAppear {
                    prepareEventRenderCacheIfNeeded(for: map)
                }
                .onChange(of: mode) { newMode in
                    if newMode == .events {
                        prepareEventRenderCacheIfNeeded(for: map)
                    }
                }
                .onChange(of: map.id) { _ in
                    prepareEventRenderCacheIfNeeded(for: map)
                }
                .onChange(of: eventSignature(for: map)) { _ in
                    prepareEventRenderCacheIfNeeded(for: map)
                }
            }
        } else {
            PlaceholderView(title: L10n.text("no.maps", language: language), systemImage: "map", message: L10n.text("open.emerald.maps", language: language))
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker(L10n.text("mode", language: language), selection: $mode) {
                    ForEach(MapEditorMode.allCases) { mode in Text(mode.localizedTitle(language: language)).tag(mode) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)

                Picker(L10n.text("tool", language: language), selection: $selectedTool) {
                    ForEach(availableTools) { tool in Text(toolbarTitle(for: tool)).tag(tool) }
                }
                .frame(minWidth: 150, maxWidth: 230)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Stepper("\(L10n.text("zoom", language: language)) \(Int(zoom * 100))%", value: $zoom, in: 0.5...4.0, step: 0.25)
                    .fixedSize(horizontal: true, vertical: false)
                Toggle(L10n.text("grid", language: language), isOn: $showGrid)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Button(action: undoMapEdit) { Image(systemName: "arrow.uturn.backward") }
                    .keyboardShortcut("z")
                    .disabled(undoStack.isEmpty)
                Button(action: redoMapEdit) { Image(systemName: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(redoStack.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var inspector: some View {
        if let map = selectedMap {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .map:
                        mapSettingsPanel(map)
                        selectedBlockPanel(map, collisionOnly: false)
                        blockPalettePanel(map)
                        connectionPanel(map)
                        hexPanel(map)
                    case .collision:
                        collisionSelectedPanel(map)
                        collisionEditPanel
                        collisionLegendPanel(map)
                        collisionDisplayPanel
                        advancedHexPanel(map)
                    case .events:
                        eventInspector(map)
                        eventFiltersPanel
                        eventLegendPanel
                        advancedHexPanel(map)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func mapSettingsPanel(_ map: MapData) -> some View {
        Panel(title: L10n.text("map.settings", language: language)) {
            MapInspectorRow(title: L10n.text("name", language: language), value: MapNameResolver.shared.mapName(group: map.group, map: map.mapID, language: language))
            MapInspectorRow(title: L10n.text("group.map", language: language), value: "\(map.group).\(map.mapID)")
            MapInspectorRow(title: L10n.text("size", language: language), value: "\(map.width)x\(map.height)")
            MapInspectorRow(title: L10n.text("music", language: language), value: "#\(map.music)")
            MapInspectorRow(title: L10n.text("layout.id", language: language), value: "#\(map.layoutID)")
            MapInspectorRow(title: L10n.text("region", language: language), value: "\(map.name) (#\(map.regionSectionID))")
            MapInspectorRow(title: L10n.text("weather", language: language), value: "#\(map.weather)")
            MapInspectorRow(title: L10n.text("map.type", language: language), value: "#\(map.mapType)")
            MapInspectorRow(title: L10n.text("battle.type", language: language), value: "#\(map.battleType)")
            MapInspectorRow(title: L10n.text("resize", language: language), value: L10n.text("unsupported.safe.relocation", language: language))
            Divider()
            Button {
                isRestoreMapConfirmationPresented = true
            } label: {
                Label(L10n.text("restore.vanilla", language: language), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private func selectedBlockPanel(_ map: MapData, collisionOnly: Bool) -> some View {
        Panel(title: collisionOnly ? L10n.text("collision", language: language) : L10n.text("block", language: language)) {
            if let block = selectedBlock(in: map) {
                if !collisionOnly, let image = document.mapMetatileImage(for: selectedMetatile, in: map) {
                    HStack(spacing: 10) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .border(.secondary.opacity(0.35))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text("selected.block", language: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("#\(selectedMetatile)")
                                .font(.title3.monospacedDigit())
                        }
                    }
                    .padding(.bottom, 6)
                }
                MapInspectorRow(title: "X", value: "\(block.x)")
                MapInspectorRow(title: "Y", value: "\(block.y)")
                if collisionOnly {
                    MapInspectorRow(title: L10n.text("metatile", language: language), value: "#\(block.metatileID)")
                } else {
                    NumericRow(L10n.text("metatile", language: language), value: Binding(
                        get: { selectedMetatile },
                        set: { selectedMetatile = min(max($0, 0), 0x03FF) }
                    ), range: 0...0x03FF)
                }
                NumericRow(L10n.text("collision", language: language), value: Binding(
                    get: { selectedCollision },
                    set: { selectedCollision = min(max($0, 0), 3) }
                ), range: 0...3)
                NumericRow(L10n.text("elevation", language: language), value: Binding(
                    get: { selectedElevation },
                    set: { selectedElevation = min(max($0, 0), 15) }
                ), range: 0...15)
                MapInspectorRow(title: L10n.text("behavior", language: language), value: L10n.text("none", language: language))
                MapInspectorRow(title: L10n.text("raw", language: language), value: String(format: "0x%04X", block.rawValue))
            } else {
                MapInspectorRow(title: L10n.text("selection", language: language), value: L10n.text("none", language: language))
            }
        }
    }

    private func blockPalettePanel(_ map: MapData) -> some View {
        Panel(title: L10n.text("block.palette", language: language)) {
            MapInspectorRow(title: L10n.text("current", language: language), value: "#\(selectedMetatile)")
            MapBlockPaletteView(
                map: map,
                selectedMetatile: $selectedMetatile,
                imageProvider: { id in document.mapMetatileImage(for: id, in: map) }
            )
            .frame(height: 320)
        }
    }

    private func collisionSelectedPanel(_ map: MapData) -> some View {
        Panel(title: language == .italian ? "Collisione selezionata" : "Selected Collision") {
            if let block = selectedBlock(in: map) {
                MapInspectorRow(title: coordinatesTitle, value: "X \(block.x), Y \(block.y)")
                MapInspectorRow(title: L10n.text("metatile", language: language), value: "#\(block.metatileID)")
                CollisionInfoRow(
                    title: L10n.text("collision", language: language),
                    value: collisionLabel(block.collision),
                    help: collisionHelp
                )
                CollisionInfoRow(
                    title: L10n.text("elevation", language: language),
                    value: elevationLabel(block.elevation),
                    help: elevationHelp
                )
                CollisionInfoRow(
                    title: L10n.text("behavior", language: language),
                    value: language == .italian ? "Non letto da Hex Mania" : "Not read by Hex Mania",
                    help: behaviorHelp
                )
                MapInspectorRow(title: language == .italian ? "Descrizione" : "Description", value: collisionDescription(for: block))
            } else {
                Text(language == .italian ? "Seleziona una cella per ispezionare collisione ed elevazione." : "Select a tile to inspect collision and elevation.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var collisionEditPanel: some View {
        Panel(title: language == .italian ? "Modifica" : "Edit") {
            Picker(language == .italian ? "Proprietà" : "Property", selection: $collisionEditProperty) {
                ForEach(CollisionEditProperty.allCases) { property in
                    Text(property.title(language: language)).tag(property)
                }
            }
            .pickerStyle(.segmented)

            switch collisionEditProperty {
            case .collision:
                Picker(L10n.text("collision", language: language), selection: $selectedCollision) {
                    ForEach(0...3, id: \.self) { value in
                        Text(collisionLabel(value)).tag(value)
                    }
                }
                .help(collisionHelp)
            case .elevation:
                Picker(L10n.text("elevation", language: language), selection: $selectedElevation) {
                    ForEach(0...15, id: \.self) { value in
                        Text(elevationLabel(value)).tag(value)
                    }
                }
                .help(elevationHelp)
            }

            Text(language == .italian ? "Usa Select per ispezionare. Usa Modifica/Matita per scrivere solo la proprietà scelta." : "Use Select to inspect. Use Edit/Pencil to write only the chosen property.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func collisionLegendPanel(_ map: MapData) -> some View {
        let collisions = Array(Set(map.blocks.map(\.collision))).sorted()
        let elevations = Array(Set(map.blocks.map(\.elevation))).sorted()

        return Panel(title: language == .italian ? "Legenda collisioni" : "Collision Legend") {
            Text(L10n.text("collision", language: language))
                .font(.subheadline.weight(.semibold))
            ForEach(collisions, id: \.self) { value in
                LegendValueRow(value: "\(value)", title: collisionLabel(value), description: collisionLegendDescription(value))
            }

            Divider()

            Text(L10n.text("elevation", language: language))
                .font(.subheadline.weight(.semibold))
            ForEach(elevations, id: \.self) { value in
                LegendValueRow(value: "\(value)", title: elevationLabel(value), description: elevationLegendDescription(value))
            }

            Divider()

            LegendValueRow(
                value: "-",
                title: L10n.text("behavior", language: language),
                description: language == .italian ? "Separato da collisione/elevazione nei dati Emerald, ma non esposto dal parser attuale." : "Separate from collision/elevation in Emerald data, but not exposed by the current parser."
            )
        }
    }

    private var collisionDisplayPanel: some View {
        Panel(title: language == .italian ? "Visualizzazione" : "Display") {
            Toggle(L10n.text("collision", language: language), isOn: $showCollisionValues)
            Toggle(L10n.text("elevation", language: language), isOn: $showElevationValues)
            Toggle(L10n.text("behavior", language: language), isOn: $showBehaviorValues)
            Text(language == .italian ? "Cambiare overlay modifica solo il rendering." : "Changing overlays only affects rendering.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eventFiltersPanel: some View {
        Panel(title: L10n.text("event.filters", language: language)) {
            Picker(language == .italian ? "Categoria" : "Category", selection: $eventFilter) {
                ForEach(MapEventDisplayFilter.allCases) { filter in
                    Text(filter.title(language: language)).tag(filter)
                }
            }
            .pickerStyle(.menu)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                Toggle("NPC", isOn: $showObjects)
                Toggle(L10n.text("warp", language: language), isOn: $showWarps)
                Toggle(L10n.text("trigger", language: language), isOn: $showCoordinateEvents)
                Toggle(L10n.text("background", language: language), isOn: $showBackgroundEvents)
            }
            .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private func eventInspector(_ map: MapData) -> some View {
        if let objectID = selectedObjectID, let object = map.objects.first(where: { $0.id == objectID }) {
            let objectAnalysis = cachedScriptAnalysis(pointer: object.scriptPointer, eventType: "Object")
            let isProtected = objectAnalysis.isImportant
            Panel(title: L10n.text("selected.event", language: language)) {
                if let sprite = eventRenderCache?.objectSprites[object.id] ?? document.objectEventSprite(for: object) {
                    HStack(spacing: 10) {
                        Image(nsImage: sprite)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 96)
                            .border(.secondary.opacity(0.35))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sprite #\(object.graphicsID)")
                                .font(.headline)
                            Text("Object #\(object.localID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 6)
                }
                if isProtected {
                    MapInspectorRow(title: L10n.text("protection", language: language), value: L10n.text("protected.event.message", language: language))
                }
                MapInspectorRow(title: L10n.text("type", language: language), value: L10n.text("npc.object", language: language))
                MapInspectorRow(title: L10n.text("local.id", language: language), value: "#\(object.localID)")
                MapInspectorRow(title: coordinatesTitle, value: "X \(object.x), Y \(object.y), Z \(object.elevation)")
                MapInspectorRow(title: L10n.text("sprite", language: language), value: "#\(object.graphicsID)")
                MapInspectorRow(title: L10n.text("movement", language: language), value: "\(movementTypeName(object.movementType)) (#\(object.movementType))")
                MapInspectorRow(title: language == .italian ? "Raggio movimento" : "Movement range", value: "X \(object.movementRangeX), Y \(object.movementRangeY)")
                MapInspectorRow(title: L10n.text("trainer.type", language: language), value: "#\(object.trainerType)")
                if object.trainerType != 0 {
                    MapInspectorRow(title: language == .italian ? "Raggio visivo" : "Sight range", value: "\(object.trainerRangeOrBerryID)")
                }
                let trainerLinks = Dictionary(grouping: document.trainerLinks(for: object), by: \.trainerID)
                    .values.compactMap(\.first).sorted { $0.trainerID < $1.trainerID }
                if trainerLinks.count == 1, let link = trainerLinks.first {
                    trainerSummary(link: link, object: object, map: map)
                    MapInspectorRow(title: "Script offset", value: String(format: "0x%08X", link.scriptOffset))
                } else if trainerLinks.count > 1 {
                    Divider()
                    Text(language == .italian ? "Allenatori associati" : "Linked Trainers").font(.headline)
                    ForEach(trainerLinks, id: \.trainerID) { link in
                        if let trainer = document.trainers.first(where: { $0.id == link.trainerID }) {
                            Button("\(trainer.name) · #\(trainer.id)") {
                                openTrainer(trainer.id, MapTrainerNavigationContext(mapID: map.id, objectID: object.id))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else if object.trainerType != 0 {
                    MapInspectorRow(title: L10n.text("trainer", language: language), value: L10n.text("trainer.metadata.unresolved", language: language))
                }
                MapInspectorRow(title: L10n.text("script", language: language), value: String(format: "0x%08X", object.scriptPointer))
                MapInspectorRow(title: L10n.text("flag", language: language), value: "#\(object.flag)")
                eventScriptSummary(objectAnalysis)
            }
        } else if let warpID = selectedWarpID, let warp = map.warps.first(where: { $0.id == warpID }) {
            Panel(title: L10n.text("selected.event", language: language)) {
                MapInspectorRow(title: L10n.text("type", language: language), value: L10n.text("warp", language: language))
                MapInspectorRow(title: L10n.text("index", language: language), value: "#\(warp.id)")
                MapInspectorRow(title: coordinatesTitle, value: "X \(warp.x), Y \(warp.y), Z \(warp.elevation)")
                MapInspectorRow(title: L10n.text("warp.id", language: language), value: "#\(warp.warpID)")
                MapInspectorRow(title: L10n.text("destination", language: language), value: "\(destinationName(group: warp.destinationGroup, mapID: warp.destinationMap)) (\(warp.destinationGroup).\(warp.destinationMap))")
                Button(L10n.text("go.destination", language: language)) {
                    selectedMapID = "\(warp.destinationGroup)-\(warp.destinationMap)"
                }
                .buttonStyle(.bordered)
            }
        } else if let coordinateID = selectedCoordinateID, let event = map.coordinateEvents.first(where: { $0.id == coordinateID }) {
            let analysis = cachedScriptAnalysis(pointer: event.scriptPointer, eventType: "Coordinate")
            Panel(title: L10n.text("selected.event", language: language)) {
                MapInspectorRow(title: L10n.text("type", language: language), value: L10n.text("trigger", language: language))
                MapInspectorRow(title: L10n.text("index", language: language), value: "#\(event.id)")
                MapInspectorRow(title: coordinatesTitle, value: "X \(event.x), Y \(event.y), Z \(event.elevation)")
                MapInspectorRow(title: L10n.text("trigger.var", language: language), value: "#\(event.trigger)")
                MapInspectorRow(title: L10n.text("value", language: language), value: "#\(event.index)")
                MapInspectorRow(title: L10n.text("script", language: language), value: String(format: "0x%08X", event.scriptPointer))
                eventScriptSummary(analysis)
            }
        } else if let backgroundID = selectedBackgroundID, let event = map.backgroundEvents.first(where: { $0.id == backgroundID }) {
            let analysis = cachedScriptAnalysis(pointer: event.argument, eventType: "Background")
            Panel(title: L10n.text("selected.event", language: language)) {
                MapInspectorRow(title: L10n.text("type", language: language), value: event.kind == 7 ? (language == .italian ? "Oggetto nascosto" : "Hidden Item") : L10n.text("background.event", language: language))
                MapInspectorRow(title: L10n.text("index", language: language), value: "#\(event.id)")
                MapInspectorRow(title: coordinatesTitle, value: "X \(event.x), Y \(event.y), Z \(event.elevation)")
                MapInspectorRow(title: L10n.text("kind", language: language), value: "#\(event.kind)")
                MapInspectorRow(title: L10n.text("script.data", language: language), value: String(format: "0x%08X", event.argument))
                eventScriptSummary(analysis)
            }
        } else {
            mapSettingsPanel(map)
        }
    }

    @ViewBuilder
    private func trainerSummary(link: MapObjectTrainerLink, object: MapObjectEvent, map: MapData) -> some View {
        if let trainer = document.trainers.first(where: { $0.id == link.trainerID }) {
            Divider()
            Text(language == .italian ? "Allenatore" : "Trainer")
                .font(.headline)
            MapInspectorRow(title: L10n.text("name", language: language), value: trainer.name)
            MapInspectorRow(title: language == .italian ? "Classe" : "Class", value: document.trainerClasses.first(where: { $0.id == trainer.trainerClass })?.name ?? "#\(trainer.trainerClass)")
            MapInspectorRow(title: "Trainer ID", value: "#\(trainer.id)")
            MapInspectorRow(title: language == .italian ? "Squadra" : "Party", value: "\(trainer.party.count) Pokémon")
            ForEach(trainer.party) { member in
                MapInspectorRow(
                    title: "Lv. \(member.level)",
                    value: document.pokemonSpecies.first(where: { $0.id == member.species })?.name ?? "Pokémon #\(member.species)"
                )
            }
            MapInspectorRow(
                title: "Vanilla",
                value: document.supportsVanillaComparison(.trainers)
                    ? (document.isTrainerModified(trainer.id) ? "Modificato" : "Vanilla")
                    : "Non verificabile"
            )
            Button {
                openTrainer(trainer.id, MapTrainerNavigationContext(mapID: map.id, objectID: object.id))
            } label: {
                Label(language == .italian ? "Apri in Allenatori" : "Open in Trainers", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
        } else {
            MapInspectorRow(title: L10n.text("trainer", language: language), value: "#\(link.trainerID) — non presente nella tabella")
        }
    }

    private var eventLegendPanel: some View {
        Panel(title: language == .italian ? "Legenda" : "Legend") {
            EventLegendRow(color: .blue, symbol: "T", title: language == .italian ? "Allenatore Vanilla" : "Vanilla Trainer", description: language == .italian ? "Allenatore identificato e invariato" : "Identified, unchanged trainer")
            EventLegendRow(color: .orange, symbol: "T", title: language == .italian ? "Allenatore modificato" : "Modified Trainer", description: language == .italian ? "Dati o squadra differenti dal riferimento Vanilla" : "Data or party differs from the Vanilla reference")
            EventLegendRow(color: .secondary, symbol: "?", title: language == .italian ? "Stato sconosciuto" : "Unknown Status", description: language == .italian ? "Confronto Vanilla non disponibile" : "Vanilla comparison unavailable")
            EventLegendRow(color: .orange, symbol: "N", title: "NPC", description: language == .italian ? "Personaggio o oggetto sulla mappa" : "Character or object on the map")
            EventLegendRow(color: .yellow, symbol: "O", title: language == .italian ? "Oggetto" : "Item", description: language == .italian ? "Oggetto nascosto identificato" : "Identified hidden item")
            EventLegendRow(color: .blue, symbol: "W", title: "Warp", description: language == .italian ? "Passaggio verso un'altra mappa" : "Passage to another map")
            EventLegendRow(color: .green, symbol: "T", title: L10n.text("trigger", language: language), description: language == .italian ? "Script attivato entrando su una casella" : "Script triggered by stepping on a tile")
            EventLegendRow(color: .purple, symbol: "i", title: L10n.text("background", language: language), description: language == .italian ? "Cartelli, punti interagibili o eventi di posizione" : "Signs, interactive spots, or position events")
        }
    }

    @ViewBuilder
    private func eventScriptSummary(_ analysis: MapScriptAnalysis) -> some View {
        MapInspectorRow(title: L10n.text("classification", language: language), value: analysis.classification.rawValue)
        if let offset = analysis.scriptOffset {
            MapInspectorRow(title: L10n.text("offset", language: language), value: String(format: "0x%08X", offset))
        }
        if !analysis.flags.isEmpty {
            MapInspectorRow(title: L10n.text("flags", language: language), value: analysis.flags.map { "#\($0)" }.joined(separator: ", "))
        }
        if !analysis.variables.isEmpty {
            MapInspectorRow(title: L10n.text("vars", language: language), value: analysis.variables.map { "#\($0)" }.joined(separator: ", "))
        }
    }

    private func toolbarTitle(for tool: MapTool) -> String {
        if mode == .collision, tool == .pencil {
            return language == .italian ? "Modifica" : "Edit"
        }
        return tool.title(language: language)
    }

    private var collisionHelp: String {
        language == .italian
            ? "Determina se la cella può essere attraversata."
            : "Determines whether the tile can be crossed."
    }

    private var elevationHelp: String {
        language == .italian
            ? "Indica il livello/altezza logica usata per passaggi e sovrapposizioni."
            : "Indicates the logical level/height used for passages and overlaps."
    }

    private var behaviorHelp: String {
        language == .italian
            ? "Definisce proprietà speciali del metatile, come erba, acqua, warp o movimenti forzati."
            : "Defines special metatile properties such as grass, water, warps, or forced movement."
    }

    private func collisionLabel(_ value: Int) -> String {
        switch value {
        case 0:
            language == .italian ? "Base / attraversabile (0)" : "Base / passable (0)"
        case 3:
            language == .italian ? "Impassabile (3)" : "Impassable (3)"
        default:
            language == .italian ? "Sconosciuto / non documentato (#\(value))" : "Unknown / undocumented (#\(value))"
        }
    }

    private func collisionLegendDescription(_ value: Int) -> String {
        switch value {
        case 0:
            language == .italian ? "Nessun bit di collisione impostato nel blocco mappa." : "No collision bits set in the map grid block."
        case 3:
            language == .italian ? "Tutti i bit di collisione impostati; Emerald lo usa per blocchi impassabili." : "All collision bits set; Emerald uses this for impassable blocks."
        default:
            language == .italian ? "Valore valido nel campo a 2 bit, ma senza significato documentato qui." : "Valid 2-bit field value, but no documented meaning here."
        }
    }

    private func elevationLabel(_ value: Int) -> String {
        switch value {
        case 0:
            language == .italian ? "Transizione (0)" : "Transition (0)"
        case 1:
            language == .italian ? "Surf (1)" : "Surf (1)"
        case 3:
            language == .italian ? "Predefinita (3)" : "Default (3)"
        case 15:
            language == .italian ? "Multi-livello (15)" : "Multi-level (15)"
        default:
            language == .italian ? "Sconosciuta / non documentata (#\(value))" : "Unknown / undocumented (#\(value))"
        }
    }

    private func elevationLegendDescription(_ value: Int) -> String {
        switch value {
        case 0:
            language == .italian ? "Valore Emerald per transizioni di elevazione." : "Emerald value for elevation transitions."
        case 1:
            language == .italian ? "Valore Emerald usato per superfici surfabili." : "Emerald value used for surf surfaces."
        case 3:
            language == .italian ? "Elevazione predefinita più comune nei blocchi normali." : "Default elevation commonly used by normal blocks."
        case 15:
            language == .italian ? "Valore Emerald per blocchi multi-livello." : "Emerald value for multi-level blocks."
        default:
            language == .italian ? "Valore presente nella mappa, ma non documentato nel riferimento usato." : "Value present in the map, but not documented in the reference used."
        }
    }

    private func collisionDescription(for block: MapBlockCell) -> String {
        let behavior = language == .italian ? "Behavior non disponibile nel parser attuale." : "Behavior is not available in the current parser."
        return "\(collisionLabel(block.collision)); \(elevationLabel(block.elevation)). \(behavior)"
    }

    private func connectionPanel(_ map: MapData) -> some View {
        Panel(title: L10n.text("connections", language: language)) {
            if map.connections.isEmpty {
                ReadOnlyRow(title: L10n.text("connections", language: language), value: L10n.text("none", language: language))
            } else {
                ForEach(map.connections) { connection in
                    EditorRow(title: connection.directionName) {
                        Button("\(destinationName(group: connection.targetGroup, mapID: connection.targetMap)) · offset \(connection.offsetValue)") {
                            selectedMapID = "\(connection.targetGroup)-\(connection.targetMap)"
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private func scriptStoryPanel(_ analysis: MapScriptAnalysis) -> some View {
        Panel(title: L10n.text("story.script", language: language)) {
            ReadOnlyRow(title: L10n.text("type", language: language), value: analysis.eventType)
            ReadOnlyRow(title: L10n.text("classification", language: language), value: analysis.classification.rawValue)
            ReadOnlyRow(title: L10n.text("pointer", language: language), value: String(format: "0x%08X", analysis.pointer))
            ReadOnlyRow(title: L10n.text("offset", language: language), value: analysis.scriptOffset.map { String(format: "0x%08X", $0) } ?? "n/a")
            ReadOnlyRow(title: L10n.text("flags", language: language), value: analysis.flags.isEmpty ? "-" : analysis.flags.map { "#\($0)" }.joined(separator: ", "))
            ReadOnlyRow(title: L10n.text("vars", language: language), value: analysis.variables.isEmpty ? "-" : analysis.variables.map { "#\($0)" }.joined(separator: ", "))
            ReadOnlyRow(title: L10n.text("commands", language: language), value: analysis.commands.isEmpty ? "-" : analysis.commands.joined(separator: ", "))
            ReadOnlyRow(title: L10n.text("reason", language: language), value: analysis.reason)
        }
    }

    private func hexPanel(_ map: MapData) -> some View {
        Panel(title: "Hex") {
            Button(L10n.text("show.map.header.hex", language: language)) {
                document.showMapHeaderInHex(map)
                showingHex = true
            }
            Button(L10n.text("show.layout.hex", language: language)) {
                document.showMapLayoutInHex(map)
                showingHex = true
            }
            Button(L10n.text("show.event.data.hex", language: language)) {
                document.showMapEventsInHex(map)
                showingHex = true
            }
            Button(L10n.text("show.tileset.hex", language: language)) {
                document.showMapTilesetInHex(map)
                showingHex = true
            }
        }
    }

    private func advancedHexPanel(_ map: MapData) -> some View {
        Panel(title: language == .italian ? "Avanzate / Hex" : "Advanced / Hex") {
            DisclosureGroup(isExpanded: $isAdvancedHexExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(L10n.text("show.map.header.hex", language: language)) {
                        document.showMapHeaderInHex(map)
                        showingHex = true
                    }
                    Button(L10n.text("show.layout.hex", language: language)) {
                        document.showMapLayoutInHex(map)
                        showingHex = true
                    }
                    Button(L10n.text("show.event.data.hex", language: language)) {
                        document.showMapEventsInHex(map)
                        showingHex = true
                    }
                    Button(L10n.text("show.tileset.hex", language: language)) {
                        document.showMapTilesetInHex(map)
                        showingHex = true
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(language == .italian ? "Strumenti Hex" : "Hex tools")
            }
        }
    }

    private func pickBlock(_ block: MapBlockCell) {
        selectedBlockID = block.id
        selectedMetatile = block.metatileID
        selectedCollision = block.collision
        selectedElevation = block.elevation
    }

    private func paintBlock(_ block: MapBlockCell) {
        let start = MapEditProfiler.now()
        defer { MapEditProfiler.log("view paint dispatch", since: start) }
        guard let map = selectedMap else { return }
        switch selectedTool {
        case .select, .move:
            pickBlock(block)
        case .eyedropper:
            pickBlock(block)
        case .fill:
            endPaintStroke()
            fillBlock(block)
        case .rectangle:
            endPaintStroke()
            rectangleBlock(block)
        case .pencil:
            let updated = updatedBlock(from: block)
            applyPencilEdit(before: block, after: updated, in: map)
        }
    }

    private func applyPencilEdit(before block: MapBlockCell, after updated: MapBlockCell, in map: MapData) {
        guard block != updated else { return }
        if strokeMapID != map.id {
            endPaintStroke()
            strokeMapID = map.id
        }
        if strokeBefore[block.id] == nil {
            strokeBefore[block.id] = block
        }
        strokeAfter[block.id] = updated
        document.updateMapBlocks([updated], in: map)
        selectedBlockID = updated.id
    }

    private func endPaintStroke() {
        guard let mapID = strokeMapID, !strokeBefore.isEmpty else {
            strokeMapID = nil
            strokeBefore.removeAll()
            strokeAfter.removeAll()
            return
        }
        let before = strokeBefore.values.sorted { $0.offset < $1.offset }
        let after = before.compactMap { strokeAfter[$0.id] }
        if before != after {
            undoStack.append(.blocks(mapID: mapID, before: before, after: after))
            redoStack.removeAll()
        }
        strokeMapID = nil
        strokeBefore.removeAll()
        strokeAfter.removeAll()
    }

    private func rectangleBlock(_ block: MapBlockCell) {
        guard let map = selectedMap else { return }
        if rectangleStart == nil {
            rectangleStart = block
            selectedBlockID = block.id
            return
        }
        guard let start = rectangleStart else { return }
        let xRange = min(start.x, block.x)...max(start.x, block.x)
        let yRange = min(start.y, block.y)...max(start.y, block.y)
        let before = map.blocks.filter { xRange.contains($0.x) && yRange.contains($0.y) }
        let after = before.map(updatedBlock)
        applyBlockEdits(before, after, in: map)
        rectangleStart = nil
    }

    private func fillBlock(_ block: MapBlockCell) {
        guard let map = selectedMap else { return }
        var visited = Set<MapBlockCell.ID>()
        var queue = [block]
        var before: [MapBlockCell] = []
        while let current = queue.popLast(), !visited.contains(current.id) {
            visited.insert(current.id)
            let matchesTarget = mode == .collision
                ? current.collision == block.collision && current.elevation == block.elevation
                : current.metatileID == block.metatileID
            guard matchesTarget else { continue }
            before.append(current)
            for neighbor in neighbors(of: current, in: map) where !visited.contains(neighbor.id) {
                queue.append(neighbor)
            }
        }
        let after = before.map(updatedBlock)
        applyBlockEdits(before, after, in: map)
    }

    private func applyBlockEdits(_ before: [MapBlockCell], _ after: [MapBlockCell], in map: MapData) {
        guard !before.isEmpty, before != after else { return }
        undoStack.append(.blocks(mapID: map.id, before: before, after: after))
        redoStack.removeAll()
        document.updateMapBlocks(after, in: map)
        selectedBlockID = after.last?.id
    }

    private func undoMapEdit() {
        endPaintStroke()
        guard let action = undoStack.popLast() else { return }
        redoStack.append(action)
        switch action {
        case .blocks(let mapID, let before, _):
            guard let map = document.maps.first(where: { $0.id == mapID }) else { return }
            document.updateMapBlocks(before, in: map)
        case .object(let mapID, let before, _):
            guard let map = document.maps.first(where: { $0.id == mapID }) else { return }
            document.updateMapObject(before, in: map)
        case .warp(let mapID, let before, _):
            guard let map = document.maps.first(where: { $0.id == mapID }) else { return }
            document.updateMapWarp(before, in: map)
        }
    }

    private func redoMapEdit() {
        endPaintStroke()
        guard let action = redoStack.popLast() else { return }
        undoStack.append(action)
        switch action {
        case .blocks(let mapID, _, let after):
            guard let map = document.maps.first(where: { $0.id == mapID }) else { return }
            document.updateMapBlocks(after, in: map)
        case .object(let mapID, _, let after):
            guard let map = document.maps.first(where: { $0.id == mapID }) else { return }
            document.updateMapObject(after, in: map)
        case .warp(let mapID, _, let after):
            guard let map = document.maps.first(where: { $0.id == mapID }) else { return }
            document.updateMapWarp(after, in: map)
        }
    }

    private func restoreSelectedMapToOriginal() {
        endPaintStroke()
        guard let map = selectedMap else { return }
        document.restoreOriginalMap(map)
        undoStack.removeAll()
        redoStack.removeAll()
        clearEventSelection()
        selectedBlockID = nil
        rectangleStart = nil
        eventRenderCache = nil
    }

    private func updatedBlock(from block: MapBlockCell) -> MapBlockCell {
        var updated = block
        switch mode {
        case .map:
            updated.metatileID = selectedMetatile
        case .collision:
            switch collisionEditProperty {
            case .collision:
                updated.collision = selectedCollision
            case .elevation:
                updated.elevation = selectedElevation
            }
        case .events:
            break
        }
        return updated
    }

    private func neighbors(of block: MapBlockCell, in map: MapData) -> [MapBlockCell] {
        [(block.x - 1, block.y), (block.x + 1, block.y), (block.x, block.y - 1), (block.x, block.y + 1)]
            .compactMap { x, y in map.blocks.first { $0.x == x && $0.y == y } }
    }

    private func selectedBlock(in map: MapData) -> MapBlockCell? {
        guard let selectedBlockID else { return nil }
        return map.blocks.first { $0.id == selectedBlockID }
    }

    private func objectBinding(_ object: MapObjectEvent, in map: MapData, _ keyPath: WritableKeyPath<MapObjectEvent, Int>) -> Binding<Int> {
        Binding {
            document.maps.first(where: { $0.id == map.id })?.objects.first(where: { $0.id == object.id })?[keyPath: keyPath] ?? object[keyPath: keyPath]
        } set: { newValue in
            guard var updated = document.maps.first(where: { $0.id == map.id })?.objects.first(where: { $0.id == object.id }) else { return }
            updated[keyPath: keyPath] = newValue
            document.updateMapObject(updated, in: map)
        }
    }

    private func trainerBinding(_ trainer: TrainerData) -> Binding<TrainerData> {
        Binding {
            document.trainers.first { $0.id == trainer.id } ?? trainer
        } set: { updatedTrainer in
            document.updateTrainer(updatedTrainer)
        }
    }

    private func warpBinding(_ warp: MapWarpEvent, in map: MapData, _ keyPath: WritableKeyPath<MapWarpEvent, Int>) -> Binding<Int> {
        Binding {
            document.maps.first(where: { $0.id == map.id })?.warps.first(where: { $0.id == warp.id })?[keyPath: keyPath] ?? warp[keyPath: keyPath]
        } set: { newValue in
            guard var updated = document.maps.first(where: { $0.id == map.id })?.warps.first(where: { $0.id == warp.id }) else { return }
            updated[keyPath: keyPath] = newValue
            document.updateMapWarp(updated, in: map)
        }
    }

    private func destinationName(group: Int, mapID: Int) -> String {
        MapNameResolver.shared.mapName(group: group, map: mapID, language: language)
    }

    private func trainerClassName(_ id: Int) -> String {
        document.trainerClasses.first(where: { $0.id == id })?.name ?? "Class #\(id)"
    }

    private func speciesName(_ id: Int) -> String {
        document.pokemonSpecies.first(where: { $0.id == id })?.name ?? "Species #\(id)"
    }

    private func moveName(_ id: Int) -> String {
        guard id != 0 else { return "-" }
        return document.moves.first(where: { $0.id == id })?.name ?? "Move #\(id)"
    }

    private func itemName(_ id: Int) -> String {
        guard id != 0 else { return "-" }
        return document.items.first(where: { $0.id == id })?.name ?? "Item #\(id)"
    }

    private func movementTypeName(_ id: Int) -> String {
        switch id {
        case 0x00: "None"
        case 0x01: "Look around"
        case 0x02: "Wander around"
        case 0x03: "Wander up/down"
        case 0x04: "Wander left/right"
        case 0x05: "Face up"
        case 0x06: "Face down"
        case 0x07: "Face left"
        case 0x08: "Face right"
        case 0x09: "Player"
        case 0x0A: "Berry tree growth"
        case 0x0B: "Face down/up and left/right"
        case 0x0C: "Face down/up and right/left"
        case 0x0D: "Face up/down and left/right"
        case 0x0E: "Face up/down and right/left"
        case 0x0F: "Walk sequence up/right/left/down"
        case 0x10: "Walk sequence right/left/down/up"
        case 0x11: "Walk sequence down/up/right/left"
        case 0x12: "Walk sequence left/down/up/right"
        case 0x13: "Walk sequence up/left/right/down"
        case 0x14: "Walk sequence left/right/down/up"
        case 0x15: "Walk sequence down/up/left/right"
        case 0x16: "Walk sequence right/down/up/left"
        case 0x17: "Copy player"
        case 0x18: "Copy player opposite"
        case 0x19: "Copy player counterclockwise"
        case 0x1A: "Copy player clockwise"
        case 0x1B: "Tree disguise"
        case 0x1C: "Mountain disguise"
        case 0x1D: "Copy player in grass"
        case 0x1E: "Copy player opposite in grass"
        case 0x1F: "Copy player counterclockwise in grass"
        case 0x20: "Copy player clockwise in grass"
        case 0x21: "Hidden"
        case 0x22: "Walk in place down"
        case 0x23: "Walk in place up"
        case 0x24: "Walk in place left"
        case 0x25: "Walk in place right"
        case 0x26: "Jog in place down"
        case 0x27: "Jog in place up"
        case 0x28: "Jog in place left"
        case 0x29: "Jog in place right"
        case 0x2A: "Run in place down"
        case 0x2B: "Run in place up"
        case 0x2C: "Run in place left"
        case 0x2D: "Run in place right"
        case 0x2E: "Invisible"
        case 0x2F: "Walk slow in place down"
        case 0x30: "Walk slow in place up"
        case 0x31: "Walk slow in place left"
        case 0x32: "Walk slow in place right"
        default: "Movement #\(id)"
        }
    }

    private func normalizeToolForMode() {
        if !availableTools.contains(selectedTool) {
            selectedTool = availableTools.first ?? .pencil
        }
        rectangleStart = nil
        endPaintStroke()
        if mode != .events {
            clearEventSelection()
        }
    }

    private func prepareEventRenderCacheIfNeeded(for map: MapData) {
        guard mode == .events else { return }
        let signature = eventSignature(for: map)
        if eventRenderCache?.mapID == map.id, eventRenderCache?.signature == signature {
            return
        }

        var objectSprites: [MapObjectEvent.ID: NSImage] = [:]
        var trainerIDsByObjectID: [MapObjectEvent.ID: [TrainerData.ID]] = [:]
        objectSprites.reserveCapacity(map.objects.count)
        for object in map.objects {
            objectSprites[object.id] = document.objectEventSprite(for: object)
            let resolvedIDs = document.trainerLinks(for: object)
                .map(\.trainerID)
                .filter { id in document.trainers.contains(where: { $0.id == id }) }
            if !resolvedIDs.isEmpty {
                trainerIDsByObjectID[object.id] = Array(Set(resolvedIDs)).sorted()
            }
        }

        var analyses: [String: MapScriptAnalysis] = [:]
        analyses.reserveCapacity(map.objects.count + map.coordinateEvents.count + map.backgroundEvents.count)
        for object in map.objects {
            analyses[eventScriptKey(pointer: object.scriptPointer, eventType: "Object")] = document.scriptAnalysis(pointer: object.scriptPointer, eventType: "Object")
        }
        for event in map.coordinateEvents {
            analyses[eventScriptKey(pointer: event.scriptPointer, eventType: "Coordinate")] = document.scriptAnalysis(pointer: event.scriptPointer, eventType: "Coordinate")
        }
        for event in map.backgroundEvents {
            analyses[eventScriptKey(pointer: event.argument, eventType: "Background")] = document.scriptAnalysis(pointer: event.argument, eventType: "Background")
        }

        eventRenderCache = MapEventRenderCache(
            mapID: map.id,
            signature: signature,
            objectSprites: objectSprites,
            scriptAnalyses: analyses,
            trainerIDsByObjectID: trainerIDsByObjectID
        )
    }

    private func cachedScriptAnalysis(pointer: UInt32, eventType: String) -> MapScriptAnalysis {
        let key = eventScriptKey(pointer: pointer, eventType: eventType)
        if let analysis = eventRenderCache?.scriptAnalyses[key] {
            return analysis
        }
        return document.scriptAnalysis(pointer: pointer, eventType: eventType)
    }

    private func eventScriptKey(pointer: UInt32, eventType: String) -> String {
        "\(eventType)-\(pointer)"
    }

    private func eventSignature(for map: MapData) -> String {
        let objects = map.objects.map {
            "\($0.id):\($0.localID):\($0.graphicsID):\($0.x):\($0.y):\($0.elevation):\($0.movementType):\($0.trainerType):\($0.scriptPointer):\($0.flag)"
        }.joined(separator: "|")
        let warps = map.warps.map {
            "\($0.id):\($0.x):\($0.y):\($0.elevation):\($0.warpID):\($0.destinationGroup):\($0.destinationMap)"
        }.joined(separator: "|")
        let coordinates = map.coordinateEvents.map {
            "\($0.id):\($0.x):\($0.y):\($0.elevation):\($0.trigger):\($0.index):\($0.scriptPointer)"
        }.joined(separator: "|")
        let backgrounds = map.backgroundEvents.map {
            "\($0.id):\($0.x):\($0.y):\($0.elevation):\($0.kind):\($0.argument)"
        }.joined(separator: "|")
        return "\(map.id)::\(objects)::\(warps)::\(coordinates)::\(backgrounds)"
    }

    private func selectEvent(_ kind: MapEventKind, id: Int) {
        selectedBlockID = nil
        clearEventSelection()
        switch kind {
        case .object: selectedObjectID = id
        case .warp: selectedWarpID = id
        case .coordinate: selectedCoordinateID = id
        case .background: selectedBackgroundID = id
        }
    }

    private func clearEventSelection() {
        selectedObjectID = nil
        selectedWarpID = nil
        selectedCoordinateID = nil
        selectedBackgroundID = nil
    }

    private func moveObject(_ objectID: MapObjectEvent.ID, toX x: Int, y: Int) {
        guard let map = selectedMap,
              var object = map.objects.first(where: { $0.id == objectID }),
              object.x != x || object.y != y else { return }
        guard !document.scriptAnalysis(pointer: object.scriptPointer, eventType: "Object").isImportant else { return }
        let before = object
        object.x = x
        object.y = y
        undoStack.append(.object(mapID: map.id, before: before, after: object))
        redoStack.removeAll()
        document.updateMapObject(object, in: map)
    }

    private func moveWarp(_ warpID: MapWarpEvent.ID, toX x: Int, y: Int) {
        guard let map = selectedMap,
              var warp = map.warps.first(where: { $0.id == warpID }),
              warp.x != x || warp.y != y else { return }
        let before = warp
        warp.x = x
        warp.y = y
        undoStack.append(.warp(mapID: map.id, before: before, after: warp))
        redoStack.removeAll()
        document.updateMapWarp(warp, in: map)
    }

    private func sortedMaps(_ maps: [MapData]) -> [MapData] {
        let romIndices = Dictionary(uniqueKeysWithValues: document.maps.enumerated().map { ($0.element.id, $0.offset) })
        switch mapOrder {
        case .rom:
            return maps
        case .alphabetical:
            return maps.sorted {
                let lhsName = MapNameResolver.shared.mapName(group: $0.group, map: $0.mapID, language: language)
                let rhsName = MapNameResolver.shared.mapName(group: $1.group, map: $1.mapID, language: language)
                if lhsName != rhsName { return lhsName.localizedStandardCompare(rhsName) == .orderedAscending }
                return (romIndices[$0.id] ?? .max) < (romIndices[$1.id] ?? .max)
            }
        case .storyProgression:
            return maps.sorted { lhs, rhs in
                let lhsIndex = EmeraldStoryProgression.index(for: MapPoint(group: lhs.group, map: lhs.mapID)) ?? .max
                let rhsIndex = EmeraldStoryProgression.index(for: MapPoint(group: rhs.group, map: rhs.mapID)) ?? .max
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return (romIndices[lhs.id] ?? .max) < (romIndices[rhs.id] ?? .max)
            }
        }
    }

    private func restoreNavigationContext(_ context: MapTrainerNavigationContext?) {
        guard let context, document.maps.contains(where: { $0.id == context.mapID }) else { return }
        selectedMapID = context.mapID
        mode = .events
        selectedTool = .select
        selectEvent(.object, id: context.objectID)
        navigationContext = nil
    }

    private func openTrainerFromObject(_ objectID: MapObjectEvent.ID) {
        guard let map = selectedMap,
              let object = map.objects.first(where: { $0.id == objectID }) else { return }
        let trainerIDs = Array(Set(document.trainerLinks(for: object).map(\.trainerID)))
        guard trainerIDs.count == 1,
              let trainerID = trainerIDs.first,
              document.trainers.contains(where: { $0.id == trainerID }) else { return }
        openTrainer(trainerID, MapTrainerNavigationContext(mapID: map.id, objectID: object.id))
    }

    private func selectInitialMap() {
        guard !document.maps.isEmpty else {
            selectedMapID = nil
            return
        }
        if selectedMapID == nil || !document.maps.contains(where: { $0.id == selectedMapID }) {
            selectedMapID = document.maps.first?.id
        }
        restoreNavigationContext(navigationContext)
    }
}

private struct MapCanvasView: View {
    let map: MapData
    let baseImage: NSImage?
    @Binding var selectedBlockID: MapBlockCell.ID?
    let selectedObjectID: MapObjectEvent.ID?
    let selectedWarpID: MapWarpEvent.ID?
    let selectedCoordinateID: MapCoordinateEvent.ID?
    let selectedBackgroundID: MapBackgroundEvent.ID?
    let mode: MapEditorMode
    let tool: MapTool
    let selectedMetatile: Int
    let selectedCollision: Int
    let selectedElevation: Int
    let zoom: Double
    let showGrid: Bool
    let showCollisionValues: Bool
    let showElevationValues: Bool
    let showBehaviorValues: Bool
    let showObjects: Bool
    let showWarps: Bool
    let showCoordinateEvents: Bool
    let showBackgroundEvents: Bool
    let onPick: (MapBlockCell) -> Void
    let onPaint: (MapBlockCell) -> Void
    let onEndPaintStroke: () -> Void
    let onRectangle: (MapBlockCell) -> Void
    let onFill: (MapBlockCell) -> Void
    let onSelectObject: (MapObjectEvent.ID) -> Void
    let onSelectWarp: (MapWarpEvent.ID) -> Void
    let onSelectCoordinate: (MapCoordinateEvent.ID) -> Void
    let onSelectBackground: (MapBackgroundEvent.ID) -> Void
    let onMoveObject: (MapObjectEvent.ID, Int, Int) -> Void
    let onMoveWarp: (MapWarpEvent.ID, Int, Int) -> Void
    let objectSprites: [MapObjectEvent.ID: NSImage]
    let importantScriptKeys: Set<String>
    let trainerIDsByObjectID: [MapObjectEvent.ID: [TrainerData.ID]]
    let modifiedTrainerIDs: Set<TrainerData.ID>
    let trainerComparisonAvailable: Bool
    let eventFilter: MapEventDisplayFilter
    let onOpenTrainer: (MapObjectEvent.ID) -> Void

    @State private var draggedObjectID: MapObjectEvent.ID?
    @State private var draggedWarpID: MapWarpEvent.ID?
    @State private var activeEventKind: MapEventKind?
    @State private var activeEventID: Int?
    @State private var lastTrainerClickID: MapObjectEvent.ID?
    @State private var lastTrainerClickTime: TimeInterval = 0

    private struct ScaledSpriteEntry {
        let native: NSImage
        let scaled: NSImage
    }

    private static var scaledSpriteStore: [String: ScaledSpriteEntry] = [:]

    private var cellSize: CGFloat { CGFloat(16 * zoom) }

    private func scaledSprite(for object: MapObjectEvent) -> NSImage? {
        guard let native = objectSprites[object.id] else { return nil }
        let key = "\(object.graphicsID)@\(Int((zoom * 100).rounded()))"
        if let entry = Self.scaledSpriteStore[key], entry.native === native {
            return entry.scaled
        }
        guard let scaled = native.pixelArtScaled(by: zoom) else { return nil }
        Self.scaledSpriteStore[key] = ScaledSpriteEntry(native: native, scaled: scaled)
        return scaled
    }

    private func isEventProtected(_ object: MapObjectEvent) -> Bool {
        importantScriptKeys.contains(eventScriptKey(pointer: object.scriptPointer, eventType: "Object"))
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                if let baseImage {
                    Image(nsImage: baseImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(map.width) * cellSize, height: CGFloat(map.height) * cellSize)
                }
                Canvas { context, _ in
                    for block in map.blocks {
                        let rect = CGRect(x: CGFloat(block.x) * cellSize, y: CGFloat(block.y) * cellSize, width: cellSize, height: cellSize)
                        if baseImage == nil {
                            context.fill(Path(rect), with: .color(color(for: block)))
                        }
                        if mode == .collision {
                            drawCollisionOverlay(for: block, in: rect, context: &context)
                        }
                        if showGrid {
                            context.stroke(Path(rect), with: .color(.black.opacity(0.16)), lineWidth: 0.5)
                        }
                        if block.id == selectedBlockID {
                            context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(.accentColor), lineWidth: 2)
                        }
                    }
                    switch mode {
                    case .map:
                        drawEventHints(in: context)
                    case .collision:
                        break
                    case .events:
                        drawEvents(in: context)
                    }
                }
                .frame(width: CGFloat(map.width) * cellSize, height: CGFloat(map.height) * cellSize)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if mode == .events {
                        if activeEventID == nil, let event = eventAt(point: value.startLocation) {
                            activeEventKind = event.kind
                            activeEventID = event.id
                            _ = selectEvent(at: value.startLocation)
                        }
                        return
                    }
                    guard let block = block(at: value.location) else { return }
                    selectedBlockID = block.id
                    onPaint(block)
                }.onEnded { value in
                    onEndPaintStroke()
                    if mode == .events,
                       activeEventKind == .object,
                       let objectID = activeEventID,
                       value.translation.width.magnitude < 4,
                       value.translation.height.magnitude < 4,
                       trainerIDsByObjectID[objectID]?.count == 1 {
                        let now = Date.timeIntervalSinceReferenceDate
                        if lastTrainerClickID == objectID, now - lastTrainerClickTime < 0.4 {
                            onOpenTrainer(objectID)
                            lastTrainerClickID = nil
                            lastTrainerClickTime = 0
                        } else {
                            lastTrainerClickID = objectID
                            lastTrainerClickTime = now
                        }
                    }
                    guard mode == .events, tool == .move, let block = block(at: value.location) else {
                        draggedObjectID = nil
                        draggedWarpID = nil
                        activeEventKind = nil
                        activeEventID = nil
                        return
                    }
                    if let draggedObjectID {
                        onMoveObject(draggedObjectID, block.x, block.y)
                    } else if let draggedWarpID {
                        onMoveWarp(draggedWarpID, block.x, block.y)
                    }
                    draggedObjectID = nil
                    draggedWarpID = nil
                    activeEventKind = nil
                    activeEventID = nil
                })
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: map.id) { _ in
            Self.scaledSpriteStore.removeAll()
        }
        .onChange(of: zoom) { _ in
            Self.scaledSpriteStore.removeAll()
        }
    }

    private func drawEvents(in context: GraphicsContext) {
        let start = MapEditProfiler.now()
        defer { MapEditProfiler.log("events layer draw", since: start) }
        if eventFilter == .warps || (eventFilter == .all && showWarps) {
            for warp in map.warps {
                let rect = markerRect(x: warp.x, y: warp.y)
                let isSelected = selectedWarpID == warp.id
                context.fill(Path(ellipseIn: rect), with: .color(.blue.opacity(0.9)))
                drawSelectionHaloIfNeeded(around: rect, cornerRadius: rect.width / 2, isSelected: isSelected, context: context)
                context.stroke(Path(ellipseIn: rect), with: .color(isSelected ? .accentColor : .white.opacity(0.9)), lineWidth: isSelected ? 3 : 1.5)
                context.draw(Text("W").font(.caption2).foregroundColor(.white), at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
        if eventFilter == .trainers || ((eventFilter == .all || eventFilter == .others) && showObjects) {
            for object in map.objects {
                let isTrainer = trainerIDsByObjectID[object.id] != nil
                guard eventFilter == .all || (eventFilter == .trainers && isTrainer) || (eventFilter == .others && !isTrainer) else { continue }
                if let sprite = scaledSprite(for: object) {
                    let rect = objectRect(for: object, sprite: sprite)
                    let isSelected = selectedObjectID == object.id
                    context.draw(Image(nsImage: sprite), in: rect)
                    drawImportantBadgeIfNeeded(for: object.scriptPointer, eventType: "Object", near: rect, context: context)
                    drawSelectionHaloIfNeeded(around: rect.insetBy(dx: -2, dy: -2), cornerRadius: 4, isSelected: isSelected, context: context)
                    context.stroke(
                        Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 3),
                        with: .color(isSelected ? .accentColor : .white.opacity(0.85)),
                        lineWidth: isSelected ? 3 : 1.2
                    )
                    drawTrainerBadgeIfNeeded(for: object, near: rect, context: context)
                } else {
                    let marker = markerRect(x: object.x, y: object.y)
                    let isSelected = selectedObjectID == object.id
                    context.fill(Path(roundedRect: marker, cornerRadius: 3), with: .color(.orange.opacity(0.9)))
                    drawSelectionHaloIfNeeded(around: marker, cornerRadius: 3, isSelected: isSelected, context: context)
                    context.stroke(Path(roundedRect: marker, cornerRadius: 3), with: .color(isSelected ? .accentColor : .white.opacity(0.9)), lineWidth: isSelected ? 3 : 1.5)
                    context.draw(Text("\(object.localID)").font(.caption2).foregroundColor(.black), at: CGPoint(x: marker.midX, y: marker.midY))
                    drawImportantBadgeIfNeeded(for: object.scriptPointer, eventType: "Object", near: marker, context: context)
                    drawTrainerBadgeIfNeeded(for: object, near: marker, context: context)
                }
            }
        }
        if showCoordinateEvents && (eventFilter == .all || eventFilter == .others) {
            for event in map.coordinateEvents {
                let rect = markerRect(x: event.x, y: event.y).insetBy(dx: 2, dy: 2)
                let isSelected = selectedCoordinateID == event.id
                var path = Path()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.closeSubpath()
                context.fill(path, with: .color(.green.opacity(0.9)))
                if isSelected {
                    context.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 6)
                }
                context.stroke(path, with: .color(isSelected ? .accentColor : .white.opacity(0.9)), lineWidth: isSelected ? 3 : 1.5)
                drawImportantBadgeIfNeeded(for: event.scriptPointer, eventType: "Coordinate", near: rect, context: context)
            }
        }
        if eventFilter == .items || ((eventFilter == .all || eventFilter == .others) && showBackgroundEvents) {
            for event in map.backgroundEvents {
                let isItem = event.kind == 7
                guard eventFilter == .all || (eventFilter == .items && isItem) || (eventFilter == .others && !isItem) else { continue }
                let rect = markerRect(x: event.x, y: event.y).insetBy(dx: 3, dy: 3)
                let isSelected = selectedBackgroundID == event.id
                context.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2), with: .color((isItem ? Color.yellow : Color.purple).opacity(0.9)))
                drawSelectionHaloIfNeeded(around: rect, cornerRadius: rect.width / 2, isSelected: isSelected, context: context)
                context.stroke(Path(roundedRect: rect, cornerRadius: rect.width / 2), with: .color(isSelected ? .accentColor : .white.opacity(0.9)), lineWidth: isSelected ? 3 : 1.5)
                context.draw(Text(isItem ? "O" : "i").font(.caption2).foregroundColor(isItem ? .black : .white), at: CGPoint(x: rect.midX, y: rect.midY))
                drawImportantBadgeIfNeeded(for: event.argument, eventType: "Background", near: rect, context: context)
            }
        }
    }

    private func drawTrainerBadgeIfNeeded(for object: MapObjectEvent, near rect: CGRect, context: GraphicsContext) {
        guard let trainerIDs = trainerIDsByObjectID[object.id] else { return }
        let side = max(12, min(18, cellSize * 0.58))
        let badge = CGRect(x: rect.minX - side * 0.3, y: rect.minY - side * 0.3, width: side, height: side)
        let color: Color = trainerComparisonAvailable
            ? (trainerIDs.contains(where: modifiedTrainerIDs.contains) ? .orange : .blue)
            : .secondary
        context.fill(Path(ellipseIn: badge), with: .color(color.opacity(0.95)))
        context.stroke(Path(ellipseIn: badge), with: .color(.white.opacity(0.9)), lineWidth: 1)
        let symbol = trainerComparisonAvailable ? "T" : "?"
        context.draw(Text(symbol).font(.system(size: max(7, side * 0.62), weight: .bold)).foregroundColor(.white), at: CGPoint(x: badge.midX, y: badge.midY))
    }

    private func drawSelectionHaloIfNeeded(around rect: CGRect, cornerRadius: CGFloat, isSelected: Bool, context: GraphicsContext) {
        guard isSelected else { return }
        context.stroke(
            Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: cornerRadius + 4),
            with: .color(.white.opacity(0.95)),
            lineWidth: 5
        )
    }

    private func drawImportantBadgeIfNeeded(for pointer: UInt32, eventType: String, near rect: CGRect, context: GraphicsContext) {
        guard importantScriptKeys.contains(eventScriptKey(pointer: pointer, eventType: eventType)) else { return }
        let side = max(12, min(18, cellSize * 0.55))
        let badge = CGRect(x: rect.maxX - side * 0.75, y: rect.minY - side * 0.25, width: side, height: side)
        context.fill(Path(ellipseIn: badge), with: .color(.yellow.opacity(0.95)))
        context.stroke(Path(ellipseIn: badge), with: .color(.black.opacity(0.75)), lineWidth: 1)
        context.draw(Text("!").font(.system(size: max(8, side * 0.72), weight: .bold)).foregroundColor(.black), at: CGPoint(x: badge.midX, y: badge.midY))
    }

    private func drawEventHints(in context: GraphicsContext) {
        let occupiedCells = Set(
            map.objects.map { "\($0.x)-\($0.y)" }
                + map.warps.map { "\($0.x)-\($0.y)" }
                + map.coordinateEvents.map { "\($0.x)-\($0.y)" }
                + map.backgroundEvents.map { "\($0.x)-\($0.y)" }
        )
        for key in occupiedCells {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let rect = markerRect(x: parts[0], y: parts[1]).insetBy(dx: cellSize * 0.18, dy: cellSize * 0.18)
            context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.28)))
        }
    }

    private func drawCollisionOverlay(for block: MapBlockCell, in rect: CGRect, context: inout GraphicsContext) {
        let collision = block.collision
        let overlay: Color = switch collision {
        case 0: .green.opacity(0.18)
        case 1: .red.opacity(0.42)
        case 2: .yellow.opacity(0.36)
        default: .blue.opacity(0.36)
        }
        context.fill(Path(rect), with: .color(overlay))
        context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(.black.opacity(0.24)), lineWidth: 1)
        let visibleValues = collisionOverlayValues(for: block)
        guard !visibleValues.isEmpty else { return }
        let badgeWidth = max(cellSize * 0.68, 13)
        let badgeHeight = max(cellSize * 0.42, 10)
        let badge = CGRect(x: rect.midX - badgeWidth / 2, y: rect.midY - badgeHeight / 2, width: badgeWidth, height: badgeHeight)
        context.fill(Path(roundedRect: badge, cornerRadius: 3), with: .color(.white.opacity(0.9)))
        context.stroke(Path(roundedRect: badge, cornerRadius: 3), with: .color(.black.opacity(0.7)), lineWidth: 0.8)
        context.draw(
            Text(visibleValues)
                .font(.system(size: max(7, min(11, cellSize * 0.42)), weight: .semibold, design: .monospaced))
                .foregroundColor(.black),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private func collisionOverlayValues(for block: MapBlockCell) -> String {
        var values: [String] = []
        if showCollisionValues {
            values.append("C\(block.collision)")
        }
        if showElevationValues {
            values.append("E\(block.elevation)")
        }
        if showBehaviorValues {
            values.append("B-")
        }
        return values.joined(separator: " ")
    }

    private func markerRect(x: Int, y: Int) -> CGRect {
        CGRect(x: CGFloat(x) * cellSize + cellSize * 0.2, y: CGFloat(y) * cellSize + cellSize * 0.2, width: cellSize * 0.6, height: cellSize * 0.6)
    }

    private func objectRect(for object: MapObjectEvent) -> CGRect {
        objectRect(for: object, sprite: nil)
    }

    private func objectRect(for object: MapObjectEvent, sprite: NSImage?) -> CGRect {
        let tileX = CGFloat(object.x) * cellSize
        let tileY = CGFloat(object.y) * cellSize
        guard let sprite, sprite.size.width > 0, sprite.size.height > 0 else {
            let side = cellSize * 0.6
            return CGRect(x: tileX + (cellSize - side) / 2, y: tileY + (cellSize - side) / 2, width: side, height: side)
        }
        let width = sprite.size.width
        let height = sprite.size.height
        return CGRect(x: tileX + (cellSize - width) / 2, y: tileY + cellSize - height, width: width, height: height)
    }

    private func block(at point: CGPoint) -> MapBlockCell? {
        let x = Int(point.x / cellSize)
        let y = Int(point.y / cellSize)
        return map.blocks.first { $0.x == x && $0.y == y }
    }

    private func selectEvent(at point: CGPoint) -> Bool {
        guard let event = eventAt(point: point) else {
            draggedObjectID = nil
            draggedWarpID = nil
            return false
        }
        switch event.kind {
        case .object:
            onSelectObject(event.id)
            let protected = map.objects.first(where: { $0.id == event.id }).map(isEventProtected) ?? false
            draggedObjectID = tool == .move && !protected ? event.id : nil
            draggedWarpID = nil
        case .warp:
            onSelectWarp(event.id)
            draggedWarpID = tool == .move ? event.id : nil
            draggedObjectID = nil
        case .coordinate:
            onSelectCoordinate(event.id)
            draggedObjectID = nil
            draggedWarpID = nil
        case .background:
            onSelectBackground(event.id)
            draggedObjectID = nil
            draggedWarpID = nil
        }
        return true
    }

    private func eventAt(point: CGPoint) -> (kind: MapEventKind, id: Int)? {
        let x = Int(point.x / cellSize)
        let y = Int(point.y / cellSize)

        var candidates: [(kind: MapEventKind, id: Int)] = []
        if eventFilter == .trainers || ((eventFilter == .all || eventFilter == .others) && showObjects) {
            for object in map.objects.reversed() {
                let isTrainer = trainerIDsByObjectID[object.id] != nil
                guard eventFilter == .all || (eventFilter == .trainers && isTrainer) || (eventFilter == .others && !isTrainer) else { continue }
                let rect = objectRect(for: object, sprite: scaledSprite(for: object))
                guard rect.contains(point) || (object.x == x && object.y == y) else { continue }
                candidates.append((.object, object.id))
            }
        }
        if eventFilter == .warps || (eventFilter == .all && showWarps) {
            candidates += map.warps
                .filter { $0.x == x && $0.y == y }
                .map { (.warp, $0.id) }
        }
        if showCoordinateEvents && (eventFilter == .all || eventFilter == .others) {
            candidates += map.coordinateEvents
                .filter { $0.x == x && $0.y == y }
                .map { (.coordinate, $0.id) }
        }
        if eventFilter == .items || ((eventFilter == .all || eventFilter == .others) && showBackgroundEvents) {
            candidates += map.backgroundEvents
                .filter {
                    let isItem = $0.kind == 7
                    return $0.x == x && $0.y == y
                        && (eventFilter == .all || (eventFilter == .items && isItem) || (eventFilter == .others && !isItem))
                }
                .map { (.background, $0.id) }
        }
        guard !candidates.isEmpty else { return nil }
        if let currentIndex = candidates.firstIndex(where: isCurrentlySelected) {
            return candidates[(currentIndex + 1) % candidates.count]
        }
        return candidates.first
    }

    private func isCurrentlySelected(_ event: (kind: MapEventKind, id: Int)) -> Bool {
        switch event.kind {
        case .object: selectedObjectID == event.id
        case .warp: selectedWarpID == event.id
        case .coordinate: selectedCoordinateID == event.id
        case .background: selectedBackgroundID == event.id
        }
    }

    private func eventScriptKey(pointer: UInt32, eventType: String) -> String {
        "\(eventType)-\(pointer)"
    }

    private func color(for block: MapBlockCell) -> Color {
        Color(hue: Double((block.metatileID * 37) % 360) / 360.0, saturation: 0.35, brightness: 0.78)
    }
}

private struct MapEventRenderCache {
    let mapID: MapData.ID
    let signature: String
    let objectSprites: [MapObjectEvent.ID: NSImage]
    let scriptAnalyses: [String: MapScriptAnalysis]
    let trainerIDsByObjectID: [MapObjectEvent.ID: [TrainerData.ID]]

    var importantScriptKeys: Set<String> {
        Set(scriptAnalyses.filter { $0.value.isImportant }.map(\.key))
    }
}

private struct MapInspectorRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EventLegendRow: View {
    let color: Color
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.9))
                Text(symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CollisionInfoRow: View {
    let title: String
    let value: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(help)
            }
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LegendValueRow: View {
    let value: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MapBlockPaletteView: View {
    let map: MapData
    @Binding var selectedMetatile: Int
    let imageProvider: (Int) -> NSImage?

    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(0..<1024, id: \.self) { metatileID in
                    Button {
                        selectedMetatile = metatileID
                    } label: {
                        MapBlockPaletteCell(
                            metatileID: metatileID,
                            image: imageProvider(metatileID),
                            isSelected: selectedMetatile == metatileID
                        )
                    }
                    .buttonStyle(.plain)
                    .help(metatileID < 512 ? "Primary #\(metatileID)" : "Secondary #\(metatileID - 512)")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
    }
}

private struct MapBlockPaletteCell: View {
    let metatileID: Int
    let image: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            preview
            Text("\(metatileID)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(5)
        .frame(width: 60)
        .frame(minHeight: 72)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 44, height: 44)
        } else {
            Rectangle()
                .fill(.secondary.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay(Text("#").font(.caption2))
        }
    }
}

struct SaveInfoView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let saveDocument = document.saveDocument {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    EditorHeaderCard {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .frame(width: 72, height: 72)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(saveDocument.parsed.fileName)
                                .font(.largeTitle.weight(.semibold))
                                .lineLimit(1)
                            HStack(spacing: 10) {
                                Chip("Emerald / Gen III")
                                Chip("Party \(saveDocument.parsed.party.count)/6")
                                Chip(saveDocument.parsed.allSectionChecksumsValid ? "Checksums OK" : "Checksum warning")
                            }
                        }
                    }
                    EditorCardGrid {
                        Panel(title: L10n.text("file", language: language)) {
                            ReadOnlyRow(title: L10n.text("name", language: language), value: saveDocument.parsed.fileName)
                            ReadOnlyRow(title: L10n.text("size", language: language), value: ROMDocument.formatSize(saveDocument.data.count))
                            ReadOnlyRow(title: L10n.text("path", language: language), value: saveDocument.fileURL.path)
                            ReadOnlyRow(title: language == .italian ? "Gioco/versione" : "Game/version", value: saveDocument.parsed.gameTitle ?? unavailable)
                            ReadOnlyRow(title: L10n.text("mode", language: language), value: L10n.text("mode.safe.party", language: language))
                        }
                        Panel(title: L10n.text("save.blocks", language: language)) {
                            ReadOnlyRow(title: L10n.text("version", language: language), value: "Pokémon Emerald / Gen III")
                            ReadOnlyRow(title: L10n.text("active.save.block", language: language), value: String(format: "0x%08X", saveDocument.parsed.saveBlockOffset))
                            ReadOnlyRow(title: L10n.text("save.block1.section", language: language), value: String(format: "0x%08X", saveDocument.parsed.saveBlock1SectionOffset))
                            ReadOnlyRow(title: L10n.text("save.index", language: language), value: "\(saveDocument.parsed.activeSaveIndex)")
                            ReadOnlyRow(title: language == .italian ? "Slot attivo" : "Active slot", value: "\(saveDocument.parsed.activeSlot)")
                            ReadOnlyRow(title: language == .italian ? "Numero salvataggi" : "Save count", value: saveDocument.parsed.saveCount.map(String.init) ?? unavailable)
                            ReadOnlyRow(title: L10n.text("section.checksums", language: language), value: saveDocument.parsed.allSectionChecksumsValid ? L10n.text("valid", language: language) : L10n.text("not.all.valid", language: language))
                        }
                        Panel(title: language == .italian ? "Allenatore" : "Trainer") {
                            ReadOnlyRow(title: L10n.text("name", language: language), value: saveDocument.parsed.trainer.name ?? unavailable)
                            ReadOnlyRow(title: "Trainer ID", value: saveDocument.parsed.trainer.trainerID.map(String.init) ?? unavailable)
                            ReadOnlyRow(title: "Secret ID", value: saveDocument.parsed.trainer.secretID.map(String.init) ?? unavailable)
                            ReadOnlyRow(title: language == .italian ? "Tempo di gioco" : "Play time", value: saveDocument.parsed.playTime?.displayValue ?? unavailable)
                        }
                        Panel(title: L10n.text("party", language: language)) {
                            ReadOnlyRow(title: L10n.text("party.count", language: language), value: "\(saveDocument.parsed.party.count)")
                            ReadOnlyRow(title: L10n.text("pokemon.checksum", language: language), value: pokemonChecksumSummary(saveDocument.parsed.party))
                            ReadOnlyRow(title: L10n.text("writing", language: language), value: "Party: nickname, item, moves, PP, EV, IV")
                        }
                    }
                }
                .padding(EditorLayout.detailPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(L10n.text("save.info", language: language))
        } else {
            PlaceholderView(title: L10n.text("no.save", language: language), systemImage: "externaldrive.badge.questionmark", message: L10n.text("open.save.home.menu", language: language))
        }
    }

    private func pokemonChecksumSummary(_ party: [PlayerPartyPokemon]) -> String {
        guard !party.isEmpty else { return L10n.text("empty.party", language: language) }
        let validCount = party.filter(\.checksumValid).count
        return L10n.validCount(validCount, total: party.count, language: language)
    }

    private var unavailable: String {
        language == .italian ? "Non disponibile" : "Not available"
    }
}

struct SaveBoxesView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @State private var selectedBoxID = 0
    @State private var selectedSlot = 0

    private var selectedBox: SavePCBox? {
        document.playerSave?.boxes.first { $0.id == selectedBoxID } ?? document.playerSave?.boxes.first
    }

    var body: some View {
        if let save = document.playerSave {
            HStack(spacing: 0) {
                List(save.boxes, selection: $selectedBoxID) { box in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(box.name).lineLimit(1)
                        Text(box.pokemon.isEmpty ? (language == .italian ? "Vuoto" : "Empty") : "\(box.pokemon.count) / 30 Pokémon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                    .tag(box.id)
                }
                .frame(minWidth: 170, idealWidth: 200, maxWidth: 230)
                Divider()

                if let box = selectedBox {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            boxHeader(box, boxes: save.boxes)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(92), spacing: 8), count: 6), alignment: .leading, spacing: 8) {
                                ForEach(0..<30, id: \.self) { slot in
                                    boxSlotCell(slot: slot, pokemon: pokemon(in: box, slot: slot), isSelected: selectedSlot == slot)
                                }
                            }
                            .frame(width: 592, alignment: .leading)
                        }
                        .padding(EditorLayout.detailPadding)

                        boxInspector(box)
                            .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)
                            .padding(.vertical, EditorLayout.detailPadding)
                            .padding(.trailing, EditorLayout.detailPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .onAppear {
                if selectedBoxID == 0, let first = save.boxes.first { selectedBoxID = first.id }
            }
            .onChange(of: selectedBoxID) { _ in selectedSlot = 0 }
            .navigationTitle(L10n.text("boxes", language: language))
        } else {
            PlaceholderView(title: L10n.text("no.save.open", language: language), systemImage: "externaldrive.badge.questionmark", message: L10n.text("open.save.instruction", language: language))
        }
    }

    private func boxHeader(_ box: SavePCBox, boxes: [SavePCBox]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(box.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text("Pokémon: \(box.pokemon.count) / 30")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                selectRelativeBox(-1, boxes: boxes)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help(language == .italian ? "Box precedente" : "Previous box")
            Button {
                selectRelativeBox(1, boxes: boxes)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(language == .italian ? "Box successivo" : "Next box")
        }
        .frame(width: 592)
    }

    private func boxSlotCell(slot: Int, pokemon: SaveBoxPokemon?, isSelected: Bool) -> some View {
        Button {
            selectedSlot = slot
        } label: {
            VStack(spacing: 4) {
                if let pokemon {
                    spriteView(for: pokemon)
                    Text(pokemon.nickname.isEmpty ? document.referenceSpeciesName(id: pokemon.species) : pokemon.nickname)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(levelText(for: pokemon))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 44, height: 44)
                    Text(language == .italian ? "Vuoto" : "Empty")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("Slot \(slot + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(6)
            .frame(width: 92, height: 92)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func boxInspector(_ box: SavePCBox) -> some View {
        let pokemon = pokemon(in: box, slot: selectedSlot)
        return Panel(title: language == .italian ? "Inspector" : "Inspector") {
            if let pokemon {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        spriteView(for: pokemon)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pokemon.nickname)
                                .font(.headline)
                                .lineLimit(1)
                            Text(document.referenceSpeciesName(id: pokemon.species))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    ReadOnlyRow(title: "Slot", value: "\(pokemon.slot + 1)")
                    ReadOnlyRow(title: L10n.text("level", language: language), value: levelText(for: pokemon))
                    ReadOnlyRow(title: L10n.text("nature", language: language), value: pokemon.natureName)
                    ReadOnlyRow(title: L10n.text("gender", language: language), value: genderDescription(for: pokemon))
                    ReadOnlyRow(title: L10n.text("item", language: language), value: document.referenceItemName(id: pokemon.heldItem))
                    ReadOnlyRow(title: "IV", value: ivSummary(for: pokemon))
                    ReadOnlyRow(title: L10n.text("egg", language: language), value: L10n.yesNo(pokemon.isEgg, language: language))
                    if !pokemon.checksumValid {
                        Text(L10n.text("pokemon.checksum", language: language) + ": " + L10n.text("warning", language: language))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "square.dashed")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(language == .italian ? "Slot vuoto" : "Empty slot")
                        .font(.headline)
                    Text("Slot \(selectedSlot + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func spriteView(for pokemon: SaveBoxPokemon) -> some View {
        ZStack {
            if let sprite = document.linkedSavePokemonSprite(forSpeciesID: pokemon.species) {
                Image(nsImage: sprite)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
    }

    private func pokemon(in box: SavePCBox, slot: Int) -> SaveBoxPokemon? {
        box.pokemon.first { $0.slot == slot }
    }

    private func selectRelativeBox(_ delta: Int, boxes: [SavePCBox]) {
        guard let currentIndex = boxes.firstIndex(where: { $0.id == selectedBoxID }) else { return }
        let nextIndex = (currentIndex + delta + boxes.count) % boxes.count
        selectedBoxID = boxes[nextIndex].id
        selectedSlot = 0
    }

    private func levelText(for pokemon: SaveBoxPokemon) -> String {
        if let level = estimatedLevel(for: pokemon) {
            return "\(L10n.text("lv", language: language)) \(level)"
        }
        return "\(L10n.text("lv", language: language)) --"
    }

    private func estimatedLevel(for pokemon: SaveBoxPokemon) -> Int? {
        guard let species = document.pokemonSpecies.first(where: { $0.id == pokemon.species }) else { return nil }
        let experience = Int64(pokemon.experience)
        return (1...100).last { level in
            experience >= experienceForLevel(level, growthRate: species.growthRate)
        }
    }

    private func experienceForLevel(_ level: Int, growthRate: Int) -> Int64 {
        let n = Int64(level)
        switch growthRate {
        case 1:
            if level <= 50 { return n * n * n * (100 - n) / 50 }
            if level <= 68 { return n * n * n * (150 - n) / 100 }
            if level <= 98 { return n * n * n * ((1911 - 10 * n) / 3) / 500 }
            return n * n * n * (160 - n) / 100
        case 2:
            if level <= 15 { return n * n * n * (((n + 1) / 3) + 24) / 50 }
            if level <= 36 { return n * n * n * (n + 14) / 50 }
            return n * n * n * ((n / 2) + 32) / 50
        case 3:
            return (6 * n * n * n / 5) - (15 * n * n) + (100 * n) - 140
        case 4:
            return 4 * n * n * n / 5
        case 5:
            return 5 * n * n * n / 4
        default:
            return n * n * n
        }
    }

    private func genderDescription(for pokemon: SaveBoxPokemon) -> String {
        guard let species = document.pokemonSpecies.first(where: { $0.id == pokemon.species }) else { return L10n.text("pid.based", language: language) }
        switch species.genderRatio {
        case 0xFF: return L10n.text("genderless", language: language)
        case 0xFE: return L10n.text("female", language: language)
        case 0x00: return L10n.text("male", language: language)
        default:
            let value = Int(pokemon.personality & 0xFF)
            return value < species.genderRatio ? L10n.text("female", language: language) : L10n.text("male", language: language)
        }
    }

    private func ivSummary(for pokemon: SaveBoxPokemon) -> String {
        let total = pokemon.ivs.hp + pokemon.ivs.attack + pokemon.ivs.defense + pokemon.ivs.specialAttack + pokemon.ivs.specialDefense + pokemon.ivs.speed
        return "\(total) / 186"
    }
}

struct SaveBagView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @State private var selectedPocket: SaveBagPocketKind = .items

    var body: some View {
        if let save = document.playerSave {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $selectedPocket) {
                    ForEach(save.bagPockets) { pocket in
                        Text(pocket.name).tag(pocket.kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let pocket = save.bagPockets.first(where: { $0.kind == selectedPocket }) {
                    bagPocketEditor(pocket)
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                if !save.bagPockets.contains(where: { $0.kind == selectedPocket }),
                   let first = save.bagPockets.first {
                    selectedPocket = first.kind
                }
            }
            .onChange(of: document.playerSave?.bagPockets) { pockets in
                guard let pockets, !pockets.contains(where: { $0.kind == selectedPocket }),
                      let first = pockets.first else { return }
                selectedPocket = first.kind
            }
            .navigationTitle(L10n.text("bag", language: language))
        } else {
            PlaceholderView(title: L10n.text("no.save.open", language: language), systemImage: "bag.fill", message: L10n.text("open.save.instruction", language: language))
        }
    }

    private func bagPocketEditor(_ pocket: SaveBagPocket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pocket.name)
                        .font(.title2.weight(.semibold))
                    Text("\(language == .italian ? "Slot usati" : "Used slots"): \(pocket.items.count) / \(pocket.capacity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    addItem(to: pocket)
                } label: {
                    Label(language == .italian ? "Aggiungi oggetto" : "Add item", systemImage: "plus")
                }
                .disabled(pocket.items.count >= pocket.capacity || defaultItemID(for: pocket) == nil)
            }

            if pocket.kind == .keyItems {
                Label(language == .italian ? "Attenzione: modificare gli strumenti chiave può influenzare la progressione della storia." : "Warning: changing key items can affect story progression.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(displayItems(for: pocket)) { item in
                        bagItemRow(item, in: pocket)
                    }
                    if pocket.items.isEmpty {
                        Text(language == .italian ? "Tasca vuota" : "Empty pocket")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func bagItemRow(_ item: SaveBagItem, in pocket: SaveBagPocket) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(itemDisplayName(item.itemID, pocket: pocket.kind))
                    .font(.headline)
                    .lineLimit(1)
                Text("Slot \(item.slot + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 170, maxWidth: 240, alignment: .leading)

            Picker("", selection: itemIDBinding(item, pocket: pocket)) {
                ForEach(itemOptions(for: pocket.kind, including: item.itemID, slot: item.slot)) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 220, maxWidth: 340)

            HStack(spacing: 6) {
                Text("x\(item.quantity)")
                    .font(.callout.monospacedDigit())
                    .frame(width: 46, alignment: .trailing)
                Stepper("", value: quantityBinding(item, pocket: pocket), in: 0...999)
                    .labelsHidden()
                    .frame(width: EditorLayout.stepperWidth)
            }

            Button {
                document.updateSaveBagItem(pocket: pocket.kind, slot: item.slot, itemID: 0, quantity: 0)
            } label: {
                Label(language == .italian ? "Rimuovi" : "Remove", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help(language == .italian ? "Rimuovi" : "Remove")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func displayItems(for pocket: SaveBagPocket) -> [SaveBagItem] {
        pocket.items.sorted { $0.slot < $1.slot }
    }

    private func addItem(to pocket: SaveBagPocket) {
        guard let slot = (0..<pocket.capacity).first(where: { candidate in
            !pocket.items.contains(where: { $0.slot == candidate })
        }), let itemID = defaultItemID(for: pocket) else { return }
        document.updateSaveBagItem(pocket: pocket.kind, slot: slot, itemID: itemID, quantity: 1)
    }

    private func itemIDBinding(_ item: SaveBagItem, pocket: SaveBagPocket) -> Binding<Int> {
        Binding {
            currentItem(slot: item.slot, in: pocket.kind)?.itemID ?? item.itemID
        } set: { newValue in
            guard isItemAllowed(newValue, in: pocket.kind, slot: item.slot) else { return }
            let quantity = currentItem(slot: item.slot, in: pocket.kind)?.quantity ?? item.quantity
            document.updateSaveBagItem(pocket: pocket.kind, slot: item.slot, itemID: newValue, quantity: newValue == 0 ? 0 : max(1, quantity))
        }
    }

    private func quantityBinding(_ item: SaveBagItem, pocket: SaveBagPocket) -> Binding<Int> {
        Binding {
            currentItem(slot: item.slot, in: pocket.kind)?.quantity ?? item.quantity
        } set: { newValue in
            let clamped = min(max(newValue, 0), 999)
            let currentID = currentItem(slot: item.slot, in: pocket.kind)?.itemID ?? item.itemID
            document.updateSaveBagItem(pocket: pocket.kind, slot: item.slot, itemID: currentID, quantity: clamped)
        }
    }

    private func currentItem(slot: Int, in pocket: SaveBagPocketKind) -> SaveBagItem? {
        document.playerSave?.bagPockets.first { $0.kind == pocket }?.items.first { $0.slot == slot }
    }

    private func itemOptions(for pocket: SaveBagPocketKind, including selectedID: Int, slot: Int) -> [PokemonNamedValue] {
        let usedIDs = Set(document.playerSave?.bagPockets.first { $0.kind == pocket }?.items
            .filter { $0.slot != slot }
            .map(\.itemID) ?? [])
        var options = compatibleItemOptions(for: pocket)
            .filter { !usedIDs.contains($0.id) }
        options.insert(PokemonNamedValue(id: 0, name: language == .italian ? "Nessuno" : "None"), at: 0)
        if selectedID != 0, !options.contains(where: { $0.id == selectedID }) {
            options.append(PokemonNamedValue(id: selectedID, name: itemDisplayName(selectedID, pocket: pocket)))
        }
        return options.sorted { $0.id < $1.id }
    }

    private func compatibleItemOptions(for pocket: SaveBagPocketKind) -> [PokemonNamedValue] {
        let items = compatibleItems(for: pocket)
        if !items.isEmpty {
            return items.map { PokemonNamedValue(id: $0.id, name: bagDisplayName(for: $0, pocket: pocket)) }
        }
        return fallbackItemIDs(for: pocket).map { id in
            PokemonNamedValue(id: id, name: pocket == .machines ? machineName(for: id, fallback: document.referenceItemName(id: id)) : document.referenceItemName(id: id))
        }
    }

    private func compatibleItems(for pocket: SaveBagPocketKind) -> [ItemData] {
        guard !document.itemData.isEmpty else { return [] }
        return document.itemData.filter { item in
            switch pocket {
            case .items:
                return item.pocket == 1 && ![.balls, .berries, .key, .tm].contains(item.itemCategory)
            case .keyItems:
                return item.itemCategory == .key
            case .balls:
                return item.itemCategory == .balls
            case .machines:
                return item.itemCategory == .tm
            case .berries:
                return item.itemCategory == .berries
            }
        }
    }

    private func defaultItemID(for pocket: SaveBagPocket) -> Int? {
        let usedIDs = Set(pocket.items.map(\.itemID))
        return compatibleItemOptions(for: pocket.kind).first { !usedIDs.contains($0.id) }?.id
    }

    private func isItemAllowed(_ itemID: Int, in pocket: SaveBagPocketKind, slot: Int) -> Bool {
        guard itemID != 0 else { return true }
        let duplicate = document.playerSave?.bagPockets.first { $0.kind == pocket }?.items.contains { $0.slot != slot && $0.itemID == itemID } == true
        guard !duplicate else { return false }
        return compatibleItemOptions(for: pocket).contains(where: { $0.id == itemID })
    }

    private func itemDisplayName(_ itemID: Int, pocket: SaveBagPocketKind) -> String {
        guard itemID != 0 else { return language == .italian ? "Nessuno" : "None" }
        if let item = document.itemData.first(where: { $0.id == itemID }) {
            return bagDisplayName(for: item, pocket: pocket)
        }
        return "\(language == .italian ? "Oggetto" : "Item") #\(itemID)"
    }

    private func bagDisplayName(for item: ItemData, pocket: SaveBagPocketKind) -> String {
        let name = item.displayName(language: language)
        if pocket == .machines {
            return machineName(for: item.id, fallback: name)
        }
        return name
    }

    private func machineName(for itemID: Int, fallback: String) -> String {
        if (289...338).contains(itemID) {
            return String(format: "MT%02d - %@", itemID - 288, fallback)
        }
        if (339...346).contains(itemID) {
            return String(format: "MN%02d - %@", itemID - 338, fallback)
        }
        return fallback
    }

    private func fallbackItemIDs(for pocket: SaveBagPocketKind) -> [Int] {
        switch pocket {
        case .items:
            return Array(13...132) + Array(176...258)
        case .keyItems:
            return Array(259...288)
        case .balls:
            return Array(1...12)
        case .machines:
            return Array(289...346)
        case .berries:
            return Array(133...175)
        }
    }
}

struct SaveTrainerView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let save = document.playerSave {
            ScrollView {
                EditorCardGrid {
                    Panel(title: language == .italian ? "Allenatore" : "Trainer") {
                        ReadOnlyRow(title: L10n.text("name", language: language), value: save.trainer.name ?? unavailable)
                        ReadOnlyRow(title: L10n.text("gender", language: language), value: genderText(save.trainer.gender))
                        ReadOnlyRow(title: "Trainer ID", value: save.trainer.trainerID.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: "Secret ID", value: save.trainer.secretID.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: language == .italian ? "Denaro" : "Money", value: save.money.map { "₽\($0)" } ?? unavailable)
                        ReadOnlyRow(title: language == .italian ? "Monete Casinò" : "Casino coins", value: save.coins.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: "Battle Points", value: unavailable)
                    }
                    Panel(title: language == .italian ? "Stato" : "Status") {
                        ReadOnlyRow(title: language == .italian ? "Tempo di gioco" : "Play time", value: save.playTime?.displayValue ?? unavailable)
                        ReadOnlyRow(title: language == .italian ? "Medaglie" : "Badges", value: save.progression.badges.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: language == .italian ? "Pokédex nazionale" : "National Pokédex", value: save.trainer.nationalDexUnlocked.map { L10n.yesNo($0, language: language) } ?? unavailable)
                    }
                }
                .padding(EditorLayout.detailPadding)
            }
            .navigationTitle(L10n.text("trainer", language: language))
        } else {
            PlaceholderView(title: L10n.text("no.save.open", language: language), systemImage: "person.crop.circle.fill", message: L10n.text("open.save.instruction", language: language))
        }
    }

    private var unavailable: String { language == .italian ? "Non disponibile" : "Not available" }

    private func genderText(_ value: Int?) -> String {
        guard let value else { return unavailable }
        return value == 0 ? L10n.text("male", language: language) : L10n.text("female", language: language)
    }
}

struct SavePokedexView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @State private var filter: PokedexFilter = .all
    @State private var confirmation: PokedexBulkAction?

    private enum PokedexFilter: String, CaseIterable, Identifiable {
        case all, seen, caught, missing
        var id: String { rawValue }

        func title(language: AppLanguage) -> String {
            switch self {
            case .all: language == .italian ? "Tutti" : "All"
            case .seen: language == .italian ? "Visti" : "Seen"
            case .caught: language == .italian ? "Catturati" : "Caught"
            case .missing: language == .italian ? "Mancanti" : "Missing"
            }
        }
    }

    private enum PokedexBulkAction: String, Identifiable {
        case markSeen, complete
        var id: String { rawValue }

        func title(language: AppLanguage) -> String {
            switch self {
            case .markSeen: language == .italian ? "Segna tutti come visti" : "Mark all as seen"
            case .complete: language == .italian ? "Completa Pokédex" : "Complete Pokédex"
            }
        }

        func message(language: AppLanguage) -> String {
            switch self {
            case .markSeen: language == .italian ? "Impostare tutte le specie supportate come viste?" : "Mark every supported species as seen?"
            case .complete: language == .italian ? "Impostare tutte le specie supportate come viste e catturate?" : "Mark every supported species as seen and caught?"
            }
        }
    }

    var body: some View {
        if let pokedex = document.playerSave?.pokedex {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("pokedex", language: language))
                            .font(.title2.weight(.semibold))
                        Text("\(language == .italian ? "Visti" : "Seen"): \(pokedex.seenCount) · \(language == .italian ? "Catturati" : "Caught"): \(pokedex.caughtCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(PokedexBulkAction.markSeen.title(language: language)) { confirmation = .markSeen }
                    Button(PokedexBulkAction.complete.title(language: language)) { confirmation = .complete }
                }

                Picker("", selection: $filter) {
                    ForEach(PokedexFilter.allCases) { filter in
                        Text(filter.title(language: language)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)

                List(filteredEntries(pokedex.entries)) { entry in
                    HStack(spacing: 16) {
                        Text(String(format: "#%03d %@", entry.id, pokedexSpeciesName(entry.id)))
                            .font(.headline)
                            .lineLimit(1)
                            .frame(minWidth: 220, alignment: .leading)
                        Spacer()
                        Toggle(language == .italian ? "Visto" : "Seen", isOn: seenBinding(entry))
                            .toggleStyle(.checkbox)
                        Toggle(language == .italian ? "Catturato" : "Caught", isOn: caughtBinding(entry))
                            .toggleStyle(.checkbox)
                    }
                        .padding(.vertical, 2)
                }
            }
            .padding(EditorLayout.detailPadding)
            .confirmationDialog(
                confirmation?.title(language: language) ?? "",
                isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                presenting: confirmation
            ) { action in
                Button(action.title(language: language), role: action == .complete ? .destructive : nil) {
                    applyBulkAction(action, entries: pokedex.entries)
                    confirmation = nil
                }
                Button(language == .italian ? "Annulla" : "Cancel", role: .cancel) { confirmation = nil }
            } message: { action in
                Text(action.message(language: language))
            }
            .navigationTitle(L10n.text("pokedex", language: language))
        } else {
            SaveReadOnlyUnavailableView(title: L10n.text("pokedex", language: language), systemImage: "book.closed.fill")
        }
    }

    private func filteredEntries(_ entries: [SavePokedexEntry]) -> [SavePokedexEntry] {
        switch filter {
        case .all: entries
        case .seen: entries.filter(\.seen)
        case .caught: entries.filter(\.caught)
        case .missing: entries.filter { !$0.seen && !$0.caught }
        }
    }

    private func seenBinding(_ entry: SavePokedexEntry) -> Binding<Bool> {
        Binding {
            currentEntry(entry.id)?.seen ?? entry.seen
        } set: { newValue in
            let caught = currentEntry(entry.id)?.caught ?? entry.caught
            document.updatePokedexEntry(speciesID: entry.id, seen: newValue || caught, caught: caught && newValue)
        }
    }

    private func caughtBinding(_ entry: SavePokedexEntry) -> Binding<Bool> {
        Binding {
            currentEntry(entry.id)?.caught ?? entry.caught
        } set: { newValue in
            let seen = currentEntry(entry.id)?.seen ?? entry.seen
            document.updatePokedexEntry(speciesID: entry.id, seen: seen || newValue, caught: newValue)
        }
    }

    private func currentEntry(_ id: Int) -> SavePokedexEntry? {
        document.playerSave?.pokedex?.entries.first { $0.id == id }
    }

    private func applyBulkAction(_ action: PokedexBulkAction, entries: [SavePokedexEntry]) {
        switch action {
        case .markSeen:
            document.updatePokedexEntries(entries.map { SavePokedexEntry(id: $0.id, seen: true, caught: $0.caught) })
        case .complete:
            document.updatePokedexEntries(entries.map { SavePokedexEntry(id: $0.id, seen: true, caught: true) })
        }
    }

    private func pokedexSpeciesName(_ id: Int) -> String {
        let resolved = document.referenceSpeciesName(id: id)
        if !resolved.hasPrefix("Species #") { return resolved }
        return Self.nationalDexNames.indices.contains(id - 1) ? Self.nationalDexNames[id - 1] : resolved
    }

    private static let nationalDexNames = (
        "Bulbasaur|Ivysaur|Venusaur|Charmander|Charmeleon|Charizard|Squirtle|Wartortle|Blastoise|Caterpie|Metapod|Butterfree|Weedle|Kakuna|Beedrill|Pidgey|Pidgeotto|Pidgeot|Rattata|Raticate|Spearow|Fearow|Ekans|Arbok|Pikachu|Raichu|Sandshrew|Sandslash|Nidoran F|Nidorina|Nidoqueen|Nidoran M|Nidorino|Nidoking|Clefairy|Clefable|Vulpix|Ninetales|Jigglypuff|Wigglytuff|Zubat|Golbat|Oddish|Gloom|Vileplume|Paras|Parasect|Venonat|Venomoth|Diglett|Dugtrio|Meowth|Persian|Psyduck|Golduck|Mankey|Primeape|Growlithe|Arcanine|Poliwag|Poliwhirl|Poliwrath|Abra|Kadabra|Alakazam|Machop|Machoke|Machamp|Bellsprout|Weepinbell|Victreebel|Tentacool|Tentacruel|Geodude|Graveler|Golem|Ponyta|Rapidash|Slowpoke|Slowbro|Magnemite|Magneton|Farfetch'd|Doduo|Dodrio|Seel|Dewgong|Grimer|Muk|Shellder|Cloyster|Gastly|Haunter|Gengar|Onix|Drowzee|Hypno|Krabby|Kingler|Voltorb|Electrode|Exeggcute|Exeggutor|Cubone|Marowak|Hitmonlee|Hitmonchan|Lickitung|Koffing|Weezing|Rhyhorn|Rhydon|Chansey|Tangela|Kangaskhan|Horsea|Seadra|Goldeen|Seaking|Staryu|Starmie|Mr. Mime|Scyther|Jynx|Electabuzz|Magmar|Pinsir|Tauros|Magikarp|Gyarados|Lapras|Ditto|Eevee|Vaporeon|Jolteon|Flareon|Porygon|Omanyte|Omastar|Kabuto|Kabutops|Aerodactyl|Snorlax|Articuno|Zapdos|Moltres|Dratini|Dragonair|Dragonite|Mewtwo|Mew|Chikorita|Bayleef|Meganium|Cyndaquil|Quilava|Typhlosion|Totodile|Croconaw|Feraligatr|Sentret|Furret|Hoothoot|Noctowl|Ledyba|Ledian|Spinarak|Ariados|Crobat|Chinchou|Lanturn|Pichu|Cleffa|Igglybuff|Togepi|Togetic|Natu|Xatu|Mareep|Flaaffy|Ampharos|Bellossom|Marill|Azumarill|Sudowoodo|Politoed|Hoppip|Skiploom|Jumpluff|Aipom|Sunkern|Sunflora|Yanma|Wooper|Quagsire|Espeon|Umbreon|Murkrow|Slowking|Misdreavus|Unown|Wobbuffet|Girafarig|Pineco|Forretress|Dunsparce|Gligar|Steelix|Snubbull|Granbull|Qwilfish|Scizor|Shuckle|Heracross|Sneasel|Teddiursa|Ursaring|Slugma|Magcargo|Swinub|Piloswine|Corsola|Remoraid|Octillery|Delibird|Mantine|Skarmory|Houndour|Houndoom|Kingdra|Phanpy|Donphan|Porygon2|Stantler|Smeargle|Tyrogue|Hitmontop|Smoochum|Elekid|Magby|Miltank|Blissey|Raikou|Entei|Suicune|Larvitar|Pupitar|Tyranitar|Lugia|Ho-Oh|Celebi|Treecko|Grovyle|Sceptile|Torchic|Combusken|Blaziken|Mudkip|Marshtomp|Swampert|Poochyena|Mightyena|Zigzagoon|Linoone|Wurmple|Silcoon|Beautifly|Cascoon|Dustox|Lotad|Lombre|Ludicolo|Seedot|Nuzleaf|Shiftry|Taillow|Swellow|Wingull|Pelipper|Ralts|Kirlia|Gardevoir|Surskit|Masquerain|Shroomish|Breloom|Slakoth|Vigoroth|Slaking|Nincada|Ninjask|Shedinja|Whismur|Loudred|Exploud|Makuhita|Hariyama|Azurill|Nosepass|Skitty|Delcatty|Sableye|Mawile|Aron|Lairon|Aggron|Meditite|Medicham|Electrike|Manectric|Plusle|Minun|Volbeat|Illumise|Roselia|Gulpin|Swalot|Carvanha|Sharpedo|Wailmer|Wailord|Numel|Camerupt|Torkoal|Spoink|Grumpig|Spinda|Trapinch|Vibrava|Flygon|Cacnea|Cacturne|Swablu|Altaria|Zangoose|Seviper|Lunatone|Solrock|Barboach|Whiscash|Corphish|Crawdaunt|Baltoy|Claydol|Lileep|Cradily|Anorith|Armaldo|Feebas|Milotic|Castform|Kecleon|Shuppet|Banette|Duskull|Dusclops|Tropius|Chimecho|Absol|Wynaut|Snorunt|Glalie|Spheal|Sealeo|Walrein|Clamperl|Huntail|Gorebyss|Relicanth|Luvdisc|Bagon|Shelgon|Salamence|Beldum|Metang|Metagross|Regirock|Regice|Registeel|Latias|Latios|Kyogre|Groudon|Rayquaza|Jirachi|Deoxys"
    ).components(separatedBy: "|")
}

struct SaveProgressionView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let save = document.playerSave {
            ScrollView {
                EditorCardGrid {
                    Panel(title: L10n.text("progress", language: language)) {
                        ReadOnlyRow(title: language == .italian ? "Medaglie ottenute" : "Badges", value: save.progression.badges.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: "Map group", value: save.progression.mapGroup.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: "Map number", value: save.progression.mapNumber.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: "X", value: save.progression.x.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: "Y", value: save.progression.y.map(String.init) ?? unavailable)
                        ReadOnlyRow(title: language == .italian ? "Respawn/heal" : "Respawn/heal", value: save.progression.healLocation ?? unavailable)
                    }
                }
                .padding(EditorLayout.detailPadding)
            }
            .navigationTitle(L10n.text("progress", language: language))
        } else {
            PlaceholderView(title: L10n.text("no.save.open", language: language), systemImage: "flag.checkered", message: L10n.text("open.save.instruction", language: language))
        }
    }

    private var unavailable: String { language == .italian ? "Non disponibile" : "Not available" }
}

struct SaveAdvancedView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language

    var body: some View {
        if let save = document.playerSave {
            List {
                Section(language == .italian ? "Save attivo" : "Active save") {
                    LabeledContent("Save index", value: "\(save.activeSaveIndex)")
                    LabeledContent(language == .italian ? "Slot attivo" : "Active slot", value: "\(save.activeSlot)")
                    LabeledContent("Save block", value: String(format: "0x%08X", save.saveBlockOffset))
                    LabeledContent("SaveBlock1", value: String(format: "0x%08X", save.saveBlock1SectionOffset))
                    LabeledContent("Party count offset", value: String(format: "0x%08X", save.partyCountOffset))
                }
                Section(language == .italian ? "Sezioni" : "Sections") {
                    ForEach(save.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Section \(section.sectionID)")
                                .font(.headline)
                            Text(String(format: "Offset 0x%08X · Save index %u", section.offset, section.saveIndex))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "Checksum 0x%04X / 0x%04X · %@", section.storedChecksum, section.calculatedChecksum, section.checksumValid ? "OK" : L10n.text("warning", language: language)))
                                .font(.caption)
                                .foregroundStyle(section.checksumValid ? Color.secondary : Color.orange)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(L10n.text("advanced", language: language))
        } else {
            PlaceholderView(title: L10n.text("no.save.open", language: language), systemImage: "slider.horizontal.3", message: L10n.text("open.save.instruction", language: language))
        }
    }
}

struct SaveReadOnlyUnavailableView: View {
    let title: String
    let systemImage: String

    var body: some View {
        PlaceholderView(title: title, systemImage: systemImage, message: "Funzione non ancora supportata")
            .navigationTitle(title)
    }
}

struct SaveSectionPlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        PlaceholderView(title: title, systemImage: systemImage, message: message)
            .navigationTitle(title)
    }
}

struct PlayerPartyEditorView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @State private var selectedPokemonID: PlayerPartyPokemon.ID?
    @State private var selectedDetailSection: PartyDetailSection = .general
    @State private var isAdvancedExpanded = false

    private enum PartyDetailSection: String, CaseIterable, Identifiable {
        case general
        case moves
        case ivEV
        case advanced

        var id: String { rawValue }

        func title(language: AppLanguage) -> String {
            switch self {
            case .general: language == .italian ? "Generale" : "General"
            case .moves: L10n.text("moves", language: language)
            case .ivEV: "IV / EV"
            case .advanced: language == .italian ? "Avanzate" : "Advanced"
            }
        }
    }

    private var selectedPokemon: PlayerPartyPokemon? {
        guard let selectedPokemonID else { return document.playerSave?.party.first }
        return document.playerSave?.party.first { $0.id == selectedPokemonID }
    }

    var body: some View {
        if let save = document.playerSave {
            HStack(spacing: 0) {
                partyList(save)
                    .frame(minWidth: EditorLayout.listMinWidth, idealWidth: EditorLayout.listIdealWidth, maxWidth: EditorLayout.listMaxWidth, maxHeight: .infinity)
                Divider()
                detail(save)
                    .frame(minWidth: EditorLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .onAppear(perform: selectInitialPokemon)
            .onChange(of: document.playerSave?.party) { _ in selectInitialPokemon() }
        } else {
            PlaceholderView(
                title: L10n.text("no.save.open", language: language),
                systemImage: "doc.badge.plus",
                message: L10n.text("open.save.instruction", language: language)
            )
        }
    }

    private func partyList(_ save: PlayerSaveData) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(save.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(L10n.text("party", language: language)) \(save.party.count)/6 · \(L10n.text("save.index", language: language)) \(save.activeSaveIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(save.allSectionChecksumsValid ? "Checksum sezioni OK" : "Checksum sezioni non perfetti")
                    .font(.caption)
                    .foregroundStyle(save.allSectionChecksumsValid ? Color.secondary : Color.orange)

                Divider()

                Button {
                    document.linkSaveReferenceROM()
                } label: {
                    Label(language == .italian ? "Associa ROM..." : "Link ROM...", systemImage: "link")
                }
                .buttonStyle(.bordered)

                Text(document.linkedSaveROMURL?.lastPathComponent ?? (language == .italian ? "Nessuna ROM associata: uso placeholder." : "No linked ROM: using placeholders."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EditorLayout.listPadding)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(0..<6, id: \.self) { slot in
                        if let pokemon = pokemon(in: save, slot: slot) {
                            Button {
                                selectedPokemonID = pokemon.id
                            } label: {
                                partySlotCard(pokemon, isSelected: selectedPokemonID == pokemon.id)
                            }
                            .buttonStyle(.plain)
                        } else {
                            emptySlotCard(slot: slot)
                        }
                    }
                }
                .padding(EditorLayout.listPadding)
            }
        }
        .navigationTitle(L10n.text("player.party", language: language))
    }

    @ViewBuilder
    private func detail(_ save: PlayerSaveData) -> some View {
        if let pokemon = selectedPokemon {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    partyHeader(pokemon)

                    Picker("", selection: $selectedDetailSection) {
                        ForEach(PartyDetailSection.allCases) { section in
                            Text(section.title(language: language)).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 560)

                    selectedDetailContent(pokemon)
                }
                .padding(EditorLayout.detailPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(pokemon.nickname)
        } else {
            PlaceholderView(title: L10n.text("empty.party", language: language), systemImage: "person.crop.circle.badge.questionmark", message: L10n.text("party.empty.message", language: language))
        }
    }

    private func pokemon(in save: PlayerSaveData, slot: Int) -> PlayerPartyPokemon? {
        save.party.first { $0.slot == slot }
    }

    private func partySlotCard(_ pokemon: PlayerPartyPokemon, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            spriteView(for: pokemon, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(pokemon.nickname)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(speciesName(pokemon.species)) • Lv. \(pokemon.level)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: isSelected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func emptySlotCard(slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
            Text(language == .italian ? "Slot vuoto" : "Empty slot")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Slot \(slot + 1)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.secondary.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func partyHeader(_ pokemon: PlayerPartyPokemon) -> some View {
        EditorHeaderCard {
            EditorSpriteBox {
                spriteContent(for: pokemon)
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(pokemon.nickname)
                    .font(.title.weight(.semibold))
                    .lineLimit(1)
                Text("\(speciesName(pokemon.species)) • Lv. \(pokemon.level)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Chip(pokemon.natureName)
                    Chip(genderDescription(for: pokemon))
                    if pokemon.isShiny { Chip("Shiny") }
                }
            }
        }
    }

    @ViewBuilder
    private func selectedDetailContent(_ pokemon: PlayerPartyPokemon) -> some View {
        switch selectedDetailSection {
        case .general:
            generalSection(pokemon)
        case .moves:
            movesSection(pokemon)
        case .ivEV:
            ivEVSection(pokemon)
        case .advanced:
            advancedSection(pokemon)
        }
    }

    private func generalSection(_ pokemon: PlayerPartyPokemon) -> some View {
        EditorCardGrid {
            Panel(title: language == .italian ? "Generale" : "General") {
                EditorRow(title: "Nickname") {
                    TextField("Nickname", text: Binding(
                        get: { selectedPokemon?.nickname ?? pokemon.nickname },
                        set: { newValue in
                            updatePokemon(pokemon) { updated in
                                updated.nickname = String(newValue.prefix(10))
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                ReadOnlyRow(title: L10n.text("species", language: language), value: "\(speciesName(pokemon.species)) (#\(pokemon.species))")
                ReadOnlyRow(title: L10n.text("level", language: language), value: "\(pokemon.level)")
                NumericRow(L10n.text("experience", language: language), value: intBinding(pokemon, get: { Int($0.experience) }, set: { $0.experience = UInt32(max(0, $1)) }), range: 0...1_640_000)
                NumericRow(L10n.text("friendship", language: language), value: intBinding(pokemon, get: \.friendship, set: { $0.friendship = $1 }), range: 0...255)
                ReadOnlyRow(title: L10n.text("nature", language: language), value: "\(pokemon.natureName) · \(natureEffectText(for: pokemon))")
                ReadOnlyRow(title: L10n.text("gender", language: language), value: genderDescription(for: pokemon))
                ReadOnlyRow(title: L10n.text("ability", language: language), value: "#\(pokemon.abilityNum + 1) \(abilityName(for: pokemon))")
                PickerRow(title: L10n.text("item", language: language), selection: intBinding(pokemon, get: \.heldItem, set: { $0.heldItem = $1 }), options: itemOptions(for: pokemon.heldItem))
            }
            Panel(title: L10n.text("statistics", language: language)) {
                currentStatRows(pokemon)
            }
        }
    }

    private func movesSection(_ pokemon: PlayerPartyPokemon) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    moveCard(pokemon, index: index)
                }
            }
            Panel(title: "PP bonus") {
                NumericRow("PP bonus", value: intBinding(pokemon, get: \.ppBonuses, set: { $0.ppBonuses = $1 }), range: 0...255)
            }
        }
    }

    private func moveCard(_ pokemon: PlayerPartyPokemon, index: Int) -> some View {
        let moveID = pokemon.moves.indices.contains(index) ? pokemon.moves[index] : 0
        let currentPP = pokemon.pp.indices.contains(index) ? pokemon.pp[index] : 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(L10n.text("move.number", language: language)) \(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(moveName(moveID))
                .font(.headline)
                .lineLimit(1)
            Text("PP \(currentPP) / \(maxPP(for: moveID, pokemon: pokemon, index: index))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: moveBinding(pokemon, index: index)) {
                ForEach(moveOptions(for: moveID)) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Text("PP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(currentPP)")
                    .font(.body.monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
                Stepper("PP", value: ppBinding(pokemon, index: index), in: 0...255)
                    .labelsHidden()
                    .frame(width: EditorLayout.stepperWidth)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func ivEVSection(_ pokemon: PlayerPartyPokemon) -> some View {
        EditorCardGrid {
            Panel(title: "IV") {
                editableStatRows(pokemon, keyPath: \.ivs, range: 0...31)
            }
            Panel(title: "EV") {
                ReadOnlyRow(title: language == .italian ? "EV totali" : "Total EVs", value: "\(evTotal(pokemon.evs)) / 510")
                editableStatRows(pokemon, keyPath: \.evs, range: 0...255)
            }
            Panel(title: L10n.text("statistics", language: language)) {
                currentStatRows(pokemon)
            }
        }
    }

    private func advancedSection(_ pokemon: PlayerPartyPokemon) -> some View {
        Panel(title: language == .italian ? "Avanzate" : "Advanced") {
            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                ReadOnlyRow(title: "PID", value: String(format: "0x%08X", pokemon.personality))
                ReadOnlyRow(title: "OT ID", value: String(format: "0x%08X", pokemon.otID))
                ReadOnlyRow(title: L10n.text("pokemon.checksum", language: language), value: pokemon.checksumValid ? "OK" : L10n.text("warning", language: language))
                ReadOnlyRow(title: L10n.text("pokerus", language: language), value: "\(pokemon.pokerus)")
                ReadOnlyRow(title: L10n.text("pokeball", language: language), value: "\(document.referencePokeballName(id: pokemon.pokeball)) (#\(pokemon.pokeball))")
                ReadOnlyRow(title: L10n.text("met.location", language: language), value: document.referenceLocationName(id: pokemon.metLocation))
                ReadOnlyRow(title: L10n.text("met.level", language: language), value: "\(pokemon.metLevel)")
                ReadOnlyRow(title: L10n.text("egg", language: language), value: L10n.yesNo(pokemon.isEgg, language: language))
                ReadOnlyRow(title: L10n.text("ability.slot", language: language), value: "#\(pokemon.abilityNum + 1)")
            } label: {
                Text(language == .italian ? "Dati tecnici" : "Technical data")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private func editableStatRows(_ pokemon: PlayerPartyPokemon, keyPath: WritableKeyPath<PlayerPartyPokemon, PokemonStatSpread>, range: ClosedRange<Int>) -> some View {
        NumericRow(L10n.text("hp", language: language), value: statBinding(pokemon, keyPath: keyPath, stat: \.hp), range: range)
        NumericRow(L10n.text("attack", language: language), value: statBinding(pokemon, keyPath: keyPath, stat: \.attack), range: range)
        NumericRow(L10n.text("defense", language: language), value: statBinding(pokemon, keyPath: keyPath, stat: \.defense), range: range)
        NumericRow(L10n.text("special.attack", language: language), value: statBinding(pokemon, keyPath: keyPath, stat: \.specialAttack), range: range)
        NumericRow(L10n.text("special.defense", language: language), value: statBinding(pokemon, keyPath: keyPath, stat: \.specialDefense), range: range)
        NumericRow(L10n.text("speed", language: language), value: statBinding(pokemon, keyPath: keyPath, stat: \.speed), range: range)
    }

    @ViewBuilder
    private func currentStatRows(_ pokemon: PlayerPartyPokemon) -> some View {
        ReadOnlyRow(title: L10n.text("hp", language: language), value: "\(pokemon.currentHP)/\(pokemon.maxHP)")
        ReadOnlyRow(title: L10n.text("attack", language: language), value: "\(pokemon.attack)")
        ReadOnlyRow(title: L10n.text("defense", language: language), value: "\(pokemon.defense)")
        ReadOnlyRow(title: L10n.text("special.attack", language: language), value: "\(pokemon.specialAttack)")
        ReadOnlyRow(title: L10n.text("special.defense", language: language), value: "\(pokemon.specialDefense)")
        ReadOnlyRow(title: L10n.text("speed", language: language), value: "\(pokemon.speed)")
    }

    private func selectInitialPokemon() {
        guard let party = document.playerSave?.party, !party.isEmpty else {
            selectedPokemonID = nil
            return
        }
        if selectedPokemonID == nil || !party.contains(where: { $0.id == selectedPokemonID }) {
            selectedPokemonID = party.first?.id
        }
    }

    private func speciesName(_ id: Int) -> String {
        document.referenceSpeciesName(id: id)
    }

    private func moveName(_ id: Int) -> String {
        document.referenceMoveName(id: id)
    }

    private func itemName(_ id: Int) -> String {
        document.referenceItemName(id: id)
    }

    private func itemOptions(for selectedID: Int) -> [PokemonNamedValue] {
        document.referenceItemOptions(including: selectedID)
    }

    private func moveOptions(for selectedID: Int) -> [PokemonNamedValue] {
        document.referenceMoveOptions(including: selectedID)
    }

    private func updatePokemon(_ pokemon: PlayerPartyPokemon, mutate: (inout PlayerPartyPokemon) -> Void) {
        var updated = selectedPokemon ?? pokemon
        mutate(&updated)
        document.updatePlayerPartyPokemon(updated)
    }

    private func intBinding(_ pokemon: PlayerPartyPokemon, get: @escaping (PlayerPartyPokemon) -> Int, set: @escaping (inout PlayerPartyPokemon, Int) -> Void) -> Binding<Int> {
        Binding {
            selectedPokemon.map(get) ?? get(pokemon)
        } set: { newValue in
            updatePokemon(pokemon) { updated in
                set(&updated, newValue)
            }
        }
    }

    private func statBinding(_ pokemon: PlayerPartyPokemon, keyPath: WritableKeyPath<PlayerPartyPokemon, PokemonStatSpread>, stat: WritableKeyPath<PokemonStatSpread, Int>) -> Binding<Int> {
        Binding {
            (selectedPokemon ?? pokemon)[keyPath: keyPath][keyPath: stat]
        } set: { newValue in
            updatePokemon(pokemon) { updated in
                updated[keyPath: keyPath][keyPath: stat] = newValue
            }
        }
    }

    private func moveBinding(_ pokemon: PlayerPartyPokemon, index: Int) -> Binding<Int> {
        Binding {
            let current = selectedPokemon ?? pokemon
            return current.moves.indices.contains(index) ? current.moves[index] : 0
        } set: { newValue in
            updatePokemon(pokemon) { updated in
                while updated.moves.count <= index { updated.moves.append(0) }
                updated.moves[index] = newValue
            }
        }
    }

    private func ppBinding(_ pokemon: PlayerPartyPokemon, index: Int) -> Binding<Int> {
        Binding {
            let current = selectedPokemon ?? pokemon
            return current.pp.indices.contains(index) ? current.pp[index] : 0
        } set: { newValue in
            updatePokemon(pokemon) { updated in
                while updated.pp.count <= index { updated.pp.append(0) }
                updated.pp[index] = newValue
            }
        }
    }

    private func abilityName(for pokemon: PlayerPartyPokemon) -> String {
        guard let species = document.pokemonSpecies.first(where: { $0.id == pokemon.species }) else { return "" }
        let abilityID = pokemon.abilityNum == 0 ? species.ability1 : species.ability2
        return document.pokemonAbilities.first { $0.id == abilityID }?.name ?? "Ability #\(abilityID)"
    }

    private func genderDescription(for pokemon: PlayerPartyPokemon) -> String {
        guard let species = document.pokemonSpecies.first(where: { $0.id == pokemon.species }) else { return L10n.text("pid.based", language: language) }
        switch species.genderRatio {
        case 0xFF: return L10n.text("genderless", language: language)
        case 0xFE: return L10n.text("female", language: language)
        case 0x00: return L10n.text("male", language: language)
        default:
            let value = Int(pokemon.personality & 0xFF)
            return value < species.genderRatio ? L10n.text("female", language: language) : L10n.text("male", language: language)
        }
    }

    private func sprite(for pokemon: PlayerPartyPokemon) -> NSImage? {
        document.linkedSavePokemonSprite(forSpeciesID: pokemon.species)
    }

    private func spriteView(for pokemon: PlayerPartyPokemon, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
            spriteContent(for: pokemon)
                .padding(5)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
    }

    @ViewBuilder
    private func spriteContent(for pokemon: PlayerPartyPokemon) -> some View {
        if let sprite = sprite(for: pokemon) {
            Image(nsImage: sprite)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    private func evTotal(_ spread: PokemonStatSpread) -> Int {
        spread.hp + spread.attack + spread.defense + spread.specialAttack + spread.specialDefense + spread.speed
    }

    private func maxPP(for moveID: Int, pokemon: PlayerPartyPokemon, index: Int) -> Int {
        let basePP = document.moves.first { $0.id == moveID }?.pp ?? 0
        guard basePP > 0 else { return 0 }
        let ppUps = (pokemon.ppBonuses >> (index * 2)) & 0x03
        return basePP * (5 + ppUps) / 5
    }

    private func natureEffectText(for pokemon: PlayerPartyPokemon) -> String {
        guard let effect = natureEffect(for: pokemon.natureIndex) else {
            return language == .italian ? "Nessuna modifica alle statistiche" : "No stat changes"
        }
        return "\(effect.increased) +10%, \(effect.decreased) -10%"
    }

    private func natureEffect(for index: Int) -> (increased: String, decreased: String)? {
        let attack = L10n.text("attack", language: language)
        let defense = L10n.text("defense", language: language)
        let speed = L10n.text("speed", language: language)
        let specialAttack = L10n.text("special.attack", language: language)
        let specialDefense = L10n.text("special.defense", language: language)
        switch index {
        case 1: return (attack, defense)
        case 2: return (attack, speed)
        case 3: return (attack, specialAttack)
        case 4: return (attack, specialDefense)
        case 5: return (defense, attack)
        case 7: return (defense, speed)
        case 8: return (defense, specialAttack)
        case 9: return (defense, specialDefense)
        case 10: return (speed, attack)
        case 11: return (speed, defense)
        case 13: return (speed, specialAttack)
        case 14: return (speed, specialDefense)
        case 15: return (specialAttack, attack)
        case 16: return (specialAttack, defense)
        case 17: return (specialAttack, speed)
        case 19: return (specialAttack, specialDefense)
        case 20: return (specialDefense, attack)
        case 21: return (specialDefense, defense)
        case 22: return (specialDefense, speed)
        case 23: return (specialDefense, specialAttack)
        default: return nil
        }
    }
}

private enum WildEncounterMapOrder: String, CaseIterable, Identifiable {
    case rom
    case alphabetical
    case storyProgression

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .rom:
            return language == .italian ? "Ordine ROM" : "ROM Order"
        case .alphabetical:
            return language == .italian ? "Alfabetico" : "Alphabetical"
        case .storyProgression:
            return language == .italian ? "Progressione storia" : "Story Progression"
        }
    }
}

struct WildEncounterEditorView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var showingHex: Bool
    @State private var searchText = ""
    @State private var selectedMapID: MapData.ID?
    @State private var mapOrder = WildEncounterMapOrder.rom
    @State private var selectedEncounterKind: WildEncounterKind?
    @State private var onlyModified = false

    private var filteredMaps: [MapData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let availableMaps = onlyModified ? document.maps.filter { map in
            area(for: map).map { document.isEncounterAreaModified($0.id) } == true
        } : document.maps
        let matches = query.isEmpty ? availableMaps : availableMaps.filter { map in
            MapNameResolver.shared.mapName(group: map.group, map: map.mapID, language: language).lowercased().contains(query)
                || "\(map.group).\(map.mapID)".contains(query)
                || area(for: map)?.groups.contains { $0.kind.title.lowercased().contains(query) } == true
        }
        return sortedMaps(matches)
    }

    private var selectedMap: MapData? {
        guard let selectedMapID else { return document.maps.first }
        return document.maps.first { $0.id == selectedMapID }
    }

    var body: some View {
        HStack(spacing: 0) {
            mapList
                .frame(minWidth: EditorLayout.listMinWidth, idealWidth: EditorLayout.listIdealWidth, maxWidth: EditorLayout.listMaxWidth, maxHeight: .infinity)
            Divider()
            detail
                .frame(minWidth: EditorLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            selectInitialMap()
        }
        .onChange(of: document.maps) { _ in
            selectInitialMap()
        }
        .onChange(of: document.wildEncounterAreas.count) { _ in
            selectInitialMap()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let map = selectedMap {
            if let area = area(for: map) {
                WildEncounterDetailEditor(
                    area: binding(for: area),
                    species: document.pokemonSpecies.map { PokemonNamedValue(id: $0.id, name: $0.name) },
                    displayName: MapNameResolver.shared.mapName(group: map.group, map: map.mapID, language: language),
                    selectedKind: $selectedEncounterKind,
                    pokemonSpriteProvider: { speciesID in
                        document.pokemonSprite(forSpeciesID: speciesID)
                    },
                    showInHex: { group in
                        document.select(group.tableOffset)
                        showingHex = true
                    }
                )
                .id(area.id)
            } else {
                PlaceholderView(
                    title: L10n.text("no.wild.encounter.available", language: language),
                    systemImage: "leaf",
                    message: "\(MapNameResolver.shared.mapName(group: map.group, map: map.mapID, language: language)) \(L10n.text("map.no.encounter.table", language: language))"
                )
            }
        } else {
            PlaceholderView(title: L10n.text("no.wild.encounters", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.encounters", language: language))
        }
    }

    private var mapList: some View {
        VStack(spacing: 0) {
            TextField(L10n.text("search.maps", language: language), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, EditorLayout.listPadding)
                .padding(.top, EditorLayout.listPadding)
                .padding(.bottom, 8)
            if document.supportsVanillaComparison(.encounters) {
                VanillaModifiedFilterToggle(isOn: $onlyModified)
                    .padding(.horizontal, EditorLayout.listPadding)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 8) {
                Text(language == .italian ? "Ordine" : "Order")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(language == .italian ? "Ordine" : "Order", selection: $mapOrder) {
                    ForEach(WildEncounterMapOrder.allCases) { order in
                        Text(order.title(language: language)).tag(order)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
            }
            .padding(.horizontal, EditorLayout.listPadding)
            .padding(.bottom, 8)

            List(filteredMaps, selection: $selectedMapID) { map in
                let area = area(for: map)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(MapNameResolver.shared.mapName(group: map.group, map: map.mapID, language: language))
                            .font(.body)
                            .lineLimit(1)
                        if area.map({ document.isEncounterAreaModified($0.id) }) == true { VanillaModifiedIndicator() }
                    }
                    Text(area?.groups.map { $0.kind.localizedTitle(language: language) }.joined(separator: " · ") ?? L10n.text("no.wild.encounter.map", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .tag(map.id)
            }
        }
        .navigationTitle(L10n.text("wild.encounters", language: language))
    }

    private func area(for map: MapData) -> WildEncounterArea? {
        document.wildEncounterAreas.first { $0.mapGroup == map.group && $0.mapNumber == map.mapID }
    }

    private func sortedMaps(_ maps: [MapData]) -> [MapData] {
        let romIndices = Dictionary(uniqueKeysWithValues: document.maps.enumerated().map { ($0.element.id, $0.offset) })
        switch mapOrder {
        case .rom:
            return maps
        case .alphabetical:
            return maps.sorted {
                let lhs = MapNameResolver.shared.mapName(group: $0.group, map: $0.mapID, language: language)
                let rhs = MapNameResolver.shared.mapName(group: $1.group, map: $1.mapID, language: language)
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        case .storyProgression:
            return maps.sorted { lhs, rhs in
                let lhsIndex = EmeraldStoryProgression.index(for: MapPoint(group: lhs.group, map: lhs.mapID)) ?? Int.max
                let rhsIndex = EmeraldStoryProgression.index(for: MapPoint(group: rhs.group, map: rhs.mapID)) ?? Int.max
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
                return (romIndices[lhs.id] ?? Int.max) < (romIndices[rhs.id] ?? Int.max)
            }
        }
    }

    private func binding(for area: WildEncounterArea) -> Binding<WildEncounterArea> {
        Binding {
            document.wildEncounterAreas.first { $0.id == area.id } ?? area
        } set: { updatedArea in
            document.updateWildEncounterArea(updatedArea)
        }
    }

    private func selectInitialMap() {
        guard !document.maps.isEmpty else {
            selectedMapID = nil
            return
        }
        if let selectedMapID, document.maps.contains(where: { $0.id == selectedMapID }) {
            return
        }
        if let firstEncounterMap = document.maps.first(where: { area(for: $0) != nil }) {
            selectedMapID = firstEncounterMap.id
        } else {
            selectedMapID = document.maps.first?.id
        }
    }

}

private struct WildEncounterDetailEditor: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var area: WildEncounterArea
    let species: [PokemonNamedValue]
    let displayName: String
    @Binding var selectedKind: WildEncounterKind?
    let pokemonSpriteProvider: (Int) -> NSImage?
    let showInHex: (WildEncounterGroup) -> Void
    @State private var isPasteSheetPresented = false
    @State private var pasteText = ""
    @State private var importPreview: WildEncounterClipboardPreview?
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                tableSelector
                if let group = selectedGroup {
                    selectedTableEditor(group)
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(displayName)
        .onAppear(perform: selectInitialGroup)
        .onChange(of: area.groups) { _ in selectInitialGroup() }
        .sheet(isPresented: $isPasteSheetPresented) {
            pasteSheet
        }
    }

    private var header: some View {
        EditorHeaderCard {
            Image(systemName: "leaf.fill")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Chip("Group \(area.mapGroup)")
                    Chip("Map \(area.mapNumber)")
                    Chip("\(area.groups.count) groups")
                }
            }
        }
    }

    private var tableSelector: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(area.groups) { group in
                    tableTab(for: group)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(area.groups) { group in
                    tableTab(for: group)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func tableTab(for group: WildEncounterGroup) -> some View {
        let isSelected = selectedKind == group.kind
        return Button {
            selectedKind = group.kind
        } label: {
            HStack(spacing: 6) {
                Text(group.kind.localizedTitle(language: language))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if document.isEncounterGroupModified(areaID: area.id, kind: group.kind) {
                    VanillaModifiedIndicator()
                }
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectedTableEditor(_ group: WildEncounterGroup) -> some View {
        Panel(title: group.kind.localizedTitle(language: language)) {
            HStack(spacing: 10) {
                Button {
                    copyCurrentTable()
                } label: {
                    Label(language == .italian ? "Copia tabella attuale" : "Copy Current Table", systemImage: "doc.on.doc")
                }
                Button {
                    pasteText = NSPasteboard.general.string(forType: .string) ?? ""
                    importPreview = nil
                    importError = nil
                    isPasteSheetPresented = true
                } label: {
                    Label(language == .italian ? "Incolla tabella" : "Paste Table", systemImage: "doc.on.clipboard")
                }
                Button {
                    showInHex(group)
                } label: {
                    Label(L10n.text("show.encounter.hex", language: language), systemImage: "number")
                }
                Spacer()
            }
            .buttonStyle(.bordered)

            Text("MAP=\(WildEncounterClipboardFormatter.mapID(for: area)) - TABLE=\(WildEncounterClipboardFormatter.tableID(for: group.kind)) - \(group.slots.count) slot")
                .font(.caption)
                .foregroundStyle(.secondary)

            NumericRow(
                L10n.text("encounter.rate", language: language),
                value: groupBinding(groupID: group.id, \.encounterRate),
                range: 0...255
            )
            WildEncounterSpeciesSummaryView(group: group, species: species)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 340), spacing: 6, alignment: .top)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(group.slots, id: \.offset) { slot in
                    WildEncounterSlotEditor(
                        slot: slotBinding(groupID: group.id, slotOffset: slot.offset),
                        species: speciesOptions(for: slot.species),
                        sprite: pokemonSpriteProvider(slot.species)
                    )
                    .id("\(area.id)-\(group.id)-\(slot.offset)")
                }
            }
        }
        .id("\(area.id)-\(group.id)")
    }

    private var pasteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language == .italian ? "Incolla tabella" : "Paste Table")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(language == .italian ? "Chiudi" : "Close") {
                    isPasteSheetPresented = false
                }
            }

            TextEditor(text: $pasteText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))

            HStack {
                Button(language == .italian ? "Anteprima" : "Preview") {
                    buildImportPreview()
                }
                .keyboardShortcut(.defaultAction)

                Button(language == .italian ? "Applica" : "Apply") {
                    applyImportPreview()
                }
                .disabled(importPreview == nil)

                Spacer()
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let importPreview {
                previewTable(importPreview)
            }
        }
        .padding(18)
        .frame(width: 720, height: 520)
    }

    private func previewTable(_ preview: WildEncounterClipboardPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MAP=\(preview.mapID) - TABLE=\(preview.tableID) - \(preview.rows.count) slot")
                .font(.caption.weight(.semibold))
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(preview.rows) { row in
                        HStack(spacing: 8) {
                            Text("\(row.chance)%")
                                .frame(width: 44, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text("\(row.currentSpeciesName) Lv.\(row.currentMinLevel)-\(row.currentMaxLevel)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text("\(row.newSpeciesName) Lv.\(row.newMinLevel)-\(row.newMaxLevel)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var selectedGroup: WildEncounterGroup? {
        guard let selectedKind else { return area.groups.first }
        return area.groups.first { $0.kind == selectedKind }
    }

    private func selectInitialGroup() {
        guard !area.groups.isEmpty else {
            selectedKind = nil
            return
        }
        if let selectedKind, area.groups.contains(where: { $0.kind == selectedKind }) {
            return
        }
        selectedKind = area.groups.first?.kind
    }

    private func copyCurrentTable() {
        guard let group = selectedGroup else { return }
        let text = WildEncounterClipboardFormatter(species: species, language: language).exportText(area: area, group: group)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func buildImportPreview() {
        guard let group = selectedGroup else { return }
        do {
            importPreview = try WildEncounterClipboardFormatter(species: species, language: language).preview(text: pasteText, area: area, group: group)
            importError = nil
        } catch {
            importPreview = nil
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyImportPreview() {
        guard let group = selectedGroup, let importPreview else { return }
        let updatedGroup = WildEncounterClipboardFormatter(species: species, language: language).applying(importPreview, to: group)
        guard let groupIndex = area.groups.firstIndex(where: { $0.id == group.id }) else { return }
        area.groups[groupIndex] = updatedGroup
        isPasteSheetPresented = false
        pasteText = ""
        self.importPreview = nil
        importError = nil
    }

    private func speciesOptions(for selectedID: Int) -> [PokemonNamedValue] {
        var result = species
        if !result.contains(where: { $0.id == selectedID }) {
            result.append(PokemonNamedValue(id: selectedID, name: "Species #\(selectedID)"))
        }
        return result.sorted { $0.id < $1.id }
    }

    private func groupBinding(groupID: WildEncounterGroup.ID, _ keyPath: WritableKeyPath<WildEncounterGroup, Int>) -> Binding<Int> {
        Binding {
            area.groups.first { $0.id == groupID }?[keyPath: keyPath] ?? 0
        } set: { newValue in
            guard let index = area.groups.firstIndex(where: { $0.id == groupID }) else { return }
            area.groups[index][keyPath: keyPath] = newValue
        }
    }

    private func slotBinding(groupID: WildEncounterGroup.ID, slotOffset: Int) -> Binding<WildEncounterSlot> {
        Binding {
            guard let group = area.groups.first(where: { $0.id == groupID }),
                  let slot = group.slots.first(where: { $0.offset == slotOffset }) else {
                return WildEncounterSlot(id: -1, species: 0, minLevel: 1, maxLevel: 1, chance: 0, offset: slotOffset)
            }
            return slot
        } set: { updatedSlot in
            guard let groupIndex = area.groups.firstIndex(where: { $0.id == groupID }),
                  let slotIndex = area.groups[groupIndex].slots.firstIndex(where: { $0.offset == slotOffset }) else { return }
            area.groups[groupIndex].slots[slotIndex] = updatedSlot
        }
    }
}

private struct WildEncounterSpeciesSummaryView: View {
    @Environment(\.appLanguage) private var language
    let group: WildEncounterGroup
    let species: [PokemonNamedValue]

    private var summaries: [WildEncounterSpeciesSummary] {
        WildEncounterSpeciesAggregator.summarize(group.slots)
    }

    private var speciesNames: [Int: String] {
        Dictionary(uniqueKeysWithValues: species.map { ($0.id, $0.name) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language == .italian ? "Incontri aggregati" : "Aggregated Encounters")
                .font(.caption.weight(.semibold))
            ForEach(summaries) { summary in
                let name = speciesNames[summary.speciesID] ?? "Species #\(summary.speciesID)"
                (
                    Text("\(name) (\(summary.totalChance)%)")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    + Text(" — \(levelDescription(for: summary))")
                        .foregroundColor(.secondary)
                )
                .font(.caption)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func levelDescription(for summary: WildEncounterSpeciesSummary) -> String {
        summary.levelChances.map { levelChance in
            let chance = levelChance.chanceTenths.isMultiple(of: 10)
                ? "\(levelChance.chanceTenths / 10)"
                : "\(levelChance.chanceTenths / 10).\(levelChance.chanceTenths % 10)"
            return "Lv. \(levelChance.level): \(chance)%"
        }
        .joined(separator: " | ")
    }
}

private struct WildEncounterSlotEditor: View {
    @Environment(\.appLanguage) private var language
    @Binding var slot: WildEncounterSlot
    let species: [PokemonNamedValue]
    let sprite: NSImage?
    @State private var levelNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Slot \(slot.id + 1)")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(slot.chance)%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 7) {
                if let sprite {
                    Image(nsImage: sprite)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
                Picker(L10n.text("species", language: language), selection: intBinding(\.species)) {
                    ForEach(species) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.text("species", language: language))
            }
            HStack(alignment: .top, spacing: 12) {
                WildLevelField(title: "Lv min", level: minLevelBinding())
                    .frame(maxWidth: .infinity, alignment: .leading)
                WildLevelField(title: "Lv max", level: maxLevelBinding())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let note = levelNote {
                Label(note, systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
    }

    private func intBinding(_ keyPath: WritableKeyPath<WildEncounterSlot, Int>) -> Binding<Int> {
        Binding {
            slot[keyPath: keyPath]
        } set: { newValue in
            slot[keyPath: keyPath] = newValue
        }
    }

    private func minLevelBinding() -> Binding<Int> {
        Binding {
            slot.minLevel
        } set: { newValue in
            var updated = slot
            updated.minLevel = newValue
            reconcile(&updated)
            slot = updated
        }
    }

    private func maxLevelBinding() -> Binding<Int> {
        Binding {
            slot.maxLevel
        } set: { newValue in
            var updated = slot
            updated.maxLevel = newValue
            reconcile(&updated)
            slot = updated
        }
    }

    private func reconcile(_ updated: inout WildEncounterSlot) {
        if updated.minLevel > updated.maxLevel {
            updated.maxLevel = updated.minLevel
            levelNote = L10n.text("wild.level.max.raised", language: language)
        } else {
            levelNote = nil
        }
    }
}

private struct WildLevelField: View {
    @Environment(\.appLanguage) private var language
    let title: String
    @Binding var level: Int
    @State private var textValue = ""
    @State private var showsError = false
    @FocusState private var isFieldFocused: Bool

    private static let validRange: ClosedRange<Int> = 1...100

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                TextField(title, text: Binding(
                    get: { textValue.isEmpty ? String(level) : textValue },
                    set: { textValue = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .focused($isFieldFocused)
                .onSubmit(commit)
                .onChange(of: isFieldFocused) { focused in
                    guard !focused else { return }
                    commit()
                }
                .frame(width: 42)

                Stepper(title, value: Binding(
                    get: { level },
                    set: { newValue in
                        level = newValue
                        showsError = false
                    }
                ), in: Self.validRange)
                .labelsHidden()
                .frame(width: EditorLayout.stepperWidth)
            }
            if showsError {
                Text(L10n.text("wild.level.invalid", language: language))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: syncText)
        .onChange(of: level) { _ in
            showsError = false
            if !isFieldFocused { syncText() }
        }
    }

    private func commit() {
        guard let number = Int(textValue), Self.validRange.contains(number) else {
            showsError = true
            syncText()
            return
        }
        level = number
        showsError = false
    }

    private func syncText() {
        textValue = String(level)
    }
}

enum ItemCategory: String, CaseIterable, Identifiable {
    case all
    case balls
    case cures
    case berries
    case held
    case key
    case tm
    case treasures
    case other
    case unresolved

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all: L10n.text("item.category.all", language: language)
        case .balls: L10n.text("item.category.balls", language: language)
        case .cures: L10n.text("item.category.cures", language: language)
        case .berries: L10n.text("item.category.berries", language: language)
        case .held: L10n.text("item.category.held", language: language)
        case .key: L10n.text("item.category.key", language: language)
        case .tm: L10n.text("item.category.tm", language: language)
        case .treasures: L10n.text("item.category.treasures", language: language)
        case .other: L10n.text("item.category.other", language: language)
        case .unresolved: L10n.text("item.category.unresolved", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .balls: "circle.circle"
        case .cures: "cross.case.fill"
        case .berries: "leaf.fill"
        case .held: "hand.raised.fill"
        case .key: "key.fill"
        case .tm: "book.closed.fill"
        case .treasures: "dollarsign.circle.fill"
        case .other: "square.stack.3d.up.fill"
        case .unresolved: "exclamationmark.triangle.fill"
        }
    }
}

extension ItemData {
    var isNameResolved: Bool {
        guard !name.isEmpty, !name.contains("\\!") else { return false }
        return name.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    func displayName(language: AppLanguage) -> String {
        guard isNameResolved else {
            return String(format: L10n.text("item.name.unresolved", language: language), id)
        }
        return name
    }

    var itemCategory: ItemCategory {
        guard isNameResolved else { return .unresolved }
        switch pocket {
        case 2: return .balls
        case 3: return .tm
        case 4: return .berries
        default: break
        }
        if keyItemValue == 1 || bagKeyItem == 1 || pocket == 5 { return .key }
        if holdEffect != 0 { return .held }
        if isTreasure { return .treasures }
        if isCureItem { return .cures }
        return .other
    }

    private var isTreasure: Bool {
        let n = name.uppercased()
        let english = ["NUGGET", "PEARL", "STARDUST", "STAR PIECE", "HEART SCALE", "SHOAL", "SHARD", "MUSHROOM"]
        let italian = ["PEPITA", "PERLA", "POLVOSTELLA", "PEZZO STELLA", "SQUAMA CUORE", "SALE ONDOSO", "GUSCIONDOSO", "COCCIO", "FUNGO"]
        return english.contains { n.contains($0) } || italian.contains { n.contains($0) }
    }

    private var isCureItem: Bool {
        let n = name.uppercased()
        let english = ["POTION", "ANTIDOTE", "AWAKENING", "PARLYZ", "HEAL", "RESTORE", "REVIVE", "SACRED ASH", "FRESH WATER", "SODA POP", "LEMONADE", "MOOMOO", "ENERGY", "REVIVAL HERB", "ETHER", "ELIXIR", "LAVA COOKIE", "BERRY JUICE"]
        let italian = ["POZIONE", "ANTIDOTO", "ANTISCOTT", "ANTIGELO", "SVEGLIA", "ANTIPARALISI", "CURA TOTALE", "RICARICA", "REVITAL", "CENEREMAGICA", "ACQUA FRESCA", "GASSOSA", "LEMONSUCCO", "MUMU", "ENERGIA", "VITALERBA", "ETERE", "ELISIR", "LAVOTTINO", "POLVOCURA"]
        return english.contains { n.contains($0) } || italian.contains { n.contains($0) }
    }

    func simplifiedEffect(language: AppLanguage) -> String {
        guard isNameResolved else { return L10n.text("item.effect.unresolved", language: language) }
        switch itemCategory {
        case .balls: return L10n.text("item.effect.ball", language: language)
        case .key: return L10n.text("item.effect.key", language: language)
        case .tm: return L10n.text("item.effect.tm", language: language)
        case .berries: return L10n.text("item.effect.berry", language: language)
        case .held: return L10n.text("item.effect.held", language: language)
        case .treasures: return L10n.text("item.effect.treasure", language: language)
        case .cures: return cureEffect(language: language)
        case .unresolved: return L10n.text("item.effect.unresolved", language: language)
        case .all, .other: return L10n.text("item.effect.other", language: language)
        }
    }

    private func cureEffect(language: AppLanguage) -> String {
        let n = name.uppercased()
        let reviveKeywords = ["REVIVE", "SACRED ASH", "REVITAL", "CENEREMAGICA"]
        let ppKeywords = ["ETHER", "ELIXIR", "ETERE", "ELISIR"]
        let statusKeywords = ["ANTIDOTE", "AWAKENING", "PARLYZ", "HEAL", "LAVA COOKIE", "ANTIDOTO", "ANTISCOTT", "ANTIGELO", "SVEGLIA", "ANTIPARALISI", "CURA TOTALE", "LAVOTTINO"]
        if reviveKeywords.contains(where: { n.contains($0) }) {
            return L10n.text("item.effect.cure.revive", language: language)
        }
        if ppKeywords.contains(where: { n.contains($0) }) {
            return L10n.text("item.effect.cure.pp", language: language)
        }
        if statusKeywords.contains(where: { n.contains($0) }) {
            return L10n.text("item.effect.cure.status", language: language)
        }
        return L10n.text("item.effect.cure", language: language)
    }

    func sanitizedDescription(language: AppLanguage) -> String {
        let sanitized = Self.sanitizeDescription(description)
        guard !sanitized.isEmpty else { return "—" }
        return sanitized
    }

    private static func sanitizeDescription(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 3 < chars.count, chars[i + 1] == "!",
               chars[i + 2].isHexDigit, chars[i + 3].isHexDigit {
                let code = String(chars[(i + 2)...(i + 3)]).uppercased()
                switch code {
                case "FF":
                    i = chars.count
                case "FE":
                    result.append("\n")
                    i += 4
                case "FD":
                    result.append("\n\n")
                    i += 4
                case "FA", "FB", "FC":
                    var j = i + 4
                    var consumed = 0
                    while consumed < 2, j + 3 < chars.count,
                          chars[j] == "\\", chars[j + 1] == "!",
                          chars[j + 2].isHexDigit, chars[j + 3].isHexDigit {
                        j += 4
                        consumed += 1
                    }
                    i = j
                default:
                    i += 4
                }
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return cleanupDescription(result)
    }

    private static func cleanupDescription(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        result = result.replacingOccurrences(of: " *\\n", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ItemEditorView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var showingHex: Bool
    @State private var searchText = ""
    @State private var selectedItemID: ItemData.ID?
    @State private var selectedCategory: ItemCategory? = .all
    @State private var onlyModified = false

    private var activeCategory: ItemCategory { selectedCategory ?? .all }

    private var filteredItems: [ItemData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidates = document.itemData
        if activeCategory != .all {
            candidates = candidates.filter { $0.itemCategory == activeCategory }
        }
        if onlyModified {
            candidates = candidates.filter { document.isItemModified($0.id) }
        }
        guard !query.isEmpty else { return candidates }
        return candidates.filter { item in
            item.displayName(language: language).lowercased().contains(query) || String(item.id).contains(query)
        }
    }

    private var selectedItem: ItemData? {
        guard let selectedItemID else { return filteredItems.first }
        return filteredItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        HStack(spacing: 0) {
            categorySidebar
                .frame(minWidth: 200, idealWidth: 215, maxWidth: 250, maxHeight: .infinity)
            Divider()
            itemList
                .frame(minWidth: EditorLayout.listMinWidth, idealWidth: EditorLayout.listIdealWidth, maxWidth: EditorLayout.listMaxWidth, maxHeight: .infinity)
            Divider()
            detail
                .frame(minWidth: EditorLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear(perform: selectInitialItem)
        .onChange(of: document.itemData) { _ in selectInitialItem() }
        .onChange(of: activeCategory) { _ in ensureVisibleSelection() }
        .onChange(of: searchText) { _ in ensureVisibleSelection() }
    }

    private var categorySidebar: some View {
        List(selection: $selectedCategory) {
            Section(L10n.text("item.categories", language: language)) {
                ForEach(ItemCategory.allCases) { category in
                    Label {
                        HStack {
                            Text(category.title(language: language))
                                .lineLimit(1)
                            Spacer()
                            Text("\(count(for: category))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: category.systemImage)
                    }
                    .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func count(for category: ItemCategory) -> Int {
        if category == .all { return document.itemData.count }
        return document.itemData.lazy.filter { $0.itemCategory == category }.count
    }

    @ViewBuilder
    private var detail: some View {
        if let item = selectedItem {
            ItemDetailEditor(
                item: binding(for: item),
                showInHex: {
                    document.showItemInHex(item)
                    showingHex = true
                }
            )
            .id(item.id)
        } else {
            PlaceholderView(title: L10n.text("no.items", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.items", language: language))
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            TextField(L10n.text("search.items", language: language), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, EditorLayout.listPadding)
                .padding(.top, EditorLayout.listPadding)
                .padding(.bottom, 8)
            if document.supportsVanillaComparison(.items) {
                VanillaModifiedFilterToggle(isOn: $onlyModified)
                    .padding(.horizontal, EditorLayout.listPadding)
                    .padding(.bottom, 8)
            }

            List(filteredItems, selection: $selectedItemID) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.displayName(language: language)).font(.body).lineLimit(1)
                        if document.isItemModified(item.id) { VanillaModifiedIndicator() }
                    }
                    Text("Index #\(item.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .tag(item.id)
            }
        }
        .navigationTitle(L10n.text("items", language: language))
    }

    private func binding(for item: ItemData) -> Binding<ItemData> {
        Binding {
            document.itemData.first { $0.id == item.id } ?? item
        } set: { updatedItem in
            document.updateItem(updatedItem)
        }
    }

    private func selectInitialItem() {
        guard !document.itemData.isEmpty else {
            selectedItemID = nil
            return
        }
        if selectedItemID == nil || !document.itemData.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = document.itemData.first?.id
        }
    }

    private func ensureVisibleSelection() {
        if let selectedItemID, filteredItems.contains(where: { $0.id == selectedItemID }) { return }
        selectedItemID = filteredItems.first?.id
    }
}

private struct ItemDetailEditor: View {
    @Environment(\.appLanguage) private var language
    @Binding var item: ItemData
    let showInHex: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                EditorCardGrid {
                    Panel(title: L10n.text("data", language: language)) {
                        ReadOnlyRow(title: L10n.text("category", language: language), value: item.itemCategory.title(language: language))
                        ReadOnlyRow(title: L10n.text("name", language: language), value: item.displayName(language: language))
                        NumericRow(L10n.text("price", language: language), value: intBinding(\.price), range: 0...65535)
                        PickerRow(title: L10n.text("pocket", language: language), selection: intBinding(\.pocket), options: pocketOptions)
                        NumericRow(L10n.text("hold.effect", language: language), value: intBinding(\.holdEffect), range: 0...255)
                        NumericRow(L10n.text("parameter", language: language), value: intBinding(\.parameter), range: 0...255)
                        NumericRow(L10n.text("key.item.value", language: language), value: intBinding(\.keyItemValue), range: 0...255)
                        NumericRow(L10n.text("bag.key.item", language: language), value: intBinding(\.bagKeyItem), range: 0...255)
                        NumericRow(L10n.text("type", language: language), value: intBinding(\.type), range: 0...255)
                    }

                    Panel(title: L10n.text("description", language: language)) {
                        Text(item.sanitizedDescription(language: language))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        ReadOnlyRow(title: L10n.text("text.offset", language: language), value: item.descriptionOffset.map { String(format: "0x%08X", $0) } ?? "—")
                    }

                    Panel(title: L10n.text("simplified.effect", language: language)) {
                        Text(item.simplifiedEffect(language: language))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Panel(title: L10n.text("advanced.readonly", language: language)) {
                        ReadOnlyRow(title: L10n.text("field.effect", language: language), value: String(format: "0x%08X", item.fieldEffectPointer))
                        ReadOnlyRow(title: L10n.text("battle.usage", language: language), value: String(format: "0x%08X", item.battleUsage))
                        ReadOnlyRow(title: L10n.text("battle.effect", language: language), value: String(format: "0x%08X", item.battleEffectPointer))
                        ReadOnlyRow(title: L10n.text("battle.extra", language: language), value: String(format: "0x%08X", item.battleExtra))
                    }
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(item.displayName(language: language))
    }

    private var header: some View {
        EditorHeaderCard {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text(item.displayName(language: language))
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Chip("Index #\(item.id)")
                    Chip(item.itemCategory.title(language: language))
                    Chip(pocketName(item.pocket))
                    Chip("Price \(item.price)")
                }
                Button(action: showInHex) {
                    Label(L10n.text("show.item.hex", language: language), systemImage: "number")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var pocketOptions: [PokemonNamedValue] {
        var result = [
            PokemonNamedValue(id: 1, name: "Item"),
            PokemonNamedValue(id: 2, name: "Ball"),
            PokemonNamedValue(id: 3, name: "TM"),
            PokemonNamedValue(id: 4, name: "Berry"),
            PokemonNamedValue(id: 5, name: "Key")
        ]
        if !result.contains(where: { $0.id == item.pocket }) {
            result.append(PokemonNamedValue(id: item.pocket, name: "Pocket #\(item.pocket)"))
        }
        return result.sorted { $0.id < $1.id }
    }

    private func pocketName(_ id: Int) -> String {
        pocketOptions.first { $0.id == id }?.name ?? "Pocket #\(id)"
    }

    private func intBinding(_ keyPath: WritableKeyPath<ItemData, Int>) -> Binding<Int> {
        Binding {
            item[keyPath: keyPath]
        } set: { newValue in
            item[keyPath: keyPath] = newValue
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WelcomeView: View {
    @Environment(\.appLanguage) private var language
    @Binding var selectedGame: SupportedGame
    let swordShieldStatusMessage: String?
    let openROM: () -> Void
    let openSave: () -> Void
    let openTeamCoach: () -> Void
    let openSettings: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "hexagon.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(L10n.text("app.title", language: language))
                        .font(.largeTitle.bold())
                    Text(L10n.text("home.description", language: language))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 18) {
                    HomeChoiceCard(
                        title: selectedGame.isEmerald ? L10n.text("open.rom", language: language).uppercased() : "APRI GIOCO",
                        subtitle: selectedGame.isEmerald ? L10n.text("home.rom.subtitle", language: language) : "Apri una cartella con dati estratti",
                        message: selectedGame.isEmerald ? L10n.text("home.rom.message", language: language) : "Richiede RomFS/ExeFS estratti (dump base o aggiornato)",
                        systemImage: "gamecontroller.fill",
                        action: openROM
                    )
                    HomeChoiceCard(
                        title: L10n.text("open.save", language: language).uppercased(),
                        subtitle: selectedGame.isEmerald ? L10n.text("home.save.subtitle", language: language) : "Non ancora disponibile",
                        message: selectedGame.isEmerald ? L10n.text("home.save.message", language: language) : "Non ancora disponibile",
                        systemImage: "externaldrive.fill",
                        isEnabled: selectedGame.isEmerald,
                        action: openSave
                    )
                    HomeChoiceCard(
                        title: "TEAM COACH",
                        subtitle: language == .italian ? "Guida squadra" : "Team guide",
                        message: language == .italian ? "Analizza la squadra e scopri come migliorarla." : "Analyze your team and learn how to improve it.",
                        systemImage: "lightbulb.fill",
                        action: openTeamCoach
                    )
                }

                if let swordShieldStatusMessage, !selectedGame.isEmerald {
                    Text(swordShieldStatusMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Text(L10n.text("home.legal", language: language))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Picker("", selection: $selectedGame) {
                    ForEach(SupportedGame.allCases) { game in
                        Text(game.displayName).tag(game)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(L10n.text("settings", language: language))
            }
            .padding(24)
        }
    }
}

private struct SettingsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.italian.rawValue

    private var appLanguage: Binding<AppLanguage> {
        Binding {
            AppLanguage.from(appLanguageRaw)
        } set: { newValue in
            appLanguageRaw = newValue.rawValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.text("settings", language: language))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L10n.text("close.document", language: language))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("language", language: language))
                    .font(.headline)
                Picker(L10n.text("language", language: language), selection: appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(24)
        .frame(width: 320, alignment: .leading)
    }
}

private struct HomeChoiceCard: View {
    let title: String
    let subtitle: String
    let message: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(width: 260, height: 190, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private extension NSImage {
    func pixelArtScaled(by scale: Double) -> NSImage? {
        guard scale > 0,
              let source = representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              source.samplesPerPixel == 4,
              let srcPixels = source.bitmapData else { return nil }
        let srcWidth = source.pixelsWide
        let srcHeight = source.pixelsHigh
        guard srcWidth > 0, srcHeight > 0 else { return nil }
        let dstWidth = max(1, Int((Double(srcWidth) * scale).rounded()))
        let dstHeight = max(1, Int((Double(srcHeight) * scale).rounded()))
        guard let destination = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dstWidth,
            pixelsHigh: dstHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: dstWidth * 4,
            bitsPerPixel: 32
        ), let dstPixels = destination.bitmapData else { return nil }
        let srcBytesPerRow = source.bytesPerRow
        for y in 0..<dstHeight {
            let srcY = min(srcHeight - 1, Int(Double(y) / scale))
            let srcRow = srcY * srcBytesPerRow
            let dstRow = y * dstWidth * 4
            for x in 0..<dstWidth {
                let srcX = min(srcWidth - 1, Int(Double(x) / scale))
                let srcIndex = srcRow + srcX * 4
                let dstIndex = dstRow + x * 4
                dstPixels[dstIndex + 0] = srcPixels[srcIndex + 0]
                dstPixels[dstIndex + 1] = srcPixels[srcIndex + 1]
                dstPixels[dstIndex + 2] = srcPixels[srcIndex + 2]
                dstPixels[dstIndex + 3] = srcPixels[srcIndex + 3]
            }
        }
        let result = NSImage(size: NSSize(width: dstWidth, height: dstHeight))
        result.addRepresentation(destination)
        return result
    }
}

fileprivate func alphabeticallyAscending(_ lhs: String, _ rhs: String, language: AppLanguage) -> Bool {
    let locale = Locale(identifier: language == .italian ? "it_IT" : "en_US")
    return lhs.compare(rhs, options: .caseInsensitive, range: nil, locale: locale) == .orderedAscending
}
