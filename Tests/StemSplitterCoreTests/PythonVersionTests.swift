import Testing
@testable import StemSplitterCore

struct PythonVersionTests {
    @Test func parsesVersionOutput() {
        #expect(PythonVersion.parse("Python 3.9.6") == (3, 9))
        #expect(PythonVersion.parse("Python 3.12.10") == (3, 12))
        #expect(PythonVersion.parse("garbage") == nil)
    }

    @Test func compatibility() {
        #expect(PythonVersion.isCompatible("Python 3.9.6"))
        #expect(PythonVersion.isCompatible("Python 3.12.10"))
        #expect(!PythonVersion.isCompatible("Python 3.8.10"))
        #expect(!PythonVersion.isCompatible("inte python"))
    }
}
