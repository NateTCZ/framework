$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot

# $ErrorActionPreference does not stop on native tools' exit codes, so check them.
function Invoke-Checked([scriptblock]$Command) {
	& $Command
	if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code ${LASTEXITCODE}: $Command" }
}

Push-Location $repositoryRoot
try {
	Invoke-Checked { stylua --check src examples tests }
	Invoke-Checked { selene src examples }
	Invoke-Checked { lune run tests/run }
	& (Join-Path $PSScriptRoot "build.ps1")

	$binary = Join-Path $repositoryRoot "dist/Framework.rbxm"
	$xml = Join-Path $repositoryRoot "dist/Framework.rbxmx"
	if ((Get-Item $binary).Length -lt 1000) { throw "Framework.rbxm is unexpectedly small." }
	$xmlText = Get-Content -Raw -LiteralPath $xml
	foreach ($required in @("Server", "Client", "Endpoint", "Gate", "Lifecycle", "Property", "GoodSignal", "Vendor")) {
		if (-not $xmlText.Contains($required)) { throw "Framework.rbxmx is missing $required." }
	}
	Write-Host "Static checks, unit tests, and model-content verification passed."
} finally {
	Pop-Location
}
