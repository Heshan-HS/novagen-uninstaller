using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Principal;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using NovaGenPro.Models;
using NovaGenPro.Services;

namespace NovaGenPro
{
    public partial class MainWindow : Window
    {
        private readonly string _appRoot;
        private readonly string _backupRoot;
        private readonly string _snapshotRoot;
        private readonly string _logRoot;

        private List<InstalledAppItem> _allAppsCache = new List<InstalledAppItem>();
        private List<StoreAppItem> _allStoreCache = new List<StoreAppItem>();
        private List<GhostItem> _ghostCache = new List<GhostItem>();
        private readonly ObservableCollection<LeftoverItem> _leftoverItems = new ObservableCollection<LeftoverItem>();
        private readonly ObservableCollection<BloatRadarItem> _bloatRadarItems = new ObservableCollection<BloatRadarItem>();
        private readonly WatchdogService _watchdog = new WatchdogService();
        private DispatcherTimer _watchdogTimer;

        private long _sessionReclaimedBytes = 0;
        private string _currentAppFilter = "ALL";
        private string _currentSortMode = "NAME_ASC";
        private string _currentTheme = "DARK";
        private double _currentBoostPct = 0.0;
        private System.Windows.Forms.NotifyIcon _trayIcon;

        public MainWindow()
        {
            InitializeComponent();

            _appRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NovaGen");
            _backupRoot = Path.Combine(_appRoot, "Backups");
            _snapshotRoot = Path.Combine(_appRoot, "Snapshots");
            _logRoot = Path.Combine(_appRoot, "Logs");
            Directory.CreateDirectory(_backupRoot);
            Directory.CreateDirectory(_snapshotRoot);
            Directory.CreateDirectory(_logRoot);
            LblBackupPathInfo.Text = "Backups: " + _backupRoot;

            LoadEmbeddedIcon();
            CheckAdminBadge();
            SetupTrayIcon();

            GridLeftovers.ItemsSource = _leftoverItems;
            GridBloatRadar.ItemsSource = _bloatRadarItems;

            WireEvents();
            Loaded += async (s, e) => await InvokeFullSystemIndexAsync();
            Closing += (s, e) =>
            {
                _watchdog.Dispose();
                if (_watchdogTimer != null) _watchdogTimer.Stop();
                if (_trayIcon != null) { _trayIcon.Visible = false; _trayIcon.Dispose(); }
            };
        }

        private void LoadEmbeddedIcon()
        {
            try
            {
                var streamInfo = Application.GetResourceStream(new Uri("pack://application:,,,/NovaGen.ico"));
                if (streamInfo != null)
                {
                    using (var ico = new System.Drawing.Icon(streamInfo.Stream, 64, 64))
                    {
                        var bmpSrc = Imaging.CreateBitmapSourceFromHIcon(ico.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                        Icon = bmpSrc;
                        ImgHeaderLogo.Source = bmpSrc;
                    }
                }
            }
            catch { }
        }

        private void CheckAdminBadge()
        {
            try
            {
                bool isAdmin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
                if (!isAdmin)
                {
                    AdminBadgeText.Text = "LIMITED USER MODE";
                    AdminBadgeBorder.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#451A03"));
                    AdminBadgeBorder.BorderBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#D97706"));
                    AdminDot.Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#F59E0B"));
                    AdminBadgeText.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#FBBF24"));
                }
            }
            catch { }
        }

        private void SetupTrayIcon()
        {
            try
            {
                _trayIcon = new System.Windows.Forms.NotifyIcon
                {
                    Text = "NovaGen Pro v5.0",
                    Visible = true
                };
                var streamInfo = Application.GetResourceStream(new Uri("pack://application:,,,/NovaGen.ico"));
                if (streamInfo != null)
                    _trayIcon.Icon = new System.Drawing.Icon(streamInfo.Stream);
                _trayIcon.DoubleClick += (s, e) =>
                {
                    Show();
                    WindowState = WindowState.Normal;
                    Activate();
                };
            }
            catch { }
        }

        private void WriteNovaLog(string msg)
        {
            string line = string.Format("[{0:HH:mm:ss}] {1}", DateTime.Now, msg);
            TxtExecutionLog.AppendText(line + Environment.NewLine);
            TxtExecutionLog.ScrollToEnd();
            LblStatusBar.Text = msg;
        }

        private void SwitchWorkspaceView(string viewName)
        {
            var views = new[] { ViewInstalledApps, ViewStoreApps, ViewGhostSweeper, ViewCustomHunter, ViewSnapshotTracker, ViewPCBoost, ViewBloatRadar, ViewWatchdog };
            foreach (var v in views)
                v.Visibility = (v.Name == viewName) ? Visibility.Visible : Visibility.Collapsed;

            if (viewName == "ViewPCBoost")
            {
                Grid.SetColumnSpan(PaneCenterWorkspace, 1);
                PaneCenterWorkspace.Margin = new Thickness(0, 0, 10, 0);
                PaneRightInspector.Visibility = Visibility.Collapsed;
                PaneRightBoostIntel.Visibility = Visibility.Visible;
            }
            else if (viewName == "ViewBloatRadar" || viewName == "ViewWatchdog")
            {
                Grid.SetColumnSpan(PaneCenterWorkspace, 2);
                PaneCenterWorkspace.Margin = new Thickness(0);
                PaneRightInspector.Visibility = Visibility.Collapsed;
                PaneRightBoostIntel.Visibility = Visibility.Collapsed;
            }
            else
            {
                PaneRightBoostIntel.Visibility = Visibility.Collapsed;
                // Auto-show Leftover Inspector ONLY if leftovers are loaded; otherwise keep hidden for full width!
                if (_leftoverItems.Count > 0) ShowLeftoverInspector();
                else HideLeftoverInspector();
            }
        }

        private void ShowLeftoverInspector()
        {
            Grid.SetColumnSpan(PaneCenterWorkspace, 1);
            PaneCenterWorkspace.Margin = new Thickness(0, 0, 10, 0);
            PaneRightInspector.Visibility = Visibility.Visible;
        }

        private void HideLeftoverInspector()
        {
            PaneRightInspector.Visibility = Visibility.Collapsed;
            Grid.SetColumnSpan(PaneCenterWorkspace, 2);
            PaneCenterWorkspace.Margin = new Thickness(0);
        }

        private void UpdateSystemTelemetry()
        {
            int win32Count = _allAppsCache.Count;
            int storeCount = _allStoreCache.Count;
            KpiAppCount.Text = (win32Count + storeCount).ToString();
            KpiAppSub.Text = string.Format("({0} Win32 Â· {1} Store)", win32Count, storeCount);

            long totBytes = _allAppsCache.Sum(a => a.SizeBytes);
            KpiTotalSize.Text = UninstallerService.FormatByteSize(totBytes);

            try
            {
                var drv = new DriveInfo(Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)));
                KpiDriveFree.Text = UninstallerService.FormatByteSize(drv.AvailableFreeSpace);
                KpiDriveSub.Text = "/ " + UninstallerService.FormatByteSize(drv.TotalSize);
            }
            catch { }

            var selItems = _leftoverItems.Where(i => i.IsSelected).ToList();
            long selBytes = selItems.Sum(i => i.SizeBytes);
            KpiLeftoverCount.Text = _leftoverItems.Count.ToString();
            KpiLeftoverSize.Text = string.Format("({0} selected)", UninstallerService.FormatByteSize(selBytes));
            KpiReclaimed.Text = UninstallerService.FormatByteSize(_sessionReclaimedBytes);

            int fsCount = _leftoverItems.Count(i => i.ItemType == "FOLDER" || i.ItemType == "FILE");
            int regCount = _leftoverItems.Count(i => i.ItemType.StartsWith("REG"));
            int svcCount = _leftoverItems.Count(i => i.ItemType == "SERVICE" || i.ItemType == "TASK");
            LblStatFiles.Text = string.Format("FS: {0} folders/files", fsCount);
            LblStatReg.Text = string.Format("REG: {0} keys/vals", regCount);
            LblStatSvc.Text = string.Format("SVC/TASK: {0}", svcCount);
            BtnNukeSelected.Content = string.Format("100% WIPE & NUKE SELECTED LEFTOVERS ({0} ITEMS)", selItems.Count);
        }

        private async Task InvokeFullSystemIndexAsync()
        {
            WriteNovaLog("Indexing installed Win32 applications across HKLM (x64/x86) and HKCU hives...");
            _allAppsCache = await Task.Run(() => UninstallerService.GetAllInstalledApps());
            ApplyInstalledAppsFilter();
            UpdateSystemTelemetry();
            WriteNovaLog(string.Format("Indexed {0} applications. Ready for 100% Zero-Trace Deep Uninstall.", _allAppsCache.Count));
        }

        private void ApplyInstalledAppsFilter()
        {
            string q = (TxtSearchApps.Text ?? "").Trim().ToLowerInvariant();
            IEnumerable<InstalledAppItem> filtered = _allAppsCache;
            if (_currentAppFilter == "DESKTOP") filtered = filtered.Where(a => a.Category == "Desktop App");
            else if (_currentAppFilter == "USER") filtered = filtered.Where(a => a.Category == "User App");
            if (!string.IsNullOrEmpty(q))
                filtered = filtered.Where(a => a.DisplayName.ToLowerInvariant().Contains(q) || a.Publisher.ToLowerInvariant().Contains(q) || a.InstallLocation.ToLowerInvariant().Contains(q));

            filtered = _currentSortMode == "SIZE_DESC"
                ? filtered.OrderByDescending(a => a.SizeBytes)
                : filtered.OrderBy(a => a.DisplayName, StringComparer.OrdinalIgnoreCase);

            GridInstalledApps.ItemsSource = filtered.ToList();
        }

        private void SetTheme(string mode)
        {
            var res = Resources;
            var bc = new BrushConverter();
            if (mode == "LIGHT")
            {
                var grad = new LinearGradientBrush
                {
                    StartPoint = new Point(0, 0),
                    EndPoint = new Point(1, 1)
                };
                grad.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString("#DBEAFE"), 0.0));
                grad.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString("#EFF6FF"), 0.5));
                grad.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString("#E0E7FF"), 1.0));
                Background = grad;
                Foreground = (Brush)bc.ConvertFromString("#0F172A");

                res["CanvasBrush"] = (Brush)bc.ConvertFromString("#EFF6FF");
                res["SurfaceBrush"] = (Brush)bc.ConvertFromString("#FFFFFF");
                res["ElevatedBrush"] = (Brush)bc.ConvertFromString("#F1F5F9");
                res["RecessedBrush"] = (Brush)bc.ConvertFromString("#E2E8F0");
                res["BorderBrush"] = (Brush)bc.ConvertFromString("#CBD5E1");
                res["PrimaryInk"] = (Brush)bc.ConvertFromString("#0F172A");
                res["SecondaryInk"] = (Brush)bc.ConvertFromString("#334155");
                res["MutedInk"] = (Brush)bc.ConvertFromString("#64748B");
                res["AccentCobalt"] = (Brush)bc.ConvertFromString("#1D4ED8");
                res["AccentCobaltHover"] = (Brush)bc.ConvertFromString("#1E40AF");
                res["AccentCyan"] = (Brush)bc.ConvertFromString("#0284C7");

                BtnThemeLight.Background = (Brush)bc.ConvertFromString("#1D4ED8");
                BtnThemeLight.Foreground = Brushes.White;
                BtnThemeDark.Background = (Brush)bc.ConvertFromString("#1E293B");
                BtnThemeDark.Foreground = (Brush)bc.ConvertFromString("#94A3B8");
                _currentTheme = "LIGHT";
            }
            else
            {
                Background = (Brush)bc.ConvertFromString("#060B16");
                Foreground = (Brush)bc.ConvertFromString("#F8FAFC");

                res["CanvasBrush"] = (Brush)bc.ConvertFromString("#060B16");
                res["SurfaceBrush"] = (Brush)bc.ConvertFromString("#0B1220");
                res["ElevatedBrush"] = (Brush)bc.ConvertFromString("#111C33");
                res["RecessedBrush"] = (Brush)bc.ConvertFromString("#040811");
                res["BorderBrush"] = (Brush)bc.ConvertFromString("#1E293B");
                res["PrimaryInk"] = (Brush)bc.ConvertFromString("#F8FAFC");
                res["SecondaryInk"] = (Brush)bc.ConvertFromString("#94A3B8");
                res["MutedInk"] = (Brush)bc.ConvertFromString("#64748B");
                res["AccentCobalt"] = (Brush)bc.ConvertFromString("#2563EB");
                res["AccentCobaltHover"] = (Brush)bc.ConvertFromString("#1D4ED8");
                res["AccentCyan"] = (Brush)bc.ConvertFromString("#22D3EE");

                BtnThemeDark.Background = (Brush)bc.ConvertFromString("#2563EB");
                BtnThemeDark.Foreground = Brushes.White;
                BtnThemeLight.Background = (Brush)bc.ConvertFromString("#111C33");
                BtnThemeLight.Foreground = (Brush)bc.ConvertFromString("#94A3B8");
                _currentTheme = "DARK";
            }
            WriteNovaLog("Switched to " + (_currentTheme == "LIGHT" ? "Enterprise Light" : "Dark Obsidian NOC") + " Mode.");
        }

        private void WireEvents()
        {
            BtnThemeLight.Click += (s, e) => SetTheme("LIGHT");
            BtnThemeDark.Click += (s, e) => SetTheme("DARK");
            BtnOpenBackups.Click += (s, e) => Process.Start("explorer.exe", _backupRoot);
            BtnRefreshAll.Click += async (s, e) => await InvokeFullSystemIndexAsync();
            BtnHideInspector.Click += (s, e) => HideLeftoverInspector();

            // Navigation
            NavBtnApps.Click += (s, e) => SwitchWorkspaceView("ViewInstalledApps");
            NavBtnStore.Click += async (s, e) =>
            {
                SwitchWorkspaceView("ViewStoreApps");
                if (_allStoreCache.Count == 0)
                {
                    WriteNovaLog("Loading Windows Store & UWP Packages...");
                    _allStoreCache = await Task.Run(() => UninstallerService.GetAllStoreApps());
                    GridStoreApps.ItemsSource = _allStoreCache;
                    UpdateSystemTelemetry();
                    WriteNovaLog(string.Format("Loaded {0} removable Store/UWP packages.", _allStoreCache.Count));
                }
            };
            NavBtnGhost.Click += (s, e) => SwitchWorkspaceView("ViewGhostSweeper");
            NavBtnHunter.Click += (s, e) => SwitchWorkspaceView("ViewCustomHunter");
            NavBtnSnapshot.Click += (s, e) => { SwitchWorkspaceView("ViewSnapshotTracker"); RefreshSnapshotsList(); };
            NavBtnBoost.Click += (s, e) =>
            {
                SwitchWorkspaceView("ViewPCBoost");
                bool idle = TxtBoostStatus.Text == "READY";
                UpdateBoostRamTelemetry(idle);
                UpdateBoostCommandCenter();
            };
            NavBtnBloatRadar.Click += (s, e) => SwitchWorkspaceView("ViewBloatRadar");
            NavBtnWatchdog.Click += (s, e) => SwitchWorkspaceView("ViewWatchdog");

            // Installed Apps Filter & Sort
            TxtSearchApps.TextChanged += (s, e) => ApplyInstalledAppsFilter();
            BtnFilterAll.Click += (s, e) => { _currentAppFilter = "ALL"; ApplyInstalledAppsFilter(); };
            BtnFilterDesktop.Click += (s, e) => { _currentAppFilter = "DESKTOP"; ApplyInstalledAppsFilter(); };
            BtnFilterUser.Click += (s, e) => { _currentAppFilter = "USER"; ApplyInstalledAppsFilter(); };
            BtnSortSize.Click += (s, e) => { _currentSortMode = "SIZE_DESC"; ApplyInstalledAppsFilter(); };
            BtnSortName.Click += (s, e) => { _currentSortMode = "NAME_ASC"; ApplyInstalledAppsFilter(); };
            BtnCalcSizes.Click += async (s, e) =>
            {
                BtnCalcSizes.IsEnabled = false;
                WriteNovaLog("Calculating exact folder sizes...");
                await Task.Run(() =>
                {
                    foreach (var app in _allAppsCache)
                    {
                        if (!string.IsNullOrWhiteSpace(app.InstallLocation) && Directory.Exists(app.InstallLocation))
                        {
                            long sz = UninstallerService.GetDirectorySizeFast(app.InstallLocation);
                            if (sz > 0)
                            {
                                app.SizeBytes = sz;
                                app.SizeDisplay = UninstallerService.FormatByteSize(sz);
                            }
                        }
                    }
                });
                ApplyInstalledAppsFilter();
                UpdateSystemTelemetry();
                BtnCalcSizes.IsEnabled = true;
                WriteNovaLog("Exact folder size calculation complete.");
            };

            GridInstalledApps.SelectionChanged += (s, e) =>
            {
                var sel = GridInstalledApps.SelectedItem as InstalledAppItem;
                if (sel == null) return;
                LblSelectedAppName.Text = string.Format("{0} (v{1} â€” {2})", sel.DisplayName, sel.DisplayVersion, sel.Publisher);
                LblSelectedAppMeta.Text = "Path: " + (string.IsNullOrWhiteSpace(sel.InstallLocation) ? sel.RegistryPath : sel.InstallLocation);
                LblSelectedAppArch.Text = string.Format("{0} // {1}", sel.Arch, sel.Category);
            };

            BtnOpenInstallDir.Click += (s, e) =>
            {
                var sel = GridInstalledApps.SelectedItem as InstalledAppItem;
                if (sel != null && Directory.Exists(sel.InstallLocation))
                    Process.Start("explorer.exe", sel.InstallLocation);
            };

            BtnDeepScanOnly.Click += async (s, e) =>
            {
                var sel = GridInstalledApps.SelectedItem as InstalledAppItem;
                if (sel == null) { MessageBox.Show(this, "Select an application first.", "NovaGen", MessageBoxButton.OK, MessageBoxImage.Information); return; }
                await RunDeepScanIntoInspectorAsync(sel.DisplayName, sel.Publisher, sel.InstallLocation, sel.RegistryPath);
            };

            BtnFullDeepUninstall.Click += async (s, e) =>
            {
                var sel = GridInstalledApps.SelectedItem as InstalledAppItem;
                if (sel == null) { MessageBox.Show(this, "Select an application first.", "NovaGen", MessageBoxButton.OK, MessageBoxImage.Information); return; }
                if (MessageBox.Show(this, string.Format("Run native uninstaller + 18-Point Deep Leftover Scan for '{0}'?", sel.DisplayName), "NovaGen // Deep Uninstall", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
                    return;
                string cmd = !string.IsNullOrWhiteSpace(sel.QuietUninstallString) ? sel.QuietUninstallString : sel.UninstallString;
                if (!string.IsNullOrWhiteSpace(cmd))
                {
                    WriteNovaLog(string.Format("Launching uninstaller for {0}...", sel.DisplayName));
                    try
                    {
                        var p = Process.Start(new ProcessStartInfo("cmd.exe", "/c " + cmd) { UseShellExecute = true });
                        if (p != null) await Task.Run(() => p.WaitForExit(120000));
                    }
                    catch { }
                }
                await RunDeepScanIntoInspectorAsync(sel.DisplayName, sel.Publisher, sel.InstallLocation, sel.RegistryPath);
            };

            // Leftover Inspector Actions
            BtnSelectAllLeftovers.Click += (s, e) => { foreach (var i in _leftoverItems) i.IsSelected = true; UpdateSystemTelemetry(); };
            BtnSelectNoneLeftovers.Click += (s, e) => { foreach (var i in _leftoverItems) i.IsSelected = false; UpdateSystemTelemetry(); };
            BtnNukeSelected.Click += async (s, e) =>
            {
                var sel = _leftoverItems.Where(i => i.IsSelected).ToList();
                if (sel.Count == 0) return;
                if (MessageBox.Show(this, string.Format("100% WIPE {0} selected leftover item(s)?\n\nRegistry backups are saved automatically to Backups\\.", sel.Count), "NovaGen // Zero-Trace Wipe", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
                    return;
                BtnNukeSelected.IsEnabled = false;
                long reclaimed = await Task.Run(() => UninstallerService.WipeLeftovers(sel, _backupRoot, m => Dispatcher.Invoke(() => WriteNovaLog(m))));
                foreach (var it in sel) _leftoverItems.Remove(it);
                _sessionReclaimedBytes += reclaimed;
                UpdateSystemTelemetry();
                BtnNukeSelected.IsEnabled = true;
                WriteNovaLog(string.Format("Wipe complete! Reclaimed {0}.", UninstallerService.FormatByteSize(reclaimed)));
            };

            // Store Apps
            TxtSearchStore.TextChanged += (s, e) =>
            {
                string q = (TxtSearchStore.Text ?? "").Trim().ToLowerInvariant();
                GridStoreApps.ItemsSource = string.IsNullOrEmpty(q) ? _allStoreCache : _allStoreCache.Where(x => x.Name.ToLowerInvariant().Contains(q) || x.Publisher.ToLowerInvariant().Contains(q)).ToList();
            };
            BtnUninstallStoreApp.Click += async (s, e) =>
            {
                var sel = GridStoreApps.SelectedItem as StoreAppItem;
                if (sel == null) return;
                if (MessageBox.Show(this, string.Format("Remove Store/UWP app '{0}'?", sel.Name), "NovaGen // Store Remover", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
                WriteNovaLog(string.Format("Removing Store package {0}...", sel.Name));
                await Task.Run(() => { var _p = Process.Start(new ProcessStartInfo("powershell.exe", string.Format("-NoProfile -Command \"Remove-AppxPackage -Package '{0}'\"", sel.PackageFullName)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(30000); });
                _allStoreCache.Remove(sel);
                GridStoreApps.ItemsSource = _allStoreCache.ToList();
                await RunDeepScanIntoInspectorAsync(sel.Name, sel.Publisher, sel.InstallLocation, "");
            };

            // Ghost Sweeper
            BtnRunGhostScan.Click += async (s, e) =>
            {
                BtnRunGhostScan.IsEnabled = false;
                WriteNovaLog("Scanning for orphaned Ghost folders...");
                _ghostCache = await Task.Run(() => UninstallerService.ScanGhostFolders(_allAppsCache));
                GridGhostItems.ItemsSource = _ghostCache;
                BtnRunGhostScan.IsEnabled = true;
                WriteNovaLog(string.Format("Ghost scan complete: Found {0} orphaned folders.", _ghostCache.Count));
            };
            BtnSendGhostToInspector.Click += (s, e) =>
            {
                var sel = GridGhostItems.SelectedItem as GhostItem;
                if (sel == null) return;
                _leftoverItems.Clear();
                _leftoverItems.Add(new LeftoverItem { IsSelected = true, ItemType = "FOLDER", LocationTag = sel.Location, SizeBytes = sel.SizeBytes, SizeDisplay = sel.SizeDisplay, TargetPath = sel.FullPath });
                LblInspectorTarget.Text = "Target: " + sel.FolderName;
                ShowLeftoverInspector();
                UpdateSystemTelemetry();
            };

            // Custom Target Hunter
            BtnBrowseHunterPath.Click += (s, e) =>
            {
                using (var fbd = new System.Windows.Forms.FolderBrowserDialog())
                    if (fbd.ShowDialog() == System.Windows.Forms.DialogResult.OK) TxtHunterPath.Text = fbd.SelectedPath;
            };
            BtnExecuteCustomHunt.Click += async (s, e) =>
            {
                string kw = (TxtHunterKeyword.Text ?? "").Trim();
                if (string.IsNullOrEmpty(kw)) { MessageBox.Show(this, "Enter an application name or keyword.", "NovaGen", MessageBoxButton.OK, MessageBoxImage.Information); return; }
                await RunDeepScanIntoInspectorAsync(kw, (TxtHunterPublisher.Text ?? "").Trim(), (TxtHunterPath.Text ?? "").Trim(), "");
            };

            // Snapshots
            BtnCreateSnapshot.Click += async (s, e) =>
            {
                string label = RegexSafe((TxtSnapshotLabel.Text ?? "Baseline").Trim());
                BtnCreateSnapshot.IsEnabled = false;
                WriteNovaLog(string.Format("Capturing baseline snapshot '{0}'...", label));
                await Task.Run(() =>
                {
                    var dirs = new List<string>();
                    foreach (var p in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) })
                    {
                        try { if (Directory.Exists(p)) dirs.AddRange(Directory.GetDirectories(p)); } catch { }
                    }
                    File.WriteAllLines(Path.Combine(_snapshotRoot, string.Format("{0}_{1:yyyyMMdd_HHmmss}.snap", label, DateTime.Now)), dirs);
                });
                RefreshSnapshotsList();
                BtnCreateSnapshot.IsEnabled = true;
                WriteNovaLog("Baseline snapshot captured!");
            };
            BtnDeleteSnapshot.Click += (s, e) =>
            {
                string fn = ListSnapshots.SelectedItem as string;
                if (fn != null)
                {
                    try { File.Delete(Path.Combine(_snapshotRoot, fn)); RefreshSnapshotsList(); } catch { }
                }
            };
            BtnCompareSnapshot.Click += async (s, e) =>
            {
                string fn = ListSnapshots.SelectedItem as string;
                if (fn == null) return;
                string snapFile = Path.Combine(_snapshotRoot, fn);
                var oldSet = new HashSet<string>(File.ReadAllLines(snapFile), StringComparer.OrdinalIgnoreCase);
                var diff = await Task.Run(() =>
                {
                    var list = new List<LeftoverItem>();
                    foreach (var p in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) })
                    {
                        try
                        {
                            if (!Directory.Exists(p)) continue;
                            foreach (var d in Directory.GetDirectories(p))
                            {
                                if (!oldSet.Contains(d) && !UninstallerService.IsProtectedPath(d))
                                {
                                    long sz = UninstallerService.GetDirectorySizeFast(d);
                                    list.Add(new LeftoverItem { IsSelected = true, ItemType = "FOLDER", LocationTag = "Snapshot Diff", SizeBytes = sz, SizeDisplay = UninstallerService.FormatByteSize(sz), TargetPath = d });
                                }
                            }
                        }
                        catch { }
                    }
                    return list;
                });
                _leftoverItems.Clear();
                foreach (var it in diff) _leftoverItems.Add(it);
                LblInspectorTarget.Text = "Target: Diff vs " + fn;
                if (_leftoverItems.Count > 0) ShowLeftoverInspector();
                UpdateSystemTelemetry();
            };

            // PC Speed Boost (60fps Async!)
            BtnBoostAnalyze.Click += async (s, e) => await RunBoostAsync(true);
            BtnBoostNow.Click += async (s, e) => await RunBoostAsync(false);
            BtnPresetSafe.Click += (s, e) => ApplyBoostPreset("SAFE");
            BtnPresetGaming.Click += (s, e) => ApplyBoostPreset("GAMING");
            BtnPresetMax.Click += (s, e) => ApplyBoostPreset("MAX");
            BtnBoostRefreshProcs.Click += (s, e) => RefreshBoostTopProcesses();
            BtnBoostScanStartup.Click += (s, e) => RefreshBoostStartupList();
            BtnBoostTogglePower.Click += (s, e) =>
            {
                bool isHp = TxtBoostPowerPlan.Text.IndexOf("High", StringComparison.OrdinalIgnoreCase) >= 0 || TxtBoostPowerPlan.Text.IndexOf("Ultimate", StringComparison.OrdinalIgnoreCase) >= 0;
                string targetGuid = isHp ? "381b4222-f694-41f0-9685-ff5bb260df2e" : "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";
                { var _p = Process.Start(new ProcessStartInfo("powercfg.exe", "/setactive " + targetGuid) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); }
                RefreshBoostPowerPlan();
            };
            BtnBoostDisableStartup.Click += (s, e) =>
            {
                var list = GridBoostStartup.ItemsSource as IEnumerable<StartupEntryItem>;
                if (list == null) return;
                var sel = list.Where(x => x.IsSelected).ToList();
                if (sel.Count == 0) return;
                if (MessageBox.Show(this, string.Format("Disable {0} startup entry(ies)?\n\nA .reg backup will be saved to Backups\\.", sel.Count), "NovaGen // Startup Accelerator", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
                foreach (var item in sel)
                {
                    try
                    {
                        string bkReg = Path.Combine(_backupRoot, string.Format("Startup_{0}_{1:yyyyMMdd_HHmmss}.reg", item.Scope, DateTime.Now));
                        { var _p = Process.Start(new ProcessStartInfo("reg.exe", string.Format("export \"{0}\" \"{1}\" /y", item.ExportPath, bkReg)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); }
                        { var _p = Process.Start(new ProcessStartInfo("reg.exe", string.Format("delete \"{0}\" /v \"{1}\" /f", item.ExportPath, item.Name)) { CreateNoWindow = true, UseShellExecute = false }); if (_p != null) _p.WaitForExit(3000); }
                    }
                    catch { }
                }
                RefreshBoostStartupList();
            };

            // Bloat Radar (True Async!)
            BtnRadarBrowse.Click += (s, e) =>
            {
                using (var fbd = new System.Windows.Forms.FolderBrowserDialog())
                    if (fbd.ShowDialog() == System.Windows.Forms.DialogResult.OK) TxtRadarRoot.Text = fbd.SelectedPath;
            };
            BtnRunBloatRadar.Click += async (s, e) =>
            {
                BtnRunBloatRadar.IsEnabled = false;
                BtnCleanBloatRadar.IsEnabled = false;
                _bloatRadarItems.Clear();
                UpdateRadarSelectedSize();

                int days = 14;
                int.TryParse(TxtRadarStaleDays.Text, out days);
                if (days < 1) days = 1;
                string root = (TxtRadarRoot.Text ?? "").Trim();
                bool sDev = ChkRadarDev.IsChecked == true;
                bool sGamer = ChkRadarGamer.IsChecked == true;
                bool sInst = ChkRadarInstallers.IsChecked == true;
                bool sDups = ChkRadarDups.IsChecked == true;

                var statusProg = new Progress<string>(m => TxtRadarStatus.Text = m);
                var itemProg = new Progress<BloatRadarItem>(it => { _bloatRadarItems.Add(it); UpdateRadarSelectedSize(); });

                var res = await Task.Run(() => BloatRadarService.Scan(root, days, sDev, sGamer, sInst, sDups, statusProg, itemProg));
                long tot = res.Sum(x => x.SizeBytes);
                TxtRadarStatus.Text = string.Format("Scan Complete â€” Found {0} items totaling {1}", _bloatRadarItems.Count, UninstallerService.FormatByteSize(tot));
                UpdateRadarSelectedSize();
                BtnRunBloatRadar.IsEnabled = true;
                BtnCleanBloatRadar.IsEnabled = true;
            };
            BtnRadarSelStale.Click += (s, e) =>
            {
                foreach (var it in _bloatRadarItems)
                    it.IsSelected = it.StatusTag.StartsWith("STALE") || it.StatusTag.StartsWith("SAFE") || it.StatusTag.StartsWith("ORPHAN") || it.StatusTag.StartsWith("DUP");
                UpdateRadarSelectedSize();
            };
            BtnRadarSelNone.Click += (s, e) => { foreach (var it in _bloatRadarItems) it.IsSelected = false; UpdateRadarSelectedSize(); };
            GridBloatRadar.CellEditEnding += (s, e) => Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(UpdateRadarSelectedSize));
            BtnCleanBloatRadar.Click += async (s, e) =>
            {
                var toClean = _bloatRadarItems.Where(x => x.IsSelected).ToList();
                if (toClean.Count == 0) return;
                long selSz = toClean.Sum(x => x.SizeBytes);
                if (MessageBox.Show(this, string.Format("Permanently delete {0} selected bloat item(s) ({1})?", toClean.Count, UninstallerService.FormatByteSize(selSz)), "NovaGen // Bloat Radar Clean", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
                    return;

                BtnRunBloatRadar.IsEnabled = false;
                BtnCleanBloatRadar.IsEnabled = false;
                var sp = new Progress<string>(m => TxtRadarStatus.Text = m);
                var rp = new Progress<BloatRadarItem>(rm => { _bloatRadarItems.Remove(rm); UpdateRadarSelectedSize(); });
                long freed = await Task.Run(() => BloatRadarService.CleanItems(toClean, sp, rp));
                _sessionReclaimedBytes += freed;
                UpdateSystemTelemetry();
                UpdateRadarSelectedSize();
                TxtRadarStatus.Text = string.Format("Clean Complete â€” Reclaimed {0}!", UninstallerService.FormatByteSize(freed));
                BtnRunBloatRadar.IsEnabled = true;
                BtnCleanBloatRadar.IsEnabled = true;
            };

            // Watchdog
            BtnWatchdogSortNow.Click += (s, e) =>
            {
                int tot = 0;
                if (ChkWatchDownloads.IsChecked == true)
                {
                    string dl = NativeMethods.GetKnownDownloadsPath();
                    WriteWatchdogLog(string.Format("Scanning Downloads ({0})...", dl));
                    foreach (var r in _watchdog.OrganizeFolderNow(dl)) { tot++; WriteWatchdogLog(string.Format("Sorted [{0}] -> {1}", r.Category, r.FileName)); }
                }
                if (ChkWatchDesktop.IsChecked == true)
                {
                    string dt = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
                    WriteWatchdogLog(string.Format("Scanning Desktop ({0})...", dt));
                    foreach (var r in _watchdog.OrganizeFolderNow(dt)) { tot++; WriteWatchdogLog(string.Format("Sorted [{0}] -> {1}", r.Category, r.FileName)); }
                }
                TxtWatchdogMoved.Text = string.Format("Files Sorted: {0}", _watchdog.MovedCount);
                WriteWatchdogLog(string.Format("Instant Sort Complete: {0} file(s) organized into Sorted\\ subfolders.", tot));
            };
            BtnWatchdogToggle.Click += (s, e) =>
            {
                if (_watchdog.IsRunning)
                {
                    _watchdog.Stop();
                    if (_watchdogTimer != null) _watchdogTimer.Stop();
                    TxtWatchdogState.Text = "STOPPED";
                    TxtWatchdogState.Foreground = Brushes.Orange;
                    BtnWatchdogToggle.Content = "â–¶ Start Real-Time Watchdog";
                    WriteWatchdogLog("Watchdog stopped.");
                }
                else
                {
                    var paths = new List<string>();
                    if (ChkWatchDownloads.IsChecked == true) paths.Add(NativeMethods.GetKnownDownloadsPath());
                    if (ChkWatchDesktop.IsChecked == true) paths.Add(Environment.GetFolderPath(Environment.SpecialFolder.Desktop));
                    if (paths.Count == 0) return;
                    _watchdog.Start(paths);
                    foreach (var p in paths) WriteWatchdogLog("Watching real-time: " + p);
                    if (_watchdogTimer == null)
                    {
                        _watchdogTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                        _watchdogTimer.Tick += (ts, te) =>
                        {
                            foreach (var r in _watchdog.DrainQueue())
                            {
                                TxtWatchdogMoved.Text = string.Format("Files Sorted: {0}", _watchdog.MovedCount);
                                WriteWatchdogLog(string.Format("[AUTO] Sorted [{0}] -> {1}", r.Category, r.FileName));
                            }
                        };
                    }
                    _watchdogTimer.Start();
                    TxtWatchdogState.Text = "ACTIVE (WATCHING)";
                    TxtWatchdogState.Foreground = Brushes.LimeGreen;
                    BtnWatchdogToggle.Content = "â¹ Stop Watchdog";
                }
            };
        }

        private async Task RunDeepScanIntoInspectorAsync(string name, string pub, string loc, string regPath)
        {
            WriteNovaLog(string.Format("Launching 18-Point Deep Leftover Scan for '{0}'...", name));
            LblInspectorTarget.Text = "Target: " + name;
            var prog = new Progress<string>(m => LblStatusBar.Text = m);
            var items = await Task.Run(() => UninstallerService.DeepScanLeftovers(name, pub, loc, regPath, prog));
            _leftoverItems.Clear();
            foreach (var it in items) _leftoverItems.Add(it);
            ShowLeftoverInspector();
            UpdateSystemTelemetry();
            WriteNovaLog(string.Format("Deep Scan Complete: Found {0} leftover trace(s).", _leftoverItems.Count));
        }

        private void RefreshSnapshotsList()
        {
            if (!Directory.Exists(_snapshotRoot)) return;
            ListSnapshots.ItemsSource = Directory.GetFiles(_snapshotRoot, "*.snap").Select(Path.GetFileName).OrderByDescending(x => x).ToList();
        }

        private void UpdateBoostRing(double pct, string ringLabel, string activeStep, string accentHex)
        {
            double p = Math.Max(0, Math.Min(100, pct));
            _currentBoostPct = p;
            if (p <= 0.1) BoostRingArc.Data = null;
            else if (p >= 99.9) BoostRingArc.Data = Geometry.Parse("M 62,5 A 57,57 0 1 1 62,119 A 57,57 0 1 1 62,5");
            else
            {
                double rad = (p / 100.0) * 2.0 * Math.PI;
                double x = Math.Round(62.0 + 57.0 * Math.Sin(rad), 2);
                double y = Math.Round(62.0 - 57.0 * Math.Cos(rad), 2);
                int large = p > 50.0 ? 1 : 0;
                BoostRingArc.Data = Geometry.Parse(string.Format(CultureInfo.InvariantCulture, "M 62,5 A 57,57 0 {0} 1 {1},{2}", large, x, y));
            }
            if (!string.IsNullOrWhiteSpace(accentHex))
                BoostRingArc.Stroke = (Brush)new BrushConverter().ConvertFromString(accentHex);
            TxtBoostRingPercent.Text = string.Format("{0}%", (int)Math.Round(p));
            TxtBoostRingLabel.Text = ringLabel;
            PbBoostProgress.Value = p;
            if (!string.IsNullOrWhiteSpace(activeStep)) TxtBoostActiveStep.Text = activeStep;
        }

        private void UpdateBoostRamTelemetry(bool updateRing)
        {
            var snap = NativeMethods.GetMemorySnapshot();
            if (snap[1] > 0)
            {
                int pct = (int)snap[0];
                double tot = Math.Round(snap[1] / 1073741824.0, 1);
                double used = Math.Round((snap[1] - snap[2]) / 1073741824.0, 1);
                TxtBoostSysRAM.Text = string.Format("{0} / {1} GB", used, tot);
                if (updateRing)
                {
                    string hex = pct >= 85 ? "#EF4444" : pct >= 65 ? "#F59E0B" : "#06B6D4";
                    UpdateBoostRing(pct, "RAM USED", string.Format("System RAM: {0} / {1} GB ({2}%) â€” Ready to optimize", used, tot, pct), hex);
                }
            }
        }

        private async Task RunBoostAsync(bool dryRun)
        {
            BtnBoostAnalyze.IsEnabled = false;
            BtnBoostNow.IsEnabled = false;
            TxtBoostStatus.Text = dryRun ? "ANALYZING..." : "BOOSTING...";
            TxtBoostStatus.Foreground = Brushes.Orange;
            TxtBoostLog.Clear();
            UpdateBoostRing(0, dryRun ? "ANALYZING" : "BOOSTING", "Starting...", dryRun ? "#06B6D4" : "#22C55E");

            var opt = new BoostOptions
            {
                DryRun = dryRun,
                DoRAM = ChkBoostRAM.IsChecked == true,
                DoWinTemp = ChkBoostWinTemp.IsChecked == true,
                DoBrowser = ChkBoostBrowser.IsChecked == true,
                DoGPU = ChkBoostGPU.IsChecked == true,
                DoUWP = ChkBoostUWP.IsChecked == true,
                DoPrefetch = ChkBoostPrefetch.IsChecked == true,
                DoDNS = ChkBoostDNS.IsChecked == true,
                DoWU = ChkBoostWU.IsChecked == true,
                DoThumb = ChkBoostThumb.IsChecked == true,
                DoWER = ChkBoostWER.IsChecked == true,
                DoDelivOpt = ChkBoostDelivOpt.IsChecked == true,
                DoTRIM = ChkBoostTRIM.IsChecked == true,
                DoPower = ChkBoostPower.IsChecked == true,
                DoFont = ChkBoostFont.IsChecked == true,
                DoRecycle = ChkBoostRecycle.IsChecked == true,
                DoDISM = ChkBoostDISM.IsChecked == true,
                DoEventLogs = ChkBoostEventLogs.IsChecked == true
            };

            var prog = new Progress<BoostProgressReport>(r =>
            {
                UpdateBoostRing(r.Percent, r.RingLabel, r.ActiveStep, r.AccentHex);
                TxtBoostEstimate.Text = UninstallerService.FormatByteSize(r.DiskFreedBytes);
                if (!dryRun) TxtBoostDisk.Text = UninstallerService.FormatByteSize(r.DiskFreedBytes);
                if (r.RamFreedMB > 0) TxtBoostRAM.Text = (dryRun ? "~" : "") + r.RamFreedMB + " MB";
                if (!string.IsNullOrEmpty(r.LogLine))
                {
                    TxtBoostLog.AppendText(r.LogLine + Environment.NewLine);
                    TxtBoostLog.ScrollToEnd();
                }
            });

            var res = await Task.Run(() => PcSpeedBoostService.RunBoost(opt, prog));
            TxtBoostStatus.Text = dryRun ? "ANALYZED" : "BOOSTED!";
            TxtBoostStatus.Foreground = Brushes.LimeGreen;
            if (!dryRun && res.TotalFreedBytes > 0) _sessionReclaimedBytes += res.TotalFreedBytes;
            UpdateBoostRamTelemetry(false);
            RefreshBoostPowerPlan();
            RefreshBoostTopProcesses();
            UpdateSystemTelemetry();
            BtnBoostAnalyze.IsEnabled = true;
            BtnBoostNow.IsEnabled = true;
        }

        private void ApplyBoostPreset(string mode)
        {
            ChkBoostRAM.IsChecked = true;
            ChkBoostWinTemp.IsChecked = true;
            ChkBoostBrowser.IsChecked = true;
            ChkBoostGPU.IsChecked = true;
            ChkBoostUWP.IsChecked = true;
            ChkBoostPrefetch.IsChecked = true;
            ChkBoostDNS.IsChecked = true;
            ChkBoostWU.IsChecked = true;
            ChkBoostThumb.IsChecked = true;
            ChkBoostWER.IsChecked = true;
            ChkBoostDelivOpt.IsChecked = true;
            ChkBoostTRIM.IsChecked = true;
            ChkBoostPower.IsChecked = mode == "GAMING" || mode == "MAX";
            ChkBoostFont.IsChecked = mode == "MAX";
            ChkBoostRecycle.IsChecked = mode == "MAX";
            ChkBoostDISM.IsChecked = mode == "MAX";
            ChkBoostEventLogs.IsChecked = false;
            TxtBoostLog.AppendText(string.Format("[{0:HH:mm:ss}] [INFO] Preset Applied: {1}{2}", DateTime.Now, mode, Environment.NewLine));
        }

        private void UpdateBoostCommandCenter()
        {
            RefreshBoostPowerPlan();
            RefreshBoostTopProcesses();
            if (GridBoostStartup.ItemsSource == null) RefreshBoostStartupList();
        }

        private void RefreshBoostPowerPlan()
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo("powercfg.exe", "/getactivescheme") { RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true });
                string outStr = p.StandardOutput.ReadToEnd();
                p.WaitForExit(3000);
                int i1 = outStr.IndexOf('(');
                int i2 = outStr.IndexOf(')');
                if (i1 >= 0 && i2 > i1)
                {
                    string name = outStr.Substring(i1 + 1, i2 - i1 - 1);
                    TxtBoostPowerPlan.Text = name;
                    BtnBoostTogglePower.Content = (name.IndexOf("High", StringComparison.OrdinalIgnoreCase) >= 0 || name.IndexOf("Ultimate", StringComparison.OrdinalIgnoreCase) >= 0) ? "âš– Balanced" : "âš¡ High Perf";
                }
            }
            catch { }
        }

        private void RefreshBoostTopProcesses()
        {
            GridBoostTopProcs.ItemsSource = Process.GetProcesses()
                .OrderByDescending(p => p.WorkingSet64)
                .Take(8)
                .Select(p => new TopProcessItem { Name = p.ProcessName, MemDisplay = string.Format("{0} MB", Math.Round(p.WorkingSet64 / 1048576.0)), Pid = p.Id })
                .ToList();
        }

        private void RefreshBoostStartupList()
        {
            var list = new ObservableCollection<StartupEntryItem>();
            var roots = new[]
            {
                new { Hive = RegistryHive.CurrentUser, View = RegistryView.Default, Sub = @"Software\Microsoft\Windows\CurrentVersion\Run", Scope = "User", Exp = @"HKCU\Software\Microsoft\Windows\CurrentVersion\Run" },
                new { Hive = RegistryHive.LocalMachine, View = RegistryView.Registry64, Sub = @"Software\Microsoft\Windows\CurrentVersion\Run", Scope = "System", Exp = @"HKLM\Software\Microsoft\Windows\CurrentVersion\Run" },
                new { Hive = RegistryHive.LocalMachine, View = RegistryView.Registry32, Sub = @"Software\Microsoft\Windows\CurrentVersion\Run", Scope = "x86", Exp = @"HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" }
            };
            foreach (var r in roots)
            {
                try
                {
                    using (var bk = RegistryKey.OpenBaseKey(r.Hive, r.View))
                    using (var k = bk.OpenSubKey(r.Sub))
                    {
                        if (k == null) continue;
                        foreach (var vn in k.GetValueNames())
                        {
                            if (string.IsNullOrWhiteSpace(vn)) continue;
                            list.Add(new StartupEntryItem { Name = vn, Scope = r.Scope, Command = Convert.ToString(k.GetValue(vn)), ExportPath = r.Exp });
                        }
                    }
                }
                catch { }
            }
            GridBoostStartup.ItemsSource = list;
        }

        private void UpdateRadarSelectedSize()
        {
            var sel = _bloatRadarItems.Where(x => x.IsSelected).ToList();
            TxtRadarSelectedSize.Text = string.Format("Selected: {0} ({1} items)", UninstallerService.FormatByteSize(sel.Sum(x => x.SizeBytes)), sel.Count);
        }

        private void WriteWatchdogLog(string msg)
        {
            TxtWatchdogLog.AppendText(string.Format("[{0:HH:mm:ss}] {1}{2}", DateTime.Now, msg, Environment.NewLine));
            TxtWatchdogLog.ScrollToEnd();
        }

        private static string RegexSafe(string s)
        {
            foreach (char c in Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
            return string.IsNullOrWhiteSpace(s) ? "Baseline" : s;
        }
    }
}
