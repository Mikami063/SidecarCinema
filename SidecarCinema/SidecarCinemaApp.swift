import SwiftUI

@main
struct SidecarCinemaApp: App {
    @StateObject private var cinema = CinemaController()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(cinema)
                .frame(minWidth: 520, minHeight: 430)
        }
        .windowResizability(.contentSize)
    }
}
