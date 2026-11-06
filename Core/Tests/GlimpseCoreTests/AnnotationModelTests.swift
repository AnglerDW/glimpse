import CoreGraphics
import Testing
@testable import GlimpseCore

private func counter(_ number: Int) -> Annotation {
    Annotation(shape: .counter(center: CGPoint(x: 10, y: 10), number: number), color: RGBA(hex: 0xFF3B30), size: 40)
}

private let red = RGBA(hex: 0xFF3B30)

struct AnnotationStyleTests {
    @Test func paletteOrder() {
        #expect(PaletteColor.allCases == [.red, .orange, .yellow, .green, .blue, .black])
    }

    @Test func blackTurnsWhiteInDarkAppearance() {
        #expect(PaletteColor.black.rgba(darkAppearance: false) == RGBA(red: 0, green: 0, blue: 0))
        #expect(PaletteColor.black.rgba(darkAppearance: true) == RGBA(red: 1, green: 1, blue: 1))
        #expect(PaletteColor.red.rgba(darkAppearance: true) == PaletteColor.red.rgba(darkAppearance: false))
    }

    @Test func widthLevelsPerTool() {
        #expect(Tool.rectangle.size(for: .thin) == 2)
        #expect(Tool.pen.size(for: .thick) == 6)
        #expect(Tool.text.size(for: .medium) == 20)
        #expect(Tool.mosaic.size(for: .thick) == 40)
        #expect(Tool.counter.size(for: .thin) == 20)
    }

    @Test func onlyYellowAndWhitePreferDarkText() {
        let dark = PaletteColor.allCases.filter { $0.rgba(darkAppearance: false).prefersDarkText }
        #expect(dark == [.yellow]) // red, orange, green, blue and black keep white text
        #expect(PaletteColor.black.rgba(darkAppearance: true).prefersDarkText) // black drawn as white
    }
}

struct AnnotationDocumentTests {
    @Test func undoAndRedo() {
        var doc = AnnotationDocument()
        #expect(!doc.canUndo && !doc.canRedo)
        doc.add(counter(1))
        doc.add(counter(2))
        #expect(doc.undo() == counter(2))
        #expect(doc.annotations == [counter(1)])
        #expect(doc.canRedo)
        #expect(doc.redo() == counter(2))
        #expect(doc.annotations == [counter(1), counter(2)])
        #expect(!doc.canRedo)
    }

    @Test func undoAndRedoOnAnEmptyDocumentDoNothing() {
        var doc = AnnotationDocument()
        #expect(doc.undo() == nil)
        #expect(doc.redo() == nil)
        #expect(doc.annotations.isEmpty)
    }

    @Test func addingAfterUndoDropsRedo() {
        var doc = AnnotationDocument()
        doc.add(counter(1))
        doc.undo()
        doc.add(counter(1))
        #expect(!doc.canRedo)
        #expect(doc.redo() == nil)
    }

    @Test func counterNumberRollsBackOnUndo() {
        var doc = AnnotationDocument()
        #expect(doc.nextCounterNumber == 1)
        doc.add(counter(doc.nextCounterNumber))
        doc.add(Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 5, height: 5)), color: red, size: 4))
        doc.add(counter(doc.nextCounterNumber))
        #expect(doc.nextCounterNumber == 3)
        doc.undo()
        #expect(doc.nextCounterNumber == 2)
        doc.redo()
        #expect(doc.nextCounterNumber == 3)
    }

    @Test func removeAllClearsUndoAndRedo() {
        var doc = AnnotationDocument()
        doc.add(counter(1))
        doc.add(counter(2))
        doc.undo()
        doc.removeAll()
        #expect(doc.annotations.isEmpty)
        #expect(!doc.canUndo && !doc.canRedo)
    }
}

struct AnnotationBoundsTests {
    @Test func rectangleBoundsCoverTheStroke() {
        let a = Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)), color: red, size: 4)
        #expect(a.bounds == CGRect(x: 7, y: 7, width: 106, height: 56))
    }

    @Test func arrowBoundsCoverTheHead() {
        // Width 10: the head's half-width (22) is the widest part, plus a pixel.
        let a = Annotation(shape: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: red, size: 10)
        #expect(a.bounds == CGRect(x: -23, y: -23, width: 146, height: 46))
    }

    @Test func textBoundsGrowByOneLineHeightPerLine() {
        // 40 pixels on a 2x screen: 20pt lines, scaled up.
        let one = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi", scale: 2), color: red, size: 40)
        let two = Annotation(shape: .text(origin: CGPoint(x: 10, y: 20), string: "Hi\nthere", scale: 2), color: red, size: 40)
        #expect(one.bounds.origin == CGPoint(x: 9, y: 9)) // a quarter of the size above, for tall fallback glyphs
        #expect(two.bounds.height - one.bounds.height == TextLayout.lineHeight(fontSize: 20) * 2)
        #expect(two.bounds.width > one.bounds.width)
    }
}
