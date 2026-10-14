$ErrorActionPreference = 'Stop'
$generator = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../scripts/configure-workspace.ps1'))
$testParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $testParent ('guide-config-' + [Guid]::NewGuid().ToString('N'))
$global:GuideConfigurationTestCalls = @()
$global:GuideConfigurationTestFail = $false
$global:GuideConfigurationTestPython = Join-Path $testRoot 'python with spaces.exe'
function Invoke-GuideConfigurationTestConda {
    $global:GuideConfigurationTestCalls += [string]$args[2]
    $global:LASTEXITCODE = if ($global:GuideConfigurationTestFail) { 17 } else { 0 }
    if (-not $global:GuideConfigurationTestFail) { Write-Output $global:GuideConfigurationTestPython }
}
function Assert-Configuration([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
}
try {
    New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
    [IO.File]::WriteAllText($global:GuideConfigurationTestPython, 'fixture; never executed')
    $template = Join-Path $testRoot 'template.json'
    $output = Join-Path $testRoot 'workspace.json'
    $models = [ordered]@{}
    foreach ($name in @('dust3r', 'mast3r', 'vggt', 'future-model')) {
        $models[$name] = [ordered]@{ environment = "$name-custom"; script = 'demo.py'; repository = 'source'; checkpoint = 'weights.bin'; port = 7899; checks = @{ cuda = $false; imports = @('json') } }
    }
    $definition = [ordered]@{ schema_version = 1; models = $models; custom_note = 'preserve template fields' }
    [IO.File]::WriteAllText($template, ($definition | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $original = 'original configuration bytes'
    [IO.File]::WriteAllText($output, $original, [Text.UTF8Encoding]::new($false))
    & $generator -Template $template -Output $output -Conda Invoke-GuideConfigurationTestConda | Out-Null
    $generated = Get-Content -LiteralPath $output -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Configuration ($generated.models.PSObject.Properties.Name.Count -eq 4) 'Fourth model not generated'
    Assert-Configuration ($generated.custom_note -eq $definition.custom_note) 'Template fields lost'
    Assert-Configuration ($generated.models.'future-model'.python -eq $global:GuideConfigurationTestPython.Replace('\', '/')) 'Resolved Python path wrong'
    Assert-Configuration ($generated.models.'future-model'.checks.cuda -eq $false) 'Check settings lost'
    Assert-Configuration (($global:GuideConfigurationTestCalls -join ',') -eq 'dust3r-custom,mast3r-custom,vggt-custom,future-model-custom') 'Environment names were hardcoded'
    $bytes = [IO.File]::ReadAllBytes($output)
    Assert-Configuration (-not ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) 'Generated configuration has UTF-8 BOM'
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'outputs/setup') -Filter 'workspace-before-*.json')
    Assert-Configuration ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -eq $original) 'Original configuration backup differs'
    $beforeFailure = [IO.File]::ReadAllText($output)
    $global:GuideConfigurationTestFail = $true
    $caught = $false
    try { & $generator -Template $template -Output $output -Conda Invoke-GuideConfigurationTestConda | Out-Null } catch { $caught = $true }
    Assert-Configuration ($caught -and [IO.File]::ReadAllText($output) -eq $beforeFailure) 'Failed environment lookup overwrote configuration'
    $global:GuideConfigurationTestFail = $false
    $invalidModels = @(
        $null,
        'not an object',
        @{ script = $null; repository = 'source'; checkpoint = 'weights.bin'; port = 7899 },
        @{ script = 'demo.py'; repository = ' '; checkpoint = 'weights.bin'; port = 7899 },
        @{ script = 'demo.py'; repository = 'source'; checkpoint = 42; port = 7899 },
        @{ script = 'demo.py'; repository = 'source'; checkpoint = 'weights.bin'; port = '7899' },
        @{ script = 'demo.py'; repository = 'source'; checkpoint = 'weights.bin'; port = 0 },
        @{ script = 'demo.py'; repository = 'source'; checkpoint = 'weights.bin'; port = 65536 },
        @{ script = 'demo.py'; repository = 'source'; checkpoint = 'weights.bin'; port = 7899; environment = @('env1', 'env2') }
    )
    $beforeInvalidHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    $beforeBackupCount = @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'outputs/setup') -Filter 'workspace-before-*.json').Count
    foreach ($invalidModel in $invalidModels) {
        $badTemplate = Join-Path $testRoot 'invalid-template.json'
        # Keep a valid model first to ensure the whole template is validated before Conda queries.
        $badModels = [ordered]@{ dust3r = $models.dust3r; 'future-model' = $invalidModel }
        [IO.File]::WriteAllText($badTemplate, (@{ models = $badModels } | ConvertTo-Json -Depth 12))
        $global:GuideConfigurationTestCalls = @()
        $caught = $false
        try { & $generator -Template $badTemplate -Output $output -Conda Invoke-GuideConfigurationTestConda | Out-Null } catch { $caught = $true }
        Assert-Configuration ($caught -and (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash -eq $beforeInvalidHash) 'Invalid template overwrote configuration'
        Assert-Configuration ($global:GuideConfigurationTestCalls.Count -eq 0) 'Invalid template queried Conda before rejecting metadata'
        Assert-Configuration (@(Get-ChildItem -LiteralPath (Join-Path $testRoot 'outputs/setup') -Filter 'workspace-before-*.json').Count -eq $beforeBackupCount) 'Invalid template created a configuration backup'
    }
    $failureRoot = Join-Path $testRoot 'backup-failure'
    New-Item -ItemType Directory -Path $failureRoot | Out-Null
    $failureOutput = Join-Path $failureRoot 'workspace.json'
    [IO.File]::WriteAllText($failureOutput, $original)
    [IO.File]::WriteAllText((Join-Path $failureRoot 'outputs'), 'block backup directory')
    $caught = $false
    try { & $generator -Template $template -Output $failureOutput -Conda Invoke-GuideConfigurationTestConda | Out-Null } catch { $caught = $true }
    Assert-Configuration ($caught -and [IO.File]::ReadAllText($failureOutput) -eq $original) 'Backup failure overwrote configuration'
    Write-Output 'Configuration tests passed: four models, custom environments, invalid-template rejection, backup preservation, lookup/backup failure and UTF-8.'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($testParent, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^guide-config-[0-9a-f]{32}$') {
        throw 'Unexpected fixture cleanup path'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
