import Metal
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd

public enum TimeOfDay: String, CaseIterable, Sendable, Identifiable {
    case morning = "Morning"
    case day = "Day"
    case dusk = "Dusk"
    case night = "Night"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .day: "sun.max"
        case .dusk: "sunset"
        case .night: "moon.stars"
        }
    }

    // How much lamps, windows and lanterns glow.
    var glow: Float {
        switch self {
        case .morning: 0.15
        case .day: 0.1
        case .dusk: 0.8
        case .night: 1.4
        }
    }

    var sunColor: SIMD3<Float> {
        switch self {
        case .morning: [1, 0.86, 0.72]
        case .day: [1, 0.96, 0.88]
        case .dusk: [1, 0.55, 0.3]
        case .night: [0.45, 0.55, 0.9]
        }
    }

    var sunIntensity: Float {
        switch self {
        case .morning: 2.2
        case .day: 2.6
        case .dusk: 1.9
        case .night: 0.45
        }
    }

    var sunDirection: SIMD3<Float> {
        switch self {
        case .morning: simd_normalize([-0.7, 0.45, 0.45])
        case .day: simd_normalize([0.55, 0.62, 0.4])
        case .dusk: simd_normalize([0.8, 0.22, -0.45])
        case .night: simd_normalize([-0.3, 0.7, -0.5])
        }
    }

    var ambient: SIMD3<Float> {
        switch self {
        case .morning: [0.22, 0.22, 0.28]
        case .day: [0.24, 0.25, 0.31]
        case .dusk: [0.18, 0.14, 0.22]
        case .night: [0.06, 0.07, 0.14]
        }
    }

    var skyTop: SIMD3<Float> {
        switch self {
        case .morning: linearColor(0x7FA9D6)
        case .day: linearColor(0x5D9BE0)
        case .dusk: linearColor(0x3B3F7A)
        case .night: linearColor(0x070B1E)
        }
    }

    var skyHorizon: SIMD3<Float> {
        switch self {
        case .morning: linearColor(0xF6D8C0)
        case .day: linearColor(0xDCEBF5)
        case .dusk: linearColor(0xF79A62)
        case .night: linearColor(0x1B2445)
        }
    }

    // The far sea, where it meets the sky; fog fades toward it.
    var seaDistance: SIMD3<Float> {
        switch self {
        case .morning: linearColor(0x8FB4C8)
        case .day: linearColor(0x7FB2CF)
        case .dusk: linearColor(0x8A6A78)
        case .night: linearColor(0x101830)
        }
    }
}

// Every color in the town. Meshes keep paints, so changing the time of day only swaps materials.
enum Paint: String, CaseIterable {
    // Ground.
    case grass, grassLight, grassDark, moss, gravel, gravelLine, path, sand, water, sea, paddyWater, rice, soil, cliff, stone, stoneDark, stoneLight
    // Wood and walls.
    case plaster, plasterCream, earthWall, darkWood, cedar, blackWood, lightWood, vermilion, vermilionDark, bamboo, bambooDry, bambooBlack, twine
    // Roofs.
    case tileGrey, tileBlue, copper, thatch, thatchDark, shingle, snowRoof, gold
    // Openings and lights.
    case shoji, lattice, door, noren, norenRed, windowGlow, lanternRed, lanternWhite, lanternYellow, lanternFire, bronze
    // Plants.
    case bark, barkGrey, barkRed, sakura, sakuraDeep, sakuraWhite, umeRed, umeWhite, umePink, momijiRed, momijiOrange, momijiGreen
    case pineDark, pineMid, cedarGreen, cypressGreen, bambooLeaf, bambooLeafGold, ginkgoYellow, ginkgoGreen, willowGreen, willowPale
    case azaleaMagenta, azaleaPink, azaleaWhite, hydrangea, leafDark, lily, lotus, iris
    // Creatures and details.
    case koiOrange, koiWhite, foxWhite, foxStone, bib, rope, paper
    // Editor.
    case highlight, highlightStretch

    static let indices: [Paint: Int] = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })

    var paletteCoordinate: SIMD2<Float> {
        [(Float(Self.indices[self]!) + 0.5) / Float(Self.allCases.count), 0.5]
    }

    var surface: Surface {
        switch self {
        case .water, .sea, .paddyWater, .gold, .koiOrange, .koiWhite, .bronze, .tileBlue: .shiny
        default: .matte
        }
    }

    // What lights reflect.
    var albedo: SIMD3<Float> {
        switch self {
        case .windowGlow: linearColor(0xF3D9A4) * 0.8
        case .highlight, .highlightStretch: .zero
        default: color
        }
    }

    // Light it gives off without being lit.
    func glow(_ time: TimeOfDay) -> SIMD3<Float> {
        let glow = time.glow
        switch self {
        case .windowGlow: return linearColor(0xFFB55A) * glow
        case .shoji: return linearColor(0xFFC77A) * glow * 0.6
        case .lanternRed: return linearColor(0xFF5A2A) * (0.25 + glow)
        case .lanternWhite: return linearColor(0xFFD69A) * (0.2 + glow)
        case .lanternYellow: return linearColor(0xFFB840) * (0.2 + glow)
        case .lanternFire: return linearColor(0xFFA040) * (0.3 + glow * 1.5)
        case .highlight: return [1.2, 1.0, 0.6]
        case .highlightStretch: return [0.5, 1.1, 1.3]
        default: return .zero
        }
    }

    var color: SIMD3<Float> {
        linearColor(hex)
    }

    var hex: UInt32 {
        switch self {
        case .grass: 0x7FA65A
        case .grassLight: 0x93B866
        case .grassDark: 0x6C9550
        case .moss: 0x5E8040
        case .gravel: 0xD9D3C4
        case .gravelLine: 0xB8B0A0
        case .path: 0xBFA27A
        case .sand: 0xE6D3A3
        case .water: 0x3E7C8C
        case .sea: 0x2E6A86
        case .paddyWater: 0x6E8C7A
        case .rice: 0x9CC25A
        case .soil: 0x7A5B3E
        case .cliff: 0x8C8378
        case .stone: 0x9C978E
        case .stoneDark: 0x6E6A63
        case .stoneLight: 0xC2BDB2
        case .plaster: 0xF2EEE4
        case .plasterCream: 0xE9DCC0
        case .earthWall: 0xC49A64
        case .darkWood: 0x4A3324
        case .cedar: 0x7A5434
        case .blackWood: 0x262321
        case .lightWood: 0xB8915F
        case .vermilion: 0xD9452B
        case .vermilionDark: 0xA3301F
        case .bamboo: 0x7FA34A
        case .bambooDry: 0xC9B27A
        case .bambooBlack: 0x3A3226
        case .twine: 0x2A2420
        // Each paint needs its own color: ModelScript models are matched back to the nearest Paint by color.
        case .tileGrey: 0x4B5057
        case .tileBlue: 0x3E4C63
        case .copper: 0x5E9C88
        case .gold: 0xD8A93A
        case .bronze: 0x5C5A3C
        case .thatch: 0xB79A63
        case .thatchDark: 0x8F7547
        case .shingle: 0x6B4A35
        case .snowRoof: 0xF4F6F8
        case .shoji: 0xEFE6D2
        case .windowGlow: 0xF3D9A4
        case .lanternRed: 0xD03A2A
        case .lanternWhite: 0xF4EEDC
        case .lanternYellow: 0xF1C24B
        case .lanternFire: 0xFFD58A
        case .highlight, .highlightStretch: 0xFFFFFF
        case .lattice: 0x3B2A1E
        case .door: 0x2E241C
        case .noren: 0x2D3E6B
        case .norenRed: 0x9E2B25
        case .bark: 0x4E3B2E
        case .barkGrey: 0x5E5752
        case .barkRed: 0x8A4B32
        case .sakura: 0xF4BCD0
        case .sakuraDeep: 0xE98FB0
        case .sakuraWhite: 0xF8E6EC
        case .umeRed: 0xC8384E
        case .umeWhite: 0xF6F1EA
        case .umePink: 0xE77D9E
        case .momijiRed: 0xC22A1E
        case .momijiOrange: 0xE2752A
        case .momijiGreen: 0x8DBA4A
        case .pineDark: 0x2F5233
        case .pineMid: 0x3F6B3D
        case .cedarGreen: 0x355A3A
        case .cypressGreen: 0x4A6E3A
        case .bambooLeaf: 0x6E9E3E
        case .bambooLeafGold: 0xB5B347
        case .ginkgoYellow: 0xF0C431
        case .ginkgoGreen: 0x8DB548
        case .willowGreen: 0x9DC060
        case .willowPale: 0xBFD68A
        case .azaleaMagenta: 0xD33B8C
        case .azaleaPink: 0xF29AB8
        case .azaleaWhite: 0xF4F0F0
        case .hydrangea: 0x7B8FD6
        case .leafDark: 0x3E6332
        case .lily: 0x4F8A3A
        case .lotus: 0xF2B6CC
        case .iris: 0x6B4FB0
        case .koiOrange: 0xF07A2A
        case .koiWhite: 0xF7F4EE
        case .foxWhite: 0xF4F1EA
        case .foxStone: 0xA8A398
        case .bib: 0xD33A2A
        case .rope: 0xE6D6A8
        case .paper: 0xF6F2E8
        }
    }
}

enum Surface: Int, CaseIterable {
    case matte
    case shiny
}

// Two small textures index every paint: one for albedo, one for glow (which changes with the time of day).
enum PaletteTextures {
    static func make(device: MTLDevice, time: TimeOfDay?) -> MTLTexture {
        let paints = Paint.allCases
        var pixels: [Float16] = []
        for paint in paints {
            let color = time.map { paint.glow($0) } ?? paint.albedo
            pixels += [Float16(color.x), Float16(color.y), Float16(color.z), 1]
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: paints.count, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.replace(region: MTLRegionMake2D(0, 0, paints.count, 1), mipmapLevel: 0, withBytes: pixels, bytesPerRow: paints.count * 8)
        return texture
    }

    static var sampler: MTLSamplerDescriptor {
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .nearest
        sampler.magFilter = .nearest
        sampler.sAddressMode = .clampToEdge
        sampler.tAddressMode = .clampToEdge
        sampler.supportArgumentBuffers = true
        return sampler
    }

    static func material(surface: Surface, albedo: MTLTexture, glow: MTLTexture) -> BlinnPhongSceneMaterial {
        let sampler = Self.sampler
        switch surface {
        case .matte:
            return BlinnPhongSceneMaterial(ambient: .texture(albedo, sampler: sampler), diffuse: .texture(albedo, sampler: sampler), specular: .color(0.05), shininess: 10, emission: .texture(glow, sampler: sampler))
        case .shiny:
            return BlinnPhongSceneMaterial(ambient: .texture(albedo, sampler: sampler), diffuse: .texture(albedo, sampler: sampler), specular: .color(0.55), shininess: 60, emission: .texture(glow, sampler: sampler))
        }
    }
}
