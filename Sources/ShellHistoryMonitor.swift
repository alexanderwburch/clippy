import Foundation

class ShellHistoryMonitor {
    static let shared = ShellHistoryMonitor()
    
    private var timer: Timer?
    private var lastBashCount: Int = 0
    private var lastZshCount: Int = 0
    private var knownCommands: Set<String> = []
    
    private let bashHistoryPath = NSHomeDirectory() + "/.bash_history"
    private let zshHistoryPath = NSHomeDirectory() + "/.zsh_history"
    
    private init() {
        // Initialize known commands from existing clipboard items
        for item in ClipboardStore.shared.items {
            if let text = item.text {
                knownCommands.insert(text)
            }
        }
        
        // Get initial line counts
        lastBashCount = countLines(at: bashHistoryPath)
        lastZshCount = countLines(at: zshHistoryPath)
        
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Check every 30 seconds for new shell history
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkForNewCommands()
        }
    }
    
    private func countLines(at path: String) -> Int {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return 0
        }
        return content.components(separatedBy: .newlines).count
    }
    
    private func checkForNewCommands() {
        checkBashHistory()
        checkZshHistory()
    }
    
    private func checkBashHistory() {
        guard FileManager.default.fileExists(atPath: bashHistoryPath) else { return }
        
        let currentCount = countLines(at: bashHistoryPath)
        guard currentCount > lastBashCount else { return }
        
        // Read new lines
        guard let content = try? String(contentsOfFile: bashHistoryPath, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        
        let newLines = Array(lines.suffix(currentCount - lastBashCount))
        lastBashCount = currentCount
        
        for line in newLines {
            addCommand(line.trimmingCharacters(in: .whitespacesAndNewlines), from: "bash")
        }
    }
    
    private func checkZshHistory() {
        guard FileManager.default.fileExists(atPath: zshHistoryPath) else { return }
        
        let currentCount = countLines(at: zshHistoryPath)
        guard currentCount > lastZshCount else { return }
        
        // Read new lines
        guard let content = try? String(contentsOfFile: zshHistoryPath, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        
        let newLines = Array(lines.suffix(currentCount - lastZshCount))
        lastZshCount = currentCount
        
        for line in newLines {
            var cmd = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove zsh timestamp prefix if present (: 1234567890:0;command)
            if cmd.hasPrefix(":") {
                if let semicolonIndex = cmd.firstIndex(of: ";") {
                    cmd = String(cmd[cmd.index(after: semicolonIndex)...])
                }
            }
            
            addCommand(cmd, from: "zsh")
        }
    }
    
    private func addCommand(_ command: String, from shell: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty, too short, or already known commands
        guard trimmed.count > 2, !knownCommands.contains(trimmed) else { return }
        
        knownCommands.insert(trimmed)
        
        let item = ClipboardItem(
            text: trimmed,
            appName: "\(shell) history",
            appBundleIdentifier: "com.apple.Terminal",
            isStarred: false
        )
        
        ClipboardStore.shared.add(item)
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
