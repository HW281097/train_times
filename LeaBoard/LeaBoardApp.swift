import SwiftUI

@main
struct LeaBoardApp: App {
    @State private var model = DeparturesViewModel()

    var body: some Scene {
        MenuBarExtra("LeaBoard", systemImage: "train.side.front.car") {
            DepartureBoardView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
