import Foundation
import XCTest

@testable import NexusCore

final class ProjectionSchemaMigrationTests: XCTestCase {
    func testV1DatabaseMigratesToV4WithoutLosingTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("Nexus.sqlite")
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(
            """
            CREATE TABLE tasks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                goal TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'active',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                archived_at TEXT
            );
            """
        )
        try database.execute(
            "INSERT INTO tasks(id, title, goal, status, created_at, updated_at) VALUES ('legacy', 'Legacy work', 'Keep me', 'active', '2026-01-01', '2026-01-01');"
        )
        try database.execute("PRAGMA user_version = 1;")

        let store = ProjectionStore(databaseURL: databaseURL)
        try store.bootstrap()

        XCTAssertEqual(try store.listTasks().map(\.id), ["legacy"])
        let migrated = try SQLiteDatabase(url: databaseURL)
        XCTAssertEqual(try migrated.queryOne("PRAGMA user_version;")?["user_version"], "4")
        XCTAssertEqual(
            try migrated.queryOne("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'context_packs';")?[
                "name"],
            "context_packs"
        )
        XCTAssertEqual(
            try migrated.queryOne("SELECT value FROM metadata WHERE key = 'projection_schema_version';")?["value"],
            "2"
        )
        XCTAssertEqual(
            try migrated.queryOne(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'context_pack_git_baselines';"
            )?["name"],
            "context_pack_git_baselines"
        )
    }

    func testV2RepositoryTableReceivesGitAnchorColumns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("Nexus.sqlite")
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(
            """
            CREATE TABLE tasks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                goal TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'active',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                archived_at TEXT
            );
            """
        )
        try database.execute(
            """
            CREATE TABLE task_repositories (
                task_id TEXT PRIMARY KEY,
                path TEXT NOT NULL,
                branch TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
        )
        try database.execute("PRAGMA user_version = 2;")

        let store = ProjectionStore(databaseURL: databaseURL)
        try store.bootstrap()

        let migrated = try SQLiteDatabase(url: databaseURL)
        let columns = try migrated.queryAll("PRAGMA table_info(task_repositories);").compactMap { $0["name"] }
        XCTAssertTrue(columns.contains("anchor_head_sha"))
        XCTAssertTrue(columns.contains("anchor_branch"))
        XCTAssertTrue(columns.contains("anchor_captured_at"))
        XCTAssertTrue(columns.contains("workspace_origin"))
        XCTAssertTrue(columns.contains("base_ref"))
        XCTAssertTrue(columns.contains("created_head_sha"))
        XCTAssertEqual(try migrated.queryOne("PRAGMA user_version;")?["user_version"], "4")
    }

    func testStoreMigratesOnlyOnceAcrossRepeatedOperations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectionStore(databaseURL: directory.appendingPathComponent("Nexus.sqlite"))

        try store.bootstrap()
        _ = try store.createTask(title: "One", goal: "")
        _ = try store.listTasks()
        _ = try store.activeTask()

        XCTAssertEqual(store.schemaMigrationCount, 1)
    }

    func testConcurrentWritesRemainSerialized() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectionStore(databaseURL: directory.appendingPathComponent("Nexus.sqlite"))
        try store.bootstrap()

        let errors = LockedErrors()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do {
                _ = try store.createTask(title: "Work \(index)", goal: "")
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.values.isEmpty, "\(errors.values)")
        XCTAssertEqual(try store.listTasks().count, 12)
        XCTAssertEqual(store.schemaMigrationCount, 1)
    }
}

private final class LockedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.withLock { storage }
    }

    func append(_ error: Error) {
        lock.withLock {
            storage.append(error)
        }
    }
}
