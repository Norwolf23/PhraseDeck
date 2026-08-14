import SwiftUI
import ServiceManagement

@main
struct PhraseDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var pomo = Pomodoro.shared

    var body: some Scene {
        MenuBarExtra {
            Button("Review 5 Now") { WindowManager.shared.openSession() }
            Button("Open PhraseDeck") { WindowManager.shared.openHome() }
            Button("Sync from Notes…") { WindowManager.shared.startSync() }
            Divider()
            if pomo.isRunning {
                Text(pomo.phase == .work ? "Working — \(pomo.clock)" : "Break — \(pomo.clock)")
                Button(pomo.paused ? "Resume" : "Pause") { pomo.togglePause() }
                Button(pomo.phase == .work ? "Skip to Break" : "Skip to Work") { pomo.skip() }
                Button("Stop Pomodoro") { pomo.stop() }
            } else {
                Button("Start Pomodoro") { pomo.start() }
            }
            Toggle("Launch at Login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enable in
                    do {
                        if enable { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSLog("PhraseDeck: launch-at-login change failed: \(error)")
                    }
                }
            ))
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            if pomo.isRunning {
                Text((pomo.paused ? "⏸ " : "") + pomo.clock)
                    .monospacedDigit()
            } else {
                Image(systemName: "rectangle.on.rectangle.angled")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in WindowManager.shared.triggerSession() }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { _ in WindowManager.shared.triggerSession() }
        WindowManager.shared.openSession(auto: true)
    }

    /// Dock icon click reopens the home window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.openHome()
        return true
    }
}

final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var sessionWindow: NSWindow?
    private var pilesWindow: NSWindow?
    private var pickerWindow: NSWindow?
    private var lastSessionOpened: Date?

    // MARK: - Session

    /// Wake/unlock path: debounced so wake + unlock don't double-fire.
    func triggerSession() {
        if let last = lastSessionOpened, Date().timeIntervalSince(last) < 60 { return }
        openSession(auto: true)
    }

    func openSession(auto: Bool = false) {
        if let w = sessionWindow { front(w); return }
        guard !Store.shared.cards.isEmpty else {
            alert("No cards yet", "Use “Sync from Notes…” in the menu bar to import your phrase lists.")
            return
        }
        presentSession(SessionLauncherView(auto: auto, onDone: { [weak self] in
            self?.sessionWindow?.close()
        }))
    }

    /// Pomodoro break: skip the language prompt, go straight to 5 new-first cards.
    func openBreakSession() {
        if let w = sessionWindow { front(w); return }
        let cards = Store.shared.pickBreakCards(count: 5)
        guard !cards.isEmpty else { return }
        presentSession(SessionView(cards: cards, onDone: { [weak self] in
            self?.sessionWindow?.close()
        }))
    }

    private func presentSession<V: View>(_ root: V) {
        lastSessionOpened = Date()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: root)
        panel.delegate = self
        panel.center()
        sessionWindow = panel
        front(panel)
    }

    // MARK: - Home

    func openHome() {
        if let w = pilesWindow { front(w); return }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.title = "PhraseDeck"
        win.contentView = NSHostingView(rootView: HomeView(onSync: { [weak self] in self?.startSync() }))
        win.delegate = self
        win.center()
        pilesWindow = win
        front(win)
    }

    // MARK: - Sync

    func startSync() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let folders = try NotesImport.listFolders()
                DispatchQueue.main.async { self.showFolderPicker(folders) }
            } catch {
                DispatchQueue.main.async { self.syncError(error) }
            }
        }
    }

    private func showFolderPicker(_ folders: [String]) {
        guard !folders.isEmpty else {
            alert("No Notes folders found", "Create a folder per language in Apple Notes, then sync again.")
            return
        }
        pickerWindow?.close()
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.title = "Sync from Notes"
        win.contentView = NSHostingView(rootView: FolderPickerView(allFolders: folders, onConfirm: { [weak self] selection in
            self?.finishSync(folders: selection)
        }))
        win.delegate = self
        win.center()
        pickerWindow = win
        front(win)
    }

    private func finishSync(folders: [String]) {
        Store.shared.setDeckFolders(folders)
        pickerWindow?.close()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cards = try NotesImport.fetchCards(folders: folders)
                DispatchQueue.main.async {
                    Store.shared.merge(imported: cards)
                    self.alert("Sync complete",
                               "Imported \(cards.count) card\(cards.count == 1 ? "" : "s") from \(folders.count) folder\(folders.count == 1 ? "" : "s").")
                }
            } catch {
                DispatchQueue.main.async { self.syncError(error) }
            }
        }
    }

    private func syncError(_ error: Error) {
        alert("Couldn’t read Apple Notes",
              "\(error.localizedDescription)\n\nIf access was denied, enable PhraseDeck under System Settings → Privacy & Security → Automation → PhraseDeck → Notes.")
    }

    // MARK: - Helpers

    private func front(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === sessionWindow { sessionWindow = nil }
        if w === pilesWindow { pilesWindow = nil }
        if w === pickerWindow { pickerWindow = nil }
    }
}
