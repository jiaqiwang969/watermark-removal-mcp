#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GitHubRepo = if ($env:WATERMARK_MCP_GITHUB_REPO) { $env:WATERMARK_MCP_GITHUB_REPO } else { "jiaqiwang969/watermark-removal-mcp" }
$Version = if ($env:WATERMARK_MCP_VERSION) { $env:WATERMARK_MCP_VERSION } else { "latest" }
$BinName = "watermark-remover-mcp-server.exe"
$LocalBinPath = Join-Path $RepoDir "target/release/$BinName"

if ($env:LOCALAPPDATA) {
    $CacheBase = if ($env:WATERMARK_MCP_CACHE_DIR) { $env:WATERMARK_MCP_CACHE_DIR } else { Join-Path $env:LOCALAPPDATA "watermark-removal-mcp" }
} else {
    $CacheBase = if ($env:WATERMARK_MCP_CACHE_DIR) { $env:WATERMARK_MCP_CACHE_DIR } else { Join-Path $env:USERPROFILE "AppData/Local/watermark-removal-mcp" }
}

function Get-TargetTriple {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch.ToString()) {
        "X64" { return "x86_64-pc-windows-msvc" }
        default { throw "Unsupported Windows architecture: $arch" }
    }
}

function Get-DownloadUrl([string] $Target) {
    $asset = "watermark-remover-mcp-$Target.zip"
    if ($Version -eq "latest") {
        return "https://github.com/$GitHubRepo/releases/latest/download/$asset"
    }
    $normalized = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
    return "https://github.com/$GitHubRepo/releases/download/$normalized/$asset"
}

function Install-PrebuiltIfMissing([string] $Target) {
    $installDir = Join-Path $CacheBase "$Version/$Target"
    $binPath = Join-Path $installDir "bin/$BinName"
    if (Test-Path $binPath) {
        return $binPath
    }

    $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("watermark-mcp-" + [System.Guid]::NewGuid().ToString("N"))
    $archivePath = Join-Path $tmpRoot "bundle.zip"
    New-Item -ItemType Directory -Path $tmpRoot | Out-Null
    try {
        $url = Get-DownloadUrl -Target $Target
        Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing

        $unpackDir = Join-Path $tmpRoot "unpack"
        Expand-Archive -Path $archivePath -DestinationPath $unpackDir -Force
        $payloadDir = Get-ChildItem -Path $unpackDir -Directory | Select-Object -First 1
        if (-not $payloadDir) {
            throw "Downloaded archive missing payload directory."
        }

        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Copy-Item -Path (Join-Path $payloadDir.FullName "*") -Destination $installDir -Recurse -Force
        if (-not (Test-Path $binPath)) {
            throw "Downloaded binary missing: $binPath"
        }
        return $binPath
    } finally {
        Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($env:WATERMARK_MCP_AUTO_UPDATE -eq "1" -and (Get-Command git -ErrorAction SilentlyContinue)) {
    try {
        git -C $RepoDir pull --ff-only | Out-Null
    } catch {
        # Ignore update failures to avoid blocking MCP startup.
    }
}

$Target = Get-TargetTriple
$BinPath = $null

try {
    $BinPath = Install-PrebuiltIfMissing -Target $Target
} catch {
    if (Test-Path $LocalBinPath) {
        $BinPath = $LocalBinPath
    } elseif ($env:WATERMARK_MCP_ALLOW_BUILD -eq "1") {
        cargo build --release --manifest-path (Join-Path $RepoDir "Cargo.toml")
        $BinPath = $LocalBinPath
    } else {
        throw "Unable to get prebuilt binary for $Target. Set WATERMARK_MCP_ALLOW_BUILD=1 once to build locally."
    }
}

if (-not $env:WATERMARK_SCRIPTS_DIR) {
    $repoScripts = Join-Path $RepoDir "scripts"
    if (Test-Path $repoScripts) {
        $env:WATERMARK_SCRIPTS_DIR = $repoScripts
    } else {
        $cachedScripts = Join-Path (Split-Path -Parent $BinPath) "../scripts"
        if (Test-Path $cachedScripts) {
            $env:WATERMARK_SCRIPTS_DIR = $cachedScripts
        } else {
            throw "Cannot find scripts directory. Set WATERMARK_SCRIPTS_DIR explicitly."
        }
    }
}

& $BinPath
