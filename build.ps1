# Build the pk3s.
#
#   .\build.ps1              RS_WeaponWheel.pk3
#   .\build.ps1 -Dev         and RS_WeaponWheel_dev.pk3 (the "Rig Test" pawn)
#   .\build.ps1 -Deploy D:\Doom   copy what was built there afterwards
#
# NO ZIPDIR. The instructions used to be "run zipdir from the GZDoom source
# tree", which makes building this mod depend on having built the engine --
# and zipdir's whole job here is a zip with the package folder's CONTENTS at
# the archive root. zipdir still works fine if you would rather use it.
#
# Entries are added ONE AT A TIME rather than by CreateFromDirectory, which
# would be the obvious call and writes "sounds\wr_open.ogg" on Windows
# PowerShell -- .NET Framework's version of it uses the platform separator,
# and the zip format specifies forward slashes. GZDoom happens to normalise
# them on read, so this looks like it works; SLADE and the other pk3 tools
# are not obliged to.
#
# Writes to the repo root, never into a package folder. A zip written inside
# RS_WeaponWheel\ is picked up as content by the NEXT build and packed into
# it -- a stale copy of the whole mod, inside the mod. That happened.

[CmdletBinding()]
param(
    [switch] $Dev,
    [string] $Deploy
)

$ErrorActionPreference = 'Stop'
# Both: ZipArchive/ZipArchiveMode live in the first, ZipFile and the
# CreateEntryFromFile extension in the second.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot

function Build-Package {
    param([string] $Name)

    $src = Join-Path $root $Name
    $out = Join-Path $root "$Name.pk3"

    if (-not (Test-Path $src)) { throw "No such package folder: $src" }

    # Refuse rather than silently shipping it. An archive in here is either
    # last build's output or someone's backup; both get packed as content.
    $stray = Get-ChildItem $src -Recurse -Include *.zip, *.pk3
    if ($stray) {
        throw "Archive inside the package folder, would be packed into the build:`n  " +
              (($stray | ForEach-Object { $_.FullName }) -join "`n  ")
    }

    if (Test-Path $out) { Remove-Item $out }

    $prefix = (Resolve-Path $src).Path.TrimEnd('\') + '\'
    $zip = [System.IO.Compression.ZipFile]::Open(
        $out, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $src -Recurse -File | Sort-Object FullName) {
            $entry = $f.FullName.Substring($prefix.Length).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $f.FullName, $entry,
                [System.IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally { $zip.Dispose() }

    $kb = [math]::Round((Get-Item $out).Length / 1KB)
    Write-Host ("  {0,-28} {1,6} KB" -f "$Name.pk3", $kb)
    return $out
}

Write-Host "Building:"
$built = @(Build-Package 'RS_WeaponWheel')
if ($Dev) { $built += Build-Package 'RS_WeaponWheel_dev' }

if ($Deploy) {
    if (-not (Test-Path $Deploy)) { throw "No such deploy folder: $Deploy" }
    Write-Host "Copying to $Deploy"
    $built | ForEach-Object { Copy-Item $_ $Deploy -Force }
}
