import Foundation
import SwiftUI

struct ProjectService {
    private(set) var groups: [ProjectGroup]

    init(groups: [ProjectGroup] = []) {
        self.groups = groups
    }

    mutating func replaceGroups(_ groups: [ProjectGroup]) {
        self.groups = groups
    }

    mutating func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
    }

    mutating func toggleCollapsed(_ groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].isCollapsed.toggle()
    }

    mutating func synchronize(
        sessions: inout [Session],
        normalizePath: (String?) -> String?,
        projectTitle: (Session) -> String
    ) {
        var groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        var orderedGroupIDs = groups.map(\.id)

        for index in sessions.indices {
            if let existing = sessions[index].projectID, groupsByID[existing] != nil {
                continue
            }

            if let existing = findMatchingGroup(for: sessions[index], groups: groups, normalizePath: normalizePath, projectTitle: projectTitle) {
                sessions[index].projectID = existing.id
                continue
            }

            let group = ProjectGroup(
                id: UUID(),
                title: projectTitle(sessions[index]),
                repoPath: normalizePath(sessions[index].repoPath),
                isCollapsed: false,
                sessionIDs: []
            )
            groups.append(group)
            groupsByID[group.id] = group
            orderedGroupIDs.append(group.id)
            sessions[index].projectID = group.id
        }

        groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        for key in groupsByID.keys {
            guard var group = groupsByID[key] else { continue }
            group.sessionIDs = []
            groupsByID[key] = group
        }

        for session in sessions {
            guard let groupID = session.projectID, var group = groupsByID[groupID] else { continue }
            group.sessionIDs.append(session.id)
            groupsByID[groupID] = group
        }

        // Update group titles for single-session groups when the session's
        // context has changed (e.g. user cd-ed into a git repo).
        for session in sessions {
            guard let groupID = session.projectID, var group = groupsByID[groupID] else { continue }
            let currentTitle = projectTitle(session)
            let normalizedRepo = normalizePath(session.repoPath)

            // Re-assign to an existing matching group if one exists
            if let betterGroup = groups.first(where: {
                $0.id != groupID &&
                (normalizedRepo != nil ? normalizePath($0.repoPath) == normalizedRepo : $0.title == currentTitle)
            }) {
                // Move session to the better-matching group
                if var oldGroup = groupsByID[groupID] {
                    oldGroup.sessionIDs.removeAll { $0 == session.id }
                    groupsByID[groupID] = oldGroup
                }
                if var target = groupsByID[betterGroup.id] {
                    target.sessionIDs.append(session.id)
                    groupsByID[betterGroup.id] = target
                }
                // Update session's projectID in caller's array
                if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[idx].projectID = betterGroup.id
                }
                continue
            }

            // Update title for single-session groups when context changed
            if group.sessionIDs.count == 1 && group.title != currentTitle {
                group.title = currentTitle
                group.repoPath = normalizedRepo
                groupsByID[groupID] = group
            }
        }

        groups = orderedGroupIDs.compactMap { groupID in
            guard let group = groupsByID[groupID], !group.sessionIDs.isEmpty else { return nil }
            return group
        }
    }

    private func findMatchingGroup(
        for session: Session,
        groups: [ProjectGroup],
        normalizePath: (String?) -> String?,
        projectTitle: (Session) -> String
    ) -> ProjectGroup? {
        let normalizedRepo = normalizePath(session.repoPath)
        if let normalizedRepo,
           let match = groups.first(where: { normalizePath($0.repoPath) == normalizedRepo }) {
            return match
        }

        let fallbackTitle = projectTitle(session)
        return groups.first(where: { $0.repoPath == nil && $0.title == fallbackTitle })
    }
}
