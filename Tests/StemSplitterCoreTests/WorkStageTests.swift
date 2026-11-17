import Testing
@testable import StemSplitterCore

struct WorkStageTests {
    @Test func wavSkipsConversion() {
        #expect(WorkStage.stages(for: "WAV") == [.reading, .preparing, .separating, .saving])
        #expect(WorkStage.stages(for: "mp3") == [.reading, .preparing, .converting, .separating, .saving])
    }

    @Test func stagesAreOrdered() {
        #expect(WorkStage.reading < .separating)
        #expect(!(WorkStage.saving < .converting))
    }

    @Test func throttleSkipsSmallChanges() {
        var throttle = ProgressThrottle(step: 0.1)
        #expect(throttle.accept(0))
        #expect(!throttle.accept(0.05))
        #expect(throttle.accept(0.12))
        #expect(!throttle.accept(0.2))
        #expect(throttle.accept(1))
    }
}
