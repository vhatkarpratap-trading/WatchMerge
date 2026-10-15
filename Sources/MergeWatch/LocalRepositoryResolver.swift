import AppKit
import Foundation

enum LocalRepositoryResolver {
    @MainActor
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a local Git repository"
        panel.message = "MergeWatch will use this repository’s origin remote to monitor its pull requests."
        panel.prompt = "Add repository"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func target(for folder: URL) throws -> LocalRepositoryTarget {
        let path = folder.standardizedFileURL.path
        guard let remote = git(["-C", path, "remote", "get-url", "origin"]), !remote.isEmpty else {
            throw LocalRepositoryError.noOrigin(path)
        }
        guard let parsed = parse(remote: remote) else { throw LocalRepositoryError.unsupportedRemote(remote) }
        return LocalRepositoryTarget(localPath: path, fullName: parsed.fullName, host: parsed.host)
    }

    private static func git(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }

    private static func parse(remote: String) -> (host: String, fullName: String)? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        let path: String
        if let ssh = trimmed.range(of: "@"), !trimmed.contains("://") {
            let remainder = String(trimmed[ssh.upperBound...])
            guard let separator = remainder.firstIndex(of: ":") else { return nil }
            host = String(remainder[..<separator])
            path = String(remainder[remainder.index(after: separator)...])
        } else if let url = URL(string: trimmed), let parsedHost = url.host {
            host = parsedHost
            path = url.path
        } else { return nil }
        let components = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: ".git", with: "")
            .split(separator: "/")
        guard components.count >= 2 else { return nil }
        return (host, components.prefix(2).joined(separator: "/"))
    }
}

enum LocalRepositoryError: LocalizedError {
    case noOrigin(String)
    case unsupportedRemote(String)
    var errorDescription: String? {
        switch self {
        case let .noOrigin(path): return "\(path) is not a Git repository with an origin remote."
        case let .unsupportedRemote(remote): return "MergeWatch can’t understand the origin remote: \(remote)"
        }
    }
}
