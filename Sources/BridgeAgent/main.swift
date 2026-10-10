import SwiftUI

@main
struct OM0RXXBridgeApp: App {
    @StateObject private var model = BridgeAppModel()

    var body: some Scene {
        WindowGroup("OM0RX-xBridge") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .defaultSize(width: 860, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
