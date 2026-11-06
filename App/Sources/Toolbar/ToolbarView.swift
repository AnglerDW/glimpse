import AppKit
import GlimpseCore

@MainActor
protocol ToolbarViewDelegate: AnyObject {
    func toolbarView(_ view: ToolbarView, didPress item: ToolbarItem)
    /// Show the tooltip for `item` next to `buttonFrame` (in the toolbar's coordinates), or hide it (nil).
    func toolbarView(_ view: ToolbarView, showToolTipFor item: ToolbarItem?, buttonFrame: CGRect)
}

/// The editing toolbar (design doc §3.3): one row of 30pt buttons on the material, groups split
/// by separators. Sizes itself in `init`; the overlay only positions it.
/// Metrics follow the mockup's `.tb`: 6pt above and below, 8pt at the ends, 2pt between items,
/// and 5pt more on each side of a separator.
final class ToolbarView: MaterialView {
    weak var delegate: ToolbarViewDelegate?

    private static let verticalPadding: CGFloat = 6
    private static let horizontalPadding: CGFloat = 8
    private static let spacing: CGFloat = 2
    private static let separatorMargin: CGFloat = 5

    private var buttons: [ToolbarItem: ToolbarButton] = [:]

    private struct State: Equatable {
        let selectedTool: Tool?
        let canUndo: Bool
        let canRedo: Bool
    }
    private var appliedState: State?

    init() {
        super.init(cornerRadius: 12)
        let height = ToolbarButton.side + Self.verticalPadding * 2
        var x = Self.horizontalPadding
        for (index, group) in ToolbarItem.groups.enumerated() {
            if index > 0 {
                let separator = MaterialSeparatorView(origin: CGPoint(
                    x: x + Self.separatorMargin, y: (height - MaterialSeparatorView.size.height) / 2))
                contentView.addSubview(separator)
                x += Self.separatorMargin * 2 + MaterialSeparatorView.size.width + Self.spacing
            }
            for item in group {
                let button = ToolbarButton(item: item, target: self, action: #selector(buttonPressed(_:)))
                button.onHover = { [weak self] button, hovering in self?.hoverChanged(button, hovering: hovering) }
                button.frame.origin = CGPoint(x: x, y: Self.verticalPadding)
                contentView.addSubview(button)
                buttons[item] = button
                x += ToolbarButton.side + Self.spacing
            }
        }
        x -= Self.spacing
        frame.size = CGSize(width: x + Self.horizontalPadding, height: height)
        update(selectedTool: nil, canUndo: false, canRedo: false)
    }

    /// Selected tool and undo / redo availability.
    func update(selectedTool: Tool?, canUndo: Bool, canRedo: Bool) {
        let state = State(selectedTool: selectedTool, canUndo: canUndo, canRedo: canRedo)
        guard state != appliedState else { return } // layout runs often; the buttons rarely change
        appliedState = state
        for tool in Tool.allCases {
            buttons[.tool(tool)]?.isSelectedTool = tool == selectedTool
        }
        buttons[.undo]?.isEnabled = canUndo
        buttons[.redo]?.isEnabled = canRedo
    }

    /// The toolbar moved or hid without the mouse moving: drop every hover and pending tooltip.
    func resetHover() {
        buttons.values.forEach { $0.resetHover() }
    }

    private func hoverChanged(_ button: ToolbarButton, hovering: Bool) {
        delegate?.toolbarView(self, showToolTipFor: hovering ? button.item : nil,
                              buttonFrame: convert(button.frame, from: contentView))
    }

    @objc private func buttonPressed(_ sender: ToolbarButton) {
        delegate?.toolbarView(self, didPress: sender.item)
    }
}
