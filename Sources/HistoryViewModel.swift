import Foundation
import Combine

class HistoryViewModel: ObservableObject {
    static let shared = HistoryViewModel()

    @Published var selectedIndex = 0
    @Published var searchText = ""
    @Published var showStarredOnly = false
    @Published private(set) var filteredItems: [ClipboardItem] = []

    private let store = ClipboardStore.shared

    init() {
        Publishers.CombineLatest3(
            store.$items,
            $searchText.removeDuplicates(),
            $showStarredOnly.removeDuplicates()
        )
        .map { items, query, starredOnly -> [ClipboardItem] in
            let base = starredOnly ? items.filter { $0.isStarred } : items
            guard !query.isEmpty else { return base }
            return base.filter { item in
                if let text = item.text, text.range(of: query, options: .caseInsensitive) != nil {
                    return true
                }
                if let appName = item.appName, appName.range(of: query, options: .caseInsensitive) != nil {
                    return true
                }
                return false
            }
        }
        .receive(on: DispatchQueue.main)
        .assign(to: &$filteredItems)
    }

    var selectedItem: ClipboardItem? {
        filteredItems[safe: selectedIndex]
    }

    func moveUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveDown() {
        if selectedIndex < filteredItems.count - 1 {
            selectedIndex += 1
        }
    }

    func toggleStarSelected() {
        if let item = selectedItem {
            store.toggleStar(item)
        }
    }

    func reset() {
        selectedIndex = 0
        searchText = ""
        showStarredOnly = false
    }
}
