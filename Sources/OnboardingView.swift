import SwiftUI
import UIKit

enum OnboardingPermissionKind: String, Equatable, Identifiable {
    case camera

    var id: String { rawValue }
}

enum OnboardingPermissionAction: String, Equatable {
    case allow
    case openSettings

    var label: String {
        switch self {
        case .allow:
            return "allow"
        case .openSettings:
            return "open settings"
        }
    }
}

struct OnboardingPermissionStates: Equatable {
    var camera: CameraPermissionState
}

struct OnboardingPermissionRow: Identifiable, Equatable {
    let kind: OnboardingPermissionKind
    let line: String
    let reason: String
    let isDone: Bool
    let action: OnboardingPermissionAction?

    var id: String { kind.rawValue }
}

struct OnboardingStep: Identifiable, Equatable {
    let id: String
    let line: String
    let reason: String
    let permissionRows: [OnboardingPermissionRow]
}

enum OnboardingChecklist {
    static let maxStepCount = 6
    static let activePermissionKinds: [OnboardingPermissionKind] = [.camera]

    static func steps(
        permissionStates: OnboardingPermissionStates,
        selectedTab: KAppTab,
        permissionKinds: [OnboardingPermissionKind] = activePermissionKinds
    ) -> [OnboardingStep] {
        Array([
            OnboardingStep(
                id: "plain-ink",
                line: "cadence starts on plain ink",
                reason: "no camera prompt appears here.",
                permissionRows: []
            ),
            OnboardingStep(
                id: "permissions",
                line: "permissions stay consent-first",
                reason: "each ask has a reason and can wait.",
                permissionRows: permissionRows(
                    permissionStates: permissionStates,
                    selectedTab: selectedTab,
                    permissionKinds: permissionKinds
                )
            ),
        ].prefix(maxStepCount))
    }

    static func permissionRows(
        permissionStates: OnboardingPermissionStates,
        selectedTab: KAppTab,
        permissionKinds: [OnboardingPermissionKind] = activePermissionKinds
    ) -> [OnboardingPermissionRow] {
        permissionKinds.map { kind in
            switch kind {
            case .camera:
                return cameraRow(cameraState: permissionStates.camera, selectedTab: selectedTab)
            }
        }
    }

    static func cameraAskGatingText(
        cameraState: CameraPermissionState,
        selectedTab: KAppTab
    ) -> String {
        switch cameraState {
        case .notDetermined:
            if cameraPromptAllowed(selectedTab: selectedTab) {
                return KCopy.cameraPrePermission
            }
            return "camera asks when build or mind opens; cadence stays plain ink."
        case .authorized:
            return "camera stage is ready across all tabs."
        case .denied, .restricted:
            return "camera is off; build and mind still work on ink."
        }
    }

    static func cameraPromptAllowed(selectedTab: KAppTab) -> Bool {
        selectedTab == .build || selectedTab == .mind
    }

    private static func cameraRow(
        cameraState: CameraPermissionState,
        selectedTab: KAppTab
    ) -> OnboardingPermissionRow {
        OnboardingPermissionRow(
            kind: .camera,
            line: "camera",
            reason: cameraAskGatingText(cameraState: cameraState, selectedTab: selectedTab),
            isDone: cameraState == .authorized,
            action: cameraAction(cameraState)
        )
    }

    private static func cameraAction(_ cameraState: CameraPermissionState) -> OnboardingPermissionAction? {
        switch cameraState {
        case .notDetermined:
            return .allow
        case .denied, .restricted:
            return .openSettings
        case .authorized:
            return nil
        }
    }
}

struct OnboardingSeenState: Equatable {
    var hasSeenFirstRun: Bool
}

enum OnboardingSeenEvent: Equatable {
    case overlayAppeared
    case laterTapped
    case completed
}

enum OnboardingSeenLogic {
    static let firstRunSeenKey = "k.onboarding.first_run.seen"

    static func shouldPresent(_ state: OnboardingSeenState) -> Bool {
        !state.hasSeenFirstRun
    }

    static func reduce(
        _ state: OnboardingSeenState,
        event: OnboardingSeenEvent
    ) -> OnboardingSeenState {
        switch event {
        case .overlayAppeared, .laterTapped, .completed:
            return OnboardingSeenState(hasSeenFirstRun: true)
        }
    }
}

struct OnboardingSeenStore {
    var load: () -> OnboardingSeenState
    var save: (OnboardingSeenState) -> Void

    static func userDefaults(_ defaults: UserDefaults = .standard) -> OnboardingSeenStore {
        OnboardingSeenStore(
            load: {
                OnboardingSeenState(
                    hasSeenFirstRun: defaults.bool(forKey: OnboardingSeenLogic.firstRunSeenKey)
                )
            },
            save: { state in
                defaults.set(state.hasSeenFirstRun, forKey: OnboardingSeenLogic.firstRunSeenKey)
            }
        )
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var isVisible: Bool
    @Published private(set) var permissionStates: OnboardingPermissionStates

    private let seenStore: OnboardingSeenStore
    private let cameraPermissions: CameraPermissionClient
    private var seenState: OnboardingSeenState

    init(
        seenStore: OnboardingSeenStore = .userDefaults(),
        cameraPermissions: CameraPermissionClient = .live
    ) {
        self.seenStore = seenStore
        self.cameraPermissions = CensusRemainderFixture.isOnboardingEnabled()
            ? CameraPermissionClient(
                currentStatus: { .notDetermined },
                requestAccess: { .denied }
            )
            : cameraPermissions
        seenState = seenStore.load()
        isVisible = CensusRemainderFixture.isOnboardingEnabled()
            || OnboardingSeenLogic.shouldPresent(seenState)
        permissionStates = OnboardingPermissionStates(camera: self.cameraPermissions.currentStatus())
    }

    func overlayAppeared() {
        apply(.overlayAppeared)
    }

    func dismiss(_ event: OnboardingSeenEvent) {
        apply(event)
        isVisible = false
    }

    func refreshPermissionStates() {
        permissionStates.camera = cameraPermissions.currentStatus()
    }

    private func apply(_ event: OnboardingSeenEvent) {
        seenState = OnboardingSeenLogic.reduce(seenState, event: event)
        seenStore.save(seenState)
    }
}

struct OnboardingView: View {
    let selectedTab: KAppTab
    let permissionStates: OnboardingPermissionStates
    let onLater: () -> Void
    let onCompleted: () -> Void
    let onCameraAllow: () -> Void
    let onOpenSettings: () -> Void

    @State private var stepIndex = 0

    init(
        selectedTab: KAppTab,
        permissionStates: OnboardingPermissionStates,
        onLater: @escaping () -> Void,
        onCompleted: @escaping () -> Void,
        onCameraAllow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = OnboardingSettingsOpener.open
    ) {
        self.selectedTab = selectedTab
        self.permissionStates = permissionStates
        self.onLater = onLater
        self.onCompleted = onCompleted
        self.onCameraAllow = onCameraAllow
        self.onOpenSettings = onOpenSettings
    }

    private var steps: [OnboardingStep] {
        OnboardingChecklist.steps(permissionStates: permissionStates, selectedTab: selectedTab)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                KStyle.nearBlack
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                    stepHeader

                    if !currentStep.permissionRows.isEmpty {
                        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                            ForEach(currentStep.permissionRows) { row in
                                permissionRow(row)
                            }
                        }
                        .padding(.top, KStyle.smallSpacing)
                    }

                    Spacer(minLength: KStyle.rowSpacing)

                    KActRow(
                        actions: navigationActions,
                        variant: .cadence,
                        onSelect: handleNavigationAction
                    )
                    .accessibilityIdentifier("k-onboarding-navigation")
                }
                .frame(width: KStyle.columnWidth(in: proxy.size.width), alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, KStyle.columnMargin)
                .padding(.top, proxy.safeAreaInsets.top + KStyle.minimumTapTarget)
                .padding(.bottom, proxy.safeAreaInsets.bottom + KStyle.minimumTapTarget)
            }
        }
        .transition(.opacity)
        .kAnimated(value: stepIndex)
        .kAnimated(value: permissionStates)
        .onChange(of: steps) { _, newSteps in
            if stepIndex >= newSteps.count {
                stepIndex = max(newSteps.count - 1, .zero)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("k-onboarding")
    }

    private var currentStep: OnboardingStep {
        steps[min(stepIndex, max(steps.count - 1, .zero))]
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            KMonoCaption("\(stepIndex + 1)/\(steps.count)", variant: .metadata)

            Text(currentStep.line.lowercased())
                .kNowTitleText()
                .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                .minimumScaleFactor(KStyle.titleMinimumScaleFactor)
                .fixedSize(horizontal: false, vertical: true)

            Text(currentStep.reason.lowercased())
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("k-onboarding-step-\(currentStep.id)")
    }

    private var navigationActions: [KActItem] {
        var actions = [
            KActItem(id: "later", label: "later", accessibilityIdentifier: "k-onboarding-later"),
        ]
        let isLastStep = stepIndex >= steps.count - 1
        actions.append(KActItem(
            id: isLastStep ? "done" : "next",
            label: isLastStep ? "done" : "next",
            accessibilityIdentifier: isLastStep ? "k-onboarding-done" : "k-onboarding-next"
        ))
        return actions
    }

    private func permissionRow(_ row: OnboardingPermissionRow) -> some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            KChecklistRow(
                title: row.line,
                isDone: row.isDone,
                state: row.action == nil ? .disabled : .resting,
                onToggle: {
                    handlePermissionAction(row)
                }
            )

            Text(row.reason.lowercased())
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, KStyle.cardLargePadding)

            if let action = row.action {
                KActRow(
                    actions: [
                        KActItem(
                            id: action.rawValue,
                            label: action.label,
                            accessibilityIdentifier: "k-onboarding-\(row.id)-\(action.rawValue)"
                        ),
                    ],
                    variant: .cadence,
                    onSelect: { _ in
                        handlePermissionAction(row)
                    }
                )
                .padding(.leading, KStyle.cardLargePadding)
            }
        }
        .padding(.vertical, KStyle.microSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("k-onboarding-permission-\(row.id)")
    }

    private func handleNavigationAction(_ action: KActItem) {
        switch action.id {
        case "later":
            onLater()
        case "done":
            onCompleted()
        case "next":
            stepIndex = min(stepIndex + 1, max(steps.count - 1, .zero))
        default:
            break
        }
    }

    private func handlePermissionAction(_ row: OnboardingPermissionRow) {
        guard let action = row.action else { return }
        switch (row.kind, action) {
        case (.camera, .allow):
            onCameraAllow()
        case (.camera, .openSettings):
            onOpenSettings()
        }
    }
}

enum OnboardingSettingsOpener {
    static func open() {
        Task { @MainActor in
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settingsURL)
        }
    }
}
