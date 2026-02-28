import AppKit
import Combine

class ClipboardManager {
    static let shared = ClipboardManager()
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    
    private init() {
        lastChangeCount = pasteboard.changeCount
        startMonitoring()
    }
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        let currentChangeCount = pasteboard.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Get current app info
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName
        let bundleId = frontApp?.bundleIdentifier
        
        // Check for image first
        if let imageData = getImageData() {
            let item = ClipboardItem(
                imageData: imageData,
                appName: appName,
                appBundleIdentifier: bundleId
            )
            ClipboardStore.shared.add(item)
            return
        }
        
        // Check for text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let item = ClipboardItem(
                text: text,
                appName: appName,
                appBundleIdentifier: bundleId
            )
            ClipboardStore.shared.add(item)
        }
    }
    
    private func getImageData() -> Data? {
        // Try to get image from pasteboard
        if let tiffData = pasteboard.data(forType: .tiff) {
            if let image = NSImage(data: tiffData) {
                // Convert to PNG for storage
                if let tiffRep = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffRep),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    return pngData
                }
            }
        }
        
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }
        
        return nil
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
