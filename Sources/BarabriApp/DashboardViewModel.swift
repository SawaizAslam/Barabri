import Combine
import Foundation
import BarabriCore

/// Holds the dashboard figures for SwiftUI. Reads them from the facade through `AppEnvironment`.
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var summary: DashboardSummary?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// On success, replaces `summary` and clears the error. On failure, keeps the previous summary.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await environment.facade.loadSummary()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var budgetRemainingText: String { text(summary.map { $0.budgetRemaining }) }
    var cashChangeText: String { text(summary.map { $0.cashChange }) }
    var personalSpendingText: String { text(summary.map { $0.personalSpending }) }
    var receivablesText: String { text(summary.map { $0.receivables }) }
    var payablesText: String { text(summary.map { $0.payables }) }

    private func text(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return RupeeFormatter.string(from: value)
    }
}
