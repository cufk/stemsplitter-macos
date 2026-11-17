import Foundation

public enum MixMath {
    /// Klipper ett ljudbuffer till [min, max] på plats (används vid export så att mixen aldrig överstyr).
    public static func clampChannel(_ buffer: UnsafeMutablePointer<Float>, count: Int, min minimum: Float = -1, max maximum: Float = 1) {
        guard count > 0 else { return }
        for i in 0..<count {
            buffer[i] = Swift.min(Swift.max(buffer[i], minimum), maximum)
        }
    }

    /// Effektiv förstärkning för en stem med hänsyn till mute och solo.
    /// Mute vinner alltid; om någon stem är solo hörs bara solo-stems.
    public static func effectiveGain(volume: Double, muted: Bool, soloed: Bool, anySoloed: Bool) -> Float {
        if muted { return 0 }
        if anySoloed && !soloed { return 0 }
        return Float(max(0, volume))
    }

    /// Antal utdataframes när `sourceDuration` sekunder spelas i `tempo` (1.0 = originaltempo).
    public static func outputFrameCount(sourceDuration: Double, tempo: Double, sampleRate: Double) -> Int64 {
        guard sourceDuration > 0, sampleRate > 0, sourceDuration.isFinite else { return 0 }
        let rate = max(tempo, 0.01)
        return Int64((sourceDuration / rate * sampleRate).rounded(.up))
    }

    /// Halvtoner till cent, som `AVAudioUnitTimePitch.pitch` förväntar sig.
    public static func cents(fromSemitones semitones: Double) -> Float {
        Float(min(max(semitones, -24), 24) * 100)
    }

    /// Det som blir kvar av mixen när de givna stems dras bort: `out = mix − Σ stems`.
    /// Används för att låta "Övrigt" innehålla allt som inte är sång, trummor eller bas,
    /// så att summan av alla stems blir exakt originalet.
    public static func residual(
        mix: UnsafePointer<Float>,
        subtracting stems: [UnsafePointer<Float>],
        into output: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        guard count > 0 else { return }
        for i in 0..<count {
            var value = mix[i]
            for stem in stems {
                value -= stem[i]
            }
            output[i] = value
        }
    }

    /// Nivåskillnad i dB mellan två energier (t.ex. hur mycket som saknades).
    public static func decibels(energy: Double, reference: Double) -> Double {
        guard energy > 0, reference > 0 else { return -.infinity }
        return 10 * log10(energy / reference)
    }

    /// Om tempo och tonläge är neutrala kan tidsenheten kopplas förbi (ingen bearbetning av ljudet).
    public static func isNeutralTuning(tempo: Double, semitones: Double) -> Bool {
        abs(tempo - 1) < 0.0001 && abs(semitones) < 0.0001
    }
}
