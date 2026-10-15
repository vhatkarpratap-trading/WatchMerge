import Foundation

/// Reads credentials already managed by the developer's machine. A token saved
/// explicitly by MergeWatch remains a fallback for machines without GitHub CLI
/// or an HTTPS Git credential helper.
enum GitHubCredentials {
    struct Credential {
        let token: String
        let source: Source
    }

    enum Source: String {
        case mergeWatchKeychain = "MergeWatch Keychain"
        case githubCLI = "GitHub CLI"
        case gitCredentialHelper = "Git credential helper"
        case unavailable
    }

    static func credentials(for host: String) -> [Credential] {
        let hostname = normalizeHost(host)
        var candidates: [Credential] = []
        if let token = run("/usr/bin/env", arguments: ["gh", "auth", "token", "--hostname", hostname]), !token.isEmpty {
            candidates.append(Credential(token: token, source: .githubCLI))
        }
        let gitResponse = run("/usr/bin/git", arguments: ["credential", "fill"], input: "protocol=https\nhost=\(hostname)\n\n")
        if let token = gitResponse?.split(separator: "\n").first(where: { $0.hasPrefix("password=") }).map({ String($0.dropFirst(9)) }), !token.isEmpty {
            candidates.append(Credential(token: token, source: .gitCredentialHelper))
        }
        if let token = Keychain.readToken(), !token.isEmpty {
            candidates.append(Credential(token: token, source: .mergeWatchKeychain))
        }
        // A user may have the same token in gh and Keychain. Avoid sending it twice.
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.token).inserted }
    }

    static func source(for host: String) -> Source {
        credentials(for: host).first?.source ?? .unavailable
    }

    /// Best-effort discovery is intentionally metadata-only: no token is read.
    static func detectedHost() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "status"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return text.split(separator: "\n").map(String.init).first { line in
                !line.hasPrefix(" ") && line.contains(".") && !line.hasPrefix("-")
            }
        } catch { return nil }
    }

    private static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func run(_ executable: String, arguments: [String], input: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        if let input {
            let standardInput = Pipe()
            process.standardInput = standardInput
            standardInput.fileHandleForWriting.write(Data(input.utf8))
            standardInput.fileHandleForWriting.closeFile()
        }
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }
}
