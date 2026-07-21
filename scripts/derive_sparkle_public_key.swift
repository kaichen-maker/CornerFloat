import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: derive_sparkle_public_key.swift PRIVATE_KEY_FILE\n", stderr)
    exit(2)
}

do {
    let keyURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let encoded = try String(contentsOf: keyURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: encoded), seed.count == 32 else {
        fputs("Sparkle private key must be a base64-encoded 32-byte Ed25519 seed.\n", stderr)
        exit(2)
    }

    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    print(privateKey.publicKey.rawRepresentation.base64EncodedString())
} catch {
    fputs("Unable to read or derive the Sparkle key: \(error.localizedDescription)\n", stderr)
    exit(2)
}
