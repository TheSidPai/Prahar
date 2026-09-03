# Single entry point for every Flutter/Gradle action in this project.
#
# Exists so there is ONE command shape to grant permission for, instead of a
# new ad-hoc invocation each time. Add tasks here rather than running flutter
# directly.
#
#   tools\dev.ps1 setup       scaffold android/ from a throwaway flutter create
#   tools\dev.ps1 androidsdk  install the Android SDK headlessly
#   tools\dev.ps1 gradledist  pre-fetch the Gradle distribution with curl
#   tools\dev.ps1 pubget      flutter pub get
#   tools\dev.ps1 test        full test suite
#   tools\dev.ps1 test <name> single test by name substring
#   tools\dev.ps1 analyze     static analysis (REQUIRED: tests do not compile lib/ui)
#   tools\dev.ps1 format      dart format lib test
#   tools\dev.ps1 doctor      flutter doctor -v
#   tools\dev.ps1 devices     connected devices
#   tools\dev.ps1 run         build + install onto the connected phone
#   tools\dev.ps1 apk         release APK

param(
    [Parameter(Position = 0)][string]$Task = 'help',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Derived, not hardcoded, so the project can be renamed or moved without
# every task in here breaking.
$Project = Split-Path -Parent $PSScriptRoot

# Prefer the known install, fall back to whatever is on PATH.
$FlutterBin = 'C:\src\flutter\bin'
if (-not (Test-Path (Join-Path $FlutterBin 'flutter.bat'))) {
    $onPath = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($onPath) { $FlutterBin = Split-Path -Parent $onPath.Source }
}
$Flutter = Join-Path $FlutterBin 'flutter.bat'
$Dart = Join-Path $FlutterBin 'dart.bat'

if (-not (Test-Path $Flutter)) {
    Write-Output "flutter not found (looked in $FlutterBin and on PATH)"
    exit 1
}
$env:Path = "$env:Path;$FlutterBin"

# Gradle needs a JDK the Android plugin supports; the system default here is
# JDK 25, which it does not.
$jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue |
       Select-Object -First 1
if ($jdk) { $env:JAVA_HOME = $jdk.FullName }

Set-Location $Project

switch ($Task.ToLower()) {

    'setup' {
        # Generate platform scaffolding in a throwaway directory so nothing
        # templated can clobber the hand-written lib/, test/ or pubspec.yaml.
        $staging = Join-Path $env:TEMP 'prahar_scaffold'
        if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
        New-Item -ItemType Directory -Force $staging | Out-Null

        Write-Output '=== flutter create (staging) ==='
        & $Flutter create --project-name prahar --org com.siddhantpai `
            --platforms=android --no-pub (Join-Path $staging 'prahar')
        if ($LASTEXITCODE -ne 0) { Write-Output "create failed: $LASTEXITCODE"; exit 1 }

        $src = Join-Path $staging 'prahar'
        Copy-Item (Join-Path $src 'android') $Project -Recurse -Force
        foreach ($f in @('.metadata', 'analysis_options.yaml', '.gitignore')) {
            $p = Join-Path $src $f
            if (Test-Path $p) { Copy-Item $p $Project -Force }
        }
        Write-Output 'copied android/ + metadata into project'
        Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue

        Write-Output '=== flutter pub get ==='
        & $Flutter pub get
        exit $LASTEXITCODE
    }

    'androidsdk' {
        # Installs the Android SDK headlessly via sdkmanager, so nobody has to
        # click through Android Studio's first-run wizard. Flutter 3.47 wants
        # compileSdk 36 (FlutterExtension.kt).
        $sdk = "$env:LOCALAPPDATA\Android\Sdk"
        $cmdlineRoot = Join-Path $sdk 'cmdline-tools'
        $latest = Join-Path $cmdlineRoot 'latest'
        $sdkmanager = Join-Path $latest 'bin\sdkmanager.bat'

        if (-not (Test-Path $sdkmanager)) {
            Write-Output '=== locating command-line tools ==='
            $repo = 'https://dl.google.com/android/repository/'
            [xml]$xml = (Invoke-WebRequest -Uri "${repo}repository2-1.xml" -UseBasicParsing).Content

            # Select by the build number embedded in the filename. Document
            # order is NOT version order — trusting it picked a 2020 build.
            $best = $null
            $bestBuild = -1
            foreach ($u in $xml.GetElementsByTagName('url')) {
                $name = $u.'#text'
                if ($name -match '^commandlinetools-win-(\d+)_latest\.zip$') {
                    $build = [int]$Matches[1]
                    if ($build -gt $bestBuild) { $bestBuild = $build; $best = $name }
                }
            }
            if (-not $best) { Write-Output 'could not find cmdline-tools'; exit 1 }
            Write-Output "package: $best (build $bestBuild)"

            New-Item -ItemType Directory -Force $cmdlineRoot | Out-Null
            $zip = Join-Path $env:TEMP 'android-cmdline-tools.zip'
            & curl.exe -L --fail --retry 5 --retry-delay 5 -s -S -o $zip "$repo$best"
            if ($LASTEXITCODE -ne 0) { Write-Output "download failed: $LASTEXITCODE"; exit 1 }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $staging = Join-Path $env:TEMP 'android-cmdline-staging'
            if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $staging)

            # Modern archives unpack to "cmdline-tools", older ones to "tools".
            # Take whatever single directory came out rather than guessing.
            $root = Get-ChildItem $staging -Directory | Select-Object -First 1
            if (-not $root) { Write-Output 'archive had no directory in it'; exit 1 }
            if (Test-Path $latest) { Remove-Item -Recurse -Force $latest }
            Move-Item $root.FullName $latest
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

            if (-not (Test-Path $sdkmanager)) {
                Write-Output "sdkmanager still missing at $sdkmanager"
                Get-ChildItem $latest | ForEach-Object { Write-Output "  $($_.Name)" }
                exit 1
            }
            Write-Output 'cmdline-tools installed'
        }

        Write-Output '=== installing SDK packages ==='
        # Package ids contain ';', which cmd.exe treats as an argument
        # separator when PowerShell hands a .bat its arguments — the quotes
        # PowerShell strips are exactly the ones cmd needs. Building the command
        # line and letting cmd parse it keeps each id intact.
        # Flutter 3.47 wants compileSdk 36 (FlutterExtension.kt).
        $pkgs = @('platform-tools', 'platforms;android-36', 'build-tools;36.0.0')
        $quoted = ($pkgs | ForEach-Object { "`"$_`"" }) -join ' '
        $line = "`"$sdkmanager`" --sdk_root=`"$sdk`" $quoted"
        Write-Output "> $line"
        & cmd.exe /c $line
        $sdkExit = $LASTEXITCODE

        # Trust the filesystem, not the exit code, in both directions:
        # sdkmanager reports success when it silently skips a package, and the
        # new Android CLI wrapper it delegates to can crash on exit
        # (0xC0000409) *after* installing everything correctly.
        $missing = @()
        foreach ($p in @('platform-tools', 'platforms\android-36', 'build-tools\36.0.0')) {
            if (-not (Test-Path (Join-Path $sdk $p))) { $missing += $p }
        }
        if ($missing.Count -gt 0) {
            Write-Output "MISSING after install: $($missing -join ', ')  (sdkmanager exit $sdkExit)"
            exit 1
        }
        if ($sdkExit -ne 0) {
            Write-Output "note: sdkmanager exited $sdkExit but every package is present - continuing"
        }
        Write-Output 'all SDK packages present'

        & $Flutter config --android-sdk $sdk
        & $Flutter doctor
        exit $LASTEXITCODE
    }

    'gradledist' {
        # Pre-seed the Gradle wrapper's distribution zip using curl.
        #
        # The wrapper downloads with java.net.HttpURLConnection: no resume, no
        # retry, and it gives up on a slow link, which is exactly how the first
        # `apk` build failed here. curl resumes and retries, so fetch the zip
        # ourselves and drop it where the wrapper expects to find it; the
        # wrapper then unpacks it without touching the network.
        $props = Get-Content "$Project\android\gradle\wrapper\gradle-wrapper.properties" -Raw
        if ($props -notmatch 'distributionUrl\s*=\s*(\S+)') {
            Write-Output 'could not read distributionUrl'; exit 1
        }
        $url = $Matches[1].Trim().Replace('\:', ':')
        $zipName = ($url -split '/')[-1]
        $distName = $zipName -replace '\.zip$', ''
        Write-Output "distribution: $url"

        $dists = "$env:USERPROFILE\.gradle\wrapper\dists\$distName"
        # Prefer the directory the wrapper already made; its name is an MD5 of
        # the URL rendered in base 36, so reproducing it is fiddly and only
        # needed on a machine that has never attempted the download.
        $target = $null
        if (Test-Path $dists) {
            $existing = Get-ChildItem $dists -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($existing) { $target = $existing.FullName }
        }
        if (-not $target) {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $digest = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($url))
            [array]::Reverse($digest)                  # .NET BigInteger is little-endian
            $bi = [System.Numerics.BigInteger]::new($digest + [byte]0)   # force positive
            $chars = '0123456789abcdefghijklmnopqrstuvwxyz'
            $hash = ''
            while ($bi -gt 0) {
                $hash = $chars[[int]($bi % 36)] + $hash
                $bi = [System.Numerics.BigInteger]::Divide($bi, 36)
            }
            $target = Join-Path $dists $hash
            Write-Output "computed cache dir: $hash"
        }
        New-Item -ItemType Directory -Force $target | Out-Null
        Write-Output "cache dir: $target"

        $zip = Join-Path $target $zipName
        if ((Test-Path $zip) -and (Get-Item $zip).Length -gt 50MB) {
            Write-Output 'distribution already present'
        } else {
            # Clear the wrapper's abandoned lock and partial file.
            Get-ChildItem $target -Filter '*.part' | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem $target -Filter '*.lck'  | Remove-Item -Force -ErrorAction SilentlyContinue

            Write-Output 'downloading with curl...'
            & curl.exe -L --fail --retry 10 --retry-delay 5 --retry-all-errors -C - -s -S -o $zip $url
            if ($LASTEXITCODE -ne 0) { Write-Output "download failed: $LASTEXITCODE"; exit 1 }
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        try {
            $t = [System.IO.Compression.ZipFile]::OpenRead($zip)
            $n = $t.Entries.Count
            $t.Dispose()
            Write-Output ("ok: {0:N0} MB, $n entries" -f ((Get-Item $zip).Length / 1MB))
        } catch {
            Write-Output "archive corrupt, deleting so it can be refetched: $_"
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            exit 1
        }
        exit 0
    }

    'sdkpkg' {
        # Install arbitrary SDK packages, e.g.
        #   tools\dev.ps1 sdkpkg "ndk;28.2.13676358"
        # Quote the id at the call site too: an unquoted ';' ends the statement
        # in PowerShell before the script ever sees it.
        if (-not $Rest) { Write-Output 'usage: sdkpkg "<package;id>" [...]'; exit 1 }
        $sdk = "$env:LOCALAPPDATA\Android\Sdk"
        $sdkmanager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
        if (-not (Test-Path $sdkmanager)) { Write-Output 'run androidsdk first'; exit 1 }

        $quoted = ($Rest | ForEach-Object { "`"$_`"" }) -join ' '
        $line = "`"$sdkmanager`" --sdk_root=`"$sdk`" $quoted"
        Write-Output "> $line"
        & cmd.exe /c $line
        Write-Output "sdkmanager exit: $LASTEXITCODE (ignored - it crashes after succeeding)"
        Write-Output 'sdk now contains:'
        foreach ($d in @('platform-tools', 'platforms', 'build-tools', 'ndk')) {
            $p = Join-Path $sdk $d
            if (Test-Path $p) {
                $kids = (Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', '
                Write-Output "  $d : $kids"
            }
        }
        exit 0
    }

    'pubget'  { & $Flutter pub get; exit $LASTEXITCODE }

    'test' {
        if ($Rest) { & $Flutter test --plain-name ($Rest -join ' ') }
        else       { & $Flutter test }
        exit $LASTEXITCODE
    }

    'analyze' { & $Flutter analyze; exit $LASTEXITCODE }
    'format'  { & $Dart format lib test; exit $LASTEXITCODE }
    'doctor'  { & $Flutter doctor -v; exit $LASTEXITCODE }
    'devices' {
        # adb is the ground truth; `flutter devices` only reports what adb
        # already authorised, so a phone missing from both needs adb's own
        # verdict to tell cable/driver problems from an unaccepted prompt.
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        if (Test-Path $adb) {
            Write-Output '=== adb devices ==='
            & $adb start-server 2>&1 | Out-Null
            $raw = & $adb devices -l
            $raw | ForEach-Object { Write-Output "  $_" }

            $rows = $raw | Select-Object -Skip 1 | Where-Object { $_.Trim() }
            if (-not $rows) {
                Write-Output ''
                Write-Output 'No device seen by adb at all. Check, in order:'
                Write-Output '  1. Settings > About phone > tap Build number 7x  (enables Developer options)'
                Write-Output '  2. Settings > Developer options > USB debugging  = ON'
                Write-Output '  3. The cable carries data, not just power - a charge-only cable shows nothing'
                Write-Output '  4. On the phone, set the USB mode to File transfer / MTP rather than Charging only'
            } elseif ($rows -match 'unauthorized') {
                Write-Output ''
                Write-Output 'Device seen but UNAUTHORIZED: unlock the phone and accept the'
                Write-Output '"Allow USB debugging?" prompt (tick "Always allow from this computer").'
            } elseif ($rows -match 'offline') {
                Write-Output ''
                Write-Output 'Device is offline: unplug, replug, and accept the prompt.'
            }
        } else {
            Write-Output 'adb not installed - run: tools\dev.ps1 androidsdk'
        }

        Write-Output ''
        Write-Output '=== flutter devices ==='
        & $Flutter devices
        exit 0
    }
    'install' {
        # Install the already-built release APK and launch it, then exit.
        # `flutter run` stays attached to the process until you press q, which
        # is wrong for a scripted install; this returns control immediately.
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        $apk = "$Project\build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path $apk)) { Write-Output 'no APK - run: tools\dev.ps1 apk'; exit 1 }

        Write-Output ("installing {0:N1} MB..." -f ((Get-Item $apk).Length / 1MB))
        & $adb install -r $apk
        if ($LASTEXITCODE -ne 0) { Write-Output "install failed: $LASTEXITCODE"; exit 1 }

        & $adb shell am start -n 'com.siddhantpai.prahar/.MainActivity'
        Write-Output 'launched'
        exit 0
    }

    'logs' {
        # Flutter's own log output from the running app. Ctrl+C to stop.
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        & $adb logcat -v brief -s flutter:V ActivityManager:I AndroidRuntime:E
        exit 0
    }

    'launch' {
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        & $adb shell am start -n 'com.siddhantpai.prahar/.MainActivity'
        exit 0
    }

    'screenshot' {
        # Pull the current screen. Faster than asking what the app is showing,
        # and it captures notifications in the shade too.
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        $out = Join-Path $Project 'build\screen.png'
        New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
        if (Test-Path $out) { Remove-Item $out -Force }

        # Capture on the device and pull the file. Do NOT use
        # `adb exec-out screencap -p > file`: PowerShell's redirection is not
        # byte-transparent — it prepends a UTF-8 BOM and mangles bytes into
        # replacement characters, producing a corrupt PNG.
        & $adb shell screencap -p /sdcard/prahar-screen.png
        & $adb pull /sdcard/prahar-screen.png $out 2>&1 | Out-Null
        & $adb shell rm -f /sdcard/prahar-screen.png

        if ((Test-Path $out) -and (Get-Item $out).Length -gt 1000) {
            Write-Output ("saved $out ({0:N0} KB)" -f ((Get-Item $out).Length / 1KB))
        } else {
            Write-Output 'screencap failed'
            exit 1
        }
        exit 0
    }

    'check' {
        # Non-blocking runtime health check: is it alive, did it crash, what do
        # its logs say. `logs` tails forever; this returns.
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        $pkg = 'com.siddhantpai.prahar'

        Write-Output '=== process ==='
        $procPid = (& $adb shell pidof $pkg 2>$null)
        if ($procPid) { Write-Output "  running, pid $procPid" }
        else { Write-Output '  NOT RUNNING (crashed, or not launched)' }

        Write-Output ''
        Write-Output '=== installed version ==='
        & $adb shell "dumpsys package $pkg | grep -E 'versionName|firstInstallTime|lastUpdateTime'" 2>$null

        Write-Output ''
        Write-Output '=== granted permissions ==='
        & $adb shell "dumpsys package $pkg | grep -E 'POST_NOTIFICATIONS|SCHEDULE_EXACT_ALARM|RECEIVE_BOOT'" 2>$null

        Write-Output ''
        Write-Output '=== recent log (flutter + crashes) ==='
        & $adb logcat -d -v brief -t 120 -s flutter:V AndroidRuntime:E DartVM:V 2>$null
        exit 0
    }

    'exempt' {
        # Add/remove the battery-optimisation exemption over adb, to test
        # whether Doze is what stops background alarms being delivered before
        # committing to an in-app permission prompt for it.
        #   tools\dev.ps1 exempt        grant
        #   tools\dev.ps1 exempt off    revoke
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        $pkg = 'com.siddhantpai.prahar'
        $sign = if ($Rest -and $Rest[0] -eq 'off') { '-' } else { '+' }
        & $adb shell "dumpsys deviceidle whitelist $sign$pkg"
        Write-Output ''
        $wl = & $adb shell 'dumpsys deviceidle whitelist' 2>$null | Select-String -Pattern 'siddhantpai'
        Write-Output ("  now: " + $(if ($wl) { "EXEMPT  $wl" } else { 'not exempt' }))
        exit 0
    }

    'notif' {
        # Channel settings as the OS holds them. Importance, sound and audio
        # attributes freeze at channel creation, so code is not the truth here.
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        $pkg = 'com.siddhantpai.prahar'

        Write-Output '=== our notification channels ==='
        # Regexes here deliberately avoid the quote character: a single quote
        # inside a double-quoted PowerShell string, and nested quoting in an
        # adb shell argument, both derail the parser.
        $raw = & $adb shell 'dumpsys notification --noredact | grep prahar_sessions' 2>$null
        $seen = @{}
        foreach ($line in $raw) {
            if ($line -match 'mId=.([a-z0-9_]+)') {
                $id = $Matches[1]
                if ($seen.ContainsKey($id)) { continue }
                $seen[$id] = $true
                $imp = '?'; $use = '?'
                if ($line -match 'mImportance=(\d+)') { $imp = $Matches[1] }
                if ($line -match 'usage=([A-Z_]+)') { $use = $Matches[1] }
                Write-Output "  $id  importance=$imp (4=HIGH)  audio=$use"
            }
        }
        if ($seen.Count -eq 0) { Write-Output '  none yet (a notification must be POSTED to create its channel)' }

        Write-Output ''
        Write-Output '=== why a background alarm may not be delivered ==='
        Write-Output '  -- standby bucket (10=ACTIVE 20=WORKING 30=FREQUENT 40=RARE 45=RESTRICTED)'
        $b = & $adb shell "am get-standby-bucket $pkg" 2>$null
        Write-Output "     $b"

        Write-Output '  -- battery optimisation exemption (whitelisted = can run in background)'
        $wl = & $adb shell "dumpsys deviceidle whitelist" 2>$null | Select-String -Pattern 'siddhantpai'
        Write-Output ("     " + $(if ($wl) { "EXEMPT: $wl" } else { 'NOT exempt - Android may freeze it' }))

        Write-Output '  -- MIUI/HyperOS background restriction (RUN_ANY_IN_BACKGROUND)'
        $ops = & $adb shell "appops get $pkg RUN_ANY_IN_BACKGROUND" 2>$null
        Write-Output ("     " + $(if ($ops) { $ops } else { 'not set' }))

        Write-Output '  -- is the process alive right now?'
        $procPid = & $adb shell "pidof $pkg" 2>$null
        Write-Output ("     " + $(if ($procPid) { "running (pid $procPid)" } else { 'NOT RUNNING - a broadcast must cold-start it' }))

        Write-Output '  -- MIUI autostart / boot ops (MIUI uses its own ops, not the AOSP ones)'
        $allops = & $adb shell "appops get $pkg" 2>$null
        $interesting = $allops | Select-String -Pattern 'AUTO_START|BOOT|BACKGROUND|WAKE'
        if ($interesting) { $interesting | ForEach-Object { Write-Output "     $_" } }
        else { Write-Output '     none reported' }

        Write-Output ''
        Write-Output '=== audio: is the alarm stream even audible? ==='
        # USAGE_ALARM plays on the alarm stream, so a muted alarm volume makes
        # a correctly-configured notification silent.
        foreach ($k in @('volume_alarm_speaker', 'volume_alarm', 'volume_system')) {
            $v = & $adb shell "settings get system $k" 2>$null
            Write-Output "  $k = $v"
        }
        $ring = & $adb shell 'dumpsys audio | grep -m 2 -i "ringer mode"' 2>$null
        if ($ring) { $ring | ForEach-Object { Write-Output "  $_" } }

        Write-Output ''
        Write-Output '=== do not disturb ==='
        & $adb shell "dumpsys notification --noredact | grep -m 1 mZenMode" 2>$null |
            ForEach-Object { Write-Output "  $_  (ZEN_MODE_OFF = DND is off)" }
        exit 0
    }

    'alarms' {
        # What the OS actually has scheduled for us, and whether it will honour
        # exact timing. The real test of the notification layer.
        $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
        # Raw `dumpsys alarm` output is enormous. Pull out just our own pending
        # alarms and their fire times.
        Write-Output '=== pending alarms for com.siddhantpai.prahar ==='
        # origWhen sits on the line AFTER the tag line, so look forward.
        $raw = & $adb shell "dumpsys alarm | grep -A 2 'siddhantpai.*ScheduledNotificationReceiver'" 2>$null
        $times = @()
        $exact = 0
        foreach ($l in $raw) {
            if ($l -match 'origWhen=(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $times += $Matches[1] }
            if ($l -match 'exactAllowReason=permission') { $exact++ }
        }
        $times = $times | Sort-Object -Unique
        if ($times) {
            foreach ($t in $times) { Write-Output "  $t" }
            Write-Output ''
            Write-Output "  $($times.Count) pending, $exact confirmed exact (window=0)"
        } else {
            Write-Output '  none scheduled (add a subject and topic in the app first)'
        }
        Write-Output ''
        Write-Output '=== exact alarm permission (an appop, not a normal grant) ==='
        & $adb shell "appops get com.siddhantpai.prahar SCHEDULE_EXACT_ALARM" 2>$null

        Write-Output ''
        Write-Output '=== battery optimisation / standby bucket ==='
        Write-Output '  (bucket 10=ACTIVE 20=WORKING_SET 30=FREQUENT 40=RARE 45=RESTRICTED)'
        & $adb shell "dumpsys deviceidle whitelist | grep siddhantpai" 2>$null
        & $adb shell "am get-standby-bucket com.siddhantpai.prahar" 2>$null
        exit 0
    }

    'run'     { & $Flutter run --release; exit $LASTEXITCODE }
    'apk'     { & $Flutter build apk --release; exit $LASTEXITCODE }

    'licenses' {
        # Flutter checks for hash files under <sdk>\licenses. The newer Android
        # CLI claims "--licenses is no longer needed" and writes none, so the
        # acceptance still has to be driven through Flutter's own prompt.
        $yes = ('y' + [Environment]::NewLine) * 100
        $yes | & $Flutter doctor --android-licenses
        Write-Output ''
        $lic = "$env:LOCALAPPDATA\Android\Sdk\licenses"
        if (Test-Path $lic) {
            Write-Output 'licence files now present:'
            Get-ChildItem $lic | ForEach-Object { Write-Output "  $($_.Name)" }
        } else {
            Write-Output "no licence files at $lic"
            exit 1
        }
        exit 0
    }

    default {
        Write-Output 'tasks: setup pubget test analyze format doctor devices run apk licenses'
    }
}
