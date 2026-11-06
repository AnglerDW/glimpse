/// The annotations on one selection, with undo / redo. Every edit adds exactly one annotation
/// (annotations are never edited after they are drawn, design doc §1), so undo removes the last one
/// and redo puts it back.
public struct AnnotationDocument: Equatable, Sendable {
    public private(set) var annotations: [Annotation] = []
    private var undone: [Annotation] = []

    public init() {}

    public var canUndo: Bool { !annotations.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    /// Adding after an undo drops what could have been redone, as in every editor.
    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
        undone.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Annotation? {
        guard let last = annotations.popLast() else { return nil }
        undone.append(last)
        return last
    }

    @discardableResult
    public mutating func redo() -> Annotation? {
        guard let next = undone.popLast() else { return nil }
        annotations.append(next)
        return next
    }

    public mutating func removeAll() {
        annotations.removeAll()
        undone.removeAll()
    }

    /// One more than the highest counter on the canvas, so undoing ③ makes the next one ③ again (design doc §3.4).
    public var nextCounterNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case .counter(_, let number) = annotation.shape { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }
}
