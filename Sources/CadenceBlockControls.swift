import Foundation
import SwiftUI
import UIKit
struct CadenceWorkInlineAffordance: View {
    let text: String
    var foregroundColor: Color = KStyle.nearBlack

    var body: some View {
        Text(text)
            .kFont(.monoCaption)
            .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("cadence-work-inline-affordance")
    }
}

struct CadenceWorkModeChips: View {
    let currentMode: String?
    var foregroundColor: Color = KStyle.nearBlack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let modes = ["divergent", "convergent", "breakthrough"]

    var body: some View {
        HStack(spacing: .zero) {
            chips
        }
        .padding(KStyle.cadenceWorkChipGroupPadding)
        .background(
            foregroundColor.opacity(KStyle.cadenceWorkChipGroupFillOpacity),
            in: RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-work-mode-chips")
    }

    private var chips: some View {
        ForEach(modes, id: \.self) { mode in
            HStack(spacing: KStyle.microSpacing) {
                if mode == "breakthrough" {
                    Image(systemName: "lock.fill")
                        .font(KStyle.monoCaptionFont)
                        .frame(width: KStyle.cadenceWorkChipLockSize, height: KStyle.cadenceWorkChipLockSize)
                        .accessibilityHidden(true)
                }

                Text(mode.uppercased())
                    .kFont(.monoCaption)
                    .lineLimit(1)
                    .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
            }
            .foregroundStyle(chipTextColor(for: mode))
            .animation(KStyle.selectorTextMotion(reduceMotion), value: normalizedCurrentMode)
            .padding(.horizontal, KStyle.cadenceWorkChipHorizontalPadding)
            .padding(.vertical, KStyle.cadenceWorkChipVerticalPadding)
            .background {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .fill(isSelected(mode)
                        ? Color.white.opacity(KStyle.selectorActiveFillOpacity)
                        : Color.clear)
                    .animation(KStyle.selectorBackgroundMotion(reduceMotion), value: normalizedCurrentMode)
            }
        }
    }

    private func isSelected(_ mode: String) -> Bool {
        normalizedCurrentMode?.contains(mode) == true
    }

    private var normalizedCurrentMode: String? {
        currentMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func chipTextColor(for mode: String) -> Color {
        isSelected(mode)
            ? KStyle.nearBlack.opacity(KStyle.selectorActiveTextOpacity)
            : foregroundColor.opacity(KStyle.selectorInactiveTextOpacity)
    }
}

struct CadenceOverrunCompleteButton: View {
    let isEnabled: Bool
    let isPaper: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(systemName: "checkmark")
                .font(KStyle.cadenceCompleteCheckIconFont)
                .foregroundStyle(iconColor)
                .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("complete")
        .accessibilityIdentifier("cadence-overrun-complete")
    }

    private var iconColor: Color {
        let base: Color = isPaper ? KStyle.nearBlack : .white
        return base.opacity(isEnabled ? KStyle.secondaryTextOpacity : KStyle.quaternaryTextOpacity)
    }
}

struct CadenceBandishFooterCaption: View {
    let text: String
    let isPaper: Bool
    var isError = false

    var body: some View {
        Text(text.lowercased())
            .kFont(.monoCaption)
            .foregroundStyle(foregroundColor)
    }

    private var foregroundColor: Color {
        if isError {
            return Color.white.opacity(KStyle.tertiaryTextOpacity)
        }
        let base: Color = isPaper ? KStyle.nearBlack : .white
        return base.opacity(isPaper ? KStyle.secondaryTextOpacity : KStyle.tertiaryTextOpacity)
    }
}

struct CadenceMealLogInlineEntry: View {
    let state: KPrimitiveInteractionState
    let echoText: String?
    var alignment: HorizontalAlignment = .leading
    var foregroundColor: Color = .white
    let onSubmit: (MealMacroMeasurements) async -> CadenceMealLogSubmitResult
    let onPhoto: (UIImage, String?) async -> CadenceMealLogSubmitResult
    @State private var isEditing = false
    @State private var text = ""
    @State private var isPending = false
    @State private var errorText: String?
    @State private var statusText: String?

    var body: some View {
        VStack(alignment: alignment, spacing: KStyle.microSpacing) {
            if isEditing {
                HStack(alignment: .center, spacing: KStyle.smallSpacing) {
                    TextField("420 kcal · 31 protein", text: $text)
                        .textFieldStyle(.plain)
                        .kFont(.monoCaption)
                        .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                        .lineLimit(KStyle.singleLineLimit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.done)
                        .padding(.horizontal, KStyle.inputHorizontalPadding)
                        .padding(.vertical, KStyle.optionButtonVerticalPadding)
                        .frame(minHeight: KStyle.minimumTapTarget)
                        .kInputFieldTone()
                        .disabled(isPending || state.disablesInput)
                        .onSubmit(save)
                        .accessibilityLabel("meal log")

                    KOptionButton(
                        label: "save",
                        variant: .quietHairline,
                        isEnabled: parsedMeal != nil && !isPending && !state.disablesAction,
                        isPending: isPending,
                        state: isPending ? .loading : state,
                        accessibilityIdentifier: "cadence-meal-log-save",
                        onSelect: save
                    )
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    if let echoText {
                        KMonoCaption(echoText, variant: .status, state: .active)
                    }

                    KOptionButton(
                        label: "log",
                        variant: .quietHairline,
                        state: state,
                        accessibilityIdentifier: "cadence-meal-log-open",
                        onSelect: {
                            errorText = nil
                            KStyle.withMotion {
                                isEditing = true
                            }
                        }
                    )

                    MealPhotoButton(
                        caption: nil,
                        foregroundColor: foregroundColor,
                        state: state,
                        accessibilityIdentifier: "cadence-meal-photo-open",
                        onImage: submitPhoto(image:caption:)
                    )
                }
            }

            if let errorText {
                KMonoCaption(errorText, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if let statusText {
                KMonoCaption(statusText, variant: .status, state: .active)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .kAnimated(value: isEditing)
        .kAnimated(value: isPending)
        .kAnimated(value: statusText)
    }

    private var parsedMeal: MealMacroMeasurements? {
        MealTextParser.parse(text)
    }

    private func save() {
        guard let meal = parsedMeal, !isPending, !state.disablesAction else { return }
        isPending = true
        errorText = nil
        statusText = nil
        Task {
            let outcome = await onSubmit(meal)
            await MainActor.run {
                isPending = false
                switch outcome {
                case .success(let message):
                    statusText = message
                    text = ""
                    KStyle.withMotion {
                        isEditing = false
                    }
                case .failure(let message):
                    errorText = message
                }
            }
        }
    }

    @MainActor
    private func submitPhoto(image: UIImage, caption: String?) async -> Bool {
        errorText = nil
        statusText = nil
        let outcome = await onPhoto(image, caption)
        switch outcome {
        case .success(let message):
            statusText = message
            return true
        case .failure(let message):
            errorText = message
            return false
        }
    }
}

struct CadenceChecklistRows: View {
    let items: [CadenceChecklistItem]
    let foregroundColor: Color
    let onToggle: (CadenceChecklistItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            ForEach(items) { item in
                KChecklistRow(
                    title: item.rowTitle,
                    isDone: item.done,
                    foregroundColor: foregroundColor,
                    onToggle: {
                        onToggle(item)
                    }
                )
                .accessibilityIdentifier("cadence-checklist-\(item.id)")
            }
        }
    }
}

struct CadenceBodyLivePacketCard: View {
    let packet: ViewPacket
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                Spacer(minLength: 0)
                KActRow(
                    actions: [KActItem(id: "dismiss")],
                    variant: .cadence,
                    onSelect: { _ in onDismiss() }
                )
            }

            RenderViewPacket(packet: packet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CadenceBodyInterventionsChecklist: View {
    let model: CadenceBodyInterventionsChecklistModel
    let state: KPrimitiveInteractionState
    let onFeedback: (BodyCueProtocol, BodyInterventionFeedbackAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if !model.protocols.isEmpty {
                KMonoCaption("interventions", variant: .metadata, state: state)
            }

            ForEach(model.protocols) { item in
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KMonoCaption(BodyCueProtocolFormatter.line(for: item), variant: .metadata, state: state)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    interventionActs(for: item)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cadence-body-intervention-\(item.id)")
            }

            if let errorText = model.errorText {
                KMonoCaption(errorText, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kAnimated(value: model)
    }

    private func interventionActs(for item: BodyCueProtocol) -> some View {
        let isPending = model.pendingIDs.contains(item.id)
        return KActRow(
            actions: [
                KActItem(
                    id: BodyInterventionFeedbackAction.accept.rawValue,
                    isEnabled: !isPending,
                    accessibilityIdentifier: "cadence-body-intervention-\(item.id)-accept"
                ),
                KActItem(
                    id: BodyInterventionFeedbackAction.dismiss.rawValue,
                    isEnabled: !isPending,
                    accessibilityIdentifier: "cadence-body-intervention-\(item.id)-dismiss"
                ),
            ],
            variant: .cadence,
            state: isPending ? .loading : state,
            onSelect: { action in
                if let feedback = BodyInterventionFeedbackAction(rawValue: action.id) {
                    onFeedback(item, feedback)
                }
            }
        )
    }
}

struct CadenceLifecycleActions: View {
    let control: CadenceLifecycleControlModel
    let isPending: Bool
    let state: KPrimitiveInteractionState
    let onAction: (CadenceBlockAction) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: KStyle.smallSpacing) {
            if let optionLabel = control.optionLabel, let optionAction = control.optionAction {
                KOptionButton(
                    label: optionLabel,
                    variant: .primaryFilled,
                    isPending: isPending,
                    state: actionState,
                    accessibilityIdentifier: "cadence-lifecycle-\(optionLabel)",
                    onSelect: { onAction(optionAction) }
                )
                .transition(.opacity)
            }

            if !control.rowActions.isEmpty {
                KActRow(
                    actions: control.rowActions.map(actionItem),
                    variant: .cadence,
                    state: actionState,
                    onSelect: { item in
                        if let action = CadenceBlockAction(rawValue: item.id) {
                            onAction(action)
                        }
                    }
                )
                .transition(.opacity)
            }
        }
    }

    private var actionState: KPrimitiveInteractionState {
        if isPending { return .loading }
        if state.disablesAction { return state }
        return control.isStarted ? .active : state
    }

    private func actionItem(_ action: CadenceBlockAction) -> KActItem {
        KActItem(id: action.rawValue, label: action.label)
    }
}

struct CadenceBlockActions: View {
    let isPending: Bool
    let isNow: Bool
    let showsBlockActions: Bool
    let showsTWSPrompt: Bool
    let twsAnswerText: String?
    let onAction: (CadenceBlockAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            if showsBlockActions {
                KActRow(
                    actions: [.complete, .skip, .extend15].map(actionItem),
                    variant: .cadence,
                    state: actionState,
                    onSelect: { item in
                        if let action = CadenceBlockAction(rawValue: item.id) {
                            onAction(action)
                        }
                    }
                )
                .transition(.opacity)
            }

            if showsTWSPrompt {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KMonoCaption("well spent?", variant: .status)
                    KActRow(
                        actions: [.twsYes, .twsNo].map(actionItem),
                        variant: .cadence,
                        state: actionState,
                        onSelect: { item in
                            if let action = CadenceBlockAction(rawValue: item.id) {
                                onAction(action)
                            }
                        }
                    )
                }
                .transition(.opacity)
            } else if let twsAnswerText {
                KMonoCaption(twsAnswerText, variant: .status, state: .disabled)
                    .transition(.opacity)
            }
        }
    }

    private var actionState: KPrimitiveInteractionState {
        if isPending { return .loading }
        return isNow ? .active : .resting
    }

    private func actionItem(_ action: CadenceBlockAction) -> KActItem {
        KActItem(id: action.rawValue, label: action.label)
    }
}

// ---- membrane compare surface (challenger-jut) ----
