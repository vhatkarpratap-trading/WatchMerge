import SwiftUI

struct PullRequestRow: View {
    let pullRequest: PullRequest
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: stateIcon)
                    .font(.title3)
                    .foregroundStyle(stateColor)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pullRequest.title).font(.headline).lineLimit(1)
                        if pullRequest.isDraft { StatusPill(title: "Draft", color: .secondary, icon: "pencil") }
                    }
                    HStack(spacing: 7) {
                        Text("#\(pullRequest.number)").monospacedDigit()
                        Text("opened by \(pullRequest.author)")
                        Text("·")
                        Text(pullRequest.updatedAt.formatted(.relative(presentation: .named)))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if pullRequest.state == .closed, let closedAt = pullRequest.closedAt {
                        Label(pullRequest.isMerged ? "Merged \(closedAt.formatted(.relative(presentation: .named)))" : "Closed \(closedAt.formatted(.relative(presentation: .named)))", systemImage: pullRequest.isMerged ? "arrow.triangle.merge" : "xmark.circle")
                            .font(.caption).foregroundStyle(pullRequest.isMerged ? .purple : .secondary)
                    }
                    HStack(spacing: 6) {
                        if pullRequest.state == .open {
                            StatusPill(title: "Open", color: .primary, icon: "arrow.up.right")
                            StatusPill(title: reviewTitle, color: reviewColor, icon: reviewIcon)
                        }
                        if pullRequest.hasPassedAllChecks { StatusPill(title: "Ready to merge", color: .green, icon: "checkmark.seal") }
                        if pullRequest.state == .open { PipelineStatusPill(pullRequest: pullRequest) }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 6)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pull request \(pullRequest.number), \(pullRequest.title), \(accessibilityStatus)")
    }

    private var stateIcon: String { pullRequest.state == .open ? "arrow.up.right.circle.fill" : (pullRequest.isMerged ? "arrow.triangle.merge" : "checkmark.circle.fill") }
    private var stateColor: Color { pullRequest.state == .open ? .green : (pullRequest.isMerged ? .purple : .secondary) }
    private var reviewTitle: String {
        switch pullRequest.reviewStatus {
        case .approved: "Approved"; case .changesRequested: "Changes requested"; case .pending: "Review pending"; case .commented: "Commented"; case .dismissed: "Review dismissed"; case .none: "No review"
        }
    }
    private var reviewIcon: String {
        switch pullRequest.reviewStatus { case .approved: "checkmark"; case .changesRequested: "exclamationmark"; case .pending: "clock"; case .commented: "text.bubble"; case .dismissed: "arrow.uturn.backward"; case .none: "person" }
    }
    private var reviewColor: Color {
        switch pullRequest.reviewStatus { case .approved: .green; case .changesRequested: .red; case .pending: .yellow; case .commented, .dismissed, .none: .secondary }
    }
    private var accessibilityStatus: String { pullRequest.hasPassedAllChecks ? "\(reviewTitle). All reported checks passed; ready to merge." : reviewTitle }
}

struct StatusPill: View {
    let title: String; let color: Color; let icon: String
    var body: some View {
        Label(title, systemImage: icon).font(.caption2.weight(.medium)).foregroundStyle(.primary).padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.20), in: Capsule())
    }
}

struct PipelineStatusPill: View {
    let pullRequest: PullRequest
    var compact = false

    private var status: PipelineStatus { pullRequest.pipelineStatus }
    private var title: String {
        switch status {
        case .notReported: "NO PIPELINE REPORTED"
        case let .running(completed, total): "PIPELINE RUNNING \(completed)/\(total)"
        case .failed: "PIPELINE FAILED"
        case .passed: "PIPELINE PASSED"
        case .completed: "PIPELINE COMPLETED"
        }
    }
    private var icon: String {
        switch status {
        case .notReported: "questionmark.circle"
        case .running: "arrow.triangle.2.circlepath"
        case .failed: "xmark.octagon"
        case .passed: "checkmark.circle"
        case .completed: "checkmark.circle"
        }
    }
    private var tint: Color {
        switch status {
        case .notReported: .gray
        case .running: .yellow
        case .failed: .red
        case .passed: .green
        case .completed: .blue
        }
    }
    private var accessibilityText: String {
        switch status {
        case let .running(completed, total): "Pipeline running. \(completed) of \(total) checks completed."
        default: title.replacingOccurrences(of: "PIPELINE ", with: "Pipeline ").capitalized
        }
    }

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            Label(title, systemImage: icon)
            if case let .running(completed, total) = status {
                ProgressView(value: Double(completed), total: Double(total))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(width: compact ? 72 : 104)
                    .accessibilityLabel("\(completed) of \(total) pipeline checks completed")
            }
        }
        .font(.system(size: compact ? 9 : 10, weight: .bold, design: compact ? .monospaced : .default))
        .foregroundStyle(.primary)
        .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 3 : 4)
        .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: compact ? 4 : 7, style: .continuous))
        .accessibilityLabel(accessibilityText)
    }
}

struct PullRequestDetail: View {
    @Environment(\.dismiss) private var dismiss
    let pullRequest: PullRequest

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(pullRequest.number)").font(.subheadline).foregroundStyle(.secondary)
                    Text(pullRequest.title).font(.title2.bold()).lineLimit(2)
                }
                Spacer()
                Link(destination: pullRequest.url) { Label("GitHub", systemImage: "arrow.up.right.square") }
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Close detail")
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 8) {
                        StateBadge(pullRequest: pullRequest)
                        if pullRequest.isDraft { StatusPill(title: "Draft", color: .secondary, icon: "pencil") }
                    }
                    DetailGrid(pullRequest: pullRequest)
                    DetailSection(title: "Review") {
                        if pullRequest.requestedReviewers.isEmpty && pullRequest.reviews.isEmpty { Text("No reviewers requested").foregroundStyle(.secondary) }
                        else {
                            if !pullRequest.requestedReviewers.isEmpty { DetailLine(label: "Requested", value: pullRequest.requestedReviewers.joined(separator: ", ")) }
                            ForEach(Array(pullRequest.reviews.reversed())) { review in
                                HStack { Image(systemName: reviewSymbol(review.state)).foregroundStyle(reviewColor(review.state)); Text(review.user.login); Spacer(); Text(reviewText(review.state)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if pullRequest.state == .open {
                        DetailSection(title: "Pipeline") {
                            PipelineStatusPill(pullRequest: pullRequest)
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private func reviewText(_ state: ReviewStatus) -> String { state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
    private func reviewSymbol(_ state: ReviewStatus) -> String {
        switch state { case .approved: "checkmark.circle.fill"; case .changesRequested: "exclamationmark.circle.fill"; case .pending: "clock.fill"; case .commented: "text.bubble.fill"; case .dismissed: "arrow.uturn.backward.circle.fill"; case .none: "person.circle" }
    }
    private func reviewColor(_ state: ReviewStatus) -> Color {
        switch state { case .approved: .green; case .changesRequested: .red; case .pending: .orange; case .commented, .dismissed, .none: .secondary }
    }
}

private struct StateBadge: View {
    let pullRequest: PullRequest
    var body: some View {
        StatusPill(title: pullRequest.state == .open ? "Open" : (pullRequest.isMerged ? "Merged" : "Closed"), color: pullRequest.state == .open ? .green : (pullRequest.isMerged ? .purple : .secondary), icon: pullRequest.state == .open ? "arrow.up.right" : "checkmark")
    }
}

private struct DetailGrid: View {
    let pullRequest: PullRequest
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
            GridRow { DetailLine(label: "Repository", value: pullRequest.repository.fullName); DetailLine(label: "Author", value: pullRequest.author) }
            GridRow { DetailLine(label: "From", value: pullRequest.headRef); DetailLine(label: "Into", value: pullRequest.baseRef) }
            GridRow { DetailLine(label: "Created", value: pullRequest.createdAt.formatted(date: .abbreviated, time: .shortened)); DetailLine(label: pullRequest.closedAt == nil ? "Updated" : "Closed", value: (pullRequest.closedAt ?? pullRequest.updatedAt).formatted(date: .abbreviated, time: .shortened)) }
        }
    }
}

private struct DetailLine: View {
    let label: String; let value: String
    var body: some View { VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
}

private struct DetailSection<Content: View>: View {
    let title: String; @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); VStack(alignment: .leading, spacing: 9, content: { content }).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous)) } }
}
