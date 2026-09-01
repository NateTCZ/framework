param(
	[string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $repositoryRoot $OutputDirectory
$modelPath = Join-Path $outputPath "Framework.rbxm"
$xmlPath = Join-Path $outputPath "Framework.rbxmx"

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
Push-Location $repositoryRoot
try {
	rojo build model.project.json --output $modelPath
	rojo build model.project.json --output $xmlPath
} finally {
	Pop-Location
}

Write-Host "Built $modelPath"
Write-Host "Built $xmlPath"
