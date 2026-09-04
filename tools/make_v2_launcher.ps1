# T2 and T3 rendered at each Android launcher density, at native pixel size.
# The point is to judge legibility as the icon will actually appear on a
# home screen — no upscaling from a master, no forgiving 512x512 downsample.
#
# Left column: the T2/T3 comparison at every density.
# Right column: a 3x zoom of the 48px render so we can see the pixel-level
# rendering (aliasing, dot survival, hand-tip crispness) that decides
# whether the design holds together at its smallest size.
#
#   tools\make_v2_launcher.ps1
#   -> build\logo-launcher-preview.png

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project 'build'
New-Item -ItemType Directory -Force $out | Out-Null

function Argb([int]$a, [int]$r, [int]$g, [int]$b) {
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}
function Gradient($g, $s, $c1, $c2, $angle) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, [float]$angle)
    $g.FillRectangle($br, $rect)
    $br.Dispose()
}

# Renders the icon at [$s] px native. Nothing here is scaled up from a
# larger master — each pixel is drawn at its final density, which is the
# only honest way to preview a small icon.
function Render([int]$s, [double]$handWidthFrac) {
    $b = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    Gradient $g $s (Argb 255 32 30 66) (Argb 255 220 118 78) 60

    $cx = $s * 0.50; $cy = $s * 0.50

    # Tick ring.
    $rIn = $s * 0.30; $rOut = $s * 0.34
    $tick = New-Object System.Drawing.Pen((Argb 90 245 244 252), [float]($s * 0.008))
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

    # Sun disc.
    $sunR = $s * 0.22
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun, [float]($cx - $sunR), [float]($cy - $sunR), [float]($sunR * 2), [float]($sunR * 2))
    $sun.Dispose()

    # Clock hand.
    $a = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
    $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * $handWidthFrac))
    $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($hand,
        [float]$cx, [float]$cy,
        [float]($cx + [Math]::Cos($a) * $sunR * 0.78),
        [float]($cy + [Math]::Sin($a) * $sunR * 0.78))
    $hand.Dispose()

    # Pivot dot.
    $pivot = New-Object System.Drawing.SolidBrush((Argb 255 60 40 40))
    $pr = $s * 0.020
    $g.FillEllipse($pivot, [float]($cx - $pr), [float]($cy - $pr), [float]($pr * 2), [float]($pr * 2))
    $pivot.Dispose(); $g.Dispose()
    return $b
}

# Zoom [$src] by nearest neighbour so each rendered pixel becomes a
# [$factor]x[$factor] block. This is what shows aliasing honestly.
function Zoom([System.Drawing.Bitmap]$src, [int]$factor) {
    $w = $src.Width * $factor
    $h = $src.Height * $factor
    $b = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)))
    $g.Dispose()
    return $b
}

# The five Android launcher densities.
$densities = @(
    @{ label = 'mdpi 48';    px = 48  },
    @{ label = 'hdpi 72';    px = 72  },
    @{ label = 'xhdpi 96';   px = 96  },
    @{ label = 'xxhdpi 144'; px = 144 },
    @{ label = 'xxxhdpi 192'; px = 192 }
)
$variants = @(
    @{ label = 'T2. Thin (0.022)';   hand = 0.022 },
    @{ label = 'T3. Medium (0.030)'; hand = 0.030 }
)

# --- layout ---
# Two rows (T2, T3). In each row: the 5 densities at native size, then a
# 3x zoom of the smallest (48px) so the pixel-level rendering is visible.

$pad = 26
$rowLabelW = 170
$cellPad = 20

# Compute row width from largest icon + zoom of smallest.
$sumOfCells = 0
foreach ($d in $densities) { $sumOfCells += $d.px + $cellPad }
$zoomCellW = 48 * 3 + $cellPad
$rowW = $rowLabelW + $sumOfCells + $zoomCellW

$rowH = 192 + 60   # tallest icon + label band
$sheetW = $rowW + 2 * $pad
$sheetH = $variants.Count * ($rowH + $pad) + $pad + 60

$sheet = New-Object System.Drawing.Bitmap($sheetW, $sheetH)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.Clear([System.Drawing.Color]::FromArgb(255, 245, 246, 250))

$family = New-Object System.Drawing.FontFamily 'Segoe UI'
$smallFont = New-Object System.Drawing.Font($family, 10.0)
$medFont = New-Object System.Drawing.Font($family, 12.0, [System.Drawing.FontStyle]::Bold)
$hdrFont = New-Object System.Drawing.Font($family, 11.0)
$ink = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 40, 42, 60))
$mute = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 130, 130, 145))

$centerFmt = New-Object System.Drawing.StringFormat
$centerFmt.Alignment = [System.Drawing.StringAlignment]::Center

# Column headers (top).
$y = $pad
$x = $pad + $rowLabelW
foreach ($d in $densities) {
    $lblRect = New-Object System.Drawing.RectangleF($x, $y, $d.px, 22)
    $sg.DrawString($d.label, $smallFont, $mute, $lblRect, $centerFmt)
    $x += $d.px + $cellPad
}
$zoomHdrRect = New-Object System.Drawing.RectangleF($x, $y, ($zoomCellW - $cellPad), 22)
$sg.DrawString('48 x3 (pixel view)', $smallFont, $mute, $zoomHdrRect, $centerFmt)

$y += 32
for ($v = 0; $v -lt $variants.Count; $v++) {
    $var = $variants[$v]

    # Row label.
    $rowLblRect = New-Object System.Drawing.RectangleF($pad, ($y + 60), $rowLabelW, 30)
    $sg.DrawString($var.label, $medFont, $ink, $rowLblRect)

    $x = $pad + $rowLabelW
    $smallest = $null
    foreach ($d in $densities) {
        $bmp = Render $d.px $var.hand
        if ($null -eq $smallest) { $smallest = $bmp }
        # Bottom-align inside the row so different sizes share a baseline.
        $cellY = $y + (192 - $d.px)
        $sg.DrawImage($bmp, $x, $cellY, $d.px, $d.px)
        # Don't dispose $smallest yet — we still need to zoom it.
        if ($bmp -ne $smallest) { $bmp.Dispose() }
        $x += $d.px + $cellPad
    }

    # Zoomed 48 rendering.
    $zoomed = Zoom $smallest 3
    $cellY = $y + (192 - $zoomed.Height)
    $sg.DrawImage($zoomed, $x, $cellY, $zoomed.Width, $zoomed.Height)
    $zoomed.Dispose()
    $smallest.Dispose()

    $y += $rowH + $pad
}

$smallFont.Dispose(); $medFont.Dispose(); $hdrFont.Dispose()
$family.Dispose(); $ink.Dispose(); $mute.Dispose(); $centerFmt.Dispose(); $sg.Dispose()

$outPath = Join-Path $out 'logo-launcher-preview.png'
$sheet.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output "  saved $outPath"
Write-Output 'DONE'
