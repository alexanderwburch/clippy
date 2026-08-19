import AppKit
import Combine

class ClipboardManager {
    static let shared = ClipboardManager()
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    /// Records a pasteboard write that Clippy made itself, so the poller skips it.
    /// Without this the paste path races the poller: `pasteItem` writes the chosen entry
    /// and posts a synthetic ⌘V 150ms later, but the 50ms poll fires in between, treats
    /// our own write as a fresh external copy, and re-runs the quote-strip on it —
    /// clearing the pasteboard and rewriting it underneath the paste. The result is a
    /// ⌘V that lands on reflowed text, or on nothing at all if it hits the window
    /// between `clearContents()` and `setString()`. It also re-added every pasted item
    /// to history as a duplicate.
    func registerSelfWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    private init() {
        lastChangeCount = pasteboard.changeCount
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Poll fast so the Claude Code quote-strip rewrites the pasteboard
        // before the user can ⌘V into the next app. 500ms was too slow for that.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
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
            let cleaned = text.stripClaudeCodeQuoting()
            if cleaned != text {
                // Overwrite pasteboard so direct ⌘V pastes the cleaned version too.
                pasteboard.clearContents()
                pasteboard.setString(cleaned, forType: .string)
                // Mark it as ours so the next tick doesn't re-read and re-clean it.
                registerSelfWrite()
            }
            let item = ClipboardItem(
                text: cleaned,
                appName: appName,
                appBundleIdentifier: bundleId
            )
            ClipboardStore.shared.add(item)
        }
    }
    
    /// Largest side (in pixels) we keep for a stored image. Full-resolution Retina
    /// screenshots run to tens of MB each; the whole history is rewritten to disk on
    /// every change, so uncapped images bloat memory and drive the app past the
    /// system disk-write limit (it gets terminated). Downscaling keeps entries small
    /// while staying perfectly legible as history thumbnails/previews.
    private static let maxImageDimension = 1600
    /// Hard ceiling on a single stored image after downscaling.
    private static let maxImageBytes = 4 * 1024 * 1024

    private func getImageData() -> Data? {
        var rep: NSBitmapImageRep?
        if let tiffData = pasteboard.data(forType: .tiff) {
            rep = NSBitmapImageRep(data: tiffData)
        }
        if rep == nil, let pngData = pasteboard.data(forType: .png) {
            rep = NSBitmapImageRep(data: pngData)
        }
        guard let bitmap = rep else { return nil }

        // Keep the original only if it's already small enough; otherwise downscale.
        if let png = bitmap.representation(using: .png, properties: [:]),
           png.count <= Self.maxImageBytes {
            return png
        }
        if let scaled = Self.downscaledPNG(bitmap, maxDimension: Self.maxImageDimension),
           scaled.count <= Self.maxImageBytes {
            return scaled
        }
        // Still oversized (e.g. a huge photo) — go smaller rather than store megabytes.
        return Self.downscaledPNG(bitmap, maxDimension: 800)
    }

    /// Redraw a bitmap so its longest side is at most `maxDimension` pixels and re-encode as PNG.
    private static func downscaledPNG(_ source: NSBitmapImageRep, maxDimension: Int) -> Data? {
        let width = source.pixelsWide
        let height = source.pixelsHigh
        let longest = max(width, height)
        let scale = longest > maxDimension ? Double(maxDimension) / Double(longest) : 1.0
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))

        guard let dest = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        dest.size = NSSize(width: targetWidth, height: targetHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: dest)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            from: NSRect(x: 0, y: 0, width: width, height: height),
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()

        return dest.representation(using: .png, properties: [:])
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

private let claudeQuotePrefix = try! NSRegularExpression(pattern: "^[ \\t]*▎ ?")
private let listMarkerPrefix = try! NSRegularExpression(pattern: "^(\\d+\\.|[-*•])\\s")

extension String {
    /// Cleans up text that was copied from terminal-rendered assistant output —
    /// either Claude Code's `▎`-quoted blocks or Claude's plainer indented prose
    /// responses. Strips the uniform leading prefix, rejoins soft-wrapped lines,
    /// and collapses redundant blank lines so the result pastes cleanly.
    func stripClaudeCodeQuoting() -> String {
        if let stripped = stripQuotePrefix() {
            return stripped.rejoinSoftWraps()
        }
        if let stripped = stripCommonLeadingIndent() {
            return stripped.rejoinSoftWraps()
        }
        return self
    }

    private func stripQuotePrefix() -> String? {
        let lines = self.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonEmpty.count >= 3 else { return nil }

        let prefixed = nonEmpty.filter { line in
            let range = NSRange(line.startIndex..., in: line)
            return claudeQuotePrefix.firstMatch(in: line, range: range) != nil
        }
        guard Double(prefixed.count) / Double(nonEmpty.count) >= 0.7 else { return nil }

        return lines.map { line in
            let range = NSRange(line.startIndex..., in: line)
            return claudeQuotePrefix.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        }.joined(separator: "\n")
    }

    /// Detects the case where every non-blank line shares a leading run of spaces
    /// (the "indented response" style Claude prints in chat panels) and strips it.
    /// Refuses to fire unless the content also looks like prose/lists, so that
    /// genuinely indented code blocks aren't reflowed.
    private func stripCommonLeadingIndent() -> String? {
        let lines = self.components(separatedBy: "\n")
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonBlank.count >= 4 else { return nil }

        var minIndent = Int.max
        for line in nonBlank {
            var spaces = 0
            for ch in line {
                if ch == " " { spaces += 1 } else { break }
            }
            minIndent = min(minIndent, spaces)
            if minIndent < 2 { return nil }
        }
        guard minIndent >= 2 else { return nil }

        // Safety: only treat this as Claude-style output if it reads like prose
        // or a list. Plain indented code (no sentence punctuation, no bullets)
        // is left alone.
        let terminators: Set<Character> = [".", "!", "?", ":"]
        let proseLines = nonBlank.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let last = trimmed.last, terminators.contains(last) { return true }
            let r = NSRange(trimmed.startIndex..., in: trimmed)
            return listMarkerPrefix.firstMatch(in: trimmed, range: r) != nil
        }
        guard Double(proseLines.count) / Double(nonBlank.count) >= 0.5 else { return nil }

        return lines.map { line in
            var stripped = line
            var n = minIndent
            while n > 0, stripped.first == " " {
                stripped.removeFirst()
                n -= 1
            }
            return stripped
        }.joined(separator: "\n")
    }

    private func rejoinSoftWraps() -> String {
        let lines = self.components(separatedBy: "\n")

        var output: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                output.append("")
                continue
            }
            if let prev = output.last,
               !prev.trimmingCharacters(in: .whitespaces).isEmpty,
               !startsWithListMarker(trimmed),
               !endsWithSentenceTerminator(prev) {
                output[output.count - 1] = prev + " " + trimmed
            } else {
                output.append(line)
            }
        }

        var result: [String] = []
        for line in output {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            let prevBlank = result.last.map { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? true
            if isBlank && prevBlank { continue }
            result.append(line)
        }
        while let first = result.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeFirst()
        }
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }
}

private func startsWithListMarker(_ s: String) -> Bool {
    let range = NSRange(s.startIndex..., in: s)
    return listMarkerPrefix.firstMatch(in: s, range: range) != nil
}

private func endsWithSentenceTerminator(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    guard let last = trimmed.last else { return true }
    return ".!?:".contains(last)
}
