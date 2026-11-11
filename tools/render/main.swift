import AppKit
import SwiftUI

// Renders README images of NotchSwitcher's panels with sample data: no window, no screen
// capture, no timers, no camera. `tools/render.sh` builds this with the app's sources.
// The Quick Note panel is left out (it reads and autosaves the real note file), and so is the
// mirror (the camera feed).

/// The notch under a mock menu bar on a desktop gradient.
struct Desk<Content: View>: View {
    let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.2, blue: 0.42), Color(red: 0.45, green: 0.25, blue: 0.5), Color(red: 0.92, green: 0.55, blue: 0.45)],
                startPoint: .top, endPoint: .bottom
            )
            Rectangle().fill(Color.black.opacity(0.28)).frame(height: 32)
            content
        }
    }
}

@MainActor
func render(_ model: NotchModel, width: CGFloat, height: CGFloat, to path: String) {
    let view = Desk(content: NotchView(model: model)).frame(width: width, height: height)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { fatalError("render failed: \(path)") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let dir = CommandLine.arguments.dropFirst().first ?? "docs"
    // Finder is always running; no other app of yours shows up in the row.
    let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
    let bands: [CGFloat] = (0..<20).map { (i: Int) -> CGFloat in
        let x = Double(i)
        let wave: Double = abs(sin(x * 0.55 + 0.8))
        let tilt: Double = 1 - x / 30
        return CGFloat(0.25 + 0.6 * wave * tilt)
    }

    let apps = NotchModel()
    apps.preview(mode: .apps, expanded: true, apps: finder, hover: finder.count + 5) // the Nightjar button
    render(apps, width: 760, height: apps.appsHeight + 40, to: "\(dir)/apps.png")

    let pomodoro = NotchModel()
    pomodoro.pomodoro.preview(remaining: Pomodoro.Phase.focus.duration * 0.45, running: true, completed: 2)
    pomodoro.preview(mode: .pomodoro, expanded: true, apps: [], hover: nil)
    render(pomodoro, width: 580, height: pomodoro.pomodoroHeight + 40, to: "\(dir)/pomodoro.png")

    let gauges = NotchModel()
    gauges.stats.preview(cpu: 0.42, memory: 0.63, disk: 0.71, download: 2_400_000, upload: 380_000)
    gauges.preview(mode: .gauges, expanded: true, apps: [], hover: nil)
    render(gauges, width: 560, height: gauges.gaugesHeight + 40, to: "\(dir)/gauges.png")

    let music = NotchModel()
    music.nowPlaying.preview(title: "Night Drive", artist: "The Lanterns", position: 72, duration: 247, bands: bands)
    music.preview(mode: .music, expanded: true, apps: [], hover: nil)
    render(music, width: 600, height: music.musicHeight + 40, to: "\(dir)/nightjar.png")

    let activity = NotchModel()
    activity.nowPlaying.preview(title: "Night Drive", artist: "The Lanterns", position: 72, duration: 247, bands: bands)
    activity.preview(mode: .apps, expanded: false, apps: [], hover: nil)
    render(activity, width: 420, height: 72, to: "\(dir)/live-activity.png")
}
