import Testing
@testable import StemSplitterCore

struct PythonVersionTests {
    @Test func parsesVersionOutput() {
        let v = PythonVersion.parse("Python 3.9.6")
        #expect(v?.major == 3 && v?.minor == 9)
        let v2 = PythonVersion.parse("Python 3.12.10")
        #expect(v2?.major == 3 && v2?.minor == 12)
        #expect(PythonVersion.parse("garbage") == nil)
    }

    @Test func compatibility() {
        #expect(PythonVersion.isCompatible("Python 3.9.6"))
        #expect(PythonVersion.isCompatible("Python 3.12.10"))
        #expect(!PythonVersion.isCompatible("Python 3.8.10"))
        #expect(!PythonVersion.isCompatible("inte python"))
    }
}
