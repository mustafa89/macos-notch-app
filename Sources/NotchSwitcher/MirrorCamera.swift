import AVFoundation
import SwiftUI

/// Front camera feed for the mirror. Runs only while the mirror is open.
final class MirrorCamera: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "notchswitcher.mirror")
    /// Created once in `configure()`; making a preview layer mutates the session, so it must
    /// never happen while `startRunning()` is in flight on the camera queue.
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    /// Calls back on the main queue.
    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Adds the camera input and preview layer once. Call on the main queue after access is granted.
    func configure() -> Bool {
        if previewLayer != nil { return true }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }
        session.addInput(input)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        // Flip the image the way a real mirror does.
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        previewLayer = layer
        return true
    }

    func run() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
}

struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Rear-view mirror outline: slightly narrower top edge, bowed bottom edge, rounded ends.
struct MirrorShape: Shape {
    func path(in rect: CGRect) -> Path {
        let taper = rect.width * 0.04
        let bow = rect.height * 0.12
        let topLeft = CGPoint(x: rect.minX + taper, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - taper, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY - bow)
        let bottomMid = CGPoint(x: rect.midX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY - bow)
        let endRadius = rect.height * 0.4

        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: endRadius)
        p.addArc(tangent1End: bottomRight, tangent2End: bottomMid, radius: endRadius)
        p.addArc(tangent1End: bottomMid, tangent2End: bottomLeft, radius: rect.width)
        p.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: endRadius)
        p.addArc(tangent1End: topLeft, tangent2End: topRight, radius: endRadius)
        p.closeSubpath()
        return p
    }
}
