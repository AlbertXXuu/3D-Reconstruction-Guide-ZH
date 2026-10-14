param(
    [string] $Model = 'dust3r',
    [switch] $NoBrowser,
    [switch] $Stop,
    [switch] $Check
)
$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeDirectory = Join-Path $workspaceRoot 'outputs\runtime'
$statePath = Join-Path $runtimeDirectory 'demo-process.json'

function Test-DemoPort([int] $port) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
    try {
        $listener.Start()
        return $true
    } catch { return $false } finally { $listener.Stop() }
}

function Resolve-ModelPath([string] $path) {
    if ([IO.Path]::IsPathRooted($path)) { return [IO.Path]::GetFullPath($path) }
    return [IO.Path]::GetFullPath((Join-Path $workspaceRoot $path))
}

if ($Check -and $Stop) { throw 'Choose either -Check or -Stop.' }
if (-not $Stop) {
    $Model = ([string]$Model).ToLowerInvariant()
    if ($Model -cnotmatch '^[a-z][a-z0-9_-]{0,63}$') {
        throw 'Model must be a lowercase name, starting with a letter and containing only letters, digits, hyphens or underscores (maximum 64 characters).'
    }
    $configPath = Join-Path $workspaceRoot 'workspace.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw 'workspace.json is missing. Create your local configuration from workspace.example.json first.'
    }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config.models -or $config.models -isnot [Management.Automation.PSCustomObject]) {
        throw 'workspace.json must contain a models object.'
    }
    $configuredModels = @($config.models.PSObject.Properties.Name | Sort-Object)
    $modelProperty = @($config.models.PSObject.Properties | Where-Object { $_.Name -ceq $Model })
    if ($modelProperty.Count -ne 1) {
        throw "Model is not configured yet: $Model. Configured models: $($configuredModels -join ', ')."
    }
    $modelConfig = $modelProperty[0].Value
    foreach ($field in @('python', 'script', 'repository', 'checkpoint')) {
        if ($modelConfig.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($modelConfig.$field)) {
            throw "Model '$Model' requires a non-empty $field path."
        }
    }
    if (($modelConfig.port -isnot [int] -and $modelConfig.port -isnot [long]) -or $modelConfig.port -lt 1 -or $modelConfig.port -gt 65535) {
        throw "Model '$Model' requires an integer port between 1 and 65535."
    }
    $pythonPath = Resolve-ModelPath $modelConfig.python
    $scriptPath = Resolve-ModelPath $modelConfig.script
    $repoPath = Resolve-ModelPath $modelConfig.repository
    $weightsPath = Resolve-ModelPath $modelConfig.checkpoint
    foreach ($requiredFile in @($pythonPath, $scriptPath, $weightsPath)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Required file missing: $requiredFile" }
    }
    if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) { throw "Repository directory missing: $repoPath" }
    $url = "http://127.0.0.1:$($modelConfig.port)/"
    if ($Check) {
        # This branch never imports model code, creates runtime files or reads/stops a managed process.
        [ordered]@{
            model = $Model
            configured_models = $configuredModels
            python = $pythonPath
            script = $scriptPath
            repository = $repoPath
            weights = $weightsPath
            port = [int]$modelConfig.port
            url = $url
            port_available = Test-DemoPort ([int]$modelConfig.port)
        } | ConvertTo-Json -Depth 3
        return
    }
}

Add-Type -AssemblyName System.Net.Http

function Get-ManagedProcess($state) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.pid)" -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $null }
    # A stale/reused PID must never stop an unrelated program.
    if ($process.ExecutablePath -ine $state.python -or -not $process.CommandLine.Contains($state.script)) {
        throw "Stored PID belongs to another program; refusing to stop it: $($state.pid)"
    }
    return $process
}

$handler = [Net.Http.HttpClientHandler]::new()
$handler.UseProxy = $false
$httpClient = [Net.Http.HttpClient]::new($handler)
$httpClient.Timeout = [TimeSpan]::FromSeconds(3)
function Test-DemoHttp([string] $url) {
    try {
        $response = $httpClient.GetAsync($url).GetAwaiter().GetResult()
        $healthy = $response.IsSuccessStatusCode
        $response.Dispose()
        return $healthy
    } catch { return $false }
}

try {
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $managedProcess = Get-ManagedProcess $state
        if ($null -ne $managedProcess) {
            if (-not $Stop -and $state.model -eq $Model -and
                $state.python -ieq $pythonPath -and $state.script -ieq $scriptPath -and
                $state.weights -ieq $weightsPath -and $state.url -eq $url -and
                (Test-DemoHttp $url)) {
                Write-Output "Already running: $($state.url)"
                if (-not $NoBrowser) { Start-Process $state.url }
                return
            }
            # Check a different destination before stopping a working demo. The current
            # managed endpoint may legitimately be reused by a model switch on the same port.
            if (-not $Stop -and $state.url -ne $url -and -not (Test-DemoPort ([int]$modelConfig.port))) {
                throw "Local port $($modelConfig.port) is occupied by another program; current managed demo remains running."
            }
            Write-Output "Stopping managed $($state.model) demo (PID $($state.pid)) to release GPU memory."
            Stop-Process -Id $state.pid -ErrorAction Stop
            Wait-Process -Id $state.pid -Timeout 20 -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $statePath
    }
    if ($Stop) {
        Write-Output 'Managed demo stopped.'
        return
    }
    if (-not (Test-DemoPort ([int]$modelConfig.port))) { throw "Local port $($modelConfig.port) is occupied by another program." }
    New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
    foreach ($variable in @('NO_PROXY', 'no_proxy')) {
        $entries = @([Environment]::GetEnvironmentVariable($variable, 'Process') -split ',' | Where-Object { $_ })
        [Environment]::SetEnvironmentVariable($variable, (($entries + @('127.0.0.1', 'localhost') | Select-Object -Unique) -join ','), 'Process')
    }
    $env:GRADIO_ANALYTICS_ENABLED = 'False'
    $env:PYTHONUTF8 = '1'
    $env:MPLBACKEND = 'Agg'
    $stamp = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyyMMdd-HHmmss-fff')
    $stdoutPath = Join-Path $runtimeDirectory "$Model-$stamp.stdout.log"
    $stderrPath = Join-Path $runtimeDirectory "$Model-$stamp.stderr.log"
    $process = Start-Process -FilePath $pythonPath -ArgumentList @('-u', '-B', ('"' + $scriptPath + '"'), '--port', [string]$modelConfig.port, '--weights', ('"' + $weightsPath + '"')) -WorkingDirectory $repoPath -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $state = [ordered]@{ model = $Model; pid = $process.Id; python = $pythonPath; script = $scriptPath; weights = $weightsPath; url = $url; started_at = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o'); stdout = $stdoutPath; stderr = $stderrPath; ready = $false }
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Output "Starting $Model. Logs: $stdoutPath and $stderrPath"
    $deadline = [DateTime]::UtcNow.AddSeconds(240)
    while ([DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) {
            Get-Content -LiteralPath $stderrPath -Tail 25 -Encoding UTF8
            throw "$Model exited with code $($process.ExitCode). See logs."
        }
        if (Test-DemoHttp $url) {
            $state.ready = $true
            $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
            Write-Output "Ready: $url"
            if (-not $NoBrowser) { Start-Process $url }
            return
        }
        Start-Sleep -Seconds 1
    }
    throw "$Model did not become ready within 240 seconds. Inspect logs or run this script with -Stop."
} finally {
    $httpClient.Dispose()
    $handler.Dispose()
}
