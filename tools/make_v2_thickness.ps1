# Four thickness variations on V2 (inner clock hand). Everything else is
# identical: dawn ground, sun disc, 12 hour ticks at the original close-in
# radius, hand ending at 78% of the sun radius (so it never approaches the
# edge), dark pivot dot. Only the hand's stroke width changes.
#
#   tools\make_v2_thickness.ps1
#   -> build\logo-v2t-<name>.png       (each on its own, 512x512)
#   -> build\logo-v2t-sheet.png        (side-by-side comparison)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project 'build'
New-Item -ItemType Directory -Force $out | Out-Null

function New-Bmp([int]$s) {
    $b = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return @{ bmp = $b; g = $g }
}
function Argb([int]$a, [int]$r, [int]$g, [int]$b) {
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}
function Gradient($g, $s, $c1, $c2, $angle) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, [float]$angle)
    $g.FillRectangle($br, $rect)
    $br.Dispose()
}

# The only thing that varies. Given as a fraction of icon size to keep the
# stroke scaling consistent across densities.
$THICKNESSES = @(
    @{ name = 'hairline'; label = "T1. Hairline`n0.014s"; w = 0.014 },
    @{ name = 'thin';     label = "T2. Thin`n0.022s";     w = 0.022 },
    @{ name = 'medium';   label = "T3. Medium`n0.030s";   w = 0.030 },
    @{ name = 'bold';     label = "T4. Bold (original)`n0.038s"; w = 0.038 }
)

function Logo-V2-With-Thickness([int]$s, [double]$widthFrac) {
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s (Argb 255 32 30 66) (Argb 255 220 118 78) 60

    $cx = $s * 0.50; $cy = $s * 0.50

    # Tick ring — restored to the original close-in radius from V2. The user
    # was fine with it there; the wider spacing was my own drift.
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

    # Sun disc — original radius.
    $sunR = $s * 0.22
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun, [float]($cx - $sunR), [float]($cy - $sunR), [float]($sunR * 2), [float]($sunR * 2))
    $sun.Dispose()

    # Clock hand — original 78% length, only the thickness varies.
    $a = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
    $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * $widthFrac))
    $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($hand,
        [float]$cx, [float]$cy,
        [float]($cx + [Math]::Cos($a) * $sunR * 0.78),
        [float]($cy + [Math]::Sin($a) * $sunR * 0.78))
    $hand.Dispose()

    # Dark pivot — kept from the earlier draft, this was the good idea to
    # preserve.
    $pivot = New-Object System.Drawing.SolidBrush((Argb 255 60 40 40))
    $pr = $s * 0.020
    $g.FillEllipse($pivot, [float]($cx - $pr), [float]($cy - $pr), [float]($pr * 2), [float]($pr * 2))
    $pivot.Dispose(); $g.Dispose()
    return $h.bmp
}

$size = 512
foreach ($t in $THICKNESSES) {
    $bmp = Logo-V2-With-Thickness $size $t.w
    $out2 = Join-Path $out ("logo-v2t-{0}.png" -f $t.name)
    $bmp.Save($out2, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("  logo-v2t-{0,-9}  {1,5:N0} KB" -f $t.name, ((Get-Item $out2).Length / 1KB))
    $bmp.Dispose()
}

# --- comparison sheet ---
$tile = 360
$pad = 28
$cols = 4
$labelH = 56
$w = $cols * $tile + ($cols + 1) * $pad
$h = $tile + $labelH + 2 * $pad

$sheet = New-Object System.Drawing.Bitmap($w, $h)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.Clear([System.Drawing.Color]::FromArgb(255, 245, 246, 250))

$family = New-Object System.Drawing.FontFamily 'Segoe UI'
$labelFont = New-Object System.Drawing.Font($family, 13.0)
$labelBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 40, 42, 60))

for ($i = 0; $i -lt $THICKNESSES.Count; $i++) {
    $t = $THICKNESSES[$i]
    $x = $pad + $i * ($tile + $pad)
    $y = $pad
    $bmp = Logo-V2-With-Thickness $tile $t.w
    $sg.DrawImage($bmp, $x, $y, $tile, $tile)
    $bmp.Dispose()

    $tf = New-Object System.Drawing.StringFormat
    $tf.Alignment = [System.Drawing.StringAlignment]::Center
    $labelRect = New-Object System.Drawing.RectangleF($x, ($y + $tile + 6), $tile, $labelH)
    $sg.DrawString($t.label, $labelFont, $labelBr, $labelRect, $tf)
    $tf.Dispose()
}
$labelFont.Dispose(); $family.Dispose(); $labelBr.Dispose(); $sg.Dispose()

$sheetPath = Join-Path $out 'logo-v2t-sheet.png'
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output ''
Write-Output "  sheet: $sheetPath"
Write-Output 'DONE'
