import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Circular pad with a draggable "sun": where the light comes from. The shadow falls the opposite way.
/// Arrow keys nudge it (⇧ for bigger steps); VoiceOver can adjust it.
struct LightSourcePad: View {
    let model: EditorModel
    @FocusState private var isFocused: Bool
    @State private var isDragging = false

    private let diameter: CGFloat = 112
    private var position: UnitOffset { model.project.shadow.lightPosition }

    var body: some View {
        let radius = diameter / 2
        ZStack {
            Circle().fill(.black.opacity(0.08))
            Circle().strokeBorder(Color(nsColor: SunshotPalette.controlStroke), lineWidth: 1.5)
            Path { path in
                path.move(to: CGPoint(x: radius, y: 8))
                path.addLine(to: CGPoint(x: radius, y: diameter - 8))
                path.move(to: CGPoint(x: 8, y: radius))
                path.addLine(to: CGPoint(x: diameter - 8, y: radius))
            }
            .stroke(Color(nsColor: SunshotPalette.controlStroke).opacity(0.5), lineWidth: 1)
            // Mini preview: a card whose shadow follows the handle.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white)
                .frame(width: 34, height: 24)
                .shadow(color: .black.opacity(0.45), radius: 4, x: -position.x * 8, y: -position.y * 8)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 18))
                .foregroundStyle(.yellow, .orange)
                .shadow(color: .orange.opacity(0.6), radius: isDragging ? 8 : 4)
                .position(x: radius + position.x * (radius - 12), y: radius + position.y * (radius - 12))
        }
        .frame(width: diameter, height: diameter)
        .contentShape(.circle)
        .overlay { if isFocused { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
        .gesture(dragGesture(radius: radius))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let large = press.modifiers.contains(.shift)
            switch press.key {
            case .leftArrow: model.nudgeLight(dx: -1, dy: 0, large: large)
            case .rightArrow: model.nudgeLight(dx: 1, dy: 0, large: large)
            case .upArrow: model.nudgeLight(dx: 0, dy: -1, large: large)
            default: model.nudgeLight(dx: 0, dy: 1, large: large)
            }
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(UIStrings.lightDirection(position))
        .accessibilityAdjustableAction { direction in
            model.nudgeLight(dx: direction == .increment ? 1 : -1, dy: 0, large: true)
        }
        .help("Drag the sun to move the light. The shadow falls the other way.")
    }

    private func dragGesture(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    model.beginGesture()
                }
                let usable = radius - 12
                let point = UnitOffset(
                    x: (value.location.x - radius) / usable, y: (value.location.y - radius) / usable)
                model.perform { $0.setLightPosition(point) }
            }
            .onEnded { _ in
                isDragging = false
                model.endGesture(EditorSession.lightActionName)
            }
    }
}
