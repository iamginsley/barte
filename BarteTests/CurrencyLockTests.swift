import Foundation
import Testing
@testable import Barte

/// Amounts aren't converted, so a group's currency is fixed once it has expenses.
@Suite("Currency lock")
struct CurrencyLockTests {
    @Test func currencyIsLockedOnceThereAreExpenses() async throws {
        let repository = DemoGroupRepository()
        let group = try #require(try await repository.fetchGroups().first { !$0.expenses.isEmpty })
        let other = group.currency == "GBP" ? "USD" : "GBP"
        await #expect(throws: BarteError.server(hint: "currency_locked")) {
            try await repository.updateGroup(group.id, name: group.name, currency: other, color: group.color)
        }
        // Name and color still change.
        try await repository.updateGroup(group.id, name: "Neu", currency: group.currency, color: .green)
        let updated = try #require(try await repository.fetchGroups().first { $0.id == group.id })
        #expect(updated.name == "Neu" && updated.color == .green && updated.currency == group.currency)
    }

    @Test func currencyChangesWithoutExpenses() async throws {
        let repository = DemoGroupRepository()
        let id = try await repository.createGroup(name: "Leer", currency: "EUR", color: .blue, myName: "Dominik", otherNames: ["Anna"])
        try await repository.updateGroup(id, name: "Leer", currency: "GBP", color: .blue)
        #expect(try await repository.fetchGroups().first { $0.id == id }?.currency == "GBP")
    }

    @MainActor
    @Test func editorShowsTheCurrencyReadOnly() throws {
        let group = try #require(DemoData.groups().first { !$0.expenses.isEmpty })
        #expect(GroupEditorModel(group: group, me: nil).isCurrencyLocked)
        #expect(!GroupEditorModel(group: nil, me: nil).isCurrencyLocked)
    }

    @Test func lockedCurrencyHasAMessage() {
        #expect(BarteError.server(hint: "currency_locked").errorDescription?.contains("Währung") == true)
    }
}
