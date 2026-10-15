import Foundation

enum GitHubAPIError: LocalizedError {
    case missingToken
    case badCredentials([GitHubCredentials.Source])
    case rateLimited(Date?)
    case mergeBlocked(String)
    case response(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Sign in with GitHub CLI (gh auth login) or configure an HTTPS Git credential. You can also add a fallback token in Settings."
        case let .badCredentials(sources): return "GitHub rejected the credential from \(sources.map(\.rawValue).joined(separator: ", ")) . Sign in again with gh auth login, or replace the fallback token in Settings.".replacingOccurrences(of: ") .", with: ").")
        case let .rateLimited(reset): return reset.map { "GitHub rate limit reached. Try again after \($0.formatted(date: .omitted, time: .shortened))." } ?? "GitHub rate limit reached. Try again later."
        case let .mergeBlocked(message): return "GitHub couldn’t merge this pull request: \(message)"
        case let .response(code, message): return "GitHub returned \(code): \(message)"
        }
    }
}

actor GitHubClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func repositories(host: String) async throws -> [Repository] {
        try await request("/user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100", host: host)
    }

    func currentUser(host: String) async throws -> User {
        try await request("/user", host: host)
    }

    func repository(fullName: String, host: String) async throws -> Repository {
        try await request("/repos/\(fullName)", host: host)
    }

    func close(_ pullRequest: PullRequest, host: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["state": "closed"])
        let _: PullResponse = try await request("/repos/\(pullRequest.repository.fullName)/pulls/\(pullRequest.number)", host: host, method: "PATCH", body: body)
    }

    func merge(_ pullRequest: PullRequest, host: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["merge_method": "merge"])
        let response: MergeResponse = try await request("/repos/\(pullRequest.repository.fullName)/pulls/\(pullRequest.number)/merge", host: host, method: "PUT", body: body)
        guard response.merged else { throw GitHubAPIError.mergeBlocked(response.message) }
    }

    func pullRequests(for repository: Repository, host: String, watching developers: Set<String>, createdSince: Date) async throws -> PullRequestBatch {
        let encoded = repository.fullName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repository.fullName
        let pulls: [PullResponse] = try await request("/repos/\(encoded)/pulls?state=all&sort=updated&direction=desc&per_page=100", host: host)
        // The activity list is intentionally based on creation time, not a
        // recent comment, commit, or review update on an older pull request.
        let recentPulls = pulls.filter { $0.createdAt >= createdSince }
        let authors = Set(recentPulls.map(\.user.login))
        var result: [PullRequest] = []
        for pull in recentPulls where developers.contains(pull.user.login) {
            // Historical PRs need only their list metadata for the Closed tab.
            // Open PRs get review data plus one check summary for the focused
            // Ready to merge signal.
            if pull.state == .closed {
                result.append(makePullRequest(pull, repository: repository, reviews: [], checks: []))
            } else {
                async let reviews: [Review] = request("/repos/\(encoded)/pulls/\(pull.number)/reviews?per_page=100", host: host)
                async let checks: CheckRunsResponse = request("/repos/\(encoded)/commits/\(pull.head.sha)/check-runs?per_page=100", host: host)
                result.append(try await makePullRequest(pull, repository: repository, reviews: reviews, checks: checks.checkRuns))
            }
        }
        return PullRequestBatch(authors: authors, pullRequests: result)
    }

    private func makePullRequest(_ pull: PullResponse, repository: Repository, reviews: [Review], checks: [CheckRun]) -> PullRequest {
        PullRequest(id: pull.id, number: pull.number, title: pull.title, state: pull.state, isDraft: pull.draft, author: pull.user.login, url: pull.htmlURL, createdAt: pull.createdAt, updatedAt: pull.updatedAt, closedAt: pull.closedAt, mergedAt: pull.mergedAt, headRef: pull.head.ref, baseRef: pull.base.ref, repository: repository, requestedReviewers: pull.requestedReviewers.map(\.login), reviews: reviews, checks: checks)
    }

    private func request<T: Decodable>(_ path: String, host: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let credentials = GitHubCredentials.credentials(for: host)
        guard !credentials.isEmpty else { throw GitHubAPIError.missingToken }
        // `appending(path:)` percent-encodes `?`, turning query parameters into
        // part of the path. Resolve the complete relative URL instead.
        guard let url = URL(string: String(path.drop(while: { $0 == "/" })), relativeTo: baseURL(for: host)) else { throw URLError(.badURL) }
        var rejectedSources: [GitHubCredentials.Source] = []
        for credential in credentials {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("MergeWatch", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 401 {
                rejectedSources.append(credential.source)
                continue
            }
            if http.statusCode == 403, let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String, message.localizedCaseInsensitiveContains("rate limit") {
                let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
                throw GitHubAPIError.rateLimited(reset)
            }
            guard 200 ..< 300 ~= http.statusCode else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw GitHubAPIError.response(http.statusCode, message)
            }
            return try decoder.decode(T.self, from: data)
        }
        throw GitHubAPIError.badCredentials(rejectedSources)
    }

    private func baseURL(for host: String) -> URL {
        let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return hostname.lowercased() == "github.com" ? URL(string: "https://api.github.com/")! : URL(string: "https://\(hostname)/api/v3/")!
    }
}
