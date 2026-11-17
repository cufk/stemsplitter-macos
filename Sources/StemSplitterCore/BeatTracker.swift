import Foundation

/// Tempo- och slagdetektering ur en onset-kurva.
/// Tempo: autokorrelation viktad mot ~120 BPM. Slag: dynamisk programmering (Ellis 2007),
/// som väljer slag på starka onsets med så jämna avstånd som möjligt.
public enum BeatTracker {
    public static func estimateTempo(
        onsets: [Float],
        frameRate: Double,
        minBPM: Double = 60,
        maxBPM: Double = 200,
        preferredBPM: Double = 120,
        octaveSpread: Double = 1.0
    ) -> Double? {
        let count = onsets.count
        let minLag = max(1, Int(floor(60 * frameRate / maxBPM)))
        let maxLag = Int(ceil(60 * frameRate / minBPM))
        guard count > maxLag * 2 else { return nil }

        let mean = onsets.reduce(0, +) / Float(count)
        let centered = onsets.map { Double($0 - mean) }
        var correlation = [Double](repeating: 0, count: maxLag + 2)
        centered.withUnsafeBufferPointer { x in
            for lag in max(1, minLag - 1)...(maxLag + 1) {
                var sum = 0.0
                for i in 0..<(count - lag) {
                    sum += x[i] * x[i + lag]
                }
                correlation[lag] = sum / Double(count - lag)
            }
        }

        var bestLag = -1
        var bestScore = 0.0
        for lag in minLag...maxLag where correlation[lag] > 0 {
            let bpm = 60 * frameRate / Double(lag)
            let octaves = log2(bpm / preferredBPM) / octaveSpread
            let score = correlation[lag] * exp(-0.5 * octaves * octaves)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }

        // Parabolisk interpolation ger tempo mellan heltalslaggar
        var lag = Double(bestLag)
        let a = correlation[bestLag - 1], b = correlation[bestLag], c = correlation[bestLag + 1]
        let denominator = a - 2 * b + c
        if denominator < 0 {
            lag += max(-0.5, min(0.5, 0.5 * (a - c) / denominator))
        }
        return 60 * frameRate / lag
    }

    /// Slagens ramindex.
    public static func trackBeats(onsets: [Float], frameRate: Double, bpm: Double, tightness: Double = 100) -> [Int] {
        let count = onsets.count
        guard count > 0, bpm > 0, frameRate > 0 else { return [] }
        let period = 60 * frameRate / bpm
        guard period >= 2 else { return [] }

        let mean = onsets.reduce(0, +) / Float(count)
        let variance = onsets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(count)
        let deviation = sqrt(variance)
        guard deviation > 0 else { return [] }
        let local = onsets.map { Double($0 / deviation) }

        let minLag = max(1, Int((period / 2).rounded()))
        let maxLag = max(minLag, Int((period * 2).rounded()))
        var score = [Double](repeating: 0, count: count)
        var backlink = [Int](repeating: -1, count: count)

        for t in 0..<count {
            var best = -Double.infinity
            var bestPrevious = -1
            let high = t - minLag
            if high >= 0 {
                for previous in max(0, t - maxLag)...high {
                    let deviationFromPeriod = log(Double(t - previous) / period)
                    let candidate = score[previous] - tightness * deviationFromPeriod * deviationFromPeriod
                    if candidate > best {
                        best = candidate
                        bestPrevious = previous
                    }
                }
            }
            if bestPrevious >= 0 && best > 0 {
                score[t] = local[t] + best
                backlink[t] = bestPrevious
            } else {
                score[t] = local[t]
            }
        }

        // Sista slaget: högst poäng inom sista perioden
        let tailStart = max(0, count - Int(period.rounded()))
        var last = tailStart
        for t in tailStart..<count where score[t] > score[last] {
            last = t
        }
        var beats: [Int] = []
        var current = last
        while current >= 0 {
            beats.append(current)
            current = backlink[current]
        }
        beats.reverse()
        return trimWeakEdges(beats, onsets: local)
    }

    /// Tar bort slag i tysta partier i början och slutet (t.ex. tyst intro).
    private static func trimWeakEdges(_ beats: [Int], onsets: [Double]) -> [Int] {
        guard beats.count > 2 else { return beats }
        let strengths = beats.map { peak(onsets, around: $0, radius: 2) }
        let rms = sqrt(strengths.reduce(0) { $0 + $1 * $1 } / Double(strengths.count))
        let threshold = 0.25 * rms
        guard let first = strengths.firstIndex(where: { $0 >= threshold }),
              let last = strengths.lastIndex(where: { $0 >= threshold }) else { return beats }
        return Array(beats[first...last])
    }

    private static func peak<T: BinaryFloatingPoint>(_ values: [T], around index: Int, radius: Int) -> T {
        let low = max(0, index - radius)
        let high = min(values.count - 1, index + radius)
        guard low <= high else { return 0 }
        return values[low...high].max() ?? 0
    }

    /// Vilket slag (0..<beatsPerBar) som oftast har starkast bas — troligen ettan.
    public static func downbeatOffset(beatFrames: [Int], accent: [Float], beatsPerBar: Int = 4) -> Int {
        guard beatsPerBar > 1, !accent.isEmpty else { return 0 }
        var sums = [Float](repeating: 0, count: beatsPerBar)
        for (index, frame) in beatFrames.enumerated() {
            sums[index % beatsPerBar] += peak(accent, around: frame, radius: 2)
        }
        return sums.indices.max { sums[$0] < sums[$1] } ?? 0
    }

    /// Hela analysen: tempo, slag och taktettor.
    public static func analyze(onsets: [Float], lowOnsets: [Float], frameRate: Double, beatsPerBar: Int = 4) -> BeatGrid? {
        guard let estimate = estimateTempo(onsets: onsets, frameRate: frameRate) else { return nil }
        let frames = trackBeats(onsets: onsets, frameRate: frameRate, bpm: estimate)
        guard frames.count >= beatsPerBar else { return nil }
        let times = frames.map { Double($0) / frameRate }
        // Visat tempo: lutningen hos en rät linje genom alla slag (exaktare än ramupplösningen)
        let interval = averageInterval(times)
        let bpm = interval > 0 ? 60 / interval : estimate
        let offset = downbeatOffset(beatFrames: frames, accent: lowOnsets, beatsPerBar: beatsPerBar)
        return BeatGrid(bpm: bpm, beats: times, downbeatOffset: offset, beatsPerBar: beatsPerBar)
    }

    /// Minsta-kvadrat-anpassning av slagtid mot slagnummer; lutningen är sekunder per slag.
    public static func averageInterval(_ times: [Double]) -> Double {
        let count = times.count
        guard count > 1 else { return 0 }
        let meanIndex = Double(count - 1) / 2
        let meanTime = times.reduce(0, +) / Double(count)
        var numerator = 0.0
        var denominator = 0.0
        for (index, time) in times.enumerated() {
            let dx = Double(index) - meanIndex
            numerator += dx * (time - meanTime)
            denominator += dx * dx
        }
        return denominator > 0 ? numerator / denominator : 0
    }
}
