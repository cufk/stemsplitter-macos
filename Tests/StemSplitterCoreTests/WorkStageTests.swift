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
        // #expect kan inte anropa mutating-metoder — samla resultaten först
        let accepted = [0, 0.05, 0.12, 0.2, 1].map { throttle.accept($0) }
        #expect(accepted == [true, false, true, false, true])
    }
}
