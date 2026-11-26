$ErrorActionPreference = 'Stop'
$root = "d:\uinsitaler"
$nativeExe = Join-Path $root "NovaGenPro\bin\Release\NovaGen.exe"
if (-not (Test-Path $nativeExe)) { throw "Native NovaGen.exe not found at $nativeExe" }

# Copy native compiled NovaGen.exe to root as portable standalone edition
Copy-Item -LiteralPath $nativeExe -Destination (Join-Path $root "NovaGen.exe") -Force
$exeKB = [math]::Round((Get-Item (Join-Path $root "NovaGen.exe")).Length / 1KB, 1)
Write-Host "Copied Native C# NovaGen.exe ($exeKB KB) to $root\NovaGen.exe"

$icoPath = Join-Path $root "NovaGen.ico"
$setupOut = Join-Path $root "NovaGen-Setup.exe"

$csSetup = @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("NovaGen Pro v5.0 Setup")]
[assembly: AssemblyProduct("NovaGen Zero-Trace Deep Uninstaller Pro")]
[assembly: AssemblyCompany("NovaGen Systems")]
[assembly: AssemblyVersion("5.0.0.0")]

namespace NovaGenSetup
{
    public class SetupForm : Form
    {
        private TextBox txtPath;
        private CheckBox chkDesktop;
        private CheckBox chkLaunch;
        private Button btnInstall;
        private ProgressBar pb;
        private Label lblStatus;

        public SetupForm()
        {
            Text = "NovaGen Pro v5.0 — Setup Wizard";
            Size = new Size(520, 340);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            BackColor = Color.FromArgb(11, 18, 32);
            ForeColor = Color.FromArgb(248, 250, 252);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            var lblTitle = new Label { Text = "NOVAGEN PRO v5.0", Font = new Font("Segoe UI", 16, FontStyle.Bold), ForeColor = Color.FromArgb(34, 211, 238), Location = new Point(24, 20), AutoSize = true };
            var lblSub = new Label { Text = "Zero-Trace Deep Uninstaller, PC Speed Boost, Bloat Radar & Watchdog", Font = new Font("Segoe UI", 9.5f), ForeColor = Color.FromArgb(148, 163, 184), Location = new Point(24, 52), AutoSize = true };

            var lblDir = new Label { Text = "Install Directory:", Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), Location = new Point(24, 95), AutoSize = true };
            txtPath = new TextBox { Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "NovaGen Pro"), Location = new Point(24, 120), Width = 370, BackColor = Color.FromArgb(17, 28, 51), ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle };
            var btnBrowse = new Button { Text = "Browse...", Location = new Point(402, 118), Width = 80, Height = 25, BackColor = Color.FromArgb(30, 41, 59), ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
            btnBrowse.Click += (s, e) => { using (var f = new FolderBrowserDialog()) { if (f.ShowDialog() == DialogResult.OK) txtPath.Text = f.SelectedPath; } };

            chkDesktop = new CheckBox { Text = "Create Desktop Shortcut", Checked = true, Location = new Point(24, 160), AutoSize = true };
            chkLaunch = new CheckBox { Text = "Launch NovaGen Pro v5.0 after installation", Checked = true, Location = new Point(24, 188), AutoSize = true };

            pb = new ProgressBar { Location = new Point(24, 224), Width = 458, Height = 12, Minimum = 0, Maximum = 100 };
            lblStatus = new Label { Text = "Ready to install.", ForeColor = Color.FromArgb(148, 163, 184), Location = new Point(24, 242), AutoSize = true };

            btnInstall = new Button { Text = "Install NovaGen Pro", Location = new Point(322, 262), Width = 160, Height = 32, BackColor = Color.FromArgb(37, 99, 235), ForeColor = Color.White, Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), FlatStyle = FlatStyle.Flat };
            btnInstall.Click += OnInstallClick;

            Controls.AddRange(new Control[] { lblTitle, lblSub, lblDir, txtPath, btnBrowse, chkDesktop, chkLaunch, pb, lblStatus, btnInstall });
        }

        private void OnInstallClick(object sender, EventArgs e)
        {
            btnInstall.Enabled = false;
            try
            {
                string targetDir = txtPath.Text.Trim();
                Directory.CreateDirectory(targetDir);
                string exeDest = Path.Combine(targetDir, "NovaGen.exe");

                lblStatus.Text = "Extracting NovaGen Pro v5.0...";
                pb.Value = 35;
                Application.DoEvents();

                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream s = asm.GetManifestResourceStream("NovaGen.exe"))
                using (FileStream fs = new FileStream(exeDest, FileMode.Create, FileAccess.Write))
                {
                    s.CopyTo(fs);
                }

                pb.Value = 70;
                lblStatus.Text = "Creating Start Menu & Desktop shortcuts...";
                Application.DoEvents();

                string startMenuDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "NovaGen Pro");
                Directory.CreateDirectory(startMenuDir);
                CreateShortcut(Path.Combine(startMenuDir, "NovaGen Pro.lnk"), exeDest);
                if (chkDesktop.Checked)
                    CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory), "NovaGen Pro.lnk"), exeDest);

                // Register in Windows Apps & Features
                using (var key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NovaGenPro"))
                {
                    key.SetValue("DisplayName", "NovaGen Zero-Trace Deep Uninstaller Pro v5.0");
                    key.SetValue("DisplayVersion", "5.0.0");
                    key.SetValue("Publisher", "NovaGen Systems");
                    key.SetValue("InstallLocation", targetDir);
                    key.SetValue("DisplayIcon", exeDest);
                    key.SetValue("UninstallString", "cmd.exe /c rmdir /s /q \"" + targetDir + "\"");
                }

                pb.Value = 100;
                lblStatus.Text = "Installation complete!";
                Application.DoEvents();

                if (chkLaunch.Checked)
                    Process.Start(new ProcessStartInfo(exeDest) { UseShellExecute = true });

                Close();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Install failed: " + ex.Message, "NovaGen Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
                btnInstall.Enabled = true;
            }
        }

        private static void CreateShortcut(string lnkPath, string targetPath)
        {
            string ps = string.Format("`$s=(New-Object -ComObject WScript.Shell).CreateShortcut('{0}');`$s.TargetPath='{1}';`$s.WorkingDirectory='{2}';`$s.Save()",
                lnkPath.Replace("'", "''"), targetPath.Replace("'", "''"), Path.GetDirectoryName(targetPath).Replace("'", "''"));
            Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -Command \"" + ps + "\"") { CreateNoWindow = true, UseShellExecute = false })?.WaitForExit(4000);
        }

        [STAThread]
        static void Main()
        {
            bool isAdmin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
            if (!isAdmin)
            {
                try
                {
                    Process.Start(new ProcessStartInfo(Application.ExecutablePath) { UseShellExecute = true, Verb = "runas" });
                    return;
                }
                catch { return; }
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }
    }
}
"@

# Fix C# 5 ?.WaitForExit in csSetup
$csSetup = $csSetup -replace '\?\.', '.'
$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$params = New-Object System.CodeDom.Compiler.CompilerParameters
$params.GenerateExecutable = $true
$params.OutputAssembly = $setupOut
$params.CompilerOptions = "/target:winexe /optimize /win32icon:`"$icoPath`""
[void]$params.ReferencedAssemblies.Add("System.dll")
[void]$params.ReferencedAssemblies.Add("System.Drawing.dll")
[void]$params.ReferencedAssemblies.Add("System.Windows.Forms.dll")
[void]$params.EmbeddedResources.Add($nativeExe)

$res = $provider.CompileAssemblyFromSource($params, $csSetup)
if ($res.Errors.HasErrors) {
    foreach ($e in $res.Errors) { Write-Error $e.ToString() }
    exit 1
}
$setupKB = [math]::Round((Get-Item $setupOut).Length / 1KB, 1)
Write-Host "Successfully built PRODUCTION INSTALLER: NovaGen-Setup.exe ($setupKB KB)"
