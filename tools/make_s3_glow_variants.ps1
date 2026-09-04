# Four takes on "clock hand inside a glowing sun". Each keeps the composition
# — dawn ground, sun in the centre, longer hand, dark pivot dot, hour ticks
# pushed outward so the glow does not crowd them — and varies only how the
# glow itself reads. The tick radius (0.40..0.44) is the same on all four, so
# the glow always has clean space between it and the ticks.
#
#   tools\make_s3_glow_variants.ps1
#   -> build\logo-glow-<name>.png
#   -> build\logo-glow-sheet.png

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

# Composition constants. Ticks live at 0.40..0.44 so there is a genuine ring
# of empty space between the glow and them regardless of how far the glow
# extends. Sun radius stays 0.18 — a hair smaller than the earlier drafts so
# the glow has room to breathe.
$SUN_R  = 0.18
$TICK_IN = 0.40
$TICK_OUT = 0.44
$HAND_HOUR = 2   # points at "2 o'clock" — off-vertical enough to read as a hand rather than a slit

# The shared bits every variant paints.
function Base($g, $s) {
    Gradient $g $s (Argb 255 32 30 66) (Argb 255 220 118 78) 60
    $cx = $s * 0.50; $cy = $s * 0.50

    # Tick ring — the same on every variant.
    $tick = New-Object System.Drawing.Pen((Argb 100 245 244 252), [float]($s * 0.009))
    $tick.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $tick.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    for ($i = 0; $i -lt 12; $i++) {
        $a = [Math]::PI * 2 * ($i / 12.0) - [Math]::PI / 2
        $g.DrawLine($tick,
            [float]($cx + [Math]::Cos($a) * $s * $TICK_IN),
            [float]($cy + [Math]::Sin($a) * $s * $TICK_IN),
            [float]($cx + [Math]::Cos($a) * $s * $TICK_OUT),
            [float]($cy + [Math]::Sin($a) * $s * $TICK_OUT))
    }
    $tick.Dispose()
    return @{ cx = $cx; cy = $cy }
}

function Sun-With-Hand($g, $s, $cx, $cy) {
    # Sun disc.
    $sunR = $s * $SUN_R
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun, [float]($cx - $sunR), [float]($cy - $sunR), [float]($sunR * 2), [float]($sunR * 2))
    $sun.Dispose()

    # Clock hand — extends to 0.92 of the sun radius, up from 0.78. Also a
    # slightly heavier stroke so the hand does not look thin on a small icon.
    $a = [Math]::PI * 2 * ($HAND_HOUR / 12.0) - [Math]::PI / 2
    $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * 0.044))
    $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($hand,
        [float]$cx, [float]$cy,
        [float]($cx + [Math]::Cos($a) * $sunR * 0.92),
        [float]($cy + [Math]::Sin($a) * $sunR * 0.92))
    $hand.Dispose()

    # Dark pivot — a touch bigger than the earlier draft so it reads as a
    # deliberate anchor rather than a shadow spot.
    $pivot = New-Object System.Drawing.SolidBrush((Argb 255 60 40 40))
    $pr = $s * 0.022
    $g.FillEllipse($pivot, [float]($cx - $pr), [float]($cy - $pr), [float]($pr * 2), [float]($pr * 2))
    $pivot.Dispose()
}

# --- G1: single tight halo ---------------------------------------------
# One glow ring hugging the sun. Sits comfortably between the sun edge and
# the tick ring — clean separation, no ambiguity.
function Logo-Glow-Single([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    $c = Base $g $s
    # One soft ring at sun_r + 0.03.
    $ring = New-Object System.Drawing.Pen((Argb 150 246 148 96), [float]($s * 0.020))
    $rr = $s * ($SUN_R + 0.03)
    $g.DrawEllipse($ring,
        [float]($c.cx - $rr), [float]($c.cy - $rr),
        [float]($rr * 2), [float]($rr * 2))
    $ring.Dispose()
    Sun-With-Hand $g $s $c.cx $c.cy
    $g.Dispose(); return $h.bmp
}

# --- G2: layered aura ---------------------------------------------------
# Three concentric rings of decreasing opacity, stopping short of the ticks.
# Looks the most "premium" — the halo really shimmers — at the cost of
# slightly less breathing space between glow and tick.
function Logo-Glow-Layered([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    $c = Base $g $s
    $offsets = @(0.028, 0.055, 0.085)
    $alphas  = @(160, 100, 55)
    for ($i = 0; $i -lt 3; $i++) {
        $rr = $s * ($SUN_R + $offsets[$i])
        $ring = New-Object System.Drawing.Pen((Argb $alphas[$i] 246 148 96), [float]($s * 0.014))
        $g.DrawEllipse($ring,
            [float]($c.cx - $rr), [float]($c.cy - $rr),
            [float]($rr * 2), [float]($rr * 2))
        $ring.Dispose()
    }
    Sun-With-Hand $g $s $c.cx $c.cy
    $g.Dispose(); return $h.bmp
}

# --- G3: soft filled halo ----------------------------------------------
# Rather than a stroke, the glow is a soft radial-suggesting fill using a
# path-based gradient — a plate of light under the sun. Warmest and most
# ambient of the four; feels lit from the inside.
function Logo-Glow-Filled([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    $c = Base $g $s

    # A path-gradient brush centred on the sun: bright amber core, transparent
    # at the halo edge. Sits a little wider than the sun.
    $haloR = $s * 0.30
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse(
        [float]($c.cx - $haloR), [float]($c.cy - $haloR),
        [float]($haloR * 2), [float]($haloR * 2))
    $halo = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
    $halo.CenterColor = (Argb 180 250 176 116)
    $halo.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 250, 176, 116))
    $halo.CenterPoint = New-Object System.Drawing.PointF([float]$c.cx, [float]$c.cy)
    $g.FillPath($halo, $path)
    $halo.Dispose(); $path.Dispose()

    Sun-With-Hand $g $s $c.cx $c.cy
    $g.Dispose(); return $h.bmp
}

# --- G4: two crisp rings, wider apart ----------------------------------
# Only two rings, deliberately spaced so the second sits about halfway to
# the tick ring. Reads more architectural than atmospheric — closer to a
# schematic than a mood piece.
function Logo-Glow-Crisp([int]$s) {
    $h = New-Bmp $s; $g = $h.g
    $c = Base $g $s
    foreach ($pair in @(@(0.032, 190), @(0.090, 110))) {
        $rr = $s * ($SUN_R + $pair[0])
        $ring = New-Object System.Drawing.Pen((Argb $pair[1] 246 148 96), [float]($s * 0.014))
        $g.DrawEllipse($ring,
            [float]($c.cx - $rr), [float]($c.cy - $rr),
            [float]($rr * 2), [float]($rr * 2))
        $ring.Dispose()
    }
    Sun-With-Hand $g $s $c.cx $c.cy
    $g.Dispose(); return $h.bmp
}

# --- render each -------------------------------------------------------

$candidates = @(
    @{ name = 'single';  label = "G1. Single halo`nOne close ring";                        fn = { param($s) Logo-Glow-Single $s } },
    @{ name = 'layered'; label = "G2. Layered aura`nThree fading rings";                   fn = { param($s) Logo-Glow-Layered $s } },
    @{ name = 'filled';  label = "G3. Soft plate`nRadial fill, lit from within";           fn = { param($s) Logo-Glow-Filled $s } },
    @{ name = 'crisp';   label = "G4. Two rings`nArchitectural, well spaced";              fn = { param($s) Logo-Glow-Crisp $s } }
)

$size = 512
foreach ($c in $candidates) {
    $bmp = & $c.fn $size
    $out2 = Join-Path $out ("logo-glow-{0}.png" -f $c.name)
    $bmp.Save($out2, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("  logo-glow-{0,-10}  {1,5:N0} KB" -f $c.name, ((Get-Item $out2).Length / 1KB))
    $bmp.Dispose()
}

# --- composite sheet ---------------------------------------------------

$tile = 340
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

$sheetPath = Join-Path $out 'logo-glow-sheet.png'
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output ''
Write-Output "  sheet: $sheetPath"
Write-Output 'DONE'
