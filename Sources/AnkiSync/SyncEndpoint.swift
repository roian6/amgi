//
//  SyncEndpoint.swift
//  AnkiSync
//
//  Created by Vladimir Gusev on 20.08.2026.
//

public import Foundation

/// Normalization for the user-configured sync server URL.
///
/// Three screens let the user set this — onboarding, the sync sheet, and
/// sync settings — and each carried its own copy of the scheme handling,
/// so a fix to one never reached the other two.
public enum SyncEndpoint: Sendable {
    public static let official = "https://sync.ankiweb.net/"

    public enum ValidationError: LocalizedError, Sendable {
        case empty
        case insecureScheme
        case malformed

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Enter a server address."
            case .insecureScheme:
                return """
                    http:// sends your username, password, and sync key in \
                    cleartext. Use https://.
                    """
            case .malformed:
                return "That doesn't look like a valid server address."
            }
        }
    }

    /// Trims, defaults a missing scheme to https, and rejects cleartext.
    ///
    /// The `http://` rejection matters more than it looks: non-watch sync
    /// goes out through the Rust HTTP client, where App Transport Security
    /// provides no backstop. The watch transport uses URLSession, but shares
    /// this validation so every platform rejects cleartext credentials.
    public static func normalized(_ raw: String) throws(ValidationError) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") { throw .insecureScheme }

        let withScheme = lowered.hasPrefix("https://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host?.isEmpty == false else {
            throw .malformed
        }
        if url.host?.lowercased() == "sync.ankiweb.net",
           url.port == nil,
           url.path.isEmpty || url.path == "/",
           url.query == nil,
           url.fragment == nil {
            return official
        }
        return withScheme
    }
}
