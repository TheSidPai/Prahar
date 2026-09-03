# Generates a strip of candidate launcher icons for review, without touching
# the installed icon. Each candidate is a distinct visual idea; the point is
# not to compare tiny variations but to see the range and pick a direction.
#
# Once one is chosen, its render function is lifted into make_icon.ps1 and
# committed as the real icon. This script never writes to android/.
#
#   tools\make_logos.ps1
#   -> build\logo-candidates.png   (all six side by side, labelled)
#   -> build\logo-<name>.png       (each on its own, 512x512)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project 'build'
New-Item -ItemType Directory -Force $out | Out-Null

# --- helpers ------------------------------------------------------------

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
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, $c1, $c2, [float]$angle)
    $g.FillRectangle($br, $rect)
    $br.Dispose()
}

# --- six candidates -----------------------------------------------------

# Each returns a bitmap; keep them small (name matches the file / label).

function Logo-Frame([int]$s) {
    # The current icon: rotated hollow square + amber dot. Kept as one of the
    # options so the comparison is honest.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s (Argb 255 41 46 96) (Argb 255 88 74 176) 55
    $edge = New-Object System.Drawing.Pen((Argb 28 255 255 255), [float]($s * 0.006))
    $ins = $s * 0.06
    $g.DrawEllipse($edge, [float]$ins, [float]$ins, [float]($s - 2 * $ins), [float]($s - 2 * $ins))
    $g.TranslateTransform([float]($s / 2), [float]($s / 2))
    $g.RotateTransform(30.0)
    $side = $s * 0.42
    $stroke = $s * 0.075
    $pen = New-Object System.Drawing.Pen((Argb 255 245 244 252), [float]$stroke)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawRectangle($pen, [float](-$side / 2), [float](-$side / 2), [float]$side, [float]$side)
    $ax = [float]($side / 2); $ay = [float](-$side / 2); $ar = $s * 0.075
    $accent = New-Object System.Drawing.SolidBrush((Argb 255 250 176 116))
    $g.FillEllipse($accent, [float]($ax - $ar), [float]($ay - $ar), [float]($ar * 2), [float]($ar * 2))
    $g.ResetTransform()
    $g.Dispose(); $edge.Dispose(); $pen.Dispose(); $accent.Dispose()
    return $h.bmp
}

function Logo-Wordmark([int]$s) {
    # Monogram: a solid rounded-corner tile with a bold "P" cut from it. Feels
    # like a serious tool; least "app-store" of the six.
    $h = New-Bmp $s; $g = $h.g
    $g.Clear([System.Drawing.Color]::FromArgb(255, 24, 25, 32))

    $ins = $s * 0.10
    $tileRect = New-Object System.Drawing.RectangleF(
        [float]$ins, [float]$ins, [float]($s - 2 * $ins), [float]($s - 2 * $ins))

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = $s * 0.14
    $path.AddArc([float]$tileRect.Left, [float]$tileRect.Top, [float]($r * 2), [float]($r * 2), 180.0, 90.0)
    $path.AddArc([float]($tileRect.Right - $r * 2), [float]$tileRect.Top, [float]($r * 2), [float]($r * 2), 270.0, 90.0)
    $path.AddArc([float]($tileRect.Right - $r * 2), [float]($tileRect.Bottom - $r * 2), [float]($r * 2), [float]($r * 2), 0.0, 90.0)
    $path.AddArc([float]$tileRect.Left, [float]($tileRect.Bottom - $r * 2), [float]($r * 2), [float]($r * 2), 90.0, 90.0)
    $path.CloseFigure()

    $tile = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $tileRect, (Argb 255 108 92 231), (Argb 255 71 62 168), 65.0)
    $g.FillPath($tile, $path)
    $tile.Dispose(); $path.Dispose()

    $family = New-Object System.Drawing.FontFamily 'Segoe UI'
    $font = New-Object System.Drawing.Font($family, [float]($s * 0.58),
        [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $tf = New-Object System.Drawing.StringFormat
    $tf.Alignment = [System.Drawing.StringAlignment]::Center
    $tf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $ink = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $textRect = New-Object System.Drawing.RectangleF(0, [float]($s * 0.05), [float]$s, [float]$s)
    $g.DrawString('P', $font, $ink, $textRect, $tf)
    $font.Dispose(); $family.Dispose(); $tf.Dispose(); $ink.Dispose()

    $g.Dispose()
    return $h.bmp
}

function Logo-Sunrise([int]$s) {
    # A rising sun over a horizon. "A division of the day" made literal, and
    # a warm dawn palette that avoids the every-scheduler-app blue-purple.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s (Argb 255 25 28 40) (Argb 255 60 47 90) 55

    # Sun
    $sunR = $s * 0.20
    $sunX = $s * 0.50 - $sunR
    $sunY = $s * 0.45 - $sunR
    $sun = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.RectangleF([float]$sunX, [float]$sunY, [float]($sunR * 2), [float]($sunR * 2))),
        (Argb 255 255 214 149), (Argb 255 246 148 96), 90.0)
    $g.FillEllipse($sun, [float]$sunX, [float]$sunY, [float]($sunR * 2), [float]($sunR * 2))
    $sun.Dispose()

    # Three horizon rays: single hairline, plus two shorter ones. Off-centred
    # so it does not read as a plain sunrise clipart.
    $rayPen = New-Object System.Drawing.Pen((Argb 220 255 234 200), [float]($s * 0.024))
    $rayPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $rayPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $ys = @(0.72, 0.80, 0.88)
    $margins = @(0.14, 0.24, 0.34)
    for ($i = 0; $i -lt 3; $i++) {
        $y = $s * $ys[$i]
        $l = $s * $margins[$i]
        $rayPen.Width = [float]($s * (0.030 - $i * 0.006))
        $g.DrawLine($rayPen, [float]$l, [float]$y, [float]($s - $l), [float]$y)
    }
    $rayPen.Dispose()
    $g.Dispose()
    return $h.bmp
}

function Logo-Arcs([int]$s) {
    # Three concentric arc segments — quarters of a day. Bolder, more graphic,
    # and reads as an information display.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s (Argb 255 34 34 54) (Argb 255 66 55 122) 55

    $cx = $s * 0.50; $cy = $s * 0.52
    $rings = @(
        @{ r = 0.36; start = 200.0; sweep = 200.0; c = (Argb 255 245 244 252); w = 0.055 },
        @{ r = 0.27; start = 240.0; sweep = 160.0; c = (Argb 255 250 176 116); w = 0.050 },
        @{ r = 0.18; start = 270.0; sweep = 110.0; c = (Argb 255 149 197 255); w = 0.045 }
    )
    foreach ($r in $rings) {
        $pen = New-Object System.Drawing.Pen($r.c, [float]($s * $r.w))
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $rad = $s * $r.r
        $g.DrawArc($pen, [float]($cx - $rad), [float]($cy - $rad), [float]($rad * 2), [float]($rad * 2), [float]$r.start, [float]$r.sweep)
        $pen.Dispose()
    }
    $g.Dispose()
    return $h.bmp
}

function Logo-Grid([int]$s) {
    # A 3x3 grid of squares with one filled — an abstract week/plan schematic.
    # The most functional-looking of the six.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s (Argb 255 18 20 30) (Argb 255 48 50 82) 65

    $ins = $s * 0.24
    $cell = ($s - 2 * $ins) / 3.0
    $gap = $cell * 0.14
    $sq = $cell - $gap

    $stroke = New-Object System.Drawing.Pen((Argb 200 245 244 252), [float]($s * 0.020))
    $fill = New-Object System.Drawing.SolidBrush((Argb 255 250 176 116))
    for ($r = 0; $r -lt 3; $r++) {
        for ($c = 0; $c -lt 3; $c++) {
            $x = $ins + $c * $cell + $gap / 2
            $y = $ins + $r * $cell + $gap / 2
            if ($r -eq 1 -and $c -eq 1) {
                $g.FillRectangle($fill, [float]$x, [float]$y, [float]$sq, [float]$sq)
            } else {
                $g.DrawRectangle($stroke, [float]$x, [float]$y, [float]$sq, [float]$sq)
            }
        }
    }
    $stroke.Dispose(); $fill.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Bookmark([int]$s) {
    # A bookmark tab. Reads as "study" more directly than any other option;
    # risk is that it feels too on-the-nose.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s (Argb 255 22 26 44) (Argb 255 60 74 138) 55

    $w = $s * 0.36
    $x = ($s - $w) / 2
    $top = $s * 0.16
    $bot = $s * 0.86
    $notch = $s * 0.12

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddLine([float]$x, [float]$top, [float]($x + $w), [float]$top)
    $path.AddLine([float]($x + $w), [float]$top, [float]($x + $w), [float]$bot)
    $path.AddLine([float]($x + $w), [float]$bot, [float]($x + $w / 2), [float]($bot - $notch))
    $path.AddLine([float]($x + $w / 2), [float]($bot - $notch), [float]$x, [float]$bot)
    $path.CloseFigure()

    $bmBr = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.RectangleF([float]$x, [float]$top, [float]$w, [float]($bot - $top))),
        (Argb 255 250 244 236), (Argb 255 224 214 199), 90.0)
    $g.FillPath($bmBr, $path)
    $bmBr.Dispose(); $path.Dispose()

    # An amber ribbon across the middle.
    $rb = New-Object System.Drawing.SolidBrush((Argb 255 246 148 96))
    $rbY = $s * 0.45
    $rbH = $s * 0.07
    $g.FillRectangle($rb, [float]$x, [float]$rbY, [float]$w, [float]$rbH)
    $rb.Dispose()

    $g.Dispose()
    return $h.bmp
}

# --- render each candidate ---------------------------------------------

$candidates = @(
    @{ name = 'frame'; label = 'A. Frame (current)'; fn = { param($s) Logo-Frame $s } },
    @{ name = 'wordmark'; label = 'B. Wordmark'; fn = { param($s) Logo-Wordmark $s } },
    @{ name = 'sunrise'; label = 'C. Sunrise'; fn = { param($s) Logo-Sunrise $s } },
    @{ name = 'arcs'; label = 'D. Arcs'; fn = { param($s) Logo-Arcs $s } },
    @{ name = 'grid'; label = 'E. Grid'; fn = { param($s) Logo-Grid $s } },
    @{ name = 'bookmark'; label = 'F. Bookmark'; fn = { param($s) Logo-Bookmark $s } }
)

$size = 512
foreach ($c in $candidates) {
    $bmp = & $c.fn $size
    $out2 = Join-Path $out ("logo-{0}.png" -f $c.name)
    $bmp.Save($out2, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("  logo-{0,-10}  {1,5:N0} KB" -f $c.name, ((Get-Item $out2).Length / 1KB))
    $bmp.Dispose()
}

# --- composite sheet ---------------------------------------------------

$tile = 256
$pad = 24
$cols = 3
$rows = [Math]::Ceiling($candidates.Count / $cols)
$labelH = 36
$w = $cols * $tile + ($cols + 1) * $pad
$h = $rows * ($tile + $labelH) + ($rows + 1) * $pad

$sheet = New-Object System.Drawing.Bitmap($w, $h)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.Clear([System.Drawing.Color]::FromArgb(255, 245, 246, 250))

$family = New-Object System.Drawing.FontFamily 'Segoe UI'
$labelFont = New-Object System.Drawing.Font($family, 14.0, [System.Drawing.FontStyle]::Regular)
$labelBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 40, 42, 60))

for ($i = 0; $i -lt $candidates.Count; $i++) {
    $c = $candidates[$i]
    $col = $i % $cols
    $row = [Math]::Floor($i / $cols)
    $x = $pad + $col * ($tile + $pad)
    $y = $pad + $row * ($tile + $labelH + $pad)

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

$sheetPath = Join-Path $out 'logo-candidates.png'
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

Write-Output ''
Write-Output "  sheet: $sheetPath"
Write-Output 'DONE'
