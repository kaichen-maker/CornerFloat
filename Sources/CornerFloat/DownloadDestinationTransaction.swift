import Darwin
import Foundation

enum DownloadDestinationTransactionError: LocalizedError {
    case invalidDestination
    case destinationDirectoryUnavailable(String)
    case destinationIsDirectory(String)
    case stagingPathCollision(String)
    case stagingFileMissing(String)
    case atomicCommitFailed(path: String, code: Int32)
    case cleanupFailed(path: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "Choose a valid file destination."
        case let .destinationDirectoryUnavailable(path):
            return "The destination folder is unavailable: \(path)"
        case let .destinationIsDirectory(path):
            return "The selected destination is a folder, not a file: \(path)"
        case let .stagingPathCollision(path):
            return "CornerFloat could not reserve a unique temporary download path: \(path)"
        case let .stagingFileMissing(path):
            return "The temporary download file is missing: \(path)"
        case let .atomicCommitFailed(path, code):
            return "CornerFloat could not finish saving the download to \(path). \(Self.posixMessage(code))"
        case let .cleanupFailed(path, code):
            return "CornerFloat could not remove the temporary download file at \(path). \(Self.posixMessage(code))"
        }
    }

    private static func posixMessage(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}

/// Stages a WebKit download beside its final destination and publishes it with
/// one atomic filesystem rename only after WebKit reports success.
///
/// A transaction never removes or truncates `finalURL` while the download is in
/// progress. Because the staging file lives in the same directory, POSIX
/// `rename(2)` can atomically replace an existing regular file or move a new
/// file into place without exposing a partially downloaded destination.
struct DownloadDestinationTransaction: Sendable {
    let finalURL: URL
    let stagingURL: URL

    init(
        finalURL: URL,
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws {
        guard finalURL.isFileURL, !finalURL.lastPathComponent.isEmpty else {
            throw DownloadDestinationTransactionError.invalidDestination
        }

        let normalizedFinalURL = finalURL.standardizedFileURL
        let directoryURL = normalizedFinalURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DownloadDestinationTransactionError.destinationDirectoryUnavailable(
                directoryURL.path
            )
        }

        var destinationIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: normalizedFinalURL.path,
            isDirectory: &destinationIsDirectory
        ), destinationIsDirectory.boolValue {
            throw DownloadDestinationTransactionError.destinationIsDirectory(
                normalizedFinalURL.path
            )
        }

        let stagingURL = directoryURL.appendingPathComponent(
            ".cornerfloat-download-\(identifier.uuidString.lowercased()).tmp",
            isDirectory: false
        )
        guard stagingURL != normalizedFinalURL,
              !fileManager.fileExists(atPath: stagingURL.path) else {
            throw DownloadDestinationTransactionError.stagingPathCollision(stagingURL.path)
        }

        self.finalURL = normalizedFinalURL
        self.stagingURL = stagingURL
    }

    /// Atomically publishes the completed staging file. On failure, the final
    /// destination is left untouched and the staging file is removed.
    func commit(fileManager: FileManager = .default) throws {
        var stagingIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: stagingURL.path,
            isDirectory: &stagingIsDirectory
        ), !stagingIsDirectory.boolValue else {
            throw DownloadDestinationTransactionError.stagingFileMissing(stagingURL.path)
        }

        let status = stagingURL.path.withCString { sourcePath in
            finalURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard status == 0 else {
            let code = errno
            try? discard()
            throw DownloadDestinationTransactionError.atomicCommitFailed(
                path: finalURL.path,
                code: code
            )
        }
    }

    /// Removes only this transaction's unique staging path. The final
    /// destination is never touched, including when a download fails or is
    /// cancelled.
    func discard() throws {
        let status = stagingURL.path.withCString { Darwin.unlink($0) }
        guard status == 0 || errno == ENOENT else {
            let code = errno
            throw DownloadDestinationTransactionError.cleanupFailed(
                path: stagingURL.path,
                code: code
            )
        }
    }
}
