using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.ServiceProcess;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Win32;
using NovaGenPro.Models;

namespace NovaGenPro.Services
{
    public static class UninstallerService
    {
        private static readonly string[] ProtectedRegexes = new[]
        {
            @"^C:\\Windows",
            @"^C:\\Windows\\System32(\\|$)",
            @"^C:\\Windows\\SysWOW64(\\|$)",
            @"^C:\\Windows\\WinSxS(\\|$)",
            @"^C:\\Windows\\Drivers(\\|$)",
            @"^C:\\Windows\\Boot(\\|$)",
            @"^C:\\Windows\\Fonts(\\|$)",
            @"^C:\\Windows\\INF(\\|$)",
            @"^C:\\Program Files",
            @"^C:\\Program Files \(x86\)",
            @"^C:\\Program Files\\Common Files",
            @"^C:\\Program Files \(x86\)\\Common Files",
            @"^C:\\Program Files\\WindowsApps(\\|$)",
            @"^C:\\Program Files\\Windows Defender(\\|$)",
            @"^C:\\ProgramData",
            @"^C:\\ProgramData\\Microsoft",
            @"^C:\\ProgramData\\Microsoft\\Windows(\\|$)",
            @"^C:\\Users",
            @"^C:\\Users\\[^\\]+",
            @"^C:\\Users\\[^\\]+\\AppData",
            @"^C:\\Users\\[^\\]+\\AppData\\(Local|LocalLow|Roaming)",
            @"^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft",
            @"^C:\\Users\\[^\\]+\\AppData\\Local\\Microsoft\\Windows(\\|$)",
            @"^C:\\Users\\[^\\]+\\AppData\\Roaming\\Microsoft",
            @"^C:\\Users\\[^\\]+\\AppData\\Roaming\\Microsoft\\Windows(\\|$)",
            @"^C:\\Users\\[^\\]+\\(Desktop|Documents|Downloads|Pictures|Music|Videos)"
        };

        private static readonly HashSet<string> StopWords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "microsoft","windows","common","files","program","system","system32","syswow64",
            "google","apple","intel","amd","nvidia","realtek","driver","drivers","package",
            "packages","client","server","service","services","update","updater","helper",
            "setup","install","installer","uninstaller","uninstall","runtime","redistributable",
            "framework","sdk","jdk","jre","net","core","desktop","app","apps","application",
            "applications","software","corporation","inc","ltd","llc","gmbh","co","the",
            "for","and","with","pro","plus","free","edition","version","x64","x86","64","32",
            "bit","user","users","default","public","local","roaming","locallow","temp","tmp",
            "data","config","cache","logs","log","bin","lib","share","docs","media","audio",
            "video","network","security","defender","edge","webview","webview2","explorer",
            "shell","host","broker","store","xbox","directx","visual","studio","code"
        };

        public static bool IsProtectedPath(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return true;
            string clean = path.TrimEnd('\\');
            if (clean.Length <= 10) return true;
            foreach (var rx in ProtectedRegexes)
            {
                if (Regex.IsMatch(clean, rx, RegexOptions.IgnoreCase)) return true;
            }
            return false;
        }

        public static string FormatByteSize(long bytes)
        {
            if (bytes <= 0) return "0 KB";
            if (bytes >= 1073741824L) return string.Format("{0:N2} GB", bytes / 1073741824.0);
            if (bytes >= 1048576L) return string.Format("{0:N1} MB", bytes / 1048576.0);
            if (bytes >= 1024L) return string.Format("{0:N0} KB", bytes / 1024.0);
            return bytes + " B";
        }

        public static long GetDirectorySizeFast(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return 0;
            try
            {
                if (File.Exists(path)) return new FileInfo(path).Length;
                if (!Directory.Exists(path)) return 0;
                long sum = 0;
                var stack = new Stack<string>();
                stack.Push(path);
                while (stack.Count > 0)
                {
                    string cur = stack.Pop();
                    try
                    {
                        foreach (var f in Directory.EnumerateFiles(cur))
                        {
                            try { sum += new FileInfo(f).Length; } catch { }
                        }
                        foreach (var d in Directory.EnumerateDirectories(cur))
                        {
                            try
                            {
                                var di = new DirectoryInfo(d);
                                if ((di.Attributes & FileAttributes.ReparsePoint) == 0) stack.Push(d);
                            }
                            catch { }
                        }
                    }
                    catch { }
                }
                return sum;
            }
            catch { return 0; }
        }

        public static List<InstalledAppItem> GetAllInstalledApps()
        {
            var list = new List<InstalledAppItem>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            var sources = new[]
            {
                new { Hive = RegistryHive.LocalMachine, View = RegistryView.Registry64, SubKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", Arch = "x64", Cat = "Desktop App", Prefix = @"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" },
                new { Hive = RegistryHive.LocalMachine, View = RegistryView.Registry32, SubKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", Arch = "x86", Cat = "Desktop App", Prefix = @"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" },
                new { Hive = RegistryHive.CurrentUser,  View = RegistryView.Default,    SubKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", Arch = "User", Cat = "User App", Prefix = @"HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
            };

            foreach (var src in sources)
            {
                try
                {
                    using (var baseKey = RegistryKey.OpenBaseKey(src.Hive, src.View))
                    using (var uninstKey = baseKey.OpenSubKey(src.SubKey))
                    {
                        if (uninstKey == null) continue;
                        foreach (var subName in uninstKey.GetSubKeyNames())
                        {
                            try
                            {
                                using (var sk = uninstKey.OpenSubKey(subName))
                                {
                                    if (sk == null) continue;
                                    string name = sk.GetValue("DisplayName") as string;
                                    if (string.IsNullOrWhiteSpace(name)) continue;
                                    object sysComp = sk.GetValue("SystemComponent");
                                    if (sysComp != null && Convert.ToInt32(sysComp) == 1) continue;
                                    if (!string.IsNullOrWhiteSpace(sk.GetValue("ParentKeyName") as string)) continue;

                                    string uninst = (sk.GetValue("QuietUninstallString") as string) ?? (sk.GetValue("UninstallString") as string) ?? "";
                                    string loc = (sk.GetValue("InstallLocation") as string) ?? "";
                                    string pub = (sk.GetValue("Publisher") as string) ?? "Unknown";
                                    string ver = (sk.GetValue("DisplayVersion") as string) ?? "â€”";
                                    string dt = (sk.GetValue("InstallDate") as string) ?? "";
                                    if (dt.Length == 8 && dt.All(char.IsDigit))
                                        dt = dt.Substring(0, 4) + "-" + dt.Substring(4, 2) + "-" + dt.Substring(6, 2);
                                    else if (string.IsNullOrWhiteSpace(dt))
                                        dt = "â€”";

                                    long sizeBytes = 0;
                                    object estSize = sk.GetValue("EstimatedSize");
                                    if (estSize != null)
                                    {
                                        long kb;
                                        if (long.TryParse(estSize.ToString(), out kb) && kb > 0) sizeBytes = kb * 1024L;
                                    }

                                    string dedupKey = name.Trim() + "|" + ver.Trim() + "|" + src.Arch;
                                    if (!seen.Add(dedupKey)) continue;

                                    string cat = src.Cat;
                                    if (name.IndexOf("Visual C++", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                        name.IndexOf(".NET", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                        name.IndexOf("Runtime", StringComparison.OrdinalIgnoreCase) >= 0)
                                        cat = "Runtime / System";

                                    list.Add(new InstalledAppItem
                                    {
                                        DisplayName = name.Trim(),
                                        Publisher = pub.Trim(),
                                        DisplayVersion = ver.Trim(),
                                        Arch = src.Arch,
                                        InstallDate = dt,
                                        Category = cat,
                                        InstallLocation = loc.Trim('"'),
                                        UninstallString = (sk.GetValue("UninstallString") as string) ?? "",
                                        QuietUninstallString = (sk.GetValue("QuietUninstallString") as string) ?? "",
                                        RegistryPath = src.Prefix + "\\" + subName,
                                        RegistryKeyName = subName,
                                        SizeBytes = sizeBytes,
                                        SizeDisplay = sizeBytes > 0 ? FormatByteSize(sizeBytes) : "â€”"
                                    });
                                }
                            }
                            catch { }
                        }
                    }
                }
                catch { }
            }

            return list.OrderBy(a => a.DisplayName, StringComparer.OrdinalIgnoreCase).ToList();
        }

        public static List<StoreAppItem> GetAllStoreApps()
        {
            var list = new List<StoreAppItem>();
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"Get-AppxPackage | Where-Object { -not $_.NonRemovable -and $_.SignatureKind -ne 'System' } | ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.Name,$_.Publisher,$_.Version,$_.PackageFullName,$_.InstallLocation }\"",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using (var p = Process.Start(psi))
                {
                    string outStr = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(15000);
                    foreach (var line in outStr.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                    {
                        var parts = line.Split('|');
                        if (parts.Length >= 4)
                        {
                            string pub = parts[1];
                            var m = Regex.Match(pub, @"CN=([^,]+)");
                            if (m.Success) pub = m.Groups[1].Value;
                            list.Add(new StoreAppItem
                            {
                                Name = parts[0],
                                Publisher = pub,
                                Version = parts[2],
                                PackageFullName = parts[3],
                                InstallLocation = parts.Length > 4 ? parts[4] : ""
                            });
                        }
                    }
                }
            }
            catch { }
            return list.OrderBy(s => s.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }

        public static List<string> ExtractSearchTokens(string appName, string publisher, string installLocation)
        {
            var tokens = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (!string.IsNullOrWhiteSpace(appName))
            {
                string clean = Regex.Replace(appName, @"\(.*?\)|\[.*?\]", "");
                clean = Regex.Replace(clean, @"(?i)\b(v?\d+(\.\d+)+([a-z0-9\-_]*)?|x64|x86|64-bit|32-bit|amd64|arm64)\b", "");
                clean = Regex.Replace(clean, @"[^\w\s\-\.]", " ").Trim();
                if (clean.Length >= 3 && !StopWords.Contains(clean)) tokens.Add(clean);
                string noSpace = clean.Replace(" ", "");
                if (noSpace.Length >= 4 && !StopWords.Contains(noSpace)) tokens.Add(noSpace);
                foreach (var w in clean.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    if (w.Length >= 4 && !StopWords.Contains(w)) tokens.Add(w);
                }
            }
            if (!string.IsNullOrWhiteSpace(installLocation))
            {
                string leaf = Path.GetFileName(installLocation.TrimEnd('\\'));
                if (!string.IsNullOrWhiteSpace(leaf) && leaf.Length >= 3 && !StopWords.Contains(leaf))
                    tokens.Add(leaf);
            }
            return tokens.ToList();
        }

        public static List<LeftoverItem> DeepScanLeftovers(string appName, string publisher, string installLocation, string registryPath, IProgress<string> progress = null)
        {
            var results = new List<LeftoverItem>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var tokens = ExtractSearchTokens(appName, publisher, installLocation);

            Action<string, string> AddFsItem = (path, tag) =>
            {
                if (string.IsNullOrWhiteSpace(path) || !seen.Add("FS|" + path)) return;
                if (IsProtectedPath(path)) return;
                if (!Directory.Exists(path) && !File.Exists(path)) return;
                long sz = GetDirectorySizeFast(path);
                results.Add(new LeftoverItem
                {
                    IsSelected = true,
                    ItemType = Directory.Exists(path) ? "FOLDER" : "FILE",
                    LocationTag = tag,
                    SizeBytes = sz,
                    SizeDisplay = FormatByteSize(sz),
                    TargetPath = path
                });
            };

            if (!string.IsNullOrWhiteSpace(installLocation) && Directory.Exists(installLocation))
                AddFsItem(installLocation, "Install Dir");

            var fsRoots = new[]
            {
                new { Tag = "Program Files", Path = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) },
                new { Tag = "Program Files x86", Path = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) },
                new { Tag = "AppData Local", Path = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData) },
                new { Tag = "AppData Roaming", Path = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) },
                new { Tag = "AppData LocalLow", Path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @"AppData\LocalLow") },
                new { Tag = "ProgramData", Path = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) },
                new { Tag = "User Temp", Path = Path.GetTempPath() }
            };

            foreach (var r in fsRoots)
            {
                if (string.IsNullOrWhiteSpace(r.Path) || !Directory.Exists(r.Path)) continue;
                if (progress != null) progress.Report("Scanning " + r.Tag + "...");
                try
                {
                    foreach (var dir in Directory.EnumerateDirectories(r.Path))
                    {
                        string name = Path.GetFileName(dir);
                        if (tokens.Any(t => name.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0))
                            AddFsItem(dir, r.Tag);
                    }
                }
                catch { }
            }

            // Prefetch
            if (progress != null) progress.Report("Scanning Windows Prefetch...");
            string pfDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Prefetch");
            if (Directory.Exists(pfDir))
            {
                try
                {
                    foreach (var f in Directory.EnumerateFiles(pfDir, "*.pf"))
                    {
                        string fn = Path.GetFileName(f);
                        if (tokens.Any(t => fn.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0))
                            AddFsItem(f, "Prefetch");
                    }
                }
                catch { }
            }

            // Registry Uninstall Key
            if (!string.IsNullOrWhiteSpace(registryPath) && seen.Add("REG|" + registryPath))
            {
                results.Add(new LeftoverItem
                {
                    IsSelected = true,
                    ItemType = "REG_KEY",
                    LocationTag = "Uninstall Hive",
                    SizeBytes = 0,
                    SizeDisplay = "Reg Key",
                    TargetPath = registryPath
                });
            }

            // Registry HKCU/HKLM Software keys
            if (progress != null) progress.Report("Scanning Registry Software Hives...");
            var regHives = new[]
            {
                new { Hive = RegistryHive.CurrentUser, View = RegistryView.Default, Sub = "Software", Prefix = @"HKCU\Software", Tag = "HKCU Software" },
                new { Hive = RegistryHive.LocalMachine, View = RegistryView.Registry64, Sub = "SOFTWARE", Prefix = @"HKLM\SOFTWARE", Tag = "HKLM Software" },
                new { Hive = RegistryHive.LocalMachine, View = RegistryView.Registry32, Sub = "SOFTWARE", Prefix = @"HKLM\SOFTWARE\WOW6432Node", Tag = "WOW6432Node" }
            };

            foreach (var rh in regHives)
            {
                try
                {
                    using (var bk = RegistryKey.OpenBaseKey(rh.Hive, rh.View))
                    using (var sw = bk.OpenSubKey(rh.Sub))
                    {
                        if (sw == null) continue;
                        foreach (var sub in sw.GetSubKeyNames())
                        {
                            if (StopWords.Contains(sub)) continue;
                            if (tokens.Any(t => sub.Equals(t, StringComparison.OrdinalIgnoreCase) || (t.Length >= 5 && sub.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0)))
                            {
                                string full = rh.Prefix + "\\" + sub;
                                if (seen.Add("REG|" + full))
                                {
                                    results.Add(new LeftoverItem
                                    {
                                        IsSelected = true,
                                        ItemType = "REG_KEY",
                                        LocationTag = rh.Tag,
                                        SizeBytes = 0,
                                        SizeDisplay = "Reg Key",
                                        TargetPath = full
                                    });
                                }
                            }
                        }
                    }
                }
                catch { }
            }

            // Windows Services
            if (progress != null) progress.Report("Scanning Services...");
            try
            {
                foreach (var svc in ServiceController.GetServices())
                {
                    if (tokens.Any(t => t.Length >= 5 && (svc.ServiceName.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0 || svc.DisplayName.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0)))
                    {
                        if (seen.Add("SVC|" + svc.ServiceName))
                        {
                            results.Add(new LeftoverItem
                            {
                                IsSelected = true,
                                ItemType = "SERVICE",
                                LocationTag = "Win Service",
                                SizeBytes = 0,
                                SizeDisplay = "Service",
                                TargetPath = svc.ServiceName
                            });
                        }
                    }
                }
            }
            catch { }

            return results.OrderByDescending(r => r.SizeBytes).ToList();
        }

        public static long WipeLeftovers(IEnumerable<LeftoverItem> items, string backupDir, Action<string> log)
        {
            long totalReclaimed = 0;
            Directory.CreateDirectory(backupDir);
            string sessionDir = Path.Combine(backupDir, "Wipe_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
            Directory.CreateDirectory(sessionDir);

            int regIdx = 0;
            foreach (var item in items)
            {
                try
                {
                    if (item.ItemType == "SERVICE")
                    {
                        try
                        {
                            using (var sc = new ServiceController(item.TargetPath))
                            {
                                if (sc.Status != ServiceControllerStatus.Stopped)
                                {
                                    sc.Stop();
                                    sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(5));
                                }
                            }
                        }
                        catch { }
                        { var _p = Process.Start(new ProcessStartInfo("sc.exe", "delete \"" + item.TargetPath + "\"") { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(4000); }
                        if (log != null) log("Removed Service: " + item.TargetPath);
                    }
                    else if (item.ItemType == "REG_KEY")
                    {
                        regIdx++;
                        string regBk = Path.Combine(sessionDir, string.Format("reg_{0}.reg", regIdx));
                        { var _p = Process.Start(new ProcessStartInfo("reg.exe", string.Format("export \"{0}\" \"{1}\" /y", item.TargetPath, regBk)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); }
                        { var _p = Process.Start(new ProcessStartInfo("reg.exe", string.Format("delete \"{0}\" /f", item.TargetPath)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); }
                        if (log != null) log("Wiped Registry Key (backed up): " + item.TargetPath);
                    }
                    else
                    {
                        if (IsProtectedPath(item.TargetPath)) continue;
                        if (File.Exists(item.TargetPath))
                        {
                            long sz = new FileInfo(item.TargetPath).Length;
                            try
                            {
                                File.SetAttributes(item.TargetPath, FileAttributes.Normal);
                                File.Delete(item.TargetPath);
                                totalReclaimed += sz;
                                if (log != null) log("Deleted File: " + item.TargetPath);
                            }
                            catch
                            {
                                NativeMethods.ScheduleDeleteOnReboot(item.TargetPath);
                                if (log != null) log("Locked â€” Scheduled Reboot Delete: " + item.TargetPath);
                            }
                        }
                        else if (Directory.Exists(item.TargetPath))
                        {
                            long before = GetDirectorySizeFast(item.TargetPath);
                            try { Directory.Delete(item.TargetPath, true); } catch { }
                            long after = Directory.Exists(item.TargetPath) ? GetDirectorySizeFast(item.TargetPath) : 0;
                            long diff = Math.Max(0, before - after);
                            totalReclaimed += diff;
                            if (Directory.Exists(item.TargetPath))
                            {
                                NativeMethods.ScheduleDeleteOnReboot(item.TargetPath);
                                if (log != null) log("Partially locked â€” Scheduled Reboot Delete: " + item.TargetPath);
                            }
                            else
                            {
                                if (log != null) log(string.Format("Obliterated Folder ({0}): {1}", FormatByteSize(diff), item.TargetPath));
                            }
                        }
                    }
                }
                catch { }
            }
            return totalReclaimed;
        }

        public static List<GhostItem> ScanGhostFolders(IEnumerable<InstalledAppItem> installedApps)
        {
            var ghosts = new List<GhostItem>();
            var activeTokens = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var app in installedApps)
            {
                foreach (var t in ExtractSearchTokens(app.DisplayName, app.Publisher, app.InstallLocation))
                    activeTokens.Add(t);
            }

            var roots = new[]
            {
                new { Name = "Program Files", Path = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) },
                new { Name = "Program Files (x86)", Path = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) },
                new { Name = "AppData Roaming", Path = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) },
                new { Name = "AppData Local", Path = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData) },
                new { Name = "ProgramData", Path = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) }
            };

            foreach (var r in roots)
            {
                if (string.IsNullOrWhiteSpace(r.Path) || !Directory.Exists(r.Path)) continue;
                try
                {
                    foreach (var dir in Directory.EnumerateDirectories(r.Path))
                    {
                        if (IsProtectedPath(dir)) continue;
                        string name = Path.GetFileName(dir);
                        if (StopWords.Contains(name) || name.StartsWith(".")) continue;
                        bool matchedActive = activeTokens.Any(t => name.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf(name, StringComparison.OrdinalIgnoreCase) >= 0);
                        if (!matchedActive)
                        {
                            long sz = GetDirectorySizeFast(dir);
                            if (sz >= 512 * 1024L)
                            {
                                ghosts.Add(new GhostItem
                                {
                                    FolderName = name,
                                    Location = r.Name,
                                    SizeBytes = sz,
                                    SizeDisplay = FormatByteSize(sz),
                                    FullPath = dir
                                });
                            }
                        }
                    }
                }
                catch { }
            }
            return ghosts.OrderByDescending(g => g.SizeBytes).ToList();
        }
    }
}
