import XCTest
import BarabriCore
@testable import BarabriApp

final class AppEnvironmentTests: XCTestCase {
    func testFreshEnvironmentSeedsBudgetAndFlatmatesGroup() async throws {
        let env = try await AppEnvironment.make(fileURL: nil)

        XCTAssertEqual(env.user, ParticipantID("ali"))
        XCTAssertEqual(env.group.name, "Flatmates")
        XCTAssertEqual(env.group.members.map(\.id.value), ["ali", "ahmed", "sara"])

        let summary = try await env.budgetService.summary(budgetID: env.budgetID)
        XCTAssertEqual(summary.budget.name, "Monthly budget")
        XCTAssertEqual(summary.budget.limit.amount, 50000)
    }

    func testSecondLaunchReusesSeededBudgetAndGroup() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("barabri-env-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = try await AppEnvironment.make(fileURL: fileURL)
        let second = try await AppEnvironment.make(fileURL: fileURL)

        XCTAssertEqual(second.budgetID, first.budgetID)
        XCTAssertEqual(second.group.id, first.group.id)

        let stored = try await JSONFileStore(fileURL: fileURL).read()
        XCTAssertEqual(stored.budgets.count, 1)
        XCTAssertEqual(stored.groups.count, 1)
    }
}
