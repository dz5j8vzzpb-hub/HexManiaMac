import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TeamCoachView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var session = TeamCoachSession()
    @State private var team = TeamCoachSlot.emptySlots()
    @State private var selectedSlotID: TeamCoachSlot.ID? = 0
    @State private var settings = TeamCoachSettings()
    @State private var mode: TeamCoachMode = .analysis

    var returnHome: (() -> Void)?

    private let analyzer = TeamCoachAnalyzer()
    private let recommendationEngine = TeamCoachRecommendationEngine()

    private var context: TeamCoachContext {
        TeamCoachContext(
            team: team,
            species: session.species,
            moves: session.moves,
            types: session.types,
            encounterAreas: session.encounterAreas,
            maps: session.maps,
            progression: selectedProgression,
            recommendDiscoveredOnly: settings.recommendDiscoveredOnly,
            pokedex: session.pokedex
        )
    }

    private var analyses: [TeamCoachSlotAnalysis] {
        analyzer.analyze(context: context)
    }

    private var recommendations: [TeamCoachRecommendation] {
        recommendationEngine.recommendations(context: context, limit: 3)
    }

    private var selectedSlot: TeamCoachSlot? {
        team.first { $0.id == selectedSlotID }
    }

    private var selectedAnalysis: TeamCoachSlotAnalysis? {
        guard let selectedSlotID else { return nil }
        return analyses.first { $0.id == selectedSlotID }
    }

    private var progressionOptions: [TeamCoachProgressionCheckpoint] {
        var options = [TeamCoachProgressionCheckpoint.notSet]
        if let progression = session.saveProgression,
           let mapGroup = progression.mapGroup,
           let mapNumber = progression.mapNumber {
            let mapName = session.maps.first { $0.group == mapGroup && $0.mapID == mapNumber }?.name
            options.append(TeamCoachProgressionCheckpoint(
                id: "save.\(mapGroup).\(mapNumber)",
                title: mapName ?? "Mappa \(mapGroup).\(mapNumber)",
                source: .saveProgression
            ))
        }
        options.append(contentsOf: session.maps.map { map in
            TeamCoachProgressionCheckpoint(
                id: "map.\(map.group).\(map.mapID)",
                title: map.name,
                source: .map(group: map.group, mapID: map.mapID)
            )
        })
        for area in session.encounterAreas where !options.contains(where: { $0.id == "map.\(area.mapGroup).\(area.mapNumber)" }) {
            options.append(TeamCoachProgressionCheckpoint(
                id: "map.\(area.mapGroup).\(area.mapNumber)",
                title: area.displayName,
                source: .map(group: area.mapGroup, mapID: area.mapNumber)
            ))
        }
        return options
    }

    private var selectedProgression: TeamCoachProgressionCheckpoint? {
        progressionOptions.first { $0.id == settings.reachedAreaID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let returnHome {
                standaloneHeader(returnHome: returnHome)
                Divider()
            }
            HStack(spacing: 0) {
                slotList
                    .frame(minWidth: 460, idealWidth: 520, maxWidth: 620, maxHeight: .infinity)
                Divider()
                detailPanel
                    .frame(minWidth: EditorLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Team Coach")
        .onChange(of: progressionOptions) { options in
            guard !options.contains(where: { $0.id == settings.reachedAreaID }) else { return }
            settings.reachedAreaID = TeamCoachProgressionCheckpoint.notSet.id
        }
    }

    private func standaloneHeader(returnHome: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: returnHome) {
                Label(language == .italian ? "Home" : "Home", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 2) {
                Text("Team Coach")
                    .font(.headline)
                Text(language == .italian ? "Strumento di analisi, sola lettura" : "Read-only analysis tool")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, EditorLayout.detailPadding)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var slotList: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsPanel
                .padding(EditorLayout.listPadding)
            Divider()
            List(selection: $selectedSlotID) {
                ForEach($team) { $slot in
                    TeamCoachSlotRow(
                        slot: $slot,
                        analysis: analyses.first { $0.id == slot.id },
                        species: session.species,
                        moves: session.moves,
                        sprite: slot.speciesID.flatMap { session.pokemonSprite(forSpeciesID: $0) },
                        language: language,
                        isDataLoaded: session.hasLoadedROM
                    )
                    .tag(slot.id)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Team Coach")
                        .font(.title2.weight(.semibold))
                    Text(localized("Costruzione squadra guidata", "Guided team building"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    presentOpenPanel(kind: .rom)
                } label: {
                    Label(localized("Carica ROM", "Load ROM"), systemImage: "gamecontroller.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    presentOpenPanel(kind: .save)
                } label: {
                    Label(localized("Carica salvataggio", "Load Save"), systemImage: "externaldrive.fill")
                }
                .buttonStyle(.bordered)
            }

            dataSourceStatus

            Picker(localized("Area più avanzata raggiunta", "Farthest reached area"), selection: $settings.reachedAreaID) {
                ForEach(progressionOptions) { option in
                    Text(localizedProgressionTitle(option)).tag(option.id)
                }
            }
            .pickerStyle(.menu)

            Toggle(localized("Consiglia solo Pokémon già scoperti", "Recommend discovered Pokémon only"), isOn: $settings.recommendDiscoveredOnly)

            Text(discoveryStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataSourceStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rom = session.loadedROM {
                Label(localized("ROM caricata", "ROM loaded"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(rom.fileName) · \(rom.identity.description) · \(rom.identity.gameCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Label(localized("Carica una ROM Pokémon Smeraldo per iniziare.", "Load a Pokémon Emerald ROM to begin."), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

            if let save = session.loadedSave {
                Label(localized("Salvataggio caricato", "Save loaded"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(save.fileName) · Party \(save.parsed.party.count)/6")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(localized("Il salvataggio è opzionale; serve per importare party e Pokédex.", "The save file is optional; it imports party and Pokédex data."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !session.statusMessage.isEmpty {
                Text(session.statusMessage)
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

    private func presentOpenPanel(kind: TeamCoachOpenPanelKind) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        switch kind {
        case .rom:
            panel.allowedContentTypes = [UTType(filenameExtension: "gba") ?? .data]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                session.loadROM(from: url)
                if session.hasLoadedSave {
                    team = session.importedParty
                    if let progressionID = saveProgressionOptionID {
                        settings.reachedAreaID = progressionID
                    }
                }
            }
        case .save:
            panel.allowedContentTypes = [UTType(filenameExtension: "sav") ?? .data]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                session.loadSave(from: url)
                if session.hasLoadedSave {
                    team = session.importedParty
                    if let progressionID = saveProgressionOptionID {
                        settings.reachedAreaID = progressionID
                    }
                }
            }
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Modalità", selection: $mode) {
                ForEach(TeamCoachMode.allCases) { mode in
                    Label(mode.title(language: language), systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(EditorLayout.detailPadding)

            Divider()

            switch mode {
            case .analysis:
                analysisPanel
            case .completeTeam:
                completeTeamPanel
            }
        }
    }

    private var analysisPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !session.hasLoadedROM {
                    PlaceholderView(
                        title: "Team Coach",
                        systemImage: "gamecontroller.fill",
                        message: localized("Carica una ROM Pokémon Smeraldo per iniziare.", "Load a Pokémon Emerald ROM to begin.")
                    )
                    .frame(minHeight: 360)
                } else if let slot = selectedSlot, slot.isEmpty {
                    TeamCoachEmptySlotCard(slotID: slot.id, language: language)
                } else if let slot = selectedSlot, let analysis = selectedAnalysis {
                    TeamCoachAnalysisCard(
                        slot: slot,
                        analysis: analysis,
                        speciesName: slot.speciesID.map(speciesName) ?? localized("Slot vuoto", "Empty slot"),
                        sprite: slot.speciesID.flatMap { session.pokemonSprite(forSpeciesID: $0) },
                        language: language
                    )
                } else {
                    PlaceholderView(
                        title: localized("Nessuno slot selezionato", "No slot selected"),
                        systemImage: "square.dashed",
                        message: localized("Seleziona uno slot squadra per vedere analisi e suggerimento.", "Select a team slot to see analysis and guidance.")
                    )
                    .frame(minHeight: 360)
                }

                Panel(title: localized("Struttura futura", "Future model")) {
                    Text(localized(
                        "La valutazione è separata dalla UI e potrà considerare tipi, statistiche base, mosse, STAB, fisico/speciale di terza generazione, debolezze condivise e progressione.",
                        "Assessment is separated from the UI and can later consider types, base stats, moves, STAB, Gen III physical/special rules, shared weaknesses and progression."
                    ))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completeTeamPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                EditorHeaderCard {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 32, weight: .semibold))
                        .frame(width: 72, height: 72)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COMPLETA SQUADRA")
                            .font(.title.weight(.semibold))
                        Text(localized("Preparato per mostrare fino a 3 candidati per gli slot vuoti.", "Prepared to show up to 3 candidates for empty slots."))
                            .foregroundStyle(.secondary)
                    }
                }

                if let blockingMessage = recommendationBlockingMessage {
                    Panel(title: localized("Candidati", "Candidates")) {
                        Text(blockingMessage)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Panel(title: localized("Candidati", "Candidates")) {
                        Text(hasEmptySlots ? localized("Suggerimenti per gli slot vuoti.", "Suggestions for empty slots.") : localized("Party completo: queste sono possibili sostituzioni.", "Full party: these are possible replacements."))
                            .foregroundStyle(.secondary)
                    }

                    if recommendations.isEmpty {
                        Panel(title: localized("Nessun candidato", "No candidates")) {
                            Text(localized("Nessun Pokémon disponibile rispetta i filtri attuali.", "No available Pokémon matches the current filters."))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                            ForEach(recommendations.prefix(3)) { recommendation in
                                TeamCoachRecommendationCard(
                                    recommendation: recommendation,
                                    name: speciesName(recommendation.speciesID),
                                    sprite: session.pokemonSprite(forSpeciesID: recommendation.speciesID),
                                    replacementName: recommendation.replacementSlotID.flatMap(speciesNameForSlot)
                                )
                            }
                        }
                    }
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var saveProgressionOptionID: String? {
        guard let progression = session.saveProgression,
              let mapGroup = progression.mapGroup,
              let mapNumber = progression.mapNumber else { return nil }
        let id = "save.\(mapGroup).\(mapNumber)"
        return progressionOptions.contains { $0.id == id } ? id : nil
    }

    private var recommendationBlockingMessage: String? {
        if !session.hasLoadedROM {
            return localized("Carica una ROM Pokémon Smeraldo per iniziare.", "Load a Pokémon Emerald ROM to begin.")
        }
        if selectedProgression?.id == TeamCoachProgressionCheckpoint.notSet.id || selectedProgression == nil {
            return localized("Imposta l'area più avanzata raggiunta per evitare spoiler.", "Set the farthest reached area to avoid spoilers.")
        }
        if settings.recommendDiscoveredOnly, session.pokedex == nil {
            return localized("Il filtro Pokémon già scoperti richiede un salvataggio con dati Pokédex.", "The discovered-only filter requires a save file with Pokédex data.")
        }
        return nil
    }

    private var hasEmptySlots: Bool {
        team.contains { $0.isEmpty }
    }

    private func speciesNameForSlot(_ slotID: TeamCoachSlot.ID) -> String? {
        team.first { $0.id == slotID }?.speciesID.map(speciesName)
    }

    private var discoveryStatusText: String {
        guard settings.recommendDiscoveredOnly else {
            return localized("Filtro Pokédex disattivato.", "Pokédex filter off.")
        }
        guard let pokedex = session.pokedex else {
            return localized("Nessun salvataggio con dati Pokédex disponibile.", "No save with Pokédex data is available.")
        }
        return localized("Pokédex disponibile: \(pokedex.seenCount) visti, \(pokedex.caughtCount) catturati.", "Pokédex available: \(pokedex.seenCount) seen, \(pokedex.caughtCount) caught.")
    }

    private func speciesName(_ speciesID: Int) -> String {
        session.speciesName(id: speciesID)
    }

    private func localizedProgressionTitle(_ option: TeamCoachProgressionCheckpoint) -> String {
        option.id == TeamCoachProgressionCheckpoint.notSet.id ? localized("Non impostata", "Not set") : option.title
    }

    private func localized(_ italian: String, _ english: String) -> String {
        language == .italian ? italian : english
    }
}

private enum TeamCoachOpenPanelKind {
    case rom
    case save
}

private enum TeamCoachMode: String, CaseIterable, Identifiable {
    case analysis
    case completeTeam

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .analysis: "chart.bar.doc.horizontal"
        case .completeTeam: "person.badge.plus"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .analysis:
            language == .italian ? "Analisi" : "Analysis"
        case .completeTeam:
            "COMPLETA SQUADRA"
        }
    }
}

private struct TeamCoachSlotRow: View {
    @Binding var slot: TeamCoachSlot
    let analysis: TeamCoachSlotAnalysis?
    let species: [PokemonSpecies]
    let moves: [MoveData]
    let sprite: NSImage?
    let language: AppLanguage
    let isDataLoaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                spriteBox
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(slot.speciesID.flatMap(speciesName) ?? localized("SLOT VUOTO", "EMPTY SLOT"))
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        if let analysis {
                            TeamCoachAssessmentBadge(category: analysis.category, language: language)
                        } else if slot.isEmpty {
                            Text(localized("SLOT VUOTO", "EMPTY SLOT"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker(localized("Pokémon", "Pokémon"), selection: $slot.speciesID) {
                        Text(localized("Vuoto", "Empty")).tag(Optional<Int>.none)
                        ForEach(species) { species in
                            Text(species.name).tag(Optional(species.id))
                        }
                    }
                    .disabled(!isDataLoaded)

                    if !slot.isEmpty {
                        HStack(spacing: 8) {
                            Text(localized("Livello", "Level"))
                                .foregroundStyle(.secondary)
                            Stepper(value: levelBinding, in: 1...100) {
                                Text("\(slot.level ?? 30)")
                                    .frame(width: 34, alignment: .trailing)
                            }
                            .disabled(!isDataLoaded)
                            Text(localized("modificabile", "editable"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let roleProfile {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profilo: \(roleProfile.traits.joined(separator: " • "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("Sviluppo: \(developmentAdvice)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 6) {
                        Picker("Mossa \(index + 1)", selection: moveBinding(index)) {
                            Text(localized("Nessuna", "None")).tag(Optional<Int>.none)
                            ForEach(moves) { move in
                                Text(move.name).tag(Optional(move.id))
                            }
                        }
                        .disabled(!isDataLoaded)

                        if let suitability = moveSuitability(index) {
                            MoveSuitabilityBadge(result: suitability)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(slot.isEmpty ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(slot.isEmpty ? Color.secondary.opacity(0.28) : Color.accentColor.opacity(0.22)))
        .onChange(of: slot.speciesID) { speciesID in
            if speciesID == nil {
                slot.level = nil
                slot.moveIDs = Array(repeating: nil, count: 4)
            } else if slot.level == nil {
                slot.level = 30
            }
        }
    }

    private var spriteBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
            if let sprite {
                Image(nsImage: sprite)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Image(systemName: slot.isEmpty ? "plus" : "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 74, height: 74)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
    }

    private var selectedSpecies: PokemonSpecies? {
        guard let speciesID = slot.speciesID else { return nil }
        return species.first { $0.id == speciesID }
    }

    private var selectedMoves: [MoveData] {
        slot.moveIDs.compactMap { moveID in
            guard let moveID else { return nil }
            return moves.first { $0.id == moveID }
        }
    }

    private var roleProfile: PokemonRoleProfile? {
        selectedSpecies.map { PokemonRoleAnalyzer().profile(for: $0, moves: selectedMoves) }
    }

    private var developmentAdvice: String {
        roleProfile.map { PokemonDevelopmentAdvisor().advice(for: $0) } ?? ""
    }

    private func speciesName(_ speciesID: Int) -> String? {
        species.first { $0.id == speciesID }?.name
    }

    private func moveSuitability(_ index: Int) -> MoveSuitabilityResult? {
        guard let species = selectedSpecies,
              slot.moveIDs.indices.contains(index),
              let moveID = slot.moveIDs[index],
              let move = moves.first(where: { $0.id == moveID }) else { return nil }
        return MoveSuitabilityAnalyzer().analyze(move: move, species: species, currentMoves: selectedMoves)
    }

    private var levelBinding: Binding<Int> {
        Binding {
            slot.level ?? 30
        } set: { newValue in
            slot.level = min(max(newValue, 1), 100)
        }
    }

    private func moveBinding(_ index: Int) -> Binding<Int?> {
        Binding {
            slot.moveIDs.indices.contains(index) ? slot.moveIDs[index] : nil
        } set: { newValue in
            while slot.moveIDs.count <= index {
                slot.moveIDs.append(nil)
            }
            slot.moveIDs[index] = newValue
        }
    }

    private func localized(_ italian: String, _ english: String) -> String {
        language == .italian ? italian : english
    }
}

private struct MoveSuitabilityBadge: View {
    let result: MoveSuitabilityResult

    var body: some View {
        Text(result.suitability.symbol)
            .font(.caption.weight(.bold))
            .frame(width: 20, height: 20)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Circle())
            .help("\(result.suitability.title): \(result.explanation)")
    }

    private var color: Color {
        switch result.suitability {
        case .suitable: .green
        case .situational: .secondary
        case .poor: .orange
        }
    }
}

private struct TeamCoachAssessmentBadge: View {
    let category: TeamCoachAssessmentCategory
    let language: AppLanguage

    var body: some View {
        Label(category.title(language: language), systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch category {
        case .excellent: .green
        case .good: .blue
        case .developing: .orange
        case .redundant: .red
        }
    }

    private var systemImage: String {
        switch category {
        case .excellent: "star.fill"
        case .good: "checkmark.circle.fill"
        case .developing: "leaf.fill"
        case .redundant: "arrow.triangle.2.circlepath"
        }
    }
}

private struct TeamCoachEmptySlotCard: View {
    let slotID: Int
    let language: AppLanguage

    var body: some View {
        EditorHeaderCard {
            EditorSpriteBox {
                Image(systemName: "square.dashed")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(language == .italian ? "SLOT VUOTO" : "EMPTY SLOT")
                    .font(.largeTitle.weight(.semibold))
                Chip("Slot \(slotID + 1)")
                Text(language == .italian ? "Questo slot non viene valutato." : "This slot is not evaluated.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TeamCoachAnalysisCard: View {
    let slot: TeamCoachSlot
    let analysis: TeamCoachSlotAnalysis
    let speciesName: String
    let sprite: NSImage?
    let language: AppLanguage

    var body: some View {
        EditorHeaderCard {
            EditorSpriteBox {
                if let sprite {
                    Image(nsImage: sprite)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    Image(systemName: slot.isEmpty ? "square.dashed" : "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(speciesName)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)
                    TeamCoachAssessmentBadge(category: analysis.category, language: language)
                }
                Chip("Slot \(slot.id + 1)")
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language == .italian ? "Motivo" : "Reason")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(analysis.explanation)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language == .italian ? "Suggerimento" : "Suggestion")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(analysis.suggestion)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TeamCoachRecommendationCard: View {
    let recommendation: TeamCoachRecommendation
    let name: String
    let sprite: NSImage?
    let replacementName: String?

    var body: some View {
        Panel(title: name.uppercased()) {
            HStack(alignment: .top, spacing: 12) {
                EditorSpriteBox {
                    if let sprite {
                        Image(nsImage: sprite)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    } else {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let areaName = recommendation.areaName {
                        Label(areaName, systemImage: "map.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let minLevel = recommendation.minLevel, let maxLevel = recommendation.maxLevel {
                        Label(minLevel == maxLevel ? "Lv. \(minLevel)" : "Lv. \(minLevel)-\(maxLevel)", systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let replacementName {
                        Text("Possibile sostituzione per \(replacementName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(recommendation.reason)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
