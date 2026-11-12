import Testing
@testable import StemSplitterCore

struct AudioFileSupportTests {
    @Test func supportedExtensions() {
        #expect(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.wav")))
        #expect(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.MP3")))
        #expect(AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.Flac")))
        #expect(!AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.txt")))
        #expect(!AudioFileSupport.isSupported(URL(fileURLWithPath: "/tmp/lat.ogg")))
    }
}
