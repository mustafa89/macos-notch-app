import AppKit
import SwiftUI

/// Classic Pomodoro: 25 min focus, 5 min break, 15 min break after every 4th focus session.
@MainActor
final class Pomodoro: ObservableObject {
    enum Phase {
        case focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Short break"
            case .longBreak: "Long break"
            }
        }

        var duration: TimeInterval {
            switch self {
            case .focus: 25 * 60
            case .shortBreak: 5 * 60
            case .longBreak: 15 * 60
            }
        }

        var color: Color { self == .focus ? Color(red: 1, green: 0.38, blue: 0.3) : Color(red: 0.35, green: 0.85, blue: 0.55) }
    }

    static let sessionsPerCycle = 4

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: TimeInterval = Phase.focus.duration
    @Published private(set) var isRunning = false
    @Published private(set) var completedFocus = 0

    private var endDate: Date?
    private var timer: Timer?

    var progress: Double { 1 - remaining / phase.duration }
    /// Running, or paused part-way through a phase.
    var isActive: Bool { isRunning || remaining < phase.duration }

    var timeText: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        tick()
        stopTimer()
    }

    func reset() {
        stopTimer()
        remaining = phase.duration
    }

    func skip() { advance(notify: false) }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining == 0 { advance(notify: true) }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        isRunning = false
    }

    /// Moves to the next phase and waits for the user to start it.
    private func advance(notify: Bool) {
        stopTimer()
        if phase == .focus {
            completedFocus += 1
            phase = completedFocus % Self.sessionsPerCycle == 0 ? .longBreak : .shortBreak
        } else {
            if phase == .longBreak { completedFocus = 0 }
            phase = .focus
        }
        remaining = phase.duration
        if notify { NSSound(named: "Glass")?.play() }
    }

    /// Sample state for the README renders (tools/render): no timer runs.
    func preview(remaining: TimeInterval, running: Bool, completed: Int) {
        phase = .focus
        self.remaining = remaining
        isRunning = running
        completedFocus = completed
    }
}

/// Progress ring used in the panel, the row button and the collapsed notch.
struct PomodoroRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct PomodoroPanel: View {
    @ObservedObject var pomodoro: Pomodoro

    var body: some View {
        HStack(spacing: 16) {
            NineTailFox(
                progress: pomodoro.progress,
                resting: pomodoro.phase != .focus,
                isRunning: pomodoro.isRunning
            )
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 2) {
                Text(pomodoro.phase.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(pomodoro.timeText)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: pomodoro.timeText)
                HStack(spacing: 5) {
                    ForEach(0..<Pomodoro.sessionsPerCycle, id: \.self) { index in
                        Circle()
                            .fill(index < pomodoro.completedFocus % Pomodoro.sessionsPerCycle
                                ? Pomodoro.Phase.focus.color : .white.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                control(pomodoro.isRunning ? "pause.fill" : "play.fill", size: 34) { pomodoro.toggle() }
                control("arrow.counterclockwise", size: 28) { pomodoro.reset() }
                control("forward.end.fill", size: 28) { pomodoro.skip() }
            }
        }
        .padding(.horizontal, 22)
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}