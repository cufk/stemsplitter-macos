import AppKit
import Foundation

/// Enkel loggfil (~/Library/Application Support/StemSplitter/StemSplitter.log) för felsökning.
/// Skrivs i bakgrunden; roteras när den blir större än 2 MB.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    let url: URL
    private let queue = DispatchQueue(label: "StemSplitter.AppLog")
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter
    }()

    private init() {
        url = SeparationService.appSupportRoot.appendingPathComponent("StemSplitter.log")
        let fileManager = FileManager.default
        if let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? Int, size > 2_000_000 {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? fileManager.removeItem(at: old)
            try? fileManager.moveItem(at: url, to: old)
        }
    }

    func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async { [url] in
            let data = Data(line.utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    @MainActor
    func reveal() {
        write("— loggen öppnad —")
        queue.sync {}
        NSWorkspace.shared.open(url)
    }
}

func log(_ message: String) {
    AppLog.shared.write(message)
}
