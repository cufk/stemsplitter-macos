import Foundation

public enum AudioFileSupport {
    public static let supportedExtensions = [
        "wav", "aiff", "aif", "caf", "mp3", "m4a", "m4b", "aac", "flac"
    ]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
