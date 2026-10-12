import Foundation

struct WildEncounterSpeciesSummary: Identifiable, Equatable {
    struct LevelChance: Identifiable, Equatable {
        let level: Int
        let chanceTenths: Int

        var id: Int { level }
    }

    let speciesID: Int
    let totalChance: Int
    let levelChances: [LevelChance]

    var id: Int { speciesID }
}

enum WildEncounterSpeciesAggregator {
    static func summarize(_ slots: [WildEncounterSlot]) -> [WildEncounterSpeciesSummary] {
        Dictionary(grouping: slots, by: \.species)
            .map { speciesID, speciesSlots in
                WildEncounterSpeciesSummary(
                    speciesID: speciesID,
                    totalChance: speciesSlots.reduce(0) { $0 + $1.chance },
                    levelChances: levelChances(for: speciesSlots)
                )
            }
            .sorted {
                if $0.totalChance != $1.totalChance {
                    return $0.totalChance > $1.totalChance
                }
                return $0.speciesID < $1.speciesID
            }
    }

    private static func levelChances(for slots: [WildEncounterSlot]) -> [WildEncounterSpeciesSummary.LevelChance] {
        var weightsByLevel: [Int: Double] = [:]

        for slot in slots {
            let lowerLevel = min(slot.minLevel, slot.maxLevel)
            let upperLevel = max(slot.minLevel, slot.maxLevel)
            let levelCount = upperLevel - lowerLevel + 1
            let weightPerLevel = Double(slot.chance) / Double(levelCount)

            for level in lowerLevel...upperLevel {
                weightsByLevel[level, default: 0] += weightPerLevel
            }
        }

        let totalWeight = weightsByLevel.values.reduce(0, +)
        guard totalWeight > 0 else {
            return weightsByLevel.keys.sorted().map {
                WildEncounterSpeciesSummary.LevelChance(level: $0, chanceTenths: 0)
            }
        }

        let rawTenths = weightsByLevel.map { level, weight in
            (level: level, value: weight / totalWeight * 1_000)
        }
        var roundedTenths = Dictionary(
            uniqueKeysWithValues: rawTenths.map { ($0.level, Int($0.value.rounded(.down))) }
        )
        let missingTenths = 1_000 - roundedTenths.values.reduce(0, +)

        for item in rawTenths.sorted(by: {
            let leftRemainder = $0.value - $0.value.rounded(.down)
            let rightRemainder = $1.value - $1.value.rounded(.down)
            return leftRemainder == rightRemainder ? $0.level < $1.level : leftRemainder > rightRemainder
        }).prefix(missingTenths) {
            roundedTenths[item.level, default: 0] += 1
        }

        return roundedTenths.keys.sorted().map {
            WildEncounterSpeciesSummary.LevelChance(level: $0, chanceTenths: roundedTenths[$0] ?? 0)
        }
    }
}
