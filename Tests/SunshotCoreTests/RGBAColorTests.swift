import Testing

@testable import SunshotCore

@Suite("RGBAColor")
struct RGBAColorTests {
    @Test(
        "[S0] parses 3, 6 and 8 digit hex",
        arguments: [
            ("#FFF", "#FFFFFF"), ("ff8800", "#FF8800"), ("#11223380", "#11223380"), (" #abc ", "#AABBCC"),
        ])
    func parsesHex(input: String, expected: String) throws {
        let color = try #require(RGBAColor(hex: input))
        #expect(color.hexString == expected)
    }

    @Test("[S0] rejects invalid hex", arguments: ["", "#", "#12", "#12345", "zzzzzz", "#1234567", "#123456789"])
    func rejectsInvalidHex(input: String) {
        #expect(RGBAColor(hex: input) == nil)
    }

    @Test("[S0] clamps components and non-finite values")
    func clamps() {
        let color = RGBAColor(red: 2, green: -1, blue: .nan, alpha: .infinity)
        #expect(color == RGBAColor(red: 1, green: 0, blue: 0, alpha: 0))
    }

    @Test("[S0] opaque colours omit alpha in hex")
    func hexOmitsOpaqueAlpha() {
        #expect(RGBAColor.white.hexString == "#FFFFFF")
        #expect(RGBAColor.clear.hexString == "#00000000")
    }
}
