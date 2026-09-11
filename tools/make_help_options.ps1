# Renders candidate icons for the help button on Today's top bar.
#
# Same method as make_nav_options.ps1: a decision about how something looks is
# made by seeing the options side by side, at the size they are used, on the
# colours they sit on. The button lives in a bar that is near-black in dark mode
# and near-white in light, and a glyph that reads well on one can look thin or
# heavy on the other, so every candidate is drawn on both.
#
# Glyphs come from the Material font Flutter itself ships, with codepoints read
# from the file beside it, so what is drawn here is what the app would draw.
#
#   tools\make_help_options.ps1
#   -> build\help_icon.png

Add-Type -AssemblyName System.Drawing

$fontDir  = 'C:\src\flutter\bin\cache\artifacts\material_fonts'
$fontFile = Join-Path $fontDir 'materialicons-regular.otf'
$outDir   = Join-Path (Split-Path -Parent $PSScriptRoot) 'build'

if (-not (Test-Path $fontFile)) { Write-Output "font not found: $fontFile"; exit 1 }
New-Item -ItemType Directory -Force $outDir | Out-Null

$codes = @{}
Get-Content (Join-Path $fontDir 'codepoints') | ForEach-Object {
    $parts = $_ -split '\s+'
    if ($parts.Count -ge 2) { $codes[$parts[0]] = $parts[1] }
}

$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($fontFile)
$iconFamily = $fonts.Families[0]

$names = @(
    'help_outline',
    'help_outline_rounded',
    'question_mark_rounded',
    'info_outline_rounded',
    'live_help_outlined',
    'lightbulb_outline_rounded',
    'tips_and_updates_outlined'
)

# The two grounds the button sits on, and the quiet secondary ink it is drawn
# in. Approximations of the theme's surface and onSurfaceVariant: close enough
# to judge weight and shape, which is the question here.
$themes = @(
    @{ bg = [System.Drawing.Color]::FromArgb(255, 16, 18, 22);    ink = [System.Drawing.Color]::FromArgb(255, 196, 193, 206); muted = [System.Drawing.Color]::FromArgb(255, 120, 116, 134) },
    @{ bg = [System.Drawing.Color]::FromArgb(255, 250, 249, 252); ink = [System.Drawing.Color]::FromArgb(255, 72, 69, 84);    muted = [System.Drawing.Color]::FromArgb(255, 140, 136, 150) }
)

$cell   = 170
$pad    = 24
$labelH = 40
$rowH   = 26 + 96 + 44 + $labelH

$w = $pad * 2 + $cell * $names.Count
$h = $pad * 2 + $rowH * $themes.Count

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAliasGridFit'

$labelFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$numFont   = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$big       = New-Object System.Drawing.Font($iconFamily, 62, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$small     = New-Object System.Drawing.Font($iconFamily, 24, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = 'Center'
$fmt.LineAlignment = 'Center'

for ($t = 0; $t -lt $themes.Count; $t++) {
    $theme = $themes[$t]
    $top = $pad + $rowH * $t

    # Each band runs to the image edge, so the two themes read as two strips.
    $bandTop = if ($t -eq 0) { 0 } else { $top }
    $bandBottom = if ($t -eq $themes.Count - 1) { $h } else { $top + $rowH }
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($theme.bg)), 0, $bandTop, $w, ($bandBottom - $bandTop))

    $brush = New-Object System.Drawing.SolidBrush($theme.ink)
    $mutedBrush = New-Object System.Drawing.SolidBrush($theme.muted)

    for ($i = 0; $i -lt $names.Count; $i++) {
        $name = $names[$i]
        $x = $pad + $cell * $i

        if (-not $codes.ContainsKey($name)) {
            Write-Output "missing codepoint: $name"
            $g.DrawString("missing", $labelFont, $mutedBrush, (New-Object System.Drawing.RectangleF($x, ($top + 60), $cell, 40)), $fmt)
            continue
        }
        $glyph = [char]::ConvertFromUtf32([Convert]::ToInt32($codes[$name], 16))

        $g.DrawString("$($i + 1)", $numFont, $mutedBrush, (New-Object System.Drawing.RectangleF($x, $top, $cell, 26)), $fmt)
        $g.DrawString($glyph, $big, $brush, (New-Object System.Drawing.RectangleF($x, ($top + 26), $cell, 96)), $fmt)
        $g.DrawString($glyph, $small, $brush, (New-Object System.Drawing.RectangleF($x, ($top + 122), $cell, 44)), $fmt)
        $g.DrawString(($name -replace '_outlined$', ''), $labelFont, $mutedBrush, (New-Object System.Drawing.RectangleF($x, ($top + 166), $cell, $labelH)), $fmt)
    }
}

$path = Join-Path $outDir 'help_icon.png'
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "wrote $path"
