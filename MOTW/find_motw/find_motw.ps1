Get-ChildItem -Path D:\MOTW_LAB\ -Recurse | ForEach-Object {
    if (Get-Item -Path $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
        Write-Host "發現被標記的檔案 (MOTW): $($_.FullName)"
    }
}
