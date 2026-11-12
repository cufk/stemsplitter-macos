import Foundation

public enum StemLocator {
    public static func locate(in directory: URL) throws -> [StemKind: URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }
        var found: [StemKind: URL] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if let kind = StemKind(fileName: url.lastPathComponent) {
                found[kind] = url
            }
        }
        return found
    }
}
