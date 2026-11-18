import Foundation

/// Slagen i en låt: tempo, tidpunkt för varje slag och var taktettorna ligger.
public struct BeatGrid: Codable, Equatable, Sendable {
    public var bpm: Double
    /// Slagens tidpunkter i sekunder, stigande.
    public var beats: [Double]
    /// Index (0..<beatsPerBar) för det första slaget som är en etta.
    public var downbeatOffset: Int
    public var beatsPerBar: Int

    public init(bpm: Double, beats: [Double], downbeatOffset: Int = 0, beatsPerBar: Int = 4) {
        self.bpm = bpm
        self.beats = beats
        self.beatsPerBar = max(1, beatsPerBar)
        self.downbeatOffset = ((downbeatOffset % self.beatsPerBar) + self.beatsPerBar) % self.beatsPerBar
    }

    public func isDownbeat(_ index: Int) -> Bool {
        ((index - downbeatOffset) % beatsPerBar + beatsPerBar) % beatsPerBar == 0
    }

    /// Starttid för varje takt (taktettorna).
    public var barStarts: [Double] {
        beats.indices.filter(isDownbeat).map { beats[$0] }
    }

    /// Index för första slaget vid eller efter `time` (binärsökning).
    public func firstBeatIndex(atOrAfter time: Double) -> Int {
        var low = 0
        var high = beats.count
        while low < high {
            let mid = (low + high) / 2
            if beats[mid] < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Halva tempot: vartannat slag (ettorna behålls).
    public func halved() -> BeatGrid {
        guard beats.count > 1 else { return self }
        let start = downbeatOffset % 2
        let kept = stride(from: start, to: beats.count, by: 2).map { beats[$0] }
        return BeatGrid(bpm: bpm / 2, beats: kept, downbeatOffset: (downbeatOffset - start) / 2, beatsPerBar: beatsPerBar)
    }

    /// Dubbla tempot: ett nytt slag mitt emellan varje par.
    public func doubled() -> BeatGrid {
        guard beats.count > 1 else { return self }
        var result: [Double] = []
        result.reserveCapacity(beats.count * 2)
        for index in beats.indices {
            result.append(beats[index])
            if index + 1 < beats.count {
                result.append((beats[index] + beats[index + 1]) / 2)
            }
        }
        return BeatGrid(bpm: bpm * 2, beats: result, downbeatOffset: downbeatOffset * 2, beatsPerBar: beatsPerBar)
    }

    /// Flytta ettan ett antal slag (t.ex. om analysen lagt den på tvåan).
    public func shiftingDownbeat(by delta: Int) -> BeatGrid {
        BeatGrid(bpm: bpm, beats: beats, downbeatOffset: downbeatOffset + delta, beatsPerBar: beatsPerBar)
    }
}
