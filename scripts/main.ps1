#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
$codeCoverageFolder = New-Item -Path . -ItemType Directory -Name 'CodeCoverage' -Force
gh run download $runId --repo $repo --pattern *-CodeCoverage --dir CodeCoverage
$files = Get-ChildItem -Path $codeCoverageFolder -Recurse -File -Filter *.json | Sort-Object Name

LogGroup 'List files' {
    $files.Name | Out-String
}

$codeCoverage = [System.Collections.Generic.List[psobject]]::new()
foreach ($file in $files) {
    $fileName = $file.BaseName
    $content = Get-Content -Path $file
    $object = $content | ConvertFrom-Json
    $codeCoverage.Add($object)

    $logGroupName = $fileName.Replace('-CodeCoverage-Report', '')
    LogGroup " - $logGroupName" {
        $object | Format-List | Out-String
    }
}
Write-Output ('─' * 50)
LogGroup ' - Summary' {
    $codeCoverage | Format-List | Out-String
}

# # Function to merge counters
# function Merge-Counters($baseNode, $newNode) {
#     foreach ($newCounter in $newNode.counter) {
#         $baseCounter = $baseNode.counter | Where-Object { $_.type -eq $newCounter.type }
#         if ($baseCounter) {
#             $baseCounter.missed = [int]$baseCounter.missed + [int]$newCounter.missed
#             $baseCounter.covered = [int]$baseCounter.covered + [int]$newCounter.covered
#         } else {
#             # Import new counter if it doesn't exist
#             $importedCounter = $mergedReport.ImportNode($newCounter, $true)
#             $baseNode.AppendChild($importedCounter) | Out-Null
#         }
#     }
# }

# # Loop through remaining reports to merge coverage data
# foreach ($reportPath in $files[1..($files.Count - 1)]) {
#     [xml]$currentReport = Get-Content -Path $reportPath

#     # Merge the top-level counters
#     Merge-Counters -baseNode $mergedReport.report -newNode $currentReport.report

#     # Merge packages and classes
#     foreach ($package in $currentReport.report.package) {
#         $basePackage = $mergedReport.report.package | Where-Object { $_.name -eq $package.name }

#         if ($basePackage) {
#             # Merge counters at package level
#             Merge-Counters -baseNode $basePackage -newNode $package

#             foreach ($class in $package.class) {
#                 $baseClass = $basePackage.class | Where-Object { $_.name -eq $class.name }
#                 if ($baseClass) {
#                     # Merge counters at class level
#                     Merge-Counters -baseNode $baseClass -newNode $class
#                 } else {
#                     # Import new class
#                     $importedClass = $mergedReport.ImportNode($class, $true)
#                     $basePackage.AppendChild($importedClass) | Out-Null
#                 }
#             }
#         } else {
#             # Import entire new package
#             $importedPackage = $mergedReport.ImportNode($package, $true)
#             $mergedReport.report.AppendChild($importedPackage) | Out-Null
#         }
#     }
# }

# # Output the combined report
# $mergedReport.Save('merged-jacoco-report.xml')

# # Assuming $mergedReport is your final [xml] object:
# $xmlString = $mergedReport.OuterXml

# # To format (pretty-print) the XML nicely:
# $stringWriter = New-Object System.IO.StringWriter
# $xmlWriter = [System.Xml.XmlTextWriter]::new($stringWriter)
# $xmlWriter.Formatting = 'Indented'
# $mergedReport.WriteTo($xmlWriter)
# $xmlWriter.Flush()
# $prettyXml = $stringWriter.ToString()

# $prettyXml | Out-String

# # Output or export the XML string
# # $prettyXml | Out-File -FilePath "merged-jacoco-report.xml" -Encoding UTF8
