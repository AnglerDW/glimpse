import AppKit
import GlimpseCore
import SwiftUI

/// The settings page (design doc §3.9): a grouped form, like System Settings, tinted with the interface accent.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                shortcutRow(String(localized: "截图", comment: "Settings: shortcut row label for the screenshot"), action: .screenshot)
                shortcutRow(String(localized: "提取文字", comment: "Shortcut row / menu item / toolbar button / panel title: extract text (OCR)"), action: .ocr)
            } header: {
                Text(String(localized: "快捷键", comment: "Settings section header"))
            } footer: {
                Text(String(localized: "按快捷键没反应时，可能被微信、QQ 等应用的截图快捷键占用，请在那边改掉，或在这里换一个",
                            comment: "Settings: shortcuts section footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(String(localized: "界面强调色", comment: "Settings: accent colour row")) {
                    AccentSwatches(selection: model.accent) { model.setAccent($0) }
                }
            } header: {
                Text(String(localized: "外观", comment: "Settings section header"))
            } footer: {
                Text(String(localized: "用于选区边框、手柄、选中的按钮和 ✓，以及 Glimpse 自己的窗口，不影响标注颜色",
                            comment: "Settings: appearance section footer"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "settings.section.save", defaultValue: "保存", comment: "Settings section header (source text 保存)")) {
                LabeledContent(String(localized: "保存目录", comment: "Settings: save folder row")) {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: model.saveDirectory.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(model.saveDirectoryName)
                            .help(model.saveDirectory.path)
                        Button(String(localized: "更改…", comment: "Settings: change the save folder")) { model.chooseSaveDirectory() }
                    }
                }
            }

            Section(String(localized: "通用", comment: "Settings section header")) {
                languageRow
                Toggle(String(localized: "开机自动启动", comment: "Launch at login switch"), isOn: Binding(get: { model.launchAtLogin },
                                                  set: { model.setLaunchAtLogin($0) }))
                if let error = model.loginItemError {
                    HStack {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                        if model.loginItemNeedsApproval {
                            Spacer()
                            Button(String(localized: "打开登录项设置", comment: "Opens System Settings → Login Items")) { LoginItemService.openSystemSettings() }
                        }
                    }
                }
            }

            Section(String(localized: "关于", comment: "Settings section header")) {
                LabeledContent {
                    Text(model.version)
                        .monospacedDigit()
                        .textSelection(.enabled)
                } label: {
                    Text("Glimpse")
                    if let copyright = model.copyright {
                        Text(copyright) // the second text is the row's secondary line
                    }
                }
                Text(String(localized: "截图、标注、提取文字都在本机完成，不联网，也不保存截图历史。", comment: "About: privacy note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Glimpse's own windows follow the interface accent too (design doc §3.9): the switch, the
        // focus ring; nil keeps the system accent.
        .tint(model.accent.tint)
        .frame(width: 480, height: 600)
    }

    /// 「语言」: a popup of the system choice and the 11 shipped languages, each in its own name; a change needs
    /// a relaunch, so a hint and 「重新启动 Glimpse」 appear until the choice matches the running language again.
    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(String(localized: "语言", comment: "Settings: interface language row"),
                   selection: Binding(get: { model.interfaceLanguage }, set: { model.setInterfaceLanguage($0) })) {
                Text(InterfaceLanguage.system.title).tag(InterfaceLanguage.system)
                Divider()
                ForEach(InterfaceLanguage.allCases.filter { $0 != .system }, id: \.self) { language in
                    Text(language.title).tag(language)
                }
            }
            if model.needsRelaunchForLanguage {
                HStack {
                    Text(String(localized: "重新启动 Glimpse 后生效", comment: "Settings: language change needs a relaunch"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "重新启动 Glimpse", comment: "Onboarding: restart button")) { model.relaunch() }
                        .buttonStyle(.borderedProminent) // filled with the form's tint: the interface accent
                }
                if model.relaunchFailed {
                    Text(String(localized: "无法自动重启，请手动退出后重新打开", comment: "Onboarding: relaunch failed"))
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func shortcutRow(_ title: String, action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    HotkeyRecorder(combo: model.combo(for: action),
                                   otherCombo: model.combo(for: action == .screenshot ? .ocr : .screenshot),
                                   onRecordingChange: { model.recordingChanged($0, for: action) },
                                   onOutcome: { model.apply($0, for: action) })
                        .frame(width: 140)
                    Button {
                        model.apply(.clear, for: action)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "清除", comment: "Clears the shortcut"))
                    .opacity(model.combo(for: action) == nil ? 0 : 1)
                    .disabled(model.combo(for: action) == nil)
                }
            }
            if let error = model.hotkeyErrors[action] {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// The recorder button inside the form.
private struct HotkeyRecorder: NSViewRepresentable {
    let combo: KeyCombo?
    let otherCombo: KeyCombo?
    let onRecordingChange: (Bool) -> Void
    let onOutcome: (HotkeyRecording.Outcome) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        HotkeyRecorderButton()
    }

    func updateNSView(_ button: HotkeyRecorderButton, context: Context) {
        button.combo = combo
        button.otherCombo = otherCombo
        button.onRecordingChange = onRecordingChange
        button.onOutcome = onOutcome
    }
}

/// 跟随系统 and the presets as colour dots, like the accent row in System Settings. The chosen dot has a
/// white centre; the name shows on hover.
private struct AccentSwatches: View {
    let selection: AccentColor
    let onPick: (AccentColor) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentColor.allCases, id: \.self) { accent in
                Button {
                    onPick(accent)
                } label: {
                    swatch(accent)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if accent == selection {
                                Circle().fill(.white).frame(width: 6, height: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(accent.title)
                .accessibilityLabel(accent.title)
                .accessibilityAddTraits(accent == selection ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func swatch(_ accent: AccentColor) -> some View {
        if accent == .system {
            Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                          center: .center))
        } else {
            Circle().fill(accent.tint ?? Color(nsColor: .controlAccentColor))
        }
    }
}
