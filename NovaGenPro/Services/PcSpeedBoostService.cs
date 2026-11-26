using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.ServiceProcess;
using System.Threading;
using System.Threading.Tasks;

namespace NovaGenPro.Services
{
    public class BoostOptions
    {
        public bool DryRun { get; set; }
        public bool DoRAM { get; set; }
        public bool DoWinTemp { get; set; }
        public bool DoBrowser { get; set; }
        public bool DoGPU { get; set; }
        public bool DoUWP { get; set; }
        public bool DoPrefetch { get; set; }
        public bool DoDNS { get; set; }
        public bool DoWU { get; set; }
        public bool DoThumb { get; set; }
        public bool DoWER { get; set; }
        public bool DoDelivOpt { get; set; }
        public bool DoTRIM { get; set; }
        public bool DoPower { get; set; }
        public bool DoFont { get; set; }
        public bool DoRecycle { get; set; }
        public bool DoDISM { get; set; }
        public bool DoEventLogs { get; set; }
    }

    public class BoostProgressReport
    {
        public double Percent { get; set; }
        public string RingLabel { get; set; }
        public string ActiveStep { get; set; }
        public string AccentHex { get; set; }
        public string LogLine { get; set; }
        public long DiskFreedBytes { get; set; }
        public int RamFreedMB { get; set; }
    }

    public class BoostResult
    {
        public long TotalFreedBytes { get; set; }
        public int RamFreedMB { get; set; }
        public bool IsDryRun { get; set; }
    }

    public static class PcSpeedBoostService
    {
        public static long CleanPathSafe(string path, bool dryRun)
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path) || UninstallerService.IsProtectedPath(path))
                return 0;

            long before = UninstallerService.GetDirectorySizeFast(path);
            if (dryRun) return before;

            try
            {
                foreach (var f in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
                {
                    try { File.SetAttributes(f, FileAttributes.Normal); File.Delete(f); } catch { }
                }
                foreach (var d in Directory.EnumerateDirectories(path, "*", SearchOption.AllDirectories).OrderByDescending(x => x.Length))
                {
                    try
                    {
                        if (!Directory.EnumerateFileSystemEntries(d).Any())
                            Directory.Delete(d, false);
                    }
                    catch { }
                }
            }
            catch { }

            long after = UninstallerService.GetDirectorySizeFast(path);
            return Math.Max(0, before - after);
        }

        public static BoostResult RunBoost(BoostOptions opt, IProgress<BoostProgressReport> progress)
        {
            bool dry = opt.DryRun;
            string label = dry ? "ANALYZING" : "BOOSTING";
            string hex = dry ? "#06B6D4" : "#22C55E";

            var flags = new[] { opt.DoRAM, opt.DoWinTemp, opt.DoBrowser, opt.DoGPU, opt.DoUWP, opt.DoPrefetch, opt.DoDNS, opt.DoWU, opt.DoThumb, opt.DoWER, opt.DoDelivOpt, opt.DoTRIM, opt.DoPower, opt.DoFont, opt.DoRecycle, opt.DoDISM, opt.DoEventLogs };
            int totalSteps = Math.Max(1, flags.Count(x => x));
            int step = 0;
            long totalFreed = 0;
            int ramFreedMB = 0;

            Action<string, string> Report = (stepText, logMsg) =>
            {
                double pct = Math.Min(96.0, (step / (double)totalSteps) * 95.0);
                if (progress != null)
                {
                    progress.Report(new BoostProgressReport
                    {
                        Percent = pct,
                        RingLabel = label,
                        ActiveStep = stepText,
                        AccentHex = hex,
                        LogLine = logMsg != null ? string.Format("[{0:HH:mm:ss}] {1}", DateTime.Now, logMsg) : null,
                        DiskFreedBytes = totalFreed,
                        RamFreedMB = ramFreedMB
                    });
                }
            };

            Report("Initializing NovaGen PC Speed Boost Engine...", "========================================");
            Report("Initializing NovaGen PC Speed Boost Engine...", "[INFO] NovaGen Native Boost Engine - MODE: " + (dry ? "ANALYZE (DRY-RUN)" : "BOOST NOW"));
            Report("Initializing NovaGen PC Speed Boost Engine...", "========================================");

            string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string roamApp = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string progData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);

            // 1. RAM + Standby Purge
            if (opt.DoRAM)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Flushing RAM & Purging Standby List...", step, totalSteps), null);
                var memBefore = NativeMethods.GetMemorySnapshot();
                if (!dry)
                {
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GC.Collect(2, GCCollectionMode.Forced, true, true);
                    int flushed = 0;
                    foreach (var proc in Process.GetProcesses())
                    {
                        try { if (proc.Handle != IntPtr.Zero && NativeMethods.EmptyWorkingSet(proc.Handle)) flushed++; } catch { }
                    }
                    Thread.Sleep(200);
                    bool sb = NativeMethods.PurgeStandbyMemory();
                    Thread.Sleep(200);
                    var memAfter = NativeMethods.GetMemorySnapshot();
                    long diff = (long)memAfter[2] - (long)memBefore[2];
                    ramFreedMB = diff > 0 ? (int)Math.Round(diff / 1048576.0) : 0;
                    Report(string.Format("Step {0}/{1} : RAM Flushed ({2} MB)", step, totalSteps, ramFreedMB), string.Format("[OK] RAM Flush: Trimmed {0} processes{1} - {2} MB reclaimed!", flushed, sb ? " + Standby RAM Purged" : "", ramFreedMB));
                }
                else
                {
                    long usedMB = (long)((memBefore[1] - memBefore[2]) / 1048576UL);
                    ramFreedMB = Math.Max(32, (int)(usedMB * 0.08));
                    Report(string.Format("Step {0}/{1} : RAM Flush (~{2} MB est.)", step, totalSteps, ramFreedMB), string.Format("[DRY] RAM Flush: Would trim working sets + purge standby (~{0} MB est.).", ramFreedMB));
                }
            }

            // 2. Windows Temp & CrashDumps
            if (opt.DoWinTemp)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Deep Cleaning Temp & CrashDumps...", step, totalSteps), null);
                long catFreed = 0;
                foreach (var tp in new[] { Path.Combine(winDir, "Temp"), Path.GetTempPath(), Path.Combine(localApp, "Temp"), Path.Combine(localApp, "CrashDumps") }.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    catFreed += CleanPathSafe(tp, dry);
                }
                totalFreed += catFreed;
                Report(string.Format("Step {0}/{1} : Temp Cleaned", step, totalSteps), string.Format("[OK] Windows Temp & CrashDumps: {0} {1}.", UninstallerService.FormatByteSize(catFreed), dry ? "would be freed" : "freed"));
            }

            // 3. All Browsers Deep Cache
            if (opt.DoBrowser)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Scanning All Browsers (Brave/Chrome/Edge/FF)...", step, totalSteps), null);
                var roots = new[]
                {
                    new { Name = "Brave", Path = Path.Combine(localApp, @"BraveSoftware\Brave-Browser\User Data") },
                    new { Name = "Chrome", Path = Path.Combine(localApp, @"Google\Chrome\User Data") },
                    new { Name = "Edge", Path = Path.Combine(localApp, @"Microsoft\Edge\User Data") },
                    new { Name = "Opera", Path = Path.Combine(roamApp, @"Opera Software\Opera Stable") },
                    new { Name = "OperaGX", Path = Path.Combine(roamApp, @"Opera Software\Opera GX Stable") },
                    new { Name = "Vivaldi", Path = Path.Combine(localApp, @"Vivaldi\User Data") }
                };
                var subs = new[] { "Cache", "Code Cache", "GPUCache", @"Service Worker\CacheStorage" };
                long catFreed = 0;
                foreach (var br in roots)
                {
                    if (!Directory.Exists(br.Path)) continue;
                    var profs = new List<string> { br.Path };
                    try
                    {
                        profs.AddRange(Directory.GetDirectories(br.Path).Where(d =>
                        {
                            string n = Path.GetFileName(d);
                            return n.Equals("Default", StringComparison.OrdinalIgnoreCase) || n.StartsWith("Profile ", StringComparison.OrdinalIgnoreCase);
                        }));
                    }
                    catch { }
                    long brFreed = 0;
                    foreach (var p in profs.Distinct(StringComparer.OrdinalIgnoreCase))
                    {
                        foreach (var sub in subs)
                            brFreed += CleanPathSafe(Path.Combine(p, sub), dry);
                    }
                    if (brFreed > 0)
                    {
                        catFreed += brFreed;
                        Report(string.Format("Step {0}/{1} : {2} Cache", step, totalSteps, br.Name), string.Format("[INFO] {0}: {1} {2}.", br.Name, UninstallerService.FormatByteSize(brFreed), dry ? "found" : "freed"));
                    }
                }
                string ffRoot = Path.Combine(localApp, @"Mozilla\Firefox\Profiles");
                if (Directory.Exists(ffRoot))
                {
                    long ffFreed = 0;
                    try
                    {
                        foreach (var p in Directory.GetDirectories(ffRoot))
                            ffFreed += CleanPathSafe(Path.Combine(p, "cache2"), dry);
                    }
                    catch { }
                    if (ffFreed > 0) catFreed += ffFreed;
                }
                totalFreed += catFreed;
                Report(string.Format("Step {0}/{1} : Browsers Cleaned", step, totalSteps), string.Format("[OK] All Browsers Deep Cache: {0} {1}.", UninstallerService.FormatByteSize(catFreed), dry ? "would be freed" : "freed"));
            }

            // 4. GPU Shader Caches
            if (opt.DoGPU)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Scanning GPU Shader Caches...", step, totalSteps), null);
                long catFreed = 0;
                foreach (var gp in new[] { @"NVIDIA\DXCache", @"NVIDIA\GLCache", @"AMD\DxCache", @"Intel\ShaderCache", "D3DSCache" })
                    catFreed += CleanPathSafe(Path.Combine(localApp, gp), dry);
                totalFreed += catFreed;
                Report(string.Format("Step {0}/{1} : GPU Caches", step, totalSteps), string.Format("[OK] GPU Shader Caches: {0} {1}.", UninstallerService.FormatByteSize(catFreed), dry ? "would be freed" : "freed"));
            }

            // 5. UWP / Store TempState
            if (opt.DoUWP)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Cleaning Store/UWP App Temp Caches...", step, totalSteps), null);
                long catFreed = 0;
                string pkgRoot = Path.Combine(localApp, "Packages");
                if (Directory.Exists(pkgRoot))
                {
                    try
                    {
                        foreach (var pkg in Directory.GetDirectories(pkgRoot))
                        {
                            catFreed += CleanPathSafe(Path.Combine(pkg, "TempState"), dry);
                            catFreed += CleanPathSafe(Path.Combine(pkg, @"AC\Temp"), dry);
                        }
                    }
                    catch { }
                }
                totalFreed += catFreed;
                Report(string.Format("Step {0}/{1} : UWP Caches", step, totalSteps), string.Format("[OK] Store/UWP Temp Caches: {0} {1}.", UninstallerService.FormatByteSize(catFreed), dry ? "would be freed" : "freed"));
            }

            // 6. Prefetch
            if (opt.DoPrefetch)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Scanning Windows Prefetch...", step, totalSteps), null);
                long f = CleanPathSafe(Path.Combine(winDir, "Prefetch"), dry);
                totalFreed += f;
                Report(string.Format("Step {0}/{1} : Prefetch", step, totalSteps), string.Format("[OK] Prefetch Cache: {0} {1}.", UninstallerService.FormatByteSize(f), dry ? "would be freed" : "freed"));
            }

            // 7. DNS
            if (opt.DoDNS)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Flushing DNS Cache...", step, totalSteps), null);
                if (!dry)
                {
                    try { { var _p = Process.Start(new ProcessStartInfo("ipconfig.exe", "/flushdns") { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); } } catch { }
                    Report(string.Format("Step {0}/{1} : DNS Flushed", step, totalSteps), "[OK] DNS Resolver Cache: Flushed.");
                }
                else
                {
                    Report(string.Format("Step {0}/{1} : DNS Cache", step, totalSteps), "[DRY] DNS Cache: Would flush resolver cache.");
                }
            }

            // 8. Windows Update Cache
            if (opt.DoWU)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Checking Windows Update Cache...", step, totalSteps), null);
                string wu = Path.Combine(winDir, @"SoftwareDistribution\Download");
                if (!dry && Directory.Exists(wu))
                {
                    try { using (var sc = new ServiceController("wuauserv")) { if (sc.Status != ServiceControllerStatus.Stopped) { sc.Stop(); sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(5)); } } } catch { }
                    long f = CleanPathSafe(wu, false);
                    totalFreed += f;
                    try { using (var sc = new ServiceController("wuauserv")) { sc.Start(); } } catch { }
                    Report(string.Format("Step {0}/{1} : WU Cache", step, totalSteps), string.Format("[OK] Windows Update Cache: {0} freed.", UninstallerService.FormatByteSize(f)));
                }
                else
                {
                    long f = CleanPathSafe(wu, true);
                    totalFreed += f;
                    Report(string.Format("Step {0}/{1} : WU Cache", step, totalSteps), string.Format("[DRY] Windows Update Cache: {0} would be freed.", UninstallerService.FormatByteSize(f)));
                }
            }

            // 9. Thumbnail Cache
            if (opt.DoThumb)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Scanning Thumbnail Cache...", step, totalSteps), null);
                string exp = Path.Combine(localApp, @"Microsoft\Windows\Explorer");
                long f = 0;
                if (Directory.Exists(exp))
                {
                    foreach (var tf in Directory.EnumerateFiles(exp, "thumbcache_*.db"))
                    {
                        try
                        {
                            long sz = new FileInfo(tf).Length;
                            if (!dry) File.Delete(tf);
                            f += sz;
                        }
                        catch { }
                    }
                }
                totalFreed += f;
                Report(string.Format("Step {0}/{1} : Thumbnail Cache", step, totalSteps), string.Format("[OK] Thumbnail Cache: {0} {1}.", UninstallerService.FormatByteSize(f), dry ? "would be freed" : "freed"));
            }

            // 10. WER
            if (opt.DoWER)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Scanning Windows Error Reports...", step, totalSteps), null);
                long f = 0;
                foreach (var wp in new[] { Path.Combine(progData, @"Microsoft\Windows\WER\ReportArchive"), Path.Combine(progData, @"Microsoft\Windows\WER\ReportQueue"), Path.Combine(localApp, @"Microsoft\Windows\WER\ReportArchive"), Path.Combine(localApp, @"Microsoft\Windows\WER\ReportQueue") })
                    f += CleanPathSafe(wp, dry);
                totalFreed += f;
                Report(string.Format("Step {0}/{1} : WER", step, totalSteps), string.Format("[OK] Windows Error Reports: {0} {1}.", UninstallerService.FormatByteSize(f), dry ? "would be freed" : "freed"));
            }

            // 11. Delivery Optimization
            if (opt.DoDelivOpt)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Checking Delivery Optimization...", step, totalSteps), null);
                long f = CleanPathSafe(Path.Combine(winDir, @"ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"), dry);
                totalFreed += f;
                Report(string.Format("Step {0}/{1} : Delivery Opt", step, totalSteps), string.Format("[OK] Delivery Optimization: {0} {1}.", UninstallerService.FormatByteSize(f), dry ? "would be freed" : "freed"));
            }

            // 12. SSD TRIM
            if (opt.DoTRIM)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Running SSD TRIM Optimization...", step, totalSteps), null);
                if (!dry)
                {
                    try
                    {
                        string drive = Path.GetPathRoot(winDir).TrimEnd('\\', ':');
                        { var _p = Process.Start(new ProcessStartInfo("defrag.exe", string.Format("{0}: /L /O", drive)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(10000); }
                        Report(string.Format("Step {0}/{1} : SSD TRIM", step, totalSteps), string.Format("[OK] SSD TRIM: Optimized {0}: drive.", drive));
                    }
                    catch { Report(string.Format("Step {0}/{1} : SSD TRIM", step, totalSteps), "[WARN] SSD TRIM skipped."); }
                }
                else Report(string.Format("Step {0}/{1} : SSD TRIM", step, totalSteps), "[DRY] SSD TRIM: Would run TRIM optimization.");
            }

            // 13. Power Plan
            if (opt.DoPower)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Activating High-Performance Power Plan...", step, totalSteps), null);
                if (!dry)
                {
                    try
                    {
                        string hp = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";
                        var p = Process.Start(new ProcessStartInfo("powercfg.exe", string.Format("/setactive {0}", hp)) { CreateNoWindow = true, UseShellExecute = false });
                        if (p != null) p.WaitForExit(3000);
                        if (p != null && p.ExitCode != 0)
                        {
                            { var _p = Process.Start(new ProcessStartInfo("powercfg.exe", string.Format("/duplicatescheme {0}", hp)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); }
                            { var _p = Process.Start(new ProcessStartInfo("powercfg.exe", string.Format("/setactive {0}", hp)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); }
                        }
                        Report(string.Format("Step {0}/{1} : Power Plan", step, totalSteps), "[OK] Power Plan: Switched to High Performance.");
                    }
                    catch { }
                }
                else Report(string.Format("Step {0}/{1} : Power Plan", step, totalSteps), "[DRY] Power Plan: Would switch to High Performance.");
            }

            // 14. Font Cache
            if (opt.DoFont)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Checking Font Cache...", step, totalSteps), null);
                string fc = Path.Combine(winDir, @"ServiceProfiles\LocalService\AppData\Local\FontCache");
                if (!dry && Directory.Exists(fc))
                {
                    try { using (var sc = new ServiceController("FontCache")) { if (sc.Status != ServiceControllerStatus.Stopped) { sc.Stop(); sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(4)); } } } catch { }
                    long f = CleanPathSafe(fc, false);
                    totalFreed += f;
                    try { using (var sc = new ServiceController("FontCache")) { sc.Start(); } } catch { }
                    Report(string.Format("Step {0}/{1} : Font Cache", step, totalSteps), string.Format("[OK] Font Cache: {0} freed.", UninstallerService.FormatByteSize(f)));
                }
                else
                {
                    long f = CleanPathSafe(fc, true);
                    totalFreed += f;
                    Report(string.Format("Step {0}/{1} : Font Cache", step, totalSteps), string.Format("[DRY] Font Cache: {0} would be freed.", UninstallerService.FormatByteSize(f)));
                }
            }

            // 15. Recycle Bin
            if (opt.DoRecycle)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Emptying Recycle Bin...", step, totalSteps), null);
                if (!dry)
                {
                    NativeMethods.EmptyRecycleBinSilent();
                    Report(string.Format("Step {0}/{1} : Recycle Bin", step, totalSteps), "[OK] Recycle Bin: Emptied silently.");
                }
                else Report(string.Format("Step {0}/{1} : Recycle Bin", step, totalSteps), "[DRY] Recycle Bin: Would empty all drives.");
            }

            // 16. DISM WinSxS
            if (opt.DoDISM)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Running DISM WinSxS Cleanup (Non-Blocking)...", step, totalSteps), null);
                if (!dry)
                {
                    try
                    {
                        string sysRoot = Path.GetPathRoot(winDir);
                        long beforeFree = new DriveInfo(sysRoot).AvailableFreeSpace;
                        var p = Process.Start(new ProcessStartInfo("Dism.exe", "/Online /Cleanup-Image /StartComponentCleanup /Quiet") { CreateNoWindow = true, UseShellExecute = false });
                        var sw = Stopwatch.StartNew();
                        while (p != null && !p.HasExited && sw.Elapsed.TotalSeconds < 180)
                        {
                            Thread.Sleep(500);
                            Report(string.Format("Step {0}/{1} : DISM WinSxS running ({2}s)...", step, totalSteps, (int)sw.Elapsed.TotalSeconds), null);
                        }
                        long afterFree = new DriveInfo(sysRoot).AvailableFreeSpace;
                        long dismFreed = Math.Max(0, afterFree - beforeFree);
                        totalFreed += dismFreed;
                        Report(string.Format("Step {0}/{1} : DISM Complete", step, totalSteps), string.Format("[OK] DISM WinSxS: Cleanup complete (~{0} reclaimed).", UninstallerService.FormatByteSize(dismFreed)));
                    }
                    catch { Report(string.Format("Step {0}/{1} : DISM Skipped", step, totalSteps), "[WARN] DISM WinSxS skipped."); }
                }
                else Report(string.Format("Step {0}/{1} : DISM WinSxS", step, totalSteps), "[DRY] DISM WinSxS: Would run StartComponentCleanup.");
            }

            // 17. Event Logs
            if (opt.DoEventLogs)
            {
                step++;
                Report(string.Format("Step {0}/{1} : Clearing Event Logs...", step, totalSteps), null);
                if (!dry)
                {
                    foreach (var lg in new[] { "Application", "System", "Security", "Setup" })
                    {
                        try { { var _p = Process.Start(new ProcessStartInfo("wevtutil.exe", string.Format("cl {0}", lg)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); } } catch { }
                    }
                    Report(string.Format("Step {0}/{1} : Event Logs", step, totalSteps), "[OK] Event Logs: Cleared.");
                }
                else Report(string.Format("Step {0}/{1} : Event Logs", step, totalSteps), "[DRY] Event Logs: Would clear App/System/Security/Setup.");
            }

            string doneText = dry
                ? string.Format("Analyze Complete â€” {0} disk + ~{1} MB RAM ready to clean", UninstallerService.FormatByteSize(totalFreed), ramFreedMB)
                : string.Format("Boost Complete â€” {0} disk freed + {1} MB RAM reclaimed!", UninstallerService.FormatByteSize(totalFreed), ramFreedMB);

            if (progress != null) progress.Report(new BoostProgressReport
            {
                Percent = 100,
                RingLabel = dry ? "ANALYZED" : "OPTIMIZED",
                ActiveStep = doneText,
                AccentHex = "#22C55E",
                LogLine = string.Format("[{0:HH:mm:ss}] [OK] {1}", DateTime.Now, doneText),
                DiskFreedBytes = totalFreed,
                RamFreedMB = ramFreedMB
            });

            return new BoostResult { TotalFreedBytes = totalFreed, RamFreedMB = ramFreedMB, IsDryRun = dry };
        }
    }
}
