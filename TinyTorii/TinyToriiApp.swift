import SwiftUI
import TipKit

@main
struct TinyToriiApp: App {
    init() {
        #if DEBUG
        // Show tips again on every launch while developing.
        try? Tips.resetDatastore()
        #endif
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
            #else
            ContentView()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 900)
        #endif
    }
}
