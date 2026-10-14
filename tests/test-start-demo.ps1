$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $tempRoot ('guide-launcher-test-' + [Guid]::NewGuid().ToString('N'))
$launcher = Join-Path $fixtureRoot 'scripts\start-demo.ps1'
$runtimeDirectory = Join-Path $fixtureRoot 'outputs\runtime'
$statePath = Join-Path $runtimeDirectory 'demo-process.json'
$configPath = Join-Path $fixtureRoot 'workspace.json'
$checks = 0

function Assert-True([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
    $script:checks++
}

function Assert-Throws([scriptblock] $action, [string] $pattern) {
    $message = $null
    try { & $action | Out-Null } catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message -and $message -match $pattern) "Expected error '$pattern'; received '$message'."
}

function Save-FixtureConfig {
    $script:config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:configPath -Encoding UTF8
}

function Read-Check([string] $model) {
    return ((& $script:launcher -Model $model -Check) -join "`n" | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'scripts'), (Join-Path $fixtureRoot 'repo'), (Join-Path $fixtureRoot 'env with spaces'), (Join-Path $fixtureRoot 'checkpoints') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\start-demo.ps1') -Destination $launcher
    # These placeholders deliberately cannot launch a demo. Preflight must never execute them.
    $pythonPath = Join-Path $fixtureRoot 'env with spaces\python.exe'
    [IO.File]::WriteAllText($pythonPath, 'Not an executable: read-only launcher fixture.')
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'scripts\stub.py'), 'raise RuntimeError("Preflight executed model code")')
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'checkpoints\stub.bin'), 'No model weights needed for preflight.')
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try { $probe.Start(); $port = $probe.LocalEndpoint.Port } finally { $probe.Stop() }
    $config = [ordered]@{ schema_version = 1; models = [ordered]@{} }
    foreach ($name in @('dust3r', 'mast3r', 'vggt', 'cpu-stub')) {
        $config.models[$name] = [ordered]@{
            python = $pythonPath
            script = 'scripts/stub.py'
            repository = 'repo'
            checkpoint = 'checkpoints/stub.bin'
            port = $port
        }
    }
    Save-FixtureConfig

    foreach ($name in @('dust3r', 'mast3r', 'vggt', 'cpu-stub')) {
        $report = Read-Check $name
        Assert-True ($report.model -ceq $name -and $report.port_available -eq $true) "Preflight failed for $name."
        Assert-True ($report.configured_models.Count -eq 4 -and $report.python -eq $pythonPath -and $report.url -eq "http://127.0.0.1:$port/") "Resolved configuration is wrong for $name."
    }
    Assert-True (-not (Test-Path -LiteralPath $runtimeDirectory)) 'Preflight created runtime files.'
    $defaultReport = ((& $launcher -Check) -join "`n" | ConvertFrom-Json)
    Assert-True ($defaultReport.model -ceq 'dust3r') 'The default model changed.'
    Assert-Throws { & $launcher -Model unconfigured -NoBrowser } 'Configured models: cpu-stub, dust3r, mast3r, vggt'
    Assert-True (-not (Test-Path -LiteralPath $runtimeDirectory)) 'Unknown model created runtime files.'

    # A real, unrelated PowerShell PID proves validation cannot act on stored process ownership.
    New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
    [ordered]@{ pid = $PID; model = 'fixture'; python = 'sentinel-not-python.exe'; script = 'sentinel-not-a-demo.py' } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    $originalStateHash = (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
    Assert-Throws { & $launcher -Model unconfigured -NoBrowser } 'Model is not configured yet'
    Assert-Throws { & $launcher -Model '../bad' -Check } 'Model must be a lowercase name'
    $report = Read-Check 'VGGT'
    Assert-True ($report.model -ceq 'vggt') 'Case-insensitive model selection changed.'
    Assert-Throws { & $launcher -Stop -Check } 'Choose either -Check or -Stop'
    $report = Read-Check 'cpu-stub'
    Assert-True ($report.model -ceq 'cpu-stub') 'Fourth configured model was not accepted with a managed state present.'

    $occupied = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
    try {
        $occupied.Start()
        $report = Read-Check 'cpu-stub'
        Assert-True ($report.port_available -eq $false) 'Preflight did not report an occupied port.'
    } finally { $occupied.Stop() }

    # Windows PowerShell Join-Path cannot combine an absolute child correctly: shared assets need an explicit rooted-path branch.
    $sharedRoot = Join-Path $fixtureRoot 'shared assets'
    $sharedRepo = Join-Path $sharedRoot 'repository'
    $sharedScript = Join-Path $sharedRoot 'demo script.py'
    $sharedWeights = Join-Path $sharedRoot 'model weights.bin'
    New-Item -ItemType Directory -Path $sharedRepo -Force | Out-Null
    [IO.File]::WriteAllText($sharedScript, 'raise RuntimeError("Preflight executed shared model code")')
    [IO.File]::WriteAllText($sharedWeights, 'Existing shared weights must not be copied or changed.')
    $originalWeightsHash = (Get-FileHash -LiteralPath $sharedWeights -Algorithm SHA256).Hash
    $config.models['cpu-stub'].script = $sharedScript
    $config.models['cpu-stub'].repository = $sharedRepo
    $config.models['cpu-stub'].checkpoint = $sharedWeights
    Save-FixtureConfig
    $report = Read-Check 'cpu-stub'
    Assert-True ($report.script -eq $sharedScript -and $report.repository -eq $sharedRepo -and $report.weights -eq $sharedWeights) 'Absolute shared asset paths with spaces resolved incorrectly.'
    Assert-True ((Get-FileHash -LiteralPath $sharedWeights -Algorithm SHA256).Hash -eq $originalWeightsHash) 'Preflight modified shared weights.'
    $config.models['cpu-stub'].python = 'env with spaces/python.exe'
    Save-FixtureConfig
    $report = Read-Check 'cpu-stub'
    Assert-True ($report.python -eq $pythonPath) 'Relative Python path was not resolved from the workspace root.'

    $config.models['cpu-stub'].port = 65536
    Save-FixtureConfig
    Assert-Throws { & $launcher -Model cpu-stub -NoBrowser } 'integer port between 1 and 65535'
    $config.models['cpu-stub'].port = '7860'
    Save-FixtureConfig
    Assert-Throws { & $launcher -Model cpu-stub -Check } 'integer port between 1 and 65535'
    $config.models['cpu-stub'].port = $port
    $config.models['cpu-stub'].checkpoint = 'checkpoints/missing.bin'
    Save-FixtureConfig
    Assert-Throws { & $launcher -Model cpu-stub -NoBrowser } 'Required file missing'
    $config.models['cpu-stub'].checkpoint = ''
    Save-FixtureConfig
    Assert-Throws { & $launcher -Model cpu-stub -Check } 'requires a non-empty checkpoint path'
    Assert-True ((Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -eq $originalStateHash) 'Validation changed the managed process state.'
    Assert-True ($null -ne (Get-Process -Id $PID -ErrorAction SilentlyContinue)) 'Validation stopped the unrelated process.'
    Write-Output "Launcher preflight passed: $checks assertions; no demo/model code launched, no managed service changed."
} finally {
    # Delete only this test's uniquely named fixture inside the resolved system temporary directory.
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $tempBoundary = $tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolvedFixture) -notmatch '^guide-launcher-test-[0-9a-f]{32}$') {
        throw "Refusing to clean up an unexpected fixture path: $resolvedFixture"
    }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
