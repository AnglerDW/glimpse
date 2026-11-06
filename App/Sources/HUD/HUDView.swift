import AppKit
import GlimpseCore

/// The HUD's content (design doc §3.8.1): an SF Symbol and one line of text on a glass capsule.
/// Sizes itself to the text when created, at most `maxWidth` wide (longer text is truncated in the middle).
final class HUDView: MaterialView {
    private static let height: CGFloat = 36
    private static let horizontalPadding: CGFloat = 14
    private static let iconSide: CGFloat = 18
    private static let iconTextGap: CGFloat = 7
    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

    init(message: HUDMessage, maxWidth: CGFloat) {
        super.init(cornerRadius: Self.height / 2)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: message.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(Self.symbolConfiguration)
        icon.contentTintColor = message.isFailure ? .systemOrange : .materialText
        icon.imageScaling = .scaleProportionallyDown
        let label = NSTextField(labelWithString: message.text)
        label.font = Self.font
        label.textColor = .materialText
        label.lineBreakMode = .byTruncatingMiddle
        // The cell size includes the label's own inset on each side (intrinsicContentSize does not, which
        // clipped the text). The label is shifted left by that inset so the visible text keeps the padding.
        let inset = NSTextField.labelTextInset
        let cell = label.cell?.cellSize ?? label.intrinsicContentSize
        let textHeight = ceil(cell.height)
        let padding = Self.horizontalPadding, iconSide = Self.iconSide
        let textX = padding + iconSide + Self.iconTextGap
        let fullWidth = textX + ceil(cell.width) - inset * 2 + padding
        let width = min(fullWidth, floor(maxWidth))
        icon.frame = CGRect(x: padding, y: (Self.height - iconSide) / 2, width: iconSide, height: iconSide)
        label.frame = CGRect(x: textX - inset, y: ((Self.height - textHeight) / 2).rounded(),
                             width: width - textX - padding + inset * 2, height: textHeight)
        contentView.addSubview(icon)
        contentView.addSubview(label)
        frame.size = CGSize(width: width, height: Self.height)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(message.text)
    }
}
