# Launcher icons for Android, rendered from a single vector definition to every
# density. Kept as a script rather than committing only PNGs so the mark can be
# retuned without hunting for whatever tool made it. Uses System.Drawing, so no
# image toolchain to install.
#
#   tools\make_icon.ps1
#
# The mark: an inscribed square rotated 30 degrees, hollow, with a small
# accent disc at one corner. A "prahar" is a division of the day, and this is a
# schematic of one - a fixed frame with a point of focus. Deliberately not a
# clock or a pie chart: those read as "timer app" and are what every calendar
# icon on the store already is.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$res = Join-Path $project 'android\app\src\main\res'

function New-Icon([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Background: subtle radial-suggesting linear gradient. The angle carries
    # depth without so much saturation that it reads as toy.
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $top = [System.Drawing.Color]::FromArgb(255, 41, 46, 96)   # deep navy
    $bot = [System.Drawing.Color]::FromArgb(255, 88, 74, 176)  # muted violet
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, $top, $bot, 55.0)
    $g.FillRectangle($bg, $rect)

    # Fine noise-suggesting hairline ring so the shape has a considered outer
    # edge rather than sitting on the raw background - one of the touches that
    # separates a hand-tuned icon from a generic one.
    $edgePen = New-Object System.Drawing.Pen(
        [System.Drawing.Color]::FromArgb(28, 255, 255, 255), [float]($size * 0.006))
    $inset = $size * 0.06
    $g.DrawEllipse($edgePen,
        [float]$inset, [float]$inset,
        [float]($size - 2 * $inset), [float]($size - 2 * $inset))

    # The mark itself: a rotated square, drawn with rounded joins. Off-white
    # rather than pure white to sit better against the gradient at small sizes.
    $g.TranslateTransform([float]($size / 2.0), [float]($size / 2.0))
    $g.RotateTransform(30.0)

    $side = $size * 0.42
    $stroke = $size * 0.075
    $off = [float](-$side / 2.0)

    $ink = [System.Drawing.Color]::FromArgb(255, 245, 244, 252)
    $pen = New-Object System.Drawing.Pen($ink, [float]$stroke)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawRectangle($pen, $off, $off, [float]$side, [float]$side)

    # Accent: a small filled circle where the top-right corner sits after the
    # rotation. Reads as a point of focus, and gives the composition an anchor
    # so it does not float symmetrically.
    $ax = [float]($side / 2.0)
    $ay = [float](-$side / 2.0)
    $accentR = $size * 0.075
    $accentColour = [System.Drawing.Color]::FromArgb(255, 250, 176, 116) # amber
    $accent = New-Object System.Drawing.SolidBrush($accentColour)
    $g.FillEllipse($accent,
        [float]($ax - $accentR), [float]($ay - $accentR),
        [float]($accentR * 2), [float]($accentR * 2))

    $g.ResetTransform()
    $g.Dispose()
    $bg.Dispose(); $edgePen.Dispose(); $pen.Dispose(); $accent.Dispose()
    return $bmp
}

# Render once large and downsample for every density; produces cleaner small
# icons than rendering each size natively.
$master = New-Icon 1024

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

$preview = Join-Path $project 'build\icon-preview.png'
New-Item -ItemType Directory -Force (Split-Path $preview) | Out-Null
$master.Save($preview, [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()
Write-Output "  preview: $preview"
Write-Output 'DONE'
