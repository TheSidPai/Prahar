# Renders candidate navigation icons as one contact sheet per tab.
#
# The same idea as make_logos.ps1 and the icon-thickness ladders: a decision
# about how something looks is made by seeing the options side by side at the
# size they will actually be used, not by reading their names in a list.
#
# Glyphs come from the Material font Flutter itself ships, so what is drawn
# here is exactly what the app would draw. Codepoints are read from the
# `codepoints` file beside the font rather than typed in from memory.
#
#   tools\make_nav_options.ps1
#   -> build\nav_<tab>.png, one row of seven, labelled and numbered

Add-Type -AssemblyName System.Drawing

$fontDir  = 'C:\src\flutter\bin\cache\artifacts\material_fonts'
$fontFile = Join-Path $fontDir 'materialicons-regular.otf'
$outDir   = Join-Path (Split-Path -Parent $PSScriptRoot) 'build'

if (-not (Test-Path $fontFile)) { Write-Output "font not found: $fontFile"; exit 1 }
New-Item -ItemType Directory -Force $outDir | Out-Null

# name -> codepoint, straight from Flutter's own table.
$codes = @{}
Get-Content (Join-Path $fontDir 'codepoints') | ForEach-Object {
    $parts = $_ -split '\s+'
    if ($parts.Count -ge 2) { $codes[$parts[0]] = $parts[1] }
}

$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($fontFile)
$iconFamily = $fonts.Families[0]

# Seven per tab. The first in each row is what the app draws today, so the
# comparison always includes the incumbent.
$sets = [ordered]@{
    'today'    = @('today_outlined','wb_twilight_outlined','wb_sunny_outlined','light_mode_outlined','schedule_outlined','event_available_outlined','brightness_5_outlined')
    'plan'     = @('calendar_month_outlined','calendar_today_outlined','date_range_outlined','event_note_outlined','view_agenda_outlined','view_timeline_outlined','map_outlined')
    'progress' = @('donut_large_outlined','data_usage_outlined','incomplete_circle_outlined','pie_chart_outline_outlined','query_stats_outlined','trending_up_outlined','show_chart_outlined')
    'subjects' = @('library_books_outlined','menu_book_outlined','auto_stories_outlined','book_outlined','topic_outlined','layers_outlined','folder_open_outlined')
    'settings' = @('settings_outlined','tune_outlined','display_settings_outlined','dashboard_customize_outlined','build_outlined','folder_open_outlined','more_horiz_outlined')

    # Progress, gone deeper. The first pass narrowed it to two families and
    # they answer different questions: a ring says "how much of a finite
    # amount is done", a line says "which way is this going". Worth choosing
    # the family before the glyph.
    'progress_rings' = @('data_usage_outlined','donut_small_outlined','timelapse_outlined','track_changes_outlined','data_saver_off_outlined','av_timer_outlined','percent_outlined')
    'progress_lines' = @('trending_up_outlined','moving_outlined','auto_graph_outlined','timeline_outlined','stacked_line_chart_outlined','north_east_outlined','leaderboard_outlined')
}

# Drawn at 96px and again at 24px. 24 is the size a nav icon is actually seen
# at, and glyphs that look elegant large can turn to mush there; 96 is for
# judging the shape.
$cell = 190
$pad  = 28
$labelH = 54

$bg      = [System.Drawing.Color]::FromArgb(255, 16, 18, 22)
$inkSel  = [System.Drawing.Color]::FromArgb(255, 250, 176, 116)
$ink     = [System.Drawing.Color]::FromArgb(255, 232, 230, 240)
$muted   = [System.Drawing.Color]::FromArgb(255, 138, 134, 152)

foreach ($tab in $sets.Keys) {
    $names = $sets[$tab]
    $w = $pad * 2 + $cell * $names.Count
    $h = $pad * 2 + $cell + $labelH

    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear($bg)

    $labelFont = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)
    $numFont   = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $big       = New-Object System.Drawing.Font($iconFamily, 62, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $small     = New-Object System.Drawing.Font($iconFamily, 24, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'
    $fmt.LineAlignment = 'Center'

    for ($i = 0; $i -lt $names.Count; $i++) {
        $name = $names[$i]
        if (-not $codes.ContainsKey($name)) { Write-Output "missing codepoint: $name"; continue }
        $glyph = [char]::ConvertFromUtf32([Convert]::ToInt32($codes[$name], 16))

        $x = $pad + $cell * $i
        $y = $pad

        # The first option is the one in the app now, marked in the accent so
        # it is obvious what is being compared against.
        $brush = New-Object System.Drawing.SolidBrush($(if ($i -eq 0) { $inkSel } else { $ink }))
        $mutedBrush = New-Object System.Drawing.SolidBrush($muted)

        $numRect = New-Object System.Drawing.RectangleF($x, $y, $cell, 26)
        $g.DrawString("$($i + 1)", $numFont, $mutedBrush, $numRect, $fmt)

        $bigRect = New-Object System.Drawing.RectangleF($x, ($y + 26), $cell, 96)
        $g.DrawString($glyph, $big, $brush, $bigRect, $fmt)

        $smallRect = New-Object System.Drawing.RectangleF($x, ($y + 124), $cell, 44)
        $g.DrawString($glyph, $small, $brush, $smallRect, $fmt)

        $short = $name -replace '_outlined$', ''
        $labRect = New-Object System.Drawing.RectangleF($x, ($y + $cell - 6), $cell, $labelH)
        $g.DrawString($short, $labelFont, $mutedBrush, $labRect, $fmt)
    }

    $path = Join-Path $outDir "nav_$tab.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "wrote $path"
}
