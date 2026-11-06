import CoreGraphics
import Foundation

/// One line Vision recognised. `frame` is in the image's unit square with a top-left origin, y down
/// (Vision's own boxes are bottom-left; the app flips them).
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var frame: CGRect

    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

/// Puts recognised lines in reading order (design doc §3.5): rows top to bottom, each row left to right.
/// Pieces on one row (table cells, a label and its value) are joined with a space, rows with a newline.
/// Columns side by side are read row by row, not column by column, as most screenshot tools do.
public enum ReadingOrder {
    public static func text(of lines: [RecognizedLine]) -> String {
        rows(of: lines).map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }

    /// Lines grouped into rows. A line joins a row when its vertical centre lies within the row's first line
    /// and that line's centre lies within it: a slightly lower or taller neighbour still counts, a tall
    /// heading does not swallow the lines beside it, and the row never grows, so a staircase of slightly
    /// offset lines cannot chain into one row. The latest row is tried first; earlier rows only past rows started
    /// by a much smaller piece (under half the line's height: a badge, a superscript), so such a piece between
    /// two pieces of one row does not split that row, while a normal line in between still ends it.
    static func rows(of lines: [RecognizedLine]) -> [[RecognizedLine]] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let index = rowIndex(for: line, in: rows) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    private static func rowIndex(for line: RecognizedLine, in rows: [[RecognizedLine]]) -> Int? {
        for index in rows.indices.reversed() {
            let first = rows[index][0].frame
            if sharesRow(line.frame, first) { return index }
            guard first.height < line.frame.height / 2 else { return nil } // only a small piece is looked past
        }
        return nil
    }

    /// Similar heights: each centre lies within the other. One more than twice as tall as the other: the short
    /// piece's centre lies within the middle half of the tall one (a badge inside a line of text), which
    /// still keeps the lines beside a tall heading, at its top and bottom, out of its row.
    private static func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
        func centre(_ r: CGRect, isWithin s: CGRect) -> Bool { r.midY >= s.minY && r.midY <= s.maxY }
        let (short, tall) = a.height <= b.height ? (a, b) : (b, a)
        if tall.height > short.height * 2 {
            return centre(short, isWithin: tall.insetBy(dx: 0, dy: tall.height / 4))
        }
        return centre(a, isWithin: b) && centre(b, isWithin: a)
    }
}
