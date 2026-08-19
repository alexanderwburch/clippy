import AppKit
import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var clipboardManager: ClipboardManager!
    private var historyWindow: NSWindow?
    private var windowObserver: Any?
    private var keyMonitor: Any?
    private let viewModel = HistoryViewModel.shared
    private var previousApp: NSRunningApplication?
    /// Ensures the Accessibility prompt is shown at most once per launch.
    private var hasPromptedForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clippy")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show History (⌘M)", action: #selector(showHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Clippy", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        // Initialize clipboard manager
        clipboardManager = ClipboardManager.shared
        
        // Initialize shell history monitor
        _ = ShellHistoryMonitor.shared
        
        // Global hotkey via Carbon RegisterEventHotKey (through KeyboardShortcuts).
        //
        // This deliberately replaces the old CGEvent tap. A tap requires Accessibility
        // trust, and Clippy is ad-hoc signed, so every rebuild changes the CDHash and
        // silently invalidates the grant — the app kept running and capturing while ⌘M
        // went dead, which is indistinguishable from a crash. Carbon hotkeys need no
        // TCC permission at all, survive rebuilds and sleep/wake, and can't be disabled
        // by the system the way a tap can. That removes the tap, its 5s health timer,
        // and the wake-recreate dance along with the whole class of bugs they existed
        // to paper over.
        setupGlobalHotkey()

        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any coalesced clipboard save so the last changes aren't lost on quit.
        ClipboardStore.shared.flush()
    }

    private func setupGlobalHotkey() {
        // The Settings window has always shown a KeyboardShortcuts.Recorder bound to
        // .showClipboardHistory, but nothing ever registered a handler for it — the
        // recorder was dead UI and the real hotkey was the CGEvent tap. Register the
        // handler so the recorder works, and seed ⌘M as the default the first time.
        if KeyboardShortcuts.getShortcut(for: .showClipboardHistory) == nil {
            KeyboardShortcuts.setShortcut(.init(.m, modifiers: [.command]), for: .showClipboardHistory)
        }

        KeyboardShortcuts.onKeyDown(for: .showClipboardHistory) { [weak self] in
            self?.showHistory()
        }
    }

    /// Shows the system Accessibility prompt and points the user at the settings pane.
    /// Only auto-paste needs this now — the hotkey itself no longer does.
    private func promptForAccessibilityOnce() {
        guard !hasPromptedForAccessibility else { return }
        hasPromptedForAccessibility = true

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if AXIsProcessTrustedWithOptions(options as CFDictionary) { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Clippy can't paste automatically"
            alert.informativeText = """
                Your clipboard history still works — the item you picked has been copied, \
                so you can press ⌘V yourself.

                To have Clippy paste for you, enable it in Privacy & Security → \
                Accessibility. If Clippy is already listed, remove it with the “−” button \
                and add it again — a rebuilt copy won't be trusted by the old entry.
                """
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc func showHistory() {
        // Remember which app was active before we show
        previousApp = NSWorkspace.shared.frontmostApplication
        
        // Always clean up first, then create fresh
        cleanupWindow()
        
        // Small delay to ensure cleanup is complete
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow()
        }
    }
    
    private func cleanupWindow() {
        // Remove key monitor
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        
        // Remove window observer
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        
        // Close existing window
        historyWindow?.orderOut(nil)
        historyWindow = nil
    }
    
    private func createAndShowWindow() {
        // Reset view model state
        viewModel.reset()
        
        let contentView = ClipboardHistoryView(
            viewModel: viewModel,
            onSelect: { [weak self] item in
                self?.pasteItem(item)
            }
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.level = .floating
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        
        historyWindow = window
        
        // Close when window loses focus
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.dismissHistory()
        }
        
        // Monitor for keyboard navigation
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            switch event.keyCode {
            case 53: // Escape
                self.dismissHistory()
                return nil
            case 126: // Up arrow
                self.viewModel.moveUp()
                return nil
            case 125: // Down arrow
                self.viewModel.moveDown()
                return nil
            case 36: // Enter/Return
                if let item = self.viewModel.selectedItem {
                    self.pasteItem(item)
                }
                return nil
            default:
                return event
            }
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func dismissHistory() {
        cleanupWindow()
    }
    
    func pasteItem(_ item: ClipboardItem) {
        // Copy to clipboard first
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if let imageData = item.imageData, let image = NSImage(data: imageData) {
            pasteboard.writeObjects([image])
        } else if let text = item.text {
            pasteboard.setString(text, forType: .string)
        }

        // Claim this write before the 50ms poller can see it. Otherwise the poller treats
        // the entry we just staged as a new external copy, re-runs the quote-strip, and
        // rewrites the pasteboard out from under the synthetic ⌘V posted below.
        ClipboardManager.shared.registerSelfWrite()

        // Store the previous app before dismissing
        let appToActivate = previousApp
        
        // Close the window
        dismissHistory()
        
        // Activate the previous app and paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Activate the previous app
            appToActivate?.activate(options: .activateIgnoringOtherApps)
            
            // Wait a bit for the app to become active, then paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Posting synthetic key events still requires Accessibility (opening the
                // window no longer does). Without it the post is silently swallowed, so
                // say so once rather than looking broken — the item is already on the
                // clipboard either way, so ⌘V by hand works.
                guard AXIsProcessTrusted() else {
                    self.promptForAccessibilityOnce()
                    return
                }

                let source = CGEventSource(stateID: .hidSystemState)

                // Key code 9 = V key
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                keyDown?.flags = .maskCommand
                keyDown?.post(tap: .cghidEventTap)

                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                keyUp?.flags = .maskCommand
                keyUp?.post(tap: .cghidEventTap)
            }
        }
    }
    
    @objc func clearHistory() {
        ClipboardStore.shared.clear()
    }
    
    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
