# Storage schema, version 1

Barabri stores everything in one JSON document, written by `JSONFileStore`
(`Sources/BarabriCore/Persistence/JSONFileStore.swift`).

## Conventions

- **Schema version:** top-level `schemaVersion` must be `1`. Any other value is rejected on read with `BarabriError.persistenceFailure`.
- **Money:** each amount is a decimal string, for example `"3000.10"`, so no precision is lost. Amounts are never negative.
- **Dates:** encoded with the default `JSONEncoder` strategy, as seconds since the 2001 reference date (`Date.timeIntervalSinceReferenceDate`).
- **IDs:** UUIDs are encoded as their standard string form. Participant IDs are encoded as the synthesised `Codable` object `{"value": "<id>"}`.
- **Writes:** the whole document is encoded with pretty printing and sorted keys, then written atomically. A failed update leaves the previous file in place.
- **Missing file:** a file that does not exist reads as an empty version 1 document.
- **Record order:** saving a record whose `id` already exists replaces it in place. A new record is appended, so arrays keep first-insertion order.

## Top-level layout

| Key | Type | Contents |
| --- | --- | --- |
| `schemaVersion` | integer | Always `1` for this version. |
| `groups` | array of Group | Expense groups and their members. |
| `budgets` | array of Budget | Personal budgets and their categories. |
| `personalExpenses` | array of PersonalExpense | Personal spending against a budget. |
| `sharedExpenses` | array of SharedExpenseRecord | Validated shared expenses. |
| `settlements` | array of Settlement | Payments between group members. |

## Records

**Group**: `id` (UUID), `name` (string), `members` (array of Member).
**Member**: `id` (participant ID), `name` (string).

**Budget**: `id` (UUID), `name` (string), `limit` (Money), `categories` (array of BudgetCategory).
**BudgetCategory**: `id` (UUID), `name` (string), `limit` (Money).

**PersonalExpense**: `id` (UUID), `budgetID` (UUID), `categoryID` (UUID or null), `title` (string), `amount` (Money), `recordedAt` (date).

**SharedExpenseRecord**: `id` (UUID), `groupID` (UUID), `title` (string), `payer` (participant ID), `total` (Money), `shares` (array of Share), `recordedAt` (date).
**Share**: `participant` (participant ID), `amount` (Money).

**Settlement**: `id` (UUID), `groupID` (UUID), `from` (participant ID), `to` (participant ID), `amount` (Money), `method` (string: `cash`, `bankTransfer`, `easypaisa` or `jazzCash`), `status` (string: `pending` or `completed`), `recordedAt` (date).

## Compatibility

Any change to these fields, or any other schema change, requires a new schema version and a migration. Version 1 readers must reject documents with any other `schemaVersion`.
