import CoreGraphics
import Testing
@testable import GlimpseCore

struct HUDTests {
    /// The text comes from the package's string catalog (zh-Hans keys), in whatever language the test runs under.
    @Test func messagesComeFromTheStringCatalog() {
        let current = LocalizedText.current
        #expect(HUDMessage.copied.text == current("已拷贝到剪贴板"))
        #expect(HUDMessage.saved(folder: "下载").text == String(format: current("已保存到「%@」"), "下载"))
        #expect(HUDMessage.saveFailed.text == current("保存失败，图片已拷贝到剪贴板"))
        #expect(HUDMessage.colorCopied("#FF3B30").text == String(format: current("已拷贝颜色 %@"), "#FF3B30"))
        #expect(HUDMessage.colorCopied("255, 59, 48").text == String(format: current("已拷贝颜色 %@"), "255, 59, 48"))
        #expect(HUDMessage.captureFailed.text == current("截图失败"))
        #expect(HUDMessage.screensChanged.text == current("显示器变化，已取消截图"))
    }

    @Test func sourceLanguageMessagesAreShortChineseLines() {
        let zh = { LocalizedText.text($0, in: "zh-Hans") }
        #expect(zh("已拷贝到剪贴板") == "已拷贝到剪贴板")
        #expect(zh("已保存到「%@」").map { String(format: $0, "下载") } == "已保存到「下载」")
        #expect(zh("保存失败，图片已拷贝到剪贴板") == "保存失败，图片已拷贝到剪贴板")
        #expect(zh("已拷贝颜色 %@").map { String(format: $0, "#FF3B30") } == "已拷贝颜色 #FF3B30")
        #expect(zh("截图失败") == "截图失败")
        #expect(zh("显示器变化，已取消截图") == "显示器变化，已取消截图")
        #expect(LocalizedText.text("已拷贝到剪贴板", in: "en") == "Copied to Clipboard")
    }

    @Test func onlyFailuresAreMarkedAsFailures() {
        #expect(!HUDMessage.copied.isFailure)
        #expect(!HUDMessage.saved(folder: "下载").isFailure)
        #expect(!HUDMessage.colorCopied("#000000").isFailure)
        #expect(HUDMessage.saveFailed.isFailure)
        #expect(HUDMessage.captureFailed.isFailure)
        #expect(HUDMessage.screensChanged.isFailure)
        #expect(HUDMessage.saveFailed.symbolName == HUDMessage.captureFailed.symbolName)
    }

    @Test func hudSitsInTheMiddleOfTheVisibleFrame() {
        // Visible frame above a 60pt Dock on a 1440 × 900 screen (menu bar 25pt).
        let frame = HUDLayout.frame(size: CGSize(width: 200, height: 36),
                                    visibleFrame: CGRect(x: 0, y: 60, width: 1440, height: 815))
        #expect(frame.midX == 720)
        #expect(frame == CGRect(x: 620, y: 450, width: 200, height: 36)) // 60 + 407.5 − 18 = 449.5, rounded
    }

    @Test func hudOriginIsOnWholePointsOnASecondaryScreen() {
        let frame = HUDLayout.frame(size: CGSize(width: 175, height: 36),
                                    visibleFrame: CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
        #expect(frame.origin == CGPoint(x: -1048, y: -558)) // −960 − 87.5 → −1047.5 rounds away from zero; −540 − 18
    }
}
