import SwiftUI
import UserNotifications
import Combine

@main
struct MergeWatchApp: App {
    @StateObject private var store = PullRequestStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    appDelegate.store = store
                    await store.start()
                }
        }
        .defaultSize(width: 1240, height: 790)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh pull requests") { Task { await store.refresh(force: true) } }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 560, height: 500)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {
    weak var store: PullRequestStore? { didSet { installStatusItem() } }
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let quickLook = NSPopover()
    private var storeUpdates: AnyCancellable?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: "MERGEWATCH_CHANGE",
            actions: [UNNotificationAction(identifier: "OPEN_GITHUB", title: "Open on GitHub", options: .foreground)],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func installStatusItem() {
        guard let store, let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "eye.circle.fill", accessibilityDescription: "MergeWatch Quick Look")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(toggleQuickLook)
        button.toolTip = "MergeWatch Quick Look"
        quickLook.behavior = .transient
        quickLook.delegate = self
        quickLook.contentViewController = NSHostingController(rootView: MenuBarView(onDisplayedCountChanged: { [weak self] count in
            self?.resizeQuickLook(for: count)
        }).environmentObject(store))
        updateStatusItem()
        storeUpdates = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
    }

    private func updateStatusItem() {
        guard let store else { return }
        statusItem.button?.title = " PR \(store.openPRs.count)"
        statusItem.button?.setAccessibilityLabel("MergeWatch Quick Look: \(store.openPRs.count) open pull requests")
        resizeQuickLook(for: store.openPRs.count)
    }

    private func resizeQuickLook(for rowCount: Int) {
        // Resize for the active tab, not just the data refresh. A PR title may
        // span several lines, so reserve a generous per-row allowance.
        let desiredHeight = CGFloat(205 + (rowCount * 108))
        let visibleScreenHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 36
        let height = min(visibleScreenHeight, max(360, desiredHeight))
        quickLook.contentSize = NSSize(width: 420, height: height)
    }

    @objc private func toggleQuickLook() {
        guard let button = statusItem.button else { return }
        if quickLook.isShown {
            quickLook.performClose(nil)
        } else {
            quickLook.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installPopupDismissalMonitoring()
        }
    }

    // `.transient` handles standard dismissal. The monitors also cover clicks
    // in another app and ensure Quick Look never remains stranded onscreen.
    private func installPopupDismissalMonitoring() {
        removePopupDismissalMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dismissQuickLookIfNeeded(for: event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async { self?.quickLook.performClose(nil) }
        }
    }

    private func dismissQuickLookIfNeeded(for event: NSEvent) {
        guard quickLook.isShown else { return }
        let isPopoverClick = event.window == quickLook.contentViewController?.view.window
        let isStatusItemClick = event.window == statusItem.button?.window
        if !isPopoverClick && !isStatusItemClick { quickLook.performClose(nil) }
    }

    private func removePopupDismissalMonitoring() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    func popoverDidClose(_ notification: Notification) {
        removePopupDismissalMonitoring()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let url = response.notification.request.content.userInfo["url"] as? String else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            if action == "OPEN_GITHUB", let githubURL = URL(string: url) {
                NSWorkspace.shared.open(githubURL)
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

