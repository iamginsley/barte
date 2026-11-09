import Foundation
import Testing
@testable import Barte

/// Everyone with the app has one name, the same in every group.
@Suite("Account name")
struct AccountNameTests {
    @Test func renamingChangesMeInEveryGroup() async throws {
        let repository = DemoGroupRepository()
        #expect(try await repository.setMyName("  Dodo ") == "Dodo")
        let groups = try await repository.fetchGroups()
        let mine = groups.flatMap(\.members).filter { $0.userID == DemoData.userID }
        #expect(mine.count == groups.count && mine.allSatisfy { $0.name == "Dodo" })
        await #expect(throws: BarteError.self) { try await repository.setMyName("  ") }
    }

    @MainActor
    @Test func onlyTypedInNamesCanBeEditedInAGroup() async throws {
        let group = try #require(DemoData.groups().first { $0.name == DemoData.Sample.skiTrip })
        let model = GroupEditorModel(group: group, me: group.me(userID: DemoData.userID))
        let fixed = model.rows.filter(\.isFixed).map(\.name)
        #expect(Set(fixed) == ["Dominik", "Anna", "Ben"])
        #expect(model.rows.filter { !$0.isFixed }.map(\.name) == ["Clara", "David"])
    }
}
