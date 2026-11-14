import Foundation

/// The whole persisted document. Schema version 1.
public struct StoreDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var groups: [ExpenseGroup]
    public var budgets: [Budget]
    public var personalExpenses: [PersonalExpense]
    public var sharedExpenses: [SharedExpenseRecord]
    public var settlements: [Settlement]

    public init() {
        schemaVersion = Self.currentSchemaVersion
        groups = []
        budgets = []
        personalExpenses = []
        sharedExpenses = []
        settlements = []
    }
}

/// Serialises every read and write. Actor isolation is the thread-safety strategy.
public actor JSONFileStore {
    private let fileURL: URL?
    private var cached: StoreDocument?

    /// - Parameter fileURL: The JSON file to persist to, or `nil` to keep data in memory only.
    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public func read() throws -> StoreDocument {
        try current()
    }

    /// Applies `change` to a copy, writes the copy atomically to disk, and only then keeps it.
    /// If `change` throws or the write fails, the stored document is left unchanged.
    public func update<T: Sendable>(_ change: @Sendable (inout StoreDocument) throws -> T) throws -> T {
        var working = try current()
        let result = try change(&working)
        if let fileURL {
            try Self.write(working, to: fileURL)
        }
        cached = working
        return result
    }

    // MARK: - Loading

    private func current() throws -> StoreDocument {
        if let cached {
            return cached
        }
        let loaded = try Self.load(from: fileURL)
        cached = loaded
        return loaded
    }

    private static func load(from fileURL: URL?) throws -> StoreDocument {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoreDocument()
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw BarabriError.persistenceFailure("the file could not be read: \(error.localizedDescription)")
        }

        let document: StoreDocument
        do {
            document = try JSONDecoder().decode(StoreDocument.self, from: data)
        } catch {
            throw BarabriError.persistenceFailure("the file is not valid JSON: \(error.localizedDescription)")
        }

        guard document.schemaVersion == StoreDocument.currentSchemaVersion else {
            throw BarabriError.persistenceFailure(
                "Unsupported schema version \(document.schemaVersion); expected \(StoreDocument.currentSchemaVersion)."
            )
        }
        return document
    }

    // MARK: - Writing

    private static func write(_ document: StoreDocument, to fileURL: URL) throws {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(document)
        } catch {
            throw BarabriError.persistenceFailure("the document could not be encoded: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw BarabriError.persistenceFailure("the file could not be written: \(error.localizedDescription)")
        }
    }
}
