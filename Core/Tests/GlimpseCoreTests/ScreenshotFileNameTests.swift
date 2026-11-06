import Foundation
import Testing
@testable import GlimpseCore

struct ScreenshotFileNameTests {
    @Test func includesMilliseconds() {
        // 2026-11-04 17:30:05.500 UTC
        let date = Date(timeIntervalSince1970: 1_793_813_405.5)
        let name = ScreenshotFileName.make(for: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Glimpse 2026-11-04 17.30.05.500.png")
    }
}
