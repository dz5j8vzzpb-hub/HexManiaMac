import Foundation

struct TeamCoachAnalyzer {
    func analyze(context: TeamCoachContext) -> [TeamCoachSlotAnalysis] {
        TeamAnalyzer(context: context).analyze()
    }
}

struct TeamAnalyzer {
    let context: TeamCoachContext

    func analyze() -> [TeamCoachSlotAnalysis] {
        let members = TeamCoachPokemonAnalyzer(context: context).members(from: context.team)
        let fullTeam = TeamCoachTeamSnapshot(members: members)
        let pokemonAnalyzer = TeamCoachPokemonAnalyzer(context: context)

        return members.map { member in
            let teamWithoutMember = TeamCoachTeamSnapshot(members: members.filter { $0.slot.id != member.slot.id })
            return pokemonAnalyzer.analyze(
                member: member,
                fullTeam: fullTeam,
                teamWithoutMember: teamWithoutMember
            )
        }
    }
}

struct TeamCoachPokemonAnalyzer {
    let context: TeamCoachContext
    private let moveAnalyzer = TeamCoachMoveAnalyzer()

    func members(from slots: [TeamCoachSlot]) -> [TeamCoachAnalyzedPokemon] {
        let speciesByID = Dictionary(uniqueKeysWithValues: context.species.map { ($0.id, $0) })
        let movesByID = Dictionary(uniqueKeysWithValues: context.moves.map { ($0.id, $0) })

        return slots.compactMap { slot in
            guard let speciesID = slot.speciesID,
                  let species = speciesByID[speciesID] else { return nil }
            let moves = slot.moveIDs.compactMap { moveID -> TeamCoachAnalyzedMove? in
                guard let moveID, let move = movesByID[moveID] else { return nil }
                return moveAnalyzer.analyze(move)
            }
            return TeamCoachAnalyzedPokemon(slot: slot, species: species, moves: moves)
        }
    }

    func analyze(
        member: TeamCoachAnalyzedPokemon,
        fullTeam: TeamCoachTeamSnapshot,
        teamWithoutMember: TeamCoachTeamSnapshot
    ) -> TeamCoachSlotAnalysis {
        if member.offensiveMoves.isEmpty {
            return TeamCoachSlotAnalysis(
                id: member.slot.id,
                category: .developing,
                explanation: "Non ha ancora mosse offensive inserite.",
                suggestion: "Aggiungi almeno una mossa STAB o una mossa di copertura."
            )
        }

        if let issue = movesetIssue(for: member) {
            return TeamCoachSlotAnalysis(
                id: member.slot.id,
                category: .developing,
                explanation: issue.reason,
                suggestion: issue.suggestion
            )
        }

        if member.stabMoves.isEmpty {
            return TeamCoachSlotAnalysis(
                id: member.slot.id,
                category: .developing,
                explanation: "Non possiede ancora una buona mossa STAB offensiva.",
                suggestion: "Prova una mossa offensiva del suo tipo principale."
            )
        }

        let contribution = fullTeam.uniqueCoverageContributed(by: member)
        let removalLoss = fullTeam.coverage.subtracting(teamWithoutMember.coverage)
        let redundancy = fullTeam.redundancy(for: member)

        if redundancy.isStrong, contribution.isEmpty, removalLoss.isEmpty {
            return TeamCoachSlotAnalysis(
                id: member.slot.id,
                category: .redundant,
                explanation: redundancy.reason,
                suggestion: "Valuta uno slot con tipi o copertura diversi."
            )
        }

        if let sharedWeakness = fullTeam.majorSharedWeakness(involving: member), contribution.isEmpty {
            return TeamCoachSlotAnalysis(
                id: member.slot.id,
                category: .developing,
                explanation: sharedWeakness,
                suggestion: "Riduci questa sovrapposizione o aggiungi copertura contro quel tipo."
            )
        }

        if !removalLoss.isEmpty || contribution.count >= 2 {
            let typeNames = typeList(removalLoss.isEmpty ? contribution : removalLoss)
            return TeamCoachSlotAnalysis(
                id: member.slot.id,
                category: .excellent,
                explanation: "È l'unico membro che copre bene \(typeNames).",
                suggestion: "Puoi tenerlo così."
            )
        }

        return TeamCoachSlotAnalysis(
            id: member.slot.id,
            category: .good,
            explanation: "Ha almeno una STAB utile e non crea grandi sovrapposizioni.",
            suggestion: "Puoi tenerlo così."
        )
    }

    private func movesetIssue(for member: TeamCoachAnalyzedPokemon) -> (reason: String, suggestion: String)? {
        let attack = member.species.baseStats.attack
        let specialAttack = member.species.baseStats.specialAttack
        let physicalPower = member.offensiveMoves
            .filter { $0.damageKind == .physical }
            .map(\.reliablePower)
            .reduce(0, +)
        let specialPower = member.offensiveMoves
            .filter { $0.damageKind == .special }
            .map(\.reliablePower)
            .reduce(0, +)

        if specialAttack >= attack + 20, physicalPower > 0, specialPower == 0 {
            return (
                "Le mosse attuali sfruttano poco il suo Attacco Speciale.",
                "Prova una mossa speciale del suo tipo."
            )
        }

        if attack >= specialAttack + 20, specialPower > 0, physicalPower == 0 {
            return (
                "Le mosse attuali sfruttano poco il suo Attacco.",
                "Prova una mossa fisica del suo tipo."
            )
        }

        return nil
    }

    private func typeList(_ typeIDs: Set<Int>) -> String {
        let names = typeIDs
            .sorted()
            .map { id in context.types.first { $0.id == id }?.name ?? TeamCoachTypeChart.typeName(id) }
        return names.prefix(3).joined(separator: ", ")
    }
}

struct TeamCoachMoveAnalyzer {
    func analyze(_ move: MoveData) -> TeamCoachAnalyzedMove {
        TeamCoachAnalyzedMove(
            move: move,
            damageKind: damageKind(forType: move.type, power: move.power),
            reliablePower: reliablePower(move)
        )
    }

    func damageKind(forType type: Int, power: Int) -> TeamCoachMoveDamageKind {
        guard power > 0 else { return .status }
        return TeamCoachTypeChart.physicalTypes.contains(type) ? .physical : .special
    }

    private func reliablePower(_ move: MoveData) -> Int {
        guard move.power > 0 else { return 0 }
        let accuracy = move.accuracy == 0 ? 100 : min(move.accuracy, 100)
        return move.power * accuracy / 100
    }
}

struct PokemonRoleAnalyzer {
    func profile(for species: PokemonSpecies, moves: [MoveData]) -> PokemonRoleProfile {
        let offensive = offensiveProfile(for: species)
        let speed = speedProfile(for: species.baseStats.speed)
        let durability = durabilityProfile(for: species.baseStats)
        let supportMoveCount = moves.filter { $0.power == 0 }.count
        let primaryTraits: [String]
        if supportMoveCount >= 2 {
            primaryTraits = ["Supporto", speed.title, durability.title]
        } else {
            primaryTraits = [offensive.title, speed.title, durability.title]
        }
        return PokemonRoleProfile(
            offensive: offensive,
            speed: speed,
            durability: durability,
            isSupportLeaning: supportMoveCount >= 2,
            traits: Array(primaryTraits.prefix(3))
        )
    }

    func offensiveProfile(for species: PokemonSpecies) -> PokemonOffensiveProfile {
        let attack = species.baseStats.attack
        let specialAttack = species.baseStats.specialAttack
        if attack >= specialAttack + 20 { return .physical }
        if specialAttack >= attack + 20 { return .special }
        return .mixed
    }

    func speedProfile(for speed: Int) -> PokemonSpeedProfile {
        if speed >= 90 { return .fast }
        if speed <= 55 { return .slow }
        return .medium
    }

    func durabilityProfile(for stats: PokemonBaseStats) -> PokemonDurabilityProfile {
        let bulk = (stats.hp + stats.defense + stats.specialDefense) / 3
        if bulk >= 80 { return .durable }
        if bulk <= 55 { return .fragile }
        return .balanced
    }
}

struct PokemonDevelopmentAdvisor {
    func advice(for profile: PokemonRoleProfile) -> String {
        if profile.isSupportLeaning {
            return "Può offrire supporto: valorizza mosse utili e durata."
        }
        switch (profile.offensive, profile.speed, profile.durability) {
        case (.special, .fast, .fragile):
            return "Sfrutta soprattutto Attacco Speciale e velocità."
        case (.physical, .slow, .durable):
            return "È lento ma resistente: valorizza potenza e durata."
        case (.special, _, _):
            return "Sfrutta soprattutto Attacco Speciale e mosse speciali."
        case (.physical, _, _):
            return "Punta su Attacco fisico e mosse coerenti con il suo tipo."
        case (.mixed, _, _):
            return "Può funzionare sia fisico sia speciale."
        }
    }
}

struct MoveSuitabilityAnalyzer {
    private let moveAnalyzer = TeamCoachMoveAnalyzer()

    func analyze(move: MoveData, species: PokemonSpecies, currentMoves: [MoveData]) -> MoveSuitabilityResult {
        let analyzedMove = moveAnalyzer.analyze(move)
        let profile = PokemonRoleAnalyzer().offensiveProfile(for: species)
        let types = Set([species.type1, species.type2].filter { TeamCoachTypeChart.validTypeIDs.contains($0) })
        let isSTAB = types.contains(move.type) && move.power > 0
        let duplicateTypeCount = currentMoves.filter { $0.id != move.id && $0.type == move.type && $0.power > 0 }.count

        if analyzedMove.damageKind == .status {
            return MoveSuitabilityResult(
                suitability: .situational,
                explanation: "È utile come supporto anche senza fare danno."
            )
        }

        let usesPreferredStat = matches(profile: profile, damageKind: analyzedMove.damageKind)
        if isSTAB, usesPreferredStat {
            return MoveSuitabilityResult(
                suitability: .suitable,
                explanation: analyzedMove.damageKind == .special
                    ? "È STAB e sfrutta bene il suo Attacco Speciale."
                    : "È STAB e sfrutta bene il suo Attacco."
            )
        }

        if usesPreferredStat, analyzedMove.reliablePower >= 50 {
            return MoveSuitabilityResult(
                suitability: .suitable,
                explanation: analyzedMove.damageKind == .special
                    ? "Usa l'Attacco Speciale, che è una statistica adatta a questo Pokémon."
                    : "Usa l'Attacco, che è una statistica adatta a questo Pokémon."
            )
        }

        if isSTAB {
            return MoveSuitabilityResult(
                suitability: .situational,
                explanation: "È STAB, anche se non sfrutta la statistica migliore."
            )
        }

        if !usesPreferredStat, profile != .mixed, analyzedMove.reliablePower >= 40 {
            return MoveSuitabilityResult(
                suitability: .poor,
                explanation: "Usa la statistica offensiva più debole."
            )
        }

        if duplicateTypeCount > 0, analyzedMove.reliablePower < 45 {
            return MoveSuitabilityResult(
                suitability: .poor,
                explanation: "È ridondante e offre poco rispetto alle altre mosse."
            )
        }

        return MoveSuitabilityResult(
            suitability: .situational,
            explanation: "Può servire come copertura in alcune situazioni."
        )
    }

    private func matches(profile: PokemonOffensiveProfile, damageKind: TeamCoachMoveDamageKind) -> Bool {
        switch (profile, damageKind) {
        case (.physical, .physical), (.special, .special), (.mixed, .physical), (.mixed, .special): true
        default: false
        }
    }
}

struct PokemonRoleProfile: Equatable {
    let offensive: PokemonOffensiveProfile
    let speed: PokemonSpeedProfile
    let durability: PokemonDurabilityProfile
    let isSupportLeaning: Bool
    let traits: [String]
}

enum PokemonOffensiveProfile: Equatable {
    case physical
    case special
    case mixed

    var title: String {
        switch self {
        case .physical: "Fisico"
        case .special: "Speciale"
        case .mixed: "Misto"
        }
    }
}

enum PokemonSpeedProfile: Equatable {
    case fast
    case medium
    case slow

    var title: String {
        switch self {
        case .fast: "Veloce"
        case .medium: "Medio"
        case .slow: "Lento"
        }
    }
}

enum PokemonDurabilityProfile: Equatable {
    case durable
    case balanced
    case fragile

    var title: String {
        switch self {
        case .durable: "Resistente"
        case .balanced: "Equilibrato"
        case .fragile: "Fragile"
        }
    }
}

struct MoveSuitabilityResult: Equatable {
    let suitability: MoveSuitability
    let explanation: String
}

enum MoveSuitability: Equatable {
    case suitable
    case situational
    case poor

    var symbol: String {
        switch self {
        case .suitable: "✓"
        case .situational: "•"
        case .poor: "⚠"
        }
    }

    var title: String {
        switch self {
        case .suitable: "Adatta"
        case .situational: "Situazionale"
        case .poor: "Poco adatta"
        }
    }
}

struct TeamCoachRecommendationEngine {
    func recommendations(context: TeamCoachContext, limit: Int = 3) -> [TeamCoachRecommendation] {
        TeamRecommendationEngine(context: context).recommendations(limit: limit)
    }
}

struct TeamRecommendationEngine {
    let context: TeamCoachContext

    func recommendations(limit: Int = 3) -> [TeamCoachRecommendation] {
        guard let progression = context.progression,
              progression.id != TeamCoachProgressionCheckpoint.notSet.id else { return [] }

        let availabilityService = EncounterAvailabilityService(context: context)
        let progressionFilter = ProgressionFilter(context: context, progression: progression)
        let pokedexFilter = PokedexSeenFilter(pokedex: context.pokedex, isEnabled: context.recommendDiscoveredOnly)
        let members = TeamCoachPokemonAnalyzer(context: context).members(from: context.team)
        let currentTeam = TeamCoachTeamSnapshot(members: members)
        let presentSpecies = Set(members.map { $0.species.id })
        let redundantSlotID = redundantSlot(in: currentTeam)

        let candidates = availabilityService.availablePokemon()
            .filter { !presentSpecies.contains($0.speciesID) }
            .filter { progressionFilter.allows($0) }
            .filter { pokedexFilter.allows(speciesID: $0.speciesID) }
            .compactMap { availability -> CandidateScore? in
                guard let species = context.species.first(where: { $0.id == availability.speciesID }) else { return nil }
                return score(species: species, availability: availability, currentTeam: currentTeam, replacementSlotID: redundantSlotID)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.availability.encounterWeight > rhs.availability.encounterWeight }
                return lhs.score > rhs.score
            }

        return diversified(candidates, limit: limit).enumerated().map { index, score in
            TeamCoachRecommendation(
                id: index,
                speciesID: score.species.id,
                reason: score.reason,
                areaName: score.availability.areaName,
                minLevel: score.availability.minLevel,
                maxLevel: score.availability.maxLevel,
                replacementSlotID: score.replacementSlotID
            )
        }
    }

    private func score(
        species: PokemonSpecies,
        availability: TeamCoachAvailablePokemon,
        currentTeam: TeamCoachTeamSnapshot,
        replacementSlotID: TeamCoachSlot.ID?
    ) -> CandidateScore {
        let profile = CandidateProfile(species: species)
        var score = 0
        var reason = "Si sovrappone poco agli altri membri."
        var reasonKind: CandidateReasonKind = .lowOverlap

        let currentTypes = Set(currentTeam.members.flatMap { Array($0.types) })
        if let newType = profile.types.subtracting(currentTypes).sorted().first {
            score += 34
            reason = "Aggiunge il tipo \(TeamCoachTypeChart.typeName(newType)), che alla squadra manca."
            reasonKind = .coverage(newType)
        }

        let missingCoverage = profile.potentialCoverage.subtracting(currentTeam.coverage)
        if let typeID = missingCoverage.sorted().first {
            score += 28
            if reasonKind == .lowOverlap {
                reason = "Aggiunge copertura contro \(TeamCoachTypeChart.typeName(typeID)), che alla squadra manca."
                reasonKind = .coverage(typeID)
            }
        }

        if let sharedWeakness = currentTeam.sharedWeaknessTypes(minCount: 2).first(where: { profile.resistances.contains($0) || profile.immunities.contains($0) }) {
            score += 26
            if reasonKind == .lowOverlap {
                reason = "Riduce una debolezza condivisa a \(TeamCoachTypeChart.typeName(sharedWeakness))."
                reasonKind = .weakness(sharedWeakness)
            }
        }

        let currentRoles = currentTeam.members.map(\.role)
        if !currentRoles.contains(profile.role) {
            score += 18
            if reasonKind == .lowOverlap {
                reason = profile.role == .special
                    ? "Ti manca un attaccante speciale: questo Pokémon ne aggiunge uno."
                    : "Aggiunge un ruolo offensivo diverso dagli altri membri."
                reasonKind = .role(profile.role)
            }
        }

        let overlaps = currentTeam.members.filter { !$0.types.intersection(profile.types).isEmpty }.count
        score -= overlaps * 8
        score += min(10, availability.encounterWeight / 8)
        score += min(14, profile.baseStatTotal / 45)

        if let replacementSlotID {
            score += 8
            if let redundant = currentTeam.members.first(where: { $0.slot.id == replacementSlotID }), reasonKind != .lowOverlap {
                reason = "Al posto di \(redundant.species.name) aggiungerebbe più varietà alla squadra."
                reasonKind = .replacement
            }
        }

        return CandidateScore(
            species: species,
            availability: availability,
            score: score,
            reason: reason,
            reasonKind: reasonKind,
            replacementSlotID: replacementSlotID
        )
    }

    private func redundantSlot(in team: TeamCoachTeamSnapshot) -> TeamCoachSlot.ID? {
        for member in team.members where team.redundancy(for: member).isStrong {
            return member.slot.id
        }
        return nil
    }

    private func diversified(_ candidates: [CandidateScore], limit: Int) -> [CandidateScore] {
        var result: [CandidateScore] = []
        var usedSpecies = Set<Int>()
        var usedKinds = Set<CandidateReasonKind>()

        for candidate in candidates where result.count < limit {
            guard !usedSpecies.contains(candidate.species.id) else { continue }
            if usedKinds.contains(candidate.reasonKind), candidates.count - result.count > limit - result.count {
                continue
            }
            result.append(candidate)
            usedSpecies.insert(candidate.species.id)
            usedKinds.insert(candidate.reasonKind)
        }

        for candidate in candidates where result.count < limit && !usedSpecies.contains(candidate.species.id) {
            result.append(candidate)
            usedSpecies.insert(candidate.species.id)
        }

        return result
    }
}

struct EncounterAvailabilityService {
    let context: TeamCoachContext

    func availablePokemon() -> [TeamCoachAvailablePokemon] {
        var bySpecies: [Int: TeamCoachAvailablePokemon] = [:]
        for (areaIndex, area) in context.encounterAreas.enumerated() {
            let areaName = mapName(group: area.mapGroup, mapID: area.mapNumber) ?? area.displayName
            for group in area.groups {
                for slot in group.slots where slot.species > 0 {
                    let current = bySpecies[slot.species]
                    let merged = TeamCoachAvailablePokemon(
                        speciesID: slot.species,
                        mapGroup: area.mapGroup,
                        mapNumber: area.mapNumber,
                        areaIndex: areaIndex,
                        areaName: areaName,
                        minLevel: min(slot.minLevel, current?.minLevel ?? slot.minLevel),
                        maxLevel: max(slot.maxLevel, current?.maxLevel ?? slot.maxLevel),
                        encounterWeight: (current?.encounterWeight ?? 0) + max(slot.chance, 1)
                    )
                    bySpecies[slot.species] = merged
                }
            }
        }
        return Array(bySpecies.values)
    }

    private func mapName(group: Int, mapID: Int) -> String? {
        context.maps.first { $0.group == group && $0.mapID == mapID }?.name
    }
}

struct ProgressionFilter {
    let context: TeamCoachContext
    let progression: TeamCoachProgressionCheckpoint

    func allows(_ availability: TeamCoachAvailablePokemon) -> Bool {
        guard let reachedIndex else { return false }
        return availability.areaIndex <= reachedIndex
    }

    private var reachedIndex: Int? {
        switch progression.source {
        case .manual:
            return nil
        case .saveProgression:
            guard let first = context.encounterAreas.firstIndex(where: { area in
                progression.id == "save.\(area.mapGroup).\(area.mapNumber)"
            }) else { return nil }
            return first
        case let .map(group, mapID):
            return context.encounterAreas.firstIndex { $0.mapGroup == group && $0.mapNumber == mapID }
        }
    }
}

struct PokedexSeenFilter {
    let pokedex: SavePokedexData?
    let isEnabled: Bool

    func allows(speciesID: Int) -> Bool {
        guard isEnabled else { return true }
        guard let pokedex else { return false }
        return pokedex.entries.first { $0.id == speciesID }?.seen == true
    }
}

struct TeamCoachAvailablePokemon: Equatable {
    let speciesID: Int
    let mapGroup: Int
    let mapNumber: Int
    let areaIndex: Int
    let areaName: String
    let minLevel: Int
    let maxLevel: Int
    let encounterWeight: Int
}

private struct CandidateProfile {
    let species: PokemonSpecies

    var types: Set<Int> {
        Set([species.type1, species.type2].filter { TeamCoachTypeChart.validTypeIDs.contains($0) })
    }

    var potentialCoverage: Set<Int> {
        Set(TeamCoachTypeChart.validTypeIDs.filter { defendingType in
            types.contains { attackingType in
                TeamCoachTypeChart.effectiveness(attackType: attackingType, defenderTypes: [defendingType]) > 1.0
            }
        })
    }

    var resistances: Set<Int> {
        Set(TeamCoachTypeChart.validTypeIDs.filter { TeamCoachTypeChart.effectiveness(attackType: $0, defenderTypes: types) < 1.0 && TeamCoachTypeChart.effectiveness(attackType: $0, defenderTypes: types) > 0.0 })
    }

    var immunities: Set<Int> {
        Set(TeamCoachTypeChart.validTypeIDs.filter { TeamCoachTypeChart.effectiveness(attackType: $0, defenderTypes: types) == 0.0 })
    }

    var role: TeamCoachBattleRole {
        let attack = species.baseStats.attack
        let specialAttack = species.baseStats.specialAttack
        if specialAttack >= attack + 20 { return .special }
        if attack >= specialAttack + 20 { return .physical }
        return .mixed
    }

    var baseStatTotal: Int {
        species.baseStats.hp + species.baseStats.attack + species.baseStats.defense + species.baseStats.speed + species.baseStats.specialAttack + species.baseStats.specialDefense
    }
}

private struct CandidateScore {
    let species: PokemonSpecies
    let availability: TeamCoachAvailablePokemon
    let score: Int
    let reason: String
    let reasonKind: CandidateReasonKind
    let replacementSlotID: TeamCoachSlot.ID?
}

private enum CandidateReasonKind: Hashable {
    case coverage(Int)
    case weakness(Int)
    case role(TeamCoachBattleRole)
    case replacement
    case lowOverlap
}

struct TeamCoachAnalyzedPokemon: Identifiable, Equatable {
    var id: TeamCoachSlot.ID { slot.id }
    let slot: TeamCoachSlot
    let species: PokemonSpecies
    let moves: [TeamCoachAnalyzedMove]

    var types: Set<Int> {
        Set([species.type1, species.type2].filter { TeamCoachTypeChart.validTypeIDs.contains($0) })
    }

    var offensiveMoves: [TeamCoachAnalyzedMove] {
        moves.filter { $0.damageKind != .status && $0.move.power > 0 }
    }

    var offensiveMoveTypes: Set<Int> {
        Set(offensiveMoves.map { $0.move.type })
    }

    var stabMoves: [TeamCoachAnalyzedMove] {
        offensiveMoves.filter { types.contains($0.move.type) }
    }

    var role: TeamCoachBattleRole {
        let physicalPower = offensiveMoves.filter { $0.damageKind == .physical }.map(\.reliablePower).reduce(0, +)
        let specialPower = offensiveMoves.filter { $0.damageKind == .special }.map(\.reliablePower).reduce(0, +)
        if physicalPower == 0, specialPower == 0 { return .support }
        if physicalPower >= specialPower * 2 { return .physical }
        if specialPower >= physicalPower * 2 { return .special }
        return .mixed
    }

    var weaknesses: Set<Int> {
        Set(TeamCoachTypeChart.validTypeIDs.filter { TeamCoachTypeChart.effectiveness(attackType: $0, defenderTypes: types) > 1.0 })
    }

    func coveredDefendingTypes() -> Set<Int> {
        Set(TeamCoachTypeChart.validTypeIDs.filter { defendingType in
            offensiveMoves.contains { move in
                TeamCoachTypeChart.effectiveness(attackType: move.move.type, defenderTypes: [defendingType]) > 1.0
            }
        })
    }
}

struct TeamCoachAnalyzedMove: Equatable {
    let move: MoveData
    let damageKind: TeamCoachMoveDamageKind
    let reliablePower: Int
}

enum TeamCoachMoveDamageKind: Equatable {
    case physical
    case special
    case status
}

enum TeamCoachBattleRole: Hashable {
    case physical
    case special
    case mixed
    case support
}

struct TeamCoachTeamSnapshot {
    let members: [TeamCoachAnalyzedPokemon]

    var coverage: Set<Int> {
        members.reduce(into: Set<Int>()) { result, member in
            result.formUnion(member.coveredDefendingTypes())
        }
    }

    func uniqueCoverageContributed(by member: TeamCoachAnalyzedPokemon) -> Set<Int> {
        let others = members.filter { $0.id != member.id }
        let otherCoverage = TeamCoachTeamSnapshot(members: others).coverage
        return member.coveredDefendingTypes().subtracting(otherCoverage)
    }

    func sharedWeaknessTypes(minCount: Int) -> [Int] {
        TeamCoachTypeChart.validTypeIDs.filter { attackType in
            members.filter { $0.weaknesses.contains(attackType) }.count >= minCount
        }
    }

    func majorSharedWeakness(involving member: TeamCoachAnalyzedPokemon) -> String? {
        let counts = TeamCoachTypeChart.validTypeIDs.map { attackType in
            (attackType, members.filter { $0.weaknesses.contains(attackType) }.count)
        }
        guard let shared = counts
            .filter({ $0.1 >= 3 && member.weaknesses.contains($0.0) })
            .max(by: { $0.1 < $1.1 }) else { return nil }
        return "\(shared.1) membri della squadra sono deboli a \(TeamCoachTypeChart.typeName(shared.0))."
    }

    func redundancy(for member: TeamCoachAnalyzedPokemon) -> TeamCoachRedundancyResult {
        let others = members.filter { $0.id != member.id }
        var bestScore = 0
        var bestOther: TeamCoachAnalyzedPokemon?

        for other in others {
            var score = 0
            if !member.types.intersection(other.types).isEmpty { score += 2 }
            if member.role == other.role, member.role != .mixed { score += 1 }
            if member.offensiveMoveTypes.intersection(other.offensiveMoveTypes).count >= 2 { score += 2 }
            if member.coveredDefendingTypes().intersection(other.coveredDefendingTypes()).count >= 4 { score += 1 }
            if member.weaknesses.intersection(other.weaknesses).count >= 2 { score += 1 }
            if score > bestScore {
                bestScore = score
                bestOther = other
            }
        }

        guard bestScore >= 4, let bestOther else {
            return TeamCoachRedundancyResult(isStrong: false, reason: "")
        }

        return TeamCoachRedundancyResult(
            isStrong: true,
            reason: "\(member.species.name) e \(bestOther.species.name) svolgono un ruolo molto simile."
        )
    }
}

struct TeamCoachRedundancyResult: Equatable {
    let isStrong: Bool
    let reason: String
}

enum TeamCoachTypeChart {
    static let validTypeIDs: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17]
    static let physicalTypes: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8]

    static func typeName(_ id: Int) -> String {
        switch id {
        case 0: "Normale"
        case 1: "Lotta"
        case 2: "Volante"
        case 3: "Veleno"
        case 4: "Terra"
        case 5: "Roccia"
        case 6: "Coleottero"
        case 7: "Spettro"
        case 8: "Acciaio"
        case 10: "Fuoco"
        case 11: "Acqua"
        case 12: "Erba"
        case 13: "Elettro"
        case 14: "Psico"
        case 15: "Ghiaccio"
        case 16: "Drago"
        case 17: "Buio"
        default: "Tipo #\(id)"
        }
    }

    static func effectiveness(attackType: Int, defenderTypes: Set<Int>) -> Double {
        defenderTypes.reduce(1.0) { result, defenderType in
            result * singleEffectiveness(attackType: attackType, defenderType: defenderType)
        }
    }

    private static func singleEffectiveness(attackType: Int, defenderType: Int) -> Double {
        if immunities[attackType, default: []].contains(defenderType) { return 0.0 }
        if superEffective[attackType, default: []].contains(defenderType) { return 2.0 }
        if resisted[attackType, default: []].contains(defenderType) { return 0.5 }
        return 1.0
    }

    private static let superEffective: [Int: Set<Int>] = [
        1: [0, 5, 8, 15, 17],
        2: [1, 6, 12],
        3: [12],
        4: [3, 5, 8, 10, 13],
        5: [2, 6, 10, 15],
        6: [12, 14, 17],
        7: [7, 14],
        8: [5, 15],
        10: [6, 8, 12, 15],
        11: [4, 5, 10],
        12: [4, 5, 11],
        13: [2, 11],
        14: [1, 3],
        15: [2, 4, 12, 16],
        16: [16],
        17: [7, 14]
    ]

    private static let resisted: [Int: Set<Int>] = [
        0: [5, 8],
        1: [2, 3, 6, 14],
        2: [5, 8, 13],
        3: [3, 4, 5, 7],
        4: [6, 12],
        5: [1, 4, 8],
        6: [1, 2, 3, 7, 8, 10],
        7: [17, 8],
        8: [8, 10, 11, 13],
        10: [5, 10, 11, 16],
        11: [11, 12, 16],
        12: [2, 3, 6, 8, 10, 12, 16],
        13: [12, 13, 16],
        14: [8, 14],
        15: [8, 10, 11, 15],
        16: [8],
        17: [1, 17, 8]
    ]

    private static let immunities: [Int: Set<Int>] = [
        0: [7],
        1: [7],
        3: [8],
        4: [2],
        7: [0],
        13: [4],
        14: [17]
    ]
}
