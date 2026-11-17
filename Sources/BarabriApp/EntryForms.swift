import SwiftUI
import BarabriCore

/// Shows the last rejection reason inside a form, so a rejected entry stays on screen with its reason.
private struct FormErrorRow: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .foregroundStyle(.red)
        }
    }
}

struct AddPersonalExpenseForm: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amountText = ""

    init(viewModel: DashboardViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Amount (Rs.)", text: $amountText)
                FormErrorRow(message: viewModel.errorMessage)
            }
            .navigationTitle("Add personal expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.addPersonalExpense(title: title, amountText: amountText) {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct AddGroupExpenseForm: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amountText = ""
    @State private var payer: ParticipantID
    @State private var selected: Set<ParticipantID>

    init(viewModel: DashboardViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _payer = State(initialValue: viewModel.environment.user)
        _selected = State(initialValue: Set(viewModel.environment.group.members.map(\.id)))
    }

    private var members: [Member] {
        viewModel.environment.group.members
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Amount (Rs.)", text: $amountText)
                Picker("Paid by", selection: $payer) {
                    ForEach(members, id: \.id) { member in
                        Text(member.name).tag(member.id)
                    }
                }
                Section {
                    ForEach(members, id: \.id) { member in
                        Toggle(member.name, isOn: binding(for: member.id))
                    }
                } header: {
                    Text("Split equally between")
                } footer: {
                    Text("Equal split only in this version.")
                }
                FormErrorRow(message: viewModel.errorMessage)
            }
            .navigationTitle("Add group expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let participants = members.map(\.id).filter { selected.contains($0) }
                        Task {
                            let saved = await viewModel.addGroupExpense(
                                title: title,
                                amountText: amountText,
                                payer: payer,
                                participants: participants
                            )
                            if saved {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    private func binding(for id: ParticipantID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn {
                    selected.insert(id)
                } else {
                    selected.remove(id)
                }
            }
        )
    }
}

struct RecordSettlementForm: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var from: ParticipantID
    @State private var to: ParticipantID
    @State private var amountText = ""
    @State private var method: SettlementMethod = .cash

    init(viewModel: DashboardViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        let user = viewModel.environment.user
        let others = viewModel.environment.group.members.map(\.id).filter { $0 != user }
        _from = State(initialValue: user)
        _to = State(initialValue: others.first ?? user)
    }

    private var members: [Member] {
        viewModel.environment.group.members
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("From", selection: $from) {
                    ForEach(members, id: \.id) { member in
                        Text(member.name).tag(member.id)
                    }
                }
                Picker("To", selection: $to) {
                    ForEach(members, id: \.id) { member in
                        Text(member.name).tag(member.id)
                    }
                }
                TextField("Amount (Rs.)", text: $amountText)
                Section {
                    Picker("Method", selection: $method) {
                        ForEach(SettlementMethod.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } footer: {
                    Text("Records a payment made outside the app. No money is moved.")
                }
                FormErrorRow(message: viewModel.errorMessage)
            }
            .navigationTitle("Record settlement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let saved = await viewModel.recordSettlement(
                                from: from,
                                to: to,
                                amountText: amountText,
                                method: method
                            )
                            if saved {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}
