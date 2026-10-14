param(
    [ValidateSet('dust3r', 'mast3r', 'vggt')][string] $Model = 'dust3r',
    [switch] $NoBrowser,
    [switch] $Stop
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeDirectory = Join-Path $workspaceRoot 'outputs\runtime'
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$statePath = Join-Path $runtimeDirectory 'demo-process.json'

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
    if (-not $Stop) {
        $config = Get-Content -LiteralPath (Join-Path $workspaceRoot 'workspace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $modelConfig = $config.models.$Model
        if ($null -eq $modelConfig) { throw "Model is not configured yet: $Model" }
        $pythonPath = [IO.Path]::GetFullPath($modelConfig.python)
        $scriptPath = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $modelConfig.script))
        $repoPath = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $modelConfig.repository))
        $weightsPath = [IO.Path]::GetFullPath((Join-Path $workspaceRoot $modelConfig.checkpoint))
        foreach ($requiredFile in @($pythonPath, $scriptPath, $weightsPath)) {
            if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Required file missing: $requiredFile" }
        }
        if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) { throw "Repository directory missing: $repoPath" }
        $url = "http://127.0.0.1:$($modelConfig.port)/"
    }
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
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, [int]$modelConfig.port)
    try { $listener.Start() } catch { throw "Local port $($modelConfig.port) is occupied by another program." } finally { $listener.Stop() }
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
