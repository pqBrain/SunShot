import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Colors & Fonts section: four colour tokens (well + HEX), chrome appearance, Text and Code fonts.
struct ColorTokenControls: View {
    let model: EditorModel

    private var tokens: DesignTokens { model.project.tokens }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ColorToken.allCases, id: \.self) { token in
                TokenColorRow(model: model, token: token)
            }

            HStack(spacing: 10) {
                ControlCaption(UIStrings.chromeLabel)
                Picker(
                    UIStrings.chromeLabel,
                    selection: Binding(
                        get: { tokens.chromeAppearance },
                        set: { value in model.perform { $0.setChromeAppearance(value) } })
                ) {
                    ForEach(ChromeAppearance.allCases, id: \.self) { Text(UIStrings.appearanceName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(UIStrings.chromeLabel)
                .accessibilityValue(UIStrings.appearanceName(tokens.chromeAppearance))
            }

            FontPickerRow(model: model, role: .text)
            FontPickerRow(model: model, role: .code)
            HStack {
                Spacer()
                Button(UIStrings.resetFonts) { model.perform { $0.resetFonts() } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }
}

struct TokenColorRow: View {
    let model: EditorModel
    let token: ColorToken
    @State private var hexText = ""

    private var color: RGBAColor { model.project.tokens.colors[token] }

    var body: some View {
        HStack(spacing: 10) {
            BackdropColorWell(
                model: model, title: UIStrings.tokenWell(token), color: color,
                actionName: EditorSession.tokenActionName(token)
            ) { session, picked in session.setTokenColor(token, picked) }
            Text(UIStrings.tokenName(token))
                .font(.callout)
                .frame(width: 84, alignment: .leading)
                .accessibilityHidden(true)
            TextField(UIStrings.hexField, text: $hexText)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .onSubmit { if !model.setTokenColor(token, hex: hexText) { hexText = color.hexString } }
                .accessibilityLabel("\(UIStrings.tokenWell(token)), \(UIStrings.hexField)")
        }
        .onAppear { hexText = color.hexString }
        .onChange(of: color) { _, value in hexText = value.hexString }
    }
}

struct FontPickerRow: View {
    let model: EditorModel
    let role: FontRole

    private var current: String { model.project.tokens.fonts[role] }

    var body: some View {
        HStack(spacing: 10) {
            ControlCaption(role == .text ? UIStrings.textFontLabel : UIStrings.codeFontLabel)
                .frame(width: 40, alignment: .leading)
            Menu {
                Section(UIStrings.recommendedFonts) { options(FontLibrary.recommended(role)) }
                Section(UIStrings.installedFonts) { options(FontLibrary.installed(role)) }
            } label: {
                Text(FontLibrary.displayName(current, role: role))
                    .foregroundStyle(
                        FontLibrary.isAvailable(current)
                            ? Color(nsColor: SunshotPalette.primaryText) : Color(nsColor: SunshotPalette.secondaryText))
            }
            .accessibilityLabel(UIStrings.fontPicker(role))
            .accessibilityValue(FontLibrary.displayName(current, role: role))
        }
    }

    @ViewBuilder
    private func options(_ list: [FontOption]) -> some View {
        ForEach(list) { option in
            Button {
                model.perform { $0.setFont(role, postScriptName: option.postScriptName) }
            } label: {
                if option.postScriptName == current {
                    Label(option.name, systemImage: "checkmark")
                } else {
                    Text(option.name)
                }
            }
        }
    }
}
