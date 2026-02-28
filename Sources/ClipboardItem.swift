import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String?
    let imageData: Data?
    let timestamp: Date
    let appName: String?
    let appBundleIdentifier: String?
    var isStarred: Bool
    
    init(id: UUID = UUID(), text: String? = nil, imageData: Data? = nil, timestamp: Date = Date(), appName: String? = nil, appBundleIdentifier: String? = nil, isStarred: Bool = false) {
        self.id = id
        self.text = text
        self.imageData = imageData
        self.timestamp = timestamp
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.isStarred = isStarred
    }
    
    var displayText: String {
        if let text = text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 200 {
                return String(trimmed.prefix(200)) + "..."
            }
            return trimmed
        }
        if imageData != nil {
            return "[Image]"
        }
        return "[Unknown]"
    }
    
    var previewText: String {
        if let text = text {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if imageData != nil {
            return "[Image copied to clipboard]"
        }
        return "[Unknown content]"
    }
    
    var isImage: Bool {
        imageData != nil
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
