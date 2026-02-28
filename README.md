# Clippy 📋

A lightweight, native macOS clipboard manager that remembers your last 1,000 copied items.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- 🎯 **Global Hotkey**: Press `⌘M` anywhere to open clipboard history
- 📝 **Text & Images**: Stores both text and image copies
- 🔍 **Search**: Quickly filter through your clipboard history
- ⌨️ **Keyboard Navigation**: Use arrow keys to navigate, Enter to paste
- 💾 **Persistent Storage**: History survives app restarts
- 🖥️ **Menu Bar App**: Lives in your menu bar, out of the way
- 🎨 **Native Look**: Built with SwiftUI for a beautiful macOS experience

## Installation

### Build from Source

1. **Prerequisites**
   - macOS 13.0 (Ventura) or later
   - Xcode 15+ or Swift 5.9+ command line tools

2. **Clone and Build**
   ```bash
   git clone https://github.com/yourusername/clippy.git
   cd clippy
   swift build -c release
   ```

3. **Create App Bundle** (optional, for better integration)
   ```bash
   ./scripts/create-app-bundle.sh
   ```

4. **Run**
   ```bash
   # Run directly
   .build/release/Clippy
   
   # Or if you created the app bundle
   open Clippy.app
   ```

### Grant Accessibility Permissions

For the global hotkey and paste functionality to work, you need to grant Clippy accessibility permissions:

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the `+` button and add Clippy
3. Restart Clippy if it was already running

## Usage

| Action | How |
|--------|-----|
| Open clipboard history | Press `⌘M` or click menu bar icon |
| Navigate items | `↑` / `↓` arrow keys |
| Paste selected item | Press `Enter` |
| Search history | Just start typing |
| Close window | Press `Esc` or click outside |
| Delete item | Right-click → Delete |
| Clear all history | Menu bar → Clear History |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘M` | Toggle clipboard history (customizable in Settings) |
| `↑` / `↓` | Navigate through items |
| `Enter` | Paste selected item |
| `Esc` | Close history window |
| `⌘,` | Open settings |
| `⌘Q` | Quit Clippy |

## Configuration

Click the menu bar icon and select **Settings...** to customize:
- Change the global hotkey from `⌘M` to any key combination you prefer

## Data Storage

Clipboard history is stored at:
```
~/Library/Application Support/Clippy/history.json
```

## Privacy

- Clippy runs entirely locally on your Mac
- No data is ever sent to any server
- Clipboard contents are stored locally and can be cleared at any time

## Building for Distribution

To create a signed `.app` bundle for distribution:

```bash
# Build release version
swift build -c release

# Create app bundle structure
mkdir -p Clippy.app/Contents/MacOS
mkdir -p Clippy.app/Contents/Resources

# Copy executable
cp .build/release/Clippy Clippy.app/Contents/MacOS/

# Copy Info.plist
cp Sources/Info.plist Clippy.app/Contents/

# Sign (optional, for Gatekeeper)
codesign --sign - --force --deep Clippy.app
```

## Troubleshooting

### Global hotkey not working
- Make sure Clippy has Accessibility permissions in System Settings
- Try restarting the app after granting permissions
- Check if another app is using the same hotkey

### Paste not working
- Clippy needs to simulate `⌘V` to paste, which requires Accessibility permissions
- Some apps may block simulated keyboard input

### App not appearing in menu bar
- Check if Clippy is running in Activity Monitor
- Try rebuilding: `swift build -c release`

## License

MIT License - feel free to use and modify!

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
