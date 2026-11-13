import Testing
@testable import StemSplitterCore

struct TimeFormatTests {
    @Test func formats() {
        #expect(TimeFormat.format(0) == "0:00")
        #expect(TimeFormat.format(9.4) == "0:09")
        #expect(TimeFormat.format(65) == "1:05")
        #expect(TimeFormat.format(3599.6) == "60:00")
        #expect(TimeFormat.format(-5) == "0:00")
        #expect(TimeFormat.format(.infinity) == "0:00")
    }
}
