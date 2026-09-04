# Ten refined logo candidates: five sunrise variations, five bookmark
# variations. Each is a distinct visual idea rather than a colour tweak, so
# the choice is genuinely between concepts. Each ties to time, study or
# focus in a specific way named next to it.
#
#   tools\make_logos_v2.ps1
#   -> build\logo-v2-<name>.png       (each on its own, 512x512)
#   -> build\logo-v2-sheet.png        (all ten in one image, labelled)
#
# Nothing here writes to android/. The choose-then-lift-into-make_icon.ps1
# flow is unchanged.

$ErrorActionPreference = 'Stop'
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

# Palettes: dawn (warm), night (cool), page (light warm). Each carries a
# semantic tone appropriate to the concept.
$Dawn = @{ top = (Argb 255 32 30 66); bot = (Argb 255 220 118 78) }    # night -> sunrise
$Ink  = @{ ink = (Argb 255 245 244 252); accent = (Argb 255 250 176 116) }
$Night = @{ top = (Argb 255 22 24 42); bot = (Argb 255 62 52 122) }
$Page = @{ top = (Argb 255 246 240 224); bot = (Argb 255 224 210 184) }

# --- SUNRISE variants --------------------------------------------------

function Logo-Sunrise-Refined([int]$s) {
    # "The moment the day begins". Refined arc: half-sun cresting a hairline
    # horizon. Restraint reads as intent -the amber sits against navy alone.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Dawn.top $Dawn.bot 60

    # Half-sun above horizon at 60%.
    $cx = $s * 0.50; $cy = $s * 0.60
    $r = $s * 0.22
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    # Rectangle-clipped pie for a clean semicircle.
    $g.FillPie($sun, [float]($cx - $r), [float]($cy - $r), [float]($r * 2), [float]($r * 2), 180.0, 180.0)
    $sun.Dispose()

    # Horizon: crisp line + fainter one below it.
    $pen = New-Object System.Drawing.Pen((Argb 235 245 244 252), [float]($s * 0.020))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen, [float]($s * 0.14), [float]$cy, [float]($s * 0.86), [float]$cy)
    $pen.Color = (Argb 130 245 244 252)
    $g.DrawLine($pen, [float]($s * 0.24), [float]($cy + $s * 0.08), [float]($s * 0.76), [float]($cy + $s * 0.08))
    $pen.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Sunrise-Book([int]$s) {
    # "Study begins with the day". Sun rising behind an open book -dawn +
    # syllabus. The book's spine is the horizon.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Dawn.top $Dawn.bot 55

    # Rising sun, mostly hidden by the book below it.
    $cx = $s * 0.50; $cy = $s * 0.55
    $r = $s * 0.24
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun, [float]($cx - $r), [float]($cy - $r), [float]($r * 2), [float]($r * 2))
    $sun.Dispose()

    # Book as a triangular open shape from the bottom, two page-triangles
    # meeting at a raised centre -a stylised silhouette rather than literal
    # spine + pages.
    $book = New-Object System.Drawing.Drawing2D.GraphicsPath
    $book.AddPolygon([System.Drawing.PointF[]] @(
        (New-Object System.Drawing.PointF([float]($s * 0.12), [float]($s * 0.78))),
        (New-Object System.Drawing.PointF([float]($s * 0.50), [float]($s * 0.62))),
        (New-Object System.Drawing.PointF([float]($s * 0.88), [float]($s * 0.78))),
        (New-Object System.Drawing.PointF([float]($s * 0.88), [float]($s * 0.86))),
        (New-Object System.Drawing.PointF([float]($s * 0.50), [float]($s * 0.72))),
        (New-Object System.Drawing.PointF([float]($s * 0.12), [float]($s * 0.86)))
    ))
    $bookBr = New-Object System.Drawing.SolidBrush((Argb 255 245 244 252))
    $g.FillPath($bookBr, $book)
    $bookBr.Dispose(); $book.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Sunrise-Scheduled([int]$s) {
    # "A moment scheduled in the day". Sun disc, ring of subtle hour marks,
    # one bold ray pointing at a specific angle -the current block. Fuses
    # sunrise with clock language.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Dawn.top $Dawn.bot 60

    $cx = $s * 0.50; $cy = $s * 0.50

    # Faint ring of 12 tick marks (hours).
    $tickPen = New-Object System.Drawing.Pen((Argb 90 245 244 252), [float]($s * 0.008))
    $rIn = $s * 0.30; $rOut = $s * 0.34
    for ($i = 0; $i -lt 12; $i++) {
        $a = [Math]::PI * 2 * ($i / 12.0) - [Math]::PI / 2
        $x1 = $cx + [Math]::Cos($a) * $rIn
        $y1 = $cy + [Math]::Sin($a) * $rIn
        $x2 = $cx + [Math]::Cos($a) * $rOut
        $y2 = $cy + [Math]::Sin($a) * $rOut
        $g.DrawLine($tickPen, [float]$x1, [float]$y1, [float]$x2, [float]$y2)
    }
    $tickPen.Dispose()

    # Sun disc.
    $sunR = $s * 0.20
    $sun = New-Object System.Drawing.SolidBrush((Argb 255 250 210 148))
    $g.FillEllipse($sun, [float]($cx - $sunR), [float]($cy - $sunR), [float]($sunR * 2), [float]($sunR * 2))
    $sun.Dispose()

    # A single bold amber ray from the sun to the ring -the "scheduled
    # moment". Points at about 2 o'clock.
    $a = [Math]::PI * 2 * (2 / 12.0) - [Math]::PI / 2
    $ray = New-Object System.Drawing.Pen((Argb 255 250 176 116), [float]($s * 0.045))
    $ray.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $ray.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($ray,
        [float]($cx + [Math]::Cos($a) * $sunR),
        [float]($cy + [Math]::Sin($a) * $sunR),
        [float]($cx + [Math]::Cos($a) * $rOut),
        [float]($cy + [Math]::Sin($a) * $rOut))
    $ray.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Sunrise-Crescent([int]$s) {
    # "The instant of focus". Only a crescent of sun peeks from the bottom —
    # very abstract, weighted heavily to negative space. The moment attention
    # lands. Least literal of the five.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Dawn.top $Dawn.bot 65

    # Sun sits mostly below the visible area.
    $cx = $s * 0.50; $cy = $s * 0.98
    $r = $s * 0.36
    $sun = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.RectangleF([float]($cx - $r), [float]($cy - $r), [float]($r * 2), [float]($r * 2))),
        (Argb 255 250 210 148),
        (Argb 255 246 148 96),
        90.0)
    $g.FillEllipse($sun, [float]($cx - $r), [float]($cy - $r), [float]($r * 2), [float]($r * 2))
    $sun.Dispose()

    # A single hairline horizon high in the frame, letting the viewer feel
    # the empty sky.
    $pen = New-Object System.Drawing.Pen((Argb 90 245 244 252), [float]($s * 0.010))
    $g.DrawLine($pen, [float]($s * 0.12), [float]($s * 0.30), [float]($s * 0.88), [float]($s * 0.30))
    $pen.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Sunrise-DayArc([int]$s) {
    # "Now, within the day". The sun's daily path drawn as an arc; a small
    # amber dot marks a specific point -where the student currently is.
    # Combines time (the arc), study (the dot as focus), and focus (its
    # position along the day).
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Night.top $Night.bot 55

    # Horizon line.
    $horizonY = $s * 0.70
    $hz = New-Object System.Drawing.Pen((Argb 140 245 244 252), [float]($s * 0.010))
    $g.DrawLine($hz, [float]($s * 0.10), [float]$horizonY, [float]($s * 0.90), [float]$horizonY)
    $hz.Dispose()

    # Day arc (semicircle) from east horizon to west horizon.
    $arcPen = New-Object System.Drawing.Pen((Argb 235 245 244 252), [float]($s * 0.030))
    $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $cx = $s * 0.50
    $arcR = $s * 0.32
    $g.DrawArc($arcPen, [float]($cx - $arcR), [float]($horizonY - $arcR), [float]($arcR * 2), [float]($arcR * 2), 180.0, 180.0)
    $arcPen.Dispose()

    # Focus dot on the arc at about mid-morning (10 o'clock along the arc).
    $t = 0.35 # 0=east, 1=west
    $a = [Math]::PI + [Math]::PI * $t
    $dx = $cx + [Math]::Cos($a) * $arcR
    $dy = $horizonY + [Math]::Sin($a) * $arcR
    $dotR = $s * 0.055
    $dot = New-Object System.Drawing.SolidBrush((Argb 255 250 176 116))
    $g.FillEllipse($dot, [float]($dx - $dotR), [float]($dy - $dotR), [float]($dotR * 2), [float]($dotR * 2))
    $dot.Dispose(); $g.Dispose()
    return $h.bmp
}

# --- BOOKMARK variants -------------------------------------------------

function Logo-Bookmark-Refined([int]$s) {
    # "A saved place". Cleaner geometry than the current bookmark: cleaner
    # notch, better width, subtle depth via a hairline highlight down its
    # left edge.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Night.top $Night.bot 55

    $w = $s * 0.36
    $x = ($s - $w) / 2
    $top = $s * 0.16
    $bot = $s * 0.86
    $notch = $s * 0.14

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddLine([float]$x, [float]$top, [float]($x + $w), [float]$top)
    $path.AddLine([float]($x + $w), [float]$top, [float]($x + $w), [float]$bot)
    $path.AddLine([float]($x + $w), [float]$bot, [float]($x + $w / 2), [float]($bot - $notch))
    $path.AddLine([float]($x + $w / 2), [float]($bot - $notch), [float]$x, [float]$bot)
    $path.CloseFigure()

    $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.RectangleF([float]$x, [float]$top, [float]$w, [float]($bot - $top))),
        (Argb 255 250 244 236),
        (Argb 255 224 214 199),
        90.0)
    $g.FillPath($fill, $path)
    $fill.Dispose(); $path.Dispose()

    # Amber accent as a horizontal ribbon near the top of the bookmark.
    $ribbon = New-Object System.Drawing.SolidBrush((Argb 255 246 148 96))
    $g.FillRectangle($ribbon, [float]$x, [float]($top + $s * 0.20), [float]$w, [float]($s * 0.045))
    $ribbon.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Bookmark-Corner([int]$s) {
    # "A page turned down". Just the bottom-right corner folded up, the way
    # you dog-ear a book. Read: a page saved for later -a moment marked
    # inside a bigger whole. Very minimal.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Night.top $Night.bot 55

    # A big rounded tile representing "the page".
    $rr = $s * 0.14
    $margin = $s * 0.12
    $rect = New-Object System.Drawing.RectangleF(
        [float]$margin, [float]$margin,
        [float]($s - 2 * $margin), [float]($s - 2 * $margin))
    $tile = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tile.AddArc([float]$rect.Left, [float]$rect.Top, [float]($rr * 2), [float]($rr * 2), 180.0, 90.0)
    $tile.AddArc([float]($rect.Right - $rr * 2), [float]$rect.Top, [float]($rr * 2), [float]($rr * 2), 270.0, 90.0)
    $tile.AddArc([float]($rect.Right - $rr * 2), [float]($rect.Bottom - $rr * 2), [float]($rr * 2), [float]($rr * 2), 0.0, 90.0)
    $tile.AddArc([float]$rect.Left, [float]($rect.Bottom - $rr * 2), [float]($rr * 2), [float]($rr * 2), 90.0, 90.0)
    $tile.CloseFigure()

    $paper = New-Object System.Drawing.SolidBrush((Argb 255 246 240 224))
    $g.FillPath($paper, $tile)
    $paper.Dispose(); $tile.Dispose()

    # The dog-ear: a triangle at the bottom-right, filled with the darker
    # underside colour so it reads as a physical fold.
    $foldSize = $s * 0.24
    $fx = $rect.Right - $foldSize
    $fy = $rect.Bottom - $foldSize

    # Underside -a shadow-toned triangle.
    $under = New-Object System.Drawing.Drawing2D.GraphicsPath
    $under.AddPolygon([System.Drawing.PointF[]] @(
        (New-Object System.Drawing.PointF([float]$fx, [float]$rect.Bottom)),
        (New-Object System.Drawing.PointF([float]$rect.Right, [float]$fy)),
        (New-Object System.Drawing.PointF([float]$rect.Right, [float]$rect.Bottom))
    ))
    $sh = New-Object System.Drawing.SolidBrush((Argb 255 210 195 170))
    $g.FillPath($sh, $under)
    $sh.Dispose(); $under.Dispose()

    # Amber flag on the fold line: the moment saved.
    $accent = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * 0.020))
    $accent.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $accent.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($accent,
        [float]$fx, [float]$rect.Bottom,
        [float]$rect.Right, [float]$fy)
    $accent.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Bookmark-Time([int]$s) {
    # "This block, kept". Bookmark with a subtle circular time marker in
    # place of the ribbon -a scheduled study block as an object you can
    # save. Fuses bookmark language with time.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Night.top $Night.bot 55

    $w = $s * 0.34
    $x = ($s - $w) / 2
    $top = $s * 0.16
    $bot = $s * 0.86
    $notch = $s * 0.14

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddLine([float]$x, [float]$top, [float]($x + $w), [float]$top)
    $path.AddLine([float]($x + $w), [float]$top, [float]($x + $w), [float]$bot)
    $path.AddLine([float]($x + $w), [float]$bot, [float]($x + $w / 2), [float]($bot - $notch))
    $path.AddLine([float]($x + $w / 2), [float]($bot - $notch), [float]$x, [float]$bot)
    $path.CloseFigure()

    $fill = New-Object System.Drawing.SolidBrush((Argb 255 246 240 224))
    $g.FillPath($fill, $path)
    $fill.Dispose(); $path.Dispose()

    # Time disc at the top: a circular block symbol.
    $cx = $x + $w / 2; $cy = $top + $s * 0.16
    $rr = $s * 0.10
    $disc = New-Object System.Drawing.Pen((Argb 255 46 44 84), [float]($s * 0.020))
    $g.DrawEllipse($disc, [float]($cx - $rr), [float]($cy - $rr), [float]($rr * 2), [float]($rr * 2))
    $disc.Dispose()

    # Amber hand pointing "start of the block" -noon.
    $hand = New-Object System.Drawing.Pen((Argb 255 246 148 96), [float]($s * 0.024))
    $hand.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $hand.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($hand, [float]$cx, [float]$cy, [float]$cx, [float]($cy - $rr * 0.7))
    $g.DrawLine($hand, [float]$cx, [float]$cy, [float]($cx + $rr * 0.6), [float]$cy)
    $hand.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Bookmark-Stack([int]$s) {
    # "The syllabus, and where you are in it". Three stacked page cards, the
    # top one bookmarked. Reads as: a body of material with your current
    # place marked. Study + focus, without a literal book.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Night.top $Night.bot 55

    # Three page cards, each offset slightly right and down.
    $w = $s * 0.44
    $hpage = $s * 0.56
    $baseX = ($s - $w) / 2 - $s * 0.06
    $baseY = ($s - $hpage) / 2 - $s * 0.04
    $off = $s * 0.06

    for ($i = 2; $i -ge 0; $i--) {
        $x = $baseX + $i * $off
        $y = $baseY + $i * $off
        $tint = 255 - $i * 20
        $br = New-Object System.Drawing.SolidBrush((Argb 255 $tint $tint 255))
        $rect = New-Object System.Drawing.RectangleF([float]$x, [float]$y, [float]$w, [float]$hpage)
        $g.FillRectangle($br, $rect)
        $br.Dispose()
    }

    # Bookmark ribbon on the topmost card, extending below its bottom edge.
    $topX = $baseX + 2 * $off
    $topY = $baseY + 2 * $off
    $ribbonX = $topX + $w * 0.72
    $ribbonW = $s * 0.075
    $ribbonTop = $topY - $s * 0.03
    $ribbonBot = $topY + $hpage + $s * 0.08
    $notchDepth = $s * 0.05

    $ribbon = New-Object System.Drawing.Drawing2D.GraphicsPath
    $ribbon.AddLine([float]$ribbonX, [float]$ribbonTop, [float]($ribbonX + $ribbonW), [float]$ribbonTop)
    $ribbon.AddLine([float]($ribbonX + $ribbonW), [float]$ribbonTop, [float]($ribbonX + $ribbonW), [float]$ribbonBot)
    $ribbon.AddLine([float]($ribbonX + $ribbonW), [float]$ribbonBot, [float]($ribbonX + $ribbonW / 2), [float]($ribbonBot - $notchDepth))
    $ribbon.AddLine([float]($ribbonX + $ribbonW / 2), [float]($ribbonBot - $notchDepth), [float]$ribbonX, [float]$ribbonBot)
    $ribbon.CloseFigure()

    $rbBr = New-Object System.Drawing.SolidBrush((Argb 255 246 148 96))
    $g.FillPath($rbBr, $ribbon)
    $rbBr.Dispose(); $ribbon.Dispose(); $g.Dispose()
    return $h.bmp
}

function Logo-Bookmark-Book([int]$s) {
    # "In the middle of studying". An open book viewed from above, with a
    # bookmark ribbon inserted between pages. Most literal of the five —
    # if immediate legibility matters, this is the winner.
    $h = New-Bmp $s; $g = $h.g
    Gradient $g $s $Night.top $Night.bot 55

    # Two page halves meeting at a raised spine.
    $bookW = $s * 0.68
    $bookH = $s * 0.48
    $bx = ($s - $bookW) / 2
    $by = ($s - $bookH) / 2 + $s * 0.02
    $spineLift = $s * 0.05

    $left = New-Object System.Drawing.Drawing2D.GraphicsPath
    $left.AddPolygon([System.Drawing.PointF[]] @(
        (New-Object System.Drawing.PointF([float]$bx, [float]$by)),
        (New-Object System.Drawing.PointF([float]($bx + $bookW / 2), [float]($by - $spineLift))),
        (New-Object System.Drawing.PointF([float]($bx + $bookW / 2), [float]($by + $bookH - $spineLift))),
        (New-Object System.Drawing.PointF([float]$bx, [float]($by + $bookH)))
    ))
    $right = New-Object System.Drawing.Drawing2D.GraphicsPath
    $right.AddPolygon([System.Drawing.PointF[]] @(
        (New-Object System.Drawing.PointF([float]($bx + $bookW / 2), [float]($by - $spineLift))),
        (New-Object System.Drawing.PointF([float]($bx + $bookW), [float]$by)),
        (New-Object System.Drawing.PointF([float]($bx + $bookW), [float]($by + $bookH))),
        (New-Object System.Drawing.PointF([float]($bx + $bookW / 2), [float]($by + $bookH - $spineLift)))
    ))

    $pageL = New-Object System.Drawing.SolidBrush((Argb 255 246 240 224))
    $pageR = New-Object System.Drawing.SolidBrush((Argb 255 230 220 200))
    $g.FillPath($pageL, $left); $g.FillPath($pageR, $right)
    $pageL.Dispose(); $pageR.Dispose(); $left.Dispose(); $right.Dispose()

    # Bookmark: a slim amber ribbon between the pages, protruding above and
    # below the book -the classic "keeping my place".
    $ribbonX = $bx + $bookW * 0.62
    $ribbonW = $s * 0.055
    $ribbonTop = $by - $s * 0.10
    $ribbonBot = $by + $bookH + $s * 0.10
    $notchDepth = $s * 0.04

    $rp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rp.AddLine([float]$ribbonX, [float]$ribbonTop, [float]($ribbonX + $ribbonW), [float]$ribbonTop)
    $rp.AddLine([float]($ribbonX + $ribbonW), [float]$ribbonTop, [float]($ribbonX + $ribbonW), [float]$ribbonBot)
    $rp.AddLine([float]($ribbonX + $ribbonW), [float]$ribbonBot, [float]($ribbonX + $ribbonW / 2), [float]($ribbonBot - $notchDepth))
    $rp.AddLine([float]($ribbonX + $ribbonW / 2), [float]($ribbonBot - $notchDepth), [float]$ribbonX, [float]$ribbonBot)
    $rp.CloseFigure()

    $rbBr = New-Object System.Drawing.SolidBrush((Argb 255 246 148 96))
    $g.FillPath($rbBr, $rp)
    $rbBr.Dispose(); $rp.Dispose(); $g.Dispose()
    return $h.bmp
}

# --- render all --------------------------------------------------------

$candidates = @(
    @{ name = 'sunrise-refined'; label = "S1. Sunrise -refined arc`nMoment the day begins"; fn = { param($s) Logo-Sunrise-Refined $s } },
    @{ name = 'sunrise-book'; label = "S2. Sunrise + book`nStudy begins with the day"; fn = { param($s) Logo-Sunrise-Book $s } },
    @{ name = 'sunrise-scheduled'; label = "S3. Sun with hour marks`nA scheduled moment"; fn = { param($s) Logo-Sunrise-Scheduled $s } },
    @{ name = 'sunrise-crescent'; label = "S4. Crescent`nThe instant of focus"; fn = { param($s) Logo-Sunrise-Crescent $s } },
    @{ name = 'sunrise-dayarc'; label = "S5. Day arc + dot`nNow, within the day"; fn = { param($s) Logo-Sunrise-DayArc $s } },
    @{ name = 'bookmark-refined'; label = "B1. Bookmark -refined`nA place saved"; fn = { param($s) Logo-Bookmark-Refined $s } },
    @{ name = 'bookmark-corner'; label = "B2. Corner fold`nA page turned down"; fn = { param($s) Logo-Bookmark-Corner $s } },
    @{ name = 'bookmark-time'; label = "B3. Bookmark + clock`nThis block, kept"; fn = { param($s) Logo-Bookmark-Time $s } },
    @{ name = 'bookmark-stack'; label = "B4. Stacked pages`nWhere you are in the syllabus"; fn = { param($s) Logo-Bookmark-Stack $s } },
    @{ name = 'bookmark-book'; label = "B5. Book with bookmark`nMid-study"; fn = { param($s) Logo-Bookmark-Book $s } }
)

$size = 512
foreach ($c in $candidates) {
    $bmp = & $c.fn $size
    $out2 = Join-Path $out ("logo-v2-{0}.png" -f $c.name)
    $bmp.Save($out2, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("  logo-v2-{0,-20}  {1,5:N0} KB" -f $c.name, ((Get-Item $out2).Length / 1KB))
    $bmp.Dispose()
}

# --- composite sheet ---------------------------------------------------

$tile = 256
$pad = 24
$cols = 5   # 5 sunrise on row 1, 5 bookmark on row 2
$rows = 2
$labelH = 56

$w = $cols * $tile + ($cols + 1) * $pad
$h = $rows * ($tile + $labelH) + ($rows + 1) * $pad

$sheet = New-Object System.Drawing.Bitmap($w, $h)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.Clear([System.Drawing.Color]::FromArgb(255, 245, 246, 250))

$family = New-Object System.Drawing.FontFamily 'Segoe UI'
$labelFont = New-Object System.Drawing.Font($family, 12.0, [System.Drawing.FontStyle]::Regular)
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
    $labelRect = New-Object System.Drawing.RectangleF($x, ($y + $tile + 4), $tile, $labelH)
    $sg.DrawString($c.label, $labelFont, $labelBr, $labelRect, $tf)
    $tf.Dispose()
}

$labelFont.Dispose(); $family.Dispose(); $labelBr.Dispose(); $sg.Dispose()

$sheetPath = Join-Path $out 'logo-v2-sheet.png'
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

Write-Output ''
Write-Output "  sheet: $sheetPath"
Write-Output 'DONE'
