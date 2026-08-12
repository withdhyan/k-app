import AVFoundation
import SwiftUI

extension Notification.Name {
    static let bioCameraCaptureHolding = Notification.Name("KBioCameraCaptureHolding")
}

enum CameraPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }
}

enum CameraSessionDirective: Equatable {
    case start
    case stop
}

struct CameraPermissionClient {
    var currentStatus: () -> CameraPermissionState
    var requestAccess: () async -> CameraPermissionState

    static let live = CameraPermissionClient(
        currentStatus: {
            CameraPermissionState(AVCaptureDevice.authorizationStatus(for: .video))
        },
        requestAccess: {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted ? .authorized : .denied)
                }
            }
        }
    )
}

@MainActor
final class CameraBackgroundModel: ObservableObject {
    @Published private(set) var permission: CameraPermissionState
    @Published private(set) var isVisible = false
    @Published private(set) var prePermissionLineVisible = false

    private let permissions: CameraPermissionClient
    private var didRequestPermission = false

    init(permissions: CameraPermissionClient = .live) {
        self.permissions = permissions
        permission = permissions.currentStatus()
    }

    var fallbackBackgroundVisible: Bool {
        permission != .authorized
    }

    var settingsNote: String? {
        switch permission {
        case .denied, .restricted:
            return KCopy.cameraDenied
        case .notDetermined, .authorized:
            return nil
        }
    }

    func appBecameActive(promptAllowed: Bool = false) async -> CameraSessionDirective {
        isVisible = true
        if promptAllowed {
            await requestPermissionIfNeeded()
        }
        return sessionDirective
    }

    func appBecameInactive() -> CameraSessionDirective {
        isVisible = false
        return .stop
    }

    func tabAppeared(promptAllowed: Bool = true) async -> CameraSessionDirective {
        await appBecameActive(promptAllowed: promptAllowed)
    }

    func tabDisappeared() -> CameraSessionDirective {
        appBecameInactive()
    }

    func reduceTransparencyChanged(_ enabled: Bool) -> CameraSessionDirective {
        guard enabled else { return sessionDirective }
        prePermissionLineVisible = false
        return .stop
    }

    private var sessionDirective: CameraSessionDirective {
        isVisible && permission == .authorized ? .start : .stop
    }

    private func requestPermissionIfNeeded() async {
        guard permission == .notDetermined, !didRequestPermission else { return }
        didRequestPermission = true
        prePermissionLineVisible = true
        do {
            try await Task.sleep(nanoseconds: 700_000_000)
        } catch {
            prePermissionLineVisible = false
            return
        }
        permission = await permissions.requestAccess()
        prePermissionLineVisible = false
    }
}

final class CameraSessionController: ObservableObject {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "holon.kedar.camera-background")
    private var configured = false

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            guard !self.session.inputs.isEmpty, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }

        guard session.inputs.isEmpty else { return }
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        guard
            let device,
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        // Preview-only: attach a camera input so AVCaptureVideoPreviewLayer can draw.
        // No capture outputs are added, so frames are never recorded, stored, or sent.
        session.addInput(input)
    }
}

struct CameraBackground: View {
    let cameraPromptAllowed: Bool
    let showsGlobalEnvironment: Bool

    @Binding private var stageRevealRequested: Bool

    init(
        cameraPromptAllowed: Bool = false,
        stageRevealRequested: Binding<Bool> = .constant(false),
        showsGlobalEnvironment: Bool = true
    ) {
        self.cameraPromptAllowed = cameraPromptAllowed
        self.showsGlobalEnvironment = showsGlobalEnvironment
        _stageRevealRequested = stageRevealRequested
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = CameraBackgroundModel()
    @StateObject private var sessionController = CameraSessionController()
    @State private var isCaptureHolding = false

    var body: some View {
        ZStack {
            KStyle.nearBlack
            if showsGlobalEnvironment {
                if !reduceTransparency && !model.fallbackBackgroundVisible {
                    CameraPreviewLayerView(session: sessionController.session)
                        .modifier(CameraPreviewFadeIn())
                        .transition(.opacity)
                    // The ONE environment haze — blur + dark tint over the camera
                    // itself. Content floats directly on this; surfaces must never
                    // add their own backdrops (founder: "remove the black
                    // container", not multiply it).
                    if case .haze(let material, let tintOpacity) =
                        KStyle.hazeResolution(reduceTransparency: reduceTransparency) {
                        Rectangle()
                            .fill(Color.black.opacity(tintOpacity))
                            .background(material.material)
                            .transition(.opacity)
                    }
                }

            } else if !reduceTransparency,
                      stageRevealRequested,
                      model.permission == .authorized,
                      model.isVisible {
                CameraPreviewLayerView(session: sessionController.session)
                    .opacity(isCaptureHolding ? KStyle.bioCameraStageRevealOpacity : KStyle.bioCameraStageOpacity)
                    .modifier(CameraPreviewFadeIn())
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if showsGlobalEnvironment {
                if !reduceTransparency && model.prePermissionLineVisible {
                    cameraNote(KCopy.cameraPrePermission)
                } else if !reduceTransparency, let settingsNote = model.settingsNote {
                    cameraNote(settingsNote)
                }
            }
        }
        .kAnimated(value: model.fallbackBackgroundVisible)
        .kAnimated(value: model.isVisible)
        .ignoresSafeArea()
        .onAppear {
            Task {
                await updateSession(for: scenePhase)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            Task {
                await updateSession(for: phase)
            }
        }
        .onChange(of: cameraPromptAllowed) { _, _ in
            Task {
                await updateSession(for: scenePhase)
            }
        }
        .onChange(of: stageRevealRequested) { _, _ in
            Task {
                await updateSession(for: scenePhase)
            }
        }
        .onChange(of: reduceTransparency) { _, enabled in
            apply(model.reduceTransparencyChanged(enabled))
            if !enabled {
                Task {
                    await updateSession(for: scenePhase)
                }
            }
        }
        .onDisappear {
            apply(model.appBecameInactive())
        }
        .kAnimated(value: model.prePermissionLineVisible)
        .kAnimated(value: model.permission)
        .animation(KStyle.cameraFadeMotion(reduceMotion), value: isCaptureHolding)
        .onReceive(NotificationCenter.default.publisher(for: .bioCameraCaptureHolding)) { note in
            isCaptureHolding = (note.object as? Bool) ?? false
        }
    }

    // Consent/permission note: content scrolls over the background layer, so the
    // text carries its own thin scrim to stay legible wherever it lands.
    private func cameraNote(_ text: String) -> some View {
        Text(text)
            .kFont(.monoCaption)
            .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                KStyle.nearBlack.opacity(KStyle.backgroundOpacity),
                in: RoundedRectangle(cornerRadius: KStyle.cornerRadius)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .transition(.opacity)
    }

    private func updateSession(for phase: ScenePhase) async {
        guard !reduceTransparency else {
            apply(model.reduceTransparencyChanged(true))
            return
        }
        if phase == .active, showsGlobalEnvironment || stageRevealRequested {
            apply(await model.appBecameActive(promptAllowed: cameraPromptAllowed))
        } else {
            apply(model.appBecameInactive())
        }
    }

    private func apply(_ directive: CameraSessionDirective) {
        switch directive {
        case .start:
            sessionController.start()
        case .stop:
            sessionController.stop()
        }
    }
}

private struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: CameraPreviewUIView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// Masks the capture-session warmup: the preview ramps in over a beat instead of
// popping from black on the first view. Later tab switches keep the session warm,
// so launch and switch now read the same.
private struct CameraPreviewFadeIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(KStyle.cameraFadeMotion(reduceMotion)) {
                    appeared = true
                }
            }
            .onDisappear {
                appeared = false
            }
    }
}
