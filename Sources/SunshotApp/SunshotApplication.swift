import SunshotCore
import SunshotRender
import SwiftUI

struct SunshotApplication: App {
    var body: some Scene {
        WindowGroup("Sunshot") {
            PlaceholderCanvasView()
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}

/// S0 placeholder: shows the sample render through the shared renderer. Replaced in S1.
struct PlaceholderCanvasView: View {
    private let image: CGImage? = try? Renderer.render(project: Project(), content: SampleContent.image(), scale: 2)

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(24)
                    .accessibilityLabel("Canvas preview")
            } else {
                Text("Rendering failed")
            }
        }
    }
}
