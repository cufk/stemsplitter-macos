import Testing
@testable import StemSplitterCore

struct PassProgressTests {
    // Regression: med htdemucs_ft visades 0→100 % fyra gånger i stället för ett samlat förlopp.
    @Test func fourModelsBecomeOneProgress() {
        var progress = PassProgress(expectedPasses: 4)
        var overall: [Double] = []
        for _ in 0..<4 {
            for step in stride(from: 0.0, through: 1.0, by: 0.25) {
                overall.append(progress.update(step))
            }
        }
        #expect(overall == overall.sorted(), "det samlade förloppet ska aldrig gå bakåt")
        #expect(overall.first == 0)
        #expect(overall.last == 1)
        #expect(progress.passNumber == 4)
        // Halvvägs genom modell 2 = 37,5 %
        var second = PassProgress(expectedPasses: 4)
        _ = second.update(1.0)
        #expect(second.update(0.5) == 0.375)
    }

    @Test func singleModelIsUnchanged() {
        var progress = PassProgress(expectedPasses: 1)
        #expect(progress.update(0.3) == 0.3)
        #expect(progress.update(0.31) == 0.31)
        #expect(progress.passNumber == 1)
    }

    @Test func unexpectedExtraPassNeverExceedsOne() {
        var progress = PassProgress(expectedPasses: 1)
        _ = progress.update(1.0)
        let value = progress.update(0.5)
        #expect(progress.passes == 2)
        #expect(value <= 1)
        #expect(value == 0.75)
    }

    @Test func smallJitterIsNotANewPass() {
        var progress = PassProgress(expectedPasses: 2)
        _ = progress.update(0.5)
        _ = progress.update(0.45)
        #expect(progress.passNumber == 1)
    }

    @Test func modelPasses() {
        #expect(SeparationModel.standard.passes == 1)
        #expect(SeparationModel.best.passes == 4)
    }
}

struct DemucsLineTests {
    @Test func separationLine() {
        #expect(ProgressParser.classify(" 45%|████▌     | 78.0/175.5 [00:10<00:12,  7.81seconds/s]") == .separation(0.45))
    }

    @Test func downloadLine() {
        #expect(ProgressParser.classify(" 62%|██████▏   | 49.7M/80.2M [00:03<00:02, 15.2MB/s]") == .download(0.62))
    }

    @Test func otherLine() {
        #expect(ProgressParser.classify("Separated tracks will be stored in /tmp/out") == .other)
    }
}
