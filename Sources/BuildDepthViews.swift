import SwiftUI
struct BuildDepthReader: View {
    @ObservedObject var model: BuildModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var depthTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(x: KStyle.gesturePageTransitionOffset))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("build depth reader")
                .accessibilityIdentifier("build-depth-reader")

            VStack(alignment: .leading, spacing: 0) {
                header

                Rectangle()
                    .fill(.white.opacity(KStyle.dividerOpacity))
                    .frame(height: 1)

                switch model.depthSurface {
                case .review:
                    ScrollView {
                        BuildReviewDepthView(state: model.reviewState, baseURL: model.baseURL)
                            .padding(18)
                            .padding(.trailing, 16)
                    }
                    .scrollIndicators(.hidden)
                case .learned:
                    ScrollView {
                        BuildLearnedDepthView(
                            state: model.learnedState,
                            onDecision: { entry, decision in
                                Task { await model.submitLearnedDecision(entry: entry, decision: decision) }
                            }
                        )
                        .padding(18)
                        .padding(.trailing, 16)
                    }
                    .scrollIndicators(.hidden)
                case .trust:
                    ScrollView {
                        BuildTrustDepthView(state: model.trustState)
                            .padding(18)
                            .padding(.trailing, 16)
                    }
                    .scrollIndicators(.hidden)
                case .logTail:
                    BuildLogTailDepthView(state: model.logTailState)
                        .padding(18)
                        .padding(.trailing, 16)
                case .desk:
                    EmptyView()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width > 48, abs(value.translation.height) < 64 {
                        KStyle.withGesturePageMotion { model.closeDepth() }
                    }
                }
        )
        .transition(depthTransition)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-depth-reader")
        // XCUI cannot see an identifier on a container whose children stay
        // exposed (SwiftUI flattens it) — same reason build-view carries a
        // 1×1 marker. The marker makes the mounted reader audit-visible;
        // children keep their own identifiers.
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.rowSpacing) {
            KActRow(
                actions: [
                    KActItem(id: "back", accessibilityIdentifier: "build-depth-back"),
                ],
                variant: .build,
                onSelect: { _ in KStyle.withGesturePageMotion { model.closeDepth() } }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title.lowercased())
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let meta {
                    Text(meta.lowercased())
                        .kFont(.monoCaption)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
    }

    private var title: String {
        switch model.depthSurface {
        case .review:
            return model.reviewState.target?.title ?? "review"
        case .learned:
            return "learned"
        case .trust:
            return "trust"
        case .logTail:
            return model.logTailState.target?.title ?? "log tail"
        case .desk:
            return "build"
        }
    }

    private var meta: String? {
        switch model.depthSurface {
        case .review:
            return nil
        case .learned:
            let feed = model.learnedState.feed
            return "\(feed.pending.count) pending · \(feed.approved.count) approved"
        case .trust:
            return "\(model.trustState.response.decisionSignalCount) decision signals"
        case .logTail:
            return nil
        case .desk:
            return nil
        }
    }
}

private struct BuildReviewDepthView: View {
    let state: BuildReviewState
    let baseURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if KLoadingPreview.value(for: "-ui34-loading-depth")?.lowercased() == "image" {
                KLoadingPrimitive(
                    variant: .skeleton,
                    lineCount: 2,
                    label: "loading image",
                    accessibilityIdentifier: "build-image-loading"
                )
            } else if state.isLoading {
                KLoadingPrimitive(
                    variant: .skeleton,
                    lineCount: 4,
                    label: "loading review",
                    accessibilityIdentifier: "build-review-loading"
                )
            }

            if let error = state.error {
                KMonoCaption(error, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !state.evidence.isEmpty {
                BuildDepthSection(title: "verification evidence", meta: "\(state.evidence.count) entries") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(state.evidence) { entry in
                            BuildEvidenceEntryView(
                                presentation: BuildEvidenceEntryPresentation(entry: entry),
                                baseURL: baseURL
                            )
                        }
                    }
                }
            }

            if !state.diffs.isEmpty {
                BuildDepthSection(title: "diffs", meta: "\(state.diffs.flatMap(\.files).count) files") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(state.diffs) { diff in
                            BuildDiffReader(diff: diff)
                        }
                    }
                }
            }

            if !state.documents.isEmpty {
                BuildDepthSection(title: "referenced docs", meta: "\(state.documents.count) artifacts") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(state.documents) { document in
                            BuildDocumentReader(document: document)
                        }
                    }
                }
            }

            if !state.isLoading, state.error == nil, state.isEmpty {
                Text("no verification evidence")
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-review-depth")
    }
}

private struct BuildEvidenceEntryView: View {
    let presentation: BuildEvidenceEntryPresentation
    let baseURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let metadata = presentation.metadata {
                KMonoCaption(metadata, variant: .metadata)
                    .textSelection(.enabled)
            }
            Text(presentation.title)
                .font(KStyle.blockDefaultTitleFont)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                .textSelection(.enabled)

            switch presentation.renderKind {
            case .gateOutput:
                KEvidenceBlock(
                    text: presentation.body.isEmpty ? "no gate output" : presentation.body,
                    variant: .gateOutput
                )
            case .transcript:
                Text(presentation.body)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            case .image:
                if let url = resolvedURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            KMonoCaption("image unavailable", variant: .inlineError, state: .error)
                        case .empty:
                            KLoadingPrimitive(
                                variant: .skeleton,
                                lineCount: 2,
                                label: "loading image",
                                accessibilityIdentifier: "build-image-loading"
                            )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
                    .kHairline()
                } else {
                    KMonoCaption(presentation.body.isEmpty ? "image unavailable" : presentation.body, variant: .metadata)
                        .textSelection(.enabled)
                }
            case .text:
                Text(presentation.body)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedURL: URL? {
        guard let reference = presentation.imageReference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reference.isEmpty
        else { return nil }
        if let url = URL(string: reference), url.scheme != nil {
            return url
        }
        guard var components = URLComponents(string: baseURL) else { return URL(string: reference) }
        if reference.hasPrefix("/") {
            components.path = reference
        } else {
            components.path = "/" + reference
        }
        return components.url
    }
}

private struct BuildDiffReader: View {
    let diff: BuildDiffResponse
    @State private var selectedPath: String?

    private var selectedFile: BuildDiffFile? {
        diff.files.first { $0.path == selectedPath } ?? diff.files.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                KMonoCaption(
                    BuildSurfaceCopy.humanTitle(diff.summary, fallback: "diff", identifiers: [diff.id]),
                    variant: .metadata,
                    state: .active
                )
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                KMonoCaption("\(diff.files.count) files", variant: .staleness)
            }

            ScrollView(.horizontal) {
                KActRow(
                    actions: diff.files.enumerated().map { index, file in
                        KActItem(id: file.path, label: "file \(index + 1)")
                    },
                    variant: .build,
                    selectedActionIDs: selectedFile.map { Set([$0.path]) } ?? [],
                    onSelect: { item in selectedPath = item.id }
                )
            }
            .scrollIndicators(.hidden)

            if let selectedFile {
                VStack(alignment: .leading, spacing: 5) {
                    KMonoCaption(fileMeta(selectedFile), variant: .metadata)
                    BuildMonoBlock(text: selectedFile.patch.isEmpty ? "no per-file diff" : selectedFile.patch, variant: .diff)
                }
            }
        }
        .onAppear {
            if selectedPath == nil {
                selectedPath = diff.files.first?.path
            }
        }
    }

    private func fileMeta(_ file: BuildDiffFile) -> String {
        var parts: [String] = [file.status, file.additions.map { "+\($0)" }, file.deletions.map { "-\($0)" }]
            .compactMap { $0 }
        if parts.isEmpty {
            parts.append("file")
        }
        return parts.joined(separator: " · ").lowercased()
    }
}

private struct BuildDocumentReader: View {
    let document: BuildDocumentResponse

    private var contentFontToken: KFontToken {
        document.language?.lowercased() == "json" ? .evidence : .content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KMonoCaption(
                BuildSurfaceCopy.humanTitle(document.title, fallback: "document", identifiers: [document.path]),
                variant: .metadata
            )
                .textSelection(.enabled)
            Text(document.content)
                .kFont(contentFontToken)
                .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if document.truncated {
                KMonoCaption("truncated", variant: .metadata)
            }
        }
    }
}

private struct BuildLearnedDepthView: View {
    let state: BuildLearnedState
    let onDecision: (BuildLearnedEntry, BuildLearnedDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if state.isLoading, state.feed.pending.isEmpty, state.feed.approved.isEmpty {
                KLoadingPrimitive(
                    variant: .skeleton,
                    lineCount: 4,
                    label: "loading learned",
                    accessibilityIdentifier: "build-learned-loading"
                )
            } else if state.isLoading {
                KLoadingPrimitive(
                    variant: .dot,
                    label: "loading learned",
                    accessibilityIdentifier: "build-learned-loading"
                )
            }

            if let error = state.error {
                KMonoCaption(error, variant: .inlineError, state: .error)
                    .textSelection(.enabled)
            }

            if (!state.isLoading && state.error == nil)
                || !state.feed.pending.isEmpty
                || !state.feed.approved.isEmpty {
                BuildDepthSection(title: "pending", meta: "\(state.feed.pending.count) entries") {
                    if let entry = state.feed.nextPending {
                        BuildLearnedPendingCard(
                            entry: entry,
                            isPending: state.pendingDecisionIDs.contains(entry.id),
                            onDecision: { decision in onDecision(entry, decision) }
                        )
                    } else {
                        Text("no pending learned entries")
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                    }
                }

                BuildDepthSection(title: "approved", meta: "\(state.feed.approved.count) entries") {
                    if state.feed.approved.isEmpty {
                        Text("no approved learned entries")
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                    } else {
                        VStack(alignment: .leading, spacing: 11) {
                            ForEach(state.feed.approved) { entry in
                                BuildLearnedApprovedRow(entry: entry)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-learned-depth")
    }
}

private struct BuildLearnedPendingCard: View {
    let entry: BuildLearnedEntry
    let isPending: Bool
    let onDecision: (BuildLearnedDecision) -> Void

    var body: some View {
        KGlassCard(state: isPending ? .loading : .resting) {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                if let title = entry.title {
                    KMonoCaption(
                        BuildSurfaceCopy.humanTitle(title, fallback: "learned entry", identifiers: [entry.id, entry.source]),
                        variant: .metadata
                    )
                }
                Text(entry.text)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: KStyle.smallSpacing) {
                    Spacer(minLength: 0)
                    KActRow(
                        actions: [
                            KActItem(id: BuildLearnedDecision.discard.rawValue),
                            KActItem(id: BuildLearnedDecision.edit.rawValue),
                            KActItem(id: BuildLearnedDecision.approve.rawValue),
                        ],
                        variant: .build,
                        state: isPending ? .loading : .resting,
                        onSelect: { item in
                            if let decision = BuildLearnedDecision(rawValue: item.id) {
                                onDecision(decision)
                            }
                        }
                    )
                }
            }
        }
    }
}

private struct BuildLearnedApprovedRow: View {
    let entry: BuildLearnedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .font(KStyle.contentFont)
                .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let meta {
                KMonoCaption(meta, variant: .metadata)
                    .textSelection(.enabled)
            }
        }
    }

    private var meta: String? {
        let text = BuildPayload.unique([entry.updatedAt].compactMap { $0 })
            .joined(separator: " · ")
            .lowercased()
        return text.isEmpty ? nil : text
    }
}

private struct BuildTrustDepthView: View {
    let state: BuildTrustState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KMonoCaption("\(state.response.decisionSignalCount) decision signals", variant: .staleness)
                .textSelection(.enabled)

            if state.isLoading, state.response.pairs.isEmpty {
                KLoadingPrimitive(
                    variant: .skeleton,
                    lineCount: 4,
                    label: "loading trust",
                    accessibilityIdentifier: "build-trust-loading"
                )
            }

            if let error = state.error {
                KMonoCaption(error, variant: .inlineError, state: .error)
                    .textSelection(.enabled)
            }

            if state.response.pairs.isEmpty, !state.isLoading, state.error == nil {
                Text("no trust pairs")
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(state.response.presentations) { row in
                        BuildTrustPairRow(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-trust-depth")
    }
}

private struct BuildTrustPairRow: View {
    let row: BuildTrustPairPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.verdictText)
                .font(KStyle.contentFont)
                .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(row.decisionText.isEmpty ? "no decision" : row.decisionText)
                .font(KStyle.contentFont)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let meta = row.metaText {
                KMonoCaption(meta, variant: .metadata)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct BuildLogTailDepthView: View {
    let state: BuildLogTailState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if state.isLoading, tailText.isEmpty {
                        KLoadingPrimitive(
                            variant: .skeleton,
                            lineCount: 5,
                            label: "loading log tail",
                            accessibilityIdentifier: "build-log-tail-loading"
                        )
                    }

                    if let error = state.error {
                        KMonoCaption(error, variant: .inlineError, state: .error)
                            .textSelection(.enabled)
                    }

                    if !tailText.isEmpty {
                        BuildMonoBlock(text: tailText, variant: .logTail)
                    } else if !state.isLoading, state.error == nil {
                        BuildMonoBlock(text: "no log tail", variant: .logTail)
                    }

                    if state.response?.truncated == true {
                        KMonoCaption("bounded tail", variant: .metadata)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("tail-bottom")
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: tailText) { _, _ in
                KStyle.withMotion {
                    proxy.scrollTo("tail-bottom", anchor: .bottom)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-log-tail-depth")
    }

    private var tailText: String {
        state.response?.text ?? ""
    }
}

private struct BuildDepthSection<Content: View>: View {
    let title: String
    let meta: String?
    let content: Content

    init(title: String, meta: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.meta = meta
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                KMonoCaption(title, variant: .metadata, state: .active)
                Spacer(minLength: 0)
                if let meta {
                    KMonoCaption(meta, variant: .staleness)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BuildMonoBlock: View {
    let text: String
    let variant: KEvidenceBlockVariant

    init(text: String, variant: KEvidenceBlockVariant = .mono) {
        self.text = text
        self.variant = variant
    }

    var body: some View {
        KEvidenceBlock(text: text, variant: variant)
    }
}
