import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const NovaGenMobileApp());
}

class NovaGenMobileApp extends StatefulWidget {
  const NovaGenMobileApp({super.key});

  @override
  State<NovaGenMobileApp> createState() => _NovaGenMobileAppState();
}

class _NovaGenMobileAppState extends State<NovaGenMobileApp> {
  bool _darkMode = true;

  @override
  Widget build(BuildContext context) {
    final bg = _darkMode ? const Color(0xFF030712) : const Color(0xFFF4F6F9);
    final surface = _darkMode ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF);
    final text = _darkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    const accent = Color(0xFF2563EB);

    return MaterialApp(
      title: 'NovaGen Mobile Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: _darkMode ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bg,
        cardColor: surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: _darkMode ? Brightness.dark : Brightness.light,
        ).copyWith(surface: surface, primary: accent),
        textTheme: ThemeData(brightness: _darkMode ? Brightness.dark : Brightness.light)
            .textTheme
            .apply(bodyColor: text, displayColor: text),
        useMaterial3: true,
      ),
      home: NovaGenDashboard(
        darkMode: _darkMode,
        onToggleTheme: () => setState(() => _darkMode = !_darkMode),
      ),
    );
  }
}

class NovaGenDashboard extends StatefulWidget {
  final bool darkMode;
  final VoidCallback onToggleTheme;

  const NovaGenDashboard({
    super.key,
    required this.darkMode,
    required this.onToggleTheme,
  });

  @override
  State<NovaGenDashboard> createState() => _NovaGenDashboardState();
}

class _NovaGenDashboardState extends State<NovaGenDashboard> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.novagen.mobile/engine');
  int _tabIndex = 0;

  // Telemetry & Breakdown
  Map<String, dynamic> _telemetry = {};
  Map<String, dynamic> _storageBreakdown = {};
  bool _loadingBreakdown = false;

  // Boost / Junk
  bool _trimmingRam = false;
  String _ramMsg = '';
  bool _scanningJunk = false;
  bool _cleaningJunk = false;
  List<Map<String, dynamic>> _junkItems = [];
  int _sessionCleanedBytes = 0;

  // Duplicates (All Categories)
  bool _scanningDups = false;
  bool _cleaningDups = false;
  List<Map<String, dynamic>> _dupItems = [];
  String _dupCategoryFilter = 'All';

  // Large Files (All Categories)
  bool _scanningLarge = false;
  bool _deletingLarge = false;
  List<Map<String, dynamic>> _largeFiles = [];
  int _largeMinMb = 20;
  String _largeCategoryFilter = 'All';

  // Apps Manager
  bool _loadingApps = false;
  List<Map<String, dynamic>> _apps = [];
  String _appQuery = '';
  String _appFilter = 'All'; // All, Large, Cache
  bool _appSortByName = false;

  // Auto-Sort
  bool _scanningSort = false;
  bool _sortingDownloads = false;
  List<Map<String, dynamic>> _sortPreview = [];
  List<String> _sortLogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTelemetry();
    _scanBreakdown();
    _loadSortPreview();
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
      if (_tabIndex == 3 && _apps.isNotEmpty) {
        _loadApps();
      }
    }
  }

  // Agency 90-8-2 Palette
  Color get _surface => widget.darkMode ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF);
  Color get _well => widget.darkMode ? const Color(0xFF111C33) : const Color(0xFFF8FAFC);
  Color get _border => widget.darkMode ? const Color(0x2494A3B8) : const Color(0xFFE2E8F0);
  Color get _muted => widget.darkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _ink => widget.darkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  Color get _accentBlue => widget.darkMode ? const Color(0xFF2563EB) : const Color(0xFF0B3D91);
  Color get _accentCyan => widget.darkMode ? const Color(0xFF22D3EE) : const Color(0xFF1D4ED8);
  Color get _okGreen => const Color(0xFF059669);
  Color get _warnAmber => const Color(0xFFD97706);
  Color get _dangerRed => const Color(0xFFDC2626);

  static const _tabularStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

  String formatBytes(num bytes) {
    final b = bytes.toDouble();
    if (b < 1024) return '${b.toInt()} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _showSnack(String msg, {Color? bg}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  Future<void> _refreshTelemetry() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getTelemetry');
      if (res != null && mounted) {
        setState(() => _telemetry = res);
      }
    } catch (_) {}
  }

  Future<void> _scanBreakdown() async {
    setState(() => _loadingBreakdown = true);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('scanStorageBreakdown');
      if (res != null && mounted) {
        setState(() {
          _storageBreakdown = res;
          _loadingBreakdown = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBreakdown = false);
    }
  }

  Future<void> _openFilePreview(String path) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openFilePreview', {'path': path}) ?? false;
      if (!ok) _showSnack('No app found to open this file.');
    } catch (_) {}
  }

  Future<void> _trimRam() async {
    setState(() {
      _trimmingRam = true;
      _ramMsg = 'Trimming cached background processes...';
    });
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('trimBackgroundRam');
      await _refreshTelemetry();
      if (mounted && res != null) {
        final freedMb = res['freedMb'] ?? 0;
        final killed = res['killedApps'] ?? 0;
        setState(() {
          _ramMsg = 'Trimmed $killed cached processes · ${freedMb > 0 ? "$freedMb MB RAM freed" : "Memory optimized"}';
          _trimmingRam = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _trimmingRam = false);
    }
  }

  Future<void> _scanJunk() async {
    if (!(_telemetry['hasStorage'] == true)) {
      await _channel.invokeMethod('requestStoragePermission');
      return;
    }
    setState(() {
      _scanningJunk = true;
      _junkItems = [];
    });
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanSafeJunk') ?? [];
      setState(() {
        _junkItems = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _scanningJunk = false;
      });
    } catch (_) {
      setState(() => _scanningJunk = false);
    }
  }

  Future<void> _cleanSelectedJunk() async {
    final selected = _junkItems.where((it) => it['selected'] == true).toList();
    if (selected.isEmpty) return;
    setState(() => _cleaningJunk = true);
    try {
      final paths = selected.map((e) => e['path'].toString()).toList();
      final freed = await _channel.invokeMethod<int>('cleanJunkItems', {'paths': paths}) ?? 0;
      await _refreshTelemetry();
      await _scanBreakdown();
      setState(() {
        _sessionCleanedBytes += freed;
        _junkItems.removeWhere((it) => it['selected'] == true);
        _cleaningJunk = false;
      });
      _showSnack('Wiped ${selected.length} items (${formatBytes(freed)} freed)', bg: _okGreen);
    } catch (_) {
      setState(() => _cleaningJunk = false);
    }
  }

  Future<void> _scanDuplicates() async {
    if (!(_telemetry['hasStorage'] == true)) {
      await _channel.invokeMethod('requestStoragePermission');
      return;
    }
    setState(() {
      _scanningDups = true;
      _dupItems = [];
      _dupCategoryFilter = 'All';
    });
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanDuplicates') ?? [];
      setState(() {
        _dupItems = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _scanningDups = false;
      });
    } catch (_) {
      setState(() => _scanningDups = false);
    }
  }

  Future<void> _cleanSelectedDups() async {
    final selected = _dupItems.where((it) => it['selected'] == true).toList();
    if (selected.isEmpty) return;
    setState(() => _cleaningDups = true);
    try {
      final paths = selected.map((e) => e['path'].toString()).toList();
      final freed = await _channel.invokeMethod<int>('cleanJunkItems', {'paths': paths}) ?? 0;
      await _refreshTelemetry();
      await _scanBreakdown();
      setState(() {
        _sessionCleanedBytes += freed;
        _dupItems.removeWhere((it) => it['selected'] == true);
        // Remove singleton groups where all duplicates were deleted so orphaned ORIGINAL cards don't clutter
        final groupCounts = <String, int>{};
        for (final it in _dupItems) {
          final gid = it['groupId']?.toString() ?? '';
          groupCounts[gid] = (groupCounts[gid] ?? 0) + 1;
        }
        _dupItems.removeWhere((it) => (groupCounts[it['groupId']?.toString() ?? ''] ?? 0) <= 1);
        _cleaningDups = false;
      });
      _showSnack('Deleted ${selected.length} duplicates (${formatBytes(freed)} freed). Originals kept safe!', bg: _okGreen);
    } catch (_) {
      setState(() => _cleaningDups = false);
    }
  }

  Future<void> _scanLargeFiles() async {
    if (!(_telemetry['hasStorage'] == true)) {
      await _channel.invokeMethod('requestStoragePermission');
      return;
    }
    setState(() {
      _scanningLarge = true;
      _largeFiles = [];
    });
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanLargeFiles', {'minMb': _largeMinMb}) ?? [];
      setState(() {
        _largeFiles = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _scanningLarge = false;
      });
    } catch (_) {
      setState(() => _scanningLarge = false);
    }
  }

  Future<void> _deleteSelectedLargeFiles() async {
    final selected = _largeFiles.where((f) => f['selected'] == true).toList();
    if (selected.isEmpty) return;
    final ok = await _confirmDelete('${selected.length} large files', selected.fold<int>(0, (s, e) => s + ((e['size'] as num?)?.toInt() ?? 0)));
    if (!ok) return;
    setState(() => _deletingLarge = true);
    try {
      final paths = selected.map((e) => e['path'].toString()).toList();
      final freed = await _channel.invokeMethod<int>('cleanJunkItems', {'paths': paths}) ?? 0;
      await _refreshTelemetry();
      await _scanBreakdown();
      setState(() {
        _sessionCleanedBytes += freed;
        _largeFiles.removeWhere((f) => f['selected'] == true);
        _deletingLarge = false;
      });
      _showSnack('Deleted ${selected.length} files (${formatBytes(freed)} freed)', bg: _okGreen);
    } catch (_) {
      setState(() => _deletingLarge = false);
    }
  }

  Future<void> _loadApps() async {
    setState(() => _loadingApps = true);
    try {
      final raw = await _channel.invokeListMethod<dynamic>('scanInstalledApps') ?? [];
      setState(() {
        _apps = raw.map((e) => Map<String, dynamic>.from(e as Map)..['selected'] = false).toList();
        _loadingApps = false;
      });
    } catch (_) {
      setState(() => _loadingApps = false);
    }
  }

  Future<void> _loadSortPreview() async {
    setState(() => _scanningSort = true);
    try {
      final raw = await _channel.invokeListMethod<dynamic>('previewDownloadSort') ?? [];
      setState(() {
        _sortPreview = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _scanningSort = false;
      });
    } catch (_) {
      setState(() => _scanningSort = false);
    }
  }

  Future<void> _executeSelectedSort() async {
    final selected = _sortPreview.where((e) => e['selected'] == true).toList();
    if (selected.isEmpty) return;
    setState(() => _sortingDownloads = true);
    try {
      final paths = selected.map((e) => e['path'].toString()).toList();
      final res = await _channel.invokeListMethod<dynamic>('executeSelectedSort', {'paths': paths}) ?? [];
      await _loadSortPreview();
      setState(() {
        _sortLogs = res.map((e) => e.toString()).toList();
        _sortingDownloads = false;
      });
      _showSnack('Sorted ${res.length} files into /Download/Sorted/', bg: _okGreen);
    } catch (_) {
      setState(() => _sortingDownloads = false);
    }
  }

  Future<bool> _confirmDelete(String label, int bytes) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Permanent Delete', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text('Permanently delete $label (${formatBytes(bytes)})?\nThis cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _dangerRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final model = _telemetry['deviceModel'] ?? 'Android Device';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
        titleSpacing: 14,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _accentBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('NOVAGEN MOBILE PRO', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _accentBlue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _accentBlue.withValues(alpha: 0.35)),
                        ),
                        child: Text('v3.0', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: _accentCyan)),
                      ),
                    ],
                  ),
                  Text('$model · ${_telemetry['androidVersion'] ?? ''}', style: TextStyle(fontSize: 10.5, color: _muted)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(widget.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: _accentCyan, size: 20),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: 'Refresh Telemetry',
            icon: Icon(Icons.refresh_rounded, color: _ink, size: 20),
            onPressed: () {
              _refreshTelemetry();
              _scanBreakdown();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildBoostTab(),
          _buildDuplicatesTab(),
          _buildLargeFilesTab(),
          _buildAppsTab(),
          _buildAutoSortTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: _border))),
        child: NavigationBar(
          backgroundColor: _surface,
          height: 62,
          indicatorColor: _accentBlue.withValues(alpha: 0.16),
          selectedIndex: _tabIndex,
          onDestinationSelected: (i) {
            setState(() => _tabIndex = i);
            if (i == 3 && _apps.isEmpty) _loadApps();
            if (i == 4 && _sortPreview.isEmpty) _loadSortPreview();
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt_rounded), label: 'Boost'),
            NavigationDestination(icon: Icon(Icons.control_point_duplicate_outlined), selectedIcon: Icon(Icons.control_point_duplicate_rounded), label: 'Duplicates'),
            NavigationDestination(icon: Icon(Icons.folder_zip_outlined), selectedIcon: Icon(Icons.folder_zip_rounded), label: 'Large Files'),
            NavigationDestination(icon: Icon(Icons.apps_outlined), selectedIcon: Icon(Icons.apps_rounded), label: 'Apps'),
            NavigationDestination(icon: Icon(Icons.folder_copy_outlined), selectedIcon: Icon(Icons.folder_copy_rounded), label: 'Auto-Sort'),
          ],
        ),
      ),
    );
  }

  // Shared Selection Header Strip
  Widget _buildSelectionStrip({
    required int totalCount,
    required int selectedCount,
    required int selectedBytes,
    required VoidCallback onSelectAll,
    required VoidCallback onClear,
    String? primarySelectLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _well,
        border: Border(top: BorderSide(color: _border), bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Text('$totalCount items', style: TextStyle(fontSize: 11.5, color: _muted, fontWeight: FontWeight.w600).merge(_tabularStyle)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: selectedCount > 0 ? _okGreen.withValues(alpha: 0.12) : _surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: selectedCount > 0 ? _okGreen.withValues(alpha: 0.4) : _border),
            ),
            child: Text(
              'Selected: $selectedCount (${formatBytes(selectedBytes)})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selectedCount > 0 ? _okGreen : _muted,
              ).merge(_tabularStyle),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onSelectAll,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(primarySelectLabel ?? 'Select All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _accentCyan)),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text('Clear', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumb(String? b64, IconData fallbackIcon, Color fallbackColor) {
    if (b64 != null && b64.isNotEmpty) {
      try {
        final bytes = base64Decode(b64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _well,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _border),
      ),
      child: Icon(fallbackIcon, color: fallbackColor, size: 20),
    );
  }

  IconData _iconForCategory(String cat) {
    switch (cat) {
      case 'Videos':
        return Icons.movie_rounded;
      case 'Images':
        return Icons.image_rounded;
      case 'Audio':
        return Icons.audiotrack_rounded;
      case 'Docs':
        return Icons.description_rounded;
      case 'APKs':
        return Icons.android_rounded;
      case 'Archives':
        return Icons.archive_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Widget _buildCategoryChips(
    List<String> categories,
    String active,
    Map<String, int> counts,
    ValueChanged<String> onSelected,
  ) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final cnt = counts[cat] ?? 0;
          final isSel = active == cat;
          return ChoiceChip(
            label: Text('$cat ($cnt)', style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500).merge(_tabularStyle)),
            selected: isSel,
            selectedColor: _accentBlue.withValues(alpha: 0.2),
            side: BorderSide(color: isSel ? _accentBlue : _border),
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onSelected(cat),
          );
        },
      ),
    );
  }

  // ==================== TAB 1: BOOST & JUNK ====================
  Widget _buildBoostTab() {
    final totalRam = (_telemetry['totalRam'] as num?)?.toDouble() ?? 1;
    final availRam = (_telemetry['availRam'] as num?)?.toDouble() ?? 0;
    final usedRam = (totalRam - availRam).clamp(0, totalRam);
    final ramPct = (usedRam / totalRam).clamp(0.0, 1.0);

    final totalStor = (_telemetry['totalStorage'] as num?)?.toDouble() ?? 1;
    final freeStor = (_telemetry['freeStorage'] as num?)?.toDouble() ?? 0;
    final batLvl = _telemetry['batteryLevel'] ?? 0;
    final batTemp = (_telemetry['batteryTemp'] as num?)?.toDouble() ?? 0.0;
    final hasStorage = _telemetry['hasStorage'] == true;

    final selItems = _junkItems.where((e) => e['selected'] == true).toList();
    final selBytes = selItems.fold<int>(0, (s, e) => s + ((e['size'] as num?)?.toInt() ?? 0));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (!hasStorage)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _warnAmber.withValues(alpha: 0.08),
                    border: Border.all(color: _warnAmber.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: _warnAmber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Grant All Files Access to scan full storage, duplicates & large files.', style: TextStyle(fontSize: 11.5, color: _ink)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _accentBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12)),
                        onPressed: () => _channel.invokeMethod('requestStoragePermission'),
                        child: const Text('Grant', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),

              // Compact Enterprise Telemetry Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: CustomPaint(
                        painter: _RingPainter(
                          progress: ramPct,
                          color: ramPct > 0.85 ? _dangerRed : _accentCyan,
                          trackColor: _well,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${(ramPct * 100).round()}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800).merge(_tabularStyle)),
                              Text('RAM USED', style: TextStyle(fontSize: 8.5, letterSpacing: 0.5, color: _muted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_ramMsg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(_ramMsg, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _okGreen)),
                            ),
                          _kvRow('RAM', '${formatBytes(usedRam)} / ${formatBytes(totalRam)}'),
                          _kvRow('Free Storage', '${formatBytes(freeStor)} / ${formatBytes(totalStor)}'),
                          _kvRow('Battery', '$batLvl% · ${batTemp.toStringAsFixed(1)}°C'),
                          _kvRow('Session Freed', formatBytes(_sessionCleanedBytes), highlight: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Monochrome Tonal Storage Breakdown Card
              if (_storageBreakdown.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('STORAGE ALLOCATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: _muted)),
                          if (_loadingBreakdown) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildBreakdownBar(),
                    ],
                  ),
                ),

              // Primary Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _trimmingRam ? null : _trimRam,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _border),
                        backgroundColor: _surface,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(Icons.memory_rounded, size: 17, color: _accentCyan),
                      label: Text(_trimmingRam ? 'Trimming...' : 'Trim RAM', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _scanningJunk ? null : _scanJunk,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _scanningJunk
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search_rounded, size: 17),
                      label: Text(_scanningJunk ? 'Scanning...' : 'Scan Safe Junk', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_junkItems.isNotEmpty) ...[
                _buildSelectionStrip(
                  totalCount: _junkItems.length,
                  selectedCount: selItems.length,
                  selectedBytes: selBytes,
                  primarySelectLabel: 'Select All',
                  onSelectAll: () => setState(() {
                    for (final it in _junkItems) {
                      it['selected'] = true;
                    }
                  }),
                  onClear: () => setState(() {
                    for (final it in _junkItems) {
                      it['selected'] = false;
                    }
                  }),
                ),
                const SizedBox(height: 8),
                ..._junkItems.map((it) {
                  final sel = it['selected'] == true;
                  final tag = it['tag']?.toString() ?? 'SAFE';
                  final isCorpse = tag == 'CORPSE';
                  return InkWell(
                    onTap: () => setState(() => it['selected'] = !sel),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? _accentBlue.withValues(alpha: 0.06) : _surface,
                        border: Border.all(color: sel ? _accentBlue.withValues(alpha: 0.45) : _border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: sel,
                            onChanged: (v) => setState(() => it['selected'] = v ?? false),
                            visualDensity: VisualDensity.compact,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(it['category'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: (isCorpse ? _warnAmber : _accentCyan).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isCorpse ? _warnAmber : _accentCyan)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(formatBytes((it['size'] as num?) ?? 0), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _okGreen).merge(_tabularStyle)),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(it['path'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: _muted))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ] else if (!_scanningJunk)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
                  child: Center(
                    child: Text('Tap "Scan Safe Junk" to detect leftovers, caches, empty folders & old APKs.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: _muted)),
                  ),
                ),
            ],
          ),
        ),
        if (selItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _border))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _cleaningJunk ? null : _cleanSelectedJunk,
                style: FilledButton.styleFrom(backgroundColor: _dangerRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text(_cleaningJunk ? 'Wiping...' : 'Wipe ${selItems.length} Selected (${formatBytes(selBytes)})', style: const TextStyle(fontWeight: FontWeight.w700).merge(_tabularStyle)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBreakdownBar() {
    final videos = (_storageBreakdown['videos'] as num?)?.toDouble() ?? 0;
    final images = (_storageBreakdown['images'] as num?)?.toDouble() ?? 0;
    final audio = (_storageBreakdown['audio'] as num?)?.toDouble() ?? 0;
    final docs = (_storageBreakdown['docs'] as num?)?.toDouble() ?? 0;
    final apks = (_storageBreakdown['apks'] as num?)?.toDouble() ?? 0;
    final total = max(1.0, videos + images + audio + docs + apks);

    // Monochrome stepped tonal ramp (agency-enterprise-ui-ux)
    final segments = [
      ('Videos', videos, const Color(0xFF1D4ED8)),
      ('Photos', images, const Color(0xFF3B82F6)),
      ('Audio', audio, const Color(0xFF60A5FA)),
      ('Docs', docs, const Color(0xFF94A3B8)),
      ('APKs', apks, const Color(0xFFCBD5E1)),
    ];

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: Row(
              children: segments
                  .where((s) => s.$2 > 0)
                  .map((s) => Expanded(
                        flex: max(1, ((s.$2 / total) * 1000).round()),
                        child: Container(color: s.$3),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 5,
          children: segments
              .map((s) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 5),
                      Text('${s.$1}: ${formatBytes(s.$2)}', style: TextStyle(fontSize: 10.5, color: _ink, fontWeight: FontWeight.w500).merge(_tabularStyle)),
                    ],
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _kvRow(String k, String v, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 11.5, color: _muted)),
          Text(v, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: highlight ? _okGreen : _ink).merge(_tabularStyle)),
        ],
      ),
    );
  }

  // ==================== TAB 2: FULL-PHONE DUPLICATES ====================
  Widget _buildDuplicatesTab() {
    const cats = ['All', 'Images', 'Videos', 'Audio', 'Docs', 'APKs', 'Archives', 'Other'];
    final counts = <String, int>{'All': _dupItems.length};
    for (final c in cats.skip(1)) {
      counts[c] = _dupItems.where((it) => it['category'] == c).length;
    }

    final visible = _dupCategoryFilter == 'All'
        ? _dupItems
        : _dupItems.where((it) => it['category'] == _dupCategoryFilter).toList();

    final selAll = _dupItems.where((it) => it['selected'] == true).toList();
    final selBytes = selAll.fold<int>(0, (s, it) => s + ((it['size'] as num?)?.toInt() ?? 0));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ALL-FILE DUPLICATE ENGINE', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                    Text('Scans MP3, MP4, Photos, Docs, APKs & ZIPs · Originals kept safe', style: TextStyle(fontSize: 10.5, color: _muted)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _scanningDups ? null : _scanDuplicates,
                style: FilledButton.styleFrom(backgroundColor: _accentBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: _scanningDups
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.control_point_duplicate_rounded, size: 17),
                label: Text(_scanningDups ? 'Scanning...' : 'Scan All', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        if (_dupItems.isNotEmpty) ...[
          _buildCategoryChips(
            cats.where((c) => c == 'All' || (counts[c] ?? 0) > 0).toList(),
            _dupCategoryFilter,
            counts,
            (c) => setState(() => _dupCategoryFilter = c),
          ),
          const SizedBox(height: 6),
          _buildSelectionStrip(
            totalCount: visible.length,
            selectedCount: selAll.length,
            selectedBytes: selBytes,
            primarySelectLabel: 'Select Dups',
            onSelectAll: () => setState(() {
              for (final it in visible) {
                if (it['isOriginal'] != true) it['selected'] = true;
              }
            }),
            onClear: () => setState(() {
              for (final it in visible) {
                it['selected'] = false;
              }
            }),
          ),
        ],
        Expanded(
          child: _dupItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _scanningDups
                          ? 'Deep scanning storage for duplicate Videos, MP3s, Photos, Docs & APKs...'
                          : 'Tap "Scan All" to find exact & similar duplicates across your entire phone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 12.5),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) {
                    final it = visible[i];
                    final isOrig = it['isOriginal'] == true;
                    final sel = it['selected'] == true;
                    final cat = it['category']?.toString() ?? 'Other';

                    return InkWell(
                      onTap: () => setState(() => it['selected'] = !sel),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? _dangerRed.withValues(alpha: 0.06) : _surface,
                          border: Border.all(
                            color: sel
                                ? _dangerRed.withValues(alpha: 0.5)
                                : (isOrig ? _okGreen.withValues(alpha: 0.45) : _border),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: sel,
                              onChanged: (v) => setState(() => it['selected'] = v ?? false),
                              visualDensity: VisualDensity.compact,
                            ),
                            GestureDetector(
                              onTap: () => _openFilePreview(it['path'].toString()),
                              child: _buildThumb(it['thumb']?.toString(), _iconForCategory(cat), _accentCyan),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(it['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isOrig ? _okGreen : _warnAmber).withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isOrig ? 'ORIGINAL' : 'DUPLICATE',
                                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: isOrig ? _okGreen : _warnAmber),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$cat · ${formatBytes((it['size'] as num?) ?? 0)} · ${it['type']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _accentCyan).merge(_tabularStyle),
                                  ),
                                  Text(it['path'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: _muted)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Play / Open',
                              icon: Icon(cat == 'Videos' || cat == 'Audio' ? Icons.play_circle_outline_rounded : Icons.open_in_new_rounded, color: _accentCyan, size: 20),
                              onPressed: () => _openFilePreview(it['path'].toString()),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (selAll.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _border))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _cleaningDups ? null : _cleanSelectedDups,
                style: FilledButton.styleFrom(backgroundColor: _dangerRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: Text(_cleaningDups ? 'Deleting...' : 'Delete ${selAll.length} Duplicates (${formatBytes(selBytes)})', style: const TextStyle(fontWeight: FontWeight.w700).merge(_tabularStyle)),
              ),
            ),
          ),
      ],
    );
  }

  // ==================== TAB 3: LARGE FILES (ALL CATEGORIES + MULTI-SELECT) ====================
  Widget _buildLargeFilesTab() {
    const cats = ['All', 'Videos', 'Images', 'Audio', 'Docs', 'APKs', 'Archives', 'Other'];
    final counts = <String, int>{'All': _largeFiles.length};
    for (final c in cats.skip(1)) {
      counts[c] = _largeFiles.where((f) => f['category'] == c).length;
    }

    final visible = _largeCategoryFilter == 'All'
        ? _largeFiles
        : _largeFiles.where((f) => f['category'] == _largeCategoryFilter).toList();

    final selAll = _largeFiles.where((f) => f['selected'] == true).toList();
    final selBytes = selAll.fold<int>(0, (s, f) => s + ((f['size'] as num?)?.toInt() ?? 0));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LARGE FILE EXPLORER (>$_largeMinMb MB)', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.4).merge(_tabularStyle)),
                    Text('Play/preview videos, audio & docs, or multi-select to delete', style: TextStyle(fontSize: 10.5, color: _muted)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _scanningLarge ? null : _scanLargeFiles,
                style: FilledButton.styleFrom(backgroundColor: _accentBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: _scanningLarge
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.radar_rounded, size: 17),
                label: Text(_scanningLarge ? 'Scanning...' : 'Scan', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // Size Threshold Chips
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [10, 20, 50, 100].map((mb) {
              final isSel = _largeMinMb == mb;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('>$mb MB', style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500).merge(_tabularStyle)),
                  selected: isSel,
                  selectedColor: _accentBlue.withValues(alpha: 0.2),
                  side: BorderSide(color: isSel ? _accentBlue : _border),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _largeMinMb = mb);
                    _scanLargeFiles();
                  },
                ),
              );
            }).toList(),
          ),
        ),
        if (_largeFiles.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildCategoryChips(
            cats.where((c) => c == 'All' || (counts[c] ?? 0) > 0).toList(),
            _largeCategoryFilter,
            counts,
            (c) => setState(() => _largeCategoryFilter = c),
          ),
          const SizedBox(height: 6),
          _buildSelectionStrip(
            totalCount: visible.length,
            selectedCount: selAll.length,
            selectedBytes: selBytes,
            onSelectAll: () => setState(() {
              for (final f in visible) {
                f['selected'] = true;
              }
            }),
            onClear: () => setState(() {
              for (final f in visible) {
                f['selected'] = false;
              }
            }),
          ),
        ],
        Expanded(
          child: _largeFiles.isEmpty
              ? Center(
                  child: Text(
                    _scanningLarge ? 'Scanning storage for files > $_largeMinMb MB...' : 'Tap "Scan" to locate large Videos, APKs, Archives & Docs.',
                    style: TextStyle(color: _muted, fontSize: 12.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) {
                    final f = visible[i];
                    final sel = f['selected'] == true;
                    final cat = f['category']?.toString() ?? 'Other';
                    final isPlayable = cat == 'Videos' || cat == 'Audio';

                    return InkWell(
                      onTap: () => setState(() => f['selected'] = !sel),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? _dangerRed.withValues(alpha: 0.06) : _surface,
                          border: Border.all(color: sel ? _dangerRed.withValues(alpha: 0.5) : _border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: sel,
                              onChanged: (v) => setState(() => f['selected'] = v ?? false),
                              visualDensity: VisualDensity.compact,
                            ),
                            GestureDetector(
                              onTap: () => _openFilePreview(f['path'].toString()),
                              child: _buildThumb(f['thumb']?.toString(), _iconForCategory(cat), _accentCyan),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$cat · ${formatBytes((f['size'] as num?) ?? 0)} · ${f['ext']}',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _accentCyan).merge(_tabularStyle),
                                  ),
                                  Text(f['path'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: _muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _openFilePreview(f['path'].toString()),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _accentBlue.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _accentBlue.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(isPlayable ? Icons.play_arrow_rounded : Icons.visibility_outlined, size: 15, color: _accentCyan),
                                    const SizedBox(width: 3),
                                    Text(isPlayable ? 'Play' : 'Open', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _accentCyan)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (selAll.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _border))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _deletingLarge ? null : _deleteSelectedLargeFiles,
                style: FilledButton.styleFrom(backgroundColor: _dangerRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: Text(_deletingLarge ? 'Deleting...' : 'Delete ${selAll.length} Files (${formatBytes(selBytes)})', style: const TextStyle(fontWeight: FontWeight.w700).merge(_tabularStyle)),
              ),
            ),
          ),
      ],
    );
  }

  // ==================== TAB 4: APPS MANAGER (MULTI-SELECT) ====================
  Widget _buildAppsTab() {
    var filtered = _apps.where((a) {
      if (_appQuery.isNotEmpty &&
          !a['name'].toString().toLowerCase().contains(_appQuery) &&
          !a['packageName'].toString().toLowerCase().contains(_appQuery)) {
        return false;
      }
      if (_appFilter == 'Large') return ((a['totalBytes'] as num?) ?? 0) >= 100 * 1024 * 1024;
      if (_appFilter == 'Cache') return ((a['cacheBytes'] as num?) ?? 0) > 0;
      return true;
    }).toList();

    if (_appSortByName) {
      filtered.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
    } else {
      filtered.sort((a, b) => ((b['totalBytes'] as num?) ?? 0).compareTo((a['totalBytes'] as num?) ?? 0));
    }

    final selApps = _apps.where((a) => a['selected'] == true).toList();
    final selBytes = selApps.fold<int>(0, (s, a) => s + ((a['totalBytes'] as num?)?.toInt() ?? 0));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search installed apps...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: _surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _border)),
                  ),
                  onChanged: (v) => setState(() => _appQuery = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _appSortByName ? 'Sorting: Name A-Z' : 'Sorting: Size ↓',
                onPressed: () => setState(() => _appSortByName = !_appSortByName),
                icon: Icon(_appSortByName ? Icons.sort_by_alpha_rounded : Icons.sort_rounded, size: 19),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Refresh Apps',
                onPressed: _loadingApps ? null : _loadApps,
                icon: _loadingApps ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: ['All', 'Large', 'Cache'].map((f) {
              final isSel = _appFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f == 'Large' ? 'Large >100MB' : f, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500)),
                  selected: isSel,
                  selectedColor: _accentBlue.withValues(alpha: 0.2),
                  side: BorderSide(color: isSel ? _accentBlue : _border),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _appFilter = f),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        if (_apps.isNotEmpty)
          _buildSelectionStrip(
            totalCount: filtered.length,
            selectedCount: selApps.length,
            selectedBytes: selBytes,
            onSelectAll: () => setState(() {
              for (final a in filtered) {
                a['selected'] = true;
              }
            }),
            onClear: () => setState(() {
              for (final a in filtered) {
                a['selected'] = false;
              }
            }),
          ),
        Expanded(
          child: _loadingApps
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final a = filtered[i];
                    final sel = a['selected'] == true;
                    final cacheBytes = (a['cacheBytes'] as num?) ?? 0;
                    final totalBytes = (a['totalBytes'] as num?) ?? 0;
                    return InkWell(
                      onTap: () => setState(() => a['selected'] = !sel),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? _accentBlue.withValues(alpha: 0.06) : _surface,
                          border: Border.all(color: sel ? _accentBlue.withValues(alpha: 0.45) : _border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: sel,
                              onChanged: (v) => setState(() => a['selected'] = v ?? false),
                              visualDensity: VisualDensity.compact,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  Text('${a['packageName']} · ${formatBytes(totalBytes)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: _muted).merge(_tabularStyle)),
                                  Text('Cache: ${formatBytes(cacheBytes)}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _accentCyan).merge(_tabularStyle)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Backup APK',
                              icon: Icon(Icons.download_rounded, color: _muted, size: 19),
                              onPressed: () async {
                                final out = await _channel.invokeMethod<String>('backupAppApk', {
                                  'packageName': a['packageName'],
                                  'appName': a['name'],
                                });
                                _showSnack('APK saved: $out');
                              },
                            ),
                            IconButton(
                              tooltip: 'App Info / Clear Cache',
                              icon: Icon(Icons.settings_outlined, color: _accentCyan, size: 19),
                              onPressed: () => _channel.invokeMethod('openAppSettings', {'packageName': a['packageName']}),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (selApps.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _border))),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      int saved = 0;
                      for (final a in selApps) {
                        final res = await _channel.invokeMethod<String>('backupAppApk', {
                          'packageName': a['packageName'],
                          'appName': a['name'],
                        });
                        if (res != null && !res.startsWith('ERROR')) saved++;
                      }
                      _showSnack('Backed up $saved APKs to /Download/NovaGen_Backups', bg: _okGreen);
                    },
                    style: OutlinedButton.styleFrom(side: BorderSide(color: _border), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    icon: const Icon(Icons.download_rounded, size: 17),
                    label: Text('Backup (${selApps.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final pkgs = selApps.map((a) => a['packageName'].toString()).toList();
                      final ok = await _channel.invokeMethod<bool>('uninstallPackages', {'packages': pkgs}) ?? false;
                      if (!ok) _showSnack('Could not launch system uninstaller.', bg: _dangerRed);
                    },
                    style: FilledButton.styleFrom(backgroundColor: _dangerRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    label: Text('Uninstall (${selApps.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ==================== TAB 5: AUTO-SORT DOWNLOADS (PREVIEW + MULTI-SELECT) ====================
  Widget _buildAutoSortTab() {
    final selItems = _sortPreview.where((e) => e['selected'] == true).toList();
    final selBytes = selItems.fold<int>(0, (s, e) => s + ((e['size'] as num?)?.toInt() ?? 0));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SMART DOWNLOADS AUTO-SORT', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                    Text('Organizes /Download into Sorted/{Videos, Audio, Docs, Images, APKs}', style: TextStyle(fontSize: 10.5, color: _muted)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _scanningSort ? null : _loadSortPreview,
                style: FilledButton.styleFrom(backgroundColor: _accentBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: _scanningSort
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, size: 17),
                label: Text(_scanningSort ? 'Scanning...' : 'Scan', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        if (_sortPreview.isNotEmpty)
          _buildSelectionStrip(
            totalCount: _sortPreview.length,
            selectedCount: selItems.length,
            selectedBytes: selBytes,
            onSelectAll: () => setState(() {
              for (final e in _sortPreview) {
                e['selected'] = true;
              }
            }),
            onClear: () => setState(() {
              for (final e in _sortPreview) {
                e['selected'] = false;
              }
            }),
          ),
        Expanded(
          child: _sortPreview.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: _surface, border: Border.all(color: _border), borderRadius: BorderRadius.circular(10)),
                      child: Center(
                        child: Text(
                          _sortLogs.isEmpty
                              ? 'Your /Download root is already clean! No loose files waiting to be sorted.'
                              : 'Sorted ${_sortLogs.length} files into /Download/Sorted/',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: _sortLogs.isEmpty ? _muted : _okGreen, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_sortLogs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ..._sortLogs.map((l) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• $l', style: TextStyle(fontSize: 11.5, color: _ink)),
                          )),
                    ],
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sortPreview.length,
                  itemBuilder: (ctx, i) {
                    final it = _sortPreview[i];
                    final sel = it['selected'] == true;
                    return InkWell(
                      onTap: () => setState(() => it['selected'] = !sel),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? _accentBlue.withValues(alpha: 0.06) : _surface,
                          border: Border.all(color: sel ? _accentBlue.withValues(alpha: 0.45) : _border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: sel,
                              onChanged: (v) => setState(() => it['selected'] = v ?? false),
                              visualDensity: VisualDensity.compact,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  Text(
                                    '-> Sorted/${it['targetCategory']} · ${formatBytes((it['size'] as num?) ?? 0)}',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _accentCyan).merge(_tabularStyle),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (selItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _border))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sortingDownloads ? null : _executeSelectedSort,
                style: FilledButton.styleFrom(backgroundColor: _accentBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_sortingDownloads ? 'Sorting...' : 'Sort ${selItems.length} Selected (${formatBytes(selBytes)})', style: const TextStyle(fontWeight: FontWeight.w700).merge(_tabularStyle)),
              ),
            ),
          ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _RingPainter({required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 5;
    const stroke = 7.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}
