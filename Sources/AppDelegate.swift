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
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
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
        
        // Set up global Cmd+M hotkey using CGEvent tap
        setupGlobalHotkey()
        
        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupGlobalHotkey() {
        // Create event tap to intercept Cmd+M globally
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        // Store self in a pointer for the callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                
                // Check for Cmd+M (keycode 46 = M)
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                if keyCode == 46 && flags.contains(.maskCommand) && !flags.contains(.maskShift) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate) {
                    // Cmd+M pressed - trigger show history on main thread
                    DispatchQueue.main.async {
                        appDelegate.showHistory()
                    }
                    // Return nil to consume the event (prevent minimize)
                    return nil
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        ) else {
            print("Failed to create event tap. Make sure Clippy has Accessibility permissions.")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
