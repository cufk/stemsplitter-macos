import Foundation

/// Ren logik för uppspelningens position, sökning och segment — oberoende av AVFoundation.
public enum Transport {
    public static func clamp(_ seconds: Double, duration: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(max(0, seconds), max(0, duration))
    }

    public static func skip(from position: Double, by delta: Double, duration: Double) -> Double {
        clamp(position + delta, duration: duration)
    }

    /// Var play ska börja: från början om positionen står i (eller precis före) slutet.
    public static func resumePosition(_ position: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return position >= duration - 0.05 ? 0 : clamp(position, duration: duration)
    }

    /// Startframe och antal frames att schemalägga från `offset` sekunder in i en fil.
    /// Returnerar nil om inget återstår att spela.
    public static func segment(offset: Double, sampleRate: Double, length: Int64) -> (start: Int64, count: Int64)? {
        guard length > 0, sampleRate > 0, offset.isFinite else { return nil }
        let start = min(max(0, Int64(offset * sampleRate)), length)
        let count = length - start
        return count > 0 ? (start, count) : nil
    }

    /// Position i låten utifrån hur många källframes spelaren har renderat sedan start.
    /// Spelaren ligger före tempo-enheten, så frames räknas i källans tid — ingen tempokorrigering behövs.
    public static func position(startOffset: Double, renderedFrames: Int64, sampleRate: Double, duration: Double) -> Double {
        guard sampleRate > 0 else { return clamp(startOffset, duration: duration) }
        return clamp(startOffset + Double(max(0, renderedFrames)) / sampleRate, duration: duration)
    }
}
