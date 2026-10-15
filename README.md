



# MergeWatch

MergeWatch is a native SwiftUI macOS app for monitoring GitHub pull requests across repositories. It puts an attention indicator in the menu bar and organizes the main dashboard by repository.

## Included

- Repository sections: every selected repository gets a named section with its own PR stack.
- Local repository watch list: choose Git repository folders on your Mac under **Settings → Repositories**. MergeWatch reads each folder’s `origin` remote and queries only those repositories—it never lists your whole account.
- Developer watch list: after choosing repositories, select one or more active PR authors in **Settings → Developers**. Your own GitHub username is selected by default.
- Open PR watch list: only open pull requests are requested and shown, with draft, review-requested, changes-requested, approved, and pipeline status.
- Creation window: by default, only open PRs created in the last 14 days are shown; changing the window never uses a PR’s update date.
- CI visibility: GitHub check-run status, including running, successful, failed, and cancelled checks.
- GitHub detail surface: PR number, branches, author, timestamps, reviewers, checks, links, contextual GitHub launch, and copy-link action.
- Global filtering/search: open, review-needed, failed checks, closed, and text search across all monitored repositories.
- macOS integration: a persistent top-right menu-bar button, attention summary, manual refresh, notification permission, background polling, and actionable notifications that open the PR on GitHub.
- Security: the GitHub fine-grained token is saved in the macOS Keychain—not UserDefaults or the project files.

## Run locally

```sh
swift run MergeWatch

# Create a double-clickable native development bundle in dist/MergeWatch.app
zsh scripts/build-app.sh
```

The app first uses your existing `gh auth login` session or HTTPS Git credential helper (including the macOS Keychain). It detects the configured GitHub host, and supports GitHub Enterprise Server hosts through their `/api/v3` API. You can change the host in **Settings → Account**. A GitHub fine-grained personal access token is available only as an optional fallback. Grant fallback tokens read-only access to **Pull requests**, **Checks**, **Metadata**, and **Actions**. Then choose the repositories to monitor under **Settings → Repositories**.

> The GitHub REST API is deliberately used as the source of truth: the app opens the full GitHub PR experience for capabilities outside the compact desktop overview, such as comments, reviews, diffs, merges, labels, and project metadata.
