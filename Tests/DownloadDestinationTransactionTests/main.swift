import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): return message
        }
    }
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw TestFailure.failed(message) }
}

private func write(_ value: String, to url: URL) throws {
    try Data(value.utf8).write(to: url)
}

private func read(_ url: URL) throws -> String {
    String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

@main
private struct DownloadDestinationTransactionTestRunner {
    static func main() {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "CornerFloat-DownloadTransactionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            defer { try? fileManager.removeItem(at: root) }

            try testFailedDownloadPreservesExistingFile(in: root)
            try testSuccessfulDownloadAtomicallyReplacesExistingFile(in: root)
            try testSuccessfulDownloadCreatesNewFile(in: root)
            try testDiscardRemovesPartialStagingFile(in: root)
            try testConcurrentTransactionsUseIndependentStagingFiles(in: root)

            print(
                "CornerFloat download transaction tests OK: failure preservation, "
                    + "atomic replacement, new destination, cleanup, and concurrent staging"
            )
        } catch {
            fputs("CornerFloat download transaction test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testFailedDownloadPreservesExistingFile(in root: URL) throws {
        let finalURL = root.appendingPathComponent("failure-existing.txt")
        try write("A", to: finalURL)
        let transaction = try DownloadDestinationTransaction(
            finalURL: finalURL,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        try expect(
            transaction.stagingURL.deletingLastPathComponent() == finalURL.deletingLastPathComponent(),
            "staging file was not placed beside the final destination"
        )
        try expect(try read(finalURL) == "A", "preparing a transaction changed the existing file")
        try write("partial B", to: transaction.stagingURL)

        // This models WKDownloadDelegate's failure/cancellation path.
        try transaction.discard()

        try expect(try read(finalURL) == "A", "a failed download replaced the existing file")
        try expect(
            !FileManager.default.fileExists(atPath: transaction.stagingURL.path),
            "a failed download left its staging file behind"
        )
    }

    private static func testSuccessfulDownloadAtomicallyReplacesExistingFile(
        in root: URL
    ) throws {
        let finalURL = root.appendingPathComponent("success-existing.txt")
        try write("A", to: finalURL)
        let transaction = try DownloadDestinationTransaction(
            finalURL: finalURL,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        try write("B", to: transaction.stagingURL)
        try expect(try read(finalURL) == "A", "staging a download changed the existing file")

        try transaction.commit()

        try expect(try read(finalURL) == "B", "a successful download did not replace A with B")
        try expect(
            !FileManager.default.fileExists(atPath: transaction.stagingURL.path),
            "a committed transaction left its staging path behind"
        )
    }

    private static func testSuccessfulDownloadCreatesNewFile(in root: URL) throws {
        let finalURL = root.appendingPathComponent("success-new.txt")
        let transaction = try DownloadDestinationTransaction(
            finalURL: finalURL,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        )
        try expect(
            !FileManager.default.fileExists(atPath: finalURL.path),
            "preparing a transaction created the final destination early"
        )
        try write("B", to: transaction.stagingURL)

        try transaction.commit()

        try expect(try read(finalURL) == "B", "a new destination did not receive the download")
        try expect(
            !FileManager.default.fileExists(atPath: transaction.stagingURL.path),
            "new-file commit left its staging path behind"
        )
    }

    private static func testDiscardRemovesPartialStagingFile(in root: URL) throws {
        let finalURL = root.appendingPathComponent("cleanup-only.txt")
        let transaction = try DownloadDestinationTransaction(
            finalURL: finalURL,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        )
        try write("partial", to: transaction.stagingURL)

        try transaction.discard()
        // Cleanup is intentionally idempotent so panel-close and WebKit's later
        // cancellation callback can both run safely.
        try transaction.discard()

        try expect(
            !FileManager.default.fileExists(atPath: transaction.stagingURL.path),
            "discard did not remove the temporary file"
        )
        try expect(
            !FileManager.default.fileExists(atPath: finalURL.path),
            "discard unexpectedly created or touched the final destination"
        )
    }

    private static func testConcurrentTransactionsUseIndependentStagingFiles(
        in root: URL
    ) throws {
        let finalURL = root.appendingPathComponent("concurrent.txt")
        try write("A", to: finalURL)
        let first = try DownloadDestinationTransaction(
            finalURL: finalURL,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        )
        let second = try DownloadDestinationTransaction(
            finalURL: finalURL,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
        )
        try expect(first.stagingURL != second.stagingURL, "concurrent downloads shared a staging path")
        try write("B", to: first.stagingURL)
        try write("C", to: second.stagingURL)
        try expect(try read(finalURL) == "A", "concurrent staging removed the original early")

        try first.commit()
        try expect(try read(finalURL) == "B", "first concurrent commit failed")
        try expect(
            FileManager.default.fileExists(atPath: second.stagingURL.path),
            "first commit removed the second download's staging file"
        )
        try second.commit()
        try expect(try read(finalURL) == "C", "second concurrent commit failed")
    }
}
