import Testing
@testable import GlimpseCore

private func key(_ k: KeyInput.Key, cmd: Bool = false, shift: Bool = false, opt: Bool = false, ctrl: Bool = false) -> KeyInput {
    KeyInput(key: k, command: cmd, shift: shift, option: opt, control: ctrl)
}

private func char(_ c: Character, cmd: Bool = false, shift: Bool = false, opt: Bool = false, ctrl: Bool = false) -> KeyInput {
    key(.character(c), cmd: cmd, shift: shift, opt: opt, ctrl: ctrl)
}

struct KeyRouterTests {
    // MARK: selecting phase
    @Test func selectingPhase() {
        let phase = EditorPhase.selecting
        #expect(KeyRouter.route(key(.escape), phase: phase) == .exit)
        #expect(KeyRouter.route(key(.space), phase: phase) == .selectFullScreen)
        #expect(KeyRouter.route(char("c"), phase: phase) == .copyColor(.hex))
        #expect(KeyRouter.route(key(.enter), phase: phase) == .finishCopy)
        #expect(KeyRouter.route(char("c", cmd: true), phase: phase) == .finishCopy)
        #expect(KeyRouter.route(char("s", cmd: true), phase: phase) == .save)
        #expect(KeyRouter.route(char("s"), phase: phase) == .ignore)
        #expect(KeyRouter.route(char("z", cmd: true), phase: phase) == .ignore)
        #expect(KeyRouter.route(key(.arrow(dx: 1, dy: 0)), phase: phase) == .ignore)
        #expect(KeyRouter.route(char("C"), phase: phase) == .copyColor(.hex)) // Caps Lock, no ⇧
    }

    @Test func shiftCCopiesTheRGBValueOnlyWhileSelecting() {
        #expect(KeyRouter.route(char("C", shift: true), phase: .selecting) == .copyColor(.rgb))
        #expect(KeyRouter.route(char("C", cmd: true, shift: true), phase: .selecting) == .finishCopy) // ⌘ wins
        #expect(KeyRouter.route(char("C", shift: true), phase: .editing(tool: nil)) == .ignore)
        #expect(KeyRouter.route(char("C", shift: true), phase: .editing(tool: .rectangle)) == .ignore)
    }

    // MARK: editing, typing layer — every key belongs to the text box except Esc
    @Test func typingLayerOwnsKeys() {
        let phase = EditorPhase.typing
        #expect(KeyRouter.route(char("r"), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(key(.enter), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(char("z", cmd: true), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(char("c", cmd: true), phase: phase) == .passToTextField)
        #expect(KeyRouter.route(key(.escape), phase: phase) == .endTyping)
        #expect(KeyRouter.route(key(.escape, cmd: true), phase: phase) == .endTyping)
    }

    // MARK: editing, tool selected
    @Test func toolLayer() {
        let phase = EditorPhase.editing(tool: .rectangle)
        #expect(KeyRouter.route(key(.escape), phase: phase) == .deselectTool)
        #expect(KeyRouter.route(char("r"), phase: phase) == .deselectTool)
        #expect(KeyRouter.route(char("a"), phase: phase) == .selectTool(.arrow))
        #expect(KeyRouter.route(key(.enter), phase: phase) == .finishCopy)
        #expect(KeyRouter.route(char("r", cmd: true), phase: phase) == .ignore)
    }

    // MARK: editing, no tool
    @Test func noToolLayer() {
        let phase = EditorPhase.editing(tool: nil)
        #expect(KeyRouter.route(key(.escape), phase: phase) == .exit)
        #expect(KeyRouter.route(key(.enter), phase: phase) == .finishCopy)
        #expect(KeyRouter.route(char("c", cmd: true), phase: phase) == .finishCopy)
        #expect(KeyRouter.route(char("s", cmd: true), phase: phase) == .save)
        #expect(KeyRouter.route(char("z", cmd: true), phase: phase) == .undo)
        #expect(KeyRouter.route(char("Z", cmd: true, shift: true), phase: phase) == .redo)
        #expect(KeyRouter.route(char("t"), phase: phase) == .selectTool(.text))
        #expect(KeyRouter.route(char("N"), phase: phase) == .selectTool(.counter))
        #expect(KeyRouter.route(key(.arrow(dx: 1, dy: 0), shift: true), phase: phase) == .nudge(dx: 1, dy: 0, large: true))
        #expect(KeyRouter.route(key(.arrow(dx: 0, dy: -1)), phase: phase) == .nudge(dx: 0, dy: -1, large: false))
        #expect(KeyRouter.route(char("x"), phase: phase) == .ignore)
        #expect(KeyRouter.route(char("r", opt: true), phase: phase) == .ignore)
        #expect(KeyRouter.route(char("r", ctrl: true), phase: phase) == .ignore)
        #expect(KeyRouter.route(char("c", cmd: true, opt: true), phase: phase) == .ignore)
        #expect(KeyRouter.route(key(.escape, opt: true), phase: phase) == .exit)
    }

    @Test func arrowsNudgeEvenWithToolSelected() {
        let phase = EditorPhase.editing(tool: .pen)
        #expect(KeyRouter.route(key(.arrow(dx: -1, dy: 0)), phase: phase) == .nudge(dx: -1, dy: 0, large: false))
    }

    // MARK: mouse rules
    @Test func rightClickStepsBack() {
        #expect(KeyRouter.rightClick(phase: .selecting) == .exit)
        #expect(KeyRouter.rightClick(phase: .editing(tool: .arrow)) == .reselect)
        #expect(KeyRouter.rightClick(phase: .editing(tool: nil)) == .reselect)
    }

    @Test func doubleClickFinishesOnlyWithoutTool() {
        #expect(KeyRouter.doubleClickFinishes(phase: .editing(tool: nil)))
        #expect(!KeyRouter.doubleClickFinishes(phase: .editing(tool: .counter)))
        #expect(!KeyRouter.doubleClickFinishes(phase: .typing))
        #expect(!KeyRouter.doubleClickFinishes(phase: .selecting))
    }

    @Test func toolShortcuts() {
        #expect(Tool.allCases.map(\.shortcut) == ["r", "o", "a", "p", "t", "m", "n"])
        #expect(Tool(shortcut: "M") == .mosaic)
        #expect(Tool(shortcut: "q") == nil)
    }
}
