#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
$codeCoverageFolder = New-Item -Path . -ItemType Directory -Name 'CodeCoverage' -Force
gh run download $runId --repo $repo --pattern *-CodeCoverage --dir CodeCoverage
$files = Get-ChildItem -Path $codeCoverageFolder -Recurse -File

LogGroup 'List CodeCoverage files' {
    $files.Name | Out-String
}

$codeCoverage = [System.Collections.Generic.List[psobject]]::new()
foreach ($file in $files) {
    $fileName = $file.BaseName
    $xmlDoc = [xml](Get-Content -Path $file.FullName)
    LogGroup $fileName {
        Get-Content -Path $file | Out-String
    }
    LogGroup "$fileName - xml" {
        $xmlDoc
    }
}
