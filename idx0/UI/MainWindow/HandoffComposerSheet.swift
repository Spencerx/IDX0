import SwiftUI

// MARK: - Handoff Composer Sheet

struct HandoffComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var workflowService: WorkflowService

    @State private var draft: HandoffComposerDraft
    @State private var sourceSessionToken: String
    @State private var targetSessionToken: String
    @State private var checkpointToken: String

    init(initialDraft: HandoffComposerDraft) {
        _draft = State(initialValue: initialDraft)
        _sourceSessionToken = State(initialValue: initialDraft.sourceSessionID.uuidString)
        _targetSessionToken = State(initialValue: initialDraft.targetSessionID?.uuidString ?? "")
        _checkpointToken = State(initialValue: initialDraft.checkpointID?.uuidString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Handoff")
                .font(.headline)

            Picker("Source Session", selection: $sourceSessionToken) {
                ForEach(sessionService.sessions) { session in
                    Text(session.title).tag(session.id.uuidString)
                }
            }
            .onChange(of: sourceSessionToken) { _, token in
                guard let id = UUID(uuidString: token),
                      sessionService.sessions.contains(where: { $0.id == id }) else { return }
                draft.sourceSessionID = id
                if draft.targetType == .otherSession,
                   draft.targetSessionID == id {
                    draft.targetSessionID = nil
                    targetSessionToken = ""
                }
                if let checkpointID = draft.checkpointID,
                   !availableCheckpoints.contains(where: { $0.id == checkpointID }) {
                    draft.checkpointID = nil
                    checkpointToken = ""
                }
            }

            Picker("Target", selection: $draft.targetType) {
                ForEach(HandoffTargetType.allCases, id: \.self) { targetType in
                    Text(targetType.displayLabel).tag(targetType)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.targetType) { _, targetType in
                switch targetType {
                case .selfSession, .reviewQueue:
                    draft.targetSessionID = nil
                    targetSessionToken = ""
                case .otherSession:
                    if let selected = availableTargetSessions.first {
                        draft.targetSessionID = selected.id
                        targetSessionToken = selected.id.uuidString
                    } else {
                        draft.targetSessionID = nil
                        targetSessionToken = ""
                    }
                }
            }

            if draft.targetType == .otherSession {
                if availableTargetSessions.isEmpty {
                    Text("No other sessions available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Target Session", selection: $targetSessionToken) {
                        ForEach(availableTargetSessions) { session in
                            Text(session.title).tag(session.id.uuidString)
                        }
                    }
                    .onChange(of: targetSessionToken) { _, token in
                        draft.targetSessionID = UUID(uuidString: token)
                    }
                }
            }

            Picker("Checkpoint", selection: $checkpointToken) {
                Text("None").tag("")
                ForEach(availableCheckpoints) { checkpoint in
                    Text(checkpoint.title).tag(checkpoint.id.uuidString)
                }
            }
            .onChange(of: checkpointToken) { _, token in
                draft.checkpointID = UUID(uuidString: token)
            }

            TextField("Title", text: $draft.title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Summary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.summary)
                    .frame(minHeight: 78)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Risks (comma or newline separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.risksText)
                    .frame(minHeight: 56)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Next Actions (comma or newline separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.nextActionsText)
                    .frame(minHeight: 56)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    workflowService.dismissHandoffComposer()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Handoff") {
                    workflowService.submitHandoffComposer(draft)
                    dismiss()
                }
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .onAppear {
            syncSelectionsToDraft()
        }
    }

    private var canSubmit: Bool {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if draft.targetType == .otherSession && draft.targetSessionID == nil { return false }
        return true
    }

    private var availableTargetSessions: [Session] {
        sessionService.sessions.filter { $0.id != draft.sourceSessionID }
    }

    private var availableCheckpoints: [Checkpoint] {
        workflowService.checkpoints(for: draft.sourceSessionID)
    }

    private func syncSelectionsToDraft() {
        sourceSessionToken = draft.sourceSessionID.uuidString
        targetSessionToken = draft.targetSessionID?.uuidString ?? ""
        checkpointToken = draft.checkpointID?.uuidString ?? ""
    }
}

