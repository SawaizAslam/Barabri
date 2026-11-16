import XCTest
@testable import BarabriCore

final class BalanceEngineNetBalanceTests: XCTestCase {
    private let ali = ParticipantID("ali")
    private let ahmed = ParticipantID("ahmed")
    private let sara = ParticipantID("sara")

    private func settlement(
        from: ParticipantID,
        to: ParticipantID,
        amount: Decimal,
        status: SettlementStatus
    ) throws -> Settlement {
        Settlement(
            groupID: UUID(),
            from: from,
            to: to,
            amount: try Money(amount),
            method: .cash,
            status: status
        )
    }

    // 1. Payer's perspective on the anchor expense.
    func testPayerSeesFullCashOutAndReceivableFromOthers() throws {
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])

        let result = BalanceEngine().calculate(for: ali, expenses: [expense])

        XCTAssertEqual(result.cashChange, -3000)
        XCTAssertEqual(result.personalExpense, 1000)
        XCTAssertEqual(result.receivables, [ahmed: 2000])
        XCTAssertEqual(result.payables, [:])
    }

    // 2. Same anchor expense from the non-payer's side.
    func testNonPayerSeesPayableToPayer() throws {
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])

        let result = BalanceEngine().calculate(for: ahmed, expenses: [expense])

        XCTAssertEqual(result.cashChange, 0)
        XCTAssertEqual(result.personalExpense, 2000)
        XCTAssertEqual(result.receivables, [:])
        XCTAssertEqual(result.payables, [ali: 2000])
    }

    // 3. Debts in both directions offset each other.
    func testOpposingDebtsOffsetAgainstEachOther() throws {
        let first = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        let second = try Expense(total: 1000, payer: ahmed, allocations: [ali: 500, ahmed: 500])
        let expenses = [first, second]

        let engine = BalanceEngine()
        XCTAssertEqual(
            engine.obligations(expenses: expenses),
            [Obligation(debtor: ahmed, creditor: ali, amount: 1500)]
        )

        let aliResult = engine.calculate(for: ali, expenses: expenses)
        XCTAssertEqual(aliResult.cashChange, -3000)
        XCTAssertEqual(aliResult.personalExpense, 1500)
        XCTAssertEqual(aliResult.receivables, [ahmed: 1500])
        XCTAssertEqual(aliResult.payables, [:])

        let ahmedResult = engine.calculate(for: ahmed, expenses: expenses)
        XCTAssertEqual(ahmedResult.cashChange, -1000)
        XCTAssertEqual(ahmedResult.personalExpense, 2500)
        XCTAssertEqual(ahmedResult.receivables, [:])
        XCTAssertEqual(ahmedResult.payables, [ali: 1500])
    }

    // 4. Three people splitting one payment equally.
    func testThreePersonEqualSplitCreatesTwoObligationsToPayer() throws {
        let expense = try Expense(
            total: 3000,
            payer: ali,
            allocations: [ali: 1000, ahmed: 1000, sara: 1000]
        )

        let engine = BalanceEngine()
        XCTAssertEqual(
            engine.obligations(expenses: [expense]),
            [
                Obligation(debtor: ahmed, creditor: ali, amount: 1000),
                Obligation(debtor: sara, creditor: ali, amount: 1000),
            ]
        )

        let result = engine.calculate(for: ali, expenses: [expense])
        XCTAssertEqual(result.receivables, [ahmed: 1000, sara: 1000])
    }

    // 5. A participant who is both a creditor and a debtor.
    func testParticipantCanBeBothCreditorAndDebtor() throws {
        let first = try Expense(
            total: 900,
            payer: ali,
            allocations: [ali: 300, ahmed: 300, sara: 300]
        )
        let second = try Expense(total: 600, payer: sara, allocations: [sara: 300, ahmed: 300])
        let expenses = [first, second]

        let engine = BalanceEngine()

        let ahmedResult = engine.calculate(for: ahmed, expenses: expenses)
        XCTAssertEqual(ahmedResult.payables, [ali: 300, sara: 300])
        XCTAssertEqual(ahmedResult.receivables, [:])

        let saraResult = engine.calculate(for: sara, expenses: expenses)
        XCTAssertEqual(saraResult.payables, [ali: 300])
        XCTAssertEqual(saraResult.receivables, [ahmed: 300])
    }

    // 6. A completed partial settlement reduces the obligation.
    func testCompletedSettlementReducesObligation() throws {
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        let payment = try settlement(from: ahmed, to: ali, amount: 500, status: .completed)
        let expenses = [expense]
        let settlements = [payment]

        let engine = BalanceEngine()
        XCTAssertEqual(
            engine.obligations(expenses: expenses, settlements: settlements),
            [Obligation(debtor: ahmed, creditor: ali, amount: 1500)]
        )

        let aliResult = engine.calculate(for: ali, expenses: expenses, settlements: settlements)
        XCTAssertEqual(aliResult.cashChange, -2500)
        XCTAssertEqual(aliResult.personalExpense, 1000)
        XCTAssertEqual(aliResult.receivables, [ahmed: 1500])

        let ahmedResult = engine.calculate(for: ahmed, expenses: expenses, settlements: settlements)
        XCTAssertEqual(ahmedResult.cashChange, -500)
        XCTAssertEqual(ahmedResult.personalExpense, 2000)
        XCTAssertEqual(ahmedResult.payables, [ali: 1500])
    }

    // 7. A completed settlement for the full amount clears the obligation.
    func testFullSettlementClearsObligation() throws {
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        let payment = try settlement(from: ahmed, to: ali, amount: 2000, status: .completed)
        let expenses = [expense]
        let settlements = [payment]

        let engine = BalanceEngine()
        XCTAssertEqual(engine.obligations(expenses: expenses, settlements: settlements), [])

        let aliResult = engine.calculate(for: ali, expenses: expenses, settlements: settlements)
        XCTAssertEqual(aliResult.receivables, [:])

        let ahmedResult = engine.calculate(for: ahmed, expenses: expenses, settlements: settlements)
        XCTAssertEqual(ahmedResult.payables, [:])
    }

    // 8. Pending settlements do not change balances.
    func testPendingSettlementIsIgnored() throws {
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        let payment = try settlement(from: ahmed, to: ali, amount: 500, status: .pending)
        let expenses = [expense]
        let settlements = [payment]

        let engine = BalanceEngine()
        XCTAssertEqual(
            engine.obligations(expenses: expenses, settlements: settlements),
            [Obligation(debtor: ahmed, creditor: ali, amount: 2000)]
        )

        let aliResult = engine.calculate(for: ali, expenses: expenses, settlements: settlements)
        XCTAssertEqual(aliResult.cashChange, -3000)
    }

    // 9. Outstanding amount is directional.
    func testOutstandingIsDirectional() throws {
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        let engine = BalanceEngine()

        XCTAssertEqual(
            engine.outstanding(from: ahmed, to: ali, expenses: [expense]),
            2000
        )
        XCTAssertEqual(
            engine.outstanding(from: ali, to: ahmed, expenses: [expense]),
            0
        )
    }

    // 10. No expenses yields empty results.
    func testNoExpensesYieldsEmptyResults() {
        let engine = BalanceEngine()

        XCTAssertEqual(engine.obligations(expenses: []), [])

        let result = engine.calculate(for: ali, expenses: [])
        XCTAssertEqual(result.cashChange, 0)
        XCTAssertEqual(result.personalExpense, 0)
        XCTAssertEqual(result.receivables, [:])
        XCTAssertEqual(result.payables, [:])
    }

    // 11. A participant not involved in any expense gets an empty result.
    func testUninvolvedParticipantGetsEmptyResult() throws {
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])

        let result = BalanceEngine().calculate(for: sara, expenses: [expense])

        XCTAssertEqual(result.cashChange, 0)
        XCTAssertEqual(result.personalExpense, 0)
        XCTAssertEqual(result.receivables, [:])
        XCTAssertEqual(result.payables, [:])
    }

    // 12. A payer whose own share is the whole amount produces no obligations.
    func testPayerWhoOwesNothingProducesNoObligations() throws {
        let expense = try Expense(total: 500, payer: ali, allocations: [ali: 500, ahmed: 0])

        let engine = BalanceEngine()
        XCTAssertEqual(engine.obligations(expenses: [expense]), [])

        let result = engine.calculate(for: ali, expenses: [expense])
        XCTAssertEqual(result.cashChange, -500)
        XCTAssertEqual(result.personalExpense, 500)
        XCTAssertEqual(result.receivables, [:])
        XCTAssertEqual(result.payables, [:])
    }
}
