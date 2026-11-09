import simd

// Seeded mulberry32, so a seed always builds the same thing.
struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    init(_ string: String) {
        self.init(seed: fnv1a(string))
    }

    mutating func next() -> Float {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Float(Double(t ^ (t >> 14)) / 4_294_967_296)
    }

    mutating func nextUInt32() -> UInt32 {
        UInt32(Double(next()) * 4_294_967_000)
    }

    mutating func range(_ lower: Float, _ upper: Float) -> Float {
        lower + (upper - lower) * next()
    }

    mutating func int(_ count: Int) -> Int {
        min(Int(next() * Float(count)), count - 1)
    }

    mutating func pick<T>(_ array: [T]) -> T {
        array[int(array.count)]
    }

    mutating func signed() -> Float {
        next() * 2 - 1
    }

    mutating func chance(_ probability: Float) -> Bool {
        next() < probability
    }
}

func fnv1a(_ string: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for byte in string.utf8 {
        hash ^= UInt32(byte)
        hash = hash &* 16_777_619
    }
    return hash
}

func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

// sRGB hex to linear RGB, which the Blinn-Phong materials expect.
func linearColor(_ hex: UInt32) -> SIMD3<Float> {
    func channel(_ value: UInt32) -> Float {
        let c = Float(value & 0xFF) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return [channel(hex >> 16), channel(hex >> 8), channel(hex)]
}

extension SIMD2 where Scalar == Float {
    var perpendicular: SIMD2<Float> {
        [-y, x]
    }

    func lifted(_ height: Float) -> SIMD3<Float> {
        [x, height, y]
    }
}

extension SIMD3 where Scalar == Float {
    var xz: SIMD2<Float> {
        [x, z]
    }
}
