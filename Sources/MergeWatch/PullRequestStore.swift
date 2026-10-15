import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class PullRequestStore: ObservableObject {
    @Published private(set) var pullRequests: [PullRequest] = []
    @Published private(set) var repositories: [Repository] = []
    @Published var localRepositories: [LocalRepositoryTarget] { didSet { persistLocalRepositories() } }
    @Published var isRefreshing = false
    @Published var closingPRIDs: Set<Int> = []
    @Published var mergingPRIDs: Set<Int> = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published private(set) var currentUsername: String?
    @Published private(set) var availableDevelopers: [String] = []
    @Published var watchedDevelopers: Set<String> { didSet { persistDevelopers() } }
    @AppStorage("refreshInterval") var refreshInterval = 15
    @AppStorage("notifyOnReview") var notifyOnReview = true
    @AppStorage("notifyOnClose") var notifyOnClose = false
    @AppStorage("githubHost") var githubHost = ""
    @AppStorage("lookbackDays") var lookbackDays = 14

    private let client = GitHubClient()
    private var refreshTask: Task<Void, Never>?
    private var hasLoadedOnce = false
    private let localRepositoriesKey = "localRepositories"
    private let developersKey = "watchedDevelopers"

    init() {
        localRepositories = (try? JSONDecoder().decode([LocalRepositoryTarget].self, from: UserDefaults.standard.data(forKey: localRepositoriesKey) ?? Data())) ?? []
        watchedDevelopers = Set(UserDefaults.standard.stringArray(forKey: developersKey) ?? [])
        if githubHost.isEmpty { githubHost = GitHubCredentials.detectedHost() ?? "github.com" }
    }

    deinit { refreshTask?.cancel() }

    var openPRs: [PullRequest] { pullRequests.filter { $0.state == .open } }
    var closedPRs: [PullRequest] { pullRequests.filter { $0.state == .closed } }
    var pendingReviewPRs: [PullRequest] { openPRs.filter { $0.reviewStatus == .pending || $0.reviewStatus == .changesRequested } }
    var readyToMergePRs: [PullRequest] { openPRs.filter(\.hasPassedAllChecks) }
    var attentionCount: Int { Set(pendingReviewPRs.map(\.id)).count }
    var menuIcon: String { attentionCount == 0 ? "arrow.triangle.branch" : "arrow.triangle.branch.circle" }

    func start() async {
        await requestNotificationPermission()
        await refresh()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let minutes = max(5, self.refreshInterval)
                try? await Task.sleep(for: .seconds(minutes * 60))
                await self.refresh()
            }
        }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing || force else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            guard !localRepositories.isEmpty else {
                repositories = []
                pullRequests = []
                availableDevelopers = []
                lastUpdated = .now
                return
            }
            let primaryHost = localRepositories[0].host
            let user = try await client.currentUser(host: primaryHost)
            let fetchedRepos = try await withThrowingTaskGroup(of: Repository.self) { group in
                for target in localRepositories {
                    group.addTask { try await self.client.repository(fullName: target.fullName, host: target.host) }
                }
                var result: [Repository] = []
                for try await repository in group { result.append(repository) }
                return result
            }
            currentUsername = user.login
            if watchedDevelopers.isEmpty { watchedDevelopers = [user.login] }
            let sortedRepositories = fetchedRepos.sorted()
            repositories = sortedRepositories
            let createdSince = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: .now) ?? .distantPast
            let batches = try await withThrowingTaskGroup(of: PullRequestBatch.self) { group in
                for repo in sortedRepositories {
                    let host = self.localRepositories.first(where: { $0.fullName == repo.fullName })?.host ?? primaryHost
                    let developers = self.watchedDevelopers
                    group.addTask { try await self.client.pullRequests(for: repo, host: host, watching: developers, createdSince: createdSince) }
                }
                var all: [PullRequestBatch] = []
                for try await batch in group { all.append(batch) }
                return all
            }
            availableDevelopers = Array(batches.reduce(into: Set<String>()) { $0.formUnion($1.authors) }).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let sorted = batches.flatMap(\.pullRequests)
                .sorted { $0.updatedAt > $1.updatedAt }
            if hasLoadedOnce { await notifyAboutChanges(from: pullRequests, to: sorted) }
            pullRequests = sorted
            hasLoadedOnce = true
            lastUpdated = .now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ pullRequest: PullRequest) { NSWorkspace.shared.open(pullRequest.url) }

    func close(_ pullRequest: PullRequest) async {
        guard !closingPRIDs.contains(pullRequest.id) else { return }
        closingPRIDs.insert(pullRequest.id)
        defer { closingPRIDs.remove(pullRequest.id) }
        do {
            let host = localRepositories.first(where: { $0.fullName == pullRequest.repository.fullName })?.host ?? githubHost
            try await client.close(pullRequest, host: host)
            await refresh(force: true)
        } catch {
            errorMessage = "Couldn’t close #\(pullRequest.number): \(error.localizedDescription)"
        }
    }

    func merge(_ pullRequest: PullRequest) async {
        guard pullRequest.hasPassedAllChecks, !mergingPRIDs.contains(pullRequest.id) else { return }
        mergingPRIDs.insert(pullRequest.id)
        defer { mergingPRIDs.remove(pullRequest.id) }
        do {
            let host = localRepositories.first(where: { $0.fullName == pullRequest.repository.fullName })?.host ?? githubHost
            try await client.merge(pullRequest, host: host)
            await refresh(force: true)
        } catch {
            errorMessage = "Couldn’t merge #\(pullRequest.number): \(error.localizedDescription)"
        }
    }

    func chooseLocalRepository() {
        guard let folder = LocalRepositoryResolver.chooseFolder() else { return }
        do {
            let target = try LocalRepositoryResolver.target(for: folder)
            if !localRepositories.contains(target) { localRepositories.append(target) }
            githubHost = target.host
            Task { await refresh(force: true) }
        } catch { errorMessage = error.localizedDescription }
    }

    func removeLocalRepository(_ target: LocalRepositoryTarget) {
        localRepositories.removeAll { $0.id == target.id }
        Task { await refresh(force: true) }
    }

    func setWatching(_ developer: String, enabled: Bool) {
        if enabled { watchedDevelopers.insert(developer) }
        else if watchedDevelopers.count > 1 { watchedDevelopers.remove(developer) }
        Task { await refresh(force: true) }
    }

    func addDeveloper(_ username: String) {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        watchedDevelopers.insert(normalized)
        Task { await refresh(force: true) }
    }

    func removeAccount() {
        Keychain.delete()
        pullRequests = []
        repositories = []
        localRepositories = []
        lastUpdated = nil
        hasLoadedOnce = false
    }

    private func persistLocalRepositories() {
        UserDefaults.standard.set(try? JSONEncoder().encode(localRepositories), forKey: localRepositoriesKey)
    }
    private func persistDevelopers() { UserDefaults.standard.set(Array(watchedDevelopers), forKey: developersKey) }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    private func notifyAboutChanges(from old: [PullRequest], to new: [PullRequest]) async {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        for current in new {
            let previous = oldByID[current.id]
            let shouldNotify: Bool
            let message: String
            if notifyOnReview, (current.reviewStatus == .pending || current.reviewStatus == .changesRequested), previous?.reviewStatus != current.reviewStatus {
                shouldNotify = true; message = current.reviewStatus == .changesRequested ? "Changes were requested" : "Review needs attention"
            } else if notifyOnClose, current.state == .closed, previous?.state == .open {
                shouldNotify = true; message = current.isMerged ? "Pull request was merged" : "Pull request was closed"
            } else {
                shouldNotify = false; message = ""
            }
            if shouldNotify { await deliverNotification(for: current, message: message) }
        }
    }

    private func deliverNotification(for pullRequest: PullRequest, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = message
        content.subtitle = "\(pullRequest.repository.fullName) #\(pullRequest.number)"
        content.body = pullRequest.title
        content.sound = .default
        content.categoryIdentifier = "MERGEWATCH_CHANGE"
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(identifier: "pr-\(pullRequest.id)-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
