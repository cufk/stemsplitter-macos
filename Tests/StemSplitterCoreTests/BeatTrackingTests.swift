import Foundation
import Testing
@testable import StemSplitterCore

/// Syntetiska "kickar" (avklingande 70 Hz-sinus) på kända tider.
private func kickTrack(bpm: Double, seconds: Double, sampleRate: Double = 44100, start: Double = 0.25,
                       accentEvery: Int? = nil, silentUntil: Double = 0) -> (samples: [Float], times: [Double]) {
    var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
    var times: [Double] = []
    let period = 60 / bpm
    var t = start
    var index = 0
    while t < seconds - 0.1 {
        if t >= silentUntil {
            let amplitude: Double = (accentEvery.map { index % $0 == 0 } ?? true) ? 0.8 : 0.35
            let first = Int(t * sampleRate)
            for i in 0..<Int(0.08 * sampleRate) {
                let tt = Double(i) / sampleRate
                samples[first + i] += Float(amplitude * sin(2 * Double.pi * 70 * tt) * exp(-tt / 0.03))
            }
            times.append(t)
        }
        t += period
        index += 1
    }
    return (samples, times)
}

private func analyze(_ samples: [Float]) -> (grid: BeatGrid?, detector: OnsetDetector) {
    var detector = OnsetDetector(sampleRate: 44100)
    // Strömmande i block, som i appen
    var offset = 0
    while offset < samples.count {
        let end = min(samples.count, offset + 4096)
        detector.add(Array(samples[offset..<end]))
        offset = end
    }
    let grid = BeatTracker.analyze(onsets: detector.onsets, lowOnsets: detector.lowFlux, frameRate: detector.frameRate)
    return (grid, detector)
}

struct BeatTrackingTests {
    @Test(arguments: [90.0, 120.0, 128.0])
    func findsTempoAndBeats(bpm: Double) throws {
        let track = kickTrack(bpm: bpm, seconds: 15)
        let grid = try #require(analyze(track.samples).grid)
        #expect(abs(grid.bpm - bpm) < 0.5)
        #expect(grid.beats.count == track.times.count)
        for beat in grid.beats {
            let error = track.times.map { abs($0 - beat) }.min() ?? 1
            #expect(error < 0.015)
        }
    }

    @Test func skipsSilentIntro() throws {
        let track = kickTrack(bpm: 100, seconds: 15, silentUntil: 3)
        let grid = try #require(analyze(track.samples).grid)
        #expect(abs(grid.beats[0] - track.times[0]) < 0.015)
        #expect(grid.beats.count == track.times.count)
    }

    @Test func accentedBeatBecomesDownbeat() throws {
        // Starkare kick på varje fjärde slag, med början på slag 0
        let track = kickTrack(bpm: 128, seconds: 15, accentEvery: 4)
        let grid = try #require(analyze(track.samples).grid)
        let downbeats = grid.barStarts
        #expect(abs(downbeats[0] - track.times[0]) < 0.015)
        #expect(abs(downbeats[1] - track.times[4]) < 0.015)
    }

    @Test func silenceGivesNoGrid() {
        #expect(analyze([Float](repeating: 0, count: 44100 * 5)).grid == nil)
    }

    @Test func impulseEnvelopeGivesExactTempo() {
        var onsets = [Float](repeating: 0, count: 4000)
        for frame in stride(from: 37, to: 4000, by: 100) { onsets[frame] = 1 }
        #expect(abs((BeatTracker.estimateTempo(onsets: onsets, frameRate: 200) ?? 0) - 120) < 0.5)
        let beats = BeatTracker.trackBeats(onsets: onsets, frameRate: 200, bpm: 120)
        #expect(beats == Array(stride(from: 37, to: 4000, by: 100)))
    }

    @Test func averageIntervalFitsLine() {
        #expect(abs(BeatTracker.averageInterval([1.0, 1.5, 2.0, 2.5]) - 0.5) < 1e-9)
        #expect(BeatTracker.averageInterval([1.0]) == 0)
    }
}

struct BeatGridTests {
    private let grid = BeatGrid(bpm: 120, beats: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5], downbeatOffset: 1)

    @Test func downbeatsFollowOffset() {
        #expect(grid.isDownbeat(1))
        #expect(grid.isDownbeat(5))
        #expect(!grid.isDownbeat(0))
        #expect(grid.barStarts == [0.5, 2.5])
    }

    @Test func offsetIsNormalized() {
        #expect(BeatGrid(bpm: 120, beats: [], downbeatOffset: -1).downbeatOffset == 3)
        #expect(grid.shiftingDownbeat(by: 3).downbeatOffset == 0)
    }

    @Test func halvingKeepsDownbeats() {
        let half = grid.halved()
        #expect(half.bpm == 60)
        #expect(half.beats == [0.5, 1.5, 2.5, 3.5])
        #expect(half.barStarts.first == 0.5)
    }

    @Test func doublingInsertsMidpoints() {
        let double = BeatGrid(bpm: 60, beats: [0, 1, 2], downbeatOffset: 1).doubled()
        #expect(double.bpm == 120)
        #expect(double.beats == [0, 0.5, 1, 1.5, 2])
        #expect(double.isDownbeat(2))
    }

    @Test func findsFirstBeatAtOrAfter() {
        #expect(grid.firstBeatIndex(atOrAfter: 0) == 0)
        #expect(grid.firstBeatIndex(atOrAfter: 1.2) == 3)
        #expect(grid.firstBeatIndex(atOrAfter: 10) == grid.beats.count)
    }

    @Test func roundTripsInProjectMeta() throws {
        let meta = ProjectMeta(sourceName: "a.wav", createdAt: Date(timeIntervalSince1970: 0), model: "htdemucs", beatGrid: grid)
        #expect(try ProjectMeta.decode(meta.encoded()).beatGrid == grid)
    }

    @Test func olderProjectsWithoutGridStillDecode() throws {
        let json = #"{"createdAt":"2026-01-01T00:00:00Z","model":"htdemucs","peaks":{},"sourceName":"a.wav"}"#
        #expect(try ProjectMeta.decode(Data(json.utf8)).beatGrid == nil)
    }
}

struct ClickSynthTests {
    @Test func clickIsShortAndDecays() {
        let click = ClickSynth.click(sampleRate: 44100, accent: false)
        #expect(click.count == Int(0.04 * 44100))
        #expect(click.prefix(200).map(abs).max()! > 0.3)
        #expect(click.suffix(100).map(abs).max()! < 0.01)
    }

    @Test func accentIsLouder() {
        let normal = ClickSynth.click(sampleRate: 44100, accent: false).map(abs).max()!
        let accent = ClickSynth.click(sampleRate: 44100, accent: true).map(abs).max()!
        #expect(accent > normal)
    }
}
