import AppKit
import SwiftUI

/// Notch outline: concave top corners that flow into the menu bar, convex bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var model: NotchModel

    private let expandSpring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    private let collapseSpring = Animation.spring(response: 0.32, dampingFraction: 0.9)

    private var mirrorOpen: Bool { model.isExpanded && model.mode == .mirror }
    private var appsOpen: Bool { model.isExpanded && model.mode == .apps }
    private var pomodoroOpen: Bool { model.isExpanded && model.mode == .pomodoro }
    private var notesOpen: Bool { model.isExpanded && model.mode == .notes }
    private var gaugesOpen: Bool { model.isExpanded && model.mode == .gauges }
    private var musicOpen: Bool { model.isExpanded && model.mode == .music }
    private var liveActivity: Bool { !model.isExpanded && model.hasLiveActivity }
    /// Modes where the notch itself grows into a panel (mirror only grows a stem).
    private var roomy: Bool { appsOpen || pomodoroOpen || notesOpen || gaugesOpen || musicOpen }
    private var topRadius: CGFloat { roomy ? 14 : 6 }
    private var bottomRadius: CGFloat { roomy ? 24 : 10 }

    private var shapeSize: CGSize {
        if appsOpen { return CGSize(width: model.appsWidth, height: model.appsHeight) }
        if pomodoroOpen { return CGSize(width: model.pomodoroSize.width, height: model.pomodoroHeight) }
        if notesOpen { return CGSize(width: model.noteSize.width, height: model.noteHeight) }
        if gaugesOpen { return CGSize(width: model.gaugesSize.width, height: model.gaugesHeight) }
        if musicOpen { return CGSize(width: model.musicSize.width, height: model.musicHeight) }
        if mirrorOpen { return CGSize(width: model.notchSize.width, height: model.notchSize.height + model.mirrorStem + 4) }
        return CGSize(width: model.collapsedWidth, height: model.notchSize.height)
    }

    private var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.6, anchor: .top))
                .animation(expandSpring.delay(0.05)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    var body: some View {
        let expanded = model.isExpanded
        let size = shapeSize

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(roomy ? 0.45 : 0), radius: 12, y: 6)

                if appsOpen {
                    content
                        .padding(.top, model.notchSize.height)
                        .transition(panelTransition)
                }
                if pomodoroOpen {
                    PomodoroPanel(pomodoro: model.pomodoro)
                        .frame(height: model.pomodoroSize.height)
                        .padding(.top, model.notchSize.height)
                        .transition(panelTransition)
                }
                if notesOpen {
                    QuickNotePanel(note: model.note)
                        .frame(height: model.noteSize.height)
                        .padding(.top, model.notchSize.height)
                        .transition(panelTransition)
                }
                if gaugesOpen {
                    SystemGaugesPanel(stats: model.stats)
                        .frame(height: model.gaugesSize.height)
                        .padding(.top, model.notchSize.height)
                        .transition(panelTransition)
                }
                if musicOpen {
                    NowPlayingPanel(now: model.nowPlaying)
                        .frame(height: model.musicSize.height)
                        .padding(.top, model.notchSize.height)
                        .transition(panelTransition)
                }
                if liveActivity {
                    liveActivityView
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: size.width + topRadius * 2, height: size.height)
            .contextMenu {
                Button("Quit Notch Switcher") { NSApp.terminate(nil) }
            }
            .zIndex(1)

            if mirrorOpen {
                mirror
                    .padding(.top, -4) // overlap the stem so the two read as one piece
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.15, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.3, anchor: .top).combined(with: .opacity)
                        )
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(expanded ? expandSpring : collapseSpring, value: expanded)
        .animation(expandSpring, value: model.mode)
        .animation(expandSpring, value: model.pomodoro.isActive)
        .animation(expandSpring, value: model.nowPlaying.isPlaying)
    }

    /// Either side of the hardware notch, like a Live Activity: the Pomodoro when one is on,
    /// else what Nightjar is playing.
    @ViewBuilder private var liveActivityView: some View {
        if model.pomodoro.isActive {
            pomodoroActivity
        } else {
            NowPlayingActivity(now: model.nowPlaying)
                .padding(.horizontal, topRadius + 12)
                .frame(height: model.notchSize.height)
        }
    }

    /// Ring on the left of the hardware notch, time on the right.
    private var pomodoroActivity: some View {
        let pomodoro = model.pomodoro
        return HStack {
            PomodoroRing(progress: pomodoro.progress, color: pomodoro.phase.color, lineWidth: 2.5)
                .frame(width: 14, height: 14)
                .opacity(pomodoro.isRunning ? 1 : 0.5)
            Spacer()
            Text(pomodoro.timeText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pomodoro.isRunning ? pomodoro.phase.color : .white.opacity(0.5))
        }
        .padding(.horizontal, topRadius + 12)
        .frame(height: model.notchSize.height)
    }

    private var mirror: some View {
        let inset: CGFloat = 6
        return ZStack {
            MirrorShape().fill(Color.black)
            Group {
                if model.cameraReady, let layer = model.camera.previewLayer {
                    CameraPreview(layer: layer)
                } else {
                    Color(white: 0.12)
                }
            }
            .clipShape(MirrorShape())
            .padding(inset)
            // Glass sheen across the top of the mirror.
            LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                .clipShape(MirrorShape())
                .padding(inset)
                .allowsHitTesting(false)
        }
        .frame(width: model.mirrorSize.width, height: model.mirrorSize.height)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        .contentShape(MirrorShape())
        .onTapGesture { model.closeMirror() }
    }

    private var content: some View {
        VStack(spacing: 2) {
            HStack(spacing: model.iconSpacing) {
                ForEach(Array(model.apps.enumerated()), id: \.element.processIdentifier) { index, app in
                    icon(for: app, scale: model.scale(at: index))
                }
                mirrorButton(scale: model.scale(at: model.apps.count))
                pomodoroButton(scale: model.scale(at: model.apps.count + 1))
                notesButton(scale: model.scale(at: model.apps.count + 2))
                gaugesButton(scale: model.scale(at: model.apps.count + 3))
                typoFixerButton(scale: model.scale(at: model.apps.count + 4))
                nightjarButton(scale: model.scale(at: model.apps.count + 5))
            }
            .frame(height: model.iconSize * model.maxScale)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.8), value: model.pointer)

            Text(model.hoveredLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(height: model.labelHeight)
        }
    }

    private func icon(for app: NSRunningApplication, scale: CGFloat) -> some View {
        let size = model.iconSize * scale
        return VStack(spacing: 3) {
            Image(nsImage: app.icon ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
            // Dock-style indicator for the app that currently has focus.
            Circle()
                .fill(.white.opacity(app.processIdentifier == model.frontmostPID ? 0.8 : 0))
                .frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.activate(app) }
    }

    private func mirrorButton(scale: CGFloat) -> some View {
        let size = model.iconSize * scale
        return VStack(spacing: 3) {
            MirrorShape()
                .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.5)], startPoint: .top, endPoint: .bottom))
                .overlay(MirrorShape().stroke(Color(white: 0.25), lineWidth: 2))
                .frame(width: size, height: size * 0.42)
                .frame(width: size, height: size)
            Color.clear.frame(width: 4, height: 4) // keeps baseline aligned with the app icons
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openMirror() }
    }

    private func pomodoroButton(scale: CGFloat) -> some View {
        let size = model.iconSize * scale
        let pomodoro = model.pomodoro
        return VStack(spacing: 3) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [Color(red: 1, green: 0.45, blue: 0.35), Color(red: 0.8, green: 0.2, blue: 0.15)],
                    startPoint: .top, endPoint: .bottom
                ))
                Image(systemName: "timer")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
                if pomodoro.isActive {
                    PomodoroRing(progress: pomodoro.progress, color: .white, lineWidth: 2)
                        .padding(2)
                }
            }
            .frame(width: size * 0.85, height: size * 0.85)
            .frame(width: size, height: size)
            Color.clear.frame(width: 4, height: 4) // keeps baseline aligned with the app icons
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openPomodoro() }
    }

    private func notesButton(scale: CGFloat) -> some View {
        let size = model.iconSize * scale
        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.2)
                    .fill(LinearGradient(
                        colors: [Color(red: 1, green: 0.88, blue: 0.4), Color(red: 0.95, green: 0.72, blue: 0.2)],
                        startPoint: .top, endPoint: .bottom
                    ))
                Image(systemName: "square.and.pencil")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .frame(width: size * 0.85, height: size * 0.85)
            .frame(width: size, height: size)
            Color.clear.frame(width: 4, height: 4) // keeps baseline aligned with the app icons
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openNotes() }
    }

    private func gaugesButton(scale: CGFloat) -> some View {
        let size = model.iconSize * scale
        return VStack(spacing: 3) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.35)], startPoint: .top, endPoint: .bottom))
                Circle().fill(Color(white: 0.08)).padding(size * 0.06)
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(.white.opacity(0.7), lineWidth: max(1, size * 0.05))
                    .rotationEffect(.degrees(135))
                    .padding(size * 0.18)
                GaugeNeedle(fraction: 0.65).fill(Color(red: 1, green: 0.3, blue: 0.2))
            }
            .frame(width: size * 0.85, height: size * 0.85)
            .frame(width: size, height: size)
            Color.clear.frame(width: 4, height: 4) // keeps baseline aligned with the app icons
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openGauges() }
    }

    private func typoFixerButton(scale: CGFloat) -> some View {
        let size = model.iconSize * scale
        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.2)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.45, green: 0.6, blue: 1), Color(red: 0.25, green: 0.35, blue: 0.85)],
                        startPoint: .top, endPoint: .bottom
                    ))
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size * 0.85, height: size * 0.85)
            .frame(width: size, height: size)
            Color.clear.frame(width: 4, height: 4) // keeps baseline aligned with the app icons
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openTypoFixer() }
    }
    /// Nightjar's own icon (a gradient note if it isn't installed), with a dot while it plays.
    private func nightjarButton(scale: CGFloat) -> some View {
        let size = model.iconSize * scale
        let now = model.nowPlaying
        return VStack(spacing: 3) {
            Group {
                if let icon = now.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: size * 0.2)
                            .fill(LinearGradient(colors: [now.accent, now.accent2], startPoint: .top, endPoint: .bottom))
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size * 0.85, height: size * 0.85)
                }
            }
            .frame(width: size, height: size)
            Circle()
                .fill(now.accent.opacity(now.isPlaying ? 0.9 : 0))
                .frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openMusic() }
    }
}
