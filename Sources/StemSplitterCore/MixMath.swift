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
}
