import Foundation

public enum Category: String, CaseIterable, Sendable, Identifiable {
    case buildings = "Buildings"
    case sacred = "Sacred"
    case garden = "Garden"
    case trees = "Trees"
    case animals = "Animals"
    case ground = "Ground"

    public var id: String { rawValue }
}

public enum Ground: String, Codable, CaseIterable, Sendable {
    case grass, moss, gravel, path, sand, water, paddy
}

public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
    // Buildings: they join with their neighbors when stretched.
    case machiya, minka, ryokan, teahouse, kura, castle, pagoda, shrine, temple
    // Sacred things.
    case torii, greatTorii, foxStatue, stoneLantern, paperLantern, bellTower
    // Garden.
    case zenGarden, koiPond, bridge, well, bambooFence, azalea, stones
    // Trees.
    case sakura, ume, momiji, pine, sugi, bamboo, ginkgo, willow
    // Animals: they wander around their cell.
    case crane, frog, fox, cat, koi, tanuki
    // Ground paints.
    case paintGrass, paintMoss, paintGravel, paintPath, paintSand, paintWater, paintPaddy

    public var id: String { rawValue }

    public var category: Category {
        switch self {
        case .machiya, .minka, .ryokan, .teahouse, .kura, .castle, .pagoda, .temple: .buildings
        case .shrine, .torii, .greatTorii, .foxStatue, .stoneLantern, .paperLantern, .bellTower: .sacred
        case .zenGarden, .koiPond, .bridge, .well, .bambooFence, .azalea, .stones: .garden
        case .sakura, .ume, .momiji, .pine, .sugi, .bamboo, .ginkgo, .willow: .trees
        case .crane, .frog, .fox, .cat, .koi, .tanuki: .animals
        case .paintGrass, .paintMoss, .paintGravel, .paintPath, .paintSand, .paintWater, .paintPaddy: .ground
        }
    }

    public var isBuilding: Bool {
        switch self {
        case .machiya, .minka, .ryokan, .teahouse, .kura, .castle, .pagoda, .shrine, .temple: true
        default: false
        }
    }

    public var paint: Ground? {
        switch self {
        case .paintGrass: .grass
        case .paintMoss: .moss
        case .paintGravel: .gravel
        case .paintPath: .path
        case .paintSand: .sand
        case .paintWater: .water
        case .paintPaddy: .paddy
        default: nil
        }
    }

    // Ground an item puts under itself.
    public var impliedGround: Ground? {
        switch self {
        case .zenGarden: .gravel
        case .koiPond, .bridge, .koi: .water
        default: nil
        }
    }

    // Whether a walker can pass through a cell holding this.
    public var blocksWalking: Bool {
        isBuilding || self == .koiPond || self == .well || self == .bellTower || self == .bambooFence
    }

    public var title: String {
        switch self {
        case .machiya: "Machiya"
        case .minka: "Cottage"
        case .ryokan: "Inn"
        case .teahouse: "Teahouse"
        case .kura: "Storehouse"
        case .castle: "Castle"
        case .pagoda: "Pagoda"
        case .shrine: "Shrine"
        case .temple: "Temple"
        case .torii: "Torii"
        case .greatTorii: "Great Torii"
        case .foxStatue: "Kitsune"
        case .stoneLantern: "Stone Lantern"
        case .paperLantern: "Paper Lanterns"
        case .bellTower: "Bell Tower"
        case .zenGarden: "Zen Garden"
        case .koiPond: "Koi Pond"
        case .bridge: "Drum Bridge"
        case .well: "Well"
        case .bambooFence: "Bamboo Fence"
        case .azalea: "Azaleas"
        case .stones: "Mossy Stones"
        case .sakura: "Cherry"
        case .ume: "Plum"
        case .momiji: "Maple"
        case .pine: "Pine"
        case .sugi: "Cedar"
        case .bamboo: "Bamboo"
        case .ginkgo: "Ginkgo"
        case .willow: "Willow"
        case .crane: "Cranes"
        case .frog: "Frogs"
        case .fox: "Foxes"
        case .cat: "Cats"
        case .koi: "Koi"
        case .tanuki: "Tanuki"
        case .paintGrass: "Grass"
        case .paintMoss: "Moss"
        case .paintGravel: "Gravel"
        case .paintPath: "Path"
        case .paintSand: "Sand"
        case .paintWater: "Water"
        case .paintPaddy: "Rice Paddy"
        }
    }

    public var symbol: String {
        switch self {
        case .machiya: "house"
        case .minka: "house.lodge"
        case .ryokan: "bed.double"
        case .teahouse: "cup.and.saucer"
        case .kura: "shippingbox"
        case .castle: "building.columns"
        case .pagoda: "building"
        case .shrine: "sparkles"
        case .temple: "building.2"
        case .torii: "pedestrian.gate.closed"
        case .greatTorii: "pedestrian.gate.open"
        case .foxStatue: "pawprint"
        case .stoneLantern: "lamp.table"
        case .paperLantern: "lightbulb"
        case .bellTower: "bell"
        case .zenGarden: "circle.dotted"
        case .koiPond: "fish"
        case .bridge: "point.topleft.down.to.point.bottomright.curvepath"
        case .well: "drop"
        case .bambooFence: "line.3.horizontal"
        case .azalea: "camera.macro"
        case .stones: "mountain.2"
        case .sakura: "camera.macro.circle"
        case .ume: "snowflake"
        case .momiji: "leaf"
        case .pine: "tree"
        case .sugi: "triangle"
        case .bamboo: "line.3.horizontal.decrease"
        case .ginkgo: "leaf.fill"
        case .willow: "wind"
        case .crane: "bird"
        case .frog: "drop.circle"
        case .fox: "pawprint.fill"
        case .cat: "cat"
        case .koi: "fish.fill"
        case .tanuki: "teddybear"
        case .paintGrass: "square.fill"
        case .paintMoss: "square.fill"
        case .paintGravel: "square.dotted"
        case .paintPath: "figure.walk"
        case .paintSand: "beach.umbrella"
        case .paintWater: "water.waves"
        case .paintPaddy: "square.grid.3x3"
        }
    }

    public var styles: [String] {
        switch self {
        case .machiya: ["Dark Timber", "Merchant", "Kyoto"]
        case .minka: ["Thatch", "Shingle", "Snow Country"]
        case .ryokan: ["Hot Spring", "Grand", "Riverside"]
        case .teahouse: ["Rustic", "Lakeside", "Moon View"]
        case .kura: ["White", "Namako", "Black"]
        case .castle: ["Himeji", "Crow", "Green Copper"]
        case .pagoda: ["Vermilion", "Weathered", "Gold Crown"]
        case .shrine: ["Vermilion", "Ise", "Gilded"]
        case .temple: ["Zen", "Copper", "Golden"]
        case .torii: ["Vermilion", "Stone", "Black", "Fushimi"]
        case .greatTorii: ["Vermilion", "Stone", "Itsukushima"]
        case .foxStatue: ["White", "Stone", "Bronze"]
        case .stoneLantern: ["Kasuga", "Yukimi", "Bronze"]
        case .paperLantern: ["Red", "White", "Festival"]
        case .bellTower: ["Temple", "Village"]
        case .zenGarden: ["White Gravel", "Sand", "Moss Islands"]
        case .koiPond: ["Lilies", "Stones", "Iris"]
        case .bridge: ["Vermilion", "Wood", "Stone"]
        case .well: ["Stone", "Wooden"]
        case .bambooFence: ["Green", "Dry", "Black Twine"]
        case .azalea: ["Magenta", "Pink", "White", "Hydrangea"]
        case .stones: ["Moss", "Grey", "Pagoda Stack"]
        case .sakura: ["Somei", "Yaezakura", "Weeping"]
        case .ume: ["Red", "White", "Pink"]
        case .momiji: ["Crimson", "Orange", "Spring Green"]
        case .pine: ["Black Pine", "Red Pine", "Windswept"]
        case .sugi: ["Cedar", "Cypress"]
        case .bamboo: ["Green", "Golden", "Black"]
        case .ginkgo: ["Autumn", "Summer"]
        case .willow: ["Spring", "Weeping"]
        case .crane: ["Red-crowned", "Grey"]
        case .frog: ["Green", "Brown"]
        case .fox: ["Red", "Silver"]
        case .cat: ["Calico", "Black", "White"]
        case .koi: ["Kohaku", "Ogon", "Showa"]
        case .tanuki: ["Wild", "Statue"]
        default: [""]
        }
    }

    public var maxLevel: Int {
        switch self {
        case .castle: 5
        case .pagoda: 5
        case .machiya, .ryokan: 3
        case .minka, .teahouse, .kura, .shrine, .temple: 2
        case .torii: 5
        case .paperLantern, .stoneLantern, .foxStatue, .zenGarden, .stones, .azalea, .bamboo: 4
        case .sakura, .ume, .momiji, .pine, .sugi, .ginkgo, .willow: 4
        case .crane, .frog, .fox, .cat, .koi, .tanuki: 4
        default: 1
        }
    }

    public var defaultLevel: Int {
        switch self {
        case .castle: 3
        case .pagoda: 3
        case .ryokan: 2
        case .sakura, .ume, .momiji, .pine, .sugi, .ginkgo, .willow: 2
        case .crane, .frog, .koi: 2
        case .foxStatue: 2
        case .bamboo, .zenGarden: 2
        default: 1
        }
    }

    public var thumbnailURL: URL? {
        Bundle.module.url(forResource: rawValue, withExtension: "png", subdirectory: "Thumbnails")
    }

    public static func kinds(in category: Category) -> [Kind] {
        allCases.filter { $0.category == category }
    }
}
