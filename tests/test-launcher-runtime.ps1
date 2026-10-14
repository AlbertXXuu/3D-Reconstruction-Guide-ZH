param([string] $PythonExe = '')
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PythonExe)) { $PythonExe = (Get-Command python -CommandType Application -ErrorAction Stop).Source }
$PythonExe = [IO.Path]::GetFullPath($PythonExe)
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw "Python executable missing: $PythonExe" }
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $tempRoot ('guide-launcher-runtime test-' + [Guid]::NewGuid().ToString('N'))
$launcher = Join-Path $fixtureRoot 'scripts\start-demo.ps1'
$serverScript = Join-Path $fixtureRoot 'scripts\cpu server.py'
$statePath = Join-Path $fixtureRoot 'outputs\runtime\demo-process.json'
$checks = 0
$handler = $null
$client = $null

function Assert-True([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
    $script:checks++
}

function Test-PortAvailable([int] $port) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
    try { $listener.Start(); return $true } catch { return $false } finally { $listener.Stop() }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'scripts'), (Join-Path $fixtureRoot 'repository'), (Join-Path $fixtureRoot 'shared weights') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\start-demo.ps1') -Destination $launcher
    $serverSource = @'
import argparse
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, required=True)
parser.add_argument("--weights", type=Path, required=True)
args = parser.parse_args()
if not args.weights.is_file():
    parser.error("Fixture weights file is missing")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        content = b"cpu launcher fixture ready"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

print(f"CPU fixture Python: {sys.executable}", flush=True)
with HTTPServer(("127.0.0.1", args.port), Handler) as server:
    server.serve_forever()
'@
    [IO.File]::WriteAllText($serverScript, $serverSource, [Text.UTF8Encoding]::new($false))
    $weightsPath = Join-Path $fixtureRoot 'shared weights\dummy model.bin'
    [IO.File]::WriteAllText($weightsPath, 'CPU-only test fixture; no actual model weights.')
    $weightsHash = (Get-FileHash -LiteralPath $weightsPath -Algorithm SHA256).Hash
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try { $probe.Start(); $port = $probe.LocalEndpoint.Port } finally { $probe.Stop() }
    $url = "http://127.0.0.1:$port/"
    $config = [ordered]@{
        schema_version = 1
        models = [ordered]@{
            'cpu-http' = [ordered]@{
                python = $PythonExe
                script = $serverScript
                repository = 'repository'
                checkpoint = $weightsPath
                port = $port
            }
            'cpu-next' = [ordered]@{
                python = $PythonExe
                script = $serverScript
                repository = 'repository'
                checkpoint = $weightsPath
                port = $port
            }
        }
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixtureRoot 'workspace.json') -Encoding UTF8
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(5)

    $launchOutput = (& $launcher -Model cpu-http -NoBrowser) -join "`n"
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $serverPid = [int]$state.pid
    Assert-True ($state.model -eq 'cpu-http' -and $state.ready -eq $true -and $launchOutput -match 'Ready:') 'Fourth model did not become ready.'
    $server = Get-CimInstance Win32_Process -Filter "ProcessId = $serverPid"
    Assert-True ($server.ExecutablePath -ieq $PythonExe -and $server.CommandLine.Contains($serverScript)) 'Launched PID does not match the configured Python and fixture script.'
    $response = $client.GetAsync($url).GetAwaiter().GetResult()
    try {
        Assert-True ([int]$response.StatusCode -eq 200 -and $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() -eq 'cpu launcher fixture ready') 'CPU demo HTTP response was not correct.'
    } finally { $response.Dispose() }
    Assert-True (-not (Test-PortAvailable $port)) 'Running demo did not own the expected port.'

    $stateHash = (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
    $repeatOutput = (& $launcher -Model CPU-HTTP -NoBrowser) -join "`n"
    $reusedState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($reusedState.pid -eq $serverPid -and $repeatOutput -match 'Already running:') 'Repeated startup did not reuse the same managed PID.'
    $report = ((& $launcher -Model cpu-http -Check) -join "`n" | ConvertFrom-Json)
    Assert-True ($report.model -eq 'cpu-http' -and $report.port_available -eq $false) 'Read-only check did not report the running demo port.'
    Assert-True ((Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -eq $stateHash -and $null -ne (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) 'Read-only check changed state or stopped the live demo.'
    $unknownError = $null
    try { & $launcher -Model unknown -NoBrowser | Out-Null } catch { $unknownError = $_.Exception.Message }
    Assert-True ($unknownError -match 'Model is not configured yet' -and (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -eq $stateHash -and $null -ne (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) 'Unknown model request changed a running demo.'

    # A valid new model on somebody else's port must not interrupt the working demo.
    $occupied = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $occupied.Start()
        $occupiedPort = $occupied.LocalEndpoint.Port
        $config.models['cpu-other'] = [ordered]@{
            python = $PythonExe
            script = $serverScript
            repository = 'repository'
            checkpoint = $weightsPath
            port = $occupiedPort
        }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixtureRoot 'workspace.json') -Encoding UTF8
        $occupiedError = $null
        try { & $launcher -Model cpu-other -NoBrowser | Out-Null } catch { $occupiedError = $_.Exception.Message }
        Assert-True ($occupiedError -match 'occupied by another program; current managed demo remains running') 'Occupied destination did not fail before switching.'
        Assert-True ((Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -eq $stateHash -and $null -ne (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) 'Occupied destination changed the live demo PID or state.'
        $response = $client.GetAsync($url).GetAwaiter().GetResult()
        try { Assert-True ([int]$response.StatusCode -eq 200) 'Original demo stopped responding after the blocked switch.' } finally { $response.Dispose() }
        Assert-True (-not (Test-PortAvailable $occupiedPort)) 'Blocked switch disturbed the unrelated listener.'
    } finally { $occupied.Stop() }

    # The current managed endpoint is allowed to switch models while retaining its port.
    $previousServerPid = $serverPid
    $switchOutput = (& $launcher -Model cpu-next -NoBrowser) -join "`n"
    $switchedState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $serverPid = [int]$switchedState.pid
    Assert-True ($switchedState.model -eq 'cpu-next' -and $switchedState.ready -eq $true -and $serverPid -ne $previousServerPid -and $switchOutput -match 'Ready:') 'Same-port authorized model switch did not start the replacement.'
    Assert-True ($null -eq (Get-Process -Id $previousServerPid -ErrorAction SilentlyContinue) -and $switchedState.url -eq $url) 'Same-port switch retained the old PID or changed the endpoint.'
    $response = $client.GetAsync($url).GetAwaiter().GetResult()
    try { Assert-True ([int]$response.StatusCode -eq 200) 'Replacement demo is not serving the reused port.' } finally { $response.Dispose() }

    & $launcher -Stop | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $statePath) -and $null -eq (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) 'Stop left the managed PID or state file behind.'
    Assert-True (Test-PortAvailable $port) 'Stop did not release the demo port.'
    Assert-True ((Get-FileHash -LiteralPath $weightsPath -Algorithm SHA256).Hash -eq $weightsHash) 'Runtime test modified shared dummy weights.'
    Write-Output "Launcher runtime passed: $checks assertions; CPU HTTP demo start/reuse/check/stop, no GPU or third-party packages."
} finally {
    if ($null -ne $client) { $client.Dispose() }
    if ($null -ne $handler) { $handler.Dispose() }
    # Stop only a PID whose current executable and command line still identify this unique fixture.
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $cleanupState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $cleanupProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($cleanupState.pid)" -ErrorAction SilentlyContinue
        if ($null -ne $cleanupProcess) {
            if ($cleanupProcess.ExecutablePath -ine $PythonExe -or -not $cleanupProcess.CommandLine.Contains($serverScript)) {
                throw "Refusing to stop an unrelated process during fixture cleanup: $($cleanupState.pid)"
            }
            Stop-Process -Id $cleanupState.pid -ErrorAction Stop
            Wait-Process -Id $cleanupState.pid -Timeout 10 -ErrorAction SilentlyContinue
        }
    }
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $tempBoundary = $tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolvedFixture) -notmatch '^guide-launcher-runtime test-[0-9a-f]{32}$') {
        throw "Refusing to clean up an unexpected fixture path: $resolvedFixture"
    }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
