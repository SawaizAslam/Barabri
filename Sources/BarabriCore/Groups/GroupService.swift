import Foundation

/// Creates expense groups and manages their members.
///
/// Every method validates its input before writing, so a throwing call saves nothing.
public struct GroupService: Sendable {
    private let repository: any GroupRepository

    public init(repository: any GroupRepository) {
        self.repository = repository
    }

    /// Trims the name. Throws `.emptyName` for a blank name.
    public func createGroup(name: String) async throws -> ExpenseGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BarabriError.emptyName }

        let group = ExpenseGroup(name: trimmed)
        try await repository.save(group)
        return group
    }

    /// Adds a member and returns the updated group.
    /// Throws `.groupNotFound`, `.emptyName` (blank member name or blank id),
    /// and `.duplicateMember` (the id is already in the group). Nothing is saved when it throws.
    public func addMember(toGroup groupID: UUID, id: ParticipantID, name: String) async throws -> ExpenseGroup {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedID = id.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedID.isEmpty else { throw BarabriError.emptyName }

        guard var group = try await repository.group(id: groupID) else {
            throw BarabriError.groupNotFound
        }
        guard !group.members.contains(where: { $0.id == id }) else {
            throw BarabriError.duplicateMember
        }

        group.members.append(Member(id: id, name: trimmedName))
        try await repository.save(group)
        return group
    }

    /// Throws `.groupNotFound`.
    public func group(id: UUID) async throws -> ExpenseGroup {
        guard let group = try await repository.group(id: id) else {
            throw BarabriError.groupNotFound
        }
        return group
    }

    public func groups() async throws -> [ExpenseGroup] {
        try await repository.groups()
    }
}
