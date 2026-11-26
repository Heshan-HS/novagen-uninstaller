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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Base64
import android.util.Size
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.novagen.mobile/engine"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTelemetry" -> executor.execute {
                    val data = collectTelemetry()
                    mainHandler.post { result.success(data) }
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
                "trimBackgroundRam" -> executor.execute {
                    val res = trimRam()
                    mainHandler.post { result.success(res) }
                }
                "scanSafeJunk" -> executor.execute {
                    val items = scanSafeJunk()
                    mainHandler.post { result.success(items) }
                }
                "cleanJunkItems" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    executor.execute {
                        val freed = cleanPaths(paths)
                        mainHandler.post { result.success(freed) }
                    }
                }
                "scanInstalledApps" -> executor.execute {
                    val apps = getInstalledAppsStats()
                    mainHandler.post { result.success(apps) }
                }
                "openAppSettings" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    if (pkg.isNotEmpty()) {
                        try {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$pkg")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            })
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
                    val minMb = call.argument<Int>("minMb") ?: 20
                    executor.execute {
                        val items = findLargeFiles(minMb)
                        mainHandler.post { result.success(items) }
                    }
                }
                "scanDuplicates" -> executor.execute {
                    val items = findDuplicates()
                    mainHandler.post { result.success(items) }
                }
                "scanStorageBreakdown" -> executor.execute {
                    val breakdown = computeStorageBreakdown()
                    mainHandler.post { result.success(breakdown) }
                }
                "openFilePreview" -> {
                    val path = call.argument<String>("path") ?: ""
                    val ok = launchFileViewer(path)
                    result.success(ok)
                }
                "sortDownloadsFolder" -> executor.execute {
                    val movedList = sortDownloads()
                    mainHandler.post { result.success(movedList) }
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
                startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
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

    private fun launchFileViewer(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val ext = file.extension.lowercase()
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: when (ext) {
                "mp4", "mkv", "mov", "avi", "webm" -> "video/*"
                "jpg", "jpeg", "png", "webp", "gif", "bmp" -> "image/*"
                "mp3", "wav", "m4a", "flac" -> "audio/*"
                "pdf" -> "application/pdf"
                else -> "*/*"
            }
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "Open with").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
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

    private fun encodeBitmapThumb(bmp: Bitmap?): String {
        if (bmp == null) return ""
        return try {
            val scaled = Bitmap.createScaledBitmap(bmp, 96, 96, true)
            val baos = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 65, baos)
            if (scaled != bmp) scaled.recycle()
            Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) {
            ""
        }
    }

    private fun getFileThumbBase64(file: File): String {
        val ext = file.extension.lowercase()
        return try {
            if (ext in listOf("mp4", "mkv", "mov", "avi", "webm")) {
                val bmp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ThumbnailUtils.createVideoThumbnail(file, Size(128, 128), null)
                } else {
                    @Suppress("DEPRECATION")
                    ThumbnailUtils.createVideoThumbnail(file.absolutePath, MediaStore.Images.Thumbnails.MINI_KIND)
                }
                val res = encodeBitmapThumb(bmp)
                bmp?.recycle()
                res
            } else if (ext in listOf("jpg", "jpeg", "png", "webp", "bmp")) {
                val opts = BitmapFactory.Options().apply { inSampleSize = 8 }
                val bmp = BitmapFactory.decodeFile(file.absolutePath, opts)
                val res = encodeBitmapThumb(bmp)
                bmp?.recycle()
                res
            } else ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun computeStorageBreakdown(): Map<String, Long> {
        var videos = 0L
        var images = 0L
        var audio = 0L
        var docs = 0L
        var apks = 0L
        val root = Environment.getExternalStorageDirectory()
        if (!root.exists()) return mapOf("videos" to 0L, "images" to 0L, "audio" to 0L, "docs" to 0L, "apks" to 0L)

        val stack = ArrayDeque<File>()
        stack.add(root)
        var visited = 0
        while (stack.isNotEmpty() && visited < 3500) {
            val cur = stack.removeLast()
            visited++
            if (cur.name.equals("Android", true) && cur.parentFile?.absolutePath == root.absolutePath) continue
            val children = cur.listFiles() ?: continue
            for (ch in children) {
                if (ch.isDirectory) stack.add(ch)
                else {
                    val sz = ch.length()
                    when (ch.extension.lowercase()) {
                        "mp4", "mkv", "mov", "avi", "webm" -> videos += sz
                        "jpg", "jpeg", "png", "webp", "gif", "heic", "bmp" -> images += sz
                        "mp3", "wav", "flac", "m4a", "aac", "ogg" -> audio += sz
                        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt" -> docs += sz
                        "apk", "apks", "xapk" -> apks += sz
                    }
                }
            }
        }
        return mapOf("videos" to videos, "images" to images, "audio" to audio, "docs" to docs, "apks" to apks)
    }

    private fun scanSafeJunk(): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val root = Environment.getExternalStorageDirectory()
        if (!root.exists()) return results

        // 1. Thumbnails, Hidden TrashBin & LOST.DIR
        for (thumbPath in listOf("DCIM/.thumbnails", "Pictures/.thumbnails", "Movies/.thumbnails", ".trashBin", ".Trash", "LOST.DIR")) {
            val f = File(root, thumbPath)
            if (f.exists() && f.isDirectory) {
                val sz = dirSize(f)
                if (sz > 64 * 1024L) {
                    val label = if (thumbPath.contains("trash", true)) "Hidden Trash Bin" else if (thumbPath == "LOST.DIR") "Lost Recovery Junk" else "Thumbnail Cache"
                    results.add(mapOf("category" to label, "tag" to "SAFE CACHE", "size" to sz, "path" to f.absolutePath, "selected" to true))
                }
            }
        }

        // 2. WhatsApp & Telegram Messenger Clutter
        val msgPaths = listOf(
            "WhatsApp/Media/WhatsApp Images/Sent" to "WhatsApp Sent Images",
            "WhatsApp/Media/WhatsApp Video/Sent" to "WhatsApp Sent Video",
            "WhatsApp/Media/.Statuses" to "WhatsApp Status Cache",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/Sent" to "WhatsApp Sent Images",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/Sent" to "WhatsApp Sent Video",
            "Android/media/com.whatsapp/WhatsApp/Media/.Statuses" to "WhatsApp Status Cache",
            "Telegram/Telegram Images" to "Telegram Cached Images",
            "Telegram/Telegram Video" to "Telegram Cached Video"
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

        // 3. App Leftovers / CorpseFinder in /Android/media/
        try {
            val installedPkgs = packageManager.getInstalledApplications(0).map { it.packageName }.toSet()
            val androidMedia = File(root, "Android/media")
            if (androidMedia.exists() && androidMedia.isDirectory) {
                androidMedia.listFiles()?.forEach { dir ->
                    if (dir.isDirectory && dir.name.contains(".") && !installedPkgs.contains(dir.name)) {
                        val sz = dirSize(dir)
                        if (sz > 256 * 1024L) {
                            results.add(mapOf("category" to "App Leftover (${dir.name})", "tag" to "CORPSE", "size" to sz, "path" to dir.absolutePath, "selected" to true))
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // 4. Temp, Log, Empty Folders & Old APK files
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
                    val stats = ssm.queryStatsForUid(StorageManager.UUID_DEFAULT, app.uid)
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
        while (stack.isNotEmpty() && visited < 3000) {
            val cur = stack.removeLast()
            visited++
            if (cur.name.equals("Android", true) && cur.parentFile?.absolutePath == root.absolutePath) continue
            val children = cur.listFiles() ?: continue
            for (ch in children) {
                if (ch.isDirectory) stack.add(ch)
                else if (ch.length() >= minBytes) {
                    val ext = ch.extension.lowercase()
                    val isVideo = ext in listOf("mp4", "mkv", "mov", "avi", "webm")
                    val thumb = if (list.size < 45) getFileThumbBase64(ch) else ""
                    list.add(mapOf(
                        "name" to ch.name,
                        "size" to ch.length(),
                        "path" to ch.absolutePath,
                        "ext" to ext.uppercase(),
                        "isVideo" to isVideo,
                        "thumb" to thumb
                    ))
                }
            }
        }
        return list.sortedByDescending { it["size"] as Long }
    }

    private fun computeSha256Sample(file: File): String {
        return try {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { fis ->
                val buf = ByteArray(65536)
                var read = fis.read(buf)
                while (read > 0) {
                    md.update(buf, 0, read)
                    read = fis.read(buf)
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            ""
        }
    }

    private fun getImageDHash(file: File): Long? {
        return try {
            val opts = BitmapFactory.Options().apply { inSampleSize = 4 }
            val raw = BitmapFactory.decodeFile(file.absolutePath, opts) ?: return null
            val bmp = Bitmap.createScaledBitmap(raw, 9, 8, true)
            if (raw != bmp) raw.recycle()
            var hash = 0L
            var bit = 0
            for (y in 0 until 8) {
                for (x in 0 until 8) {
                    val p1 = bmp.getPixel(x, y)
                    val p2 = bmp.getPixel(x + 1, y)
                    val l1 = ((p1 shr 16 and 0xFF) * 0.299) + ((p1 shr 8 and 0xFF) * 0.587) + ((p1 and 0xFF) * 0.114)
                    val l2 = ((p2 shr 16 and 0xFF) * 0.299) + ((p2 shr 8 and 0xFF) * 0.587) + ((p2 and 0xFF) * 0.114)
                    if (l1 > l2) hash = hash or (1L shl bit)
                    bit++
                }
            }
            bmp.recycle()
            hash
        } catch (_: Exception) {
            null
        }
    }

    private fun hammingDist(a: Long, b: Long): Int = java.lang.Long.bitCount(a xor b)

    private fun findDuplicates(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val root = Environment.getExternalStorageDirectory()
        if (!root.exists()) return out

        val allFiles = mutableListOf<File>()
        val stack = ArrayDeque<File>()
        stack.add(root)
        var visited = 0
        while (stack.isNotEmpty() && visited < 3000) {
            val cur = stack.removeLast()
            visited++
            if (cur.name.equals("Android", true) && cur.parentFile?.absolutePath == root.absolutePath) continue
            if (cur.name.startsWith(".")) continue
            val children = cur.listFiles() ?: continue
            for (ch in children) {
                if (ch.isDirectory) stack.add(ch)
                else if (ch.length() >= 64 * 1024L) {
                    allFiles.add(ch)
                    if (allFiles.size >= 3000) break
                }
            }
        }

        // 1. Exact Duplicates (Size bucket + SHA256)
        val seenPaths = HashSet<String>()
        val sizeGroups = allFiles.groupBy { it.length() }.filter { it.value.size > 1 }
        for ((_, grp) in sizeGroups) {
            val byHash = mutableMapOf<String, MutableList<File>>()
            for (f in grp.sortedBy { it.lastModified() }) {
                if (f.length() > 150L * 1024L * 1024L) continue // skip huge files from full hash freeze
                val h = computeSha256Sample(f)
                if (h.isEmpty()) continue
                byHash.getOrPut(h) { mutableListOf() }.add(f)
            }
            for ((_, dupGroup) in byHash) {
                if (dupGroup.size > 1) {
                    val orig = dupGroup.first()
                    val thumb = getFileThumbBase64(orig)
                    for ((idx, df) in dupGroup.withIndex()) {
                        seenPaths.add(df.absolutePath)
                        out.add(mapOf(
                            "name" to df.name,
                            "path" to df.absolutePath,
                            "size" to df.length(),
                            "type" to "Exact Duplicate",
                            "group" to "Copy of ${orig.name}",
                            "isOriginal" to (idx == 0),
                            "selected" to (idx > 0),
                            "thumb" to thumb
                        ))
                    }
                }
            }
        }

        // 2. Perceptual Similar Photos (dHash <= 4 bits)
        val imgExts = setOf("jpg", "jpeg", "png", "webp", "bmp")
        val imgs = allFiles.filter { !seenPaths.contains(it.absolutePath) && imgExts.contains(it.extension.lowercase()) }.take(300)
        val hashed = mutableListOf<Pair<Long, File>>()
        for (im in imgs) {
            val dh = getImageDHash(im) ?: continue
            val match = hashed.firstOrNull { hammingDist(dh, it.first) <= 4 }
            if (match != null) {
                val thumb = getFileThumbBase64(im)
                out.add(mapOf(
                    "name" to im.name,
                    "path" to im.absolutePath,
                    "size" to im.length(),
                    "type" to "Similar Photo (dHash)",
                    "group" to "Near ${match.second.name}",
                    "isOriginal" to false,
                    "selected" to false,
                    "thumb" to thumb
                ))
            } else {
                hashed.add(dh to im)
            }
        }

        return out
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
