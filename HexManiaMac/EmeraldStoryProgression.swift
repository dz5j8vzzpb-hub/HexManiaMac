import Foundation

/// Canonical first-significant-visit order for Pokémon Emerald.
/// Map identity, never localized display text, drives the ordering.
enum EmeraldStoryProgression {
    private static let canonicalSteps: [[MapPoint]] = [
        [MapPoint(group: 0, map: 9)], // Littleroot Town
        [MapPoint(group: 0, map: 16)], // Route 101
        [MapPoint(group: 0, map: 10)], // Oldale Town
        [MapPoint(group: 0, map: 18)], // Route 103
        [MapPoint(group: 0, map: 17)], // Route 102
        [MapPoint(group: 0, map: 0)], // Petalburg City (first visit)
        [MapPoint(group: 0, map: 19)], // Route 104
        [MapPoint(group: 24, map: 11)], // Petalburg Woods
        [MapPoint(group: 0, map: 3)], // Rustboro City
        [MapPoint(group: 0, map: 31)], // Route 116
        [MapPoint(group: 24, map: 4)], // Rusturf Tunnel
        [MapPoint(group: 0, map: 11)], // Dewford Town
        [
            MapPoint(group: 24, map: 7),
            MapPoint(group: 24, map: 8),
            MapPoint(group: 24, map: 9),
            MapPoint(group: 24, map: 10)
        ], // Granite Cave
        [MapPoint(group: 0, map: 24)], // Route 109
        [MapPoint(group: 0, map: 1)], // Slateport City
        [MapPoint(group: 0, map: 25)], // Route 110
        [MapPoint(group: 0, map: 2)], // Mauville City
        [MapPoint(group: 0, map: 32)], // Route 117
        [MapPoint(group: 0, map: 14)], // Verdanturf Town
        [MapPoint(group: 0, map: 26)], // Route 111
        [MapPoint(group: 0, map: 27)], // Route 112
        [MapPoint(group: 24, map: 14)], // Fiery Path
        [MapPoint(group: 0, map: 28)], // Route 113
        [MapPoint(group: 0, map: 13)], // Fallarbor Town
        [MapPoint(group: 0, map: 29)], // Route 114
        [
            MapPoint(group: 24, map: 0),
            MapPoint(group: 24, map: 1),
            MapPoint(group: 24, map: 2),
            MapPoint(group: 24, map: 3)
        ], // Meteor Falls
        [MapPoint(group: 24, map: 12)], // Mt. Chimney
        [MapPoint(group: 24, map: 13)], // Jagged Pass
        [MapPoint(group: 0, map: 12)], // Lavaridge Town
        [MapPoint(group: 0, map: 30)], // Route 115
        [MapPoint(group: 0, map: 20)], // Route 105
        [MapPoint(group: 0, map: 21)], // Route 106
        [MapPoint(group: 0, map: 22)], // Route 107
        [MapPoint(group: 0, map: 23)], // Route 108
        Array(54...66).map { MapPoint(group: 24, map: $0) }, // Abandoned Ship
        [MapPoint(group: 0, map: 33)], // Route 118
        [MapPoint(group: 0, map: 34)], // Route 119
        [MapPoint(group: 0, map: 4)], // Fortree City
        [MapPoint(group: 0, map: 35)], // Route 120
        [MapPoint(group: 0, map: 36)], // Route 121
        [MapPoint(group: 0, map: 5)], // Lilycove City
        [MapPoint(group: 0, map: 37)], // Route 122
        Array(15...22).map { MapPoint(group: 24, map: $0) }, // Mt. Pyre
        Array(86...93).map { MapPoint(group: 24, map: $0) }, // Magma Hideout
        Array(23...25).map { MapPoint(group: 24, map: $0) }, // Aqua Hideout
        [MapPoint(group: 0, map: 39)], // Route 124
        [MapPoint(group: 0, map: 6)], // Mossdeep City
        [MapPoint(group: 0, map: 40)], // Route 125
        Array(46...51).map { MapPoint(group: 24, map: $0) }
            + [MapPoint(group: 24, map: 83)], // Shoal Cave
        [MapPoint(group: 0, map: 42)], // Route 127
        [MapPoint(group: 0, map: 43)], // Route 128
        Array(26...36).map { MapPoint(group: 24, map: $0) }, // Seafloor Cavern
        [MapPoint(group: 0, map: 41)], // Route 126
        [MapPoint(group: 0, map: 7), MapPoint(group: 24, map: 5)], // Sootopolis
        Array(37...42).map { MapPoint(group: 24, map: $0) }, // Cave of Origin
        [MapPoint(group: 0, map: 44)], // Route 129
        [MapPoint(group: 0, map: 45)], // Route 130
        [MapPoint(group: 0, map: 46)], // Route 131
        Array(77...82).map { MapPoint(group: 24, map: $0) }
            + [MapPoint(group: 24, map: 84), MapPoint(group: 24, map: 85)], // Sky Pillar
        [MapPoint(group: 0, map: 15)], // Pacifidlog Town
        [MapPoint(group: 0, map: 47)], // Route 132
        [MapPoint(group: 0, map: 48)], // Route 133
        [MapPoint(group: 0, map: 49)], // Route 134
        [MapPoint(group: 0, map: 8)], // Ever Grande City
        Array(43...45).map { MapPoint(group: 24, map: $0) } // Victory Road
    ]

    private static let indexByMap: [MapPoint: Int] = {
        var result: [MapPoint: Int] = [:]
        for (step, maps) in canonicalSteps.enumerated() {
            for map in maps where result[map] == nil {
                result[map] = step
            }
        }
        return result
    }()

    /// Building groups inherit their parent area's first-visit step.
    private static let parentPointByGroup: [Int: MapPoint] = [
        1: MapPoint(group: 0, map: 9),
        2: MapPoint(group: 0, map: 10),
        3: MapPoint(group: 0, map: 11),
        4: MapPoint(group: 0, map: 12),
        5: MapPoint(group: 0, map: 13),
        6: MapPoint(group: 0, map: 14),
        7: MapPoint(group: 0, map: 15),
        8: MapPoint(group: 0, map: 0),
        9: MapPoint(group: 0, map: 1),
        10: MapPoint(group: 0, map: 2),
        11: MapPoint(group: 0, map: 3),
        12: MapPoint(group: 0, map: 4),
        13: MapPoint(group: 0, map: 5),
        14: MapPoint(group: 0, map: 6),
        15: MapPoint(group: 0, map: 7),
        16: MapPoint(group: 0, map: 8)
    ]

    static func index(for point: MapPoint) -> Int? {
        if let exactIndex = indexByMap[point] {
            return exactIndex
        }
        guard let parent = parentPointByGroup[point.group] else {
            return nil
        }
        return indexByMap[parent]
    }
}
