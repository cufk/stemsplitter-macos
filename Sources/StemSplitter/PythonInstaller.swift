import AppKit
import Foundation

enum PythonInstaller {
    static let packageURL = URL(
        string: "https://www.python.org/ftp/python/3.12.10/python-3.12.10-macos11.pkg"
    )!

    /// Laddar ner Python-installationspaketet till Downloads. Returnerar sökvägen till .pkg.
    static func download(progress: @escaping (Double) -> Void) async throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = downloads.appendingPathComponent(packageURL.lastPathComponent)

        let delegate = DownloadDelegate(onProgress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: packageURL)
        delegate.task = task
        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            delegate.continuation = continuation
            task.resume()
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: location, to: destination)
        return destination
    }

    /// Öppnar .pkg i macOS Installer (användaren slutför installationen och anger lösenord).
    static func openInstaller(at url: URL) {
        NSWorkspace.shared.open(url)
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let onProgress: (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        var task: URLSessionDownloadTask?

        init(onProgress: @escaping (Double) -> Void) {
            self.onProgress = onProgress
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            if totalBytesExpectedToWrite > 0 {
                onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            continuation?.resume(returning: location)
            continuation = nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error, continuation != nil {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }
    }
}
