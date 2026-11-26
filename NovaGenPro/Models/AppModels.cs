using System;
using System.ComponentModel;

namespace NovaGenPro.Models
{
    public class InstalledAppItem : INotifyPropertyChanged
    {
        private long _sizeBytes;
        private string _sizeDisplay;

        public string DisplayName { get; set; }
        public string Publisher { get; set; }
        public string DisplayVersion { get; set; }
        public string Arch { get; set; }
        public string InstallDate { get; set; }
        public string Category { get; set; }
        public string InstallLocation { get; set; }
        public string UninstallString { get; set; }
        public string QuietUninstallString { get; set; }
        public string RegistryPath { get; set; }
        public string RegistryKeyName { get; set; }

        public long SizeBytes
        {
            get { return _sizeBytes; }
            set { _sizeBytes = value; OnPropertyChanged("SizeBytes"); }
        }

        public string SizeDisplay
        {
            get { return _sizeDisplay; }
            set { _sizeDisplay = value; OnPropertyChanged("SizeDisplay"); }
        }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            var h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }

    public class StoreAppItem
    {
        public string Name { get; set; }
        public string Publisher { get; set; }
        public string Version { get; set; }
        public string PackageFullName { get; set; }
        public string InstallLocation { get; set; }
    }

    public class LeftoverItem : INotifyPropertyChanged
    {
        private bool _isSelected = true;
        public bool IsSelected
        {
            get { return _isSelected; }
            set { _isSelected = value; OnPropertyChanged("IsSelected"); }
        }
        public string ItemType { get; set; }
        public string LocationTag { get; set; }
        public long SizeBytes { get; set; }
        public string SizeDisplay { get; set; }
        public string TargetPath { get; set; }
        public string RegValueName { get; set; }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            var h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }

    public class GhostItem
    {
        public string FolderName { get; set; }
        public string Location { get; set; }
        public string SizeDisplay { get; set; }
        public long SizeBytes { get; set; }
        public string FullPath { get; set; }
    }

    public class BloatRadarItem : INotifyPropertyChanged
    {
        private bool _isSelected;
        public bool IsSelected
        {
            get { return _isSelected; }
            set { _isSelected = value; OnPropertyChanged("IsSelected"); }
        }
        public string Category { get; set; }
        public string StatusTag { get; set; }
        public long SizeBytes { get; set; }
        public string SizeDisplay { get; set; }
        public string TargetPath { get; set; }
        public string ItemType { get; set; }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            var h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }

    public class TopProcessItem
    {
        public string Name { get; set; }
        public string MemDisplay { get; set; }
        public int Pid { get; set; }
    }

    public class StartupEntryItem : INotifyPropertyChanged
    {
        private bool _isSelected;
        public bool IsSelected
        {
            get { return _isSelected; }
            set { _isSelected = value; OnPropertyChanged("IsSelected"); }
        }
        public string Name { get; set; }
        public string Scope { get; set; }
        public string Command { get; set; }
        public string RegPath { get; set; }
        public string ExportPath { get; set; }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            var h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }
}
