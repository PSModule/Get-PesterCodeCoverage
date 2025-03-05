#Requires -Modules GitHub

[CmdletBinding()]
param()

LogGroup 'Init - Setup prerequisites' {
    'Markdown' | ForEach-Object {
        Write-Output "Installing module: $_"
        Install-PSResource -Name $_ -WarningAction SilentlyContinue -TrustRepository -Repository PSGallery
        Import-Module -Name $_
    }
    Import-Module "$PSScriptRoot/Helpers.psm1"
}

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
$codeCoverageFolder = New-Item -Path . -ItemType Directory -Name 'CodeCoverage' -Force
gh run download $runId --repo $repo --pattern *-CodeCoverage --dir CodeCoverage
$files = Get-ChildItem -Path $codeCoverageFolder -Recurse -File -Filter *.json | Sort-Object Name

LogGroup 'List files' {
    $files.Name | Out-String
}

# Accumulators for coverage items across all files
$allMissed = @()
$allExecuted = @()
$allFiles = @()
$allTargets = @()

foreach ($file in $files) {
    Write-Verbose "Processing file: $($file.FullName)"

    # Convert each JSON file into an object
    $jsonContent = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json

    # --- Normalize file paths in CommandsMissed, CommandsExecuted, and FilesAnalyzed ---
    # 1. Normalize every "File" property in CommandsMissed
    foreach ($missed in $jsonContent.CommandsMissed) {
        if ($missed.File) {
            $missed.File = ConvertTo-RelativePath $missed.File
        }
    }

    # 2. Normalize every "File" property in CommandsExecuted
    foreach ($exec in $jsonContent.CommandsExecuted) {
        if ($exec.File) {
            $exec.File = ConvertTo-RelativePath $exec.File
        }
    }

    # 3. Normalize the file paths in FilesAnalyzed
    $normalizedFiles = @()
    foreach ($fa in $jsonContent.FilesAnalyzed) {
        $normalizedFiles += ConvertTo-RelativePath $fa
    }
    $jsonContent.FilesAnalyzed = $normalizedFiles

    # Now accumulate coverage items
    $allMissed += $jsonContent.CommandsMissed
    $allExecuted += $jsonContent.CommandsExecuted
    $allFiles += $jsonContent.FilesAnalyzed
    $allTargets += $jsonContent.CoveragePercentTarget
}

# -- Remove duplicates from each set --
$finalExecuted = $allExecuted |
    Sort-Object -Property File, Line, Command, StartColumn, EndColumn, Class, Function -Unique

$finalFiles = $allFiles | Sort-Object -Unique

# -- Remove from missed any command that shows up in executed --
$executedKeys = $finalExecuted | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $_.File, $_.Line, $_.Command, $_.StartColumn, $_.EndColumn, $_.Class, $_.Function
}
$finalMissed = $allMissed |
    Sort-Object -Property File, Line, Command, StartColumn, EndColumn, Class, Function -Unique |
    Where-Object {
        $key = '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $_.File, $_.Line, $_.Command, $_.StartColumn, $_.EndColumn, $_.Class, $_.Function
        $executedKeys -notcontains $key
    }

# -- Compute the new coverage percentages --
$missedCount = $finalMissed.Count
$executedCount = $finalExecuted.Count
$totalAnalyzed = $missedCount + $executedCount

if ($totalAnalyzed -gt 0) {
    $coveragePercent = [Math]::Round(($executedCount / $totalAnalyzed) * 100, 2)
} else {
    $coveragePercent = 0
}

$coveragePercentTarget = $allTargets | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
if (-not $coveragePercentTarget) {
    $coveragePercentTarget = 0
}

# -- Build final coverage object --
$codeCoverage = [PSCustomObject]@{
    CommandsMissed        = $finalMissed
    CommandsExecuted      = $finalExecuted
    FilesAnalyzed         = $finalFiles
    CoveragePercent       = $coveragePercent
    CoveragePercentTarget = $coveragePercentTarget
    CoverageReport        = ''
    CommandsAnalyzedCount = [Int64]$totalAnalyzed
    CommandsExecutedCount = [Int64]$executedCount
    CommandsMissedCount   = [Int64]$missedCount
    FilesAnalyzedCount    = [Int64]$finalFiles.Count
}

# Print stats:
$stats = [pscustomobject]@{
    Coverage = "$($codeCoverage.CoveragePercent)% / $($codeCoverage.CoveragePercentTarget)%"
    Analyzed = "$($codeCoverage.CommandsAnalyzedCount) commands"
    Executed = "$($codeCoverage.CommandsExecutedCount) commands"
    Missed   = "$($codeCoverage.CommandsMissedCount) commands"
    Files    = "$($codeCoverage.FilesAnalyzedCount) files"
}

$stats | Format-List | Out-String

# Output the final coverage object to logs
LogGroup 'Missed commands' {
    $codeCoverage.CommandsMissed | Format-List | Out-String
}

LogGroup 'Executed commands' {
    $codeCoverage.CommandsExecuted | Format-List | Out-String
}

LogGroup 'Files analyzed' {
    $codeCoverage.FilesAnalyzed | Format-Table -AutoSize | Out-String
}

# --------------------------------------------------------------------------------
# Transform the Command property with markdown code fences before building the table
# --------------------------------------------------------------------------------
$missedForDisplay = $codeCoverage.CommandsMissed | Sort-Object -Property File, Line | ForEach-Object {
    $command = (Normalize-IndentationExceptFirst -Code $_.Command)
    $command = $command.Replace([Environment]::NewLine, '<br>').Replace(' ', '&nbsp;').Replace('{', '\{').Replace('}', '\}')
    $command = '<pre><code class="language-powershell">{0}</pre></code>' -f $command
    [PSCustomObject]@{
        File        = $_.File
        Line        = $_.Line
        StartColumn = $_.StartColumn
        EndColumn   = $_.EndColumn
        Class       = $_.Class
        Function    = $_.Function
        # Wrap the command in triple-backtick code fences with "pwsh"
        Command     = $command
    }
}

$executedForDisplay = $codeCoverage.CommandsExecuted | Sort-Object -Property File, Line | ForEach-Object {
    $command = (Normalize-IndentationExceptFirst -Code $_.Command)
    $command = $command.Replace([Environment]::NewLine, '<br>').Replace(' ', '&nbsp;').Replace('{', '\{').Replace('}', '\}')
    $command = '<pre><code class="language-powershell">{0}</pre></code>' -f $command
    [PSCustomObject]@{
        File        = $_.File
        Line        = $_.Line
        StartColumn = $_.StartColumn
        EndColumn   = $_.EndColumn
        Class       = $_.Class
        Function    = $_.Function
        # Wrap the command in triple-backtick code fences with "pwsh"
        Command     = $command
    }
}

# -- Output the markdown to GitHub step summary --
$markdown = Heading 1 'Code Coverage Report' {

    Heading 2 'Summary' {
        Table {
            $stats
        }

        Details "Missed commands [$($codeCoverage.CommandsMissedCount)]" {
            Table {
                $missedForDisplay
            }
        }

        Details "Executed commands [$($codeCoverage.CommandsExecutedCount)]" {
            Table {
                $executedForDisplay
            }
        }

        Details "Files analyzed [$($codeCoverage.FilesAnalyzedCount)]" {
            Table {
                $codeCoverage | Select-Object -Property FilesAnalyzed
            }
        }
    }
}

Set-GitHubStepSummary -Summary $markdown

# Throw an error if coverage is below target
if ($coveragePercent -lt $coveragePercentTarget) {
    Write-GitHubError "Coverage is below target! Found $coveragePercent%, target is $coveragePercentTarget%."
    exit 1
}

Write-GitHubNotice "Coverage is above target! Found $coveragePercent%, target is $coveragePercentTarget%."
exit 0
