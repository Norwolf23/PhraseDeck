import AppKit
import Combine
import UserNotifications

/// Work/break cycle timer. Tracks a target end Date rather than counting ticks,
/// so the clock stays correct across sleep/wake.
final class Pomodoro: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Pomodoro()

    enum Phase { case idle, work, rest }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining = 0
    @Published private(set) var paused = false

    private var endDate: Date?
    private var timer: Timer?

    var isRunning: Bool { phase != .idle }
    var clock: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }

    // MARK: - Controls

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        begin(.work)
    }

    func togglePause() {
        guard isRunning else { return }
        if paused {
            paused = false
            endDate = Date().addingTimeInterval(TimeInterval(remaining))
        } else {
            paused = true
            remaining = max(Int((endDate?.timeIntervalSinceNow ?? 0).rounded()), 0)
            endDate = nil
        }
    }

    func skip() {
        guard isRunning else { return }
        advance()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        paused = false
        remaining = 0
        endDate = nil
    }

    // MARK: - Cycle

    private func begin(_ p: Phase) {
        phase = p
        paused = false
        remaining = (p == .work ? Store.shared.workMinutes : Store.shared.breakMinutes) * 60
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        if timer == nil {
            let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        guard !paused, let end = endDate else { return }
        remaining = max(Int(end.timeIntervalSinceNow.rounded()), 0)
        if remaining == 0 { advance() }
    }

    private func advance() {
        if phase == .work {
            begin(.rest)
            let open = Store.shared.openCardsOnBreak
            notify("Break time", "\(Store.shared.breakMinutes) min break." + (open ? " Here are 5 new cards." : ""))
            if open { WindowManager.shared.openBreakSession() }
        } else {
            begin(.work)
            notify("Back to work", "\(Store.shared.workMinutes) min of focus.")
        }
    }

    // MARK: - Notifications

    private func notify(_ title: String, _ body: String) {
        NSSound(named: "Glass")?.play() // audible even if notification permission was denied
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Show banners even while PhraseDeck is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
