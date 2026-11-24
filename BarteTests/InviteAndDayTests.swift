import Foundation
import Testing
@testable import Barte

@Suite("Invite links")
struct InviteLinkTests {
    @Test func appSchemeLink() {
        #expect(InviteLink.code(from: URL(string: "barte://join/SKI2FUN7")!) == "SKI2FUN7")
        #expect(InviteLink.code(from: URL(string: "barte://join/ski2fun7")!) == "SKI2FUN7")
    }

    @Test func webLinkRoundTrip() {
        let url = InviteLink.url(for: "SKI2FUN7")
        #expect(url.absoluteString == "https://iamginsley.github.io/barte/join/?c=SKI2FUN7")
        #expect(InviteLink.code(from: url) == "SKI2FUN7")
    }

    @Test func unrelatedLinksAreIgnored() {
        #expect(InviteLink.code(from: URL(string: "https://example.com/join/?c=SKI2FUN7")!) == nil)
        #expect(InviteLink.code(from: URL(string: "barte://other/SKI2FUN7")!) == nil)
    }

    @Test func typedCodes() {
        #expect(InviteLink.normalize(" ski2 fun7 ") == "SKI2FUN7")
        #expect(InviteLink.normalize("SKI2-FUN7") == "SKI2FUN7")
        #expect(InviteLink.normalize("https://iamginsley.github.io/barte/join/?c=abcd2345") == "ABCD2345")
        #expect(InviteLink.normalize("abc") == nil)
        #expect(InviteLink.normalize("ÄÖÜÄÖÜÄÖ") == nil)
    }
}

@Suite("Wall-clock days")
struct LocalDayTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    @Test func lateEveningStaysOnItsDay() {
        // 23:30 in Vienna is already the next day in UTC; the stored day must be Vienna's.
        let vienna = calendar("Europe/Vienna")
        let date = vienna.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 30))!
        #expect(LocalDay.string(from: date, calendar: vienna) == "2026-11-04")
        #expect(LocalDay.string(from: date, calendar: calendar("UTC")) == "2026-11-04")
        #expect(LocalDay.string(from: date, calendar: calendar("Asia/Tokyo")) == "2026-11-05")
    }

    @Test func parsesToStartOfDayInTheGivenZone() {
        let ny = calendar("America/New_York")
        let date = LocalDay.date(from: "2026-03-08", calendar: ny)!
        #expect(ny.dateComponents([.year, .month, .day, .hour], from: date) == DateComponents(year: 2026, month: 3, day: 8, hour: 0))
        #expect(LocalDay.string(from: date, calendar: ny) == "2026-03-08")
    }

    @Test func rejectsInvalidDays() {
        #expect(LocalDay.date(from: "2026-02-30") == nil)
        #expect(LocalDay.date(from: "2026-13-01") == nil)
        #expect(LocalDay.date(from: "gestern") == nil)
    }
}

@Suite("Group sharing rules")
struct GroupRulesTests {
    let me = UUID()
    let friend = UUID()

    private func group(createdBy: UUID?, friendUsesApp: Bool) -> SplitGroup {
        SplitGroup(
            id: UUID(), name: "WG", currency: "EUR", color: .blue, createdAt: .now,
            members: [Member(id: UUID(), name: "Ich", userID: me), Member(id: UUID(), name: "Lena", userID: friendUsesApp ? friend : nil)],
            expenses: [], createdBy: createdBy
        )
    }

    @Test func findsMyMember() {
        let group = group(createdBy: me, friendUsesApp: true)
        #expect(group.me(userID: me) == group.members[0].id)
        #expect(group.me(userID: UUID()) == nil)
        #expect(group.me(userID: nil) == nil)
    }

    @Test func onlyTheLastAppUserTakesTheGroupAlong() {
        // Being the creator doesn't matter: nobody deletes a group for the others.
        #expect(!group(createdBy: me, friendUsesApp: true).leavingDeletes(userID: me))
        #expect(group(createdBy: friend, friendUsesApp: false).leavingDeletes(userID: me))
        #expect(!group(createdBy: me, friendUsesApp: false).leavingDeletes(userID: nil))
    }

    @Test func leavingNeedsToBeSquareWhileOthersStay() {
        var shared = group(createdBy: me, friendUsesApp: true)
        #expect(shared.canLeave(userID: me))
        shared.expenses = [Expense(id: UUID(), title: "Pizza", amountCents: 2000, date: .now,
                                   payerID: shared.members[0].id, participantIDs: shared.members.map(\.id))]
        #expect(!shared.canLeave(userID: me))
        #expect(!shared.canLeave(userID: friend))
        // Alone with typed-in names, the group goes with them, open amounts or not.
        var alone = group(createdBy: me, friendUsesApp: false)
        alone.expenses = shared.expenses.map { var e = $0; e.payerID = alone.members[0].id; e.participantIDs = alone.members.map(\.id); return e }
        #expect(alone.canLeave(userID: me))
    }

    @Test func sharedOnlyWithASecondAppUser() {
        #expect(group(createdBy: me, friendUsesApp: true).isShared)
        #expect(!group(createdBy: me, friendUsesApp: false).isShared)
    }
}
