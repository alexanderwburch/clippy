import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showClipboardHistory = Self("showClipboardHistory")
}

@main
struct ClippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Show Clipboard History:", name: .showClipboardHistory)
        }
        .padding()
        .frame(width: 300)
    }
}
