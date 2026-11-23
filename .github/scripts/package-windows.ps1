# Packages a Ladybird Windows build tree into a portable .zip.
#
# On Windows, `cmake --install` neither ships the vcpkg DLLs nor the Qt plugins, and it moves the
# helper processes to libexec\ while the build tree keeps them next to ladybird.exe. So this packages
# the build tree layout (bin\ + share\), which is the one `ladybird.py run` uses, and adds:
#   - the DLLs vcpkg built (Qt, Skia, ICU, ...)
#   - the Qt plugins (platforms\qwindows.dll, styles, image formats, ...)
#   - the MSVC runtime, so it runs without the Visual C++ Redistributable
#   - Mozilla's CA bundle (cacert.pem), which the patched RequestServer trusts next to the Windows store
#   - the license of Ladybird and of every bundled third-party library (Qt and FFmpeg are LGPL)
# It also marks every executable as a Windows GUI application, so that the browser and its helper
# processes run without console windows.

param(
    [Parameter(Mandatory)] [string] $BuildDir,
    [Parameter(Mandatory)] [string] $SourceDir,
    [Parameter(Mandatory)] [string] $OutDir,
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $CaBundle,
    [string] $Version = '',
    [string] $UpstreamSha = '',
    [string] $Repository = ''
)

$ErrorActionPreference = 'Stop'

$staging = Join-Path $OutDir $Name
$bin = Join-Path $staging 'bin'
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force $bin | Out-Null

# 1. The browser, its helper processes and the Ladybird libraries.
$buildBin = Join-Path $BuildDir 'bin'
Get-ChildItem $buildBin -File | Where-Object { $_.Extension -in '.exe', '.dll' } |
    Copy-Item -Destination $bin

# Helper processes, in case a future layout moves them to libexec\. Windows looks up DLLs next to
# the executable, so they go to bin\ with everything else.
$buildLibexec = Join-Path $BuildDir 'libexec'
if (Test-Path $buildLibexec) {
    Get-ChildItem $buildLibexec -File -Filter '*.exe' | Copy-Item -Destination $bin -Force
}

# 2. Resources (fonts, icons, themes, internal pages, PDF.js).
foreach ($dir in 'share') {
    $src = Join-Path $BuildDir $dir
    if (Test-Path $src) { Copy-Item -Recurse $src (Join-Path $staging $dir) }
}

# 3. The vcpkg DLLs. Release ones only: the debug tree lives under debug\bin.
$vcpkgInstalled = Join-Path $BuildDir 'vcpkg_installed'
$qwindows = Get-ChildItem $vcpkgInstalled -Recurse -Filter 'qwindows.dll' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]debug[\\/]' } | Select-Object -First 1
if (-not $qwindows) { throw "Qt's qwindows.dll was not found under $vcpkgInstalled" }

$pluginsDir = $qwindows.Directory.Parent.FullName                 # ...\<triplet>\Qt6\plugins
$tripletDir = $qwindows.Directory.Parent.Parent.Parent.FullName   # ...\<triplet>
Write-Host "vcpkg triplet directory: $tripletDir"
Write-Host "Qt plugins directory:    $pluginsDir"

Get-ChildItem (Join-Path $tripletDir 'bin') -File -Filter '*.dll' | ForEach-Object {
    $dest = Join-Path $bin $_.Name
    if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest }
}

# 4. Qt plugins. Qt searches <application dir>\<plugin type>\ without any qt.conf.
foreach ($type in 'platforms', 'styles', 'imageformats', 'iconengines', 'tls', 'networkinformation', 'position', 'generic') {
    $src = Join-Path $pluginsDir $type
    if (Test-Path $src) {
        $dest = Join-Path $bin $type
        New-Item -ItemType Directory -Force $dest | Out-Null
        Get-ChildItem $src -File -Filter '*.dll' | Copy-Item -Destination $dest
    }
}

# 5. The MSVC runtime (app-local deployment), from the Visual Studio environment set by msvc-dev-cmd.
if ($env:VCToolsRedistDir) {
    $crt = Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
        Select-Object -First 1
    if ($crt) {
        Get-ChildItem $crt.FullName -File -Filter '*.dll' | ForEach-Object {
            $dest = Join-Path $bin $_.Name
            if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest }
        }
    }
} else {
    Write-Warning 'VCToolsRedistDir is not set; the MSVC runtime is not bundled'
}

# 6. Mozilla's CA bundle, next to RequestServer.exe, where the patched RequestServer looks for it.
Copy-Item $CaBundle (Join-Path $bin 'cacert.pem')

# 7. No console windows. Upstream links the browser and its helpers as console programs, so the browser
#    opens a console that closes it when closed. Marking them as GUI programs changes only the subsystem
#    field of the PE header; upstream does the same for its other GUI targets (WIN32_EXECUTABLE with
#    /ENTRY:mainCRTStartup), so the entry point stays main().
function Get-PeSubsystem([string] $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    # PE signature (4 bytes), COFF header (20 bytes), then the Subsystem field at offset 68 of the optional header.
    return [BitConverter]::ToUInt16($bytes, $peOffset + 4 + 20 + 68)
}
foreach ($exe in Get-ChildItem $bin -File -Filter '*.exe') {
    & editbin /nologo /SUBSYSTEM:WINDOWS $exe.FullName
    if ($LASTEXITCODE -ne 0) { throw "editbin failed on $($exe.Name) with exit code $LASTEXITCODE" }
    $subsystem = Get-PeSubsystem $exe.FullName
    if ($subsystem -ne 2) { throw "$($exe.Name) still has PE subsystem $subsystem, not 2 (Windows GUI)" }
    Write-Host "$($exe.Name): Windows GUI subsystem"
}

# 8. Refuse to publish a package that cannot start.
$required = 'Ladybird.exe', 'WebContent.exe', 'RequestServer.exe', 'platforms\qwindows.dll', 'cacert.pem'
$missing = $required | Where-Object { -not (Test-Path (Join-Path $bin $_)) }
if ($missing) {
    Write-Host 'Package contents:'
    Get-ChildItem -Recurse $staging | ForEach-Object { $_.FullName.Substring($staging.Length) }
    throw "Missing from the package: $($missing -join ', ')"
}

# 9. Licenses: Ladybird's own, and the copyright file vcpkg installs for each library it built.
$licenses = Join-Path $staging 'licenses'
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item (Join-Path $SourceDir 'LICENSE') (Join-Path $licenses 'Ladybird.txt')
$ports = @()
Get-ChildItem (Join-Path $tripletDir 'share') -Directory | ForEach-Object {
    $copyright = Join-Path $_.FullName 'copyright'
    if (Test-Path $copyright) {
        Copy-Item $copyright (Join-Path $licenses "$($_.Name).txt")
        $ports += $_.Name
    }
}
@"
This package bundles third-party libraries built with vcpkg from the manifest (vcpkg.json) and the overlay
ports (Meta/CMake/vcpkg/overlay-ports) of Ladybird at commit ${UpstreamSha}:
https://github.com/LadybirdBrowser/ladybird/tree/$UpstreamSha

Each file in this folder is the license of one of them. Some, such as Qt and FFmpeg, are licensed under the
GNU Lesser General Public License. They are linked dynamically (the .dll files in bin\), so you may replace
them with your own builds. Their source code is available from the upstream projects at the versions that
manifest pins, and on request from the publisher of this package: https://github.com/$Repository/issues

Bundled libraries: $($ports -join ', ')

bin\cacert.pem is Mozilla's list of trusted root certificates, as extracted by the curl project
(https://curl.se/docs/caextract.html). It is licensed under the Mozilla Public License 2.0
(https://www.mozilla.org/MPL/2.0/).
"@ | Set-Content -Encoding utf8 (Join-Path $licenses 'README.txt')

$caDate = (Select-String -Path $CaBundle -Pattern '^## Certificate data from Mozilla as of: (.+)$' |
    Select-Object -First 1).Matches.Groups[1].Value

$kind = if ($Version) { "Ladybird $Version alpha" } else { 'Ladybird nightly' }
@"
$kind for Windows x86_64 - UNOFFICIAL BUILD

This is not an official Ladybird release. It is not made, endorsed or supported by the Ladybird Browser
Initiative. Ladybird does not support Windows yet; report Windows-specific problems to the publisher below.

Date:      $(Get-Date -AsUTC -Format 'yyyy-MM-dd')
Commit:    https://github.com/LadybirdBrowser/ladybird/commit/$UpstreamSha
Patches:   https://github.com/$Repository/tree/$(if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { 'main' })/patches
CA bundle: Mozilla root certificates as of $caDate
Built by:  https://github.com/$Repository

Run bin\Ladybird.exe
"@ | Set-Content -Encoding utf8 (Join-Path $staging 'README.txt')

Write-Host 'Package contents (top level of bin\):'
Get-ChildItem $bin | Select-Object Name, Length | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# 10. Zip it, with the versioned folder at the top.
$zip = Join-Path $OutDir "$Name.zip"
if (Test-Path $zip) { Remove-Item $zip }
Push-Location $OutDir
try {
    & 7z a -tzip -mx=7 $zip $Name | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
Get-Item $zip | Select-Object FullName, @{ n = 'SizeMB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-List | Out-String | Write-Host
