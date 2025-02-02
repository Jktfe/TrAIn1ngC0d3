import SwiftUI

@main
struct TrAIn1ngC0d3App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    if let window = NSApplication.shared.windows.first {
                        window.appearance = NSAppearance(named: .vibrantLight)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}