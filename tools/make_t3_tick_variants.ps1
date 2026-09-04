# Five tick-thickness variations of T3 (hand at 0.030s), previewed at every
# Android launcher density. The hand, sun, pivot and gradient stay identical
# to T3; only the tick stroke width changes.
#
#   tools\make_t3_tick_variants.ps1
#   -> build\logo-t3-ticks-preview.png

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project 'build'
New-Item -ItemType Directory -Force $out | Out-Null

function Argb([int]$a, [int]$r, [int]$g, [int]$b) { return [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
function Gradient($g, $s, $c1, $c2, $angle) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, [float]$angle)
    $g.FillRectangle($br, $rect); $br.Dispose()
}

# Native-size render. Tick thickness is the only variable; a slightly higher
# tick opacity is also passed in for the thicker variants, because a heavier
# line at the same faint alpha reads as a smudge — thickness should carry
# some presence with it.
function Render([int]$s, [double]$tickFrac, [int]$tickAlpha) {
    $b = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    Gradient $g $s (Argb 255 32 30 66) (Argb 255 220 118 78) 60

    $cx = $s * 0.50; $cy = $s * 0.50
    $rIn = $s * 0.30; $rOut = $s * 0.34

    $tick = New-Object System.Drawing.Pen((Argb $tickAlpha 245 244 252), [float]($s * $tickFrac))
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

    $sunR = $s * 0.22
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun, [float]($cx - $sunR), [float]($cy - $sunR), [float]($sunR * 2), [float]($sunR * 2))
    $sun.Dispose()

    $a = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
    $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * 0.030))
    $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($hand,
        [float]$cx, [float]$cy,
        [float]($cx + [Math]::Cos($a) * $sunR * 0.78),
        [float]($cy + [Math]::Sin($a) * $sunR * 0.78))
    $hand.Dispose()

    $pivot = New-Object System.Drawing.SolidBrush((Argb 255 60 40 40))
    $pr = $s * 0.020
    $g.FillEllipse($pivot, [float]($cx - $pr), [float]($cy - $pr), [float]($pr * 2), [float]($pr * 2))
    $pivot.Dispose(); $g.Dispose()
    return $b
}

function Zoom([System.Drawing.Bitmap]$src, [int]$factor) {
    $w = $src.Width * $factor; $h = $src.Height * $factor
    $b = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)))
    $g.Dispose(); return $b
}

$densities = @(
    @{ label = 'mdpi 48';    px = 48  },
    @{ label = 'hdpi 72';    px = 72  },
    @{ label = 'xhdpi 96';   px = 96  },
    @{ label = 'xxhdpi 144'; px = 144 },
    @{ label = 'xxxhdpi 192'; px = 192 }
)
# Alpha increases with thickness so a heavier stroke also carries a bit more
# presence — otherwise a thick, translucent line just reads as a smudge.
$variants = @(
    @{ label = 'K1. 0.008 s   (current)';   tick = 0.008; alpha = 90  },
    @{ label = 'K2. 0.010 s';                tick = 0.010; alpha = 105 },
    @{ label = 'K3. 0.012 s';                tick = 0.012; alpha = 120 },
    @{ label = 'K4. 0.014 s';                tick = 0.014; alpha = 135 },
    @{ label = 'K5. 0.017 s   (bold)';       tick = 0.017; alpha = 150 }
)

# --- layout ---
$pad = 26
$rowLabelW = 200
$cellPad = 20
$sumOfCells = 0
foreach ($d in $densities) { $sumOfCells += $d.px + $cellPad }
$zoomCellW = 48 * 3 + $cellPad
$rowW = $rowLabelW + $sumOfCells + $zoomCellW
$rowH = 192 + 20

$sheetW = $rowW + 2 * $pad
$sheetH = $variants.Count * ($rowH + $pad) + $pad + 40

$sheet = New-Object System.Drawing.Bitmap($sheetW, $sheetH)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.Clear([System.Drawing.Color]::FromArgb(255, 245, 246, 250))

$family = New-Object System.Drawing.FontFamily 'Segoe UI'
$smallFont = New-Object System.Drawing.Font($family, 10.0)
$medFont = New-Object System.Drawing.Font($family, 12.0, [System.Drawing.FontStyle]::Bold)
$ink = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 40, 42, 60))
$mute = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 130, 130, 145))
$centerFmt = New-Object System.Drawing.StringFormat
$centerFmt.Alignment = [System.Drawing.StringAlignment]::Center

# Column headers.
$y = $pad
$x = $pad + $rowLabelW
foreach ($d in $densities) {
    $sg.DrawString($d.label, $smallFont, $mute,
        (New-Object System.Drawing.RectangleF($x, $y, $d.px, 22)), $centerFmt)
    $x += $d.px + $cellPad
}
$sg.DrawString('48 x3 (pixel view)', $smallFont, $mute,
    (New-Object System.Drawing.RectangleF($x, $y, ($zoomCellW - $cellPad), 22)), $centerFmt)

$y += 26
foreach ($var in $variants) {
    $sg.DrawString($var.label, $medFont, $ink,
        (New-Object System.Drawing.RectangleF($pad, ($y + 80), $rowLabelW, 30)))

    $x = $pad + $rowLabelW
    $smallest = $null
    foreach ($d in $densities) {
        $bmp = Render $d.px $var.tick $var.alpha
        if ($null -eq $smallest) { $smallest = $bmp }
        $sg.DrawImage($bmp, $x, ($y + 192 - $d.px), $d.px, $d.px)
        if ($bmp -ne $smallest) { $bmp.Dispose() }
        $x += $d.px + $cellPad
    }
    $zoomed = Zoom $smallest 3
    $sg.DrawImage($zoomed, $x, ($y + 192 - $zoomed.Height), $zoomed.Width, $zoomed.Height)
    $zoomed.Dispose(); $smallest.Dispose()

    $y += $rowH + $pad
}

$smallFont.Dispose(); $medFont.Dispose(); $family.Dispose()
$ink.Dispose(); $mute.Dispose(); $centerFmt.Dispose(); $sg.Dispose()

$outPath = Join-Path $out 'logo-t3-ticks-preview.png'
$sheet.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output "  saved $outPath"
Write-Output 'DONE'
