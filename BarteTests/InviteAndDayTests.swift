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
    let me: UserID = "uid-me"
    let friend: UserID = "uid-friend"

    private func group(createdBy: UserID?, friendUsesApp: Bool) -> SplitGroup {
        SplitGroup(
            id: UUID(), name: "WG", currency: "EUR", color: .blue, createdAt: .now,
            members: [Member(id: UUID(), name: "Ich", userID: me), Member(id: UUID(), name: "Lena", userID: friendUsesApp ? friend : nil)],
            expenses: [], createdBy: createdBy
        )
    }

    @Test func findsMyMember() {
        let group = group(createdBy: me, friendUsesApp: true)
        #expect(group.me(userID: me) == group.members[0].id)
        #expect(group.me(userID: "uid-other") == nil)
        #expect(group.me(userID: nil) == nil)
    }

    @Test func whoMayDelete() {
        #expect(group(createdBy: me, friendUsesApp: true).canDelete(userID: me))
        #expect(!group(createdBy: friend, friendUsesApp: true).canDelete(userID: me))
        // The creator left: the last person with the app may delete.
        #expect(group(createdBy: nil, friendUsesApp: false).canDelete(userID: me))
    }

    @Test func sharedOnlyWithASecondAppUser() {
        #expect(group(createdBy: me, friendUsesApp: true).isShared)
        #expect(!group(createdBy: me, friendUsesApp: false).isShared)
    }
}
