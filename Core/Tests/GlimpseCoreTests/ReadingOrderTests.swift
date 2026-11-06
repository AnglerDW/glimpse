import CoreGraphics
import Testing
@testable import GlimpseCore

struct ReadingOrderTests {
    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.3, height: CGFloat = 0.05) -> RecognizedLine {
        RecognizedLine(text: text, frame: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func nothingRecognisedIsEmpty() {
        #expect(ReadingOrder.text(of: []) == "")
    }

    @Test func rowsGoTopToBottomWhateverTheInputOrder() {
        let lines = [line("第三行", x: 0.1, y: 0.5), line("第一行", x: 0.1, y: 0.1), line("第二行", x: 0.1, y: 0.3)]
        #expect(ReadingOrder.text(of: lines) == "第一行\n第二行\n第三行")
    }

    @Test func piecesOnOneRowGoLeftToRightWithASpace() {
        let lines = [line("value", x: 0.6, y: 0.2), line("名称：", x: 0.1, y: 0.2)]
        #expect(ReadingOrder.text(of: lines) == "名称： value")
    }

    @Test func aSlightlyLowerOrTallerNeighbourIsTheSameRow() {
        let lines = [line("左", x: 0.1, y: 0.20, height: 0.05),   // centre 0.225
                     line("右", x: 0.6, y: 0.22, height: 0.06),   // centre 0.25, inside 左; 左's centre inside it
                     line("下一行", x: 0.1, y: 0.26, height: 0.05)] // centre 0.285, below 左
        #expect(ReadingOrder.text(of: lines) == "左 右\n下一行")
    }

    @Test func aTallHeadingDoesNotSwallowTheLinesBesideIt() {
        // A big number on the left, two caption lines on its right.
        let lines = [line("50%", x: 0.05, y: 0.10, width: 0.3, height: 0.20),
                     line("第一行说明", x: 0.5, y: 0.10, height: 0.05),
                     line("第二行说明", x: 0.5, y: 0.20, height: 0.05)]
        #expect(ReadingOrder.text(of: lines) == "50%\n第一行说明\n第二行说明")
    }

    @Test func aStaircaseDoesNotChainIntoOneRow() {
        let lines = (0..<4).map { line("第\($0)段", x: 0.1 + CGFloat($0) * 0.2, y: 0.1 + CGFloat($0) * 0.02, width: 0.15) }
        #expect(ReadingOrder.text(of: lines) == "第0段 第1段\n第2段 第3段")
    }

    @Test func aSmallBadgeBetweenTwoPiecesDoesNotSplitTheirRow() {
        let lines = [line("A", x: 0.05, y: 0.10, height: 0.05),           // centre 0.125
                     line("B", x: 0.40, y: 0.11, width: 0.05, height: 0.01), // centre 0.115: in A's middle half
                     line("C", x: 0.50, y: 0.12, height: 0.05)]           // centre 0.145: A's row
        #expect(ReadingOrder.text(of: lines) == "A B C")
    }

    @Test func mixedChineseAndEnglish() {
        let lines = [line("Glimpse 截图工具", x: 0.05, y: 0.05, width: 0.6),
                     line("Version 0.1", x: 0.05, y: 0.15),
                     line("快捷键", x: 0.05, y: 0.25), line("⇧⌘A", x: 0.5, y: 0.255)]
        #expect(ReadingOrder.text(of: lines) == "Glimpse 截图工具\nVersion 0.1\n快捷键 ⇧⌘A")
    }

    @Test func blankLinesAreDropped() {
        let lines = [line("  ", x: 0.1, y: 0.1), line("文字", x: 0.1, y: 0.3)]
        #expect(ReadingOrder.text(of: lines) == "文字")
    }
}
