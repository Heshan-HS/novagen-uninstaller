using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;

namespace NovaGenPro.Services
{
    public class SortedFileResult
    {
        public string FileName { get; set; }
        public string Category { get; set; }
        public string DestPath { get; set; }
    }

    public class WatchdogService : IDisposable
    {
        private readonly List<FileSystemWatcher> _watchers = new List<FileSystemWatcher>();
        private readonly ConcurrentQueue<string> _queue = new ConcurrentQueue<string>();

        public bool IsRunning { get; private set; }
        public int MovedCount { get; private set; }

        public static string GetCategory(string ext)
        {
            switch (ext.ToLowerInvariant())
            {
                case ".exe": case ".msi": case ".msix": case ".appx": case ".appinstaller": case ".apk": case ".iso": case ".bat":
                    return "Installers";
                case ".zip": case ".rar": case ".7z": case ".tar": case ".gz": case ".xz":
                    return "Archives";
                case ".png": case ".jpg": case ".jpeg": case ".webp": case ".gif": case ".bmp": case ".svg": case ".ico":
                    return "Images";
                case ".mp4": case ".mkv": case ".avi": case ".mov": case ".webm": case ".wmv":
                    return "Videos";
                case ".mp3": case ".wav": case ".flac": case ".m4a": case ".ogg": case ".aac":
                    return "Audio";
                case ".pdf": case ".doc": case ".docx": case ".xls": case ".xlsx": case ".ppt": case ".pptx": case ".txt": case ".csv": case ".md":
                    return "Documents";
                case ".ps1": case ".py": case ".js": case ".ts": case ".dart": case ".json": case ".html": case ".css": case ".sql": case ".cs":
                    return "Code_Scripts";
                default:
                    return null;
            }
        }

        public SortedFileResult MoveFileToSorted(string filePath)
        {
            if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return null;
            try
            {
                var fi = new FileInfo(filePath);
                string ext = fi.Extension.ToLowerInvariant();
                if (ext == ".lnk" || ext == ".url" || ext == ".ini" || ext == ".tmp" || ext == ".crdownload" || ext == ".part" || ext == ".opdownload")
                    return null;

                string cat = GetCategory(ext);
                if (cat == null) return null;

                string parentDir = fi.DirectoryName;
                string destDir = Path.Combine(parentDir, "Sorted", cat);
                Directory.CreateDirectory(destDir);

                string destPath = Path.Combine(destDir, fi.Name);
                if (File.Exists(destPath))
                {
                    string baseName = Path.GetFileNameWithoutExtension(fi.Name);
                    int n = 1;
                    while (File.Exists(destPath))
                    {
                        destPath = Path.Combine(destDir, string.Format("{0} ({1}){2}", baseName, n, fi.Extension));
                        n++;
                    }
                }
                File.Move(filePath, destPath);
                MovedCount++;
                return new SortedFileResult { FileName = fi.Name, Category = cat, DestPath = destPath };
            }
            catch { return null; }
        }

        public List<SortedFileResult> OrganizeFolderNow(string folderPath)
        {
            var list = new List<SortedFileResult>();
            if (string.IsNullOrWhiteSpace(folderPath) || !Directory.Exists(folderPath)) return list;
            try
            {
                foreach (var f in Directory.EnumerateFiles(folderPath))
                {
                    var res = MoveFileToSorted(f);
                    if (res != null) list.Add(res);
                }
            }
            catch { }
            return list;
        }

        public void Start(IEnumerable<string> paths)
        {
            Stop();
            foreach (var p in paths)
            {
                if (!Directory.Exists(p)) continue;
                var fsw = new FileSystemWatcher(p)
                {
                    IncludeSubdirectories = false,
                    NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite
                };
                fsw.Created += (s, e) => { if (!string.IsNullOrEmpty(e.FullPath)) _queue.Enqueue(e.FullPath); };
                fsw.Renamed += (s, e) => { if (!string.IsNullOrEmpty(e.FullPath)) _queue.Enqueue(e.FullPath); };
                fsw.EnableRaisingEvents = true;
                _watchers.Add(fsw);
            }
            IsRunning = _watchers.Count > 0;
        }

        public List<SortedFileResult> DrainQueue()
        {
            var list = new List<SortedFileResult>();
            string path;
            while (_queue.TryDequeue(out path))
            {
                var res = MoveFileToSorted(path);
                if (res != null) list.Add(res);
            }
            return list;
        }

        public void Stop()
        {
            foreach (var w in _watchers)
            {
                try { w.EnableRaisingEvents = false; w.Dispose(); } catch { }
            }
            _watchers.Clear();
            IsRunning = false;
        }

        public void Dispose() { Stop(); }
    }
}
