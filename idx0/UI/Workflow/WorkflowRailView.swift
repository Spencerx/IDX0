import SwiftUI

private enum CompareMode: String, CaseIterable {
    case objects
    case branches

    var displayLabel: String {
        switch self {
        case .objects: return "Checkpoints / Sessions"
        case .branches: return "Branches"
        }
    }
}

private extension WorkflowRailSurface {
    var title: String {
        switch self {
        case .checkpoints: return "Checkpoints"
        case .handoffs: return "Handoffs"
        case .review: return "Review"
        case .compare: return "Compare"
        }
    }

    var icon: String {
        switch self {
        case .checkpoints: return "bookmark"
        case .handoffs: return "paperplane"
        case .review: return "doc.text.magnifyingglass"
        case .compare: return "square.split.2x1"
        }
    }
}

struct WorkflowRailView: View {
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var workflowService: WorkflowService
    @Environment(\.themeColors) private var tc

    @State private var checkpointSessionFilter: String = "selected"

    @State private var compareMode: CompareMode = .objects
    @State private var leftCompareID = ""
    @State private var rightCompareID = ""
    @State private var selectedBranchRepoPath = ""
    @State private var leftBranch = ""
    @State private var rightBranch = ""
    @State private var availableBranches: [String] = []
    @State private var isLoadingBranches = false
    @State private var compareResult: CompareResult?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Icon Tab Bar (#5)
            HStack(spacing: 0) {
                ForEach(WorkflowRailSurface.allCases, id: \.self) { surface in
                    railTabButton(surface)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)

            Rectangle()
                .fill(tc.divider)
                .frame(height: 1)

            // Section header
            HStack {
                Text(workflowService.selectedRailSurface.title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(tc.mutedText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            switch workflowService.selectedRailSurface {
            case .checkpoints:
                checkpointsTab
            case .handoffs:
                handoffsTab
            case .review:
                reviewTab
            case .compare:
                compareTab
            }
        }
        .background(tc.sidebarBackground)
        .onAppear {
            seedCompareSelectionsIfNeeded()
            seedCheckpointFilterIfNeeded()
            seedBranchRepoIfNeeded()
        }
        .onChange(of: workflowService.comparePresetLeft) { _, _ in seedCompareSelectionsIfNeeded() }
        .onChange(of: workflowService.comparePresetRight) { _, _ in seedCompareSelectionsIfNeeded() }
        .onChange(of: sessionService.selectedSessionID) { _, _ in seedCheckpointFilterIfNeeded() }
        .onChange(of: selectedBranchRepoPath) { _, _ in loadBranchesForSelectedRepo() }
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func railTabButton(_ surface: WorkflowRailSurface) -> some View {
        let isActive = workflowService.selectedRailSurface == surface
        Button {
            workflowService.openRailSurface(surface)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: surface.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? tc.primaryText : tc.tertiaryText)
                    .frame(width: 30, height: 24)

                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(surface.title)
    }

    // MARK: - Checkpoints Tab

    private var checkpointsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Session", selection: $checkpointSessionFilter) {
                    Text("Selected Session").tag("selected")
                    Text("All Sessions").tag("all")
                    ForEach(sessionService.sessions) { session in
                        Text(session.title).tag(session.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                if let selectedSessionID = sessionService.selectedSessionID {
                    Button("Create") {
                        Task {
                            _ = try? await workflowService.createManualCheckpoint(
                                sessionID: selectedSessionID, title: "Manual Checkpoint",
                                summary: "Created from checkpoints rail", requestReview: false
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            .padding(.horizontal, 10)

            let filtered = filteredCheckpoints
            if filtered.isEmpty {
                EmptyStateView(
                    icon: "bookmark",
                    title: "No checkpoints yet",
                    subtitle: "Press \u{2318}\u{21e7}C to save your current state"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { checkpoint in
                            WorkflowCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(checkpoint.title)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(checkpoint.summary)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        if let branch = checkpoint.branchName {
                                            Text(branch).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                        }
                                        if let sha = checkpoint.commitSHA {
                                            Text(String(sha.prefix(8))).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                        }
                                        Text(checkpoint.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    if let diff = checkpoint.diffStat {
                                        Text("\u{0394} \(diff.filesChanged) files, +\(diff.additions) -\(diff.deletions)")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    if let tests = checkpoint.testSummary {
                                        Text("Tests: \(tests.status.rawValue) \u{2014} \(tests.summaryText)")
                                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { workflowService.selectCheckpoint(checkpoint.id) }
                            .background(
                                checkpoint.id == selectedCheckpoint?.id ? Color.white.opacity(0.04) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }

                if let checkpoint = selectedCheckpoint {
                    Divider()
                    checkpointDetails(checkpoint)
                        .padding(10)
                }
            }
        }
    }

    private func checkpointDetails(_ checkpoint: Checkpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(checkpoint.title).font(.system(size: 12, weight: .semibold))
            Text(checkpoint.summary).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let branch = checkpoint.branchName { Text("Branch: \(branch)").font(.caption).foregroundStyle(.secondary) }
                if let sha = checkpoint.commitSHA { Text("SHA: \(String(sha.prefix(12)))").font(.caption).foregroundStyle(.secondary) }
                Text(checkpoint.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            if let diff = checkpoint.diffStat {
                Text("\u{0394} \(diff.filesChanged) files, +\(diff.additions) -\(diff.deletions)").font(.caption).foregroundStyle(.secondary)
            }
            if let tests = checkpoint.testSummary {
                Text("Tests: \(tests.status.rawValue) \u{2014} \(tests.summaryText)").font(.caption).foregroundStyle(.secondary)
            }
            if !checkpoint.changedFiles.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(checkpoint.changedFiles.prefix(30).enumerated()), id: \.offset) { _, file in
                            Text("\(file.status) \(file.path)")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
            HStack {
                Button("Request Review") {
                    _ = workflowService.createReviewRequest(sourceSessionID: checkpoint.sessionID, checkpointID: checkpoint.id, summary: checkpoint.summary, changedFiles: checkpoint.changedFiles, diffStat: checkpoint.diffStat, testSummary: checkpoint.testSummary)
                    workflowService.openRailSurface(.review)
                }.buttonStyle(.bordered).controlSize(.small)
                Button("Create Handoff") {
                    workflowService.presentHandoffComposer(sourceSessionID: checkpoint.sessionID, checkpointID: checkpoint.id)
                }.buttonStyle(.bordered).controlSize(.small)
                Button("Compare\u{2026}") {
                    workflowService.beginCompare(with: checkpoint.id)
                }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // MARK: - Handoffs Tab

    private var handoffsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if let selectedSessionID = sessionService.selectedSessionID {
                    Button("New Handoff") {
                        workflowService.presentHandoffComposer(sourceSessionID: selectedSessionID)
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            .padding(.horizontal, 10)

            let ordered = workflowService.handoffs.sorted { $0.createdAt > $1.createdAt }
            if ordered.isEmpty {
                EmptyStateView(
                    icon: "paperplane",
                    title: "No handoffs",
                    subtitle: "Transfer work between sessions with \u{2318}\u{21e7}H"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(ordered) { handoff in
                            WorkflowCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(handoff.title).font(.system(size: 11, weight: .semibold))
                                    Text(handoff.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                                    Text("Status: \(handoff.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { workflowService.selectHandoff(handoff.id) }
                            .background(
                                handoff.id == selectedHandoff?.id ? Color.white.opacity(0.04) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }

                if let handoff = selectedHandoff {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(handoff.title).font(.system(size: 12, weight: .semibold))
                        Text(handoff.summary).font(.system(size: 10)).foregroundStyle(.secondary)
                        if !handoff.risks.isEmpty { Text("Risks: \(handoff.risks.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                        if !handoff.nextActions.isEmpty { Text("Next: \(handoff.nextActions.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Pending") { workflowService.updateHandoffStatus(id: handoff.id, status: .pending) }.buttonStyle(.bordered).controlSize(.small)
                            Button("Accept") { workflowService.updateHandoffStatus(id: handoff.id, status: .accepted) }.buttonStyle(.bordered).controlSize(.small)
                            Button("Resolve") { workflowService.updateHandoffStatus(id: handoff.id, status: .resolved) }.buttonStyle(.borderedProminent).controlSize(.small)
                        }
                        HStack {
                            Button("Jump Source") { sessionService.focusSession(handoff.sourceSessionID) }.buttonStyle(.bordered).controlSize(.small)
                            if let target = handoff.targetSessionID {
                                Button("Jump Target") { sessionService.focusSession(target) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    // MARK: - Review Tab

    private var reviewTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            let allReviews = workflowService.reviews.sorted { $0.createdAt > $1.createdAt }
            let options = allReviews.map { (id: $0.id.uuidString, label: "\($0.summary.prefix(36))") }

            if options.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No reviews pending",
                    subtitle: "Request a review from the Checkpoints tab"
                )
            } else {
                Picker("Request", selection: Binding(
                    get: { workflowService.selectedReviewID?.uuidString ?? options[0].id },
                    set: { workflowService.selectReview(UUID(uuidString: $0)) }
                )) {
                    ForEach(options, id: \.id) { option in Text(option.label).tag(option.id) }
                }
                .padding(.horizontal, 10)

                if let selectedReview = allReviews.first(where: { $0.id == (workflowService.selectedReviewID ?? allReviews[0].id) }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status: \(selectedReview.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                            Text(selectedReview.summary).font(.system(size: 12, weight: .semibold))
                            Text("Files: \(selectedReview.changedFiles.count)").font(.caption).foregroundStyle(.secondary)
                            if let diff = selectedReview.diffStat {
                                Text("\u{0394} \(diff.filesChanged) files, +\(diff.additions) -\(diff.deletions)").font(.caption).foregroundStyle(.secondary)
                            }
                            if let testSummary = selectedReview.testSummary {
                                Text("Tests: \(testSummary.status.rawValue) \u{2014} \(testSummary.summaryText)").font(.caption).foregroundStyle(.secondary)
                            }
                            if !selectedReview.changedFiles.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(selectedReview.changedFiles.prefix(20).enumerated()), id: \.offset) { _, file in
                                        HStack(spacing: 6) {
                                            Text(file.status).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                                            Text(file.path).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                }
                            }

                            HStack {
                                Button("Approve") { try? workflowService.setReviewStatus(id: selectedReview.id, status: .approved) }.buttonStyle(.borderedProminent).controlSize(.small)
                                Button("Changes Requested") { try? workflowService.setReviewStatus(id: selectedReview.id, status: .changesRequested) }.buttonStyle(.bordered).controlSize(.small)
                                Button("Defer") { try? workflowService.setReviewStatus(id: selectedReview.id, status: .deferred) }.buttonStyle(.bordered).controlSize(.small)
                            }
                            HStack {
                                Button("Jump to Source Session") { sessionService.focusSession(selectedReview.sourceSessionID) }.buttonStyle(.bordered).controlSize(.small)
                                if let checkpointID = selectedReview.checkpointID, workflowService.checkpoints.contains(where: { $0.id == checkpointID }) {
                                    Button("Open Checkpoint") { workflowService.openCheckpoint(checkpointID) }.buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                        .padding(10)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Compare Tab

    private var compareTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $compareMode) {
                ForEach(CompareMode.allCases, id: \.self) { mode in Text(mode.displayLabel).tag(mode) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)

            if compareMode == .objects { compareObjectInputs } else { compareBranchInputs }

            if let compareResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(compareResult.leftTitle) \u{2194} \(compareResult.rightTitle)").font(.system(size: 12, weight: .semibold))
                        Text("Left: \(compareResult.leftSummary)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text("Right: \(compareResult.rightSummary)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let leftStat = compareResult.leftDiffStat {
                            Text("Left \u{0394} \(leftStat.filesChanged) files, +\(leftStat.additions) -\(leftStat.deletions)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let rightStat = compareResult.rightDiffStat {
                            Text("Right \u{0394} \(rightStat.filesChanged) files, +\(rightStat.additions) -\(rightStat.deletions)").font(.caption).foregroundStyle(.secondary)
                        }
                        filePathSection(title: "Overlap", paths: compareResult.overlapPaths)
                        filePathSection(title: "Left only", paths: compareResult.leftOnlyPaths)
                        filePathSection(title: "Right only", paths: compareResult.rightOnlyPaths)
                        HStack {
                            if let leftSessionID = compareResult.leftSourceSessionID {
                                Button("Jump Left") { sessionService.focusSession(leftSessionID) }.buttonStyle(.bordered).controlSize(.small)
                            }
                            if let rightSessionID = compareResult.rightSourceSessionID {
                                Button("Jump Right") { sessionService.focusSession(rightSessionID) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    .padding(10)
                }
            }
            Spacer()
        }
    }

    private var compareObjectInputs: some View {
        let options = compareOptions
        return Group {
            if options.count < 2 {
                EmptyStateView(icon: "square.split.2x1", title: "Not enough data", subtitle: "Need at least two checkpoints or sessions to compare")
            } else {
                VStack(spacing: 8) {
                    Picker("Left", selection: $leftCompareID) {
                        ForEach(options, id: \.id) { option in Text(option.label).tag(option.id) }
                    }
                    Picker("Right", selection: $rightCompareID) {
                        ForEach(options, id: \.id) { option in Text(option.label).tag(option.id) }
                    }
                    Button("Compare") {
                        Task {
                            guard let left = compareInput(for: leftCompareID), let right = compareInput(for: rightCompareID) else { compareResult = nil; return }
                            compareResult = await workflowService.compare(left, right)
                        }
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private var compareBranchInputs: some View {
        let repoPaths = workflowService.branchCompareRepoPaths()
        return Group {
            if repoPaths.isEmpty {
                EmptyStateView(icon: "arrow.triangle.branch", title: "No repos available", subtitle: "Open a repo-backed session to compare branches")
            } else {
                VStack(spacing: 8) {
                    Picker("Repo", selection: $selectedBranchRepoPath) {
                        ForEach(repoPaths, id: \.self) { repoPath in Text(URL(fileURLWithPath: repoPath).lastPathComponent).tag(repoPath) }
                    }
                    if isLoadingBranches {
                        ProgressView().controlSize(.small)
                    } else if availableBranches.isEmpty {
                        Text("No local branches found.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Left Branch", selection: $leftBranch) { ForEach(availableBranches, id: \.self) { b in Text(b).tag(b) } }
                        Picker("Right Branch", selection: $rightBranch) { ForEach(availableBranches, id: \.self) { b in Text(b).tag(b) } }
                        Button("Compare Branches") {
                            Task {
                                guard !selectedBranchRepoPath.isEmpty, !leftBranch.isEmpty, !rightBranch.isEmpty else { compareResult = nil; return }
                                compareResult = await workflowService.compareBranches(repoPath: selectedBranchRepoPath, leftBranch: leftBranch, rightBranch: rightBranch)
                            }
                        }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func filePathSection(title: String, paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(title): \(paths.count)").font(.caption).foregroundStyle(.secondary)
            if paths.isEmpty {
                Text("None").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(paths.prefix(40)), id: \.self) { path in
                        Text(path).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - State Helpers

    private var filteredCheckpoints: [Checkpoint] {
        let base = workflowService.checkpoints.sorted { $0.createdAt > $1.createdAt }
        switch checkpointSessionFilter {
        case "all": return base
        case "selected":
            guard let selectedSessionID = sessionService.selectedSessionID else { return [] }
            return base.filter { $0.sessionID == selectedSessionID }
        default:
            guard let sessionID = UUID(uuidString: checkpointSessionFilter) else { return base }
            return base.filter { $0.sessionID == sessionID }
        }
    }

    private var selectedCheckpoint: Checkpoint? {
        if let selectedCheckpointID = workflowService.selectedCheckpointID,
           let selected = workflowService.checkpoints.first(where: { $0.id == selectedCheckpointID }) {
            return selected
        }
        return filteredCheckpoints.first
    }

    private var selectedHandoff: Handoff? {
        if let selectedHandoffID = workflowService.selectedHandoffID,
           let selected = workflowService.handoffs.first(where: { $0.id == selectedHandoffID }) {
            return selected
        }
        return workflowService.handoffs.sorted { $0.createdAt > $1.createdAt }.first
    }

    private var compareOptions: [(id: String, label: String)] {
        let checkpointOptions = workflowService.checkpoints.map { ("checkpoint:\($0.id.uuidString)", "Checkpoint: \($0.title)") }
        let sessionOptions = sessionService.sessions.map { ("session:\($0.id.uuidString)", "Session: \($0.title)") }
        return checkpointOptions + sessionOptions
    }

    private func compareInput(for token: String) -> CompareInput? {
        if token.hasPrefix("checkpoint:"), let id = UUID(uuidString: String(token.dropFirst("checkpoint:".count))) { return .checkpoint(id) }
        if token.hasPrefix("session:"), let id = UUID(uuidString: String(token.dropFirst("session:".count))) { return .session(id) }
        return nil
    }

    private func seedCompareSelectionsIfNeeded() {
        if let leftPreset = workflowService.comparePresetLeft {
            switch leftPreset {
            case .checkpoint(let id): leftCompareID = "checkpoint:\(id.uuidString)"
            case .session(let id): leftCompareID = "session:\(id.uuidString)"
            case .branches: break
            }
        } else if leftCompareID.isEmpty, let first = compareOptions.first?.id { leftCompareID = first }
        if let rightPreset = workflowService.comparePresetRight {
            switch rightPreset {
            case .checkpoint(let id): rightCompareID = "checkpoint:\(id.uuidString)"
            case .session(let id): rightCompareID = "session:\(id.uuidString)"
            case .branches: break
            }
        } else if rightCompareID.isEmpty, compareOptions.count > 1 { rightCompareID = compareOptions[1].id }
    }

    private func seedCheckpointFilterIfNeeded() {
        if checkpointSessionFilter == "selected", sessionService.selectedSessionID == nil, let fallback = sessionService.sessions.first {
            checkpointSessionFilter = fallback.id.uuidString
        }
    }

    private func seedBranchRepoIfNeeded() {
        if selectedBranchRepoPath.isEmpty, let first = workflowService.branchCompareRepoPaths().first {
            selectedBranchRepoPath = first
            loadBranchesForSelectedRepo()
        }
    }

    private func loadBranchesForSelectedRepo() {
        guard !selectedBranchRepoPath.isEmpty else { availableBranches = []; return }
        isLoadingBranches = true
        Task {
            let branches = await workflowService.localBranches(for: selectedBranchRepoPath)
            await MainActor.run {
                availableBranches = branches
                if leftBranch.isEmpty || !branches.contains(leftBranch) { leftBranch = branches.first ?? "" }
                if rightBranch.isEmpty || !branches.contains(rightBranch) { rightBranch = branches.dropFirst().first ?? (branches.first ?? "") }
                isLoadingBranches = false
            }
        }
    }
}
