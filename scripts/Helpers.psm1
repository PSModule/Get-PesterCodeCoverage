function ConvertTo-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # 1) Remove everything up to and including "outputs/module/" (case-insensitive),
    #    allowing either slash or backslash.
    $relative = $Path -replace '(?i)^.*outputs[\\/]+module[\\/]+', ''

    # 2) Convert all backslashes to forward slashes for consistency
    $relative = $relative -replace '\\', '/'

    # 3) Remove the *next* folder (the module name) in the path.
    #    For example, "PSModuleTest/scripts/loader.ps1" => "scripts/loader.ps1"
    $segments = $relative -split '/'
    if ($segments.Count -gt 1) {
        # Skip the first segment (the module name) and rejoin the rest
        $relative = ($segments[1..($segments.Count - 1)]) -join '/'
    } else {
        # If there was only one segment, just keep it (file in the root)
        $relative = $segments[0]
    }

    return $relative
}
