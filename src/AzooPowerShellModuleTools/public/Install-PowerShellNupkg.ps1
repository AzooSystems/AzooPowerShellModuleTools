# Original work: https://gist.github.com/jborean93/e0cb0e3aabeaa1701e41f2304b023366
# Copyright: (c) 2019, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)


Function Install-PowerShellNupkg {
    <#
    .SYNOPSIS
    Installs a PowerShell module as a nupkg.
    .DESCRIPTION
    Installs the PowerShell module nupkg specified by the URI on the local system. This module can be set up in the
    path specified by using -Path, or in the PSModule path controlled by -Scope. The default is to install the module
    in the CurrentUser scope so it is picked up automatically by PowerShell.
    .PARAMETER Uri
    The URI of the nupkg file to download and install. You can use Get-GitHubNupkgUri to get the URI to the latest
    nupkg stored on a GitHub release. Otherwise this can be the URI to PowerShell Gallery nupkg for the version
    specified.
    .PARAMETER Scope
    Used instead of -Path, determines the PSModulePath that module is installed to. Can be set to 'CurrentUser' or
    'AllUsers' and defaults to 'CurrentUser'. Admin privileges are typically required when installing a module to the
    'AllUsers' location.
    .PARAMETER Path
    Instead of installing it into the PSModulePath, the -Path parameter can be used to install the module in the
    specified path. This should be a directory where module directory is installed to.
    .PARAMETER Force
    Overwrite an existing module if it already exists. If not set and an existing module is there, the cmdlet will
    fail.
    .PARAMETER PassThru
    Output the module details back to the caller. You can use the 'ModuleBase' property to determine where the module
    was installed to and remove it manually if need be. There are other properties you can also use.
    .EXAMPLE Install a module into the CurrentUser PSModulePath
    $nupkg_uri = 'https://psg-prod-eastus.azureedge.net/packages/psprivilege.0.1.0.nupkg'
    Install-PowerShellNupkg -Uri $nupkg_uri
    .EXAMPLE Install a module into the AllUsers PSModulePath
    $nupkg_uri = 'https://psg-prod-eastus.azureedge.net/packages/psprivilege.0.1.0.nupkg'
    Install-PowerShellNupkg -Uri $nupkg_uri -Scope Allusers
    .EXAMPLE Install a module to C:\temp\PSPrivilege
    $nupkg_uri = Get-GitHubNupkgUri -Account jborean93 -Name PSPrivilege
    Install-PowerShellNupkg -Uri $nupkg_uri -Path C:\temp
    .NOTES
    For ease of use, this module will unblock the files so they are not seem by Windows as downloaded from the internet
    and can be loaded easily.
    #>
    [OutputType([System.Management.AUtomation.PSModuleInfo])]
    [CmdletBinding(DefaultParameterSetName='Install')]
    Param (
        [Parameter(Mandatory=$true)]
        [System.Uri]
        $Uri,

        [Parameter(ParameterSetName='Install')]
        [ValidateSet('AllUsers', 'CurrentUser')]
        [System.String]
        $Scope = 'CurrentUser',

        [Parameter(ParameterSetName='Path')]
        [System.String]
        $Path,

        [Switch]
        $Force,

        [Switch]
        $PassThru
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        # Resolve the Path so it become the absolute path based on the current PS Path.
        $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        Write-Verbose -Message "Setting the resolved PSModule path to install to as '$Path'"
    } else {
        # Logic for these paths have been derived from PowerShellGet.
        if ((-not (Get-Variable -Name IsWindows -ErrorAction Ignore)) -or $IsWindows) {
            try {
                $documents_path = [System.Environment]::GetFolderPath('MyDocuments')
            } catch {
                $documents_path = Join-Path -Path $env:USERPROFILE -ChildPath 'Documents'
            }

            if ($PSVersionTable.ContainsKey('PSEdition') -and $PSVersionTable.PSEdition -eq 'Core') {
                Write-Verbose -Message "Determining PSModule path options for Windows on PowerShell Core"
                $module_folder = 'PowerShell'
            } else {
                Write-Verbose -Message "Determining PSModule path options for Windows on PowerShell Desktop"
                $module_folder = 'WindowsPowerShell'
            }

            $all_users_pspath = Join-Path -Path $env:ProgramFiles -ChildPath $module_folder
            $current_users_pspath = Join-Path -Path $documents_path -ChildPath $module_folder
        } else {
            Write-Verbose -Message "Determining PSModule path options for non-Windows"
            $all_users_pspath = Split-Path -Path ([System.Management.Automation.Platform]::SelectProductNameForDirectory('SHARED_MODULES')) -Parent
            $current_users_pspath = Split-Path -Path ([System.Management.Automation.Platform]::SelectProductNameForDirectory('USER_MODULES')) -Parent
        }

        if ($Scope -eq 'AllUsers') {
            $Path = Join-Path -Path $all_users_pspath -ChildPath 'Modules'
        } else {
            $Path = Join-Path -Path $current_users_pspath -ChildPath 'Modules'
        }

        Write-Verbose -Message "Setting PSModule path to install to as '$Path'"
    }

    $temp_folder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.IO.Path]::GetRandomFileName())
    New-Item -Path $temp_folder -ItemType Directory > $null
    try {
        # Use a .zip extension so Shell.Application can extract the file.
        $temp_file = Join-Path -Path $temp_folder -ChildPath 'temp_nupkg.zip'
        Write-Verbose -Message "Downloading '$($Uri)' to '$temp_file'"
        $web_client = New-Object -TypeName System.Net.WebClient
        $web_client.DownloadFile($Uri, $temp_file)

        $use_legacy = $false
        try {
            # Requires .NET 4.5+, really old Windows versions may not have this. Remove the legacy work when Server
            # 2008 goes EOL.
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop > $null
        } catch {
            Write-Verbose -Message "System.IO.Compression is not available, using the Windows Shell COM API to extract the nupkg"
            $use_legacy = $true
        }

        Write-Verbose -Message "Extracting temp nupkg at '$temp_file' to '$temp_folder'"
        if ($use_legacy) {
            $shell = New-Object -ComObject Shell.Application
            $zip = $shell.NameSpace($temp_file)
            $zip_dest = $shell.NameSpace($temp_folder)

            # https://msdn.microsoft.com/en-us/library/windows/desktop/bb787866.aspx
            # From Folder.CopyHere documentation, 1044 means:
            #  - 1024: do not display a user interface if an error occurs
            #  -   16: respond with "yes to all" for any dialog box that is displayed
            #  -    4: do not display a progress dialog box
            $zip_dest.CopyHere($zip.Items(), 1044)
        } else {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($temp_file, $temp_folder)
        }
        Remove-Item -LiteralPath $temp_file -Force

        $nuspec_file = Get-Item -Path (Join-Path -Path $temp_folder -ChildPath '*.nuspec')
        if ($null -eq $nuspec_file) {
            Write-Error -Message 'Failed to find .nuspec file inside .nupkg, cannot continue' -Category ObjectNotFound
            return
        }
        $package_nuspec = [System.Xml.XmlDocument](Get-Content -LiteralPath $nuspec_file.FullName -Raw -ErrorAction Stop)
        $name = $package_nuspec.package.metadata.id
        $version = $package_nuspec.package.metadata.version
        Write-Verbose -Message "Parsed package nuspec and gathered: Name=$name, Version=$version"

        $module_path = Join-Path -Path $Path -ChildPath $name
        # PowerShell 5.1+ supports modules being stored for a particular version. If running on 5.1+ we should place
        # the files inside a folder of that particular version.
        if ($PSVersionTable.PSVersion -ge [Version]'5.1') {
            Write-Verbose -Message "PowerShell version supports version specific module path, appending module version $version"
            $module_path = Join-Path -Path $module_path -ChildPath $version
        }

        if (-not (Test-Path -LiteralPath $module_path)) {
            Write-Verbose -Message "Creating module path '$module_path'"
            New-Item -Path $module_path -ItemType Directory > $null
        } elseif ($Force) {
            Write-Verbose -Message "Module at path '$module_path' already exists and -Force was used, cleaning directory"
            Remove-Item -LiteralPath $module_path -Force -Recurse
            New-Item -Path $module_path -ItemType Directory > $null
        } else {
            Write-Error -Message "Module at path '$module_path' already exists, use -Force to continue"
            return
        }

        # Ignore these files in the .nupkg, we don't care or need them.
        $ignored_files = @("$name.nuspec", '[Content_Types].xml', '_rels', 'package')

        # Copy all the files and Unblock-File them
        Function Copy-FolderContents {
            Param ($Path, $DestinationPath, $IgnoredFiles = @())

            # -Filter won't work for all paths ([Content_Types].xml), so we do a post processing filter
            $path_items = Get-ChildItem -LiteralPath $Path
            foreach ($path_item in $path_items) {
                if ($path_item.Name -in $IgnoredFiles) {
                    continue
                }

                $dest_path = Join-Path -Path $DestinationPath -ChildPath $path_item.Name
                if ($path_item.PSIsContainer) {
                    Write-Verbose -Message "Creating dest directory at '$dest_path'"
                    New-Item -Path $dest_path -ItemType Directory -Force > $null
                    Copy-FolderContents -Path $path_item.FullName -DestinationPath $dest_path
                } else {
                    Write-Verbose -Message "Copying module file '$($path_item.Name)' to $dest_path"
                    Copy-Item -LiteralPath $path_item.FullName -Destination $dest_path -Force

                    if (Get-Command -Name Unblock-File -ErrorAction Ignore) {
                        Write-Verbose -Message "Unblocking file at $dest_path"
                        Unblock-File -LiteralPath $dest_path
                    }
                }
            }
        }
        Copy-FolderContents -Path $temp_folder -DestinationPath $module_path -IgnoredFiles $ignored_files
    } finally {
        Write-Verbose -Message "Removing temporary directory at '$temp_folder'"
        Remove-Item -LiteralPath $temp_folder -Force -Recurse
    }

    if ($PassThru) {
        return Get-Module -Name $module_path -ListAvailable
    }
}