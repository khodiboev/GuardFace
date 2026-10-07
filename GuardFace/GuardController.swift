import AppKit
import AVFoundation
import Vision
import Combine

/// What happens when the screen is left unattended or someone is looking over your shoulder
enum GuardAction: String, CaseIterable, Identifiable {
    case blur, lock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blur: return "Blur the screen"
        case .lock: return "Lock the Mac"
        }
    }
}

/// How long the trigger must last before the screen reacts
enum ReactDelay: String, CaseIterable, Identifiable {
    case instant, short, relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instant: return "Right away"
        case .short: return "After 2 seconds"
        case .relaxed: return "After 5 seconds"
        }
    }

    var seconds: Double {
        switch self {
        case .instant: return 0.4   // a tiny delay avoids flicker from a dropped frame
        case .short: return 2
        case .relaxed: return 5
        }
    }
}

enum GuardState {
    case starting, watching, triggered, locked, paused, noCamera, noAccess
}

final class GuardController: NSObject, ObservableObject {

    // MARK: - UI state (main thread)

    @Published private(set) var state: GuardState = .starting
    @Published private(set) var isCovered = false   // the blur curtain is up

    @Published var isEnabled: Bool = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            isEnabled ? start() : stop()
        }
    }

    @Published var action: GuardAction = GuardAction(rawValue: UserDefaults.standard.string(forKey: Keys.action) ?? "") ?? .blur {
        didSet { UserDefaults.standard.set(action.rawValue, forKey: Keys.action) }
    }

    @Published var delay: ReactDelay = ReactDelay(rawValue: UserDefaults.standard.string(forKey: Keys.delay) ?? "") ?? .short {
        didSet {
            UserDefaults.standard.set(delay.rawValue, forKey: Keys.delay)
            let seconds = delay.seconds
            queue.async { self.reactAfter = seconds }
        }
    }

    var statusText: String {
        switch state {
        case .starting: return "Starting…"
        case .watching: return "Watching — you're in view"
        case .triggered: return reasonText
        case .locked: return "Locked"
        case .paused: return "Paused"
        case .noCamera: return "No camera found"
        case .noAccess: return "No camera access → System Settings › Privacy › Camera"
        }
    }

    private var reasonText = "Screen covered"

    private enum Keys {
        static let enabled = "enabled"
        static let action = "action"
        static let delay = "delay"
    }

    // MARK: - Camera (main thread)

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "guardface.video")
    private var cameraReady = false
    private let curtain = CurtainOverlay()

    // MARK: - Tracking state (only used on `queue`)

    private var reactAfter = ReactDelay.short.seconds
    private var badSince: Double?      // when the "unsafe" condition started
    private var lastFrame = 0.0
    private var covered = false
    private var reason = ""

    private let faceRequest: VNDetectFaceRectanglesRequest = {
        let r = VNDetectFaceRectanglesRequest()
        r.revision = VNDetectFaceRectanglesRequestRevision3
        return r
    }()

    // MARK: - Lifecycle

    override init() {
        super.init()
        reactAfter = delay.seconds

        // Turn the camera off while the Mac sleeps or is locked (privacy + battery)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(pause), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(resumeCamera), name: NSWorkspace.didWakeNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(pause), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(onUnlock), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)

        if isEnabled { start() } else { state = .paused }
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            if !cameraReady { setupCamera() }
            guard cameraReady else { state = .noCamera; return }
            runSession(true)
            state = .watching
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { self.start() }
            }
        default:
            state = .noAccess
        }
    }

    private func stop() {
        runSession(false)
        curtain.hide()
        isCovered = false
        queue.async { self.covered = false; self.badSince = nil }
        state = .paused
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        cameraReady = true
    }

    private func runSession(_ on: Bool) {
        guard cameraReady else { return }
        queue.async {
            if on && !self.session.isRunning { self.session.startRunning() }
            if !on && self.session.isRunning { self.session.stopRunning() }
        }
    }

    @objc private func pause() {
        runSession(false)
        curtain.hide()
        DispatchQueue.main.async { self.isCovered = false }
        queue.async { self.covered = false; self.badSince = nil }
    }

    @objc private func resumeCamera() {
        if isEnabled { runSession(true) }
    }

    /// After a real Mac lock is opened (with your password/Touch ID), start watching again
    @objc private func onUnlock() {
        if isEnabled {
            runSession(true)
            queue.async { self.badSince = nil; self.covered = false }
            DispatchQueue.main.async {
                self.isCovered = false
                self.state = .watching
            }
        }
    }

    // MARK: - Deciding what to do (queue)

    /// faceCount: how many faces the camera sees right now
    private func evaluate(faceCount: Int, now: Double) {
        // Unsafe in two cases: you've stepped away (0 faces), or someone else is also looking (2+)
        let unsafe: Bool
        let why: String
        if faceCount == 0 {
            unsafe = true; why = "You stepped away"
        } else if faceCount >= 2 {
            unsafe = true; why = "Someone is looking over your shoulder"
        } else {
            unsafe = false; why = ""
        }

        if unsafe {
            if badSince == nil { badSince = now }
            if let since = badSince, now - since >= reactAfter, !covered {
                covered = true
                reason = why
                trigger(reason: why)
            }
        } else {
            // You're back and alone → clear everything
            badSince = nil
            if covered {
                covered = false
                DispatchQueue.main.async {
                    self.curtain.hide()
                    self.isCovered = false
                    self.state = .watching
                }
            }
        }
    }

    private func trigger(reason: String) {
        let mode = action   // read the current choice once
        DispatchQueue.main.async {
            self.reasonText = reason
            switch mode {
            case .blur:
                self.isCovered = true
                self.state = .triggered
                self.curtain.show(message: reason)
            case .lock:
                self.state = .locked
                self.lockScreen()
                // After locking we don't keep a curtain; macOS shows its own lock screen
                self.queue.async { self.covered = false; self.badSince = nil }
            }
        }
    }

    /// Locks the Mac the same way the keyboard shortcut does, using a tiny built-in helper
    private func lockScreen() {
        // /System/Library/CoreServices/Menu Extras/User.menu can lock, but the supported way
        // is the SACLockScreenImmediate call in login.framework.
        let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
        if let handle, let sym = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockFn = @convention(c) () -> Int32
            let lock = unsafeBitCast(sym, to: LockFn.self)
            _ = lock()
            dlclose(handle)
        } else {
            // Fallback: ask the system to start the screensaver, which locks if a password is required
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "ScreenSaverEngine"]
            try? task.run()
        }
    }
}

// MARK: - Camera frames

extension GuardController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // A few frames per second is plenty for "is someone there?"
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.25 else { return }
        lastFrame = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([faceRequest])

        // Count only faces that are reasonably confident, to avoid false positives from posters etc.
        let faces = (faceRequest.results ?? []).filter { $0.confidence > 0.3 }.count
        evaluate(faceCount: faces, now: now)
    }
}
