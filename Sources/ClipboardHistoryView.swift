import SwiftUI
import AppKit

struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let onSelect: (ClipboardItem) -> Void
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Search clipboard history...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFocused)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Favorites filter toggle
                Button(action: { 
                    viewModel.showStarredOnly.toggle()
                    viewModel.selectedIndex = 0
                }) {
                    Image(systemName: viewModel.showStarredOnly ? "star.fill" : "star")
                        .foregroundColor(viewModel.showStarredOnly ? .yellow : .secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Show starred only (F)")
                
                Text("\(viewModel.filteredItems.count) items")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Items list
            if viewModel.filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.searchText.isEmpty ? "No clipboard history yet" : "No matching items")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    if viewModel.searchText.isEmpty {
                        Text("Copy something to get started!")
                            .font(.system(size: 12))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemRow(
                                    item: item,
                                    isSelected: index == viewModel.selectedIndex,
                                    index: index,
                                    onToggleStar: { ClipboardStore.shared.toggleStar(item) }
                                )
                                .id(item.id)
                                .onTapGesture(count: 2) {
                                    onSelect(item)
                                }
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                }
                                .contextMenu {
                                    Button("Copy") {
                                        onSelect(item)
                                    }
                                    Button(item.isStarred ? "Unstar" : "Star") {
                                        ClipboardStore.shared.toggleStar(item)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        ClipboardStore.shared.remove(item)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .onChange(of: viewModel.selectedIndex) { newValue in
                        if let item = viewModel.filteredItems[safe: newValue] {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Footer with hints
            HStack(spacing: 16) {
                KeyHint(keys: ["↑", "↓"], action: "navigate")
                KeyHint(keys: ["↵"], action: "paste")
                KeyHint(keys: ["esc"], action: "close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: viewModel.searchText) { _ in
            viewModel.selectedIndex = 0
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let index: Int
    let onToggleStar: () -> Void
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.timestamp, relativeTo: Date())
    }
    
    private var previewText: String {
        guard let text = item.text else { return "[Unknown]" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = isSelected ? 300 : 100
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength)) + "..."
        }
        return trimmed
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Index indicator with star
            ZStack {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                
                if item.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                        .offset(x: 10, y: -6)
                }
            }
            .frame(width: 28)
            
            // Content preview
            VStack(alignment: .leading, spacing: 4) {
                if item.isImage, let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: isSelected ? 100 : 60)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(previewText)
                        .font(.system(size: 13))
                        .lineLimit(isSelected ? 6 : 2)
                        .foregroundColor(.primary)
                }
                
                HStack(spacing: 8) {
                    if let appName = item.appName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    
                    Text(timeAgo)
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    
                    if let text = item.text {
                        Text("\(text.count) chars")
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            }
            
            Spacer()
            
            // Star button
            Button(action: onToggleStar) {
                Image(systemName: item.isStarred ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundColor(item.isStarred ? .yellow : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(item.isStarred ? "Unstar" : "Star")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct KeyHint: View {
    let keys: [String]
    let action: String
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .tertiaryLabelColor).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            
            Text(action)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
