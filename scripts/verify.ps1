$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repositoryRoot
try {
	stylua --check src examples
	selene src examples
	& (Join-Path $PSScriptRoot "build.ps1")

	$binary = Join-Path $repositoryRoot "dist/Framework.rbxm"
	$xml = Join-Path $repositoryRoot "dist/Framework.rbxmx"
	if ((Get-Item $binary).Length -lt 1000) { throw "Framework.rbxm is unexpectedly small." }
	$xmlText = Get-Content -Raw -LiteralPath $xml
	foreach ($required in @("Server", "Client", "Endpoint", "GoodSignal", "Vendor")) {
		if (-not $xmlText.Contains($required)) { throw "Framework.rbxmx is missing $required." }
	}
	Write-Host "Static checks and model-content verification passed."
} finally {
	Pop-Location
}
