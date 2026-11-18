import Testing
@testable import StemSplitterCore

struct PythonVersionTests {
    @Test func parsesVersionOutput() {
        let version = PythonVersion.parse("Python 3.12.4")
        #expect(version?.major == 3)
        #expect(version?.minor == 12)
        #expect(PythonVersion.parse("ingen version") == nil)
    }

    @Test func compatibilityRespectsMinimum() {
        #expect(PythonVersion.isCompatible("Python 3.9.6"))
        #expect(!PythonVersion.isCompatible("Python 3.8.10"))
        #expect(PythonVersion.isCompatible("Python 4.0.0"))
    }

    @Test func supportedRangeMatchesTorchWheels() {
        #expect(PythonVersion.isSupported("Python 3.9.6"))
        #expect(PythonVersion.isSupported("Python 3.12.10"))
        // Homebrews python3 är ofta 3.13+ — där saknas torch-hjulen i bootstrap.sh
        #expect(!PythonVersion.isSupported("Python 3.13.1"))
        #expect(!PythonVersion.isSupported("Python 3.8.10"))
    }

    @Test func candidatesPreferVersionedAndSkipSystemShim() {
        let without = PythonCandidates.paths(includeSystem: false)
        #expect(!without.contains("/usr/bin/python3"))
        #expect(without.first == "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3")
        #expect(without.firstIndex(of: "/opt/homebrew/bin/python3.12")! < without.firstIndex(of: "/opt/homebrew/bin/python3")!)
        #expect(Set(without).count == without.count)

        let with = PythonCandidates.paths(includeSystem: true)
        #expect(with.last == "/usr/bin/python3")
    }
}
