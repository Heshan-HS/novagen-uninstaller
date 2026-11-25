# NovaGen Deep Uninstaller Pro

Enterprise-grade application uninstaller and leftover cleaner for Windows. Removes leftover files, directories, registry traces, services, and scheduled tasks after uninstallation.

---

## Features

- **18-Point Deep Scan**: Checks Program Files, AppData (Local/Roaming/LocalLow), ProgramData, Registry software hives, Start Menu shortcuts, Prefetch, and MSI caches.
- **Service & Task Cleaner**: Identifies and terminates orphaned background services and scheduled tasks.
- **Locked File Handling**: Clears restrictive permissions and uses `MoveFileEx` (`MOVEFILE_DELAY_UNTIL_REBOOT`) to delete files locked by Windows at next boot.
- **Safety Whitelist**: Built-in protection prevents modification of essential Windows operating system directories and hives.
- **Automatic Registry Backups**: Automatically exports `.reg` backup files to a `Backups` folder before any deletion.
- **Dual Themes**: Includes Dark Obsidian mode and Executive Light mode.

---

## Architecture

- **Engine**: PowerShell 5.1+ and Windows Presentation Foundation (WPF) GUI.
- **Native Launcher**: C# launcher executable compiled using Windows .NET framework compilers.
- **Dependencies**: No external runtime or framework installation required; uses native Windows components.

---

## Quick Start

### Option A: Executable
1. Download or clone this repository.
2. Run `NovaGen.exe` as Administrator.

### Option B: Batch Script
1. Double-click `NovaGen-Uninstaller.bat`.
2. Confirm the Administrator (UAC) prompt.

---

## Building from Source

To compile the launcher executable and icon locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-NovaGen-Exe.ps1
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
