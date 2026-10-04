import SwiftUI

@main
struct RumlogWavelogBridgeApp: App {
    @StateObject private var model = BridgeAppModel()

    var body: some Scene {
        WindowGroup("RUMlog–Wavelog Bridge") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .defaultSize(width: 860, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
