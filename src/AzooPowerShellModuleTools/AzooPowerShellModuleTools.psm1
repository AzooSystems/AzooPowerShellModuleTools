Get-ChildItem -Recurse "$PSScriptRoot/public/*.ps1" |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Recurse "$PSScriptRoot/private/*.ps1" |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function (
    Get-ChildItem -Recurse "$PSScriptRoot/public/*.ps1" |
    ForEach-Object BaseName
)
