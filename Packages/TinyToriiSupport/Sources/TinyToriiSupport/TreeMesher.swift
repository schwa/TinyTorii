import simd

// Trees are built in local space: origin on the ground at the cell's center, +y up.
enum TreeMesher {
    struct Branch {
        var a: SIMD3<Float>
        var b: SIMD3<Float>
        var radiusA: Float
        var radiusB: Float
    }

    // A small recursive branching structure; returns the twig tips.
    static func branches(_ builder: MeshBuilder, paint: Paint, random: inout SeededRandom, height: Float, radius: Float, lean: SIMD3<Float>, depth: Int, spread: Float, droop: Float = 0, sides: Int = 6) -> [SIMD3<Float>] {
        var tips: [SIMD3<Float>] = []
        func grow(from start: SIMD3<Float>, direction: SIMD3<Float>, length: Float, radius: Float, level: Int) {
            let end = start + direction * length
            builder.frustum(paint, from: start, to: end, radiusA: radius, radiusB: radius * 0.7, sides: sides)
            builder.blob(paint, center: end, scale: SIMD3(repeating: radius * 0.7))
            guard level > 0 else {
                tips.append(end)
                return
            }
            let children = level == depth ? 3 : 2
            for _ in 0..<children {
                let angle = random.range(0, 2 * .pi)
                var child = direction + SIMD3<Float>(cos(angle), 0, sin(angle)) * spread + SIMD3<Float>(0, -droop, 0)
                child = simd_normalize(child + SIMD3(random.signed(), random.signed() * 0.3, random.signed()) * 0.25)
                grow(from: end, direction: child, length: length * random.range(0.6, 0.8), radius: radius * 0.65, level: level - 1)
            }
            if random.chance(0.35) {
                tips.append(end)
            }
        }
        grow(from: .zero, direction: simd_normalize([0, 1, 0] + lean), length: height, radius: radius, level: depth)
        return tips
    }

    static func build(_ builder: MeshBuilder, item: Item) {
        var random = SeededRandom(seed: item.seed)
        let scale = 0.55 + 0.22 * Float(item.level)
        let lean = SIMD3<Float>(random.signed(), 0, random.signed()) * 0.15
        switch item.kind {
        case .sakura:
            let weeping = item.style == 2
            let tips = branches(builder, paint: .barkGrey, random: &random, height: 0.7 * scale, radius: 0.09 * scale, lean: lean, depth: 3, spread: weeping ? 0.6 : 0.9, droop: weeping ? 0.2 : 0)
            let colors: [Paint] = item.style == 1 ? [.sakuraDeep, .sakura, .sakuraDeep] : [.sakura, .sakuraWhite, .sakuraDeep]
            for tip in tips {
                for _ in 0..<3 {
                    let offset = SIMD3<Float>(random.signed(), random.signed() * 0.5, random.signed()) * 0.25 * scale
                    builder.blob(random.pick(colors), center: tip + offset, scale: SIMD3(repeating: random.range(0.16, 0.26) * scale), rotation: simd_quatf(angle: random.range(0, 6), axis: [0, 1, 0]))
                }
                if weeping {
                    var point = tip
                    for _ in 0..<5 {
                        point += [random.signed() * 0.03, -0.17 * scale, random.signed() * 0.03]
                        guard point.y > 0.15 else { break }
                        builder.blob(random.pick(colors), center: point, scale: SIMD3(repeating: 0.07 * scale))
                    }
                }
            }
            petals(builder, colors: colors, radius: 0.9 * scale, count: 14, random: &random)
        case .ume:
            let tips = branches(builder, paint: .bark, random: &random, height: 0.5 * scale, radius: 0.08 * scale, lean: lean * 2.5, depth: 3, spread: 1.3, sides: 5)
            let color: Paint = [.umeRed, .umeWhite, .umePink][item.style]
            for tip in tips {
                for _ in 0..<6 {
                    let offset = SIMD3<Float>(random.signed(), random.signed(), random.signed()) * 0.18 * scale
                    builder.blob(color, center: tip + offset, scale: SIMD3(repeating: 0.045 * scale))
                }
            }
            petals(builder, colors: [color], radius: 0.6 * scale, count: 8, random: &random)
        case .momiji:
            let tips = branches(builder, paint: .bark, random: &random, height: 0.55 * scale, radius: 0.07 * scale, lean: lean, depth: 3, spread: 1.1)
            let colors: [Paint] = switch item.style {
            case 1: [.momijiOrange, .ginkgoYellow, .momijiRed]
            case 2: [.momijiGreen, .willowGreen, .momijiGreen]
            default: [.momijiRed, .momijiRed, .momijiOrange]
            }
            for tip in tips {
                for _ in 0..<2 {
                    let offset = SIMD3<Float>(random.signed(), random.signed() * 0.3, random.signed()) * 0.22 * scale
                    builder.blob(random.pick(colors), center: tip + offset, scale: [0.3, 0.13, 0.3] * scale * random.range(0.8, 1.1), rotation: simd_quatf(angle: random.range(0, 6), axis: [0, 1, 0]))
                }
            }
            petals(builder, colors: colors, radius: 0.8 * scale, count: 10, random: &random)
        case .pine:
            let windswept = item.style == 2
            let trunkLean = windswept ? SIMD3<Float>(0.9, 0, 0.2) : lean * 3
            let trunk: Paint = item.style == 1 ? .barkRed : .bark
            var point = SIMD3<Float>.zero
            var direction = simd_normalize(SIMD3<Float>(0, 1, 0) + trunkLean * 0.5)
            let segments = 5
            var trunkPoints: [SIMD3<Float>] = []
            for segment in 0..<segments {
                let length = 0.3 * scale
                let next = point + direction * length
                let radius = 0.1 * scale * (1 - Float(segment) / Float(segments) * 0.6)
                builder.frustum(trunk, from: point, to: next, radiusA: radius, radiusB: radius * 0.85)
                builder.blob(trunk, center: next, scale: SIMD3(repeating: radius * 0.85))
                trunkPoints.append(next)
                point = next
                direction = simd_normalize(direction + SIMD3(random.signed() * 0.6, 0.2, random.signed() * 0.6) + (windswept ? [0.3, -0.05, 0] : .zero))
            }
            for (index, base) in trunkPoints.enumerated() where index >= 1 {
                let angle = random.range(0, 2 * .pi)
                let reach = (windswept ? 0.5 : 0.35) * scale * (1.2 - Float(index) * 0.12)
                var out = SIMD3<Float>(cos(angle), 0.1, sin(angle))
                if windswept {
                    out = simd_normalize(out + [1.2, 0, 0])
                }
                let end = base + out * reach
                builder.frustum(trunk, from: base, to: end, radiusA: 0.035 * scale, radiusB: 0.02 * scale, sides: 5)
                let padSize = 0.32 * scale * (1.1 - Float(index) * 0.1)
                builder.blob(.pineDark, center: end + [0, 0.05, 0], scale: [padSize, padSize * 0.32, padSize])
                builder.blob(.pineMid, center: end + [0, 0.11, 0], scale: [padSize * 0.75, padSize * 0.25, padSize * 0.75])
            }
            builder.blob(.pineDark, center: point + [0, 0.06, 0], scale: [0.3, 0.12, 0.3] * scale)
        case .sugi:
            let height = 2.2 * scale
            let green: Paint = item.style == 1 ? .cypressGreen : .cedarGreen
            builder.frustum(.barkRed, from: .zero, to: [0, height, 0], radiusA: 0.09 * scale, radiusB: 0.02, sides: 6)
            let layers = 5
            for layer in 0..<layers {
                let t = Float(layer) / Float(layers)
                let y = height * (0.25 + t * 0.6)
                let radius = 0.45 * scale * (1 - t * 0.75)
                builder.cone(green, base: [0, y, 0], tip: [0, y + 0.55 * scale, 0], radius: radius, sides: 7, capped: true)
            }
        case .bamboo:
            let count = 3 + item.level * 3
            let leaf: Paint = item.style == 1 ? .bambooLeafGold : .bambooLeaf
            let stalk: Paint = [.bamboo, .bambooDry, .bambooBlack][item.style]
            for _ in 0..<count {
                let base = SIMD3<Float>(random.signed() * 0.55, 0, random.signed() * 0.55)
                let height = random.range(1.6, 2.6)
                let tip = base + [random.signed() * 0.25, height, random.signed() * 0.25]
                builder.frustum(stalk, from: base, to: tip, radiusA: 0.035, radiusB: 0.02, sides: 5)
                var t: Float = 0.25
                while t < 1 {
                    let node = base + (tip - base) * t
                    builder.frustum(stalk == .bamboo ? .leafDark : .bark, from: node, to: node + [0, 0.025, 0], radiusA: 0.04, radiusB: 0.04, sides: 5)
                    t += 0.18
                }
                for _ in 0..<4 {
                    let tuft = base + (tip - base) * random.range(0.6, 1) + SIMD3(random.signed() * 0.15, 0, random.signed() * 0.15)
                    builder.blob(leaf, center: tuft, scale: [0.16, 0.05, 0.08], rotation: simd_quatf(angle: random.range(0, 6), axis: [0, 1, 0]))
                }
            }
        case .ginkgo:
            let height = 0.9 * scale
            builder.frustum(.barkGrey, from: .zero, to: [0, height * 1.6, 0], radiusA: 0.09 * scale, radiusB: 0.03, sides: 6)
            let color: Paint = item.style == 1 ? .ginkgoGreen : .ginkgoYellow
            for _ in 0..<12 {
                let t = random.range(0.4, 1.6)
                let width = (1.7 - t) * 0.4 * scale
                let angle = random.range(0, 2 * .pi)
                let center = SIMD3<Float>(cos(angle) * width * 0.6, height * t, sin(angle) * width * 0.6)
                builder.blob(color, center: center, scale: SIMD3(repeating: 0.24 * scale), rotation: simd_quatf(angle: angle, axis: [0, 1, 0]))
            }
            if item.style == 0 {
                petals(builder, colors: [.ginkgoYellow], radius: 0.9 * scale, count: 16, random: &random)
            }
        case .willow:
            let tips = branches(builder, paint: .bark, random: &random, height: 0.8 * scale, radius: 0.08 * scale, lean: lean, depth: 2, spread: 0.7)
            let colors: [Paint] = item.style == 1 ? [.willowGreen, .momijiGreen] : [.willowPale, .willowGreen]
            for tip in tips {
                builder.blob(colors[0], center: tip, scale: SIMD3(repeating: 0.2 * scale))
                for _ in 0..<6 {
                    let start = tip + SIMD3(random.signed() * 0.25, 0, random.signed() * 0.25) * scale
                    let length = min(start.y - 0.1, random.range(0.6, 1.1) * scale)
                    builder.cone(random.pick(colors), base: start, tip: start - [0, length, 0], radius: 0.06 * scale, sides: 3)
                }
            }
        default:
            break
        }
    }

    static func petals(_ builder: MeshBuilder, colors: [Paint], radius: Float, count: Int, random: inout SeededRandom) {
        for _ in 0..<count {
            let angle = random.range(0, 2 * .pi)
            let distance = sqrt(random.next()) * radius
            builder.disc(random.pick(colors), center: [cos(angle) * distance, 0.012, sin(angle) * distance], radius: 0.035, sides: 5)
        }
    }
}
