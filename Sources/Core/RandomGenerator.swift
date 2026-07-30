import CoreGraphics

/// SplitMix64: rápido, sin estado global y con la misma salida en todas las
/// plataformas. Eso último es lo que importa aquí — el mundo se genera por
/// índice de chunk, así que la misma semilla debe dar el mismo mundo hoy, en un
/// test y en el iPhone de otra persona.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        let unit = CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
