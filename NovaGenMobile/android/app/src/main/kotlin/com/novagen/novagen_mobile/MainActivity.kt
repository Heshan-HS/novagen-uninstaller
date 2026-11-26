package com.novagen.novagen_mobile

import android.Manifest
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.novagen.mobile/engine"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTelemetry" -> {
                    executor.execute {
                        val data = collectTelemetry()
                        mainHandler.post { result.success(data) }
                    }
                }
                "requestStoragePermission" -> {
                    requestAllFilesPermission()
                    result.success(true)
                }
                "requestUsagePermission" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "trimBackgroundRam" -> {
                    executor.execute {
                        val res = trimRam()
                        mainHandler.post { result.success(res) }
                    }
                }
                "scanSafeJunk" -> {
                    executor.execute {
                        val items = scanSafeJunk()
                        mainHandler.post { result.success(items) }
                    }
                }
                "cleanJunkItems" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    executor.execute {
                        val freed = cleanPaths(paths)
                        mainHandler.post { result.success(freed) }
                    }
                }
                "scanInstalledApps" -> {
                    executor.execute {
                        val apps = getInstalledAppsStats()
                        mainHandler.post { result.success(apps) }
                    }
                }
                "openAppSettings" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    if (pkg.isNotEmpty()) {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$pkg")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "backupAppApk" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: pkg
                    executor.execute {
                        val outPath = extractApkBackup(pkg, appName)
                        mainHandler.post { result.success(outPath) }
                    }
                }
                "scanLargeFiles" -> {
                    val minMb = call.argument<Int>("minMb") ?: 50
                    executor.execute {
                        val items = findLargeFiles(minMb)
                        mainHandler.post { result.success(items) }
                    }
                }
                "sortDownloadsFolder" -> {
                    executor.execute {
                        val movedList = sortDownloads()
                        mainHandler.post { result.success(movedList) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasStorageAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasUsageStatsAccess(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    private fun requestAllFilesPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE),
                1001
            )
        }
    }

    private fun collectTelemetry(): Map<String, Any> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        val totalRam = mi.totalMem
        val availRam = mi.availMem
        val usedRam = (totalRam - availRam).coerceAtLeast(0L)
        val ramPct = if (totalRam > 0) ((usedRam * 100.0) / totalRam).toInt() else 0

        val stat = StatFs(Environment.getDataDirectory().path)
        val totalStorage = stat.totalBytes
        val availStorage = stat.availableBytes
        val usedStorage = (totalStorage - availStorage).coerceAtLeast(0L)
        val storagePct = if (totalStorage > 0) ((usedStorage * 100.0) / totalStorage).toInt() else 0

        val batIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val batPct = if (level >= 0 && scale > 0) (level * 100) / scale else 0
        val tempTenths = batIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val tempC = tempTenths / 10.0
        val voltMv = batIntent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0) ?: 0
        val status = batIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

        return mapOf(
            "totalRam" to totalRam,
            "availRam" to availRam,
            "usedRam" to usedRam,
            "ramPercent" to ramPct,
            "totalStorage" to totalStorage,
            "availStorage" to availStorage,
            "usedStorage" to usedStorage,
            "storagePercent" to storagePct,
            "batteryPercent" to batPct,
            "batteryTempC" to tempC,
            "batteryVoltageMv" to voltMv,
            "isCharging" to isCharging,
            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "androidVersion" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"),
            "hasStorage" to hasStorageAccess(),
            "hasUsage" to hasUsageStatsAccess()
        )
    }

    private fun trimRam(): Map<String, Any> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val miBefore = ActivityManager.MemoryInfo()
        am.getMemoryInfo(miBefore)

        var trimmedCount = 0
        try {
            val pkgs = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            for (app in pkgs) {
                if (app.packageName == packageName) continue
                if ((app.flags and ApplicationInfo.FLAG_SYSTEM) == 0) {
                    try {
                        am.killBackgroundProcesses(app.packageName)
                        trimmedCount++
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
        System.gc()
        Thread.sleep(300)

        val miAfter = ActivityManager.MemoryInfo()
        am.getMemoryInfo(miAfter)
        val freedBytes = (miAfter.availMem - miBefore.availMem).coerceAtLeast(0L)
        val freedMb = (freedBytes / (1024L * 1024L)).toInt()
        return mapOf("freedMb" to freedMb, "trimmedApps" to trimmedCount)
    }

    private fun dirSize(dir: File): Long {
        if (!dir.exists()) return 0L
        if (dir.isFile) return dir.length()
        var sum = 0L
        val stack = ArrayDeque<File>()
        stack.add(dir)
        while (stack.isNotEmpty()) {
            val cur = stack.removeLast()
            val files = cur.listFiles() ?: continue
            for (f in files) {
                if (f.isFile) sum += f.length()
                else if (f.isDirectory) stack.add(f)
            }
        }
        return sum
    }

    private fun scanSafeJunk(): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val root = Environment.getExternalStorageDirectory()
        if (!root.exists()) return results

        // 1. Thumbnails Cache
        for (thumbPath in listOf("DCIM/.thumbnails", "Pictures/.thumbnails", "Movies/.thumbnails")) {
            val f = File(root, thumbPath)
            if (f.exists() && f.isDirectory) {
                val sz = dirSize(f)
                if (sz > 64 * 1024L) {
                    results.add(mapOf("category" to "Thumbnail Cache", "tag" to "SAFE CACHE", "size" to sz, "path" to f.absolutePath, "selected" to true))
                }
            }
        }

        // 2. WhatsApp / Telegram Sent & Status Cache
        val msgPaths = listOf(
            "WhatsApp/Media/WhatsApp Images/Sent" to "WhatsApp Sent Images",
            "WhatsApp/Media/WhatsApp Video/Sent" to "WhatsApp Sent Video",
            "WhatsApp/Media/.Statuses" to "WhatsApp Status Cache",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/Sent" to "WhatsApp Sent Images",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/Sent" to "WhatsApp Sent Video",
            "Android/media/com.whatsapp/WhatsApp/Media/.Statuses" to "WhatsApp Status Cache"
        )
        for ((rel, label) in msgPaths) {
            val f = File(root, rel)
            if (f.exists() && f.isDirectory) {
                val sz = dirSize(f)
                if (sz > 512 * 1024L) {
                    results.add(mapOf("category" to label, "tag" to "MESSENGER", "size" to sz, "path" to f.absolutePath, "selected" to false))
                }
            }
        }

        // 3. Temp, Log & Old APK files
        val now = System.currentTimeMillis()
        val staleMs = 7L * 24L * 3600L * 1000L
        val stack = ArrayDeque<Pair<File, Int>>()
        stack.add(root to 0)
        var visited = 0
        while (stack.isNotEmpty() && visited < 2500) {
            val (cur, depth) = stack.removeLast()
            if (depth > 4) continue
            visited++
            val name = cur.name
            if (name.equals("Android", true) && depth == 1) continue
            val children = cur.listFiles() ?: continue
            if (children.isEmpty() && depth >= 1 && !setOf("DCIM", "Pictures", "Download", "Documents", "Music", "Movies").contains(name)) {
                results.add(mapOf("category" to "Empty Folder", "tag" to "SAFE", "size" to 4096L, "path" to cur.absolutePath, "selected" to true))
                continue
            }
            for (ch in children) {
                if (ch.isDirectory) {
                    stack.add(ch to (depth + 1))
                } else {
                    val ext = ch.extension.lowercase()
                    if (ext == "tmp" || ext == "log" || ext == "bak") {
                        results.add(mapOf("category" to "Temp / Log (.$ext)", "tag" to "SAFE JUNK", "size" to ch.length(), "path" to ch.absolutePath, "selected" to true))
                    } else if (ext == "apk" && ch.length() > 1024 * 1024L) {
                        val old = (now - ch.lastModified()) > staleMs
                        results.add(mapOf("category" to "APK Installer", "tag" to if (old) "OLD APK" else "RECENT APK", "size" to ch.length(), "path" to ch.absolutePath, "selected" to old))
                    }
                }
            }
        }

        return results.sortedByDescending { it["size"] as Long }
    }

    private fun cleanPaths(paths: List<String>): Long {
        var freed = 0L
        val rootPath = Environment.getExternalStorageDirectory().absolutePath
        for (p in paths) {
            val f = File(p)
            if (!f.exists() || f.absolutePath == rootPath) continue
            if (f.isFile) {
                val sz = f.length()
                if (f.delete()) freed += sz
            } else if (f.isDirectory) {
                val before = dirSize(f)
                f.deleteRecursively()
                val after = if (f.exists()) dirSize(f) else 0L
                freed += (before - after).coerceAtLeast(0L)
            }
        }
        return freed
    }

    private fun getInstalledAppsStats(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val pm = packageManager
        val hasUsage = hasUsageStatsAccess()
        val ssm = if (hasUsage && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
        } else null

        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        for (app in apps) {
            if ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0) continue
            val label = pm.getApplicationLabel(app).toString()
            var appBytes = 0L
            var dataBytes = 0L
            var cacheBytes = 0L
            if (ssm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    val uid = app.uid
                    val stats = ssm.queryStatsForUid(StorageManager.UUID_DEFAULT, uid)
                    appBytes = stats.appBytes
                    dataBytes = stats.dataBytes
                    cacheBytes = stats.cacheBytes
                } catch (_: Exception) {}
            } else {
                try {
                    val srcFile = File(app.sourceDir)
                    if (srcFile.exists()) appBytes = srcFile.length()
                } catch (_: Exception) {}
            }
            list.add(mapOf(
                "name" to label,
                "packageName" to app.packageName,
                "appBytes" to appBytes,
                "dataBytes" to dataBytes,
                "cacheBytes" to cacheBytes,
                "totalBytes" to (appBytes + dataBytes + cacheBytes)
            ))
        }
        return list.sortedByDescending { it["cacheBytes"] as Long }
    }

    private fun extractApkBackup(pkg: String, appName: String): String {
        return try {
            val ai = packageManager.getApplicationInfo(pkg, 0)
            val src = File(ai.sourceDir)
            val dl = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val outDir = File(dl, "NovaGen_Backups")
            if (!outDir.exists()) outDir.mkdirs()
            val safeName = appName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val dest = File(outDir, "$safeName.apk")
            src.copyTo(dest, overwrite = true)
            dest.absolutePath
        } catch (e: Exception) {
            "ERROR: ${e.message}"
        }
    }

    private fun findLargeFiles(minMb: Int): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val minBytes = minMb.toLong() * 1024L * 1024L
        val root = Environment.getExternalStorageDirectory()
        if (!root.exists()) return list

        val stack = ArrayDeque<File>()
        stack.add(root)
        var visited = 0
        while (stack.isNotEmpty() && visited < 2500) {
            val cur = stack.removeLast()
            visited++
            if (cur.name.equals("Android", true) && cur.parentFile?.absolutePath == root.absolutePath) continue
            val children = cur.listFiles() ?: continue
            for (ch in children) {
                if (ch.isDirectory) stack.add(ch)
                else if (ch.length() >= minBytes) {
                    list.add(mapOf(
                        "name" to ch.name,
                        "size" to ch.length(),
                        "path" to ch.absolutePath,
                        "ext" to ch.extension.uppercase()
                    ))
                }
            }
        }
        return list.sortedByDescending { it["size"] as Long }
    }

    private fun sortDownloads(): List<String> {
        val moved = mutableListOf<String>()
        val dl = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dl.exists()) return moved
        val files = dl.listFiles() ?: return moved
        for (f in files) {
            if (!f.isFile) continue
            val ext = f.extension.lowercase()
            val cat = when (ext) {
                "apk", "apks", "xapk", "exe", "msi" -> "Installers"
                "zip", "rar", "7z", "tar", "gz" -> "Archives"
                "jpg", "jpeg", "png", "webp", "gif", "heic" -> "Images"
                "mp4", "mkv", "mov", "webm", "avi" -> "Videos"
                "mp3", "wav", "flac", "m4a", "aac", "ogg" -> "Audio"
                "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv" -> "Documents"
                else -> null
            } ?: continue

            val destDir = File(dl, "Sorted/$cat")
            if (!destDir.exists()) destDir.mkdirs()
            var dest = File(destDir, f.name)
            var n = 1
            while (dest.exists()) {
                dest = File(destDir, "${f.nameWithoutExtension} ($n).${f.extension}")
                n++
            }
            if (f.renameTo(dest)) {
                moved.add("[$cat] ${f.name}")
            }
        }
        return moved
    }
}
