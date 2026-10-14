param(
    [string] $Template = 'workspace.example.json',
    [string] $Output = 'workspace.json',
    [string] $Conda = 'conda'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Resolve-ConfigurationPath([string] $path) {
    if ([IO.Path]::IsPathRooted($path)) { return [IO.Path]::GetFullPath($path) }
    return [IO.Path]::GetFullPath((Join-Path $projectRoot $path))
}
$templatePath = Resolve-ConfigurationPath $Template
$outputPath = Resolve-ConfigurationPath $Output
if ((Test-Path -LiteralPath $outputPath) -and -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw "Configuration output is not a file: $outputPath"
}
$configuration = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($configuration.models -isnot [Management.Automation.PSCustomObject] -or -not $configuration.models.PSObject.Properties.Count) {
    throw 'Template must define at least one model in models.'
}
# Validate all template metadata before querying environments or replacing a usable configuration.
foreach ($modelProperty in $configuration.models.PSObject.Properties) {
    $model = $modelProperty.Name
    if ($model -cnotmatch '^[a-z][a-z0-9_-]{0,63}$') { throw "Invalid model key: $model" }
    $settings = $modelProperty.Value
    if ($settings -isnot [Management.Automation.PSCustomObject]) { throw "Model '$model' must be an object." }
    foreach ($field in @('script', 'repository', 'checkpoint')) {
        if ($settings.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($settings.$field)) {
            throw "Model '$model' requires a non-empty $field path."
        }
    }
    if (($settings.port -isnot [int] -and $settings.port -isnot [long]) -or $settings.port -lt 1 -or $settings.port -gt 65535) {
        throw "Model '$model' requires an integer port between 1 and 65535."
    }
    if ($null -ne $settings.environment -and ($settings.environment -isnot [string] -or [string]::IsNullOrWhiteSpace($settings.environment))) {
        throw "Model '$model' requires a non-empty named Conda environment when environment is specified."
    }
    $environmentName = if ($settings.environment) { [string]$settings.environment } else { "$model-demo" }
    if ($environmentName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$') {
        throw "Invalid named Conda environment: $environmentName"
    }
}
foreach ($modelProperty in $configuration.models.PSObject.Properties) {
    $model = $modelProperty.Name
    $settings = $modelProperty.Value
    $environmentName = if ($settings.environment) { [string]$settings.environment } else { "$model-demo" }
    $probe = @(& $Conda run -n $environmentName python -c 'import sys; print(sys.executable)')
    if ($LASTEXITCODE -ne 0) { throw "Cannot locate environment: $environmentName" }
    $nonemptyLines = @($probe | Where-Object { $_ -is [string] -and $_.Trim() })
    if (-not $nonemptyLines.Count) { throw "Environment did not return a Python path: $environmentName" }
    $pythonPath = $nonemptyLines[-1].Trim()
    if (-not [IO.Path]::IsPathRooted($pythonPath) -or -not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
        throw "Python executable not found: $pythonPath"
    }
    $settings | Add-Member -NotePropertyName python -NotePropertyValue $pythonPath.Replace('\', '/') -Force
}
$outputDirectory = Split-Path $outputPath -Parent
New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
if (Test-Path -LiteralPath $outputPath) {
    $backupDirectory = Join-Path $outputDirectory 'outputs/setup'
    New-Item -ItemType Directory -Path $backupDirectory -Force -ErrorAction Stop | Out-Null
    $backupPath = Join-Path $backupDirectory ('workspace-before-' + [Guid]::NewGuid().ToString('N') + '.json')
    Copy-Item -LiteralPath $outputPath -Destination $backupPath -ErrorAction Stop
    Write-Output "Previous configuration saved: $backupPath"
}
$json = $configuration | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($outputPath, $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Output "Configured models: $($configuration.models.PSObject.Properties.Name -join ', ')"
Write-Output "Local configuration saved: $outputPath"
