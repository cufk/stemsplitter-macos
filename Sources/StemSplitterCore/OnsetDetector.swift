import Foundation

/// Bygger en "onset-kurva" (hur mycket ny energi som tillkommer per tidsram) ur ljud.
/// Körs strömmande i block så att hela låten aldrig behöver ligga i minnet.
/// Två band: hela signalen och ett lågpassat band (bastrumma), som används för att hitta taktettan.
public struct OnsetDetector {
    public let sampleRate: Double
    public let hop: Int
    public var frameRate: Double { sampleRate / Double(hop) }

    /// Ny energi per ram, hela bandet.
    public private(set) var fullFlux: [Float] = []
    /// Ny energi per ram, lågt band.
    public private(set) var lowFlux: [Float] = []

    private let lowCoefficient: Float
    private var lowState: Float = 0
    private var fullEnergy: Float = 0
    private var lowEnergy: Float = 0
    private var count = 0
    private var previousFull: Float?
    private var previousLow: Float?

    public init(sampleRate: Double, frameRate: Double = 200, lowCutoff: Double = 150) {
        self.sampleRate = sampleRate
        self.hop = max(1, Int((sampleRate / frameRate).rounded()))
        self.lowCoefficient = Float(1 - exp(-2 * Double.pi * lowCutoff / sampleRate))
    }

    /// Kombinerad kurva (hela + lågt band) som används för tempo och slag.
    public var onsets: [Float] {
        zip(fullFlux, lowFlux).map { $0 + $1 }
    }

    public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            lowState += lowCoefficient * (sample - lowState)
            fullEnergy += sample * sample
            lowEnergy += lowState * lowState
            count += 1
            if count == hop {
                emitFrame()
            }
        }
    }

    public mutating func add(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { add($0) }
    }

    private mutating func emitFrame() {
        let scale = 1000 / Float(hop)
        let full = log1p(scale * fullEnergy)
        let low = log1p(scale * lowEnergy)
        fullFlux.append(max(0, full - (previousFull ?? full)))
        lowFlux.append(max(0, low - (previousLow ?? low)))
        previousFull = full
        previousLow = low
        fullEnergy = 0
        lowEnergy = 0
        count = 0
    }
}
