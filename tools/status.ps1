# Read-only status probe for the Prahar toolchain and project.
#
# Takes no arguments so the invocation string is byte-identical every run and
# can be allow-listed once. Add checks here rather than writing new one-off
# commands — that is the whole point of this file.
#
#   & "<project>\tools\status.ps1"

$ProgressPreference = 'SilentlyContinue'

# Derived, not hardcoded: this file lives in <project>\tools.
$Project = Split-Path -Parent $PSScriptRoot
$Sdk = "$env:LOCALAPPDATA\Android\Sdk"

function Show-Row {
    param([string]$Label, [bool]$Ok, [string]$Detail = '')
    $mark = if ($Ok) { 'yes' } else { ' NO' }
    Write-Output ("  [{0}] {1,-16} {2}" -f $mark, $Label, $Detail)
}

Write-Output '=== toolchain ==='

$flutterBat = 'C:\src\flutter\bin\flutter.bat'
if (-not (Test-Path $flutterBat)) {
    $onPath = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($onPath) { $flutterBat = $onPath.Source }
}
$hasFlutter = Test-Path $flutterBat
$ver = ''
if ($hasFlutter) {
    $root = Split-Path -Parent (Split-Path -Parent $flutterBat)
    # 3.47 dropped the legacy plain-text "version" file (the
    # omit-legacy-version-file feature flag); read the JSON it replaced it with,
    # keeping the old path as a fallback for older installs.
    $json = Join-Path $root 'bin\cache\flutter.version.json'
    $legacy = Join-Path $root 'version'
    if (Test-Path $json) {
        try { $ver = (Get-Content $json -Raw | ConvertFrom-Json).frameworkVersion } catch { }
    }
    if (-not $ver -and (Test-Path $legacy)) {
        $ver = (Get-Content $legacy | Select-Object -First 1)
    }
}
Show-Row 'flutter' $hasFlutter "$ver  $flutterBat"

$jdk17 = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue
Show-Row 'jdk 17' ([bool]$jdk17) $(if ($jdk17) { $jdk17[0].Name } else { 'needed by the Android Gradle plugin' })

Show-Row 'android studio' (Test-Path 'C:\Program Files\Android\Android Studio\bin\studio64.exe')

Write-Output ''
Write-Output '=== android sdk components ==='
Show-Row 'sdk root' (Test-Path $Sdk) $Sdk
Show-Row 'cmdline-tools' (Test-Path "$Sdk\cmdline-tools\latest\bin\sdkmanager.bat")
Show-Row 'platform-tools' (Test-Path "$Sdk\platform-tools\adb.exe")
Show-Row 'platforms 36' (Test-Path "$Sdk\platforms\android-36")
Show-Row 'build-tools 36' (Test-Path "$Sdk\build-tools\36.0.0")

Write-Output ''
Write-Output '=== project ==='
Show-Row 'pubspec' (Test-Path "$Project\pubspec.yaml")
Show-Row 'deps fetched' (Test-Path "$Project\.dart_tool\package_config.json")
Show-Row 'android/' (Test-Path "$Project\android\app\build.gradle.kts")
Show-Row 'CLAUDE.md' (Test-Path "$Project\CLAUDE.md")

$gradle = "$Project\android\app\build.gradle.kts"
if (Test-Path $gradle) {
    $g = Get-Content $gradle -Raw
    Show-Row 'desugaring' ($g -match 'isCoreLibraryDesugaringEnabled\s*=\s*true') 'required by flutter_local_notifications'
}
$mf = "$Project\android\app\src\main\AndroidManifest.xml"
if (Test-Path $mf) {
    $m = Get-Content $mf -Raw
    Show-Row 'exact alarms' ($m -match 'SCHEDULE_EXACT_ALARM')
    Show-Row 'boot receiver' ($m -match 'ScheduledNotificationBootReceiver')
}

$dartFiles = Get-ChildItem "$Project\lib" -Recurse -Filter '*.dart' -ErrorAction SilentlyContinue
$testFiles = Get-ChildItem "$Project\test" -Filter '*_test.dart' -ErrorAction SilentlyContinue
Write-Output ("       {0} dart files in lib/, {1} test files" -f $dartFiles.Count, $testFiles.Count)

Write-Output ''
Write-Output '=== devices ==='
$adb = "$Sdk\platform-tools\adb.exe"
if (Test-Path $adb) {
    $devices = & $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_.Trim() }
    if ($devices) { $devices | ForEach-Object { Write-Output "  $_" } }
    else { Write-Output '  no device attached (enable USB debugging and plug the phone in)' }
} else {
    Write-Output '  adb not installed yet'
}

Write-Output ''
Write-Output '=== recent background tasks ==='
# Auto-discovered: session ids change every run, so never hardcode one.
$taskRoot = "$env:LOCALAPPDATA\Temp\claude"
if (Test-Path $taskRoot) {
    $outs = Get-ChildItem $taskRoot -Recurse -Filter '*.output' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-6) } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 5
    if ($outs) {
        foreach ($o in $outs) {
            $tail = (Get-Content $o.FullName -Tail 1 -ErrorAction SilentlyContinue)
            Write-Output ("  {0:HH:mm:ss} {1,-12} {2}" -f $o.LastWriteTime, $o.BaseName, $tail)
        }
    } else { Write-Output '  (none in the last 6 hours)' }
} else { Write-Output '  (no task directory)' }
