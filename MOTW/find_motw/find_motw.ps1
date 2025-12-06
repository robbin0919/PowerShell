param(
    [string]$Path = "."
)

Get-ChildItem -Path $Path -Recurse | ForEach-Object {
    if ($_.PSIsContainer -eq $false) {
        try {
            $stream = Get-Item -Path $_.FullName -Stream Zone.Identifier -ErrorAction Stop
            if ($stream) {
                Write-Host "發現檔案帶有網路標記 (MOTW): $($_.FullName)"
            }
        }
        catch {
            # This will suppress errors for files that don't have the Zone.Identifier stream
        }
    }
}

