import AppKit
import Combine
import SwiftUI

/// Borderless panel that floats over the menu bar. It takes keyboard focus only while the
/// quick note is open, and as a non-activating panel it does so without activating this app.
final class NotchPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a non-key panel reach SwiftUI.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private let model = NotchModel()
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = FirstMouseHostingView(rootView: NotchView(model: model))

        layoutPanel()
        panel.orderFrontRegardless()

        // Mouse-moved monitors do not need Accessibility permission (only key events do).
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) {
            monitors.append(local)
        }

        // A click outside the open panel closes it (the note does not close on hover-out).
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.clicked() }
            return event
        }) {
            monitors.append(local)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? false } ? nil : event
        }) {
            monitors.append(keys)
        }

        model.$mode
            .sink { [weak self] mode in MainActor.assumeIsolated { self?.updateKeyFocus(for: mode) } }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutPanel() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.note.flush()
    }

    /// Pins a full-width strip to the top of the notched screen; the notch shape is drawn inside it.
    private func layoutPanel() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        model.configure(for: screen)
        let height = model.panelHeight
        let frame = screen.frame
        panel.setFrame(
            NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height),
            display: true
        )
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        if model.isExpanded {
            if model.mode != .notes, !model.keepsOpen(at: point) { model.setExpanded(false) }
        } else if model.notchHitRect.contains(point) {
            model.setExpanded(true)
        }
        // Publishing the pointer redraws the view, so only do it while the panel is open.
        if model.isExpanded { model.pointer = point }
        panel.ignoresMouseEvents = !model.isExpanded
    }

    private func clicked() {
        guard model.isExpanded, !model.expandedHitRect.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    private func collapse() {
        model.setExpanded(false)
        panel.ignoresMouseEvents = true
    }

    /// Returns true when the key event was handled and must not reach the text view again.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.isExpanded, model.mode == .notes else { return false }
        if event.keyCode == 53 { // Esc
            collapse()
            return true
        }
        // This app has no Edit menu, so route the standard shortcuts to the text view directly.
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        let shift = event.modifierFlags.contains(.shift)
        let action: Selector? = switch key {
        case "x": #selector(NSText.cut(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": shift ? Selector(("redo:")) : Selector(("undo:"))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: nil)
    }

    private func updateKeyFocus(for mode: NotchModel.Mode) {
        if mode == .notes {
            panel.allowsKey = true
            panel.makeKey()
        } else if panel.allowsKey {
            panel.allowsKey = false
            // Re-ordering drops key status so typing goes back to the app underneath.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }
}
