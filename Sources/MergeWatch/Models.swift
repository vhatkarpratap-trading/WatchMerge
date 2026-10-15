import Foundation

struct Repository: Codable, Hashable, Identifiable, Comparable {
    let id: Int
    let fullName: String
    let htmlURL: URL
    let isPrivate: Bool
    var name: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }
    static func < (lhs: Repository, rhs: Repository) -> Bool { lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending }

    enum CodingKeys: String, CodingKey { case id, fullName = "full_name", htmlURL = "html_url", isPrivate = "private" }
}

struct LocalRepositoryTarget: Codable, Hashable, Identifiable {
    let localPath: String
    let fullName: String
    let host: String
    var id: String { localPath }
    var folderName: String { URL(fileURLWithPath: localPath).lastPathComponent }
}

enum PullRequestState: String, Codable, CaseIterable {
    case open, closed
}

enum ReviewStatus: String, Codable {
    case approved, changesRequested, pending, commented, dismissed, none

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).uppercased()
        switch value {
        case "APPROVED": self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "PENDING": self = .pending
        case "COMMENTED": self = .commented
        case "DISMISSED": self = .dismissed
        default: self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum CheckState: String, Codable {
    case success, failure, pending, neutral, skipped, cancelled, unknown
}

enum PipelineStatus: Equatable {
    case notReported
    case running(completed: Int, total: Int)
    case failed
    case passed
    case completed
}

struct PullRequest: Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let state: PullRequestState
    let isDraft: Bool
    let author: String
    let url: URL
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let mergedAt: Date?
    let headRef: String
    let baseRef: String
    let repository: Repository
    let requestedReviewers: [String]
    var reviews: [Review]
    var checks: [CheckRun]

    var isMerged: Bool { mergedAt != nil }
    /// Every check GitHub reported for the current head commit must have
    /// completed successfully. No reported checks is not ready.
    var hasPassedAllChecks: Bool { !checks.isEmpty && checks.allSatisfy { $0.state == .success } }
    var pipelineStatus: PipelineStatus {
        guard !checks.isEmpty else { return .notReported }
        let completed = checks.filter { $0.status == "completed" }.count
        if checks.contains(where: { $0.state == .failure || $0.state == .cancelled }) { return .failed }
        if completed < checks.count { return .running(completed: completed, total: checks.count) }
        return hasPassedAllChecks ? .passed : .completed
    }
    var reviewStatus: ReviewStatus {
        if reviews.contains(where: { $0.state == .changesRequested }) { return .changesRequested }
        if reviews.contains(where: { $0.state == .approved }) { return .approved }
        if !requestedReviewers.isEmpty || reviews.contains(where: { $0.state == .pending }) { return .pending }
        return .none
    }
    var needsAttention: Bool { state == .open && (reviewStatus == .pending || reviewStatus == .changesRequested) }
}

struct PullRequestBatch {
    let authors: Set<String>
    let pullRequests: [PullRequest]
}

struct Review: Codable, Hashable, Identifiable {
    let id: Int
    let state: ReviewStatus
    let user: User
}

struct User: Codable, Hashable { let login: String }

struct CheckRun: Codable, Hashable, Identifiable {
    let id: Int
    let status: String
    let conclusion: String?

    var state: CheckState {
        if status != "completed" { return .pending }
        switch conclusion {
        case "success": return .success
        case "failure", "timed_out", "action_required", "startup_failure", "stale": return .failure
        case "cancelled": return .cancelled
        case "neutral": return .neutral
        case "skipped": return .skipped
        default: return .unknown
        }
    }
}

struct PullResponse: Decodable {
    let id: Int
    let number: Int
    let title: String
    let state: PullRequestState
    let draft: Bool
    let user: User
    let htmlURL: URL
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let mergedAt: Date?
    let requestedReviewers: [User]
    let head: Branch
    let base: Branch
    struct Branch: Decodable { let ref: String; let sha: String }
    enum CodingKeys: String, CodingKey {
        case id, number, title, state, draft, user, htmlURL = "html_url", createdAt = "created_at", updatedAt = "updated_at", closedAt = "closed_at", mergedAt = "merged_at", requestedReviewers = "requested_reviewers", head, base
    }
}

struct CheckRunsResponse: Decodable {
    let checkRuns: [CheckRun]
    enum CodingKeys: String, CodingKey { case checkRuns = "check_runs" }
}

struct MergeResponse: Decodable {
    let merged: Bool
    let message: String
}

