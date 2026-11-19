import Foundation
import Testing
@testable import StemSplitterCore

struct BatchQueueTests {
    private let a = URL(fileURLWithPath: "/musik/a.mp3")
    private let b = URL(fileURLWithPath: "/musik/b.wav")
    private let c = URL(fileURLWithPath: "/musik/c.m4a")

    @Test func addsInOrderAndSkipsDuplicatesStillInQueue() {
        var queue = BatchQueue()
        #expect(queue.add([a, b]) == 2)
        #expect(queue.add([a, c]) == 1)   // a väntar redan
        #expect(queue.items.map(\.name) == ["a", "b", "c"])
        #expect(queue.next?.url == a)
    }

    @Test func finishedSongCanBeQueuedAgain() {
        var queue = BatchQueue()
        queue.add([a])
        queue.update(queue.items[0].id, to: .done(key: "k"))
        #expect(queue.add([a]) == 1)
    }

    @Test func worksThroughTheQueue() {
        var queue = BatchQueue()
        queue.add([a, b])
        let first = queue.next!
        queue.update(first.id, to: .working(stage: .separating, progress: 0.5))
        #expect(queue.current?.id == first.id)
        #expect(queue.next?.url == b)
        queue.update(first.id, to: .done(key: "k1"))
        #expect(queue.current == nil)
        #expect(queue.finishedCount == 1)
        #expect(queue.isActive)
        queue.update(queue.next!.id, to: .alreadyInLibrary(key: "k2"))
        #expect(!queue.isActive)
        #expect(queue.items.compactMap(\.state.projectKey) == ["k1", "k2"])
    }

    @Test func overallProgressCombinesSongs() {
        var queue = BatchQueue()
        queue.add([a, b])
        #expect(queue.overallProgress == 0)
        queue.update(queue.items[0].id, to: .done(key: "k"))
        #expect(queue.overallProgress == 0.5)
        queue.update(queue.items[1].id, to: .working(stage: .separating, progress: 1))
        #expect(abs(queue.overallProgress - 0.975) < 1e-9)
    }

    @Test func cancellingRemovesFromProgressAndStopsLateUpdates() {
        var queue = BatchQueue()
        queue.add([a, b])
        let working = queue.items[0].id
        queue.update(working, to: .working(stage: .converting, progress: 0.2))
        #expect(queue.cancel(working))              // var igång
        queue.update(working, to: .working(stage: .separating, progress: 0.3))   // sent besked
        #expect(queue.items[0].state == .cancelled)
        #expect(queue.counted.count == 1)
    }

    @Test func cancelAllAndClearFinished() {
        var queue = BatchQueue()
        queue.add([a, b, c])
        queue.update(queue.items[0].id, to: .done(key: "k"))
        queue.update(queue.items[1].id, to: .failed("fel"))
        queue.cancelAll()
        #expect(queue.items[2].state == .cancelled)
        #expect(!queue.isActive)
        queue.clearFinished()
        #expect(queue.items.isEmpty)
    }

    @Test func itemProgressGrowsThroughStages() {
        let values = [
            BatchQueue.itemProgress(stage: .reading, progress: nil),
            BatchQueue.itemProgress(stage: .preparing, progress: nil),
            BatchQueue.itemProgress(stage: .converting, progress: 1),
            BatchQueue.itemProgress(stage: .separating, progress: 0.5),
            BatchQueue.itemProgress(stage: .separating, progress: 1),
            BatchQueue.itemProgress(stage: .saving, progress: 1),
        ]
        #expect(values == values.sorted())
        #expect(values.last == 1)
    }
}

struct CollectAudioFilesTests {
    @Test func findsAudioInFoldersAndSkipsOtherFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("batch-\(UUID().uuidString)", isDirectory: true)
        let album = root.appendingPathComponent("Album", isDirectory: true)
        try fm.createDirectory(at: album, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for name in ["02 Andra.mp3", "10 Tionde.flac", "1 Första.wav", "omslag.jpg", ".dold.mp3"] {
            fm.createFile(atPath: album.appendingPathComponent(name).path, contents: Data())
        }
        let single = root.appendingPathComponent("Singel.m4a")
        fm.createFile(atPath: single.path, contents: Data())
        let text = root.appendingPathComponent("anteckning.txt")
        fm.createFile(atPath: text.path, contents: Data())

        let found = AudioFileSupport.collectAudioFiles(from: [album, single, text])
        // Mappens filer i naturlig sortering (1, 02, 10), sedan den enskilda filen
        #expect(found.map(\.lastPathComponent) == ["1 Första.wav", "02 Andra.mp3", "10 Tionde.flac", "Singel.m4a"])
    }

    @Test func missingPathsAreIgnored() {
        #expect(AudioFileSupport.collectAudioFiles(from: [URL(fileURLWithPath: "/finns/inte")]).isEmpty)
    }
}
