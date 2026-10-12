import AppKit
import SwiftUI

enum EditorLayout {
    static let windowDefaultWidth: CGFloat = 1700
    static let windowDefaultHeight: CGFloat = 950
    static let windowMinWidth: CGFloat = 1500
    static let windowMinHeight: CGFloat = 750
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 250
    static let sidebarMaxWidth: CGFloat = 300
    static let listMinWidth: CGFloat = 300
    static let listIdealWidth: CGFloat = 340
    static let listMaxWidth: CGFloat = 380
    static let detailMinWidth: CGFloat = 600
    static let detailPadding: CGFloat = 18
    static let listPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 14
    static let rowLabelWidth: CGFloat = 140
    static let controlMinWidth: CGFloat = 180
    static let numericFieldWidth: CGFloat = 72
    static let stepperWidth: CGFloat = 52
    static let spriteBoxSide: CGFloat = 112
    static let mapListMinWidth: CGFloat = 250
    static let mapListIdealWidth: CGFloat = 280
    static let mapListMaxWidth: CGFloat = 320
    static let mapCanvasMinWidth: CGFloat = 560
    static let mapInspectorMinWidth: CGFloat = 360
    static let mapInspectorIdealWidth: CGFloat = 390
    static let mapInspectorMaxWidth: CGFloat = 430
}

struct PokemonEditorView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @Binding var showingHex: Bool
    @State private var searchText = ""
    @State private var selectedSpeciesID: PokemonSpecies.ID?
    @State private var onlyModified = false

    private var filteredSpecies: [PokemonSpecies] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = onlyModified ? document.pokemonSpecies.filter { document.isPokemonModified($0.id) } : document.pokemonSpecies
        guard !query.isEmpty else { return candidates }
        return candidates.filter { species in
            species.name.lowercased().contains(query) || String(species.id).contains(query)
        }
    }

    private var selectedSpecies: PokemonSpecies? {
        guard let selectedSpeciesID else { return document.pokemonSpecies.first }
        return document.pokemonSpecies.first { $0.id == selectedSpeciesID }
    }

    var body: some View {
        HStack(spacing: 0) {
            speciesList
                .frame(minWidth: EditorLayout.listMinWidth, idealWidth: EditorLayout.listIdealWidth, maxWidth: EditorLayout.listMaxWidth, maxHeight: .infinity)
            Divider()
            detail
                .frame(minWidth: EditorLayout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear(perform: selectInitialSpecies)
        .onChange(of: document.pokemonSpecies) { _ in selectInitialSpecies() }
    }

    @ViewBuilder
    private var detail: some View {
        if let species = selectedSpecies {
            PokemonDetailEditor(
                species: binding(for: species),
                sprite: document.pokemonSprite(for: species),
                types: document.pokemonTypes,
                abilities: document.pokemonAbilities,
                showInHex: {
                    document.showPokemonInHex(species)
                    showingHex = true
                }
            )
            .id(species.id)
        } else {
            PlaceholderView(title: L10n.text("no.pokemon.table", language: language), systemImage: "exclamationmark.triangle", message: L10n.text("open.emerald.species", language: language))
        }
    }

    private var speciesList: some View {
        VStack(spacing: 0) {
            TextField(L10n.text("search.pokemon", language: language), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, EditorLayout.listPadding)
                .padding(.top, EditorLayout.listPadding)
                .padding(.bottom, 8)
            if document.supportsVanillaComparison(.pokemon) {
                VanillaModifiedFilterToggle(isOn: $onlyModified)
                    .padding(.horizontal, EditorLayout.listPadding)
                    .padding(.bottom, 8)
            }

            List(filteredSpecies, selection: $selectedSpeciesID) { species in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(species.name).font(.body).lineLimit(1)
                        if document.isPokemonModified(species.id) { VanillaModifiedIndicator() }
                    }
                    Text("Index #\(species.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .tag(species.id)
            }
        }
        .navigationTitle(L10n.text("pokemon", language: language))
    }

    private func binding(for species: PokemonSpecies) -> Binding<PokemonSpecies> {
        Binding {
            document.pokemonSpecies.first { $0.id == species.id } ?? species
        } set: { updatedSpecies in
            document.updatePokemonSpecies(updatedSpecies)
        }
    }

    private func selectInitialSpecies() {
        guard !document.pokemonSpecies.isEmpty else {
            selectedSpeciesID = nil
            return
        }
        if selectedSpeciesID == nil || !document.pokemonSpecies.contains(where: { $0.id == selectedSpeciesID }) {
            selectedSpeciesID = document.pokemonSpecies.first?.id
        }
    }
}

private struct PokemonDetailEditor: View {
    @Environment(\.appLanguage) private var language
    @Binding var species: PokemonSpecies
    let sprite: NSImage?
    let types: [PokemonNamedValue]
    let abilities: [PokemonNamedValue]
    let showInHex: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                EditorCardGrid {
                    Panel(title: L10n.text("base.stats", language: language)) {
                        NumericRow(L10n.text("hp", language: language), value: intBinding(\.baseStats.hp), range: 0...255)
                        NumericRow(L10n.text("attack", language: language), value: intBinding(\.baseStats.attack), range: 0...255)
                        NumericRow(L10n.text("defense", language: language), value: intBinding(\.baseStats.defense), range: 0...255)
                        NumericRow(L10n.text("special.attack", language: language), value: intBinding(\.baseStats.specialAttack), range: 0...255)
                        NumericRow(L10n.text("special.defense", language: language), value: intBinding(\.baseStats.specialDefense), range: 0...255)
                        NumericRow(L10n.text("speed", language: language), value: intBinding(\.baseStats.speed), range: 0...255)
                        Divider()
                        ReadOnlyRow(title: "Totale statistiche (BST)", value: "\(baseStatTotal)")
                    }

                    Panel(title: "Identità e abilità") {
                        PickerRow(title: L10n.text("type.1", language: language), selection: intBinding(\.type1), options: typeOptions)
                        PickerRow(title: L10n.text("type.2", language: language), selection: intBinding(\.type2), options: typeOptions)
                        PickerRow(title: "\(L10n.text("ability", language: language)) 1", selection: intBinding(\.ability1), options: abilityOptions)
                        PickerRow(title: "\(L10n.text("ability", language: language)) 2", selection: intBinding(\.ability2), options: secondAbilityOptions)
                    }

                    Panel(title: "Cattura ed esperienza") {
                        NumericRow(L10n.text("catch.rate", language: language), value: intBinding(\.catchRate), range: 0...255)
                            .help("Determina la facilità con cui questa specie può essere catturata. La probabilità effettiva dipende anche dalla Ball utilizzata, dai PS rimasti e dalle alterazioni di stato.")
                        Text(catchRateDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        NumericRow(L10n.text("base.exp", language: language), value: intBinding(\.baseExperience), range: 0...255)
                            .help("Contribuisce a determinare quanta esperienza viene assegnata quando questo Pokémon viene sconfitto. Non determina la curva di crescita della specie.")
                        Divider()
                        PickerRow(title: L10n.text("growth.rate", language: language), selection: intBinding(\.growthRate), options: growthRates)
                        growthRateDetails
                    }

                    Panel(title: "Altri parametri") {
                        NumericRow(L10n.text("gender.ratio", language: language), value: intBinding(\.genderRatio), range: 0...255)
                            .help("Codifica il rapporto tra i sessi secondo le regole della terza generazione. I valori 0, 254 e 255 rappresentano rispettivamente solo maschi, solo femmine e specie senza sesso.")
                        Text(genderRatioDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NumericRow(L10n.text("friendship", language: language), value: intBinding(\.baseFriendship), range: 0...255)
                            .help("Valore di amicizia posseduto normalmente da un esemplare appena ottenuto.")
                        NumericRow(L10n.text("steps.to.hatch", language: language), value: intBinding(\.stepsToHatch), range: 0...255)
                            .help("Numero interno di cicli richiesti per la schiusa; il gioco converte ciascun ciclo in passi.")
                    }
                }
            }
            .padding(EditorLayout.detailPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(species.name)
    }

    private var header: some View {
        EditorHeaderCard {
            EditorSpriteBox {
                if let sprite {
                    Image(nsImage: sprite)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.title2)
                        Text(L10n.text("sprite.unavailable", language: language))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(species.name)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Chip("Index #\(species.id)")
                    Chip(typeName(species.type1))
                    Chip(typeName(species.type2))
                }
                Button(action: showInHex) {
                    Label(L10n.text("show.in.hex", language: language), systemImage: "number")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var typeOptions: [PokemonNamedValue] {
        options(types, including: [species.type1, species.type2])
    }

    private var abilityOptions: [PokemonNamedValue] {
        options(abilities, including: [species.ability1, species.ability2])
    }

    private var secondAbilityOptions: [PokemonNamedValue] {
        abilityOptions.map { option in
            option.id == 0 ? PokemonNamedValue(id: option.id, name: "Nessuna") : option
        }
    }

    private var growthRates: [PokemonNamedValue] {
        [
            PokemonNamedValue(id: 1, name: "Erratica"),
            PokemonNamedValue(id: 4, name: "Rapida"),
            PokemonNamedValue(id: 0, name: "Medio-rapida"),
            PokemonNamedValue(id: 3, name: "Medio-lenta"),
            PokemonNamedValue(id: 5, name: "Lenta"),
            PokemonNamedValue(id: 2, name: "Fluttuante")
        ]
    }

    private var baseStatTotal: Int {
        let stats = species.baseStats
        return stats.hp + stats.attack + stats.defense + stats.specialAttack + stats.specialDefense + stats.speed
    }

    private var catchRateDescription: String {
        switch species.catchRate {
        case 0...30: "Generalmente molto difficile da catturare."
        case 31...90: "Generalmente difficile da catturare."
        case 91...180: "Difficoltà di cattura intermedia."
        default: "Generalmente più facile da catturare."
        }
    }

    private var genderRatioDescription: String {
        switch species.genderRatio {
        case 255: "Specie senza sesso."
        case 254: "Solo femmine."
        case 0: "Solo maschi."
        default: "Valore soglia interno: \(species.genderRatio)/254 femmine circa; non è una percentuale memorizzata direttamente."
        }
    }

    private var selectedGrowthRate: GrowthRatePresentation {
        GrowthRatePresentation(id: species.growthRate)
    }

    private var growthRateDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedGrowthRate.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Livello 100: \(selectedGrowthRate.experienceText(at: 100)) EXP")
                .font(.caption.weight(.semibold))
            if selectedGrowthRate.isKnown {
                Text("Livello 20: \(selectedGrowthRate.experienceText(at: 20))  •  Livello 50: \(selectedGrowthRate.experienceText(at: 50))  •  Livello 100: \(selectedGrowthRate.experienceText(at: 100))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, EditorLayout.rowLabelWidth + 12)
    }

    private func options(_ values: [PokemonNamedValue], including selectedIDs: [Int]) -> [PokemonNamedValue] {
        var result = values
        for id in selectedIDs where !result.contains(where: { $0.id == id }) {
            result.append(PokemonNamedValue(id: id, name: "Unknown #\(id)"))
        }
        return result.sorted { $0.id < $1.id }
    }

    private func typeName(_ id: Int) -> String {
        typeOptions.first { $0.id == id }?.name ?? "Type #\(id)"
    }

    private func intBinding(_ keyPath: WritableKeyPath<PokemonSpecies, Int>) -> Binding<Int> {
        Binding {
            species[keyPath: keyPath]
        } set: { newValue in
            species[keyPath: keyPath] = newValue
        }
    }

    private func intBinding(_ keyPath: WritableKeyPath<PokemonBaseStats, Int>) -> Binding<Int> {
        Binding {
            species.baseStats[keyPath: keyPath]
        } set: { newValue in
            species.baseStats[keyPath: keyPath] = newValue
        }
    }
}

private enum GrowthRatePresentation {
    case mediumFast
    case erratic
    case fluctuating
    case mediumSlow
    case fast
    case slow
    case unknown(Int)

    init(id: Int) {
        switch id {
        case 0: self = .mediumFast
        case 1: self = .erratic
        case 2: self = .fluctuating
        case 3: self = .mediumSlow
        case 4: self = .fast
        case 5: self = .slow
        default: self = .unknown(id)
        }
    }

    var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    var explanation: String {
        switch self {
        case .erratic: "Crescita inizialmente più lenta, poi progressivamente più rapida verso i livelli alti."
        case .fast: "Richiede meno esperienza della media lungo tutta la progressione."
        case .mediumFast: "Segue la progressione cubica standard."
        case .mediumSlow: "Parte rapidamente e richiede gradualmente più esperienza della curva medio-rapida."
        case .slow: "Richiede più esperienza della media lungo tutta la progressione."
        case .fluctuating: "Crescita variabile: più rapida all'inizio e particolarmente lenta ai livelli alti."
        case .unknown(let id): "Curva non riconosciuta (identificativo interno \(id)); il valore viene conservato senza interpretazione."
        }
    }

    func experienceText(at level: Int) -> String {
        guard let experience = experience(at: level) else { return "—" }
        return experience.formatted(.number.grouping(.automatic))
    }

    private func experience(at level: Int) -> Int? {
        guard isKnown, (1...100).contains(level) else { return nil }
        let n = Int64(level)
        let cube = n * n * n
        let result: Int64
        switch self {
        case .erratic:
            switch level {
            case ...50:
                result = cube * (100 - n) / 50
            case ...68:
                result = cube * (150 - n) / 100
            case ...98:
                result = cube * ((1911 - 10 * n) / 3) / 500
            default:
                result = cube * (160 - n) / 100
            }
        case .fast:
            result = 4 * cube / 5
        case .mediumFast:
            result = cube
        case .mediumSlow:
            result = max(0, 6 * cube / 5 - 15 * n * n + 100 * n - 140)
        case .slow:
            result = 5 * cube / 4
        case .fluctuating:
            switch level {
            case ...15:
                result = cube * (((n + 1) / 3) + 24) / 50
            case ...35:
                result = cube * (n + 14) / 50
            default:
                result = cube * ((n / 2) + 32) / 50
            }
        case .unknown:
            return nil
        }
        return Int(result)
    }
}

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(spacing: 8) {
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EditorCardGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: EditorLayout.sectionSpacing, alignment: .top)], alignment: .leading, spacing: EditorLayout.sectionSpacing) {
            content
        }
    }
}

struct EditorHeaderCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EditorSpriteBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
            content
        }
        .frame(width: EditorLayout.spriteBoxSide, height: EditorLayout.spriteBoxSide)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
    }
}

struct EditorRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text(title)
                    .frame(width: EditorLayout.rowLabelWidth, alignment: .leading)
                    .lineLimit(1)
                control
                    .frame(minWidth: EditorLayout.controlMinWidth, maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 28)
    }
}

struct NumericRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var textValue = ""
    @FocusState private var isFieldFocused: Bool

    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) {
        self.title = title
        self._value = value
        self.range = range
    }

    var body: some View {
        EditorRow(title: title) {
            HStack(spacing: 8) {
                numericField
                Stepper(title, value: clampedValue, in: range)
                    .labelsHidden()
                    .frame(width: EditorLayout.stepperWidth)
            }
        }
        .onAppear(perform: syncText)
        .onChange(of: value) { _ in syncText() }
    }

    private var numericField: some View {
        TextField(title, text: Binding(
            get: { textValue.isEmpty ? String(value) : textValue },
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
        .frame(width: EditorLayout.numericFieldWidth)
    }

    private var clampedValue: Binding<Int> {
        Binding {
            value
        } set: { newValue in
            value = min(max(newValue, range.lowerBound), range.upperBound)
            syncText()
        }
    }

    private func commit() {
        guard let number = Int(textValue) else {
            syncText()
            return
        }
        value = min(max(number, range.lowerBound), range.upperBound)
    }

    private func syncText() {
        textValue = String(value)
    }
}

struct PickerRow: View {
    let title: String
    @Binding var selection: Int
    let options: [PokemonNamedValue]

    var body: some View {
        EditorRow(title: title) {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ReadOnlyRow: View {
    let title: String
    let value: String

    var body: some View {
        EditorRow(title: title) {
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct Chip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }
}
