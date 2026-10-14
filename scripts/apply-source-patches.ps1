$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRoot = Join-Path $projectRoot 'repos\dust3r'
$patchPath = Join-Path $projectRoot 'patches\dust3r-gradio4.patch'
$expectedCommit = 'a53d073bb07455f5a3e7fcbeaaea240c159c4f08'
$expectedCroco = '743ee71a2a9bf57cea6832a9064a70a0597fcfcb'

if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'dust3r\demo.py') -PathType Leaf)) {
    throw 'DUSt3R source is missing. Initialize the official submodules first.'
}
if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "Patch file is missing: $patchPath"
}
$actualRoot = & git -C $sourceRoot rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($actualRoot) -ine $sourceRoot) {
    throw 'repos/dust3r must be its own official Git checkout.'
}
$actualCommit = & git -C $sourceRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
    throw "Unexpected DUSt3R revision; preserve it and inspect first. Expected: $expectedCommit"
}
$actualCroco = & git -C (Join-Path $sourceRoot 'croco') rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $actualCroco -ne $expectedCroco) {
    throw "Unexpected CroCo revision; initialize the pinned submodule first. Expected: $expectedCroco"
}

# Reverse-check identifies this exact patch without resetting any source files.
& git -C $sourceRoot apply --reverse --check --quiet -- $patchPath 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Output 'DUSt3R viewer/download patch is already applied.'
    exit 0
}
& git -C $sourceRoot apply --check -- $patchPath
if ($LASTEXITCODE -ne 0) {
    throw 'Patch conflicts with the current source; files were preserved. Inspect local changes before retrying.'
}
& git -C $sourceRoot apply -- $patchPath
if ($LASTEXITCODE -ne 0) { throw 'DUSt3R patch application failed.' }
Write-Output 'Applied DUSt3R viewer/download patch; other source files were preserved.'
