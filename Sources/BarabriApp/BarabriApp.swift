import SwiftUI

@main
struct BarabriApp: App {
    @State private var environment: AppEnvironment?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            if let environment {
                DashboardView(environment: environment)
            } else if let startupError {
                Text(startupError)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ProgressView("Loading…")
                    .task { await start() }
            }
        }
    }

    private func start() async {
        do {
            environment = try await AppEnvironment.make(fileURL: Self.storeURL())
        } catch {
            startupError = error.localizedDescription
        }
    }

    /// The JSON file in Application Support where all data is kept.
    static func storeURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barabri/barabri.json")
    }
}

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var activeForm: EntryForm?

    init(environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Personal budgeting") {
                    SummaryRow(title: "Cash change (group expenses and settlements)", value: viewModel.cashChangeText)
                    SummaryRow(title: "Budget remaining", value: viewModel.budgetRemainingText)
                    SummaryRow(title: "Personal spending", value: viewModel.personalSpendingText)
                }

                Section("Group expenses") {
                    SummaryRow(title: "People owe you", value: viewModel.receivablesText)
                    SummaryRow(title: "You owe others", value: viewModel.payablesText)
                }

                Section("Add") {
                    Button("Add personal expense") { activeForm = .personalExpense }
                    Button("Add group expense") { activeForm = .groupExpense }
                    Button("Record settlement") { activeForm = .settlement }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Barabri")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $activeForm) { form in
                switch form {
                case .personalExpense:
                    AddPersonalExpenseForm(viewModel: viewModel)
                case .groupExpense:
                    AddGroupExpenseForm(viewModel: viewModel)
                case .settlement:
                    RecordSettlementForm(viewModel: viewModel)
                }
            }
        }
    }
}

private enum EntryForm: String, Identifiable {
    case personalExpense, groupExpense, settlement

    var id: String { rawValue }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
