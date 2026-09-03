# Generates the launcher icon into android/app/src/main/res/mipmap-*.
#
# Kept as a script rather than committing only the PNGs so the mark can be
# retuned later without hunting for whatever tool produced it. Uses
# System.Drawing, which ships with Windows - no image toolchain to install.
#
#   tools\make_icon.ps1
#
# The mark: a ring with one quarter filled. A "prahar" is a division of the
# day, so the icon is a day with one portion claimed. It stays legible at
# 48x48, which rules out anything more detailed.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$res = Join-Path $project 'android\app\src\main\res'

# Full-bleed background: launcher masks (Xiaomi's especially) crop to a circle
# or squircle, so the colour must reach every edge and the glyph must sit well
# inside a safe zone.
$bgTop = [System.Drawing.Color]::FromArgb(255, 99, 91, 255)   # indigo
$bgBot = [System.Drawing.Color]::FromArgb(255, 124, 58, 237)  # violet

function New-Icon([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, $bgTop, $bgBot, 60.0)
    $g.FillRectangle($brush, $rect)

    # Glyph geometry, as fractions of the canvas so every density matches.
    $cx = $size / 2.0
    $cy = $size / 2.0
    $r = $size * 0.29
    $stroke = $size * 0.085

    # Pass the bounds as separate floats: PowerShell resolves a RectangleF
    # argument to the Rectangle overload and then fails to convert it.
    $x = [float]($cx - $r)
    $y = [float]($cy - $r)
    $d = [float]($r * 2)

    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [float]$stroke)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    # One quarter of the day, filled: from 12 o'clock clockwise to 3.
    $g.FillPie($white, $x, $y, $d, $d, [float]-90.0, [float]90.0)
    # The whole day, outlined.
    $g.DrawEllipse($pen, $x, $y, $d, $d)

    $g.Dispose()
    $brush.Dispose(); $white.Dispose(); $pen.Dispose()
    return $bmp
}

# Render once at high resolution and downsample, so small densities stay clean.
$master = New-Icon 512

$targets = @{
    'mipmap-mdpi'    = 48
    'mipmap-hdpi'    = 72
    'mipmap-xhdpi'   = 96
    'mipmap-xxhdpi'  = 144
    'mipmap-xxxhdpi' = 192
}

foreach ($dir in $targets.Keys) {
    $px = $targets[$dir]
    $out = Join-Path $res "$dir\ic_launcher.png"
    if (-not (Test-Path (Split-Path $out))) {
        New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
    }

    $bmp = New-Object System.Drawing.Bitmap($px, $px)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($master, (New-Object System.Drawing.Rectangle(0, 0, $px, $px)))
    $g.Dispose()

    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("  {0,-16} {1,3}x{1}  {2:N1} KB" -f $dir, $px, ((Get-Item $out).Length / 1KB))
}

# A large copy for README / store listing use.
$preview = Join-Path $project 'build\icon-preview.png'
New-Item -ItemType Directory -Force (Split-Path $preview) | Out-Null
$master.Save($preview, [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()
Write-Output "  preview: $preview"
Write-Output 'DONE'
