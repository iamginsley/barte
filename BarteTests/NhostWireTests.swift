import Foundation
import Testing
@testable import Barte

/// What goes over the wire to Hasura and back.
@Suite("Nhost wire format")
struct NhostWireTests {
    private func json(_ value: JSON) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    @Test func arraysBecomePostgresLiterals() throws {
        #expect(try json(.pgArray(["Ben", "Clara"])) == #""{\"Ben\",\"Clara\"}""#)
        // Quotes and backslashes in names stay intact.
        #expect(JSON.pgArray([#"Al "Bo" \ C"#]) == .string(#"{"Al \"Bo\" \\ C"}"#))
        #expect(JSON.pgArray([String]()) == .string("{}"))
        let id = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        #expect(JSON.pgArray([id]) == .string(#"{"aaaaaaaa-0000-0000-0000-000000000001"}"#))
        #expect(JSON.pgArray([2, 1] as [Int]?) == .string("{2,1}"))
        #expect(JSON.pgArray(nil as [Int]?) == .null)
    }

    @Test func variablesEncodeNullsExplicitly() throws {
        // "No member" must reach the SQL function as null, not as a missing key.
        let value: JSON = ["p_member_id": .uuid(nil), "p_name": .optional("Ben")]
        let text = try json(value)
        #expect(text.contains(#""p_member_id":null"#))
        #expect(text.contains(#""p_name":"Ben""#))
    }

    @Test func postgresArraysDecodeInBothForms() throws {
        struct Row: Decodable { let ids: PGArray<UUID>; let values: PGArray<Int>? }
        let id = "aaaaaaaa-0000-0000-0000-000000000001"
        let fromJSON = try JSONDecoder().decode(Row.self, from: Data(#"{"ids": ["\#(id)"], "values": [2, 1]}"#.utf8))
        #expect(fromJSON.ids.values == [UUID(uuidString: id)!])
        #expect(fromJSON.values?.values == [2, 1])
        let fromText = try JSONDecoder().decode(Row.self, from: Data(#"{"ids": "{\#(id)}", "values": null}"#.utf8))
        #expect(fromText.ids.values == [UUID(uuidString: id)!])
        #expect(fromText.values == nil)
    }

    @Test func hasuraTimestamps() {
        let micro = Timestamp.date(from: "2026-11-07T16:31:06.123456+00:00")
        let plain = Timestamp.date(from: "2026-11-07T16:31:06+00:00")
        let zulu = Timestamp.date(from: "2026-11-07T16:31:06.5Z")
        #expect(micro != nil && plain != nil && zulu != nil)
        #expect(abs(micro!.timeIntervalSince(plain!) - 0.123) < 0.001)
        #expect(Timestamp.date(from: "2026-11-07T17:31:06+01:00") == plain)
        #expect(Timestamp.date(from: "gestern") == nil)
    }

    @Test func functionResultWithPreview() throws {
        let body = """
        {"data": {"preview_invite": [{"id": "aaaaaaaa-0000-0000-0000-000000000001", "code": null, "preview": {
          "group_id": "aaaaaaaa-0000-0000-0000-000000000001", "name": "Ski", "currency": "EUR", "color": 1, "is_member": false,
          "members": [{"id": "bbbbbbbb-0000-0000-0000-000000000002", "name": "Anna", "is_claimed": true}]
        }}]}}
        """
        struct Response: Decodable { let data: [String: [NhostAPI.Result]] }
        let result = try NhostAPI.decoder.decode(Response.self, from: Data(body.utf8)).data["preview_invite"]?.first
        #expect(result?.preview?.name == "Ski")
        #expect(result?.preview?.members.first?.isClaimed == true)
        #expect(result?.code == nil)
    }

    @Test func serverHintsBecomeGermanMessages() {
        #expect(BarteError.server(hint: "invalid_code").errorDescription?.contains("Einladungscode") == true)
        #expect(BarteError.server(hint: "database query error").errorDescription == "Das hat nicht geklappt. Versuch es noch einmal.")
    }

    @Test func endpoints() {
        #expect(Backend.url("graphql").absoluteString == "https://uenqaayyhyrekjhojdwn.graphql.eu-central-1.nhost.run/v1")
        #expect(Backend.url("auth", "signin/idtoken").absoluteString == "https://uenqaayyhyrekjhojdwn.auth.eu-central-1.nhost.run/v1/signin/idtoken")
        #expect(Backend.url("functions", "apple-revoke").absoluteString == "https://uenqaayyhyrekjhojdwn.functions.eu-central-1.nhost.run/v1/apple-revoke")
    }
}
