import SwiftUI

@main
struct TinyToriiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 900)
        #endif
    }
}
