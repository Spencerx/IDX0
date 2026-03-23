import Foundation

struct FileSystemPaths {
    let appSupportDirectory: URL
    let sessionsFile: URL
    let projectsFile: URL
    let inboxFile: URL
    let checkpointsFile: URL
    let handoffsFile: URL
    let reviewsFile: URL
    let approvalsFile: URL
    let queueFile: URL
    let timelineFile: URL
    let layoutFile: URL
    let agentEventsFile: URL
    let settingsFile: URL
    let runDirectory: URL
    let tempDirectory: URL
    let worktreesDirectory: URL

    init(
        appSupportDirectory: URL,
        sessionsFile: URL,
        projectsFile: URL,
        inboxFile: URL,
        checkpointsFile: URL,
        handoffsFile: URL,
        reviewsFile: URL,
        approvalsFile: URL,
        queueFile: URL,
        timelineFile: URL,
        layoutFile: URL,
        agentEventsFile: URL,
        settingsFile: URL,
        runDirectory: URL,
        tempDirectory: URL,
        worktreesDirectory: URL
    ) {
        self.appSupportDirectory = appSupportDirectory
        self.sessionsFile = sessionsFile
        self.projectsFile = projectsFile
        self.inboxFile = inboxFile
        self.checkpointsFile = checkpointsFile
        self.handoffsFile = handoffsFile
        self.reviewsFile = reviewsFile
        self.approvalsFile = approvalsFile
        self.queueFile = queueFile
        self.timelineFile = timelineFile
        self.layoutFile = layoutFile
        self.agentEventsFile = agentEventsFile
        self.settingsFile = settingsFile
        self.runDirectory = runDirectory
        self.tempDirectory = tempDirectory
        self.worktreesDirectory = worktreesDirectory
    }

    init(
        appSupportDirectory: URL,
        sessionsFile: URL,
        projectsFile: URL,
        inboxFile: URL,
        settingsFile: URL,
        runDirectory: URL,
        tempDirectory: URL,
        worktreesDirectory: URL
    ) {
        self.init(
            appSupportDirectory: appSupportDirectory,
            sessionsFile: sessionsFile,
            projectsFile: projectsFile,
            inboxFile: inboxFile,
            checkpointsFile: appSupportDirectory.appendingPathComponent("checkpoints.json", isDirectory: false),
            handoffsFile: appSupportDirectory.appendingPathComponent("handoffs.json", isDirectory: false),
            reviewsFile: appSupportDirectory.appendingPathComponent("reviews.json", isDirectory: false),
            approvalsFile: appSupportDirectory.appendingPathComponent("approvals.json", isDirectory: false),
            queueFile: appSupportDirectory.appendingPathComponent("queue.json", isDirectory: false),
            timelineFile: appSupportDirectory.appendingPathComponent("timeline.json", isDirectory: false),
            layoutFile: appSupportDirectory.appendingPathComponent("layout.json", isDirectory: false),
            agentEventsFile: appSupportDirectory.appendingPathComponent("agent-events.json", isDirectory: false),
            settingsFile: settingsFile,
            runDirectory: runDirectory,
            tempDirectory: tempDirectory,
            worktreesDirectory: worktreesDirectory
        )
    }

    init(fileManager: FileManager = .default) throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        appSupportDirectory = appSupport.appendingPathComponent("idx0", isDirectory: true)
        sessionsFile = appSupportDirectory.appendingPathComponent("sessions.json", isDirectory: false)
        projectsFile = appSupportDirectory.appendingPathComponent("projects.json", isDirectory: false)
        inboxFile = appSupportDirectory.appendingPathComponent("inbox.json", isDirectory: false)
        checkpointsFile = appSupportDirectory.appendingPathComponent("checkpoints.json", isDirectory: false)
        handoffsFile = appSupportDirectory.appendingPathComponent("handoffs.json", isDirectory: false)
        reviewsFile = appSupportDirectory.appendingPathComponent("reviews.json", isDirectory: false)
        approvalsFile = appSupportDirectory.appendingPathComponent("approvals.json", isDirectory: false)
        queueFile = appSupportDirectory.appendingPathComponent("queue.json", isDirectory: false)
        timelineFile = appSupportDirectory.appendingPathComponent("timeline.json", isDirectory: false)
        layoutFile = appSupportDirectory.appendingPathComponent("layout.json", isDirectory: false)
        agentEventsFile = appSupportDirectory.appendingPathComponent("agent-events.json", isDirectory: false)
        settingsFile = appSupportDirectory.appendingPathComponent("settings.json", isDirectory: false)
        runDirectory = appSupportDirectory.appendingPathComponent("run", isDirectory: true)
        tempDirectory = appSupportDirectory.appendingPathComponent("temp", isDirectory: true)
        worktreesDirectory = appSupportDirectory.appendingPathComponent("worktrees", isDirectory: true)
    }

    func ensureDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
}
