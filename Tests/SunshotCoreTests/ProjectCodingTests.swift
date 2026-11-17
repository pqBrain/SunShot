import Foundation
import Testing

@testable import SunshotCore

@Suite("Project coding")
struct ProjectCodingTests {
    @Test(
        "[S0] project round-trips through JSON",
        arguments: [
            Project(),
            Project(canvas: .ratio(1.5), backdrop: .none, padding: 0.2),
            Project(canvas: .exact(PixelSize(width: 1280, height: 800)), backdrop: .solid(.black)),
        ])
    func roundTrip(project: Project) throws {
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data) == project)
    }
}
