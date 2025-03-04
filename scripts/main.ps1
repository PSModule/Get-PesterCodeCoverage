#Requires -Modules GitHub

[CmdletBinding()]
param()

LogGroup 'Init - Setup prerequisites' {
    'Markdown' | ForEach-Object {
        Write-Output "Installing module: $_"
        Install-PSResource -Name $_ -WarningAction SilentlyContinue -TrustRepository -Repository PSGallery
        Import-Module -Name $_
    }
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

    # Accumulate coverage items
    $allMissed += $jsonContent.CommandsMissed
    $allExecuted += $jsonContent.CommandsExecuted
    $allFiles += $jsonContent.FilesAnalyzed

    # Keep track of coverage targets to pick the highest
    $allTargets += $jsonContent.CoveragePercentTarget
}

# -- Remove duplicates from each set --
# Adjust these properties as necessary for your "unique" definition:
$finalExecuted = $allExecuted |
    Sort-Object -Property File, Line, Command, StartColumn, EndColumn, Class, Function -Unique

# Normalize them to paths relative to outputs/module
$finalFiles = $allFiles | ForEach-Object {
    ($_ -replace '(?i)^.*outputs[\\/]+module[\\/]+', '') -replace '\\', '/'
} | Sort-Object -Unique

# -- Remove from missed any command that shows up in executed --
# Build "keys" for each unique executed command
$executedKeys = $finalExecuted | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $_.File, $_.Line, $_.Command, $_.StartColumn, $_.EndColumn, $_.Class, $_.Function
}
# Filter out commands from $allMissed that are in $executedKeys
$finalMissed = $allMissed | Sort-Object -Property File, Line, Command, StartColumn, EndColumn, Class, Function -Unique | Where-Object {
    $key = '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $_.File, $_.Line, $_.Command, $_.StartColumn, $_.EndColumn, $_.Class, $_.Function
    $executedKeys -notcontains $key
}

# -- Compute the new coverage percentages --
#   CoveragePercent = (Count(Executed) / Count(Executed + Missed)) * 100
#   Use the highest coverage target from all the files
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
    # If no coverage targets were found in the files, default to 0 or whatever you choose
    $coveragePercentTarget = 0
}

# -- Build final coverage object with the specified fields --
$codeCoverage = [PSCustomObject]@{
    CommandsMissed        = $finalMissed
    CommandsExecuted      = $finalExecuted
    FilesAnalyzed         = $finalFiles
    CoveragePercent       = $coveragePercent
    CoveragePercentTarget = $coveragePercentTarget
    CoverageReport        = ''  # "Ignore this; can be generated later"
    CommandsAnalyzedCount = [Int64]$totalAnalyzed
    CommandsExecutedCount = [Int64]$executedCount
    CommandsMissedCount   = [Int64]$missedCount
    FilesAnalyzedCount    = [Int64]$finalFiles.Count
}

#Print stats:
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
    $codeCoverage.CommandsMissed | Format-Table -AutoSize | Out-String
}

LogGroup 'Executed commands' {
    $codeCoverage.CommandsExecuted | Format-Table -AutoSize | Out-String
}

LogGroup 'Files analyzed' {
    $codeCoverage.FilesAnalyzed | Format-Table -AutoSize | Out-String
}

# -- Output the markdown to GitHub step summary --
$markdown = Heading 'Code Coverage Report' {
    Table {
        $stats
    }

    Details 'Missed commands' {
        Table {
            $codeCoverage.CommandsMissed | Format-Table -AutoSize
        }
    }

    Details 'Executed commands' {
        Table {
            $codeCoverage.CommandsExecuted | Format-Table -AutoSize
        }
    }

    Details 'Files analyzed' {
        Table {
            $codeCoverage.FilesAnalyzed | Format-Table -AutoSize
        }
    }
}

Set-GitHubStepSummary -Summary $markdown

#   TODO: Output the markdown to PR comment

#TODO: Generate a JSON coverage report and upload it as an artifact

# -- Throw an error if coverage is below target --
if ($coveragePercent -lt $coveragePercentTarget) {
    throw "Coverage is below target! Found $coveragePercent%, target is $coveragePercentTarget%."
}
