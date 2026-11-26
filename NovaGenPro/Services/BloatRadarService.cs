using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using NovaGenPro.Models;

namespace NovaGenPro.Services
{
    public static class BloatRadarService
    {
        private static readonly string[] DevTargets = { "node_modules", ".dart_tool", ".gradle", "build", "target", "__pycache__", ".next", "dist", ".venv" };
        private static readonly HashSet<string> SkipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Windows", "Program Files", "Program Files (x86)", "ProgramData", "$Recycle.Bin", "System Volume Information", "AppData", ".git"
        };

        public static ulong? GetImageDHash(string filePath)
        {
            try
            {
                using (var fs = File.OpenRead(filePath))
                using (var img = Image.FromStream(fs, false, false))
                using (var bmp = new Bitmap(9, 8))
                {
                    using (var g = Graphics.FromImage(bmp))
                    {
                        g.InterpolationMode = InterpolationMode.Bilinear;
                        g.DrawImage(img, 0, 0, 9, 8);
                    }
                    ulong hash = 0;
                    int bit = 0;
                    for (int y = 0; y < 8; y++)
                    {
                        for (int x = 0; x < 8; x++)
                        {
                            var c1 = bmp.GetPixel(x, y);
                            var c2 = bmp.GetPixel(x + 1, y);
                            double l1 = c1.R * 0.299 + c1.G * 0.587 + c1.B * 0.114;
                            double l2 = c2.R * 0.299 + c2.G * 0.587 + c2.B * 0.114;
                            if (l1 > l2) hash |= (1UL << bit);
                            bit++;
                        }
                    }
                    return hash;
                }
            }
            catch { return null; }
        }

        private static int HammingDistance64(ulong a, ulong b)
        {
            ulong x = a ^ b;
            int dist = 0;
            while (x != 0) { x &= (x - 1); dist++; }
            return dist;
        }

        public static List<BloatRadarItem> Scan(string customRoot, int staleDays, bool scanDev, bool scanGamer, bool scanInstallers, bool scanDuplicates, IProgress<string> statusProgress, IProgress<BloatRadarItem> itemProgress)
        {
            var results = new List<BloatRadarItem>();
            DateTime now = DateTime.Now;
            DateTime staleCutoff = now.AddDays(-staleDays);
            string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string dlReal = NativeMethods.GetKnownDownloadsPath();
            string dtReal = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);

            Action<BloatRadarItem> Emit = (item) =>
            {
                results.Add(item);
                if (itemProgress != null) itemProgress.Report(item);
            };

            // 1. Gamer & GPU Caches (Fast)
            if (scanGamer)
            {
                if (statusProgress != null) statusProgress.Report("Scanning Gamer & Shader caches (Steam, NVIDIA, AMD, DirectX)...");
                var gamerPaths = new List<Tuple<string, string>>();
                foreach (var sb in new[] { @"C:\Program Files (x86)\Steam\steamapps", @"C:\Program Files\Steam\steamapps", @"D:\SteamLibrary\steamapps", @"E:\SteamLibrary\steamapps" })
                {
                    if (Directory.Exists(sb))
                    {
                        gamerPaths.Add(Tuple.Create("Steam Downloading", Path.Combine(sb, "downloading")));
                        gamerPaths.Add(Tuple.Create("Steam ShaderCache", Path.Combine(sb, "shadercache")));
                    }
                }
                gamerPaths.Add(Tuple.Create("NVIDIA DXCache", Path.Combine(localApp, @"NVIDIA\DXCache")));
                gamerPaths.Add(Tuple.Create("NVIDIA GLCache", Path.Combine(localApp, @"NVIDIA\GLCache")));
                gamerPaths.Add(Tuple.Create("AMD DxCache", Path.Combine(localApp, @"AMD\DxCache")));
                gamerPaths.Add(Tuple.Create("DirectX Cache", Path.Combine(localApp, "D3DSCache")));

                foreach (var gp in gamerPaths)
                {
                    if (!Directory.Exists(gp.Item2)) continue;
                    long sz = UninstallerService.GetDirectorySizeFast(gp.Item2);
                    if (sz >= 1048576L)
                    {
                        Emit(new BloatRadarItem
                        {
                            IsSelected = true,
                            Category = gp.Item1,
                            StatusTag = "SAFE CACHE",
                            SizeBytes = sz,
                            SizeDisplay = UninstallerService.FormatByteSize(sz),
                            TargetPath = gp.Item2,
                            ItemType = "DIR_CONTENTS"
                        });
                    }
                }
            }

            // 2. Orphaned Installers
            if (scanInstallers)
            {
                if (statusProgress != null) statusProgress.Report("Scanning orphaned installers (.exe / .msi / .iso)...");
                foreach (var dir in new[] { dlReal, dtReal }.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    if (!Directory.Exists(dir)) continue;
                    try
                    {
                        foreach (var f in new DirectoryInfo(dir).EnumerateFiles())
                        {
                            string ext = f.Extension.ToLowerInvariant();
                            if ((ext == ".exe" || ext == ".msi" || ext == ".msix" || ext == ".iso") && f.Length >= 5 * 1048576L)
                            {
                                int age = (int)(now - f.LastWriteTime).TotalDays;
                                bool isOld = age >= staleDays;
                                Emit(new BloatRadarItem
                                {
                                    IsSelected = isOld,
                                    Category = string.Format("Installer ({0})", f.Extension),
                                    StatusTag = isOld ? string.Format("ORPHAN ({0} d)", age) : string.Format("RECENT ({0} d)", age),
                                    SizeBytes = f.Length,
                                    SizeDisplay = UninstallerService.FormatByteSize(f.Length),
                                    TargetPath = f.FullName,
                                    ItemType = "FILE"
                                });
                            }
                        }
                    }
                    catch { }
                }
            }

            // 3. Dev Bloat
            if (scanDev)
            {
                if (statusProgress != null) statusProgress.Report("Scanning stale Dev artifacts (node_modules, .dart_tool, .gradle, build)...");
                var roots = new List<string>();
                if (!string.IsNullOrWhiteSpace(customRoot) && Directory.Exists(customRoot))
                {
                    roots.Add(customRoot);
                }
                else
                {
                    foreach (var cand in new[] { dtReal, dlReal, Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), Path.Combine(userProfile, "source"), Path.Combine(userProfile, "Projects") })
                        if (!string.IsNullOrWhiteSpace(cand) && Directory.Exists(cand)) roots.Add(cand);
                    foreach (var drv in DriveInfo.GetDrives())
                    {
                        try
                        {
                            string sysRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
                            if (drv.DriveType == DriveType.Fixed && drv.IsReady && !drv.Name.Equals(sysRoot, StringComparison.OrdinalIgnoreCase))
                                roots.Add(drv.Name.TrimEnd('\\'));
                        }
                        catch { }
                    }
                }

                var queue = new Queue<Tuple<string, int>>();
                foreach (var r in roots.Distinct(StringComparer.OrdinalIgnoreCase)) queue.Enqueue(Tuple.Create(r, 0));
                int visited = 0;
                while (queue.Count > 0 && visited < 2000)
                {
                    var cur = queue.Dequeue();
                    string curPath = cur.Item1;
                    int depth = cur.Item2;
                    if (depth > 3) continue;
                    visited++;
                    if (visited % 80 == 0)
                        if (statusProgress != null) statusProgress.Report(string.Format("Scanning Dev ({0} dirs, {1} found): {2}", visited, results.Count, curPath));

                    string[] subDirs;
                    try { subDirs = Directory.GetDirectories(curPath); } catch { continue; }
                    foreach (var sd in subDirs)
                    {
                        string name = Path.GetFileName(sd);
                        if (SkipDirs.Contains(name)) continue;
                        if (DevTargets.Contains(name, StringComparer.OrdinalIgnoreCase))
                        {
                            try
                            {
                                if (name.Equals("build", StringComparison.OrdinalIgnoreCase) || name.Equals("dist", StringComparison.OrdinalIgnoreCase) || name.Equals("target", StringComparison.OrdinalIgnoreCase))
                                {
                                    bool hasMarker = File.Exists(Path.Combine(curPath, "package.json")) || File.Exists(Path.Combine(curPath, "pubspec.yaml")) ||
                                                     File.Exists(Path.Combine(curPath, "build.gradle")) || File.Exists(Path.Combine(curPath, "Cargo.toml")) || File.Exists(Path.Combine(curPath, "pom.xml"));
                                    if (!hasMarker) continue;
                                }
                                var di = new DirectoryInfo(sd);
                                long sz = UninstallerService.GetDirectorySizeFast(sd);
                                if (sz < 1048576L) continue;
                                int age = (int)(now - di.LastWriteTime).TotalDays;
                                bool isStale = di.LastWriteTime < staleCutoff;
                                Emit(new BloatRadarItem
                                {
                                    IsSelected = isStale,
                                    Category = string.Format("Dev Bloat [{0}]", name),
                                    StatusTag = isStale ? string.Format("STALE ({0} d)", age) : string.Format("ACTIVE ({0} d)", age),
                                    SizeBytes = sz,
                                    SizeDisplay = UninstallerService.FormatByteSize(sz),
                                    TargetPath = sd,
                                    ItemType = "DIR"
                                });
                            }
                            catch { }
                            continue;
                        }
                        queue.Enqueue(Tuple.Create(sd, depth + 1));
                    }
                }
            }

            // 4. Duplicate Media (SHA256 + Perceptual dHash)
            if (scanDuplicates)
            {
                if (statusProgress != null) statusProgress.Report("Scanning Duplicate Media (SHA256 + Perceptual Image dHash)...");
                var mediaRoots = new[] { Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), dlReal, dtReal }.Distinct(StringComparer.OrdinalIgnoreCase);
                var allFiles = new List<FileInfo>();
                foreach (var mr in mediaRoots)
                {
                    if (string.IsNullOrWhiteSpace(mr) || !Directory.Exists(mr)) continue;
                    try
                    {
                        foreach (var f in new DirectoryInfo(mr).EnumerateFiles("*", SearchOption.AllDirectories))
                        {
                            if (f.Length >= 102400L && f.FullName.IndexOf(@"\Sorted\", StringComparison.OrdinalIgnoreCase) < 0)
                            {
                                allFiles.Add(f);
                                if (allFiles.Count >= 2500) break;
                            }
                        }
                    }
                    catch { }
                }

                var seenDup = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                using (var sha = SHA256.Create())
                {
                    foreach (var grp in allFiles.GroupBy(x => x.Length).Where(g => g.Count() > 1))
                    {
                        var hashes = new Dictionary<string, string>();
                        foreach (var f in grp.OrderBy(x => x.LastWriteTime))
                        {
                            try
                            {
                                using (var fs = File.OpenRead(f.FullName))
                                {
                                    string h = BitConverter.ToString(sha.ComputeHash(fs));
                                    if (hashes.ContainsKey(h))
                                    {
                                        seenDup.Add(f.FullName);
                                        Emit(new BloatRadarItem
                                        {
                                            IsSelected = true,
                                            Category = "Exact Duplicate",
                                            StatusTag = "DUP OF " + hashes[h],
                                            SizeBytes = f.Length,
                                            SizeDisplay = UninstallerService.FormatByteSize(f.Length),
                                            TargetPath = f.FullName,
                                            ItemType = "FILE"
                                        });
                                    }
                                    else hashes[h] = f.Name;
                                }
                            }
                            catch { }
                        }
                    }
                }

                var dhashList = new List<Tuple<ulong, string>>();
                foreach (var im in allFiles.Where(f => !seenDup.Contains(f.FullName) && (f.Extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase) || f.Extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase) || f.Extension.Equals(".png", StringComparison.OrdinalIgnoreCase) || f.Extension.Equals(".bmp", StringComparison.OrdinalIgnoreCase))).Take(350))
                {
                    ulong? dh = GetImageDHash(im.FullName);
                    if (!dh.HasValue) continue;
                    var match = dhashList.FirstOrDefault(prev => HammingDistance64(dh.Value, prev.Item1) <= 4);
                    if (match != null)
                    {
                        Emit(new BloatRadarItem
                        {
                            IsSelected = false,
                            Category = "Similar Photo (dHash)",
                            StatusTag = "NEAR " + match.Item2,
                            SizeBytes = im.Length,
                            SizeDisplay = UninstallerService.FormatByteSize(im.Length),
                            TargetPath = im.FullName,
                            ItemType = "FILE"
                        });
                    }
                    else dhashList.Add(Tuple.Create(dh.Value, im.Name));
                }
            }

            return results.OrderByDescending(r => r.SizeBytes).ToList();
        }

        public static long CleanItems(List<BloatRadarItem> toClean, IProgress<string> statusProgress, IProgress<BloatRadarItem> removedProgress)
        {
            long freedTotal = 0;
            int idx = 0;
            foreach (var item in toClean)
            {
                idx++;
                if (statusProgress != null) statusProgress.Report(string.Format("Cleaning ({0} / {1}) : {2} | Reclaimed: {3}", idx, toClean.Count, item.TargetPath, UninstallerService.FormatByteSize(freedTotal)));
                if (UninstallerService.IsProtectedPath(item.TargetPath)) continue;
                try
                {
                    if (item.ItemType == "FILE")
                    {
                        if (File.Exists(item.TargetPath))
                        {
                            long sz = new FileInfo(item.TargetPath).Length;
                            File.SetAttributes(item.TargetPath, FileAttributes.Normal);
                            File.Delete(item.TargetPath);
                            freedTotal += sz;
                            if (removedProgress != null) removedProgress.Report(item);
                        }
                    }
                    else if (item.ItemType == "DIR_CONTENTS")
                    {
                        freedTotal += PcSpeedBoostService.CleanPathSafe(item.TargetPath, false);
                        if (removedProgress != null) removedProgress.Report(item);
                    }
                    else
                    {
                        if (Directory.Exists(item.TargetPath))
                        {
                            long before = item.SizeBytes;
                            try { Directory.Delete(item.TargetPath, true); } catch { }
                            long after = Directory.Exists(item.TargetPath) ? UninstallerService.GetDirectorySizeFast(item.TargetPath) : 0;
                            freedTotal += Math.Max(0, before - after);
                            if (!Directory.Exists(item.TargetPath)) if (removedProgress != null) removedProgress.Report(item);
                        }
                    }
                }
                catch { }
            }
            return freedTotal;
        }
    }
}
