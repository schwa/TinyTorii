import SwiftUI

@main
struct TinyToriiApp: App {
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
