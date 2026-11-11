import Darwin
import SwiftUI

/// Samples CPU, memory, network and disk once a second, only while the gauges panel is open.
@MainActor
final class SystemStats: ObservableObject {
    @Published private(set) var cpu = 0.0          // 0...1
    @Published private(set) var memory = 0.0       // 0...1
    @Published private(set) var disk = 0.0         // 0...1
    @Published private(set) var download = 0.0     // bytes/s
    @Published private(set) var upload = 0.0       // bytes/s

    private var timer: Timer?
    private var lastCPU: (busy: UInt64, total: UInt64)?
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastCPU = nil
        lastNet = nil
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let last = lastCPU, ticks.total > last.total {
                cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastCPU = ticks
        }
        if let used = Self.memoryUsed() {
            memory = Double(used) / Double(ProcessInfo.processInfo.physicalMemory)
        }
        if let net = Self.networkBytes() {
            let now = Date()
            if let last = lastNet {
                let seconds = now.timeIntervalSince(last.at)
                // Interface counters are 32-bit and wrap; skip the sample when they do.
                download = net.rx >= last.rx ? Double(net.rx - last.rx) / seconds : download
                upload = net.tx >= last.tx ? Double(net.tx - last.tx) / seconds : upload
            }
            lastNet = (net.rx, net.tx, now)
        }
        if let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = values.volumeTotalCapacity, total > 0,
           let available = values.volumeAvailableCapacityForImportantUsage {
            disk = 1 - Double(available) / Double(total)
        }
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Same definition as Activity Monitor's "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(vm_kernel_page_size)
    }

    /// Total bytes received and sent on physical (en*) interfaces.
    private static func networkBytes() -> (rx: UInt64, tx: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var cursor = list
        while let entry = cursor?.pointee {
            if let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: entry.ifa_name).hasPrefix("en"),
               let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                rx += UInt64(data.ifi_ibytes)
                tx += UInt64(data.ifi_obytes)
            }
            cursor = entry.ifa_next
        }
        return (rx, tx)
    }

    /// Sample readings for the README renders (tools/render): nothing is sampled.
    func preview(cpu: Double, memory: Double, disk: Double, download: Double, upload: Double) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.download = download
        self.upload = upload
    }
}

/// Needle angle: 135° (bottom-left) sweeping 270° clockwise to 45° (bottom-right), like a car dial.
private func gaugeAngle(_ fraction: Double) -> Angle { .degrees(135 + 270 * fraction) }

private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
    CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
}

struct GaugeNeedle: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        // Small allowance past the end so the spring overshoot is visible at full scale.
        let angle = gaugeAngle(min(max(fraction, 0), 1.03))
        let side = Angle(radians: angle.radians + .pi / 2)
        let back = point(center, -r * 0.14, angle)
        var p = Path()
        p.move(to: point(back, r * 0.035, side))
        p.addLine(to: point(center, r * 0.78, angle))
        p.addLine(to: point(back, -r * 0.035, side))
        p.closeSubpath()
        return p
    }
}

struct CarGauge: View {
    let title: String
    let fraction: Double
    let readout: String
    let labels: [String]
    var redline = 0.8

    private static let needle = Color(red: 1, green: 0.3, blue: 0.2)

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                ctx.scaleBy(x: size.width / 100, y: size.height / 100)
                drawDial(&ctx)
            }
            GaugeNeedle(fraction: fraction)
                .fill(Self.needle)
                .shadow(color: Self.needle.opacity(0.8), radius: 3)
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                .frame(width: 9, height: 9)
            VStack(spacing: 0) {
                Text(readout)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(title)
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .offset(y: 27)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.6, dampingFraction: 0.55), value: fraction)
    }

    private func drawDial(_ ctx: inout GraphicsContext) {
        let center = CGPoint(x: 50, y: 50)
        // Chrome rim and dark face.
        ctx.fill(Path(ellipseIn: CGRect(x: 1, y: 1, width: 98, height: 98)), with: .linearGradient(
            Gradient(colors: [Color(white: 0.85), Color(white: 0.35), Color(white: 0.6)]),
            startPoint: CGPoint(x: 50, y: 0), endPoint: CGPoint(x: 50, y: 100)
        ))
        ctx.fill(Path(ellipseIn: CGRect(x: 5, y: 5, width: 90, height: 90)), with: .radialGradient(
            Gradient(colors: [Color(white: 0.16), Color(white: 0.03)]),
            center: center, startRadius: 0, endRadius: 45
        ))

        var red = Path()
        red.addArc(center: center, radius: 39, startAngle: gaugeAngle(redline), endAngle: gaugeAngle(1), clockwise: false)
        ctx.stroke(red, with: .color(Color(red: 0.9, green: 0.15, blue: 0.1)), lineWidth: 4)

        for step in 0...20 {
            let f = Double(step) / 20
            let major = step % 5 == 0
            var tick = Path()
            tick.move(to: point(center, major ? 34 : 37, gaugeAngle(f)))
            tick.addLine(to: point(center, 41, gaugeAngle(f)))
            let color: Color = f > redline ? Color(red: 1, green: 0.35, blue: 0.3) : .white
            ctx.stroke(tick, with: .color(color.opacity(major ? 0.95 : 0.6)), lineWidth: major ? 1.8 : 0.9)
        }

        for (index, label) in labels.enumerated() {
            let f = Double(index) / Double(max(labels.count - 1, 1))
            ctx.draw(
                Text(label).font(.system(size: 8, weight: .semibold)).foregroundColor(.white.opacity(0.8)),
                at: point(center, 26, gaugeAngle(f))
            )
        }
    }
}

struct SystemGaugesPanel: View {
    @ObservedObject var stats: SystemStats

    /// Full scale of the network dial.
    private static let networkMax = 40.0 * 1_000_000

    var body: some View {
        HStack(spacing: 10) {
            CarGauge(title: "CPU", fraction: stats.cpu, readout: percent(stats.cpu), labels: ["0", "25", "50", "75", "100"])
            CarGauge(title: "MEM", fraction: stats.memory, readout: percent(stats.memory), labels: ["0", "25", "50", "75", "100"])
            CarGauge(
                title: "NET ↑\(rate(stats.upload))",
                fraction: stats.download / Self.networkMax,
                readout: "↓" + rate(stats.download),
                labels: ["0", "10", "20", "30", "40"],
                redline: 0.9
            )
            CarGauge(title: "DISK", fraction: stats.disk, readout: percent(stats.disk), labels: ["0", "25", "50", "75", "100"], redline: 0.9)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    /// Compact rate in MB/s or KB/s.
    private func rate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond >= 1_000_000
            ? String(format: "%.1fM", bytesPerSecond / 1_000_000)
            : String(format: "%.0fK", bytesPerSecond / 1_000)
    }
}