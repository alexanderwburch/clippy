import Foundation
import Combine

class HistoryViewModel: ObservableObject {
    static let shared = HistoryViewModel()
    
    @Published var selectedIndex = 0
    @Published var searchText = ""
    @Published var showStarredOnly = false
    @Published private var refreshTrigger = false
    
    private let store = ClipboardStore.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe store changes and trigger refresh
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshTrigger.toggle()
            }
            .store(in: &cancellables)
    }
    
    var filteredItems: [ClipboardItem] {
        // Access refreshTrigger to create dependency
        _ = refreshTrigger
        
        var results = store.search(searchText)
        if showStarredOnly {
            results = results.filter { $0.isStarred }
        }
        return results
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
