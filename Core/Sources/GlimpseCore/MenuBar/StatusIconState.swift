/// What the menu bar icon shows (design doc §3.7): one of six scenes, picked from `StatusIconInputs` by
/// priority. The frames and their rhythm are `StatusIconTimeline`; drawing lives in the app (`StatusIcon`).
public enum StatusIconState: Equatable, Sendable {
    /// Nothing else applies: the viewfinder corners and the centre dot.
    case idle
    /// A copy, save or pin just worked: the ✓ flash. The app ends it after `StatusIconTimeline.doneDuration`.
    case done
    /// 提取文字 is running: three text rows and a scan line.
    case recognizing
    /// The settings page records a shortcut (the global shortcuts are suspended): ripples from the centre.
    case recordingHotkey
    /// At least one pin is on screen: a dot in the top-right corner. The count itself only matters to the
    /// 「关闭所有贴图 (N)」 menu item, which gets it straight from `StatusIconInputs.pinCount`.
    case pinned
    /// The Screen Recording permission is missing, or the last capture was refused (§3.8): the ⚠ corner.
    case needsPermission
}

/// Everything that can make the icon change, kept by `StatusItemController`; `StatusIconState.resolve`
/// picks the scene.
public struct StatusIconInputs: Equatable, Sendable {
    public var needsPermission: Bool
    /// `flashDone()` was called less than `StatusIconTimeline.doneDuration` ago.
    public var isDoneFlashing: Bool
    public var isRecognizing: Bool
    public var isRecordingHotkey: Bool
    public var pinCount: Int

    public init(needsPermission: Bool = false, isDoneFlashing: Bool = false, isRecognizing: Bool = false,
                isRecordingHotkey: Bool = false, pinCount: Int = 0) {
        self.needsPermission = needsPermission
        self.isDoneFlashing = isDoneFlashing
        self.isRecognizing = isRecognizing
        self.isRecordingHotkey = isRecordingHotkey
        self.pinCount = pinCount
    }

    /// Whether the pin dot belongs on the icon; its pop plays once, when this turns true (design doc §3.7).
    public var hasPins: Bool { pinCount >= 1 }
}

extension StatusIconState {
    /// The scene for `inputs`. When several apply, the first of needsPermission > done > recognizing >
    /// recordingHotkey > pinned wins; `idle` when none does. A pin count below 1 never counts as pinned.
    public static func resolve(_ inputs: StatusIconInputs) -> StatusIconState {
        if inputs.needsPermission { return .needsPermission }
        if inputs.isDoneFlashing { return .done }
        if inputs.isRecognizing { return .recognizing }
        if inputs.isRecordingHotkey { return .recordingHotkey }
        if inputs.hasPins { return .pinned }
        return .idle
    }
}
