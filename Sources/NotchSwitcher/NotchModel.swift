import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchModel: ObservableObject {
    enum Mode { case apps, mirror, pomodoro, notes, gauges, music }

    /// Buttons shown after the running apps, in row order.
    enum Tool: CaseIterable {
        case mirror, pomodoro, notes, gauges, typoFixer, nightjar

        var label: String {
            switch self {
            case .mirror: "Mirror"
            case .pomodoro: "Pomodoro"
            case .notes: "Quick Note"
            case .gauges: "System"
            case .typoFixer: "Typo Fixer"
            case .nightjar: "Nightjar"
            }
        }
    }

    @Published private(set) var isExpanded = false
    @Published private(set) var mode: Mode = .apps {
        // A tool panel opened from the app row is often narrower than the row, leaving the
        // pointer outside it; the row's area keeps it open until the pointer reaches the panel.
        didSet { graceRect = oldValue == .apps && mode != .apps ? appsHitRect : nil }
    }
    private var graceRect: CGRect?
    @Published private(set) var cameraReady = false
    @Published private(set) var apps: [NSRunningApplication] = []
    @Published private(set) var frontmostPID: pid_t?
    @Published var pointer: CGPoint = .zero

    // Layout constants (points).
    let iconSize: CGFloat = 36
    let iconSpacing: CGFloat = 10
    let maxScale: CGFloat = 1.6
    let horizontalPadding: CGFloat = 18
    let labelHeight: CGFloat = 18
    var slot: CGFloat { iconSize + iconSpacing }
    /// Distance over which a neighbour icon still magnifies.
    var magnifyRange: CGFloat { slot * 2.5 }
    /// Running apps plus the tool buttons at the end of the row.
    var itemCount: Int { apps.count + Tool.allCases.count }

    let mirrorSize = CGSize(width: 380, height: 120)
    let mirrorStem: CGFloat = 10
    let camera = MirrorCamera()

    let pomodoro = Pomodoro()
    let pomodoroSize = CGSize(width: 370, height: 96)
    /// Extra width on each side of the collapsed notch while a Pomodoro is active.
    let liveActivityWidth: CGFloat = 46

    let note = QuickNote()
    let noteSize = CGSize(width: 420, height: 180)

    let stats = SystemStats()
    let gaugesSize = CGSize(width: 440, height: 112)

    let nowPlaying = NowPlaying()
    let musicSize = CGSize(width: 480, height: 104)
    private var cancellables = Set<AnyCancellable>()

    private(set) var notchSize = CGSize(width: 190, height: 32)
    private(set) var screenFrame: CGRect = .zero

    init() {
        refreshApps()
        // Redraw the notch when the timer ticks (once a second while running).
        pomodoro.objectWillChange
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.objectWillChange.send() } }
            .store(in: &cancellables)
        // Track and state only; the 30-per-second levels redraw just the bars that observe them.
        nowPlaying.objectWillChange
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.objectWillChange.send() } }
            .store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshApps() }
            }
        }
    }

    func configure(for screen: NSScreen) {
        screenFrame = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: top)
        } else {
            // No hardware notch: draw a notch-sized pill under the menu bar edge.
            notchSize = CGSize(width: 190, height: max(NSStatusBar.system.thickness, 24))
        }
    }

    // MARK: Geometry

    var expandedContentHeight: CGFloat { iconSize * maxScale + labelHeight + 14 }
    var appsHeight: CGFloat { notchSize.height + expandedContentHeight }
    var mirrorHeight: CGFloat { notchSize.height + mirrorStem + mirrorSize.height }
    var pomodoroHeight: CGFloat { notchSize.height + pomodoroSize.height }
    var noteHeight: CGFloat { notchSize.height + noteSize.height }
    var gaugesHeight: CGFloat { notchSize.height + gaugesSize.height }
    var musicHeight: CGFloat { notchSize.height + musicSize.height }
    var expandedHeight: CGFloat {
        switch mode {
        case .apps: appsHeight
        case .mirror: mirrorHeight
        case .pomodoro: pomodoroHeight
        case .notes: noteHeight
        case .gauges: gaugesHeight
        case .music: musicHeight
        }
    }
    /// Panel is taller than the shapes so the spring overshoot and shadow are not clipped.
    var panelHeight: CGFloat { max(appsHeight, mirrorHeight, pomodoroHeight, noteHeight, gaugesHeight, musicHeight) + 30 }

    var collapsedWidth: CGFloat {
        notchSize.width + (hasLiveActivity ? liveActivityWidth * 2 : 0)
    }

    /// A Pomodoro or Nightjar playing widens the collapsed notch; the Pomodoro wins when both are.
    var hasLiveActivity: Bool {
        pomodoro.isActive || nowPlaying.isPlaying
    }

    var appsWidth: CGFloat {
        let row = CGFloat(itemCount) * slot - iconSpacing + iconSize * (maxScale - 1) * 2
        return max(notchSize.width + 80, row + horizontalPadding * 2)
    }
    var expandedWidth: CGFloat {
        switch mode {
        case .apps: appsWidth
        case .mirror: mirrorSize.width
        case .pomodoro: pomodoroSize.width
        case .notes: noteSize.width
        case .gauges: gaugesSize.width
        case .music: musicSize.width
        }
    }

    var notchHitRect: CGRect {
        CGRect(
            x: screenFrame.midX - collapsedWidth / 2, y: screenFrame.maxY - notchSize.height,
            width: collapsedWidth, height: notchSize.height
        ).insetBy(dx: -4, dy: -2)
    }

    var expandedHitRect: CGRect { hitRect(width: expandedWidth, height: expandedHeight) }
    private var appsHitRect: CGRect { hitRect(width: appsWidth, height: appsHeight) }

    private func hitRect(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
            .insetBy(dx: -6, dy: -8)
    }

    /// Whether the open panel stays open with the pointer at `point`: on the panel, or on the app
    /// row it was opened from until the pointer first reaches the panel.
    func keepsOpen(at point: CGPoint) -> Bool {
        if expandedHitRect.contains(point) {
            graceRect = nil
            return true
        }
        return graceRect?.contains(point) ?? false
    }

    /// Dock-style magnification, measured against unmagnified icon centres so the row does not jitter.
    func scale(at index: Int) -> CGFloat {
        guard isExpanded, mode == .apps, expandedHitRect.contains(pointer) else { return 1 }
        let center = screenFrame.midX + (CGFloat(index) - CGFloat(itemCount - 1) / 2) * slot
        let t = max(0, 1 - abs(pointer.x - center) / magnifyRange)
        // Cosine falloff gives the smooth Dock curve instead of a linear peak.
        return 1 + (maxScale - 1) * (1 - cos(t * .pi)) / 2
    }

    var hoveredIndex: Int? {
        guard isExpanded, mode == .apps, expandedHitRect.contains(pointer) else { return nil }
        let offset = (pointer.x - screenFrame.midX) / slot + CGFloat(itemCount - 1) / 2
        let index = Int(offset.rounded())
        return (0..<itemCount).contains(index) ? index : nil
    }

    var hoveredLabel: String {
        guard let index = hoveredIndex else { return " " }
        return index < apps.count ? apps[index].localizedName ?? "" : Tool.allCases[index - apps.count].label
    }

    // MARK: State

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if expanded {
            refreshApps()
        } else {
            closeMirror()
            stats.stop()
            mode = .apps
        }
        isExpanded = expanded
    }

    func openPomodoro() { mode = .pomodoro }
    func openMusic() { mode = .music }
    func openNotes() { mode = .notes }

    func openGauges() {
        stats.start()
        mode = .gauges
    }

    /// Opens Typo Fixer's settings window. A running Typo Fixer gets a reopen event and shows
    /// settings; one that is not running is launched with --settings.
    func openTypoFixer() {
        setExpanded(false)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "local.typofixer") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.arguments = ["--settings"]
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    func openMirror() {
        mode = .mirror
        camera.requestAccess { [weak self] granted in
            MainActor.assumeIsolated {
                // The mirror may have closed while the permission prompt was up.
                guard let self, self.mode == .mirror, granted, self.camera.configure() else { return }
                self.cameraReady = true
                self.camera.run()
            }
        }
    }

    func closeMirror() {
        guard mode == .mirror else { return }
        mode = .apps
        cameraReady = false
        camera.stop()
    }

    func refreshApps() {
        let own = ProcessInfo.processInfo.processIdentifier
        apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isTerminated
        }
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func activate(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateAllWindows])
        setExpanded(false)
        // macOS may refuse activation requests from a background app; fall back to
        // LaunchServices, which behaves like a Dock click (no relaunch for a running app).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard NSWorkspace.shared.frontmostApplication != app, let url = app.bundleURL else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    /// Sample geometry and state for the README renders (tools/render): a notch of the usual
    /// size on a 1512-point-wide screen, `apps` in the row, the pointer at `hover` (an item
    /// index) for the magnification.
    func preview(mode: Mode, expanded: Bool, apps: [NSRunningApplication], hover: Int?) {
        screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        notchSize = CGSize(width: 190, height: 32)
        self.apps = apps
        self.mode = mode
        isExpanded = expanded
        if let hover {
            let x = screenFrame.midX + (CGFloat(hover) - CGFloat(itemCount - 1) / 2) * slot
            pointer = CGPoint(x: x, y: screenFrame.maxY - notchSize.height - 20)
        }
    }
}