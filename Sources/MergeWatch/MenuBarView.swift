import SwiftUI

private enum QuickLookTab: String, CaseIterable, Identifiable {
    case open = "OPEN PR"
    case review = "REVIEW PENDING"
    case closed = "CLOSED PRS"
    var id: String { rawValue }
}

private enum PullRequestAction: String {
    case merge, close
}

private struct PullRequestConfirmation: Identifiable {
    let action: PullRequestAction
    let pullRequest: PullRequest
    var id: String { "\(action.rawValue)-\(pullRequest.id)" }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: PullRequestStore
    @Environment(\.openWindow) private var openWindow
    var onDisplayedCountChanged: ((Int) -> Void)? = nil
    @State private var confirmation: PullRequestConfirmation?
    @State private var selectedTab: QuickLookTab = .open

    private var displayedPullRequests: [PullRequest] {
        let pullRequests: [PullRequest]
        switch selectedTab {
        case .open: pullRequests = store.openPRs
        case .review: pullRequests = store.pendingReviewPRs
        case .closed: pullRequests = store.closedPRs
        }
        return pullRequests.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var groupedPullRequests: [(String, [PullRequest])] {
        Dictionary(grouping: displayedPullRequests, by: { $0.repository.name })
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PR / QUICK LOOK")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .tracking(0.35)
                    Text(summary.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(store.isRefreshing).accessibilityLabel("Refresh pull requests")
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            tabStrip
            if displayedPullRequests.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.green)
                    Text("NO \(selectedTab.rawValue)").font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("IN THE CREATION WINDOW").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 26)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedPullRequests, id: \.0) { repository, pullRequests in
                            Section {
                                ForEach(pullRequests) { pr in
                                    HStack(spacing: 2) {
                                        Button { store.open(pr) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: statusIcon(for: pr)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).frame(width: 16)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(pr.title)
                                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                    .lineLimit(3)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                HStack(spacing: 7) {
                                                    Text("#\(pr.number) / \(pr.createdAt.formatted(.relative(presentation: .named)).uppercased())")
                                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                    statusTextBadge(for: pr)
                                                }
                                                if pr.hasPassedAllChecks { readyToMergeBadge }
                                                if pr.state == .open { PipelineStatusPill(pullRequest: pr, compact: true) }
                                            }
                                            Spacer()
                                        }
                                        .padding(.leading, 16).padding(.vertical, 10).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                        if pr.state == .open {
                                            HStack(spacing: 6) {
                                                if pr.hasPassedAllChecks {
                                                    Button { confirmation = PullRequestConfirmation(action: .merge, pullRequest: pr) } label: {
                                                        if store.mergingPRIDs.contains(pr.id) { ProgressView().controlSize(.small) }
                                                        else { Text("MERGE").font(.system(size: 9, weight: .bold, design: .monospaced)) }
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .foregroundStyle(.primary).frame(minWidth: 50, minHeight: 28)
                                                    .background(Color.green.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                    .disabled(store.mergingPRIDs.contains(pr.id) || store.closingPRIDs.contains(pr.id))
                                                    .accessibilityLabel("Merge pull request \(pr.number)")
                                                }
                                                Button { confirmation = PullRequestConfirmation(action: .close, pullRequest: pr) } label: {
                                                    if store.closingPRIDs.contains(pr.id) { ProgressView().controlSize(.small) }
                                                    else { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                                }
                                                .buttonStyle(.borderless)
                                                .foregroundStyle(.secondary).frame(width: 28, height: 28)
                                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                .disabled(store.closingPRIDs.contains(pr.id) || store.mergingPRIDs.contains(pr.id))
                                                .accessibilityLabel("Close pull request \(pr.number)")
                                            }
                                            .padding(.trailing, 14)
                                        } else {
                                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).frame(width: 28, height: 28).padding(.trailing, 14)
                                        }
                                    }
                                }
                            } header: {
                                Text(repository.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .tracking(0.7).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
                            }
                        }
                    }
                }
                .frame(maxHeight: 700)
            }
            Divider().padding(.top, 8)
            HStack {
                Button("OPEN APP") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
                Spacer()
                Button("QUIT") { NSApp.terminate(nil) }
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .frame(width: 420)
        .onAppear { reportDisplayedCount() }
        .onChange(of: selectedTab) { _, _ in reportDisplayedCount() }
        .onChange(of: store.pullRequests) { _, _ in reportDisplayedCount() }
        .alert(confirmation?.action == .merge ? "Merge pull request?" : "Close pull request?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button(confirmation?.action == .merge ? "Merge PR" : "Close PR", role: confirmation?.action == .close ? .destructive : nil) {
                guard let confirmation else { return }
                Task {
                    switch confirmation.action {
                    case .merge: await store.merge(confirmation.pullRequest)
                    case .close: await store.close(confirmation.pullRequest)
                    }
                }
                self.confirmation = nil
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text(confirmation.map { confirmation in
                confirmation.action == .merge
                    ? "Merge #\(confirmation.pullRequest.number): \(confirmation.pullRequest.title)? GitHub will still enforce branch rules and required reviews."
                    : "Close #\(confirmation.pullRequest.number): \(confirmation.pullRequest.title)?"
            } ?? "")
        }
    }

    private var summary: String {
        if store.isRefreshing { return "Refreshing…" }
        return "\(store.openPRs.count) open · \(store.pendingReviewPRs.count) review · \(store.closedPRs.count) closed"
    }

    private func reportDisplayedCount() {
        onDisplayedCountChanged?(displayedPullRequests.count)
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            tabButton(.open, count: store.openPRs.count)
            tabButton(.review, count: store.pendingReviewPRs.count)
            tabButton(.closed, count: store.closedPRs.count)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.bar)
    }

    private func tabButton(_ tab: QuickLookTab, count: Int) -> some View {
        Button { selectedTab = tab } label: {
            Text("\(tab.rawValue) \(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 7)
                .background(selectedTab == tab ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(tab.rawValue.lowercased()), \(count) pull requests")
    }

    private func statusIcon(for pr: PullRequest) -> String {
        pr.state == .closed ? "checkmark.circle.fill" : (pr.reviewStatus == .changesRequested ? "exclamationmark.circle.fill" : (pr.reviewStatus == .pending ? "clock.fill" : "arrow.up.right.circle.fill"))
    }

    private func statusTextBadge(for pr: PullRequest) -> some View {
        Text(statusText(for: pr))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(statusBackground(for: pr).opacity(0.22), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel(statusText(for: pr))
    }

    private func statusText(for pr: PullRequest) -> String {
        if pr.state == .closed { return pr.isMerged ? "MERGED" : "CLOSED" }
        switch pr.reviewStatus {
        case .approved: return "REVIEW APPROVED"
        case .changesRequested: return "CHANGES REQUESTED"
        case .pending: return "REVIEW PENDING"
        case .commented: return "REVIEW COMMENTED"
        case .dismissed: return "REVIEW DISMISSED"
        case .none: return "OPEN"
        }
    }

    private func statusBackground(for pr: PullRequest) -> Color {
        if pr.state == .closed { return pr.isMerged ? .purple : .gray }
        switch pr.reviewStatus {
        case .approved: return .teal
        case .changesRequested: return .red
        case .pending: return .yellow
        case .commented: return .indigo
        case .dismissed: return .gray
        case .none: return .blue
        }
    }

    private var readyToMergeBadge: some View {
        Label("READY TO MERGE", systemImage: "checkmark")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.green.opacity(0.22), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel("All reported checks passed; ready to merge")
    }
}
