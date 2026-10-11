import SwiftUI

@main
struct BarabriApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
    }
}

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Personal budgeting") {
                    SummaryRow(title: "Cash available", value: "Rs. 0")
                    SummaryRow(title: "Budget remaining", value: "Rs. 0")
                    SummaryRow(title: "Personal spending", value: "Rs. 0")
                }

                Section("Group expenses") {
                    SummaryRow(title: "People owe you", value: "Rs. 0")
                    SummaryRow(title: "You owe others", value: "Rs. 0")
                }
            }
            .navigationTitle("Barabri")
        }
    }
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
