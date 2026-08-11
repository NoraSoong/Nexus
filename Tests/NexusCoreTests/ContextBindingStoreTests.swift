import Foundation
import XCTest

@testable import NexusCore

final class ContextBindingStoreTests: XCTestCase {
    func testWorkspaceBindingsRemainPinnedWhenGlobalWorkChanges() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let taskA = try fixture.store.createTask(title: "Requirement A", goal: "Implement A")
        let taskB = try fixture.store.createTask(title: "Requirement B", goal: "Implement B")
        let workspaceA = try fixture.makeWorkspace("worktree-a")
        let workspaceB = try fixture.makeWorkspace("worktree-b")

        try fixture.store.setRepository(taskID: taskA.id, path: workspaceA.path)
        try fixture.store.setRepository(taskID: taskB.id, path: workspaceB.path)
        let initialA = try XCTUnwrap(fixture.store.workspaceBinding(path: workspaceA.path))
        let initialB = try XCTUnwrap(fixture.store.workspaceBinding(path: workspaceB.path))

        try fixture.store.switchTask(taskID: taskA.id)
        try fixture.store.switchTask(taskID: taskB.id)

        let currentA = try XCTUnwrap(fixture.store.workspaceBinding(path: workspaceA.path))
        let currentB = try XCTUnwrap(fixture.store.workspaceBinding(path: workspaceB.path))
        XCTAssertEqual(currentA.id, initialA.id)
        XCTAssertEqual(currentA.taskID, taskA.id)
        XCTAssertEqual(currentB.id, initialB.id)
        XCTAssertEqual(currentB.taskID, taskB.id)
        XCTAssertEqual(try fixture.store.activeTask()?.taskID, taskB.id)
    }

    func testUpdatingOneBoundWorkOnlyAdvancesItsBindings() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let taskA = try fixture.store.createTask(title: "Requirement A", goal: "Implement A")
        let taskB = try fixture.store.createTask(title: "Requirement B", goal: "Implement B")
        let workspaceA = try fixture.makeWorkspace("worktree-a")
        let workspaceB = try fixture.makeWorkspace("worktree-b")
        try fixture.store.setRepository(taskID: taskA.id, path: workspaceA.path)
        try fixture.store.setRepository(taskID: taskB.id, path: workspaceB.path)
        try fixture.store.switchTask(taskID: taskB.id)

        let beforeA = try XCTUnwrap(fixture.store.workspaceBinding(taskID: taskA.id))
        let beforeB = try XCTUnwrap(fixture.store.workspaceBinding(taskID: taskB.id))
        try fixture.store.updateTask(id: taskA.id, title: "Requirement A updated", goal: taskA.goal)
        let afterA = try XCTUnwrap(fixture.store.workspaceBinding(taskID: taskA.id))
        let afterB = try XCTUnwrap(fixture.store.workspaceBinding(taskID: taskB.id))

        XCTAssertGreaterThan(afterA.activeRevision, beforeA.activeRevision)
        XCTAssertEqual(afterB.activeRevision, beforeB.activeRevision)
        XCTAssertEqual(try fixture.store.activeTask()?.taskID, taskB.id)
        let projection = try XCTUnwrap(fixture.store.projectionSnapshot(taskID: taskA.id))
        XCTAssertTrue(projection.activeTaskJSON.contains("Requirement A updated"))
    }

    func testArchivingWorkRemovesItsWorkspaceBinding() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(title: "Requirement", goal: "Implement it")
        let workspace = try fixture.makeWorkspace("worktree")
        try fixture.store.setRepository(taskID: task.id, path: workspace.path)
        XCTAssertNotNil(try fixture.store.workspaceBinding(path: workspace.path))

        try fixture.store.archiveTask(id: task.id)

        XCTAssertNil(try fixture.store.workspaceBinding(path: workspace.path))

        try fixture.store.restoreTask(id: task.id)

        XCTAssertEqual(
            try fixture.store.workspaceBinding(path: workspace.path)?.taskID,
            task.id
        )
    }

    func testGitWorktreesShareProjectIdentity() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = try fixture.makeWorkspace("repository", initializeGit: false)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "Nexus Test"], at: repository)
        try runGit(["config", "user.email", "nexus-test@example.invalid"], at: repository)
        try "fixture".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], at: repository)
        try runGit(["commit", "-m", "Initial fixture"], at: repository)
        let worktree = fixture.directory.appendingPathComponent("requirement-a", isDirectory: true)
        try runGit(["worktree", "add", "-b", "requirement-a", worktree.path], at: repository)

        let mainInfo = try XCTUnwrap(fixture.store.gitWorkspaceInfo(at: repository.path))
        let worktreeInfo = try XCTUnwrap(fixture.store.gitWorkspaceInfo(at: worktree.path))

        XCTAssertEqual(mainInfo.kind, "main")
        XCTAssertEqual(worktreeInfo.kind, "worktree")
        XCTAssertEqual(mainInfo.commonDirectory, worktreeInfo.commonDirectory)
        XCTAssertEqual(mainInfo.repositoryRoot, worktreeInfo.repositoryRoot)
        XCTAssertEqual(worktreeInfo.branch, "requirement-a")

        let discovered = fixture.store.gitWorktrees(at: repository.path)
        XCTAssertEqual(Set(discovered.map(\.path)), Set([repository.path, worktree.path]))
        XCTAssertEqual(Set(discovered.map(\.branch)), Set(["main", "requirement-a"]))
    }

    func testCreatingWorkFromWorkspaceIsAtomicAndBound() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = try fixture.makeWorkspace("repository", initializeGit: false)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "Nexus Test"], at: repository)
        try runGit(["config", "user.email", "nexus-test@example.invalid"], at: repository)
        try "fixture".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], at: repository)
        try runGit(["commit", "-m", "Initial fixture"], at: repository)
        let worktree = fixture.directory.appendingPathComponent("requirement-a", isDirectory: true)
        try runGit(["worktree", "add", "-b", "requirement-a", worktree.path], at: repository)

        let task = try fixture.store.createTask(
            title: "Requirement A",
            goal: "",
            workspacePath: worktree.path
        )

        XCTAssertEqual(try fixture.store.repository(taskID: task.id)?.path, worktree.path)
        XCTAssertEqual(try fixture.store.workspaceBinding(path: worktree.path)?.taskID, task.id)
        let projection = try XCTUnwrap(fixture.store.projectionSnapshot(taskID: task.id))
        XCTAssertTrue(projection.manifestJSON.contains("\"workspace_activity\""))
        XCTAssertTrue(projection.manifestJSON.contains("\"provenance\":\"derived_from_git\""))
        XCTAssertFalse(projection.manifestJSON.contains("committed_diff"))
        XCTAssertFalse(projection.manifestJSON.contains("uncommitted_diff"))
        XCTAssertThrowsError(
            try fixture.store.createTask(
                title: "Duplicate",
                goal: "",
                workspacePath: worktree.path
            )
        )
        XCTAssertEqual(try fixture.store.listTasks().count, 1)

        let other = try fixture.store.createTask(title: "Existing Work", goal: "")
        XCTAssertThrowsError(
            try fixture.store.setRepository(taskID: other.id, path: worktree.path)
        )
        XCTAssertNil(try fixture.store.repository(taskID: other.id))
        XCTAssertEqual(try fixture.store.workspaceBinding(path: worktree.path)?.taskID, task.id)
    }

    func testWorkspaceAssociationReportsActionableReasons() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let task = try fixture.store.createTask(title: "Requirement", goal: "")
        let otherTask = try fixture.store.createTask(title: "Other", goal: "")
        let workspace = try fixture.makeWorkspace("workspace")
        let plainDirectory = try fixture.makeWorkspace("plain", initializeGit: false)
        let missingPath = fixture.directory.appendingPathComponent("missing").path

        XCTAssertThrowsError(try fixture.store.setRepository(taskID: task.id, path: plainDirectory.path)) { error in
            XCTAssertEqual(error as? WorkspaceAssociationError, .notGitWorkspace(plainDirectory.path))
        }
        XCTAssertThrowsError(try fixture.store.setRepository(taskID: task.id, path: missingPath)) {
            error in
            XCTAssertEqual(
                error as? WorkspaceAssociationError,
                .pathUnavailable(missingPath)
            )
        }

        try fixture.store.setRepository(taskID: task.id, path: workspace.path)
        try fixture.store.setRepository(taskID: task.id, path: workspace.path)
        XCTAssertThrowsError(try fixture.store.setRepository(taskID: otherTask.id, path: workspace.path)) { error in
            XCTAssertEqual(
                error as? WorkspaceAssociationError,
                .alreadyBound(path: workspace.path, taskID: task.id)
            )
        }
        XCTAssertEqual(try fixture.store.workspaceBinding(path: workspace.path)?.taskID, task.id)
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProjectionStore(databaseURL: directory.appendingPathComponent("Nexus.sqlite"))
        try store.bootstrap()
        return Fixture(store: store, directory: directory)
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = Pipe()
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            throw NSError(
                domain: "ContextBindingStoreTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "git failed"]
            )
        }
    }

    private struct Fixture {
        let store: ProjectionStore
        let directory: URL

        func makeWorkspace(_ name: String, initializeGit: Bool = true) throws -> URL {
            let url = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if initializeGit {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["-C", url.path, "init", "-q", "-b", "main"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(
                        domain: "ContextBindingStoreTests",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "git init failed"]
                    )
                }
            }
            return url
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
