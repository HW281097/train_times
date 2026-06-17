import SwiftUI

@main
struct LeaBoardApp: App {
    @State private var trainModel = DeparturesViewModel()
    @State private var busModel = BusViewModel()

    var body: some Scene {
        // Train board — amber, National Rail / Darwin.
        MenuBarExtra("LeaBoard", systemImage: "train.side.front.car") {
            DepartureBoardView(model: trainModel)
        }
        .menuBarExtraStyle(.window)

        // Bus board — TfL red, a second icon in the menu bar, same app.
        MenuBarExtra("LeaBoard Buses", systemImage: "bus.doubledecker.fill") {
            BusBoardView(model: busModel)
        }
        .menuBarExtraStyle(.window)
    }
}
