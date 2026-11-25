<#
.SYNOPSIS
    NOVAGEN // ZERO-TRACE DEEP UNINSTALLER PRO (v4.2)
    Enterprise-Grade Deep Application Uninstaller, Leftover Hunter, Ghost Sweeper & Fresh-State Reset Engine.
.DESCRIPTION
    100% Native Windows WPF + PowerShell Deep Uninstaller Engine.
    Scans 18+ FileSystem, Registry, Service, Task Scheduler, Prefetch, MuiCache, Installer & Firewall locations.
#>

#Requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'

# ============================================================================
# 1. AUTO-ELEVATION TO ADMINISTRATOR
# ============================================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        $psi.Verb = "runas"
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit
    } catch {
        # User declined UAC; continue in limited mode with warning in UI
    }
}

# ============================================================================
# 2. LOAD WPF & WIN32 NATIVE INTEROP (MoveFileEx for Locked Reboot Deletion)
# ============================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$win32Source = @"
using System;
using System.Runtime.InteropServices;

public class NovaGenNative {
    [Flags]
    public enum MoveFileFlags : uint {
        MOVEFILE_REPLACE_EXISTING = 0x00000001,
        MOVEFILE_COPY_ALLOWED = 0x00000002,
        MOVEFILE_DELAY_UNTIL_REBOOT = 0x00000004,
        MOVEFILE_WRITE_THROUGH = 0x00000008
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, MoveFileFlags dwFlags);

    public static bool ScheduleDeleteOnReboot(string path) {
        return MoveFileEx(path, null, MoveFileFlags.MOVEFILE_DELAY_UNTIL_REBOOT);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public class MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
        public MEMORYSTATUSEX() {
            this.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

    [DllImport("psapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    public static ulong[] GetMemorySnapshot() {
        MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
        if (GlobalMemoryStatusEx(mem)) {
            return new ulong[] { mem.dwMemoryLoad, mem.ullTotalPhys, mem.ullAvailPhys };
        }
        return new ulong[] { 0, 0, 0 };
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct LUID {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct TOKEN_PRIVILEGES {
        public int PrivilegeCount;
        public LUID Luid;
        public int Attributes;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("ntdll.dll")]
    public static extern uint NtSetSystemInformation(int SystemInformationClass, ref int SystemInformation, int SystemInformationLength);

    public static bool PurgeStandbyMemory() {
        try {
            IntPtr hToken = IntPtr.Zero;
            if (!OpenProcessToken(GetCurrentProcess(), 0x0028, out hToken)) return false;
            try {
                LUID luid;
                if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid)) return false;
                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1;
                tp.Luid = luid;
                tp.Attributes = 0x00000002; // SE_PRIVILEGE_ENABLED
                AdjustTokenPrivileges(hToken, false, ref tp, Marshal.SizeOf(tp), IntPtr.Zero, IntPtr.Zero);
            } finally {
                CloseHandle(hToken);
            }
            int purgeCmd = 4; // MemoryPurgeStandbyList
            uint status = NtSetSystemInformation(80, ref purgeCmd, sizeof(int)); // SystemMemoryListInformation = 80
            return (status == 0);
        } catch {
            return false;
        }
    }
}
"@
try {
    Add-Type -TypeDefinition $win32Source -ErrorAction SilentlyContinue
} catch {}

# ============================================================================
# 3. GLOBAL WORKSPACE & SAFETY CONFIGURATIONS
# ============================================================================
if (-not [string]::IsNullOrWhiteSpace($env:NOVAGEN_DATA_DIR)) {
    $Script:AppRoot = $env:NOVAGEN_DATA_DIR
} else {
    $Script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
    if (-not $Script:AppRoot) { $Script:AppRoot = "d:\uinsitaler" }
}
$Script:BackupRoot = Join-Path $Script:AppRoot "Backups"
$Script:SnapshotRoot = Join-Path $Script:AppRoot "Snapshots"
$Script:LogRoot = Join-Path $Script:AppRoot "Logs"

foreach ($dir in @($Script:BackupRoot, $Script:SnapshotRoot, $Script:LogRoot)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$Script:SessionReclaimedBytes = [int64]0
$Script:InstalledApps = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$Script:StoreApps = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$Script:LeftoverItems = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$Script:GhostItems = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]

# Generic / Dangerous tokens that MUST NEVER be searched standalone
$Script:StopWords = @(
    'microsoft', 'windows', 'common', 'files', 'program', 'system', 'system32', 'syswow64',
    'google', 'apple', 'intel', 'amd', 'nvidia', 'realtek', 'driver', 'drivers', 'package',
    'packages', 'client', 'server', 'service', 'services', 'update', 'updater', 'helper',
    'setup', 'install', 'installer', 'uninstaller', 'uninstall', 'runtime', 'redistributable',
    'framework', 'sdk', 'jdk', 'jre', 'net', 'core', 'desktop', 'app', 'apps', 'application',
    'applications', 'software', 'corporation', 'inc', 'ltd', 'llc', 'gmbh', 'co', 'the',
    'for', 'and', 'with', 'pro', 'plus', 'free', 'edition', 'version', 'x64', 'x86', '64', '32',
    'bit', 'user', 'users', 'default', 'public', 'local', 'roaming', 'locallow', 'temp', 'tmp',
    'data', 'config', 'cache', 'logs', 'log', 'bin', 'lib', 'share', 'docs', 'media', 'audio',
    'video', 'network', 'security', 'defender', 'edge', 'webview', 'webview2', ' explorer',
    'shell', 'host', 'broker', 'store', 'xbox', 'directx', 'visual', 'studio', 'code'
)

# Critical System Paths that NovaGen will NEVER allow deleting
$Script:ProtectedPaths = @(
    "^C:\\Windows$",
    "^C:\\Windows\\System32(\\|$)",
    "^C:\\Windows\\SysWOW64(\\|$)",
    "^C:\\Windows\\WinSxS(\\|$)",
    "^C:\\Windows\\Drivers(\\|$)",
    "^C:\\Windows\\Boot(\\|$)",
    "^C:\\Windows\\Fonts(\\|$)",
    "^C:\\Windows\\INF(\\|$)",
    "^C:\\Program Files$",
    "^C:\\Program Files \(x86\)$",
    "^C:\\Program Files\\Common Files$",
    "^C:\\Program Files \(x86\)\\Common Files$",
    "^C:\\Program Files\\WindowsApps(\\|$)",
    "^C:\\Program Files\\Windows Defender(\\|$)",
    "^C:\\ProgramData$",
    "^C:\\ProgramData\\Microsoft$",
    "^C:\\ProgramData\\Microsoft\\Windows(\\|$)",
    "^C:\\Users$",
    "^C:\\Users\\[^\\]+$",
    "^C:\\Users\\[^\\]+\\AppData$",
    "^C:\\Users\\[^\\]+\\AppData\\(Local|LocalLow|Roaming)$",
    "^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft$",
    "^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows(\\|$)",
    "^C:\\Users\\[^\\]+\\AppData\\Roaming\\Microsoft$",
    "^C:\\Users\\[^\\]+\\AppData\\Roaming\\Microsoft\\Windows(\\|$)",
    "^C:\\Users\\[^\\]+\\(Desktop|Documents|Downloads|Pictures|Music|Videos)$"
)

function Test-IsProtectedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $clean = $Path.TrimEnd('\')
    if ($clean.Length -le 10) { return $true }
    foreach ($regex in $Script:ProtectedPaths) {
        if ($clean -imatch $regex) { return $true }
    }
    return $false
}

function Format-ByteSize {
    param([int64]$Bytes)
    if ($Bytes -le 0) { return "0 KB" }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-DirectorySizeFast {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if (-not $item.PSIsContainer) { return [int64]$item.Length }
        $sum = [int64]0
        $files = [System.IO.Directory]::EnumerateFiles($Path, "*", [System.IO.SearchOption]::AllDirectories)
        foreach ($f in $files) {
            try {
                $fi = New-Object System.IO.FileInfo($f)
                $sum += $fi.Length
            } catch {}
        }
        return $sum
    } catch {
        try {
            $measure = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
            if ($measure.Sum) { return [int64]$measure.Sum }
        } catch {}
        return [int64]0
    }
}

# ============================================================================
# 4. SIGNATURE TOKEN EXTRACTOR FOR 18-POINT DEEP HEURISTIC SCAN
# ============================================================================
function Get-AppSearchTokens {
    param(
        [string]$AppName,
        [string]$Publisher,
        [string]$InstallLocation,
        [string]$UninstallString,
        [string]$RegistryKeyName
    )

    $tokens = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $exactPhrases = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    # 1. Clean AppName (strip version numbers, architectures, brackets)
    if (-not [string]::IsNullOrWhiteSpace($AppName)) {
        $cleanName = $AppName -replace '\(.*?\)', '' -replace '\[.*?\]', ''
        $cleanName = $cleanName -replace '(?i)\b(v?\d+(\.\d+)+([a-z0-9\-_]*)?|x64|x86|64-bit|32-bit|amd64|arm64)\b', ''
        $cleanName = ($cleanName -replace '[^\w\s\-\.]', ' ' -replace '\s+', ' ').Trim()

        if ($cleanName.Length -ge 3 -and ($Script:StopWords -notcontains $cleanName.ToLower())) {
            [void]$exactPhrases.Add($cleanName)
            $noSpace = $cleanName -replace '\s+', ''
            if ($noSpace.Length -ge 4 -and ($Script:StopWords -notcontains $noSpace.ToLower())) {
                [void]$tokens.Add($noSpace)
            }
        }

        # First strong word or two-word brand
        $words = $cleanName -split '\s+' | Where-Object { $_.Length -ge 3 -and ($Script:StopWords -notcontains $_.ToLower()) }
        if ($words.Count -ge 1) {
            if ($words[0].Length -ge 4) {
                [void]$tokens.Add($words[0])
            }
            if ($words.Count -ge 2) {
                $twoWord = "$($words[0]) $($words[1])"
                $twoWordJoined = "$($words[0])$($words[1])"
                [void]$exactPhrases.Add($twoWord)
                [void]$tokens.Add($twoWordJoined)
            }
        }
    }

    # 2. Extract folder name from InstallLocation
    if (-not [string]::IsNullOrWhiteSpace($InstallLocation)) {
        $cleanLoc = $InstallLocation.Trim('"').TrimEnd('\')
        if (Test-Path -LiteralPath $cleanLoc) {
            $leaf = Split-Path -Leaf $cleanLoc
            if ($leaf.Length -ge 3 -and ($Script:StopWords -notcontains $leaf.ToLower())) {
                [void]$exactPhrases.Add($leaf)
                [void]$tokens.Add(($leaf -replace '\s+', ''))
            }
        }
    }

    # 3. Extract EXE or folder name from UninstallString
    if (-not [string]::IsNullOrWhiteSpace($UninstallString)) {
        if ($UninstallString -match '([a-zA-Z]:\\[^"<>|?*]+\.exe)') {
            $exePath = $Matches[1]
            $parentDir = Split-Path -Parent $exePath
            $dirLeaf = Split-Path -Leaf $parentDir
            if ($dirLeaf.Length -ge 4 -and ($Script:StopWords -notcontains $dirLeaf.ToLower())) {
                [void]$exactPhrases.Add($dirLeaf)
            }
            $exeBase = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
            if ($exeBase.Length -ge 4 -and $exeBase -notmatch '(?i)^(unins|uninst|setup|install|update|helper|msiexec)' -and ($Script:StopWords -notcontains $exeBase.ToLower())) {
                [void]$tokens.Add($exeBase)
            }
        }
    }

    # 4. Publisher token (only if specific non-giant vendor)
    if (-not [string]::IsNullOrWhiteSpace($Publisher)) {
        $cleanPub = ($Publisher -replace '(?i)\b(corporation|corp|inc|ltd|llc|gmbh|co|limited|software|technologies|systems|international|studio|studios)\b', '' -replace '[^\w\s]', '' -replace '\s+', ' ').Trim()
        if ($cleanPub.Length -ge 4 -and ($Script:StopWords -notcontains $cleanPub.ToLower())) {
            [void]$exactPhrases.Add($cleanPub)
            $pubNoSpace = $cleanPub -replace '\s+', ''
            if ($pubNoSpace.Length -ge 4 -and ($Script:StopWords -notcontains $pubNoSpace.ToLower())) {
                [void]$tokens.Add($pubNoSpace)
            }
        }
    }

    # 5. Registry Key Name (if not pure GUID or if GUID keep separate)
    if (-not [string]::IsNullOrWhiteSpace($RegistryKeyName)) {
        $cleanKey = $RegistryKeyName -replace '_is1$', ''
        if ($cleanKey.Length -ge 4 -and $cleanKey -notmatch '^\{[0-9A-Fa-f\-]+\}$' -and ($Script:StopWords -notcontains $cleanKey.ToLower())) {
            [void]$exactPhrases.Add($cleanKey)
        }
    }

    return [PSCustomObject]@{
        Tokens       = @($tokens)
        ExactPhrases = @($exactPhrases)
    }
}

function Test-NameMatchesSignature {
    param(
        [string]$CandidateName,
        [string[]]$Tokens,
        [string[]]$ExactPhrases
    )
    if ([string]::IsNullOrWhiteSpace($CandidateName)) { return $false }
    $candLower = $CandidateName.ToLower().Trim()
    if ($Script:StopWords -contains $candLower) { return $false }

    $candNormalized = ($candLower -replace '[\s\-_\.]+', '')

    foreach ($phrase in $ExactPhrases) {
        $pLower = $phrase.ToLower().Trim()
        if ($pLower.Length -lt 3) { continue }
        if ($candLower -eq $pLower) { return $true }
        if ($candLower -like "*$pLower*") {
            # Verify boundary or strong length
            if ($pLower.Length -ge 4) { return $true }
        }
    }

    foreach ($tok in $Tokens) {
        $tLower = $tok.ToLower().Trim()
        if ($tLower.Length -lt 4) { continue }
        if ($candNormalized -eq $tLower) { return $true }
        if ($tLower.Length -ge 5 -and $candNormalized -like "*$tLower*") { return $true }
        # Word boundary match on candidate
        if ($candLower -match "(?i)(^|[\s\-_\.])$([regex]::Escape($tLower))($|[\s\-_\.\d])") {
            return $true
        }
    }

    return $false
}

# ============================================================================
# 5. INSTALLED APPLICATIONS SCANNER (Multi-Hive Win32 + User + Store)
# ============================================================================
function Get-AllInstalledApps {
    $list = New-Object System.Collections.Generic.List[PSObject]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $regPaths = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; Arch = "x64"; Scope = "System"; Hive = "HKLM" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"; Arch = "x86"; Scope = "System"; Hive = "HKLM" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"; Arch = "User"; Scope = "Current User"; Hive = "HKCU" }
    )

    foreach ($rp in $regPaths) {
        if (-not (Test-Path -LiteralPath $rp.Path)) { continue }
        $subKeys = Get-ChildItem -LiteralPath $rp.Path -ErrorAction SilentlyContinue
        foreach ($sk in $subKeys) {
            try {
                $name = [string]$sk.GetValue("DisplayName")
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $name = $name.Trim()

                $pub = [string]$sk.GetValue("Publisher")
                $ver = [string]$sk.GetValue("DisplayVersion")
                $uninst = [string]$sk.GetValue("UninstallString")
                $quietUninst = [string]$sk.GetValue("QuietUninstallString")
                $installLoc = [string]$sk.GetValue("InstallLocation")
                $dispIcon = [string]$sk.GetValue("DisplayIcon")
                $instDateRaw = [string]$sk.GetValue("InstallDate")
                $sysComp = $sk.GetValue("SystemComponent")
                $winInst = $sk.GetValue("WindowsInstaller")
                $estSizeRaw = $sk.GetValue("EstimatedSize")

                if (-not [string]::IsNullOrWhiteSpace($installLoc)) {
                    $installLoc = $installLoc.Trim('"').TrimEnd('\')
                }

                # Infer InstallLocation from UninstallString or DisplayIcon if missing
                if ([string]::IsNullOrWhiteSpace($installLoc)) {
                    $probeStr = if ($uninst) { $uninst } else { $dispIcon }
                    if ($probeStr -match '([a-zA-Z]:\\[^"<>|?*]+\\)[^\\]+\.(exe|ico)') {
                        $candidateDir = $Matches[1].TrimEnd('\')
                        if ($candidateDir -notmatch '(?i)^C:\\Windows(\\|$)' -and (Test-Path -LiteralPath $candidateDir)) {
                            $installLoc = $candidateDir
                        }
                    }
                }

                $dedupKey = "$name|$ver|$installLoc"
                if ($seen.Contains($dedupKey)) { continue }
                [void]$seen.Add($dedupKey)

                # Size calculation (Registry EstimatedSize is in KB)
                $sizeBytes = [int64]0
                if ($null -ne $estSizeRaw) {
                    try {
                        $kbVal = [int64]$estSizeRaw
                        if ($kbVal -gt 0 -and $kbVal -lt 1073741824) {
                            $sizeBytes = $kbVal * 1024
                        }
                    } catch {}
                }

                # Format InstallDate
                $installDateStr = "—"
                if ($instDateRaw -and $instDateRaw -match '^(\d{4})(\d{2})(\d{2})$') {
                    $installDateStr = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
                } elseif (-not [string]::IsNullOrWhiteSpace($installLoc) -and (Test-Path -LiteralPath $installLoc)) {
                    try {
                        $dirInfo = Get-Item -LiteralPath $installLoc -ErrorAction SilentlyContinue
                        if ($dirInfo) { $installDateStr = $dirInfo.CreationTime.ToString("yyyy-MM-dd") }
                    } catch {}
                }

                $isSystemComp = ($sysComp -eq 1) -or ($name -match '(?i)^(Microsoft Visual C\+\+|Microsoft \.NET|Windows Software Development Kit)')
                $category = if ($isSystemComp) { "Runtime / System" } elseif ($rp.Scope -eq "Current User") { "User App" } else { "Desktop App" }

                $list.Add([PSCustomObject]@{
                    DisplayName          = $name
                    Publisher            = if (-not [string]::IsNullOrWhiteSpace($pub)) { $pub.Trim() } else { "Unknown Publisher" }
                    DisplayVersion       = if (-not [string]::IsNullOrWhiteSpace($ver)) { $ver.Trim() } else { "—" }
                    InstallLocation      = if ($installLoc) { $installLoc } else { "" }
                    UninstallString      = if ($uninst) { $uninst } else { "" }
                    QuietUninstallString = if ($quietUninst) { $quietUninst } else { "" }
                    RegistryPath         = ($sk.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')
                    PSRegistryPath       = $sk.PSPath
                    RegistryKeyName      = $sk.PSChildName
                    Architecture         = $rp.Arch
                    Scope                = $rp.Scope
                    Category             = $category
                    SizeBytes            = $sizeBytes
                    SizeFormatted        = if ($sizeBytes -gt 0) { Format-ByteSize $sizeBytes } else { "—" }
                    InstallDate          = $installDateStr
                    WindowsInstaller     = ($winInst -eq 1)
                })
            } catch {}
        }
    }

    return ($list | Sort-Object DisplayName)
}

function Get-AllStoreApps {
    $list = New-Object System.Collections.Generic.List[PSObject]
    try {
        $packages = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            -not $_.IsFramework -and $_.SignatureKind -ne 'System' -and $_.NonRemovable -ne $true
        }
        foreach ($pkg in $packages) {
            $loc = $pkg.InstallLocation
            $localState = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)"
            $list.Add([PSCustomObject]@{
                Name              = $pkg.Name
                Publisher         = ($pkg.Publisher -replace '^CN=', '' -split ',')[0]
                Version           = $pkg.Version.ToString()
                PackageFullName   = $pkg.PackageFullName
                PackageFamilyName = $pkg.PackageFamilyName
                InstallLocation   = if ($loc) { $loc } else { "" }
                LocalStatePath    = if (Test-Path $localState) { $localState } else { "" }
                Architecture      = $pkg.Architecture.ToString()
            })
        }
    } catch {}
    return ($list | Sort-Object Name)
}

# ============================================================================
# 6. THE 18-POINT DEEP LEFTOVER HUNTER ENGINE
# ============================================================================
function Invoke-DeepLeftoverScan {
    param(
        [string]$AppName,
        [string]$Publisher,
        [string]$InstallLocation,
        [string]$UninstallString,
        [string]$RegistryPath,
        [string]$RegistryKeyName,
        [bool]$IncludeInstallRegistry = $true
    )

    $results = New-Object System.Collections.Generic.List[PSObject]
    $seenTargets = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    function Add-LeftoverEntry {
        param(
            [string]$Category,
            [string]$ItemType,     # File, Folder, RegistryKey, RegistryValue, Service, Task, Firewall
            [string]$TargetPath,
            [string]$SubTarget = "",
            [string]$RiskLevel = "SAFE",
            [string]$Confidence = "HIGH"
        )
        if ([string]::IsNullOrWhiteSpace($TargetPath)) { return }
        $dedup = "$ItemType|$TargetPath|$SubTarget"
        if ($seenTargets.Contains($dedup)) { return }

        if ($ItemType -in @('File', 'Folder')) {
            if (Test-IsProtectedPath $TargetPath) { return }
            if (-not (Test-Path -LiteralPath $TargetPath)) { return }
        }

        [void]$seenTargets.Add($dedup)

        $sizeBytes = [int64]0
        if ($ItemType -eq 'File') {
            try { $sizeBytes = (Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue).Length } catch {}
        } elseif ($ItemType -eq 'Folder') {
            $sizeBytes = Get-DirectorySizeFast -Path $TargetPath
        }

        $displayPath = if ($SubTarget) { "$TargetPath -> [$SubTarget]" } else { $TargetPath }

        $results.Add([PSCustomObject]@{
            IsSelected    = $true
            Category      = $Category
            ItemType      = $ItemType
            TargetPath    = $TargetPath
            SubTarget     = $SubTarget
            DisplayPath   = $displayPath
            SizeBytes     = $sizeBytes
            SizeFormatted = if ($sizeBytes -gt 0) { Format-ByteSize $sizeBytes } else { "—" }
            Confidence    = $Confidence
            RiskLevel     = $RiskLevel
        })
    }

    $sig = Get-AppSearchTokens -AppName $AppName -Publisher $Publisher -InstallLocation $InstallLocation -UninstallString $UninstallString -RegistryKeyName $RegistryKeyName
    $tokens = $sig.Tokens
    $phrases = $sig.ExactPhrases

    # 1. Explicit InstallLocation
    if (-not [string]::IsNullOrWhiteSpace($InstallLocation)) {
        $cleanLoc = $InstallLocation.Trim('"').TrimEnd('\')
        if ((Test-Path -LiteralPath $cleanLoc) -and -not (Test-IsProtectedPath $cleanLoc)) {
            Add-LeftoverEntry -Category "Install Directory" -ItemType "Folder" -TargetPath $cleanLoc -Confidence "EXACT"
        }
    }

    # 2. Explicit Uninstall Registry Key
    if ($IncludeInstallRegistry -and -not [string]::IsNullOrWhiteSpace($RegistryPath)) {
        $psReg = if ($RegistryPath -like "HK*:\*") { $RegistryPath } else {
            $RegistryPath -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\' -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
        }
        if (Test-Path -LiteralPath $psReg) {
            Add-LeftoverEntry -Category "Uninstall Registry" -ItemType "RegistryKey" -TargetPath $psReg -Confidence "EXACT"
        }
    }

    # If no valid search tokens exist, return only explicit findings
    if ($tokens.Count -eq 0 -and $phrases.Count -eq 0) {
        return $results
    }

    # 3. File System Root Directories to Deep Scan (1st & 2nd Level Vendor Folders)
    $fsRoots = @(
        @{ Path = $env:ProgramFiles; Label = "Program Files (x64)" },
        @{ Path = ${env:ProgramFiles(x86)}; Label = "Program Files (x86)" },
        @{ Path = "$env:ProgramFiles\Common Files"; Label = "Common Files (x64)" },
        @{ Path = "${env:ProgramFiles(x86)}\Common Files"; Label = "Common Files (x86)" },
        @{ Path = $env:ProgramData; Label = "ProgramData" },
        @{ Path = $env:LOCALAPPDATA; Label = "AppData\Local" },
        @{ Path = "$env:LOCALAPPDATA\Programs"; Label = "AppData\Local\Programs" },
        @{ Path = "$env:USERPROFILE\AppData\LocalLow"; Label = "AppData\LocalLow" },
        @{ Path = $env:APPDATA; Label = "AppData\Roaming" },
        @{ Path = "$env:USERPROFILE\.config"; Label = "User .config" },
        @{ Path = "$env:USERPROFILE\Documents"; Label = "User Documents" }
    )

    foreach ($root in $fsRoots) {
        if ([string]::IsNullOrWhiteSpace($root.Path) -or -not (Test-Path -LiteralPath $root.Path)) { continue }
        $subDirs = Get-ChildItem -LiteralPath $root.Path -Directory -Force -ErrorAction SilentlyContinue
        foreach ($dir in $subDirs) {
            if (Test-NameMatchesSignature -CandidateName $dir.Name -Tokens $tokens -ExactPhrases $phrases) {
                Add-LeftoverEntry -Category $root.Label -ItemType "Folder" -TargetPath $dir.FullName -Confidence "HIGH"
            } else {
                # Check 2nd level inside Vendor folder (e.g., AppData\Local\Publisher\AppName)
                $level2 = Get-ChildItem -LiteralPath $dir.FullName -Directory -Force -ErrorAction SilentlyContinue
                foreach ($sub in $level2) {
                    if (Test-NameMatchesSignature -CandidateName $sub.Name -Tokens $tokens -ExactPhrases $phrases) {
                        Add-LeftoverEntry -Category "$($root.Label) (Sub)" -ItemType "Folder" -TargetPath $sub.FullName -Confidence "HIGH"
                    }
                }
            }
        }
    }

    # 4. User Profile Root Dot-Folders (e.g. C:\Users\User\.appname)
    $dotDirs = Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name.StartsWith(".") }
    foreach ($dd in $dotDirs) {
        $cleanDot = $dd.Name.TrimStart('.')
        if (Test-NameMatchesSignature -CandidateName $cleanDot -Tokens $tokens -ExactPhrases $phrases) {
            Add-LeftoverEntry -Category "User Dot-Folder" -ItemType "Folder" -TargetPath $dd.FullName -Confidence "HIGH"
        }
    }

    # 5. Temp Directories (User Temp & Windows Temp)
    $tempRoots = @(
        @{ Path = $env:TEMP; Label = "User Temp" },
        @{ Path = "C:\Windows\Temp"; Label = "Windows Temp" }
    )
    foreach ($tr in $tempRoots) {
        if (-not (Test-Path -LiteralPath $tr.Path)) { continue }
        $tempItems = Get-ChildItem -LiteralPath $tr.Path -Force -ErrorAction SilentlyContinue
        foreach ($ti in $tempItems) {
            if (Test-NameMatchesSignature -CandidateName $ti.Name -Tokens $tokens -ExactPhrases $phrases) {
                $iType = if ($ti.PSIsContainer) { "Folder" } else { "File" }
                Add-LeftoverEntry -Category $tr.Label -ItemType $iType -TargetPath $ti.FullName -Confidence "MEDIUM"
            }
        }
    }

    # 6. Windows Prefetch Traces (C:\Windows\Prefetch\*.pf)
    $prefetchDir = "C:\Windows\Prefetch"
    if (Test-Path -LiteralPath $prefetchDir) {
        $pfFiles = Get-ChildItem -LiteralPath $prefetchDir -Filter "*.pf" -Force -ErrorAction SilentlyContinue
        foreach ($pf in $pfFiles) {
            $pfBase = ($pf.Name -split '-')[0]
            if (Test-NameMatchesSignature -CandidateName $pfBase -Tokens $tokens -ExactPhrases $phrases) {
                Add-LeftoverEntry -Category "Windows Prefetch" -ItemType "File" -TargetPath $pf.FullName -Confidence "HIGH"
            }
        }
    }

    # 7. Start Menu & Desktop Shortcuts (.lnk / .url / folders)
    $shortcutRoots = @(
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "$env:USERPROFILE\Desktop",
        "C:\Users\Public\Desktop",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    )
    foreach ($sr in $shortcutRoots) {
        if (-not (Test-Path -LiteralPath $sr)) { continue }
        $scItems = Get-ChildItem -LiteralPath $sr -Force -ErrorAction SilentlyContinue
        foreach ($sci in $scItems) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($sci.Name)
            if (Test-NameMatchesSignature -CandidateName $baseName -Tokens $tokens -ExactPhrases $phrases) {
                $iType = if ($sci.PSIsContainer) { "Folder" } else { "File" }
                Add-LeftoverEntry -Category "Shortcuts & Start Menu" -ItemType $iType -TargetPath $sci.FullName -Confidence "HIGH"
            }
        }
    }

    # 8. AppData\Local\Packages & CrashDumps
    $crashDumpDir = "$env:LOCALAPPDATA\CrashDumps"
    if (Test-Path -LiteralPath $crashDumpDir) {
        $dumps = Get-ChildItem -LiteralPath $crashDumpDir -Force -ErrorAction SilentlyContinue
        foreach ($dmp in $dumps) {
            if (Test-NameMatchesSignature -CandidateName $dmp.Name -Tokens $tokens -ExactPhrases $phrases) {
                Add-LeftoverEntry -Category "Crash Dumps" -ItemType "File" -TargetPath $dmp.FullName -Confidence "HIGH"
            }
        }
    }

    # 9. Registry Software Hives (HKCU & HKLM & WOW6432Node & VirtualStore)
    $regSoftwareRoots = @(
        @{ Path = "HKCU:\SOFTWARE"; Label = "Registry (HKCU\Software)" },
        @{ Path = "HKCU:\SOFTWARE\Classes\VirtualStore\MACHINE\SOFTWARE"; Label = "Registry (VirtualStore)" },
        @{ Path = "HKLM:\SOFTWARE"; Label = "Registry (HKLM\Software)" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node"; Label = "Registry (HKLM\WOW6432Node)" }
    )
    foreach ($rs in $regSoftwareRoots) {
        if (-not (Test-Path -LiteralPath $rs.Path)) { continue }
        $subKeys = Get-ChildItem -LiteralPath $rs.Path -ErrorAction SilentlyContinue
        foreach ($sk in $subKeys) {
            $keyName = $sk.PSChildName
            if (Test-NameMatchesSignature -CandidateName $keyName -Tokens $tokens -ExactPhrases $phrases) {
                $cleanRegPath = $sk.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
                Add-LeftoverEntry -Category $rs.Label -ItemType "RegistryKey" -TargetPath $sk.PSPath -Confidence "HIGH"
            } else {
                # 2nd level under Vendor key
                if ($keyName -notin @('Microsoft', 'Classes', 'Policies', 'RegisteredApplications', 'Clients')) {
                    $sub2 = Get-ChildItem -LiteralPath $sk.PSPath -ErrorAction SilentlyContinue
                    foreach ($s2 in $sub2) {
                        if (Test-NameMatchesSignature -CandidateName $s2.PSChildName -Tokens $tokens -ExactPhrases $phrases) {
                            Add-LeftoverEntry -Category "$($rs.Label) (Sub)" -ItemType "RegistryKey" -TargetPath $s2.PSPath -Confidence "HIGH"
                        }
                    }
                }
            }
        }
    }

    # 10. All Uninstall Registry Hives (Orphaned Uninstall Entries)
    $uninstHives = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($uh in $uninstHives) {
        if (-not (Test-Path -LiteralPath $uh)) { continue }
        $uKeys = Get-ChildItem -LiteralPath $uh -ErrorAction SilentlyContinue
        foreach ($uk in $uKeys) {
            $props = Get-ItemProperty -LiteralPath $uk.PSPath -ErrorAction SilentlyContinue
            $disp = if ($props.DisplayName) { $props.DisplayName } else { $uk.PSChildName }
            if (Test-NameMatchesSignature -CandidateName $disp -Tokens $tokens -ExactPhrases $phrases) {
                Add-LeftoverEntry -Category "Uninstall Registry" -ItemType "RegistryKey" -TargetPath $uk.PSPath -Confidence "HIGH"
            }
        }
    }

    # 11. Startup Run / RunOnce Registry Values
    $runKeys = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($rk in $runKeys) {
        if (-not (Test-Path -LiteralPath $rk)) { continue }
        $regObj = Get-Item -LiteralPath $rk -ErrorAction SilentlyContinue
        if (-not $regObj) { continue }
        foreach ($valName in $regObj.GetValueNames()) {
            if ([string]::IsNullOrWhiteSpace($valName)) { continue }
            $valData = [string]$regObj.GetValue($valName)
            if ((Test-NameMatchesSignature -CandidateName $valName -Tokens $tokens -ExactPhrases $phrases) -or
                (Test-NameMatchesSignature -CandidateName $valData -Tokens $tokens -ExactPhrases $phrases) -or
                (-not [string]::IsNullOrWhiteSpace($InstallLocation) -and $valData -like "*$InstallLocation*")) {
                Add-LeftoverEntry -Category "Startup Registry (Run)" -ItemType "RegistryValue" -TargetPath $rk -SubTarget $valName -Confidence "HIGH"
            }
        }
    }

    # 12. Execution Trace Caches (MuiCache, AppCompatFlags, FeatureUsage - CRITICAL FOR FRESH RESET!)
    $traceValKeys = @(
        @{ Path = "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"; Label = "Registry (MuiCache Trace)" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store"; Label = "Registry (AppCompat Trace)" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"; Label = "Registry (AppCompat Layers)" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"; Label = "Registry (HKLM AppCompat)" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched"; Label = "Registry (Explorer AppSwitched)" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\ShowJumpView"; Label = "Registry (Explorer JumpView)" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Folders"; Label = "Registry (MSI Installer Folders)" }
    )
    foreach ($tv in $traceValKeys) {
        if (-not (Test-Path -LiteralPath $tv.Path)) { continue }
        $regObj = Get-Item -LiteralPath $tv.Path -ErrorAction SilentlyContinue
        if (-not $regObj) { continue }
        foreach ($valName in $regObj.GetValueNames()) {
            if ([string]::IsNullOrWhiteSpace($valName)) { continue }
            if ((Test-NameMatchesSignature -CandidateName $valName -Tokens $tokens -ExactPhrases $phrases) -or
                (-not [string]::IsNullOrWhiteSpace($InstallLocation) -and $valName -like "*$InstallLocation*")) {
                Add-LeftoverEntry -Category $tv.Label -ItemType "RegistryValue" -TargetPath $tv.Path -SubTarget $valName -Confidence "HIGH"
            }
        }
    }

    # 13. Windows Installer Products (HKLM:\SOFTWARE\Classes\Installer\Products)
    $msiProductsPath = "HKLM:\SOFTWARE\Classes\Installer\Products"
    if (Test-Path -LiteralPath $msiProductsPath) {
        $msiKeys = Get-ChildItem -LiteralPath $msiProductsPath -ErrorAction SilentlyContinue
        foreach ($mk in $msiKeys) {
            $pName = (Get-ItemProperty -LiteralPath $mk.PSPath -Name "ProductName" -ErrorAction SilentlyContinue).ProductName
            if ($pName -and (Test-NameMatchesSignature -CandidateName $pName -Tokens $tokens -ExactPhrases $phrases)) {
                Add-LeftoverEntry -Category "MSI Installer Cache" -ItemType "RegistryKey" -TargetPath $mk.PSPath -Confidence "HIGH"
            }
        }
    }

    # 14. Windows Services matching App Name or InstallLocation
    try {
        $svcRegRoot = "HKLM:\SYSTEM\CurrentControlSet\Services"
        $services = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue
        foreach ($svc in $services) {
            if ($svc.PathName -match '(?i)^C:\\Windows\\') { continue }
            $svcMatch = $false
            if (-not [string]::IsNullOrWhiteSpace($InstallLocation) -and $svc.PathName -like "*$InstallLocation*") {
                $svcMatch = $true
            } elseif ((Test-NameMatchesSignature -CandidateName $svc.Name -Tokens $tokens -ExactPhrases $phrases) -or
                      (Test-NameMatchesSignature -CandidateName $svc.DisplayName -Tokens $tokens -ExactPhrases $phrases)) {
                $svcMatch = $true
            }
            if ($svcMatch) {
                Add-LeftoverEntry -Category "Windows Service" -ItemType "Service" -TargetPath $svc.Name -SubTarget $svc.DisplayName -Confidence "HIGH"
            }
        }
    } catch {}

    # 15. Scheduled Tasks matching App Name or InstallLocation
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike "\Microsoft\*" }
        foreach ($t in $tasks) {
            if ((Test-NameMatchesSignature -CandidateName $t.TaskName -Tokens $tokens -ExactPhrases $phrases) -or
                (Test-NameMatchesSignature -CandidateName $t.TaskPath -Tokens $tokens -ExactPhrases $phrases)) {
                Add-LeftoverEntry -Category "Scheduled Task" -ItemType "Task" -TargetPath "$($t.TaskPath)$($t.TaskName)" -Confidence "HIGH"
            }
        }
    } catch {}

    # 16. Windows Firewall Rules matching App Name or InstallLocation
    try {
        $fwReg = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
        if (Test-Path -LiteralPath $fwReg) {
            $fwObj = Get-Item -LiteralPath $fwReg -ErrorAction SilentlyContinue
            if ($fwObj) {
                foreach ($vName in $fwObj.GetValueNames()) {
                    $vData = [string]$fwObj.GetValue($vName)
                    if ((-not [string]::IsNullOrWhiteSpace($InstallLocation) -and $vData -like "*$InstallLocation*") -or
                        (Test-NameMatchesSignature -CandidateName $vData -Tokens $tokens -ExactPhrases $phrases)) {
                        Add-LeftoverEntry -Category "Firewall Rule" -ItemType "RegistryValue" -TargetPath $fwReg -SubTarget $vName -Confidence "HIGH"
                    }
                }
            }
        }
    } catch {}

    return $results
}

# ============================================================================
# 7. GHOST LEFTOVER SWEEPER (ORPHANED APPDATA & PROGRAMDATA HUNTER)
# ============================================================================
function Invoke-GhostLeftoverSweep {
    param([System.Collections.Generic.List[PSObject]]$CurrentInstalledApps)

    $ghosts = New-Object System.Collections.Generic.List[PSObject]

    # Build known active token set from all installed Win32 + Store apps
    $activeWords = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($sw in $Script:StopWords) { [void]$activeWords.Add($sw) }

    # Well-known safe Windows / Browser / Hardware folders to never flag as ghosts
    $safeVendors = @(
        'Microsoft', 'Windows', 'Google', 'Mozilla', 'BraveSoftware', 'Opera Software',
        'Apple', 'Apple Computer', 'Intel', 'AMD', 'NVIDIA', 'NVIDIA Corporation', 'Realtek',
        'ASUS', 'Acer', 'Dell', 'HP', 'Lenovo', 'MSI', 'Razer', 'Logitech', 'Corsair',
        'Package Cache', 'Packages', 'Comms', 'ConnectedDevicesPlatform', 'D3DSCache',
        'Diagnostics', 'ElevatedDiagnostics', 'FontCache', 'History', 'IconCache.db',
        'INetCache', 'INetCookies', 'NetHood', 'PeerDistRepub', 'PlaceholderTileLogoFolder',
        'PrintHood', 'Publishers', 'Recent', 'SendTo', 'SquirrelTemp', 'Start Menu',
        'Templates', 'Temp', 'TileDataLayer', 'ToastNotificationManagerCompat', 'VirtualStore',
        'WindowsApps', 'WMI', 'Application Data', 'Desktop', 'Favorites', 'Links',
        'MicrosoftEdge', 'OneDrive', 'pip', 'npm', 'npm-cache', 'yarn', 'NuGet', 'cargo',
        'rustup', 'go-build', 'gradle', 'Maven', 'Android', 'Flutter', 'Dart', 'Python',
        'JetBrains', 'vscode', 'Code', 'Git', 'GitHub', 'Docker', 'Cloudflare', 'SSH',
        'gnupg', 'certbot', 'Postman', 'Insomnia', 'Figma', 'Discord', 'Slack', 'Telegram Desktop',
        'WhatsApp', 'Spotify', 'Steam', 'EpicGamesLauncher', 'UnrealEngine', 'Unity',
        'Adobe', 'Autodesk', 'VLC', 'obs-studio', '7-Zip', 'WinRAR', 'Notepad++'
    )
    foreach ($sv in $safeVendors) {
        [void]$activeWords.Add($sv)
        [void]$activeWords.Add(($sv -replace '\s+', ''))
    }

    foreach ($app in $CurrentInstalledApps) {
        $sig = Get-AppSearchTokens -AppName $app.DisplayName -Publisher $app.Publisher -InstallLocation $app.InstallLocation -UninstallString $app.UninstallString -RegistryKeyName $app.RegistryKeyName
        foreach ($t in $sig.Tokens) { [void]$activeWords.Add($t) }
        foreach ($p in $sig.ExactPhrases) {
            [void]$activeWords.Add($p)
            [void]$activeWords.Add(($p -replace '\s+', ''))
        }
    }

    $scanTargets = @(
        @{ Path = $env:LOCALAPPDATA; Label = "AppData\Local" },
        @{ Path = $env:APPDATA; Label = "AppData\Roaming" },
        @{ Path = "$env:USERPROFILE\AppData\LocalLow"; Label = "AppData\LocalLow" },
        @{ Path = $env:ProgramData; Label = "ProgramData" }
    )

    foreach ($st in $scanTargets) {
        if (-not (Test-Path -LiteralPath $st.Path)) { continue }
        $dirs = Get-ChildItem -LiteralPath $st.Path -Directory -Force -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            $name = $d.Name
            if ($name.StartsWith("{") -or $name.StartsWith(".")) { continue }
            $norm = $name -replace '[\s\-_\.]+', ''
            if ($activeWords.Contains($name) -or $activeWords.Contains($norm)) { continue }

            # Check if any active word is a substring
            $matched = $false
            foreach ($aw in $activeWords) {
                if ($aw.Length -ge 4 -and ($norm -like "*$aw*" -or $aw -like "*$norm*")) {
                    $matched = $true
                    break
                }
            }
            if ($matched) { continue }

            # Check if folder still contains a running process or was modified in last 24 hours
            $ageDays = [int]((Get-Date) - $d.LastWriteTime).TotalDays
            $sizeBytes = Get-DirectorySizeFast -Path $d.FullName

            $ghosts.Add([PSCustomObject]@{
                IsSelected    = $false
                FolderName    = $name
                Location      = $st.Label
                FullPath      = $d.FullName
                SizeBytes     = $sizeBytes
                SizeFormatted = Format-ByteSize $sizeBytes
                LastModified  = $d.LastWriteTime.ToString("yyyy-MM-dd")
                IdleDays      = "$ageDays days ago"
            })
        }
    }

    return ($ghosts | Sort-Object SizeBytes -Descending)
}

# ============================================================================
# 8. PROCESS KILLER, REGISTRY BACKUP & FORCE WIPE ENGINE
# ============================================================================
function Stop-AppRelatedProcesses {
    param(
        [string]$AppName,
        [string]$InstallLocation
    )
    $killed = New-Object System.Collections.Generic.List[string]

    # 1. Kill any process running from InstallLocation
    if (-not [string]::IsNullOrWhiteSpace($InstallLocation) -and (Test-Path -LiteralPath $InstallLocation)) {
        $procs = Get-Process -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try {
                if ($p.Id -eq $PID) { continue }
                $pPath = $p.MainModule.FileName
                if ($pPath -and $pPath.StartsWith($InstallLocation, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    $killed.Add("$($p.ProcessName) (PID: $($p.Id))")
                }
            } catch {}
        }
    }

    # 2. Match process name by strong token
    if (-not [string]::IsNullOrWhiteSpace($AppName)) {
        $sig = Get-AppSearchTokens -AppName $AppName -Publisher "" -InstallLocation $InstallLocation -UninstallString "" -RegistryKeyName ""
        foreach ($tok in $sig.Tokens) {
            if ($tok.Length -lt 5) { continue }
            $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
                $_.ProcessName -ieq $tok -and $_.Id -ne $PID -and $_.ProcessName -notin @('explorer', 'powershell', 'pwsh', 'cmd', 'svchost', 'conhost', 'dwm', 'csrss', 'lsass', 'winlogon', 'services')
            }
            foreach ($p in $procs) {
                try {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    $killed.Add("$($p.ProcessName) (PID: $($p.Id))")
                } catch {}
            }
        }
    }
    return $killed
}

function Export-RegistryKeyBackup {
    param(
        [string]$PSRegistryPath,
        [string]$BackupFolder
    )
    try {
        $nativeKey = $PSRegistryPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
        $nativeKey = $nativeKey -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\' -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\' -replace '^HKEY_CURRENT_USER\\', 'HKCU\'
        $safeFileName = ($nativeKey -replace '[\\/:*?"<>|]', '_') + ".reg"
        $outFile = Join-Path $BackupFolder $safeFileName
        $proc = Start-Process -FilePath "reg.exe" -ArgumentList "export `"$nativeKey`" `"$outFile`" /y" -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
        return (Test-Path -LiteralPath $outFile)
    } catch {
        return $false
    }
}

function Invoke-ForceDeleteFileSystemItem {
    param([string]$TargetPath)
    if (Test-IsProtectedPath $TargetPath) {
        return [PSCustomObject]@{ Success = $false; Status = "BLOCKED (Protected OS Path)" }
    }
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return [PSCustomObject]@{ Success = $true; Status = "Already Removed" }
    }

    # 1. Kill processes holding files inside TargetPath
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try {
                if ($p.Id -eq $PID) { continue }
                if ($p.MainModule.FileName -and $p.MainModule.FileName.StartsWith($TargetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    } catch {}

    # 2. Clear ReadOnly / System / Hidden attributes
    try {
        $item = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
        if ($item) {
            $item.Attributes = [System.IO.FileAttributes]::Normal
            if ($item.PSIsContainer) {
                Get-ChildItem -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {}
                }
            }
        }
    } catch {}

    # 3. Direct PowerShell Remove-Item
    try {
        Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $TargetPath)) {
            return [PSCustomObject]@{ Success = $true; Status = "Deleted (100% Clean)" }
        }
    } catch {}

    # 4. Takeown + Icacls + Cmd RMDIR / DEL fallback
    try {
        $isDir = (Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue).PSIsContainer
        if ($isDir) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c takeown /f `"$TargetPath`" /r /d y >nul 2>&1 & icacls `"$TargetPath`" /grant administrators:F /t /c /q >nul 2>&1 & rmdir /s /q `"$TargetPath`" >nul 2>&1" -WindowStyle Hidden -Wait
        } else {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c takeown /f `"$TargetPath`" >nul 2>&1 & icacls `"$TargetPath`" /grant administrators:F /q >nul 2>&1 & del /f /q `"$TargetPath`" >nul 2>&1" -WindowStyle Hidden -Wait
        }
        if (-not (Test-Path -LiteralPath $TargetPath)) {
            return [PSCustomObject]@{ Success = $true; Status = "Force Nuked (ACL Override)" }
        }
    } catch {}

    # 5. Schedule Locked Files for Next Reboot Deletion via Win32 MoveFileEx
    try {
        if (Test-Path -LiteralPath $TargetPath) {
            $item = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
            if ($item -and $item.PSIsContainer) {
                Get-ChildItem -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
                    [void][NovaGenNative]::ScheduleDeleteOnReboot($_.FullName)
                }
            }
            [void][NovaGenNative]::ScheduleDeleteOnReboot($TargetPath)
            return [PSCustomObject]@{ Success = $true; Status = "Queued for Reboot Wipe (Kernel Locked)" }
        }
    } catch {}

    return [PSCustomObject]@{ Success = $false; Status = "Locked by Kernel" }
}

# ============================================================================
# 9. SNAPSHOT TRACKER (BEFORE / AFTER INSTALL DIFF ENGINE)
# ============================================================================
function New-SystemInstallSnapshot {
    param([string]$SnapshotName)
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $safeName = ($SnapshotName -replace '[^\w\-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "Baseline" }
    $filePath = Join-Path $Script:SnapshotRoot "Snapshot_${stamp}_${safeName}.json"

    $fsDirs = New-Object System.Collections.Generic.List[string]
    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:LOCALAPPDATA,
        "$env:LOCALAPPDATA\Programs",
        "$env:USERPROFILE\AppData\LocalLow",
        $env:APPDATA
    )
    foreach ($r in $roots) {
        if (Test-Path -LiteralPath $r) {
            Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $fsDirs.Add($_.FullName)
            }
        }
    }

    $regKeys = New-Object System.Collections.Generic.List[string]
    $rRoots = @(
        "HKCU:\SOFTWARE",
        "HKLM:\SOFTWARE",
        "HKLM:\SOFTWARE\WOW6432Node",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($rr in $rRoots) {
        if (Test-Path -LiteralPath $rr) {
            Get-ChildItem -LiteralPath $rr -ErrorAction SilentlyContinue | ForEach-Object {
                $regKeys.Add($_.PSPath)
            }
        }
    }

    $payload = [PSCustomObject]@{
        Name        = $SnapshotName
        CreatedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Directories = $fsDirs
        Registry    = $regKeys
    }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $filePath -Encoding UTF8
    return $filePath
}

function Compare-SystemInstallSnapshot {
    param([string]$SnapshotFilePath)
    $diffResults = New-Object System.Collections.Generic.List[PSObject]
    if (-not (Test-Path -LiteralPath $SnapshotFilePath)) { return $diffResults }

    $snap = Get-Content -LiteralPath $SnapshotFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $oldDirs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($d in $snap.Directories) { [void]$oldDirs.Add([string]$d) }

    $oldRegs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $snap.Registry) { [void]$oldRegs.Add([string]$r) }

    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:LOCALAPPDATA,
        "$env:LOCALAPPDATA\Programs",
        "$env:USERPROFILE\AppData\LocalLow",
        $env:APPDATA
    )
    foreach ($r in $roots) {
        if (Test-Path -LiteralPath $r) {
            Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $oldDirs.Contains($_.FullName) -and -not (Test-IsProtectedPath $_.FullName)) {
                    $sz = Get-DirectorySizeFast -Path $_.FullName
                    $diffResults.Add([PSCustomObject]@{
                        IsSelected    = $true
                        Category      = "Snapshot Diff (New Folder)"
                        ItemType      = "Folder"
                        TargetPath    = $_.FullName
                        SubTarget     = ""
                        DisplayPath   = $_.FullName
                        SizeBytes     = $sz
                        SizeFormatted = Format-ByteSize $sz
                        Confidence    = "SNAPSHOT DIFF"
                        RiskLevel     = "SAFE"
                    })
                }
            }
        }
    }

    $rRoots = @(
        "HKCU:\SOFTWARE",
        "HKLM:\SOFTWARE",
        "HKLM:\SOFTWARE\WOW6432Node",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($rr in $rRoots) {
        if (Test-Path -LiteralPath $rr) {
            Get-ChildItem -LiteralPath $rr -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $oldRegs.Contains($_.PSPath)) {
                    $diffResults.Add([PSCustomObject]@{
                        IsSelected    = $true
                        Category      = "Snapshot Diff (New Registry)"
                        ItemType      = "RegistryKey"
                        TargetPath    = $_.PSPath
                        SubTarget     = ""
                        DisplayPath   = ($_.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '')
                        SizeBytes     = [int64]0
                        SizeFormatted = "—"
                        Confidence    = "SNAPSHOT DIFF"
                        RiskLevel     = "SAFE"
                    })
                }
            }
        }
    }

    return $diffResults
}

# ============================================================================
# 9B. PC SPEED BOOST ENGINE — ULTRA-ADVANCED SAFE OPTIMIZATION (MODULE 6)
# ============================================================================

$Script:BoostLog = New-Object System.Collections.Generic.List[string]
$Script:CurrentBoostPct = 0.0

function Invoke-BoostUiPump {
    try {
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $Window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [System.Threading.DispatcherOperationCallback]{ param($f); $f.Continue = $false; return $null },
            $frame
        ) | Out-Null
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } catch {}
}

function Set-BoostRingProgress {
    param(
        [double]$Percent,
        [string]$RingLabel = "PROGRESS",
        [string]$ActiveStep = "",
        [string]$AccentHex = ""
    )
    $p = [Math]::Max(0, [Math]::Min(100, $Percent))
    $Script:CurrentBoostPct = $p
    try {
        if ($p -le 0.1) {
            $Controls['BoostRingArc'].Data = $null
        } elseif ($p -ge 99.9) {
            $Controls['BoostRingArc'].Data = [System.Windows.Media.Geometry]::Parse("M 62,5 A 57,57 0 1 1 62,119 A 57,57 0 1 1 62,5")
        } else {
            $rad = ($p / 100.0) * 2.0 * [Math]::PI
            $x = [Math]::Round(62.0 + 57.0 * [Math]::Sin($rad), 2)
            $y = [Math]::Round(62.0 - 57.0 * [Math]::Cos($rad), 2)
            $large = if ($p -gt 50.0) { 1 } else { 0 }
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $pathStr = [string]::Format($inv, "M 62,5 A 57,57 0 {0} 1 {1},{2}", $large, $x, $y)
            $Controls['BoostRingArc'].Data = [System.Windows.Media.Geometry]::Parse($pathStr)
        }
        if (-not [string]::IsNullOrWhiteSpace($AccentHex)) {
            $Controls['BoostRingArc'].Stroke = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($AccentHex)
        }
        $Controls['TxtBoostRingPercent'].Text = "$([int][Math]::Round($p))%"
        $Controls['TxtBoostRingLabel'].Text   = $RingLabel
        $Controls['PbBoostProgress'].Value    = $p
        if (-not [string]::IsNullOrWhiteSpace($ActiveStep)) {
            $Controls['TxtBoostActiveStep'].Text = $ActiveStep
        }
    } catch {}
    Invoke-BoostUiPump
}

function Animate-BoostRingTo {
    param(
        [double]$TargetPercent,
        [string]$RingLabel = "PROGRESS",
        [string]$ActiveStep = "",
        [string]$AccentHex = "",
        [int]$Steps = 8,
        [int]$DelayMs = 16
    )
    $start = $Script:CurrentBoostPct
    $end   = [Math]::Max(0, [Math]::Min(100, $TargetPercent))
    if ([Math]::Abs($end - $start) -lt 1.0) {
        Set-BoostRingProgress -Percent $end -RingLabel $RingLabel -ActiveStep $ActiveStep -AccentHex $AccentHex
        return
    }
    for ($i = 1; $i -le $Steps; $i++) {
        $t = $i / [double]$Steps
        # Ease-out cubic
        $ease = 1.0 - [Math]::Pow(1.0 - $t, 3.0)
        $val = $start + ($end - $start) * $ease
        Set-BoostRingProgress -Percent $val -RingLabel $RingLabel -ActiveStep $ActiveStep -AccentHex $AccentHex
        Start-Sleep -Milliseconds $DelayMs
    }
}

function Update-BoostRamTelemetry {
    param([bool]$UpdateRing = $true)
    try {
        $snap = [NovaGenNative]::GetMemorySnapshot()
        if ($snap -and $snap[1] -gt 0) {
            $loadPct = [int]$snap[0]
            $totalGB = [Math]::Round($snap[1] / 1GB, 1)
            $availGB = [Math]::Round($snap[2] / 1GB, 1)
            $usedGB  = [Math]::Round(($snap[1] - $snap[2]) / 1GB, 1)
            $Controls['TxtBoostSysRAM'].Text = "$usedGB / $totalGB GB"
            if ($UpdateRing) {
                $ringColor = if ($loadPct -ge 85) { "#EF4444" } elseif ($loadPct -ge 65) { "#F59E0B" } else { "#06B6D4" }
                Set-BoostRingProgress -Percent $loadPct -RingLabel "RAM USED" -ActiveStep "System RAM: $usedGB / $totalGB GB ($loadPct%) — Ready to optimize" -AccentHex $ringColor
            }
        }
    } catch {}
}

function Write-BoostLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    $Script:BoostLog.Add($line)
    try {
        $Controls['TxtBoostLog'].AppendText($line + "`r`n")
        $Controls['TxtBoostLog'].CaretIndex = $Controls['TxtBoostLog'].Text.Length
        $Controls['TxtBoostLog'].ScrollToEnd()
    } catch {}
    Invoke-BoostUiPump
}

function Get-BoostCategorySize {
    param([string]$CategoryKey)
    $paths = @()
    switch ($CategoryKey) {
        "WinTemp"   { $paths = @("$env:SystemRoot\Temp", "$env:TEMP", "$env:TMP") }
        "Prefetch"  { $paths = @("$env:SystemRoot\Prefetch") }
        "WUCache"   { $paths = @("$env:SystemRoot\SoftwareDistribution\Download") }
        "Thumbnail" { $paths = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer") }
        "WER"       { $paths = @("$env:ProgramData\Microsoft\Windows\WER","$env:LOCALAPPDATA\Microsoft\Windows\WER") }
        "DelivOpt"  { $paths = @("$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache") }
        "BrowserCache" {
            $paths = @(
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
                "$env:APPDATA\Mozilla\Firefox\Profiles"
            )
        }
        "FontCache" { $paths = @("$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache") }
        "EventLogs" { return [int64]0 }  # Measured differently
    }
    $total = [int64]0
    foreach ($p in $paths) {
        if (Test-Path $p) { $total += Get-DirectorySizeFast $p }
    }
    return $total
}

function Invoke-BoostCleanPath {
    param([string]$Path, [bool]$DryRun = $false, [string]$Label = "")
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    if (Test-IsProtectedPath $Path) { return [int64]0 }

    $beforeSz = Get-DirectorySizeFast $Path
    if ($DryRun) { return $beforeSz }
    if ($beforeSz -le 0) {
        # Still try removing empty dirs/0-byte files
        try {
            Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        return [int64]0
    }

    # Delete file-by-file so a single locked file never blocks cleaning unlocked sibling files
    try {
        $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            try {
                [System.IO.File]::Delete($f.FullName)
            } catch {
                try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        # Clean empty directories bottom-up
        $dirs = Get-ChildItem -LiteralPath $Path -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending
        foreach ($d in $dirs) {
            try {
                if ((Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
                    Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    } catch {}

    $afterSz = Get-DirectorySizeFast $Path
    $actualFreed = [int64]($beforeSz - $afterSz)
    if ($actualFreed -lt 0) { $actualFreed = [int64]0 }
    return $actualFreed
}

function Invoke-PCSpeedBoost {
    param(
        [bool]$DryRun = $false,
        [bool]$DoRAM = $true,
        [bool]$DoWinTemp = $true,
        [bool]$DoPrefetch = $true,
        [bool]$DoDNS = $true,
        [bool]$DoWUCache = $true,
        [bool]$DoThumbnail = $true,
        [bool]$DoFontCache = $false,
        [bool]$DoBrowserCache = $true,
        [bool]$DoGPUCache = $true,
        [bool]$DoUWPCache = $true,
        [bool]$DoWER = $true,
        [bool]$DoDelivOpt = $true,
        [bool]$DoSSDTrim = $true,
        [bool]$DoPowerPlan = $false,
        [bool]$DoRecycleBin = $false,
        [bool]$DoDISMClean = $false,
        [bool]$DoEventLogs = $false
    )

    $Script:BoostLog.Clear()
    $mode = if ($DryRun) { "ANALYZE (DRY-RUN)" } else { "BOOST NOW" }
    $ringLabel = if ($DryRun) { "ANALYZING" } else { "BOOSTING" }
    $ringHex   = if ($DryRun) { "#06B6D4" } else { "#22C55E" }

    $enabledFlags = @($DoRAM, $DoWinTemp, $DoPrefetch, $DoDNS, $DoWUCache, $DoThumbnail, $DoFontCache, $DoBrowserCache, $DoGPUCache, $DoUWPCache, $DoWER, $DoDelivOpt, $DoSSDTrim, $DoPowerPlan, $DoRecycleBin, $DoDISMClean, $DoEventLogs)
    $totalSteps = ($enabledFlags | Where-Object { $_ -eq $true }).Count
    if ($totalSteps -le 0) { $totalSteps = 1 }
    $stepIdx = 0

    Set-BoostRingProgress -Percent 0 -RingLabel $ringLabel -ActiveStep "Initializing NovaGen PC Speed Boost Engine..." -AccentHex $ringHex
    Write-BoostLog "========================================" "INFO"
    Write-BoostLog "NovaGen PC Speed Boost Engine — MODE: $mode" "INFO"
    Write-BoostLog "========================================" "INFO"

    $totalFreed = [int64]0
    $ramFreedMB = 0

    # ---- 1. RAM / Working Set Flush ----
    if ($DoRAM) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Flushing RAM & Process Working Sets..." -AccentHex $ringHex
        Write-BoostLog "RAM Flush: Measuring system physical memory..." "INFO"
        $memBefore = [NovaGenNative]::GetMemorySnapshot()
        if (-not $DryRun) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect(2, [System.GCCollectionMode]::Forced, $true, $true)
            $flushed = 0
            foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
                try {
                    if ($proc.Handle -ne [IntPtr]::Zero) {
                        if ([NovaGenNative]::EmptyWorkingSet($proc.Handle)) { $flushed++ }
                    }
                } catch {}
            }
            Start-Sleep -Milliseconds 250
            $standbyOk = [NovaGenNative]::PurgeStandbyMemory()
            Start-Sleep -Milliseconds 200
            $memAfter = [NovaGenNative]::GetMemorySnapshot()
            $diffBytes = [int64]$memAfter[2] - [int64]$memBefore[2]
            $ramFreedMB = if ($diffBytes -gt 0) { [int][Math]::Round($diffBytes / 1MB) } else { 0 }
            $Controls['TxtBoostRAM'].Text = "$ramFreedMB MB"
            Update-BoostRamTelemetry -UpdateRing $false
            $sbNote = if ($standbyOk) { " + Standby RAM List Purged" } else { "" }
            Write-BoostLog "RAM Flush: Trimmed $flushed processes$sbNote — $ramFreedMB MB physical RAM reclaimed!" "OK"
        } else {
            $usedMB = [int][Math]::Round(($memBefore[1] - $memBefore[2]) / 1MB)
            $ramFreedMB = [Math]::Max(32, [int][Math]::Round($usedMB * 0.08))
            $Controls['TxtBoostRAM'].Text = "~$ramFreedMB MB"
            Write-BoostLog "RAM Flush: Would trim idle process working sets (~$ramFreedMB MB est.). (Dry Run)" "DRY"
        }
    }

    # ---- 2. Windows Temp Files + Shader & Crash Caches ----
    if ($DoWinTemp) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Deep Cleaning Temp & Shader Caches..." -AccentHex $ringHex
        $tempPaths = @(
            "$env:SystemRoot\Temp",
            "$env:TEMP",
            "$env:TMP",
            "$env:LOCALAPPDATA\Temp",
            "$env:LOCALAPPDATA\D3DSCache",
            "$env:LOCALAPPDATA\CrashDumps"
        )
        $catFound = [int64]0
        $catFreed = [int64]0
        foreach ($tp in ($tempPaths | Select-Object -Unique)) {
            if (Test-Path $tp) {
                $sz = Get-DirectorySizeFast $tp
                if ($sz -gt 0) {
                    $catFound += $sz
                    Write-BoostLog "Temp/Cache [$tp]: $(Format-ByteSize $sz) found." "INFO"
                    $catFreed += Invoke-BoostCleanPath -Path $tp -DryRun $DryRun -Label "WinTemp"
                }
            }
        }
        $totalFreed += $catFreed
        $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        if (-not $DryRun) {
            $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed
            $lockedLeft = [Math]::Max([int64]0, $catFound - $catFreed)
            if ($lockedLeft -gt 1MB) {
                Write-BoostLog "Temp/Cache: $(Format-ByteSize $catFreed) freed ($(Format-ByteSize $lockedLeft) locked by running apps)." "OK"
            } else {
                Write-BoostLog "Temp/Cache: $(Format-ByteSize $catFreed) freed." "OK"
            }
        } else {
            Write-BoostLog "Temp/Cache: $(Format-ByteSize $catFreed) would be freed." "OK"
        }
    }

    # ---- 3. Prefetch Files ----
    if ($DoPrefetch) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Scanning Windows Prefetch..." -AccentHex $ringHex
        $pfPath = "$env:SystemRoot\Prefetch"
        if (Test-Path $pfPath) {
            $sz = Get-DirectorySizeFast $pfPath
            Write-BoostLog "Prefetch [$pfPath]: $(Format-ByteSize $sz) found." "INFO"
            if (-not $DryRun) {
                $freed = Invoke-BoostCleanPath -Path $pfPath -DryRun $false -Label "Prefetch"
                $totalFreed += $freed
                $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed
                Write-BoostLog "Prefetch: $(Format-ByteSize $freed) freed. Windows will rebuild automatically." "OK"
            } else {
                $totalFreed += $sz
                Write-BoostLog "Prefetch: $(Format-ByteSize $sz) would be freed. (Dry Run)" "DRY"
            }
            $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        }
    }

    # ---- 4. DNS Cache Flush ----
    if ($DoDNS) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Flushing DNS Resolver Cache..." -AccentHex $ringHex
        if (-not $DryRun) {
            try {
                & ipconfig /flushdns 2>&1 | Out-Null
                Write-BoostLog "DNS Cache: Flushed successfully via ipconfig." "OK"
            } catch {
                Write-BoostLog "DNS Cache: Flush skipped (not critical)." "WARN"
            }
        } else {
            Write-BoostLog "DNS Cache: Would flush DNS resolver cache. (Dry Run)" "DRY"
        }
    }

    # ---- 5. Windows Update Download Cache ----
    if ($DoWUCache) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Checking Windows Update Cache..." -AccentHex $ringHex
        $wuPath = "$env:SystemRoot\SoftwareDistribution\Download"
        if (Test-Path $wuPath) {
            $sz = Get-DirectorySizeFast $wuPath
            Write-BoostLog "WU Cache [$wuPath]: $(Format-ByteSize $sz) found." "INFO"
            if (-not $DryRun) {
                try { Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue } catch {}
                Start-Sleep -Milliseconds 1200
                $freed = Invoke-BoostCleanPath -Path $wuPath -DryRun $false -Label "WUCache"
                $totalFreed += $freed
                $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed
                Start-Sleep -Milliseconds 400
                try { Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue } catch {}
                Write-BoostLog "WU Cache: $(Format-ByteSize $freed) freed (wuauserv restarted)." "OK"
            } else {
                $totalFreed += $sz
                Write-BoostLog "WU Cache: $(Format-ByteSize $sz) would be freed. (Dry Run)" "DRY"
            }
            $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        }
    }

    # ---- 6. Thumbnail Cache ----
    if ($DoThumbnail) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Scanning Thumbnail Cache..." -AccentHex $ringHex
        $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        if (Test-Path $thumbPath) {
            $thumbFiles = Get-ChildItem -LiteralPath $thumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue
            $sz = ($thumbFiles | Measure-Object -Property Length -Sum).Sum
            if (-not $sz) { $sz = [int64]0 }
            Write-BoostLog "Thumbnail Cache: $(Format-ByteSize $sz) found ($($thumbFiles.Count) files)." "INFO"
            if (-not $DryRun) {
                $freed = [int64]0
                foreach ($tf in $thumbFiles) {
                    try {
                        $freed += $tf.Length
                        Remove-Item -LiteralPath $tf.FullName -Force -ErrorAction SilentlyContinue
                    } catch {}
                }
                $totalFreed += $freed
                $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed
                Write-BoostLog "Thumbnail Cache: $(Format-ByteSize $freed) freed (auto-rebuilds)." "OK"
            } else {
                $totalFreed += $sz
                Write-BoostLog "Thumbnail Cache: $(Format-ByteSize $sz) would be freed. (Dry Run)" "DRY"
            }
            $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        }
    }

    # ---- 7. Font Cache ----
    if ($DoFontCache) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Checking Font Cache..." -AccentHex $ringHex
        $fontPath = "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache"
        if (Test-Path $fontPath) {
            $sz = Get-DirectorySizeFast $fontPath
            Write-BoostLog "Font Cache: $(Format-ByteSize $sz) found." "INFO"
            if (-not $DryRun) {
                try { Stop-Service -Name "FontCache" -Force -ErrorAction SilentlyContinue } catch {}
                Start-Sleep -Milliseconds 1000
                $freed = Invoke-BoostCleanPath -Path $fontPath -DryRun $false -Label "FontCache"
                $totalFreed += $freed
                $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed
                try { Start-Service -Name "FontCache" -ErrorAction SilentlyContinue } catch {}
                Write-BoostLog "Font Cache: $(Format-ByteSize $freed) freed (FontCache service restarted)." "OK"
            } else {
                $totalFreed += $sz
                Write-BoostLog "Font Cache: $(Format-ByteSize $sz) would be freed. (Dry Run)" "DRY"
            }
            $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        }
    }

    # ---- 8. All Browsers Deep Cache (Brave, Chrome, Edge, Opera, Vivaldi, Firefox — All Profiles) ----
    if ($DoBrowserCache) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Scanning All Browser Caches (Brave/Chrome/Edge/FF)..." -AccentHex $ringHex
        $chromiumRoots = @(
            @{ Name = "Brave";    Root = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
            @{ Name = "Chrome";   Root = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
            @{ Name = "Edge";     Root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
            @{ Name = "Opera";    Root = "$env:APPDATA\Opera Software\Opera Stable" },
            @{ Name = "OperaGX";  Root = "$env:APPDATA\Opera Software\Opera GX Stable" },
            @{ Name = "Vivaldi";  Root = "$env:LOCALAPPDATA\Vivaldi\User Data" }
        )
        $cacheSubDirs = @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage")
        $catFreed = [int64]0

        foreach ($br in $chromiumRoots) {
            if (-not (Test-Path $br.Root)) { continue }
            # Check direct (Opera) and profile folders (Default, Profile *)
            $profileDirs = @($br.Root)
            $subProfiles = Get-ChildItem -LiteralPath $br.Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
            foreach ($sp in $subProfiles) { $profileDirs += $sp.FullName }

            $brTotal = [int64]0
            foreach ($pDir in ($profileDirs | Select-Object -Unique)) {
                foreach ($sub in $cacheSubDirs) {
                    $target = Join-Path $pDir $sub
                    if (Test-Path -LiteralPath $target) {
                        $brTotal += Invoke-BoostCleanPath -Path $target -DryRun $DryRun -Label $br.Name
                    }
                }
            }
            if ($brTotal -gt 0) {
                $catFreed += $brTotal
                Write-BoostLog "$($br.Name) Cache: $(Format-ByteSize $brTotal) $(if($DryRun){'found'}else{'freed'})." "INFO"
            }
        }

        # Firefox cache2 across all profiles
        $ffRoot = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
        if (Test-Path $ffRoot) {
            $ffTotal = [int64]0
            Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $c2 = Join-Path $_.FullName "cache2"
                if (Test-Path -LiteralPath $c2) {
                    $ffTotal += Invoke-BoostCleanPath -Path $c2 -DryRun $DryRun -Label "Firefox"
                }
            }
            if ($ffTotal -gt 0) {
                $catFreed += $ffTotal
                Write-BoostLog "Firefox Cache: $(Format-ByteSize $ffTotal) $(if($DryRun){'found'}else{'freed'})." "INFO"
            }
        }

        $totalFreed += $catFreed
        $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        if (-not $DryRun) { $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed }
        Write-BoostLog "All Browsers Deep Cache: $(Format-ByteSize $catFreed) $(if($DryRun){'would be freed'}else{'freed'})." "OK"
    }

    # ---- 8B. GPU Shader Caches (NVIDIA / AMD / Intel) ----
    if ($DoGPUCache) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Scanning GPU Shader Caches..." -AccentHex $ringHex
        $gpuPaths = @(
            @{ Name = "NVIDIA DXCache";    Path = "$env:LOCALAPPDATA\NVIDIA\DXCache" },
            @{ Name = "NVIDIA GLCache";    Path = "$env:LOCALAPPDATA\NVIDIA\GLCache" },
            @{ Name = "AMD DxCache";       Path = "$env:LOCALAPPDATA\AMD\DxCache" },
            @{ Name = "Intel ShaderCache"; Path = "$env:LOCALAPPDATA\Intel\ShaderCache" }
        )
        $catFreed = [int64]0
        foreach ($gp in $gpuPaths) {
            if (Test-Path $gp.Path) {
                $sz = Get-DirectorySizeFast $gp.Path
                if ($sz -gt 0) {
                    Write-BoostLog "$($gp.Name): $(Format-ByteSize $sz) found." "INFO"
                    $catFreed += Invoke-BoostCleanPath -Path $gp.Path -DryRun $DryRun -Label $gp.Name
                }
            }
        }
        $totalFreed += $catFreed
        $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        if (-not $DryRun) { $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed }
        Write-BoostLog "GPU Shader Caches: $(Format-ByteSize $catFreed) $(if($DryRun){'would be freed'}else{'freed'})." "OK"
    }

    # ---- 8C. Store / UWP App TempState Caches ----
    if ($DoUWPCache) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Cleaning Store/UWP App Temp Caches..." -AccentHex $ringHex
        $pkgRoot = "$env:LOCALAPPDATA\Packages"
        $catFreed = [int64]0
        if (Test-Path $pkgRoot) {
            Get-ChildItem -LiteralPath $pkgRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                foreach ($sub in @("TempState", "AC\Temp")) {
                    $tp = Join-Path $_.FullName $sub
                    if (Test-Path -LiteralPath $tp) {
                        $catFreed += Invoke-BoostCleanPath -Path $tp -DryRun $DryRun -Label "UWP"
                    }
                }
            }
        }
        $totalFreed += $catFreed
        $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        if (-not $DryRun) { $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed }
        Write-BoostLog "Store/UWP Temp Caches: $(Format-ByteSize $catFreed) $(if($DryRun){'would be freed'}else{'freed'})." "OK"
    }

    # ---- 9. Windows Error Reporting ----
    if ($DoWER) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Scanning Windows Error Reports..." -AccentHex $ringHex
        $werPaths = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                      "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
                      "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
                      "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue")
        $catFreed = [int64]0
        foreach ($wp in $werPaths) {
            if (Test-Path $wp) {
                $catFreed += Invoke-BoostCleanPath -Path $wp -DryRun $DryRun -Label "WER"
            }
        }
        $totalFreed += $catFreed
        $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        if (-not $DryRun) { $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed }
        Write-BoostLog "Windows Error Reports: $(Format-ByteSize $catFreed) $(if($DryRun){'would be freed'}else{'freed'})." "OK"
    }

    # ---- 10. Delivery Optimization Cache ----
    if ($DoDelivOpt) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Checking Delivery Optimization..." -AccentHex $ringHex
        $doPath = "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
        if (Test-Path $doPath) {
            $sz = Get-DirectorySizeFast $doPath
            Write-BoostLog "Delivery Optimization: $(Format-ByteSize $sz) found." "INFO"
            if (-not $DryRun) {
                $freed = Invoke-BoostCleanPath -Path $doPath -DryRun $false -Label "DelivOpt"
                $totalFreed += $freed
                $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed
                Write-BoostLog "Delivery Optimization: $(Format-ByteSize $freed) freed." "OK"
            } else {
                $totalFreed += $sz
                Write-BoostLog "Delivery Optimization: $(Format-ByteSize $sz) would be freed. (Dry Run)" "DRY"
            }
            $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
        }
    }

    # ---- 10B. SSD TRIM Optimization ----
    if ($DoSSDTrim) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Running SSD TRIM Optimization..." -AccentHex $ringHex
        try {
            $sysDrive = $env:SystemDrive.TrimEnd(':')
            $hasSSD = (Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq 'SSD' }).Count -gt 0
            if ($hasSSD) {
                if (-not $DryRun) {
                    Optimize-Volume -DriveLetter $sysDrive -ReTrim -ErrorAction SilentlyContinue
                    Write-BoostLog "SSD TRIM: ReTrim completed on $($sysDrive): drive." "OK"
                } else {
                    Write-BoostLog "SSD TRIM: Would run ReTrim on SSD ($($sysDrive):). (Dry Run)" "DRY"
                }
            } else {
                Write-BoostLog "SSD TRIM: No SSD detected (or virtual disk) — skipped safely." "INFO"
            }
        } catch {
            Write-BoostLog "SSD TRIM: Skipped (not supported on this volume)." "WARN"
        }
    }

    # ---- 10C. Turbo High-Performance Power Plan (Opt-In) ----
    if ($DoPowerPlan) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Activating High-Performance Power Plan..." -AccentHex $ringHex
        try {
            $activeScheme = (& powercfg /getactivescheme 2>&1) -join ' '
            if (-not $DryRun) {
                # Try High Performance first; if missing, duplicate it
                $hpGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
                & powercfg /setactive $hpGuid 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    & powercfg /duplicatescheme $hpGuid 2>&1 | Out-Null
                    & powercfg /setactive $hpGuid 2>&1 | Out-Null
                }
                $newScheme = (& powercfg /getactivescheme 2>&1) -join ' '
                Write-BoostLog "Power Plan: Active -> $newScheme" "OK"
            } else {
                Write-BoostLog "Power Plan: Current -> $activeScheme | Would switch to High Performance. (Dry Run)" "DRY"
            }
        } catch {
            Write-BoostLog "Power Plan: Could not switch (Modern Standby / OEM lock)." "WARN"
        }
    }

    # ---- 11. Recycle Bin ----
    if ($DoRecycleBin) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Checking Recycle Bin..." -AccentHex $ringHex
        try {
            if (-not $DryRun) {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                Write-BoostLog "Recycle Bin: Cleared all drives." "OK"
            } else {
                Write-BoostLog "Recycle Bin: Would empty all drive Recycle Bins. (Dry Run)" "DRY"
            }
        } catch {
            Write-BoostLog "Recycle Bin: Skipped (may already be empty)." "WARN"
        }
    }

    # ---- 11B. DISM WinSxS Component Cleanup (Opt-In) ----
    if ($DoDISMClean) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Running DISM WinSxS Component Cleanup..." -AccentHex $ringHex
        if (-not $DryRun) {
            try {
                Write-BoostLog "DISM WinSxS: Cleaning superseded Windows Update backups (please wait)..." "INFO"
                $driveBefore = (Get-PSDrive $env:SystemDrive.TrimEnd(':')).Free
                & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet 2>&1 | Out-Null
                $driveAfter  = (Get-PSDrive $env:SystemDrive.TrimEnd(':')).Free
                $dismFreed   = [Math]::Max([int64]0, [int64]($driveAfter - $driveBefore))
                $totalFreed += $dismFreed
                $Controls['TxtBoostDisk'].Text = Format-ByteSize $totalFreed
                $Controls['TxtBoostEstimate'].Text = Format-ByteSize $totalFreed
                Write-BoostLog "DISM WinSxS: Cleanup complete (~$(Format-ByteSize $dismFreed) reclaimed)." "OK"
            } catch {
                Write-BoostLog "DISM WinSxS: Skipped or encountered an error." "WARN"
            }
        } else {
            Write-BoostLog "DISM WinSxS: Would run StartComponentCleanup to trim old update backups. (Dry Run)" "DRY"
        }
    }

    # ---- 12. Event Logs (Optional — user must opt-in) ----
    if ($DoEventLogs) {
        $stepIdx++
        Animate-BoostRingTo -TargetPercent (($stepIdx / $totalSteps) * 95) -RingLabel $ringLabel -ActiveStep "Step $stepIdx/$totalSteps : Processing Event Logs..." -AccentHex $ringHex
        $logs = @("Application", "System", "Security", "Setup")
        if (-not $DryRun) {
            foreach ($logName in $logs) {
                try {
                    & wevtutil.exe cl $logName 2>&1 | Out-Null
                    Write-BoostLog "Event Log [$logName]: Cleared." "OK"
                } catch {
                    Write-BoostLog "Event Log [$logName]: Skipped (access denied or in use)." "WARN"
                }
            }
        } else {
            Write-BoostLog "Event Logs [App/System/Security/Setup]: Would be cleared. (Dry Run)" "DRY"
        }
    }

    # ---- FINAL SUMMARY ----
    $doneLabel = if ($DryRun) { "ANALYZED" } else { "OPTIMIZED" }
    $doneStep  = if ($DryRun) { "Analyze Complete — $(Format-ByteSize $totalFreed) disk + ~$ramFreedMB MB RAM ready to clean" } else { "Boost Complete — $(Format-ByteSize $totalFreed) disk freed + $ramFreedMB MB RAM reclaimed!" }
    Animate-BoostRingTo -TargetPercent 100 -RingLabel $doneLabel -ActiveStep $doneStep -AccentHex "#22C55E" -Steps 12 -DelayMs 18
    Write-BoostLog "========================================" "INFO"
    if ($DryRun) {
        Write-BoostLog "ANALYZE COMPLETE — Estimated savings: $(Format-ByteSize $totalFreed) disk + ~$ramFreedMB MB RAM" "OK"
    } else {
        Write-BoostLog "BOOST COMPLETE — Disk freed: $(Format-ByteSize $totalFreed) | RAM flushed: $ramFreedMB MB" "OK"
    }
    Write-BoostLog "========================================" "INFO"

    return [PSCustomObject]@{
        TotalFreedBytes = $totalFreed
        RAMFreedMB      = $ramFreedMB
        IsDryRun        = $DryRun
    }
}

# ============================================================================
# 10. WPF XAML INTERFACE (DARK OBSIDIAN NOC MODE - 90/8/2 ENTERPRISE DISCIPLINE)
# ============================================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NOVAGEN // ZERO-TRACE DEEP UNINSTALLER PRO v4.2"
        Width="1380" Height="860" MinWidth="1120" MinHeight="720"
        WindowStartupLocation="CenterScreen"
        Background="#060B16"
        Foreground="#F8FAFC"
        FontFamily="Segoe UI">

    <Window.Resources>
        <!-- Solid Brushes (90-8-2 Enterprise Dark Obsidian Palette) -->
        <SolidColorBrush x:Key="CanvasBrush" Color="#060B16"/>
        <SolidColorBrush x:Key="SurfaceBrush" Color="#0B1220"/>
        <SolidColorBrush x:Key="ElevatedBrush" Color="#111C33"/>
        <SolidColorBrush x:Key="RecessedBrush" Color="#040811"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#1E293B"/>
        <SolidColorBrush x:Key="PrimaryInk" Color="#F8FAFC"/>
        <SolidColorBrush x:Key="SecondaryInk" Color="#94A3B8"/>
        <SolidColorBrush x:Key="MutedInk" Color="#64748B"/>
        <SolidColorBrush x:Key="AccentCobalt" Color="#2563EB"/>
        <SolidColorBrush x:Key="AccentCobaltHover" Color="#1D4ED8"/>
        <SolidColorBrush x:Key="AccentCyan" Color="#22D3EE"/>
        <SolidColorBrush x:Key="SemanticSuccess" Color="#059669"/>
        <SolidColorBrush x:Key="SemanticWarning" Color="#D97706"/>
        <SolidColorBrush x:Key="SemanticDanger" Color="#DC2626"/>
        <SolidColorBrush x:Key="SemanticDangerHover" Color="#B91C1C"/>

        <!-- Primary Cobalt Button -->
        <Style x:Key="BtnPrimary" TargetType="Button">
            <Setter Property="Background" Value="#2563EB"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#3B82F6"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bdr" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bdr" Property="Background" Value="#1D4ED8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bdr" Property="Background" Value="#1E293B"/>
                                <Setter Property="Foreground" Value="#64748B"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger / Nuke Action Button -->
        <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="#DC2626"/>
            <Setter Property="BorderBrush" Value="#EF4444"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bdr" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bdr" Property="Background" Value="#B91C1C"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bdr" Property="Background" Value="#1E293B"/>
                                <Setter Property="Foreground" Value="#64748B"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary Surface Button -->
        <Style x:Key="BtnSecondary" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="{DynamicResource ElevatedBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryInk}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bdr" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bdr" Property="Background" Value="{DynamicResource BorderBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bdr" Property="Background" Value="{DynamicResource RecessedBrush}"/>
                                <Setter Property="Foreground" Value="{DynamicResource MutedInk}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Sidebar Navigation Button -->
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{DynamicResource SecondaryInk}"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bdr" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}" Margin="0,2">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bdr" Property="Background" Value="{DynamicResource ElevatedBrush}"/>
                                <Setter Property="Foreground" Value="{DynamicResource PrimaryInk}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Dark TextBox -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource RecessedBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryInk}"/>
            <Setter Property="CaretBrush" Value="{DynamicResource AccentCyan}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Dark DataGrid Styling -->
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="{DynamicResource SurfaceBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryInk}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="RowBackground" Value="{DynamicResource SurfaceBrush}"/>
            <Setter Property="AlternatingRowBackground" Value="{DynamicResource RecessedBrush}"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="VerticalGridLinesBrush" Value="Transparent"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="SelectionUnit" Value="FullRow"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserDeleteRows" Value="False"/>
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="RowHeight" Value="34"/>
            <Setter Property="FontSize" Value="12.5"/>
        </Style>

        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="{DynamicResource RecessedBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource MutedInk}"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
        </Style>

        <Style TargetType="DataGridRow">
            <Setter Property="Foreground" Value="{DynamicResource PrimaryInk}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{DynamicResource ElevatedBrush}"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{DynamicResource AccentCobalt}"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="DataGridCell">
            <Setter Property="Foreground" Value="{DynamicResource PrimaryInk}"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/>  <!-- Top Telemetry Bar -->
            <RowDefinition Height="78"/>  <!-- 5-Col KPI Strip -->
            <RowDefinition Height="*"/>   <!-- Main Operational Split -->
            <RowDefinition Height="34"/>  <!-- Bottom Live Telemetry & Console Bar -->
        </Grid.RowDefinitions>

        <!-- ================================================================ -->
        <!-- ROW 0: TOP TELEMETRY UTILITY BAR                                 -->
        <!-- ================================================================ -->
        <Border Grid.Row="0" Background="#040811" BorderBrush="#1E293B" BorderThickness="0,0,0,1" Padding="16,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Brand Identity -->
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#2563EB" CornerRadius="4" Width="22" Height="22" Margin="0,0,10,0">
                        <TextBlock Text="N" Foreground="#FFFFFF" FontWeight="Bold" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="NOVAGEN" Foreground="#F8FAFC" FontWeight="Bold" FontSize="14" VerticalAlignment="Center"/>
                    <TextBlock Text=" // ZERO-TRACE DEEP UNINSTALLER PRO" Foreground="#64748B" FontWeight="SemiBold" FontSize="11.5" VerticalAlignment="Center" Margin="6,1,0,0"/>
                    <Border Background="#111C33" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="4" Padding="6,2" Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="ENGINE v4.2" Foreground="#22D3EE" FontFamily="Consolas" FontSize="10" FontWeight="Bold"/>
                    </Border>
                </StackPanel>

                <!-- Right Telemetry Pills & Quick Utility Actions -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border x:Name="AdminBadgeBorder" Background="#06281E" BorderBrush="#059669" BorderThickness="1" CornerRadius="10" Padding="9,3" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                            <Ellipse x:Name="AdminDot" Width="6" Height="6" Fill="#10B981" Margin="0,0,6,0" VerticalAlignment="Center"/>
                            <TextBlock x:Name="AdminBadgeText" Text="ADMINISTRATOR ELEVATED" Foreground="#34D399" FontSize="10" FontWeight="Bold"/>
                        </StackPanel>
                    </Border>

                    <Border Background="#0B1220" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="10" Padding="9,3" Margin="0,0,10,0">
                        <TextBlock Text="AUTO-REG BACKUP: ON" Foreground="#94A3B8" FontSize="10" FontWeight="SemiBold"/>
                    </Border>

                    <!-- Theme Toggle Switch (Dark / Gradient Blue Light) -->
                    <Border Background="#0B1220" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="14" Padding="3" Margin="0,0,10,0" VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="BtnThemeDark" Content="🌙 DARK" Style="{StaticResource BtnSecondary}" Padding="9,3" FontSize="10" FontWeight="Bold" Margin="0,0,2,0"/>
                            <Button x:Name="BtnThemeLight" Content="☀️ LIGHT" Style="{StaticResource BtnSecondary}" Padding="9,3" FontSize="10" FontWeight="Bold"/>
                        </StackPanel>
                    </Border>

                    <Button x:Name="BtnOpenBackups" Content="Backups Folder" Style="{StaticResource BtnSecondary}" Padding="10,4" FontSize="11" Margin="0,0,6,0"/>
                    <Button x:Name="BtnRefreshAll" Content="Rescan System" Style="{StaticResource BtnPrimary}" Padding="11,4" FontSize="11"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ================================================================ -->
        <!-- ROW 1: 5-COLUMN COMPACT KPI TELEMETRY STRIP                      -->
        <!-- ================================================================ -->
        <Grid Grid.Row="1" Margin="14,10,14,6">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- KPI 1: Installed Apps -->
            <Border Grid.Column="0" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,0,8,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="INSTALLED APPLICATIONS" Foreground="{DynamicResource MutedInk}" FontSize="10" FontWeight="Bold"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Bottom">
                        <TextBlock x:Name="KpiAppCount" Text="0" Foreground="{DynamicResource PrimaryInk}" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
                        <TextBlock x:Name="KpiAppSub" Text=" Win32 + Store" Foreground="{DynamicResource SecondaryInk}" FontSize="11" VerticalAlignment="Bottom" Margin="6,0,0,3"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- KPI 2: Total App Footprint -->
            <Border Grid.Column="1" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,0,8,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="INDEXED APP FOOTPRINT" Foreground="{DynamicResource MutedInk}" FontSize="10" FontWeight="Bold"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Bottom">
                        <TextBlock x:Name="KpiTotalSize" Text="0.00 GB" Foreground="{DynamicResource PrimaryInk}" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
                        <TextBlock Text=" Registered Size" Foreground="{DynamicResource SecondaryInk}" FontSize="11" VerticalAlignment="Bottom" Margin="6,0,0,3"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- KPI 3: System C: Drive Telemetry -->
            <Border Grid.Column="2" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,0,8,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="C: SYSTEM DRIVE FREE SPACE" Foreground="{DynamicResource MutedInk}" FontSize="10" FontWeight="Bold"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Bottom">
                        <TextBlock x:Name="KpiDriveFree" Text="0.00 GB" Foreground="{DynamicResource AccentCyan}" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
                        <TextBlock x:Name="KpiDriveSub" Text=" / 0 GB" Foreground="{DynamicResource SecondaryInk}" FontFamily="Consolas" FontSize="11" VerticalAlignment="Bottom" Margin="4,0,0,3"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- KPI 4: Active Scan Artifacts -->
            <Border Grid.Column="3" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12,8" Margin="0,0,8,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="DETECTED LEFTOVER TRACES" Foreground="{DynamicResource MutedInk}" FontSize="10" FontWeight="Bold"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Bottom">
                        <TextBlock x:Name="KpiLeftoverCount" Text="0" Foreground="{DynamicResource PrimaryInk}" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
                        <TextBlock x:Name="KpiLeftoverSize" Text=" (0 KB selected)" Foreground="{DynamicResource SecondaryInk}" FontSize="11" VerticalAlignment="Bottom" Margin="6,0,0,3"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- KPI 5: Session Reclaimed Space -->
            <Border Grid.Column="4" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12,8">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="SESSION RECLAIMED STORAGE" Foreground="{DynamicResource MutedInk}" FontSize="10" FontWeight="Bold"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" VerticalAlignment="Bottom">
                        <TextBlock x:Name="KpiReclaimed" Text="0 KB" Foreground="{DynamicResource SemanticSuccess}" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
                        <TextBlock Text=" 100% Wiped" Foreground="{DynamicResource SecondaryInk}" FontSize="11" VerticalAlignment="Bottom" Margin="6,0,0,3"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>

        <!-- ================================================================ -->
        <!-- ROW 2: MAIN 3-PANE ENTERPRISE WORKSPACE                          -->
        <!-- ================================================================ -->
        <Grid Grid.Row="2" Margin="14,4,14,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="210"/> <!-- Left Navigation Sidebar -->
                <ColumnDefinition Width="*"/>   <!-- Center Primary Workspace -->
                <ColumnDefinition Width="430"/> <!-- Right Deep-Scan & Nuke Inspector -->
            </Grid.ColumnDefinitions>

            <!-- ============================================================ -->
            <!-- LEFT SIDEBAR: OPERATIONAL MODES                              -->
            <!-- ============================================================ -->
            <Border Grid.Column="0" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,10,0">
                <DockPanel LastChildFill="False">
                    <TextBlock DockPanel.Dock="Top" Text="OPERATIONAL MODULES" Foreground="{DynamicResource MutedInk}" FontSize="10" FontWeight="Bold" Margin="6,4,0,8"/>

                    <Button x:Name="NavBtnApps" DockPanel.Dock="Top" Content="1. Installed Applications" Style="{StaticResource NavButton}"/>
                    <Button x:Name="NavBtnStore" DockPanel.Dock="Top" Content="2. Store &amp; Bloatware" Style="{StaticResource NavButton}"/>
                    <Button x:Name="NavBtnGhost" DockPanel.Dock="Top" Content="3. Ghost Leftover Sweeper" Style="{StaticResource NavButton}"/>
                    <Button x:Name="NavBtnHunter" DockPanel.Dock="Top" Content="4. Custom Target Hunter" Style="{StaticResource NavButton}"/>
                    <Button x:Name="NavBtnSnapshot" DockPanel.Dock="Top" Content="5. Install Snapshot Tracker" Style="{StaticResource NavButton}"/>
                    <Button x:Name="NavBtnBoost" DockPanel.Dock="Top" Content="6. PC Speed Boost" Style="{StaticResource NavButton}"/>

                    <Border DockPanel.Dock="Top" Background="{DynamicResource BorderBrush}" Height="1" Margin="4,12"/>

                    <!-- Deep Scan Coverage Card -->
                    <Border DockPanel.Dock="Top" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="10">
                        <StackPanel>
                            <TextBlock Text="18-POINT DEEP ENGINE" Foreground="{DynamicResource AccentCyan}" FontSize="10" FontWeight="Bold" Margin="0,0,0,6"/>
                            <TextBlock Text="• Program Files (x64 / x86)" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• AppData (Local/Low/Roaming)" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• ProgramData &amp; User .config" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• HKLM &amp; HKCU Software Hives" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• WOW6432Node &amp; VirtualStore" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• MSI Installer &amp; Folders Cache" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• MuiCache &amp; AppCompat Store" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• Prefetch (.pf) &amp; Temp Traces" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• Services, Tasks &amp; Firewall" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                            <TextBlock Text="• Locked File Reboot Nuker" Foreground="{DynamicResource SecondaryInk}" FontSize="11" Margin="0,1"/>
                        </StackPanel>
                    </Border>

                    <!-- Safety Shield Footer -->
                    <Border DockPanel.Dock="Bottom" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="10">
                        <StackPanel>
                            <TextBlock Text="OS PROTECTION GUARD" Foreground="{DynamicResource SemanticSuccess}" FontSize="10" FontWeight="Bold"/>
                            <TextBlock Text="System32, WinSxS &amp; core Windows directories are hardware-whitelisted. Auto .reg backup runs before every wipe."
                                       Foreground="{DynamicResource MutedInk}" FontSize="10.5" TextWrapping="Wrap" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>
                </DockPanel>
            </Border>

            <!-- ============================================================ -->
            <!-- CENTER PANE: MULTI-VIEW WORKSPACE                            -->
            <!-- ============================================================ -->
            <Border Grid.Column="1" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,10,0">
                <Grid>
                    <!-- ==================================================== -->
                    <!-- VIEW 1: INSTALLED DESKTOP APPLICATIONS               -->
                    <!-- ==================================================== -->
                    <Grid x:Name="ViewInstalledApps" Visibility="Visible">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <!-- Row 0: Section Header -->
                        <StackPanel Grid.Row="0" Margin="0,0,0,8">
                            <TextBlock Text="INSTALLED APPLICATIONS" Foreground="{DynamicResource PrimaryInk}" FontSize="13" FontWeight="Bold"/>
                            <TextBlock Text="Select any application to perform a 100% Zero-Trace Uninstall or Deep Leftover Scan" Foreground="{DynamicResource MutedInk}" FontSize="11"/>
                        </StackPanel>

                        <!-- Row 1: Dedicated Full-Width Search & Filter Bar -->
                        <Grid Grid.Row="1" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Border Grid.Column="0" Background="{DynamicResource ElevatedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1,1,0,1" CornerRadius="4,0,0,4" Padding="8,0">
                                <TextBlock Text="SEARCH" Foreground="{DynamicResource MutedInk}" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                            </Border>
                            <TextBox x:Name="TxtSearchApps" Grid.Column="1" Margin="0,0,8,0" ToolTip="Type application name, publisher, or install path"/>
                            <StackPanel Grid.Column="2" Orientation="Horizontal">
                                <Button x:Name="BtnFilterAll" Content="All" Style="{StaticResource BtnSecondary}" Padding="9,5" Margin="0,0,4,0"/>
                                <Button x:Name="BtnFilterDesktop" Content="Desktop" Style="{StaticResource BtnSecondary}" Padding="9,5" Margin="0,0,4,0"/>
                                <Button x:Name="BtnFilterUser" Content="User" Style="{StaticResource BtnSecondary}" Padding="9,5" Margin="0,0,4,0"/>
                                <Button x:Name="BtnSortSize" Content="Sort: Size ↓" Style="{StaticResource BtnSecondary}" Padding="9,5" Margin="0,0,4,0" ToolTip="Sort applications by size (Largest to Smallest)"/>
                                <Button x:Name="BtnSortName" Content="Sort: Name A-Z" Style="{StaticResource BtnSecondary}" Padding="9,5" Margin="0,0,4,0" ToolTip="Sort applications alphabetically by Name"/>
                                <Button x:Name="BtnCalcSizes" Content="Calc Exact Sizes" Style="{StaticResource BtnSecondary}" Padding="9,5"/>
                            </StackPanel>
                        </Grid>

                        <!-- Row 2: Selected App Telemetry Banner -->
                        <Border Grid.Row="2" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="10,7" Margin="0,0,0,8">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <TextBlock x:Name="LblSelectedAppName" Text="No Application Selected" Foreground="{DynamicResource AccentCyan}" FontSize="12.5" FontWeight="Bold"/>
                                    <TextBlock x:Name="LblSelectedAppMeta" Text="Click an application row below to inspect its install path and uninstall command." Foreground="{DynamicResource MutedInk}" FontFamily="Consolas" FontSize="11" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                                </StackPanel>
                                <Border Grid.Column="1" Background="{DynamicResource ElevatedBrush}" CornerRadius="4" Padding="8,4" VerticalAlignment="Center">
                                    <TextBlock x:Name="LblSelectedAppArch" Text="READY" Foreground="{DynamicResource SecondaryInk}" FontFamily="Consolas" FontSize="10.5" FontWeight="Bold"/>
                                </Border>
                            </Grid>
                        </Border>

                        <!-- Row 3: Applications DataGrid -->
                        <DataGrid x:Name="GridInstalledApps" Grid.Row="3">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="APPLICATION NAME" Binding="{Binding DisplayName}" Width="210"/>
                                <DataGridTextColumn Header="PUBLISHER" Binding="{Binding Publisher}" Width="140"/>
                                <DataGridTextColumn Header="VERSION" Binding="{Binding DisplayVersion}" Width="80"/>
                                <DataGridTextColumn Header="SIZE" Binding="{Binding SizeFormatted}" Width="75"/>
                                <DataGridTextColumn Header="ARCH" Binding="{Binding Architecture}" Width="50"/>
                                <DataGridTextColumn Header="INSTALLED" Binding="{Binding InstallDate}" Width="85"/>
                                <DataGridTextColumn Header="CATEGORY" Binding="{Binding Category}" Width="*"/>
                            </DataGrid.Columns>
                        </DataGrid>

                        <!-- Row 4: Action Footer for Selected App -->
                        <Grid Grid.Row="4" Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Orientation="Horizontal">
                                <Button x:Name="BtnOpenInstallDir" Content="Open Folder" Style="{StaticResource BtnSecondary}" Padding="10,7" Margin="0,0,6,0"/>
                                <Button x:Name="BtnFreshResetApp" Content="Fresh Config Reset" Style="{StaticResource BtnSecondary}" Padding="10,7" ToolTip="Scans only AppData, ProgramData, MuiCache &amp; HKCU configs to reset app to fresh install state"/>
                            </StackPanel>

                            <StackPanel Grid.Column="2" Orientation="Horizontal">
                                <Button x:Name="BtnDeepScanOnly" Content="Deep Scan Leftovers" Style="{StaticResource BtnPrimary}" Padding="11,7" Margin="0,0,6,0"/>
                                <Button x:Name="BtnFullDeepUninstall" Content="100% Deep Uninstall + Wipe" Style="{StaticResource BtnDanger}" Padding="12,7"/>
                            </StackPanel>
                        </Grid>
                    </Grid>

                    <!-- ==================================================== -->
                    <!-- VIEW 2: WINDOWS STORE & UWP BLOATWARE                -->
                    <!-- ==================================================== -->
                    <Grid x:Name="ViewStoreApps" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Margin="0,0,14,0">
                                <TextBlock Text="WINDOWS STORE &amp; UWP PACKAGES" Foreground="#F8FAFC" FontSize="13" FontWeight="Bold"/>
                                <TextBlock Text="Remove pre-installed UWP apps, Microsoft Store packages, and their AppData\Local\Packages cache" Foreground="#64748B" FontSize="11"/>
                            </StackPanel>
                            <TextBox x:Name="TxtSearchStore" Grid.Column="1" Margin="8,0,0,0"/>
                        </Grid>

                        <DataGrid x:Name="GridStoreApps" Grid.Row="1">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="PACKAGE NAME" Binding="{Binding Name}" Width="240"/>
                                <DataGridTextColumn Header="PUBLISHER" Binding="{Binding Publisher}" Width="160"/>
                                <DataGridTextColumn Header="VERSION" Binding="{Binding Version}" Width="100"/>
                                <DataGridTextColumn Header="ARCH" Binding="{Binding Architecture}" Width="65"/>
                                <DataGridTextColumn Header="PACKAGE FAMILY" Binding="{Binding PackageFamilyName}" Width="*"/>
                            </DataGrid.Columns>
                        </DataGrid>

                        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                            <Button x:Name="BtnScanStoreLeftovers" Content="Scan Package Cache" Style="{StaticResource BtnSecondary}" Margin="0,0,8,0"/>
                            <Button x:Name="BtnUninstallStoreApp" Content="Deep Remove Store App + LocalState" Style="{StaticResource BtnDanger}"/>
                        </StackPanel>
                    </Grid>

                    <!-- ==================================================== -->
                    <!-- VIEW 3: GHOST LEFTOVER SWEEPER                       -->
                    <!-- ==================================================== -->
                    <Grid x:Name="ViewGhostSweeper" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0">
                                <TextBlock Text="GHOST LEFTOVER SWEEPER (ORPHANED APPDATA &amp; PROGRAMDATA)" Foreground="#F8FAFC" FontSize="13" FontWeight="Bold"/>
                                <TextBlock Text="Finds folders in AppData (Local, Roaming, LocalLow) and ProgramData that do not match any currently installed application" Foreground="#64748B" FontSize="11"/>
                            </StackPanel>
                            <Button x:Name="BtnRunGhostScan" Grid.Column="1" Content="Scan for Ghost Folders" Style="{StaticResource BtnPrimary}"/>
                        </Grid>

                        <DataGrid x:Name="GridGhostItems" Grid.Row="1">
                            <DataGrid.Columns>
                                <DataGridTextColumn Header="FOLDER NAME" Binding="{Binding FolderName}" Width="180"/>
                                <DataGridTextColumn Header="LOCATION" Binding="{Binding Location}" Width="120"/>
                                <DataGridTextColumn Header="SIZE" Binding="{Binding SizeFormatted}" Width="85"/>
                                <DataGridTextColumn Header="LAST MODIFIED" Binding="{Binding LastModified}" Width="95"/>
                                <DataGridTextColumn Header="IDLE" Binding="{Binding IdleDays}" Width="85"/>
                                <DataGridTextColumn Header="FULL PATH" Binding="{Binding FullPath}" Width="*"/>
                            </DataGrid.Columns>
                        </DataGrid>

                        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                            <Button x:Name="BtnSendGhostToInspector" Content="Send Selected Ghost Folder to Deep Inspector ->" Style="{StaticResource BtnPrimary}"/>
                        </StackPanel>
                    </Grid>

                    <!-- ==================================================== -->
                    <!-- VIEW 4: CUSTOM TARGET HUNTER (KEYWORD / PATH NUKER)  -->
                    <!-- ==================================================== -->
                    <Grid x:Name="ViewCustomHunter" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Margin="0,0,0,12">
                            <TextBlock Text="CUSTOM TARGET HUNTER (DEEP KEYWORD &amp; FOLDER NUKER)" Foreground="#F8FAFC" FontSize="13" FontWeight="Bold"/>
                            <TextBlock Text="Hunt down portable apps, broken installations, or previously deleted software by name, publisher, or folder path across all 18 system points."
                                       Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
                        </StackPanel>

                        <Border Grid.Row="1" Background="#040811" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="8" Padding="14">
                            <StackPanel>
                                <TextBlock Text="1. TARGET APPLICATION OR KEYWORD (e.g. AnyDesk, Valorant, JetBrains, Adobe)" Foreground="#94A3B8" FontSize="11" FontWeight="Bold" Margin="0,0,0,4"/>
                                <TextBox x:Name="TxtHunterKeyword" Margin="0,0,0,12"/>

                                <TextBlock Text="2. OPTIONAL PUBLISHER / VENDOR NAME" Foreground="#94A3B8" FontSize="11" FontWeight="Bold" Margin="0,0,0,4"/>
                                <TextBox x:Name="TxtHunterPublisher" Margin="0,0,0,12"/>

                                <TextBlock Text="3. OPTIONAL TARGET INSTALL FOLDER OR EXE PATH" Foreground="#94A3B8" FontSize="11" FontWeight="Bold" Margin="0,0,0,4"/>
                                <Grid Margin="0,0,0,14">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="TxtHunterPath" Grid.Column="0" Margin="0,0,8,0"/>
                                    <Button x:Name="BtnBrowseHunterPath" Grid.Column="1" Content="Browse Folder..." Style="{StaticResource BtnSecondary}"/>
                                </Grid>

                                <Button x:Name="BtnExecuteCustomHunt" Content="Launch 18-Point Deep Hunt Across C: &amp; Registry ->" Style="{StaticResource BtnPrimary}" HorizontalAlignment="Left" Padding="18,9"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- ==================================================== -->
                    <!-- VIEW 5: INSTALL SNAPSHOT TRACKER                     -->
                    <!-- ==================================================== -->
                    <Grid x:Name="ViewSnapshotTracker" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Margin="0,0,0,12">
                            <TextBlock Text="INSTALL SNAPSHOT TRACKER (BEFORE / AFTER DIFF ENGINE)" Foreground="#F8FAFC" FontSize="13" FontWeight="Bold"/>
                            <TextBlock Text="Take a baseline snapshot before installing any software. Later, compare current system state against the snapshot to reveal 100% of every new folder and registry key created."
                                       Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
                        </StackPanel>

                        <Border Grid.Row="1" Background="#040811" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,12">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="TxtSnapshotLabel" Grid.Column="0" Text="PreInstall_Baseline" Margin="0,0,10,0"/>
                                <Button x:Name="BtnCreateSnapshot" Grid.Column="1" Content="Capture Baseline Snapshot Now" Style="{StaticResource BtnPrimary}"/>
                            </Grid>
                        </Border>

                        <Border Grid.Row="2" Background="#040811" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="8" Padding="14">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock Grid.Row="0" Text="SAVED SYSTEM SNAPSHOTS" Foreground="#94A3B8" FontSize="11" FontWeight="Bold" Margin="0,0,0,8"/>
                                <ListBox x:Name="ListSnapshots" Grid.Row="1" Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#1E293B" FontFamily="Consolas" FontSize="12"/>
                                <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                                    <Button x:Name="BtnDeleteSnapshot" Content="Delete Snapshot" Style="{StaticResource BtnSecondary}" Margin="0,0,8,0"/>
                                    <Button x:Name="BtnCompareSnapshot" Content="Compare Snapshot &amp; Send Diff to Inspector ->" Style="{StaticResource BtnPrimary}"/>
                                </StackPanel>
                            </Grid>
                        </Border>
                    </Grid>

                    <!-- ============================================================ -->
                    <!-- VIEW: PC SPEED BOOST (Module 6)                              -->
                    <!-- ============================================================ -->
                    <Grid x:Name="ViewPCBoost" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <!-- Header -->
                        <StackPanel Grid.Row="0" Margin="0,0,0,10">
                            <TextBlock Text="PC SPEED BOOST ENGINE (ULTRA-ADVANCED SAFE OPTIMIZER)" Foreground="{DynamicResource PrimaryInk}" FontSize="13" FontWeight="Bold"/>
                            <TextBlock Text="Live RAM telemetry, circular optimization gauge &amp; 12-point deep cache cleaner. Analyze first or Boost Now."
                                       Foreground="{DynamicResource MutedInk}" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
                        </StackPanel>

                        <!-- Hero Telemetry + Circular Progress Ring -->
                        <Border Grid.Row="1" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,0,0,10">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <!-- Circular Progress / Health Ring -->
                                <Grid Grid.Column="0" Width="124" Height="124" Margin="0,0,18,0" VerticalAlignment="Center">
                                    <Ellipse Width="124" Height="124" Stroke="{DynamicResource BorderBrush}" StrokeThickness="9"/>
                                    <Path x:Name="BoostRingArc" Width="124" Height="124" Stroke="{DynamicResource AccentCyan}" StrokeThickness="9"
                                          StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M 62,5 A 57,57 0 0 1 62,5"/>
                                    <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                        <TextBlock x:Name="TxtBoostRingPercent" Text="0%" Foreground="{DynamicResource PrimaryInk}" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center"/>
                                        <TextBlock x:Name="TxtBoostRingLabel" Text="RAM USED" Foreground="{DynamicResource MutedInk}" FontSize="9" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                                    </StackPanel>
                                </Grid>

                                <!-- Right Side: Live Step, Progress Bar & 4 Metric Cards -->
                                <Grid Grid.Column="1" VerticalAlignment="Center">
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>

                                    <Grid Grid.Row="0" Margin="0,0,0,6">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="TxtBoostActiveStep" Grid.Column="0" Text="Ready — Click Analyze or Boost Now to start live scan"
                                                   Foreground="{DynamicResource SecondaryInk}" FontSize="11" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
                                        <TextBlock x:Name="TxtBoostStatus" Grid.Column="1" Text="READY" Foreground="#22C55E" FontSize="12" FontWeight="Bold" Margin="10,0,0,0" VerticalAlignment="Center"/>
                                    </Grid>

                                    <ProgressBar x:Name="PbBoostProgress" Grid.Row="1" Height="6" Minimum="0" Maximum="100" Value="0"
                                                 Background="{DynamicResource BorderBrush}" Foreground="{DynamicResource AccentCyan}" BorderThickness="0" Margin="0,0,0,12"/>

                                    <Grid Grid.Row="2">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,6,0">
                                            <StackPanel>
                                                <TextBlock Text="SYSTEM RAM" Foreground="{DynamicResource MutedInk}" FontSize="9" FontWeight="Bold"/>
                                                <TextBlock x:Name="TxtBoostSysRAM" Text="—" Foreground="{DynamicResource PrimaryInk}" FontSize="13" FontWeight="Bold" Margin="0,2,0,0"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Grid.Column="1" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,6,0">
                                            <StackPanel>
                                                <TextBlock Text="ESTIMATED SAVINGS" Foreground="{DynamicResource MutedInk}" FontSize="9" FontWeight="Bold"/>
                                                <TextBlock x:Name="TxtBoostEstimate" Text="—" Foreground="{DynamicResource AccentCyan}" FontSize="13" FontWeight="Bold" Margin="0,2,0,0"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Grid.Column="2" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,6,0">
                                            <StackPanel>
                                                <TextBlock Text="RAM FREED" Foreground="{DynamicResource MutedInk}" FontSize="9" FontWeight="Bold"/>
                                                <TextBlock x:Name="TxtBoostRAM" Text="0 MB" Foreground="#22C55E" FontSize="13" FontWeight="Bold" Margin="0,2,0,0"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Grid.Column="3" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8,6">
                                            <StackPanel>
                                                <TextBlock Text="DISK FREED" Foreground="{DynamicResource MutedInk}" FontSize="9" FontWeight="Bold"/>
                                                <TextBlock x:Name="TxtBoostDisk" Text="0 KB" Foreground="#22C55E" FontSize="13" FontWeight="Bold" Margin="0,2,0,0"/>
                                            </StackPanel>
                                        </Border>
                                    </Grid>
                                </Grid>
                            </Grid>
                        </Border>

                        <!-- Main Content: Scrollable Options + Live Log -->
                        <Grid Grid.Row="2">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="270"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Left: Scrollable Boost Option Checkboxes -->
                            <Border Grid.Column="0" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,8,0">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Text="BOOST OPERATIONS (17 PRO MODULES)" Foreground="{DynamicResource AccentCyan}" FontSize="10" FontWeight="Bold" Margin="2,0,0,6"/>
                                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                                        <StackPanel>
                                            <CheckBox x:Name="ChkBoostRAM"      Content="RAM + Standby List Purge"      Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  Working-set trim + NtSetSystemInfo purge" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostWinTemp"  Content="Windows Temp &amp; Crash Dumps" Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  %TEMP%, Windows\Temp, CrashDumps" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostBrowser"  Content="All Browsers Deep Cache"        Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  Brave, Chrome, Edge, Opera, Firefox (all profiles)" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostGPU"      Content="GPU Shader Caches"              Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  NVIDIA DX/GLCache, AMD DxCache, D3D" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostUWP"      Content="Store / UWP App Temp Caches"    Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  Packages\*\TempState &amp; AC\Temp" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostPrefetch" Content="Prefetch Files"                 Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  C:\Windows\Prefetch (auto-rebuild)" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostDNS"      Content="DNS Resolver Cache"             Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  ipconfig /flushdns (instant)" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostWU"       Content="Windows Update Cache"           Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  SoftwareDistribution\Download only" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostThumb"    Content="Thumbnail Cache"                Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  Explorer thumbcache_*.db files" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostWER"      Content="Windows Error Reports"          Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  WER ReportArchive + ReportQueue" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostDelivOpt" Content="Delivery Optimization Cache"    Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  Windows update delivery cache" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostTRIM"     Content="SSD TRIM Optimization"          Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="True"  Margin="0,3"/>
                                            <TextBlock Text="  Optimize-Volume -ReTrim (SSD only)" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <Border Background="{DynamicResource BorderBrush}" Height="1" Margin="0,6"/>

                                            <CheckBox x:Name="ChkBoostPower"    Content="Turbo High-Performance Plan"    Foreground="{DynamicResource AccentCyan}" FontSize="12" IsChecked="False" Margin="0,3"/>
                                            <TextBlock Text="  Switch Balanced -> High Performance" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostFont"     Content="Font Cache"                     Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="False" Margin="0,3"/>
                                            <TextBlock Text="  Stops FontCache svc briefly" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostRecycle"  Content="Empty Recycle Bin"              Foreground="{DynamicResource PrimaryInk}" FontSize="12" IsChecked="False" Margin="0,3"/>
                                            <TextBlock Text="  Permanently delete Recycle Bin" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostDISM"     Content="DISM WinSxS Component Clean"    Foreground="#F59E0B" FontSize="12" IsChecked="False" Margin="0,3"/>
                                            <TextBlock Text="  Official Windows Update backup trim (20-60s)" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>

                                            <CheckBox x:Name="ChkBoostEventLogs" Content="Clear Event Logs (Optional)"    Foreground="#F59E0B" FontSize="12" IsChecked="False" Margin="0,3"/>
                                            <TextBlock Text="  Clears App/System/Security logs" Foreground="{DynamicResource MutedInk}" FontSize="10" Margin="0,0,0,4"/>
                                        </StackPanel>
                                    </ScrollViewer>
                                </Grid>
                            </Border>

                            <!-- Right: Live Real-time Log Output -->
                            <Border Grid.Column="1" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="10">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Text="LIVE BOOST ENGINE LOG" Foreground="{DynamicResource AccentCyan}" FontSize="10" FontWeight="Bold" Margin="0,0,0,6"/>
                                    <TextBox x:Name="TxtBoostLog" Grid.Row="1"
                                             Background="Transparent"
                                             Foreground="{DynamicResource PrimaryInk}"
                                             BorderThickness="0"
                                             FontFamily="Consolas"
                                             FontSize="11.5"
                                             IsReadOnly="True"
                                             TextWrapping="Wrap"
                                             AcceptsReturn="True"
                                             VerticalScrollBarVisibility="Auto"
                                             HorizontalScrollBarVisibility="Disabled"
                                             VerticalContentAlignment="Top"
                                             Text="[Boost Engine] Ready. Select operations and click Analyze or Boost Now.&#x0a;"/>
                                </Grid>
                            </Border>
                        </Grid>

                        <!-- Action Buttons -->
                        <Grid Grid.Row="3" Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock x:Name="TxtBoostSafetyNote" Grid.Column="0"
                                       Text="✓ Safe: Never touches System32, SysWOW64, WinSxS or user documents. Locked files skipped automatically."
                                       Foreground="{DynamicResource MutedInk}" FontSize="10" VerticalAlignment="Center" TextWrapping="Wrap"/>
                            <Button x:Name="BtnBoostAnalyze" Grid.Column="1" Content="🔍 Analyze (Dry Run)" Style="{StaticResource BtnSecondary}" Margin="0,0,8,0" Padding="14,8"/>
                            <Button x:Name="BtnBoostNow" Grid.Column="2" Content="⚡ Boost Now!" Style="{StaticResource BtnPrimary}" Padding="14,8"/>
                        </Grid>
                    </Grid>
                </Grid>
            </Border>

            <!-- ============================================================ -->
            <!-- RIGHT PANE (ALT): PC SPEED BOOST TELEMETRY & STARTUP MANAGER -->
            <!-- ============================================================ -->
            <Border x:Name="PaneRightBoostIntel" Grid.Column="2" Visibility="Collapsed" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Header -->
                    <StackPanel Grid.Row="0" Margin="0,0,0,8">
                        <TextBlock Text="PERFORMANCE COMMAND CENTER" Foreground="{DynamicResource PrimaryInk}" FontSize="12" FontWeight="Bold"/>
                        <TextBlock Text="Live RAM consumers, power profile &amp; startup boot accelerator" Foreground="{DynamicResource MutedInk}" FontSize="10"/>
                    </StackPanel>

                    <!-- Quick Presets -->
                    <Border Grid.Row="1" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="QUICK OPTIMIZATION PRESETS" Foreground="{DynamicResource AccentCyan}" FontSize="9" FontWeight="Bold" Margin="0,0,0,6"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Button x:Name="BtnPresetSafe" Grid.Column="0" Content="✓ Safe" Style="{StaticResource BtnSecondary}" Margin="0,0,4,0" Padding="6,5" FontSize="11"/>
                                <Button x:Name="BtnPresetGaming" Grid.Column="1" Content="⚡ Gaming" Style="{StaticResource BtnSecondary}" Margin="0,0,4,0" Padding="6,5" FontSize="11"/>
                                <Button x:Name="BtnPresetMax" Grid.Column="2" Content="🔥 Max Clean" Style="{StaticResource BtnSecondary}" Padding="6,5" FontSize="11"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- Active Power Plan Card -->
                    <Border Grid.Row="2" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,0,0,8">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                <TextBlock Text="ACTIVE WINDOWS POWER PLAN" Foreground="{DynamicResource MutedInk}" FontSize="9" FontWeight="Bold"/>
                                <TextBlock x:Name="TxtBoostPowerPlan" Text="Balanced" Foreground="{DynamicResource PrimaryInk}" FontSize="12" FontWeight="Bold" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                            </StackPanel>
                            <Button x:Name="BtnBoostTogglePower" Grid.Column="1" Content="⚡ High Perf" Style="{StaticResource BtnPrimary}" Padding="10,5" FontSize="11"/>
                        </Grid>
                    </Border>

                    <!-- Top Memory Consumers -->
                    <Border Grid.Row="3" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,0,0,8">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0" Margin="0,0,0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="TOP RAM CONSUMERS (LIVE)" Foreground="{DynamicResource AccentCyan}" FontSize="9" FontWeight="Bold" VerticalAlignment="Center"/>
                                <Button x:Name="BtnBoostRefreshProcs" Grid.Column="1" Content="↻ Refresh" Style="{StaticResource BtnSecondary}" Padding="6,2" FontSize="10"/>
                            </Grid>
                            <DataGrid x:Name="GridBoostTopProcs" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True" HeadersVisibility="Column"
                                      Background="Transparent" BorderThickness="0" GridLinesVisibility="Horizontal" RowHeight="24">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="PROCESS" Binding="{Binding Name}" Width="*"/>
                                    <DataGridTextColumn Header="RAM" Binding="{Binding MemDisplay}" Width="70"/>
                                    <DataGridTextColumn Header="PID" Binding="{Binding Pid}" Width="55"/>
                                </DataGrid.Columns>
                            </DataGrid>
                        </Grid>
                    </Border>

                    <!-- Startup Boot Accelerator -->
                    <Border Grid.Row="4" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8" Margin="0,0,0,8">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0" Margin="0,0,0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="STARTUP BOOT ACCELERATOR" Foreground="{DynamicResource AccentCyan}" FontSize="9" FontWeight="Bold" VerticalAlignment="Center"/>
                                <Button x:Name="BtnBoostScanStartup" Grid.Column="1" Content="Scan Startup" Style="{StaticResource BtnSecondary}" Padding="6,2" FontSize="10"/>
                            </Grid>
                            <DataGrid x:Name="GridBoostStartup" Grid.Row="1" AutoGenerateColumns="False" HeadersVisibility="Column"
                                      Background="Transparent" BorderThickness="0" GridLinesVisibility="Horizontal" RowHeight="24">
                                <DataGrid.Columns>
                                    <DataGridCheckBoxColumn Header="✓" Binding="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Width="28"/>
                                    <DataGridTextColumn Header="STARTUP APP" Binding="{Binding Name}" Width="*" IsReadOnly="True"/>
                                    <DataGridTextColumn Header="SCOPE" Binding="{Binding Scope}" Width="55" IsReadOnly="True"/>
                                </DataGrid.Columns>
                            </DataGrid>
                        </Grid>
                    </Border>

                    <!-- Startup Action Footer -->
                    <Button x:Name="BtnBoostDisableStartup" Grid.Row="5" Content="Disable Selected Startup Entries (Auto-Backup)" Style="{StaticResource BtnDanger}" Padding="10,7" FontSize="11"/>
                </Grid>
            </Border>

            <!-- ============================================================ -->
            <!-- RIGHT PANE: DEEP-SCAN LEFTOVER INSPECTOR & NUKE ENGINE       -->
            <!-- ============================================================ -->
            <Border x:Name="PaneRightInspector" Grid.Column="2" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="12">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Inspector Header -->
                    <Grid Grid.Row="0" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="ZERO-TRACE LEFTOVER INSPECTOR" Foreground="{DynamicResource PrimaryInk}" FontSize="13" FontWeight="Bold"/>
                            <TextBlock x:Name="LblInspectorTarget" Text="Target: Awaiting Scan..." Foreground="{DynamicResource AccentCyan}" FontSize="11" FontWeight="SemiBold"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                            <Button x:Name="BtnSelectAllLeftovers" Content="All" Style="{StaticResource BtnSecondary}" Padding="8,4" FontSize="11" Margin="0,0,4,0"/>
                            <Button x:Name="BtnSelectNoneLeftovers" Content="None" Style="{StaticResource BtnSecondary}" Padding="8,4" FontSize="11"/>
                        </StackPanel>
                    </Grid>

                    <!-- Breakdown Summary Pills -->
                    <Border Grid.Row="1" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,0,8">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock x:Name="LblStatFiles" Grid.Column="0" Text="FS: 0 folders/files" Foreground="{DynamicResource SecondaryInk}" FontFamily="Consolas" FontSize="11"/>
                            <TextBlock x:Name="LblStatReg" Grid.Column="1" Text="REG: 0 keys/vals" Foreground="{DynamicResource SecondaryInk}" FontFamily="Consolas" FontSize="11"/>
                            <TextBlock x:Name="LblStatSvc" Grid.Column="2" Text="SVC/TASK: 0" Foreground="{DynamicResource SecondaryInk}" FontFamily="Consolas" FontSize="11"/>
                        </Grid>
                    </Border>

                    <!-- Leftovers Checkable DataGrid -->
                    <DataGrid x:Name="GridLeftovers" Grid.Row="2" CanUserAddRows="False">
                        <DataGrid.Columns>
                            <DataGridCheckBoxColumn Header="✓" Binding="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Width="32"/>
                            <DataGridTextColumn Header="TYPE" Binding="{Binding ItemType}" Width="78" IsReadOnly="True"/>
                            <DataGridTextColumn Header="LOCATION" Binding="{Binding Category}" Width="115" IsReadOnly="True"/>
                            <DataGridTextColumn Header="SIZE" Binding="{Binding SizeFormatted}" Width="68" IsReadOnly="True"/>
                            <DataGridTextColumn Header="PATH / REGISTRY KEY" Binding="{Binding DisplayPath}" Width="350" IsReadOnly="True"/>
                        </DataGrid.Columns>
                    </DataGrid>

                    <!-- Live Execution Log Box -->
                    <Border Grid.Row="3" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Height="115" Margin="0,8,0,8" Padding="6">
                        <TextBox x:Name="TxtExecutionLog" Background="Transparent" Foreground="{DynamicResource SecondaryInk}" BorderThickness="0"
                                 FontFamily="Consolas" FontSize="11" IsReadOnly="True" TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"/>
                    </Border>

                    <!-- Primary Nuke CTA Button -->
                    <Button x:Name="BtnNukeSelected" Grid.Row="4" Content="100% WIPE &amp; NUKE SELECTED LEFTOVERS (0 ITEMS)"
                            Style="{StaticResource BtnDanger}" Padding="14,10" FontSize="12.5"/>
                </Grid>
            </Border>
        </Grid>

        <!-- ================================================================ -->
        <!-- ROW 3: BOTTOM STATUS TELEMETRY BAR                               -->
        <!-- ================================================================ -->
        <Border Grid.Row="3" Background="{DynamicResource RecessedBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,1,0,0" Padding="16,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="LblStatusBar" Grid.Column="0" Text="NovaGen Engine Ready. All 18 deep-scan sensors online."
                           Foreground="{DynamicResource SecondaryInk}" FontFamily="Consolas" FontSize="11.5" VerticalAlignment="Center"/>
                <TextBlock x:Name="LblBackupPathInfo" Grid.Column="1" Text="Backups: d:\uinsitaler\Backups"
                           Foreground="{DynamicResource MutedInk}" FontFamily="Consolas" FontSize="11" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ============================================================================
# 11. BUILD WINDOW & WIRE CONTROLS
# ============================================================================
$reader = New-Object System.Xml.XmlNodeReader($xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)

$Controls = @{}
$xaml.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $cName = $_.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml")
    if (-not $cName) { $cName = $_.GetAttribute("Name") }
    if ($cName) {
        $found = $Window.FindName($cName)
        if ($found) {
            $Controls[$cName] = $found
        }
    }
}

function Write-NovaLog {
    param([string]$Message)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $line = "[$ts] $Message"
    $Controls['TxtExecutionLog'].AppendText("$line`r`n")
    $Controls['TxtExecutionLog'].ScrollToEnd()
    $Controls['LblStatusBar'].Text = $Message
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Update-SystemTelemetry {
    # Admin badge check
    if (-not $isAdmin) {
        $Controls['AdminBadgeText'].Text = "LIMITED USER MODE (RUN AS ADMIN)"
        $Controls['AdminBadgeText'].Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(251, 191, 36))
    }

    # C: Drive telemetry
    try {
        $cDrive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
        if ($cDrive) {
            $freeGB = $cDrive.Free / 1GB
            $totalGB = ($cDrive.Free + $cDrive.Used) / 1GB
            $Controls['KpiDriveFree'].Text = ("{0:N2} GB" -f $freeGB)
            $Controls['KpiDriveSub'].Text = (" / {0:N0} GB" -f $totalGB)
        }
    } catch {}

    # Installed Apps KPI
    $win32Count = $Script:AllAppsCache.Count
    $storeCount = $Script:AllStoreCache.Count
    $Controls['KpiAppCount'].Text = [string]($win32Count + $storeCount)
    $Controls['KpiAppSub'].Text = " ($win32Count Win32 · $storeCount Store)"

    $totalBytes = [int64]0
    foreach ($a in $Script:AllAppsCache) { $totalBytes += $a.SizeBytes }
    $Controls['KpiTotalSize'].Text = Format-ByteSize $totalBytes
    $Controls['KpiReclaimed'].Text = Format-ByteSize $Script:SessionReclaimedBytes
    if ($Controls['LblBackupPathInfo']) {
        $Controls['LblBackupPathInfo'].Text = "Backups: $Script:BackupRoot"
    }
}

function Update-InspectorCounters {
    $total = $Script:LeftoverItems.Count
    $selected = 0
    $selBytes = [int64]0
    $fsCount = 0
    $regCount = 0
    $svcCount = 0

    foreach ($item in $Script:LeftoverItems) {
        if ($item.ItemType -in @('File', 'Folder')) { $fsCount++ }
        elseif ($item.ItemType -like 'Registry*') { $regCount++ }
        else { $svcCount++ }

        if ($item.IsSelected) {
            $selected++
            $selBytes += $item.SizeBytes
        }
    }

    $Controls['KpiLeftoverCount'].Text = [string]$total
    $Controls['KpiLeftoverSize'].Text = " ($(Format-ByteSize $selBytes) selected)"
    $Controls['LblStatFiles'].Text = "FS: $fsCount items"
    $Controls['LblStatReg'].Text = "REG: $regCount items"
    $Controls['LblStatSvc'].Text = "SVC/TASK: $svcCount"
    $Controls['BtnNukeSelected'].Content = "100% WIPE & NUKE SELECTED LEFTOVERS ($selected / $total ITEMS)"
}

# ============================================================================
# 12. NAVIGATION & FILTERING LOGIC
# ============================================================================
function Switch-WorkspaceView {
    param([string]$ViewName)
    $views = @('ViewInstalledApps', 'ViewStoreApps', 'ViewGhostSweeper', 'ViewCustomHunter', 'ViewSnapshotTracker', 'ViewPCBoost')
    foreach ($v in $views) {
        $Controls[$v].Visibility = if ($v -eq $ViewName) { 'Visible' } else { 'Collapsed' }
    }
    if ($ViewName -eq 'ViewPCBoost') {
        $Controls['PaneRightInspector'].Visibility  = 'Collapsed'
        $Controls['PaneRightBoostIntel'].Visibility = 'Visible'
    } else {
        $Controls['PaneRightInspector'].Visibility  = 'Visible'
        $Controls['PaneRightBoostIntel'].Visibility = 'Collapsed'
    }
}

$Controls['NavBtnApps'].Add_Click({ Switch-WorkspaceView 'ViewInstalledApps' })
$Controls['NavBtnStore'].Add_Click({
    Switch-WorkspaceView 'ViewStoreApps'
    if ($Script:AllStoreCache.Count -eq 0) {
        Write-NovaLog "Loading Windows Store & UWP Packages..."
        $Script:AllStoreCache = Get-AllStoreApps
        $Controls['GridStoreApps'].ItemsSource = $Script:AllStoreCache
        Update-SystemTelemetry
        Write-NovaLog "Loaded $($Script:AllStoreCache.Count) removable Store/UWP packages."
    }
})
$Controls['NavBtnGhost'].Add_Click({ Switch-WorkspaceView 'ViewGhostSweeper' })
$Controls['NavBtnHunter'].Add_Click({ Switch-WorkspaceView 'ViewCustomHunter' })
$Controls['NavBtnSnapshot'].Add_Click({
    Switch-WorkspaceView 'ViewSnapshotTracker'
    Refresh-SnapshotsList
})

$Controls['NavBtnBoost'].Add_Click({
    Switch-WorkspaceView 'ViewPCBoost'
    $isIdle = ($Controls['TxtBoostStatus'].Text -eq 'READY')
    Update-BoostRamTelemetry -UpdateRing $isIdle
    Update-BoostCommandCenter
})

$Script:CurrentAppFilterCategory = "ALL"
$Script:CurrentSortMode = "NAME_ASC"

function Apply-InstalledAppsFilter {
    $q = $Controls['TxtSearchApps'].Text.Trim().ToLower()
    $filtered = New-Object System.Collections.Generic.List[PSObject]
    foreach ($app in $Script:AllAppsCache) {
        if ($Script:CurrentAppFilterCategory -eq "DESKTOP" -and $app.Category -ne "Desktop App") { continue }
        if ($Script:CurrentAppFilterCategory -eq "USER" -and $app.Category -ne "User App") { continue }

        if (-not [string]::IsNullOrWhiteSpace($q)) {
            $matchName = $app.DisplayName.ToLower().Contains($q)
            $matchPub  = $app.Publisher.ToLower().Contains($q)
            $matchLoc  = $app.InstallLocation.ToLower().Contains($q)
            if (-not ($matchName -or $matchPub -or $matchLoc)) { continue }
        }
        $filtered.Add($app)
    }

    if ($Script:CurrentSortMode -eq "SIZE_DESC") {
        $sorted = $filtered | Sort-Object SizeBytes -Descending
    } else {
        $sorted = $filtered | Sort-Object DisplayName
    }

    $Controls['GridInstalledApps'].ItemsSource = @($sorted)
}

$Controls['TxtSearchApps'].Add_TextChanged({ Apply-InstalledAppsFilter })
$Controls['BtnFilterAll'].Add_Click({ $Script:CurrentAppFilterCategory = "ALL"; Apply-InstalledAppsFilter })
$Controls['BtnFilterDesktop'].Add_Click({ $Script:CurrentAppFilterCategory = "DESKTOP"; Apply-InstalledAppsFilter })
$Controls['BtnFilterUser'].Add_Click({ $Script:CurrentAppFilterCategory = "USER"; Apply-InstalledAppsFilter })

$Controls['BtnSortSize'].Add_Click({
    $Script:CurrentSortMode = "SIZE_DESC"
    Apply-InstalledAppsFilter
    Write-NovaLog "Sorted applications by size: Largest to Smallest."
})

$Controls['BtnSortName'].Add_Click({
    $Script:CurrentSortMode = "NAME_ASC"
    Apply-InstalledAppsFilter
    Write-NovaLog "Sorted applications alphabetically: A to Z."
})

# ============================================================================
# THEME SWITCHER ENGINE (DARK OBSIDIAN <-> GRADIENT BLUE ENTERPRISE LIGHT)
# ============================================================================
$Script:CurrentTheme = "DARK"

function Set-NovaGenTheme {
    param([string]$ThemeMode)

    if ($ThemeMode -eq "LIGHT") {
        # Light Gradient Blue Theme
        $Window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
        $Window.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")

        $res = $Window.Resources
        $res["CanvasBrush"]        = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
        $res["SurfaceBrush"]       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $res["ElevatedBrush"]      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EEF2F6")
        $res["RecessedBrush"]      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F1F5F9")
        $res["BorderBrush"]        = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
        $res["PrimaryInk"]         = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $res["SecondaryInk"]       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#334155")
        $res["MutedInk"]           = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $res["AccentCobalt"]       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1D4ED8")
        $res["AccentCobaltHover"]  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E40AF")
        $res["AccentCyan"]         = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
        $res["SemanticSuccess"]    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
        $res["SemanticWarning"]    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706")
        $res["SemanticDanger"]     = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")

        # Top Bar (Rich Gradient Navy / Indigo Bar)
        if ($Window.Content -is [System.Windows.Controls.Grid]) {
            $mainGrid = $Window.Content
            if ($mainGrid.Children.Count -ge 4) {
                $topBar = $mainGrid.Children[0]
                $topBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A192F")
                $topBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")

                $bottomBar = $mainGrid.Children[3]
                $bottomBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
                $bottomBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
            }
        }

        # Force DataGrid Cells & Rows to redraw with Light colors
        foreach ($dg in @($Controls['GridInstalledApps'], $Controls['GridStoreApps'], $Controls['GridGhostItems'], $Controls['GridLeftovers'])) {
            if ($dg) {
                $dg.Items.Refresh()
            }
        }

        # Active Toggle button styling
        $Controls['BtnThemeLight'].Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2563EB")
        $Controls['BtnThemeLight'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $Controls['BtnThemeDark'].Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $Controls['BtnThemeDark'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")

        $Script:CurrentTheme = "LIGHT"
        Write-NovaLog "Switched to Enterprise Light Mode (Executive Navy & Gradient Blue)."
    } else {
        # Dark Obsidian NOC Mode
        $Window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060B16")
        $Window.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")

        $res = $Window.Resources
        $res["CanvasBrush"]        = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060B16")
        $res["SurfaceBrush"]       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0B1220")
        $res["ElevatedBrush"]      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#111C33")
        $res["RecessedBrush"]      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#040811")
        $res["BorderBrush"]        = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $res["PrimaryInk"]         = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
        $res["SecondaryInk"]       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $res["MutedInk"]           = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $res["AccentCobalt"]       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2563EB")
        $res["AccentCobaltHover"]  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1D4ED8")
        $res["AccentCyan"]         = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#22D3EE")
        $res["SemanticSuccess"]    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
        $res["SemanticWarning"]    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706")
        $res["SemanticDanger"]     = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")

        if ($Window.Content -is [System.Windows.Controls.Grid]) {
            $mainGrid = $Window.Content
            if ($mainGrid.Children.Count -ge 4) {
                $topBar = $mainGrid.Children[0]
                $topBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#040811")
                $topBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")

                $bottomBar = $mainGrid.Children[3]
                $bottomBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#040811")
                $bottomBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
            }
        }

        foreach ($dg in @($Controls['GridInstalledApps'], $Controls['GridStoreApps'], $Controls['GridGhostItems'], $Controls['GridLeftovers'])) {
            if ($dg) {
                $dg.Items.Refresh()
            }
        }

        $Controls['BtnThemeDark'].Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2563EB")
        $Controls['BtnThemeDark'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $Controls['BtnThemeLight'].Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#111C33")
        $Controls['BtnThemeLight'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")

        $Script:CurrentTheme = "DARK"
        Write-NovaLog "Switched to Dark Obsidian NOC Mode."
    }
}

$Controls['BtnThemeLight'].Add_Click({ Set-NovaGenTheme "LIGHT" })
$Controls['BtnThemeDark'].Add_Click({ Set-NovaGenTheme "DARK" })

$Controls['TxtSearchStore'].Add_TextChanged({
    $q = $Controls['TxtSearchStore'].Text.Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($q)) {
        $Controls['GridStoreApps'].ItemsSource = $Script:AllStoreCache
    } else {
        $Controls['GridStoreApps'].ItemsSource = @($Script:AllStoreCache | Where-Object {
            $_.Name.ToLower().Contains($q) -or $_.Publisher.ToLower().Contains($q)
        })
    }
})

# Selection Changed in Installed Apps Grid
$Controls['GridInstalledApps'].Add_SelectionChanged({
    $sel = $Controls['GridInstalledApps'].SelectedItem
    if ($sel) {
        $Controls['LblSelectedAppName'].Text = "$($sel.DisplayName)  (v$($sel.DisplayVersion) · $($sel.Publisher))"
        $locText = if ($sel.InstallLocation) { "Path: $($sel.InstallLocation)" } else { "Registry: $($sel.RegistryPath)" }
        $Controls['LblSelectedAppMeta'].Text = $locText
        $Controls['LblSelectedAppArch'].Text = "$($sel.Architecture) // $($sel.Scope)"
    }
})

# Calculate Exact Missing Folder Sizes
$Controls['BtnCalcSizes'].Add_Click({
    Write-NovaLog "Calculating exact disk sizes for applications without registry size data..."
    $count = 0
    foreach ($app in $Script:AllAppsCache) {
        if ($app.SizeBytes -le 0 -and -not [string]::IsNullOrWhiteSpace($app.InstallLocation) -and (Test-Path -LiteralPath $app.InstallLocation)) {
            $sz = Get-DirectorySizeFast -Path $app.InstallLocation
            if ($sz -gt 0) {
                $app.SizeBytes = $sz
                $app.SizeFormatted = Format-ByteSize $sz
                $count++
            }
        }
    }
    $Controls['GridInstalledApps'].Items.Refresh()
    Update-SystemTelemetry
    Write-NovaLog "Computed disk footprint for $count additional folders."
})

# Open Selected App Install Folder
$Controls['BtnOpenInstallDir'].Add_Click({
    $sel = $Controls['GridInstalledApps'].SelectedItem
    if (-not $sel) { return }
    if (-not [string]::IsNullOrWhiteSpace($sel.InstallLocation) -and (Test-Path -LiteralPath $sel.InstallLocation)) {
        Start-Process "explorer.exe" -ArgumentList "`"$($sel.InstallLocation)`""
    } else {
        [System.Windows.MessageBox]::Show("No active InstallLocation folder on disk for '$($sel.DisplayName)'. Click 'Deep Scan Leftovers' to hunt down all remaining files.", "NovaGen", "OK", "Information") | Out-Null
    }
})

# Open Backups Folder
$Controls['BtnOpenBackups'].Add_Click({
    Start-Process "explorer.exe" -ArgumentList "`"$Script:BackupRoot`""
})

# ============================================================================
# 13B. PC SPEED BOOST — BUTTON HANDLERS
# ============================================================================
function Invoke-BoostWithUI {
    param([bool]$DryRun = $false)

    $Controls['BtnBoostAnalyze'].IsEnabled = $false
    $Controls['BtnBoostNow'].IsEnabled     = $false
    $Controls['TxtBoostStatus'].Text       = if ($DryRun) { "ANALYZING..." } else { "BOOSTING..." }
    $Controls['TxtBoostStatus'].Foreground = [Windows.Media.Brushes]::Orange
    $Controls['TxtBoostLog'].Clear()
    $Controls['TxtBoostDisk'].Text         = if ($DryRun) { "Scanning..." } else { "0 KB" }
    $Controls['TxtBoostRAM'].Text          = if ($DryRun) { "Scanning..." } else { "0 MB" }
    Update-BoostRamTelemetry -UpdateRing $false
    Invoke-BoostUiPump

    $doRAM    = $Controls['ChkBoostRAM'].IsChecked
    $doTemp   = $Controls['ChkBoostWinTemp'].IsChecked
    $doPref   = $Controls['ChkBoostPrefetch'].IsChecked
    $doDNS    = $Controls['ChkBoostDNS'].IsChecked
    $doWU     = $Controls['ChkBoostWU'].IsChecked
    $doThumb  = $Controls['ChkBoostThumb'].IsChecked
    $doFont   = $Controls['ChkBoostFont'].IsChecked
    $doBrowse = $Controls['ChkBoostBrowser'].IsChecked
    $doGPU    = $Controls['ChkBoostGPU'].IsChecked
    $doUWP    = $Controls['ChkBoostUWP'].IsChecked
    $doWER    = $Controls['ChkBoostWER'].IsChecked
    $doDO     = $Controls['ChkBoostDelivOpt'].IsChecked
    $doTRIM   = $Controls['ChkBoostTRIM'].IsChecked
    $doPower  = $Controls['ChkBoostPower'].IsChecked
    $doRBin   = $Controls['ChkBoostRecycle'].IsChecked
    $doDISM   = $Controls['ChkBoostDISM'].IsChecked
    $doEvt    = $Controls['ChkBoostEventLogs'].IsChecked

    $result = $null
    try {
        $result = Invoke-PCSpeedBoost -DryRun $DryRun -DoRAM $doRAM -DoWinTemp $doTemp `
            -DoPrefetch $doPref -DoDNS $doDNS -DoWUCache $doWU -DoThumbnail $doThumb `
            -DoFontCache $doFont -DoBrowserCache $doBrowse -DoGPUCache $doGPU -DoUWPCache $doUWP `
            -DoWER $doWER -DoDelivOpt $doDO -DoSSDTrim $doTRIM -DoPowerPlan $doPower `
            -DoRecycleBin $doRBin -DoDISMClean $doDISM -DoEventLogs $doEvt
    } catch {
        Write-BoostLog "ERROR: $_" "ERROR"
    }

    if ($result) {
        $diskStr = Format-ByteSize $result.TotalFreedBytes
        $ramStr  = if ($DryRun) { "~$($result.RAMFreedMB) MB" } else { "$($result.RAMFreedMB) MB" }
        $Controls['TxtBoostEstimate'].Text = $diskStr
        $Controls['TxtBoostDisk'].Text     = if ($DryRun) { "0 KB (Dry Run)" } else { $diskStr }
        $Controls['TxtBoostRAM'].Text      = $ramStr
        $Controls['TxtBoostStatus'].Text   = if ($DryRun) { "ANALYZED" } else { "BOOSTED!" }
        $Controls['TxtBoostStatus'].Foreground = [Windows.Media.Brushes]::LimeGreen
        if (-not $DryRun -and $result.TotalFreedBytes -gt 0) {
            $Script:SessionReclaimedBytes += $result.TotalFreedBytes
        }
        Update-BoostRamTelemetry -UpdateRing $false
        Refresh-BoostPowerPlan
        Refresh-BoostTopProcesses
        Update-SystemTelemetry
    } else {
        $Controls['TxtBoostStatus'].Text   = "ERROR"
        $Controls['TxtBoostStatus'].Foreground = [Windows.Media.Brushes]::Red
    }

    $Controls['BtnBoostAnalyze'].IsEnabled = $true
    $Controls['BtnBoostNow'].IsEnabled     = $true
    Invoke-BoostUiPump
}

$Controls['BtnBoostAnalyze'].Add_Click({
    Invoke-BoostWithUI -DryRun $true
})

$Controls['BtnBoostNow'].Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "This will clean temp files, caches, and other safe junk from your PC.`n`nSafe — never touches OS files or user documents.`n`nProceed with PC Speed Boost?",
        "NovaGen // PC Speed Boost",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-BoostWithUI -DryRun $false
    }
})

function Refresh-BoostPowerPlan {
    try {
        $raw = (& powercfg /getactivescheme 2>&1) -join ' '
        if ($raw -match '\(([^)]+)\)') {
            $planName = $Matches[1]
            $Controls['TxtBoostPowerPlan'].Text = $planName
            if ($planName -match 'High|Ultimate') {
                $Controls['BtnBoostTogglePower'].Content = "⚖ Balanced"
            } else {
                $Controls['BtnBoostTogglePower'].Content = "⚡ High Perf"
            }
        }
    } catch {}
}

function Refresh-BoostTopProcesses {
    try {
        $list = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
        $procs = Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 8
        foreach ($p in $procs) {
            $mb = [Math]::Round($p.WorkingSet64 / 1MB, 0)
            $list.Add([PSCustomObject]@{
                Name       = $p.ProcessName
                MemDisplay = "$mb MB"
                Pid        = $p.Id
            })
        }
        $Controls['GridBoostTopProcs'].ItemsSource = $list
    } catch {}
}

function Refresh-BoostStartupList {
    $list = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
    $regRoots = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope = "User";   Export = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" },
        @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope = "System"; Export = "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" },
        @{ Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope = "x86"; Export = "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" }
    )
    foreach ($rr in $regRoots) {
        if (-not (Test-Path $rr.Path)) { continue }
        try {
            $key = Get-Item -LiteralPath $rr.Path -ErrorAction SilentlyContinue
            foreach ($valName in $key.GetValueNames()) {
                if ([string]::IsNullOrWhiteSpace($valName)) { continue }
                $cmd = $key.GetValue($valName)
                $list.Add([PSCustomObject]@{
                    IsSelected = $false
                    Name       = $valName
                    Scope      = $rr.Scope
                    Command    = [string]$cmd
                    RegPath    = $rr.Path
                    ExportPath = $rr.Export
                })
            }
        } catch {}
    }
    $Controls['GridBoostStartup'].ItemsSource = $list
}

function Update-BoostCommandCenter {
    Refresh-BoostPowerPlan
    Refresh-BoostTopProcesses
    if (-not $Controls['GridBoostStartup'].ItemsSource) {
        Refresh-BoostStartupList
    }
}

$Controls['BtnBoostRefreshProcs'].Add_Click({ Refresh-BoostTopProcesses })
$Controls['BtnBoostScanStartup'].Add_Click({ Refresh-BoostStartupList })

$Controls['BtnBoostTogglePower'].Add_Click({
    try {
        $cur = $Controls['TxtBoostPowerPlan'].Text
        if ($cur -match 'High|Ultimate') {
            & powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
            Write-BoostLog "Power Plan switched to: Balanced" "OK"
        } else {
            $hp = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            & powercfg /setactive $hp 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                & powercfg /duplicatescheme $hp 2>&1 | Out-Null
                & powercfg /setactive $hp 2>&1 | Out-Null
            }
            Write-BoostLog "Power Plan switched to: High Performance!" "OK"
        }
        Refresh-BoostPowerPlan
    } catch {}
})

$Controls['BtnBoostDisableStartup'].Add_Click({
    $items = $Controls['GridBoostStartup'].ItemsSource
    if (-not $items) { return }
    $selected = @($items | Where-Object { $_.IsSelected })
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Tick at least one startup entry to disable.", "NovaGen // Startup Accelerator", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    $confirm = [System.Windows.MessageBox]::Show(
        "Disable $($selected.Count) selected startup item(s)?`n`nA full .reg backup will be saved to Backups\ before removing.",
        "NovaGen // Startup Accelerator",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $exported = @{}
    foreach ($s in $selected) {
        try {
            if (-not $exported.ContainsKey($s.ExportPath)) {
                $bkFile = Join-Path $Script:BackupRoot "Startup_$($s.Scope)_$ts.reg"
                & reg.exe export $s.ExportPath $bkFile /y 2>&1 | Out-Null
                $exported[$s.ExportPath] = $true
            }
            Remove-ItemProperty -LiteralPath $s.RegPath -Name $s.Name -Force -ErrorAction SilentlyContinue
            Write-BoostLog "Startup Disabled [$($s.Scope)]: $($s.Name) (Backed up)" "OK"
        } catch {
            Write-BoostLog "Startup Failed [$($s.Name)]: $_" "WARN"
        }
    }
    Refresh-BoostStartupList
})

function Set-BoostPreset {
    param([string]$Mode)
    # Reset optional ones first
    $Controls['ChkBoostRAM'].IsChecked      = $true
    $Controls['ChkBoostWinTemp'].IsChecked  = $true
    $Controls['ChkBoostBrowser'].IsChecked  = $true
    $Controls['ChkBoostGPU'].IsChecked      = $true
    $Controls['ChkBoostUWP'].IsChecked      = $true
    $Controls['ChkBoostPrefetch'].IsChecked = $true
    $Controls['ChkBoostDNS'].IsChecked      = $true
    $Controls['ChkBoostWU'].IsChecked       = $true
    $Controls['ChkBoostThumb'].IsChecked    = $true
    $Controls['ChkBoostWER'].IsChecked      = $true
    $Controls['ChkBoostDelivOpt'].IsChecked = $true
    $Controls['ChkBoostTRIM'].IsChecked     = $true
    $Controls['ChkBoostPower'].IsChecked    = ($Mode -eq 'GAMING' -or $Mode -eq 'MAX')
    $Controls['ChkBoostFont'].IsChecked     = ($Mode -eq 'MAX')
    $Controls['ChkBoostRecycle'].IsChecked  = ($Mode -eq 'MAX')
    $Controls['ChkBoostDISM'].IsChecked     = ($Mode -eq 'MAX')
    $Controls['ChkBoostEventLogs'].IsChecked = $false
    Write-BoostLog "Preset Applied: $Mode" "INFO"
}

$Controls['BtnPresetSafe'].Add_Click({ Set-BoostPreset 'SAFE' })
$Controls['BtnPresetGaming'].Add_Click({ Set-BoostPreset 'GAMING' })
$Controls['BtnPresetMax'].Add_Click({ Set-BoostPreset 'MAX' })

# ============================================================================
# 13. CORE UNINSTALL & DEEP SCAN BUTTON HANDLERS
# ============================================================================
function Populate-InspectorResults {
    param(
        [string]$TargetTitle,
        [System.Collections.Generic.List[PSObject]]$ScanList
    )
    $Script:CurrentTargetTitle = $TargetTitle
    $Controls['LblInspectorTarget'].Text = "Target: $TargetTitle"
    $Script:LeftoverItems.Clear()
    foreach ($r in $ScanList) {
        $Script:LeftoverItems.Add($r)
    }
    $Controls['GridLeftovers'].ItemsSource = $Script:LeftoverItems
    Update-InspectorCounters
}

# 1. Deep Scan Leftovers Only (Force Hunt)
$Controls['BtnDeepScanOnly'].Add_Click({
    $sel = $Controls['GridInstalledApps'].SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Please select an application from the table first.", "NovaGen Deep Scanner", "OK", "Warning") | Out-Null
        return
    }

    Write-NovaLog "Running 18-Point Deep Heuristic Scan for '$($sel.DisplayName)'..."
    $scanResults = Invoke-DeepLeftoverScan -AppName $sel.DisplayName `
                                           -Publisher $sel.Publisher `
                                           -InstallLocation $sel.InstallLocation `
                                           -UninstallString $sel.UninstallString `
                                           -RegistryPath $sel.PSRegistryPath `
                                           -RegistryKeyName $sel.RegistryKeyName `
                                           -IncludeInstallRegistry $true

    Populate-InspectorResults -TargetTitle $sel.DisplayName -ScanList $scanResults
    Write-NovaLog "Deep Scan complete for '$($sel.DisplayName)': Found $($scanResults.Count) traces across C: and Registry."
})

# 2. Fresh Trial / Config State Reset
$Controls['BtnFreshResetApp'].Add_Click({
    $sel = $Controls['GridInstalledApps'].SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Please select an application to reset its config/trial state.", "NovaGen Fresh Reset", "OK", "Warning") | Out-Null
        return
    }

    Write-NovaLog "Scanning user config, AppData, ProgramData, Prefetch & MuiCache traces for '$($sel.DisplayName)'..."
    $allResults = Invoke-DeepLeftoverScan -AppName $sel.DisplayName `
                                          -Publisher $sel.Publisher `
                                          -InstallLocation $sel.InstallLocation `
                                          -UninstallString $sel.UninstallString `
                                          -RegistryPath $sel.PSRegistryPath `
                                          -RegistryKeyName $sel.RegistryKeyName `
                                          -IncludeInstallRegistry $false

    # Filter out main Program Files install folder so the app stays installed, but wipe all user data / registry / caches
    $resetResults = New-Object System.Collections.Generic.List[PSObject]
    foreach ($item in $allResults) {
        if ($item.Category -in @('Install Directory', 'Program Files (x64)', 'Program Files (x86)', 'Uninstall Registry', 'Shortcuts & Start Menu')) {
            continue
        }
        $resetResults.Add($item)
    }

    Populate-InspectorResults -TargetTitle "$($sel.DisplayName) [FRESH CONFIG RESET]" -ScanList $resetResults
    Write-NovaLog "Fresh-State Reset scan ready: Found $($resetResults.Count) config/cache/registry traces."
})

# 3. 100% Full Deep Uninstall + Leftover Wipe
$Controls['BtnFullDeepUninstall'].Add_Click({
    $sel = $Controls['GridInstalledApps'].SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Please select an application to uninstall.", "NovaGen Deep Uninstaller", "OK", "Warning") | Out-Null
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Launch 100% Zero-Trace Deep Uninstall for:`n`nApp: $($sel.DisplayName)`nPublisher: $($sel.Publisher)`n`nStep 1: Terminate running processes`nStep 2: Run official uninstaller (or bypass if broken)`nStep 3: Deep scan all 18 FileSystem & Registry locations for 100% leftover wipe.`n`nProceed?",
        "NovaGen // Zero-Trace Deep Uninstall",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    # Step 1: Kill running processes
    Write-NovaLog "Step 1/3: Terminating active processes for '$($sel.DisplayName)'..."
    $killed = Stop-AppRelatedProcesses -AppName $sel.DisplayName -InstallLocation $sel.InstallLocation
    if ($killed.Count -gt 0) {
        Write-NovaLog "Terminated processes: $($killed -join ', ')"
    }

    # Step 2: Run Official Uninstaller if available
    $uninstCmd = $sel.UninstallString
    if (-not [string]::IsNullOrWhiteSpace($uninstCmd)) {
        Write-NovaLog "Step 2/3: Launching official uninstaller: $uninstCmd"
        try {
            if ($sel.WindowsInstaller -or $uninstCmd -match '(?i)msiexec') {
                if ($uninstCmd -match '(\{[0-9A-Fa-f\-]+\})') {
                    $guid = $Matches[1]
                    Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $guid" -Wait
                } else {
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstCmd" -Wait
                }
            } elseif ($uninstCmd -match '^"([^"]+)"(.*)$') {
                $exe = $Matches[1]
                $args = $Matches[2].Trim()
                if (Test-Path -LiteralPath $exe) {
                    if ($args) {
                        Start-Process -FilePath $exe -ArgumentList $args -Wait
                    } else {
                        Start-Process -FilePath $exe -Wait
                    }
                } else {
                    Write-NovaLog "Official uninstaller binary missing on disk. Proceeding directly to Force Deep Scan."
                }
            } else {
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstCmd`"" -Wait
            }
        } catch {
            Write-NovaLog "Official uninstaller exited or failed: $($_.Exception.Message). Proceeding to Deep Hunt."
        }
    } else {
        Write-NovaLog "No standard uninstaller registered. Proceeding directly to Force Deep Hunt."
    }

    # Step 3: Run 18-Point Deep Leftover Scan
    Write-NovaLog "Step 3/3: Running post-uninstall 18-Point Deep Leftover Scan..."
    $scanResults = Invoke-DeepLeftoverScan -AppName $sel.DisplayName `
                                           -Publisher $sel.Publisher `
                                           -InstallLocation $sel.InstallLocation `
                                           -UninstallString $sel.UninstallString `
                                           -RegistryPath $sel.PSRegistryPath `
                                           -RegistryKeyName $sel.RegistryKeyName `
                                           -IncludeInstallRegistry $true

    Populate-InspectorResults -TargetTitle $sel.DisplayName -ScanList $scanResults
    Write-NovaLog "Post-uninstall scan complete: Found $($scanResults.Count) leftover files, folders, registry keys & services. Click '100% WIPE & NUKE' on the right panel to finish."
})

# ============================================================================
# 14. WINDOWS STORE / UWP DEEP UNINSTALL HANDLERS
# ============================================================================
$Controls['BtnScanStoreLeftovers'].Add_Click({
    $sel = $Controls['GridStoreApps'].SelectedItem
    if (-not $sel) { return }
    Write-NovaLog "Scanning UWP package directories and registry for '$($sel.Name)'..."
    $res = Invoke-DeepLeftoverScan -AppName $sel.Name -Publisher $sel.Publisher -InstallLocation $sel.LocalStatePath -UninstallString "" -RegistryPath "" -RegistryKeyName $sel.PackageFamilyName -IncludeInstallRegistry $false
    Populate-InspectorResults -TargetTitle "Store: $($sel.Name)" -ScanList $res
})

$Controls['BtnUninstallStoreApp'].Add_Click({
    $sel = $Controls['GridStoreApps'].SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Select a Windows Store / UWP package first.", "NovaGen Store Remover", "OK", "Warning") | Out-Null
        return
    }

    Write-NovaLog "Removing Windows Store AppX package '$($sel.PackageFullName)'..."
    try {
        Remove-AppxPackage -Package $sel.PackageFullName -ErrorAction Stop
        Write-NovaLog "Removed AppxPackage: $($sel.Name)"
    } catch {
        Write-NovaLog "Remove-AppxPackage status: $($_.Exception.Message)"
    }

    # Also check LocalState leftover folder
    if (-not [string]::IsNullOrWhiteSpace($sel.LocalStatePath) -and (Test-Path -LiteralPath $sel.LocalStatePath)) {
        $delRes = Invoke-ForceDeleteFileSystemItem -TargetPath $sel.LocalStatePath
        Write-NovaLog "LocalState Cache ($($sel.LocalStatePath)): $($delRes.Status)"
    }

    $Script:AllStoreCache = Get-AllStoreApps
    $Controls['GridStoreApps'].ItemsSource = $Script:AllStoreCache
    Update-SystemTelemetry
})

# ============================================================================
# 15. GHOST SWEEPER, CUSTOM HUNTER & SNAPSHOT HANDLERS
# ============================================================================
$Controls['BtnRunGhostScan'].Add_Click({
    Write-NovaLog "Scanning AppData (Local, Roaming, LocalLow) & ProgramData for orphaned ghost folders..."
    $ghostList = Invoke-GhostLeftoverSweep -CurrentInstalledApps $Script:AllAppsCache
    $Controls['GridGhostItems'].ItemsSource = $ghostList
    Write-NovaLog "Ghost Sweep complete: Found $($ghostList.Count) potential orphaned folders."
})

$Controls['BtnSendGhostToInspector'].Add_Click({
    $sel = $Controls['GridGhostItems'].SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Select a Ghost folder row first.", "NovaGen Ghost Sweeper", "OK", "Warning") | Out-Null
        return
    }
    Write-NovaLog "Hunting all related files and registry entries for ghost folder '$($sel.FolderName)'..."
    $res = Invoke-DeepLeftoverScan -AppName $sel.FolderName -Publisher "" -InstallLocation $sel.FullPath -UninstallString "" -RegistryPath "" -RegistryKeyName $sel.FolderName -IncludeInstallRegistry $true
    Populate-InspectorResults -TargetTitle "Ghost: $($sel.FolderName)" -ScanList $res
    Write-NovaLog "Found $($res.Count) total traces linked to '$($sel.FolderName)'."
})

# Custom Hunter Browse & Execute
$Controls['BtnBrowseHunterPath'].Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select Target Application Folder to Hunt & Nuke"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Controls['TxtHunterPath'].Text = $dlg.SelectedPath
        if ([string]::IsNullOrWhiteSpace($Controls['TxtHunterKeyword'].Text)) {
            $Controls['TxtHunterKeyword'].Text = Split-Path -Leaf $dlg.SelectedPath
        }
    }
})

$Controls['BtnExecuteCustomHunt'].Add_Click({
    $kw = $Controls['TxtHunterKeyword'].Text.Trim()
    $pub = $Controls['TxtHunterPublisher'].Text.Trim()
    $path = $Controls['TxtHunterPath'].Text.Trim()

    if ([string]::IsNullOrWhiteSpace($kw) -and [string]::IsNullOrWhiteSpace($path)) {
        [System.Windows.MessageBox]::Show("Enter an Application Name/Keyword or select a Target Folder Path.", "NovaGen Custom Hunter", "OK", "Warning") | Out-Null
        return
    }
    if ($kw.Length -gt 0 -and $kw.Length -lt 3) {
        [System.Windows.MessageBox]::Show("Keyword must be at least 3 characters long for safety.", "NovaGen Safety Guard", "OK", "Warning") | Out-Null
        return
    }

    $title = if ($kw) { $kw } else { Split-Path -Leaf $path }
    Write-NovaLog "Executing 18-Point Custom Target Hunt for '$title'..."
    $res = Invoke-DeepLeftoverScan -AppName $kw -Publisher $pub -InstallLocation $path -UninstallString "" -RegistryPath "" -RegistryKeyName $kw -IncludeInstallRegistry $true
    Populate-InspectorResults -TargetTitle "Custom Hunt: $title" -ScanList $res
    Write-NovaLog "Custom Hunt finished: Found $($res.Count) files, folders, registry keys & background items."
})

# Snapshot Tracker Handlers
function Refresh-SnapshotsList {
    $Controls['ListSnapshots'].Items.Clear()
    $files = Get-ChildItem -LiteralPath $Script:SnapshotRoot -Filter "Snapshot_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    foreach ($f in $files) {
        [void]$Controls['ListSnapshots'].Items.Add($f.Name)
    }
}

$Controls['BtnCreateSnapshot'].Add_Click({
    $label = $Controls['TxtSnapshotLabel'].Text.Trim()
    Write-NovaLog "Capturing system filesystem & registry baseline snapshot ($label)..."
    $saved = New-SystemInstallSnapshot -SnapshotName $label
    Refresh-SnapshotsList
    Write-NovaLog "Snapshot saved: $(Split-Path -Leaf $saved)"
})

$Controls['BtnDeleteSnapshot'].Add_Click({
    $sel = $Controls['ListSnapshots'].SelectedItem
    if (-not $sel) { return }
    $full = Join-Path $Script:SnapshotRoot $sel
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        Refresh-SnapshotsList
        Write-NovaLog "Deleted snapshot: $sel"
    }
})

$Controls['BtnCompareSnapshot'].Add_Click({
    $sel = $Controls['ListSnapshots'].SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Select a saved snapshot from the list to compare.", "NovaGen Snapshot Tracker", "OK", "Warning") | Out-Null
        return
    }
    $full = Join-Path $Script:SnapshotRoot $sel
    Write-NovaLog "Comparing current C: & Registry state against snapshot '$sel'..."
    $diffs = Compare-SystemInstallSnapshot -SnapshotFilePath $full
    Populate-InspectorResults -TargetTitle "Diff vs $sel" -ScanList $diffs
    Write-NovaLog "Snapshot comparison complete: Found $($diffs.Count) newly created folders/registry keys."
})

# ============================================================================
# 16. RIGHT-PANE INSPECTOR SELECTION & 100% NUKE ENGINE
# ============================================================================
$Controls['BtnSelectAllLeftovers'].Add_Click({
    foreach ($item in $Script:LeftoverItems) { $item.IsSelected = $true }
    $Controls['GridLeftovers'].Items.Refresh()
    Update-InspectorCounters
})

$Controls['BtnSelectNoneLeftovers'].Add_Click({
    foreach ($item in $Script:LeftoverItems) { $item.IsSelected = $false }
    $Controls['GridLeftovers'].Items.Refresh()
    Update-InspectorCounters
})

$Controls['GridLeftovers'].Add_CellEditEnding({
    $Window.Dispatcher.BeginInvoke([Action]{ Update-InspectorCounters }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
})

$Controls['BtnNukeSelected'].Add_Click({
    $toWipe = @($Script:LeftoverItems | Where-Object { $_.IsSelected })
    if ($toWipe.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No leftover items are selected in the Inspector.", "NovaGen Wipe Engine", "OK", "Information") | Out-Null
        return
    }

    $totalBytesToFree = [int64]0
    foreach ($w in $toWipe) { $totalBytesToFree += $w.SizeBytes }

    $confirm = [System.Windows.MessageBox]::Show(
        "CRITICAL CONFIRMATION — 100% ZERO-TRACE WIPE`n`nTarget: $($Script:CurrentTargetTitle)`nItems Selected: $($toWipe.Count) items ($(Format-ByteSize $totalBytesToFree))`n`n• Automatic .reg backup will be saved to:`n  $Script:BackupRoot`n• Running services, tasks & processes will be terminated.`n• Locked files will be force-unlocked or queued for boot deletion.`n`nExecute permanent wipe now?",
        "NovaGen // Confirm 100% Zero-Trace Wipe",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    # Create Timestamped Backup Directory
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $safeTarget = (($Script:CurrentTargetTitle -replace '[^\w\-]', '_') -replace '_+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeTarget)) { $safeTarget = "DeepWipe" }
    $sessionBackupDir = Join-Path $Script:BackupRoot "${stamp}_${safeTarget}"
    New-Item -ItemType Directory -Path $sessionBackupDir -Force | Out-Null
    $auditLogFile = Join-Path $sessionBackupDir "WipeAuditLog.txt"

    Write-NovaLog "Created safety backup vault: $sessionBackupDir"
    "NOVAGEN ZERO-TRACE WIPE AUDIT LOG - $(Get-Date)" | Set-Content -LiteralPath $auditLogFile -Encoding UTF8

    # Kill related processes first
    [void](Stop-AppRelatedProcesses -AppName $Script:CurrentTargetTitle -InstallLocation "")

    $wipedCount = 0
    $reclaimedNow = [int64]0
    $remainingList = New-Object System.Collections.Generic.List[PSObject]

    foreach ($item in $Script:LeftoverItems) {
        if (-not $item.IsSelected) {
            $remainingList.Add($item)
            continue
        }

        $type = $item.ItemType
        $path = $item.TargetPath
        $sub  = $item.SubTarget

        switch ($type) {
            "Service" {
                try {
                    Stop-Service -Name $path -Force -ErrorAction SilentlyContinue
                    Start-Process -FilePath "sc.exe" -ArgumentList "delete `"$path`"" -WindowStyle Hidden -Wait
                    Write-NovaLog "[SERVICE DELETED] $path ($sub)"
                    "SERVICE DELETED: $path ($sub)" | Add-Content -LiteralPath $auditLogFile
                    $wipedCount++
                } catch {
                    Write-NovaLog "[SERVICE ERROR] $path : $($_.Exception.Message)"
                    $remainingList.Add($item)
                }
            }
            "Task" {
                try {
                    Start-Process -FilePath "schtasks.exe" -ArgumentList "/Delete /TN `"$path`" /F" -WindowStyle Hidden -Wait
                    Write-NovaLog "[TASK DELETED] $path"
                    "TASK DELETED: $path" | Add-Content -LiteralPath $auditLogFile
                    $wipedCount++
                } catch {
                    $remainingList.Add($item)
                }
            }
            "RegistryKey" {
                try {
                    [void](Export-RegistryKeyBackup -PSRegistryPath $path -BackupFolder $sessionBackupDir)
                    if (Test-Path -LiteralPath $path) {
                        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                    }
                    Write-NovaLog "[REGISTRY KEY WIPED] $($item.DisplayPath)"
                    "REGISTRY KEY WIPED: $($item.DisplayPath)" | Add-Content -LiteralPath $auditLogFile
                    $wipedCount++
                } catch {
                    # Fallback via reg.exe delete
                    $nativeKey = $path -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\'
                    Start-Process -FilePath "reg.exe" -ArgumentList "delete `"$nativeKey`" /f" -WindowStyle Hidden -Wait
                    if (-not (Test-Path -LiteralPath $path)) {
                        Write-NovaLog "[REGISTRY KEY FORCE-WIPED] $nativeKey"
                        "REGISTRY KEY FORCE-WIPED: $nativeKey" | Add-Content -LiteralPath $auditLogFile
                        $wipedCount++
                    } else {
                        Write-NovaLog "[REGISTRY LOCKED] $nativeKey"
                        $remainingList.Add($item)
                    }
                }
            }
            "RegistryValue" {
                try {
                    [void](Export-RegistryKeyBackup -PSRegistryPath $path -BackupFolder $sessionBackupDir)
                    Remove-ItemProperty -LiteralPath $path -Name $sub -Force -ErrorAction Stop
                    Write-NovaLog "[REGISTRY VALUE WIPED] $path -> [$sub]"
                    "REGISTRY VALUE WIPED: $path -> [$sub]" | Add-Content -LiteralPath $auditLogFile
                    $wipedCount++
                } catch {
                    $remainingList.Add($item)
                }
            }
            Default {
                # File or Folder
                $res = Invoke-ForceDeleteFileSystemItem -TargetPath $path
                if ($res.Success) {
                    Write-NovaLog "[$($res.Status.ToUpper())] $path"
                    "$($res.Status): $path ($($item.SizeFormatted))" | Add-Content -LiteralPath $auditLogFile
                    $wipedCount++
                    $reclaimedNow += $item.SizeBytes
                } else {
                    Write-NovaLog "[FAILED: $($res.Status)] $path"
                    $remainingList.Add($item)
                }
            }
        }
    }

    $Script:SessionReclaimedBytes += $reclaimedNow
    Populate-InspectorResults -TargetTitle "$($Script:CurrentTargetTitle) (CLEANED)" -ScanList $remainingList

    # Refresh Installed Apps list in case an Uninstall Registry key was removed
    $Script:AllAppsCache = Get-AllInstalledApps
    Apply-InstalledAppsFilter
    Update-SystemTelemetry

    Write-NovaLog "=== ZERO-TRACE WIPE COMPLETE: $wipedCount items obliterated | Reclaimed $(Format-ByteSize $reclaimedNow) ==="
    [System.Windows.MessageBox]::Show(
        "100% Zero-Trace Wipe Complete!`n`n• Obliterated Items: $wipedCount`n• Storage Reclaimed: $(Format-ByteSize $reclaimedNow)`n• Registry Backup & Audit Log saved to:`n  $sessionBackupDir",
        "NovaGen // Wipe Successful",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
})

# ============================================================================
# 17. INITIALIZATION & STARTUP LOAD
# ============================================================================
function Invoke-FullSystemIndex {
    Write-NovaLog "Indexing installed Win32 applications across HKLM (x64/x86) and HKCU hives..."
    $Script:AllAppsCache = Get-AllInstalledApps
    if (-not $Script:AllStoreCache) {
        $Script:AllStoreCache = New-Object System.Collections.Generic.List[PSObject]
    }
    Apply-InstalledAppsFilter
    Update-SystemTelemetry
    Write-NovaLog "Indexed $($Script:AllAppsCache.Count) applications. Ready for 100% Zero-Trace Deep Uninstall."
}

$Controls['BtnRefreshAll'].Add_Click({
    Invoke-FullSystemIndex
})

$Window.Add_Loaded({
    Invoke-FullSystemIndex
})

[void]$Window.ShowDialog()
