<#
.SYNOPSIS
    Compiles a TRUE SINGLE-FILE STANDALONE Windows executable (NovaGen.exe) with custom icon
    and embedded NovaGen-Engine.ps1 resource.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $root) { $root = "d:\uinsitaler" }

$enginePath = Join-Path $root "NovaGen-Engine.ps1"
if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "NovaGen-Engine.ps1 not found at $enginePath"
}

Add-Type -AssemblyName System.Drawing

# 1. Use existing custom NovaGen.ico (only generate fallback if missing)
$icoPath = Join-Path $root "NovaGen.ico"
if (-not (Test-Path -LiteralPath $icoPath)) {
$bmp = New-Object System.Drawing.Bitmap(64, 64)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::FromArgb(6, 11, 22))

$rect = New-Object System.Drawing.Rectangle(4, 4, 56, 56)
$brushBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(37, 99, 235))
$penBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(34, 211, 238), 2)
$g.FillRectangle($brushBg, $rect)
$g.DrawRectangle($penBorder, $rect)

$font = New-Object System.Drawing.Font("Segoe UI", 30, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$brushText = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$g.DrawString("N", $font, $brushText, (New-Object System.Drawing.RectangleF(0, 2, 64, 64)), $sf)
$g.Dispose()

$msPng = New-Object System.IO.MemoryStream
$bmp.Save($msPng, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = $msPng.ToArray()
$msPng.Dispose()
$bmp.Dispose()

$fsIco = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fsIco)
$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]1)
$bw.Write([byte]64)
$bw.Write([byte]64)
$bw.Write([byte]0)
$bw.Write([byte]0)
$bw.Write([uint16]1)
$bw.Write([uint16]32)
$bw.Write([uint32]$pngBytes.Length)
$bw.Write([uint32]22)
$bw.Write($pngBytes)
$bw.Flush()
$bw.Close()
$fsIco.Dispose()
}

# 2. Compile Single-File Standalone NovaGen.exe with Embedded Engine Script
$exePath = Join-Path $root "NovaGen.exe"
$csCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("NovaGen Zero-Trace Deep Uninstaller Pro")]
[assembly: AssemblyDescription("Standalone 18-Point Deep Uninstaller, Leftover Wipe & PC Speed Boost Engine")]
[assembly: AssemblyCompany("NovaGen Systems")]
[assembly: AssemblyProduct("NovaGen Deep Uninstaller Pro")]
[assembly: AssemblyVersion("4.3.0.0")]
[assembly: AssemblyFileVersion("4.3.0.0")]

namespace NovaGenLauncher {
    static class Program {
        [STAThread]
        static void Main() {
            try {
                bool isAdmin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
                if (!isAdmin) {
                    try {
                        ProcessStartInfo elevate = new ProcessStartInfo();
                        elevate.FileName = Application.ExecutablePath;
                        elevate.UseShellExecute = true;
                        elevate.Verb = "runas";
                        Process.Start(elevate);
                        return;
                    } catch {
                        // User declined UAC; continue in limited mode
                    }
                }

                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string localEngine = Path.Combine(baseDir, "NovaGen-Engine.ps1");
                string targetEngine = localEngine;
                string dataDir = baseDir;

                if (!File.Exists(localEngine)) {
                    // Standalone Single-File Mode: extract embedded engine to %LOCALAPPDATA%\NovaGen
                    string appDataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NovaGen");
                    string runtimeDir = Path.Combine(appDataRoot, "Runtime");
                    Directory.CreateDirectory(runtimeDir);
                    targetEngine = Path.Combine(runtimeDir, "NovaGen-Engine.ps1");
                    dataDir = appDataRoot;

                    Assembly asm = Assembly.GetExecutingAssembly();
                    using (Stream s = asm.GetManifestResourceStream("NovaGen-Engine.ps1")) {
                        if (s == null) {
                            MessageBox.Show("Embedded engine resource missing.", "NovaGen Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            return;
                        }
                        using (FileStream fs = new FileStream(targetEngine, FileMode.Create, FileAccess.Write, FileShare.Read)) {
                            s.CopyTo(fs);
                        }
                    }
                    using (Stream sIco = asm.GetManifestResourceStream("NovaGen.ico")) {
                        if (sIco != null) {
                            using (FileStream fsIco = new FileStream(Path.Combine(runtimeDir, "NovaGen.ico"), FileMode.Create, FileAccess.Write, FileShare.Read)) {
                                sIco.CopyTo(fsIco);
                            }
                        }
                    }
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + targetEngine + "\"";
                psi.WorkingDirectory = dataDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.EnvironmentVariables["NOVAGEN_DATA_DIR"] = dataDir;
                Process.Start(psi);
            } catch (Exception ex) {
                MessageBox.Show("Failed to launch NovaGen Engine: " + ex.Message, "NovaGen Launcher", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }
}
"@

$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$params = New-Object System.CodeDom.Compiler.CompilerParameters
$params.GenerateExecutable = $true
$params.OutputAssembly = $exePath
$params.CompilerOptions = "/target:winexe /optimize /win32icon:`"$icoPath`""
[void]$params.ReferencedAssemblies.Add("System.dll")
[void]$params.ReferencedAssemblies.Add("System.Windows.Forms.dll")
[void]$params.EmbeddedResources.Add($enginePath)
[void]$params.EmbeddedResources.Add($icoPath)

$results = $provider.CompileAssemblyFromSource($params, $csCode)
if ($results.Errors.HasErrors) {
    foreach ($err in $results.Errors) {
        Write-Error $err.ToString()
    }
    exit 1
}

$exeSizeKB = [math]::Round((Get-Item $exePath).Length / 1KB, 1)
Write-Host "Successfully built SINGLE-FILE STANDALONE NovaGen.exe ($exeSizeKB KB) in $root"
