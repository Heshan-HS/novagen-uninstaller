# NovaGen Deep Uninstaller Pro

![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011-0078D6?style=flat-square&logo=windows)
![Engine](https://img.shields.io/badge/Engine-PowerShell%20%2B%20WPF-2563EB?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-059669?style=flat-square)

**NovaGen Deep Uninstaller Pro** is a zero-install, native Windows desktop application designed to completely remove software and hunt down every leftover file, folder, registry key, service, scheduled task, and execution trace.

---

## Why NovaGen?

Standard uninstallers often leave behind configuration files, license caches, registry entries, background updaters, and orphaned directories in `AppData`, `ProgramData`, and the Windows Registry. NovaGen runs an **18-Point Deep Heuristic Engine** after uninstallation (or in standalone Force-Hunt mode) so software can be removed cleanly with zero traces remaining.

---

## Key Capabilities

| Module | Description |
| :--- | :--- |
| **Installed Applications** | Indexes Win32 (`x64`, `x86`) and Current-User apps with instant search, category filters, size sorting (`Sort: Size ↓`), and exact disk footprint calculation. |
| **100% Deep Uninstall + Wipe** | Terminates running processes, executes the official uninstaller, and scans 18 filesystem and registry locations for remaining artifacts. |
| **Force Hunt & Fresh Config Reset** | Scans leftovers for broken/corrupt apps without needing an official uninstaller, or resets user/config/cache traces for a clean state. |
| **Store & Bloatware Remover** | Lists removable Microsoft Store / UWP packages and clears their `AppData\Local\Packages` cache. |
| **Ghost Leftover Sweeper** | Scans `AppData` (`Local`, `Roaming`, `LocalLow`) and `ProgramData` for orphaned folders left behind by previously uninstalled software. |
| **Custom Target Hunter** | Hunts any keyword, publisher, or folder path across the C: drive and Windows Registry. |
| **Install Snapshot Tracker** | Captures pre-install filesystem & registry baselines and computes exact diffs after installation. |
| **Dual Enterprise Themes** | Instant top-bar toggle between **Dark Obsidian** and **Executive Light** modes. |

---

## Safety & Force-Deletion Engine

- **OS Protection Guard:** Core Windows directories (`System32`, `SysWOW64`, `WinSxS`, `WindowsApps`, user profile roots) are strictly whitelisted and cannot be deleted.
- **Automatic Registry Backups:** Before any registry key or value is deleted, `.reg` backups and a `WipeAuditLog.txt` are automatically saved to `Backups/`.
- **Locked File Handling:** Clears restrictive attributes/ACLs and uses Win32 `MoveFileEx` (`MOVEFILE_DELAY_UNTIL_REBOOT`) to schedule kernel-locked files for deletion on next reboot.

---

## Quick Start (Download & Run)

No Python, Node.js, or external runtime is required.

### Option 1: One-Click Release Download (Recommended)
1. Go to the **[Latest Release](https://github.com/Heshan-HS/novagen-uninstaller/releases/latest)** page and download **`NovaGen-Deep-Uninstaller-v4.2.zip`**.
2. Extract the ZIP to any folder.
3. Double-click **`NovaGen.exe`** (or **`NovaGen-Uninstaller.bat`**) and click **Yes** on the Administrator (UAC) prompt.

### Option 2: Clone with Git
```powershell
git clone https://github.com/Heshan-HS/novagen-uninstaller.git
cd novagen-uninstaller
.\NovaGen.exe
```

---

## Building `NovaGen.exe` from Source

To recompile `NovaGen.exe` and `NovaGen.ico` locally using the built-in .NET C# compiler:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-NovaGen-Exe.ps1
```

---

## Project Structure

```text
novagen-uninstaller/
├── NovaGen.exe                 # Native Windows launcher executable (UAC elevated)
├── NovaGen-Uninstaller.bat     # Batch launcher alternative
├── NovaGen-Engine.ps1          # Core 18-point deep uninstaller & WPF GUI
├── Build-NovaGen-Exe.ps1       # .NET C# compiler & icon generator script
├── NovaGen.ico                 # Application icon
├── LICENSE                     # MIT License
└── README.md                   # Documentation
```

---

## License

Licensed under the [MIT License](LICENSE).
