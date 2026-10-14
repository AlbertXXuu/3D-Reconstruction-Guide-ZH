$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = 0
$scriptCount = 0
$fenceCount = 0

# Parsing reports syntax only; scripts and tutorial commands are never invoked.
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File -Recurse) {
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    $scriptCount++
    foreach ($parseError in $parseErrors) {
        Write-Output ("ERROR: {0}:{1}: {2}" -f $file.FullName, $parseError.Extent.StartLineNumber, $parseError.Message)
        $failures++
    }
}

$documents = @('README.md', 'CONTRIBUTING.md', 'LICENSE-DOCS.md') | ForEach-Object { Join-Path $projectRoot $_ }
$documents += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'docs') -Filter '*.md' -File -Recurse | ForEach-Object { $_.FullName })
foreach ($document in $documents) {
    $lines = [IO.File]::ReadAllLines($document, [Text.Encoding]::UTF8)
    $fenceCharacter = $null
    $fenceLength = 0
    $isPowerShell = $false
    $startLine = 0
    $content = New-Object 'Collections.Generic.List[string]'
    for ($index = 0; $index -lt $lines.Length; $index++) {
        $marker = [regex]::Match($lines[$index], '^ {0,3}(`{3,}|~{3,})(.*)$')
        if ($null -eq $fenceCharacter) {
            if ($marker.Success) {
                $fenceCharacter = $marker.Groups[1].Value.Substring(0, 1)
                $fenceLength = $marker.Groups[1].Value.Length
                $isPowerShell = $marker.Groups[2].Value.Trim() -match '^(powershell|pwsh)(\s|$)'
                $startLine = $index + 2
                $content.Clear()
            }
            continue
        }
        if ($marker.Success -and $marker.Groups[1].Value.Substring(0, 1) -eq $fenceCharacter -and $marker.Groups[1].Value.Length -ge $fenceLength -and $marker.Groups[2].Value.Trim() -eq '') {
            if ($isPowerShell) {
                $tokens = $null
                $parseErrors = $null
                $null = [Management.Automation.Language.Parser]::ParseInput(($content -join "`n"), [ref]$tokens, [ref]$parseErrors)
                $fenceCount++
                foreach ($parseError in $parseErrors) {
                    $sourceLine = $startLine + $parseError.Extent.StartLineNumber - 1
                    Write-Output ("ERROR: {0}:{1}: {2}" -f $document, $sourceLine, $parseError.Message)
                    $failures++
                }
            }
            $fenceCharacter = $null
        } elseif ($isPowerShell) {
            $content.Add($lines[$index])
        }
    }
    if ($null -ne $fenceCharacter -and $isPowerShell) {
        Write-Output ("ERROR: {0}:{1}: Unclosed PowerShell code fence." -f $document, ($startLine - 1))
        $failures++
    }
}

Write-Output ("Parsed {0} PowerShell scripts and {1} tutorial fences with PowerShell {2}." -f $scriptCount, $fenceCount, $PSVersionTable.PSVersion)
if ($failures -gt 0) {
    Write-Output ("PowerShell syntax checks failed: {0} error(s)." -f $failures)
    exit 1
}
Write-Output 'PowerShell syntax checks passed. No tutorial commands were executed.'
