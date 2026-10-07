import SwiftUI
import ServiceManagement
import Combine

@main
struct GuardFaceApp: App {
    @StateObject private var controller = GuardController()

    var body: some Scene {
        // No Dock icon: the app lives in the menu bar
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: controller.isCovered ? "eye.slash.fill" : "eye.fill")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var controller: GuardController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(controller.statusText)

        Divider()

        Toggle("Enabled", isOn: $controller.isEnabled)

        Picker("When unattended", selection: $controller.action) {
            ForEach(GuardAction.allCases) { option in
                Text(option.title).tag(option)
            }
        }

        Picker("React after", selection: $controller.delay) {
            ForEach(ReactDelay.allCases) { option in
                Text(option.title).tag(option)
            }
        }

        Divider()

        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
