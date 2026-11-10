import SwiftUI
import TipKit

// How to move the camera in each mode. The controls differ on Mac (keys and mouse) and iOS (touch).

struct BuildNavigationTip: Tip {
    var title: Text {
        Text("Look Around the Island")
    }

    var message: Text? {
        #if os(macOS)
        Text("""
        Drag to pan · Option-drag to orbit · Scroll to zoom
        W A S D or arrows pan · Q E rotate · R F zoom
        Painting tools paint when you drag on the island
        X to explore
        """)
        #else
        Text("""
        Drag to pan · Two-finger drag to orbit
        Pinch to zoom · Twist to rotate
        Painting tools paint when you drag on the island
        """)
        #endif
    }

    var image: Image? {
        Image(systemName: "map")
    }
}

struct ExploreNavigationTip: Tip {
    var title: Text {
        Text("Walk Through Town")
    }

    var message: Text? {
        #if os(macOS)
        Text("""
        W A S D to walk · Arrows or drag to look · Shift to hurry
        M to look with the mouse
        Space to stroll · F to fly · Esc to build
        """)
        #else
        Text("""
        Joystick to walk · Drag to look
        Stroll or Fly to let the town show itself
        """)
        #endif
    }

    var image: Image? {
        Image(systemName: "figure.walk")
    }
}
