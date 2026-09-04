# Generates the launcher icon into android/app/src/main/res/mipmap-*.
#
# The mark: a sun with 12 faint hour marks around it and a single amber clock
# hand pointing to a specific moment - a schematic of a scheduled block in the
# day. The gradient is dawn-warm: night navy at the top, sunrise amber at
# the bottom. A dark pivot dot at the centre anchors the hand.
#
#   tools\make_icon.ps1
#
# All proportions are fractions of the icon size, so each density renders
# from the same specification rather than five slightly different drawings.
# Numbers here are the result of the T3 (hand) + K4 (tick) tuning pass;
# see tools\make_v2_thickness.ps1 and tools\make_t3_tick_variants.ps1 for
# the previews that led here.
#
# The whole mark was then scaled up by 0.26/0.22 = 1.182 - the sun read too
# small inside the tile. Every measurement below is multiplied by that one
# factor, ticks and stroke widths included, so this is the same drawing seen
# closer rather than a fatter sun inside the old ring. The T3+K4 ratios are
# therefore untouched; only the zoom changed.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$res = Join-Path $project 'android\app\src\main\res'

function Argb([int]$a, [int]$r, [int]$g, [int]$b) {
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

function New-Icon([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Ground: dawn gradient. Angle 60 so the amber pools bottom-right, which
    # aligns visually with the amber hand pointing top-right.
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $ground = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, (Argb 255 32 30 66), (Argb 255 220 118 78), 60.0)
    $g.FillRectangle($ground, $rect)
    $ground.Dispose()

    $cx = $size * 0.50
    $cy = $size * 0.50

    # Hour ticks - K4 tuning at 1.182x zoom. Thickness 0.014 -> 0.0165, ring
    # 0.30..0.34 -> 0.3545..0.4018. The ring keeps its 4-unit width relative to
    # the sun, so the gap between sun edge and ticks reads exactly as before.
    $rIn = $size * 0.3545
    $rOut = $size * 0.4018
    $tick = New-Object System.Drawing.Pen((Argb 135 245 244 252), [float]($size * 0.0165))
    $tick.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $tick.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    for ($i = 0; $i -lt 12; $i++) {
        $a = [Math]::PI * 2 * ($i / 12.0) - [Math]::PI / 2
        $g.DrawLine($tick,
            [float]($cx + [Math]::Cos($a) * $rIn),
            [float]($cy + [Math]::Sin($a) * $rIn),
            [float]($cx + [Math]::Cos($a) * $rOut),
            [float]($cy + [Math]::Sin($a) * $rOut))
    }
    $tick.Dispose()

    # Sun disc. 0.22 -> 0.26; the zoom factor every other number here follows.
    $sunR = $size * 0.26
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun,
        [float]($cx - $sunR), [float]($cy - $sunR),
        [float]($sunR * 2), [float]($sunR * 2))
    $sun.Dispose()

    # Clock hand - T3 tuning at 1.182x zoom. Stroke 0.030 -> 0.0355; the length
    # stays 78% of the sun radius, which scales with the sun on its own.
    $a = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
    $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($size * 0.0355))
    $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($hand,
        [float]$cx, [float]$cy,
        [float]($cx + [Math]::Cos($a) * $sunR * 0.78),
        [float]($cy + [Math]::Sin($a) * $sunR * 0.78))
    $hand.Dispose()

    # Pivot: a dark disc at the hand's origin. Reads as intentional anchor
    # rather than an artefact.
    $pivot = New-Object System.Drawing.SolidBrush((Argb 255 60 40 40))
    $pr = $size * 0.0236   # 0.020 * 1.182
    $g.FillEllipse($pivot,
        [float]($cx - $pr), [float]($cy - $pr),
        [float]($pr * 2), [float]($pr * 2))
    $pivot.Dispose(); $g.Dispose()

    return $bmp
}

# Render once large and downsample. Direct native renders at 48px lose
# subpixel detail; a bicubic downsample from 1024 keeps the ticks and hand
# looking as designed rather than as anti-aliased approximations.
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

# Large preview for the README / store listing.
$preview = Join-Path $project 'build\icon-preview.png'
New-Item -ItemType Directory -Force (Split-Path $preview) | Out-Null
$master.Save($preview, [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()
Write-Output "  preview: $preview"
Write-Output 'DONE'
