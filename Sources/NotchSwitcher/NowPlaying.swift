import AppKit
import Combine
import SwiftUI

/// Nightjar's now-playing status, received over UDP on localhost (port 47811), with transport
/// commands sent back (port 47812). Track and state change rarely and drive the notch; levels
/// and position change 30 times a second and live in their own object, so only the bars and the
/// progress line redraw.
@MainActor
final class NowPlaying: ObservableObject {
    static let bundleID = "dev.mustafa.nightjar"
    static let statusPort: UInt16 = 47811
    static let commandPort: UInt16 = 47812
    /// No status for this long means Nightjar quit.
    static let timeout: TimeInterval = 3

    enum State: String { case playing, paused, stopped }

    /// Fast-changing values: spectrum bands (0...1) and position.
    final class Levels: ObservableObject {
        @Published var bands: [CGFloat] = Array(repeating: 0, count: 20)
        @Published var position: Double = 0
        @Published var duration: Double = 0
    }

    @Published private(set) var connected = false
    @Published private(set) var state: State = .stopped
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var accent = Color(red: 0.16, green: 0.83, blue: 1)
    @Published private(set) var accent2 = Color(red: 0.69, green: 0.42, blue: 1)
    @Published private(set) var bars: [Color] = [Color(red: 1, green: 0.31, blue: 0.85), Color(red: 0.16, green: 0.42, blue: 1)]
    let levels = Levels()

    var isPlaying: Bool { connected && state == .playing }

    private var socket: Int32 = -1
    private var source: DispatchSourceRead?
    private var lastPacket = Date.distantPast
    private var timer: Timer?
    private var accentHex = ""
    /// The bars redraw at most 15 times a second; Nightjar sends 30.
    private var barsAt = Date.distantPast

    private struct Packet: Decodable {
        let state: String
        let title: String
        let artist: String
        let pos: Double
        let dur: Double
        let bands: [Double]
        let accent: String
        let accent2: String
        let bars: [String]
    }

    init() {
        listen()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Commands

    func toggle() { send("toggle") }
    func next() { send("next") }
    func previous() { send("prev") }

    /// Launches Nightjar, or brings it to the front when it is running.
    func openNightjar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    var appIcon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func send(_ command: String) {
        guard socket >= 0 else { return }
        var addr = Self.loopback(port: Self.commandPort)
        let bytes = Array(command.utf8)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(socket, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    // MARK: Socket

    private static func loopback(port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return addr
    }

    /// Binds 127.0.0.1 only: nothing off this Mac can reach the port.
    private func listen() {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        var addr = Self.loopback(port: Self.statusPort)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            close(fd)
            return
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        socket = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// Reads every waiting packet and applies only the newest.
    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var latest: Data?
        while true {
            let n = recv(socket, &buffer, buffer.count, 0)
            if n <= 0 { break }
            latest = Data(buffer[0..<n])
        }
        guard let latest, let packet = try? JSONDecoder().decode(Packet.self, from: latest) else { return }
        apply(packet)
    }

    private func apply(_ p: Packet) {
        lastPacket = Date()
        // Assign only on change: every assignment redraws the notch.
        if !connected { connected = true }
        let newState = State(rawValue: p.state) ?? .stopped
        if newState != state { state = newState }
        if p.title != title { title = p.title }
        if p.artist != artist { artist = p.artist }
        if p.accent != accentHex {
            accentHex = p.accent
            accent = Color(hex: p.accent) ?? accent
            accent2 = Color(hex: p.accent2) ?? accent2
            bars = p.bars.compactMap { Color(hex: $0) }
        }
        if Date().timeIntervalSince(barsAt) >= 1.0 / 15.0 {
            barsAt = Date()
            levels.bands = p.bands.map { CGFloat($0) }
            levels.position = p.pos
        }
        levels.duration = p.dur
    }

    private func expire() {
        guard connected, Date().timeIntervalSince(lastPacket) > Self.timeout else { return }
        connected = false
        state = .stopped
        levels.bands = levels.bands.map { _ in 0 }
    }
}

extension Color {
    /// `#rrggbb`.
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// Spectrum bars grown from the bottom, in the skin's bar gradient.
struct NowPlayingBars: View {
    @ObservedObject var levels: NowPlaying.Levels
    let colors: [Color]
    var count = 20
    var spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let width = (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let band = levels.bands.isEmpty ? 0 : levels.bands[i * levels.bands.count / count]
                    RoundedRectangle(cornerRadius: min(2, width / 2))
                        .fill(LinearGradient(colors: colors.isEmpty ? [.white] : colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: width, height: max(2, geo.size.height * band))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

/// Elapsed / total time over a thin progress line.
struct NowPlayingProgress: View {
    @ObservedObject var levels: NowPlaying.Levels
    let color: Color

    var body: some View {
        let fraction = levels.duration > 0 ? min(1, levels.position / levels.duration) : 0
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
            HStack {
                Text(Self.clock(levels.position))
                Spacer()
                Text(Self.clock(levels.duration))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct NowPlayingPanel: View {
    @ObservedObject var now: NowPlaying

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
                NowPlayingBars(levels: now.levels, colors: now.bars, count: 16, spacing: 2)
                    .padding(8)
            }
            .frame(width: 96, height: 72)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(now.connected ? now.accent : .white.opacity(0.5))
                    .lineLimit(1)
                NowPlayingProgress(levels: now.levels, color: now.accent)
                    .padding(.top, 6)
                    .opacity(now.connected && now.state != .stopped ? 1 : 0.3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if now.connected {
                    control("backward.fill", size: 28) { now.previous() }
                    control(now.state == .playing ? "pause.fill" : "play.fill", size: 34) { now.toggle() }
                    control("forward.fill", size: 28) { now.next() }
                }
                control("arrow.up.forward.app", size: 28) { now.openNightjar() }
                    .help(now.connected ? "Show Nightjar" : "Open Nightjar")
            }
        }
        .padding(.horizontal, 22)
    }

    private var headline: String {
        guard now.connected else { return "Nightjar isn't running" }
        return now.title.isEmpty ? "Nothing playing" : now.title
    }

    private var subline: String {
        guard now.connected else { return "Open it to play music here" }
        return now.artist.isEmpty ? now.state.rawValue.capitalized : now.artist
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

/// Collapsed-notch Live Activity: a note badge on the left, live bars on the right.
struct NowPlayingActivity: View {
    @ObservedObject var now: NowPlaying

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [now.accent, now.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                )
                .frame(width: 16, height: 16)
            Spacer()
            NowPlayingBars(levels: now.levels, colors: now.bars, count: 5, spacing: 2)
                .frame(width: 22, height: 14)
        }
    }
}
