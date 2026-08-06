import Foundation
import NexusCore

let store = ProjectionStore()

func arg(_ index: Int, default fallback: String = "") -> String {
    let args = Array(CommandLine.arguments.dropFirst())
    return index < args.count ? args[index] : fallback
}

do {
    let command = arg(0, default: "status")
    switch command {
    case "bootstrap":
        try store.bootstrap()
        print("bootstrapped \(NexusPaths.databaseURL.path)")

    case "create-task":
        let title = arg(1, default: "Untitled Task")
        let goal = arg(2, default: "")
        let task = try store.createTask(title: title, goal: goal)
        try store.switchTask(taskID: task.id)
        print("created \(task.id) \(task.title)")

    case "list-tasks":
        try store.bootstrap()
        for task in try store.listTasks() {
            print("\(task.id)\t\(task.title)\t\(task.goal)")
        }

    case "list-archived":
        try store.bootstrap()
        for task in try store.listArchivedTasks() {
            print("\(task.id)\t\(task.title)\t\(task.goal)")
        }

    case "archive-task":
        let taskID = arg(1)
        try store.archiveTask(id: taskID)
        print("archived \(taskID)")

    case "restore-task":
        let taskID = arg(1)
        try store.restoreTask(id: taskID)
        print("restored \(taskID)")

    case "delete-task":
        let taskID = arg(1)
        try store.deleteTask(id: taskID)
        print("deleted \(taskID)")

    case "switch":
        try store.bootstrap()
        let taskID = arg(1, default: "")
        guard try store.listTasks().contains(where: { $0.id == taskID }) else {
            throw NSError(domain: "nexus-debug", code: 1, userInfo: [NSLocalizedDescriptionKey: "task not found"])
        }
        try store.switchTask(taskID: taskID)
        let active = try store.activeTask()
        print("active \(active?.taskID ?? "none") revision \(active?.revision ?? 0)")

    case "add-note":
        let taskID = arg(1)
        let title = arg(2, default: "Note")
        let body = arg(3, default: "")
        let exposed = arg(4, default: "true") != "false"
        let note = try store.addNote(taskID: taskID, title: title, body: body, exposed: exposed)
        print("note \(note.id) exposed=\(note.isExposedToMCP)")

    case "add-file":
        let taskID = arg(1)
        let path = arg(2)
        let visible = arg(3, default: "true") != "false"
        let file = try store.addFile(taskID: taskID, fileURL: URL(fileURLWithPath: path), visibleToAgent: visible)
        print("file \(file.id) \(file.displayName) visible=\(file.isVisibleToAgent)")

    case "list-files":
        let taskID = arg(1)
        for file in try store.listFiles(taskID: taskID) {
            print("\(file.id)\t\(file.displayName)\t\(file.path)\tvisible=\(file.isVisibleToAgent)")
        }

    case "remove-file":
        let taskID = arg(1)
        let fileID = arg(2)
        try store.removeFileReference(id: fileID, taskID: taskID)
        print("removed file reference \(fileID)")

    case "file-visible":
        let taskID = arg(1)
        let fileID = arg(2)
        let visible = arg(3, default: "true") != "false"
        guard let file = try store.listFiles(taskID: taskID).first(where: { $0.id == fileID }) else {
            throw NSError(domain: "nexus-debug", code: 2, userInfo: [NSLocalizedDescriptionKey: "file not found"])
        }
        try store.updateFile(id: file.id, taskID: taskID, displayName: file.displayName, visibleToAgent: visible)
        print("file \(fileID) visible=\(visible)")

    case "repo":
        let taskID = arg(1)
        let path = arg(2)
        try store.setRepository(taskID: taskID, path: path)
        if let repo = try store.repository(taskID: taskID) {
            print("repo \(repo.path) branch=\(repo.branch)")
        }

    case "list-bindings":
        try store.bootstrap()
        for binding in try store.listWorkspaceBindings() {
            print(
                "\(binding.id)\t\(binding.scopeType)\t\(binding.scopeKey)\t\(binding.taskID)\trevision=\(binding.activeRevision)"
            )
        }

    case "workspace-info":
        let path = arg(1)
        guard let info = store.gitWorkspaceInfo(at: path) else {
            throw NSError(
                domain: "nexus-debug",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "not a Git checkout or worktree: \(path)"]
            )
        }
        print(
            "\(info.kind)\t\(info.path)\t\(info.branch)\troot=\(info.repositoryRoot)\tcommon=\(info.commonDirectory)"
        )

    case "supplement":
        let taskID = arg(1)
        let body = arg(2)
        try store.updateSupplement(taskID: taskID, body: body)
        print("supplement saved")

    case "checkpoint":
        let taskID = arg(1)
        let current = arg(2, default: "")
        let next = arg(3, default: "")
        let blockers = arg(4, default: "")
        let checkpoint = try store.saveCheckpoint(
            taskID: taskID, currentState: current, nextStep: next, blockers: blockers)
        print("checkpoint \(checkpoint.id)")

    case "status":
        try store.bootstrap()
        if let active = try store.activeTask() {
            print("active \(active.taskID) \(active.title) revision \(active.revision)")
        } else {
            print("no active task")
        }

    default:
        print(
            """
            usage:
              nexus-debug bootstrap
              nexus-debug status
              nexus-debug list-tasks
              nexus-debug list-archived
              nexus-debug create-task <title> [goal]
              nexus-debug archive-task <task-id>
              nexus-debug restore-task <task-id>
              nexus-debug delete-task <task-id>
              nexus-debug switch <task-id>
              nexus-debug add-note <task-id> <title> <body> [true|false]
              nexus-debug add-file <task-id> <path> [true|false]
              nexus-debug list-files <task-id>
              nexus-debug remove-file <task-id> <file-id>
              nexus-debug file-visible <task-id> <file-id> <true|false>
              nexus-debug repo <task-id> <path>
              nexus-debug list-bindings
              nexus-debug workspace-info <path>
              nexus-debug supplement <task-id> <body>
              nexus-debug checkpoint <task-id> <current> <next> [blockers]
            """
        )
    }
} catch {
    fputs("nexus-debug error: \(error)\n", stderr)
    exit(1)
}
