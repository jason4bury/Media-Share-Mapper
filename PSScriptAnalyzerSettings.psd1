# PSScriptAnalyzer settings for Media Share Mapper.
# Run: Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # A console tool: coloured Write-Host output is the interface, and -Quiet
        # already turns it off for the scheduled task (everything still goes to the log).
        'PSAvoidUsingWriteHost',
        # The functions are private helpers inside one script, not exported cmdlets.
        # Set-DriveIcon only changes per-user icon settings and only when they differ,
        # so -WhatIf/-Confirm support adds nothing here.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
