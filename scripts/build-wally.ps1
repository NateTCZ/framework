$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repositoryRoot "src"
$outputPath = Join-Path $repositoryRoot "build/wally"
$resolvedOutput = [System.IO.Path]::GetFullPath($outputPath)
$resolvedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "build"))

if (-not $resolvedOutput.StartsWith($resolvedBuildRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
	throw "Refusing to clean a Wally output path outside the repository build directory."
}

if (Test-Path -LiteralPath $resolvedOutput) {
	Remove-Item -Recurse -Force -LiteralPath $resolvedOutput
}
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

Copy-Item -Recurse -Force -Path (Join-Path $sourcePath "*") -Destination $resolvedOutput
Copy-Item -Force -LiteralPath (Join-Path $repositoryRoot "wally.project.json") -Destination (Join-Path $resolvedOutput "default.project.json")

$manifest = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot "wally.toml")
$manifest = [regex]::Replace($manifest, '(?ms)^include\s*=\s*\[.*?^\]\s*', '')
$manifest = [regex]::Replace($manifest, '(?ms)^exclude\s*=\s*\[.*?^\]\s*', '')
Set-Content -NoNewline -Encoding utf8 -LiteralPath (Join-Path $resolvedOutput "wally.toml") -Value $manifest

Write-Host "Built clean Wally package at $resolvedOutput"
