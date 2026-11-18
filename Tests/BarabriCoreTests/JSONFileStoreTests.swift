import XCTest
@testable import BarabriCore

final class JSONFileStoreTests: XCTestCase {
    private var createdURLs: [URL] = []
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let ali = ParticipantID("ali")
    private let ahmed = ParticipantID("ahmed")

    override func tearDown() {
        for url in createdURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdURLs.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        createdURLs.append(url)
        return url
    }

    private func makeGroup() -> ExpenseGroup {
        ExpenseGroup(name: "Trip", members: [Member(id: ali, name: "Ali")])
    }

    private func makeSharedRecord(
        groupID: UUID,
        total: Decimal,
        allocations: Allocations
    ) throws -> SharedExpenseRecord {
        let expense = try Expense(total: total, payer: ali, allocations: allocations)
        return try SharedExpenseRecord(
            groupID: groupID,
            title: "Dinner",
            expense: expense,
            recordedAt: fixedDate
        )
    }

    // MARK: - Empty and durable reads

    func testMissingFileReadsAsEmptyCurrentVersionDocument() async throws {
        let store = JSONFileStore(fileURL: makeFileURL())

        let document = try await store.read()

        XCTAssertEqual(document, StoreDocument())
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.schemaVersion, StoreDocument.currentSchemaVersion)
        XCTAssertTrue(document.groups.isEmpty)
        XCTAssertTrue(document.budgets.isEmpty)
        XCTAssertTrue(document.personalExpenses.isEmpty)
        XCTAssertTrue(document.sharedExpenses.isEmpty)
        XCTAssertTrue(document.settlements.isEmpty)
    }

    func testUpdatedGroupIsReturnedByReadOnSameStore() async throws {
        let store = JSONFileStore(fileURL: makeFileURL())
        let group = makeGroup()

        try await store.update { $0.groups.append(group) }
        let document = try await store.read()

        XCTAssertEqual(document.groups, [group])
    }

    func testSecondStoreOnSameURLReadsPersistedData() async throws {
        let url = makeFileURL()
        let group = makeGroup()
        let writer = JSONFileStore(fileURL: url)

        try await writer.update { $0.groups.append(group) }
        let reader = JSONFileStore(fileURL: url)
        let document = try await reader.read()

        XCTAssertEqual(document.groups, [group])
        XCTAssertEqual(document.schemaVersion, 1)
    }

    // MARK: - Update return value

    func testUpdateReturnsValueProducedByClosure() async throws {
        let store = JSONFileStore(fileURL: makeFileURL())
        let group = makeGroup()

        let count = try await store.update { document -> Int in
            document.groups.append(group)
            return document.groups.count
        }

        XCTAssertEqual(count, 1)
    }

    // MARK: - Rollback on failure

    func testThrowingChangeKeepsOldDocumentAndPropagatesError() async throws {
        let store = JSONFileStore(fileURL: makeFileURL())
        let kept = makeGroup()
        try await store.update { $0.groups.append(kept) }

        let rejected = ExpenseGroup(name: "Rejected")
        do {
            try await store.update { (document: inout StoreDocument) throws in
                document.groups.append(rejected)
                throw BarabriError.invalidAmount
            }
            XCTFail("expected the closure's error to propagate")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }

        let document = try await store.read()
        XCTAssertEqual(document.groups, [kept])
    }

    func testFailedChangeIsNotVisibleToSecondStoreOnSameURL() async throws {
        let url = makeFileURL()
        let kept = makeGroup()
        let writer = JSONFileStore(fileURL: url)
        try await writer.update { $0.groups.append(kept) }

        let rejected = ExpenseGroup(name: "Rejected")
        do {
            try await writer.update { (document: inout StoreDocument) throws in
                document.groups.append(rejected)
                throw BarabriError.invalidAmount
            }
            XCTFail("expected the closure's error to propagate")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }

        let reader = JSONFileStore(fileURL: url)
        let document = try await reader.read()
        XCTAssertEqual(document.groups, [kept])
    }

    // MARK: - Corrupt and incompatible files

    func testInvalidJSONFileMakesReadThrowPersistenceFailure() async throws {
        let url = makeFileURL()
        try Data("not json".utf8).write(to: url)
        let store = JSONFileStore(fileURL: url)

        do {
            _ = try await store.read()
            XCTFail("expected a persistence failure")
        } catch {
            guard case .persistenceFailure = error as? BarabriError else {
                return XCTFail("expected persistenceFailure, got \(error)")
            }
        }
    }

    func testUnsupportedSchemaVersionMakesReadThrowPersistenceFailure() async throws {
        let url = makeFileURL()
        var future = StoreDocument()
        future.schemaVersion = 99
        try JSONEncoder().encode(future).write(to: url)
        let store = JSONFileStore(fileURL: url)

        do {
            _ = try await store.read()
            XCTFail("expected a persistence failure")
        } catch {
            guard case .persistenceFailure = error as? BarabriError else {
                return XCTFail("expected persistenceFailure, got \(error)")
            }
        }
    }

    // MARK: - In-memory store

    func testInMemoryStoreKeepsDataAcrossUpdateAndRead() async throws {
        let store = JSONFileStore(fileURL: nil)
        let group = makeGroup()

        try await store.update { $0.groups.append(group) }
        let document = try await store.read()

        XCTAssertEqual(document.groups, [group])
        XCTAssertEqual(document.schemaVersion, 1)
    }

    // MARK: - Money precision

    func testMoneyAmountsSurviveRoundTripExactly() async throws {
        let url = makeFileURL()
        let group = makeGroup()
        let record = try makeSharedRecord(
            groupID: group.id,
            total: Decimal(string: "3000.10")!,
            allocations: [
                ali: Decimal(string: "1000.05")!,
                ahmed: Decimal(string: "2000.05")!
            ]
        )
        try await JSONFileStore(fileURL: url).update { document in
            document.groups.append(group)
            document.sharedExpenses.append(record)
        }

        let document = try await JSONFileStore(fileURL: url).read()

        let stored = try XCTUnwrap(document.sharedExpenses.first)
        XCTAssertEqual(stored, record)
        XCTAssertEqual(stored.total.amount, Decimal(string: "3000.10")!)
    }
}
