import XCTest
@testable import BarabriCore

final class JSONRepositoriesTests: XCTestCase {
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

    private func makeGroup(id: UUID = UUID(), name: String = "Trip") -> ExpenseGroup {
        ExpenseGroup(id: id, name: name, members: [Member(id: ali, name: "Ali")])
    }

    private func makeBudget(id: UUID = UUID(), name: String = "May") throws -> Budget {
        Budget(id: id, name: name, limit: try Money(Decimal(string: "25000.50")!))
    }

    private func makePersonalExpense(budgetID: UUID, title: String) throws -> PersonalExpense {
        PersonalExpense(
            budgetID: budgetID,
            title: title,
            amount: try Money(Decimal(string: "120.25")!),
            recordedAt: fixedDate
        )
    }

    private func makeSharedRecord(
        id: UUID = UUID(),
        groupID: UUID,
        title: String = "Dinner"
    ) throws -> SharedExpenseRecord {
        let expense = try Expense(
            total: Decimal(string: "3000.10")!,
            payer: ali,
            allocations: [
                ali: Decimal(string: "1000.05")!,
                ahmed: Decimal(string: "2000.05")!,
            ]
        )
        return try SharedExpenseRecord(
            id: id,
            groupID: groupID,
            title: title,
            expense: expense,
            recordedAt: fixedDate
        )
    }

    private func makeSettlement(
        id: UUID = UUID(),
        groupID: UUID,
        status: SettlementStatus = .completed
    ) throws -> Settlement {
        Settlement(
            id: id,
            groupID: groupID,
            from: ahmed,
            to: ali,
            amount: try Money(Decimal(string: "500.75")!),
            method: .easypaisa,
            status: status,
            recordedAt: fixedDate
        )
    }

    // MARK: - Group repository

    func testGroupRepositorySavesAndFindsGroupById() async throws {
        let repository = JSONGroupRepository(store: JSONFileStore(fileURL: nil))
        let group = makeGroup()

        try await repository.save(group)
        let found = try await repository.group(id: group.id)

        XCTAssertEqual(found, group)
    }

    func testGroupRepositoryReturnsAllGroups() async throws {
        let repository = JSONGroupRepository(store: JSONFileStore(fileURL: nil))
        let first = makeGroup(name: "Trip")
        let second = makeGroup(name: "Flat")

        try await repository.save(first)
        try await repository.save(second)
        let all = try await repository.groups()

        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(first))
        XCTAssertTrue(all.contains(second))
    }

    func testSavingGroupWithSameIdReplacesIt() async throws {
        let repository = JSONGroupRepository(store: JSONFileStore(fileURL: nil))
        let id = UUID()
        try await repository.save(makeGroup(id: id, name: "Trip"))

        try await repository.save(makeGroup(id: id, name: "Trip renamed"))
        let all = try await repository.groups()
        let found = try await repository.group(id: id)

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(found?.name, "Trip renamed")
    }

    func testUnknownGroupIdReturnsNil() async throws {
        let repository = JSONGroupRepository(store: JSONFileStore(fileURL: nil))
        try await repository.save(makeGroup())

        let found = try await repository.group(id: UUID())

        XCTAssertNil(found)
    }

    // MARK: - Budget repository

    func testBudgetRepositorySavesAndFindsBudgetById() async throws {
        let repository = JSONBudgetRepository(store: JSONFileStore(fileURL: nil))
        let budget = try makeBudget()

        try await repository.save(budget)
        let found = try await repository.budget(id: budget.id)
        let all = try await repository.budgets()

        XCTAssertEqual(found, budget)
        XCTAssertEqual(all, [budget])
    }

    func testSavingBudgetWithSameIdReplacesIt() async throws {
        let repository = JSONBudgetRepository(store: JSONFileStore(fileURL: nil))
        let id = UUID()
        try await repository.save(try makeBudget(id: id, name: "May"))

        try await repository.save(try makeBudget(id: id, name: "June"))
        let all = try await repository.budgets()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "June")
    }

    func testPersonalExpensesAreFilteredByBudget() async throws {
        let repository = JSONBudgetRepository(store: JSONFileStore(fileURL: nil))
        let mayID = UUID()
        let juneID = UUID()
        let mayLunch = try makePersonalExpense(budgetID: mayID, title: "Lunch")
        let mayTaxi = try makePersonalExpense(budgetID: mayID, title: "Taxi")
        let juneRent = try makePersonalExpense(budgetID: juneID, title: "Rent")
        try await repository.save(mayLunch)
        try await repository.save(mayTaxi)
        try await repository.save(juneRent)

        let mayExpenses = try await repository.personalExpenses(inBudget: mayID)

        XCTAssertEqual(mayExpenses.count, 2)
        XCTAssertTrue(mayExpenses.contains(mayLunch))
        XCTAssertTrue(mayExpenses.contains(mayTaxi))
        XCTAssertFalse(mayExpenses.contains(juneRent))
    }

    func testAllPersonalExpensesReturnsExpensesFromEveryBudget() async throws {
        let repository = JSONBudgetRepository(store: JSONFileStore(fileURL: nil))
        let lunch = try makePersonalExpense(budgetID: UUID(), title: "Lunch")
        let rent = try makePersonalExpense(budgetID: UUID(), title: "Rent")
        try await repository.save(lunch)
        try await repository.save(rent)

        let all = try await repository.allPersonalExpenses()

        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(lunch))
        XCTAssertTrue(all.contains(rent))
    }

    // MARK: - Expense repository

    func testSharedExpenseIsSavedAndReturnedForItsGroupOnly() async throws {
        let repository = JSONExpenseRepository(store: JSONFileStore(fileURL: nil))
        let groupID = UUID()
        let otherGroupID = UUID()
        let dinner = try makeSharedRecord(groupID: groupID, title: "Dinner")
        let taxi = try makeSharedRecord(groupID: otherGroupID, title: "Taxi")
        try await repository.save(dinner)
        try await repository.save(taxi)

        let inGroup = try await repository.sharedExpenses(inGroup: groupID)

        XCTAssertEqual(inGroup, [dinner])
    }

    func testAllSharedExpensesReturnsEveryGroup() async throws {
        let repository = JSONExpenseRepository(store: JSONFileStore(fileURL: nil))
        let dinner = try makeSharedRecord(groupID: UUID(), title: "Dinner")
        let taxi = try makeSharedRecord(groupID: UUID(), title: "Taxi")
        try await repository.save(dinner)
        try await repository.save(taxi)

        let all = try await repository.allSharedExpenses()

        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(dinner))
        XCTAssertTrue(all.contains(taxi))
    }

    func testSavingSharedExpenseWithSameIdReplacesIt() async throws {
        let repository = JSONExpenseRepository(store: JSONFileStore(fileURL: nil))
        let groupID = UUID()
        let id = UUID()
        try await repository.save(try makeSharedRecord(id: id, groupID: groupID, title: "Dinner"))

        try await repository.save(try makeSharedRecord(id: id, groupID: groupID, title: "Dinner (corrected)"))
        let all = try await repository.allSharedExpenses()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Dinner (corrected)")
    }

    // MARK: - Settlement repository

    func testSettlementIsSavedAndReturnedForItsGroupOnly() async throws {
        let repository = JSONSettlementRepository(store: JSONFileStore(fileURL: nil))
        let groupID = UUID()
        let otherGroupID = UUID()
        let payment = try makeSettlement(groupID: groupID)
        let elsewhere = try makeSettlement(groupID: otherGroupID)
        try await repository.save(payment)
        try await repository.save(elsewhere)

        let inGroup = try await repository.settlements(inGroup: groupID)

        XCTAssertEqual(inGroup, [payment])
    }

    func testAllSettlementsReturnsEveryGroup() async throws {
        let repository = JSONSettlementRepository(store: JSONFileStore(fileURL: nil))
        let payment = try makeSettlement(groupID: UUID())
        let elsewhere = try makeSettlement(groupID: UUID())
        try await repository.save(payment)
        try await repository.save(elsewhere)

        let all = try await repository.allSettlements()

        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(payment))
        XCTAssertTrue(all.contains(elsewhere))
    }

    func testSavingSettlementWithSameIdReplacesItsStatus() async throws {
        let repository = JSONSettlementRepository(store: JSONFileStore(fileURL: nil))
        let groupID = UUID()
        let id = UUID()
        try await repository.save(try makeSettlement(id: id, groupID: groupID, status: .pending))

        try await repository.save(try makeSettlement(id: id, groupID: groupID, status: .completed))
        let all = try await repository.allSettlements()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .completed)
    }

    // MARK: - Shared store

    func testRepositoriesSharingOneStoreSeeOneDocument() async throws {
        let store = JSONFileStore(fileURL: nil)
        let groups = JSONGroupRepository(store: store)
        let budgets = JSONBudgetRepository(store: store)
        let group = makeGroup()
        let budget = try makeBudget()

        try await groups.save(group)
        try await budgets.save(budget)
        let document = try await store.read()

        XCTAssertEqual(document.groups, [group])
        XCTAssertEqual(document.budgets, [budget])
    }

    // MARK: - Durability

    func testSavedValueIsReadableByNewStoreAndRepositoryOnSameFile() async throws {
        let url = makeFileURL()
        let group = makeGroup()
        try await JSONGroupRepository(store: JSONFileStore(fileURL: url)).save(group)

        let reopened = JSONGroupRepository(store: JSONFileStore(fileURL: url))
        let found = try await reopened.group(id: group.id)

        XCTAssertEqual(found, group)
    }
}
