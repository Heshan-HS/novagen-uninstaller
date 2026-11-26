import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovaGenMobileApp());
}

class NovaGenMobileApp extends StatefulWidget {
  const NovaGenMobileApp({super.key});

  @override
  State<NovaGenMobileApp> createState() => _NovaGenMobileAppState();
}

class _NovaGenMobileAppState extends State<NovaGenMobileApp> {
  bool _isDark = true;

  @override
  Widget build(BuildContext context) {
    final bg = _isDark ? const Color(0xFF060B16) : const Color(0xFFEFF6FF);
    final surface = _isDark ? const Color(0xFF0B1220) : Colors.white;
    final primaryInk = _isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NovaGen Mobile Pro',
      theme: ThemeData(
        useMaterial3: true,
        brightness: _isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bg,
        cardColor: surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: _isDark ? Brightness.dark : Brightness.light,
          surface: surface,
        ),
        textTheme: ThemeData(brightness: _isDark ? Brightness.dark : Brightness.light)
            .textTheme
            .apply(bodyColor: primaryInk, displayColor: primaryInk),
      ),
      home: NovaGenHomePage(
        isDark: _isDark,
        onToggleTheme: () => setState(() => _isDark = !_isDark),
      ),
    );
  }
}

class NovaGenHomePage extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const NovaGenHomePage({super.key, required this.isDark, required this.onToggleTheme});

  @override
  State<NovaGenHomePage> createState() => _NovaGenHomePageState();
}

class _NovaGenHomePageState extends State<NovaGenHomePage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.novagen.mobile/engine');

  int _tabIndex = 0;
  Map<String, dynamic> _telemetry = {};
  bool _loadingTelemetry = true;

  // Boost & Junk state
  bool _scanningJunk = false;
  bool _cleaningJunk = false;
  List<Map<String, dynamic>> _junkItems = [];
  String _boostStatus = 'READY â€” Tap Scan Junk or Trim RAM';
  int _lastFreedBytes = 0;

  // Apps state
  bool _loadingApps = false;
  List<Map<String, dynamic>> _apps = [];
  String _appSearch = '';

  // Large files state
  bool _scanningLarge = false;
  List<Map<String, dynamic>> _largeFiles = [];

  // Auto-Sort state
  bool _sortingDownloads = false;
  final List<String> _sortLogs = ['[Watchdog] Ready to organize your Download folder safely.'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTelemetry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTelemetry();
    }
  }

  Color get _surface => widget.isDark ? const Color(0xFF0B1220) : Colors.white;
  Color get _recessed => widget.isDark ? const Color(0xFF040811) : const Color(0xFFF1F5F9);
  Color get _border => widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
  Color get _muted => widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _accentCyan => widget.isDark ? const Color(0xFF22D3EE) : const Color(0xFF0284C7);
  Color get _accentBlue => const Color(0xFF2563EB);

  static String formatBytes(num b) {
    final bytes = b.toDouble();
    if (bytes <= 0) return '0 KB';
    if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${bytes.toInt()} B';
  }

  Future<void> _refreshTelemetry() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getTelemetry');
      if (mounted && res != null) {
        setState(() {
          _telemetry = res;
          _loadingTelemetry = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTelemetry = false);
    }
  }

  Future<void> _trimRam() async {
    setState(() => _boostStatus = 'Trimming idle background processes...');
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('trimBackgroundRam');
      await _refreshTelemetry();
      final freed = res?['freedMb'] ?? 0;
      final trimmed = res?['trimmedApps'] ?? 0;
      setState(() {
        _boostStatus = 'Trimmed $trimmed apps â€” $freed MB RAM freed!';
      });
    } catch (e) {
      setState(() => _boostStatus = 'RAM trim error: $e');
    }
  }

  Future<void> _scanJunk() async {
    if (!(_telemetry['hasStorage'] == true)) {
      await _channel.invokeMethod('requestStoragePermission');
      return;
    }
    setState(() {
      _scanningJunk = true;
      _boostStatus = 'Scanning thumbnails, temp, empty folders & old APKs...';
      _junkItems = [];
    });
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanSafeJunk') ?? [];
      final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final total = list.fold<int>(0, (sum, it) => sum + ((it['size'] as num?)?.toInt() ?? 0));
      setState(() {
        _junkItems = list;
        _scanningJunk = false;
        _boostStatus = 'Found ${list.length} items (${formatBytes(total)})';
      });
    } catch (e) {
      setState(() {
        _scanningJunk = false;
        _boostStatus = 'Scan error: $e';
      });
    }
  }

  Future<void> _cleanSelectedJunk() async {
    final selected = _junkItems.where((it) => it['selected'] == true).toList();
    if (selected.isEmpty) return;
    setState(() {
      _cleaningJunk = true;
      _boostStatus = 'Cleaning ${selected.length} safe items...';
    });
    try {
      final paths = selected.map((e) => e['path'].toString()).toList();
      final freed = await _channel.invokeMethod<int>('cleanJunkItems', {'paths': paths}) ?? 0;
      await _refreshTelemetry();
      setState(() {
        _junkItems.removeWhere((it) => it['selected'] == true);
        _lastFreedBytes += freed;
        _cleaningJunk = false;
        _boostStatus = 'Cleaned! Reclaimed ${formatBytes(freed)}';
      });
    } catch (e) {
      setState(() {
        _cleaningJunk = false;
        _boostStatus = 'Clean error: $e';
      });
    }
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _loadingApps = true);
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanInstalledApps') ?? [];
      final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _apps = list;
        _loadingApps = false;
      });
    } catch (_) {
      setState(() => _loadingApps = false);
    }
  }

  Future<void> _scanLargeFiles() async {
    if (!(_telemetry['hasStorage'] == true)) {
      await _channel.invokeMethod('requestStoragePermission');
      return;
    }
    setState(() => _scanningLarge = true);
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanLargeFiles', {'minMb': 50}) ?? [];
      setState(() {
        _largeFiles = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _scanningLarge = false;
      });
    } catch (_) {
      setState(() => _scanningLarge = false);
    }
  }

  Future<void> _sortDownloads() async {
    if (!(_telemetry['hasStorage'] == true)) {
      await _channel.invokeMethod('requestStoragePermission');
      return;
    }
    setState(() {
      _sortingDownloads = true;
      _sortLogs.add('[Watchdog] Scanning /Download for unsorted files...');
    });
    try {
      final moved = await _channel.invokeListMethod<String>('sortDownloadsFolder') ?? [];
      setState(() {
        if (moved.isEmpty) {
          _sortLogs.add('[Watchdog] Download folder is already clean!');
        } else {
          for (final m in moved) {
            _sortLogs.add('[SORTED] $m');
          }
          _sortLogs.add('[DONE] Organized ${moved.length} file(s) into Download/Sorted/');
        }
        _sortingDownloads = false;
      });
    } catch (e) {
      setState(() {
        _sortLogs.add('[ERROR] $e');
        _sortingDownloads = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _recessed,
        elevation: 0,
        titleSpacing: 14,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFFA855F7)]),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.cleaning_services_rounded, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NOVAGEN MOBILE PRO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                Text(_telemetry['deviceModel']?.toString() ?? 'Android Optimizer v1.0',
                    style: TextStyle(fontSize: 10.5, color: _muted)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: _accentCyan),
          ),
          IconButton(
            tooltip: 'Refresh Telemetry',
            onPressed: _refreshTelemetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildBoostTab(),
          _buildAppsTab(),
          _buildLargeFilesTab(),
          _buildAutoSortTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: _recessed,
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) {
          setState(() => _tabIndex = idx);
          if (idx == 1 && _apps.isEmpty && !_loadingApps) _loadInstalledApps();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt_rounded), label: 'Boost'),
          NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'App Cache'),
          NavigationDestination(icon: Icon(Icons.radar_rounded), label: 'Large Files'),
          NavigationDestination(icon: Icon(Icons.folder_copy_rounded), label: 'Auto-Sort'),
        ],
      ),
    );
  }

  Widget _buildBoostTab() {
    final ramPct = (_telemetry['ramPercent'] as num?)?.toDouble() ?? 0.0;
    final usedRam = (_telemetry['usedRam'] as num?) ?? 0;
    final totalRam = (_telemetry['totalRam'] as num?) ?? 0;
    final availStorage = (_telemetry['availStorage'] as num?) ?? 0;
    final totalStorage = (_telemetry['totalStorage'] as num?) ?? 0;
    final batPct = (_telemetry['batteryPercent'] as num?) ?? 0;
    final batTemp = (_telemetry['batteryTempC'] as num?) ?? 0.0;
    final hasStorage = _telemetry['hasStorage'] == true;
    final hasUsage = _telemetry['hasUsage'] == true;
    final selBytes = _junkItems.where((x) => x['selected'] == true).fold<int>(0, (s, x) => s + ((x['size'] as num?)?.toInt() ?? 0));

    return RefreshIndicator(
      onRefresh: _refreshTelemetry,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (!hasStorage || !hasUsage)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF451A03).withValues(alpha: 0.35),
                border: Border.all(color: const Color(0xFFF59E0B)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PERMISSIONS REQUIRED FOR FULL SCAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (!hasStorage)
                        FilledButton.tonal(
                          onPressed: () => _channel.invokeMethod('requestStoragePermission'),
                          child: const Text('Grant All Files Access', style: TextStyle(fontSize: 12)),
                        ),
                      if (!hasUsage) ...[
                        FilledButton.tonal(
                          onPressed: () => _channel.invokeMethod('requestUsagePermission'),
                          child: const Text('Grant App Usage Stats', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: () => _channel.invokeMethod('openAppSettings', {'packageName': 'com.novagen.novagen_mobile'}),
                          child: const Text('Allow Restricted (â‹®)', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

          // Hero Circular Ring Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: ramPct),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, val, _) {
                    final color = val >= 85 ? const Color(0xFFEF4444) : (val >= 65 ? const Color(0xFFF59E0B) : _accentCyan);
                    return SizedBox(
                      width: 112,
                      height: 112,
                      child: CustomPaint(
                        painter: _RingGaugePainter(percent: val, trackColor: _border, progressColor: color),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${val.round()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                              Text('RAM USED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _muted)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_loadingTelemetry ? 'Reading sensors...' : _boostStatus,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentCyan)),
                      const SizedBox(height: 10),
                      _metricRow('RAM', '${formatBytes(usedRam)} / ${formatBytes(totalRam)}'),
                      _metricRow('Free Storage', '${formatBytes(availStorage)} / ${formatBytes(totalStorage)}'),
                      _metricRow('Battery', '$batPct% Â· ${batTemp.toStringAsFixed(1)}Â°C'),
                      _metricRow('Session Cleaned', formatBytes(_lastFreedBytes)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Action Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _trimRam,
                  style: OutlinedButton.styleFrom(side: BorderSide(color: _border), padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: Icon(Icons.memory_rounded, color: _accentCyan, size: 18),
                  label: const Text('Trim RAM'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanningJunk ? null : _scanJunk,
                  style: FilledButton.styleFrom(backgroundColor: _accentBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: _scanningJunk
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search_rounded, size: 18),
                  label: Text(_scanningJunk ? 'Scanning...' : 'Scan Safe Junk'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (_junkItems.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('DETECTED JUNK (${_junkItems.length})', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _muted)),
                Text('Selected: ${formatBytes(selBytes)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF22C55E))),
              ],
            ),
            const SizedBox(height: 8),
            ..._junkItems.map((it) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
                child: CheckboxListTile(
                  value: it['selected'] == true,
                  onChanged: (v) => setState(() => it['selected'] = v ?? false),
                  dense: true,
                  title: Text('${it['category']} Â· ${formatBytes((it['size'] as num?) ?? 0)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(it['path'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: _muted)),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _cleaningJunk ? null : _cleanSelectedJunk,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.delete_sweep_rounded),
              label: Text(_cleaningJunk ? 'Cleaning...' : 'Clean Selected (${formatBytes(selBytes)})'),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Icon(Icons.verified_user_rounded, size: 36, color: _accentCyan),
                  const SizedBox(height: 8),
                  const Text('100% Honest & OS-Safe Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Scans .thumbnails, temp/log files, empty folders, WhatsApp Sent/Statuses & old APKs. Never touches photos or app data without review.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: _muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppsTab() {
    final hasUsage = _telemetry['hasUsage'] == true;
    final filtered = _apps.where((a) {
      if (_appSearch.isEmpty) return true;
      return a['name'].toString().toLowerCase().contains(_appSearch) || a['packageName'].toString().toLowerCase().contains(_appSearch);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search installed apps...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: _surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
                  ),
                  onChanged: (v) => setState(() => _appSearch = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _loadInstalledApps, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
        ),
        if (!hasUsage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: ListTile(
              tileColor: const Color(0xFF451A03).withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFF59E0B))),
              title: const Text('Grant Usage Access to see exact Cache Sizes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
              trailing: TextButton(onPressed: () => _channel.invokeMethod('requestUsagePermission'), child: const Text('Grant')),
            ),
          ),
        Expanded(
          child: _loadingApps
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final app = filtered[i];
                    final cache = (app['cacheBytes'] as num?) ?? 0;
                    final total = (app['totalBytes'] as num?) ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(app['name'].toString(), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                                Text('${app['packageName']} Â· Total: ${formatBytes(total)}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: _muted)),
                                Text('Cache: ${formatBytes(cache)}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cache > 10485760 ? const Color(0xFFF59E0B) : _accentCyan)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Backup APK to Download/NovaGen_Backups',
                            onPressed: () async {
                              final out = await _channel.invokeMethod<String>('backupAppApk', {'packageName': app['packageName'], 'appName': app['name']});
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('APK saved: $out')));
                              }
                            },
                            icon: const Icon(Icons.download_rounded, size: 20),
                          ),
                          IconButton(
                            tooltip: 'Open Storage & Clear Cache',
                            onPressed: () => _channel.invokeMethod('openAppSettings', {'packageName': app['packageName']}),
                            icon: Icon(Icons.cleaning_services_rounded, size: 20, color: _accentCyan),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLargeFilesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LARGE FILE HUNTER (> 50 MB)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('Find forgotten videos, APKs & ZIPs eating storage', style: TextStyle(fontSize: 11, color: _muted)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _scanningLarge ? null : _scanLargeFiles,
                style: FilledButton.styleFrom(backgroundColor: _accentBlue),
                icon: _scanningLarge ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.radar_rounded, size: 18),
                label: Text(_scanningLarge ? 'Scanning...' : 'Scan >50MB'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _largeFiles.isEmpty
              ? Center(child: Text('Tap "Scan >50MB" to inspect large files.', style: TextStyle(color: _muted)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _largeFiles.length,
                  itemBuilder: (ctx, i) {
                    final f = _largeFiles[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        dense: true,
                        title: Text('${f['name']} (${formatBytes((f['size'] as num?) ?? 0)})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(f['path'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: _muted)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete Large File?'),
                                content: Text('Permanently delete ${f['name']}?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _channel.invokeMethod('cleanJunkItems', {'paths': [f['path']]});
                              setState(() => _largeFiles.removeAt(i));
                              _refreshTelemetry();
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAutoSortTab() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AUTO-SORT WATCHDOG (DOWNLOADS ORGANIZER)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Organizes /Download into Sorted/{Installers, Archives, Images, Videos, Audio, Documents} safely without overwriting.',
                    style: TextStyle(fontSize: 11.5, color: _muted)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sortingDownloads ? null : _sortDownloads,
                  style: FilledButton.styleFrom(backgroundColor: _accentBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.folder_special_rounded),
                  label: Text(_sortingDownloads ? 'Organizing...' : 'Sort Download Folder Now'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('ACTIVITY LOG', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: _accentCyan)),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _recessed, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
              child: ListView.builder(
                itemCount: _sortLogs.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_sortLogs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: _muted)),
          Text(val, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _RingGaugePainter extends CustomPainter {
  final double percent;
  final Color trackColor;
  final Color progressColor;

  _RingGaugePainter({required this.percent, required this.trackColor, required this.progressColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - 10) / 2;
    const stroke = 9.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final sweep = (percent.clamp(0, 100) / 100.0) * 2 * math.pi;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _RingGaugePainter old) => old.percent != percent || old.progressColor != progressColor;
}
