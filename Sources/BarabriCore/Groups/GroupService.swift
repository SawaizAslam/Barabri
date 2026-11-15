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

        var group = try await loadGroup(id: groupID)
        guard !group.members.contains(where: { $0.id == id }) else {
            throw BarabriError.duplicateMember
        }

        group.members.append(Member(id: id, name: trimmedName))
        try await repository.save(group)
        return group
    }

    /// Removes a member and returns the updated group. Other members keep their order.
    /// Throws `.groupNotFound` and `.memberNotFound`. Nothing is saved when it throws.
    public func removeMember(fromGroup groupID: UUID, id: ParticipantID) async throws -> ExpenseGroup {
        var group = try await loadGroup(id: groupID)
        guard let index = group.members.firstIndex(where: { $0.id == id }) else {
            throw BarabriError.memberNotFound
        }

        group.members.remove(at: index)
        try await repository.save(group)
        return group
    }

    /// Checks that a shared expense involves only members of the group. Saves nothing.
    /// Throws `.groupNotFound`, `.noParticipants`, `.duplicateParticipant`, `.memberNotFound`
    /// (payer or a participant is not a member), and `.payerNotFound` (payer is not in `participants`).
    public func validateParticipants(
        groupID: UUID,
        payer: ParticipantID,
        participants: [ParticipantID]
    ) async throws {
        let group = try await loadGroup(id: groupID)

        guard !participants.isEmpty else { throw BarabriError.noParticipants }
        guard Set(participants).count == participants.count else {
            throw BarabriError.duplicateParticipant
        }

        let memberIDs = Set(group.members.map(\.id))
        guard participants.allSatisfy({ memberIDs.contains($0) }) else {
            throw BarabriError.memberNotFound
        }
        guard memberIDs.contains(payer) else {
            throw BarabriError.memberNotFound
        }
        guard participants.contains(payer) else {
            throw BarabriError.payerNotFound
        }
    }

    /// Throws `.groupNotFound`.
    public func group(id: UUID) async throws -> ExpenseGroup {
        try await loadGroup(id: id)
    }

    public func groups() async throws -> [ExpenseGroup] {
        try await repository.groups()
    }

    /// Loads a group or throws `.groupNotFound`.
    private func loadGroup(id: UUID) async throws -> ExpenseGroup {
        guard let group = try await repository.group(id: id) else {
            throw BarabriError.groupNotFound
        }
        return group
    }
}
