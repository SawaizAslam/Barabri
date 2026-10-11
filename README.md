# Barabri

Barabri is a native Swift foundation for personal budgeting and group expense splitting in PKR.

## Current implementation

- Strategy pattern: equal, exact-amount, and percentage splitting.
- Factory Method: creates the selected split strategy.
- Balance accounting: full cash impact, personal share, and receivables.
- Defensive validation with domain-specific errors.
- TDD baseline covering the core split and balance rules.

## Build and test

```bash
swift test
```

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
