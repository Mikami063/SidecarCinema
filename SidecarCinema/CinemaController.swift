import AVFoundation
import AppKit
import CoreImage
import CoreVideo
import Combine

@MainActor
final class CinemaController: ObservableObject {
    @Published private(set) var videoURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var leftImage: CGImage?
    @Published private(set) var rightImage: CGImage?
    @Published private(set) var dualScreenActive = false

    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var renderTimer: Timer?
    private var statusObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var leftWindow: NSWindow?
    private var rightWindow: NSWindow?
    private var keyMonitor: Any?
    private var leftCrop: DisplayCrop?
    private var rightCrop: DisplayCrop?

    func open(_ url: URL) {
        guard url.isFileURL else { return }
        stopAndClear()
        errorMessage = nil
        let asset = AVURLAsset(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        let nextItem = AVPlayerItem(asset: asset)
        nextItem.add(output)
        let nextPlayer = AVPlayer(playerItem: nextItem)
        nextPlayer.actionAtItemEnd = .pause
        item = nextItem
        videoOutput = output
        player = nextPlayer
        videoURL = url
        statusObserver = nextItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed { self.errorMessage = item.error?.localizedDescription ?? "The video could not be opened." }
                if item.status == .readyToPlay {
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    self.player?.play()
                    self.isPlaying = true
                }
            }
        }
        timeObserver = nextPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
        startRenderTimer()
    }

    func startDualScreen(leftID: UInt32, rightID: UInt32, gapMillimeters: Double) {
        guard leftID != rightID else { errorMessage = "Choose two different displays."; return }
        guard let left = DisplayChoice.connected().first(where: { $0.id == leftID }),
              let right = DisplayChoice.connected().first(where: { $0.id == rightID }),
              let leftScreen = left.nsScreen(), let rightScreen = right.nsScreen() else {
            errorMessage = "Both selected displays must be connected. Check the Sidecar connection and try again."
            return
        }
        exitDualScreen()
        let crops = DisplayCrop.pair(left: left, right: right, gapMillimeters: gapMillimeters)
        leftCrop = crops.0
        rightCrop = crops.1
        leftWindow = makeVideoWindow(screen: leftScreen, side: .left)
        rightWindow = makeVideoWindow(screen: rightScreen, side: .right)
        dualScreenActive = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.dualScreenActive else { return event }
            switch event.keyCode {
            case 53: self.exitDualScreen(); return nil // Escape
            case 49: self.togglePlayback(); return nil // Space
            case 123: self.seek(by: -10); return nil // Left
            case 124: self.seek(by: 10); return nil // Right
            default: return event
            }
        }
        renderCurrentFrame()
        player?.play()
        isPlaying = true
    }

    func exitDualScreen() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        leftWindow?.orderOut(nil)
        rightWindow?.orderOut(nil)
        leftWindow = nil
        rightWindow = nil
        leftCrop = nil
        rightCrop = nil
        dualScreenActive = false
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(by seconds: Double) {
        guard let player else { return }
        let target = max(0, min(duration, currentTime + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private enum Side { case left, right }

    private func makeVideoWindow(screen: NSScreen, side: Side) -> NSWindow {
        let window = CinemaWindow(contentRect: screen.frame, screen: screen)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = VideoFrameView()
        view.image = side == .left ? leftImage : rightImage
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func startRenderTimer() {
        renderTimer?.invalidate()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderCurrentFrame() }
        }
        if let renderTimer { RunLoop.main.add(renderTimer, forMode: .common) }
    }

    private func renderCurrentFrame() {
        guard let output = videoOutput else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return }
        guard let leftCrop, let rightCrop else { return }
        // Fit the complete video into one virtual canvas. Any unused canvas area
        // remains black, so no part of the source frame is cut off.
        let canvasHeight = extent.height
        let canvasWidth = canvasHeight * max(0.1, leftCrop.canvasAspect)
        let canvasRect = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        let scale = min(canvasWidth / extent.width, canvasHeight / extent.height)
        let fittedWidth = extent.width * scale
        let fittedHeight = extent.height * scale
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                          tx: (canvasWidth - fittedWidth) / 2 - extent.minX * scale,
                                          ty: (canvasHeight - fittedHeight) / 2 - extent.minY * scale)
        let fittedVideo = image.transformed(by: transform).cropped(to: canvasRect)
        let blackCanvas = CIImage(color: CIColor.black).cropped(to: canvasRect)
        let canvas = fittedVideo.composited(over: blackCanvas)

        let leftRect = CGRect(x: canvasRect.minX + canvasWidth * leftCrop.normalizedX,
                              y: canvasRect.minY + canvasHeight * leftCrop.normalizedY,
                              width: canvasWidth * leftCrop.normalizedWidth,
                              height: canvasHeight * leftCrop.normalizedHeight)
        let rightRect = CGRect(x: canvasRect.minX + canvasWidth * rightCrop.normalizedX,
                               y: canvasRect.minY + canvasHeight * rightCrop.normalizedY,
                               width: canvasWidth * rightCrop.normalizedWidth,
                               height: canvasHeight * rightCrop.normalizedHeight)
        if let cgLeft = imageContext.createCGImage(canvas.cropped(to: leftRect), from: leftRect),
           let cgRight = imageContext.createCGImage(canvas.cropped(to: rightRect), from: rightRect) {
            leftImage = cgLeft
            rightImage = cgRight
            (leftWindow?.contentView as? VideoFrameView)?.image = cgLeft
            (rightWindow?.contentView as? VideoFrameView)?.image = cgRight
        }
    }

    private func stopAndClear() {
        exitDualScreen()
        renderTimer?.invalidate()
        renderTimer = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player = nil
        item = nil
        videoOutput = nil
        leftImage = nil
        rightImage = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }
}

final class VideoFrameView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
    }
}

final class CinemaWindow: NSWindow {
    init(contentRect: NSRect, screen: NSScreen) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(contentRect, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
