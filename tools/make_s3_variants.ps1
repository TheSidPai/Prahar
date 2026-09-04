# Five refinements of S3 (sun + hour marks). Each keeps the dawn gradient
# and the 12-tick ring; the differences are how (or whether) the "current
# moment" is marked.
#
#   tools\make_s3_variants.ps1
#   -> build\logo-s3-<name>.png       (each on its own, 512x512)
#   -> build\logo-s3-sheet.png        (all five side by side, labelled)

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

# Shared: dawn ground, sun disc, tick ring. Every variant calls these so the
# five are trivially comparable — only the "current moment" mark differs.
function Draw-Ground($g, $s) {
    Gradient $g $s (Argb 255 32 30 66) (Argb 255 220 118 78) 60
}
function Draw-Sun($g, $s, $cx, $cy, $r) {
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun, [float]($cx - $r), [float]($cy - $r), [float]($r * 2), [float]($r * 2))
    $sun.Dispose()
}
function Draw-Ticks($g, $s, $cx, $cy, $rIn, $rOut, $skipIndex = -1) {
    $tick = New-Object System.Drawing.Pen((Argb 90 245 244 252), [float]($s * 0.008))
    $tick.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $tick.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    for ($i = 0; $i -lt 12; $i++) {
        if ($i -eq $skipIndex) { continue }
        $a = [Math]::PI * 2 * ($i / 12.0) - [Math]::PI / 2
        $x1 = $cx + [Math]::Cos($a) * $rIn
        $y1 = $cy + [Math]::Sin($a) * $rIn
        $x2 = $cx + [Math]::Cos($a) * $rOut
        $y2 = $cy + [Math]::Sin($a) * $rOut
        $g.DrawLine($tick, [float]$x1, [float]$y1, [float]$x2, [float]$y2)
    }
    $tick.Dispose()
}

# --- V1: no ticker at all ----------------------------------------------
# Reads as "the day, waiting". Restraint — the viewer supplies the moment.
function Logo-S3-Clean([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    Draw-Ground $g $s
    $cx = $s * 0.50; $cy = $s * 0.50
    Draw-Ticks $g $s $cx $cy ($s * 0.30) ($s * 0.34)
    Draw-Sun $g $s $cx $cy ($s * 0.20)
    $g.Dispose(); return $h.bmp
}

# --- V2: amber inside the sun as a clock hand --------------------------
# The marker becomes a hand pointing to the hour, contained within the sun
# rather than extending to a tick. Reads much more as "a scheduled moment"
# because the metaphor of a clock hand is unmistakable.
function Logo-S3-InnerHand([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    Draw-Ground $g $s
    $cx = $s * 0.50; $cy = $s * 0.50
    Draw-Ticks $g $s $cx $cy ($s * 0.30) ($s * 0.34)
    $sunR = $s * 0.22
    Draw-Sun $g $s $cx $cy $sunR

    # A single clock hand from the sun's centre, pointing at "2 o'clock".
    $a = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
    $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * 0.038))
    $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($hand,
        [float]$cx, [float]$cy,
        [float]($cx + [Math]::Cos($a) * $sunR * 0.78),
        [float]($cy + [Math]::Sin($a) * $sunR * 0.78))
    $hand.Dispose()

    # Tiny centre dot so the pivot reads as intentional, not a smudge.
    $pivot = New-Object System.Drawing.SolidBrush((Argb 255 220 118 78))
    $pr = $s * 0.016
    $g.FillEllipse($pivot, [float]($cx - $pr), [float]($cy - $pr), [float]($pr * 2), [float]($pr * 2))
    $pivot.Dispose(); $g.Dispose(); return $h.bmp
}

# --- V3: highlighted hour mark, no connecting ray ----------------------
# One tick is amber and slightly thicker/longer. The eye jumps to it, but
# nothing is drawn between it and the sun — the composition breathes.
function Logo-S3-Highlight([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    Draw-Ground $g $s
    $cx = $s * 0.50; $cy = $s * 0.50
    $rIn = $s * 0.30; $rOut = $s * 0.34
    Draw-Ticks $g $s $cx $cy $rIn $rOut 2  # skip the 2 o'clock tick

    # Draw the highlighted tick over the skipped position.
    $a = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
    $highlight = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * 0.016))
    $highlight.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $highlight.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($highlight,
        [float]($cx + [Math]::Cos($a) * ($rIn - $s * 0.015)),
        [float]($cy + [Math]::Sin($a) * ($rIn - $s * 0.015)),
        [float]($cx + [Math]::Cos($a) * ($rOut + $s * 0.020)),
        [float]($cy + [Math]::Sin($a) * ($rOut + $s * 0.020)))
    $highlight.Dispose()

    Draw-Sun $g $s $cx $cy ($s * 0.20)
    $g.Dispose(); return $h.bmp
}

# --- V4: two hands, showing block start and end ------------------------
# Two clock hands from the sun's centre: a bolder one at the block start
# (say 9), a paler one at the block end (say 10). Reads as an active study
# block. Slightly denser but more informative.
function Logo-S3-BlockSpan([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    Draw-Ground $g $s
    $cx = $s * 0.50; $cy = $s * 0.50
    Draw-Ticks $g $s $cx $cy ($s * 0.30) ($s * 0.34)
    $sunR = $s * 0.22
    Draw-Sun $g $s $cx $cy $sunR

    function Hand($g, $cx, $cy, $sunR, $hour, $colour, $widthS, $s) {
        $a = [Math]::PI * 2 * ($hour / 12.0) - [Math]::PI / 2
        $pen = New-Object System.Drawing.Pen($colour, [float]$widthS)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawLine($pen,
            [float]$cx, [float]$cy,
            [float]($cx + [Math]::Cos($a) * $sunR * 0.78),
            [float]($cy + [Math]::Sin($a) * $sunR * 0.78))
        $pen.Dispose()
    }

    Hand $g $cx $cy $sunR 10 (Argb 130 246 148 96) ($s * 0.026) $s
    Hand $g $cx $cy $sunR 9  (Argb 255 246 148 96) ($s * 0.038) $s

    $pivot = New-Object System.Drawing.SolidBrush((Argb 255 220 118 78))
    $pr = $s * 0.018
    $g.FillEllipse($pivot, [float]($cx - $pr), [float]($cy - $pr), [float]($pr * 2), [float]($pr * 2))
    $pivot.Dispose(); $g.Dispose(); return $h.bmp
}

# --- V5: soft glow ring around the sun ---------------------------------
# No hand at all. A soft amber ring hugs the sun from outside — the whole
# sun "is on fire". Reads as "focus" more than "scheduled". Warmest of the
# five; feels the most premium.
function Logo-S3-Glow([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    Draw-Ground $g $s
    $cx = $s * 0.50; $cy = $s * 0.50
    Draw-Ticks $g $s $cx $cy ($s * 0.30) ($s * 0.34)

    $sunR = $s * 0.20

    # Three concentric rings of decreasing opacity for a soft-glow effect.
    for ($i = 0; $i -lt 3; $i++) {
        $ringR = $sunR + $s * (0.020 + $i * 0.024)
        $alpha = 130 - $i * 40
        $ring = New-Object System.Drawing.Pen((Argb $alpha 246 148 96), [float]($s * 0.018))
        $g.DrawEllipse($ring, [float]($cx - $ringR), [float]($cy - $ringR), [float]($ringR * 2), [float]($ringR * 2))
        $ring.Dispose()
    }

    Draw-Sun $g $s $cx $cy $sunR
    $g.Dispose(); return $h.bmp
}

# --- render each -------------------------------------------------------

$candidates = @(
    @{ name = 'clean';       label = "V1. Clean`nNo marker"; fn = { param($s) Logo-S3-Clean $s } },
    @{ name = 'inner-hand';  label = "V2. Inner hand`nClock hand inside sun"; fn = { param($s) Logo-S3-InnerHand $s } },
    @{ name = 'highlight';   label = "V3. Highlight`nOne tick in amber"; fn = { param($s) Logo-S3-Highlight $s } },
    @{ name = 'block-span';  label = "V4. Block span`nTwo hands, start and end"; fn = { param($s) Logo-S3-BlockSpan $s } },
    @{ name = 'glow';        label = "V5. Glow`nSun with soft aura"; fn = { param($s) Logo-S3-Glow $s } }
)

$size = 512
foreach ($c in $candidates) {
    $bmp = & $c.fn $size
    $out2 = Join-Path $out ("logo-s3-{0}.png" -f $c.name)
    $bmp.Save($out2, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("  logo-s3-{0,-14}  {1,5:N0} KB" -f $c.name, ((Get-Item $out2).Length / 1KB))
    $bmp.Dispose()
}

# --- composite sheet ---------------------------------------------------

$tile = 320
$pad = 28
$cols = 5
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

for ($i = 0; $i -lt $candidates.Count; $i++) {
    $c = $candidates[$i]
    $x = $pad + $i * ($tile + $pad)
    $y = $pad
    $bmp = & $c.fn $tile
    $sg.DrawImage($bmp, $x, $y, $tile, $tile)
    $bmp.Dispose()

    $tf = New-Object System.Drawing.StringFormat
    $tf.Alignment = [System.Drawing.StringAlignment]::Center
    $labelRect = New-Object System.Drawing.RectangleF($x, ($y + $tile + 6), $tile, $labelH)
    $sg.DrawString($c.label, $labelFont, $labelBr, $labelRect, $tf)
    $tf.Dispose()
}

$labelFont.Dispose(); $family.Dispose(); $labelBr.Dispose(); $sg.Dispose()

$sheetPath = Join-Path $out 'logo-s3-sheet.png'
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output ''
Write-Output "  sheet: $sheetPath"
Write-Output 'DONE'
