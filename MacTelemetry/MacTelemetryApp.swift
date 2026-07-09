import SwiftUI

@main
struct MacTelemetryApp: App {
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            MenuBarIcon(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window("About MacTelemetry", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Sensors", id: "sensors") {
            SensorsView(monitor: monitor)
        }
        .windowResizability(.contentSize)

        Window("Graphs", id: "graphs") {
            GraphsWindowView(monitor: monitor)
        }
        .windowResizability(.contentMinSize)
    }
}
