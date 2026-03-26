import Foundation
import Combine

class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()
    
    @Published private(set) var items: [ClipboardItem] = []
    
    private let maxItems = 5000
    private let saveURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clippyDir = appSupport.appendingPathComponent("Clippy", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: clippyDir, withIntermediateDirectories: true)
        
        saveURL = clippyDir.appendingPathComponent("history.json")
        load()
    }
    
    func add(_ item: ClipboardItem) {
        // Avoid duplicates - remove existing item with same content (but preserve starred status)
        var wasStarred = false
        items.removeAll { existing in
            if let newText = item.text, let existingText = existing.text, newText == existingText {
                wasStarred = existing.isStarred
                return true
            }
            if let newImage = item.imageData, let existingImage = existing.imageData, newImage == existingImage {
                wasStarred = existing.isStarred
                return true
            }
            return false
        }
        
        // Add to front (preserve starred status if it was starred before)
        var newItem = item
        if wasStarred {
            newItem.isStarred = true
        }
        items.insert(newItem, at: 0)
        
        // Trim to max size, but keep starred items
        trimToMaxSize()
        
        save()
    }
    
    private func trimToMaxSize() {
        // Separate starred and non-starred items
        let starred = items.filter { $0.isStarred }
        var nonStarred = items.filter { !$0.isStarred }
        
        // Only trim non-starred items
        let maxNonStarred = maxItems - starred.count
        if nonStarred.count > maxNonStarred && maxNonStarred > 0 {
            nonStarred = Array(nonStarred.prefix(maxNonStarred))
        }
        
        // Reconstruct items list maintaining order
        items = items.filter { item in
            starred.contains { $0.id == item.id } || nonStarred.contains { $0.id == item.id }
        }
    }
    
    func toggleStar(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isStarred.toggle()
            save()
        }
    }
    
    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }
    
    func clear() {
        items.removeAll()
        save()
    }
    
    func search(_ query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        
        let lowercased = query.lowercased()
        return items.filter { item in
            if let text = item.text?.lowercased() {
                return text.contains(lowercased)
            }
            if let appName = item.appName?.lowercased() {
                return appName.contains(lowercased)
            }
            return false
        }
    }
    
    private func save() {
        // Snapshot items on the main thread to avoid data race
        let snapshot = items
        let url = saveURL
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("Failed to save clipboard history: \(error)")
            }
        }
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            items = []
        }
    }
}
