import XCTest
@testable import BarabriCore

private actor FakeGroupRepository: GroupRepository {
    private var storage: [UUID: ExpenseGroup] = [:]

    func save(_ group: ExpenseGroup) async throws {
        storage[group.id] = group
    }

    func group(id: UUID) async throws -> ExpenseGroup? {
        storage[id]
    }

    func groups() async throws -> [ExpenseGroup] {
        Array(storage.values)
    }
}

final class GroupServiceTests: XCTestCase {
    private var repository: FakeGroupRepository!
    private var service: GroupService!

    override func setUp() async throws {
        try await super.setUp()
        repository = FakeGroupRepository()
        service = GroupService(repository: repository)
    }

    override func tearDown() async throws {
        repository = nil
        service = nil
        try await super.tearDown()
    }

    func testCreateGroupReturnsNamedEmptyGroupAndStoresIt() async throws {
        let group = try await service.createGroup(name: "Flat")

        XCTAssertEqual(group.name, "Flat")
        XCTAssertTrue(group.members.isEmpty)

        let stored = try await repository.group(id: group.id)
        XCTAssertEqual(stored, group)
    }

    func testCreateGroupTrimsSurroundingWhitespaceFromName() async throws {
        let group = try await service.createGroup(name: "  Trip to Murree \n")

        XCTAssertEqual(group.name, "Trip to Murree")

        let stored = try await repository.group(id: group.id)
        XCTAssertEqual(stored?.name, "Trip to Murree")
    }

    func testCreateGroupWithBlankNameThrowsEmptyNameAndStoresNothing() async throws {
        do {
            _ = try await service.createGroup(name: " ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .emptyName)
        }

        let all = try await repository.groups()
        XCTAssertTrue(all.isEmpty)
    }

    func testAddMemberReturnsGroupContainingNewMemberAndStoresIt() async throws {
        let group = try await service.createGroup(name: "Flat")
        let ali = ParticipantID("ali")

        let updated = try await service.addMember(toGroup: group.id, id: ali, name: "Ali")

        XCTAssertEqual(updated.members, [Member(id: ali, name: "Ali")])

        let stored = try await repository.group(id: group.id)
        XCTAssertEqual(stored?.members, [Member(id: ali, name: "Ali")])
    }

    func testAddMemberKeepsExistingMembersInOrder() async throws {
        let group = try await service.createGroup(name: "Flat")
        let ali = ParticipantID("ali")
        let ahmed = ParticipantID("ahmed")

        _ = try await service.addMember(toGroup: group.id, id: ali, name: "Ali")
        let updated = try await service.addMember(toGroup: group.id, id: ahmed, name: "Ahmed")

        XCTAssertEqual(
            updated.members,
            [Member(id: ali, name: "Ali"), Member(id: ahmed, name: "Ahmed")]
        )

        let stored = try await repository.group(id: group.id)
        XCTAssertEqual(stored?.members, updated.members)
    }

    func testAddMemberWithIDAlreadyInGroupThrowsDuplicateMemberAndSavesNothing() async throws {
        let group = try await service.createGroup(name: "Flat")
        let ali = ParticipantID("ali")
        _ = try await service.addMember(toGroup: group.id, id: ali, name: "Ali")

        do {
            _ = try await service.addMember(toGroup: group.id, id: ali, name: "Ali Again")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .duplicateMember)
        }

        let stored = try await repository.group(id: group.id)
        XCTAssertEqual(stored?.members.count, 1)
        XCTAssertEqual(stored?.members, [Member(id: ali, name: "Ali")])
    }

    func testAddMemberWithBlankNameThrowsEmptyName() async throws {
        let group = try await service.createGroup(name: "Flat")

        do {
            _ = try await service.addMember(toGroup: group.id, id: ParticipantID("ali"), name: "   ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .emptyName)
        }

        let stored = try await repository.group(id: group.id)
        XCTAssertTrue(stored?.members.isEmpty ?? false)
    }

    func testAddMemberWithBlankIDThrowsEmptyName() async throws {
        let group = try await service.createGroup(name: "Flat")

        do {
            _ = try await service.addMember(toGroup: group.id, id: ParticipantID("  "), name: "Ali")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .emptyName)
        }

        let stored = try await repository.group(id: group.id)
        XCTAssertTrue(stored?.members.isEmpty ?? false)
    }

    func testAddMemberToUnknownGroupThrowsGroupNotFound() async throws {
        do {
            _ = try await service.addMember(toGroup: UUID(), id: ParticipantID("ali"), name: "Ali")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .groupNotFound)
        }
    }

    func testGroupByIDReturnsStoredGroup() async throws {
        let created = try await service.createGroup(name: "Flat")

        let fetched = try await service.group(id: created.id)

        XCTAssertEqual(fetched, created)
    }

    func testGroupByUnknownIDThrowsGroupNotFound() async throws {
        do {
            _ = try await service.group(id: UUID())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .groupNotFound)
        }
    }

    func testGroupsReturnsEveryCreatedGroup() async throws {
        let flat = try await service.createGroup(name: "Flat")
        let trip = try await service.createGroup(name: "Trip")
        let dinner = try await service.createGroup(name: "Dinner")

        let all = try await service.groups()

        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map(\.id)), Set([flat.id, trip.id, dinner.id]))
    }

    func testSamePersonCanBeMemberOfTwoGroups() async throws {
        let flat = try await service.createGroup(name: "Flat")
        let trip = try await service.createGroup(name: "Trip")
        let ali = ParticipantID("ali")

        _ = try await service.addMember(toGroup: flat.id, id: ali, name: "Ali")
        _ = try await service.addMember(toGroup: trip.id, id: ali, name: "Ali")

        let storedFlat = try await service.group(id: flat.id)
        let storedTrip = try await service.group(id: trip.id)
        XCTAssertEqual(storedFlat?.members.map(\.id), [ali])
        XCTAssertEqual(storedTrip?.members.map(\.id), [ali])
    }
}
