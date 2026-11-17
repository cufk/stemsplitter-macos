import Foundation

/// Syntetiserar ett kort metronomklick (avklingande sinus). Ettan är ljusare och starkare.
public enum ClickSynth {
    public static func click(sampleRate: Double, accent: Bool, duration: Double = 0.04) -> [Float] {
        let count = max(1, Int(duration * sampleRate))
        let frequency = accent ? 1760.0 : 1200.0
        let amplitude: Double = accent ? 0.9 : 0.6
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            return Float(amplitude * sin(2 * Double.pi * frequency * t) * exp(-t / 0.007))
        }
    }
}
