<#
.SYNOPSIS
    Compiles a native standalone Windows GUI executable (NovaGen.exe) with a custom icon
    that launches the NovaGen Deep Uninstaller Pro engine with Administrator privileges.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $root) { $root = "d:\uinsitaler" }

Add-Type -AssemblyName System.Drawing

# 1. Generate a crisp high-contrast Obsidian + Cobalt "N" Icon (NovaGen.ico)
$icoPath = Join-Path $root "NovaGen.ico"
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

# Write valid ICO header wrapping PNG data
$msPng = New-Object System.IO.MemoryStream
$bmp.Save($msPng, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = $msPng.ToArray()
$msPng.Dispose()
$bmp.Dispose()

$fsIco = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fsIco)
$bw.Write([uint16]0)          # Reserved
$bw.Write([uint16]1)          # Type: 1 = ICO
$bw.Write([uint16]1)          # Count: 1 image
$bw.Write([byte]64)           # Width
$bw.Write([byte]64)           # Height
$bw.Write([byte]0)            # Color count
$bw.Write([byte]0)            # Reserved
$bw.Write([uint16]1)          # Planes
$bw.Write([uint16]32)         # BitCount
$bw.Write([uint32]$pngBytes.Length) # BytesInRes
$bw.Write([uint32]22)         # ImageOffset
$bw.Write($pngBytes)
$bw.Flush()
$bw.Close()
$fsIco.Dispose()

# 2. Compile Native Windows Executable (NovaGen.exe)
$exePath = Join-Path $root "NovaGen.exe"
$csCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

[assembly: AssemblyTitle("NovaGen Zero-Trace Deep Uninstaller Pro")]
[assembly: AssemblyDescription("Enterprise 18-Point Deep Uninstaller & Leftover Wipe Engine")]
[assembly: AssemblyCompany("NovaGen Systems")]
[assembly: AssemblyProduct("NovaGen Deep Uninstaller Pro")]
[assembly: AssemblyVersion("4.2.0.0")]
[assembly: AssemblyFileVersion("4.2.0.0")]

namespace NovaGenLauncher {
    static class Program {
        [STAThread]
        static void Main() {
            try {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string engineScript = Path.Combine(baseDir, "NovaGen-Engine.ps1");
                if (!File.Exists(engineScript)) {
                    MessageBox.Show("NovaGen-Engine.ps1 not found in: " + baseDir, "NovaGen Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }

                bool isAdmin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + engineScript + "\"";
                psi.WorkingDirectory = baseDir;
                if (!isAdmin) {
                    psi.Verb = "runas";
                    psi.UseShellExecute = true;
                } else {
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                }
                Process.Start(psi);
            } catch (Exception ex) {
                // User cancelled UAC or error
                if (!ex.Message.Contains("canceled")) {
                    MessageBox.Show("Failed to launch NovaGen Engine: " + ex.Message, "NovaGen Launcher", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
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

$results = $provider.CompileAssemblyFromSource($params, $csCode)
if ($results.Errors.HasErrors) {
    foreach ($err in $results.Errors) {
        Write-Error $err.ToString()
    }
    exit 1
}

Write-Host "Successfully built NovaGen.exe and NovaGen.ico in $root"
