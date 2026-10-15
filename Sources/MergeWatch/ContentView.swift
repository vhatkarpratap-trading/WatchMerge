import SwiftUI

enum PRFilter: String, CaseIterable, Identifiable {
    case all = "All open", ready = "Ready to merge", review = "Review needed"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: PullRequestStore
    @State private var filter: PRFilter = .all
    @State private var search = ""
    @State private var selectedPR: PullRequest?
    @State private var showSettings = false
    @State private var showQuickLook = false

    private var visiblePRs: [PullRequest] {
        store.pullRequests.filter { pr in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = pr.state == .open
            case .ready: matchesFilter = pr.state == .open && pr.hasPassedAllChecks
            case .review: matchesFilter = pr.state == .open && (pr.reviewStatus == .pending || pr.reviewStatus == .changesRequested)
            }
            let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = term.isEmpty || pr.title.localizedCaseInsensitiveContains(term) || pr.repository.fullName.localizedCaseInsensitiveContains(term) || "#\(pr.number)".contains(term)
            return matchesFilter && matchesSearch
        }
    }

    private var groupedPRs: [(Repository, [PullRequest])] {
        Dictionary(grouping: visiblePRs, by: \.repository)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            dashboard
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search pull requests")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showQuickLook.toggle() } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .accessibilityLabel("Quick Look: show all open pull requests")
                .help("Quick Look: open pull requests")
                .popover(isPresented: $showQuickLook, arrowEdge: .top) {
                    MenuBarView()
                        .environmentObject(store)
                }

                Button { store.chooseLocalRepository() } label: {
                    Label("Add local repository", systemImage: "folder.badge.plus")
                }
                .accessibilityLabel("Add a local Git repository to watch")

                Button { Task { await store.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
                .accessibilityLabel("Refresh pull requests")

                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Open MergeWatch settings")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() .environmentObject(store).frame(width: 560, height: 500) }
        .alert("GitHub couldn’t refresh", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Open Settings") { showSettings = true }
            Button("OK", role: .cancel) { }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var sidebar: some View {
        List(selection: $filter) {
            Section("Pull requests") {
                ForEach(PRFilter.allCases) { item in
                    Label {
                        HStack { Text(item.rawValue); Spacer(); Text("\(count(for: item))").foregroundStyle(.secondary).monospacedDigit() }
                    } icon: { Image(systemName: icon(for: item)) }
                    .tag(item)
                }
            }
            Section("Repositories") {
                ForEach(store.localRepositories) { target in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(target.fullName, systemImage: "folder.fill").lineLimit(1)
                        Text(target.folderName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Button { store.chooseLocalRepository() } label: {
                    Label("Add local repository", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MergeWatch")
    }

    private var dashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                header
                if store.isRefreshing && store.pullRequests.isEmpty {
                    LoadingView()
                } else if store.localRepositories.isEmpty {
                    LocalRepositorySetup(addRepository: store.chooseLocalRepository)
                } else if groupedPRs.isEmpty {
                    EmptyState(showSettings: { showSettings = true })
                } else {
                    ForEach(groupedPRs, id: \.0.id) { repository, pullRequests in
                        Section {
                            VStack(spacing: 10) {
                                ForEach(pullRequests) { pullRequest in
                                    PullRequestRow(pullRequest: pullRequest) { selectedPR = pullRequest }
                                        .contextMenu {
                                            Button("Open on GitHub") { store.open(pullRequest) }
                                            Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string) }
                                        }
                                }
                            }
                            .padding(.horizontal, 24)
                        } header: {
                            RepositoryHeader(repository: repository, count: pullRequests.count)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedPR) { PullRequestDetail(pullRequest: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Pull request overview").font(.system(size: 28, weight: .bold))
                    Text(lastUpdatedText).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 12) {
                MetricCard(title: "Open", value: store.openPRs.count, symbol: "arrow.up.right.circle.fill", tint: .blue) { filter = .all }
                MetricCard(title: "Ready to merge", value: store.readyToMergePRs.count, symbol: "checkmark.seal.fill", tint: .green) { filter = .ready }
                MetricCard(title: "Review needed", value: store.pendingReviewPRs.count, symbol: "person.crop.circle.badge.exclamationmark", tint: .yellow) { filter = .review }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var lastUpdatedText: String {
        guard store.lastUpdated != nil else { return "Connect GitHub to see your pull requests" }
        return "\(store.watchedDevelopers.sorted().joined(separator: ", ")) · created in last \(store.lookbackDays)d · \(store.localRepositories.count) local repositories"
    }

    private func count(for item: PRFilter) -> Int {
        switch item {
        case .all: return store.pullRequests.count
        case .ready: return store.readyToMergePRs.count
        case .review: return store.pendingReviewPRs.count
        }
    }

    private func icon(for item: PRFilter) -> String {
        switch item { case .all: "tray.full"; case .ready: "checkmark.seal"; case .review: "person.crop.circle.badge.exclamationmark" }
    }
}

private struct MetricCard: View {
    let title: String; let value: Int; let symbol: String; let tint: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) { Text("\(value)").font(.title2.bold()).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(title). Filter results")
    }
}

private struct RepositoryHeader: View {
    let repository: Repository; let count: Int
    var body: some View {
        HStack {
            Image(systemName: repository.isPrivate ? "lock.fill" : "folder.fill").foregroundStyle(.secondary)
            Text(repository.fullName).font(.headline)
            Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule())
            Spacer()
            Link(destination: repository.htmlURL) { Image(systemName: "arrow.up.right.square") }.accessibilityLabel("Open \(repository.fullName) on GitHub")
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.bar)
    }
}

private struct LoadingView: View { var body: some View { VStack(spacing: 14) { ProgressView(); Text("Loading pull requests…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 100) } }

private struct EmptyState: View {
    let showSettings: () -> Void
    var body: some View {
        ContentUnavailableView { Label("No pull requests here", systemImage: "arrow.triangle.branch") } description: { Text("Select repositories in the sidebar or connect your GitHub account.") } actions: { Button("Open Settings", action: showSettings) }
            .frame(maxWidth: .infinity).padding(.vertical, 120)
    }
}

private struct LocalRepositorySetup: View {
    let addRepository: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Choose a local repository", systemImage: "folder.badge.plus")
        } description: {
            Text("Choose a Git repository folder from your Mac. MergeWatch reads its origin remote and watches only that repository’s pull requests.")
        } actions: {
            Button("Choose local repository", action: addRepository)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 120)
    }
}
