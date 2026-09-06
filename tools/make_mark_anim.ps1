# Renders proposed mark animations as filmstrips, to be judged before any of
# it is written into the app.
#
# Same principle as make_nav_options.ps1: motion is a design decision, and a
# decision made from a description is a decision made blind. Each strip is ten
# frames left to right across the whole timeline, so the shape of the motion —
# what arrives first, what overshoots, what is still moving at the end — can
# be read at a glance.
#
# The geometry is lifted from make_icon.ps1 unchanged, so these are frames of
# the real mark rather than an impression of it. Only the drawing is animated;
# the proportions are the same T3+K4 numbers at the same 1.182x zoom.
#
#   tools\make_mark_anim.ps1
#   -> build\anim_<variant>.png

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'build'
New-Item -ItemType Directory -Force $outDir | Out-Null

function Argb([int]$a, [int]$r, [int]$g, [int]$b) {
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

# --- easing, the same curves Flutter names -------------------------------

function Clamp01([double]$t) { if ($t -lt 0) { return 0.0 } elseif ($t -gt 1) { return 1.0 } else { return $t } }

function EaseOutCubic([double]$t) { $t = Clamp01 $t; return 1 - [Math]::Pow(1 - $t, 3) }

function EaseOutBack([double]$t) {
    $t = Clamp01 $t
    $c1 = 1.70158; $c3 = $c1 + 1
    return 1 + $c3 * [Math]::Pow($t - 1, 3) + $c1 * [Math]::Pow($t - 1, 2)
}

# Maps a global 0..1 onto a sub-interval, which is exactly what Flutter's
# Interval curve does inside a staggered animation.
function Stage([double]$t, [double]$from, [double]$to) {
    if ($to -le $from) { return 1.0 }
    return Clamp01(($t - $from) / ($to - $from))
}

# --- one frame of the mark ------------------------------------------------

function Draw-Mark {
    param(
        [System.Drawing.Graphics]$g,
        [int]$size,
        [double]$sunT,      # 0..1 disc scale
        [double]$tickT,     # 0..1 how far round the ticks have arrived
        [double]$handT,     # 0..1 hand sweep
        [bool]$staggerTicks # ticks one by one, or all together
    )

    $cx = $size * 0.50
    $cy = $size * 0.50

    $rIn = $size * 0.3545
    $rOut = $size * 0.4018

    # Ticks. Each one either fades in on its own slice of the tick stage
    # (stagger) or the whole ring fades together.
    for ($i = 0; $i -lt 12; $i++) {
        $local = if ($staggerTicks) {
            # Clockwise from noon, each tick taking a fifth of the stage so
            # they overlap rather than march.
            $start = $i / 12.0 * 0.8
            Stage $tickT $start ($start + 0.2)
        } else { $tickT }

        if ($local -le 0) { continue }
        $alpha = [int](135 * (EaseOutCubic $local))
        if ($alpha -le 0) { continue }

        $pen = New-Object System.Drawing.Pen((Argb $alpha 245 244 252), [float]($size * 0.0165))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

        $a = [Math]::PI * 2 * ($i / 12.0) - [Math]::PI / 2
        # Grows outward from the inner radius, so a tick is drawn rather than
        # switched on.
        $grow = EaseOutCubic $local
        $g.DrawLine($pen,
            [float]($cx + [Math]::Cos($a) * $rIn),
            [float]($cy + [Math]::Sin($a) * $rIn),
            [float]($cx + [Math]::Cos($a) * ($rIn + ($rOut - $rIn) * $grow)),
            [float]($cy + [Math]::Sin($a) * ($rIn + ($rOut - $rIn) * $grow)))
        $pen.Dispose()
    }

    # Sun disc, scaling from nothing with a little overshoot.
    if ($sunT -gt 0) {
        $scale = EaseOutBack $sunT
        $sunR = $size * 0.26 * $scale
        if ($sunR -gt 0) {
            $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
            $g.FillEllipse($sun,
                [float]($cx - $sunR), [float]($cy - $sunR),
                [float]($sunR * 2), [float]($sunR * 2))
            $sun.Dispose()
        }
    }

    # The hand sweeps from noon round to two o'clock.
    if ($handT -gt 0) {
        $sunR = $size * 0.26
        $target = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
        $start = -[Math]::PI / 2
        $a = $start + ($target - $start) * (EaseOutCubic $handT)

        $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($size * 0.0355))
        $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawLine($hand,
            [float]$cx, [float]$cy,
            [float]($cx + [Math]::Cos($a) * $sunR * 0.78),
            [float]($cy + [Math]::Sin($a) * $sunR * 0.78))
        $hand.Dispose()

        $pivotR = $size * 0.0236
        $pivot = New-Object System.Drawing.SolidBrush((Argb 255 32 30 66))
        $g.FillEllipse($pivot,
            [float]($cx - $pivotR), [float]($cy - $pivotR),
            [float]($pivotR * 2), [float]($pivotR * 2))
        $pivot.Dispose()
    }
}

# --- the variants ---------------------------------------------------------
#
# Three timings over the same drawing. What differs is the order things
# arrive in and how much they overlap, which is the whole question.

$variants = [ordered]@{
    # Core first, then the ring is written on clockwise, then the hand
    # sweeps. Reads as the mark being assembled.
    'unfurl' = @{
        label = 'Unfurl: sun 0-35%, ticks stagger 20-70%, hand 35-90%'
        sun = @(0.00, 0.35); ticks = @(0.20, 0.70); hand = @(0.35, 0.90); stagger = $true
    }
    # Everything overlaps heavily and finishes together. Quicker, less of a
    # performance, better if this plays on every cold start.
    'bloom' = @{
        label = 'Bloom: sun 0-45%, ticks together 15-65%, hand 25-80%'
        sun = @(0.00, 0.45); ticks = @(0.15, 0.65); hand = @(0.25, 0.80); stagger = $false
    }
    # The hand leads and the ring follows it round, as though the hand were
    # drawing the ticks as it passes them.
    'sweep' = @{
        label = 'Sweep: hand 0-60% leads, ticks trail 10-85%, sun 0-30%'
        sun = @(0.00, 0.30); ticks = @(0.10, 0.85); hand = @(0.00, 0.60); stagger = $true
    }
}

$frames = 10
$cell = 150
$pad = 24
$labelH = 40

foreach ($name in $variants.Keys) {
    $v = $variants[$name]
    $w = $pad * 2 + $cell * $frames
    $h = $pad * 2 + $cell + $labelH

    $sheet = New-Object System.Drawing.Bitmap($w, $h)
    $sg = [System.Drawing.Graphics]::FromImage($sheet)
    $sg.SmoothingMode = 'AntiAlias'
    $sg.TextRenderingHint = 'AntiAliasGridFit'
    $sg.Clear((Argb 255 16 18 22))

    for ($f = 0; $f -lt $frames; $f++) {
        $t = $f / ($frames - 1.0)

        $tile = New-Object System.Drawing.Bitmap($cell, $cell)
        $tg = [System.Drawing.Graphics]::FromImage($tile)
        $tg.SmoothingMode = 'AntiAlias'
        $tg.PixelOffsetMode = 'HighQuality'

        # The dawn ground, as the launcher icon has it, so the frames read the
        # way the filled mark actually looks.
        $rect = New-Object System.Drawing.Rectangle(0, 0, $cell, $cell)
        $ground = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect, (Argb 255 32 30 66), (Argb 255 220 118 78), 60.0)
        $tg.FillRectangle($ground, $rect)
        $ground.Dispose()

        Draw-Mark -g $tg -size $cell `
            -sunT (Stage $t $v.sun[0] $v.sun[1]) `
            -tickT (Stage $t $v.ticks[0] $v.ticks[1]) `
            -handT (Stage $t $v.hand[0] $v.hand[1]) `
            -staggerTicks $v.stagger

        $sg.DrawImage($tile, ($pad + $cell * $f), $pad)
        $tg.Dispose(); $tile.Dispose()

        $pct = [int]($t * 100)
        $numFont = New-Object System.Drawing.Font('Segoe UI', 9)
        $numBrush = New-Object System.Drawing.SolidBrush((Argb 255 138 134 152))
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = 'Center'
        $numRect = New-Object System.Drawing.RectangleF(($pad + $cell * $f), ($pad + $cell + 4), $cell, 18)
        $sg.DrawString("$pct%", $numFont, $numBrush, $numRect, $fmt)
    }

    $capFont = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $capBrush = New-Object System.Drawing.SolidBrush((Argb 255 232 230 240))
    $sg.DrawString($v.label, $capFont, $capBrush, [float]$pad, [float]($pad + $cell + 20))

    $path = Join-Path $outDir "anim_$name.png"
    $sheet.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $sg.Dispose(); $sheet.Dispose()
    Write-Output "wrote $path"
}
