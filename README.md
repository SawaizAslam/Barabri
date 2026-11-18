# Barabri

Barabri is a native Swift package for personal budgeting and group expense splitting in PKR. On `main`, the implemented code is the core library, `BarabriCore`: split strategies, balance and settlement calculations, validation, and a JSON file store. The SwiftUI app target, `BarabriApp`, is a static placeholder dashboard that is not connected to the services yet.

## Status on main

- **BarabriCore:** implemented and tested. Covers shared expenses in a group, net balances, and settlements.
- **Personal budgeting:** `Budget`, `BudgetCategory` and `PersonalExpense` models and a `BudgetRepository` protocol with a JSON implementation exist. No budget service exists yet.
- **Groups:** the `ExpenseGroup` and `Member` models and `GroupRepository` exist. No service for creating groups or managing members exists yet.
- **BarabriApp:** shows fixed `Rs. 0` values and makes no calls into BarabriCore.

## Requirements

- macOS 13 or later (`Package.swift` declares macOS 13 and iOS 16).
- Xcode with a Swift 6 toolchain (`swift-tools-version: 6.0`).
- SwiftLint, only if you want to run the lint step locally.

## Build

```bash
git clone <repository-url>
cd barabri
swift build
```

Run the placeholder app:

```bash
swift run BarabriApp
```

## Tests, coverage and lint

Run the tests:

```bash
swift test
```

Produce coverage and the llvm-cov reports:

```bash
swift test --enable-code-coverage
./scripts/coverage-report.sh
```

`scripts/coverage-report.sh` reads the profile written by the previous command. It writes `coverage/coverage-report.txt` and `coverage/coverage.lcov`, and prints the text report. It needs `xcrun llvm-cov`, which comes with Xcode.

Lint with the repository configuration in `.swiftlint.yml` (it includes `Sources` and `Tests` and excludes `.build`):

```bash
swiftlint lint
```

### What CI runs

`.github/workflows/ci.yml` runs on every push and pull request, on `macos-latest`:

- **test job:** `swift test --enable-code-coverage`, then `scripts/coverage-report.sh`. The text report is added to the job summary, and the `coverage/` folder is uploaded as the `coverage-report` artifact.
- **lint job:** installs SwiftLint if it is missing, runs `swiftlint lint --reporter github-actions-logging`, and uploads `swiftlint-report.txt` as the `swiftlint-report` artifact, even when the step fails.

## Architecture

All library code is in `Sources/BarabriCore`.

- **Domain models** (`Domain/Models.swift`): `Member`, `ExpenseGroup`, `Budget`, `BudgetCategory`, `PersonalExpense`, `Share`, `SharedExpenseRecord`, `Settlement`, `SettlementMethod` and `SettlementStatus`.
- **Money** (`Money.swift`): a non-negative amount that is encoded as a decimal string.
- **BarabriError** (`BarabriError.swift`): the typed error enum used across the library.
- **Split strategies** (`ExpenseSplitting.swift`): `ParticipantID`, `Allocations`, the `SplitStrategy` protocol, and the equal, exact-amount and percentage strategies.
- **SplitStrategyCreator** (`SplitStrategyCreator.swift`): the creator protocol, one creator per split kind, and `SplitType`, which selects a creator.
- **Expense and BalanceEngine** (`BalanceEngine.swift`): `Expense`, which checks its own invariants, and `BalanceEngine`, which computes per-expense results, netted obligations, outstanding amounts and per-participant balances.
- **ExpenseService** (`Expenses/ExpenseService.swift`): validates a shared-expense request, splits it, and saves the record.
- **SettlementService** (`Settlements/SettlementService.swift`): validates a settlement against the outstanding debt and saves it.
- **Repository protocols** (`Persistence/Repositories.swift`): `ExpenseRepository`, `SettlementRepository`, `BudgetRepository` and `GroupRepository`.
- **JSONFileStore** (`Persistence/JSONFileStore.swift`): the actor that loads, caches and writes the document.
- **JSON repositories** (`Persistence/JSONRepositories.swift`): repository implementations that share one `JSONFileStore`.

Dependencies are passed in through initialisers. `ExpenseService` takes an expense repository and a group repository. `SettlementService` takes a settlement, expense and group repository, plus a `BalanceEngine` with a default value. The JSON repositories take a `JSONFileStore`.

## Design patterns

Only two patterns are implemented.

- **Strategy:** `SplitStrategy` is the strategy interface. `EqualSplitStrategy`, `ExactAmountSplitStrategy` and `PercentageSplitStrategy` implement it, in `ExpenseSplitting.swift`.
- **Factory Method:** `SplitStrategyCreator` declares the factory method `makeStrategy()`. `EqualSplitCreator`, `ExactAmountSplitCreator` and `PercentageSplitCreator` implement it, in `SplitStrategyCreator.swift`. `SplitType.creator` picks the creator for a request. `ExpenseService` calls `split.creator.allocate(...)` and never names a concrete strategy.

Equal and percentage splits round each share to two decimal places. The rounding difference goes to the first participant.

## Persistence

All data is stored in one JSON document, described in [docs/storage-schema.md](docs/storage-schema.md). In summary:

- `StoreDocument` carries `schemaVersion`, which must be `1`. Any other value is rejected on read with `BarabriError.persistenceFailure`.
- Amounts are stored as decimal strings, such as `"3000.10"`.
- `JSONFileStore` writes the whole document with `.atomic`. A failed write leaves the previous file in place.
- A missing file reads as an empty document. A `nil` file URL keeps data in memory only.

## Concurrency

- `JSONFileStore` is a Swift `actor`, so reads and writes to the document are serialised.
- `update` applies its change to a copy. The copy is written to disk and cached only if the change and the write both succeed.
- The services are `Sendable` structs whose operations are `async throws`.
- `SettlementService` documents a limitation in a code comment: "The check-then-save is not atomic across concurrent callers. Two simultaneous settlements for the same debt can both pass the check."

## Defensive programming

- `Money` rejects negative values. Decoding accepts only plain decimal strings.
- `Expense` rejects a non-positive total, a payer who is not in the allocations, and allocations that do not sum to the total.
- Split strategies reject a non-positive total, an empty or duplicated participant list, negative values, exact allocations that do not add up to the total, percentages that do not add up to 100, and allocations or percentages whose participants do not match the expense's participants.
- `ExpenseService` runs its checks in a fixed order and stops at the first failure. Nothing is saved when a check fails.
- `SettlementService` rejects a non-positive amount, a settlement from a person to themselves, non-members, and amounts larger than the outstanding debt.
- `SharedExpenseRecord.expense()` re-runs the expense checks when stored data is turned back into a domain value.
- `BarabriError` is the typed error enum. Each case has a `LocalizedError` message.

## Tests

Tests are in `Tests/BarabriCoreTests`, with one file per area. They cover the split strategies and their validation, the creator and `SplitType`, `Money`, `BalanceEngine`, `ExpenseService`, `SettlementService`, `JSONFileStore` and the JSON repositories.

## Branch policy

- `main` contains reviewed, buildable code.
- Use task branches such as `feature/split-strategies` and `test/balance-engine`.
- Merge through pull requests after review.
- The author does not approve their own pull request.
- Preserve red-green-refactor commits so TDD evidence remains visible.

## Ownership

- Mehreen: Personal Budgeting and Group Management.
- Sawaiz: Expense/Split Engine, Balance Engine, and Settlement Tracking.

Both members review, test, and defend the whole system.
