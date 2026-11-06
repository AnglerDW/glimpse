import Foundation
import Testing
@testable import GlimpseCore

struct AtomicFileWriterTests {
    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glimpse-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test func writesFileAndLeavesNoTemp() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.png")
            try AtomicFileWriter.writeWithoutOverwriting(Data([1, 2, 3]), to: url)
            #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.png"])
        }
    }

    @Test func existingFileIsKeptAndTempRemoved() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.png")
            try Data([9]).write(to: url)
            #expect(throws: (any Error).self) {
                try AtomicFileWriter.writeWithoutOverwriting(Data([1]), to: url)
            }
            #expect(try Data(contentsOf: url) == Data([9]))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.png"])
        }
    }

    @Test func missingDirectoryThrows() {
        let url = URL(fileURLWithPath: "/no/such/dir/a.png")
        #expect(throws: (any Error).self) {
            try AtomicFileWriter.writeWithoutOverwriting(Data([1]), to: url)
        }
    }
}
