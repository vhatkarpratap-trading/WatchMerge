import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PullRequestStore
    @Environment(\.dismiss) private var dismiss
    // Never rehydrate a secret into a text field. Besides being safer, this
    // avoids macOS rendering stale password bullets after a token is removed.
    @State private var token = ""
    @State private var hasFallbackToken = !(Keychain.readToken() ?? "").isEmpty
    @State private var saveMessage: String?
    @State private var developerInput = ""

    var body: some View {
        TabView {
            Form {
                Section {
                    TextField("GitHub host", text: $store.githubHost, prompt: Text("github.company.com"))
                        .textFieldStyle(.roundedBorder)
                    Text("For GitHub Enterprise Server, enter only the host name (for example, github.company.com). The app automatically uses its /api/v3 endpoint.")
                        .font(.caption).foregroundStyle(.secondary)
                    switch GitHubCredentials.source(for: store.githubHost) {
                    case .githubCLI, .gitCredentialHelper:
                        Label("Using your existing \(GitHubCredentials.source(for: store.githubHost).rawValue) login", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("MergeWatch reads this credential only to make GitHub API requests. It does not copy or save it.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .mergeWatchKeychain:
                        Label("Using a MergeWatch Keychain fallback token", systemImage: "key.fill")
                            .foregroundStyle(.secondary)
                    case .unavailable:
                        Label("No system GitHub credential found", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Sign in once with gh auth login, use an HTTPS Git credential helper, or add a fallback token below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    SecureField(hasFallbackToken ? "Enter a token to replace the saved fallback" : "Enter a fallback GitHub token", text: $token)
                        .textFieldStyle(.roundedBorder)
                    Text("Optional fallback only. Create a fine-grained token with read access to Pull requests, Checks, and Metadata. It is stored in your macOS Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Save token") {
                            do {
                                try Keychain.save(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
                                token = ""
                                hasFallbackToken = true
                                saveMessage = "Fallback token saved securely. Refreshing repositories…"
                                Task { await store.refresh(force: true) }
                            }
                            catch { saveMessage = error.localizedDescription }
                        }.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if hasFallbackToken {
                            Button("Remove token", role: .destructive) {
                                Keychain.delete()
                                token = ""
                                hasFallbackToken = false
                                saveMessage = "Fallback token removed."
                            }
                        }
                        Spacer()
                        Link("Create token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                    }
                    if let saveMessage { Text(saveMessage).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("GitHub account") }
            }
            .formStyle(.grouped)
            .tabItem { Label("Account", systemImage: "person.crop.circle") }

            Form {
                Section("Refresh") {
                    Picker("Check GitHub every", selection: $store.refreshInterval) {
                        Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("30 minutes").tag(30); Text("60 minutes").tag(60)
                    }
                    Text("Manual refresh is always available from the toolbar and menu bar.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Pull request window") {
                    Picker("Show PRs created within", selection: $store.lookbackDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    Text("This uses when the pull request was created, not its most recent update.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Notify me when") {
                    Toggle("A review needs attention", isOn: $store.notifyOnReview)
                    Toggle("A pull request closes or merges", isOn: $store.notifyOnClose)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Notifications", systemImage: "bell.badge") }

            Form {
                Section {
                    Text("Choose local Git folders. MergeWatch reads each folder’s origin remote; it never scans or lists your account’s repositories.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Add local repository", action: store.chooseLocalRepository)
                    if store.localRepositories.isEmpty {
                        Text("No local repositories are being watched.").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.localRepositories) { target in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(target.fullName, systemImage: "folder.fill")
                                    Text(target.localPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) { store.removeLocalRepository(target) }
                            }
                        }
                    }
                } header: { Text("Local repositories to watch") } footer: { Text("Only these remotes are fetched and shown. Pull requests are grouped under their repository names on the dashboard.") }
            }
            .formStyle(.grouped)
            .tabItem { Label("Repositories", systemImage: "folder") }

            Form {
                Section {
                    Text("Watch any developer by their GitHub username. Your current account is included by default.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("GitHub username", text: $developerInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Watch") {
                            store.addDeveloper(developerInput)
                            developerInput = ""
                        }
                        .disabled(developerInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Divider()
                    Text("CURRENT WATCH LIST").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    ForEach(store.watchedDevelopers.sorted(), id: \.self) { developer in
                        HStack {
                            Text(developer)
                            if developer == store.currentUsername { Text("YOU").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Remove", role: .destructive) { store.setWatching(developer, enabled: false) }
                                .disabled(store.watchedDevelopers.count == 1)
                        }
                    }
                    if !store.availableDevelopers.isEmpty {
                        Divider()
                        Text("RECENT AUTHORS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                        ForEach(store.availableDevelopers, id: \.self) { developer in
                            Toggle(isOn: Binding(get: { store.watchedDevelopers.contains(developer) }, set: { enabled in
                                store.setWatching(developer, enabled: enabled)
                            })) {
                                HStack { Text(developer); if developer == store.currentUsername { Text("You").font(.caption).foregroundStyle(.secondary) } }
                            }
                            .disabled(store.watchedDevelopers.contains(developer) && store.watchedDevelopers.count == 1)
                        }
                    }
                } header: { Text("Developers to watch") } footer: { Text("The app shows PRs for everyone in the current watch list. Keep at least one developer selected.") }
            }
            .formStyle(.grouped)
            .tabItem { Label("Developers", systemImage: "person.2") }
        }
        .padding(.top, 8)
        .onChange(of: store.lookbackDays) { _, _ in Task { await store.refresh(force: true) } }
        .safeAreaInset(edge: .bottom) {
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(16).background(.bar)
        }
    }
}
