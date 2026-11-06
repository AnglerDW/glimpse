import AppKit

/// One line of text on the shared material: the selection's pixel size and the toolbar's tooltips. Clicks pass through it to the selection view underneath.
/// Metrics follow the mockup's `.size`: 4pt above and below the text, 9pt at the ends, and the toolbar's
/// 12pt corner, which on a label this short makes it nearly a capsule.
final class GlassLabelView: MaterialView {
    private static let verticalPadding: CGFloat = 4
    private static let horizontalPadding: CGFloat = 9
    private static let maxCornerRadius: CGFloat = 12

    private let label = NSTextField(labelWithString: "")

    init(font: NSFont) {
        super.init(cornerRadius: Self.maxCornerRadius)
        label.font = font
        label.textColor = .materialText
        contentView.addSubview(label)
    }

    /// Updates the text and resizes to fit it.
    func setText(_ text: String) {
        label.stringValue = text
        let size = label.intrinsicContentSize
        let width = ceil(size.width), height = ceil(size.height)
        label.frame = CGRect(x: Self.horizontalPadding, y: Self.verticalPadding, width: width, height: height)
        frame.size = CGSize(width: width + Self.horizontalPadding * 2, height: height + Self.verticalPadding * 2)
        cornerRadius = min(Self.maxCornerRadius, frame.height / 2)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
